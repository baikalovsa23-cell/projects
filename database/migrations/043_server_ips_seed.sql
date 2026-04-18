-- ============================================================================
-- Migration 043: Server IPs Configuration
-- ============================================================================
-- Store server IPs in system_config for IP Guard module
-- These IPs must NEVER be exposed via proxy leaks
-- ============================================================================

INSERT INTO system_config (key, value, value_type, category, description) VALUES
    ('server_ips', '["82.40.60.131", "82.40.60.132", "82.22.53.183", "82.22.53.184"]', 'json', 'security', 'Server IPs that must never be exposed'),
    ('decodo_ttl_minutes', '60', 'integer', 'proxy', 'Decodo proxy TTL in minutes'),
    ('decodo_ttl_buffer_minutes', '10', 'integer', 'proxy', 'Decodo TTL buffer before expiry')
ON CONFLICT (key) DO UPDATE SET 
    value = EXCLUDED.value,
    updated_at = NOW();

-- Record migration
INSERT INTO schema_migrations (version, applied_at, description)
VALUES (43, NOW(), 'Server IPs configuration seed')
ON CONFLICT (version) DO NOTHING;
