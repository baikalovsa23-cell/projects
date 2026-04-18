# Monitoring Module

Мониторинг системы: обнаружение аирдропов, верификация токенов, health checks компонентов.

---

## 📁 Архитектурный анализ файлов модуля

### `__init__.py`

**Зачем:** Точка входа модуля. Экспортирует публичный API для AirdropDetector, TokenVerifier, HealthCheckOrchestrator.

**Бизнес-задача:** Предоставляет единый интерфейс импорта для всех monitoring компонентов.

**Интеграция:**
- Экспортирует `AirdropDetector`, `TokenBalance`, `ScanCycleStats` (Module 17)
- Экспортирует `TokenVerifier`, `VerificationResult` (Module 18)
- Экспортирует `HealthCheckOrchestrator`, мониторы Workers/RPC/DB/Proxy (Module 20)
- Версия модуля: `0.20.0`

**Ключевые ограничения:** Нет.

**Заглушки:** Нет.  
**Хардкод:** Нет.

---

### `airdrop_detector.py` (Module 17)

**Зачем:** Закрывает проблему ручного мониторинга аирдропов. Автоматически обнаруживает новые токены на кошельках.

**Бизнес-задача:** Сканирует 90 кошельков на 7 chains каждые 6 часов, находит новые токены, верифицирует через CoinGecko, отправляет Telegram alerts.

**Интеграция:**
- **Explorer APIs:** Arbiscan, Basescan, Optimistic Etherscan, Polygonscan, BscScan (API keys из `.env`)
- **RPC fallback:** Для chains без explorer API (ink, megaeth) — заглушка, не реализовано
- **Token Verifier:** Вызывает Module 18 для верификации найденных токенов
- **Database:** `wallet_tokens`, `airdrops`, `airdrop_scan_logs` tables
- **Telegram:** Alerts при confidence > 0.6

**Ключевые ограничения:**
- **TLS fingerprinting:** Использует `curl_cffi` с browser-like fingerprint для каждого wallet_id
- **Rate limiting:** 0.2 сек между API calls (5 calls/sec)
- **Dust filter:** `MIN_BALANCE_THRESHOLD = 0.01` — игнорирует dust amounts
- **Non-airdrop filter:** Исключает stablecoins (USDC, USDT, DAI, etc.), wrapped native (WETH, WMATIC, etc.)
- **Confidence threshold:** Создаёт airdrop entry только при confidence > 0.6
- **Scan cycle:** 90 wallets × 7 chains = 630 API calls за ~2 минуты

**Заглушки:** ✅ **ДА** — `_fetch_tokens_via_rpc()` возвращает пустой список (не реализовано для ink, megaeth).  
**Хардкод:** `SUPPORTED_CHAINS`, `EXPLORER_CHAINS`, `RPC_ONLY_CHAINS`, `RATE_LIMIT_DELAY = 0.2`, `MIN_BALANCE_THRESHOLD = 0.01`, stablecoins/wrapped native sets.

---

### `token_verifier.py` (Module 18)

**Зачем:** Закрывает проблему детекции scam-токенов. Фильтрует false positives из Airdrop Detector.

**Бизнес-задача:** Верифицирует токены через CoinGecko API + эвристический анализ, рассчитывает confidence score (0.0-1.0).

**Интеграция:**
- **CoinGecko API:** Free tier (10k calls/month), проверяет листинг и market cap
- **Scam heuristics:** Regex patterns для детекции pump-and-dump, guaranteed returns, suspicious names
- **Legitimate patterns:** Whitelist для известных токенов (stablecoins, DeFi blue chips, native tokens)
- **Confidence calculation:** Base 0.5, +0.3 за CoinGecko листинг, +0.1 за market cap > $1B, -0.3 за scam flag

**Ключевые ограничения:**
- **Confidence threshold:** `is_verified_airdrop = confidence > 0.6 AND NOT is_scam_heuristic`
- **Scam detection:** Требуется ≥2 scam reasons И не в legitimate patterns
- **Rate limiting:** 1.5 сек между CoinGecko calls (free tier limits)
- **Chain mapping:** ink, megaeth не поддерживаются CoinGecko → None

**Заглушки:** Нет.  
**Хардкод:** `COINGECKO_BASE_URL`, `SCAM_PATTERNS` (6 regex patterns), `LEGITIMATE_PATTERNS` (4 regex patterns), chain_id_map, confidence calculation weights.

---

### `health_check.py` (Module 20)

**Зачем:** Закрывает проблему отсутствия видимости состояния системы. Обеспечивает мониторинг всех критичных компонентов.

**Бизнес-задача:** Запускает 4 фоновых монитора (Workers, RPC, DB, Proxy) с автоматическим failover и Telegram alerts.

**Интеграция:**
- **WorkerHealthMonitor:** Проверяет heartbeat каждые 60 сек, статус = healthy если < 2 мин с последнего heartbeat
- **RPCHealthMonitor:** Проверяет `eth_blockNumber` каждые 5 мин, automatic failover после 3 failures
- **DatabaseHealthMonitor:** Проверяет `SELECT 1` каждые 2 мин, статус = degraded если > 1 сек
- **ProxyHealthMonitor:** Валидирует 10% proxy каждые 6 часов, полная валидация Sunday 03:00 UTC
- **HealthCheckOrchestrator:** Координирует все мониторы как daemon threads

**Ключевые ограничения:**
- **Worker heartbeat threshold:** 2 минуты → offline
- **RPC failover:** 3 consecutive failures → disable primary, activate backup
- **RPC response time:** < 5 сек → healthy, ≥ 5 сек → degraded
- **DB response time:** < 1 сек → healthy, ≥ 1 сек → degraded
- **Proxy validation:** 10% random subset каждые 6 часов
- **Alert throttling:** 5 мин cooldown между одинаковыми alerts
- **TLS fingerprinting:** RPC checks используют random wallet_id (1-90) для proxy + fingerprint

**Заглушки:** Нет.  
**Хардкод:** `SUPPORTED_CHAINS` (8 chains), heartbeat threshold (120 сек), RPC failover threshold (3 failures), response time thresholds (5 сек RPC, 1 сек DB), proxy validation percentage (10%), `TEST_URL = 'https://ipinfo.io/json'`, check intervals (60 сек Workers, 5 мин RPC, 2 мин DB, 6 часов Proxy).

---

## 📊 Сводка Anti-Sybil механизмов в Monitoring

| Файл | Механизм | Защита от |
|------|----------|-----------|
| `airdrop_detector.py` | TLS fingerprinting per wallet | Детекция бота по одинаковому UA при API calls |
| `airdrop_detector.py` | Rate limiting 0.2 сек | API rate limit blocks |
| `health_check.py` | Random wallet_id для RPC checks | Кластеризация monitoring requests |
| `health_check.py` | Proxy для RPC health checks | IP детекция при мониторинге |

---

## 📈 Сводка по заглушкам и хардкоду

| Файл | Заглушки | Хардкод |
|------|----------|---------|
| `__init__.py` | ❌ Нет | ❌ Нет |
| `airdrop_detector.py` | ✅ **ДА** (`_fetch_tokens_via_rpc` не реализовано) | ✅ **ДА** (chains, thresholds, filters) |
| `token_verifier.py` | ❌ Нет | ✅ **ДА** (API URL, patterns, weights) |
| `health_check.py` | ❌ Нет | ✅ **ДА** (thresholds, intervals, chains, URLs) |

**Ключевой вывод:** Одна заглушка — RPC fallback для chains без explorer API (ink, megaeth). В production требует реализации через web3.py contract calls.

Хардкод присутствует как:
- Конфигурация chains и API endpoints
- Пороги детекции (thresholds)
- Regex patterns для scam detection
- Intervals для background monitoring
- Weights для confidence calculation

---

## 🔗 Зависимости между модулями

```
airdrop_detector.py → token_verifier.py (верификация токенов)
airdrop_detector.py → telegram_bot (alerts)
health_check.py → telegram_bot (alerts при failover)
health_check.py → proxy_manager (proxy для RPC checks)
```

---

## 📌 Рекомендации

1. **Реализовать RPC fallback:** `_fetch_tokens_via_rpc()` для ink, megaeth — критично для новых L2
2. **Вынести thresholds в config:** Heartbeat threshold, RPC failover threshold, confidence threshold
3. **Мониторинг CoinGecko quota:** Добавить счётчик API calls для контроля 10k/month лимита
