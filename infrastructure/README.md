# Infrastructure Module

Базовая инфраструктура системы: безопасность, идентификация, режимы работы, симуляция, обнаружение сетей.

---

## 📁 Архитектурный анализ файлов модуля

### `__init__.py`

**Зачем:** Точка входа модуля. Экспортирует публичные API для использования в других частях системы.

**Бизнес-задача:** Предоставляет единый интерфейс импорта для Identity, NetworkMode, TransactionSimulator.

**Интеграция:**
- Экспортирует `identity_manager`, `get_curl_session`, `get_async_curl_session`
- Экспортирует `NetworkMode`, `NetworkModeManager`, `is_dry_run`, `is_testnet`, `is_mainnet`
- Экспортирует `TransactionSimulator`, `SimulationResult`, `BalanceTracker`

**Ключевые ограничения:** Нет.

**Заглушки:** Нет.  
**Хардкод:** Нет.

---

### `identity_manager.py`

**Зачем:** Закрывает проблему детекции ботов по TLS fingerprint и User-Agent. Каждый кошелек должен иметь уникальный, консистентный "цифровой отпечаток" браузера.

**Бизнес-задача:** Генерирует детерминированную конфигурацию браузерного fingerprint для 90 кошельков: Chrome version, User-Agent, Client Hints, HTTP/2 support.

**Интеграция:**
- Вход: `wallet_id` (1-90)
- Выход: конфигурация для `curl_cffi` (impersonate) и Playwright (User-Agent)
- SHA256 hash от `seed_prefix + wallet_id` → детерминированный выбор параметров
- 4 Chrome версии: chrome110, chrome116, chrome120, chrome124 (~25% каждая)
- 2 платформы: Windows, macOS (50/50)

**Ключевые ограничения:**
- **Deterministic:** Один и тот же `wallet_id` всегда получает одинаковую конфигурацию
- **Tier A HTTP/2:** Кошельки 1-18 (Tier A) ОБЯЗАНЫ использовать HTTP/2 (L2 bridges check this)
- **Tier B/C HTTP/2:** Кошельки 19-90 — ~67% HTTP/2 enabled (diversity)
- **Desktop only:** `Sec-Ch-Ua-Mobile: ?0` — никогда не имитируем мобильные устройства
- **Thread-safe:** Может использоваться concurrently

**Заглушки:** Нет.  
**Хардкод:** `CHROME_VERSIONS` (4 версии), `seed_prefix = "wallet_identity_v1"`, Windows/macOS UA templates.

---

### `ip_guard.py`

**Зачем:** Закрывает критическую проблему безопасности: утечка реального IP серверов при сбое прокси. Если прокси упадёт, запрос может пойти с реального IP сервера → деанонимизация.

**Бизнес-задача:** Защищает от утечек IP через три механизма: Pre-flight check, TTL Guard, Heartbeat Monitor.

**Интеграция:**
- **SERVER_IPS:** Загружает IP серверов из `system_config` таблицы (fallback на hardcoded)
- **Pre-flight check:** Проверяет IP ПЕРЕД любым сетевым действием через `ifconfig.me`
- **TTL Guard:** Проверяет время жизни Decodo прокси (60 мин TTL, 10 мин buffer)
- **Heartbeat Monitor:** Фоновый поток проверяет IP каждые 60 сек во время длинных сессий

**Ключевые ограничения:**
- **CRITICAL EXIT:** При обнаружении утечки IP → `sys.exit(1)` (немедленная остановка)
- **Decodo TTL:** 60 минут, buffer 10 минут (ждать обновления если <10 мин осталось)
- **IPRoyal TTL:** 7 дней (всегда OK)
- **Telegram alert:** Отправляет критический алерт при утечке (если доступен)

**Заглушки:** Нет.  
**Хардкод:** Fallback SERVER_IPs (4 IP адреса), `DECODO_TTL_MINUTES = 60`, `DECODO_TTL_BUFFER_MINUTES = 10`, `check_interval_seconds = 60`, `ifconfig.me` URL.

---

### `network_mode.py`

**Зачем:** Закрывает проблему случайного запуска транзакций на mainnet. Разделяет окружения: разработка (dry-run), тестирование (testnet), продакшн (mainnet).

**Бизнес-задача:** Управляет режимами выполнения системы и обеспечивает safety gates для mainnet.

**Интеграция:**
- Читает `NETWORK_MODE` из `.env` (DRY_RUN, TESTNET, MAINNET)
- **DRY_RUN:** Симуляция без реальных транзакций, mock RPC
- **TESTNET:** Sepolia testnet (chain_id: 11155111)
- **MAINNET:** Production L2 chains с safety gates проверкой
- **Safety gates:** Запрос таблицы `safety_gates` — все gates должны быть `status = 'open'`
- **Decorator `@require_mode`:** Ограничивает выполнение функций определёнными режимами

**Ключевые ограничения:**
- **Singleton:** Только один экземпляр `NetworkModeManager`
- **Safety gates:** Mainnet блокируется если ANY gate закрыт
- **Sepolia config:** Зафиксирован в `SEPOLIA_CONFIG` (RPC URLs, faucets, test tokens)
- **Dry-run config:** Mock chain_id = 999999

**Заглушки:** Нет.  
**Хардкод:** `SEPOLIA_CONFIG` (chain_id, RPC URLs, faucets, test token addresses), `DRY_RUN_CONFIG`, `.env` path `/opt/farming/.env`.

---

### `simulator.py`

**Зачем:** Закрывает проблему тестирования транзакций без затрат. Позволяет валидировать логику в dry-run режиме перед mainnet.

**Бизнес-задача:** Симулирует транзакции (swap, bridge, stake, funding, withdrawal) с валидацией балансов, газа, адресов.

**Интеграция:**
- **BalanceTracker:** In-memory хранение симулированных балансов
- **Gas heuristics:** Загружает из `system_config` категории `gas` (fallback на hardcoded)
- **Gas price estimates:** Загружает из DB (fallback на hardcoded по цепям)
- **Transaction types:** SWAP, BRIDGE, STAKE, UNSTAKE, LP_ADD, LP_REMOVE, NFT_MINT, WRAP, UNWRAP, APPROVE, TRANSFER
- **SimulationResult:** would_succeed, failure_reason, estimated_gas, estimated_cost_usd, validation_checks, warnings

**Ключевые ограничения:**
- **Dry-run only update balance:** Балансы обновляются только в dry-run режиме
- **Gas noise ±20%:** Random variation для реалистичности
- **Gas price variation ±10%:** Random variation
- **ETH price:** Hardcoded $3000 для расчёта gas cost USD
- **Slippage assumption:** 0.5% для swaps, 0.1% для bridges
- **Validation checks:** balance_ok, gas_ok, to_address_valid

**Заглушки:** Нет.  
**Хардкод:** `ETH_PRICE_USD = 3000`, gas heuristics (fallback), gas price estimates (fallback по 9 цепям), slippage assumptions (0.5%, 0.1%).

---

### `chain_discovery.py`

**Зачем:** Закрывает проблему ручного добавления новых сетей. Автоматически обнаруживает и регистрирует сети из внешних источников.

**Бизнес-задача:** Обнаруживает chain metadata (chain_id, RPC, native token, explorer) из chainid.network, DeFiLlama, Socket и регистрирует в БД.

**Интеграция:**
- **External sources:** chainid.network (официальный EVM registry), DeFiLlama (TVL + metadata), Socket (bridge-supported chains)
- **Fuzzy matching:** RapidFuzz для нечёткого поиска (threshold 90%)
- **RPC health check:** Проверка каждого RPC endpoint перед регистрацией (timeout 1.5 сек)
- **Race condition protection:** Per-network `asyncio.Lock` для параллельных запросов
- **Negative cache:** Кеширует "not found" результаты на 1 час (защита от API spam)
- **Atomic registration:** Chain + aliases в одной транзакции

**Ключевые ограничения:**
- **L2 classification:** Автоматически определяет L2 по chain_id или "rollup" в имени
- **Gas multiplier:** L2 = 5.0x, L1 = 1.5x, sidechain = 2.0x
- **RPC validation:** Минимум 1 рабочий RPC для регистрации
- **Failure threshold:** 3 неудачные проверки RPC → `is_active = FALSE`
- **Aliases:** Автоматически добавляет name, short_name, normalized name

**Заглушки:** Нет.  
**Хардкод:** `CHAINID_URL`, `DEFILLAMA_URL`, `SOCKET_URL`, `L2_CHAIN_IDS` (9 chain IDs), `L1_CHAIN_IDS` (1 chain ID), `RPC_TIMEOUT = 1.5`, `negative_cache_ttl = 1 hour`, `failure_threshold = 3`.

---

## 📊 Сводка по Anti-Sybil и безопасности

| Файл | Механизм | Защита от |
|------|----------|-----------|
| `identity_manager.py` | Deterministic TLS fingerprint | Детекция ботов по одинаковому UA |
| `identity_manager.py` | Tier A HTTP/2 mandatory | L2 bridges детекция отсутствия HTTP/2 |
| `identity_manager.py` | Platform diversity (Win/Mac) | Кластеризация по платформе |
| `ip_guard.py` | IP leak detection | Деанонимизация IP серверов |
| `ip_guard.py` | TTL Guard | Смена IP во время сессии |
| `ip_guard.py` | Heartbeat Monitor | Прокси сбой во время сессии |
| `network_mode.py` | Safety gates | Случайный mainnet запуск |
| `simulator.py` | Dry-run validation | Ошибки в транзакциях на mainnet |

---

## 📈 Сводка по заглушкам и хардкоду

| Файл | Заглушки | Хардкод |
|------|----------|---------|
| `__init__.py` | ❌ Нет | ❌ Нет |
| `identity_manager.py` | ❌ Нет | ✅ **ДА** (Chrome versions, seed_prefix, UA templates) |
| `ip_guard.py` | ❌ Нет | ✅ **ДА** (fallback server IPs, TTL values, check interval, ifconfig.me) |
| `network_mode.py` | ❌ Нет | ✅ **ДА** (Sepolia config, dry-run config, .env path) |
| `simulator.py` | ❌ Нет | ✅ **ДА** (ETH price, gas heuristics fallback, slippage assumptions) |
| `chain_discovery.py` | ❌ Нет | ✅ **ДА** (API URLs, L2/L1 chain IDs, timeouts, thresholds) |

**Ключевой вывод:** Заглушек НЕТ. Все модули полностью реализованы.

Хардкод присутствует как:
- Fallback значения при ошибке загрузки из БД
- Конфигурация по умолчанию
- Внешние API endpoints
- Параметры безопасности (TTL, thresholds)

---

## 🔗 Зависимости между модулями

```
network_mode.py ← simulator.py (режим dry-run/testnet/mainnet)
identity_manager.py ← ip_guard.py (curl_cffi session для IP check)
chain_discovery.py → database (chain_rpc_endpoints, chain_aliases)
simulator.py → database (simulation_logs)
```

---

## 📌 Рекомендации

1. **Вынести в config:** ETH price ($3000) в simulator.py — должен быть динамическим
2. **Мониторинг:** Добавить алерт при fallback на hardcoded values
3. **Тестирование:** Unit tests для IP leak detection (критичный модуль безопасности)
