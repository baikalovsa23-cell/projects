# Withdrawal Module (Module 19)

Безопасный вывод средств после аирдропа с human-in-the-loop подтверждением и Anti-Sybil защитой.

---

## Файлы модуля

### `orchestrator.py`

**Зачем нужен:**  
Управляет процессом вывода средств — от создания плана до исполнения транзакции.

**Бизнес-задача:**  
Оркестрирует withdrawal пайплайн: создаёт tier-specific планы, обрабатывает pending steps, отправляет запросы на approval в Telegram, исполняет транзакции через Worker API.

**Встраивание в систему:**  
Центральный координатор модуля. Вызывается `MasterOrchestrator` (каждые 6 часов). Взаимодействует с БД (`withdrawal_plans`, `withdrawal_steps`), Telegram Bot, Worker API, NetworkModeManager, TransactionSimulator.

**Ключевые особенности:**
- **Human-in-the-loop:** Каждая транзакция требует `/approve_<ID>` через Telegram
- **Burn address protection:** Блокирует вывод на burn-адреса (0x0, 0xdead)
- **Mainnet safety gates:** Блокирует вывод если safety gates не пройдены
- **Simulation before execution:** Симуляция через TransactionSimulator перед реальной транзакцией
- **Dry-run mode:** Полная симуляция без реальных транзакций

**Заглушки:** 
- ✅ **ДА** — `_calculate_amount()` использует placeholder balance ($100)
- ✅ **ДА** — `_send_to_worker()` не реализован (TODO: JWT integration)

**Хардкод:**
- BURN_ADDRESSES set
- Gas fee placeholder ($3.50)

---

### `strategies.py`

**Зачем нужен:**  
Определяет стратегии вывода по тирям — сколько шагов, какие проценты, какие задержки.

**Бизнес-задача:**  
Tier A — консервативная стратегия (4 steps, 30% HODL), Tier B — умеренная (3 steps), Tier C — агрессивная (2 steps, быстрый профит). Gaussian распределение задержек для Anti-Sybil.

**Встраивание в систему:**  
Конфигурация для `orchestrator.py`. Используется при создании withdrawal plans.

**Ключевые особенности:**
- **Anti-Sybil:** Gaussian distribution (`np.random.normal`), не uniform
- **First step delay:** 1-7 дней (mean=4) — предотвращает немедленный вывод после детекции аирдропа
- **Tier-specific delays:** A: 30-60 дней, B: 21-45, C: 14-30

**Заглушки:** Нет  
**Хардкод:**
- Стратегии по тирям (percentages, delay_mean, delay_std, delay_min, delay_max)

---

### `validator.py`

**Зачем нужен:**  
Предотвращает потерю средств — проверяет безопасность перед каждой транзакцией.

**Бизнес-задача:**  
Выполняет 5 safety checks: баланс, gas, сеть, destination address, минимальная сумма. Блокирует withdrawal если проверки не пройдены.

**Встраивание в систему:**  
Вызывается `orchestrator.py` перед отправкой на approval. Взаимодействует с БД и web3.py.

**Ключевые особенности:**
- **Balance check:** Баланс >= amount + gas
- **Gas check:** Gas < 200 gwei (защита от high-gas периодов)
- **Destination validation:** Ethereum checksum address
- **Minimum amount:** >= $10 USDT

**Заглушки:**
- ✅ **ДА** — `_check_balance()` использует placeholder balance ($1000)
- ✅ **ДА** — `_estimate_gas()` использует placeholder gas (25 gwei)
- ✅ **ДА** — `estimate_withdrawal_gas()` — TODO: implement via web3.py

**Хардкод:**
- min_withdrawal_amount = $10
- max_gas_gwei = 200
- gas_buffer = 20%

---

### `__init__.py`

Экспорт модулей и метаданные. Не содержит логики.

**Заглушки:** Нет  
**Хардкод:** Tier strategies в METADATA

---

## Архитектура потока

```
Airdrop Detector (trigger)
         ↓
orchestrator.create_withdrawal_plan()
         ↓
    withdrawal_plans + withdrawal_steps (БД)
         ↓
orchestrator.process_pending_steps() (каждые 6 часов)
         ↓
validator.validate_step() → 5 safety checks
         ↓
Telegram → Human approval (/approve_<ID>)
         ↓
orchestrator.execute_withdrawal_step()
         ↓
TransactionSimulator → Worker API → Blockchain
```

---

## Интеграция с системой

| Компонент | Взаимодействие |
|-----------|----------------|
| **MasterOrchestrator** | Вызывает `process_pending_steps()` каждые 6 часов |
| **Airdrop Detector** | Триггер для создания withdrawal plan |
| **Telegram Bot** | Human-in-the-loop approval workflow |
| **Worker API** | Исполнение транзакций (JWT auth) |
| **NetworkModeManager** | Dry-run vs Mainnet mode |
| **TransactionSimulator** | Симуляция перед исполнением |

---

## Anti-Sybil механизмы

| Механизм | Реализация |
|----------|------------|
| **Temporal isolation** | 14-60 дней между шагами по тиру |
| **Gaussian distribution** | `np.random.normal` для задержек |
| **First step delay** | 1-7 дней после детекции аирдропа |
| **Tier-specific strategies** | Разные паттерны для A/B/C |

---

## Критичные моменты

1. **Заглушки в validator:** Balance и gas — placeholders, нужна интеграция с RPC
2. **Worker API не реализован:** `_send_to_worker()` требует JWT integration
3. **Burn address protection:** Критично — двойная проверка перед approval и execution
4. **Mainnet safety gates:** Блокировка вывода если gates не пройдены

---

## Стратегии по тирям

| Tier | Steps | Percentages | Delay range |
|------|-------|-------------|-------------|
| **A** | 4 | 15% → 25% → 30% → 30% HODL | 30-60 дней |
| **B** | 3 | 20% → 40% → 40% | 21-45 дней |
| **C** | 2 | 50% → 50% | 14-30 дней |

---

## Статусы withdrawal_steps

```
planned → pending_approval → approved → executing → completed
                                    ↓
                                 rejected
```
