# OpenClaw Integration Module

> **Browser automation для Tier A кошельков (18 wallets)**  
> **Created:** 2026-02-25  
> **Status:** Phase 2 Complete (Browser automation implemented, ready for integration testing)

---

## 📋 Overview

OpenClaw Integration – это модуль для browser automation, который создает reputation profiles для 18 Tier A кошельков через off-chain/hybrid активности:

- **Gitcoin Passport:** 5+ stamps (GitHub, Twitter, Discord, Google, LinkedIn)
- **POAP Claiming:** 3-5 event participation badges
- **ENS/Coinbase ID:** FREE registration (cb.id recommended, base.eth, or ENS)
- **Snapshot Voting:** 5-10 governance votes per wallet
- **Lens Protocol:** Profile creation + 2-3 posts

**Цель:** Bypass Sybil detection алгоритмов и qualify для higher airdrop tiers (2-5x multipliers).

---

## 🏗️ Architecture

### Master-Worker Pattern

```
┌─────────────────────────────────────┐
│   Master Node                       │
│                                     │
│   OpenClawOrchestrator              │
│   - Schedule tasks                 │
│   - Queue to openclaw_tasks table   │
│   - NO browser automation           │
└──────────────┬──────────────────────┘
               │
               │ Tasks in PostgreSQL
               │
    ┌──────────┼──────────┐
    │          │          │
    v          v          v
┌──────┐  ┌──────┐  ┌──────┐
│Worker│  │Worker│  │Worker│
│  1   │  │  2   │  │  3   │
│ (NL) │  │ (IS) │  │ (IS) │
│      │  │      │  │      │
│OpenClaw│  │OpenClaw│  │OpenClaw│
│Executor│  │Executor│  │Executor│
│   +    │  │   +    │  │   +    │
│Browser │  │Browser │  │Browser │
│        │  │        │  │        │
│ Wallets│  │ Wallets│  │ Wallets│
│  1-6   │  │  7-12  │  │ 13-18  │
└────────┘  └────────┘  └────────┘
```

**Why This Design:**
- ✅ Master Node НЕ запускает browser → нет OOM риска
- ✅ Workers выполняют tasks → memory isolation
- ✅ Geographic distribution → better IP diversity
- ✅ Scalability → easy to add Worker 4-7 later

---

## 📦 Module Structure

```
openclaw/
├── __init__.py              # Module exports
├── manager.py               # OpenClawOrchestrator (Master-side)
├── executor.py              # OpenClawExecutor (Worker-side)
├── browser.py               # Browser automation engine ✅
├── fingerprint.py           # Browser fingerprinting ✅
├── llm_vision.py            # LLM vision for page analysis ✅
├── exceptions.py            # Custom exceptions ✅
├── tasks/                   # Task implementations ✅
│   ├── __init__.py
│   ├── base.py              # BaseTask abstract class ✅
│   ├── gitcoin.py           # Gitcoin Passport stamping ✅
│   ├── poap.py              # POAP claiming ✅
│   ├── ens.py               # ENS subdomain registration ✅
│   ├── coinbase_id.py       # Coinbase ID (cb.id) — FREE ENS alternative ✅
│   ├── snapshot.py          # Snapshot voting ✅
│   └── lens.py              # Lens Protocol interactions ✅
├── anti_detection/          # Anti-Sybil fingerprinting
│   └── __init__.py          # Placeholder (basic anti-detection in browser.py)
└── README.md                # This file
```

---

## 🚀 Usage

### Master Node: Schedule Tasks

```python
from openclaw.manager import OpenClawOrchestrator
from database.db_manager import DatabaseManager

# Initialize
db = DatabaseManager()
orchestrator = OpenClawOrchestrator(db)

# Fetch Tier A wallets (should be 18)
tier_a_wallets = db.query("SELECT * FROM wallets WHERE tier = 'A'")

# Schedule Gitcoin Passport для всех 18 wallets
# Temporal isolation: 60-240 min между задачами
tasks_count = orchestrator.schedule_gitcoin_passport_batch(tier_a_wallets)
print(f"✅ Scheduled {tasks_count} Gitcoin Passport tasks")

# Schedule POAP claiming
poap_events = [
    (12345, "ETHDenver 2026"),
    (67890, "Gitcoin GR19"),
    (11111, "Base Mainnet Launch")
]
event_ids = [e[0] for e in poap_events]
event_names = [e[1] for e in poap_events]

orchestrator.schedule_poap_claim_batch(tier_a_wallets, event_ids, event_names)

# Schedule ENS registration (FREE cb.id or base.eth)
orchestrator.schedule_ens_registration_batch(tier_a_wallets)

# Schedule Snapshot voting
snapshot_proposals = [
    {"proposal_id": "0xabc123", "space": "aave.eth", "title": "Increase LTV"},
    {"proposal_id": "0xdef456", "space": "uniswap.eth", "title": "Fee Tier Change"},
    # ... more proposals
]
orchestrator.schedule_snapshot_voting_batch(tier_a_wallets, snapshot_proposals)

# Assign tasks to workers (based on wallet assignment)
assigned = orchestrator.assign_tasks_to_workers()
print(f"✅ Assigned {assigned} tasks to Workers")

# Check stats
stats = orchestrator.get_task_stats()
print(f"📊 Task stats: {stats}")
# Example output: {'queued': 108, 'running': 0, 'completed': 0, 'failed': 0, 'total': 108}
```

### Worker Node: Execute Tasks

```python
from openclaw.executor import OpenClawExecutor
from database.db_manager import DatabaseManager
import asyncio

# Initialize
db = DatabaseManager()
executor = OpenClawExecutor(worker_id=1, db_manager=db)  # Worker 1 (NL)

# Start polling loop (runs forever, checks every 60 seconds)
asyncio.run(executor.start_polling())

# В фоне процесс будет:
# 1. Poll openclaw_tasks таблицу
# 2. Fetch tasks где assigned_worker_id = 1 и scheduled_at <= NOW()
# 3. Execute task (launch browser, perform action, save screenshot)
# 4. Update task status (queued → running → completed/failed)
# 5. Retry если failed (up to max_retries = 3)
```

---

## ⏱️ Temporal Isolation (CRITICAL)

**ВАЖНО:** OpenClaw использует 60-240 минут задержки между задачами (NOT 30-90 минут).

### Why This Matters:

- L2 chains in 2026 имеют 2-3 second block times
- Короткие задержки (30-90 мин) = ЛЕГКО ДЕТЕКТИРУЕМЫЙ ПАТТЕРН
- 18 wallets executing tasks каждые 30-90 мин = OBVIOUS CLUSTER
- **Risk:** All 18 Tier A wallets banned within 2-3 weeks

### Implementation:

```python
# openclaw/manager.py (line 245)
def _calculate_next_task_delay(self) -> int:
    """Delay: 60-240 minutes (1-4 hours)."""
    base_delay = random.uniform(3600, 14400)  # 1-4 hours
    
    # 25% шанс длинной паузы (5-10 hours) — "ушел спать"
    if random.random() < 0.25:
        base_delay = random.uniform(18000, 36000)
    
    # Gaussian noise (±20 minutes)
    noise = random.gauss(0, 1200)
    
    final_delay = max(3600, base_delay + noise)
    return int(final_delay)
```

### Execution Timeline:

- **18 wallets × 6 tasks/week × 2.5 hours avg = 270 hours ≈ 11.25 days**
- This means: Complete all tasks over **3-4 weeks** (not 1-2 weeks)
- **This is GOOD:** Speed is NOT a metric in airdrop farming — stealth IS

---

## 💰 Cost Estimate (Updated)

### One-Time Costs

| Item | Original Plan | Updated | Savings |
|------|--------------|---------|---------|
| ENS (18 wallets) | $126 | **$20-40** (FREE cb.id/base.eth) | -$86-106 |
| Lens profiles | $13.50 | **$2.88** (ZKsync) | -$10.62 |
| POAP claiming | $3.60 | **$3.60** | $0 |
| CAPTCHA solving | $0.10 | **$0.10** | $0 |
| **TOTAL** | **$145** | **$27-47** | **-$98-118 (68%)** |

### Recurring Costs (Monthly)

| Item | Original | Updated | Savings |
|------|----------|---------|---------|
| CAPTCHA | $2-5 | **$0.10** | -$1.90-4.90 |
| Storage (screenshots) | $1 | **$1** | $0 |
| **TOTAL** | **$3-6** | **$1.10** | **-$1.90-4.90** |

### ROI

- **Investment:** $27-47 (one-time) + $1.10/month × 6 = **$34-54** total
- **Expected Return:** $12,000-$24,000 (reputation multiplier boost)
- **ROI:** **220-700x** 🚀

---

## 🗄️ Database Tables

OpenClaw uses 8 new tables (created by [`database/migrations/002_openclaw.sql`](../database/migrations/002_openclaw.sql)):

### Core Tables:
1. **`openclaw_tasks`** — Task queue (Master → Workers communication)
2. **`openclaw_profiles`** — Browser profiles (cookies, fingerprints)
3. **`openclaw_task_history`** — Execution history (audit trail)

### Reputation Tables:
4. **`gitcoin_stamps`** — Gitcoin Passport stamps
5. **`poap_tokens`** — POAP event badges
6. **`ens_names`** — ENS subdomains
7. **`snapshot_votes`** — Snapshot governance votes
8. **`lens_profiles`** — Lens Protocol profiles

---

## 📊 Success Metrics

### Per-Wallet Targets

| Metric | Target | Query |
|--------|--------|-------|
| Gitcoin Score | ≥15 | `SUM(gitcoin_stamps.score_contribution)` |
| POAP Count | ≥3 | `COUNT(poap_tokens)` |
| ENS Ownership | 1 | `COUNT(ens_names)` |
| Snapshot Votes | ≥5 | `COUNT(snapshot_votes)` |
| Lens Profile | 1 | `COUNT(lens_profiles)` |

### System-Level Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Task Success Rate | ≥90% | completed / total tasks |
| Avg Task Duration | <10 min | Median(openclaw_task_history.duration_seconds) |
| CAPTCHA Solve Rate | ≥95% | Solved / encountered |

---

## 🧪 Testing Strategy

### Phase 1: Dry-Run (Week 1)
- [ ] Implement dry-run mode в BaseTask
- [ ] Test ALL task types without real execution
- [ ] Verify temporal isolation (1-4 hour delays)

### Phase 2: Test Wallets (Week 2)
- [ ] Run on 2 wallets (1 NL, 1 IS)
- [ ] Execute 1-2 tasks per wallet
- [ ] Monitor for 3 days
- [ ] Check for bans/blocks

### Phase 3: Limited Deployment (Week 3)
- [ ] Scale to 6 wallets (2 per worker)
- [ ] Execute all task types
- [ ] Monitor for 3 days

### Phase 4: Full Deployment (Week 4+)
- [ ] All 18 Tier A wallets
- [ ] Spread tasks over 3-4 weeks
- [ ] Continuous monitoring

---

## 🚨 Current Status

### ✅ Completed (Foundation + Implementation Phase)
- [x] Database migration (002_openclaw.sql)
- [x] OpenClawOrchestrator (manager.py)
- [x] OpenClawExecutor (executor.py)
- [x] Module structure (openclaw/)
- [x] Temporal isolation logic (60-240 min)
- [x] Browser automation engine (browser.py)
- [x] Browser fingerprinting (fingerprint.py)
- [x] LLM vision integration (llm_vision.py)
- [x] Custom exceptions (exceptions.py)
- [x] BaseTask abstract class (tasks/base.py)
  - Dry-run mode with mock data
  - Human-like delays and typing simulation
  - CAPTCHA solving placeholder
  - Error handling and retry logic
- [x] GitcoinPassportTask (tasks/gitcoin.py)
  - Wallet connection via MetaMask simulation
  - Stamp collection flow
  - OAuth placeholders (Google, Twitter, Discord, GitHub)
- [x] POAPTask (tasks/poap.py)
  - Navigate to claim URL
  - Wallet connection simulation
  - Claim confirmation flow
- [x] ENSTask (tasks/ens.py)
  - Domain availability search
  - Commit-reveal registration process
  - Primary ENS name setting
- [x] CoinbaseIDTask (tasks/coinbase_id.py) — **NEW**
  - FREE cb.id subdomain registration
  - Recommended over paid ENS
- [x] SnapshotTask (tasks/snapshot.py)
  - Proposal navigation
  - Voting power check
  - Off-chain vote signing simulation
- [x] LensTask (tasks/lens.py)
  - Profile creation
  - Follow/Post/Collect/Mirror actions
  - Wallet connection to hey.xyz

### ⏳ TODO (Testing & Deployment Phase)
- [ ] Integration testing (dry-run mode)
- [ ] Test with 2 wallets (1 NL, 1 IS)
- [ ] CAPTCHA solving integration (2captcha)
- [ ] OAuth flow implementation (Google, Twitter, Discord, GitHub)
- [ ] Production deployment (1-2 test wallets first)
- [ ] Scale to full 18 Tier A wallets

---

## 📝 Next Steps

1. **Run database migration (if not done):**
   ```bash
   psql -h localhost -U farming_user -d farming_db -f database/migrations/002_openclaw.sql
   ```

2. **Test dry-run mode:**
   ```python
   from openclaw.tasks import GitcoinPassportTask, POAPTask, CoinbaseIDTask
   
   # Test Gitcoin task in dry-run mode
   task = GitcoinPassportTask(dry_run=True)
   result = await task.execute(wallet_address="0x...")
   print(result)
   ```

3. **Test orchestrator scheduling:**
   ```python
   from openclaw.manager import OpenClawOrchestrator
   from database.db_manager import DatabaseManager
   
   db = DatabaseManager()
   orchestrator = OpenClawOrchestrator(db)
   
   # Fetch Tier A wallets
   tier_a = db.query("SELECT * FROM wallets WHERE tier = 'A' LIMIT 2")
   
   # Schedule tasks
   orchestrator.schedule_gitcoin_passport_batch(tier_a)
   ```

4. **Integration testing with real browser** (Phase 2 testing)

---

**Status:** ✅ Phase 2 Complete (All tasks implemented)
**Next:** Integration Testing & OAuth Implementation  
**ETA:** 1-2 weeks for production deployment

---

## 📁 Архитектурный анализ файлов модуля

### `__init__.py`

**Зачем:** Закрывает проблему единой точки входа для Master-Worker архитектуры. Разделяет планирование (Master) и выполнение (Workers).

**Бизнес-задача:** Экспортирует `OpenClawOrchestrator` (планирование задач) и `OpenClawExecutor` (выполнение задач) для 18 Tier A кошельков.

**Интеграция:**
- Master Node использует `OpenClawOrchestrator` для записи в `openclaw_tasks` таблицу
- Worker Nodes используют `OpenClawExecutor` для polling и выполнения задач
- Temporal isolation: 60-240 минут между задачами (КРИТИЧНО для anti-Sybil)

**Ключевые ограничения:**
- **Tier A only:** Модуль работает только с 18 кошельками (wallet_id 1-18)
- **Separate API key:** Использует `OPENROUTER_OPENCLAW_API_KEY` (не `OPENROUTER_API_KEY` для research)

**Заглушки:** Нет.  
**Хардкод:** Нет.

---

### `manager.py`

**Зачем:** Закрывает проблему синхронного выполнения browser automation на 18 кошельках. Планирует задачи с temporal isolation.

**Бизнес-задача:** Создаёт записи в `openclaw_tasks` для Gitcoin Passport, POAP, ENS/Coinbase ID, Snapshot, Lens с задержками 1-4 часа между задачами.

**Интеграция:**
- Работает ТОЛЬКО на Master Node (НЕ запускает browser)
- Shuffle кошельков перед планированием (random.sample)
- Worker assignment: кошельки 1-6 → Worker 1, 7-12 → Worker 2, 13-18 → Worker 3

**Ключевые ограничения:**
- **Temporal isolation:** 60-240 минут (NOT 30-90!) — КРИТИЧНО для L2 2026
- **Long pause probability:** 25% шанс паузы 5-10 часов ("ушёл спать")
- **Gaussian noise:** ±20 минут на delay
- **Coinbase ID preferred:** ENS deprecated в пользу FREE cb.id

**Заглушки:** Нет.  
**Хардкод:** `min_delay_seconds = 3600`, `max_delay_seconds = 14400`, `long_pause_probability = 0.25`, `long_pause_min/max = 18000/36000`

---

### `executor.py`

**Зачем:** Закрывает проблему выполнения browser automation на Worker Nodes без утечки приватных ключей.

**Бизнес-задача:** Polling `openclaw_tasks` таблицы каждые 60 секунд, запуск browser, выполнение задачи, сохранение screenshot для audit trail.

**Интеграция:**
- Работает ТОЛЬКО на Worker Nodes
- Hybrid execution: Scripted fast path + LLM Vision fallback
- LLM Vision НЕ имеет доступа к приватным ключам (security boundary)
- Retry logic: до 3 попыток, затем статус 'failed'

**Ключевые ограничения:**
- **LLM cost limit:** $0.10 per task (защита от runaway costs)
- **Max iterations:** 10 LLM calls per task
- **Security boundary:** LLM видит только screenshot и page URL

**Заглушки:** Нет.  
**Хардкод:** `poll_interval = 60`, `MAX_LLM_ITERATIONS = 10`, `LLM_COST_LIMIT = 0.10`, directories `/opt/farming/openclaw/profiles` и `/opt/farming/openclaw/screenshots`

---

### `browser.py`

**Зачем:** Закрывает проблему детекции browser automation через fingerprinting и IP leak.

**Бизнес-задача:** Управляет headless браузером (pyppeteer) с anti-detection: TLS fingerprint synchronization, Canvas/WebGL spoofing, IP leak protection.

**Интеграция:**
- TLS fingerprint synchronization с Python scripts через `identity_manager`
- Canvas/WebGL/AudioContext fingerprinting через `FingerprintGenerator`
- IP leak protection: pre-flight check, TTL guard, heartbeat monitoring
- MetaMask wallet injection для on-chain interactions

**Ключевые ограничения:**
- **wallet_id REQUIRED:** Без wallet_id TLS fingerprint НЕ будет match Python scripts
- **Pre-flight IP check:** Блокирует запуск при IP leak
- **Heartbeat monitoring:** Проверка IP каждые 60 секунд для long sessions
- **Fingerprint deterministic:** Тот же wallet_id → тот же fingerprint всегда

**Заглушки:** Нет.  
**Хардкод:** `wallet_id range [1, 90]`, `check_interval_seconds = 60`, browser args (`--no-sandbox`, `--disable-blink-features=AutomationControlled`, etc.)

---

### `fingerprint.py`

**Зачем:** Закрывает проблему browser fingerprint clustering — 18 кошельков с одинаковым fingerprint = Sybil detection.

**Бизнес-задача:** Генерирует уникальный, но детерминированный browser fingerprint для каждого из 90 кошельков (Canvas, WebGL, AudioContext, fonts, screen).

**Интеграция:**
- Deterministic seed: `sha256("fingerprint_v1_{wallet_id}")` → одинаковый fingerprint всегда
- 8 realistic WebGL renderers (NVIDIA, AMD, Intel distribution)
- JS injection script для spoofing через `page.evaluateOnNewDocument()`

**Ключевые ограничения:**
- **NO private keys:** Fingerprint генерируется без приватных данных
- **NO network requests:** Полностью offline генерация
- **Thread-safe:** Может использоваться concurrently
- **wallet_id range:** [1, 90] — выбросит ValueError если вне диапазона

**Заглушки:** Нет.  
**Хардкод:** `WEBGL_RENDERERS` (8 GPU names), `AUDIO_NOISE_MIN/MAX`, `ALL_FONTS` (16 fonts), `SCREEN_RESOLUTIONS` (8 resolutions), `seed_prefix = "fingerprint_v1"`

---

### `llm_vision.py`

**Зачем:** Закрывает проблему ломающихся browser automation скриптов при изменении UI сайтов. Self-healing через LLM.

**Бизнес-задача:** Отправляет screenshot в OpenRouter API (Claude Haiku), получает action (click, type, wait, complete, fail) для адаптивного взаимодействия с UI.

**Интеграция:**
- OpenRouter API: `https://openrouter.ai/api/v1/chat/completions`
- Model: `anthropic/claude-haiku-4.5` (дешёвый для browser automation)
- Separate API key: `OPENROUTER_API_KEY_OPENCLAW` (не research key)
- Cost tracking: input/output tokens, USD cost

**Ключевые ограничения:**
- **Security boundary:** НЕТ доступа к приватным ключам, wallet addresses, database, file system
- **Input ONLY:** Screenshot (base64), task description, page URL, previous actions
- **Retry logic:** 3 попытки с exponential backoff (2-10 секунд)
- **Cost limit:** Проверяется в executor ($0.10 per task)

**Заглушки:** Нет.  
**Хардкод:** `API_URL`, `MODEL_CLAUDE_HAIKU`, `PRICE_PER_1K_INPUT = 0.00025`, `PRICE_PER_1K_OUTPUT = 0.00125`, `max_tokens = 1024`, `timeout = 30.0`

---

### `exceptions.py`

**Зачем:** Закрывает проблему неинформативных ошибок при browser automation. Обеспечивает structured error handling.

**Бизнес-задача:** Определяет 20+ custom exceptions для всех сценариев ошибок: element not found, task execution, browser launch, LLM API, OAuth, proxy, fingerprint.

**Интеграция:**
- `ElementNotFoundError` → triggers LLM Vision fallback
- `TaskFailedError` → retry или mark as failed
- `LLMRateLimitError` → exponential backoff
- `IPLeakDetected` → критическая ошибка, блокирует выполнение

**Ключевые ограничения:**
- **to_dict() method:** Все exceptions сериализуемы в JSON для API responses
- **Details dict:** Каждая ошибка содержит structured context

**Заглушки:** Нет.  
**Хардкод:** Нет.

---

### `tasks/base.py`

**Зачем:** Закрывает проблему дублирования кода в task implementations. Единый интерфейс для всех задач.

**Бизнес-задача:** Абстрактный класс с dry-run mode, human-like delays, error handling framework, CAPTCHA solving placeholder.

**Интеграция:**
- Dry-run mode: simulation без real execution (1-3 сек задержка)
- Human-like behavior: random delays, mouse movements
- Abstract methods: `_execute_real()`, `_mock_result()`

**Ключевые ограничения:**
- **Dry-run required:** Все subclasses ДОЛЖНЫ implement `_mock_result()`
- **CAPTCHA placeholder:** Метод определён, но не реализован (future 2captcha integration)

**Заглушки:** ✅ **ДА** — CAPTCHA solving placeholder (`async def _solve_captcha(self) -> str`).  
**Хардкод:** Dry-run delay range 1-3 секунды (Gaussian mean=2.0, std=0.5).

---

### `tasks/gitcoin.py`

**Зачем:** Закрывает проблему низкого Gitcoin Passport score у 18 Tier A кошельков. Target: ≥15 score для Sybil resistance.

**Бизнес-задача:** Автоматизация получения stamps: Google OAuth, Twitter OAuth, Discord OAuth, GitHub OAuth, BrightID, POAP verification, ENS ownership.

**Интеграция:**
- Navigate to `https://passport.gitcoin.co`
- MetaMask wallet connection
- Sequential stamp collection
- OAuth flows (placeholders for credentials)

**Ключевые ограничения:**
- **OAuth credentials required:** Task params должен содержать `credentials` dict
- **Stamp IDs:** Использует актуальные 2026 stamp IDs (Google, Twitter, Discord, Github, Ens, BrightId, POHV2, GitPOAP)

**Заглушки:** ✅ **ДА** — OAuth credentials placeholders в task_params.  
**Хардкод:** `GITCOIN_PASSPORT_URL`, `AVAILABLE_STAMPS` dict.

---

### `tasks/poap.py`

**Зачем:** Закрывает проблему отсутствия event participation badges у Tier A кошельков. Target: 3-5 POAPs per wallet.

**Бизнес-задача:** Автоматизация claiming POAP NFTs через claim link: navigate, connect wallet, claim, verify transaction.

**Интеграция:**
- Принимает `claim_url` и `event_name` в task_params
- MetaMask wallet connection
- Mint transaction verification

**Ключевые ограничения:**
- **claim_url REQUIRED:** Выбросит ValueError если не указан
- **Already claimed check:** Обрабатывает случай "already claimed"

**Заглушки:** Нет.  
**Хардкод:** Нет.

---

### `tasks/snapshot.py`

**Зачем:** Закрывает проблему отсутствия governance activity у Tier A кошельков. Target: 5-10 votes per wallet.

**Бизнес-задача:** Автоматизация голосования в Snapshot DAO proposals (off-chain, gas-free).

**Интеграция:**
- Navigate to proposal URL
- Select vote choice (1=For, 2=Against, 3=Abstain)
- Sign off-chain message
- Verify voting power

**Ключевые ограничения:**
- **proposal_url REQUIRED:** Выбросит ValueError если не указан
- **Off-chain signature:** Не требует gas

**Заглушки:** Нет.  
**Хардкод:** `SNAPSHOT_URL = "https://snapshot.org"`

---

### `tasks/ens.py`

**Зачем:** [DEPRECATED] Закрывает проблему отсутствия ENS name у Tier A кошельков. Reputation score: +10.

**Бизнес-задача:** Автоматизация регистрации ENS домена (commit + reveal процесс). **УСТАРЕЛО:** Используйте `CoinbaseIDTask` для FREE альтернативы.

**Интеграция:**
- Navigate to `https://app.ens.domains`
- Search domain availability
- Commit-reveal registration (2 transactions)
- Set primary name

**Ключевые ограничения:**
- **DEPRECATED:** Использовать `CoinbaseIDTask` вместо (экономия $90/year)
- **Cost:** $5-10/year per wallet vs FREE cb.id

**Заглушки:** Нет.  
**Хардкод:** `ENS_APP_URL`, registration cost range 0.003-0.01 ETH.

---

### `tasks/coinbase_id.py`

**Зачем:** Закрывает проблему стоимости ENS регистрации. FREE альтернатива с reputation score: +9 (почти как ENS +10).

**Бизнес-задача:** Автоматизация регистрации Coinbase ID (cb.id) subdomain на Base L2. Стоимость: FREE (только gas ~$0.01).

**Интеграция:**
- Navigate to `https://www.coinbase.com/onchain-username`
- Search username availability
- One transaction on Base L2
- Set primary name

**Ключевые ограничения:**
- **Base L2 only:** cb.id работает только на Base
- **Username auto-generation:** Если не указан, генерируется `wallet{wallet_id:03d}`
- **Cost savings:** $90/year (18 wallets × $5) vs ENS

**Заглушки:** Нет.  
**Хардкод:** `COINBASE_ID_URL`, default username pattern `wallet{wallet_id:03d}`.

---

### `tasks/lens.py`

**Зачем:** Закрывает проблему отсутствия Web3 social presence у Tier A кошельков. Lens Protocol = decentralized social graph.

**Бизнес-задача:** Автоматизация действий в Lens Protocol: create profile, follow, post, collect, mirror.

**Интеграция:**
- Navigate to `https://hey.xyz` (popular Lens frontend)
- Create Lens profile (если нет)
- Execute actions: follow profiles, create posts, collect/mirror posts

**Ключевые ограничения:**
- **Polygon network:** Lens Protocol работает на Polygon
- **Profile required:** Перед другими действиями нужен profile
- **Action types:** create_profile, follow, post, collect, mirror

**Заглушки:** Нет.  
**Хардкод:** `LENS_APP_URL = "https://hey.xyz"`, `LENS_POLYGON_URL`, `AVAILABLE_ACTIONS` list.

---

### `anti_detection/__init__.py`

**Зачем:** Placeholder для будущих advanced anti-detection плагинов.

**Бизнес-задача:** Зарезервировано для canvas/WebGL/audio fingerprinting protection, advanced proxy rotation, browser randomization.

**Интеграция:** Currently basic anti-detection реализован в `browser.py`.

**Ключевые ограничения:**
- **NOT IMPLEMENTED:** Модуль пустой, только docstring

**Заглушки:** ✅ **ДА** — весь модль placeholder (`pass`).  
**Хардкод:** Нет.

---

## 📊 Сводка Anti-Sybil механизмов в OpenClaw

| Файл | Механизм | Защита от |
|------|----------|-----------|
| `manager.py` | Temporal isolation 60-240 мин | Синхронные задачи |
| `manager.py` | Long pause 5-10h (25%) | Bot-like patterns |
| `manager.py` | Shuffle wallets | Sequential patterns |
| `browser.py` | TLS fingerprint sync | TLS fingerprinting |
| `browser.py` | Canvas/WebGL spoofing | Browser fingerprinting |
| `browser.py` | IP leak protection | IP-based clustering |
| `fingerprint.py` | Deterministic fingerprint | Fingerprint inconsistency |
| `fingerprint.py` | Unique per wallet | 18 identical fingerprints |
| `executor.py` | LLM security boundary | Private key exposure |
| `tasks/base.py` | Human-like delays | Bot-like timing |

---

## 📈 Сводка по заглушкам и хардкоду

| Файл | Заглушки | Хардкод |
|------|----------|---------|
| `__init__.py` | ❌ Нет | ❌ Нет |
| `manager.py` | ❌ Нет | ✅ **ДА** (delays, probabilities) |
| `executor.py` | ❌ Нет | ✅ **ДА** (poll_interval, limits, directories) |
| `browser.py` | ❌ Нет | ✅ **ДА** (wallet_id range, check_interval, browser args) |
| `fingerprint.py` | ❌ Нет | ✅ **ДА** (GPU names, fonts, resolutions, seed_prefix) |
| `llm_vision.py` | ❌ Нет | ✅ **ДА** (API URL, model, prices, limits) |
| `exceptions.py` | ❌ Нет | ❌ Нет |
| `tasks/base.py` | ✅ **ДА** (CAPTCHA placeholder) | ✅ **ДА** (dry-run delay range) |
| `tasks/gitcoin.py` | ✅ **ДА** (OAuth placeholders) | ✅ **ДА** (URL, stamp IDs) |
| `tasks/poap.py` | ❌ Нет | ❌ Нет |
| `tasks/snapshot.py` | ❌ Нет | ✅ **ДА** (SNAPSHOT_URL) |
| `tasks/ens.py` | ❌ Нет | ✅ **ДА** (URL, cost range) |
| `tasks/coinbase_id.py` | ❌ Нет | ✅ **ДА** (URL, username pattern) |
| `tasks/lens.py` | ❌ Нет | ✅ **ДА** (URLs, actions list) |
| `anti_detection/__init__.py` | ✅ **ДА** (весь модль placeholder) | ❌ Нет |

**Ключевой вывод:** Заглушки присутствуют только в:
- `tasks/base.py` — CAPTCHA solving (требует 2captcha integration)
- `tasks/gitcoin.py` — OAuth credentials (требует реальных аккаунтов)
- `anti_detection/__init__.py` — весь модль placeholder

Хардкод присутствует во всех task implementations как конфигурация (URLs, IDs, ranges). Это приемлемо для seed конфигурации.
