-- ============================================================================
-- OpenClaw Integration — Database Migration v2.0
-- ============================================================================
-- Created: 2026-02-25
-- Description: Add 8 tables for OpenClaw browser automation module
-- Target: Tier A wallets only (18 wallets)
-- Dependencies: 001_initial.sql (must be run first)
-- ============================================================================

-- ============================================================================
-- SECTION 1: OPENCLAW CORE TABLES
-- ============================================================================

-- OpenClaw task queue (CRITICAL — missing from original plan)
CREATE TABLE openclaw_tasks (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    task_type VARCHAR(100) NOT NULL,  -- 'gitcoin_passport', 'poap_claim', 'ens_register', 'snapshot_vote', 'lens_post'
    task_params JSONB NOT NULL,       -- Task-specific config (URLs, target stamps, etc.)
    status openclaw_task_status NOT NULL DEFAULT 'queued',
    assigned_worker_id INTEGER REFERENCES worker_nodes(worker_id),
    priority INTEGER DEFAULT 5,       -- 1 (highest) to 10 (lowest)
    max_retries INTEGER DEFAULT 3,
    retry_count INTEGER DEFAULT 0,
    scheduled_at TIMESTAMPTZ NOT NULL,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE openclaw_tasks IS 'OpenClaw task queue — managed by Master, executed by Workers';
COMMENT ON COLUMN openclaw_tasks.task_type IS 'Task type: gitcoin_passport, poap_claim, ens_register, snapshot_vote, lens_post';
COMMENT ON COLUMN openclaw_tasks.task_params IS 'JSONB config: {"target_stamps": ["github", "twitter"], "event_id": 12345, ...}';
COMMENT ON COLUMN openclaw_tasks.priority IS 'Priority: 1 (highest) to 10 (lowest) — Gitcoin/ENS are priority 1';
COMMENT ON COLUMN openclaw_tasks.assigned_worker_id IS 'Worker assignment: NULL (unassigned), 1 (NL), 2-3 (IS)';

-- OpenClaw browser profiles (persistent sessions per wallet)
CREATE TABLE openclaw_profiles (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    browser_fingerprint JSONB,  -- User-Agent, screen resolution, fonts, canvas, WebGL, etc.
    cookies JSONB,              -- Encrypted cookies from GitHub, Twitter, Discord OAuth
    local_storage JSONB,        -- localStorage state (Gitcoin Passport, etc.)
    session_storage JSONB,      -- sessionStorage state
    indexed_db_state JSONB,     -- IndexedDB state (optional, for complex apps)
    profile_path TEXT,          -- File path: /opt/farming/openclaw/profiles/wallet_{id}/
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(wallet_id)
);

COMMENT ON TABLE openclaw_profiles IS 'Browser profiles for 18 Tier A wallets — persistent sessions';
COMMENT ON COLUMN openclaw_profiles.browser_fingerprint IS 'Unique fingerprint per wallet (canvas, WebGL, fonts, timezone)';
COMMENT ON COLUMN openclaw_profiles.cookies IS 'OAuth cookies (GitHub, Twitter, Discord) — stored as encrypted JSONB';
COMMENT ON COLUMN openclaw_profiles.profile_path IS 'Path to browser profile directory on Worker node';

-- OpenClaw task execution history (audit trail)
CREATE TABLE openclaw_task_history (
    id SERIAL PRIMARY KEY,
    task_id INTEGER NOT NULL REFERENCES openclaw_tasks(id),
    attempt_number INTEGER NOT NULL DEFAULT 1,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    duration_seconds INTEGER,
    screenshot_path TEXT,         -- Path to screenshot: /opt/farming/openclaw/screenshots/YYYY-MM-DD/wallet_{id}_{task}_{timestamp}.png
    error_message TEXT,
    stack_trace TEXT,
    metadata JSONB,               -- Task-specific data (tx_hash, claim_id, stamp_score, etc.)
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE openclaw_task_history IS 'Task execution history — one record per retry attempt';
COMMENT ON COLUMN openclaw_task_history.attempt_number IS 'Retry attempt: 1 (first try), 2-3 (retries)';
COMMENT ON COLUMN openclaw_task_history.screenshot_path IS 'Screenshot for audit trail — stored for 90 days';
COMMENT ON COLUMN openclaw_task_history.metadata IS 'JSONB: {"tx_hash": "0x...", "stamp_score": 15, "poap_token_id": 123456, ...}';

-- ============================================================================
-- SECTION 2: REPUTATION TRACKING TABLES
-- ============================================================================

-- Gitcoin Passport stamps tracking
CREATE TABLE gitcoin_stamps (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    stamp_type VARCHAR(100) NOT NULL,  -- 'github', 'twitter', 'discord', 'google', 'linkedin', 'brightid', etc.
    stamp_id TEXT,                     -- Stamp ID from Gitcoin API
    earned_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    score_contribution DECIMAL(5, 2), -- Score value (e.g., 2.50 for GitHub)
    metadata JSONB,                   -- Additional stamp data (username, profile URL, etc.)
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(wallet_id, stamp_type)
);

COMMENT ON TABLE gitcoin_stamps IS 'Gitcoin Passport stamps — target: 5+ stamps per Tier A wallet';
COMMENT ON COLUMN gitcoin_stamps.stamp_type IS 'Stamp type: github, twitter, discord, google, linkedin, brightid, ens, poh, etc.';
COMMENT ON COLUMN gitcoin_stamps.score_contribution IS 'Score contribution (ranges 0.5-10 depending on stamp)';
COMMENT ON COLUMN gitcoin_stamps.metadata IS 'JSONB: {"github_username": "user123", "followers": 50, ...}';

-- POAP tokens tracking  
CREATE TABLE poap_tokens (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    event_id INTEGER NOT NULL,
    event_name TEXT NOT NULL,
    token_id TEXT,                    -- POAP token ID (minted NFT)
    claimed_at TIMESTAMPTZ,
    metadata JSONB,                   -- Image URL, description, event date, etc.
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(wallet_id, event_id)
);

COMMENT ON TABLE poap_tokens IS 'POAP tokens — target: 3-5 POAPs per Tier A wallet';
COMMENT ON COLUMN poap_tokens.event_id IS 'POAP event ID (from POAP API)';
COMMENT ON COLUMN poap_tokens.token_id IS 'POAP token ID after minting (ERC-721)';
COMMENT ON COLUMN poap_tokens.metadata IS 'JSONB: {"image_url": "...", "description": "...", "event_date": "2026-02-15", ...}';

-- ENS names/subdomains
CREATE TABLE ens_names (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    ens_name TEXT NOT NULL,           -- 'user123.cb.id' or 'wallet42.base.eth'
    parent_domain TEXT,               -- 'cb.id', 'base.eth', 'myproject.eth'
    registration_tx_hash TEXT,
    registered_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    cost_eth DECIMAL(18, 8),         -- Cost in ETH (may be 0 for FREE subdomains)
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(wallet_id, ens_name)
);

COMMENT ON TABLE ens_names IS 'ENS names/subdomains — target: 1 per Tier A wallet (prefer FREE: cb.id, base.eth)';
COMMENT ON COLUMN ens_names.ens_name IS 'Full ENS name: user.cb.id, wallet42.base.eth, name.myproject.eth';
COMMENT ON COLUMN ens_names.parent_domain IS 'Parent domain: cb.id (FREE), base.eth (FREE), myproject.eth ($5-10)';
COMMENT ON COLUMN ens_names.cost_eth IS 'Registration cost in ETH — 0 for FREE options, 0.003-0.01 for premium';

-- Snapshot votes tracking
CREATE TABLE snapshot_votes (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    proposal_id TEXT NOT NULL,
    space TEXT NOT NULL,             -- 'aave.eth', 'uniswap.eth', 'gitcoin.eth', etc.
    choice TEXT,                     -- 'for', 'against', 'abstain', or custom (JSONB for multi-choice)
    voting_power DECIMAL(18, 8),     -- Voting power at time of vote
    voted_at TIMESTAMPTZ,
    metadata JSONB,                  -- Proposal title, choices, reason (optional)
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(wallet_id, proposal_id)
);

COMMENT ON TABLE snapshot_votes IS 'Snapshot votes — target: 5-10 votes per Tier A wallet';
COMMENT ON COLUMN snapshot_votes.space IS 'Snapshot space: aave.eth, uniswap.eth, gitcoin.eth, etc.';
COMMENT ON COLUMN snapshot_votes.choice IS 'Vote choice: for/against/abstain or custom (multi-choice proposals)';
COMMENT ON COLUMN snapshot_votes.voting_power IS 'Voting power (based on token balance at snapshot block)';
COMMENT ON COLUMN snapshot_votes.metadata IS 'JSONB: {"title": "Proposal Title", "choices": ["Yes", "No"], "reason": "..."}';

-- Lens Protocol profile tracking
CREATE TABLE lens_profiles (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    profile_id TEXT,                 -- Lens profile ID (e.g., '0x01abcd')
    handle TEXT,                     -- user123.lens
    created_tx_hash TEXT,
    follower_count INTEGER DEFAULT 0,
    following_count INTEGER DEFAULT 0,
    publication_count INTEGER DEFAULT 0,  -- Posts + comments + mirrors
    last_activity_at TIMESTAMPTZ,
    metadata JSONB,                  -- Bio, avatar URL, cover image, etc.
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(wallet_id)
);

COMMENT ON TABLE lens_profiles IS 'Lens Protocol profiles — target: 1 profile + 2-3 posts per Tier A wallet';
COMMENT ON COLUMN lens_profiles.profile_id IS 'Lens profile ID (hex string)';
COMMENT ON COLUMN lens_profiles.handle IS 'Lens handle: user123.lens';
COMMENT ON COLUMN lens_profiles.publication_count IS 'Total publications: posts + comments + mirrors';
COMMENT ON COLUMN lens_profiles.metadata IS 'JSONB: {"bio": "...", "avatar_url": "...", "cover_image_url": "..."}';

-- ============================================================================
-- SECTION 3: INDEXES
-- ============================================================================

-- openclaw_tasks indexes
CREATE INDEX idx_openclaw_tasks_status ON openclaw_tasks(status);
CREATE INDEX idx_openclaw_tasks_wallet ON openclaw_tasks(wallet_id);
CREATE INDEX idx_openclaw_tasks_scheduled ON openclaw_tasks(scheduled_at);
CREATE INDEX idx_openclaw_tasks_worker ON openclaw_tasks(assigned_worker_id);
CREATE INDEX idx_openclaw_tasks_created ON openclaw_tasks(created_at);

-- openclaw_task_history indexes
CREATE INDEX idx_openclaw_task_history_task ON openclaw_task_history(task_id);
CREATE INDEX idx_openclaw_task_history_completed ON openclaw_task_history(completed_at);

-- Reputation tables indexes
CREATE INDEX idx_gitcoin_stamps_wallet ON gitcoin_stamps(wallet_id);
CREATE INDEX idx_gitcoin_stamps_earned ON gitcoin_stamps(earned_at);

CREATE INDEX idx_poap_tokens_wallet ON poap_tokens(wallet_id);
CREATE INDEX idx_poap_tokens_claimed ON poap_tokens(claimed_at);

CREATE INDEX idx_ens_names_wallet ON ens_names(wallet_id);
CREATE INDEX idx_ens_names_registered ON ens_names(registered_at);

CREATE INDEX idx_snapshot_votes_wallet ON snapshot_votes(wallet_id);
CREATE INDEX idx_snapshot_votes_space ON snapshot_votes(space);
CREATE INDEX idx_snapshot_votes_voted ON snapshot_votes(voted_at);

CREATE INDEX idx_lens_profiles_wallet ON lens_profiles(wallet_id);
CREATE INDEX idx_lens_profiles_activity ON lens_profiles(last_activity_at);

-- ============================================================================
-- SECTION 4: TRIGGERS (Auto-update timestamps)
-- ============================================================================

-- Auto-update updated_at timestamp on openclaw_tasks
CREATE OR REPLACE FUNCTION update_openclaw_tasks_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_openclaw_tasks_updated_at
BEFORE UPDATE ON openclaw_tasks
FOR EACH ROW
EXECUTE FUNCTION update_openclaw_tasks_updated_at();

-- Auto-update updated_at timestamp on openclaw_profiles
CREATE OR REPLACE FUNCTION update_openclaw_profiles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_openclaw_profiles_updated_at
BEFORE UPDATE ON openclaw_profiles
FOR EACH ROW
EXECUTE FUNCTION update_openclaw_profiles_updated_at();

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

-- Verify tables created:
-- SELECT table_name FROM information_schema.tables 
-- WHERE table_schema = 'public' 
--   AND (table_name LIKE 'openclaw%' 
--        OR table_name IN ('gitcoin_stamps', 'poap_tokens', 'ens_names', 'snapshot_votes', 'lens_profiles'));

-- Expected output (8 tables):
-- openclaw_tasks
-- openclaw_profiles
-- openclaw_task_history
-- gitcoin_stamps
-- poap_tokens
-- ens_names
-- snapshot_votes
-- lens_profiles
