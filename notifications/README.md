# Notifications Module

Telegram Bot для мониторинга и управления системой: human-in-the-loop control, real-time alerts, command interface.

---

## 📁 Архитектурный анализ файлов модуля

### `telegram_bot.py` (Module 4)

**Зачем:** Закрывает проблему отсутствия контроля над автономной системой. Обеспечивает human-in-the-loop для критичных операций и real-time visibility состояния системы.

**Бизнес-задача:** Telegram Bot с командным интерфейсом для emergency control, approval workflow, и автоматических alerts о событиях системы.

**Интеграция:**
- **Commands (управление):**
  - `/panic` → Emergency stop всех транзакций, global PANIC_MODE flag
  - `/resume` → Возобновление после panic
  - `/status` → Workers status, wallet counts, pending TX, funding progress
  - `/balances` → Балансы по tiers (Tier A/B/C totals)
  - `/health` → System health dashboard (DB, Workers, RPC endpoints)
  - `/revive_worker <ID>` → HTTP wake-up request к offline Worker

- **Commands (protocol research):**
  - `/research_status` → Pending protocols queue
  - `/approve_protocol_<ID>` → Approve protocol для farming
  - `/reject_protocol_<ID>` → Reject protocol
  - `/research_config` → Research engine config, last cycle stats
  - `/force_research_cycle` → Manual trigger research (restricted)

- **Commands (withdrawal):**
  - `/approve_<ID>` → Human-in-the-loop approval withdrawal step
  - `/reject_<ID>` → Reject withdrawal step

- **Automatic Alerts:**
  - 🚨 CRITICAL → Database errors, CEX API failures, Worker offline
  - ⚠️ WARNING → Low gas balance, high gas price (>200 gwei), funding delays
  - 📢 AIRDROP → New token detected on wallet
  - 💰 WITHDRAWAL → Approval request for withdrawal step

- **Database:** `scheduled_transactions`, `withdrawal_steps`, `wallets`, `worker_nodes`, `system_events`, `protocol_research_pending`

**Ключевые ограничения:**
- **Authentication:** Whitelist по `TELEGRAM_CHAT_ID` — только один chat имеет доступ
- **Non-blocking polling:** Background daemon thread — не блокирует master_node
- **Panic mode:** Global `PANIC_MODE` flag — отменяет все pending transactions
- **Human-in-the-loop:** Withdrawal steps требуют явного `/approve_<ID>` или `/reject_<ID>`
- **Singleton pattern:** Один bot instance через `get_bot()`
- **Module-level convenience:** `send_alert()`, `send_withdrawal_request()`, `send_airdrop_alert()` для простого вызова из других модулей

**Заглушки:** ✅ **ДА** — `_get_balances_summary()` возвращает mock data (все значения 0.0), TODO: "Fetch actual on-chain balances via Worker API".  
**Хардкод:** `.env` path `/opt/farming/.env`, Worker heartbeat threshold 5 min (300 sec), emoji mapping для severity, `allowed_usernames = ['your_username']` для `/force_research_cycle` (TODO: configure).

---

## 📊 Сводка Anti-Sybil и безопасности

| Механизм | Защита от |
|----------|-----------|
| CHAT_ID whitelist | Unauthorized access к bot |
| Human-in-the-loop withdrawals | Автоматический вывод средств без контроля |
| Panic mode | Неконтролируемое выполнение транзакций при ошибке |
| Restricted commands (`/force_research_cycle`) | Несанкционированный запуск LLM analysis |

---

## 📈 Сводка по заглушкам и хардкоду

| Файл | Заглушки | Хардкод |
|------|----------|---------|
| `telegram_bot.py` | ✅ **ДА** (`_get_balances_summary` mock) | ✅ **ДА** (paths, thresholds, allowed_usernames) |

**Ключевой вывод:** Одна заглушка — mock balances вместо реальных on-chain balances. Требует интеграции с Worker API для получения актуальных балансов.

Хардкод присутствует как:
- Конфигурация путей и thresholds
- Access control lists (allowed_usernames)
- UI elements (emoji mapping)

---

## 🔗 Зависимости

```
telegram_bot.py → database.db_manager (queries)
telegram_bot.py → monitoring.health_check (system health)
telegram_bot.py → research.scheduler (force_research_cycle)
telegram_bot.py → all modules (via send_alert convenience function)
```

---

## 📌 Рекомендации

1. **Реализовать `_get_balances_summary()`:** Интеграция с Worker API для on-chain balances — критично для `/balances` command
2. **Вынести thresholds в config:** Worker heartbeat threshold (5 min), panic mode settings
3. **Настроить `allowed_usernames`:** Заменить `'your_username'` на реальные usernames для restricted commands
4. **Rate limiting:** Добавить throttling для alerts (не спамить при burst errors)
