-- ===================================================================
-- Migration 026: Direct Funding Architecture (v3.0)
-- Remove intermediate wallet infrastructure, enable direct CEX withdrawals
-- ===================================================================
-- Author: Senior Backend Developer
-- Date: 2026-03-01
-- Purpose: Eliminate Star patterns by removing intermediate wallets.
--          Enable direct CEX → target wallet withdrawals with interleaving.
-- ===================================================================

BEGIN;

-- ===================================================================
-- STEP 1: Remove Intermediate Wallet Infrastructure from funding_chains
-- ===================================================================

-- Remove intermediate-related columns from funding_chains
ALTER TABLE funding_chains
DROP COLUMN IF EXISTS intermediate_wallet_1 CASCADE,
DROP COLUMN IF EXISTS intermediate_wallet_2 CASCADE,
DROP COLUMN IF EXISTS use_two_hops CASCADE,
DROP COLUMN IF EXISTS intermediate_delay_1_hours CASCADE,
DROP COLUMN IF EXISTS intermediate_delay_2_hours CASCADE;

-- ===================================================================
-- STEP 2: Add Direct Funding Columns to funding_withdrawals
-- ===================================================================

-- Add columns for direct CEX withdrawal tracking
ALTER TABLE funding_withdrawals
ADD COLUMN IF NOT EXISTS direct_cex_withdrawal BOOLEAN DEFAULT TRUE,
ADD COLUMN IF NOT EXISTS cex_withdrawal_scheduled_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS cex_withdrawal_completed_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS cex_txid VARCHAR(100),
ADD COLUMN IF NOT EXISTS interleave_round INTEGER,
ADD COLUMN IF NOT EXISTS interleave_position INTEGER;

-- Add comments for clarity
COMMENT ON COLUMN funding_withdrawals.direct_cex_withdrawal IS 
'TRUE = direct CEX → target wallet (v3.0 architecture).
 FALSE = using intermediate wallets (deprecated v2.0).';

COMMENT ON COLUMN funding_withdrawals.cex_withdrawal_scheduled_at IS 
'Interleaved schedule timestamp. Withdrawals processed when scheduled_at <= NOW().
 Uses Gaussian delays (2-10h) to spread 90 withdrawals over 7 days.';

COMMENT ON COLUMN funding_withdrawals.cex_withdrawal_completed_at IS 
'Timestamp when CEX withdrawal was successfully completed (confirmed on-chain).';

COMMENT ON COLUMN funding_withdrawals.cex_txid IS 
'Transaction ID from CEX withdrawal API response.';

COMMENT ON COLUMN funding_withdrawals.interleave_round IS 
'Round number in interleaved execution (0-17 for 18 funding chains).
 Ensures exchange diversity: no consecutive withdrawals from same CEX.';

COMMENT ON COLUMN funding_withdrawals.interleave_position IS 
'Position within the round (determines order of execution within round).';

-- ===================================================================
-- STEP 3: Create Indexes for Efficient Scheduling Queries
-- ===================================================================

-- Index for scheduling job: find withdrawals ready to execute
CREATE INDEX IF NOT EXISTS idx_funding_withdrawals_cex_scheduled
ON funding_withdrawals(cex_withdrawal_scheduled_at)
WHERE status IN ('planned', 'processing');

-- Index for interleaving queries
CREATE INDEX IF NOT EXISTS idx_funding_withdrawals_interleave
ON funding_withdrawals(interleave_round, interleave_position)
WHERE direct_cex_withdrawal = TRUE;

-- Index for completed withdrawals tracking
CREATE INDEX IF NOT EXISTS idx_funding_withdrawals_completed
ON funding_withdrawals(cex_withdrawal_completed_at)
WHERE direct_cex_withdrawal = TRUE AND status = 'completed';

-- ===================================================================
-- STEP 4: Deprecate Intermediate Wallet Tables (Keep for Audit)
-- ===================================================================

-- Rename tables instead of dropping (audit trail)
ALTER TABLE IF EXISTS intermediate_funding_wallets 
RENAME TO intermediate_funding_wallets_deprecated_v2;

ALTER TABLE IF EXISTS intermediate_consolidation_wallets 
RENAME TO intermediate_consolidation_wallets_deprecated_v2;

-- Add deprecation notice
COMMENT ON TABLE intermediate_funding_wallets_deprecated_v2 IS 
'DEPRECATED v2.0: Intermediate funding wallets (no longer used).
 Kept for audit purposes only. DO NOT USE in v3.0+.
 Star patterns detected → architecture changed to direct withdrawals.';

COMMENT ON TABLE intermediate_consolidation_wallets_deprecated_v2 IS 
'DEPRECATED v2.0: Intermediate consolidation wallets (no longer used).
 Kept for audit purposes only. DO NOT USE in v3.0+.';

-- ===================================================================
-- STEP 5: Update funding_chains Table Comments
-- ===================================================================

COMMENT ON TABLE funding_chains IS 
'v3.0: Direct CEX → wallet funding chains. NO intermediate wallets.
 Each chain: 1 unique CEX subaccount → 3-7 target wallets (variable cluster sizes).
 18 total chains = full exchange/subaccount/network diversity.';

-- ===================================================================
-- STEP 6: Create Monitoring Views
-- ===================================================================

-- View: Direct funding schedule (upcoming withdrawals)
CREATE OR REPLACE VIEW v_direct_funding_schedule AS
SELECT 
    fw.id as withdrawal_id,
    fw.cex_withdrawal_scheduled_at as scheduled_time,
    cs.exchange,
    cs.subaccount_name,
    w.address as target_wallet,
    w.tier,
    fw.amount_usdt,
    p.country_code as proxy_region,
    fw.withdrawal_network,
    fw.interleave_round,
    fw.interleave_position,
    fw.status,
    EXTRACT(EPOCH FROM (fw.cex_withdrawal_scheduled_at - NOW()))/3600 as hours_until_execution,
    CASE 
        WHEN fw.cex_withdrawal_scheduled_at <= NOW() THEN 'READY'
        WHEN fw.cex_withdrawal_scheduled_at <= NOW() + INTERVAL '1 hour' THEN 'UPCOMING'
        ELSE 'SCHEDULED'
    END as execution_status
FROM funding_withdrawals fw
JOIN wallets w ON fw.wallet_id = w.id
JOIN cex_subaccounts cs ON fw.cex_subaccount_id = cs.id
JOIN proxy_pool p ON w.proxy_id = p.id
WHERE fw.direct_cex_withdrawal = TRUE
ORDER BY fw.cex_withdrawal_scheduled_at;

COMMENT ON VIEW v_direct_funding_schedule IS 
'Real-time view of direct funding schedule.
 Shows upcoming CEX withdrawals with execution status.';

-- View: Interleaving quality check
CREATE OR REPLACE VIEW v_funding_interleave_quality AS
SELECT 
    fw.interleave_round,
    COUNT(*) as withdrawals_in_round,
    COUNT(DISTINCT cs.exchange) as unique_exchanges,
    COUNT(DISTINCT cs.subaccount_name) as unique_subaccounts,
    COUNT(DISTINCT fw.withdrawal_network) as unique_networks,
    COUNT(DISTINCT p.country_code) as unique_proxy_regions,
    MIN(fw.cex_withdrawal_scheduled_at) as round_start,
    MAX(fw.cex_withdrawal_scheduled_at) as round_end,
    EXTRACT(EPOCH FROM (MAX(fw.cex_withdrawal_scheduled_at) - MIN(fw.cex_withdrawal_scheduled_at)))/3600 as round_duration_hours
FROM funding_withdrawals fw
JOIN cex_subaccounts cs ON fw.cex_subaccount_id = cs.id
JOIN proxy_pool p ON fw.wallet_id = p.id
WHERE fw.direct_cex_withdrawal = TRUE
GROUP BY fw.interleave_round
ORDER BY fw.interleave_round;

COMMENT ON VIEW v_funding_interleave_quality IS 
'Quality metrics for interleaved execution.
 Each round should have high exchange/network/proxy diversity.';

-- View: Temporal distribution check (7-day spread)
CREATE OR REPLACE VIEW v_funding_temporal_distribution AS
WITH daily_stats AS (
    SELECT 
        DATE_TRUNC('day', cex_withdrawal_scheduled_at) as day,
        COUNT(*) as withdrawals_count,
        COUNT(DISTINCT cex_subaccount_id) as unique_subaccounts,
        ARRAY_AGG(DISTINCT cs.exchange) as exchanges,
        AVG(amount_usdt) as avg_amount_usdt
    FROM funding_withdrawals fw
    JOIN cex_subaccounts cs ON fw.cex_subaccount_id = cs.id
    WHERE direct_cex_withdrawal = TRUE
    GROUP BY DATE_TRUNC('day', cex_withdrawal_scheduled_at)
)
SELECT 
    day,
    withdrawals_count,
    unique_subaccounts,
    exchanges,
    avg_amount_usdt,
    ROUND(withdrawals_count::NUMERIC / SUM(withdrawals_count) OVER () * 100, 2) as percentage_of_total
FROM daily_stats
ORDER BY day;

COMMENT ON VIEW v_funding_temporal_distribution IS 
'Daily breakdown of funding schedule.
 Should show relatively even distribution over 7 days (12-15 withdrawals/day).';

-- ===================================================================
-- STEP 7: Create Validation Function
-- ===================================================================

CREATE OR REPLACE FUNCTION validate_direct_funding_schedule()
RETURNS TABLE(
    check_name TEXT,
    severity TEXT,
    status TEXT,
    details TEXT
) AS $$
BEGIN
    -- Check 1: No Star patterns (all chains have different subaccounts)
    RETURN QUERY
    SELECT 
        'No Star Patterns'::TEXT,
        'CRITICAL'::TEXT,
        CASE WHEN COUNT(DISTINCT cex_subaccount_id) = COUNT(*) THEN 'PASS' ELSE 'FAIL' END,
        FORMAT('Funding chains: %s total, %s unique subaccounts', 
               COUNT(*), COUNT(DISTINCT cex_subaccount_id))
    FROM funding_chains;

    -- Check 2: All withdrawals are direct (no intermediate hops)
    RETURN QUERY
    SELECT 
        'All Direct Withdrawals'::TEXT,
        'CRITICAL'::TEXT,
        CASE WHEN COUNT(*) FILTER (WHERE direct_cex_withdrawal = FALSE) = 0 THEN 'PASS' ELSE 'FAIL' END,
        FORMAT('%s direct, %s via intermediate (should be 0)', 
               COUNT(*) FILTER (WHERE direct_cex_withdrawal = TRUE),
               COUNT(*) FILTER (WHERE direct_cex_withdrawal = FALSE))
    FROM funding_withdrawals;

    -- Check 3: Interleaving quality (each round has diversity)
    RETURN QUERY
    SELECT 
        'Interleave Diversity'::TEXT,
        'HIGH'::TEXT,
        CASE WHEN MIN(unique_exchanges) >= 3 THEN 'PASS' ELSE 'WARN' END,
        FORMAT('Min exchanges per round: %s (should be ≥3)', MIN(unique_exchanges))
    FROM v_funding_interleave_quality;

    -- Check 4: Temporal spread (7 days)
    RETURN QUERY
    SELECT 
        'Temporal Spread'::TEXT,
        'HIGH'::TEXT,
        CASE 
            WHEN EXTRACT(EPOCH FROM (MAX(cex_withdrawal_scheduled_at) - MIN(cex_withdrawal_scheduled_at)))/86400 BETWEEN 6 AND 8
            THEN 'PASS' 
            ELSE 'FAIL' 
        END,
        FORMAT('%s days spread (target: 7 days)', 
               ROUND(EXTRACT(EPOCH FROM (MAX(cex_withdrawal_scheduled_at) - MIN(cex_withdrawal_scheduled_at)))/86400, 1))
    FROM funding_withdrawals
    WHERE direct_cex_withdrawal = TRUE;

    -- Check 5: No burst withdrawals (min 1h gap between same subaccount)
    RETURN QUERY
    WITH gaps AS (
        SELECT 
            cex_subaccount_id,
            cex_withdrawal_scheduled_at,
            LAG(cex_withdrawal_scheduled_at) OVER (PARTITION BY cex_subaccount_id ORDER BY cex_withdrawal_scheduled_at) as prev_time,
            EXTRACT(EPOCH FROM (cex_withdrawal_scheduled_at - LAG(cex_withdrawal_scheduled_at) OVER (PARTITION BY cex_subaccount_id ORDER BY cex_withdrawal_scheduled_at)))/3600 as gap_hours
        FROM funding_withdrawals
        WHERE direct_cex_withdrawal = TRUE
    )
    SELECT 
        'No Burst Withdrawals'::TEXT,
        'HIGH'::TEXT,
        CASE WHEN MIN(gap_hours) >= 1.0 OR MIN(gap_hours) IS NULL THEN 'PASS' ELSE 'FAIL' END,
        FORMAT('Min gap: %sh (should be ≥1h)', ROUND(MIN(gap_hours), 2))
    FROM gaps
    WHERE gap_hours IS NOT NULL;

    -- Check 6: Cluster size variability (3-7 wallets per chain)
    RETURN QUERY
    WITH cluster_sizes AS (
        SELECT 
            funding_chain_id,
            COUNT(*) as wallets_count
        FROM funding_withdrawals
        WHERE direct_cex_withdrawal = TRUE
        GROUP BY funding_chain_id
    )
    SELECT 
        'Variable Cluster Sizes'::TEXT,
        'MEDIUM'::TEXT,
        CASE WHEN COUNT(DISTINCT wallets_count) >= 3 THEN 'PASS' ELSE 'WARN' END,
        FORMAT('%s unique cluster sizes (target: ≥3 for variability)', COUNT(DISTINCT wallets_count))
    FROM cluster_sizes;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_direct_funding_schedule IS 
'Validates direct funding schedule for anti-Sybil compliance.
 Run after setup_direct_funding.py to ensure quality.';

-- ===================================================================
-- STEP 8: Migration Metadata
-- ===================================================================

-- Record migration in version table (if exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'schema_migrations') THEN
        INSERT INTO schema_migrations (version, applied_at)
        VALUES ('026', NOW())
        ON CONFLICT (version) DO NOTHING;
    END IF;
END $$;

COMMIT;

-- ===================================================================
-- Post-Migration Verification
-- ===================================================================

-- Show summary
DO $$
DECLARE
    chains_count INTEGER;
    withdrawals_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO chains_count FROM funding_chains;
    SELECT COUNT(*) INTO withdrawals_count FROM funding_withdrawals WHERE direct_cex_withdrawal = TRUE;
    
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Migration 026 Applied Successfully';
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Architecture: Direct CEX → Wallet (v3.0)';
    RAISE NOTICE 'Funding Chains: %', chains_count;
    RAISE NOTICE 'Direct Withdrawals: %', withdrawals_count;
    RAISE NOTICE '';
    RAISE NOTICE 'Next Steps:';
    RAISE NOTICE '1. Run setup_direct_funding.py to generate schedule';
    RAISE NOTICE '2. Run SELECT * FROM validate_direct_funding_schedule()';
    RAISE NOTICE '3. Review v_direct_funding_schedule view';
    RAISE NOTICE '==============================================';
END $$;

-- ===================================================================
-- ROLLBACK PROCEDURE (Manual Execution Required)
-- ===================================================================
-- Execute this section ONLY if you need to rollback migration 026
-- WARNING: v3.0 architecture uses direct funding ONLY (no intermediate wallets)
-- This rollback only removes monitoring views/indexes, NOT intermediate columns
-- Run: SELECT rollback_migration_026();
-- ===================================================================

CREATE OR REPLACE FUNCTION rollback_migration_026()
RETURNS TEXT AS $$
DECLARE
    v_result TEXT := 'Rollback completed (partial - v3.0 architecture preserved)';
BEGIN
    -- NOTE: v3.0 architecture uses direct CEX → wallet funding
    -- Intermediate wallets are DEPRECATED and will NOT be restored
    
    -- STEP 1: Drop monitoring views
    DROP VIEW IF EXISTS v_direct_funding_schedule;
    DROP VIEW IF EXISTS v_funding_interleave_quality;
    DROP VIEW IF EXISTS v_funding_temporal_distribution;
    
    -- STEP 2: Drop validation function
    DROP FUNCTION IF EXISTS validate_direct_funding_schedule();
    
    -- STEP 3: Drop indexes
    DROP INDEX IF EXISTS idx_funding_withdrawals_cex_scheduled;
    DROP INDEX IF EXISTS idx_funding_withdrawals_interleave;
    DROP INDEX IF EXISTS idx_funding_withdrawals_completed;
    
    -- STEP 4: Remove migration record
    DELETE FROM schema_migrations WHERE version = '026';
    
    -- STEP 5: Remove direct funding columns (optional - only if needed)
    -- Uncomment below if you want to remove direct funding columns:
    -- ALTER TABLE funding_withdrawals
    -- DROP COLUMN IF EXISTS direct_cex_withdrawal,
    -- DROP COLUMN IF EXISTS cex_withdrawal_scheduled_at,
    -- DROP COLUMN IF EXISTS cex_withdrawal_completed_at,
    -- DROP COLUMN IF EXISTS cex_txid,
    -- DROP COLUMN IF EXISTS interleave_round,
    -- DROP COLUMN IF EXISTS interleave_position;
    
    RAISE NOTICE 'Migration 026 rolled back (partial)';
    RAISE NOTICE 'Direct funding architecture (v3.0) preserved';
    RAISE NOTICE 'Intermediate wallets remain DEPRECATED';
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rollback_migration_026 IS
'Partial rollback of migration 026: removes monitoring views/indexes only.
 v3.0 direct funding architecture is preserved (no intermediate wallets).
 Run manually: SELECT rollback_migration_026();';
