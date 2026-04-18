# Wallets Module (Module 5 + 8)

Генерация кошельков и уникальных персон для Anti-Sybil защиты. Создаёт 90 уникальных "личностей" с разными паттернами активности.

---

## Файлы модуля

### `generator.py`

**Зачем нужен:**  
Создаёт инфраструктуру фарминга — генерирует кошельки и связывает их с воркерами/прокси.

**Бизнес-задача:**  
Генерирует 90 EVM кошельков с распределением по тирям (18 Tier A, 45 Tier B, 27 Tier C) и воркерам (по 30 на каждого). Шифрует приватные ключи Fernet, экспортирует whitelist для CEX.

**Встраивание в систему:**  
Входная точка системы. Создаёт записи в таблицах `wallets` и `worker_nodes`. Назначает прокси из `proxy_pool`. Данные используются всеми модулями: funding, activity, monitoring, withdrawal.

**Ключевые особенности:**
- **Anti-Sybil:** Shuffle распределения (не последовательные паттерны), рандомизация дат whitelist
- **OpenClaw:** Включён только для Tier A (off-chain активность)
- **Proxy binding:** Worker 1 → NL proxies, Workers 2-3 → IS proxies
- **CEX whitelist:** 1-7 дней между адресами, разные сети для diversity

**Заглушки:** Нет  
**Хардкод:** 
- Распределение 30/30/30 по воркерам, 18/45/27 по тирям
- Worker metadata (IP, location, timezone)
- CEX networks список
- TARGET_DAYS = 10 для whitelist

---

### `personas.py`

**Зачем нужен:**  
Делает кошельки уникальными "личностями" — защищает от Sybil-детекции через поведенческое разнообразие.

**Бизнес-задача:**  
Генерирует уникальные паттерны активности для каждого кошелька: часы активности, частота транзакций, предпочтения по типам операций, slippage, gas. 12 архетипов поведения (ActiveTrader, Ghost, WeekendWarrior и др.).

**Встраивание в систему:**  
Работает после `generator.py`. Записывает в `wallet_personas`. Данные используются:
- **Scheduler** — планирование транзакций по preferred_hours
- **Activity modules** — выбор типа транзакции по tx_weight
- **AdaptiveSkipper** — вероятность пропуска недели

**Ключевые особенности:**
- **Anti-Sybil diversity:** Balanced archetype distribution (не >15% одного архетипа)
- **Gaussian randomization:** Все параметры через `np.random.normal`, не uniform
- **Timezone-aware:** Часы активности конвертируются в UTC по timezone прокси (критично для CA кошельков)
- **Archetype-specific behaviour:** 
  - `BridgeMaxi` → 50% bridges
  - `DeFiDegen` → 60% LP
  - `NFTCollector` → 30% NFT
  - `MonthlyActive` → 75% skip probability (бёрсты раз в месяц)

**Заглушки:** Нет  
**Хардкод:**
- 12 архетипов (ARCHETYPES)
- TIMEZONE_HOURS (часы активности по timezone)
- ARCHETYPE_HOURS (MorningTrader, NightOwl)
- TX weights по архетипам
- Slippage ranges по тирям

---

## Архитектура потока

```
generator.py (создание кошельков)
         ↓
    wallets table (адрес, тир, воркер, прокси)
         ↓
personas.py (назначение персон)
         ↓
    wallet_personas table (паттерны активности)
         ↓
    Scheduler → Activity → Monitoring
```

---

## Интеграция с системой

| Компонент | Взаимодействие |
|-----------|----------------|
| **proxy_pool** | Назначение прокси при генерации (NL/IS/CA) |
| **worker_nodes** | Создание/привязка воркеров |
| **wallet_personas** | Параметры активности для Scheduler |
| **Fernet encryption** | Шифрование приватных ключей |
| **CEX whitelist** | Экспорт для бирж (Anti-Sybil funding) |

---

## Anti-Sybil механизмы

| Механизм | Реализация |
|----------|------------|
| **Shuffle распределения** | `random.shuffle(distribution)` — ломает последовательные паттерны |
| **12 архетипов** | Разнообразие поведений, балансировка ≤15% |
| **Gaussian randomization** | Все параметры через normal distribution |
| **Timezone binding** | Активность соответствует геолокации прокси |
| **CEX whitelist spacing** | 1-7 дней между адресами |

---

## Критичные моменты

1. **P0 FIX (Migration 033):** Timezone берётся из `proxy_pool`, не `worker_nodes` — критично для CA кошельков
2. **Хардкод распределения:** 18/45/27 по тирям — изменить можно только в коде
3. **Fernet key required:** Без `FERNET_KEY` генерация невозможна
4. **Proxy availability:** Генерация падает если нет свободных прокси нужной страны

---

## Запуск

```bash
# Генерация кошельков
python wallets/generator.py generate --count 90

# Экспорт whitelist для CEX
python wallets/generator.py export-whitelist --output cex_whitelist.csv

# Генерация персон
python wallets/personas.py generate
```
