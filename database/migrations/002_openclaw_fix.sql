-- ============================================================================
-- OpenClaw Integration — Migration Fix/Patch
-- ============================================================================
-- Created: 2026-02-25
-- Description: Add missing columns to openclaw_tasks table
-- Issue: Table exists but missing priority and assigned_worker_id columns
-- ============================================================================

-- Add missing columns to openclaw_tasks table
ALTER TABLE openclaw_tasks ADD COLUMN IF NOT EXISTS priority INTEGER DEFAULT 5;
ALTER TABLE openclaw_tasks ADD COLUMN IF NOT EXISTS assigned_worker_id INTEGER REFERENCES worker_nodes(worker_id);

COMMENT ON COLUMN openclaw_tasks.priority IS 'Priority: 1 (highest) to 10 (lowest) — Gitcoin/ENS are priority 1';
COMMENT ON COLUMN openclaw_tasks.assigned_worker_id IS 'Worker assignment: NULL (unassigned), 1 (NL), 2-3 (IS)';

-- Add missing indexes
CREATE INDEX IF NOT EXISTS idx_openclaw_tasks_worker ON openclaw_tasks(assigned_worker_id);
CREATE INDEX IF NOT EXISTS idx_openclaw_tasks_created ON openclaw_tasks(created_at);

-- Verify all tables exist
DO $$
BEGIN
    -- Check openclaw_profiles
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'openclaw_profiles') THEN
        RAISE EXCEPTION 'Table openclaw_profiles does not exist';
    END IF;
    
    -- Check gitcoin_stamps
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'gitcoin_stamps') THEN
        RAISE EXCEPTION 'Table gitcoin_stamps does not exist';
    END IF;
    
    -- Check poap_tokens
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'poap_tokens') THEN
        RAISE EXCEPTION 'Table poap_tokens does not exist';
    END IF;
    
    -- Check ens_names
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'ens_names') THEN
        RAISE EXCEPTION 'Table ens_names does not exist';
    END IF;
    
    -- Check snapshot_votes
    IF NOT EXISTS (SELECT 1 from information_schema.tables WHERE table_name = 'snapshot_votes') THEN
        RAISE EXCEPTION 'Table snapshot_votes does not exist';
    END IF;
    
    -- Check lens_profiles
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'lens_profiles') THEN
        RAISE EXCEPTION 'Table lens_profiles does not exist';
    END IF;
    
    RAISE NOTICE 'All OpenClaw tables verified successfully';
END $$;

-- List all OpenClaw tables
SELECT 
    table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE columns.table_name = tables.table_name) AS column_count
FROM information_schema.tables
WHERE table_schema = 'public' 
  AND (table_name LIKE 'openclaw%' 
       OR table_name IN ('gitcoin_stamps', 'poap_tokens', 'ens_names', 'snapshot_votes', 'lens_profiles'))
ORDER BY table_name;
