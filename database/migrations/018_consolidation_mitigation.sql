-- ============================================================================
-- Consolidation Clustering Mitigation — Phased Withdrawal Architecture
-- ============================================================================
-- Migration: 018
-- Purpose: Anti-Sybil two-phase consolidation (wallets → intermediates → master)
-- Date: 2026-02-26
-- Risk Level: CRITICAL (Sybil detection mitigation P0)
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Create consolidation_plans table
-- ============================================================================

CREATE TABLE consolidation_plans (
    id SERIAL PRIMARY KEY,
    airdrop_id INTEGER,  -- Nullable - can be NULL if not linked to specific airdrop
    phase_1_start_date DATE NOT NULL,  -- Week 1-4 after airdrop claim
    phase_2_start_date DATE NOT NULL,  -- Week 12-24 after airdrop claim
    master_cold_wallet VARCHAR(42) NOT NULL CHECK (master_cold_wallet ~* '^0x[a-fA-F0-9]{40}$'),
    status VARCHAR(50) DEFAULT 'planned' CHECK (status IN ('planned', 'phase1_active', 'phase1_completed', 'phase2_active', 'completed', 'cancelled')),
    phase1_completed_at TIMESTAMPTZ,
    phase2_completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_consolidation_plans_airdrop 
    ON consolidation_plans(airdrop_id);

CREATE INDEX idx_consolidation_plans_status 
    ON consolidation_plans(status);

CREATE INDEX idx_consolidation_plans_phase1_start 
    ON consolidation_plans(phase_1_start_date);

CREATE INDEX idx_consolidation_plans_phase2_start 
    ON consolidation_plans(phase_2_start_date);

-- Constraint: Phase 2 must be after Phase 1
ALTER TABLE consolidation_plans
ADD CONSTRAINT check_phase2_after_phase1
    CHECK (phase_2_start_date > phase_1_start_date);

-- Comments
COMMENT ON TABLE consolidation_plans IS 
    'Two-phase consolidation plans for anti-clustering.
     Phase 1: Individual wallets → 18 intermediate consolidation wallets (Week 1-4)
     Phase 2: 18 intermediates → 1 master cold wallet (Week 12-24)';

COMMENT ON COLUMN consolidation_plans.airdrop_id IS 
    'Links to airdrop_detections table. Consolidation triggered after airdrop claim.';

COMMENT ON COLUMN consolidation_plans.phase_1_start_date IS 
    'Start date for Phase 1 (wallets → intermediates). 
     Typically 1-4 weeks after airdrop claim (Gaussian: mean=17 days, std=7 days).';

COMMENT ON COLUMN consolidation_plans.phase_2_start_date IS 
    'Start date for Phase 2 (intermediates → master cold wallet). 
     Typically 12-24 weeks after airdrop claim (Gaussian: mean=130 days, std=21 days). 
     CRITICAL: Long delay prevents clustering detection.';

COMMENT ON COLUMN consolidation_plans.master_cold_wallet IS 
    'Final destination cold wallet address. All 90 wallets eventually consolidate here via intermediates.';


-- ============================================================================
-- 2. Create intermediate_consolidation_wallets table
-- ============================================================================

CREATE TABLE intermediate_consolidation_wallets (
    id SERIAL PRIMARY KEY,
    address VARCHAR(42) NOT NULL UNIQUE CHECK (address ~* '^0x[a-fA-F0-9]{40}$'),
    encrypted_private_key TEXT NOT NULL,
    funding_chain_id INTEGER REFERENCES funding_chains(id) ON DELETE CASCADE,
    source_wallet_ids INTEGER[],  -- Array of wallet IDs that will consolidate here
    consolidated_at TIMESTAMPTZ,  -- When all source wallets consolidated
    consolidated_amount_usdt NUMERIC(12, 2),
    forwarded_to_master_at TIMESTAMPTZ,  -- When forwarded to master cold wallet
    forward_txhash VARCHAR(66),
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'consolidating', 'consolidated', 'forwarded', 'failed')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_intermediate_consolidation_chain 
    ON intermediate_consolidation_wallets(funding_chain_id);

CREATE INDEX idx_intermediate_consolidation_status 
    ON intermediate_consolidation_wallets(status);

CREATE INDEX idx_intermediate_consolidation_address 
    ON intermediate_consolidation_wallets(address);

-- GIN index for array search (find which intermediate wallet contains a specific source wallet)
CREATE INDEX idx_intermediate_consolidation_source_wallets 
    ON intermediate_consolidation_wallets USING GIN(source_wallet_ids);

-- Comments
COMMENT ON TABLE intermediate_consolidation_wallets IS 
    '18 intermediate wallets for first-stage consolidation (1 per funding chain).
     Each intermediate receives funds from 3-7 source wallets (variable cluster size).
     Anti-Sybil: Breaks direct "90 wallets → 1 address" clustering pattern.';

COMMENT ON COLUMN intermediate_consolidation_wallets.funding_chain_id IS 
    'Links to funding_chains. Each funding chain has 1 intermediate consolidation wallet.';

COMMENT ON COLUMN intermediate_consolidation_wallets.source_wallet_ids IS 
    'Array of wallet IDs that will send funds to this intermediate wallet (Phase 1).
     Example: {1, 2, 3, 4, 5} means wallets 1-5 consolidate here.';

COMMENT ON COLUMN intermediate_consolidation_wallets.consolidated_at IS 
    'Timestamp when all source wallets have completed Phase 1 transfers.';

COMMENT ON COLUMN intermediate_consolidation_wallets.forwarded_to_master_at IS 
    'Timestamp when this intermediate forwarded funds to master cold wallet (Phase 2).';


-- ============================================================================
-- 3. Add consolidation fields to withdrawal_steps table
-- ============================================================================

-- Add phase tracking (check if columns exist first)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='withdrawal_steps' AND column_name='consolidation_phase') THEN
        ALTER TABLE withdrawal_steps ADD COLUMN consolidation_phase INTEGER DEFAULT 1 CHECK (consolidation_phase IN (1, 2));
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='withdrawal_steps' AND column_name='intermediate_destination') THEN
        ALTER TABLE withdrawal_steps ADD COLUMN intermediate_destination VARCHAR(42);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='withdrawal_steps' AND column_name='is_final_consolidation') THEN
        ALTER TABLE withdrawal_steps ADD COLUMN is_final_consolidation BOOLEAN DEFAULT FALSE;
    END IF;
END $$;

-- Add constraint for intermediate destination format (only if doesn't exist)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='check_intermediate_destination_format') THEN
        ALTER TABLE withdrawal_steps
        ADD CONSTRAINT check_intermediate_destination_format
            CHECK (intermediate_destination IS NULL OR intermediate_destination ~* '^0x[a-fA-F0-9]{40}$');
    END IF;
END $$;

-- Comments
COMMENT ON COLUMN withdrawal_steps.consolidation_phase IS 
    'Consolidation phase: 
     1 = Source wallet → Intermediate consolidation wallet (Phase 1)
     2 = Intermediate → Master cold wallet (Phase 2, executed 90-180 days later)';

COMMENT ON COLUMN withdrawal_steps.intermediate_destination IS 
    'Intermediate consolidation wallet address (Phase 1 only). 
     NULL for Phase 2 or if not using phased consolidation.';

COMMENT ON COLUMN withdrawal_steps.is_final_consolidation IS 
    'TRUE if this step transfers to master cold wallet (final consolidation).
     FALSE if transferring to intermediate wallet.';


-- ============================================================================
-- 4. Create phase2_transfer_queue table
-- ============================================================================

CREATE TABLE phase2_transfer_queue (
    id SERIAL PRIMARY KEY,
    consolidation_plan_id INTEGER REFERENCES consolidation_plans(id) ON DELETE CASCADE,
    intermediate_wallet_id INTEGER REFERENCES intermediate_consolidation_wallets(id) ON DELETE CASCADE,
    scheduled_at TIMESTAMPTZ NOT NULL,
    delay_from_previous_days INTEGER,  -- Staggered delay (7-14 days)
    amount_usdt NUMERIC(12, 2),
    master_destination VARCHAR(42) NOT NULL,
    status VARCHAR(50) DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'approved', 'executing', 'completed', 'failed')),
    executed_at TIMESTAMPTZ,
    txhash VARCHAR(66),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_phase2_queue_plan 
    ON phase2_transfer_queue(consolidation_plan_id);

CREATE INDEX idx_phase2_queue_status 
    ON phase2_transfer_queue(status);

CREATE INDEX idx_phase2_queue_scheduled 
    ON phase2_transfer_queue(scheduled_at);

-- Comments
COMMENT ON TABLE phase2_transfer_queue IS 
    'Queue for Phase 2 transfers (intermediates → master cold wallet).
     Transfers are staggered with 7-14 days delay between each (Gaussian distribution).
     CRITICAL: Long delays prevent on-chain clustering detection.';

COMMENT ON COLUMN phase2_transfer_queue.delay_from_previous_days IS 
    'Days to wait after previous Phase 2 transfer (Gaussian: mean=10, std=2, range 7-14).
     Creates temporal dispersion to avoid "burst withdrawal" pattern.';


-- ============================================================================
-- 5. Create analytics views
-- ============================================================================

CREATE OR REPLACE VIEW consolidation_progress AS
SELECT 
    cp.id AS plan_id,
    cp.airdrop_id,
    cp.status AS plan_status,
    cp.phase_1_start_date,
    cp.phase_2_start_date,
    COUNT(DISTINCT icw.id) AS total_intermediates,
    COUNT(DISTINCT icw.id) FILTER (WHERE icw.status = 'consolidated') AS phase1_completed,
    COUNT(DISTINCT icw.id) FILTER (WHERE icw.status = 'forwarded') AS phase2_completed,
    SUM(icw.consolidated_amount_usdt) AS total_phase1_amount_usdt,
    cp.master_cold_wallet
FROM consolidation_plans cp
LEFT JOIN intermediate_consolidation_wallets icw ON icw.id IN (
    SELECT intermediate_wallet_id FROM phase2_transfer_queue WHERE consolidation_plan_id = cp.id
)
GROUP BY cp.id, cp.airdrop_id, cp.status, cp.phase_1_start_date, 
         cp.phase_2_start_date, cp.master_cold_wallet;

COMMENT ON VIEW consolidation_progress IS 
    'Real-time progress monitoring for consolidation plans (Phase 1 and Phase 2)';


-- ============================================================================
-- 6. Create consolidation audit trail
-- ============================================================================

CREATE TABLE consolidation_audit_trail (
    id SERIAL PRIMARY KEY,
    consolidation_plan_id INTEGER REFERENCES consolidation_plans(id),
    event_type VARCHAR(50) NOT NULL CHECK (event_type IN (
        'plan_created', 'phase1_started', 'phase1_transfer', 'phase1_completed',
        'phase2_started', 'phase2_transfer', 'phase2_completed', 'cancelled'
    )),
    wallet_id INTEGER,  -- Source or intermediate wallet
    amount_usdt NUMERIC(12, 2),
    txhash VARCHAR(66),
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_consolidation_audit_plan 
    ON consolidation_audit_trail(consolidation_plan_id);

CREATE INDEX idx_consolidation_audit_event 
    ON consolidation_audit_trail(event_type);

CREATE INDEX idx_consolidation_audit_created 
    ON consolidation_audit_trail(created_at DESC);

COMMENT ON TABLE consolidation_audit_trail IS 
    'Complete audit trail for all consolidation operations (Phase 1 and Phase 2)';


-- ============================================================================
-- 7. Security constraints
-- ============================================================================

-- Prevent burn addresses in intermediate consolidation wallets
ALTER TABLE intermediate_consolidation_wallets
ADD CONSTRAINT check_not_burn_address
    CHECK (
        address NOT IN (
            '0x0000000000000000000000000000000000000000',
            '0x000000000000000000000000000000000000dead',
            '0xdead000000000000000042069420694206942069'
        )
    );

-- Prevent burn addresses in master cold wallet
ALTER TABLE consolidation_plans
ADD CONSTRAINT check_master_not_burn_address
    CHECK (
        master_cold_wallet NOT IN (
            '0x0000000000000000000000000000000000000000',
            '0x000000000000000000000000000000000000dead',
            '0xdead000000000000000042069420694206942069'
        )
    );


-- ============================================================================
-- 8. Helper function to validate consolidation cluster sizes
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_consolidation_clusters()
RETURNS TABLE (
    intermediate_wallet_address VARCHAR,
    source_wallet_count INTEGER,
    funding_chain_number INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        icw.address AS intermediate_wallet_address,
        array_length(icw.source_wallet_ids, 1) AS source_wallet_count,
        fc.chain_number AS funding_chain_number
    FROM intermediate_consolidation_wallets icw
    JOIN funding_chains fc ON icw.funding_chain_id = fc.id
    ORDER BY fc.chain_number;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_consolidation_clusters() IS 
    'Validates that consolidation clusters have variable sizes (not all same).
     Should return variety of source_wallet_count values (3-7), matching funding chain sizes.';


COMMIT;

-- ============================================================================
-- Verification queries (run after migration)
-- ============================================================================

-- Check 1: Tables created
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_name IN ('consolidation_plans', 'intermediate_consolidation_wallets', 
                     'phase2_transfer_queue', 'consolidation_audit_trail')
ORDER BY table_name;

-- Check 2: Columns added to withdrawal_steps
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'withdrawal_steps'
  AND column_name IN ('consolidation_phase', 'intermediate_destination', 'is_final_consolidation')
ORDER BY ordinal_position;

-- Check 3: Views created
SELECT table_name
FROM information_schema.views
WHERE table_name = 'consolidation_progress';

--Check 4: Indexes created
SELECT tablename, indexname
FROM pg_indexes
WHERE tablename IN ('consolidation_plans', 'intermediate_consolidation_wallets',
                    'phase2_transfer_queue', 'consolidation_audit_trail')
ORDER BY tablename, indexname;
