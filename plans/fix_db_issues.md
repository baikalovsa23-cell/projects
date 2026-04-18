# План исправления проблем БД v4.0

**Сервер:** 82.40.60.131 (Netherlands)  
**База данных:** farming_db  
**Пользователь:** farming_user  
**Пароль:** U5e8xXLTX7zm0v5KDu2oVsJuvdW478

---

## Выявленные проблемы

| # | Проблема | Статус | Решение |
|---|----------|--------|---------|
| 1 | `discovery_failures` для Unichain/MegaETH | ❌ | Добавить chain_aliases |
| 2 | `worker_nodes` = 0 строк | ❌ | INSERT 3 воркера |
| 3 | `safety_gates` отсутствует | ❌ | CREATE TABLE + INSERT |

---

## Инструкция по выполнению

### Шаг 1: Подключение к серверу

```bash
ssh root@82.40.60.131
# Пароль: yIFdCq9812%
```

### Шаг 2: Подключение к PostgreSQL

```bash
psql -U farming_user -d farming_db -h 127.0.0.1
# Пароль: U5e8xXLTX7zm0v5KDu2oVsJuvdW478
```

### Шаг 3: Выполнить SQL-команды

```sql
-- ============================================================================
-- ИСПРАВЛЕНИЕ 1: Добавить chain_aliases для Unichain и MegaETH
-- ============================================================================

-- Unichain (chain_id = 130)
INSERT INTO chain_aliases (chain_id, alias, source) VALUES
    (130, 'unichain', 'manual'),
    (130, 'uni', 'manual'),
    (130, 'unichain-mainnet', 'manual'),
    (130, 'uni-chain', 'manual')
ON CONFLICT (alias) DO UPDATE SET last_seen = NOW();

-- MegaETH (chain_id = 420420 - тестнет, может измениться для mainnet)
INSERT INTO chain_aliases (chain_id, alias, source) VALUES
    (420420, 'megaeth', 'manual'),
    (420420, 'mega', 'manual'),
    (420420, 'megaeth-mainnet', 'manual'),
    (420420, 'mega-eth', 'manual')
ON CONFLICT (alias) DO UPDATE SET last_seen = NOW();

-- Добавить RPC endpoints для новых сетей (если ещё не существуют)
INSERT INTO chain_rpc_endpoints (chain, chain_id, url, priority, is_active, is_l2, network_type, gas_multiplier)
VALUES 
    ('unichain', 130, 'https://mainnet.unichain.org', 1, TRUE, TRUE, 'l2', 5.0),
    ('megaeth', 420420, 'https://rpc.megaeth.com', 1, TRUE, TRUE, 'l2', 5.0)
ON CONFLICT (chain_id, url) DO NOTHING;

-- ============================================================================
-- ИСПРАВЛЕНИЕ 2: Добавить worker_nodes (3 воркера)
-- ============================================================================

INSERT INTO worker_nodes (worker_id, hostname, ip_address, location, timezone, utc_offset, status) VALUES
    (1, 'worker1-nl', '10.0.1.1', 'Amsterdam, NL', 'Europe/Amsterdam', 1, 'active'),
    (2, 'worker2-is', '10.0.2.1', 'Reykjavik, IS', 'Atlantic/Reykjavik', 0, 'active'),
    (3, 'worker3-is', '10.0.2.2', 'Reykjavik, IS', 'Atlantic/Reykjavik', 0, 'active')
ON CONFLICT (worker_id) DO UPDATE SET 
    hostname = EXCLUDED.hostname,
    ip_address = EXCLUDED.ip_address,
    location = EXCLUDED.location,
    timezone = EXCLUDED.timezone,
    utc_offset = EXCLUDED.utc_offset,
    status = EXCLUDED.status;

-- ============================================================================
-- ИСПРАВЛЕНИЕ 3: Создать таблицу safety_gates (если не существует)
-- ============================================================================

CREATE TABLE IF NOT EXISTS safety_gates (
    id SERIAL PRIMARY KEY,
    gate_name VARCHAR(50) UNIQUE NOT NULL,
    is_open BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Добавить стандартные safety gates
INSERT INTO safety_gates (gate_name, is_open) VALUES
    ('mainnet_execution', FALSE),
    ('dry_run_validation', FALSE),
    ('funding_enabled', FALSE),
    ('withdrawal_enabled', FALSE)
ON CONFLICT (gate_name) DO NOTHING;

-- ============================================================================
-- ВЕРИФИКАЦИЯ ИСПРАВЛЕНИЙ
-- ============================================================================

-- Проверить chain_aliases
SELECT 'chain_aliases' as table_name, COUNT(*) as count FROM chain_aliases
UNION ALL
SELECT 'worker_nodes', COUNT(*) FROM worker_nodes
UNION ALL
SELECT 'safety_gates', COUNT(*) FROM safety_gates
UNION ALL
SELECT 'chain_rpc_endpoints', COUNT(*) FROM chain_rpc_endpoints;

-- Проверить discovery_failures (должно быть пусто или содержать только реальные ошибки)
SELECT network_name, sources_checked, error_message, created_at 
FROM discovery_failures 
WHERE resolved = FALSE
ORDER BY created_at DESC;

-- Проверить worker_nodes
SELECT worker_id, hostname, location, timezone, status FROM worker_nodes ORDER BY worker_id;

-- Проверить safety_gates
SELECT gate_name, is_open, updated_at FROM safety_gates;
```

---

## Альтернативный способ: Выполнить через psql -c

```bash
# Выполнить одной командой
psql -U farming_user -d farming_db -h 127.0.0.1 << 'EOF'
-- Вставить SQL из шага 3 выше
EOF
```

---

## Ожидаемый результат

После выполнения:

| Таблица | Ожидаемое количество |
|---------|---------------------|
| chain_aliases | ≥ 25 записей |
| worker_nodes | 3 записи |
| safety_gates | 4 записи |
| chain_rpc_endpoints | ≥ 11 записей |

---

## Примечания

### Unichain
- **Chain ID:** 130
- **Launch:** Декабрь 2024
- **RPC:** https://mainnet.unichain.org
- **L2 на базе OP Stack**

### MegaETH
- **Chain ID:** 420420 (тестнет), mainnet ID может отличаться
- **Status:** В разработке, mainnet ожидается в 2025
- **RPC:** Проверить актуальный на https://megaeth.com

### Worker Nodes
- Worker 1: Netherlands (Amsterdam) - UTC+1
- Worker 2-3: Iceland (Reykjavik) - UTC+0
- IP-адреса должны соответствовать реальным серверам

---

## Риски детекции

⚠️ **Важно:** При добавлении новых сетей убедитесь, что:

1. **RPC endpoints валидны** - выполните health check перед регистрацией
2. **Chain ID актуален** - проверьте на chainid.network
3. **Gas multiplier корректен** - L2 сети используют 5.0x

---

## Связанные файлы

- [`database/schema.sql`](../database/schema.sql) - Основная схема БД
- [`database/migrations/035_chain_aliases_discovery.sql`](../database/migrations/035_chain_aliases_discovery.sql) - Миграция chain_aliases
- [`database/migrations/037_missing_tables.sql`](../database/migrations/037_missing_tables.sql) - Миграция safety_gates
- [`infrastructure/chain_discovery.py`](../infrastructure/chain_discovery.py) - Сервис автообнаружения сетей
