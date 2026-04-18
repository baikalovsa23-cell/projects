-- Migration 032: Protocol Research Bridge Integration
-- Date: 2026-03-06
-- Author: System Architect
-- Description: Adds bridge-related fields to protocol_research_pending for integration with Bridge Manager v2.0
-- 
-- This migration enables:
-- 1. Protocol Research to check bridge availability when discovering new protocols
-- 2. Scheduler to recheck bridge before assigning wallets
-- 3. Automatic recheck of unreachable protocols weekly
-- 4. Auto-reject after 30 days (4 recheck attempts)

-- ===========================================================================
-- 1. ADD BRIDGE FIELDS TO protocol_research_pending
-- ===========================================================================

-- Bridge requirement and availability
ALTER TABLE protocol_research_pending
ADD COLUMN IF NOT EXISTS bridge_required BOOLEAN DEFAULT FALSE;

ALTER TABLE protocol_research_pending
ADD COLUMN IF NOT EXISTS bridge_from_network VARCHAR(50) DEFAULT 'Arbitrum';

ALTER TABLE protocol_research_pending
ADD COLUMN IF NOT EXISTS bridge_provider VARCHAR(100);

ALTER TABLE protocol_research_pending
ADD COLUMN IF NOT EXISTS bridge_cost_usd DECIMAL(10, 2);

ALTER TABLE protocol_research_pending
ADD COLUMN IF NOT EXISTS bridge_safety_score INTEGER CHECK (bridge_safety_score BETWEEN 0 AND 100);

ALTER TABLE protocol_research_pending
ADD COLUMN IF NOT EXISTS bridge_available BOOLEAN DEFAULT TRUE;

ALTER TABLE protocol_research_pending
ADD COLUMN IF NOT EXISTS bridge_checked_at TIMESTAMPTZ;

-- Unreachable protocol handling
ALTER TABLE protocol_research_pending
ADD COLUMN IF NOT EXISTS bridge_unreachable_reason TEXT;

ALTER TABLE protocol_research_pending
ADD COLUMN IF NOT EXISTS bridge_recheck_after TIMESTAMPTZ;

ALTER TABLE protocol_research_pending
ADD COLUMN IF NOT EXISTS bridge_recheck_count INTEGER DEFAULT 0;

-- CEX support (if direct withdrawal is possible)
ALTER TABLE protocol_research_pending
ADD COLUMN IF NOT EXISTS cex_support VARCHAR(50);

-- ===========================================================================
-- 2. CREATE INDEXES
-- ===========================================================================

-- Index for finding unreachable protocols that need recheck
CREATE INDEX IF NOT EXISTS idx_research_pending_bridge_recheck 
ON protocol_research_pending(bridge_recheck_after) 
WHERE bridge_available = FALSE AND status = 'pending_approval';

-- Index for unreachable protocol statistics
CREATE INDEX IF NOT EXISTS idx_research_pending_unreachable 
ON protocol_research_pending(bridge_available, bridge_recheck_count) 
WHERE bridge_available = FALSE;

-- Index for bridge-required protocols
CREATE INDEX IF NOT EXISTS idx_research_pending_bridge_required
ON protocol_research_pending(bridge_required, bridge_available)
WHERE bridge_required = TRUE;

-- ===========================================================================
-- 3. HELPER FUNCTIONS
-- ===========================================================================

-- Function to get unreachable protocols for recheck
CREATE OR REPLACE FUNCTION get_unreachable_protocols_for_recheck()
RETURNS TABLE (
    id INTEGER,
    name VARCHAR,
    chain VARCHAR,
    bridge_from_network VARCHAR,
    bridge_recheck_count INTEGER,
    airdrop_score INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        prp.id,
        prp.name,
        prp.chains[1] as chain,
        prp.bridge_from_network,
        prp.bridge_recheck_count,
        prp.airdrop_score
    FROM protocol_research_pending prp
    WHERE prp.bridge_available = FALSE
      AND prp.status = 'pending_approval'
      AND prp.bridge_recheck_after <= NOW()
      AND prp.bridge_recheck_count < 4
    ORDER BY prp.airdrop_score DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_unreachable_protocols_for_recheck() IS 
'Returns unreachable protocols that need bridge recheck. Max 4 attempts (30 days).';

-- Function to update bridge info after recheck
CREATE OR REPLACE FUNCTION update_protocol_bridge_info(
    p_protocol_id INTEGER,
    p_bridge_available BOOLEAN,
    p_bridge_provider VARCHAR DEFAULT NULL,
    p_bridge_cost_usd DECIMAL DEFAULT NULL,
    p_bridge_safety_score INTEGER DEFAULT NULL,
    p_unreachable_reason TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    IF p_bridge_available THEN
        -- Bridge became available
        UPDATE protocol_research_pending
        SET 
            bridge_available = TRUE,
            bridge_provider = p_bridge_provider,
            bridge_cost_usd = p_bridge_cost_usd,
            bridge_safety_score = p_bridge_safety_score,
            bridge_checked_at = NOW(),
            bridge_unreachable_reason = NULL,
            bridge_recheck_after = NULL
        WHERE id = p_protocol_id;
    ELSE
        -- Still unreachable - increment count and set next recheck
        UPDATE protocol_research_pending
        SET 
            bridge_available = FALSE,
            bridge_unreachable_reason = p_unreachable_reason,
            bridge_checked_at = NOW(),
            bridge_recheck_count = bridge_recheck_count + 1,
            bridge_recheck_after = NOW() + INTERVAL '7 days'
        WHERE id = p_protocol_id;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_protocol_bridge_info() IS 
'Updates bridge availability info after recheck. Auto-schedules next recheck if still unavailable.';

-- Function to auto-reject protocols after 4 failed rechecks
CREATE OR REPLACE FUNCTION auto_reject_stale_unreachable_protocols()
RETURNS INTEGER AS $$
DECLARE
    rejected_count INTEGER;
BEGIN
    UPDATE protocol_research_pending
    SET 
        status = 'auto_rejected',
        rejected_reason = 'Bridge unavailable for 30 days (4 recheck attempts)',
        rejected_at = NOW(),
        updated_at = NOW()
    WHERE 
        bridge_available = FALSE
        AND bridge_recheck_count >= 4
        AND status = 'pending_approval';
    
    GET DIAGNOSTICS rejected_count = ROW_COUNT;
    
    IF rejected_count > 0 THEN
        INSERT INTO research_logs (
            cycle_start_at,
            cycle_end_at,
            status,
            protocols_auto_rejected,
            summary_report
        ) VALUES (
            NOW(),
            NOW(),
            'completed',
            rejected_count,
            FORMAT('Auto-rejected %s unreachable protocols (no bridge for 30 days)', rejected_count)
        );
    END IF;
    
    RETURN rejected_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION auto_reject_stale_unreachable_protocols() IS 
'Auto-rejects protocols that have been unreachable for 30+ days (4 recheck attempts).';

-- Function to calculate final priority score with bridge penalty
CREATE OR REPLACE FUNCTION calculate_final_priority_score(
    p_airdrop_score INTEGER,
    p_bridge_required BOOLEAN DEFAULT FALSE,
    p_bridge_cost_usd DECIMAL DEFAULT NULL,
    p_bridge_safety_score INTEGER DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_base_score INTEGER := p_airdrop_score;
    v_bridge_penalty INTEGER := 0;
    v_cost_penalty INTEGER := 0;
    v_safety_penalty INTEGER := 0;
    v_final_score INTEGER;
BEGIN
    -- Only apply penalty if bridge is required
    IF p_bridge_required THEN
        -- Cost penalty: $1 = -2 points, max -10
        IF p_bridge_cost_usd IS NOT NULL THEN
            v_cost_penalty := LEAST(10, FLOOR(p_bridge_cost_usd * 2));
        END IF;
        
        -- Safety penalty: lower safety = higher penalty
        -- 100 safety = 0 penalty, 50 safety = -5 penalty, 0 safety = -10 penalty
        IF p_bridge_safety_score IS NOT NULL THEN
            v_safety_penalty := GREATEST(0, (100 - p_bridge_safety_score) / 10);
        END IF;
        
        v_bridge_penalty := v_cost_penalty + v_safety_penalty;
    END IF;
    
    v_final_score := GREATEST(0, v_base_score - v_bridge_penalty);
    
    RETURN v_final_score;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_final_priority_score() IS 
'Calculates final priority score with bridge cost and safety penalties. Max penalty: -20 points.';

-- ===========================================================================
-- 4. UPDATE EXISTING FUNCTION: approve_protocol
-- ===========================================================================

-- Update approve_protocol to copy bridge fields to protocols table
CREATE OR REPLACE FUNCTION approve_protocol(
    pending_id INTEGER,
    approved_by_user VARCHAR(100)
)
RETURNS INTEGER AS $$
DECLARE
    protocol_data RECORD;
    new_protocol_id INTEGER;
BEGIN
    -- Fetch pending protocol
    SELECT * INTO protocol_data
    FROM protocol_research_pending
    WHERE id = pending_id AND status = 'pending_approval';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Protocol ID % not found or already processed', pending_id;
    END IF;
    
    -- Calculate final priority score with bridge penalty
    -- (stored in priority_score column of protocols table)
    
    -- Insert into protocols table (including bridge fields)
    INSERT INTO protocols (
        name,
        category,
        chains,
        has_points_program,
        points_program_url,
        priority_score,
        is_active,
        last_researched_at,
        -- Bridge fields (added in migration 031)
        bridge_required,
        bridge_from_network,
        bridge_provider,
        bridge_cost_usd,
        cex_support
    ) VALUES (
        protocol_data.name,
        protocol_data.category,
        protocol_data.chains,
        protocol_data.has_points_program,
        protocol_data.points_program_url,
        calculate_final_priority_score(
            protocol_data.airdrop_score,
            protocol_data.bridge_required,
            protocol_data.bridge_cost_usd,
            protocol_data.bridge_safety_score
        ),
        TRUE,
        NOW(),
        -- Bridge fields
        protocol_data.bridge_required,
        protocol_data.bridge_from_network,
        protocol_data.bridge_provider,
        protocol_data.bridge_cost_usd,
        protocol_data.cex_support
    )
    RETURNING id INTO new_protocol_id;
    
    -- Update pending status
    UPDATE protocol_research_pending
    SET 
        status = 'approved',
        approved_by = approved_by_user,
        approved_at = NOW(),
        updated_at = NOW()
    WHERE id = pending_id;
    
    RETURN new_protocol_id;
END;
$$ LANGUAGE plpgsql;

-- ===========================================================================
-- 5. COMMENTS ON COLUMNS
-- ===========================================================================

COMMENT ON COLUMN protocol_research_pending.bridge_required IS 
'TRUE if the protocol network requires bridge (no CEX direct withdrawal support)';

COMMENT ON COLUMN protocol_research_pending.bridge_from_network IS 
'Source network for bridge, usually Arbitrum or Base (default: Arbitrum)';

COMMENT ON COLUMN protocol_research_pending.bridge_provider IS 
'Bridge aggregator: socket, across, relay, or NULL if unavailable';

COMMENT ON COLUMN protocol_research_pending.bridge_cost_usd IS 
'Estimated bridge cost in USD from aggregator API';

COMMENT ON COLUMN protocol_research_pending.bridge_safety_score IS 
'DeFiLlama safety score 0-100 (TVL + rank + no hacks + verified)';

COMMENT ON COLUMN protocol_research_pending.bridge_available IS 
'TRUE if bridge route found, FALSE if unreachable';

COMMENT ON COLUMN protocol_research_pending.bridge_checked_at IS 
'Timestamp of last bridge availability check';

COMMENT ON COLUMN protocol_research_pending.bridge_unreachable_reason IS 
'Reason why bridge is unavailable (e.g., "No route found via Socket/Across/Relay")';

COMMENT ON COLUMN protocol_research_pending.bridge_recheck_after IS 
'When to recheck unreachable protocol (7 days from last check)';

COMMENT ON COLUMN protocol_research_pending.bridge_recheck_count IS 
'Number of recheck attempts (max 4, then auto-reject)';

COMMENT ON COLUMN protocol_research_pending.cex_support IS 
'CEX name if direct withdrawal to network is supported (e.g., "bybit", "kucoin")';

-- ===========================================================================
-- 6. UPDATE EXISTING SAMPLE DATA
-- ===========================================================================

-- Update the test protocol with bridge info for testing
UPDATE protocol_research_pending
SET 
    bridge_required = FALSE,
    bridge_available = TRUE,
    cex_support = 'bybit',
    bridge_checked_at = NOW()
WHERE name = 'TestProtocol (Sample)';

-- Add another test protocol that requires bridge
INSERT INTO protocol_research_pending (
    name,
    category,
    chains,
    airdrop_score,
    has_points_program,
    has_token,
    recommended_actions,
    reasoning,
    discovered_from,
    source_article_title,
    -- Bridge fields
    bridge_required,
    bridge_from_network,
    bridge_provider,
    bridge_cost_usd,
    bridge_safety_score,
    bridge_available,
    bridge_checked_at
) VALUES (
    'InkDeFi (Bridge Required Sample)',
    'DEX',
    ARRAY['ink'],
    90,
    TRUE,
    FALSE,
    '["SWAP", "LP"]'::jsonb,
    'New DEX on Ink chain with points program. Requires bridge from Arbitrum.',
    'manual_testing',
    'InkDeFi Launches on Ink Network',
    -- Bridge fields
    TRUE,
    'Arbitrum',
    'across',
    2.50,
    95,
    TRUE,
    NOW()
) ON CONFLICT (name) DO NOTHING;

-- Add unreachable test protocol
INSERT INTO protocol_research_pending (
    name,
    category,
    chains,
    airdrop_score,
    has_points_program,
    has_token,
    recommended_actions,
    reasoning,
    discovered_from,
    source_article_title,
    -- Bridge fields
    bridge_required,
    bridge_available,
    bridge_unreachable_reason,
    bridge_checked_at,
    bridge_recheck_after,
    bridge_recheck_count
) VALUES (
    'FutureChain Protocol (Unreachable Sample)',
    'Lending',
    ARRAY['unknown_chain_xyz'],
    95,
    TRUE,
    FALSE,
    '["STAKE", "LP"]'::jsonb,
    'High potential protocol but on unsupported chain. Will recheck weekly.',
    'manual_testing',
    'FutureChain Raises $100M',
    -- Bridge fields
    TRUE,
    FALSE,
    'No bridge route found via Socket/Across/Relay. No CEX support.',
    NOW(),
    NOW() + INTERVAL '7 days',
    0
) ON CONFLICT (name) DO NOTHING;

-- ===========================================================================
-- 7. MIGRATION COMPLETE
-- ===========================================================================

-- Log migration completion
INSERT INTO research_logs (
    cycle_start_at,
    cycle_end_at,
    status,
    summary_report
) VALUES (
    NOW(),
    NOW(),
    'completed',
    'Migration 032: Protocol Research Bridge Integration completed. Added bridge fields to protocol_research_pending.'
);
