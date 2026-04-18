-- ============================================================================
-- Bridge Manager v2.0 - Database Migration
-- ============================================================================
-- Version: 2.0
-- Date: 2026-03-06
-- Description: Add bridge support with dynamic CEX checking
-- 
-- CRITICAL: No hardcoded network lists! All checks are dynamic via CEX API.
-- ============================================================================

-- ============================================================================
-- SECTION 1: BRIDGE HISTORY TABLE
-- ============================================================================

-- Bridge History (лог всех bridge операций)
CREATE TABLE IF NOT EXISTS bridge_history (
    id SERIAL PRIMARY KEY,
    
    -- Wallet and networks (ЛЮБЫЕ сети, не hardcoded!)
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    from_network VARCHAR(100) NOT NULL,  -- Source network (e.g., 'Arbitrum')
    to_network VARCHAR(100) NOT NULL,    -- Destination network (e.g., 'Ink', 'MegaETH', ANY L2)
    amount_eth DECIMAL(18, 8) NOT NULL,
    
    -- Provider information
    provider VARCHAR(100) NOT NULL,      -- Bridge provider (e.g., 'Across Protocol')
    cost_usd DECIMAL(10, 2),             -- Total cost in USD
    tx_hash VARCHAR(66),                 -- On-chain transaction hash
    
    -- DeFiLlama safety metrics
    defillama_tvl_usd BIGINT,            -- Total Value Locked in USD
    defillama_volume_30d_usd BIGINT,     -- 30-day volume in USD
    defillama_rank INTEGER,              -- Rank in DeFiLlama bridges list
    defillama_hacks INTEGER DEFAULT 0,   -- Number of known hacks/exploits
    safety_score INTEGER,                -- Calculated safety score 0-100
    
    -- CEX check result (для аудита - какие CEX были проверены)
    cex_checked VARCHAR(100),            -- Comma-separated: 'bybit,kucoin,mexc,okx,binance'
    cex_support_found BOOLEAN DEFAULT FALSE, -- TRUE if any CEX supports the network
    
    -- Status
    status VARCHAR(20) DEFAULT 'pending',
    error_message TEXT,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    
    CONSTRAINT chk_bridge_status CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'rejected'))
);

-- Indexes for bridge_history
CREATE INDEX IF NOT EXISTS idx_bridge_history_wallet ON bridge_history(wallet_id);
CREATE INDEX IF NOT EXISTS idx_bridge_history_status ON bridge_history(status);
CREATE INDEX IF NOT EXISTS idx_bridge_history_provider ON bridge_history(provider);
CREATE INDEX IF NOT EXISTS idx_bridge_history_to_network ON bridge_history(to_network);
CREATE INDEX IF NOT EXISTS idx_bridge_history_created ON bridge_history(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bridge_history_safety ON bridge_history(safety_score);

-- Comments
COMMENT ON TABLE bridge_history IS 'Log of all bridge operations with DeFiLlama safety metrics and CEX check results';
COMMENT ON COLUMN bridge_history.to_network IS 'Destination network - can be ANY L2 (no hardcoded list, dynamic check)';
COMMENT ON COLUMN bridge_history.from_network IS 'Source network - typically Arbitrum or another major L2';
COMMENT ON COLUMN bridge_history.safety_score IS 'Calculated safety score 0-100 based on TVL, rank, hacks';
COMMENT ON COLUMN bridge_history.cex_checked IS 'Comma-separated list of CEXes checked before bridge decision';
COMMENT ON COLUMN bridge_history.cex_support_found IS 'TRUE if any CEX supports the destination network (bridge not needed)';

-- ============================================================================
-- SECTION 2: PROTOCOL RESEARCH PENDING - BRIDGE COLUMNS
-- ============================================================================

-- Add bridge-related columns to protocol_research_pending
ALTER TABLE protocol_research_pending ADD COLUMN IF NOT EXISTS bridge_required BOOLEAN DEFAULT FALSE;
ALTER TABLE protocol_research_pending ADD COLUMN IF NOT EXISTS bridge_from_network VARCHAR(50) DEFAULT 'Arbitrum';
ALTER TABLE protocol_research_pending ADD COLUMN IF NOT EXISTS bridge_provider VARCHAR(100);
ALTER TABLE protocol_research_pending ADD COLUMN IF NOT EXISTS bridge_cost_usd DECIMAL(10, 2);
ALTER TABLE protocol_research_pending ADD COLUMN IF NOT EXISTS bridge_time_minutes INTEGER;
ALTER TABLE protocol_research_pending ADD COLUMN IF NOT EXISTS bridge_safety_score INTEGER;
ALTER TABLE protocol_research_pending ADD COLUMN IF NOT EXISTS bridge_available BOOLEAN DEFAULT TRUE;
ALTER TABLE protocol_research_pending ADD COLUMN IF NOT EXISTS bridge_checked_at TIMESTAMPTZ;
ALTER TABLE protocol_research_pending ADD COLUMN IF NOT EXISTS cex_support_found VARCHAR(50); -- CEX name if direct withdrawal possible

-- Indexes for protocol_research_pending bridge columns
CREATE INDEX IF NOT EXISTS idx_protocol_bridge_available ON protocol_research_pending(bridge_available);
CREATE INDEX IF NOT EXISTS idx_protocol_bridge_required ON protocol_research_pending(bridge_required) WHERE bridge_required = TRUE;
CREATE INDEX IF NOT EXISTS idx_protocol_bridge_safety ON protocol_research_pending(bridge_safety_score);

-- Comments
COMMENT ON COLUMN protocol_research_pending.bridge_required IS 'TRUE if no CEX supports the network (dynamic check via live API)';
COMMENT ON COLUMN protocol_research_pending.bridge_from_network IS 'Source network for bridge (default: Arbitrum)';
COMMENT ON COLUMN protocol_research_pending.bridge_available IS 'TRUE if bridge route found via aggregators';
COMMENT ON COLUMN protocol_research_pending.cex_support_found IS 'CEX name if direct withdrawal possible (e.g., "bybit"), NULL if bridge required';

-- ============================================================================
-- SECTION 3: PROTOCOLS TABLE - BRIDGE COLUMNS
-- ============================================================================

-- Add bridge information to approved protocols
ALTER TABLE protocols ADD COLUMN IF NOT EXISTS bridge_required BOOLEAN DEFAULT FALSE;
ALTER TABLE protocols ADD COLUMN IF NOT EXISTS bridge_from_network VARCHAR(50);
ALTER TABLE protocols ADD COLUMN IF NOT EXISTS bridge_provider VARCHAR(100);
ALTER TABLE protocols ADD COLUMN IF NOT EXISTS bridge_cost_usd DECIMAL(10, 2);
ALTER TABLE protocols ADD COLUMN IF NOT EXISTS cex_support VARCHAR(50); -- CEX name if direct withdrawal possible

-- Comments
COMMENT ON COLUMN protocols.bridge_required IS 'TRUE if protocol requires bridge to access (no CEX support)';
COMMENT ON COLUMN protocols.cex_support IS 'CEX name if direct withdrawal possible (e.g., "bybit")';

-- ============================================================================
-- SECTION 4: CEX NETWORKS CACHE TABLE (Optional - for performance)
-- ============================================================================

-- Cache table for CEX supported networks (24-hour TTL)
CREATE TABLE IF NOT EXISTS cex_networks_cache (
    id SERIAL PRIMARY KEY,
    
    cex_name VARCHAR(50) NOT NULL,       -- 'binance', 'bybit', 'okx', 'kucoin', 'mexc'
    coin VARCHAR(20) NOT NULL DEFAULT 'ETH',
    supported_networks JSONB NOT NULL,   -- Array of network names: ["Arbitrum One", "Base Mainnet", ...]
    
    -- Cache metadata
    fetched_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,     -- NOW() + 24 hours
    is_stale BOOLEAN DEFAULT FALSE,      -- TRUE if API failed and using old cache
    
    -- Constraints
    UNIQUE(cex_name, coin)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_cex_cache_cex ON cex_networks_cache(cex_name);
CREATE INDEX IF NOT EXISTS idx_cex_cache_expires ON cex_networks_cache(expires_at);
CREATE INDEX IF NOT EXISTS idx_cex_cache_stale ON cex_networks_cache(is_stale) WHERE is_stale = TRUE;

-- Comments
COMMENT ON TABLE cex_networks_cache IS 'Cache for CEX supported networks (24-hour TTL). Updated via live API calls.';
COMMENT ON COLUMN cex_networks_cache.supported_networks IS 'JSON array of network names from live CEX API';
COMMENT ON COLUMN cex_networks_cache.expires_at IS 'Cache expiration time (24 hours from fetch)';
COMMENT ON COLUMN cex_networks_cache.is_stale IS 'TRUE if API failed and using expired cache as fallback';

-- ============================================================================
-- SECTION 5: DEFILLAMA BRIDGES CACHE TABLE (Optional - for performance)
-- ============================================================================

-- Cache table for DeFiLlama bridges data (6-hour TTL)
CREATE TABLE IF NOT EXISTS defillama_bridges_cache (
    id SERIAL PRIMARY KEY,
    
    bridge_name VARCHAR(100) NOT NULL UNIQUE,
    display_name VARCHAR(100),
    chains JSONB,                        -- Array of supported chains
    tvl_usd BIGINT,                      -- Total Value Locked
    volume_30d_usd BIGINT,               -- 30-day volume
    rank INTEGER,                        -- Rank in DeFiLlama list
    hacks JSONB,                         -- Array of hack incidents
    
    -- Cache metadata
    fetched_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL      -- NOW() + 6 hours
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_defillama_cache_name ON defillama_bridges_cache(bridge_name);
CREATE INDEX IF NOT EXISTS idx_defillama_cache_rank ON defillama_bridges_cache(rank);
CREATE INDEX IF NOT EXISTS idx_defillama_cache_tvl ON defillama_bridges_cache(tvl_usd DESC);
CREATE INDEX IF NOT EXISTS idx_defillama_cache_expires ON defillama_bridges_cache(expires_at);

-- Comments
COMMENT ON TABLE defillama_bridges_cache IS 'Cache for DeFiLlama bridges data (6-hour TTL). Used for safety verification.';
COMMENT ON COLUMN defillama_bridges_cache.tvl_usd IS 'Total Value Locked in USD - used for safety score calculation';
COMMENT ON COLUMN defillama_bridges_cache.rank IS 'Rank in DeFiLlama bridges list - TOP-50 required for auto-approve';

-- ============================================================================
-- SECTION 6: SCHEDULED_TRANSACTIONS - BRIDGE SUPPORT
-- ============================================================================

-- Add bridge-specific columns to scheduled_transactions
ALTER TABLE scheduled_transactions ADD COLUMN IF NOT EXISTS from_network VARCHAR(50);
ALTER TABLE scheduled_transactions ADD COLUMN IF NOT EXISTS to_network VARCHAR(50);
ALTER TABLE scheduled_transactions ADD COLUMN IF NOT EXISTS depends_on_tx_id INTEGER REFERENCES scheduled_transactions(id);

-- Comments
COMMENT ON COLUMN scheduled_transactions.from_network IS 'Source network for BRIDGE transactions';
COMMENT ON COLUMN scheduled_transactions.to_network IS 'Destination network for BRIDGE transactions';
COMMENT ON COLUMN scheduled_transactions.depends_on_tx_id IS 'Dependency: wait for this TX to complete before executing';

-- ============================================================================
-- SECTION 7: HELPER FUNCTIONS
-- ============================================================================

-- Function to calculate bridge safety score
CREATE OR REPLACE FUNCTION calculate_bridge_safety_score(
    p_tvl_usd BIGINT,
    p_rank INTEGER,
    p_hacks_count INTEGER DEFAULT 0,
    p_is_verified BOOLEAN DEFAULT TRUE
) RETURNS INTEGER AS $$
DECLARE
    v_score INTEGER := 0;
BEGIN
    -- TVL score (40 points max)
    IF p_tvl_usd >= 100000000 THEN        -- $100M+
        v_score := v_score + 40;
    ELSIF p_tvl_usd >= 50000000 THEN      -- $50M+
        v_score := v_score + 35;
    ELSIF p_tvl_usd >= 10000000 THEN      -- $10M+
        v_score := v_score + 25;
    ELSIF p_tvl_usd >= 5000000 THEN       -- $5M+
        v_score := v_score + 15;
    END IF;
    
    -- Rank score (30 points max)
    IF p_rank <= 5 THEN
        v_score := v_score + 30;
    ELSIF p_rank <= 10 THEN
        v_score := v_score + 25;
    ELSIF p_rank <= 25 THEN
        v_score := v_score + 20;
    ELSIF p_rank <= 50 THEN
        v_score := v_score + 15;
    END IF;
    
    -- No hacks (20 points)
    IF p_hacks_count = 0 THEN
        v_score := v_score + 20;
    ELSE
        v_score := v_score - (p_hacks_count * 10);  -- -10 per hack
    END IF;
    
    -- Verified contract (10 points)
    IF p_is_verified THEN
        v_score := v_score + 10;
    END IF;
    
    -- Clamp to 0-100
    RETURN GREATEST(0, LEAST(100, v_score));
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_bridge_safety_score IS 'Calculate bridge safety score 0-100 based on TVL, rank, hacks, verification';

-- Function to check if bridge is safe (auto-approve threshold)
CREATE OR REPLACE FUNCTION is_bridge_safe(p_safety_score INTEGER)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN p_safety_score >= 60;  -- 60+ = auto-approve
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION is_bridge_safe IS 'Returns TRUE if bridge safety score >= 60 (auto-approve threshold)';

-- Function to get cached CEX networks (or mark as stale)
CREATE OR REPLACE FUNCTION get_cex_cached_networks(p_cex_name VARCHAR, p_coin VARCHAR DEFAULT 'ETH')
RETURNS TABLE (
    supported_networks JSONB,
    is_stale BOOLEAN,
    fetched_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.supported_networks,
        c.is_stale,
        c.fetched_at
    FROM cex_networks_cache c
    WHERE c.cex_name = p_cex_name
      AND c.coin = p_coin
      AND (c.expires_at > NOW() OR c.is_stale = TRUE)  -- Return even if stale (fallback)
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_cex_cached_networks IS 'Get cached CEX networks (returns stale cache if fresh not available)';

-- ============================================================================
-- SECTION 8: TRIGGERS
-- ============================================================================

-- Trigger to auto-update expires_at for cex_networks_cache
CREATE OR REPLACE FUNCTION update_cex_cache_expires()
RETURNS TRIGGER AS $$
BEGIN
    NEW.expires_at = NEW.fetched_at + INTERVAL '24 hours';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cex_cache_expires ON cex_networks_cache;
CREATE TRIGGER trg_cex_cache_expires
    BEFORE INSERT OR UPDATE ON cex_networks_cache
    FOR EACH ROW
    EXECUTE FUNCTION update_cex_cache_expires();

-- Trigger to auto-update expires_at for defillama_bridges_cache
CREATE OR REPLACE FUNCTION update_defillama_cache_expires()
RETURNS TRIGGER AS $$
BEGIN
    NEW.expires_at = NEW.fetched_at + INTERVAL '6 hours';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_defillama_cache_expires ON defillama_bridges_cache;
CREATE TRIGGER trg_defillama_cache_expires
    BEFORE INSERT OR UPDATE ON defillama_bridges_cache
    FOR EACH ROW
    EXECUTE FUNCTION update_defillama_cache_expires();

-- ============================================================================
-- SECTION 9: VIEWS FOR MONITORING
-- ============================================================================

-- View: Recent bridge operations
CREATE OR REPLACE VIEW v_recent_bridges AS
SELECT 
    bh.id,
    bh.wallet_id,
    w.address AS wallet_address,
    bh.from_network,
    bh.to_network,
    bh.amount_eth,
    bh.provider,
    bh.cost_usd,
    bh.safety_score,
    bh.status,
    bh.tx_hash,
    bh.created_at,
    bh.completed_at,
    bh.cex_support_found
FROM bridge_history bh
JOIN wallets w ON w.id = bh.wallet_id
ORDER BY bh.created_at DESC
LIMIT 100;

COMMENT ON VIEW v_recent_bridges IS 'Recent bridge operations for monitoring';

-- View: Bridge statistics by network
CREATE OR REPLACE VIEW v_bridge_stats_by_network AS
SELECT 
    to_network,
    COUNT(*) AS total_bridges,
    COUNT(*) FILTER (WHERE status = 'completed') AS successful_bridges,
    COUNT(*) FILTER (WHERE status = 'failed') AS failed_bridges,
    AVG(cost_usd) AS avg_cost_usd,
    AVG(safety_score) AS avg_safety_score,
    SUM(amount_eth) AS total_eth_bridged
FROM bridge_history
GROUP BY to_network
ORDER BY total_bridges DESC;

COMMENT ON VIEW v_bridge_stats_by_network IS 'Bridge statistics by destination network';

-- View: Protocols requiring bridge
CREATE OR REPLACE VIEW v_protocols_requiring_bridge AS
SELECT 
    p.id AS protocol_id,
    p.name AS protocol_name,
    p.chain,
    prp.bridge_required,
    prp.bridge_available,
    prp.bridge_provider,
    prp.bridge_cost_usd,
    prp.bridge_safety_score,
    prp.cex_support_found,
    prp.airdrop_score,
    prp.status AS research_status
FROM protocols p
JOIN protocol_research_pending prp ON prp.name = p.name
WHERE prp.bridge_required = TRUE
ORDER BY prp.airdrop_score DESC;

COMMENT ON VIEW v_protocols_requiring_bridge IS 'Protocols that require bridge to access (no CEX support)';

-- ============================================================================
-- SECTION 10: CACHE CLEANUP FUNCTIONS
-- ============================================================================

-- Function to clean expired CEX networks cache
CREATE OR REPLACE FUNCTION cleanup_expired_cex_cache()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM cex_networks_cache
    WHERE expires_at < NOW()
      AND is_stale = FALSE;  -- Keep stale cache as fallback
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    
    RAISE NOTICE 'Cleaned % expired CEX cache entries', v_deleted_count;
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_expired_cex_cache IS
'Remove expired CEX networks cache entries. Run periodically via pg_cron or application scheduler.';

-- Function to clean expired DeFiLlama bridges cache
CREATE OR REPLACE FUNCTION cleanup_expired_defillama_cache()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM defillama_bridges_cache
    WHERE expires_at < NOW();
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    
    RAISE NOTICE 'Cleaned % expired DeFiLlama cache entries', v_deleted_count;
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_expired_defillama_cache IS
'Remove expired DeFiLlama bridges cache entries. Run periodically via pg_cron or application scheduler.';

-- Combined cleanup function for all cache tables
CREATE OR REPLACE FUNCTION cleanup_all_expired_cache()
RETURNS TABLE(
    cache_type TEXT,
    deleted_count INTEGER
) AS $$
BEGIN
    -- Clean CEX cache
    RETURN QUERY
    SELECT 'cex_networks'::TEXT, cleanup_expired_cex_cache();
    
    -- Clean DeFiLlama cache
    RETURN QUERY
    SELECT 'defillama_bridges'::TEXT, cleanup_expired_defillama_cache();
    
    RAISE NOTICE 'Cache cleanup completed';
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_all_expired_cache IS
'Clean all expired cache entries. Recommended: run every 6 hours via pg_cron.';

-- ============================================================================
-- SECTION 11: PG_CRON JOBS (Optional - requires pg_cron extension)
-- ============================================================================

-- Uncomment if pg_cron is installed:
-- SELECT cron.schedule('cleanup_cache_hourly', '0 * * * *',
--     $$SELECT cleanup_all_expired_cache()$$);

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

-- Summary:
-- ✅ Created bridge_history table (logs all bridge operations)
-- ✅ Added bridge columns to protocol_research_pending
-- ✅ Added bridge columns to protocols table
-- ✅ Created cex_networks_cache table (24-hour TTL)
-- ✅ Created defillama_bridges_cache table (6-hour TTL)
-- ✅ Added bridge support to scheduled_transactions
-- ✅ Created helper functions for safety score calculation
-- ✅ Created triggers for cache expiration
-- ✅ Created views for monitoring
-- ✅ Added cache cleanup functions (cleanup_all_expired_cache)
