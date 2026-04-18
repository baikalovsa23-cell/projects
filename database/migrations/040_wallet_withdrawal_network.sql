-- Migration 040: Add withdrawal_network column to wallets table
-- Purpose: Each wallet gets a unique withdrawal network within its exchange
-- This is separate from funding_network (network used for funding from CEX)
-- withdrawal_network is used for final withdrawal to authorized address

-- Add withdrawal_network column
ALTER TABLE wallets 
ADD COLUMN IF NOT EXISTS withdrawal_network VARCHAR(100);

-- Add comment
COMMENT ON COLUMN wallets.withdrawal_network IS 
'Network for final withdrawal to authorized address (e.g., arbitrum, base, optimism). Each wallet has a unique network within its CEX subaccount for anti-Sybil diversification.';

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_wallets_withdrawal_network ON wallets(withdrawal_network);

-- Verification query (can be run separately)
-- SELECT 
--   cs.exchange,
--   cs.subaccount_name,
--   w.id,
--   w.tier,
--   w.withdrawal_network
-- FROM wallets w
-- JOIN cex_subaccounts cs ON w.funding_cex_subaccount_id = cs.id
-- ORDER BY cs.exchange, cs.subaccount_name, w.id;