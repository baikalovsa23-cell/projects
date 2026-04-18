# Отчет: Анализ распределения кошельков по воркерам

**Дата:** 2026-03-20
**База данных:** farming_db@82.40.60.131
**Пользователь:** farming_user

---

## Резюме

Выполнен анализ текущего состояния распределения кошельков в системе Crypto Airdrop Farming v4.0. Распределение кошельков полностью соответствует ТЗ из [`Crypto.md`](Crypto.md:173-180).

---

## Результаты SQL-запросов

### 1. Распределение кошельков по воркерам и tier

```sql
SELECT worker_node_id, tier, COUNT(*) as cnt
FROM wallets
GROUP BY worker_node_id, tier
ORDER BY worker_node_id, tier;
```

**Результаты:**

| Worker Node ID | Tier | Count |
|---------------|------|-------|
| 1             | A    | 6     |
| 1             | B    | 15    |
| 1             | C    | 9     |
| 2             | A    | 6     |
| 2             | B    | 15    |
| 2             | C    | 9     |
| 3             | A    | 6     |
| 3             | B    | 15    |
| 3             | C    | 9     |

**Агрегация по воркерам:**
- Worker 1: 30 кошельков (6 A + 15 B + 9 C)
- Worker 2: 30 кошельков (6 A + 15 B + 9 C)
- Worker 3: 30 кошельков (6 A + 15 B + 9 C)

**Агрегация по tier:**
- Tier A: 18 кошельков (6 × 3 воркера)
- Tier B: 45 кошельков (15 × 3 воркера)
- Tier C: 27 кошельков (9 × 3 воркера)
- **Всего:** 90 кошельков

### 2. Проверка NULL значений в worker_node_id

```sql
SELECT COUNT(*) as null_worker FROM wallets WHERE worker_node_id IS NULL;
```

**Результат:** 0

✅ Все кошельки привязаны к воркерам.

### 3. Проверка структуры FK ограничений

```sql
SELECT conname, contype, confdeltype
FROM pg_constraint
WHERE conrelid = 'wallets'::regclass
AND conname LIKE '%worker%';
```

**Результат:**

| Constraint Name              | Type        | On Delete |
|------------------------------|-------------|-----------|
| wallets_worker_node_id_fkey  | FOREIGN KEY | NO ACTION |

✅ FK ограничение существует и настроено корректно.

### 4. Информация о worker_nodes

```sql
SELECT id, worker_id, hostname, ip_address, location, status, last_heartbeat
FROM worker_nodes
ORDER BY worker_id;
```

**Результат:**

| ID | Worker ID | Hostname              | IP Address    | Location      | Status | Last Heartbeat              |
|----|-----------|-----------------------|---------------|---------------|--------|-----------------------------|
| 1  | 1         | worker1.farming.local | 82.40.60.132  | Amsterdam, NL | active | 2026-03-02 08:53:40.584617 |
| 3  | 2         | worker2.farming.local | 82.22.53.183  | Reykjavik, IS | active | 2026-03-02 09:15:25.262081 |
| 2  | 3         | worker3.farming.local | 82.22.53.184  | Reykjavik, IS | active | 2026-03-02 12:30:58.054349 |

---

## Сравнение с ТЗ

### Ожидаемое распределение (из [`Crypto.md`](Crypto.md:173-180)):

| Worker | Локация | Tier A | Tier B | Tier C | Итого | Proxy Region |
|--------|---------|--------|--------|--------|-------|--------------|
| Worker 1 | Amsterdam, NL (UTC+1) | 6 | 15 | 9 | **30** | netherlands |
| Worker 2 | Reykjavik, IS (UTC+0) | 6 | 15 | 9 | **30** | iceland |
| Worker 3 | Reykjavik, IS (UTC+0) | 6 | 15 | 9 | **30** | iceland |
| **Итого** | | **18** | **45** | **27** | **90** | |

### Фактическое распределение:

| Worker | Локация | Tier A | Tier B | Tier C | Итого |
|--------|---------|--------|--------|--------|-------|
| Worker 1 | Amsterdam, NL | 6 | 15 | 9 | **30** |
| Worker 2 | Reykjavik, IS | 6 | 15 | 9 | **30** |
| Worker 3 | Reykjavik, IS | 6 | 15 | 9 | **30** |
| **Итого** | | **18** | **45** | **27** | **90** |

✅ **Распределение кошельков полностью соответствует ТЗ!**

---

## Обнаруженные проблемы

### 🟡 ПРОБЛЕМА 1: Устаревшие heartbeat timestamps

**Последний heartbeat:** 2026-03-02 (18 дней назад)

**Влияние:**
- Невозможность мониторинга реального состояния воркеров
- Риск пропуска падений воркеров
- Нарушение системы оповещений

### 🟢 ПОЛОЖИТЕЛЬНЫЕ АСПЕКТЫ

1. ✅ Распределение кошельков полностью соответствует ТЗ
2. ✅ Все кошельки привязаны к воркерам (NULL отсутствуют)
3. ✅ FK ограничения настроены корректно
4. ✅ Равномерное распределение кошельков по воркерам (30 × 3)
5. ✅ Все воркеры в статусе "active"

---

## Рекомендации

### Рекомендация 1: Восстановление heartbeat timestamps

**Решение:** Настроить автоматическую отправку heartbeat от воркеров

**Реализация:**

```python
# В worker/api.py добавить периодическую отправку heartbeat
import asyncio
from datetime import datetime

async def send_heartbeat():
    """Отправка heartbeat каждые 5 минут"""
    while True:
        try:
            db.update_worker_heartbeat(WORKER_ID)
            logger.info(f"Heartbeat sent for worker {WORKER_ID}")
        except Exception as e:
            logger.error(f"Heartbeat failed: {e}")
        await asyncio.sleep(300)  # 5 минут
```

### Рекомендация 2: Мониторинг распределения кошельков

**Создать view для мониторинга:**

```sql
CREATE OR REPLACE VIEW wallet_distribution_monitor AS
SELECT
    wn.worker_id,
    wn.hostname,
    wn.location,
    COUNT(*) FILTER (WHERE w.tier = 'A') as tier_a_count,
    COUNT(*) FILTER (WHERE w.tier = 'B') as tier_b_count,
    COUNT(*) FILTER (WHERE w.tier = 'C') as tier_c_count,
    COUNT(*) as total_count,
    wn.last_heartbeat,
    CASE
        WHEN NOW() - wn.last_heartbeat > INTERVAL '10 minutes' THEN 'STALE'
        ELSE 'FRESH'
    END as heartbeat_status
FROM worker_nodes wn
LEFT JOIN wallets w ON w.worker_node_id = wn.id
GROUP BY wn.id, wn.worker_id, wn.hostname, wn.location, wn.last_heartbeat
ORDER BY wn.worker_id;
```

**Использование:**

```sql
SELECT * FROM wallet_distribution_monitor;
```

---

## Заключение

Текущее состояние системы показывает полное соответствие ТЗ в распределении кошельков по воркерам и tier. Все 90 кошельков распределены корректно:
- 18 Tier A кошельков (6 × 3 воркера)
- 45 Tier B кошельков (15 × 3 воркера)
- 27 Tier C кошельков (9 × 3 воркера)

Единственная обнаруженная проблема — устаревшие heartbeat timestamps, что указывает на необходимость настройки автоматического мониторинга состояния воркеров.

Рекомендуется настроить автоматическую отправку heartbeat от воркеров и создать систему мониторинга для предотвращения подобных проблем в будущем.
