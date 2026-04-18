-- Migration 025: Add proxy_id to intermediate_consolidation_wallets
-- Purpose: Enable geo-stability for consolidation phases (Phase 1 & Phase 2)
-- Date: 2026-03-01
-- Requirement: Each consolidation wallet must use consistent proxy from same region as source wallets

-- Add proxy_id column to intermediate_consolidation_wallets
ALTER TABLE intermediate_consolidation_wallets
ADD COLUMN IF NOT EXISTS proxy_id INTEGER REFERENCES proxy_pool(id);

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_consolidation_wallets_proxy_id 
    ON intermediate_consolidation_wallets(proxy_id);

-- Add comment
COMMENT ON COLUMN intermediate_consolidation_wallets.proxy_id IS 
    'Proxy for Phase 1 and Phase 2 consolidation (permanent geo-stability)';

-- Verify table structure
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'intermediate_consolidation_wallets'
    AND column_name = 'proxy_id';
