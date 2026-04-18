-- ============================================================================
-- Migration 043: Remove Hardcode - System Config and Chain Config
-- ============================================================================
-- Date: 2026-03-21
-- Author: Backend Developer
-- Description: 
--   1. Add missing fields to chain_rpc_endpoints (native_token, block_time, is_poa)
--   2. Create system_config table for system-wide settings
--   3. Populate system_config with hardcoded values from code
-- Purpose: Eliminate hardcoded values and make system configurable via database
-- ============================================================================

-- ============================================================================
-- STEP 1: Add missing fields to chain_rpc_endpoints
-- ============================================================================

ALTER TABLE chain_rpc_endpoints
ADD COLUMN IF NOT EXISTS native_token VARCHAR(20) DEFAULT 'ETH',
ADD COLUMN IF NOT EXISTS block_time NUMERIC(4,2) DEFAULT 2.0,
ADD COLUMN IF NOT EXISTS is_poa BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN chain_rpc_endpoints.native_token IS 'Native token symbol (ETH, MATIC, BNB, etc.)';
COMMENT ON COLUMN chain_rpc_endpoints.block_time IS 'Average block time in seconds';
COMMENT ON COLUMN chain_rpc_endpoints.is_poa IS 'Whether chain uses Proof of Authority (requires PoA middleware)';

-- ============================================================================
-- STEP 2: Update chain_rpc_endpoints with chain-specific data
-- ============================================================================

UPDATE chain_rpc_endpoints SET 
    native_token = 'ETH',
    block_time = 0.25,
    is_poa = FALSE
WHERE chain = 'arbitrum';

UPDATE chain_rpc_endpoints SET 
    native_token = 'ETH',
    block_time = 2.0,
    is_poa = FALSE
WHERE chain = 'base';

UPDATE chain_rpc_endpoints SET 
    native_token = 'ETH',
    block_time = 2.0,
    is_poa = FALSE
WHERE chain = 'optimism';

UPDATE chain_rpc_endpoints SET 
    native_token = 'MATIC',
    block_time = 2.0,
    is_poa = TRUE
WHERE chain = 'polygon';

UPDATE chain_rpc_endpoints SET 
    native_token = 'BNB',
    block_time = 3.0,
    is_poa = TRUE
WHERE chain = 'bsc';

UPDATE chain_rpc_endpoints SET 
    native_token = 'ETH',
    block_time = 2.0,
    is_poa = FALSE
WHERE chain = 'ink';

UPDATE chain_rpc_endpoints SET 
    native_token = 'ETH',
    block_time = 0.1,
    is_poa = FALSE
WHERE chain = 'megaeth';

-- ============================================================================
-- STEP 3: Create system_config table
-- ============================================================================

CREATE TABLE IF NOT EXISTS system_config (
    key VARCHAR(100) PRIMARY KEY,
    value TEXT NOT NULL,
    value_type VARCHAR(20) NOT NULL DEFAULT 'string',
    description TEXT,
    category VARCHAR(50),
    is_sensitive BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE system_config IS 'System-wide configuration settings. Replaces hardcoded values in code.';
COMMENT ON COLUMN system_config.key IS 'Configuration key (e.g., "decodo_ttl_minutes")';
COMMENT ON COLUMN system_config.value IS 'Configuration value (stored as TEXT, parsed by type)';
COMMENT ON COLUMN system_config.value_type IS 'Value type: string, integer, float, boolean, json';
COMMENT ON COLUMN system_config.description IS 'Human-readable description of the setting';
COMMENT ON COLUMN system_config.category IS 'Category for grouping (e.g., "proxy", "gas", "validation")';
COMMENT ON COLUMN system_config.is_sensitive IS 'Whether value contains sensitive data (passwords, keys)';
COMMENT ON COLUMN system_config.updated_at IS 'Last update timestamp';

-- ============================================================================
-- STEP 4: Populate system_config with hardcoded values
-- ============================================================================

-- Proxy validation settings
INSERT INTO system_config (key, value, value_type, description, category) VALUES
    ('proxy_validation_timeout', '10', 'integer', 'Seconds to wait for proxy response during validation', 'proxy'),
    ('proxy_validation_test_url', 'https://ipinfo.io/json', 'string', 'URL used for proxy validation', 'proxy'),
    ('proxy_validation_cache_ttl_hours', '1', 'integer', 'Hours before re-validating proxy', 'proxy')
ON CONFLICT (key) DO NOTHING;

-- Decodo proxy TTL settings
INSERT INTO system_config (key, value, value_type, description, category) VALUES
    ('decodo_ttl_minutes', '60', 'integer', 'Decodo proxy session TTL in minutes', 'proxy'),
    ('decodo_ttl_buffer_minutes', '10', 'integer', 'Buffer minutes before TTL expires (wait if less than this)', 'proxy')
ON CONFLICT (key) DO NOTHING;

-- Server IPs for IP leak detection
INSERT INTO system_config (key, value, value_type, description, category) VALUES
    ('server_ips', '["82.40.60.131", "82.40.60.132", "82.22.53.183", "82.22.53.184"]', 'json', 'Server IPs that must NEVER be exposed (IP leak detection)', 'security')
ON CONFLICT (key) DO NOTHING;

-- Gas estimation settings
INSERT INTO system_config (key, value, value_type, description, category) VALUES
    ('gas_safety_multiplier', '1.2', 'float', 'Safety multiplier for gas estimation (default 1.2 = +20%)', 'gas'),
    ('gas_noise_stddev', '0.025', 'float', 'Standard deviation for Gaussian noise in gas randomization (anti-Sybil)', 'gas'),
    ('gas_price_randomization_stddev', '0.025', 'float', 'Standard deviation for gas price randomization (±2.5%)', 'gas')
ON CONFLICT (key) DO NOTHING;

-- Gas heuristics for dry-run mode
INSERT INTO system_config (key, value, value_type, description, category) VALUES
    ('gas_heuristic_swap', '150000', 'integer', 'Gas units for SWAP transactions (dry-run heuristic)', 'gas'),
    ('gas_heuristic_bridge', '200000', 'integer', 'Gas units for BRIDGE transactions (dry-run heuristic)', 'gas'),
    ('gas_heuristic_stake', '100000', 'integer', 'Gas units for STAKE transactions (dry-run heuristic)', 'gas'),
    ('gas_heuristic_unstake', '120000', 'integer', 'Gas units for UNSTAKE transactions (dry-run heuristic)', 'gas'),
    ('gas_heuristic_lp_add', '180000', 'integer', 'Gas units for LP_ADD transactions (dry-run heuristic)', 'gas'),
    ('gas_heuristic_lp_remove', '150000', 'integer', 'Gas units for LP_REMOVE transactions (dry-run heuristic)', 'gas'),
    ('gas_heuristic_nft_mint', '120000', 'integer', 'Gas units for NFT_MINT transactions (dry-run heuristic)', 'gas'),
    ('gas_heuristic_wrap', '50000', 'integer', 'Gas units for WRAP transactions (dry-run heuristic)', 'gas'),
    ('gas_heuristic_unwrap', '50000', 'integer', 'Gas units for UNWRAP transactions (dry-run heuristic)', 'gas'),
    ('gas_heuristic_approve', '50000', 'integer', 'Gas units for APPROVE transactions (dry-run heuristic)', 'gas'),
    ('gas_heuristic_transfer', '21000', 'integer', 'Gas units for TRANSFER transactions (dry-run heuristic)', 'gas'),
    ('gas_heuristic_eth_transfer', '21000', 'integer', 'Gas units for ETH_TRANSFER transactions (dry-run heuristic)', 'gas'),
    ('gas_heuristic_token_transfer', '65000', 'integer', 'Gas units for TOKEN_TRANSFER transactions (dry-run heuristic)', 'gas')
ON CONFLICT (key) DO NOTHING;

-- Gas price estimates per chain (gwei)
INSERT INTO system_config (key, value, value_type, description, category) VALUES
    ('gas_price_estimate_ethereum', '30.0', 'float', 'Gas price estimate for Ethereum (gwei)', 'gas'),
    ('gas_price_estimate_arbitrum', '0.1', 'float', 'Gas price estimate for Arbitrum (gwei)', 'gas'),
    ('gas_price_estimate_base', '0.05', 'float', 'Gas price estimate for Base (gwei)', 'gas'),
    ('gas_price_estimate_optimism', '0.1', 'float', 'Gas price estimate for Optimism (gwei)', 'gas'),
    ('gas_price_estimate_polygon', '50.0', 'float', 'Gas price estimate for Polygon (gwei)', 'gas'),
    ('gas_price_estimate_bsc', '3.0', 'float', 'Gas price estimate for BSC (gwei)', 'gas'),
    ('gas_price_estimate_ink', '0.1', 'float', 'Gas price estimate for Ink (gwei)', 'gas'),
    ('gas_price_estimate_sepolia', '1.0', 'float', 'Gas price estimate for Sepolia testnet (gwei)', 'gas'),
    ('gas_price_estimate_dry_run', '1.0', 'float', 'Gas price estimate for dry-run mode (gwei)', 'gas')
ON CONFLICT (key) DO NOTHING;

-- ============================================================================
-- STEP 5: Create index for quick lookups
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_system_config_category 
ON system_config(category);

CREATE INDEX IF NOT EXISTS idx_system_config_updated_at 
ON system_config(updated_at DESC);

-- ============================================================================
-- STEP 6: Verification
-- ============================================================================

DO $$
DECLARE
    chain_count INTEGER;
    config_count INTEGER;
BEGIN
    SELECT COUNT(DISTINCT chain) INTO chain_count FROM chain_rpc_endpoints;
    SELECT COUNT(*) INTO config_count FROM system_config;
    
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Migration 043 Applied Successfully';
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Chains configured: %', chain_count;
    RAISE NOTICE 'System config entries: %', config_count;
    RAISE NOTICE '';
    RAISE NOTICE 'Hardcoded values moved to database.';
    RAISE NOTICE '==============================================';
END $$;

-- ============================================================================
-- STEP 7: Show sample data
-- ============================================================================

SELECT 
    chain,
    chain_id,
    native_token,
    block_time,
    is_poa
FROM chain_rpc_endpoints
GROUP BY chain, chain_id, native_token, block_time, is_poa
ORDER BY chain
LIMIT 5;

SELECT 
    category,
    key,
    value,
    value_type
FROM system_config
ORDER BY category, key
LIMIT 10;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
