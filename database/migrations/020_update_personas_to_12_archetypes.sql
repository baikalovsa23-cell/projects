-- Migration 020: Update personas to 12 archetypes
-- Part 1: Add new archetype values to persona_type ENUM
-- NOTE: Must be in separate transaction from usage due to PostgreSQL ENUM constraint

-- Add 8 new archetype values to the persona_type ENUM
ALTER TYPE persona_type ADD VALUE IF NOT EXISTS 'MorningTrader';
ALTER TYPE persona_type ADD VALUE IF NOT EXISTS 'NightOwl';
ALTER TYPE persona_type ADD VALUE IF NOT EXISTS 'WeekdayOnly';
ALTER TYPE persona_type ADD VALUE IF NOT EXISTS 'MonthlyActive';
ALTER TYPE persona_type ADD VALUE IF NOT EXISTS 'BridgeMaxi';
ALTER TYPE persona_type ADD VALUE IF NOT EXISTS 'DeFiDegen';
ALTER TYPE persona_type ADD VALUE IF NOT EXISTS 'NFTCollector';
ALTER TYPE persona_type ADD VALUE IF NOT EXISTS 'Governance';

-- Verification: Show all persona_type ENUM values
SELECT 'Available persona types:' as info;
SELECT unnest(enum_range(NULL::persona_type)) as persona_type;
