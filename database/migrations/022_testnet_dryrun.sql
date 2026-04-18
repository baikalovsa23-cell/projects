-- ============================================================================
-- Testnet & Dry-Run Support — Sepolia Validation & Simulation Infrastructure
-- ============================================================================
-- Migration: 022
-- Purpose: Enable safe testnet validation and dry-run simulation before mainnet
-- Date: 2026-02-27
-- Risk Level: P0 CRITICAL (BLOCKING FOR MAINNET DEPLOYMENT)
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Create testnet_runs table
-- ============================================================================

CREATE TABLE testnet_runs (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    status VARCHAR(20) DEFAULT 'running' CHECK (status IN ('running', 'completed', 'failed')),
    total_wallets INTEGER DEFAULT 0,
    total_transactions INTEGER DEFAULT 0,
    success_rate DECIMAL(5,2),
    notes TEXT
);

-- Indexes
CREATE INDEX idx_testnet_runs_status 
    ON testnet_runs(status);

CREATE INDEX idx_testnet_runs_started 
    ON testnet_runs(started_at DESC);

-- Comments
COMMENT ON TABLE testnet_runs IS 
    'Track Sepolia testnet validation campaigns.
     Each run represents a complete validation cycle (funding → activity → withdrawal).
     CRITICAL: All runs must pass with 95%+ success_rate before mainnet deployment.';

COMMENT ON COLUMN testnet_runs.name IS 
    'Human-readable campaign name. Example: "Pre-mainnet validation v1", "Protocol X integration test".';

COMMENT ON COLUMN testnet_runs.success_rate IS 
    'Percentage of successful transactions (0.00-100.00).
     Mainnet gate requirement: ≥95% success rate.';


-- ============================================================================
-- 2. Create testnet_wallets table
-- ============================================================================

CREATE TABLE testnet_wallets (
    id SERIAL PRIMARY KEY,
    run_id INTEGER REFERENCES testnet_runs(id) ON DELETE CASCADE,
    address VARCHAR(42) NOT NULL UNIQUE CHECK (address ~* '^0x[a-fA-F0-9]{40}$'),
    encrypted_private_key TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    funded_at TIMESTAMPTZ,
    balance_eth DECIMAL(18,8) DEFAULT 0,
    transactions_count INTEGER DEFAULT 0,
    success_count INTEGER DEFAULT 0,
    auto_delete_after TIMESTAMPTZ
);

-- Indexes
CREATE INDEX idx_testnet_wallets_run 
    ON testnet_wallets(run_id);

CREATE INDEX idx_testnet_wallets_address 
    ON testnet_wallets(address);

CREATE INDEX idx_testnet_wallets_auto_delete 
    ON testnet_wallets(auto_delete_after) 
    WHERE auto_delete_after IS NOT NULL;

-- Comments
COMMENT ON TABLE testnet_wallets IS 
    'Temporary Sepolia testnet wallets for validation.
     SECURITY: Keys auto-deleted 7 days after validation completes.
     Do NOT use these wallets/keys for mainnet operations!';

COMMENT ON COLUMN testnet_wallets.encrypted_private_key IS 
    'Fernet-encrypted private key. Temporary — will be deleted after validation.';

COMMENT ON COLUMN testnet_wallets.auto_delete_after IS 
    'Timestamp when private key should be auto-deleted (typically run_completed_at + 7 days).
     NULL = do not delete (ongoing validation).';

COMMENT ON COLUMN testnet_wallets.balance_eth IS 
    'Current Sepolia ETH balance. Monitored to ensure sufficient test funds.';


-- ============================================================================
-- 3. Create dry_run_logs table
-- ============================================================================

CREATE TABLE dry_run_logs (
    id SERIAL PRIMARY KEY,
    wallet_address VARCHAR(42) CHECK (wallet_address IS NULL OR wallet_address ~* '^0x[a-fA-F0-9]{40}$'),
    operation_type VARCHAR(50) NOT NULL CHECK (operation_type IN (
        'swap', 'bridge', 'stake', 'unstake', 'lp_add', 'lp_remove', 
        'nft_mint', 'wrap', 'unwrap', 'approve', 'funding', 'withdrawal'
    )),
    simulated_at TIMESTAMPTZ DEFAULT NOW(),
    chain VARCHAR(20),
    estimated_gas BIGINT,
    estimated_cost_usd DECIMAL(10,4),
    would_succeed BOOLEAN,
    failure_reason TEXT,
    parameters JSONB,
    validation_checks JSONB
);

-- Indexes
CREATE INDEX idx_dry_run_logs_wallet 
    ON dry_run_logs(wallet_address);

CREATE INDEX idx_dry_run_logs_operation 
    ON dry_run_logs(operation_type);

CREATE INDEX idx_dry_run_logs_simulated 
    ON dry_run_logs(simulated_at DESC);

CREATE INDEX idx_dry_run_logs_chain 
    ON dry_run_logs(chain);

-- GIN index for JSONB queries
CREATE INDEX idx_dry_run_logs_parameters 
    ON dry_run_logs USING GIN(parameters);

CREATE INDEX idx_dry_run_logs_validation_checks 
    ON dry_run_logs USING GIN(validation_checks);

-- Comments
COMMENT ON TABLE dry_run_logs IS 
    'Simulation results for DRY_RUN mode.
     Logs what WOULD happen without executing on-chain.
     Used for logic validation, gas estimation, and debugging.';

COMMENT ON COLUMN dry_run_logs.operation_type IS 
    'Transaction type being simulated. Maps to activity/tx_types.py categories.';

COMMENT ON COLUMN dry_run_logs.estimated_gas IS 
    'Simulated gas cost in wei. 
     DRY_RUN mode uses heuristics, TESTNET/MAINNET use eth_estimateGas.';

COMMENT ON COLUMN dry_run_logs.estimated_cost_usd IS 
    'Estimated cost in USD (gas × gas_price × ETH_price).';

COMMENT ON COLUMN dry_run_logs.would_succeed IS 
    'Simulation prediction: TRUE = transaction would succeed, FALSE = would fail.';

COMMENT ON COLUMN dry_run_logs.failure_reason IS 
    'Explanation if would_succeed=FALSE. Examples: "insufficient balance", "nonce conflict", "contract error".';

COMMENT ON COLUMN dry_run_logs.parameters IS 
    'JSONB: Transaction parameters. 
     Example: {"from": "0x...", "to": "0x...", "value": "0.01", "data": "0x..."}.';

COMMENT ON COLUMN dry_run_logs.validation_checks IS 
    'JSONB: Pre-execution validation results.
     Example: {"balance_ok": true, "gas_ok": true, "nonce_ok": true, "contract_exists": true}.';


-- ============================================================================
-- 4. Create safety_gates table
-- ============================================================================

CREATE TABLE safety_gates (
    id SERIAL PRIMARY KEY,
    gate_name VARCHAR(50) UNIQUE NOT NULL,
    is_open BOOLEAN DEFAULT FALSE,
    required_for_mainnet BOOLEAN DEFAULT TRUE,
    opened_at TIMESTAMPTZ,
    opened_by VARCHAR(100),
    conditions_met JSONB,
    notes TEXT
);

-- Index
CREATE INDEX idx_safety_gates_name 
    ON safety_gates(gate_name);

CREATE INDEX idx_safety_gates_required 
    ON safety_gates(required_for_mainnet, is_open);

-- Comments
COMMENT ON TABLE safety_gates IS 
    'Mainnet access control gates.
     ALL gates with required_for_mainnet=TRUE must be is_open=TRUE before mainnet execution.
     Prevents accidental production deployment before validation completes.';

COMMENT ON COLUMN safety_gates.gate_name IS 
    'Unique gate identifier. Examples: "dry_run_validation", "testnet_validation", "human_approval".';

COMMENT ON COLUMN safety_gates.is_open IS 
    'Gate status: FALSE = BLOCKS mainnet, TRUE = allows mainnet.
     Default FALSE — must be manually opened after validation.';

COMMENT ON COLUMN safety_gates.required_for_mainnet IS 
    'If TRUE, this gate MUST be open before mainnet execution.
     If FALSE, gate is optional/informational.';

COMMENT ON COLUMN safety_gates.opened_by IS 
    'Operator who opened the gate (Telegram username or "system" for automated).';

COMMENT ON COLUMN safety_gates.conditions_met IS 
    'JSONB: Validation conditions that must pass before opening.
     Example: {"testnet_success_rate": 97.3, "dry_run_tests_passed": 245, "manual_review": true}.';


-- ============================================================================
-- 5. Create testnet_transactions table
-- ============================================================================

CREATE TABLE testnet_transactions (
    id SERIAL PRIMARY KEY,
    run_id INTEGER REFERENCES testnet_runs(id) ON DELETE CASCADE,
    wallet_id INTEGER REFERENCES testnet_wallets(id) ON DELETE CASCADE,
    tx_hash VARCHAR(66) UNIQUE CHECK (tx_hash ~* '^0x[a-fA-F0-9]{64}$'),
    operation_type VARCHAR(50) CHECK (operation_type IN (
        'swap', 'bridge', 'stake', 'unstake', 'lp_add', 'lp_remove',
        'nft_mint', 'wrap', 'unwrap', 'approve', 'funding', 'withdrawal'
    )),
    chain VARCHAR(20) DEFAULT 'sepolia',
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'failed')),
    gas_used BIGINT,
    gas_price_gwei DECIMAL(10,2),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    confirmed_at TIMESTAMPTZ,
    error_message TEXT
);

-- Indexes
CREATE INDEX idx_testnet_txs_run 
    ON testnet_transactions(run_id);

CREATE INDEX idx_testnet_txs_wallet 
    ON testnet_transactions(wallet_id);

CREATE INDEX idx_testnet_txs_hash 
    ON testnet_transactions(tx_hash);

CREATE INDEX idx_testnet_txs_status 
    ON testnet_transactions(status);

CREATE INDEX idx_testnet_txs_created 
    ON testnet_transactions(created_at DESC);

-- Comments
COMMENT ON TABLE testnet_transactions IS 
    'Sepolia testnet transaction history for validation runs.
     Tracks actual on-chain Sepolia transactions (not simulations).';

COMMENT ON COLUMN testnet_transactions.tx_hash IS 
    'Sepolia transaction hash (66 chars, 0x prefix).';

COMMENT ON COLUMN testnet_transactions.operation_type IS 
    'Transaction type. Matches activity/tx_types.py categories for consistency.';

COMMENT ON COLUMN testnet_transactions.gas_used IS 
    'Actual gas consumed (from transaction receipt).
     Used to validate dry-run gas estimation accuracy.';

COMMENT ON COLUMN testnet_transactions.error_message IS 
    'Revert reason if status=failed. Example: "insufficient funds", "execution reverted".';


-- ============================================================================
-- 6. Insert default safety gates
-- ============================================================================

INSERT INTO safety_gates (gate_name, is_open, required_for_mainnet, notes) VALUES
    ('dry_run_validation', FALSE, TRUE, 
     'All transaction types must pass dry-run simulation (100% success rate required).'),
    ('testnet_validation', FALSE, TRUE, 
     'Sepolia testnet validation complete (≥95% success rate across 200+ transactions).'),
    ('human_approval', FALSE, TRUE, 
     'Manual approval via Telegram command /enable_mainnet by authorized operator.');


-- ============================================================================
-- 7. Create validation status view
-- ============================================================================

CREATE OR REPLACE VIEW v_testnet_validation_status AS
SELECT 
    tr.id AS run_id,
    tr.name AS run_name,
    tr.status AS run_status,
    tr.started_at,
    tr.completed_at,
    COUNT(tw.id) AS total_wallets,
    COUNT(ttx.id) AS total_transactions,
    COUNT(ttx.id) FILTER (WHERE ttx.status = 'confirmed') AS confirmed_transactions,
    COUNT(ttx.id) FILTER (WHERE ttx.status = 'failed') AS failed_transactions,
    CASE 
        WHEN COUNT(ttx.id) > 0 
        THEN ROUND(
            100.0 * COUNT(ttx.id) FILTER (WHERE ttx.status = 'confirmed') / COUNT(ttx.id),
            2
        )
        ELSE 0 
    END AS success_rate,
    AVG(ttx.gas_used) FILTER (WHERE ttx.status = 'confirmed') AS avg_gas_used,
    MAX(ttx.confirmed_at) AS last_transaction_at,
    BOOL_AND(sg.is_open) FILTER (WHERE sg.required_for_mainnet = TRUE) AS all_gates_open,
    COUNT(sg.id) FILTER (WHERE sg.required_for_mainnet = TRUE AND sg.is_open = FALSE) AS gates_remaining
FROM testnet_runs tr
LEFT JOIN testnet_wallets tw ON tw.run_id = tr.id
LEFT JOIN testnet_transactions ttx ON ttx.run_id = tr.id
CROSS JOIN safety_gates sg
WHERE sg.required_for_mainnet = TRUE
GROUP BY tr.id, tr.name, tr.status, tr.started_at, tr.completed_at;

COMMENT ON VIEW v_testnet_validation_status IS 
    'Real-time testnet validation progress dashboard.
     Shows success rates, transaction counts, and safety gate status.
     Used by monitoring/health_check.py to validate mainnet readiness.';


-- ============================================================================
-- 8. Create helper function to check mainnet readiness
-- ============================================================================

CREATE OR REPLACE FUNCTION check_mainnet_readiness()
RETURNS TABLE (
    gate_name VARCHAR,
    is_open BOOLEAN,
    blocking_mainnet BOOLEAN,
    conditions_met JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        sg.gate_name,
        sg.is_open,
        sg.required_for_mainnet AS blocking_mainnet,
        sg.conditions_met
    FROM safety_gates sg
    WHERE sg.required_for_mainnet = TRUE
    ORDER BY sg.is_open ASC, sg.gate_name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION check_mainnet_readiness() IS 
    'Returns all required safety gates and their status.
     If ANY gate has is_open=FALSE and blocking_mainnet=TRUE, mainnet execution is BLOCKED.
     Used by activity/executor.py, funding/engine_v3.py, withdrawal/orchestrator.py.';


-- ============================================================================
-- 9. Create trigger to update testnet_runs success_rate
-- ============================================================================

CREATE OR REPLACE FUNCTION update_testnet_run_stats()
RETURNS TRIGGER AS $$
BEGIN
    -- Update total_transactions and success_rate for the run
    UPDATE testnet_runs
    SET 
        total_transactions = (
            SELECT COUNT(*) 
            FROM testnet_transactions 
            WHERE run_id = NEW.run_id
        ),
        success_rate = (
            SELECT ROUND(
                100.0 * COUNT(*) FILTER (WHERE status = 'confirmed') / NULLIF(COUNT(*), 0),
                2
            )
            FROM testnet_transactions
            WHERE run_id = NEW.run_id
        )
    WHERE id = NEW.run_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_testnet_run_stats
    AFTER INSERT OR UPDATE OF status ON testnet_transactions
    FOR EACH ROW
    EXECUTE FUNCTION update_testnet_run_stats();

COMMENT ON FUNCTION update_testnet_run_stats() IS 
    'Auto-update testnet_runs statistics when transactions are added/updated.
     Keeps success_rate and total_transactions in sync.';


-- ============================================================================
-- 10. Create auto-cleanup function for expired testnet wallets
-- ============================================================================

CREATE OR REPLACE FUNCTION cleanup_expired_testnet_keys()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    -- Delete private keys from expired testnet wallets
    UPDATE testnet_wallets
    SET encrypted_private_key = '[DELETED]'
    WHERE auto_delete_after IS NOT NULL
      AND auto_delete_after < NOW()
      AND encrypted_private_key != '[DELETED]';
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_expired_testnet_keys() IS 
    'Auto-delete expired testnet private keys for security.
     Should be called daily via cron (APScheduler).
     Returns count of keys deleted.';


-- ============================================================================
-- 11. Create performance indices for analytics queries
-- ============================================================================

-- Index for finding recent dry-run failures (debugging)
CREATE INDEX idx_dry_run_logs_failures 
    ON dry_run_logs(simulated_at DESC)
    WHERE would_succeed = FALSE;

-- Index for testnet transaction analytics
CREATE INDEX idx_testnet_txs_analytics 
    ON testnet_transactions(run_id, status, operation_type, created_at);

-- Partial index for pending testnet transactions (monitoring)
CREATE INDEX idx_testnet_txs_pending 
    ON testnet_transactions(created_at DESC)
    WHERE status = 'pending';


COMMIT;

-- ============================================================================
-- Post-migration verification queries
-- ============================================================================

-- Check 1: All tables created
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_name IN ('testnet_runs', 'testnet_wallets', 'dry_run_logs', 
                     'safety_gates', 'testnet_transactions')
ORDER BY table_name;

-- Check 2: Safety gates inserted
SELECT gate_name, is_open, required_for_mainnet 
FROM safety_gates
ORDER BY gate_name;

-- Check 3: View created
SELECT table_name
FROM information_schema.views
WHERE table_name = 'v_testnet_validation_status';

-- Check 4: Indexes created
SELECT tablename, indexname
FROM pg_indexes
WHERE tablename IN ('testnet_runs', 'testnet_wallets', 'dry_run_logs',
                    'safety_gates', 'testnet_transactions')
ORDER BY tablename, indexname;

-- Check 5: Functions created
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_name IN ('check_mainnet_readiness', 'update_testnet_run_stats', 
                       'cleanup_expired_testnet_keys')
ORDER BY routine_name;

-- Check 6: Triggers created
SELECT trigger_name, event_object_table, event_manipulation
FROM information_schema.triggers
WHERE trigger_name = 'trigger_update_testnet_run_stats';
