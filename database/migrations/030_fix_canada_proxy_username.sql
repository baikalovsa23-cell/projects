-- ============================================================================
-- Migration 030: Fix Canada Proxy Username
-- ============================================================================
-- PROBLEM: ca.decodo.com proxies have incorrect username without country-ca
-- Current: user-sp8g3q9g5c-sessionduration-60
-- Correct: user-sp8g3q9g5c-sessionduration-60-country-ca
--
-- Without country-ca parameter, Decodo returns UK IPs instead of Canada!
-- This migration fixes the username and updates host to gate.decodo.com
-- ============================================================================

-- Update Canada proxies with correct username and host
UPDATE proxy_pool 
SET 
    ip_address = 'gate.decodo.com',
    username = 'user-sp8g3q9g5c-sessionduration-60-country-ca',
    port = 7000 + (id - 445)  -- Remap ports: 446->7001, 447->7002, etc.
WHERE provider = 'decodo' 
  AND country_code = 'CA'
  AND ip_address = 'ca.decodo.com';

-- Verify the fix
SELECT id, ip_address, port, username, country_code, provider, session_id 
FROM proxy_pool 
WHERE country_code = 'CA' 
ORDER BY id 
LIMIT 10;

-- ============================================================================
-- Expected result after migration:
-- id  | ip_address      | port | username                                      | country_code
-- ----|-----------------|------|-----------------------------------------------|-------------
-- 446 | gate.decodo.com | 7001 | user-sp8g3q9g5c-sessionduration-60-country-ca | CA
-- 447 | gate.decodo.com | 7002 | user-sp8g3q9g5c-sessionduration-60-country-ca | CA
-- ... (30 total)
-- ============================================================================
