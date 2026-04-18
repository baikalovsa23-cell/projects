# Crypto Airdrop Farming System — ТЗ v4.0
> Актуально на: февраль 2026  
> Статус: **В разработке** — инфраструктура арендована, код не написан  
> Предыдущая версия: v3.0 (устарела)

---

## 1. Общая информация

**Цель:** Автоматизированная ферма из 90 EVM-кошельков для фарминга аирдропов на L2-сетях 2026 года с максимальной защитой от Sybil-детекции.

**Архитектура:** Двухслойная — Python/web3.py (все 90 кошельков) + OpenClaw browser automation (только 18 Tier A).

**Стек технологий:**
- Python 3.11, web3.py, ccxt, aiohttp, Flask, APScheduler
- PostgreSQL 15, Node.js 20 LTS
- OpenClaw (self-hosted AI-браузер)
- Fedora 43 (локальная среда разработчика) + Ubuntu 24.04 (серверы)
- KiloCode + DeepSeek V3 (исполнение кода)

**� азработчики:**
- Архитектор: Человек
- Senior-разработчик (исполнитель через KiloCode): AI

---

## 2. Что уже готово

| Статус | Компонент |
|--------|-----------|
5 бирж зарегистрированы: Binance, Bybit, OKX, KuCoin, MEXC |
зарегестрированы 18 субаккаунтов.

| # | Биржа | Субаккаунт | CEX Сеть | Целевая сеть | Сумма | Bridge Fee | ИТОГО |
|---|-------|------------|----------|--------------|-------|------------|-------|-----------|
| 1 | Bybit | BybitScalpMaster | **Base Mainnet** | Base | $19.00 | $0 | **$19.00** | 
| 2 | Bybit | DeltaNeutralTrade | **Arbitrum One** | Arbitrum | $6.00 | $0 | **$6.00** | 
| 3 | Bybit | GlobalAssetManage | **OP Mainnet** | Optimism | $6.00 | $0 | **$6.00** | 
| 4 | Bybit | RiskControlAccount | **BSC (BEP20)** | BSC | $6.00 | $0 | **$6.00** |

| 5 | Binance | BinanceGridBotOne | **ARBITRUM** | → Ink via bridge | $9.00 | +$3.00 | **$12.00** |
| 6 | Binance | SpotPortfolioMain | **BSC** | BSC | $6.00 | $0 | **$6.00** | 
| 7 | Binance | ArbitrageLiquidity | **OPTIMISM** | Optimism | $6.00 | $0 | **$6.00** | 
| 8 | Binance | VentureGrowthFund | **BASE** | Base | $6.00 | $0 | **$6.00** |

| 9 | OKX | AlphaTradingStrategy | **Arbitrum One** | → MegaETH via bridge | $15.00 | +$5.00 | **$20.00** |
| 10 | OKX | LongTermStakingVault | **Arbitrum One** | Arbitrum | $19.00 | $0 | **$19.00** | 
| 11 | OKX | MarketMakingNode | **Optimism** | Optimism | $6.00 | $0 | **$6.00** |
| 12 | OKX | DefiLiquidityPools | **Polygon** | Polygon | $6.00 | $0 | **$6.00** | 

| 13 | KuCoin | HiddenGemHunter | **ARBITRUM** | Arbitrum | $6.00 | $0 | **$6.00** | 
| 14 | KuCoin | KCSYieldOptimizer | **OPTIMISM** | Optimism | $6.00 | $0 | **$6.00** | 
| 15 | KuCoin | BotDeploymentLab | **BEP20** | BSC | $6.00 | $0 | **$6.00** |

| 16 | MEXC | EarlyListingPlay23 | **BASE** | Base | $6.00 | $0 | **$6.00** | 
| 17 | MEXC | MarketFlowEngine11 | **UNICHAIN** | Unichain | $6.00 | $0 | **$6.00** | 
| 18 | MEXC | SecondaryReserve82 | **BSC (BEP20)** | BSC | $6.00 | $0 | **$6.00** | 

| | | | | | | | **ОБЩИЙ ИТОГО: $154** | **90** |


Суммы на субаккаунтах могут немного отличаться от таблицы — главное, чтобы на каждом было достаточно для вывода на 5 кошельков (с учётом комиссий биржи).

 Вот список всех сетей монета ETH Bybit:

					 Ethereum (ERC20) — основная сеть эфира (высокие комиссии, долгие подтверждения).
					 Arbitrum One — популярная L2-сеть для быстрых и дешевых транзакций ETH.
					 BSC (BEP20) — BNB Smart Chain (сеть Binance, низкие комиссии).
					 zkSync Lite — ранняя версия протокола zkSync.
					 OP Mainnet — сеть Optimism (еще один популярный L2).
					 Mantle Network — собственная L2-сеть экосистемы Bybit/Mantle.
					 Arbitrum Nova — версия Arbitrum, оптимизированная для еще более низких комиссий (часто используется в играх).
					 zkSync Era — основная современная версия сети zkSync.
					 Base Mainnet — L2-сеть от биржи Coinbase.
					 LINEA — L2-сеть от компании ConsenSys.

Вот список всех сетей монета ETH kucoin:
					ERC20		Родная сеть Ethereum	Самая безопасная, но самая дорогая (комиссия может быть $5–20+).
					KCC		KuCoin Community Chain	Собственная сеть биржи KuCoin. Дешевая, но используется редко за пределами этой биржи.
					BEP20		BNB Smart Chain (BSC)	Сеть от Binance. Народный стандарт: очень дешево и поддерживается почти везде.
					ARBITRUM	Arbitrum One		Мощный L2 для эфира. Золотой стандарт для тех, кто хочет экономить на «газе», не покидая экосистему ETH.
					OPTIMISM	OP Mainnet		Прямой конкурент Arbitrum и Base. Быстрая, дешевая и очень популярная.
Вот список всех сетей монета ETH mexc: 
					ETH (ERC20) — Родная сеть Ethereum. Самая безопасная, но и самая дорогая (высокая комиссия за вывод).
					BSC (BEP20) — BNB Smart Chain от Binance. Популярный стандарт для дешевых и быстрых переводов.
					ARB (Arbitrum One) — Один из лидеров среди L2. Очень низкие комиссии и высокая поддержка кошельками.
					BASE — Сеть от биржи Coinbase. Сейчас одна из самых быстрорастущих, идеальна для переводов на личные кошельки.
					OP (OP Mainnet) — Бывшая Optimism. Прямой аналог Arbitrum, очень быстрая.
					LINEA — Сеть от ConsenSys (создателей MetaMask). Хорошо интегрирована в этот кошелек.
					STARK (Starknet) — Использует ZK-технологию (Zero-Knowledge). У нее свои адреса (не начинаются на 0x), поэтому будь внимателен при копировании.
					UNICHAIN — Новая сеть от Uniswap Labs. Запущена (в начале 2025-го) специально для супер-быстрого DeFi-трейдинга и обменов.
					MORPH — «Потребительский» блокчейн, ориентированный на повседневные платежи. Гибридная сеть, сочетающая скорость и безопасность.


Вот список всех сетей монета ETH okx:
					X Layer
					Ethereum (ERC20)
					Arbitrum One
					Avalanche C-Chain
					BNB Smart Chain
					Base
					Berachain
					CFX_EVM
					Celo
					Chiliz Chain
					Core
					Endurance Smart Chain
					Ethereum Classic
					EthereumPoW
					Fantom
					Flare
					Gravity Alpha Mainnet
					HyperEVM
					Kaia
					Layer 3
					Linea
					Lisk
					Merlin
					Metis
					Optimism
					Plasma
					Polygon
					Ronin
					SEI EVM
					Scroll
					Sonic Network
					Sophon
					Story
					Theta
					Unichain
					ZetaChain
					zkSync Era
					OKT Chain
Вот список всех сетей монета ETH binance:
					BSC 	(Binance Smart Chain): 		Сеть от Binance, популярна из-за низких комиссий.
					ETH 	(Ethereum): 			Основная сеть эфириума. Обычно самая дорогая по комиссиям (газу).
					ARBITRUM, BASE, OPTIMISM, SCROLL: 	Это так называемые Layer 2 (L2) решения для масштабирования Ethereum. Они работают быстрее и значительно дешевле основной сети.
					MANTA: 					Сеть экосистемы Manta Network (также L2 на базе модульной архитектуры).
					STARKNET: 				Еще одно L2 решение, использующее технологию ZK-Rollups для обеспечения приватности и масштабируемости.
					ZKSYNCERA

 

Суммы на субаккаунтах могут немного отличаться от таблицы — главное, чтобы на каждом было достаточно для вывода на 5 кошельков (с учётом комиссий биржи).

 VPS арендованы: 4 ноды на Hotkeys.com |
 Прокси: Decodo 4G/5G (2GB, pay as you go) + IPRoyal Residential(2GB, pay as you go) |
 OpenRouter API ключ (основной — для Protocol Research Agent) Второй OpenRouter ключ для OpenClaw создан|
 Локальная среда: Fedora 43 + VS Code + KiloCode |
 SSH-ключи для доступа к VPS |
| ❌ | Код не написан |
| ❌ | Кошельки не сгенерированы |
 API-ключи бирж созданы |
| ❌ | Telegram-бот не настроен |

---

## 3. инфраструктура

### 3.1 Топология нодов

| Нода | Провайдер | Локация | RAM | � оль |
|------|-----------|---------|-----|------|
| **Master Node** | Hotkeys | Нидерланды | 4 GB | БД, оркестрация, LLM, мониторинг, OpenClaw gateway |
| **Worker 1** | Hotkeys | Нидерланды | 4 GB | 30 кошельков (web3.py транзакции) |
| **Worker 2** | Hotkeys | � сландия | 4 GB | 30 кошельков (web3.py транзакции) |
| **Worker 3** | Hotkeys | � сландия | 4 GB | 30 кошельков (web3.py транзакции) |

> � ️ **Важно:** VPS-локации определяют timezone поведения кошельков и регион прокси.  
> Netherlands → UTC+1 → прокси iproyal | Decodo Netherlands  
> Iceland → UTC+0 → прокси iproyal | Decodo Iceland

### 3.2 распределение кошельков по воркерам

| Worker | Локация | Tier A | Tier B | Tier C | итого | Proxy Region |
|--------|---------|--------|--------|--------|-------|--------------|
| Worker 1 | Amsterdam, NL (UTC+1) | 6 | 15 | 9 | **30** | netherlands |
| Worker 2 | Reykjavik, IS (UTC+0) | 6 | 15 | 9 | **30** | iceland |
| Worker 3 | Reykjavik, IS (UTC+0) | 6 | 15 | 9 | **30** | iceland |
| **итого** | | **18** | **45** | **27** | **90** | |

### 3.3 Двухслойная архитектура

| Параметр | Слой 1: Python/web3.py | Слой 2: OpenClaw |
|----------|------------------------|------------------|
| Технология | web3.py, ccxt, aiohttp, curl_cffi | Playwright, Chrome, MetaMask |
| Кошельки | ВСЕ 90 (Tier A + B + C) | ТОЛЬКО 18 Tier A |
| Транзакции | Swap, Bridge, Stake, LP, Governance | Gitcoin, POAP, ENS, Snapshot, Lens, Lighter, OpenSea |
| Скорость | Быстро (прямые RPC вызовы) | Медленно (браузер, имитация человека) |
| IP защита | iproyal, Decodo 4G/5G sticky-сессии | iproyal,Decodo 4G/5G (те же пулы!) |
| OpenRouter ключ | Основной ($10/мес) | **Отдельный ключ** ($5/мес) |
| Цель | Основная активность 24/7 | � епутация и identity Tier A |

---

## 4. Бюджет

### 4.1 Стартовые расходы (месяц 1)

| Статья | Сумма | Периодичность |
|--------|-------|---------------|
| Газ для 90 кошельков | $120 | разово |
| Прокси Decodo + IPRoyal | ✅ оплачено | pay as you go |
| VPS Hotkeys (4 ноды) | $17.44 | Ежемесячно |
| OpenRouter (Python агенты) | $10 | Ежемесячно |
| OpenRouter (OpenClaw, отдельный ключ!) | $5 | Ежемесячно |
| Gitcoin Passport Tier A (18 кошельков) | $36 | разово |
| Staking Tier A — Lido | $9 | разово |
| ~~ENS домены Tier A (18 × $5)~~ | ~~$90~~ | ~~разово (годовая)~~ (заменено на Coinbase ID) |
| Coinbase ID (cb.id) Tier A — FREE | $0 | разово (только gas ~$2) |
| резерв / дозаправка газа | $30 | Ежемесячно |


### 4.2 Операционные расходы (месяцы 2–6)

| Статья | Сумма/мес |
|--------|-----------|
| VPS (4 ноды) | $17.44 |
| OpenRouter (оба ключа) | $15 |
| Газ дозаправка | $90 |
| Прокси (pay as you go) | ~$11 |




### 4.3 расход газа в месяц

| Tier | Кошельков | TX/мес (μ) | Стоимость |
|------|-----------|------------|-----------|
| Tier A | 18 | 30 = 540 tx | $2.70 |
| Tier B | 45 | 12 = 540 tx | $2.70 |
| Tier C | 27 | 4 = 108 tx | $0.54 |


---

## 5. Кошельки и тиры

### 5.1 распределение по тирам

| Tier | Кол-во | % | Активность | CEX источник | OpenClaw | Архетип |
|------|--------|---|------------|-------------|---------|---------|
| **Tier A** | 18 | 20% | ВЫСОКАЯ (25–35 tx/мес) | Binance, Bybit, OKX | ✅ ДА | ActiveTrader / CasualUser (60/40) |
| **Tier B** | 45 | 50% | СРЕДНЯЯ (10–15 tx/мес) | Binance, Bybit, OKX, KuCoin | ❌ НЕТ | CasualUser / WeekendWarrior (55/45) |
| **Tier C** | 27 | 30% | НиЗКАЯ (3–6 tx/мес) | KuCoin, MEXC | ❌ НЕТ | Ghost |

### 5.2 Активность по тирам (Gaussian параметры)

| Tier | μ (mean) | σ (std) | min | max | skip_week_prob |
|------|----------|---------|-----|-----|----------------|
| Tier A (ActiveTrader) | 30 | 8 | 15 | 50 | 2–10% |
| Tier A (CasualUser) | 12 | 5 | 4 | 25 | 10–20% |
| Tier B (CasualUser) | 12 | 5 | 4 | 25 | 10–20% |
| Tier B (WeekendWarrior) | 10 | 4 | 2 | 20 | 20–35% |
| Tier C (Ghost) | 4 | 2 | 1 | 8 | 35–55% |

---

## 6. 90 Уникальных Персон

> � ️ **изменение относительно v3.0:** Вместо 4 общих шаблонов — 90 индивидуальных записей в `wallet_personas`.

### 6.1 Принцип уникальности

Каждый из 90 кошельков имеет **индивидуальные** параметры:

- `preferred_hours` — UTC-часы активности, сдвинутые по timezone воркера + личный шум ±1-2ч
- `tx_type_weights` — уникальные веса транзакций (SWAP/BRIDGE/STAKE/LP/NFT_MINT) с шумом ±7%
- `slippage_tolerance` — нецелое значение: 0.33–1.10% (не 0.5 и не 1.0!)
- `gas_preference` — slow/normal/fast
- `skip_week_probability` — вероятность пропустить неделю
- `first_tx_delay_days` — задержка до первой TX: A=3–10d, B=5–14d, C=7–21d

### 6.2 Timezone привязка к географии

| Worker | Локация | Timezone | Preferred hours (пример UTC) |
|--------|---------|----------|------------------------------|
| Worker 1 | Amsterdam | UTC+1 | [9,10,11,15,16,17,21,22] |
| Worker 2 | Reykjavik | UTC+0 | [8,9,10,14,15,16,20,21] |
| Worker 3 | Reykjavik | UTC+0 | [8,9,10,14,15,16,20,21] |

> IP-геолокация прокси ВСЕГДА совпадает с timezone поведения кошелька.  
> Если прокси — Iceland (UTC+0), кошелёк активен в UTC+0 часы.

### 6.3 Шумовые транзакции

| Тип | Вероятность (диапазон по архетипу) | Описание |
|-----|-------------------------------------|----------|
| wrap/unwrap ETH | 3–20% | Wrap ETH → WETH и обратно |
| approve без swap | 2–15% | ERC-20 approve без последующей операции |
| cancel транзакции | 1–12% | Отмена pending TX с higher gas |

---

## 7. 5 Бирж и цепочки финансирования

### 7.1 Субаккаунты и сети вывода

| Биржа | Субаккаунтов | Кошельков | Сети вывода | Tier |
|-------|-------------|-----------|-------------|------|
| Binance | 4 | 20 | Arbitrum, Base, BNB Chain | A + B |
| Bybit | 4 | 20 | Arbitrum, Optimism, Base | A + B |
| OKX | 4 | 20 | Arbitrum, Base, Optimism | A + B |
| KuCoin | 3 | 15 | Base, Polygon, Arbitrum | B + C |
| MEXC | 3 | 15 | Polygon, BNB Chain, Base | C |
| **итого** | **18** | **90** | | |

### 7.2 изоляция цепочек финансирования

- **18 изолированных цепочек** × 5 кошельков (порог детекции Nansen/Trusta: >20)
- Каждая цепочка — отдельный субаккаунт на отдельной бирже
- **Temporal isolation**: задержка 24–168 часов (1–7 дней) между выводами в одной цепочке
- Суммы: базовая ± 25% шум (не круглые числа: не $50, а $47.23 или $53.87)

---

## 8. Протоколы для фарминга (2026)

### 8.1 Активные протоколы

| Приоритет | Протокол | Чейн | Токен | Вероятность дропа | Кошельки | Слой |
|-----------|----------|------|-------|-------------------|---------|------|
| 🔥🔥🔥 **S** | Base (Coinbase L2) | Base | Не выпущен | 82% | ВСЕ 90 | web3.py |
| 🔥🔥🔥 **S** | Ink (Kraken L2) | Ink | INK (анонс) | 88% | ВСЕ 90 | web3.py |
| 🔥🔥🔥 **S** | MetaMask MASK | Ethereum | MASK | 65% | 18 Tier A | OpenClaw |
| 🔥🔥🔥 **S** | Polymarket POLY | Polygon | POLY (подтверждён) | 75% | 18 Tier A | OpenClaw |
| 🔥🔥 **A** | Unichain | Unichain | Не выпущен | 68% | ВСЕ 90 | web3.py |
| 🔥🔥 **A** | Robinhood Chain | Robinhood Chain | Не выпущен | 55% | ВСЕ 90 | web3.py (testnet) |
| 🔥🔥 **A** | Lighter (Perps) | Arbitrum | Не выпущен | 60% | 18 Tier A | OpenClaw |
| 🔥🔥 **A** | MegaETH | MegaETH | MEGA (TBD) | 35% | ВСЕ 90 | web3.py |
| 🔥🔥 **A** | OpenSea SEA | Base | SEA (подтверждён) | 72% | 18 Tier A | OpenClaw |
| 🔥 **B** | Aerodrome | Base | AERO (есть) | 70% | ВСЕ 90 | web3.py |
| 🔥 **B** | Farcaster | Base | Не выпущен | 50% | 18 Tier A | OpenClaw |
| 🔥 **B** | EdgeX | Arbitrum | Не выпущен | 45% | ВСЕ 90 | web3.py |
| 🔥 **B** | Espresso | Arbitrum | Не выпущен | 40% | ВСЕ 90 | web3.py |
| 🔥 **B** | Nexus Testnet | Ethereum | Не выпущен | 35% | ВСЕ 90 | web3.py |

### 8.2 Удалённые протоколы

| Протокол | Причина удаления |
|----------|------------------|
| Linea | Дроп прошёл сентябрь 2025, claim закрыт декабрь 2025 |
| Aztec | Токен торгуется с сентября 2025, retro airdrop отменён |
| Monad | Дроп прошёл ноябрь 2025 |
| Scroll, Taiko, zkSync Era, Starknet | Дропы прошли в 2024–2025 |
| Arbitrum | Дроп прошёл, протокол используется только как транзитная сеть |
| Hyperliquid S2 | Требует реального торгового капитала, несовместим с анти-Sybil |

### 8.3 Цепочки действий по протоколам

**Ink (Kraken L2) — обязательный порядок:**
```
bridge_to_ink → lend_tydro_ink → perp_nado_ink → lp_velodrome_ink
```

**Base — параллельные действия:**
```
swap_uniswap_base  |  lend_aave_base  |  lp_aerodrome_base  |  bridge_to_base
```

**Unichain:**
```
bridge_to_unichain → swap_uniswap_v4 → lp_uniswap_v4
```

---

## 9. OpenClaw — интеграция

### 9.1 Архитектура (исправление относительно v3.0)

> � ️ **Важно:** OpenClaw работает как **долгоживущий gateway-процесс**, не через `subprocess.run()`.

```
master_node.py
    └── openclaw/manager.py
            └── HTTP POST → http://localhost:8080/task (OpenClaw webhook)
                    └── OpenClaw выполняет задачу в браузере
                            └── Callback → manager.py → PostgreSQL + Telegram
```

**Systemd сервис:** `farming-openclaw.service` запускается при старте системы и остаётся активным.  
**Паузы между агентами:** 30–90 минут (случайно) — имитация естественного поведения.  
**OpenRouter ключ:** ОТДЕЛЬНЫЙ от основного ключа Python-агентов.

### 9.2 Задачи OpenClaw для Tier A

| Задача | Газ | Очки | Частота | Важность |
|--------|-----|------|---------|----------|
| Snapshot vote | 0 (off-chain) | +2 | 10 голосований | Обязательно |
| POAP claim | 0 | +1 за штуку | До 5 POAP (разные события!) | Обязательно |
| Gitcoin donate | $1–2 | +5 | разово | Обязательно |
| ~~ENS регистрация~~ | ~~$5–10~~ | ~~+10~~ | ~~разово (годовая)~~ | ❌ Заменено на Coinbase ID |
| **Coinbase ID (cb.id)** | **$0 (FREE)** | **+9** | **разово** | ✅ **Обязательно (Tier A)** |
| Lens Profile | $2 (Polygon) | +3 | разово | Обязательно |
| Discord verify | 0 | +2 | � азово | Опционально |
| Lighter perps | $0.01–0.1 | — | 3 tx/мес | Tier A only |
| OpenSea NFT | $5–50 | — | 2 tx/мес | Tier A only |
| Farcaster пост | 0 | — | 1–2/нед | Tier A only |

**Цель Gitcoin Passport Score:** 25–30 баллов (минимум большинства проектов: 15–20)

---

## 10. Анти-Sybil стратегия (12 пунктов)

1. **изоляция цепочек финансирования** — 18 цепочек × 5 кошельков, разные CEX, temporal gaps 1–7 дней. Порог детекции Nansen/Breadcrumbs: >20 кошельков в цепочке.

2. **Поведенческая уникальность** — 90 уникальных персон, Gaussian timing (`numpy.random.normal`, не `random.uniform`), суммы ±25% с шумом, запрет синхронных транзакций между кошельками одного воркера.

3. **IP изоляция по географии** — iproyal residential proxy, Decodo 4G/5G Netherlands (Worker 1) и Iceland (Workers 2–3). Sticky-сессии, ротация не чаще 1 раза в неделю. `curl_cffi` для TLS-fingerprinting (имитирует Chrome, не детектируется как datacenter).

4. **Пороговые фильтры** — цепочки ≤5 кошельков, `GasController` (баланс >0 перед TX), `Gradual activation` Tier C — не раньше 3-й недели, минимум 2–4 протокола на старте.

5. **� епутация web3.py** — стейкинг Lido (Tier A 30%, Tier B 20%), governance vote через контракт (`governance_vote_direct` для Tier B, не через браузер), Gitcoin донаты ТОЛЬКО через OpenClaw (не web3.py!).

6. **� епутация OpenClaw (Tier A)** — ENS (10 pts), POAP × 5 разных событий (5 pts), Gitcoin Passport (5 pts), Snapshot × 10 голосований (2 pts), Lens Profile (3 pts). Цель: 25–30 баллов.

7. **ML-устойчивость** — уникальный lifecycle каждого кошелька, разные `first_tx_delay_days` (1–21 дней), вариация `gas_preference` и `slippage_tolerance`, шумовые транзакции, пост-snapshot активность 2–4 недели.

8. **Пост-snapshot поведение** — продолжать активность 2–4 недели после snapshot. Мониторинг on-chain изменений. Поле `post_snapshot_active_until` в `wallets`.

9. **Выбор протоколов 2026** — только активные L2 без завершённых дропов. Приоритет: Base, Ink, Unichain, Robinhood Chain, MegaETH. Blacklist: Linea, Aztec, Monad, Scroll, Taiko, zkSync, Starknet, Arbitrum (дропы прошли).

10. **Прокси-разнообразие** — Decodo 4G/5G, IPRoyal residential proxy.

11. **Browser Fingerprint изоляция** — отдельные профили Dolphin Anty / AdsPower для каждого Tier A кошелька. Уникальные canvas fingerprint, WebGL renderer, timezone, language. Профили хранятся в `/opt/farming/openclaw/profiles/`.

12. **Диверсификация протоколов** — разные `first_protocol` при инициализации кошелька: Tier A — 3–6 стартовых протоколов, Tier B — 2–4, Tier C — 1–2. Запрет одинакового стартового протокола у >10% кошельков одного тира.
13. Имитация «человеческих» ошибок и неидеальности
    Редкие неудачные транзакции (revert) из-за intentional манипуляций с slippage или allowance.
    Отмена (cancel) зависших транзакций с повышением газа — имитация нетерпения.
    Использование неоптимальных маршрутов свопов (например, через пару с низкой ликвидностью) для части кошельков.
    Случайные approve без последующей операции (2–15% в зависимости от архетипа, уже есть в ТЗ, но важно реализовать с реалистичными суммами).
14. Кросс-чейн синхронизация и временные задержки
    При активности одного кошелька в нескольких L2 (например, Base и Ink) обеспечивать правдоподобные интервалы между транзакциями в разных сетях — минимум 10–30 минут (учитывая время бриджей).
    Избегать «телепортации»: если кошелёк сделал tx в Base, следующая в Ink не может быть через 1 минуту без использования моста.
    Использовать разные мосты для разных кошельков (Hop, Across, официальные), чтобы не создавать паттерн «один мост на всех».
15. Управление балансами и газом без паттернов
    Автодозаправка (GasController) должна выполняться с CEX на L2 не синхронно для всех кошельков одной цепочки. Разносить по времени на 1–7 дней.
    Суммы дозаправки — не кратные, с шумом (как в пункте 1), и с разных субаккаунтов.
    Избегать ситуации, когда у всех кошельков баланс падает ниже порога одновременно.
16. Динамическая реакция на прокси и RPC
    Мониторинг «здоровья» прокси: если IP попал в чёрный список (ошибки 403, капча), автоматически сменить на другой из того же пула и той же географии, но с сохранением sticky-сессии (не чаще 1 раза в неделю).
    Ротация RPC-эндпоинтов для каждого кошелька (из chain_rpc_endpoints), чтобы не светить постоянным подключением с одного IP к одному провайдеру.
17. Децентрализация принятия решений (Agent-based)
    Каждый кошелёк имеет свой экземпляр «персоны» с уникальной логикой выбора протоколов и времени, а не централизованный планировщик, который даёт команды всем сразу. Это уже заложено в wallet_personas, но важно, чтобы даже внутри одного тира решения принимались асинхронно.
    Использовать numpy.random для генерации индивидуальных параметров при старте и не менять их кардинально в процессе (только адаптация, например, AdaptiveSkipper).
18. Off-chain активность и социальные профили (Tier A)
    Для Tier A обязательно создать и поддерживать профили в Farcaster и Lens с постами/репостами (1–2 в неделю), подписками на случайные аккаунты.
    Участие в Discord-серверах проектов (verify, редкие сообщения) — но через OpenClaw с паузами и уникальными профилями.
    Это создаёт «социальную репутацию», которую некоторые дропы也开始 учитывать (например, через Galileo или SimilarWeb).
19. Пост-дроп поведение (пункт 8 детализация)
    После получения токенов не выводить всё сразу. Растягивать продажи на 2–4 недели, используя разные DEX и суммы.
    Часть токенов оставлять в стейкинге/LP для имитации долгосрочного холдера.
    Избегать массового одновременного вывода с нескольких кошельков на одну биржу — разносить по субаккаунтам и временным окнам (как в пункте 1).
20. Рандомизация жизненного цикла кошелька
    Варьировать не только first_tx_delay_days, но и дату «рождения» кошелька (первая транзакция вообще, если это новый кошелёк). Для старых кошельков (с предысторией) — использовать разные даты первой активности.
    Для Tier A создать видимость «миграции»: сначала активность в Ethereum L1 (несколько простых действий через мосты), затем переход в L2 через несколько месяцев.
21. Использование смарт-контрактных кошельков (Safe)
    Для части Tier A можно развернуть мультиподписи (Safe) с 1 владельцем (как EOA). Это меняет структуру транзакций и усложняет кластеризацию.
    Такие кошельки могут участвовать в голосованиях по управлению (Snapshot) и получать дополнительные очки.
22. Мониторинг новых метрик анти-Sybil
    Подписаться на обновления Trusta, Nansen, Breadcrumbs и других аналитиков. При появлении новых методов детекции (например, анализ времени жизни кошелька между транзакциями) оперативно вносить изменения в параметры wallet_personas через Protocol Research (модуль 15).
    Периодически (раз в месяц) прогонять свои кошельки через публичные чекеры (типа sybil.list), чтобы выявить возможные связи.
23. Изоляция по времени выполнения задач OpenClaw
    Задачи OpenClaw (Snapshot, Gitcoin и др.) для разных Tier A должны выполняться с интервалами не менее 30–90 минут (как в ТЗ), но также важно, чтобы они не группировались по дням недели. Пусть один кошелёк делает POAP в понедельник, другой — в среду.
    Использовать разные аккаунты Gitcoin Passport (с разными стикерами) и не привязывать все к одному GitHub/Twitter.
    Дополнения к анти-Sybil стратегии для работы в L2 (продолжение, пункты 20+)
---

## 11. База данных (PostgreSQL 15)

### 11.1 итоговая структура (30 таблиц, 3 файла)

```bash
psql -U farming_user -d farming_db -f database/schema.sql                # 21 таблица
psql -U farming_user -d farming_db -f database/schema_patch_personas.sql # +3 (персоны, воркеры, прокси)
psql -U farming_user -d farming_db -f database/schema_patch_protocols.sql # +6 (RPC, контракты, action-цепочки)
```

### 11.2 Таблицы

| Группа | Таблицы |
|--------|---------|
| **инфраструктура** | `worker_nodes`, `proxy_pool` |
| **CEX** | `cex_subaccounts`, `funding_chains`, `funding_withdrawals` |
| **Кошельки** | `wallets`, `wallet_personas` |
| **Персоны** | `personas_config` (архетипы-шаблоны) |
| **Протоколы** | `protocols`, `protocol_contracts`, `protocol_actions`, `chain_rpc_endpoints`, `chain_rpc_health_log` |
| **Points** | `points_programs`, `wallet_points_balances` |
| **Активность** | `wallet_protocol_assignments`, `scheduled_transactions`, `weekly_plans` |
| **OpenClaw** | `openclaw_tasks`, `openclaw_reputation` |
| **Аирдропы** | `airdrops`, `snapshot_events` |
| **Вывод** | `withdrawal_plans`, `withdrawal_steps` |
| **Мониторинг** | `gas_snapshots`, `protocol_research_reports`, `news_items`, `system_events` |

### 11.3 Ключевые ENUMы

```sql
wallet_tier:   A | B | C
persona_type:  ActiveTrader | CasualUser | WeekendWarrior | Ghost
wallet_status: inactive | warming_up | active | paused | post_snapshot | compromised | retired
tx_type:       SWAP | BRIDGE | STAKE | LP | NFT_MINT | WRAP | APPROVE | CANCEL |
               GOVERNANCE_VOTE | GOVERNANCE_VOTE_DIRECT | GITCOIN_DONATE |
               POAP_CLAIM | ENS_REGISTER | SNAPSHOT_VOTE | LENS_POST
action_layer:  web3py | openclaw
```

---

## 12. Модули (21 файл)

| # | Файл | Назначение |
|---|------|------------|
| 1 | `database/schema.sql` | PostgreSQL схема — 30 таблиц, 35+ индексов, 14 ENUMов ✅ |
| 2 | `database/db_manager.py` | CRUD для всех таблиц, `log_openclaw_task`, `update_openclaw_score`, `get_wallet_proxy` |
| 3 | `funding/secrets.py` | Fernet шифрование API-ключей и приватных ключей кошельков |
| 4 | `notifications/telegram_bot.py` | `/panic`, `/status`, `/balances`, `/openclaw_status`, `/approve_withdrawal_ID`. Ежедневный отчёт 09:00 |
| 5 | `wallets/generator.py` | Генерация 90 кошельков, 90 уникальных персон, привязка к воркерам, Fernet шифрование ключей |
| 6 | `funding/cex_integration.py` | Единый интерфейс к 5 биржам через CCXT. Вывод только в L2, не Ethereum mainnet |
| 7 | `funding/engine.py` | `FundingDiversificationEngine`: 18 цепочек × 5 кошельков, temporal isolation, суммы ±25% |
| 8 | `worker/api.py` | Flask API на каждом Worker, JWT авторизация, слушает только `127.0.0.1:5000` |
| 9 | `activity/personas.py` | Загрузка индивидуальных персон из `wallet_personas`, методы расписания |
| 10 | `activity/transaction_types.py` | Параметры транзакций по `protocol_actions`, нецелые суммы |
| 11 | `activity/scheduler.py` | Gaussian-расписание на неделю, исключение синхронности, шумовые TX |
| 12 | `activity/executor.py` | `TaskExecutor`: отправка задач Workers через JWT REST API, вызов `OpenClawManager` |
| 13 | `activity/adaptive.py` | `AdaptiveSkipper`: пропуск при gas >200 gwei, снижение активности при ошибках |
| 14 | `openclaw/manager.py` | `OpenClawManager`: HTTP POST на OpenClaw webhook, последовательный запуск с паузами 30–90 мин |
| 15 | `protocol_research/engine.py` | LLM-агент (OpenRouter, каждое воскресенье), обновление `protocols`, `protocol_contracts`, `protocol_actions` |
| 16 | `research/news_analyzer.py` | CryptoPanic бесплатный API, анализ релевантности, ключевые слова: airdrop/token launch/layer 2/points |
| 17 | `monitoring/airdrop_detector.py` | Async сканирование 90 кошельков каждые 6 часов (Etherscan, Basescan, Arbiscan) + points API |
| 18 | `monitoring/token_verifier.py` | CoinGecko + эвристики (claim/reward/visit), confidence >0.6 для алерта |
| 19 | `withdrawal/orchestrator.py` | Tier-стратегии вывода, human-in-the-loop через Telegram, `/approve_withdrawal_ID` |
| 20 | `infrastructure/gas_controller.py` | Мониторинг балансов (A: >0.003 ETH, B: >0.002, C: >0.001), `BulkSender` дозаправка, RPC health |
| 21 | `master_node.py` | `APScheduler`: каждый час TX, каждые 6ч airdrop scan, воскресенье research + OpenClaw batch |

---

## 13. Установка Master Node (Ubuntu 24.04)

### 13.1 Быстрый запуск

```bash
scp master_setup.sh root@<MASTER_IP>:/root/
ssh root@<MASTER_IP>
bash /root/master_setup.sh
```

### 13.2 Что устанавливается

| Компонент | Версия | Назначение |
|-----------|--------|------------|
| Python | 3.11 | Основной язык |
| PostgreSQL | 15 | БД с оптимизацией 4GB RAM |
| Node.js | 20 LTS | Runtime для OpenClaw |
| OpenClaw | latest | Browser automation gateway |
| Playwright/Chromium | latest | Браузер для OpenClaw |
| web3 | 6.20.3 | EVM транзакции |
| ccxt | 4.3.95 | 5 бирж |
| curl_cffi | 0.7.3 | TLS fingerprinting |
| cryptography | 43.0.3 | Fernet шифрование |
| python-telegram-bot | 21.9 | Telegram уведомления |
| APScheduler | 3.10.4 | Планировщик |
| psycopg2-binary | 2.9.10 | PostgreSQL драйвер |
| flask-jwt-extended | 4.7.1 | JWT для Worker API |
| openai | 1.58.1 | OpenRouter API |
| numpy | 2.2.1 | Gaussian randomization |
| loguru | 0.7.3 | Логирование |
| tenacity | 9.0.0 | Retry/backoff |

### 13.3 Безопасность

- SSH на нестандартный порт **2299**, только key authentication, root login отключён
- **UFW**: запрещено всё входящее кроме SSH и localhost. Worker IP добавляются вручную после получения
- **fail2ban**: бан после 3 попыток SSH (1ч), 5 попыток к PostgreSQL (30мин)
- Fernet ключ и JWT secret генерируются автоматически → `/root/.farming_secrets`

### 13.4 Структура директорий

```
/opt/farming/
├── .env                          # Секреты (не в git!)
├── master_node.py                # Модуль 21
├── database/                     # Модули 1-2
├── funding/                      # Модули 3, 6, 7
├── wallets/                      # Модуль 5
├── activity/                     # Модули 9-13
├── openclaw/                     # Модуль 14
│   ├── config.json
│   └── profiles/                 # Dolphin Anty профили для 18 Tier A
├── protocol_research/            # Модуль 15
├── research/                     # Модуль 16
├── monitoring/                   # Модули 17-18
├── withdrawal/                   # Модуль 19
├── infrastructure/               # Модуль 20
├── notifications/                # Модуль 4
├── venv/                         # Python virtualenv
├── logs/
├── data/
└── keys/                         # chmod 700
```

---

## 14. Вывод средств (стратегии по тирам)

| Tier | Стратегия | Шаги |
|------|-----------|------|
| Tier A | 15% → 25% → 30% → 30% HODL | 4 этапа, растянутые во времени |
| Tier B | 20% → 40% → 40% | 3 этапа |
| Tier C | 50% → 50% | 2 этапа |

> **Human-in-the-loop обязателен:** каждый вывод требует подтверждения через Telegram команду `/approve_withdrawal_<ID>`.

---

## 15. Прогноз доходности

### 15.1 Сценарии (49 квалифицированных кошельков с учётом success rate)

| Сценарий | Чистая прибыль | Вероятность |
|----------|----------------|-------------|
| 🐻 Conservative | **$40,403** | 30% |
| ➡️ Moderate | **$138,283** | 40% |
| 🚀 Optimistic | **$483,300** | 15% |
| 💀 Провал (2–3 дропа из 14) | $2,300–7,300 | 15% |


### 15.2 Success Rate по тирам

| Tier | Success rate | Дропов из 14 |
|------|-------------|--------------|
| Tier A (с OpenClaw + Gitcoin) | 75% | ~10.5 |
| Tier B | 55–65% | ~8–9 |
| Tier C | 40–55% | ~5–7 |

---

## 16. План развёртывания

### 16.1 До начала разработки (человек)

- [ ] Получить IP-адреса 4 VPS на Hotkeys
- [ ] Создать API-ключи на 5 биржах с привязкой к IP Master Node (whitelist)
- [ ] Пополнить биржи на $200 **ТОЛЬКО ПОСЛЕ** привязки IP
- [ ] Создать второй OpenRouter ключ (для OpenClaw, лимит $5/мес)
- [ ] Настроить Telegram-бота (@BotFather), получить `BOT_TOKEN` и `CHAT_ID`

### 16.2 развёртывание (AI через KiloCode)

**Неделя 1–2: инфраструктура**
1. Запуск `master_setup.sh` на Master Node
2. Запуск `worker_setup.sh` на Workers 1, 2, 3
3. � азвёртывание схемы БД (3 файла SQL)
4. Модули 3, 4, 5: secrets.py + telegram_bot.py + generator.py

**Неделя 3–4: Транзакционный слой**

5. Модули 6, 7: CEX интеграция + FundingDiversificationEngine
6. Модуль 8: Worker API (Flask + JWT)
7. Модули 9–13: Персоны + scheduler + executor + adaptive

**Неделя 5–7: OpenClaw + мониторинг**

8. Модуль 14: OpenClawManager (gateway интеграция)
9. Модули 15, 16: Protocol Research + News Analyzer
10. Модули 17, 18: Airdrop Detector + Token Verifier

**Неделя 8: Финализация**

11. Модули 19, 20, 21: Withdrawal + Gas Controller + Master Node
12. **Testnet Sepolia** — тест 10 кошельков, 2 недели
13. После успешного теста → **Production funding** 90 кошельков

### 16.3 После запуска (производство)

- Неделя 4: Staking Tier A (Lido $9) + Gitcoin donations ($36) через OpenClaw
- Неделя 4: ~~ENS регистрация Tier A (18 × $5 = $90)~~ → **Coinbase ID (FREE, только gas ~$2)** через OpenClaw
- Неделя 4–6: OpenClaw — POAP, Snapshot, Lens для Tier A
- Цель недели 6: Gitcoin Passport Score ≥ 25 для всех 18 Tier A кошельков
- Месяцы 2–6: Мониторинг дропов, пост-snapshot активность, Protocol Research

---

## 17. Переменные окружения (.env)

```env
# База данных
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=farming_db
DB_USER=farming_user
DB_PASS=<из .farming_secrets>

# Шифрование
FERNET_KEY=<из .farming_secrets>

# Telegram
TELEGRAM_BOT_TOKEN=<из BotFather>
TELEGRAM_CHAT_ID=<твой chat_id>

# OpenRouter (ДВА � АЗНЫХ КЛЮЧА!)
OPENROUTER_API_KEY=<основной, для Python агентов>
OPENROUTER_API_KEY_OPENCLAW=<отдельный, только для OpenClaw>

# Workers JWT
JWT_SECRET=<из .farming_secrets>

# IP адреса Workers (заполнить после аренды VPS)
WORKER1_IP=<Netherlands>
WORKER2_IP=<Iceland>
WORKER3_IP=<Iceland>
```

---

*Конец ТЗ v4.0 — Crypto Airdrop Farming System*
*Следующий статус: ожидание IP-адресов VPS → начало развёртывания*
