-- Migration 038: Drop Intermediate/Consolidation Tables (v4.0 Architecture)
-- ============================================================================
-- Purpose: Remove all intermediate wallet infrastructure (deprecated v2.0)
-- Date: 2026-03-12
-- 
-- Background:
-- v2.0 used intermediate wallets for funding and consolidation (Star patterns).
-- v3.0+ uses direct CEX → wallet funding (no intermediate wallets).
-- v4.0 removes all intermediate/consolidation infrastructure completely.
--
-- Tables to DROP:
--   - intermediate_funding_wallets_deprecated_v2 (renamed in migration 026)
--   - intermediate_consolidation_wallets_deprecated_v2 (renamed in migration 026)
--   - intermediate_wallet_operations
--   - consolidation_plans
--   - consolidation_audit_trail
--   - phase2_transfer_queue
--
-- Views to DROP:
--   - v_intermediate_wallet_status
--
-- Functions to DROP:
--   - get_consolidation_wallet_summary() (if exists)
--
-- Migration dependencies:
--   - Migration 017 created intermediate_funding_wallets, intermediate_wallet_operations
--   - Migration 018 created consolidation_plans, intermediate_consolidation_wallets, 
--     phase2_transfer_queue, consolidation_audit_trail
--   - Migration 023 added proxy_id to intermediate_funding_wallets
--   - Migration 024 created v_intermediate_wallet_status view
--   - Migration 025 added proxy_id to intermediate_consolidation_wallets
--   - Migration 026 renamed tables to _deprecated_v2
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Drop Views
-- ============================================================================

DROP VIEW IF EXISTS v_intermediate_wallet_status CASCADE;

-- ============================================================================
-- 2. Drop Tables (in correct order due to FK constraints)
-- ============================================================================

-- Phase 2 transfer queue (depends on consolidation_plans and intermediate_consolidation_wallets)
DROP TABLE IF EXISTS phase2_transfer_queue CASCADE;

-- Consolidation audit trail (depends on consolidation_plans)
DROP TABLE IF EXISTS consolidation_audit_trail CASCADE;

-- Consolidation plans
DROP TABLE IF EXISTS consolidation_plans CASCADE;

-- Intermediate wallet operations (depends on intermediate_funding_wallets)
DROP TABLE IF EXISTS intermediate_wallet_operations CASCADE;

-- Intermediate consolidation wallets (deprecated v2)
DROP TABLE IF EXISTS intermediate_consolidation_wallets_deprecated_v2 CASCADE;

-- Intermediate funding wallets (deprecated v2)
DROP TABLE IF EXISTS intermediate_funding_wallets_deprecated_v2 CASCADE;

-- Also drop non-deprecated versions if they exist (safety)
DROP TABLE IF EXISTS intermediate_consolidation_wallets CASCADE;
DROP TABLE IF EXISTS intermediate_funding_wallets CASCADE;

-- ============================================================================
-- 3. Drop Functions
-- ============================================================================

DROP FUNCTION IF EXISTS get_consolidation_wallet_summary() CASCADE;

-- ============================================================================
-- 4. Remove intermediate-related columns from withdrawal_steps (if exist)
-- ============================================================================

-- These columns were added in migration 018 but are no longer needed
ALTER TABLE withdrawal_steps 
DROP COLUMN IF EXISTS consolidation_phase CASCADE;

ALTER TABLE withdrawal_steps 
DROP COLUMN IF EXISTS intermediate_destination CASCADE;

ALTER TABLE withdrawal_steps 
DROP COLUMN IF EXISTS is_final_consolidation CASCADE;

-- ============================================================================
-- 5. Verification
-- ============================================================================

-- Log migration completion
DO $$
BEGIN
    RAISE NOTICE 'Migration 038 completed: All intermediate/consolidation tables dropped';
    RAISE NOTICE 'Architecture is now v4.0: Direct CEX → wallet funding only';
END $$;

-- Insert migration record
INSERT INTO system_events (event_type, severity, message, metadata)
VALUES (
    'migration_complete',
    'info',
    'Migration 038: Dropped intermediate/consolidation tables',
    jsonb_build_object(
        'migration_id', 38,
        'tables_dropped', ARRAY[
            'intermediate_funding_wallets_deprecated_v2',
            'intermediate_consolidation_wallets_deprecated_v2',
            'intermediate_wallet_operations',
            'consolidation_plans',
            'consolidation_audit_trail',
            'phase2_transfer_queue'
        ],
        'views_dropped', ARRAY['v_intermediate_wallet_status'],
        'architecture_version', '4.0',
        'funding_model', 'direct_cex_to_wallet'
    )
);

COMMIT;

-- ============================================================================
-- Post-migration verification query
-- ============================================================================

-- Verify tables are gone
SELECT 
    table_name,
    CASE 
        WHEN table_name LIKE '%intermediate%' OR table_name LIKE '%consolidation%' 
        THEN 'SHOULD NOT EXIST' 
        ELSE 'OK' 
    END as status
FROM information_schema.tables 
WHERE table_schema = 'public'
  AND (table_name LIKE '%intermediate%' OR table_name LIKE '%consolidation%')
ORDER BY table_name;

-- Expected result: 0 rows (all intermediate/consolidation tables removed)