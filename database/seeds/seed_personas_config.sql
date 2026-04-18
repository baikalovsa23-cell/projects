-- ============================================================================
-- Seed: Personas Config (12 Archetypes)
-- ============================================================================
-- 12 archetype templates for wallet persona generation.
-- Used by wallets/personas.py to create unique behavioral profiles.
-- 
-- Run AFTER schema.sql:
--   psql -U farming_user -d farming_db -f database/seeds/seed_personas_config.sql
--
-- Original 4 archetypes (2026-02-24):
--   ActiveTrader, CasualUser, WeekendWarrior, Ghost
-- 
-- Extended 8 archetypes (2026-02-27):
--   MorningTrader, NightOwl, WeekdayOnly, MonthlyActive,
--   BridgeMaxi, DeFiDegen, NFTCollector, Governance
-- ============================================================================

-- Clear existing data (for idempotency)
-- Using DELETE instead of TRUNCATE to avoid sequence permission issues
DELETE FROM personas_config;

-- Insert all 12 archetypes
INSERT INTO personas_config (persona_type, description, default_tx_per_week_mean, default_tx_per_week_stddev, default_preferred_hours_range) VALUES

-- Original 4 archetypes (high-level behavioral patterns)
('ActiveTrader', 'High activity: daytime and evening', 4.5, 1.2, ARRAY[8,9,10,11,12,13,14,15,16,17,18,19,20,21,22]),
('CasualUser', 'Medium activity: primarily evenings', 2.5, 0.8, ARRAY[17,18,19,20,21,22,23]),
('WeekendWarrior', 'Low weekday, high weekend activity', 2.0, 0.7, ARRAY[10,11,12,13,14,15,16,17,18,19,20,21]),
('Ghost', 'Minimal activity: sporadic timing', 1.0, 0.5, ARRAY[6,7,8,14,15,20,21,22,23]),

-- Extended 8 archetypes (specialized behavioral patterns)
('MorningTrader', 'Active in morning hours (6-11 UTC)', 3.5, 1.0, ARRAY[6,7,8,9,10,11]),
('NightOwl', 'Active in late evening/night (21-02 UTC)', 3.0, 0.9, ARRAY[21,22,23,0,1,2]),
('WeekdayOnly', 'Only active Monday-Friday', 2.5, 0.8, ARRAY[9,10,11,12,13,14,15,16,17,18]),
('MonthlyActive', 'Very low frequency, 1-2 TX per month', 0.5, 0.3, ARRAY[10,11,12,13,14,15,16,17,18]),
('BridgeMaxi', 'Focus on bridge and cross-chain activity', 2.5, 0.8, ARRAY[10,11,12,13,14,15,16,17,18,19,20]),
('DeFiDegen', 'High DeFi activity, complex transactions', 4.0, 1.1, ARRAY[8,9,10,11,12,13,14,15,16,17,18,19,20,21,22]),
('NFTCollector', 'Focus on NFT mints and transfers', 2.0, 0.7, ARRAY[12,13,14,15,16,17,18,19,20]),
('Governance', 'Focus on governance votes and delegation', 1.5, 0.6, ARRAY[10,11,12,13,14,15,16,17,18,19,20]);

-- Verification
SELECT 'personas_config seeded:' AS status, COUNT(*) AS count FROM personas_config;
SELECT * FROM personas_config ORDER BY id;