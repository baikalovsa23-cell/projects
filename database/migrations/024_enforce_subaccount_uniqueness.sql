-- ============================================================================
-- Migration 024: Enforce Subaccount Uniqueness
-- ============================================================================
-- 
-- Critical Security Fix:
-- Ensures each CEX subaccount is used by EXACTLY one funding chain.
-- Prevents Sybil detection through funding source clustering.
--
-- Changes:
-- 1. Add UNIQUE constraint on cex_subaccount_id
-- 2. Create validation function for isolation checks
-- 3. Add helper views for monitoring
--
-- Author: Airdrop Farming System v4.0
-- Created: 2026-02-28
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Add UNIQUE Constraint
-- ============================================================================

-- First check if there are any violations
DO $$
DECLARE
    violation_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO violation_count
    FROM (
        SELECT cex_subaccount_id, COUNT(*) as cnt
        FROM funding_chains
        WHERE cex_subaccount_id IS NOT NULL
        GROUP BY cex_subaccount_id
        HAVING COUNT(*) > 1
    ) violations;
    
    IF violation_count > 0 THEN
        RAISE EXCEPTION 'Cannot add UNIQUE constraint: % subaccounts used by multiple chains', violation_count;
    END IF;
END $$;

-- Add UNIQUE constraint (will fail if violations exist)
ALTER TABLE funding_chains
ADD CONSTRAINT unique_subaccount_per_chain UNIQUE(cex_subaccount_id);

COMMENT ON CONSTRAINT unique_subaccount_per_chain ON funding_chains IS 
    'Each CEX subaccount must fund exactly one chain (1:1 mapping for anti-Sybil isolation)';


-- ============================================================================
-- 2. Validation Function
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_funding_isolation()
RETURNS TABLE (issue_type TEXT, severity TEXT, details TEXT) AS $$
BEGIN
    -- Check 1: Subaccount reuse (CRITICAL)
    RETURN QUERY
    SELECT 
        'SUBACCOUNT_REUSE'::TEXT,
        'CRITICAL'::TEXT,
        'Subaccount ' || cex_subaccount_id || ' used by ' || COUNT(*) || ' chains: ' || 
        ARRAY_AGG(id ORDER BY id)::TEXT as details
    FROM funding_chains
    WHERE cex_subaccount_id IS NOT NULL
    GROUP BY cex_subaccount_id
    HAVING COUNT(*) > 1;
    
    -- Check 2: Stuck intermediate wallets (HIGH)
    -- Wallets funded but not forwarded after expected delay + 24h buffer
    RETURN QUERY
    SELECT
        'STUCK_INTERMEDIATE'::TEXT,
        'HIGH'::TEXT,
        'Wallet ' || ifw.address || ' (layer ' || ifw.layer || ') stuck for ' || 
        ROUND(EXTRACT(EPOCH FROM (NOW() - ifw.cex_funded_at))/3600, 1) || 'h | ' ||
        'Expected forward at: ' || (ifw.cex_funded_at + (fc.intermediate_delay_1_hours || ' hours')::INTERVAL)::TEXT
    FROM intermediate_funding_wallets ifw
    JOIN funding_chains fc ON ifw.funding_chain_id = fc.id
    WHERE ifw.status = 'funded'
      AND ifw.cex_funded_at IS NOT NULL
      AND NOW() > ifw.cex_funded_at + (fc.intermediate_delay_1_hours + 24 || ' hours')::INTERVAL;
    
    -- Check 3: Intermediate wallets without funding chain (MEDIUM)
    RETURN QUERY
    SELECT
        'ORPHAN_INTERMEDIATE'::TEXT,
        'MEDIUM'::TEXT,
        'Wallet ' || address || ' has no valid funding_chain_id: ' || funding_chain_id::TEXT
    FROM intermediate_funding_wallets ifw
    WHERE NOT EXISTS (
        SELECT 1 FROM funding_chains fc WHERE fc.id = ifw.funding_chain_id
    );
    
    -- Check 4: Chains with missing intermediate wallets (MEDIUM)
    RETURN QUERY
    SELECT
        'MISSING_INTERMEDIATE'::TEXT,
        'MEDIUM'::TEXT,
        'Chain ' || id || ' has intermediate_wallet_1=' || 
        COALESCE(intermediate_wallet_1, 'NULL') || ' but no DB record'
    FROM funding_chains fc
    WHERE intermediate_wallet_1 IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM intermediate_funding_wallets ifw 
          WHERE ifw.address = fc.intermediate_wallet_1
      );
    
    -- Check 5: Variable cluster size violations (LOW)
    -- Alert if all chains have same size (anti-sybil violation)
    RETURN QUERY
    SELECT
        'UNIFORM_CLUSTER_SIZE'::TEXT,
        'LOW'::TEXT,
        'All ' || COUNT(*) || ' chains have size ' || actual_wallet_count || ' (expected: variable 3-7)'
    FROM funding_chains
    WHERE actual_wallet_count IS NOT NULL
    GROUP BY actual_wallet_count
    HAVING COUNT(*) = (SELECT COUNT(*) FROM funding_chains WHERE actual_wallet_count IS NOT NULL)
      AND COUNT(*) > 1;
    
    -- Check 6: Proxy assignment issues (MEDIUM)
    RETURN QUERY
    SELECT
        'INTERMEDIATE_NO_PROXY'::TEXT,
        'MEDIUM'::TEXT,
        'Intermediate wallet ' || address || ' (layer ' || layer || ') has no proxy assigned'
    FROM intermediate_funding_wallets
    WHERE proxy_id IS NULL;
    
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_funding_isolation() IS 
    'Validates funding chain isolation and detects anti-Sybil violations';


-- ============================================================================
-- 3. Monitoring Views
-- ============================================================================

-- View: Subaccount usage summary
CREATE OR REPLACE VIEW v_subaccount_usage AS
SELECT 
    cs.id,
    cs.exchange,
    cs.subaccount_name,
    fc.id as funding_chain_id,
    fc.chain_number,
    fc.actual_wallet_count,
    fc.withdrawal_network,
    fc.status,
    fc.created_at
FROM cex_subaccounts cs
LEFT JOIN funding_chains fc ON cs.id = fc.cex_subaccount_id
ORDER BY cs.exchange, cs.subaccount_name;

COMMENT ON VIEW v_subaccount_usage IS 
    'Shows which funding chains use which CEX subaccounts (should be 1:1)';


-- View: Intermediate wallet status
CREATE OR REPLACE VIEW v_intermediate_wallet_status AS
SELECT 
    ifw.id,
    ifw.address,
    ifw.layer,
    ifw.status,
    fc.chain_number,
    fc.withdrawal_network,
    cs.exchange || '/' || cs.subaccount_name as cex_source,
    ifw.cex_funded_at,
    CASE 
        WHEN ifw.layer = 1 THEN fc.intermediate_delay_1_hours
        WHEN ifw.layer = 2 THEN fc.intermediate_delay_2_hours
    END as expected_delay_hours,
    CASE 
        WHEN ifw.cex_funded_at IS NOT NULL THEN
            ROUND(EXTRACT(EPOCH FROM (NOW() - ifw.cex_funded_at))/3600, 1)
    END as hours_since_funding,
    pp.country_code as proxy_region,
    pp.ip_address as proxy_ip
FROM intermediate_funding_wallets ifw
JOIN funding_chains fc ON ifw.funding_chain_id = fc.id
JOIN cex_subaccounts cs ON fc.cex_subaccount_id = cs.id
LEFT JOIN proxy_pool pp ON ifw.proxy_id = pp.id
ORDER BY fc.chain_number, ifw.layer;

COMMENT ON VIEW v_intermediate_wallet_status IS 
    'Real-time status of all intermediate wallets with timing metrics';


-- ============================================================================
-- 4. Index Optimizations
-- ============================================================================

-- Speed up validation queries
CREATE INDEX IF NOT EXISTS idx_intermediate_wallets_status_funded 
ON intermediate_funding_wallets(status, cex_funded_at) 
WHERE status = 'funded';

CREATE INDEX IF NOT EXISTS idx_intermediate_wallets_chain_layer 
ON intermediate_funding_wallets(funding_chain_id, layer);

CREATE INDEX IF NOT EXISTS idx_funding_chains_subaccount 
ON funding_chains(cex_subaccount_id) 
WHERE cex_subaccount_id IS NOT NULL;


-- ============================================================================
-- 5. Helper Function: Quick Isolation Check
-- ============================================================================

CREATE OR REPLACE FUNCTION quick_isolation_check()
RETURNS JSON AS $$
DECLARE
    result JSON;
    critical_count INTEGER;
    high_count INTEGER;
    total_issues INTEGER;
BEGIN
    -- Count issues by severity
    SELECT 
        COUNT(*) FILTER (WHERE severity = 'CRITICAL') as critical,
        COUNT(*) FILTER (WHERE severity = 'HIGH') as high,
        COUNT(*) as total
    INTO critical_count, high_count, total_issues
    FROM validate_funding_isolation();
    
    -- Return summary
    result := json_build_object(
        'timestamp', NOW(),
        'total_issues', total_issues,
        'critical', critical_count,
        'high', high_count,
        'status', CASE 
            WHEN critical_count > 0 THEN 'CRITICAL'
            WHEN high_count > 0 THEN 'WARNING'
            ELSE 'OK'
        END
    );
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION quick_isolation_check() IS 
    'Returns JSON summary of isolation status (for monitoring)';


-- ============================================================================
-- Migration Complete
-- ============================================================================

-- Log migration
INSERT INTO system_events (event_type, severity, message, metadata)
VALUES (
    'MIGRATION',
    'info',
    'Migration 024: Subaccount uniqueness constraint added',
    json_build_object(
        'constraint', 'unique_subaccount_per_chain',
        'validation_function', 'validate_funding_isolation',
        'views_created', ARRAY['v_subaccount_usage', 'v_intermediate_wallet_status']
    )
);

COMMIT;

-- ============================================================================
-- Post-Migration Validation
-- ============================================================================

-- Run validation check
SELECT * FROM validate_funding_isolation();

-- Show summary
SELECT * FROM quick_isolation_check();

-- Show subaccount usage
SELECT * FROM v_subaccount_usage ORDER BY exchange, subaccount_name;
