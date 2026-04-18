# Funding Module

> **Модули 6-7:** CEX Integration & Funding Diversification Engine  
> **Статус:** 🔶 В разработке (1/2 модулей готов)

---

## 📦 Модули

### ✅ Module: `secrets.py` — CEX API Keys Encryption
**Статус:** Готов к использованию

**Функционал:**
- Шифрование API ключей 18 CEX субаккаунтов
- Расшифровка для использования в CCXT
- Верификация шифрования
- CLI interface для управления

**Использование:**
```bash
# Зашифровать ключи
python funding/secrets.py encrypt-cex-keys

# Проверить шифрование
python funding/secrets.py verify-encryption
```

**Документация:** [`docs/CEX_ENCRYPTION_GUIDE.md`](../docs/CEX_ENCRYPTION_GUIDE.md)

---

### ⏳ Module: `cex_integration.py` — CCXT Exchange Manager
**Статус:** Планируется

**Функционал:**
- Унифицированный интерфейс к 5 биржам (Binance, Bybit, OKX, KuCoin, MEXC)
- Проверка балансов
- Withdrawal через L2 сети
- Retry logic с экспоненциальным backoff
- Rate limiting (соблюдение API лимитов)

**Зависимости:**
- `ccxt==4.3.95`
- `funding/secrets.py` (расшифровка ключей)

---

### ⏳ Module: `diversification.py` — Funding Diversification Engine
**Статус:** Планируется

**Функционал:**
- Управление 18 funding chains
- Temporal isolation (60-240 мин между выводами)
- Shuffle mode (рандомизация порядка кошельков)
- Bridge emulation (пауза 2-4 часа после получения средств)
- Интеграция с `cex_integration.py`

**Алгоритм:**
1. Shuffle кошельки в каждой цепочке (не 1,2,3,4,5 → random)
2. Для каждого кошелька:
   - Рассчитать сумму с ±25% шумом
   - Выполнить withdrawal через `cex_integration.py`
   - Задержка 60-240 мин (базовая) или 300-600 мин (25% шанс "длинной паузы")
   - Проверка ночного времени: если 2-6 утра UTC → +20-60 мин
3. Mark wallet as funded в БД (`last_funded_at`)

---

## 🔐 Security

### Фernet Encryption

**Ключи шифруются с помощью Fernet (AES-128 CBC + HMAC SHA256):**

```python
from funding.secrets import SecretsManager

secrets = SecretsManager()

# Расшифровать credentials для OKX subaccount ID 1
creds = secrets.decrypt_cex_credentials(subaccount_id=1)
# → {
#     'exchange': 'okx',
#     'api_key': 'fcbc32ed-4923-4152-93e3-e7ef130a9d3d',
#     'api_secret': '2142F386984C039F492013EBBCA54CCC',
#     'api_passphrase': 'yIFdCq9812!'
# }
```

### Хранение

| Компонент | Локация | Permissions | Encryption |
|-----------|---------|-------------|------------|
| **Fernet Key** | `/root/.farming_secrets` | 600 | Plain (защищён правами доступа) |
| **API Keys (DB)** | PostgreSQL `cex_subaccounts` | 700 (БД) | ✅ Fernet encrypted |
| **Seed File** | `database/seed_cex_subaccounts.sql` | — | ❌ Plain text (удалить после шифрования!) |

---

## 📊 18 Funding Chains

Каждая цепочка финансирует 5 кошельков с уникальными параметрами:

| Chain | Exchange | Subaccount | Network | Base Amount | Wallets | Tier Distribution |
|-------|----------|------------|---------|-------------|---------|-------------------|
| 1 | OKX | AlphaTradingStrategy | MegaETH | $19.00 | 5 | Tier A (3) + B (2) |
| 2 | OKX | LongTermStakingVault | Arbitrum | $19.00 | 5 | Tier A (3) + B (2) |
| 3 | Binance | BinanceGridBotOne | Ink | $19.00 | 5 | Tier A (3) + B (2) |
| 4 | Bybit | BybitScalpMaster | Base | $19.00 | 5 | Tier A (3) + B (2) |
| 5-18 | ... | ... | Polygon/BNB | $3.00-$5.00 | 5 each | Tier B (3) + C (2) |

**Temporal Isolation между цепочками:**
- Day 1: Chains 1, 5, 9, 13, 17 (25 wallets)
- Day 2: Chains 2, 6, 10, 14, 18 (25 wallets)
- Day 3: Chains 3, 7, 11, 15 (20 wallets)
- Day 4: Chains 4, 8, 12, 16 (20 wallets)
- Day 5: Reserve / verification

**Итого:** 90 кошельков за 4-5 дней = максимальная Anti-Sybil защита

---

## 🛠️ Usage Example

```python
from funding.cex_integration import CEXManager
from funding.diversification import FundingDiversificationEngine
from database.db_manager import DatabaseManager

# Инициализация
db = DatabaseManager()
cex = CEXManager()
funding_engine = FundingDiversificationEngine(db, cex)

# Запустить funding для chain #1 (OKX → MegaETH → 5 Tier A wallets)
await funding_engine.execute_funding_chain(chain_id=1)

# Процесс:
# 1. Get chain details from funding_chains table
# 2. Get 5 assigned wallets (shuffle order)
# 3. For each wallet:
#    - Calculate amount with ±25% noise
#    - Withdraw from OKX to wallet address via MegaETH
#    - Wait 60-240 min (or 300-600 min for "long pause")
# 4. Mark chain as completed
```

---

## 📁 File Structure

```
funding/
├── README.md                 # Этот файл
├── secrets.py                # ✅ CEX encryption/decryption (DONE)
├── cex_integration.py        # ⏳ CCXT wrapper for 5 exchanges
└── diversification.py        # ⏳ 18 funding chains orchestrator
```

---

## 🔗 Dependencies

```txt
# requirements.txt (уже установлено master_setup.sh)
ccxt==4.3.95               # CEX API unified interface
cryptography==42.0.8       # Fernet encryption
tenacity==8.5.0            # Retry logic with backoff
```

---

## 🚀 Roadmap

### Phase 1 (Completed)
- [x] `secrets.py` — Fernet encryption для CEX ключей
- [x] Documentation — CEX_ENCRYPTION_GUIDE.md
- [x] `.gitignore` — защита чувствительных файлов

### Phase 2 (Next)
- [ ] `cex_integration.py` — CCXT wrapper
- [ ] Unit tests для `secrets.py`
- [ ] Integration tests (mainnet forks)

### Phase 3 (Future)
- [ ] `diversification.py` — Funding orchestrator
- [ ] Telegram notifications для funding events
- [ ] Grafana dashboard для monitoring

---

**Статус:** 3/3 модулей готовы.

---

## 📁 Архитектурный анализ файлов модуля

### `secrets.py`

**Зачем:** Закрывает проблему безопасности хранения API ключей и паролей прокси в БД. Защищает от утечки при компрометации дампа БД.

**Бизнес-задача:** Шифрует/расшифровывает敏感ные данные (CEX API keys, proxy passwords) через Fernet (AES-128 CBC + HMAC SHA256).

**Интеграция:**
- Загружает Fernet ключ из `/root/.farming_secrets` (chmod 600)
- Шифрует поля `api_key`, `api_secret`, `api_passphrase` в `cex_subaccounts`
- Шифрует поле `password` в `proxy_pool`
- Создаёт backup перед шифрованием (`/root/cex_backups`, `/root/proxy_backups`)
- CLI interface: `encrypt-cex-keys`, `encrypt-proxy-passwords`, `verify-encryption`, `verify-proxy-encryption`

**Ключевые ограничения:**
- **Fernet signature check:** Зашифрованные значения начинаются с `gAAAAA`
- **Backup before encryption:** Автоматическое создание plain text backup (chmod 600)
- **Verification after encryption:** Проверка длины (>100 символов) и расшифровки
- **Passphrase optional:** Только OKX и KuCoin имеют `api_passphrase`

**Заглушки:** Нет.  
**Хардкод:** `/root/.farming_secrets`, `/root/cex_backups`, `/root/proxy_backups`, backup file naming pattern.

---

### `cex_integration.py`

**Зачем:** Закрывает проблему разрозненных API 5 бирж. Унифицирует withdrawal операции через единый интерфейс CCXT.

**Бизнес-задача:** Выполняет USDT withdrawal с 18 CEX субаккаунтов на кошельки через L2 сети (БЛОКИРУЕТ Ethereum mainnet).

**Интеграция:**
- 5 бирж: Binance, Bybit, OKX, KuCoin, MEXC (через CCXT 4.3.95)
- Расшифровка credentials через `SecretsManager`
- Retry logic: 3 попытки с exponential backoff (4-60 сек) для RateLimitExceeded, NetworkError
- Network code mapping: Human-readable → exchange-specific (Base → BASE, Arbitrum → ARBITRUM)
- BybitDirectClient: обходит CCXT V3 query-api bug через прямые V5 API calls

**Ключевые ограничения:**
- **L2 ONLY:** БЛОКИРУЕТ Ethereum mainnet — `ALLOWED_NETWORKS` whitelist
- **Balance check:** Проверка достаточности средств перед withdrawal
- **Whitelist verification:** Warning если address не в whitelist биржи (manual verification required)
- **Internal transfer:** Bybit требует Spot → Funding transfer перед withdrawal
- **OKX special handling:** Использует `privateGetAccountBalance` напрямую из-за CCXT 4.3.95 bug

**Заглушки:** Нет.  
**Хардкод:** `ALLOWED_NETWORKS` (8 сетей), `NETWORK_CODES` (5 бирж × 8 сетей), Bybit API URL, retry parameters (3 attempts, 4-60 сек backoff).

---

### `engine_v3.py`

**Зачем:** Закрывает проблему Sybil детекции через Star patterns (много кошельков получают средства с одного адреса). Eliminates intermediate wallets.

**Бизнес-задача:** Прямой CEX → wallet funding с interleaved execution: 90 кошельков получают средства напрямую с разных бирж без промежуточных адресов.

**Интеграция:**
- Создаёт funding chains с variable cluster sizes (3-7 кошельков, Gaussian distribution)
- Interleaved schedule: Round-robin между 5 биржами (не все с одной)
- Dynamic gas thresholds через `GasLogic` (MA_24h × multiplier)
- Dry-run mode через `NetworkModeManager` и `TransactionSimulator`
- Записывает в `funding_chains` и `funding_withdrawals` таблицы

**Ключевые ограничения:**
- **NO Star patterns:** Прямые CEX → wallet, без intermediate addresses
- **Interleaved execution:** Round-robin между биржами (4-6 withdrawals per round)
- **Temporal isolation:** 60-240 мин задержка, 25% шанс 300-600 мин ("ушёл спать")
- **Night delay:** 2-6 AM UTC → +20-60 мин
- **Weekend delay:** 30% шанс +360-720 мин
- **Gas-based triggering:** Dynamic thresholds через GasLogic (НЕ hardcoded!)
- **Amount precision:** 6 decimal places max (ROUND_HALF_UP)
- **Variable cluster sizes:** Gaussian (µ=5, σ=1.2), clipped [3, 7]

**Заглушки:** Нет.  
**Хардкод:** `AMOUNT_DECIMAL_PLACES = 6`, `MAX_BRIDGE_FEE_USDT`, `NETWORK_TO_CHAIN_ID` mapping, delay ranges (60-240, 300-600, 20-60 night, 360-720 weekend).

---

## 📊 Сводка Anti-Sybil механизмов в Funding

| Файл | Механизм | Защита от |
|------|----------|-----------|
| `engine_v3.py` | NO Star patterns | On-chain связность (все с одного адреса) |
| `engine_v3.py` | Interleaved execution | Single-C_exchange clustering |
| `engine_v3.py` | Variable cluster sizes | Одинаковые группы кошельков |
| `engine_v3.py` | Temporal isolation 60-240 мин | Синхронные выводы |
| `engine_v3.py` | Long pause 25% (5-10h) | Bot-like patterns |
| `engine_v3.py` | Night/Weekend delays | Ночная активность бота |
| `engine_v3.py` | Gas-based triggering | Высокий газ → детекция |
| `engine_v3.py` | Amount noise ±25% | Одинаковые суммы |
| `cex_integration.py` | L2 ONLY (Ethereum blocked) | Дорогие mainnet транзакции |
| `secrets.py` | Fernet encryption | Утечка API ключей при DB dump |

---

## 📈 Сводка по заглушкам и хардкоду

| Файл | Заглушки | Хардкод |
|------|----------|---------|
| `secrets.py` | ❌ Нет | ✅ **ДА** (secrets file path, backup paths, naming patterns) |
| `cex_integration.py` | ❌ Нет | ✅ **ДА** (ALLOWED_NETWORKS, NETWORK_CODES, retry params, API URLs) |
| `engine_v3.py` | ❌ Нет | ✅ **ДА** (decimal places, delay ranges, cluster size params, chain_id mapping) |

**Ключевой вывод:** Заглушек НЕТ. Все модули полностью реализованы.

Хардкод присутствует как конфигурация:
- Пути к файлам (secrets, backups)
- Списки сетей и бирж
- Параметры задержек и retry
- Маппинги network → chain_id

Это приемлемо для seed конфигурации и не требует выноса в env/config файлы.
