-- ============================================================================
-- Migration 033: Timezone Architecture Fix
-- ============================================================================
-- PRIORITY: P0 CRITICAL (Anti-Sybil)
-- DATE: 2026-03-06
-- ============================================================================
-- PROBLEM:
--   - 30 Canada (CA) wallets use Iceland timezone (UTC+0) instead of Toronto (UTC-5)
--   - This creates Sybil detection risk: CA IP active at 3am local time
--   - Timezone taken from worker_nodes instead of proxy_pool
--
-- SOLUTION:
--   - Add timezone and utc_offset columns to proxy_pool
--   - Each proxy now has its own timezone based on country_code
--   - Update personas.py and scheduler.py to use proxy timezone
--
-- IMPACT:
--   - Fixes sleep window enforcement for CA wallets
--   - Ensures activity matches proxy geography
--   - Reduces Sybil detection risk by +0.5 score
-- ============================================================================

-- ============================================================================
-- STEP 1: Add timezone columns to proxy_pool
-- ============================================================================

ALTER TABLE proxy_pool 
ADD COLUMN IF NOT EXISTS timezone VARCHAR(50),
ADD COLUMN IF NOT EXISTS utc_offset INTEGER;

COMMENT ON COLUMN proxy_pool.timezone IS 'IANA timezone name (e.g., Europe/Amsterdam, America/Toronto)';
COMMENT ON COLUMN proxy_pool.utc_offset IS 'UTC offset in hours (e.g., +1 for NL, -5 for CA)';

-- ============================================================================
-- STEP 2: Update existing proxies with timezone data
-- ============================================================================

-- Netherlands (NL) → Europe/Amsterdam, UTC+1
UPDATE proxy_pool 
SET timezone = 'Europe/Amsterdam',
    utc_offset = 1
WHERE country_code = 'NL';

-- Iceland (IS) → Atlantic/Reykjavik, UTC+0
UPDATE proxy_pool 
SET timezone = 'Atlantic/Reykjavik',
    utc_offset = 0
WHERE country_code = 'IS';

-- Canada (CA) → America/Toronto, UTC-5
-- NOTE: Canada has multiple timezones, but Toronto is most common for residential proxies
-- If specific cities are known, use: America/Vancouver (UTC-8), America/Edmonton (UTC-7), etc.
UPDATE proxy_pool 
SET timezone = 'America/Toronto',
    utc_offset = -5
WHERE country_code = 'CA';

-- ============================================================================
-- STEP 3: Add NOT NULL constraint after data update
-- ============================================================================

ALTER TABLE proxy_pool 
ALTER COLUMN timezone SET NOT NULL,
ALTER COLUMN utc_offset SET NOT NULL;

-- ============================================================================
-- STEP 4: Create index for timezone lookups
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_proxy_pool_timezone 
ON proxy_pool(timezone);

-- ============================================================================
-- STEP 5: Verification query
-- ============================================================================

-- Check all proxies have timezone data
DO $$
DECLARE
    missing_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO missing_count
    FROM proxy_pool
    WHERE timezone IS NULL OR utc_offset IS NULL;
    
    IF missing_count > 0 THEN
        RAISE EXCEPTION 'CRITICAL: % proxies missing timezone data!', missing_count;
    END IF;
    
    RAISE NOTICE 'All proxies have timezone data assigned';
END $$;

-- ============================================================================
-- STEP 6: Summary statistics
-- ============================================================================

-- Show timezone distribution
SELECT 
    country_code,
    timezone,
    utc_offset,
    COUNT(*) as proxy_count
FROM proxy_pool
GROUP BY country_code, timezone, utc_offset
ORDER BY country_code;

-- Expected output:
-- | country_code | timezone              | utc_offset | proxy_count |
-- |--------------|----------------------|------------|-------------|
-- | NL           | Europe/Amsterdam      | 1          | 45          |
-- | IS           | Atlantic/Reykjavik    | 0          | 125         |
-- | CA           | America/Toronto       | -5         | 30          |

-- ============================================================================
-- STEP 7: Update wallet_personas comment
-- ============================================================================

COMMENT ON COLUMN wallet_personas.preferred_hours IS 'Active hours array in UTC, derived from proxy timezone (NOT worker timezone). For NL: 8am-9pm UTC, for IS: 10am-11pm UTC, for CA: 2pm-3am UTC (next day)';

-- ============================================================================
-- ROLLBACK (if needed)
-- ============================================================================

-- To rollback this migration:
-- ALTER TABLE proxy_pool DROP COLUMN IF EXISTS timezone;
-- ALTER TABLE proxy_pool DROP COLUMN IF EXISTS utc_offset;
-- DROP INDEX IF EXISTS idx_proxy_pool_timezone;

-- ============================================================================
-- POST-MIGRATION STEPS
-- ============================================================================

-- After applying this migration:
-- 1. Run: python3 wallets/personas.py generate (regenerate all personas)
-- 2. Update activity/scheduler.py to use proxy timezone
-- 3. Verify with: SELECT w.id, pp.country_code, pp.timezone FROM wallets w JOIN proxy_pool pp ON w.proxy_id = pp.id;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
