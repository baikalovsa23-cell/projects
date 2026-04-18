-- ============================================================================
-- Migration 043: System State Table
-- ============================================================================
-- Purpose: Persist global system state (panic_mode, maintenance_mode, etc.)
-- Fixes: PANIC_MODE global variable not persisted on restart
-- Created: 2026-03-25
-- ============================================================================

-- Create system_state table
CREATE TABLE IF NOT EXISTS system_state (
    key VARCHAR(100) PRIMARY KEY,
    value BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by VARCHAR(255),
    metadata JSONB
);

-- Insert initial state
INSERT INTO system_state (key, value, updated_at, updated_by)
VALUES 
    ('panic_mode', FALSE, NOW(), 'system'),
    ('maintenance_mode', FALSE, NOW(), 'system')
ON CONFLICT (key) DO NOTHING;

-- Create index
CREATE INDEX IF NOT EXISTS idx_system_state_key ON system_state(key);

-- Add comment
COMMENT ON TABLE system_state IS 'Global system state persisted across restarts (panic_mode, maintenance_mode, etc.)';

-- Grant permissions
GRANT SELECT, INSERT, UPDATE ON system_state TO farming_user;
