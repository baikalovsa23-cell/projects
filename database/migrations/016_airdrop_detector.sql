-- Migration 016: Airdrop Detector (Module 17)
-- Date: 2026-02-25
-- Author: System Architect
-- Description: Creates tables for token balance tracking and scan logging

-- ===========================================================================
-- 1. CREATE TABLE: wallet_tokens (Detected Token Balances)
-- ===========================================================================

CREATE TABLE wallet_tokens (
    id SERIAL PRIMARY KEY,
    
    -- Wallet & Chain
    wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    chain VARCHAR(50) NOT NULL,  -- 'arbitrum', 'base', 'optimism', etc.
    
    -- Token Details
    token_contract_address VARCHAR(42) NOT NULL,
    token_symbol VARCHAR(50) NOT NULL,
    token_name TEXT,
    decimals INTEGER NOT NULL CHECK (decimals >= 0 AND decimals <= 78),
    
    -- Balance
    balance NUMERIC(78, 0) NOT NULL,  -- Raw balance (big integer)
    balance_human DECIMAL(30, 18),    -- Human-readable balance (balance / 10^decimals)
    
    -- Airdrop Detection Metadata
    first_detected_at TIMESTAMPTZ DEFAULT NOW(),
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT unique_wallet_token UNIQUE(wallet_id, chain, token_contract_address)
);

COMMENT ON TABLE wallet_tokens IS 'Detected token balances on wallets (Module 17)';
COMMENT ON COLUMN wallet_tokens.balance IS 'Raw balance as returned by Explorer API (need to divide by 10^decimals)';
COMMENT ON COLUMN wallet_tokens.balance_human IS 'Human-readable balance for display in Telegram / UI';
COMMENT ON COLUMN wallet_tokens.first_detected_at IS 'Timestamp when token was first detected (for airdrop timing analysis)';

-- Indexes for performance
CREATE INDEX idx_wallet_tokens_wallet ON wallet_tokens(wallet_id);
CREATE INDEX idx_wallet_tokens_chain ON wallet_tokens(chain);
CREATE INDEX idx_wallet_tokens_updated ON wallet_tokens(last_updated DESC);
CREATE INDEX idx_wallet_tokens_first_detected ON wallet_tokens(first_detected_at DESC);

-- Index for finding new tokens (common query)
CREATE INDEX idx_wallet_tokens_recent_airdrops ON wallet_tokens(first_detected_at DESC, balance_human DESC)
    WHERE balance_human > 0;

-- ===========================================================================
-- 2. CREATE TABLE: airdrop_scan_logs (Scan Audit Trail)
-- ===========================================================================

CREATE TABLE airdrop_scan_logs (
    id SERIAL PRIMARY KEY,
    
    -- Scan Timing
    scan_start_at TIMESTAMPTZ NOT NULL,
    scan_end_at TIMESTAMPTZ,
    status VARCHAR(50) DEFAULT 'running',  -- 'running', 'completed', 'failed'
    
    -- Statistics
    total_wallets_scanned INTEGER DEFAULT 0,
    total_chains_scanned INTEGER DEFAULT 0,
    total_api_calls INTEGER DEFAULT 0,
    new_tokens_detected INTEGER DEFAULT 0,
    alerts_sent INTEGER DEFAULT 0,
    
    -- Performance Metrics
    scan_duration_seconds DECIMAL(10, 2),
    avg_api_response_time_ms DECIMAL(10, 2),
    
    -- Error Tracking
    api_errors_encountered INTEGER DEFAULT 0,
    rate_limit_hits INTEGER DEFAULT 0,
    timeout_errors INTEGER DEFAULT 0,
    error_details JSONB,  -- [{"chain": "arbitrum", "error": "rate limit", "timestamp": "..."}]
    
    -- Per-Chain Breakdown
    chain_stats JSONB,  -- {"arbitrum": {"api_calls": 90, "errors": 0, "duration_ms": 18000}}
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE airdrop_scan_logs IS 'Audit trail for Module 17 airdrop detection cycles';
COMMENT ON COLUMN airdrop_scan_logs.scan_duration_seconds IS 'Total time for scan cycle (target: ~110 seconds for 90 wallets)';
COMMENT ON COLUMN airdrop_scan_logs.chain_stats IS 'Per-chain performance metrics for debugging bottlenecks';

-- Indexes
CREATE INDEX idx_airdrop_scan_logs_start ON airdrop_scan_logs(scan_start_at DESC);
CREATE INDEX idx_airdrop_scan_logs_status ON airdrop_scan_logs(status);
CREATE INDEX idx_airdrop_scan_logs_new_tokens ON airdrop_scan_logs(new_tokens_detected DESC)
    WHERE new_tokens_detected > 0;

-- ===========================================================================
-- 3. CREATE TRIGGER: Auto-update last_updated timestamp
-- ===========================================================================

CREATE OR REPLACE FUNCTION update_wallet_token_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_updated = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_wallet_token_timestamp
    BEFORE UPDATE ON wallet_tokens
    FOR EACH ROW
    EXECUTE FUNCTION update_wallet_token_timestamp();

-- ===========================================================================
-- 4. HELPER FUNCTIONS
-- ===========================================================================

-- Function: Get newly detected tokens (detected in last N hours)
CREATE OR REPLACE FUNCTION get_recent_airdrops(
    hours_ago INTEGER DEFAULT 24
)
RETURNS TABLE (
    wallet_id INTEGER,
    chain VARCHAR(50),
    token_symbol VARCHAR(50),
    balance_human DECIMAL(30, 18),
    first_detected_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        wt.wallet_id,
        wt.chain,
        wt.token_symbol,
        wt.balance_human,
        wt.first_detected_at
    FROM wallet_tokens wt
    WHERE wt.first_detected_at >= NOW() - INTERVAL '1 hour' * hours_ago
      AND wt.balance_human > 0
    ORDER BY wt.first_detected_at DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_recent_airdrops IS 'Get tokens detected in last N hours (default 24h)';

-- Function: Get scan cycle statistics
CREATE OR REPLACE FUNCTION get_scan_statistics(
    last_n_scans INTEGER DEFAULT 10
)
RETURNS TABLE (
    scan_id INTEGER,
    scan_date TIMESTAMPTZ,
    duration_sec DECIMAL(10, 2),
    wallets_scanned INTEGER,
    new_tokens INTEGER,
    api_errors INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        asl.id,
        asl.scan_start_at,
        asl.scan_duration_seconds,
        asl.total_wallets_scanned,
        asl.new_tokens_detected,
        asl.api_errors_encountered
    FROM airdrop_scan_logs asl
    WHERE asl.status = 'completed'
    ORDER BY asl.scan_start_at DESC
    LIMIT last_n_scans;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_scan_statistics IS 'Get statistics for last N scan cycles (default 10)';

-- ===========================================================================
-- 5. SAMPLE DATA (for testing)
-- ===========================================================================

-- Insert test scan log (for Telegram /airdrop_scan_status command testing)
INSERT INTO airdrop_scan_logs (
    scan_start_at,
    scan_end_at,
    status,
    total_wallets_scanned,
    total_chains_scanned,
    total_api_calls,
    new_tokens_detected,
    alerts_sent,
    scan_duration_seconds,
    avg_api_response_time_ms,
    api_errors_encountered,
    chain_stats
) VALUES (
    NOW() - INTERVAL '1 hour',
    NOW() - INTERVAL '50 minutes',
    'completed',
    90,
    7,
    630,
    5,
    2,
    110.53,
    185.42,
    0,
    '{
        "arbitrum": {"api_calls": 90, "errors": 0, "duration_ms": 18000},
        "base": {"api_calls": 90, "errors": 0, "duration_ms": 18000},
        "optimism": {"api_calls": 90, "errors": 0, "duration_ms": 18000},
        "polygon": {"api_calls": 90, "errors": 0, "duration_ms": 18000},
        "bnbchain": {"api_calls": 90, "errors": 0, "duration_ms": 18000},
        "ink": {"rpc_calls": 90, "errors": 0, "duration_ms": 4500},
        "megaeth": {"rpc_calls": 90, "errors": 0, "duration_ms": 4500}
    }'::jsonb
);

-- ===========================================================================
-- 6. MIGRATION COMPLETE
-- ===========================================================================

-- Log migration completion
INSERT INTO airdrop_scan_logs (
    scan_start_at,
    scan_end_at,
    status,
    total_wallets_scanned,
    total_chains_scanned
) VALUES (
    NOW(),
    NOW(),
    'completed',
    0,
    0
) RETURNING id;

-- Success message
SELECT 'Migration 016: Airdrop Detector tables created successfully' AS migration_status;
