-- ============================================================================
-- Migration 001: Initial Database Setup
-- ============================================================================
-- Version: 0.2.0
-- Date: 2026-02-24
-- Description: Complete database initialization (schema + seed data)
-- ============================================================================

-- This migration includes:
-- 1. Full schema (30 tables, 14 ENUMs, 35+ indexes)
-- 2. 90 proxies (45 IPRoyal NL + 45 Decodo IS)
-- 3. 18 CEX subaccounts (OKX-4, Binance-4, Bybit-4, KuCoin-3, MEXC-3)

-- ============================================================================
-- Step 1: Run main schema (30 tables)
-- ============================================================================

\echo '=== Step 1/3: Creating schema (30 tables) ==='
\i ../schema.sql

-- ============================================================================
-- Step 2: Seed proxies (90 entries)
-- ============================================================================

\echo '=== Step 2/3: Seeding proxy pool (90 proxies) ==='
\i ../seed_proxies.sql

-- ============================================================================
-- Step 3: Seed CEX subaccounts (18 entries)
-- ============================================================================

\echo '=== Step 3/3: Seeding CEX subaccounts (18 subaccounts) ==='
\i ../seed_cex_subaccounts.sql

-- ============================================================================
-- Verification Queries
-- ============================================================================

\echo ''
\echo '=== Migration 001 Verification ==='

-- Count tables
SELECT 
    'Tables' AS object_type,
    COUNT(*) AS count
FROM pg_tables
WHERE schemaname = 'public';

-- Count ENUMs
SELECT 
    'ENUM types' AS object_type,
    COUNT(*) AS count
FROM pg_type
WHERE typtype = 'e';

-- Count indexes
SELECT 
    'Indexes' AS object_type,
    COUNT(*) AS count
FROM pg_indexes
WHERE schemaname = 'public';

-- Verify proxies
SELECT 
    'Proxies' AS object_type,
    COUNT(*) AS count
FROM proxy_pool;

SELECT 
    'NL Proxies' AS provider,
    COUNT(*) AS count
FROM proxy_pool
WHERE country_code = 'NL';

SELECT 
    'IS Proxies' AS provider,
    COUNT(*) AS count
FROM proxy_pool
WHERE country_code = 'IS';

-- Verify CEX subaccounts
SELECT 
    'CEX Subaccounts' AS object_type,
    COUNT(*) AS count
FROM cex_subaccounts;

SELECT 
    exchange,
    COUNT(*) AS subaccounts_count
FROM cex_subaccounts
GROUP BY exchange
ORDER BY exchange;

-- ============================================================================
-- Migration Complete
-- ============================================================================

\echo ''
\echo '✅ Migration 001 completed successfully!'
\echo ''
\echo 'Next steps:'
\echo '1. Run: python funding/secrets.py encrypt-cex-keys'
\echo '2. Verify encryption: SELECT LENGTH(api_key) FROM cex_subaccounts LIMIT 1'
\echo '   (Should be ~100+ characters for encrypted vs ~30-80 for plain)'
\echo '3. Generate 90 wallets: python wallets/generator.py'
\echo '4. Create funding chains: python setup_direct_funding.py'
\echo ''
