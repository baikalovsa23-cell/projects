# План: RPC Failover Implementation

## Проблема
Нет failover RPC — если primary упадёт, система встанет.

## Текущее состояние

### База данных
- Таблица `chain_rpc_endpoints` имеет колонки: `url`, `priority`, `is_active`
- **НЕТ** колонки `low_priority_rpc` для fallback
- **НЕТ** публичных fallback RPC URL

### Код
- `db_manager.py` имеет `get_chain_rpc_url(chain)` — возвращает только primary URL
- **НЕТ** метода `get_chain_rpc_with_fallback()`
- **НЕТ** логики переключения на fallback при ошибке

## Решение

### ШАГ 1: Миграция БД — добавить колонку low_priority_rpc

```sql
-- migration: 041_add_low_priority_rpc.sql
ALTER TABLE chain_rpc_endpoints
ADD COLUMN IF NOT EXISTS low_priority_rpc TEXT;

COMMENT ON COLUMN chain_rpc_endpoints.low_priority_rpc 
IS 'Fallback RPC URL (public, free) for failover when primary fails';
```

### ШАГ 2: Обновить данные — добавить публичные fallback RPC

| Chain | Primary URL | Fallback URL (low_priority_rpc) |
|-------|-------------|--------------------------------|
| arbitrum | https://arb1.arbitrum.io/rpc | https://arbitrum.public-rpc.com |
| base | https://mainnet.base.org | https://base-rpc.publicnode.com |
| optimism | https://mainnet.optimism.io | https://optimism.publicnode.com |
| zksync | https://mainnet.era.zksync.io | https://mainnet.era.zksync.io |
| linea | https://rpc.linea.build | https://linea.public-rpc.com |
| scroll | https://rpc.scroll.io | https://scroll.public-rpc.com |
| unichain | https://mainnet.unichain.org | https://mainnet.unichain.org |
| mantle | https://rpc.mantle.xyz | https://rpc.mantle.xyz |
| manta | https://pacific-rpc.manta.network/http | https://pacific-rpc.manta.network/http |
| arbitrum_nova | https://nova.arbitrum.io/rpc | https://nova.arbitrum.io/rpc |
| morph | https://rpc-quicknode.morphl2.io | https://rpc-quicknode.morphl2.io |

### ШАГ 3: Добавить метод get_chain_rpc_with_fallback() в db_manager.py

```python
def get_chain_rpc_with_fallback(self, chain: str) -> Dict[str, Optional[str]]:
    """
    Get RPC URLs for a chain with fallback support.
    
    Returns:
        Dict with 'primary' and 'fallback' keys
        - 'primary': Primary RPC URL (priority 1)
        - 'fallback': Low priority RPC URL for failover
    """
    query = """
        SELECT url, low_priority_rpc 
        FROM chain_rpc_endpoints 
        WHERE chain = %s AND is_active = TRUE 
        ORDER BY priority ASC 
        LIMIT 1
    """
    result = self.execute_query(query, (chain.lower(),), fetch='one')
    
    if not result:
        return {'primary': None, 'fallback': None}
    
    return {
        'primary': result.get('url'),
        'fallback': result.get('low_priority_rpc')
    }
```

### ШАГ 4: Обновить chain_discovery.py и activity/executor.py

Использовать `get_chain_rpc_with_fallback()` вместо `get_chain_rpc_url()`:

```python
# В chain_discovery.py и executor.py
rpc_urls = db.get_chain_rpc_with_fallback(chain)
primary_url = rpc_urls['primary']
fallback_url = rpc_urls['fallback']

# Попробовать primary
try:
    result = web3.eth.get_block('latest')
except Exception as e:
    logger.warning(f"Primary RPC failed for {chain}: {e}")
    if fallback_url:
        logger.info(f"Switching to fallback RPC for {chain}")
        web3 = Web3(Web3.HTTPProvider(fallback_url))
        result = web3.eth.get_block('latest')
    else:
        raise
```

## Файлы для изменения

1. **database/migrations/041_add_low_priority_rpc.sql** — НОВАЯ миграция
2. **database/seed_chain_rpc_endpoints.sql** — обновить с fallback URL
3. **database/db_manager.py** — добавить `get_chain_rpc_with_fallback()`
4. **infrastructure/chain_discovery.py** — использовать fallback
5. **activity/executor.py** — использовать fallback

## Приоритет

**ВЫСОКИЙ** — без failover система уязвима к падению primary RPC.

## Оценка

- Миграция БД: 5 минут
- Обновление seed данных: 10 минут
- Добавление метода в db_manager: 5 минут
- Обновление chain_discovery.py: 15 минут
- Обновление executor.py: 15 минут

**Итого: ~50 минут**