-- ============================================================================
-- Migration 039: Schema Migrations Tracking Table
-- ============================================================================
-- Date: 2026-03-12
-- Author: Database Architect
-- Description: Creates schema_migrations table to track applied migrations
-- Purpose: Enable proper migration versioning and audit trail
-- ============================================================================

-- ============================================================================
-- STEP 1: Create schema_migrations table
-- ============================================================================

CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(255) PRIMARY KEY,
    applied_at TIMESTAMPTZ DEFAULT NOW(),
    description TEXT
);

COMMENT ON TABLE schema_migrations IS 'Tracks all applied database migrations. Each migration file should insert a record here.';
COMMENT ON COLUMN schema_migrations.version IS 'Migration version number (e.g., "001", "026", "039")';
COMMENT ON COLUMN schema_migrations.applied_at IS 'Timestamp when migration was applied';
COMMENT ON COLUMN schema_migrations.description IS 'Brief description of what the migration does';

-- ============================================================================
-- STEP 2: Create index for quick lookups
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_schema_migrations_applied_at 
ON schema_migrations(applied_at DESC);

-- ============================================================================
-- STEP 3: Populate with history of already applied migrations
-- ============================================================================

-- These migrations were applied before schema_migrations table existed
-- Descriptions based on migration file headers

INSERT INTO schema_migrations (version, applied_at, description) VALUES
('001', '2026-02-24 00:00:00+00', 'Initial Database Setup - 30 tables, 90 proxies, 18 CEX subaccounts'),
('002', '2026-02-25 00:00:00+00', 'OpenClaw Integration - 8 tables for browser automation (Tier A wallets)'),
('015', '2026-02-25 00:00:00+00', 'Protocol Research Engine - LLM-based protocol discovery and approval workflow'),
('016', '2026-02-25 00:00:00+00', 'Airdrop Detector - Token balance tracking and scan logging (Module 17)'),
('017', '2026-02-26 00:00:00+00', 'Funding Tree Mitigation - Anti-Sybil protection for funding patterns'),
('018', '2026-02-26 00:00:00+00', 'Consolidation Mitigation - Anti-Sybil protection for withdrawal consolidation'),
('019', '2026-02-26 00:00:00+00', 'Withdrawal Security Policy - Tier-based withdrawal strategies with human approval'),
('020', '2026-02-27 00:00:00+00', 'Update Personas to 12 Archetypes - Behavioral persona diversification'),
('021', '2026-02-27 00:00:00+00', 'Redistribute Personas - Reassign personas across wallets for diversity'),
('022', '2026-02-28 00:00:00+00', 'Testnet Dryrun - Safe testing mode on Sepolia testnet'),
('023', '2026-02-28 00:00:00+00', 'Add Proxy to Intermediate Wallets - Proxy assignment for intermediate wallets'),
('024', '2026-03-01 00:00:00+00', 'Enforce Subaccount Uniqueness - Ensure unique CEX subaccounts per funding chain'),
('025', '2026-03-01 00:00:00+00', 'Add Proxy to Consolidation Wallets - Proxy assignment for consolidation wallets'),
('026', '2026-03-01 00:00:00+00', 'Direct Funding Architecture v3.0 - Remove intermediate wallets, direct CEX withdrawals'),
('027', '2026-03-02 00:00:00+00', 'Fix Preferred Hours Diversity - Ensure unique activity hours per wallet'),
('028', '2026-03-02 00:00:00+00', 'Add Warmup State - Wallet warmup period before active farming'),
('029', '2026-03-03 00:00:00+00', 'Wallet Funding Denormalization - Performance optimization for funding queries'),
('030', '2026-03-03 00:00:00+00', 'Fix Canada Proxy Username - Correct proxy authentication for CA proxies'),
('031', '2026-03-04 00:00:00+00', 'Bridge Manager v2 - Enhanced bridge routing with DeFiLlama integration'),
('032', '2026-03-04 00:00:00+00', 'Protocol Research Bridge - Bridge availability checks for new protocols'),
('033', '2026-03-06 00:00:00+00', 'Timezone Fix - Correct timezone assignment from proxy_pool (P0 Critical Anti-Sybil)'),
('034', '2026-03-07 00:00:00+00', 'Gas Logic Refactoring - Modular gas estimation with L2 support'),
('035', '2026-03-08 00:00:00+00', 'Chain Aliases Discovery - Network name normalization for bridge/CEX compatibility'),
('036', '2026-03-09 00:00:00+00', 'Farm Status Risk Scorer - Real-time Sybil risk assessment'),
('037', '2026-03-10 00:00:00+00', 'Missing Tables - Add missing tables from schema review'),
('038', '2026-03-11 00:00:00+00', 'Drop Intermediate Tables - Remove deprecated intermediate wallet tables')
ON CONFLICT (version) DO NOTHING;

-- ============================================================================
-- STEP 4: Insert current migration record
-- ============================================================================

INSERT INTO schema_migrations (version, description) VALUES
('039', 'Schema Migrations Tracking Table - Create migration versioning system')
ON CONFLICT (version) DO NOTHING;

-- ============================================================================
-- STEP 5: Verification
-- ============================================================================

-- Show migration count and latest migrations
DO $$
DECLARE
    total_count INTEGER;
    latest_version TEXT;
BEGIN
    SELECT COUNT(*) INTO total_count FROM schema_migrations;
    SELECT version INTO latest_version FROM schema_migrations ORDER BY applied_at DESC LIMIT 1;
    
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Migration 039 Applied Successfully';
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Total migrations tracked: %', total_count;
    RAISE NOTICE 'Latest migration: %', latest_version;
    RAISE NOTICE '';
    RAISE NOTICE 'Table schema_migrations created and populated.';
    RAISE NOTICE '==============================================';
END $$;

-- ============================================================================
-- STEP 6: Show migration history
-- ============================================================================

SELECT 
    version,
    applied_at,
    description
FROM schema_migrations
ORDER BY version;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
