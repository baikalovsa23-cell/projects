-- ============================================================================
-- P0 FIXES: protocols + protocol_actions + wallet_transactions
-- Date: 2026-03-25
-- ============================================================================

-- P0-8: Create wallet_transactions table (missing from live DB)
CREATE TABLE IF NOT EXISTS wallet_transactions (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER REFERENCES wallets(id) ON DELETE CASCADE,
    protocol_action_id INTEGER REFERENCES protocol_actions(id) ON DELETE SET NULL,
    tx_hash VARCHAR(66) NOT NULL,
    chain VARCHAR(50) NOT NULL,
    from_address VARCHAR(42) NOT NULL,
    to_address VARCHAR(42),
    value NUMERIC,
    gas_used NUMERIC,
    status VARCHAR(20) NOT NULL,
    block_number INTEGER,
    confirmed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallet_transactions_wallet_id ON wallet_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_tx_hash ON wallet_transactions(tx_hash);

COMMENT ON TABLE wallet_transactions IS 'History of executed on-chain transactions';

-- ============================================================================
-- P0-7: Insert protocols (DeFi protocols for farming)
-- ============================================================================

INSERT INTO protocols (name, category, chains, has_points_program, priority_score, is_active) VALUES
-- DEX
('Uniswap', 'DEX', ARRAY['arbitrum', 'base', 'optimism', 'polygon', 'bsc', 'zksync', 'unichain'], TRUE, 95, TRUE),
('SushiSwap', 'DEX', ARRAY['arbitrum', 'base', 'optimism', 'polygon', 'bsc'], TRUE, 80, TRUE),
('PancakeSwap', 'DEX', ARRAY['bsc', 'arbitrum', 'base', 'optimism', 'polygon'], TRUE, 85, TRUE),
('1inch', 'DEX', ARRAY['arbitrum', 'base', 'optimism', 'polygon', 'bsc', 'zksync'], FALSE, 75, TRUE),
('Curve', 'DEX', ARRAY['arbitrum', 'base', 'optimism', 'polygon'], TRUE, 90, TRUE),
('Balancer', 'DEX', ARRAY['arbitrum', 'base', 'optimism', 'polygon'], TRUE, 80, TRUE),
('Jupiter', 'DEX', ARRAY['arbitrum', 'base', 'optimism'], TRUE, 85, TRUE),

-- Lending
('Aave', 'Lending', ARRAY['arbitrum', 'base', 'optimism', 'polygon', 'scroll'], TRUE, 95, TRUE),
('Compound', 'Lending', ARRAY['arbitrum', 'base', 'optimism', 'polygon'], TRUE, 85, TRUE),
('Lido', 'Staking', ARRAY['arbitrum', 'base', 'optimism', 'polygon'], TRUE, 90, TRUE),
('RocketPool', 'Staking', ARRAY['arbitrum', 'base', 'optimism'], TRUE, 80, TRUE),

-- Bridge
('Stargate', 'Bridge', ARRAY['arbitrum', 'base', 'optimism', 'polygon', 'bsc', 'zksync'], TRUE, 85, TRUE),
('LayerZero', 'Bridge', ARRAY['arbitrum', 'base', 'optimism', 'polygon', 'bsc'], TRUE, 90, TRUE),
('Hop', 'Bridge', ARRAY['arbitrum', 'base', 'optimism', 'polygon'], FALSE, 70, TRUE),

-- NFT
('OpenSea', 'NFT Marketplace', ARRAY['arbitrum', 'base', 'optimism', 'polygon'], FALSE, 60, TRUE),
('Blur', 'NFT Marketplace', ARRAY['arbitrum', 'base', 'optimism', 'polygon'], TRUE, 75, TRUE),

-- Governance
('Snapshot', 'Governance', ARRAY['arbitrum', 'base', 'optimism', 'polygon'], FALSE, 70, TRUE),
('ENS', 'Governance', ARRAY['arbitrum', 'base', 'optimism', 'polygon'], TRUE, 80, TRUE),

-- New L2s with points
('Manta', 'DEX', ARRAY['manta'], TRUE, 90, TRUE),
('Mantle', 'DEX', ARRAY['mantle'], TRUE, 85, TRUE),
('Linea', 'DEX', ARRAY['linea'], TRUE, 85, TRUE),
('Scroll', 'DEX', ARRAY['scroll'], TRUE, 85, TRUE),
('Morph', 'DEX', ARRAY['morph'], TRUE, 80, TRUE),
('zkSync', 'DEX', ARRAY['zksync'], TRUE, 90, TRUE),
('Unichain', 'DEX', ARRAY['unichain'], TRUE, 95, TRUE)

ON CONFLICT (name) DO UPDATE SET
    chains = EXCLUDED.chains,
    priority_score = EXCLUDED.priority_score,
    is_active = EXCLUDED.is_active;

-- ============================================================================
-- P0-7: Insert protocol_actions (specific actions for each protocol)
-- ============================================================================

-- Uniswap actions (multi-chain)
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'swap_eth_for_tokens', 'SWAP', 'web3py', chain, 10.0, 500.0, 150, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'Uniswap'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'add_liquidity_eth', 'LP', 'web3py', chain, 50.0, 1000.0, 250, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'Uniswap'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'wrap_eth', 'WRAP', 'web3py', chain, 10.0, 500.0, 50, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'Uniswap'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- Aave actions
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'deposit_eth', 'STAKE', 'web3py', chain, 50.0, 2000.0, 200, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'Aave'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'withdraw_eth', 'STAKE', 'web3py', chain, 50.0, 2000.0, 200, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'Aave'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- Lido actions
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'stake_eth', 'STAKE', 'web3py', chain, 100.0, 5000.0, 150, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'Lido'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- Stargate bridge actions
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'bridge_eth', 'BRIDGE', 'web3py', chain, 50.0, 1000.0, 300, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'Stargate'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- Curve actions
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'add_liquidity', 'LP', 'web3py', chain, 100.0, 2000.0, 350, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'Curve'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'swap_stablecoins', 'SWAP', 'web3py', chain, 50.0, 500.0, 150, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'Curve'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- PancakeSwap actions
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'swap_eth_for_tokens', 'SWAP', 'web3py', chain, 10.0, 500.0, 100, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'PancakeSwap'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'add_liquidity_eth', 'LP', 'web3py', chain, 50.0, 1000.0, 200, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'PancakeSwap'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- 1inch actions
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'aggregate_swap', 'SWAP', 'web3py', chain, 20.0, 1000.0, 180, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = '1inch'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- Compound actions
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'supply_eth', 'STAKE', 'web3py', chain, 50.0, 2000.0, 200, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'Compound'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- SushiSwap actions
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'swap_eth_for_tokens', 'SWAP', 'web3py', chain, 10.0, 500.0, 150, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'SushiSwap'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'add_liquidity_eth', 'LP', 'web3py', chain, 50.0, 1000.0, 250, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'SushiSwap'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- OpenSea actions (NFT) - via OpenClaw for Tier A
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'mint_nft', 'NFT_MINT', 'openclaw', chain, 10.0, 200.0, 100, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'OpenSea'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- Snapshot voting (OpenClaw only for Tier A)
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'vote_on_proposal', 'SNAPSHOT_VOTE', 'openclaw', chain, 0.0, 0.0, 0, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'Snapshot'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- ENS registration (OpenClaw)
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'register_ens', 'ENS_REGISTER', 'openclaw', chain, 5.0, 50.0, 0, TRUE
FROM protocols p, unnest(p.chains) AS chain
WHERE p.name = 'ENS'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- Manta specific
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'swap_eth_for_tokens', 'SWAP', 'web3py', 'manta', 10.0, 500.0, 100, TRUE
FROM protocols p WHERE p.name = 'Manta'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'add_liquidity_eth', 'LP', 'web3py', 'manta', 50.0, 1000.0, 200, TRUE
FROM protocols p WHERE p.name = 'Manta'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- Mantle specific
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'swap_eth_for_tokens', 'SWAP', 'web3py', 'mantle', 10.0, 500.0, 50, TRUE
FROM protocols p WHERE p.name = 'Mantle'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'stake_mantle', 'STAKE', 'web3py', 'mantle', 50.0, 1000.0, 100, TRUE
FROM protocols p WHERE p.name = 'Mantle'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- Linea specific
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'swap_eth_for_tokens', 'SWAP', 'web3py', 'linea', 10.0, 500.0, 100, TRUE
FROM protocols p WHERE p.name = 'Linea'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'add_liquidity_eth', 'LP', 'web3py', 'linea', 50.0, 1000.0, 200, TRUE
FROM protocols p WHERE p.name = 'Linea'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- Scroll specific
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'swap_eth_for_tokens', 'SWAP', 'web3py', 'scroll', 10.0, 500.0, 100, TRUE
FROM protocols p WHERE p.name = 'Scroll'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'bridge_eth', 'BRIDGE', 'web3py', 'scroll', 50.0, 1000.0, 200, TRUE
FROM protocols p WHERE p.name = 'Scroll'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- zkSync specific
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'swap_eth_for_tokens', 'SWAP', 'web3py', 'zksync', 10.0, 500.0, 50, TRUE
FROM protocols p WHERE p.name = 'zkSync'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'add_liquidity_eth', 'LP', 'web3py', 'zksync', 50.0, 1000.0, 150, TRUE
FROM protocols p WHERE p.name = 'zkSync'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- Unichain specific
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'swap_eth_for_tokens', 'SWAP', 'web3py', 'unichain', 10.0, 500.0, 50, TRUE
FROM protocols p WHERE p.name = 'Unichain'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'add_liquidity_eth', 'LP', 'web3py', 'unichain', 50.0, 1000.0, 150, TRUE
FROM protocols p WHERE p.name = 'Unichain'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- Morph specific
INSERT INTO protocol_actions (protocol_id, action_name, tx_type, layer, chain, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, is_enabled)
SELECT p.id, 'swap_eth_for_tokens', 'SWAP', 'web3py', 'morph', 10.0, 500.0, 100, TRUE
FROM protocols p WHERE p.name = 'Morph'
ON CONFLICT (protocol_id, action_name, chain) DO NOTHING;

-- ============================================================================
-- VERIFICATION QUERIES (run after migration)
-- ============================================================================

-- SELECT COUNT(*) as protocols_count FROM protocols;
-- SELECT COUNT(*) as actions_count FROM protocol_actions;
-- SELECT name, COUNT(*) as actions FROM protocols p JOIN protocol_actions pa ON p.id = pa.protocol_id GROUP BY name ORDER BY actions DESC;
