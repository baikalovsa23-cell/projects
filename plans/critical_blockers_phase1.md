# Критичные блокеры для запуска Фазы 1 (Tier A тестнет)

**Дата:** 2026-03-21  
**Статус:** Анализ завершён

---

## 📊 Итоговая сводка

| Пункт | Статус | Критичность | Описание |
|-------|--------|-------------|----------|
| activity/8 | ✅ ОК | - | Таблица `wallet_transactions` существует в БД |
| activity/12 | ✅ ОК | - | `CHAIN_CONFIGS` читаются из БД с fallback |
| activity/19 | ❌ БЛОКЕР | 🔴 HIGH | WETH адреса захардкожены в `tx_types.py` |
| worker/1 | ❌ БЛОКЕР | 🔴 HIGH | `/execute_transaction` — заглушка (mock response) |
| worker/2 | ❌ БЛОКЕР | 🔴 HIGH | `execute_withdrawal_tx` привязан к Base |
| infrastructure/15 | ✅ ОК | - | `SERVER_IPS` читаются из БД с fallback |
| infrastructure/18 | ✅ ОК | - | `network_mode` и `safety_gates` реализованы |

**Итого:** 3 критичных блокера для запуска Фазы 1

---

## 🔴 БЛОКЕР 1: WETH адреса захардкожены

**Файл:** [`activity/tx_types.py`](activity/tx_types.py:377-387)

**Проблема:**
```python
# Строки 377-387
WETH_ADDRESSES = {
    1: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',  # Ethereum
    42161: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',  # Arbitrum
    8453: '0x4200000000000000000000000000000000000006',  # Base
    10: '0x4200000000000000000000000000000000000006',  # Optimism
    137: '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270',  # Polygon (WMATIC)
    56: '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c'  # BNB Chain (WBNB)
}
```

**Почему это блокер:**
- Нарушает принцип конфигурации через БД
- При добавлении новых сетей (Ink, MegaETH и др.) нужно править код
- Невозможно динамически обновлять адреса без деплоя

**Решение:**
1. Создать таблицу `chain_tokens` в БД:
```sql
CREATE TABLE chain_tokens (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER NOT NULL,
    token_symbol VARCHAR(10) NOT NULL,
    token_address VARCHAR(42) NOT NULL,
    is_native_wrapped BOOLEAN DEFAULT FALSE,
    UNIQUE(chain_id, token_symbol)
);
```

2. Заполнить таблицу данными:
```sql
INSERT INTO chain_tokens (chain_id, token_symbol, token_address, is_native_wrapped) VALUES
(1, 'WETH', '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', TRUE),
(42161, 'WETH', '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1', TRUE),
(8453, 'WETH', '0x4200000000000000000000000000000000000006', TRUE),
(10, 'WETH', '0x4200000000000000000000000000000000000006', TRUE),
(137, 'WMATIC', '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270', TRUE),
(56, 'WBNB', '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c', TRUE),
(57073, 'WETH', '0x...', TRUE),  -- Ink
(1088, 'WETH', '0x...', TRUE);   -- MegaETH
```

3. Обновить [`SwapBuilder._get_weth_address()`](activity/tx_types.py:369-387):
```python
def _get_weth_address(self) -> str:
    """Get WETH address for current chain from database."""
    chain_id = self.w3.eth.chain_id
    
    try:
        from database.db_manager import DatabaseManager
        db = DatabaseManager()
        
        token = db.execute_query(
            "SELECT token_address FROM chain_tokens WHERE chain_id = %s AND is_native_wrapped = TRUE",
            (chain_id,),
            fetch='one'
        )
        
        if token:
            return token['token_address']
    except Exception as e:
        logger.warning(f"Failed to load WETH address from DB: {e}")
    
    # Fallback to hardcoded values
    WETH_ADDRESSES = {
        1: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
        # ... rest of fallback
    }
    return WETH_ADDRESSES.get(chain_id, WETH_ADDRESSES[1])
```

**Приоритет:** HIGH (блокирует добавление новых сетей)

---

## 🔴 БЛОКЕР 2: `/execute_transaction` — заглушка

**Файл:** [`worker/api.py`](worker/api.py:370-447)

**Проблема:**
```python
# Строки 434-443
# TODO: Execute transaction via web3.py (Module 12)
# For now, return mock success
return jsonify({
    'success': True,
    'tx_hash': '0x' + 'a' * 64,  # Mock TX hash
    'gas_used': 150000,
    'gas_price_gwei': 15.3,
    'timestamp': datetime.utcnow().isoformat(),
    'note': 'Mock response — implement web3.py execution in Module 12'
}), 200
```

**Почему это блокер:**
- Master Node не может выполнять реальные транзакции через Workers
- Все транзакции возвращают mock данные
- Система не может работать в production режиме

**Решение:**
Интегрировать [`TransactionExecutor`](activity/executor.py:267) в Worker API:

```python
# Добавить импорт в начале файла
from activity.executor import TransactionExecutor

# Инициализировать executor глобально
executor = TransactionExecutor()

@app.route('/execute_transaction', methods=['POST'])
@jwt_required()
def execute_transaction():
    """Execute on-chain transaction via web3.py."""
    current_identity = get_jwt_identity()
    
    try:
        # Validate request
        data = request.get_json()
        if not data:
            return jsonify({'success': False, 'error': 'No JSON data provided'}), 400
        
        wallet_id = data.get('wallet_id')
        tx_type = data.get('tx_type')
        protocol_action_id = data.get('protocol_action_id')
        amount_usdt = data.get('amount_usdt')
        params = data.get('params', {})
        
        if not all([wallet_id, tx_type, protocol_action_id]):
            return jsonify({'success': False, 'error': 'Missing required fields'}), 400
        
        # Check if Worker is paused
        if WORKER_PAUSED:
            logger.warning(f"Transaction rejected (Worker paused) | Wallet: {wallet_id}")
            return jsonify({'success': False, 'error': 'Worker is paused'}), 403
        
        logger.info(
            f"Transaction request received | Wallet: {wallet_id} | "
            f"Type: {tx_type} | Protocol Action: {protocol_action_id} | "
            f"Requested by: {current_identity}"
        )
        
        # ✅ Execute transaction via TransactionExecutor
        result = executor.execute_contract_function(
            wallet_id=wallet_id,
            protocol_action_id=protocol_action_id,
            params=params,
            gas_preference=params.get('gas_preference', 'normal')
        )
        
        return jsonify({
            'success': True,
            'tx_hash': result['tx_hash'],
            'gas_used': result['gas_used'],
            'gas_price_gwei': float(result.get('gas_price', 0)),
            'timestamp': result['confirmed_at'].isoformat()
        }), 200
    
    except Exception as e:
        logger.exception(f"Transaction execution error | Error: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500
```

**Приоритет:** HIGH (блокирует выполнение транзакций)

---

## 🔴 БЛОКЕР 3: `execute_withdrawal_tx` привязан к Base

**Файл:** [`worker/api.py`](worker/api.py:166-322)

**Проблема:**
```python
# Строка 170
def execute_withdrawal_tx(
    private_key: str,
    destination: str,
    amount_usdt: Decimal,
    chain_id: int = 8453,  # Base mainnet by default
    wallet_id: Optional[int] = None
) -> Tuple[str, int, float]:

# Строка 201
rpc_url = os.getenv('RPC_URL_BASE')  # Base mainnet
if not rpc_url:
    raise ValueError("RPC_URL_BASE not set in .env")
```

**Почему это блокер:**
- Вывод средств возможен только в сети Base
- Невозможно выводить средства из других сетей (Arbitrum, Optimism и т.д.)
- RPC URL захардкожен на `RPC_URL_BASE`

**Решение:**
1. Получать RPC URL из БД по chain_id:
```python
def execute_withdrawal_tx(
    private_key: str,
    destination: str,
    amount_usdt: Decimal,
    chain_id: int = 8453,  # Base mainnet by default
    wallet_id: Optional[int] = None
) -> Tuple[str, int, float]:
    """Execute withdrawal transaction via web3.py with wallet's assigned proxy."""
    global proxy_manager
    
    # ✅ Get RPC URL from database by chain_id
    try:
        from database.db_manager import DatabaseManager
        db = DatabaseManager()
        
        chain_info = db.execute_query(
            "SELECT url FROM chain_rpc_endpoints WHERE chain_id = %s AND is_active = TRUE LIMIT 1",
            (chain_id,),
            fetch='one'
        )
        
        if not chain_info:
            raise ValueError(f"No active RPC endpoint found for chain_id: {chain_id}")
        
        rpc_url = chain_info['url']
    except Exception as e:
        logger.error(f"Failed to get RPC URL for chain {chain_id}: {e}")
        raise ValueError(f"Cannot get RPC URL for chain {chain_id}: {e}")
    
    # ... rest of the function
```

2. Добавить поддержку разных сетей в `wallet_withdrawal_network`:
```sql
-- Таблица уже существует (migration 040)
-- Нужно заполнить данными:
UPDATE wallets SET withdrawal_network = 'arbitrum' WHERE id IN (1, 2, 3);
UPDATE wallets SET withdrawal_network = 'base' WHERE id IN (4, 5, 6);
-- и т.д.
```

3. Обновить вызов функции в [`execute_withdrawal()`](worker/api.py:450-643):
```python
# Получить chain_id из withdrawal_network кошелька
wallet_network = db.execute_query(
    "SELECT withdrawal_network FROM wallets WHERE id = %s",
    (wallet['id'],),
    fetch='one'
)

if wallet_network:
    # Получить chain_id по имени сети
    chain_info = db.execute_query(
        "SELECT chain_id FROM chain_rpc_endpoints WHERE chain_name = %s LIMIT 1",
        (wallet_network['withdrawal_network'],),
        fetch='one'
    )
    
    if chain_info:
        withdrawal_chain_id = chain_info['chain_id']
    else:
        withdrawal_chain_id = 8453  # Fallback to Base
else:
    withdrawal_chain_id = 8453  # Default to Base

# Execute withdrawal with correct chain_id
tx_hash, gas_used, gas_price = execute_withdrawal_tx(
    private_key=private_key,
    destination=destination,
    amount_usdt=amount_usdt,
    chain_id=withdrawal_chain_id,  # ✅ Use wallet's withdrawal network
    wallet_id=wallet['id']
)
```

**Приоритет:** HIGH (блокирует вывод средств из разных сетей)

---

## ✅ Проверенные пункты (ОК)

### activity/8: Таблица `wallet_transactions` существует

**Файлы:**
- [`database/schema.sql`](database/schema.sql:719)
- [`database/migrations/037_missing_tables.sql`](database/migrations/037_missing_tables.sql:4)

**Статус:** ✅ Таблица создана и содержит все необходимые поля

---

### activity/12: `CHAIN_CONFIGS` читаются из БД

**Файл:** [`activity/executor.py`](activity/executor.py:128-260)

**Реализация:**
```python
def get_chain_configs() -> Dict[str, Dict]:
    """Get chain configurations from database."""
    try:
        from database.db_manager import DatabaseManager
        db = DatabaseManager()
        chain_configs = db.get_all_chain_configs()
        
        # Transform to expected format
        configs = {}
        for chain, config in chain_configs.items():
            configs[chain] = {
                'chain_id': config.get('chain_id'),
                'name': chain.capitalize(),
                'native_token': config.get('native_token', 'ETH'),
                'block_time': float(config.get('block_time', 2.0)),
                'is_poa': config.get('is_poa', False)
            }
        
        # Fallback to defaults if empty
        if not configs:
            return { /* hardcoded fallback */ }
        
        return configs
    except Exception as e:
        logger.warning(f"Failed to load chain configs from DB, using fallback: {e}")
        return { /* hardcoded fallback */ }
```

**Статус:** ✅ Читается из БД с fallback

---

### infrastructure/15: `SERVER_IPS` читаются из БД

**Файл:** [`infrastructure/ip_guard.py`](infrastructure/ip_guard.py:34-64)

**Реализация:**
```python
def get_server_ips() -> Dict[str, str]:
    """Get server IPs from database system_config table."""
    try:
        from database.db_manager import DatabaseManager
        db = DatabaseManager()
        server_ips_list = db.get_system_config('server_ips', default='[]')
        
        # Convert list to dict with placeholder names
        server_names = ['master_node_nl', 'worker_1_nl', 'worker_2_is', 'worker_3_is']
        return {ip: server_names[i] if i < len(server_names) else f'server_{i}' 
                for i, ip in enumerate(server_ips_list)}
    except Exception as e:
        logger.warning(f"Failed to load server IPs from DB, using fallback: {e}")
        # Fallback to hardcoded values
        return {
            '82.40.60.131': 'master_node_nl',
            '82.40.60.132': 'worker_1_nl',
            '82.22.53.183': 'worker_2_is',
            '82.22.53.184': 'worker_3_is',
        }
```

**Статус:** ✅ Читается из БД с fallback

---

### infrastructure/18: `network_mode` и `safety_gates` реализованы

**Файлы:**
- [`infrastructure/network_mode.py`](infrastructure/network_mode.py)
- [`infrastructure/simulator.py`](infrastructure/simulator.py)

**Статус:** ✅ Реализованы (уже закрыт в PROGRESS.md)

---

## 📋 План действий

### Приоритет 1 (Критично для запуска Фазы 1)

1. **Реализовать `/execute_transaction`** (worker/1)
   - Интегрировать `TransactionExecutor` в Worker API
   - Удалить mock response
   - Добавить обработку ошибок

2. **Исправить `execute_withdrawal_tx`** (worker/2)
   - Получать RPC URL из БД по chain_id
   - Использовать `wallet_withdrawal_network` для определения сети вывода
   - Убрать захардкоженный `RPC_URL_BASE`

3. **Перенести WETH адреса в БД** (activity/19)
   - Создать таблицу `chain_tokens`
   - Заполнить данными для всех сетей
   - Обновить `SwapBuilder._get_weth_address()`

### Приоритет 2 (Улучшения)

4. Добавить миграцию для `chain_tokens`
5. Обновить документацию по конфигурации сетей
6. Добавить тесты для новых функций

---

## 🎯 Критерии готовности к запуску Фазы 1

- [x] Таблица `wallet_transactions` существует
- [x] `CHAIN_CONFIGS` читаются из БД
- [ ] WETH адреса читаются из БД
- [ ] `/execute_transaction` выполняет реальные транзакции
- [ ] `execute_withdrawal_tx` поддерживает разные сети
- [x] `SERVER_IPS` читаются из БД
- [x] `network_mode` и `safety_gates` реализованы

**Прогресс:** 4/7 (57%)

---

**Примечание:** После исправления всех блокеров система будет готова к запуску Фазы 1 (Tier A тестнет).
