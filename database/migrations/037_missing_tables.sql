-- Migration 037: Add missing tables (wallet_transactions, dry_run_logs, safety_gates)

-- 1. wallet_transactions
CREATE TABLE IF NOT EXISTS wallet_transactions (
    id SERIAL PRIMARY KEY,
    wallet_id INT REFERENCES wallets(id) ON DELETE CASCADE,
    protocol_action_id INT REFERENCES protocol_actions(id) ON DELETE SET NULL,
    tx_hash VARCHAR(66) NOT NULL,
    chain VARCHAR(50) NOT NULL,
    from_address VARCHAR(42) NOT NULL,
    to_address VARCHAR(42),
    value NUMERIC,
    gas_used NUMERIC,
    status VARCHAR(20) NOT NULL,
    block_number INT,
    confirmed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_wallet_transactions_wallet_id ON wallet_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_tx_hash ON wallet_transactions(tx_hash);

-- 2. dry_run_logs
CREATE TABLE IF NOT EXISTS dry_run_logs (
    id SERIAL PRIMARY KEY,
    wallet_address VARCHAR(42) NOT NULL,
    chain VARCHAR(50) NOT NULL,
    tx_type VARCHAR(50) NOT NULL,
    value NUMERIC,
    estimated_gas NUMERIC,
    estimated_cost_usd NUMERIC,
    would_succeed BOOLEAN NOT NULL,
    failure_reason TEXT,
    simulated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_dry_run_logs_wallet_address ON dry_run_logs(wallet_address);

-- 3. safety_gates
CREATE TABLE IF NOT EXISTS safety_gates (
    id SERIAL PRIMARY KEY,
    gate_name VARCHAR(50) UNIQUE NOT NULL,
    is_open BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert default safety gates
INSERT INTO safety_gates (gate_name, is_open) VALUES
    ('mainnet_execution', FALSE),
    ('dry_run_validation', FALSE)
ON CONFLICT (gate_name) DO NOTHING;
