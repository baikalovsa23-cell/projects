-- ============================================================================
-- Migration 042: Safety Gates Seed Data
-- ============================================================================
-- Creates default safety gates for mainnet execution control
-- Gates must be opened manually before mainnet operations
-- ============================================================================

INSERT INTO safety_gates (gate_name, is_open) VALUES
    ('testnet_passed', FALSE),
    ('funding_verified', FALSE),
    ('proxy_health', FALSE),
    ('rpc_health', FALSE),
    ('gas_safe', FALSE),
    ('manual_approval', FALSE)
ON CONFLICT (gate_name) DO NOTHING;

-- Record migration
INSERT INTO schema_migrations (version, applied_at, description)
VALUES (42, NOW(), 'Safety gates seed data')
ON CONFLICT (version) DO NOTHING;
