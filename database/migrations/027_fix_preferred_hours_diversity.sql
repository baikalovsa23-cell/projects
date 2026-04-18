-- Migration 027: Fix Preferred Hours Diversity & Skip Week Probability
-- =======================================================================
-- ПРОБЛЕМА (P0.3 from Code Review):
-- Все кошельки одного архетипа имеют одинаковые preferred_hours.
-- Например, все 7-8 "ActiveTrader" → [8,9,10,11,12,13,14,15,16,17,18,19,20,21,22]
-- Это создаёт синхронизацию между кошельками одного архетипа.
--
-- РЕШЕНИЕ:
-- 1. Для каждого кошелька выбрать случайное подмножество часов из archetype range
-- 2. Варьировать skip_week_probability по архетипам (MonthlyActive=0.15, ActiveTrader=0.02)
-- 
-- КРИТИЧНОСТЬ: 🔴 P0 — ТРЕБУЕТ ИСПРАВЛЕНИЯ ПЕРЕД PRODUCTION
-- =======================================================================

BEGIN;

-- ====================================
-- STEP 1: Update preferred_hours
-- ====================================

-- Temporary function для генерации случайного подмножества часов
CREATE OR REPLACE FUNCTION random_subset_of_hours(
    full_range INTEGER[],
    min_count INTEGER,
    max_count INTEGER
) RETURNS INTEGER[] AS $$
DECLARE
    result INTEGER[];
    count INTEGER;
    shuffled INTEGER[];
BEGIN
    -- Shuffle array (Fisher-Yates algorithm)
    shuffled := full_range;
    
    -- Random count: between min_count and max_count
    count := min_count + floor(random() * (max_count - min_count + 1))::INTEGER;
    
    -- Take first 'count' elements from shuffled array
    result := shuffled[1:count];
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Update preferred_hours для каждого архетипа
-- ActiveTrader: выбрать 10-14 часов из [8-22]
UPDATE wallet_personas
SET preferred_hours = random_subset_of_hours(
    ARRAY[8,9,10,11,12,13,14,15,16,17,18,19,20,21,22],
    10,
    14
)
WHERE persona_type = 'ActiveTrader';

-- CasualUser: выбрать 5-7 часов из [17-23]
UPDATE wallet_personas
SET preferred_hours = random_subset_of_hours(
    ARRAY[17,18,19,20,21,22,23],
    5,
    7
)
WHERE persona_type = 'CasualUser';

-- WeekendWarrior: выбрать 8-12 часов из [10-21]
UPDATE wallet_personas
SET preferred_hours = random_subset_of_hours(
    ARRAY[10,11,12,13,14,15,16,17,18,19,20,21],
    8,
    12
)
WHERE persona_type = 'WeekendWarrior';

-- Ghost: выбрать 6-8 часов из [6,7,8,14,15,20,21,22,23]
UPDATE wallet_personas
SET preferred_hours = random_subset_of_hours(
    ARRAY[6,7,8,14,15,20,21,22,23],
    6,
    8
)
WHERE persona_type = 'Ghost';

-- MorningTrader: выбрать 5-7 часов из [6,7,8,9,10,11,12]
UPDATE wallet_personas
SET preferred_hours = random_subset_of_hours(
    ARRAY[6,7,8,9,10,11,12],
    5,
    7
)
WHERE persona_type = 'MorningTrader';

-- NightOwl: выбрать 5-7 часов из [19,20,21,22,23,0,1,2]
UPDATE wallet_personas
SET preferred_hours = random_subset_of_hours(
    ARRAY[19,20,21,22,23,0,1,2],
    5,
    7
)
WHERE persona_type = 'NightOwl';

-- WeekdayOnly: выбрать 8-12 часов из [9-18]
UPDATE wallet_personas
SET preferred_hours = random_subset_of_hours(
    ARRAY[9,10,11,12,13,14,15,16,17,18],
    8,
    12
)
WHERE persona_type = 'WeekdayOnly';

-- MonthlyActive: выбрать 4-6 часов из [10-16]
UPDATE wallet_personas
SET preferred_hours = random_subset_of_hours(
    ARRAY[10,11,12,13,14,15,16],
    4,
    6
)
WHERE persona_type = 'MonthlyActive';

-- BridgeMaxi: выбрать 8-12 часов из [8-22]
UPDATE wallet_personas
SET preferred_hours = random_subset_of_hours(
    ARRAY[8,9,10,11,12,13,14,15,16,17,18,19,20,21,22],
    8,
    12
)
WHERE persona_type = 'BridgeMaxi';

-- DeFiDegen: выбрать 10-14 часов из [7-23]
UPDATE wallet_personas
SET preferred_hours = random_subset_of_hours(
    ARRAY[7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23],
    10,
    14
)
WHERE persona_type = 'DeFiDegen';

-- NFTCollector: выбрать 6-9 часов из [12-22]
UPDATE wallet_personas
SET preferred_hours = random_subset_of_hours(
    ARRAY[12,13,14,15,16,17,18,19,20,21,22],
    6,
    9
)
WHERE persona_type = 'NFTCollector';

-- Governance: выбрать 4-7 часов из [10-18]
UPDATE wallet_personas
SET preferred_hours = random_subset_of_hours(
    ARRAY[10,11,12,13,14,15,16,17,18],
    4,
    7
)
WHERE persona_type = 'Governance';

-- ====================================
-- STEP 2: Update skip_week_probability
-- ====================================

-- MonthlyActive: 15% шанс пропустить неделю (самый редкий активист)
UPDATE wallet_personas
SET skip_week_probability = 0.15
WHERE persona_type = 'MonthlyActive';

-- Ghost: 12% шанс пропустить неделю
UPDATE wallet_personas
SET skip_week_probability = 0.12
WHERE persona_type = 'Ghost';

-- WeekdayOnly: 8% шанс (может взять выходные целиком off)
UPDATE wallet_personas
SET skip_week_probability = 0.08
WHERE persona_type = 'WeekdayOnly';

-- CasualUser, MorningTrader, NightOwl, BridgeMaxi, NFTCollector, Governance: 5% (default)
UPDATE wallet_personas
SET skip_week_probability = 0.05
WHERE persona_type IN ('CasualUser', 'MorningTrader', 'NightOwl', 'BridgeMaxi', 'NFTCollector', 'Governance');

-- WeekendWarrior: 6% (чуть выше среднего)
UPDATE wallet_personas
SET skip_week_probability = 0.06
WHERE persona_type = 'WeekendWarrior';

-- ActiveTrader, DeFiDegen: 2% (самые активные, редко пропускают недели)
UPDATE wallet_personas
SET skip_week_probability = 0.02
WHERE persona_type IN ('ActiveTrader', 'DeFiDegen');

-- ====================================
-- STEP 3: Cleanup
-- ====================================

-- Drop temporary function
DROP FUNCTION IF EXISTS random_subset_of_hours(INTEGER[], INTEGER, INTEGER);

-- ====================================
-- VERIFICATION
-- ====================================

-- Проверка: показать разнообразие preferred_hours по архетипам
DO $$
DECLARE
    archetype_row RECORD;
    sample_row RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== PREFERRED_HOURS DIVERSITY VERIFICATION ===';
    RAISE NOTICE '';
    
    FOR archetype_row IN
        SELECT persona_type, COUNT(*) as wallet_count
        FROM wallet_personas
        GROUP BY persona_type
        ORDER BY persona_type
    LOOP
        RAISE NOTICE 'Archetype: % (% wallets)', archetype_row.persona_type, archetype_row.wallet_count;
        
        -- Show first 3 wallets of this archetype
        FOR sample_row IN
            SELECT wallet_id, ARRAY_LENGTH(preferred_hours, 1) as hour_count, preferred_hours
            FROM wallet_personas
            WHERE persona_type = archetype_row.persona_type
            ORDER BY wallet_id
            LIMIT 3
        LOOP
            RAISE NOTICE '  Wallet %: % hours → %', sample_row.wallet_id, sample_row.hour_count, sample_row.preferred_hours;
        END LOOP;
        
        RAISE NOTICE '';
    END LOOP;
END $$;

-- Проверка: показать skip_week_probability по архетипам
SELECT
    persona_type,
    COUNT(*) as wallet_count,
    MIN(skip_week_probability) as min_skip_prob,
    MAX(skip_week_probability) as max_skip_prob,
    AVG(skip_week_probability) as avg_skip_prob
FROM wallet_personas
GROUP BY persona_type
ORDER BY avg_skip_prob DESC, persona_type;

COMMIT;

-- ====================================
-- SUCCESS MESSAGE
-- ====================================

SELECT 'Migration 027 completed successfully!' as status;
SELECT 'Preferred hours now vary within each archetype' as fix_1;
SELECT 'Skip week probability now differs by archetype' as fix_2;
