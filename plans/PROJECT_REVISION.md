# ПОЛНАЯ РЕВИЗИЯ ПРОЕКТА airdrop_v4
> **Дата:** 2026-03-10  
> **Автор:** System Architect  
> **Метод:** Статический анализ кода + **прямое подключение к БД** (`psql -h 82.40.60.131`)

---

## ШАГ 2 — РЕАЛЬНАЯ ИНВЕНТАРИЗАЦИЯ БАЗЫ ДАННЫХ (farming_db @ 82.40.60.131)

> ⚠️ **Расхождение обнаружено:** В [`database/schema.sql`](../database/schema.sql) описано ~30 таблиц. Реально в БД: **52 таблицы**. Разница в 22 таблицы — следствие множества миграций, которые добавляли таблицы без обновления schema.sql.

### 2.1 Все таблицы с количеством строк (реальные данные)

| Таблица | Строк | Статус | Назначение |
|---------|-------|--------|-----------|
| **ИНФРАСТРУКТУРА** |
| `worker_nodes` | **3** | ✅ ЗАПОЛНЕНА | 3 воркера: NL×1, IS×2 |
| `proxy_pool` | **475** | ✅ ЗАПОЛНЕНА | Прокси: CA 30 + IS 310 + NL 135 = 475 |
| `chain_rpc_endpoints` | **11** | ✅ ЗАПОЛНЕНА | RPC для 11 сетей |
| `chain_aliases` | **35** | ✅ ЗАПОЛНЕНА | Алиасы сетей для chain_discovery |
| `chain_rpc_health_log` | 0 | ⬜ ПУСТАЯ | Мониторинг здоровья RPC (не запускался) |
| **CEX** |
| `cex_subaccounts` | **18** | ✅ ЗАПОЛНЕНА | 18 субаккаунтов (4 Binance + 4 Bybit + 4 OKX + 3 KuCoin + 3 MEXC) |
| `funding_chains` | **18** | ✅ ЗАПОЛНЕНА | 18 funding цепочек |
| `funding_withdrawals` | **90** | ✅ ЗАПОЛНЕНА | 90 planned выводов (~$3.89 avg) |
| `cex_networks_cache` | 0 | ⬜ ПУСТАЯ | Кэш доступных сетей CEX |
| **КОШЕЛЬКИ** |
| `wallets` | **90** | ✅ ЗАПОЛНЕНА | 18A + 45B + 27C. Все `inactive`. Все с proxy (30 NL / 30 IS / 30 CA) |
| `wallet_personas` | **90** | ✅ ЗАПОЛНЕНА | 12 архетипов распределены по 90 кошелькам |
| `personas_config` | **12** | ✅ ЗАПОЛНЕНА | 12 шаблонов архетипов |
| `wallet_withdrawal_address_history` | 0 | ⬜ ПУСТАЯ | История авторизованных адресов |
| **ПРОТОКОЛЫ** |
| `protocols` | 0 | ⬜ ПУСТАЯ | Protocol Research не запускался |
| `protocol_contracts` | 0 | ⬜ ПУСТАЯ | Контракты не добавлены |
| `protocol_actions` | 0 | ⬜ ПУСТАЯ | Действия не добавлены |
| `protocol_research_pending` | **3** | ✅ ЗАПОЛНЕНА | 3 протокола ожидают одобрения |
| `protocol_research_reports` | 0 | ⬜ ПУСТАЯ | Отчёты LLM не запускались |
| `defillama_bridges_cache` | 0 | ⬜ ПУСТАЯ | Кэш DefiLlama мостов |
| `discovery_failures` | **2** | ⚠️ ОШИБКИ | 2 ошибки при обнаружении сетей |
| **АКТИВНОСТЬ** |
| `scheduled_transactions` | 0 | ⬜ ПУСТАЯ | Scheduler не запускался |
| `weekly_plans` | 0 | ⬜ ПУСТАЯ | |
| `wallet_protocol_assignments` | 0 | ⬜ ПУСТАЯ | |
| `wallet_points_balances` | 0 | ⬜ ПУСТАЯ | Points не мониторились |
| `points_programs` | 0 | ⬜ ПУСТАЯ | |
| `wallet_tokens` | 0 | ⬜ ПУСТАЯ | Airdrop scanner не запускался |
| **OPENCLAW** |
| `openclaw_tasks` | 0 | ⬜ ПУСТАЯ | Browser automation не запускался |
| `openclaw_task_history` | 0 | ⬜ ПУСТАЯ | |
| `openclaw_reputation` | 0 | ⬜ ПУСТАЯ | Репутация Tier A не набрана |
| `openclaw_profiles` | 0 | ⬜ ПУСТАЯ | Профили браузера не созданы |
| `gitcoin_stamps` | 0 | ⬜ ПУСТАЯ | Gitcoin stamps не получены |
| `poap_tokens` | 0 | ⬜ ПУСТАЯ | POAP не получены |
| `ens_names` | 0 | ⬜ ПУСТАЯ | ENS/cb.id не зарегистрированы |
| `lens_profiles` | 0 | ⬜ ПУСТАЯ | Lens профили не созданы |
| `snapshot_votes` | 0 | ⬜ ПУСТАЯ | Голосования не выполнены |
| **АИРДРОПЫ И ВЫВОД** |
| `airdrops` | 0 | ⬜ ПУСТАЯ | Аирдропы не обнаружены |
| `snapshot_events` | 0 | ⬜ ПУСТАЯ | |
| `withdrawal_plans` | 0 | ⬜ ПУСТАЯ | Вывод не инициирован |
| `withdrawal_steps` | 0 | ⬜ ПУСТАЯ | |
| **МОНИТОРИНГ** |
| `gas_snapshots` | 0 | ⬜ ПУСТАЯ | Gas controller не запускался |
| `gas_history` | 0 | ⬜ ПУСТАЯ | |
| `news_items` | 0 | ⬜ ПУСТАЯ | News aggregator не запускался |
| `research_logs` | **2** | ✅ ЗАПОЛНЕНА | 2 записи (Research scheduler запускался) |
| `system_events` | **2** | ✅ ЗАПОЛНЕНА | 2 info события |
| `airdrop_scan_logs` | **2** | ✅ ЗАПОЛНЕНА | 2 запуска airdrop scan |
| **BRIDGE** |
| `bridge_history` | 0 | ⬜ ПУСТАЯ | Bridge операции не выполнялись |
| **DEPRECATED (v2.0)** |
| `intermediate_funding_wallets_deprecated_v2` | 0 | ✅ КОРРЕКТНО | Переименована с суффиксом `_deprecated_v2` |
| `intermediate_consolidation_wallets_deprecated_v2` | 0 | ✅ КОРРЕКТНО | Переименована с суффиксом `_deprecated_v2` |
| `intermediate_wallet_operations` | 0 | ⬜ ПУСТАЯ | Операции intermediate кошельков |
| `consolidation_plans` | 0 | ⬜ ПУСТАЯ | Планы консолидации |
| `consolidation_audit_trail` | 0 | ⬜ ПУСТАЯ | Аудит-трейл консолидации |
| `phase2_transfer_queue` | 0 | ⬜ ПУСТАЯ | Очередь phase 2 переводов |

**Итог:** 52 таблицы. Заполнены 12, пустых 40. Система на стадии инициализации — кошельки созданы, финансирование запланировано, транзакции не выполнялись.

---

### 2.2 Расхождения schema.sql vs реальная БД

Таблицы, которые **ЕСТЬ в БД но НЕТ в schema.sql** (добавлены через миграции 031-036 и не добавлены в schema.sql):

| Таблица | Добавлена в | Причина |
|---------|-------------|---------|
| `bridge_history` | migration 031 | Bridge Manager v2.0 |
| `cex_networks_cache` | migration 031/032 | Кэш CEX сетей |
| `chain_aliases` | migration 035 | ChainDiscovery алиасы |
| `defillama_bridges_cache` | migration 031 | DefiLlama кэш |
| `discovery_failures` | migration 035 | Ошибки обнаружения |
| `airdrop_scan_logs` | migration 016 | Логи сканирования |
| `openclaw_profiles` | migration 002 | Browser профили |
| `openclaw_task_history` | migration 002 | История задач |
| `gitcoin_stamps` | migration 002 | Gitcoin stamps |
| `poap_tokens` | migration 002 | POAP токены |
| `ens_names` | migration 002 | ENS имена |
| `lens_profiles` | migration 002 | Lens профили |
| `snapshot_votes` | migration 002 | Голосования |
| `research_logs` | migration 015 | Логи research |
| `wallet_withdrawal_address_history` | migration 019 | История адресов |
| `gas_history` | migration 034 | История gas |
| `intermediate_*_deprecated_v2` | migration 026 | Переименованные intermediate |

**⚠️ schema.sql устарел** — отражает только начальное состояние. Реальная схема = schema.sql + все 36 миграций.

---

### 2.3 ENUMs в реальной БД (15 типов)

| ENUM | Значения |
|------|---------|
| `action_layer` | web3py, openclaw |
| `cex_exchange` | binance, bybit, okx, kucoin, mexc |
| `event_severity` | info, warning, error, critical |
| `funding_withdrawal_status` | planned, requested, processing, completed, failed |
| `gas_preference` | slow, normal, fast |
| `openclaw_task_status` | queued, running, completed, failed, skipped |
| `persona_type` | ActiveTrader, CasualUser, WeekendWarrior, Ghost, MorningTrader, NightOwl, WeekdayOnly, MonthlyActive, BridgeMaxi, DeFiDegen, NFTCollector, Governance |
| `proxy_protocol` | http, https, socks5, socks5h |
| `research_status` | pending_approval, approved, rejected, auto_rejected, duplicate |
| `rpc_health_status` | healthy, degraded, down |
| `tx_status` | pending, submitted, confirmed, failed, cancelled, replaced |
| `tx_type` | SWAP, BRIDGE, STAKE, LP, NFT_MINT, WRAP, APPROVE, CANCEL, GOVERNANCE_VOTE, GOVERNANCE_VOTE_DIRECT, GITCOIN_DONATE, POAP_CLAIM, ENS_REGISTER, SNAPSHOT_VOTE, LENS_POST |
| `wallet_status` | inactive, warming_up, active, paused, post_snapshot, compromised, retired |
| `wallet_tier` | A, B, C |
| `withdrawal_status` | planned, pending_approval, approved, executing, completed, rejected |

---

### 2.4 Views в реальной БД (10 views)

| View | Назначение |
|------|-----------|
| `v_direct_funding_schedule` | Расписание прямых выводов CEX→wallet |
| `v_funding_interleave_quality` | Качество interleaving по раундам |
| `v_funding_temporal_distribution` | Темпоральное распределение funding |
| `v_subaccount_usage` | Использование субаккаунтов |
| `v_wallets_funding_info` | Денормализованная информация о funding кошельков |
| `v_bridge_stats_by_network` | Статистика bridge по сетям |
| `v_protocols_requiring_bridge` | Протоколы, требующие bridge |
| `v_recent_bridges` | Последние bridge операции |
| `consolidation_progress` | Прогресс консолидации |
| `wallet_withdrawal_security_status` | Безопасность вывода (migration 019) |

---

### 2.5 PostgreSQL Functions (27 функций)

| Функция | Назначение |
|---------|-----------|
| `approve_protocol()` | Одобрение протокола из pending |
| `auto_reject_stale_protocols()` | Автоотклонение устаревших протоколов |
| `auto_reject_stale_unreachable_protocols()` | Автоотклонение недостижимых |
| `calculate_bridge_safety_score()` | Расчёт safety score моста |
| `calculate_final_priority_score()` | Итоговый score протокола |
| `get_cex_cached_networks()` | Кэшированные сети CEX |
| `get_recent_airdrops()` | Последние аирдропы |
| `get_scan_statistics()` | Статистика сканирований |
| `get_unreachable_protocols_for_recheck()` | Протоколы для перепроверки |
| `get_wallet_funding_source_address()` | Адрес источника финансирования |
| `is_bridge_safe()` | Проверка безопасности моста |
| `log_authorized_withdrawal_address_change()` | Логирование изменений адреса |
| `quick_isolation_check()` | Быстрая проверка изоляции |
| `update_cex_cache_expires()` | Обновление CEX кэша |
| `update_defillama_cache_expires()` | Обновление DefiLlama кэша |
| `update_openclaw_profiles_updated_at()` | Trigger для openclaw_profiles |
| `update_openclaw_tasks_updated_at()` | Trigger для openclaw_tasks |
| `update_protocol_bridge_info()` | Обновление bridge info протокола |
| `update_research_timestamp()` | Trigger обновления времени |
| `update_updated_at_column()` | Универсальный trigger updated_at |
| `update_wallet_token_timestamp()` | Trigger wallet_tokens |
| `validate_all_authorized_addresses()` | Валидация всех withdrawal адресов |
| `validate_cluster_size_distribution()` | Проверка распределения кластеров |
| `validate_consolidation_clusters()` | Проверка консолидационных кластеров |
| `validate_direct_funding_schedule()` | Проверка прямого funding (10+ checks) |
| `validate_funding_isolation()` | Проверка изоляции funding chains |
| `validate_withdrawal_destination()` | Проверка адреса вывода |

---

### 2.6 Реальное состояние критических данных

```
КОШЕЛЬКИ:
  Всего: 90 (18A + 45B + 27C)
  Статус: все inactive (финансирование ещё не выполнено)
  Proxy: 30 NL (iproyal) + 30 IS (decodo) + 30 CA (decodo) — МАКСИМАЛЬНЫЙ ХАОС ✅

PROXY POOL:
  Всего: 475 активных прокси
  NL (iproyal):  135
  IS (decodo):   310 (была 125 IS sticky + 80 IS gate — загружены дополнительные!)
  CA (decodo):    30
  ⚠️ В schema.sql и seed_proxies.sql написано 200, реально 475 — в 2.4 раза больше!

WORKER NODES:
  Worker 1: 82.40.60.132 (Amsterdam, NL) — active, last heartbeat 2026-03-02
  Worker 2: 82.22.53.183 (Reykjavik, IS) — active, last heartbeat 2026-03-02
  Worker 3: 82.22.53.184 (Reykjavik, IS) — active, last heartbeat 2026-03-02
  ⚠️ Последний heartbeat 8 дней назад — воркеры могли быть остановлены

CEX SUBACCOUNTS:
  18 субаккаунтов, все active
  Binance×4, Bybit×4, OKX×4, KuCoin×3, MEXC×3

FUNDING WITHDRAWALS:
  90 записей, все planned, avg $3.89/кошелёк
  ⚠️ Суммы очень маленькие ($3.89 avg) — возможно это тестовые суммы!
  ТЗ предполагает $6-20 на кошелёк в зависимости от сети

WALLET PERSONAS:
  12 архетипов, 90 персон распределены:
  Ghost:10, NightOwl:10, BridgeMaxi:10 (максимум)
  Governance:9, MonthlyActive:9, WeekendWarrior:9
  CasualUser:6, MorningTrader:5, DeFiDegen:5, NFTCollector:5
  ActiveTrader:4 (минимум!)
  ⚠️ ActiveTrader всего 4 из 18 Tier A — ожидалось больше активных трейдеров в Tier A

schema_migrations: НЕ СУЩЕСТВУЕТ
  → Нет автоматического трекинга применённых миграций!
  → Нельзя знать, какие именно миграции применены без ручной проверки
```

---

### 2.7 Реально имеющиеся индексы vs необходимые

Все ключевые индексы **УЖЕ ЕСТЬ** в реальной БД (всего 231 индекс):

| Таблица | Нужные индексы | Статус |
|---------|---------------|--------|
| `scheduled_transactions` | `(wallet_id)`, `(status)`, `(scheduled_at)`, `(bridge_required)` | ✅ Все есть |
| `openclaw_tasks` | `(wallet_id)`, `(status)`, `(worker_id)` | ✅ Все есть |
| `system_events` | `(telegram_sent WHERE false)`, `(severity)` | ✅ Все есть |
| `wallets` | `(tier)`, `(status)`, `(worker_node_id)`, `(warmup_status)` | ✅ Все есть |
| `funding_withdrawals` | `(wallet_id)`, `(status)`, `(chain_id)`, `(scheduled_at)` | ✅ Все есть |

**Вывод по индексам:** Индексная стратегия **отличная**. Мои рекомендации в первоначальном анализе оказались уже реализованными в миграциях.

---

## ШАГ 5 (ОБНОВЛЁННЫЙ) — ВЕРДИКТ ПО БАЗЕ ДАННЫХ (реальные данные)

### 5.1 Критические находки из реальной БД

#### ❌ ПРОБЛЕМА 1: Малые суммы funding ($3.89 avg)
**Файл:** [`funding_withdrawals`](таблица)  
Среднее значение `amount_usdt = 3.89` ОЧЕНЬ мало. Согласно ТЗ: Tier A должен получать $19, Tier B $6, Tier C $6.  
`90 × $3.89 = $350` — это ~ $154 / 2.3 — в 2-3 раза меньше expected.  
**Возможно:** суммы заданы без шума или это неправильный базовый расчёт.  
**Нужно:** выполнить `SELECT * FROM v_direct_funding_schedule LIMIT 5` и проверить scheduled_at.

#### ❌ ПРОБЛЕМА 2: proxy_pool 475 vs. ожидаемых 200
Прокси значительно больше (475), из них IS 310 (ожидалось 125 IS). Возможно DECODO генерирует уникальные записи при каждом session ID, и seed был перезапущен. Дублей быть не должно, но нужно проверить.

#### ⚠️ ПРОБЛЕМА 3: schema_migrations не существует
Нельзя знать, какие из 36 SQL-миграций применены. При следующем запуске нет защиты от повторного применения.  
**Решение:** Создать таблицу `schema_migrations` и записать все уже применённые версии.

#### ⚠️ ПРОБЛЕМА 4: Worker heartbeat устарел (8 дней)
Последний heartbeat `2026-03-02` (8 дней назад). К дате ревизии `2026-03-10` воркеры молчат. Либо система остановлена, либо heartbeat сломан.

#### ✅ ХОРОШЕЕ: Deprecated таблицы правильно переименованы
`intermediate_funding_wallets_deprecated_v2` и `intermediate_consolidation_wallets_deprecated_v2` — правильно помечены суффиксом. Продакшн архитектура clean.

#### ✅ ХОРОШЕЕ: research_logs существует
Вопрос ❓1 из первоначального анализа снят — таблица в БД есть, в ней 2 строки. В schema.sql отсутствует, но это несущественно.

#### ✅ ХОРОШЕЕ: 12 архетипов в wallet_personas — правильно
90 персон распределены по 12 архетипам, что соответствует migration 020-021.

### 5.2 Вердикты по таблицам (обновлён)

| Таблица | Вердикт | Обоснование |
|---------|---------|------------|
| `wallets` | ✅ ОСТАВИТЬ | 90 записей, структура полная (23 колонки) |
| `wallet_personas` | ✅ ОСТАВИТЬ | 90 персон, 12 архетипов |
| `cex_subaccounts` | ✅ ОСТАВИТЬ | 18 субаккаунтов |
| `funding_chains` | ✅ ОСТАВИТЬ | 18 цепочек |
| `funding_withdrawals` | ⚠️ ПРОВЕРИТЬ | 90 planned, суммы подозрительно малые |
| `proxy_pool` | ⚠️ ПРОВЕРИТЬ | 475 vs ожидаемых ~200, откуда лишние 275? |
| `worker_nodes` | ✅ ОСТАВИТЬ | 3 воркера registered, heartbeat устарел |
| `chain_rpc_endpoints` | ✅ ОСТАВИТЬ | 11 сетей |
| `chain_aliases` | ✅ ОСТАВИТЬ | 35 алиасов — нужны для chain_discovery |
| `personas_config` | 🔧 РЕФАКТОРИТЬ | 12 шаблонов, но `wallet_personas` уже содержит финальные значения; personas_config нужен как reference |
| `intermediate_*_deprecated_v2` | ✅ ОСТАВИТЬ (archived) | Правильно переименованы, 0 строк |
| `consolidation_*` | ✅ ОСТАВИТЬ (0 строк) | Нужны для future consolidation phase |
| `openclaw_*` | ✅ ОСТАВИТЬ (0 строк) | Browser automation не запускался |
| `protocols/protocol_*` | ⚠️ ПУСТЫЕ | Research не запускался, когда запустится — заполнятся |
| `scheduled_transactions` | ⚠️ ПУСТАЯ | Scheduler не запускался — это и есть следующий шаг |
| `gas_snapshots/gas_history` | ⚠️ ПУСТЫЕ | Gas controller не запускался |
| `news_items` | ⚠️ ПУСТАЯ | News aggregator не запускался |
| `research_logs` | ✅ ЗАПОЛНЕНА (2 строки) | Работает, в schema.sql добавить |
| `system_events` | ✅ ЗАПОЛНЕНА (2 строки) | Работает |
| `airdrop_scan_logs` | ✅ ЗАПОЛНЕНА (2 строки) | Сканирование запускалось 2 раза |
| `discovery_failures` | ⚠️ ОШИБКИ (2 строки) | 2 ошибки discovery — нужно проверить |

---

## ШАГ 1 — ИНВЕНТАРИЗАЦИЯ ФАЙЛОВ

### 1.1 Модули (директории)

| Файл | Назначение | Используется? | Кем вызывается | Что вызывает сам | Связь с БД |
|------|-----------|---------------|----------------|-----------------|------------|
| **DATABASE** |
| [`database/db_manager.py`](../database/db_manager.py) | Единственная точка доступа к PostgreSQL, 80+ методов CRUD | ✅ Да | всеми модулями | psycopg2 pool, tenacity retry | Все 52 таблицы |
| [`database/schema.sql`](../database/schema.sql) | Начальная схема БД (~30 таблиц). **Устарела — реально 52 таблицы** | ✅ Да (разово) | deploy-скрипт | — | создаёт ~30 таблиц |
| [`database/seed_cex_subaccounts.sql`](../database/seed_cex_subaccounts.sql) | 18 субаккаунтов CEX (API ключи в PLAIN TEXT — ❗) | ✅ Да (разово) | deploy-скрипт | — | `cex_subaccounts` |
| [`database/seed_proxies.sql`](../database/seed_proxies.sql) | ~200 прокси (реально в БД 475 — схема запускалась несколько раз?) | ✅ Да (разово) | deploy-скрипт | — | `proxy_pool` |
| [`database/seed_chain_rpc_endpoints.sql`](../database/seed_chain_rpc_endpoints.sql) | 9 L2-сетей с RPC URL (в БД 11 — добавлены через migration 034/035) | ✅ Да (разово) | deploy-скрипт | — | `chain_rpc_endpoints` |
| [`database/README.md`](../database/README.md) | Документация модуля БД | — | — | — | — |
| **ACTIVITY** |
| [`activity/scheduler.py`](../activity/scheduler.py) | Gaussian-планировщик (1084 LOC): генерация расписания транзакций | ✅ Да | `master_node/jobs.py` | `db_manager`, `bridge_manager` | `scheduled_transactions`(0 строк!), `weekly_plans`, `wallets`, `wallet_personas` |
| [`activity/executor.py`](../activity/executor.py) | Исполнитель TX (1442 LOC): EIP-1559, контракты, бриджи | ✅ Да | `worker/api.py`, `master_node/jobs.py` | `db_manager`, `proxy_manager`, `bridge_manager`, `infrastructure/*` | `scheduled_transactions`, `wallets`, `protocol_contracts`(пустая) |
| [`activity/adaptive.py`](../activity/adaptive.py) | AdaptiveGasController (781 LOC): skip при высоком gas, мониторинг RPC | ✅ Да | `master_node/jobs.py` | `db_manager` | `gas_snapshots`(пустая), `proxy_pool`, `chain_rpc_endpoints` |
| [`activity/bridge_manager.py`](../activity/bridge_manager.py) | Bridge Manager v2.0 (1500+ LOC): Socket/Across/Relay агрегаторы | ✅ Да | `activity/scheduler.py`, `activity/executor.py` | `db_manager`, `gas_logic`, `chain_discovery` | `bridge_history`(пустая), `chain_rpc_endpoints`, `cex_networks_cache`(пустая) |
| [`activity/proxy_manager.py`](../activity/proxy_manager.py) | ProxyManager: wallet→proxy маппинг, LRU ротация | ✅ Да | `activity/executor.py`, `worker/api.py` | `db_manager` | `proxy_pool`(475 прокси), `wallets` |
| [`activity/tx_types.py`](../activity/tx_types.py) | Transaction builders (691 LOC): SWAP, WRAP, APPROVE | ✅ Да | `activity/executor.py` | `db_manager` | `chain_rpc_endpoints`, `protocol_contracts`(пустая) |
| [`activity/exceptions.py`](../activity/exceptions.py) | `ProxyRequiredError` и другие исключения | ✅ Да | `activity/executor.py`, `worker/api.py`, `openclaw/executor.py` | — | — |
| [`activity/__init__.py`](../activity/__init__.py) | Экспорт публичного API модуля | ✅ Да | — | — | — |
| **FUNDING** |
| [`funding/engine_v3.py`](../funding/engine_v3.py) | DirectFundingEngineV3 (596 LOC): прямые выводы, interleaving | ✅ Да | `setup_direct_funding.py`, `master_node/jobs.py` | `db_manager`, `cex_integration`, `infrastructure/*` | `funding_withdrawals`(90 строк), `funding_chains`(18), `cex_subaccounts`(18) |
| [`funding/cex_integration.py`](../funding/cex_integration.py) | CEXManager (632 LOC): CCXT для 5 бирж | ✅ Да | `funding/engine_v3.py`, `activity/bridge_manager.py` | `db_manager`, `funding/secrets` | `cex_subaccounts`, `cex_networks_cache`(пустая) |
| [`funding/secrets.py`](../funding/secrets.py) | SecretsManager (465 LOC): Fernet шифрование | ✅ Да | `funding/cex_integration.py`, `setup_intermediate_wallets.py`, `wallets/generator.py` | `db_manager` | `cex_subaccounts`, `wallets` |
| **INFRASTRUCTURE** |
| [`infrastructure/identity_manager.py`](../infrastructure/identity_manager.py) | TLS Fingerprinting (curl_cffi) | ✅ Да | `activity/executor.py`, `monitoring/airdrop_detector.py`, `openclaw/browser.py` | curl_cffi | — |
| [`infrastructure/gas_logic.py`](../infrastructure/gas_logic.py) | GasLogic: async проверка gas, L2 multiplier | ✅ Да | `activity/bridge_manager.py`, `funding/engine_v3.py` | `db_manager` | `gas_snapshots`(пустая), `gas_history`(пустая), `chain_rpc_endpoints` |
| [`infrastructure/gas_controller.py`](../infrastructure/gas_controller.py) | GasBalanceController (263 LOC): мониторинг балансов | ✅ Да | `master_node/jobs.py` | `db_manager` | `wallets`(90 inactive), `proxy_pool` |
| [`infrastructure/chain_discovery.py`](../infrastructure/chain_discovery.py) | ChainDiscoveryService (35K chars): динамическое обнаружение сетей | ✅ Да | `activity/bridge_manager.py` | `db_manager` | `chain_rpc_endpoints`(11), `chain_aliases`(35), `discovery_failures`(2 ошибки!) |
| [`infrastructure/ip_guard.py`](../infrastructure/ip_guard.py) | IPGuard: pre_flight_check() — блокировка прямых соединений | ✅ Да | `activity/executor.py`, `openclaw/browser.py` | — | — |
| [`infrastructure/network_mode.py`](../infrastructure/network_mode.py) | NetworkModeManager: DRY_RUN/TESTNET/MAINNET | ✅ Да | `funding/engine_v3.py`, `withdrawal/orchestrator.py`, `master_node/orchestrator.py` | — | — |
| [`infrastructure/simulator.py`](../infrastructure/simulator.py) | TransactionSimulator: dry-run симуляция TX | ✅ Да | `funding/engine_v3.py`, `withdrawal/orchestrator.py` | `infrastructure/network_mode` | — |
| **MASTER_NODE** |
| [`master_node/orchestrator.py`](../master_node/orchestrator.py) | MasterOrchestrator (580 LOC): APScheduler, lifecycle, safety gates | ✅ Да | systemd service | `db_manager`, `monitoring/health_check`, `notifications/telegram_bot`, `master_node/jobs` | `system_events`(2 строки) |
| [`master_node/jobs.py`](../master_node/jobs.py) | JobRunner (27K chars): 6 job-функций для APScheduler (lazy imports) | ✅ Да | `master_node/orchestrator.py` | все 6 основных подсистем | через вложенные модули |
| [`master_node/systemd/airdrop-farming.service`](../master_node/systemd/airdrop-farming.service) | Systemd unit-файл | ✅ Да (установка) | — | — | — |
| **MONITORING** |
| [`monitoring/health_check.py`](../monitoring/health_check.py) | HealthCheckOrchestrator (33K chars): 10+ проверок, curl_cffi | ✅ Да | `master_node/orchestrator.py` | `db_manager`, curl_cffi | `system_events`(2 строки), `chain_rpc_health_log`(пустая) |
| [`monitoring/airdrop_detector.py`](../monitoring/airdrop_detector.py) | AirdropDetector (718 LOC): async сканирование 90 кошельков | ✅ Да | `master_node/jobs.py` | `db_manager`, `identity_manager` | `wallet_tokens`(пустая), `airdrops`(пустая), `airdrop_scan_logs`(2 строки!) |
| [`monitoring/token_verifier.py`](../monitoring/token_verifier.py) | TokenVerifier (397 LOC): CoinGecko + scam heuristics | ✅ Да | `monitoring/airdrop_detector.py` | `db_manager`, aiohttp | `wallet_tokens`(пустая) |
| **NOTIFICATIONS** |
| [`notifications/telegram_bot.py`](../notifications/telegram_bot.py) | TelegramBot (959 LOC): /panic, /status, /approve_withdrawal | ✅ Да | `master_node/orchestrator.py`, `withdrawal/orchestrator.py` | `db_manager`, curl_cffi | `system_events`, `withdrawal_steps`(пустая), `wallets` |
| **OPENCLAW** |
| [`openclaw/manager.py`](../openclaw/manager.py) | OpenClawOrchestrator (491 LOC): планирование задач Tier A | ✅ Да | `master_node/jobs.py` | `db_manager` | `openclaw_tasks`(пустая), `wallets`(18 Tier A с openclaw_enabled?) |
| [`openclaw/executor.py`](../openclaw/executor.py) | OpenClawExecutor (29K chars): browser automation на Worker | ✅ Да | `worker/api.py` | `db_manager`, `openclaw/browser`, `openclaw/llm_vision` | `openclaw_tasks`(пустая), `openclaw_reputation`(пустая) |
| [`openclaw/browser.py`](../openclaw/browser.py) | BrowserEngine (25K chars): Pyppeteer + proxy + fingerprint | ✅ Да | `openclaw/executor.py`, `openclaw/tasks/*` | `identity_manager`, `ip_guard`, `openclaw/fingerprint` | — |
| [`openclaw/fingerprint.py`](../openclaw/fingerprint.py) | FingerprintGenerator (31K chars): Canvas/WebGL fingerprinting | ✅ Да | `openclaw/browser.py` | — | — |
| [`openclaw/llm_vision.py`](../openclaw/llm_vision.py) | LLMVisionClient: screenshot → LLM action (OpenRouter) | ✅ Да | `openclaw/executor.py` | httpx | — |
| [`openclaw/exceptions.py`](../openclaw/exceptions.py) | Кастомные исключения OpenClaw | ✅ Да | `openclaw/executor.py`, `openclaw/browser.py` | — | — |
| [`openclaw/tasks/base.py`](../openclaw/tasks/base.py) | BaseTask ABC | ✅ Да | все task-классы | — | — |
| [`openclaw/tasks/gitcoin.py`](../openclaw/tasks/gitcoin.py) | GitcoinPassportTask | ✅ Да | `openclaw/executor.py` | `openclaw/tasks/base`, `openclaw/browser` | `gitcoin_stamps`(пустая) |
| [`openclaw/tasks/poap.py`](../openclaw/tasks/poap.py) | POAPTask | ✅ Да | `openclaw/executor.py` | `openclaw/tasks/base`, `openclaw/browser` | `poap_tokens`(пустая) |
| [`openclaw/tasks/ens.py`](../openclaw/tasks/ens.py) | ENSTask (deprecated → Coinbase ID) | ⚠️ Устарел | `openclaw/tasks/__init__.py` | `openclaw/tasks/base`, `openclaw/browser` | `ens_names`(пустая) |
| [`openclaw/tasks/coinbase_id.py`](../openclaw/tasks/coinbase_id.py) | CoinbaseIDTask (замена ENS, FREE) | ✅ Да | `openclaw/executor.py` | `openclaw/tasks/base`, `openclaw/browser` | — |
| [`openclaw/tasks/snapshot.py`](../openclaw/tasks/snapshot.py) | SnapshotTask | ✅ Да | `openclaw/executor.py` | `openclaw/tasks/base`, `openclaw/browser` | `snapshot_votes`(пустая) |
| [`openclaw/tasks/lens.py`](../openclaw/tasks/lens.py) | LensTask | ✅ Да | `openclaw/executor.py` | `openclaw/tasks/base`, `openclaw/browser` | `lens_profiles`(пустая) |
| [`openclaw/anti_detection/__init__.py`](../openclaw/anti_detection/__init__.py) | ❓ Пустой пакет | ❌ Никем | — | — | — |
| **RESEARCH** |
| [`research/protocol_analyzer.py`](../research/protocol_analyzer.py) | ProtocolAnalyzer (582 LOC): LLM-агент, оценка протоколов | ✅ Да | `research/scheduler.py` | `db_manager`, aiohttp | `protocol_research_pending`(3), `research_logs`(2), `protocols`(пустая) |
| [`research/news_aggregator.py`](../research/news_aggregator.py) | NewsAggregator: CryptoPanic, RSS feeds | ✅ Да | `research/scheduler.py` | `db_manager`, aiohttp | `news_items`(пустая), `research_logs`(2) |
| [`research/news_analyzer.py`](../research/news_analyzer.py) | NewsAnalyzer: keyword фильтрация | ✅ Да | `research/scheduler.py` | — | — |
| [`research/scheduler.py`](../research/scheduler.py) | ResearchScheduler: weekly research цикл | ✅ Да | `master_node/jobs.py` | `db_manager`, все `research/*` | `research_logs`(2 запуска) |
| **WALLETS** |
| [`wallets/generator.py`](../wallets/generator.py) | WalletGenerator (517 LOC): 90 кошельков, Fernet, worker assignment | ✅ Да (разово) | deploy-скрипт | `db_manager`, eth_account | `wallets`(90), `wallet_personas`(90), `funding_withdrawals` |
| [`wallets/personas.py`](../wallets/personas.py) | PersonaGenerator (237 LOC): 12 архетипов, Gaussian | ✅ Да (разово) | `wallets/generator.py`, migration 027 | `db_manager` | `wallet_personas`(90), `worker_nodes`(3), `proxy_pool`(475) |
| **WITHDRAWAL** |
| [`withdrawal/orchestrator.py`](../withdrawal/orchestrator.py) | WithdrawalOrchestrator (1158 LOC): Tier-стратегии, Telegram approval | ✅ Да | `master_node/jobs.py` | `db_manager`, `strategies`, `validator`, `infrastructure/*` | `withdrawal_plans`(пустая), `withdrawal_steps`(пустая), `wallets` |
| [`withdrawal/consolidation_orchestrator.py`](../withdrawal/consolidation_orchestrator.py) | ConsolidationOrchestrator: сбор через intermediate кошельки | ⚠️ Неясно | `master_node/jobs.py`? | `db_manager`, eth_account | `consolidation_plans`(пустая), `intermediate_*_deprecated_v2`(пустые) |
| [`withdrawal/strategies.py`](../withdrawal/strategies.py) | TierStrategy: A(4 steps), B(3), C(2) | ✅ Да | `withdrawal/orchestrator.py` | numpy | — |
| [`withdrawal/validator.py`](../withdrawal/validator.py) | WithdrawalValidator (20K chars): защита от burn address, баланс | ✅ Да | `withdrawal/orchestrator.py` | `db_manager` | `wallets`, `withdrawal_steps`(пустая) |
| **WORKER** |
| [`worker/api.py`](../worker/api.py) | Flask API (895 LOC): JWT auth, withdrawal execution | ✅ Да | Master (via HTTP) | `db_manager`, `activity/proxy_manager`, web3 | `wallets`(90), `proxy_pool`(475), `scheduled_transactions`(пустая) |

---

### 1.2 Корневые скрипты (одноразовые/служебные)

| Файл | Тип | Назначение | Вердикт |
|------|-----|-----------|---------|
| `apply_migration_024.py` | migration | Migration 024 (subaccount uniqueness) | ❌ УДАЛИТЬ |
| `apply_migration_026.py` | migration | Direct Funding Architecture | ❌ УДАЛИТЬ |
| `apply_migration_027.py` | migration | Fix preferred hours diversity | ❌ УДАЛИТЬ |
| `apply_migration_028.py` | migration | Warmup state machine | ❌ УДАЛИТЬ |
| `apply_migration_029.py` | migration | Wallet denormalization | ❌ УДАЛИТЬ |
| `apply_migration_031.py` | migration | Bridge Manager v2 schema | ❌ УДАЛИТЬ |
| `apply_migration_032.py` | migration | Protocol Research Bridge | ❌ УДАЛИТЬ |
| `apply_migration_033.py` | migration | Timezone fix | ❌ УДАЛИТЬ |
| `apply_migration_034.py` | migration | Gas logic refactoring | ❌ УДАЛИТЬ |
| `apply_proxy_redistribution.py` | setup | Оркестрирует перераспределение прокси | ❌ УДАЛИТЬ |
| `assign_consolidation_proxies.py` | setup | Назначение прокси consolidation кошелькам | ❌ УДАЛИТЬ |
| `assign_proxies_to_intermediate_wallets.py` | setup | Назначение прокси intermediate кошелькам | ❌ УДАЛИТЬ |
| `audit_anti_sybil_comprehensive.py` | audit | Aудит anti-Sybil паттернов (pandas, scipy) | 🔧 → `tests/` |
| `audit_temporal_patterns.py` | audit | Аудит temporal patterns | 🔧 → `tests/` |
| `check_and_redistribute_wallets.py` | fix | Перераспределение кошельков + SQL | ❌ УДАЛИТЬ |
| `check_db_complete.py` | debug | Проверка состояния БД | ❌ УДАЛИТЬ (дублирует `db_full_audit.py`) |
| `check_funding_assignments.py` | debug | Проверка funding assignments | ❌ УДАЛИТЬ |
| `check_migration.py` | debug | Статус migration 029 | ❌ УДАЛИТЬ |
| `check_postgresql_master.sh` | debug | Диагностика PostgreSQL настроек | 🔧 → `scripts/` |
| `check_proxy_pool.py` | debug | Распределение прокси по регионам | ❌ УДАЛИТЬ |
| `check_system_ready.py` | debug | Готовность системы | ❌ УДАЛИТЬ (дублирует `validate_pre_sepolia.py`) |
| `check_wallet_timezones.py` | debug | Timezone кошельков | ❌ УДАЛИТЬ |
| `check_wallets_structure.py` | debug | Структура таблицы wallets | ❌ УДАЛИТЬ |
| `check_worker3_status.py` | debug | Статус Worker 3 | ❌ УДАЛИТЬ |
| `db_full_audit.py` | audit | Полный аудит БД | 🔧 → `tests/` |
| `fix_funding_networks.py` | hotfix | Исправление сетей funding | ❌ УДАЛИТЬ |
| `generate_whitelist_files.py` | setup | Генерация CSV белых списков для бирж | ✅ ОСТАВИТЬ |
| `generate_whitelist_files_debug.py` | debug | Debug-версия whitelist | ❌ УДАЛИТЬ (дублирует) |
| `install_curl_cffi.sh` | setup | Установка curl_cffi | ✅ ОСТАВИТЬ |
| `master_setup.sh` | setup | Настройка Master Node | ✅ ОСТАВИТЬ |
| `nods.md` | **security** | **❗СОДЕРЖИТ РЕАЛЬНЫЕ root-ПАРОЛИ, SSH-КЛЮЧИ, PROXY CREDENTIALS** | ❌ УДАЛИТЬ НЕМЕДЛЕННО |
| `query_intermediate_wallets.py` | debug | SQL к intermediate wallets | ❌ УДАЛИТЬ |
| `quick_check.py` | debug | Однострочник count | ❌ УДАЛИТЬ |
| `redistribute_proxies_simple.py` | fix | Перераспределение прокси NL/IS/CA | ❌ УДАЛИТЬ |
| `redistribute_wallet_proxies.py` | fix | Перераспределение прокси per chain | ❌ УДАЛИТЬ |
| `requirements.txt` | config | Python зависимости | ✅ ОСТАВИТЬ |
| `setup_direct_funding.py` | setup | Настройка direct funding v3.0 | ✅ ОСТАВИТЬ |
| `setup_intermediate_wallets.py` | setup | Генерация intermediate wallets (v2 DEPRECATED) | ❌ УДАЛИТЬ |
| `test_whitelist.py` | debug | Тест whitelist query | ❌ УДАЛИТЬ |
| `update_cex_credentials.py` | setup | Обновление CEX API ключей | ✅ ОСТАВИТЬ |
| `validate_pre_production.py` | validate | 22 проверки перед mainnet | ✅ ОСТАВИТЬ |
| `validate_pre_sepolia.py` | validate | 15 проверок перед Sepolia | ✅ ОСТАВИТЬ |
| `verify_cex_keys.py` | verify | Верификация CEX ключей | ✅ ОСТАВИТЬ |
| `verify_direct_funding.py` | verify | Верификация funding schedule | ✅ ОСТАВИТЬ |
| `verify_monitoring_proxy_fixes.sh` | debug | Shell-проверка proxy fixes в коде | ❌ УДАЛИТЬ |
| `verify_proxy_chaos.py` | debug | Проверка случайности прокси | ❌ УДАЛИТЬ |
| `verify_proxy_distribution.py` | verify | Верификация proxy distribution | 🔧 → `tests/` |
| `verify_timezone_fix.py` | debug | Timezone fix CA кошельков | ❌ УДАЛИТЬ (migration 033 применена) |
| `view_schedule.py` | debug | Просмотр schedule из БД | ❌ УДАЛИТЬ |
| `worker_setup.sh` | setup | Настройка Worker Node | ✅ ОСТАВИТЬ |
| `=3.0.0` | **мусор** | Пустой файл | ❌ УДАЛИТЬ НЕМЕДЛЕННО |
| `.gitignore` | config | Git ignore | ✅ ОСТАВИТЬ |
| `ACTION_ITEMS_FIXES.md` | documentation | P0-P3 issues | ✅ ОСТАВИТЬ |
| `AUDIT.md` | documentation | Template для аудита | ✅ ОСТАВИТЬ |
| `Crypto.md` | documentation | ТЗ v4.0 | ✅ ОСТАВИТЬ |
| `changelog.md` | documentation | Changelog | ✅ ОСТАВИТЬ |

---

## ШАГ 3 — ГРАФ ЗАВИСИМОСТЕЙ

### 3.1 Иерархия вызовов

```
master_node/orchestrator.py (ТОЧКА ВХОДА)
    └── master_node/jobs.py (6 job-функций, lazy imports)
            ├── activity/scheduler.py → activity/bridge_manager.py
            │                        → database/db_manager.py
            ├── research/scheduler.py → research/news_aggregator.py
            │                        → research/protocol_analyzer.py
            │                        → research/news_analyzer.py
            ├── monitoring/airdrop_detector.py → infrastructure/identity_manager.py
            ├── withdrawal/orchestrator.py → withdrawal/strategies.py
            │                             → withdrawal/validator.py
            │                             → infrastructure/network_mode.py
            ├── funding/engine_v3.py → funding/cex_integration.py
            │                        → infrastructure/gas_logic.py
            └── activity/bridge_manager.py → infrastructure/chain_discovery.py
                                            → infrastructure/gas_logic.py

worker/api.py (ТОЧКА ВХОДА — Worker Node)
    ├── database/db_manager.py
    ├── activity/proxy_manager.py
    ├── activity/executor.py → activity/bridge_manager.py
    │                        → infrastructure/identity_manager.py
    │                        → infrastructure/ip_guard.py
    └── openclaw/executor.py → openclaw/browser.py
                             → openclaw/llm_vision.py
                             → openclaw/tasks/*
```

### 3.2 Циклические зависимости: НЕ ОБНАРУЖЕНО

### 3.3 БАГ: Дублирующийся метод в db_manager.py
[`log_system_event()`](../database/db_manager.py:777) определён **дважды** (строки 777 и 898). Второй перезаписывает первый.

---

## ШАГ 4 — ВЕРДИКТЫ ПО ФАЙЛАМ (модули)

| Файл | Вердикт | Причина |
|------|---------|---------|
| `database/db_manager.py` | 🔧 РЕФАКТОРИТЬ | BUG: `log_system_event()` определён дважды (строки 777/898) |
| `database/schema.sql` | 🔧 РЕФАКТОРИТЬ | Устарел — не включает 22 таблицы из миграций 002-036 |
| `database/seed_proxies.sql` | ⚠️ ПРОВЕРИТЬ | В БД 475 прокси, seed создаёт ~200 — возможно seed запускался N раз |
| `activity/scheduler.py` | ✅ ОСТАВИТЬ | |
| `activity/executor.py` | ✅ ОСТАВИТЬ | |
| `activity/adaptive.py` | ✅ ОСТАВИТЬ | |
| `activity/bridge_manager.py` | ✅ ОСТАВИТЬ | |
| `activity/proxy_manager.py` | ✅ ОСТАВИТЬ | |
| `activity/tx_types.py` | ✅ ОСТАВИТЬ | |
| `activity/exceptions.py` | ✅ ОСТАВИТЬ | |
| `funding/engine_v3.py` | ✅ ОСТАВИТЬ | |
| `funding/cex_integration.py` | ✅ ОСТАВИТЬ | |
| `funding/secrets.py` | ✅ ОСТАВИТЬ | |
| все `infrastructure/*` | ✅ ОСТАВИТЬ | |
| `master_node/orchestrator.py` | ✅ ОСТАВИТЬ | |
| `master_node/jobs.py` | ✅ ОСТАВИТЬ | |
| все `monitoring/*` | ✅ ОСТАВИТЬ | |
| `notifications/telegram_bot.py` | ✅ ОСТАВИТЬ | |
| `openclaw/manager.py` | ✅ ОСТАВИТЬ | |
| `openclaw/executor.py` | ✅ ОСТАВИТЬ | |
| `openclaw/browser.py` | ✅ ОСТАВИТЬ | |
| `openclaw/fingerprint.py` | ✅ ОСТАВИТЬ | |
| `openclaw/llm_vision.py` | ✅ ОСТАВИТЬ | |
| `openclaw/exceptions.py` | ✅ ОСТАВИТЬ | |
| `openclaw/tasks/base.py` | ✅ ОСТАВИТЬ | |
| `openclaw/tasks/gitcoin.py` | ✅ ОСТАВИТЬ | |
| `openclaw/tasks/poap.py` | ✅ ОСТАВИТЬ | |
| `openclaw/tasks/ens.py` | 🔧 РЕФАКТОРИТЬ | DEPRECATED — пометить в docstring, не вызывать |
| `openclaw/tasks/coinbase_id.py` | ✅ ОСТАВИТЬ | Актуальная замена ENS |
| `openclaw/tasks/snapshot.py` | ✅ ОСТАВИТЬ | |
| `openclaw/tasks/lens.py` | ✅ ОСТАВИТЬ | |
| `openclaw/anti_detection/__init__.py` | ❌ УДАЛИТЬ | Пустой пакет, никем не используется |
| все `research/*` | ✅ ОСТАВИТЬ | |
| `wallets/generator.py` | ✅ ОСТАВИТЬ | |
| `wallets/personas.py` | ✅ ОСТАВИТЬ | |
| `withdrawal/orchestrator.py` | ✅ ОСТАВИТЬ | |
| `withdrawal/consolidation_orchestrator.py` | ⚠️ УТОЧНИТЬ | `intermediate_*` deprecated; может понадобиться при withdrawal phase |
| `withdrawal/strategies.py` | ✅ ОСТАВИТЬ | |
| `withdrawal/validator.py` | ✅ ОСТАВИТЬ | |
| `worker/api.py` | ✅ ОСТАВИТЬ | |
| все `tests/*` | ✅ ОСТАВИТЬ | |

---

## ШАГ 6 — ЦЕЛЕВАЯ АРХИТЕКТУРА

### 6.1 Слои после чистки

```
ORCHESTRATION (2 файла)
  master_node/orchestrator.py  ←→  master_node/jobs.py

LOGIC (21 файл)
  activity/{scheduler, executor, adaptive, bridge_manager, proxy_manager, tx_types, exceptions}
  funding/{engine_v3, cex_integration, secrets}
  withdrawal/{orchestrator, consolidation_orchestrator, strategies, validator}
  wallets/{generator, personas}
  openclaw/{manager, executor, browser, fingerprint, llm_vision, exceptions, tasks/*}
  research/{protocol_analyzer, news_aggregator, news_analyzer, scheduler}
  notifications/telegram_bot.py
  monitoring/{airdrop_detector, health_check, token_verifier}

UTILS (7 файлов)
  infrastructure/{identity_manager, gas_logic, gas_controller, chain_discovery, 
                  ip_guard, network_mode, simulator}

DATA (5 файлов)
  database/db_manager.py
  database/schema.sql  (нужно обновить!)
  database/migrations/001-036
  database/seed_*.sql

WORKER NODE (отдельная точка входа)
  worker/api.py → activity/executor.py + openclaw/executor.py

DEPLOY/CONFIG (корень, постоянные)
  master_setup.sh, worker_setup.sh, install_curl_cffi.sh, requirements.txt,
  setup_direct_funding.py, update_cex_credentials.py, generate_whitelist_files.py,
  verify_cex_keys.py, verify_direct_funding.py,
  validate_pre_production.py, validate_pre_sepolia.py

TESTS (после переноса)
  tests/{test_bridge_manager_v2, test_dryrun_mode, test_gaussian_distribution,
         test_llm_vision_architecture, test_sepolia_integration, test_tier_a_sync,
         verify_tls_distribution, verify_proxy_distribution,
         audit_anti_sybil_comprehensive, audit_temporal_patterns, db_full_audit}
```

### 6.2 Метрики

| Показатель | До | После |
|------------|-----|-------|
| Python файлов в корне | 43 | 13 |
| Всего Python файлов | ~155 | ~128 |
| Таблиц в БД | 52 | 52 (без удалений, переименования уже выполнены) |
| Таблиц заполненных | 12 | 12 (будет расти по мере запуска) |
| Индексов | 231 | 231 |
| ENUMs | 15 | 15 |
| Views | 10 | 10 |
| PostgreSQL functions | 27 | 27 |

---

## ПРИОРИТЕТЫ ЧИСТКИ (обновлён)

### 🔴 НЕМЕДЛЕННО

1. **`nods.md` УДАЛИТЬ** — содержит `root` пароли серверов, SSH приватный ключ, proxy user/pass. Добавить в `.gitignore`
2. **`=3.0.0` УДАЛИТЬ** — пустой файл с некорректным именем
3. **BUG в `db_manager.py`** — удалить дубликат `log_system_event()` на строке 898
4. **`database/schema.sql` ОБНОВИТЬ** — добавить все 22 таблицы из миграций 002-036

### 🟠 ПЕРЕД ЗАПУСКОМ

5. **Проверить суммы funding**: `avg $3.89 × 90 = $350`, ТЗ предполагает `$154` начальный бюджет. Суммы корректны? Запустить `SELECT * FROM v_direct_funding_schedule LIMIT 10`
6. **Создать `schema_migrations`** и записать v001-v036 чтобы защититься от повторного накатывания
7. **Проверить прокси**: реально 475 vs. ожидаемых 200. Проверить дублей: `SELECT ip_address, COUNT(*) FROM proxy_pool GROUP BY ip_address HAVING COUNT(*) > 1`
8. **Worker heartbeat устарел** (8 дней) — проверить статус воркеров и перезапустить при необходимости
9. **Реализовать warmup state machine** в [`activity/scheduler.py`](../activity/scheduler.py) — поля `warmup_status` добавлены migration 028, но код не обновлён

### 🟡 ТЕХНИЧЕСКИЙ ДОЛГ

10. Удалить 29 одноразовых корневых скриптов
11. Перенести 4 audit-скрипта в `tests/`
12. Пометить `openclaw/tasks/ens.py` как DEPRECATED
13. Удалить пустой `openclaw/anti_detection/__init__.py`
14. Расследовать `discovery_failures` (2 строки) — что не удалось обнаружить?

---

*Отчёт составлен: System Architect, 2026-03-10*  
*БД: прямое подключение к `farming_db @ 82.40.60.131` via SSH*  
*Покрытие: 155 Python-файлов + 52 реальные таблицы + 231 индекс + 27 PostgreSQL функций*
