-- ============================================================================
-- Seed Chain RPC Endpoints — 11 L2 Networks + 2 Withdrawal-Only Networks
-- ============================================================================
-- Adds public RPC endpoints for L2 networks used in airdrop_v4
-- All endpoints are free public RPC nodes (no API keys required)
--
-- Farming Networks (11 L2, withdrawal_only = false):
--   - Arbitrum One (chain_id: 42161)
--   - Arbitrum Nova (chain_id: 42170)
--   - Base (chain_id: 8453)
--   - Optimism (chain_id: 10)
--   - zkSync Era (chain_id: 324)
--   - Linea (chain_id: 59144)
--   - Scroll (chain_id: 534352)
--   - Unichain (chain_id: 130)
--   - Manta (chain_id: 169)
--   - Mantle (chain_id: 5000)
--   - Morph (chain_id: 2818)
--
-- Withdrawal-Only Networks (2 sidechains, withdrawal_only = true):
--   - BSC (chain_id: 56) — BNB Chain, for CEX withdrawals only
--   - Polygon (chain_id: 137) — for CEX withdrawals only
--
-- CRITICAL: withdrawal_only = true networks are NOT used for farming!
-- They exist solely for receiving funds from CEX, then bridging to L2.
--
-- Missing (require manual addition via db_manager):
--   - Ink (chain_id TBD, no public RPC yet)
--   - MegaETH (chain_id TBD, no public RPC yet)
--
-- ============================================================================

BEGIN;

-- Clear existing endpoints (if any)
DELETE FROM chain_rpc_endpoints;

-- ============================================================================
-- Layer 2 Networks (11 total, withdrawal_only = false)
-- ============================================================================

-- Arbitrum One (chain_id: 42161)
INSERT INTO chain_rpc_endpoints (chain, chain_id, url, priority, is_active, is_l2, network_type, withdrawal_only, gas_multiplier)
VALUES ('arbitrum', 42161, 'https://arb1.arbitrum.io/rpc', 1, true, true, 'l2', false, 1.0);

-- Arbitrum Nova (chain_id: 42170)
-- A separate L2 from Arbitrum One, lower fees but lower security
INSERT INTO chain_rpc_endpoints (chain, chain_id, url, priority, is_active, is_l2, network_type, withdrawal_only, gas_multiplier)
VALUES ('arbitrum_nova', 42170, 'https://nova.arbitrum.io/rpc', 1, true, true, 'l2', false, 1.0);

-- Base (chain_id: 8453)
INSERT INTO chain_rpc_endpoints (chain, chain_id, url, priority, is_active, is_l2, network_type, withdrawal_only, gas_multiplier)
VALUES ('base', 8453, 'https://mainnet.base.org', 1, true, true, 'l2', false, 1.0);

-- Optimism (chain_id: 10)
INSERT INTO chain_rpc_endpoints (chain, chain_id, url, priority, is_active, is_l2, network_type, withdrawal_only, gas_multiplier)
VALUES ('optimism', 10, 'https://mainnet.optimism.io', 1, true, true, 'l2', false, 1.0);

-- zkSync Era (chain_id: 324)
-- NOTE: zkSync Lite is NOT EVM compatible, use zkSync Era instead
INSERT INTO chain_rpc_endpoints (chain, chain_id, url, priority, is_active, is_l2, network_type, withdrawal_only, gas_multiplier)
VALUES ('zksync', 324, 'https://mainnet.era.zksync.io', 1, true, true, 'l2', false, 1.0);

-- Linea (chain_id: 59144)
INSERT INTO chain_rpc_endpoints (chain, chain_id, url, priority, is_active, is_l2, network_type, withdrawal_only, gas_multiplier)
VALUES ('linea', 59144, 'https://rpc.linea.build', 1, true, true, 'l2', false, 1.0);

-- Scroll (chain_id: 534352)
INSERT INTO chain_rpc_endpoints (chain, chain_id, url, priority, is_active, is_l2, network_type, withdrawal_only, gas_multiplier)
VALUES ('scroll', 534352, 'https://rpc.scroll.io', 1, true, true, 'l2', false, 1.0);

-- Unichain (chain_id: 130)
INSERT INTO chain_rpc_endpoints (chain, chain_id, url, priority, is_active, is_l2, network_type, withdrawal_only, gas_multiplier)
VALUES ('unichain', 130, 'https://mainnet.unichain.org', 1, true, true, 'l2', false, 1.0);

-- Manta (chain_id: 169)
-- Manta Pacific - L2 with low fees
INSERT INTO chain_rpc_endpoints (chain, chain_id, url, priority, is_active, is_l2, network_type, withdrawal_only, gas_multiplier)
VALUES ('manta', 169, 'https://pacific-rpc.manta.network/http', 1, true, true, 'l2', false, 1.0);

-- Mantle (chain_id: 5000)
-- Mantle Network - L2 with modular architecture
INSERT INTO chain_rpc_endpoints (chain, chain_id, url, priority, is_active, is_l2, network_type, withdrawal_only, gas_multiplier)
VALUES ('mantle', 5000, 'https://rpc.mantle.xyz', 1, true, true, 'l2', false, 1.0);

-- Morph (chain_id: 2818)
-- Morph L2 - emerging L2 network
INSERT INTO chain_rpc_endpoints (chain, chain_id, url, priority, is_active, is_l2, network_type, withdrawal_only, gas_multiplier)
VALUES ('morph', 2818, 'https://rpc-quicknode.morphl2.io', 1, true, true, 'l2', false, 1.0);

-- ============================================================================
-- Withdrawal-Only Networks (2 total, withdrawal_only = true)
-- These are for CEX withdrawals ONLY, NOT for farming!
-- ============================================================================

-- BSC — BNB Chain (chain_id: 56)
-- Used for: CEX withdrawals → bridge to L2
-- NOT used for: farming, activity execution
INSERT INTO chain_rpc_endpoints (chain, chain_id, url, priority, is_active, is_l2, network_type, withdrawal_only, gas_multiplier)
VALUES ('bsc', 56, 'https://bsc-dataseed.binance.org', 1, true, false, 'sidechain', true, 1.0);

-- Polygon (chain_id: 137)
-- Used for: CEX withdrawals → bridge to L2
-- NOT used for: farming, activity execution
INSERT INTO chain_rpc_endpoints (chain, chain_id, url, priority, is_active, is_l2, network_type, withdrawal_only, gas_multiplier)
VALUES ('polygon', 137, 'https://polygon-rpc.com', 1, true, false, 'sidechain', true, 1.0);

COMMIT;

-- ============================================================================
-- Verification: Show all configured RPC endpoints
-- ============================================================================
SELECT 
    id,
    chain,
    chain_id,
    url,
    priority,
    is_active,
    is_l2,
    network_type,
    withdrawal_only,
    created_at
FROM chain_rpc_endpoints
ORDER BY withdrawal_only, chain;

-- Summary
SELECT 
    COUNT(*) as total_endpoints,
    SUM(CASE WHEN is_active THEN 1 ELSE 0 END) as active_endpoints,
    SUM(CASE WHEN is_l2 THEN 1 ELSE 0 END) as l2_networks,
    SUM(CASE WHEN withdrawal_only THEN 1 ELSE 0 END) as withdrawal_only_networks,
    SUM(CASE WHEN NOT withdrawal_only THEN 1 ELSE 0 END) as farming_networks
FROM chain_rpc_endpoints;

-- ============================================================================
-- Notes:
-- ============================================================================
-- ✅ 11 L2 networks for farming (withdrawal_only = false)
-- ✅ 2 sidechain networks for CEX withdrawals only (withdrawal_only = true)
-- ⚠️  Ink and MegaETH are NOT included (no public RPC endpoints available)
-- ⚠️  These networks need to be added manually via db_manager.insert_chain_rpc()
--     when RPC endpoints become available
--
-- CRITICAL: When selecting chains for farming activity, ALWAYS filter:
--   WHERE withdrawal_only = false
--
-- To add a new L2 network:
--   db.insert_chain_rpc(
--       chain='Ink',
--       chain_id=<TBD>,
--       url='https://rpc.ink.xyz',
--       priority=1,
--       is_l2=True,
--       network_type='l2',
--       withdrawal_only=False
--   )
--
-- ============================================================================
