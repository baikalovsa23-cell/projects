# Database — PostgreSQL 15 Schema & CRUD Interface
> **Version:** 0.2.0  
> **Status:** ✅ Schema Complete — Ready for Deployment  
> **Tables:** 30 | **ENUMs:** 14 | **Indexes:** 35+

---

## 📂 Files Overview

| File | Description | Lines | Status |
|------|-------------|-------|--------|
| [`schema.sql`](schema.sql) | Complete database schema (30 tables) | ~800 | ✅ Ready |
| [`seed_proxies.sql`](seed_proxies.sql) | 90 proxies (45 NL + 45 IS) | ~150 | ✅ Ready |
| [`seed_cex_subaccounts.sql`](seed_cex_subaccounts.sql) | 18 CEX subaccounts (5 exchanges) | ~120 | ✅ Ready |
| [`db_manager.py`](db_manager.py) | Python CRUD interface | ~700 | ✅ Ready |
| [`migrations/001_initial.sql`](migrations/001_initial.sql) | Combined migration script | ~100 | ✅ Ready |

---

## 🚀 Quick Start — Database Deployment

### Option 1: Single Migration Script (Recommended)

```bash
# Navigate to database directory
cd /opt/farming/database

# Run migration (creates schema + seeds data)
psql -U farming_user -d farming_db -f migrations/001_initial.sql
```

### Option 2: Manual Step-by-Step

```bash
# 1. Create schema
psql -U farming_user -d farming_db -f schema.sql

# 2. Seed proxies (90 entries)
psql -U farming_user -d farming_db -f seed_proxies.sql

# 3. Seed CEX subaccounts (18 entries)
psql -U farming_user -d farming_db -f seed_cex_subaccounts.sql
```

---

## ⚠️ CRITICAL: Post-Deployment Security Steps

### 1. Encrypt CEX API Keys

**WARNING:** API keys are currently stored in **PLAIN TEXT**. Run encryption script immediately after seeding:

```bash
python funding/secrets.py encrypt-cex-keys
```

**Verification:**
```bash
psql -U farming_user -d farming_db -c "SELECT LENGTH(api_key) FROM cex_subaccounts LIMIT 1;"
```

Expected output:
- **Before encryption:** ~30-80 characters (plain text)
- **After encryption:** ~100-200 characters (Fernet encrypted)

### 2. Set Correct Permissions

```bash
chmod 600 /opt/farming/.env
chmod 700 /opt/farming/keys/
```

---

## 📊 Database Schema Overview

### Infrastructure (2 tables)
- `worker_nodes` — 3 workers (1 NL, 2 IS)
- `proxy_pool` — 90 proxies (45 IPRoyal NL, 45 Decodo IS)

### CEX (3 tables)
- `cex_subaccounts` — 18 subaccounts across 5 exchanges
- `funding_chains` — 18 funding chains (each → 5 wallets)
- `funding_withdrawals` — 90 withdrawal records (1 per wallet)

### Wallets (3 tables)
- `wallets` — 90 wallets (18 Tier A, 45 Tier B, 27 Tier C)
- `wallet_personas` — 90 unique behavioral profiles (Anti-Sybil)
- `personas_config` — 4 archetype templates

### Protocols (6 tables)
- `protocols` — DeFi protocols for farming
- `protocol_contracts` — Smart contract addresses + ABIs
- `protocol_actions` — Specific on-chain actions (swap, stake, LP)
- `chain_rpc_endpoints` — RPC URLs with failover
- `chain_rpc_health_log` — RPC monitoring (7-day retention)

### Points (2 tables)
- `points_programs` — Points loyalty programs (Blast, Scroll, etc.)
- `wallet_points_balances` — Points balances per wallet

### Activity (3 tables)
- `wallet_protocol_assignments` — Protocol → Wallet mapping
- `scheduled_transactions` — Transaction queue (from Gaussian scheduler)
- `weekly_plans` — Weekly TX plans per wallet

### OpenClaw (2 tables)
- `openclaw_tasks` — Browser automation tasks (Tier A only)
- `openclaw_reputation` — Gitcoin Passport, ENS, POAP tracking

### Airdrops & Withdrawal (4 tables)
- `airdrops` — Detected airdrops
- `snapshot_events` — Snapshot dates for post-snapshot activity
- `withdrawal_plans` — Multi-stage withdrawal plans (A: 4 steps, B: 3, C: 2)
- `withdrawal_steps` — Individual withdrawal steps (Telegram approval required)

### Monitoring (4 tables)
- `gas_snapshots` — Gas price monitoring
- `protocol_research_reports` — LLM agent weekly reports
- `news_items` — CryptoPanic news feed
- `system_events` — Events log for Telegram alerts

---

## 🐍 Python Interface — `db_manager.py`

### Connection Pooling

```python
from database.db_manager import DatabaseManager

db = DatabaseManager()  # Uses .env credentials
```

**Connection Pool:**
- Min connections: 2
- Max connections: 20
- Auto-reconnect on transient failures (3 retries with exponential backoff)

### Example Queries

```python
# Get wallet by ID
wallet = db.get_wallet(wallet_id=1)
print(f"Address: {wallet['address']} | Tier: {wallet['tier']}")

# Get all wallets for Worker 1
worker1_wallets = db.get_wallets_by_worker(worker_id=1)  # Returns 30 wallets
for w in worker1_wallets:
    print(f"Wallet {w['id']}: {w['address']}")

# Get wallet's persona
persona = db.get_wallet_persona(wallet_id=1)
print(f"Persona type: {persona['persona_type']}")
print(f"Slippage tolerance: {persona['slippage_tolerance']}%")
print(f"Preferred hours: {persona['preferred_hours']}")

# Create a scheduled transaction
tx_id = db.create_scheduled_transaction(
    wallet_id=1,
    protocol_action_id=5,
    tx_type='SWAP',
    layer='web3py',
    scheduled_at=datetime.now() + timedelta(hours=2),
    amount_usdt=Decimal('15.73')
)

# Get pending transactions (for executor module)
pending_txs = db.get_pending_transactions(before=datetime.now(), limit=10)
for tx in pending_txs:
    print(f"TX {tx['id']}: Wallet {tx['wallet_id']} @ {tx['scheduled_at']}")

# Log system event (for Telegram alerts)
db.log_system_event(
    event_type='worker_down',
    severity='critical',
    message='Worker 2 heartbeat timeout',
    component='worker_2',
    metadata={'last_heartbeat': '2026-02-24 05:30:00'}
)

# Close pool when done
db.close_pool()
```

### Available Methods (80+)

**Infrastructure:**
- `get_worker_node(worker_id)`, `update_worker_heartbeat(worker_id)`
- `get_proxy(proxy_id)`, `get_proxies_by_country(country_code)`, `mark_proxy_used(proxy_id)`

**CEX:**
- `get_cex_subaccount(subaccount_id)`, `get_cex_subaccounts_by_exchange(exchange)`
- `update_cex_balance(subaccount_id, balance_usdt)`
- `create_funding_withdrawal(...)`, `update_funding_withdrawal_status(...)`

**Wallets:**
- `get_wallet(wallet_id)`, `get_wallet_by_address(address)`, `get_wallets_by_tier(tier)`
- `create_wallet(...)`, `update_wallet_status(wallet_id, status)`
- `update_wallet_funded(wallet_id)`, `increment_wallet_tx_count(wallet_id)`
- `get_wallet_persona(wallet_id)`, `create_wallet_persona(...)`

**Protocols:**
- `get_protocol(protocol_id)`, `get_protocol_by_name(name)`, `get_active_protocols()`
- `create_protocol(...)`, `get_protocol_actions(protocol_id, layer)`

**Activity:**
- `create_scheduled_transaction(...)`, `get_pending_transactions(before, limit)`
- `update_transaction_status(tx_id, status, tx_hash, error_message)`
- `create_weekly_plan(...)`, `increment_weekly_plan_actual(plan_id)`

**OpenClaw:**
- `create_openclaw_task(...)`, `get_queued_openclaw_tasks(before, limit)`
- `update_openclaw_task_status(task_id, status, error_message)`
- `update_openclaw_score(wallet_id, gitcoin_passport_score)`

**Monitoring:**
- `log_system_event(event_type, severity, message, component, metadata)`
- `get_unsent_critical_events()`, `mark_event_sent(event_id)`
- `record_gas_snapshot(chain, slow_gwei, normal_gwei, fast_gwei)`
- `get_latest_gas(chain)`

**Withdrawal:**
- `create_withdrawal_plan(wallet_id, tier)`, `create_withdrawal_step(...)`
- `approve_withdrawal_step(step_id, approved_by)`, `get_pending_withdrawals()`

---

## 🔍 Verification Queries

### Check Table Counts

```sql
-- Should return 30
SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public';

-- Should return 14
SELECT COUNT(*) FROM pg_type WHERE typtype = 'e';

-- Should return 35+
SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public';
```

### Verify Seed Data

```sql
-- Should return 90
SELECT COUNT(*) FROM proxy_pool;

-- Should return 45 NL, 45 IS
SELECT country_code, COUNT(*) FROM proxy_pool GROUP BY country_code;

-- Should return 18
SELECT COUNT(*) FROM cex_subaccounts;

-- Should return: binance-4, bybit-4, kucoin-3, mexc-3, okx-4
SELECT exchange, COUNT(*) FROM cex_subaccounts GROUP BY exchange ORDER BY exchange;
```

### Check API Key Encryption

```sql
-- Plain text keys: ~30-80 characters
-- Encrypted keys: ~100-200 characters
SELECT 
    subaccount_name, 
    LENGTH(api_key) AS key_length,
    LENGTH(api_secret) AS secret_length
FROM cex_subaccounts;
```

---

## 🛠️ Troubleshooting

### Error: "relation does not exist"

**Cause:** Schema not created yet.

**Solution:**
```bash
psql -U farming_user -d farming_db -f schema.sql
```

### Error: "duplicate key value violates unique constraint"

**Cause:** Seed data already inserted.

**Solution (if you want to re-seed):**
```sql
TRUNCATE proxy_pool, cex_subaccounts RESTART IDENTITY CASCADE;
```

Then re-run seed scripts.

### Error: "password authentication failed"

**Cause:** Incorrect `DB_PASS` in `.env`.

**Solution:**
```bash
# Check .farming_secrets
cat /root/.farming_secrets | grep DB_PASS

# Update .env
nano /opt/farming/.env
```

### Low Performance / Slow Queries

**Check connection pool:**
```python
import psycopg2.pool

db = DatabaseManager()
print(f"Pool connections: {len(db.pool._used)} used, {len(db.pool._pool)} available")
```

**Increase pool size:**
```python
db = DatabaseManager(min_conn=5, max_conn=50)
```

---

## 📝 Next Steps

1. ✅ Deploy database schema
2. ⚠️ **CRITICAL:** Encrypt CEX API keys (`python funding/secrets.py encrypt-cex-keys`)
3. Generate 90 wallets: `python wallets/generator.py`
4. Create funding chains: `python funding/engine.py --plan`
5. Initialize Workers: `curl http://127.0.0.1:5000/api/health`
6. Start Master Node scheduler: `systemctl start farming-master`

---

---

## 📁 Архитектурный анализ файлов модуля

### `db_manager.py`

**Зачем:** Закрывает проблему дублирования SQL-кода и обеспечивает типобезопасный интерфейс к PostgreSQL для всех модулей системы.

**Бизнес-задача:** Предоставляет унифицированный CRUD-слой для 30 таблиц с connection pooling, retry logic и structured logging.

**Интеграция:**
- Connection pool (2-20 connections) с автоматическим возвратом
- Retry на transient failures (OperationalError, InterfaceError) — 3 попытки с exponential backoff
- Context managers для автоматического commit/rollback
- 80+ методов для всех доменов: Infrastructure, CEX, Wallets, Protocols, Activity, OpenClaw, Monitoring, Withdrawal

**Ключевые ограничения:**
- **Fernet encryption required:** Приватные ключи и API ключи должны быть зашифрованы перед записью
- **Tier A only для OpenClaw:** Методы `create_openclaw_task` и `update_openclaw_score` работают только с `openclaw_enabled = TRUE`
- **Worker assignment:** `get_wallets_by_worker` использует `worker_id` (1-3), не `worker_node_id`

**Заглушки:** Нет.  
**Хардкод:** Нет (все параметры из env/аргументов).

---

### `schema.sql`

**Зачем:** Закрывает проблему целостности данных и обеспечивает типизацию через ENUMs для критических бизнес-полей.

**Бизнес-задача:** Определяет структуру данных для 90 кошельков, 18 CEX субаккаунтов, 200 прокси, протоколов, транзакций и мониторинга.

**Интеграция:**
- 14 ENUM типов: `wallet_tier`, `persona_type`, `wallet_status`, `tx_type`, `action_layer`, `tx_status`, `gas_preference`, `withdrawal_status`, `openclaw_task_status`, `rpc_health_status`, `funding_withdrawal_status`, `cex_exchange`, `proxy_protocol`, `event_severity`
- 30 таблиц с FOREIGN KEY constraints
- 35+ индексов для оптимизации запросов
- Автоматические триггеры `update_updated_at_column()`

**Ключевые ограничения:**
- **Address validation:** `CHECK (address ~ '^0x[a-f0-9]{40}$')` + lowercase enforcement
- **tx_weights_sum:** Сумма весов транзакций в `wallet_personas` должна быть ≈ 1.00
- **worker_id range:** `CHECK (worker_id BETWEEN 1 AND 3)`

**Заглушки:** Нет.  
**Хардкод:** Нет (чистая схема без данных).

---

### `seed_cex_subaccounts.sql`

**Зачем:** Закрывает проблему начальной конфигурации 18 субаккаунтов для funding chains.

**Бизнес-задача:** Создаёт 18 записей в `cex_subaccounts` для 5 бирж (OKX-4, Binance-4, Bybit-4, KuCoin-3, MEXC-3) с network assignments.

**Интеграция:**
- Связывает каждый субаккаунт с `withdrawal_network` (Arbitrum, Base, OP Mainnet, SCROLL, Linea, zkSync Era)
- Определяет `balance_usdt` для начального распределения

**Ключевые ограничения:**
- **PLACEHOLDER keys:** Все `api_key`, `api_secret`, `api_passphrase` = `'PLACEHOLDER_ENCRYPTED_BY_SECRETS_MANAGER'`
- **Encryption required:** После seeding нужно запустить `python funding/secrets.py encrypt-cex-keys`
- **Network constraints:** Ink и MegaETH недоступны для прямого вывода — требуют bridge

**Заглушки:** ✅ **ДА** — все ключи PLACEHOLDER.  
**Хардкод:** ✅ **ДА** — network assignments, balance_usdt, subaccount names.

---

### `seed_chain_rpc_endpoints.sql`

**Зачем:** Закрывает проблему конфигурации RPC endpoints для 11 L2 сетей + 2 withdrawal-only сетей.

**Бизнес-задача:** Создаёт публичные RPC URLs для farming сетей с приоритетами и health tracking полями.

**Интеграция:**
- 11 L2 farming networks: Arbitrum, Base, Optimism, zkSync, Linea, Scroll, Unichain, Manta, Mantle, Morph, Arbitrum Nova
- 2 withdrawal-only: BSC, Polygon (не для farming!)
- Поля: `chain_id`, `priority`, `is_l2`, `network_type`, `withdrawal_only`, `gas_multiplier`

**Ключевые ограничения:**
- **withdrawal_only = true:** BSC и Polygon НЕ используются для farming, только для приёма с CEX
- **Missing networks:** Ink и MegaETH не имеют публичных RPC (TBD)

**Заглушки:** Нет.  
**Хардкод:** ✅ **ДА** — RPC URLs, chain IDs, network types.

---

### `seed_proxies.sql`

**Зачем:** Закрывает проблему 1:1 wallet-to-proxy mapping для anti-Sybil защиты.

**Бизнес-задача:** Создаёт 200 прокси (45 IPRoyal NL + 125 Decodo IS + 30 Decodo CA) с encrypted passwords.

**Интеграция:**
- IPRoyal: SOCKS5, 7 дней sticky session, geo.iproyal.com:12321
- Decodo: SOCKS5h, 60 минут sticky session, gate.decodo.com:7000
- Encrypted passwords через Fernet (длина ~100+ символов)

**Ключевые ограничения:**
- **Geolocation alignment:** NL wallets → NL proxies, IS wallets → IS proxies, CA wallets → CA proxies
- **Session IDs:** Уникальные для каждого прокси (sticky sessions)
- **v0.32.0 expansion:** +30 Canada proxies для geographic diversity

**Заглушки:** Нет.  
**Хардкод:** ✅ **ДА** — hostnames, ports, usernames, session IDs, country codes.

---

### `migrations/` (44 файла)

**Зачем:** Закрывает проблему эволюции схемы без потери данных и обеспечивает audit trail изменений.

**Бизнес-задача:** Последовательное применение изменений схемы от v0.2.0 до v0.44.0 с backward compatibility.

**Интеграция:**
- `001_initial.sql` — базовая инициализация (schema + seeds)
- `002_openclaw.sql` — 8 таблиц для OpenClaw (tasks, profiles, history, reputation)
- `015-019` — Protocol Research Engine, Airdrop Detector, Funding Tree Mitigation
- `020-021` — 12 архетипов персон (расширение с 4 до 12)
- `026` — Direct Funding Architecture (устранение intermediate wallets)
- `031-032` — Bridge Manager v2, Protocol Research Bridge integration
- `033-044` — Timezone fix, Gas refactoring, Chain aliases, Farm status, Proxy validation, Chain tokens

**Ключевые ограничения:**
- **Sequential execution:** Миграции должны выполняться по порядку номеров
- `001_initial.sql` требует `\i` для schema.sql и seed файлов
- **Verification queries:** Каждая миграция содержит проверочные SELECT

**Заглушки:** Нет.  
**Хардкод:** ✅ **ДА** — в каждой миграции (пороги, константы, ENUM значения).

---

### `seeds/seed_personas_config.sql`

**Зачем:** Закрывает проблему генерации уникальных персон для 90 кошельков без шаблонного поведения.

**Бизнес-задача:** Создаёт 12 архетипов-шаблонов для `wallet_personas` с диапазонами preferred_hours.

**Интеграция:**
- Original 4: ActiveTrader, CasualUser, WeekendWarrior, Ghost
- Extended 8: MorningTrader, NightOwl, WeekdayOnly, MonthlyActive, BridgeMaxi, DeFiDegen, NFTCollector, Governance
- Параметры: `default_tx_per_week_mean`, `default_tx_per_week_stddev`, `default_preferred_hours_range`

**Ключевые ограничения:**
- **Idempotency:** `DELETE FROM personas_config` перед INSERT
- **Used by:** `wallets/personas.py` для генерации уникальных параметров с Gaussian шумом

**Заглушки:** Нет.  
**Хардкод:** ✅ **ДА** — µ, σ, preferred_hours для каждого архетипа.

---

## 📊 Сводка Anti-Sybil механизмов в БД

| Таблица | Механизм | Защита от |
|---------|----------|-----------|
| `wallet_personas` | Уникальные µ/σ для каждого кошелька | Одинаковые паттерны активности |
| `wallet_personas` | `preferred_hours` по timezone воркера | Синхронные транзакции |
| `wallet_personas` | `slippage_tolerance` 0.33%-1.10% | Slippage fingerprinting |
| `wallet_personas` | `amount_noise_pct` ±3-8% | Одинаковые суммы |
| `proxy_pool` | 1:1 wallet-proxy mapping | IP-based clustering |
| `proxy_pool` | Sticky sessions (7 дней / 60 мин) | IP rotation patterns |
| `funding_chains` | 18 изолированных цепочек | Funding tree detection |
| `funding_withdrawals` | `delay_minutes` 60-240+ | Синхронные выводы |
| `scheduled_transactions` | Gaussian scheduling | Bot-like timing |

---

**Database v0.44.0 — Ready for Production** 🚀
