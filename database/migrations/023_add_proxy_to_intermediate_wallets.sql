-- Migration 023: Add Proxy Support to Intermediate Funding Wallets
-- Description: Adds proxy_id field to intermediate_funding_wallets table to ensure all wallet types use proxies
-- Date: 2026-02-28
-- Anti-Sybil Enhancement: Prevents IP clustering by ensuring intermediate wallets use proxies

-- Add proxy_id column to intermediate_funding_wallets
ALTER TABLE intermediate_funding_wallets
ADD COLUMN proxy_id INTEGER REFERENCES proxy_pool(id);

-- Add index for faster proxy lookups
CREATE INDEX idx_intermediate_wallets_proxy_id ON intermediate_funding_wallets(proxy_id);

-- Add comment explaining the field
COMMENT ON COLUMN intermediate_funding_wallets.proxy_id IS 'Reference to proxy used by this intermediate wallet for anti-Sybil protection';

-- Verify the change
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'intermediate_funding_wallets'
ORDER BY ordinal_position;
