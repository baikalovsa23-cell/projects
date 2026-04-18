# Activity Module — Модули 10-13

> **Status:** ✅ Все модули реализованы  
> **Created:** 2026-02-25  
> **Updated:** 2026-03-23

---

## 📁 Структура модуля

```
activity/
├── __init__.py           # Экспорты модуля
├── scheduler.py          # Модуль 11: Gaussian-планировщик транзакций
├── tx_types.py           # Модуль 10: Transaction builders (SWAP, WRAP, APPROVE)
├── executor.py           # Модуль 12: On-chain выполнение транзакций через web3.py
├── adaptive.py           # Модуль 13: Адаптивный газ-контроллер + баланс-мониторинг
├── bridge_manager.py     # Bridge между L2 сетями (динамическая проверка CEX)
├── proxy_manager.py      # Управление wallet-to-proxy маппингом
└── exceptions.py         # Кастомные исключения (ProxyRequiredError)
```

---

## 📋 Анализ файлов

### `__init__.py`

**Зачем:** Точка входа модуля, экспортирует основные классы и обеспечивает backward compatibility.

**Бизнес-задача:** Предоставляет унифицированный API для планирования и выполнения транзакций 90 кошельков.

**Интеграция:** Экспортирует `ActivityScheduler`, `TransactionExecutor`, `AdaptiveGasController`, transaction builders и конфигурационные константы. Создаёт алиасы для backward compatibility (`GasManager`, `GasBalanceController`, `GasLogic`).

**Особенности:** Версия 0.8.0, консолидирован из deprecated модулей `infrastructure/gas_*.py`.

**Заглушки:** Нет.  
**Хардкод:** Нет.

---

### `scheduler.py` (Модуль 11)

**Зачем:** Закрывает проблему детекции Sybil-паттернов через синхронизацию активности. Генерирует уникальные расписания для каждого кошелька.

**Бизнес-задача:** Планирует транзакции на неделю вперёд с Gaussian распределением, имитируя человеческое поведение каждого из 90 кошельков.

**Интеграция:**
- Загружает персоны из `wallet_personas` (µ, σ, preferred_hours, tx_weights)
- Учитывает timezone кошелька из `proxy_pool` (не worker_nodes!)
- Создаёт записи в `weekly_plans` и `scheduled_transactions`
- Интегрируется с `BridgeManager` для проверки необходимости bridge

**Ключевые ограничения:**
- **Bridge emulation delay:** 12-24 часа после funding (P0 FIX 2026-02-28, было 2-4 часа)
- **Sleep window:** 03:00-06:00 local time — транзакции не планируются
- **Anti-sync:** Конфликты разрешаются Gaussian сдвигом 10-25 минут (mean=17.5, std=4)
- **Weekend activity:** -40% вероятность TX в субботу/воскресенье
- **Skip week probability:** Варьируется по архетипу (Ghost = 30%, ActiveTrader = 5%)

**Заглушки:** Нет.  
**Хардкод:** 
- `MIN_BRIDGE_DELAY_HOURS = 12`, `MAX_BRIDGE_DELAY_HOURS = 24`
- `MIN_SYNC_OFFSET = 10`, `MAX_SYNC_OFFSET = 25`

---

### `tx_types.py` (Модуль 10)

**Зачем:** Закрывает проблему детекции через одинаковые суммы транзакций. Строит параметры транзакций с anti-Sybil рандомизацией.

**Бизнес-задача:** Генерирует данные для on-chain транзакций (SWAP, WRAP, APPROVE) с Gaussian шумом в суммах и slippage.

**Интеграция:**
- Использует Web3 для кодирования ABI calls
- Загружает WETH адреса из БД (`chain_tokens`) с fallback на hardcoded
- Работает с DEX routers (Uniswap V2 pattern)

**Ключевые ограничения:**
- **Amount noise:** Gaussian (mean=0, std=8%), clipped ±25%
- **Slippage:** Рассчитывается как min_output = input × (1 - slippage%)
- **Infinite approval:** По умолчанию для approve (2^256 - 1)

**Заглушки:** Нет.  
**Хардкод:**
- WETH адреса для 8 цепочек (fallback при ошибке БД)
- Simplified ABI для ERC20, WETH, Uniswap V2 Router

---

### `executor.py` (Модуль 12)

**Зачем:** Закрывает проблему IP-leak и связывания кошельков через общий IP. Выполняет транзакции через wallet-specific прокси.

**Бизнес-задача:** Подписывает и отправляет on-chain транзакции для 90 кошельков с защитой от IP-based clustering.

**Интеграция:**
- Расшифровывает приватные ключи из БД (Fernet encryption)
- Получает wallet-specific прокси через `ProxyManager`
- Интегрирует TLS fingerprinting через `identity_manager`
- Pre-flight IP проверка через `ip_guard`
- Симуляция через `TransactionSimulator` перед отправкой
- Dry-run mode через `NetworkModeManager`

**Ключевые ограничения:**
- **Proxy REQUIRED:** Прямые подключения ЗАПРЕЩЕНЫ — выбросит `ProxyRequiredError`
- **Internal transfer blocked:** Нельзя отправлять на другой farm wallet (только CEX → wallet)
- **Nonce locks:** Per-wallet threading locks для защиты от race conditions
- **Gas randomization:** Gaussian noise ±2.5% для gas_limit, ±5% для gas_price
- **RPC failover:** Автоматическое переключение на fallback RPC

**Заглушки:** Нет.  
**Хардкод:**
- Fallback chain configs для 7 цепочек (Arbitrum, Base, Optimism, Polygon, BNB, Ink, MegaETH)

---

### `adaptive.py` (Модуль 13)

**Зачем:** Закрывает проблему выполнения TX при высоком газе и отслеживания балансов кошельков.

**Бизнес-задача:** Контролирует газ-цены в реальном времени и определяет оптимальные окна для выполнения транзакций. Мониторит балансы кошельков по Tier-ам.

**Интеграция:**
- Все RPC вызовы идут через прокси (критично для anti-Sybil)
- Кэширует газ-цены на 5 минут (TTL)
- Хранит историю 24 часа (288 точек)
- Динамические пороги: Threshold = MA_24h × Multiplier (L1=1.5x, L2=5x, Sidechain=2x)

**Ключевые ограничения:**
- **Tier thresholds:** A=0.003 ETH, B=0.002 ETH, C=0.001 ETH
- **High gas action:** Skip TX если gas > threshold, reschedule на off-peak (3-6 AM UTC)
- **Activity throttling:** -30% активность при sustained high gas (>3 часов)
- **CEX-only topup alerts:** НЕТ внутренних переводов между кошельками

**Заглушки:** Нет.  
**Хардкод:**
- `GAS_THRESHOLDS` и `GAS_THRESHOLDS_BY_CHAIN` для 8 цепочек
- `TIER_THRESHOLDS` для 3 Tier-ов
- `CACHE_TTL_SECONDS = 300`, `HISTORY_SIZE = 288`

---

### `bridge_manager.py`

**Зачем:** Закрывает проблему невозможности прямого вывода с CEX на некоторые L2 сети. Определяет необходимость bridge динамически.

**Бизнес-задача:** Проверяет через live CEX API, поддерживает ли биржа сеть протокола. Если нет — находит безопасный bridge маршрут.

**Интеграция:**
- `CEXNetworkChecker`: Live API запросы через CCXT к 5 биржам (Binance, Bybit, OKX, KuCoin, MEXC)
- `DeFiLlamaChecker`: Проверка безопасности bridge провайдеров (TVL, rank, hacks)
- `SocketAggregator`, `AcrossAggregator`: Получение quote для bridge
- Кэширование результатов на 24 часа в БД

**Ключевые ограничения:**
- **Safety score ≥ 60:** Авто-approve только для проверенных провайдеров
- **Manual whitelist:** Hop, Across, Stargate, Socket, Relay и др. — fallback при API недоступности
- **Network normalizations:** Fuzzy matching названий сетей (arbitrum=Arbitrum One=arb)

**Заглушки:** Нет.  
**Хардкод:**
- `ALL_CEXES = ['bybit', 'kucoin', 'mexc', 'okx', 'binance']`
- `MANUAL_WHITELIST` для 15 bridge провайдеров
- `CHAIN_IDS` для Socket и Across агрегаторов

---

### `proxy_manager.py`

**Зачем:** Закрывает проблему связывания 90 кошельков через 3 Worker IP. Обеспечивает 1:1 wallet-to-proxy mapping.

**Бизнес-задача:** Управляет постоянным назначением прокси для каждого кошелька с валидацией и health tracking.

**Интеграция:**
- Читает `wallets.proxy_id` → `proxy_pool` mapping
- Авто-валидация прокси через ipinfo.io
- Кэширование на 5 минут
- Обновление `last_used_at` и `validation_status` в БД

**Ключевые ограничения:**
- **Sticky sessions:** IPRoyal 7 дней, Decodo 60 мин
- **Geolocation alignment:** NL wallets → NL proxies, IS wallets → IS proxies
- **Auto-validation:** Проверка при первом использовании, затем по TTL

**Заглушки:** Нет.  
**Хардкод:**
- `_cache_ttl = 300` (5 минут)
- `VALIDATION_TEST_URL = 'https://ipinfo.io/json'`

---

### `exceptions.py`

**Зачем:** Определяет критическое исключение для защиты от IP leak.

**Бизнес-задача:** Гарантирует, что ни одна транзакция не будет выполнена без прокси.

**Интеграция:** Используется в `executor.py` и `adaptive.py` для блокировки операций без прокси.

**Особенности:** Прямые подключения FORBIDDEN — экспонируют VPS IP и связывают все 90 кошельков.

**Заглушки:** Нет.  
**Хардкод:** Нет.

---

## 🛡️ Anti-Sybil Механизмы (сводка)

| Файл | Механизм | Защита от |
|------|----------|-----------|
| `scheduler.py` | Gaussian µ/σ для каждого кошелька | Одинаковые паттерны активности |
| `scheduler.py` | Anti-sync (сдвиг 10-25 мин) | Синхронные транзакции |
| `scheduler.py` | Bridge emulation 12-24h | Bridge→activity timing pattern |
| `scheduler.py` | Sleep window 03:00-06:00 | Ночная активность бота |
| `tx_types.py` | Gaussian amount noise ±8% | Одинаковые суммы |
| `executor.py` | Proxy REQUIRED | IP-based clustering |
| `executor.py` | TLS fingerprinting | TLS fingerprinting |
| `executor.py` | Gas randomization | Gas-based fingerprinting |
| `executor.py` | Internal transfer blocked | On-chain связность |
| `adaptive.py` | Proxy для RPC calls | IP leak при мониторинге |
| `proxy_manager.py` | 1:1 wallet-proxy mapping | 90 кошельков = 90 IP |

---

## 📊 Таблицы БД

| Таблица | Модуль | Назначение |
|---------|--------|------------|
| `weekly_plans` | scheduler | Недельные планы по кошелькам |
| `scheduled_transactions` | scheduler | Запланированные TX |
| `wallet_personas` | scheduler | Параметры персон (µ, σ, weights) |
| `proxy_pool` | proxy_manager | Пул прокси с валидацией |
| `gas_history` | adaptive | История газ-цен |
| `cex_networks_cache` | bridge_manager | Кэш сетей CEX |
| `defillama_bridges_cache` | bridge_manager | Кэш safety данных |

---

## 🚀 Usage

### Генерация расписания

```python
from activity import ActivityScheduler

scheduler = ActivityScheduler()
count = scheduler.generate_for_all_wallets(week_start=datetime(2026, 3, 3, tzinfo=timezone.utc))
```

### Выполнение транзакции

```python
from activity import TransactionExecutor

executor = TransactionExecutor()
result = executor.execute_transaction(
    wallet_id=1,
    chain='arbitrum',
    to_address='0x...',
    value_wei=w3.to_wei(0.01, 'ether'),
    gas_preference='normal'
)
```

### Проверка газа

```python
from activity import AdaptiveGasController, check_chain_gas

result = await check_chain_gas(42161)  # Arbitrum
if result.status == GasStatus.HIGH_GAS:
    print(f"Wait {result.extra_delay_minutes} min")
```

---

**Author:** Airdrop Farming System v4.0
