-- Migration 015: Protocol Research Engine
-- Date: 2026-02-25
-- Author: Module 15 Implementation
-- Description: Creates tables and functions for semi-automated protocol research

-- ===========================================================================
-- 1. CREATE ENUM TYPE
-- ===========================================================================

CREATE TYPE research_status AS ENUM (
    'pending_approval',  -- LLM analyzed, waiting for human
    'approved',          -- Human approved, moved to protocols table
    'rejected',          -- Human rejected
    'auto_rejected',     -- Timeout after 7 days
    'duplicate'          -- Already in protocols or pending table
);

-- ===========================================================================
-- 2. CREATE TABLES
-- ===========================================================================

-- protocol_research_pending: Approval queue for LLM-discovered protocols awaiting human review
CREATE TABLE protocol_research_pending (
    id SERIAL PRIMARY KEY,
    
    -- Protocol details (from LLM analysis)
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100), -- 'DEX', 'Lending', 'Bridge', 'NFT Marketplace', etc.
    chains VARCHAR(100)[], -- ['base', 'arbitrum', 'optimism']
    website_url TEXT,
    twitter_url TEXT,
    discord_url TEXT,
    
    -- Airdrop indicators
    airdrop_score INTEGER NOT NULL CHECK (airdrop_score BETWEEN 0 AND 100),
    has_points_program BOOLEAN DEFAULT FALSE,
    points_program_url TEXT,
    has_token BOOLEAN DEFAULT FALSE, -- FALSE = airdrop potential
    
    -- TVL and metrics (from DefiLlama)
    current_tvl_usd DECIMAL(18, 2), -- Total Value Locked
    tvl_change_30d_pct DECIMAL(6, 2), -- % change in last 30 days
    launch_date DATE,
    
    -- LLM analysis output
    recommended_actions JSONB NOT NULL, -- ["SWAP", "LP", "STAKE"]
    reasoning TEXT NOT NULL, -- LLM explanation (2-3 sentences)
    raw_llm_response JSONB, -- Full JSON for debugging
    
    -- Approval workflow
    status research_status DEFAULT 'pending_approval',
    approved_by VARCHAR(100), -- Telegram username
    approved_at TIMESTAMPTZ,
    rejected_reason TEXT,
    rejected_at TIMESTAMPTZ,
    
    -- Source tracking
    discovered_from VARCHAR(100), -- 'crypto_news_api', 'defillama', 'rss_theblock'
    source_article_url TEXT,
    source_article_title TEXT,
    source_published_at TIMESTAMPTZ,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT unique_pending_protocol UNIQUE(name),
    CONSTRAINT chk_valid_urls CHECK (
        (website_url IS NULL OR website_url ~ '^https?://') AND
        (twitter_url IS NULL OR twitter_url ~ '^https?://(twitter\.com|x\.com)/') AND
        (discord_url IS NULL OR discord_url ~ '^https?://(discord\.gg|discord\.com)/')
    )
);

-- research_logs: Audit trail for research cycles (cost tracking, performance metrics)
CREATE TABLE research_logs (
    id SERIAL PRIMARY KEY,
    
    -- Research cycle metadata
    cycle_start_at TIMESTAMPTZ NOT NULL,
    cycle_end_at TIMESTAMPTZ,
    status VARCHAR(50) DEFAULT 'running', -- 'running', 'completed', 'failed'
    
    -- Statistics
    total_sources_checked INTEGER DEFAULT 0, -- Number of news sources queried
    total_candidates_found INTEGER DEFAULT 0, -- Raw protocols mentioned in news
    total_analyzed_by_llm INTEGER DEFAULT 0, -- Protocols sent to GPT-4
    total_added_to_pending INTEGER DEFAULT 0, -- High-scoring protocols (>=50)
    total_duplicates INTEGER DEFAULT 0, -- Already in protocols or pending
    total_rejected_low_score INTEGER DEFAULT 0, -- Score < 50
    
    -- Per-source breakdown (JSON)
    source_stats JSONB, -- {"crypto_news_api": {"candidates": 23, "analyzed": 5}}
    
    -- Cost tracking
    llm_api_calls INTEGER DEFAULT 0,
    llm_tokens_used INTEGER DEFAULT 0, -- Total tokens (input + output)
    estimated_cost_usd DECIMAL(6, 4) DEFAULT 0, -- e.g., 0.1250 = $0.125
    
    -- Error tracking
    errors_encountered INTEGER DEFAULT 0,
    error_details JSONB, -- [{"source": "defillama", "error": "timeout"}]
    
    -- Output
    summary_report TEXT, -- Human-readable summary for Telegram
    
    -- Auto-cleanup tracking
    protocols_auto_rejected INTEGER DEFAULT 0, -- Timed out after 7 days
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===========================================================================
-- 3. CREATE INDEXES
-- ===========================================================================

-- Indexes for protocol_research_pending
CREATE INDEX idx_research_pending_status ON protocol_research_pending(status);
CREATE INDEX idx_research_pending_score ON protocol_research_pending(airdrop_score DESC);
CREATE INDEX idx_research_pending_created ON protocol_research_pending(created_at DESC);
CREATE INDEX idx_research_pending_high_priority ON protocol_research_pending(airdrop_score DESC, status) 
    WHERE airdrop_score >= 80 AND status = 'pending_approval';

-- Indexes for research_logs
CREATE INDEX idx_research_logs_cycle ON research_logs(cycle_start_at DESC);
CREATE INDEX idx_research_logs_status ON research_logs(status);
CREATE INDEX idx_research_logs_cost ON research_logs(estimated_cost_usd DESC);

-- ===========================================================================
-- 4. HELPER FUNCTIONS
-- ===========================================================================

-- auto_reject_stale_protocols(): Auto-reject protocols pending approval for > 7 days
CREATE OR REPLACE FUNCTION auto_reject_stale_protocols()
RETURNS INTEGER AS $$
DECLARE
    rejected_count INTEGER;
BEGIN
    UPDATE protocol_research_pending
    SET 
        status = 'auto_rejected',
        rejected_reason = 'Auto-rejected: No action taken within 7 days',
        rejected_at = NOW(),
        updated_at = NOW()
    WHERE 
        status = 'pending_approval'
        AND created_at < NOW() - INTERVAL '7 days';
    
    GET DIAGNOSTICS rejected_count = ROW_COUNT;
    
    -- Log the cleanup
    IF rejected_count > 0 THEN
        INSERT INTO research_logs (
            cycle_start_at,
            cycle_end_at,
            status,
            protocols_auto_rejected,
            summary_report
        ) VALUES (
            NOW(),
            NOW(),
            'completed',
            rejected_count,
            FORMAT('Auto-rejected %s stale protocols (older than 7 days)', rejected_count)
        );
    END IF;
    
    RETURN rejected_count;
END;
$$ LANGUAGE plpgsql;

-- approve_protocol(pending_id, user): Move approved protocol from pending → production
CREATE OR REPLACE FUNCTION approve_protocol(
    pending_id INTEGER,
    approved_by_user VARCHAR(100)
)
RETURNS INTEGER AS $$
DECLARE
    protocol_data RECORD;
    new_protocol_id INTEGER;
BEGIN
    -- Fetch pending protocol
    SELECT * INTO protocol_data
    FROM protocol_research_pending
    WHERE id = pending_id AND status = 'pending_approval';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Protocol ID % not found or already processed', pending_id;
    END IF;
    
    -- Insert into protocols table
    INSERT INTO protocols (
        name,
        category,
        chains,
        has_points_program,
        points_program_url,
        priority_score,
        is_active,
        last_researched_at
    ) VALUES (
        protocol_data.name,
        protocol_data.category,
        protocol_data.chains,
        protocol_data.has_points_program,
        protocol_data.points_program_url,
        protocol_data.airdrop_score, -- airdrop_score maps to priority_score
        TRUE,
        NOW()
    )
    RETURNING id INTO new_protocol_id;
    
    -- Update pending status
    UPDATE protocol_research_pending
    SET 
        status = 'approved',
        approved_by = approved_by_user,
        approved_at = NOW(),
        updated_at = NOW()
    WHERE id = pending_id;
    
    RETURN new_protocol_id;
END;
$$ LANGUAGE plpgsql;

-- ===========================================================================
-- 5. TRIGGERS
-- ===========================================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_research_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_research_pending_timestamp
    BEFORE UPDATE ON protocol_research_pending
    FOR EACH ROW
    EXECUTE FUNCTION update_research_timestamp();

CREATE TRIGGER trigger_update_research_logs_timestamp
    BEFORE UPDATE ON research_logs
    FOR EACH ROW
    EXECUTE FUNCTION update_research_timestamp();

-- ===========================================================================
-- 6. COMMENTS
-- ===========================================================================

COMMENT ON TABLE protocol_research_pending IS 'LLM-discovered protocols awaiting human approval via Telegram';
COMMENT ON COLUMN protocol_research_pending.airdrop_score IS 'LLM-assigned probability (0-100): 80+ = high priority, 50-79 = medium, <50 = low/auto-reject';
COMMENT ON COLUMN protocol_research_pending.recommended_actions IS 'JSON array: ["SWAP", "LP", "STAKE"] - used to auto-create protocol_actions';
COMMENT ON COLUMN protocol_research_pending.reasoning IS 'LLM explanation shown in Telegram notification';

COMMENT ON TABLE research_logs IS 'Audit trail for weekly research cycles - tracks costs, performance, and errors';
COMMENT ON COLUMN research_logs.estimated_cost_usd IS 'OpenRouter API cost: ~$0.01-0.03 per protocol (GPT-4 Turbo)';
COMMENT ON COLUMN research_logs.summary_report IS 'Formatted summary sent to Telegram';

-- ===========================================================================
-- 7. SAMPLE DATA (for testing)
-- ===========================================================================

-- Insert test protocol (for Telegram approval workflow testing)
INSERT INTO protocol_research_pending (
    name,
    category,
    chains,
    website_url,
    twitter_url,
    airdrop_score,
    has_points_program,
    points_program_url,
    has_token,
    current_tvl_usd,
    tvl_change_30d_pct,
    recommended_actions,
    reasoning,
    discovered_from,
    source_article_title
) VALUES (
    'TestProtocol (Sample)',
    'DEX',
    ARRAY['base', 'arbitrum'],
    'https://testprotocol.xyz',
    'https://twitter.com/testprotocol',
    85,
    TRUE,
    'https://testprotocol.xyz/points',
    FALSE,
    25000000.00,
    120.50,
    '["SWAP", "LP"]'::jsonb,
    'TestProtocol raised $50M Series A led by a16z. Active points program similar to Blast. No token launched yet.',
    'manual_testing',
    'TestProtocol Raises $50M in Series A Funding'
);

-- ===========================================================================
-- 8. MIGRATION COMPLETE
-- ===========================================================================

-- Log migration completion
INSERT INTO research_logs (
    cycle_start_at,
    cycle_end_at,
    status,
    summary_report
) VALUES (
    NOW(),
    NOW(),
    'completed',
    'Migration 015: Protocol Research Engine tables created successfully'
);
