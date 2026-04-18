-- ============================================================================
-- Migration 035: Chain Aliases & Discovery Failures
-- ============================================================================
-- Purpose: Support automatic chain discovery and name normalization
-- Author: System Architect
-- Date: 2026-03-09
-- ============================================================================

-- ============================================================================
-- SECTION 1: CHAIN_ALIASES TABLE
-- ============================================================================

-- Table for storing alternative names for chains (normalization)
-- Note: chain_id is stored as INTEGER (not FK) because chain_rpc_endpoints
-- can have multiple rows per chain_id (multiple RPC endpoints)
CREATE TABLE IF NOT EXISTS chain_aliases (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER NOT NULL,
    alias VARCHAR(100) NOT NULL,
    source VARCHAR(50) DEFAULT 'manual',
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure unique aliases across all chains
    CONSTRAINT chain_aliases_alias_unique UNIQUE (alias)
);

-- Indexes for fast lookup
CREATE INDEX IF NOT EXISTS idx_chain_aliases_chain_id ON chain_aliases(chain_id);
CREATE INDEX IF NOT EXISTS idx_chain_aliases_alias ON chain_aliases(alias);
CREATE INDEX IF NOT EXISTS idx_chain_aliases_source ON chain_aliases(source);

COMMENT ON TABLE chain_aliases IS 'Alternative names for blockchain networks (normalization)';
COMMENT ON COLUMN chain_aliases.chain_id IS 'Chain ID (e.g., 42161 for Arbitrum)';
COMMENT ON COLUMN chain_aliases.alias IS 'Alternative name (e.g., "eth-mainnet" for "ethereum")';
COMMENT ON COLUMN chain_aliases.source IS 'Where this alias came from: "chainid", "defillama", "socket", "cex", "manual"';
COMMENT ON COLUMN chain_aliases.last_seen IS 'When this alias was last encountered in external data';

-- ============================================================================
-- SECTION 2: DISCOVERY_FAILURES TABLE
-- ============================================================================

-- Table for logging failed chain discovery attempts
CREATE TABLE IF NOT EXISTS discovery_failures (
    id SERIAL PRIMARY KEY,
    network_name VARCHAR(100) NOT NULL,
    sources_checked TEXT[] NOT NULL,
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    last_retry_at TIMESTAMPTZ,
    resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMPTZ,
    resolved_chain_id INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for discovery_failures
CREATE INDEX IF NOT EXISTS idx_discovery_failures_network_name ON discovery_failures(network_name);
CREATE INDEX IF NOT EXISTS idx_discovery_failures_resolved ON discovery_failures(resolved) WHERE resolved = FALSE;
CREATE INDEX IF NOT EXISTS idx_discovery_failures_created_at ON discovery_failures(created_at DESC);

COMMENT ON TABLE discovery_failures IS 'Log of failed chain discovery attempts for manual review';
COMMENT ON COLUMN discovery_failures.network_name IS 'Network name that could not be discovered';
COMMENT ON COLUMN discovery_failures.sources_checked IS 'Array of sources that were checked: ["chainid", "defillama", "socket"]';
COMMENT ON COLUMN discovery_failures.error_message IS 'Error message from discovery attempt';
COMMENT ON COLUMN discovery_failures.retry_count IS 'Number of times discovery was retried';
COMMENT ON COLUMN discovery_failures.resolved IS 'TRUE if the chain was later registered manually or discovered';
COMMENT ON COLUMN discovery_failures.resolved_chain_id IS 'Chain ID if the network was later resolved';

-- ============================================================================
-- SECTION 3: ADD is_auto_discovered TO chain_rpc_endpoints
-- ============================================================================

-- Add column to track auto-discovered chains
ALTER TABLE chain_rpc_endpoints 
ADD COLUMN IF NOT EXISTS is_auto_discovered BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN chain_rpc_endpoints.is_auto_discovered IS 'TRUE if this chain was auto-discovered by ChainDiscoveryService';

-- ============================================================================
-- SECTION 4: SEED KNOWN ALIASES
-- ============================================================================

-- Insert known aliases for existing chains
-- These are common variations used by different APIs

-- Ethereum
INSERT INTO chain_aliases (chain_id, alias, source) VALUES
(1, 'eth', 'manual'),
(1, 'eth-mainnet', 'socket'),
(1, 'ethereum mainnet', 'defillama'),
(1, 'erc20', 'cex'),
(1, 'mainnet', 'common')
ON CONFLICT (alias) DO UPDATE SET last_seen = NOW();

-- Arbitrum
INSERT INTO chain_aliases (chain_id, alias, source) VALUES
(42161, 'arb', 'manual'),
(42161, 'arbitrum one', 'socket'),
(42161, 'arbitrum-one', 'across'),
(42161, 'arb1', 'common')
ON CONFLICT (alias) DO UPDATE SET last_seen = NOW();

-- Base
INSERT INTO chain_aliases (chain_id, alias, source) VALUES
(8453, 'base mainnet', 'socket'),
(8453, 'base-mainnet', 'across')
ON CONFLICT (alias) DO UPDATE SET last_seen = NOW();

-- Optimism
INSERT INTO chain_aliases (chain_id, alias, source) VALUES
(10, 'op', 'manual'),
(10, 'op mainnet', 'socket'),
(10, 'optimism mainnet', 'defillama'),
(10, 'optimism-mainnet', 'across')
ON CONFLICT (alias) DO UPDATE SET last_seen = NOW();

-- Polygon
INSERT INTO chain_aliases (chain_id, alias, source) VALUES
(137, 'matic', 'manual'),
(137, 'polygon mainnet', 'defillama'),
(137, 'polygon-mainnet', 'across')
ON CONFLICT (alias) DO UPDATE SET last_seen = NOW();

-- BNB Chain
INSERT INTO chain_aliases (chain_id, alias, source) VALUES
(56, 'bsc', 'manual'),
(56, 'bnb', 'common'),
(56, 'bnb smart chain', 'socket'),
(56, 'bnbchain', 'cex')
ON CONFLICT (alias) DO UPDATE SET last_seen = NOW();

-- zkSync Era
INSERT INTO chain_aliases (chain_id, alias, source) VALUES
(324, 'zksync', 'manual'),
(324, 'zksync era', 'defillama'),
(324, 'era', 'common')
ON CONFLICT (alias) DO UPDATE SET last_seen = NOW();

-- Scroll
INSERT INTO chain_aliases (chain_id, alias, source) VALUES
(534352, 'scroll', 'manual'),
(534352, 'scroll mainnet', 'defillama')
ON CONFLICT (alias) DO UPDATE SET last_seen = NOW();

-- Linea
INSERT INTO chain_aliases (chain_id, alias, source) VALUES
(59144, 'linea', 'manual'),
(59144, 'linea mainnet', 'defillama')
ON CONFLICT (alias) DO UPDATE SET last_seen = NOW();

-- Mantle
INSERT INTO chain_aliases (chain_id, alias, source) VALUES
(5000, 'mantle', 'manual')
ON CONFLICT (alias) DO UPDATE SET last_seen = NOW();

-- Ink
INSERT INTO chain_aliases (chain_id, alias, source) VALUES
(57073, 'ink', 'manual'),
(57073, 'ink mainnet', 'defillama')
ON CONFLICT (alias) DO UPDATE SET last_seen = NOW();

-- ============================================================================
-- SECTION 5: GRANT PERMISSIONS
-- ============================================================================

GRANT SELECT, INSERT, UPDATE ON chain_aliases TO farming_user;
GRANT SELECT, INSERT, UPDATE ON discovery_failures TO farming_user;
GRANT USAGE ON SEQUENCE chain_aliases_id_seq TO farming_user;
GRANT USAGE ON SEQUENCE discovery_failures_id_seq TO farming_user;

-- ============================================================================
-- SECTION 6: VERIFICATION
-- ============================================================================

-- Verify aliases were created
DO $$
DECLARE
    alias_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO alias_count FROM chain_aliases;
    
    RAISE NOTICE 'Chain aliases created: %', alias_count;
    
    IF alias_count < 10 THEN
        RAISE WARNING 'Expected at least 10 aliases, got %', alias_count;
    END IF;
END $$;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================

-- Summary:
-- ✅ Created chain_aliases table for name normalization
-- ✅ Created discovery_failures table for logging failed discoveries
-- ✅ Added is_auto_discovered column to chain_rpc_endpoints
-- ✅ Seeded known aliases for existing chains
-- ✅ Added indexes for fast lookup
-- ✅ Granted permissions to farming_user

-- Next steps:
-- 1. Implement ChainDiscoveryService in infrastructure/chain_discovery.py
-- 2. Integrate with BridgeManager._get_chain_id()
-- 3. Add weekly job to sync chains from CEX networks