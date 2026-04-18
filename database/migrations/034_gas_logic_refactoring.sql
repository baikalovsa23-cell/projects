-- ============================================================================
-- Migration 034: Gas Logic Refactoring
-- ============================================================================
-- Purpose: Remove hardcoded gas thresholds, add dynamic gas logic
-- Author: System Architect
-- Date: 2026-03-08
-- ============================================================================

-- ============================================================================
-- SECTION 1: EXTEND chain_rpc_endpoints
-- ============================================================================

-- Add columns for network type classification
ALTER TABLE chain_rpc_endpoints 
ADD COLUMN IF NOT EXISTS chain_id INTEGER,
ADD COLUMN IF NOT EXISTS is_l2 BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS l1_data_fee BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS network_type VARCHAR(20) DEFAULT 'sidechain',
ADD COLUMN IF NOT EXISTS gas_multiplier DECIMAL(3, 1) DEFAULT 2.0;

COMMENT ON COLUMN chain_rpc_endpoints.chain_id IS 'Unique chain identifier (1=Ethereum, 42161=Arbitrum, etc.)';
COMMENT ON COLUMN chain_rpc_endpoints.is_l2 IS 'TRUE for L2 networks (Optimistic Rollups, ZK Rollups)';
COMMENT ON COLUMN chain_rpc_endpoints.l1_data_fee IS 'TRUE if network requires L1 gas for data posting';
COMMENT ON COLUMN chain_rpc_endpoints.network_type IS 'Network classification: l1, l2, sidechain';
COMMENT ON COLUMN chain_rpc_endpoints.gas_multiplier IS 'Dynamic threshold multiplier (L1=1.5, L2=5.0, Sidechain=2.0)';

-- ============================================================================
-- SECTION 2: POPULATE EXISTING CHAINS
-- ============================================================================

-- Ethereum Mainnet (L1)
UPDATE chain_rpc_endpoints SET 
    chain_id = 1, 
    is_l2 = FALSE,
    l1_data_fee = FALSE,
    network_type = 'l1',
    gas_multiplier = 1.5
WHERE chain = 'ethereum' OR chain = 'Ethereum';

-- Arbitrum (L2 - Optimistic Rollup)
UPDATE chain_rpc_endpoints SET 
    chain_id = 42161, 
    is_l2 = TRUE,
    l1_data_fee = TRUE,
    network_type = 'l2',
    gas_multiplier = 5.0
WHERE chain = 'arbitrum' OR chain = 'Arbitrum' OR chain = 'arbitrum one';

-- Base (L2 - Optimistic Rollup)
UPDATE chain_rpc_endpoints SET 
    chain_id = 8453, 
    is_l2 = TRUE,
    l1_data_fee = TRUE,
    network_type = 'l2',
    gas_multiplier = 5.0
WHERE chain = 'base' OR chain = 'Base';

-- Optimism (L2 - Optimistic Rollup)
UPDATE chain_rpc_endpoints SET 
    chain_id = 10, 
    is_l2 = TRUE,
    l1_data_fee = TRUE,
    network_type = 'l2',
    gas_multiplier = 5.0
WHERE chain = 'optimism' OR chain = 'Optimism' OR chain = 'op' OR chain = 'OP Mainnet';

-- Polygon (Sidechain)
UPDATE chain_rpc_endpoints SET 
    chain_id = 137, 
    is_l2 = FALSE,
    l1_data_fee = FALSE,
    network_type = 'sidechain',
    gas_multiplier = 2.0
WHERE chain = 'polygon' OR chain = 'Polygon' OR chain = 'matic';

-- BNB Chain (Sidechain)
UPDATE chain_rpc_endpoints SET 
    chain_id = 56, 
    is_l2 = FALSE,
    l1_data_fee = FALSE,
    network_type = 'sidechain',
    gas_multiplier = 2.0
WHERE chain = 'bnbchain' OR chain = 'BNB Chain' OR chain = 'bsc' OR chain = 'BSC';

-- Ink (L2 - New network)
UPDATE chain_rpc_endpoints SET 
    chain_id = 57073, 
    is_l2 = TRUE,
    l1_data_fee = TRUE,
    network_type = 'l2',
    gas_multiplier = 5.0
WHERE chain = 'ink' OR chain = 'Ink';

-- MegaETH (L2 - New network, placeholder chain_id)
UPDATE chain_rpc_endpoints SET 
    chain_id = 420420,  -- Placeholder, update when official
    is_l2 = TRUE,
    l1_data_fee = TRUE,
    network_type = 'l2',
    gas_multiplier = 5.0
WHERE chain = 'megaeth' OR chain = 'MegaETH';

-- zkSync Era (L2 - ZK Rollup)
UPDATE chain_rpc_endpoints SET 
    chain_id = 324, 
    is_l2 = TRUE,
    l1_data_fee = TRUE,
    network_type = 'l2',
    gas_multiplier = 5.0
WHERE chain = 'zksync' OR chain = 'zkSync' OR chain = 'zksync era';

-- Scroll (L2 - ZK Rollup)
UPDATE chain_rpc_endpoints SET 
    chain_id = 534352, 
    is_l2 = TRUE,
    l1_data_fee = TRUE,
    network_type = 'l2',
    gas_multiplier = 5.0
WHERE chain = 'scroll' OR chain = 'Scroll';

-- Linea (L2 - ZK Rollup)
UPDATE chain_rpc_endpoints SET 
    chain_id = 59144, 
    is_l2 = TRUE,
    l1_data_fee = TRUE,
    network_type = 'l2',
    gas_multiplier = 5.0
WHERE chain = 'linea' OR chain = 'Linea';

-- Mantle (L2 - Optimistic Rollup)
UPDATE chain_rpc_endpoints SET 
    chain_id = 5000, 
    is_l2 = TRUE,
    l1_data_fee = TRUE,
    network_type = 'l2',
    gas_multiplier = 5.0
WHERE chain = 'mantle' OR chain = 'Mantle';

-- Avalanche (Sidechain - Subnet)
UPDATE chain_rpc_endpoints SET 
    chain_id = 43114, 
    is_l2 = FALSE,
    l1_data_fee = FALSE,
    network_type = 'sidechain',
    gas_multiplier = 2.0
WHERE chain = 'avalanche' OR chain = 'Avalanche' OR chain = 'avax';

-- ============================================================================
-- SECTION 3: CREATE gas_history TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS gas_history (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER NOT NULL,
    gas_price_gwei DECIMAL(10, 4) NOT NULL,
    recorded_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE gas_history IS 'Historical gas prices for dynamic threshold calculation (MA_24h)';
COMMENT ON COLUMN gas_history.chain_id IS 'Chain ID from chain_rpc_endpoints';
COMMENT ON COLUMN gas_history.gas_price_gwei IS 'Gas price in Gwei';

-- Indexes for gas_history
CREATE INDEX IF NOT EXISTS idx_gas_history_chain_time 
ON gas_history(chain_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_gas_history_retention 
ON gas_history(recorded_at);

-- ============================================================================
-- SECTION 4: CREATE UNIQUE INDEX ON chain_id
-- ============================================================================

-- Ensure chain_id is unique per chain (but allow multiple RPC endpoints per chain)
CREATE INDEX IF NOT EXISTS idx_chain_rpc_chain_id 
ON chain_rpc_endpoints(chain_id) 
WHERE chain_id IS NOT NULL;

-- ============================================================================
-- SECTION 5: ADD gas_history_retention FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION cleanup_old_gas_history()
RETURNS void AS $$
BEGIN
    DELETE FROM gas_history 
    WHERE recorded_at < NOW() - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_old_gas_history() IS 'Remove gas history older than 7 days';

-- ============================================================================
-- SECTION 6: ADD COLUMNS TO bridge_history (if exists)
-- ============================================================================

-- Add gas check columns to bridge_history if table exists
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'bridge_history') THEN
        ALTER TABLE bridge_history 
        ADD COLUMN IF NOT EXISTS source_chain_gas_ok BOOLEAN,
        ADD COLUMN IF NOT EXISTS dest_chain_gas_ok BOOLEAN,
        ADD COLUMN IF NOT EXISTS gas_check_at TIMESTAMPTZ;
        
        COMMENT ON COLUMN bridge_history.source_chain_gas_ok IS 'TRUE if source chain gas was below threshold';
        COMMENT ON COLUMN bridge_history.dest_chain_gas_ok IS 'TRUE if destination chain gas was below threshold';
        COMMENT ON COLUMN bridge_history.gas_check_at IS 'Timestamp of gas check before bridge execution';
    END IF;
END $$;

-- ============================================================================
-- SECTION 7: VERIFICATION QUERIES
-- ============================================================================

-- Verify chain_id assignments
DO $$
DECLARE
    total_chains INTEGER;
    chains_with_id INTEGER;
    l2_chains INTEGER;
BEGIN
    SELECT COUNT(*) INTO total_chains FROM chain_rpc_endpoints;
    SELECT COUNT(*) INTO chains_with_id FROM chain_rpc_endpoints WHERE chain_id IS NOT NULL;
    SELECT COUNT(*) INTO l2_chains FROM chain_rpc_endpoints WHERE is_l2 = TRUE;
    
    RAISE NOTICE 'Total chains: %', total_chains;
    RAISE NOTICE 'Chains with chain_id: %', chains_with_id;
    RAISE NOTICE 'L2 chains: %', l2_chains;
    
    IF chains_with_id < total_chains THEN
        RAISE WARNING 'Some chains do not have chain_id assigned!';
    END IF;
END $$;

-- ============================================================================
-- SECTION 8: GRANT PERMISSIONS
-- ============================================================================

GRANT SELECT, INSERT ON gas_history TO farming_user;
GRANT USAGE ON SEQUENCE gas_history_id_seq TO farming_user;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================

-- Summary:
-- ✅ Added chain_id, is_l2, l1_data_fee, network_type, gas_multiplier to chain_rpc_endpoints
-- ✅ Populated chain_id for all known networks
-- ✅ Created gas_history table for MA_24h calculation
-- ✅ Added indexes for performance
-- ✅ Added cleanup function for gas history retention
-- ✅ Added gas check columns to bridge_history

-- Next steps:
-- 1. Create infrastructure/gas_logic.py
-- 2. Refactor funding/engine_v3.py to use GasLogic
-- 3. Integrate with BridgeManager
