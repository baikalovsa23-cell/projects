-- Migration 021: Redistribute personas across 12 archetypes
-- Distribute 90 existing personas evenly across 12 archetype types
-- Each archetype gets 7-8 wallets for maximum anti-Sybil diversity

BEGIN;

-- Temporary table for archetype mapping
CREATE TEMP TABLE archetype_mapping AS
SELECT 
    wallet_id,
    ROW_NUMBER() OVER (ORDER BY wallet_id) AS row_num,
    CASE 
        -- Each archetype gets ~7-8 wallets (90 ÷ 12 = 7.5)
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 = 0 THEN 'ActiveTrader'::persona_type
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 = 1 THEN 'CasualUser'::persona_type
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 = 2 THEN 'WeekendWarrior'::persona_type
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 = 3 THEN 'Ghost'::persona_type
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 = 4 THEN 'MorningTrader'::persona_type
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 = 5 THEN 'NightOwl'::persona_type
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 = 6 THEN 'WeekdayOnly'::persona_type
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 = 7 THEN 'MonthlyActive'::persona_type
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 = 8 THEN 'BridgeMaxi'::persona_type
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 = 9 THEN 'DeFiDegen'::persona_type
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 = 10 THEN 'NFTCollector'::persona_type
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 = 11 THEN 'Governance'::persona_type
    END AS new_archetype,
    CASE 
        -- TX frequency mean (adjusted for archetype, will be refined per tier later)
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 = 7 THEN 1.0  -- MonthlyActive
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 IN (0, 9) THEN 4.0  -- ActiveTrader, DeFiDegen
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 IN (1, 4, 5, 8) THEN 2.5  -- CasualUser, MorningTrader, NightOwl, BridgeMaxi
        ELSE 1.5  -- Low frequency archetypes
    END AS base_tx_mean,
    CASE 
        -- TX frequency stddev
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 = 7 THEN 0.3  -- MonthlyActive
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 IN (0, 9) THEN 1.0  -- ActiveTrader, DeFiDegen
        WHEN (ROW_NUMBER() OVER (ORDER BY wallet_id) - 1) % 12 IN (1, 4, 5, 8) THEN 0.8  -- Medium archetypes
        ELSE 0.5  -- Low frequency archetypes
    END AS base_tx_stddev
FROM wallet_personas;

-- Update personas with new archetypes and frequencies
UPDATE wallet_personas wp
SET 
    persona_type = am.new_archetype,
    tx_per_week_mean = am.base_tx_mean,
    tx_per_week_stddev = am.base_tx_stddev
FROM archetype_mapping am
WHERE wp.wallet_id = am.wallet_id;

-- Log the distribution
DO $$
DECLARE
    archetype_count RECORD;
    total_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO total_count FROM wallet_personas;
    RAISE NOTICE '=== Persona Distribution After Update ===';
    RAISE NOTICE 'Total wallets: %', total_count;
    RAISE NOTICE '';
    FOR archetype_count IN 
        SELECT persona_type, COUNT(*) as count 
        FROM wallet_personas 
        GROUP BY persona_type 
        ORDER BY persona_type
    LOOP
        RAISE NOTICE '%-15s : %2s wallets', archetype_count.persona_type, archetype_count.count;
    END LOOP;
END $$;

COMMIT;

-- Final verification query
SELECT 
    persona_type,
    COUNT(*) as wallet_count,
    ROUND(AVG(tx_per_week_mean)::numeric, 2) as avg_tx_mean,
    ROUND(AVG(tx_per_week_stddev)::numeric, 2) as avg_tx_stddev
FROM wallet_personas
GROUP BY persona_type
ORDER BY persona_type;
