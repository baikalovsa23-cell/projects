-- ============================================================================
-- Migration 036: Farm Status & Risk Scorer Support
-- ============================================================================
-- Purpose: Add farm_status column for Anti-Sybil filtering
-- Author: System Architect
-- Date: 2026-03-09
-- ============================================================================

-- ============================================================================
-- SECTION 1: ADD farm_status TO chain_rpc_endpoints
-- ============================================================================

-- Add column for farming status (ACTIVE, DROPPED, TARGET, BLACKLISTED)
ALTER TABLE chain_rpc_endpoints 
ADD COLUMN IF NOT EXISTS farm_status VARCHAR(20) DEFAULT 'ACTIVE';

-- Add comment
COMMENT ON COLUMN chain_rpc_endpoints.farm_status IS 'Farming status: ACTIVE (normal), DROPPED (airdrop passed), TARGET (priority), BLACKLISTED (unsafe)';

-- Create index for fast filtering
CREATE INDEX IF NOT EXISTS idx_chain_rpc_farm_status 
ON chain_rpc_endpoints(farm_status) 
WHERE farm_status IN ('ACTIVE', 'TARGET');

-- ============================================================================
-- SECTION 2: MARK DROPPED NETWORKS (Airdrop already happened)
-- ============================================================================

-- These networks had their airdrops in 2024-2025, no point farming
UPDATE chain_rpc_endpoints 
SET farm_status = 'DROPPED' 
WHERE LOWER(chain) IN (
    'zksync era', 'zksync', 'zksync-era',
    'layerzero',
    'optimism', 'op',
    'linea',
    'scroll',
    'taiko',
    'aztec',
    'starknet',
    'arbitrum', 'arbitrum one', 'arb'
);

-- ============================================================================
-- SECTION 3: MARK TARGET NETWORKS (Priority for 2026)
-- ============================================================================

-- These are the main targets for 2026 farming
UPDATE chain_rpc_endpoints 
SET farm_status = 'TARGET' 
WHERE LOWER(chain) IN (
    'base', 'base mainnet',
    'ink',
    'unichain',
    'megaeth', 'megaeth mainnet',
    'robinhood', 'robinhood chain',
    'mask', 'mask network'
);

-- ============================================================================
-- SECTION 4: ADD risk_tags TO protocols TABLE (if exists)
-- ============================================================================

-- Add column for risk tags from RiskScorer
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'protocols') THEN
        ALTER TABLE protocols ADD COLUMN IF NOT EXISTS risk_tags TEXT[];
        ALTER TABLE protocols ADD COLUMN IF NOT EXISTS risk_level VARCHAR(20) DEFAULT 'LOW';
        ALTER TABLE protocols ADD COLUMN IF NOT EXISTS requires_manual BOOLEAN DEFAULT FALSE;
        
        COMMENT ON COLUMN protocols.risk_tags IS 'Risk tags from RiskScorer: KYC, SYBIL, DERIVATIVES, etc.';
        COMMENT ON COLUMN protocols.risk_level IS 'Risk level: LOW, MEDIUM, HIGH, CRITICAL';
        COMMENT ON COLUMN protocols.requires_manual IS 'TRUE if protocol requires manual intervention (KYC, etc.)';
    END IF;
END $$;

-- ============================================================================
-- SECTION 5: ADD risk_tags TO protocol_research_pending TABLE
-- ============================================================================

-- Add risk columns to pending protocols table
ALTER TABLE protocol_research_pending 
ADD COLUMN IF NOT EXISTS risk_tags TEXT[];

ALTER TABLE protocol_research_pending 
ADD COLUMN IF NOT EXISTS risk_level VARCHAR(20) DEFAULT 'LOW';

ALTER TABLE protocol_research_pending 
ADD COLUMN IF NOT EXISTS requires_manual BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN protocol_research_pending.risk_tags IS 'Risk tags from RiskScorer: KYC, SYBIL, DERIVATIVES, etc.';
COMMENT ON COLUMN protocol_research_pending.risk_level IS 'Risk level: LOW, MEDIUM, HIGH, CRITICAL';
COMMENT ON COLUMN protocol_research_pending.requires_manual IS 'TRUE if protocol requires manual intervention';

-- ============================================================================
-- SECTION 6: VERIFICATION
-- ============================================================================

-- Verify farm_status distribution
DO $$
DECLARE
    active_count INTEGER;
    dropped_count INTEGER;
    target_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO active_count FROM chain_rpc_endpoints WHERE farm_status = 'ACTIVE';
    SELECT COUNT(*) INTO dropped_count FROM chain_rpc_endpoints WHERE farm_status = 'DROPPED';
    SELECT COUNT(*) INTO target_count FROM chain_rpc_endpoints WHERE farm_status = 'TARGET';
    
    RAISE NOTICE 'Farm Status Distribution:';
    RAISE NOTICE '  ACTIVE: %', active_count;
    RAISE NOTICE '  DROPPED: %', dropped_count;
    RAISE NOTICE '  TARGET: %', target_count;
END $$;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================

-- Summary:
-- ✅ Added farm_status column to chain_rpc_endpoints
-- ✅ Marked DROPPED networks (Arbitrum, ZKsync, etc.)
-- ✅ Marked TARGET networks (Base, Ink, Unichain, etc.)
-- ✅ Added risk_tags, risk_level, requires_manual to protocols
-- ✅ Added risk columns to protocol_research_pending
-- ✅ Created index for fast filtering

-- Next steps:
-- 1. Implement RiskScorer in research/risk_scorer.py
-- 2. Update NewsAggregator to use dynamic chain loading
-- 3. Update ProtocolAnalyzer to integrate with ChainDiscoveryService
