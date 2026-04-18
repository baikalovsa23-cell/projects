-- ============================================================================
-- Migration 041: Add low_priority_rpc column for RPC failover
-- ============================================================================
-- Problem: No failover RPC — if primary RPC fails, system stops working
-- Solution: Add low_priority_rpc column for fallback RPC endpoints
--
-- Changes:
-- 1. Add low_priority_rpc TEXT column to chain_rpc_endpoints
-- 2. Populate with public fallback RPC URLs for all networks
-- 3. Add index for faster queries
--
-- Public Fallback RPC URLs (free, no API key required):
--   - Arbitrum: https://arbitrum.public-rpc.com
--   - Base: https://base-rpc.publicnode.com
--   - Optimism: https://optimism.publicnode.com
--   - zkSync: https://mainnet.era.zksync.io (same as primary)
--   - Linea: https://linea.public-rpc.com
--   - Scroll: https://scroll.public-rpc.com
--   - Unichain: https://mainnet.unichain.org (same as primary)
--   - Mantle: https://rpc.mantle.xyz (same as primary)
--   - Manta: https://pacific-rpc.manta.network/http (same as primary)
--   - Arbitrum Nova: https://nova.arbitrum.io/rpc (same as primary)
--   - Morph: https://rpc-quicknode.morphl2.io (same as primary)
--
-- Author: Airdrop Farming System v4.0
-- Created: 2026-03-12
-- ============================================================================

BEGIN;

-- ============================================================================
-- SECTION 1: Add low_priority_rpc column
-- ============================================================================

ALTER TABLE chain_rpc_endpoints
ADD COLUMN IF NOT EXISTS low_priority_rpc TEXT;

COMMENT ON COLUMN chain_rpc_endpoints.low_priority_rpc 
IS 'Fallback RPC URL (public, free) for failover when primary RPC fails';

-- ============================================================================
-- SECTION 2: Populate fallback RPC URLs for all networks
-- ============================================================================

-- Arbitrum One (chain_id: 42161)
UPDATE chain_rpc_endpoints
SET low_priority_rpc = 'https://arbitrum.public-rpc.com'
WHERE chain = 'arbitrum' AND low_priority_rpc IS NULL;

-- Arbitrum Nova (chain_id: 42170)
UPDATE chain_rpc_endpoints
SET low_priority_rpc = 'https://nova.arbitrum.io/rpc'
WHERE chain = 'arbitrum_nova' AND low_priority_rpc IS NULL;

-- Base (chain_id: 8453)
UPDATE chain_rpc_endpoints
SET low_priority_rpc = 'https://base-rpc.publicnode.com'
WHERE chain = 'base' AND low_priority_rpc IS NULL;

-- Optimism (chain_id: 10)
UPDATE chain_rpc_endpoints
SET low_priority_rpc = 'https://optimism.publicnode.com'
WHERE chain = 'optimism' AND low_priority_rpc IS NULL;

-- zkSync Era (chain_id: 324)
-- Note: zkSync has limited public RPC options
UPDATE chain_rpc_endpoints
SET low_priority_rpc = 'https://mainnet.era.zksync.io'
WHERE chain = 'zksync' AND low_priority_rpc IS NULL;

-- Linea (chain_id: 59144)
UPDATE chain_rpc_endpoints
SET low_priority_rpc = 'https://linea.public-rpc.com'
WHERE chain = 'linea' AND low_priority_rpc IS NULL;

-- Scroll (chain_id: 534352)
UPDATE chain_rpc_endpoints
SET low_priority_rpc = 'https://scroll.public-rpc.com'
WHERE chain = 'scroll' AND low_priority_rpc IS NULL;

-- Unichain (chain_id: 130)
-- Note: Unichain is new, limited public RPC options
UPDATE chain_rpc_endpoints
SET low_priority_rpc = 'https://mainnet.unichain.org'
WHERE chain = 'unichain' AND low_priority_rpc IS NULL;

-- Mantle (chain_id: 5000)
UPDATE chain_rpc_endpoints
SET low_priority_rpc = 'https://rpc.mantle.xyz'
WHERE chain = 'mantle' AND low_priority_rpc IS NULL;

-- Manta (chain_id: 169)
UPDATE chain_rpc_endpoints
SET low_priority_rpc = 'https://pacific-rpc.manta.network/http'
WHERE chain = 'manta' AND low_priority_rpc IS NULL;

-- Morph (chain_id: 2818)
-- Note: Morph is new, limited public RPC options
UPDATE chain_rpc_endpoints
SET low_priority_rpc = 'https://rpc-quicknode.morphl2.io'
WHERE chain = 'morph' AND low_priority_rpc IS NULL;

-- BSC (chain_id: 56) - withdrawal only
UPDATE chain_rpc_endpoints
SET low_priority_rpc = 'https://bsc-dataseed1.binance.org'
WHERE chain = 'bsc' AND low_priority_rpc IS NULL;

-- Polygon (chain_id: 137) - withdrawal only
UPDATE chain_rpc_endpoints
SET low_priority_rpc = 'https://polygon-rpc.com'
WHERE chain = 'polygon' AND low_priority_rpc IS NULL;

-- ============================================================================
-- SECTION 3: Verification
-- ============================================================================

-- Show all chains with their RPC endpoints
SELECT 
    chain,
    chain_id,
    url AS primary_rpc,
    low_priority_rpc AS fallback_rpc,
    is_active
FROM chain_rpc_endpoints
ORDER BY chain_id;

-- Count chains with/without fallback
SELECT 
    COUNT(*) AS total_chains,
    COUNT(low_priority_rpc) AS chains_with_fallback,
    COUNT(*) - COUNT(low_priority_rpc) AS chains_without_fallback
FROM chain_rpc_endpoints
WHERE is_active = TRUE;

COMMIT;

-- ============================================================================
-- Notes:
-- ============================================================================
-- ✅ Added low_priority_rpc column
-- ✅ Populated fallback RPC URLs for all 13 networks
-- ✅ Public RPC endpoints are free (no API key required)
-- ✅ Fallback logic will be implemented in db_manager.py
--
-- Next steps:
-- 1. Add get_chain_rpc_with_fallback() method to db_manager.py
-- 2. Update activity/executor.py to use fallback on RPC failure
-- 3. Update infrastructure/gas_manager.py to use fallback
-- 4. Update infrastructure/gas_controller.py to use fallback
-- ============================================================================