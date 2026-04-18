# Аудит проекта и тестов airdrop_v4
## Полный анализ несоответствий между реализацией модулей и тестами

**Дата:** 2026-03-29  
**Статус тестов:** 63 failed (75.9% success rate)  
**Цель:** Выявить причины падающих тестов без внесения изменений в код

---

## Исполнительное резюме

В ходе аудита проанализированы 4 проблемных модуля и их тесты:
1. **TransactionExecutor** (9 failed tests)
2. **PersonaGenerator** (3 failed tests)
3. **ActivityScheduler** (2 failed tests)
4. **DirectFundingEngineV3** (1 failed test)

Обнаружены критические несоответствия:
- Неправильное мокирование в тестах
- Несоответствие схемы БД ожиданиям кода
- Отсутствие моков для внутренних методов
- Использование неправильных названий методов

---

## 1. TransactionExecutor (9 failed tests)

### 1.1. Реальная сигнатура метода

```python
def execute_transaction(
    self,
    wallet_id: int,
    chain: str,
    to_address: str,
    value_wei: int = 0,
    data: str = '0x',
    gas_preference: str = 'normal',
    max_wait_seconds: int = 300
) -> Dict[str, Any]:
```

### 1.2. Конструктор `__init__`

```python
def __init__(self, fernet_key: Optional[str] = None):
    self.fernet = Fernet(fernet_key)
    self.db = DatabaseManager()
    self.proxy_manager = ProxyManager(db=self.db)
    self.network_mode = NetworkModeManager()
    self.simulator = TransactionSimulator(self.db, self.network_mode)
    self._web3_instances: Dict[Tuple[str, int], Web3] = {}
    self._nonce_locks: Dict[int, threading.Lock] = {}
```

### 1.3. Проблемы в тестах

#### Проблема 1: Неправильные названия методов в моках

**Тесты используют:**
```python
with patch.object(executor, '_get_wallet_private_key', return_value='0x...'):
    with patch.object(executor, '_get_w3_instance', return_value=mock_web3):
```

**Реальные методы:**
- `_get_wallet_account(wallet_id: int)` (строка 512) - а не `_get_wallet_private_key`
- `_get_web3(chain: str, wallet_id: Optional[int] = None)` (строка 322) - а не `_get_w3_instance`

#### Проблема 2: Не мокированы все используемые атрибуты

**Метод `execute_transaction` использует:**
- `self.proxy_manager.get_proxy_for_wallet(wallet_id)` - НЕ МОКИРОВАН
- `self._get_web3(chain, wallet_id)` - использует `self._web3_instances` - НЕ ИНИЦИАЛИЗИРОВАН
- `self._get_wallet_account(wallet_id)` - использует `self.fernet` - НЕ ИНИЦИАЛИЗИРОВАН
- `self._nonce_locks[wallet_id]` - НЕ ИНИЦИАЛИЗИРОВАН

#### Проблема 3: Не мокированы Web3 методы

**Не мокированы:**
- `w3.eth.get_balance(from_address)` (строка 777)
- `w3.eth.get_transaction_count(from_address, 'pending')` (строка 790)
- `w3.eth.estimate_gas(transaction)` (строка 568)
- `w3.eth.max_priority_fee` (строка 610)
- `w3.eth.get_block('latest')` (строка 605)
- `w3.eth.send_raw_transaction(signed_tx.rawTransaction)` (строка 837)
- `w3.eth.get_transaction_receipt(tx_hash)` (строка 872)

#### Проблема 4: Не мокированы зависимости

**Не мокированы:**
- `identity_manager.get_config(wallet_id)` (строка 366)
- `pre_flight_check(wallet_id, proxy_url, ...)` (строка 377)
- `get_curl_session(wallet_id, proxy_url)` (строка 394)
- `self.db.get_chain_rpc_with_fallback(chain)` (строка 350)
- `self.db.execute_query` для internal wallet check (строка 764)

### 1.4. Рекомендации по исправлению

**Решение А (рекомендуется): Не патчить `__init__`, мокировать зависимости**

```python
def test_execute_swap_transaction(self, mock_db, mock_web3):
    with patch('activity.executor.DatabaseManager', return_value=mock_db):
        with patch('activity.executor.ProxyManager') as mock_proxy_mgr:
            with patch('activity.executor.NetworkModeManager') as mock_network:
                with patch('activity.executor.TransactionSimulator') as mock_sim:
                    with patch('activity.executor.BridgeManager') as mock_bridge:
                        with patch.dict(os.environ, {'FERNET_KEY': 'test_key_32_characters_long_12345', 'NETWORK_MODE': 'DRY_RUN'}):
                            from activity.executor import TransactionExecutor
                            from infrastructure.simulator import SimulationResult
                            
                            # Настроить моки зависимостей
                            mock_proxy_mgr.return_value.get_proxy_for_wallet.return_value = {
                                'protocol': 'http',
                                'ip_address': '1.2.3.4',
                                'port': 8080,
                                'username': 'user',
                                'password': 'pass'
                            }
                            
                            mock_network.return_value.is_dry_run.return_value = True
                            
                            mock_sim.return_value.simulate_transaction.return_value = SimulationResult(
                                would_succeed=True,
                                estimated_gas=21000,
                                error_message=None
                            )
                            
                            # Создать executor БЕЗ патчинга __init__
                            executor = TransactionExecutor(fernet_key='test_key_32_characters_long_12345')
                            
                            # Мокировать Web3 методы
                            mock_web3.eth.get_balance.return_value = Web3.to_wei(1, 'ether')
                            mock_web3.eth.get_transaction_count.return_value = 0
                            mock_web3.eth.estimate_gas.return_value = 21000
                            mock_web3.eth.max_priority_fee.return_value = Web3.to_wei(1, 'gwei')
                            mock_web3.eth.get_block.return_value = {'baseFeePerGas': Web3.to_wei(30, 'gwei')}
                            mock_web3.eth.send_raw_transaction.return_value = b'0' * 32
                            mock_web3.eth.get_transaction_receipt.return_value = {
                                'status': 1,
                                'gasUsed': 21000,
                                'blockNumber': 12345
                            }
                            
                            # Вызвать метод
                            result = executor.execute_transaction(
                                wallet_id=1,
                                chain='arbitrum',
                                to_address='0x1234567890123456789012345678901234567890',
                                value_wei=10000000000000000
                            )
                            
                            assert result is not None
```

**Решение Б (если нужен патчинг): Мокировать ВСЕ атрибуты**

```python
with patch.object(TransactionExecutor, '__init__', lambda self, fernet_key=None: None):
    executor = TransactionExecutor()
    executor.db = mock_db
    executor.proxy_manager = MagicMock()
    executor.proxy_manager.get_proxy_for_wallet.return_value = {...}
    executor.network_mode = MagicMock()
    executor.simulator = MagicMock()
    executor.bridge_manager = MagicMock()
    executor.fernet = Fernet(b'test_key_32_characters_long_12345')
    executor._nonce_locks = {}
    executor._web3_instances = {}
    
    # Мокировать внутренние методы
    with patch.object(executor, '_get_wallet_account', return_value=(account, address)):
        with patch.object(executor, '_get_web3', return_value=mock_web3):
            result = executor.execute_transaction(...)
```

---

## 2. PersonaGenerator (3 failed tests)

### 2.1. Реальная сигнатура метода

```python
def generate_persona(self, wallet_id: int) -> Dict:
```

### 2.2. Последовательность DB запросов

```python
# 1. _get_archetype_distribution_balanced()
query = "SELECT persona_type, COUNT(*) as count FROM wallet_personas GROUP BY persona_type"
result = self.db.execute_query(query, fetch='all')  # Возвращает список словарей

# 2. generate_persona()
wallet = self.db.execute_query(
    "SELECT w.id, w.tier, pp.country_code, pp.timezone, pp.utc_offset "
    "FROM wallets w JOIN proxy_pool pp ON w.proxy_id = pp.id "
    "WHERE w.id = %s",
    (wallet_id,), fetch='one'
)  # Возвращает словарь
```

### 2.3. Проблемы в тестах

#### Проблема 1: Не мокирован `random.choices`

**Метод `_get_archetype_distribution_balanced` использует:**
```python
return random.choices(ARCHETYPES, weights=weights, k=1)[0]
```

**Тесты не мокируют `random.choices` для предсказуемости выбора архетипа.**

#### Проблема 2: Не мокирован `random.sample`

**Метод `generate_persona` использует:**
```python
hours = random.sample(available_hours, k)
```

**Тесты не мокируют `random.sample` для предсказуемости выбора часов.**

#### Проблема 3: Не мокирован `np.random.normal`

**Метод `generate_persona` использует:**
```python
slippage = round(np.random.normal(0.465, 0.07), 2)
```

**Тесты не мокируют `np.random.normal` для предсказуемости Gaussian распределений.**

#### Проблема 4: Не мокирован `random.choices` для gas preference

**Метод `generate_persona` использует:**
```python
gas_choice = random.choices(['slow', 'normal', 'fast'], 
                           weights=[gas_weights['slow'], gas_weights['normal'], gas_weights['fast']])[0]
```

**Тесты не мокируют этот вызов для предсказуемости.**

### 2.4. Рекомендации по исправлению

```python
def test_generate_persona_returns_all_fields(self, mock_db):
    from wallets.personas import PersonaGenerator
    
    # Mock DB: first call returns archetype distribution, second returns wallet info
    mock_db.execute_query.side_effect = [
        # _get_archetype_distribution_balanced query
        [{'persona_type': 'ActiveTrader', 'count': 5}],
        # generate_persona wallet query
        {
            'id': 1,
            'tier': 'A',
            'country_code': 'NL',
            'timezone': 'Europe/Amsterdam',
            'utc_offset': 1
        }
    ]
    
    generator = PersonaGenerator(db_manager=mock_db)
    
    # Mock random for predictability
    with patch('wallets.personas.random.choices', return_value=['ActiveTrader']):
        with patch('wallets.personas.random.sample', return_value=[8, 9, 10, 14, 15]):
            with patch('wallets.personas.np.random.normal', return_value=0.465):
                persona = generator.generate_persona(wallet_id=1)
                
                # Check all required fields
                required_fields = [
                    'wallet_id', 'persona_type', 'preferred_hours',
                    'tx_per_week_mean', 'tx_per_week_stddev', 'skip_week_probability',
                    'tx_weight_swap', 'tx_weight_bridge', 'tx_weight_liquidity',
                    'tx_weight_stake', 'tx_weight_nft', 'slippage_tolerance',
                    'gas_preference'
                ]
                
                for field in required_fields:
                    assert field in persona, f"Missing field: {field}"
```

---

## 3. ActivityScheduler (2 failed tests)

### 3.1. Реальная сигнатура метода

```python
def generate_weekly_schedule(
    self,
    wallet_id: int,
    week_start: datetime
) -> Optional[int]:
```

### 3.2. Последовательность вызовов

```python
# 1. _get_wallet_persona(wallet_id)
persona = self._get_wallet_persona(wallet_id)

# 2. _check_bridge_emulation_delay(persona)
if not self._check_bridge_emulation_delay(persona):
    return None

# 3. _should_skip_week(persona)
if self._should_skip_week(persona):
    # INSERT INTO weekly_plans
    return result['id']

# 4. gas_controller.should_execute_transaction()
should_exec, gas_reason = self.gas_controller.should_execute_transaction(...)

# 5. _calculate_weekly_tx_count(persona)
tx_count = self._calculate_weekly_tx_count(persona)

# 6. _generate_tx_timestamps()
timestamps = self._generate_tx_timestamps(persona, week_start, tx_count)

# 7. _apply_bridge_emulation_to_first_tx(timestamps, persona)
timestamps = self._apply_bridge_emulation_to_first_tx(timestamps, persona)

# 8. _remove_sync_conflicts(wallet_id, timestamps)
timestamps = self._remove_sync_conflicts(wallet_id, timestamps)

# 9. _select_protocol_actions(persona, tx_count)
protocol_actions = self._select_protocol_actions(persona, tx_count)

# 10. INSERT INTO weekly_plans
# 11. INSERT INTO scheduled_transactions
```

### 3.3. Проблемы в тестах

#### Проблема 1: Не мокированы внутренние методы

**Тесты не мокируют:**
- `_get_wallet_persona(wallet_id)`
- `_check_bridge_emulation_delay(persona)`
- `_should_skip_week(persona)`
- `_calculate_weekly_tx_count(persona)`
- `_generate_tx_timestamps(persona, week_start, count)`
- `_apply_bridge_emulation_to_first_tx(timestamps, persona)`
- `_remove_sync_conflicts(wallet_id, timestamps)`
- `_select_protocol_actions(persona, count)`

#### Проблема 2: Не мокированы зависимости

**Тесты не мокируют:**
- `self.gas_controller` (AdaptiveGasController)
- `self.bridge_manager` (BridgeManager)

#### Проблема 3: Не мокированы DB запросы

**Тесты не мокируют:**
- INSERT INTO weekly_plans
- INSERT INTO scheduled_transactions
- SELECT FROM wallet_personas
- SELECT FROM scheduled_transactions (для проверки конфликтов)

#### Проблема 4: Не мокированы random и np.random

**Тесты не мокируют:**
- `random.randint(0, 6)` (строка 272)
- `random.choice(preferred_hours)` (строка 283)
- `random.randint(0, 59)` (строка 286)
- `random.randint(0, 59)` (строка 289)
- `np.random.normal(mean, stddev)` (строка 196)
- `np.random.normal(17.5, 4)` (строка 417)

### 3.4. Рекомендации по исправлению

```python
def test_generate_weekly_schedule(self, mock_db):
    from activity.scheduler import ActivityScheduler
    from datetime import datetime, timezone
    
    scheduler = ActivityScheduler()
    scheduler.db = mock_db
    
    # Mock зависимости
    scheduler.gas_controller = MagicMock()
    scheduler.gas_controller.should_execute_transaction.return_value = (True, "Gas OK")
    scheduler.bridge_manager = MagicMock()
    
    # Mock внутренние методы
    with patch.object(scheduler, '_get_wallet_persona', return_value={
        'wallet_id': 1,
        'persona_type': 'ActiveTrader',
        'preferred_hours': [8, 9, 10, 14, 15, 16, 18, 19, 20, 21],
        'tx_per_week_mean': 4.5,
        'tx_per_week_stddev': 1.2,
        'skip_week_probability': 0.05,
        'tx_weight_swap': 0.40,
        'tx_weight_bridge': 0.25,
        'tx_weight_liquidity': 0.20,
        'tx_weight_stake': 0.10,
        'tx_weight_nft': 0.05,
        'slippage_tolerance': 0.45,
        'gas_preference': 'normal',
        'last_funded_at': None
    }):
        with patch.object(scheduler, '_check_bridge_emulation_delay', return_value=True):
            with patch.object(scheduler, '_should_skip_week', return_value=False):
                with patch.object(scheduler, '_calculate_weekly_tx_count', return_value=5):
                    with patch.object(scheduler, '_generate_tx_timestamps', return_value=[
                        datetime(2026, 3, 3, 10, 0, tzinfo=timezone.utc),
                        datetime(2026, 3, 3, 14, 0, tzinfo=timezone.utc),
                        datetime(2026, 3, 4, 10, 0, tzinfo=timezone.utc),
                        datetime(2026, 3, 4, 14, 0, tzinfo=timezone.utc),
                        datetime(2026, 3, 5, 10, 0, tzinfo=timezone.utc),
                    ]):
                        with patch.object(scheduler, '_apply_bridge_emulation_to_first_tx', return_value=[
                            datetime(2026, 3, 3, 10, 0, tzinfo=timezone.utc),
                            datetime(2026, 3, 3, 14, 0, tzinfo=timezone.utc),
                            datetime(2026, 3, 4, 10, 0, tzinfo=timezone.utc),
                            datetime(2026, 3, 4, 14, 0, tzinfo=timezone.utc),
                            datetime(2026, 3, 5, 10, 0, tzinfo=timezone.utc),
                        ]):
                            with patch.object(scheduler, '_remove_sync_conflicts', return_value=[
                                datetime(2026, 3, 3, 10, 0, tzinfo=timezone.utc),
                                datetime(2026, 3, 3, 14, 0, tzinfo=timezone.utc),
                                datetime(2026, 3, 4, 10, 0, tzinfo=timezone.utc),
                                datetime(2026, 3, 4, 14, 0, tzinfo=timezone.utc),
                                datetime(2026, 3, 5, 10, 0, tzinfo=timezone.utc),
                            ]):
                                with patch.object(scheduler, '_select_protocol_actions', return_value=[1, 2, 3, 4, 5]):
                                    # Mock DB INSERT
                                    mock_db.execute_query.side_effect = [
                                        {'id': 123},  # INSERT INTO weekly_plans
                                        {'tx_type': 'SWAP', 'action_layer': 'web3py'},  # SELECT FROM protocol_actions
                                        None,  # INSERT INTO scheduled_transactions (x5)
                                        None,
                                        None,
                                        None,
                                        None,
                                    ]
                                    
                                    week_start = datetime(2026, 3, 3, 0, 0, tzinfo=timezone.utc)
                                    result = scheduler.generate_weekly_schedule(wallet_id=1, week_start=week_start)
                                    
                                    assert result == 123
```

---

## 4. DirectFundingEngineV3 (1 failed test)

### 4.1. Реальная сигнатура метода

```python
async def prepare_funding_task(
    self,
    wallet_id: int,
    target_network: str
) -> TaskResult:
```

### 4.2. Внутренние вызовы

```python
# Вызывает async метод
is_ok, extra_delay, gas_info = await self.check_gas_viability(target_network)

if not is_ok:
    return TaskResult(status=TaskStatus.SLEEP, ...)

return TaskResult(status=TaskStatus.READY, ...)
```

### 4.3. Проблемы в тестах

#### Проблема 1: Патчинг `__init__` блокирует инициализацию

**Тесты используют:**
```python
with patch.object(DirectFundingEngineV3, '__init__', lambda self, fernet_key=None: None):
    engine = DirectFundingEngineV3()
    engine.db = mock_db
    engine.cex = mock_cex_manager
    engine.gas_manager = MagicMock()
```

**Проблема:** Патчинг `__init__` полностью блокирует инициализацию, не создаются все атрибуты.

#### Проблема 2: Не мокированы все атрибуты

**Не мокированы:**
- `self.fernet` (Fernet)
- `self.network_mode` (NetworkModeManager)
- `self.simulator` (TransactionSimulator)

#### Проблема 3: Не мокирован `_network_to_chain_id` метод

**Метод `check_gas_viability` использует:**
```python
chain_id = self._network_to_chain_id(network)
```

**Тесты не мокируют этот метод.**

#### Проблема 4: Не мокирован `simulate_wallet_funding` метод

**Метод `execute_direct_cex_withdrawal` использует:**
```python
simulation = await self.simulator.simulate_funding(
    wallet_address=wallet_address,
    amount_usd=amount_usd
)
```

**Тесты не мокируют этот метод.**

#### Проблема 5: Не мокированы CEX методы

**Не мокированы:**
- `self.cex.verify_whitelist(subaccount_id, address)`
- `self.cex.get_balance(subaccount_id)`
- `self.cex.withdraw(subaccount_id, address, amount, network)`

### 4.4. Рекомендации по исправлению

```python
@pytest.mark.asyncio
async def test_prepare_funding_task(self, mock_db, mock_cex_manager):
    from funding.engine_v3 import DirectFundingEngineV3, TaskResult, TaskStatus
    
    with patch('funding.engine_v3.DatabaseManager', return_value=mock_db):
        with patch('funding.engine_v3.CEXManager', return_value=mock_cex_manager):
            with patch.dict('os.environ', {'FERNET_KEY': 'test_key_32_characters_long_12345', 'NETWORK_MODE': 'DRY_RUN'}):
                # Создать engine БЕЗ патчинга __init__
                engine = DirectFundingEngineV3(fernet_key='test_key_32_characters_long_12345')
                
                # Mock gas_manager как AsyncMock
                from unittest.mock import AsyncMock
                engine.gas_manager.check_gas_viability = AsyncMock(return_value=MagicMock(
                    status=MagicMock(value='ok'),
                    current_gwei=30.0,
                    threshold_gwei=100.0,
                    extra_delay_minutes=0,
                    network_type=MagicMock(value='l2'),
                    ma_24h_available=True
                ))
                
                result = await engine.prepare_funding_task(
                    wallet_id=1,
                    target_network='arbitrum'
                )
                
                assert result.status == TaskStatus.READY
                assert result.gas_result is not None
```

---

## 5. Критические несоответствия схемы БД

### 5.1. Таблица `scheduled_transactions`

**Схема БД (строки 472-488):**
```sql
CREATE TABLE scheduled_transactions (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    protocol_action_id INTEGER NOT NULL REFERENCES protocol_actions(id),
    tx_type tx_type NOT NULL,
    layer action_layer NOT NULL,
    scheduled_at TIMESTAMPTZ NOT NULL,
    amount_usdt DECIMAL(10, 4),
    params JSONB,
    status tx_status DEFAULT 'pending',
    tx_hash VARCHAR(66),
    gas_used BIGINT,
    gas_price_gwei DECIMAL(10, 2),
    error_message TEXT,
    executed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Код ActivityScheduler (строки 894-909) пытается вставить:**
```python
tx_query = """
    INSERT INTO scheduled_transactions (
        wallet_id,
        protocol_action_id,
        tx_type,
        layer,
        scheduled_at,
        status,
        from_network,        # ❌ НЕТ В СХЕМЕ!
        to_network,          # ❌ НЕТ В СХЕМЕ!
        depends_on_tx_id,    # ❌ НЕТ В СХЕМЕ!
        bridge_required,     # ❌ НЕТ В СХЕМЕ!
        bridge_provider,     # ❌ НЕТ В СХЕМЕ!
        bridge_status        # ❌ НЕТ В СХЕМЕ!
    )
    VALUES (%s, %s, %s, %s, %s, 'pending', %s, %s, %s, %s, %s, %s)
    RETURNING id
"""
```

**Проблема:** Код пытается вставить данные в поля, которых нет в схеме БД.

**Решение:** Добавить недостающие поля в схему БД:

```sql
ALTER TABLE scheduled_transactions
ADD COLUMN from_network VARCHAR(50),
ADD COLUMN to_network VARCHAR(50),
ADD COLUMN depends_on_tx_id INTEGER REFERENCES scheduled_transactions(id),
ADD COLUMN bridge_required BOOLEAN DEFAULT FALSE,
ADD COLUMN bridge_provider VARCHAR(50),
ADD COLUMN bridge_status VARCHAR(20) DEFAULT 'pending';
```

### 5.2. Таблица `funding_withdrawals`

**Схема БД (строки 181-197):**
```sql
CREATE TABLE funding_withdrawals (
    id SERIAL PRIMARY KEY,
    funding_chain_id INTEGER NOT NULL REFERENCES funding_chains(id),
    wallet_id INTEGER,
    cex_subaccount_id INTEGER NOT NULL REFERENCES cex_subaccounts(id),
    withdrawal_network VARCHAR(50) NOT NULL,
    amount_usdt DECIMAL(10, 4) NOT NULL,
    withdrawal_address VARCHAR(42) NOT NULL,
    cex_txid VARCHAR(255),
    blockchain_txhash VARCHAR(66),
    status funding_withdrawal_status DEFAULT 'planned',
    delay_minutes INTEGER,
    scheduled_at TIMESTAMPTZ,
    requested_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Код DirectFundingEngineV3 (строки 407-413) пытается вставить:**
```python
withdrawal_query = """
    INSERT INTO funding_withdrawals (
        funding_chain_id, wallet_id, cex_subaccount_id,
        withdrawal_network, amount_usdt, withdrawal_address,
        direct_cex_withdrawal,  # ❌ НЕТ В СХЕМЕ!
        status
    ) VALUES (%s, %s, %s, %s, %s, %s, TRUE, 'planned')
    RETURNING id
"""
```

**Проблема:** Поле `direct_cex_withdrawal` отсутствует в схеме БД.

**Решение:** Добавить поле в схему БД:

```sql
ALTER TABLE funding_withdrawals
ADD COLUMN direct_cex_withdrawal BOOLEAN DEFAULT FALSE;
```

### 5.3. Таблица `funding_withdrawals` - недостающие поля

**Код DirectFundingEngineV3 (строки 562-570) пытается обновить:**
```python
self.db.execute_query(
    """
        UPDATE funding_withdrawals
        SET cex_withdrawal_scheduled_at = %s,    # ❌ НЕТ В СХЕМЕ!
            interleave_round = %s,                # ❌ НЕТ В СХЕМЕ!
            interleave_position = %s               # ❌ НЕТ В СХЕМЕ!
        WHERE id = %s
    """,
    (scheduled_time, withdrawal['interleave_round'], withdrawal['interleave_position'], withdrawal['id'])
)
```

**Проблема:** Поля отсутствуют в схеме БД.

**Решение:** Добавить поля в схему БД:

```sql
ALTER TABLE funding_withdrawals
ADD COLUMN cex_withdrawal_scheduled_at TIMESTAMPTZ,
ADD COLUMN interleave_round INTEGER,
ADD COLUMN interleave_position INTEGER;
```

---

## 6. Приоритизация исправлений

### Фаза 1: Критичные исправления (9+2 тестов)

1. **TransactionExecutor** - исправить патчинг `__init__` (9 тестов)
   - Не патчить `__init__`, мокировать зависимости
   - Исправить названия методов: `_get_wallet_private_key` → `_get_wallet_account`, `_get_w3_instance` → `_get_web3`
   - Мокировать все Web3 методы

2. **ActivityScheduler** - мокировать внутренние методы (2 теста)
   - Мокировать все 8+ внутренних методов
   - Мокировать зависимости `gas_controller` и `bridge_manager`
   - Мокировать DB INSERT запросы

### Фаза 2: Средние исправления (3+1 тестов)

3. **PersonaGenerator** - добавить моки для random (3 теста)
   - Мокировать `random.choices` для выбора архетипа
   - Мокировать `random.sample` для выбора часов
   - Мокировать `np.random.normal` для Gaussian распределений

4. **DirectFundingEngineV3** - заменить MagicMock на AsyncMock (1 тест)
   - Использовать `AsyncMock` для async методов
   - Не патчить `__init__`
   - Мокировать `_network_to_chain_id` метод

### Фаза 3: Исправления схемы БД (критично для production)

5. **scheduled_transactions** - добавить недостающие поля
   - `from_network`
   - `to_network`
   - `depends_on_tx_id`
   - `bridge_required`
   - `bridge_provider`
   - `bridge_status`

6. **funding_withdrawals** - добавить недостающие поля
   - `direct_cex_withdrawal`
   - `cex_withdrawal_scheduled_at`
   - `interleave_round`
   - `interleave_position`

### Фаза 4: Остальные ~48 тестов

7. Исправить тесты для других модулей (CEX, Bridge, OpenClaw, и т.д.)
8. Добавить интеграционные тесты с реальной БД

---

## 7. Оценка времени

- **Фаза 1:** 2-3 часа (критичные исправления)
- **Фаза 2:** 1-2 часа (средние исправления)
- **Фаза 3:** 1-2 часа (исправления схемы БД)
- **Фаза 4:** 5-8 часов (остальные тесты)

**Итого:** 9-15 часов для достижения 320+ passed тестов (85%+ success rate)

---

## 8. Заключение

В ходе аудита обнаружены следующие основные проблемы:

1. **Неправильное мокирование в тестах** - использование патчинга `__init__` блокирует инициализацию объектов
2. **Несоответствие названий методов** - тесты используют неправильные названия методов
3. **Отсутствие моков для внутренних методов** - тесты не мокируют все вызываемые методы
4. **Отсутствие моков для зависимостей** - тесты не мокируют `gas_controller`, `bridge_manager`, и т.д.
5. **Критические несоответствия схемы БД** - код пытается использовать поля, которых нет в схеме

**Рекомендация:** Начать с Фазы 1 (критичные исправления), затем перейти к Фазе 3 (исправления схемы БД), так как это блокирует работу в production.

---

**Отчёт составлен:** 2026-03-29  
**Аудитор:** Code Mode (AI Assistant)  
**Статус:** Завершён
