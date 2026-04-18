-- ============================================================================
-- Funding Tree Mitigation — Variable Cluster Sizes & Multi-Hop Routing
-- ============================================================================
-- Migration: 017
-- Purpose: Anti-Sybil enhancement для funding architecture
-- Date: 2026-02-26
-- Risk Level: CRITICAL (Sybil detection mitigation P0)
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Modify funding_chains table for multi-hop support
-- ============================================================================

-- Add intermediate wallet support
ALTER TABLE funding_chains 
ADD COLUMN intermediate_wallet_1 VARCHAR(42),
ADD COLUMN intermediate_wallet_2 VARCHAR(42),
ADD COLUMN intermediate_delay_1_hours INTEGER DEFAULT 48 CHECK (intermediate_delay_1_hours BETWEEN 24 AND 72),
ADD COLUMN intermediate_delay_2_hours INTEGER DEFAULT 24 CHECK (intermediate_delay_2_hours BETWEEN 12 AND 36),
ADD COLUMN use_two_hops BOOLEAN DEFAULT FALSE;

-- Add variable cluster size
ALTER TABLE funding_chains
ADD COLUMN actual_wallet_count INTEGER DEFAULT 5 CHECK (actual_wallet_count BETWEEN 3 AND 7);

-- Add constraints for Ethereum address format
ALTER TABLE funding_chains
ADD CONSTRAINT check_intermediate_wallet_1_format  
    CHECK (intermediate_wallet_1 IS NULL OR intermediate_wallet_1 ~* '^0x[a-fA-F0-9]{40}$');

ALTER TABLE funding_chains
ADD CONSTRAINT check_intermediate_wallet_2_format  
    CHECK (intermediate_wallet_2 IS NULL OR intermediate_wallet_2 ~* '^0x[a-fA-F0-9]{40}$');

-- Comments for documentation
COMMENT ON COLUMN funding_chains.intermediate_wallet_1 IS 
    'First intermediate wallet address for multi-hop funding (CEX → intermediate_1). 
     Anti-Sybil: Breaks direct funding tree detection.';

COMMENT ON COLUMN funding_chains.intermediate_wallet_2 IS 
    'Second intermediate wallet address (intermediate_1 → intermediate_2 → targets). 
     NULL if using single-hop routing (50% probability).';

COMMENT ON COLUMN funding_chains.intermediate_delay_1_hours IS 
    'Delay in hours between CEX withdrawal → intermediate_1 → target wallets. 
     Range: 24-72h (Gaussian distribution, mean=48h, std=12h).';

COMMENT ON COLUMN funding_chains.intermediate_delay_2_hours IS 
    'Delay in hours for second hop (intermediate_1 → intermediate_2). 
     Range: 12-36h (Gaussian distribution, mean=24h, std=6h). 
     Only used if use_two_hops=TRUE.';

COMMENT ON COLUMN funding_chains.use_two_hops IS 
    'If TRUE, use 2 intermediate wallets (CEX → int1 → int2 → target). 
     If FALSE, use 1 intermediate wallet (CEX → int1 → target). 
     Randomly set to TRUE with 50% probability (anti-pattern detection).';

COMMENT ON COLUMN funding_chains.actual_wallet_count IS 
    'Actual number of target wallets for this chain (variable: 3-7). 
     Anti-Sybil: Prevents "always 5 wallets per chain" pattern. 
     Gaussian distribution: mean=5, std=1.2, clipped to [3,7].';


-- ============================================================================
-- 2. Create intermediate_funding_wallets table
-- ============================================================================

CREATE TABLE intermediate_funding_wallets (
    id SERIAL PRIMARY KEY,
    address VARCHAR(42) NOT NULL UNIQUE CHECK (address ~* '^0x[a-fA-F0-9]{40}$'),
    encrypted_private_key TEXT NOT NULL,
    funding_chain_id INTEGER REFERENCES funding_chains(id) ON DELETE CASCADE,
    layer INTEGER NOT NULL CHECK (layer IN (1, 2)),
    cex_funded_at TIMESTAMPTZ,
    forwarded_at TIMESTAMPTZ,
    forward_txhash VARCHAR(66),  -- 0x prefix + 64 hex chars
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'funded', 'forwarded', 'failed')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_intermediate_wallets_chain 
    ON intermediate_funding_wallets(funding_chain_id);

CREATE INDEX idx_intermediate_wallets_status 
    ON intermediate_funding_wallets(status);

CREATE INDEX idx_intermediate_wallets_layer 
    ON intermediate_funding_wallets(layer);

CREATE INDEX idx_intermediate_wallets_address 
    ON intermediate_funding_wallets(address);

-- Comments
COMMENT ON TABLE intermediate_funding_wallets IS 
    'Intermediate wallets for multi-hop funding (anti-clustering architecture). 
     Layer 1: CEX → intermediate_1 
     Layer 2: intermediate_1 → intermediate_2 (optional, 50% probability) 
     Target: intermediate → farming wallets';

COMMENT ON COLUMN intermediate_funding_wallets.layer IS 
    'Hop layer: 1 (first hop from CEX) or 2 (second hop for two-hop chains)';

COMMENT ON COLUMN intermediate_funding_wallets.cex_funded_at IS 
    'Timestamp when CEX withdrawal arrived to this intermediate wallet';

COMMENT ON COLUMN intermediate_funding_wallets.forwarded_at IS 
    'Timestamp when funds were forwarded to next layer or target wallets';

COMMENT ON COLUMN intermediate_funding_wallets.forward_txhash IS 
    'Transaction hash of forward transaction (intermediate → next layer)';


-- ============================================================================
-- 3. Create funding_chain_analytics view (for monitoring)
-- ============================================================================

CREATE OR REPLACE VIEW funding_chain_analytics AS
SELECT 
    fc.id AS chain_id,
    fc.chain_number,
    fc.withdrawal_network,
    fc.actual_wallet_count,
    fc.use_two_hops,
    fc.intermediate_delay_1_hours,
    fc.intermediate_delay_2_hours,
    cs.exchange,
    cs.subaccount_name,
    COUNT(fw.wallet_id) AS funded_wallets_count,
    COUNT(fw.wallet_id) FILTER (WHERE fw.status = 'completed') AS completed_count,
    COUNT(fw.wallet_id) FILTER (WHERE fw.status = 'failed') AS failed_count
FROM funding_chains fc
LEFT JOIN cex_subaccounts cs ON fc.cex_subaccount_id = cs.id
LEFT JOIN funding_withdrawals fw ON fc.id = fw.funding_chain_id
GROUP BY fc.id, fc.chain_number, fc.withdrawal_network, fc.actual_wallet_count,
         fc.use_two_hops, fc.intermediate_delay_1_hours, fc.intermediate_delay_2_hours,
        cs.exchange, cs.subaccount_name
ORDER BY fc.chain_number;

COMMENT ON VIEW funding_chain_analytics IS 
    'Analytics view for monitoring funding chain execution and wallet distribution';


-- ============================================================================
-- 4. Update existing funding_chains if any exist
-- ============================================================================

-- Set default actual_wallet_count for existing chains (if any)
UPDATE funding_chains
SET actual_wallet_count = wallets_count
WHERE actual_wallet_count IS NULL;


-- ============================================================================
-- 5. Audit trail table for intermediate wallet operations
-- ============================================================================

CREATE TABLE intermediate_wallet_operations (
    id SERIAL PRIMARY KEY,
    intermediate_wallet_id INTEGER REFERENCES intermediate_funding_wallets(id) ON DELETE CASCADE,
    operation_type VARCHAR(50) NOT NULL CHECK (operation_type IN ('created', 'funded', 'forwarded', 'failed')),
    amount_usdt NUMERIC(10, 2),
    txhash VARCHAR(66),
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_intermediate_operations_wallet 
    ON intermediate_wallet_operations(intermediate_wallet_id);

CREATE INDEX idx_intermediate_operations_type 
    ON intermediate_wallet_operations(operation_type);

COMMENT ON TABLE intermediate_wallet_operations IS 
    'Audit trail for all operations on intermediate funding wallets';


-- ============================================================================
-- 6. Function to validate cluster size distribution
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_cluster_size_distribution()
RETURNS TABLE (
    cluster_size INTEGER,
    chain_count BIGINT,
    percentage NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        fc.actual_wallet_count AS cluster_size,
        COUNT(*) AS chain_count,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
    FROM funding_chains fc
    GROUP BY fc.actual_wallet_count
    ORDER BY fc.actual_wallet_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_cluster_size_distribution() IS 
    'Returns distribution of cluster sizes. Should have variety (3,4,5,6,7), not all 5.';


-- ============================================================================
-- 7. Security constraints
-- ============================================================================

-- Prevent burn addresses in intermediate wallets (defense in depth)
ALTER TABLE intermediate_funding_wallets
ADD CONSTRAINT check_not_burn_address
    CHECK (
        address NOT IN (
            '0x0000000000000000000000000000000000000000',
            '0x000000000000000000000000000000000000dead',
            '0xdead000000000000000042069420694206942069'
        )
    );


COMMIT;

-- ============================================================================
-- Verification queries (run after migration)
-- ============================================================================

-- Check 1: Column additions
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'funding_chains'
  AND column_name IN ('intermediate_wallet_1', 'intermediate_wallet_2', 
                      'intermediate_delay_1_hours', 'use_two_hops', 
                      'actual_wallet_count')
ORDER BY ordinal_position;

-- Check 2: New table created
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_name = 'intermediate_funding_wallets';

-- Check 3: Indexes created
SELECT indexname, tablename
FROM pg_indexes
WHERE tablename IN ('intermediate_funding_wallets', 'intermediate_wallet_operations')
ORDER BY tablename, indexname;

-- Check 4: View created
SELECT table_name, view_definition
FROM information_schema.views
WHERE table_name = 'funding_chain_analytics';
