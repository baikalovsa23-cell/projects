-- ============================================================================
-- Migration 028: Wallet Warm-Up State Machine
-- ============================================================================
-- Добавляет поля для отслеживания состояния прогрева кошельков
-- Решает P1-5 из ACTION_ITEMS_FIXES.md
-- 
-- Цель: Постепенный прогрев новых кошельков перед основной активностью
-- 
-- Этапы прогрева:
-- 1. inactive → кошелёк создан, но еще не получил funding
-- 2. warming_up → первая транзакция выполнена, идёт прогрев (3+ TX)
-- 3. active → прогрев завершён, можно использовать полный набор действий
-- 
-- Author: Airdrop Farming System v4.0
-- Created: 2026-03-01
-- ============================================================================

BEGIN;

-- Добавить поля warm-up состояния в таблицу wallets
ALTER TABLE wallets
ADD COLUMN warmup_status VARCHAR(20) DEFAULT 'inactive' CHECK (warmup_status IN ('inactive', 'warming_up', 'active')),
ADD COLUMN first_tx_at TIMESTAMP,
ADD COLUMN warmup_completed_at TIMESTAMP;

-- Индекс для быстрого поиска кошельков по статусу прогрева
CREATE INDEX idx_wallets_warmup_status ON wallets(warmup_status);

-- Комментарии
COMMENT ON COLUMN wallets.warmup_status IS 'Wallet warm-up state: inactive → warming_up → active';
COMMENT ON COLUMN wallets.first_tx_at IS 'Timestamp of first transaction after funding';
COMMENT ON COLUMN wallets.warmup_completed_at IS 'Timestamp when warm-up phase completed (3+ successful transactions)';

-- Установить существующие кошельки в состояние 'active' если у них уже есть транзакции
UPDATE wallets
SET warmup_status = 'active',
    warmup_completed_at = NOW()
WHERE id IN (
    SELECT DISTINCT wallet_id 
    FROM activity_log 
    WHERE status = 'success'
);

-- Логирование миграции
INSERT INTO system_events (event_type, severity, message, metadata, created_at)
VALUES (
    'MIGRATION_COMPLETED',
    'info',
    'Migration 028: Wallet warm-up state machine installed',
    '{"migration": "028_add_warmup_state.sql", "wallets_updated": "existing wallets set to active"}'::jsonb,
    NOW()
);

COMMIT;

-- ============================================================================
-- Verification Queries
-- ============================================================================
-- Проверить распределение статусов:
-- SELECT warmup_status, COUNT(*) FROM wallets GROUP BY warmup_status;
--
-- Проверить кошельки в прогреве:
-- SELECT id, address, warmup_status, first_tx_at, warmup_completed_at
-- FROM wallets
-- WHERE warmup_status = 'warming_up';
