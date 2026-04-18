# ДОРОЖНАЯ КАРТА airdrop_v4
## От сломанного кода до работающей фермы

---

# ФАЗА 0 — СТАБИЛИЗАЦИЯ (устранение блокирующих ошибок)
> Цель: система запускается без падений и пишет в правильные таблицы.
> Без этого запуск Sepolia невозможен.

---

## БЛОК 0.1 — КРИТИЧЕСКИЕ БАГИ БД (1 день)

### Задача 0.1.1 — Создать таблицу safety_gates
**Проблема:** `network_mode.py`, `orchestrator.py`, `run_validation_campaign.py`,
`test_dryrun_mode.py` — все обращаются к таблице `safety_gates` которой нет в БД.
Результат: система падает при старте.

**Промпт для GLM-5:**
```
Создай миграцию database/migrations/037_safety_gates.sql

Таблица должна содержать:
- id SERIAL PRIMARY KEY
- gate_name VARCHAR(100) UNIQUE NOT NULL  -- имя проверки
- is_enabled BOOLEAN DEFAULT true
- description TEXT
- last_checked_at TIMESTAMPTZ
- created_at TIMESTAMPTZ DEFAULT NOW()

После создания таблицы добавь INSERT с начальными значениями:
- 'mainnet_allowed' (false) — запрет mainnet по умолчанию
- 'funding_enabled' (false) — запрет финансирования по умолчанию
- 'withdrawal_enabled' (false) — запрет вывода по умолчанию
- 'openclaw_enabled' (false) — запрет браузерной автоматизации по умолчанию

Также добавь в database/db_manager.py методы:
- check_safety_gate(gate_name: str) -> bool
- set_safety_gate(gate_name: str, enabled: bool) -> None
```

---

### Задача 0.1.2 — Исправить несуществующие таблицы в коде
**Проблема:** Код пишет в таблицы которых нет → молчаливые ошибки.

| Файл | Несуществующая таблица | Правильная таблица |
|------|----------------------|-------------------|
| `activity/executor.py` | `wallet_transactions` | `scheduled_transactions` |
| `infrastructure/simulator.py` | `dry_run_logs` | `system_events` |

**Промпт для GLM-5:**
```
В файле activity/executor.py найди все упоминания таблицы 'wallet_transactions'
и замени на 'scheduled_transactions'. Проверь что колонки совпадают со схемой.

В файле infrastructure/simulator.py найди все упоминания 'dry_run_logs'
и замени логирование на вызов db_manager.log_system_event() который пишет
в таблицу system_events. Формат: severity='info', message=..., details=...
```

---

### Задача 0.1.3 — Исправить дубликат log_system_event в db_manager.py
**Проблема:** Метод определён дважды (строки 777 и 898). Второй перезаписывает первый.

**Промпт для GLM-5:**
```
В файле database/db_manager.py найди два определения метода log_system_event().
Оставь то которое на строке 777 (или более полное из двух).
Второе определение полностью удали.
Убедись что сигнатура метода совпадает с тем как его вызывают другие модули.
```

---

## БЛОК 0.2 — ЗАПОЛНИТЬ chain_rpc_endpoints (1 день)
> КРИТИЧНО. Сейчас в таблице 2 записи. Все модули которые читают RPC из БД
> работают вслепую. chain_discovery падает. BridgeManager не знает сети.

### Задача 0.2.1 — Создать полный seed для RPC эндпоинтов

**Промпт для GLM-5:**
```
Создай файл database/seed_chain_rpc_endpoints_v2.sql

Добавь RPC endpoints для ВСЕХ целевых сетей проекта.
Для каждой сети минимум 2 endpoint (primary + fallback).

Обязательные сети (из ТЗ и discovery_failures):
1. Ethereum Mainnet (chain_id: 1)
2. Arbitrum One (chain_id: 42161)
3. Base (chain_id: 8453)
4. Optimism (chain_id: 10)
5. Polygon (chain_id: 137)
6. BSC (chain_id: 56)
7. Avalanche (chain_id: 43114)
8. Linea (chain_id: 59144)
9. Scroll (chain_id: 534352)
10. zkSync Era (chain_id: 324)
11. Ink (chain_id: 57073) — есть в discovery_failures!
12. Unichain (chain_id: 1301) — есть в discovery_failures!
13. MegaETH (testnet, chain_id: 6342) — есть в discovery_failures!
14. Sepolia (chain_id: 11155111) — для тестов

Для каждой записи:
- chain_id (integer)
- chain_name (varchar)
- rpc_url (primary, публичный endpoint)
- rpc_url_fallback (второй публичный endpoint)
- is_l2 (boolean)
- is_testnet (boolean)
- native_token (ETH/BNB/MATIC etc)
- block_explorer_url

Используй только ПУБЛИЧНЫЕ бесплатные RPC (Alchemy public, Infura public,
официальные RPC сетей). НЕ используй приватные ключи.

После seed файла создай миграцию которая:
1. Очищает старые 2 записи
2. Вставляет все новые
3. Обновляет discovery_failures — помечает Ink/Unichain/MegaETH как resolved
```

---

### Задача 0.2.2 — Убрать хардкод RPC из кода
**Проблема:** Несмотря на таблицу chain_rpc_endpoints, в 3 местах RPC захардкожены.

**Промпт для GLM-5:**
```
Найди и исправь захардкоженные RPC и CHAIN_CONFIGS в следующих файлах:

1. activity/executor.py — найди CHAIN_CONFIGS = {...} или аналог
   Замени на загрузку из БД через db_manager метод get_chain_rpc_endpoints()
   который читает из таблицы chain_rpc_endpoints
   Кэшируй результат в памяти на 5 минут

2. activity/tx_types.py — найди захардкоженные WETH адреса для сетей
   Замени на загрузку из таблицы protocol_contracts
   Если записи нет в БД — использовать захардкоженный fallback с warning логом

3. infrastructure/network_mode.py — найди захардкоженные Sepolia RPC
   Замени на чтение из chain_rpc_endpoints WHERE chain_name = 'Sepolia'
   Если записи нет — использовать публичный fallback RPC

4. infrastructure/ip_guard.py — найди SERVER_IPS = [...]
   Перенеси список IP в конфиг-файл config/servers.yaml
   Загружай из файла при старте, не хардкодь в коде

5. infrastructure/simulator.py — найди GAS_HEURISTICS = {...}
   Замени на загрузку из chain_rpc_endpoints (там есть поля для gas)
   или вынеси в config/gas_heuristics.yaml

Важно: добавь db_manager.get_chain_rpc_endpoints() если его нет.
Метод должен возвращать dict {chain_id: {rpc_url, rpc_url_fallback, ...}}
```

---

## БЛОК 0.3 — ЗАГЛУШКИ В КРИТИЧЕСКИХ МЕТОДАХ (2 дня)

### Задача 0.3.1 — Реализовать execute_direct_cex_withdrawal()
**Проблема:** `funding/engine_v3.py` метод `execute_direct_cex_withdrawal()` —
PLACEHOLDER. Реальный вывод с CEX не реализован. Ферма не может получить деньги.

**Промпт для GLM-5:**
```
В файле funding/engine_v3.py найди метод execute_direct_cex_withdrawal()
который содержит PLACEHOLDER или заглушку.

Реализуй его полностью используя CEXManager из funding/cex_integration.py:

1. Получить параметры вывода из funding_withdrawals по withdrawal_id
2. Проверить баланс субаккаунта через cex_manager.get_balance()
3. Если balance < amount → записать ошибку в funding_withdrawals, return False
4. Выполнить вывод через cex_manager.withdraw(
     exchange=...,
     account_name=...,
     address=wallet_address,
     amount=amount_usdt,
     network=network,
     currency='USDT'
   )
5. При успехе:
   - Обновить funding_withdrawals.status = 'completed'
   - Записать txhash если есть
   - Залогировать через db_manager.log_system_event()
6. При ошибке:
   - Обновить status = 'failed', записать error_message
   - Если ошибка временная (rate limit, network) → status = 'retry'
   - Отправить алерт в Telegram

Также проверь что CEXManager.withdraw() в cex_integration.py реально
вызывает CCXT exchange.withdraw() а не тоже является заглушкой.
```

---

### Задача 0.3.2 — Реализовать Worker API execute_transaction
**Проблема:** `worker/api.py` эндпоинт `/execute_transaction` — mock.
Воркер получает задачи но не выполняет их.

**Промпт для GLM-5:**
```
В файле worker/api.py найди эндпоинт /execute_transaction
который содержит mock или заглушку.

Реализуй его полностью:

1. Получить задачу из request.json:
   {task_id, wallet_id, action_type, params, chain_id}

2. Получить кошелёк из БД (адрес + зашифрованный приватный ключ)
3. Расшифровать приватный ключ через SecretsManager
4. Получить прокси для кошелька через proxy_manager

5. Выбрать путь выполнения:
   a) Если action_type в [SWAP, LEND, BRIDGE, STAKE, WRAP, APPROVE]:
      → вызвать activity/executor.py execute_transaction()
   b) Если action_type в [GITCOIN, POAP, ENS, SNAPSHOT, LENS, COINBASE_ID]:
      → вызвать openclaw/executor.py execute_task()

6. Обновить scheduled_transactions.status = 'completed'/'failed'
7. Вернуть {success, tx_hash, gas_used, error}

Добавь обработку:
- Timeout 120 секунд на транзакцию
- Если приватный ключ не расшифровывается → 403
- Если прокси недоступен → retry с другим прокси (1 попытка)
- Race condition защита: проверить что задача не выполняется другим воркером
```

---

### Задача 0.3.3 — Исправить заглушки в validator.py
**Проблема:** `withdrawal/validator.py` методы `_check_balance()`,
`_estimate_gas()`, `estimate_withdrawal_gas()` — все возвращают хардкод.

**Промпт для GLM-5:**
```
В файле withdrawal/validator.py найди и реализуй методы-заглушки:

1. _check_balance(wallet_address, chain_id, required_amount):
   - Подключиться к RPC из chain_rpc_endpoints для данного chain_id
   - Вызвать web3.eth.get_balance(address)
   - Сравнить с required_amount (в wei)
   - Вернуть (bool, actual_balance_eth)

2. _estimate_gas(transaction_params, chain_id):
   - Использовать infrastructure/gas_logic.py GasLogic.get_current_gas_price()
   - НЕ дублировать логику, импортировать GasLogic
   - Вернуть gas_price_gwei

3. estimate_withdrawal_gas(wallet_id, withdrawal_plan):
   - Для каждого шага плана вызвать _estimate_gas()
   - Суммировать gas стоимость в USD (цена ETH из БД или хардкод $3000 с warning)
   - Вернуть total_gas_usd
```

---

### Задача 0.3.4 — Исправить scheduler (не проверяет финансирование)
**Проблема:** `activity/scheduler.py` создаёт расписание для кошельков
со статусом `inactive` (нефинансированных). Задачи никогда не выполнятся.

**Промпт для GLM-5:**
```
В файле activity/scheduler.py найди метод который генерирует недельное
расписание и добавь проверку:

Перед созданием scheduled_transactions для кошелька проверять:
1. wallet.status != 'inactive'  → если inactive, пропустить с логом
2. funding_withdrawals WHERE wallet_id = ? AND status = 'completed' EXISTS
   → если нет completed withdrawal, пропустить кошелёк с логом

Также добавь в начало scheduler'а проверку:
- Если 0 кошельков прошли фильтр → отправить Telegram алерт
  "Планировщик: все кошельки неактивны. Запустите финансирование."

В логах указывать: сколько кошельков добавлено в расписание из скольких.
```

---

### Задача 0.3.5 — Зарегистрировать воркеры в БД
**Проблема:** `worker_nodes` таблица пустая (0 строк).
Планировщик не может назначить задачи воркерам.

**Промпт для GLM-5:**
```
Создай скрипт setup_worker_nodes.py в корне проекта:

Скрипт должен:
1. Прочитать конфиг воркеров из конфига или из аргументов командной строки
2. Для каждого воркера INSERT OR UPDATE в worker_nodes:
   - worker_id (1, 2, 3)
   - hostname (например 'worker-nl-01')
   - ip_address
   - location (Amsterdam NL / Reykjavik IS)
   - status = 'active'
   - last_heartbeat = NOW()
   - assigned_wallet_tiers (например ['A', 'B'] для worker 1)

Данные для 3 воркеров (из предыдущего аудита):
- Worker 1: 82.40.60.132, Amsterdam NL, Tier A+B
- Worker 2: 82.22.53.183, Reykjavik IS, Tier B+C
- Worker 3: 82.22.53.184, Reykjavik IS, Tier C

После записи выводить статус каждого воркера.
```

---

## БЛОК 0.4 — GAS УНИФИКАЦИЯ (1 день)
**Проблема:** Газовая логика в 3 местах: `gas_logic.py`, `gas_controller.py`, `adaptive.py`
+ дублируется в `executor.py` и `validator.py`.

### Задача 0.4.1 — Слить газовые модули

**Промпт для GLM-5:**
```
Нужно слить три газовых модуля в один.

Текущее состояние:
- infrastructure/gas_logic.py → проверка текущей цены газа, L2 multiplier
- infrastructure/gas_controller.py → мониторинг балансов ETH у кошельков
- activity/adaptive.py → AdaptiveGasController, skip при высоком газе

Создай infrastructure/gas_manager.py который объединяет ВСЕ три:

class GasManager:
    # Из gas_logic.py:
    async def get_current_gas_price(chain_id) -> GasPrice
    async def should_skip_transaction(chain_id, threshold_multiplier) -> bool
    async def wait_for_acceptable_gas(chain_id, max_wait_minutes=30)

    # Из gas_controller.py:
    async def check_wallet_balances(wallet_ids) -> dict[int, float]
    async def needs_gas_topup(wallet_id, chain_id, min_threshold_eth=0.003) -> bool
    async def topup_gas(wallet_id, chain_id) -> bool

    # Из adaptive.py:
    async def adaptive_wait(chain_id) -> None  # wait until gas acceptable
    def get_monitoring_proxy() -> str

После создания gas_manager.py:
1. В gas_logic.py и gas_controller.py и adaptive.py оставь только:
   from infrastructure.gas_manager import GasManager
   (для обратной совместимости импортов)
2. Обнови импорты в файлах которые используют старые модули:
   - activity/bridge_manager.py
   - activity/executor.py
   - funding/engine_v3.py
   - monitoring/health_check.py
   - withdrawal/validator.py
```

---

# ФАЗА 1 — ЗАПУСК НА SEPOLIA (тестирование)
> После Фазы 0 система должна запускаться. Здесь мы проверяем что она
> правильно выполняет транзакции на тестнете.

## БЛОК 1.1 — ПОДГОТОВКА ТЕСТНЕТА (0.5 дня)

**Промпт для GLM-5:**
```
Подготовь систему к запуску на Sepolia testnet:

1. В infrastructure/network_mode.py установить режим TESTNET
   - Убедиться что все safety_gates для testnet открыты
   - mainnet_allowed = false (ОБЯЗАТЕЛЬНО)

2. Создать 10 тестовых кошельков в БД для Sepolia:
   - 2 Tier A (wallet_id 91-92)
   - 5 Tier B (wallet_id 93-97)
   - 3 Tier C (wallet_id 98-100)
   - Статус: inactive (будем финансировать через Sepolia faucet)

3. Добавить Sepolia в chain_rpc_endpoints если нет:
   chain_id=11155111, public RPC: https://rpc.sepolia.org

4. Написать скрипт tests/fund_sepolia_wallets.py:
   - Выводит адреса 10 тестовых кошельков
   - Выводит инструкцию по получению Sepolia ETH с faucet
   - После получения ETH — обновляет статус кошельков на 'active'
```

---

## БЛОК 1.2 — ТЕСТ ПОЛНОГО ЦИКЛА (1 день)

**Промпт для GLM-5:**
```
Создай интеграционный тест tests/test_full_cycle_sepolia.py

Тест должен проверить полный цикл:

ТЕСТ 1: Планирование
- Запустить activity/scheduler.py для 10 тестовых кошельков
- Проверить что scheduled_transactions НЕ пустая
- Проверить что нет задач для inactive кошельков

ТЕСТ 2: Выполнение SWAP на Sepolia
- Взять первую задачу типа SWAP из scheduled_transactions
- Отправить на Worker API
- Проверить что вернулся tx_hash (не mock)
- Проверить что scheduled_transactions.status = 'completed'

ТЕСТ 3: Gas мониторинг
- Вызвать GasManager.check_wallet_balances() для 10 кошельков
- Убедиться что балансы читаются (не захардкоженные значения)

ТЕСТ 4: Airdrop сканирование
- Запустить monitoring/airdrop_detector.py для 10 тестовых кошельков
- Проверить что airdrop_scan_logs получил запись (статус completed или no_airdrops)

ТЕСТ 5: Безопасность — mainnet заблокирован
- Попытаться выполнить TX с chain_id=1 (Ethereum mainnet)
- Убедиться что safety_gate 'mainnet_allowed'=false блокирует выполнение

Каждый тест: PASS/FAIL с деталями почему провалился.
```

---

# ФАЗА 2 — НОВЫЕ МОДУЛИ
> Только после того как Фаза 0 и Фаза 1 пройдены успешно.

---

## БЛОК 2.1 — Protocol Action Resolver v2.1

**Файлы для создания:**
- `protocol_research/action_resolver.py`
- `protocol_research/action_resolver_config.py`
- `protocol_research/type_detector.py`
- `database/migrations/037_protocol_action_resolver.sql`

**Промпт для GLM-5:**
```
Реализуй модуль protocol_research/action_resolver.py согласно ТЗ v2.1.

ПРИОРИТЕТ РЕАЛИЗАЦИИ (в таком порядке):

ШАГ 1: action_resolver_config.py
- 7 категорий протоколов (DEX/Lending/LiquidStaking/Restaking/YieldAggregators/Derivatives/Bridge)
- Для каждой: allowed_actions[], primary_action, weights, airdrop_priorities
- Конфигурация детерминированной рандомизации (seed=wallet_id)

ШАГ 2: type_detector.py — ProtocolClassifier
- Level 1: DefiLlama API /protocol/{name} (timeout 5s, retry 3x exponential)
- Level 2: LLM через OpenRouter (model из env PROTOCOL_CLASSIFIER_MODEL)
- Level 3: Telegram manual classification (кнопки classify_dex etc.)
- Кэш результатов в БД (поле protocols.category) на 30 дней

ШАГ 3: action_resolver.py — 4 класса:

class ProtocolClassifier:
    async def classify(protocol_name, chain, contract_address) -> (category, confidence, source)

class ActionMapper:
    def get_allowed_actions(category) -> list[str]
    def get_optimal_action(category, wallet_id, history) -> str  # детерминированный по wallet_id
    def get_weighted_random_action(category, wallet_id) -> str

class FailSafeValidator:
    async def validate_action(protocol_id, action_type, wallet_id) -> ValidationResult
    # ValidationResult: {valid, blocked_reason, suggested_action, auto_fix_applied}

class DeltaNeutralChainBuilder:  # только Tier A, min $15
    def build_conservative_chain(wallet, capital_eth) -> list[ChainStep]  # 4 протокола
    def build_aggressive_chain(wallet, capital_eth) -> list[ChainStep]   # 6 протоколов
    def validate_chain_dependencies(steps) -> bool

ШАГ 4: Интеграция
- В activity/executor.py: вызов FailSafeValidator.validate_action() перед КАЖДОЙ TX
- В activity/scheduler.py: вызов ActionMapper.get_optimal_action() при создании задач
- В research/protocol_analyzer.py: вызов ProtocolClassifier.classify() при новом протоколе

ШАГ 5: Миграция БД (037_protocol_action_resolver.sql)
Добавить в protocols:
- category VARCHAR(50)
- allowed_actions JSONB
- detection_confidence DECIMAL(3,2)
- detection_source VARCHAR(20) -- defillama/llm/manual

Создать таблицы:
- protocol_classification_history
- blocked_actions_log (protocol_id, wallet_id, attempted_action, auto_fixed, fixed_action)

НЕ используй Redis — кэшируй в БД и in-memory dict с TTL.
```

---

## БЛОК 2.2 — Smart Risk Engine (TokenGuard + RiskScorer)

**Файлы для создания:**
- `infrastructure/token_guard.py`
- `research/risk_scorer.py`
- Обновить `research/protocol_analyzer.py`

**Промпт для GLM-5:**
```
Реализуй Smart Risk Engine согласно ТЗ.

ШАГ 1: infrastructure/token_guard.py

class TokenGuard:
    async def check_token_exists(protocol_name, chain) -> TokenCheckResult
    # TokenCheckResult: {has_token, ticker, token_address, source}
    
    # Источники (приоритет):
    # 1. CoinGecko /coins/markets (кэш 24ч в БД cex_networks_cache или новая таблица)
    # 2. DefiLlama /protocol/{name} → поле 'symbol'
    
    async def mark_protocol_dropped(protocol_id, ticker) -> None
    # Обновить chain_rpc_endpoints.farm_status = 'DROPPED'
    # Отправить Telegram: "Прекращён фарм сети X: обнаружен токен $Y"
    
    async def run_periodic_check(interval_hours=24) -> None
    # Фоновая проверка всех ACTIVE протоколов

ШАГ 2: research/risk_scorer.py

class RiskScorer:
    async def score_protocol(protocol_name, description, chain, website) -> RiskScore
    # RiskScore: {risk_level, flags, recommendation, reasoning}
    
    # LLM промпт анализирует:
    # - Красные флаги: "Sybil", "Snapshot", "Proof of Humanity", "Passport", "KYC"
    # - Требования к капиталу: минимальный депозит > $500 → HIGH_CAPITAL
    # - Социальные требования: Discord/Twitter → MANUAL
    # - Категорийный бан: Derivatives, Options → AUTO_BAN (требуют PnL)
    # - Приоритет: L2/L3, DEX, Lending в Base/Ink/Unichain → HIGH_PRIORITY

    # Бритва Сибила (Hardcoded Rules — до LLM):
    BANNED_KEYWORDS = ['proof of humanity', 'gitcoin passport', 'kyc required',
                       'sybil check', 'identity verification']
    BANNED_CATEGORIES = ['derivatives', 'options', 'perpetuals']
    PRIORITY_CHAINS = ['base', 'ink', 'unichain', 'megaeth']
    
    # risk_level: LOW/MEDIUM/HIGH/CRITICAL
    # recommendation: APPROVE/MANUAL/REJECT

ШАГ 3: Обновить research/protocol_analyzer.py

В метод analyze_protocol() добавить ПЕРЕД сохранением в БД:

1. token_guard.check_token_exists() 
   → если has_token: пометить DROPPED, return (не анализировать дальше)

2. risk_scorer.score_protocol()
   → если CRITICAL/HIGH: статус MANUAL, Telegram алерт с деталями
   → если MEDIUM: статус APPROVED с предупреждением
   → если LOW: статус APPROVED

3. Только после прохождения обеих проверок:
   → action_resolver.ProtocolClassifier.classify()
   → Сохранить category + allowed_actions в protocols

ШАГ 4: Миграция — расширить chain_rpc_endpoints (или таблицу protocols):
ALTER TABLE protocols ADD COLUMN IF NOT EXISTS farm_status VARCHAR(20) DEFAULT 'ACTIVE';
ALTER TABLE protocols ADD COLUMN IF NOT EXISTS token_ticker VARCHAR(20);
ALTER TABLE protocols ADD COLUMN IF NOT EXISTS risk_level VARCHAR(20);
ALTER TABLE protocols ADD COLUMN IF NOT EXISTS risk_flags JSONB;
ALTER TABLE protocols ADD COLUMN IF NOT EXISTS last_token_check TIMESTAMPTZ;

НЕ используй Redis — кэш в БД.
```

---

# ФАЗА 3 — ФИНАЛЬНАЯ ПРОВЕРКА ЛОГИКИ

> После реализации Фаз 0, 1, 2 — сквозная проверка всего приложения.

**Промпт для GLM-5:**
```
Проверь сквозную логику всего приложения airdrop_v4.

Пройди ПОЛНЫЙ цикл работы фермы и проверь что каждый этап:
A) реализован (не заглушка)
B) передаёт данные следующему этапу
C) пишет в правильную таблицу БД

ЭТАП 1: Research → протоколы
- research/scheduler.py запускается → вызывает research/protocol_analyzer.py
- protocol_analyzer вызывает TokenGuard (новый) → RiskScorer (новый) → ProtocolClassifier
- Результат: запись в таблицу protocols (category, allowed_actions, farm_status)
- Проверь: есть ли хоть одна запись в protocols после запуска?

ЭТАП 2: Планирование → расписание
- activity/scheduler.py читает таблицу protocols (APPROVED записи)
- Для каждого активного кошелька + каждого протокола → scheduled_transactions
- ActionMapper.get_optimal_action() → правильное действие для категории
- Проверь: scheduled_transactions заполнена?

ЭТАП 3: Валидация → перед выполнением
- FailSafeValidator.validate_action() вызывается из executor.py?
- Тест: создать задачу SWAP для Lending протокола → должна быть заблокирована

ЭТАП 4: Выполнение → транзакции
- master_node/jobs.py берёт из scheduled_transactions задачи с наступившим временем
- Отправляет на worker/api.py через HTTP
- Worker выполняет через activity/executor.py (web3) или openclaw/executor.py (browser)
- Результат записывается обратно в scheduled_transactions
- Проверь: есть ли completed транзакции?

ЭТАП 5: Мониторинг → аирдропы
- monitoring/airdrop_detector.py сканирует все active кошельки
- Если найден токен с confidence>0.6 → запись в airdrops + Telegram
- Проверь: airdrop_scan_logs заполнен?

ЭТАП 6: Вывод → средства
- withdrawal/orchestrator.py вызывается после Telegram команды
- Строит план по тирам (A:15%+25%+30%+30%, B:20%+40%+40%, C:50%+50%)
- Отправляет на подтверждение → Telegram /approve_withdrawal_XXX
- После approve → выполняет через worker

ЭТАП 7: Gas → поддержка балансов
- infrastructure/gas_manager.py (новый объединённый) работает каждые 6 часов
- Проверяет балансы всех Tier A кошельков
- При balance < 0.003 ETH → topup с газового кошелька

ДЛЯ КАЖДОГО ЭТАПА ОТВЕТЬ:
✅ Работает — данные передаются корректно
⚠️ Работает частично — что именно не работает
❌ Сломано — что и почему

В конце: список оставшихся проблем по приоритету.
```

---

## ИТОГОВАЯ СТАТИСТИКА

| Фаза | Задач | Дней | Результат |
|------|-------|------|-----------|
| Фаза 0: Стабилизация | 10 | 4-5 | Система запускается |
| Фаза 1: Sepolia | 2 | 1-2 | Транзакции выполняются |
| Фаза 2: Новые модули | 2 | 5-7 | Полная автономность |
| Фаза 3: Проверка | 1 | 1 | Система работает как единое целое |
| **ИТОГО** | **15** | **11-15** | **Ферма готова к mainnet** |

---

*Каждый промпт — отдельное задание. Скармливать по одному.*
*Следующий промпт только после закрытия предыдущего.*