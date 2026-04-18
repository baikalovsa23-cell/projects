-- Migration 044: Add chain_tokens table for WETH and other token addresses
-- This migration removes hardcoded token addresses from code and moves them to database
-- Author: Airdrop Farming System v4.0
-- Date: 2026-03-22

-- Create chain_tokens table
CREATE TABLE IF NOT EXISTS chain_tokens (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER NOT NULL,
    token_symbol VARCHAR(10) NOT NULL,
    token_address VARCHAR(42) NOT NULL,
    is_native_wrapped BOOLEAN DEFAULT FALSE,
    decimals INTEGER DEFAULT 18,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chain_id, token_symbol)
);

-- Create index for faster lookups by chain_id
CREATE INDEX IF NOT EXISTS idx_chain_tokens_chain_id ON chain_tokens(chain_id);

-- Create index for faster lookups by is_native_wrapped
CREATE INDEX IF NOT EXISTS idx_chain_tokens_native_wrapped ON chain_tokens(is_native_wrapped);

-- Insert WETH addresses for all supported chains
INSERT INTO chain_tokens (chain_id, token_symbol, token_address, is_native_wrapped, decimals) VALUES
    -- Ethereum Mainnet
    (1, 'WETH', '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', TRUE, 18),
    
    -- Arbitrum One
    (42161, 'WETH', '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1', TRUE, 18),
    
    -- Base
    (8453, 'WETH', '0x4200000000000000000000000000000000000006', TRUE, 18),
    
    -- Optimism
    (10, 'WETH', '0x4200000000000000000000000000000000000006', TRUE, 18),
    
    -- Polygon (WMATIC)
    (137, 'WMATIC', '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270', TRUE, 18),
    
    -- BNB Chain (WBNB)
    (56, 'WBNB', '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c', TRUE, 18),
    
    -- Ink (WETH)
    (57073, 'WETH', '0x4200000000000000000000000000000000000006', TRUE, 18),
    
    -- MegaETH (WETH)
    (1088, 'WETH', '0x4200000000000000000000000000000000000006', TRUE, 18)
ON CONFLICT (chain_id, token_symbol) DO NOTHING;

-- Insert common stablecoins for reference (optional, for future use)
INSERT INTO chain_tokens (chain_id, token_symbol, token_address, is_native_wrapped, decimals) VALUES
    -- USDC on Arbitrum
    (42161, 'USDC', '0xaf88d065e77c8cC2239327C5EDb3A432268e5831', FALSE, 6),
    
    -- USDC on Base
    (8453, 'USDC', '0x833589fCD6eDb6E08f4c7C32D4f71b54bDA02913', FALSE, 6),
    
    -- USDC on Optimism
    (10, 'USDC', '0x7F5c764cBc14f9669B88837ca1490cCa17c31607', FALSE, 6),
    
    -- USDC on Polygon
    (137, 'USDC', '0x3c499c542cEF5E3811e1192ce70d8cC03d5c335', FALSE, 6),
    
    -- USDT on Arbitrum
    (42161, 'USDT', '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb', FALSE, 6),
    
    -- USDT on Base
    (8453, 'USDT', '0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb', FALSE, 6),
    
    -- USDT on Optimism
    (10, 'USDT', '0x94b008aA00579c1307B0EF2c499aD98a8ce58e58', FALSE, 6),
    
    -- USDT on Polygon
    (137, 'USDT', '0xc2132D05D31c914a87C6611C10748AEb04B58e8F', FALSE, 6)
ON CONFLICT (chain_id, token_symbol) DO NOTHING;

-- Add comment to table
COMMENT ON TABLE chain_tokens IS 'Stores token addresses for different chains, including WETH and common tokens';
COMMENT ON COLUMN chain_tokens.is_native_wrapped IS 'TRUE for native wrapped tokens (WETH, WMATIC, WBNB)';
COMMENT ON COLUMN chain_tokens.token_address IS 'Contract address of the token on the chain';
