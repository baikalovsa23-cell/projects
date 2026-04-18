-- Migration 045: Token Cache and Chain Farm Status for Smart Risk Engine
-- This migration adds token_check_cache table and farm_status columns for token kill-switch
-- Author: Airdrop Farming System v4.0
-- Date: 2026-03-23

-- ============================================================================
-- 1. Create token_check_cache table
-- ============================================================================

CREATE TABLE IF NOT EXISTS token_check_cache (
    protocol_name VARCHAR(100) PRIMARY KEY,
    has_token BOOLEAN NOT NULL,
    ticker VARCHAR(20),
    market_cap_usd NUMERIC,
    checked_at TIMESTAMPTZ NOT NULL,
    source VARCHAR(20) NOT NULL
);

-- Index for faster lookups by checked_at (for cache expiration)
CREATE INDEX IF NOT EXISTS idx_token_cache_checked_at ON token_check_cache(checked_at);

-- Add comments
COMMENT ON TABLE token_check_cache IS 'Cache for token existence checks - used by Smart Risk Engine to skip protocols with existing tokens';
COMMENT ON COLUMN token_check_cache.protocol_name IS 'Protocol/chain name to check (e.g., "arbitrum", "uniswap")';
COMMENT ON COLUMN token_check_cache.has_token IS 'TRUE if protocol has its own token listed on CoinGecko/DeFiLlama';
COMMENT ON COLUMN token_check_cache.ticker IS 'Token ticker symbol (e.g., "ARB", "UNI")';
COMMENT ON COLUMN token_check_cache.market_cap_usd IS 'Market cap in USD from CoinGecko';
COMMENT ON COLUMN token_check_cache.source IS 'Data source: "coingecko" or "defillama"';
COMMENT ON COLUMN token_check_cache.checked_at IS 'Timestamp of last check - cache expires after 24 hours';

-- ============================================================================
-- 2. Add farm_status and token_ticker columns to chain_rpc_endpoints
-- ============================================================================

-- Add farm_status column (ACTIVE, TARGET, DROPPED, INACTIVE)
ALTER TABLE chain_rpc_endpoints 
ADD COLUMN IF NOT EXISTS farm_status VARCHAR(20) DEFAULT 'ACTIVE';

-- Add token_ticker column (populated when token detected)
ALTER TABLE chain_rpc_endpoints 
ADD COLUMN IF NOT EXISTS token_ticker VARCHAR(20);

-- Add last_discovery_check timestamp
ALTER TABLE chain_rpc_endpoints 
ADD COLUMN IF NOT EXISTS last_discovery_check TIMESTAMPTZ;

-- Create index for farming chains lookup
CREATE INDEX IF NOT EXISTS idx_chain_farm_status ON chain_rpc_endpoints(farm_status);

-- Add comments
COMMENT ON COLUMN chain_rpc_endpoints.farm_status IS 'Farming status: ACTIVE (farming), TARGET (planned), DROPPED (token exists - kill-switch), INACTIVE (disabled)';
COMMENT ON COLUMN chain_rpc_endpoints.token_ticker IS 'Token ticker if chain has its own token (e.g., "ARB" for Arbitrum)';
COMMENT ON COLUMN chain_rpc_endpoints.last_discovery_check IS 'Timestamp of last discovery check including token verification';

-- ============================================================================
-- 3. Add risk columns to protocol_research_pending (if not exists)
-- ============================================================================

-- Add risk_level column
ALTER TABLE protocol_research_pending 
ADD COLUMN IF NOT EXISTS risk_level VARCHAR(20) DEFAULT 'MEDIUM';

-- Add risk_tags column (array of risk tags)
ALTER TABLE protocol_research_pending 
ADD COLUMN IF NOT EXISTS risk_tags TEXT[] DEFAULT '{}';

-- Add requires_manual column (human review needed)
ALTER TABLE protocol_research_pending 
ADD COLUMN IF NOT EXISTS requires_manual BOOLEAN DEFAULT FALSE;

-- Add risk_score column (0-100)
ALTER TABLE protocol_research_pending 
ADD COLUMN IF NOT EXISTS risk_score INTEGER;

-- Add comments
COMMENT ON COLUMN protocol_research_pending.risk_level IS 'Risk level: LOW, MEDIUM, HIGH, CRITICAL';
COMMENT ON COLUMN protocol_research_pending.risk_tags IS 'Array of risk tags: ["SYBIL", "KYC_REQUIRED", "TVL_LOW", "HACK_HISTORY", etc.]';
COMMENT ON COLUMN protocol_research_pending.requires_manual IS 'TRUE if protocol requires manual review before approval';
COMMENT ON COLUMN protocol_research_pending.risk_score IS 'Risk score 0-100 (higher = safer)';

-- ============================================================================
-- 4. Insert default farm_status for existing chains
-- ============================================================================

-- Set ACTIVE for all existing chains (will be updated by discovery check)
UPDATE chain_rpc_endpoints 
SET farm_status = 'ACTIVE' 
WHERE farm_status IS NULL;

-- ============================================================================
-- 5. Create helper function for cache cleanup
-- ============================================================================

CREATE OR REPLACE FUNCTION clear_expired_token_cache()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM token_check_cache 
    WHERE checked_at < NOW() - INTERVAL '24 hours';
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    RETURN deleted_count;
END;
$$;

COMMENT ON FUNCTION clear_expired_token_cache() IS 'Removes token cache entries older than 24 hours - returns count of deleted rows';

-- ============================================================================
-- 6. Create helper function to get farming chains
-- ============================================================================

CREATE OR REPLACE FUNCTION get_active_farming_chains()
RETURNS TABLE(chain VARCHAR, farm_status VARCHAR, token_ticker VARCHAR)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT 
        cre.chain::VARCHAR,
        cre.farm_status::VARCHAR,
        cre.token_ticker::VARCHAR
    FROM chain_rpc_endpoints cre
    WHERE cre.farm_status IN ('ACTIVE', 'TARGET')
      AND cre.is_active = TRUE
    ORDER BY cre.chain;
END;
$$;

COMMENT ON FUNCTION get_active_farming_chains() IS 'Returns list of chains with ACTIVE or TARGET farm_status for protocol filtering';
