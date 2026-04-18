# Worker Module (Module 8)

Flask REST API на Workers для выполнения on-chain транзакций от Master Node через SSH tunnel.

---

## Файлы модуля

### `api.py`

**Зачем нужен:**  
Исполняет транзакции на blockchain от имени 30 кошельков, назначенных Worker'у. Изолирует приватные ключи — они никогда не покидают Worker.

**Бизнес-задача:**  
Выполняет swaps, bridges, withdrawals и другие on-chain операции через web3.py. Проверяет CEX подключения. Возвращает балансы кошельков Master Node.

**Встраивание в систему:**  
Работает на каждом Worker сервере (3 nodes). Вызывается Master Node через SSH tunnel (`ssh -L 5000:127.0.0.1:5000 worker1`). Взаимодействует с БД (wallets, chain_rpc_endpoints), web3.py, ProxyManager, CEXManager, TransactionExecutor.

**Ключевые особенности:**
- **Localhost only:** Слушает 127.0.0.1:5000 — доступ только через SSH tunnel
- **JWT authentication:** Все endpoints (кроме /health) требуют JWT token
- **Private key isolation:** Ключи извлекаются из локальной БД, расшифровываются in-memory, удаляются сразу после signing
- **Anti-Sybil proxy binding:** Каждая транзакция использует proxy конкретного кошелька (не Worker IP)
- **Internal transfer blocking:** Запрещает переводы между farm кошельками
- **Pause/Resume:** Emergency pause через /panic команду

**Endpoints:**
| Endpoint | Назначение | JWT |
|----------|------------|-----|
| `/health` | Health check + heartbeat | Нет |
| `/execute_transaction` | On-chain транзакции (swap, bridge, etc.) | Да |
| `/api/execute_withdrawal` | Вывод на cold wallet | Да |
| `/balances` | Балансы 30 кошельков | Да |
| `/pause` | Emergency pause | Да |
| `/resume` | Resume после pause | Да |
| `/check_cex_connections` | Проверка 18 CEX субаккаунтов | Да |

**Заглушки:**
- ✅ **ДА** — ETH price = $3000 (TODO: price oracle)
- ✅ **ДА** — RPC URL fallback на Base mainnet

**Хардкод:**
- JWT token expires = 24 hours
- Gas max = 200 gwei
- Min withdrawal = $10 USDT
- Default chain_id = 8453 (Base)
- Gas buffer = +20%

---

## Архитектура безопасности

```
Master Node
    ↓ SSH Tunnel (ssh -L 5000:127.0.0.1:5000 worker1)
Worker API (127.0.0.1:5000)
    ↓ JWT verification
    ↓ Local DB query (encrypted_private_key)
    ↓ Fernet decrypt (in-memory)
    ↓ web3.py + wallet's proxy
EVM Network
```

**Критичные правила:**
1. Private key NEVER передаётся по сети
2. Private key расшифровывается in-memory только
3. Private key удаляется сразу после signing (`del private_key`)
4. Все транзакции используют wallet-specific proxy

---

## Интеграция с системой

| Компонент | Взаимодействие |
|-----------|----------------|
| **Master Node** | Вызывает через SSH tunnel + JWT |
| **DatabaseManager** | Читает wallets, chain_rpc_endpoints |
| **ProxyManager** | Получает proxy для кошелька |
| **TransactionExecutor** | Исполняет contract functions |
| **CEXManager** | Проверяет CEX API connections |
| **web3.py** | On-chain транзакции |

---

## Anti-Sybil механизмы

| Механизм | Реализация |
|----------|------------|
| **Wallet-specific proxy** | Каждая транзакция через proxy кошелька |
| **No Worker IP leakage** | 90 уникальных IP вместо 3 Worker IP |
| **ProxyRequiredError** | Блокировка транзакций без proxy |

---

## Withdrawal Security Flow

```
1. Request validation (wallet_address, destination, amount)
2. Internal transfer check (destination не farm wallet)
3. Worker assignment check (wallet принадлежит этому Worker)
4. Encrypted key retrieval from LOCAL DB
5. Fernet decrypt (in-memory)
6. Execute withdrawal via wallet's proxy
7. CRITICAL: del private_key (cleanup)
8. Log to system_events
9. Return tx_hash
```

**Internal Transfer Protection:**
```python
# Блокирует если destination — farm wallet
internal_wallet_check = db.execute_query(
    "SELECT id FROM wallets WHERE address = %s",
    (destination.lower(),),
    fetch='one'
)
if internal_wallet_check:
    return {'error': 'Internal transfers blocked'}, 403
```

---

## Критичные моменты

1. **ENCRYPTION_KEY required:** Без ключа Worker не может расшифровать приватные ключи
2. **JWT_SECRET required:** Без секрета API не стартует
3. **WORKER_ID required:** Необходим для определения назначенных кошельков
4. **SSH tunnel mandatory:** Прямой доступ извне заблокирован (127.0.0.1 only)
5. **UFW whitelist:** Только Master Node IP имеет доступ к Worker

---

## Запуск

```bash
# Production
python worker/api.py --worker-id 1 --host 127.0.0.1 --port 5000

# Development (with debug)
python worker/api.py --worker-id 1 --debug
```

---

## Переменные окружения (критичные)

| Variable | Назначение |
|----------|------------|
| `JWT_SECRET` | Secret для JWT signing |
| `WORKER_ID` | ID Worker (1, 2, или 3) |
| `ENCRYPTION_KEY` | Fernet key для расшифровки private keys |

---

## Emergency процедуры

**Pause Worker:**
```
POST /pause
Authorization: Bearer <JWT>
```

**Resume Worker:**
```
POST /resume
Authorization: Bearer <JWT>
```

**Health Check (no JWT):**
```
GET /health
→ {"status": "healthy", "worker_id": 1, "paused": false}
```
