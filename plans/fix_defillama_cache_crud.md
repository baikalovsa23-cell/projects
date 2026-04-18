# План исправления CRUD методов для defillama_bridges_cache

## Проблема

В `database/db_manager.py` (строки 1030-1043) есть методы для работы с таблицей `defillama_bridges_cache`, но они используют **НЕВЕРНУЮ структуру колонок**:

### Текущие (неправильные) методы:
```python
def get_defillama_bridge_cache(self, provider: str) -> Optional[Dict]:
    """Get cached DeFiLlama bridge data."""
    query = "SELECT * FROM defillama_bridges_cache WHERE provider = %s"
    return self.execute_query(query, (provider,), fetch='one')
    
def update_defillama_bridge_cache(self, provider: str, data: Dict, expires_at: datetime):
    """Update DeFiLlama bridge cache."""
    query = """
        INSERT INTO defillama_bridges_cache (provider, data, expires_at)
        VALUES (%s, %s, %s)
        ON CONFLICT (provider) DO UPDATE
        SET data = EXCLUDED.data, expires_at = EXCLUDED.expires_at, updated_at = NOW()
    """
    self.execute_query(query, (provider, extras.Json(data), expires_at))
```

### Реальная структура таблицы (из миграции 031):
```sql
CREATE TABLE IF NOT EXISTS defillama_bridges_cache (
    id SERIAL PRIMARY KEY,
    bridge_name VARCHAR(100) NOT NULL UNIQUE,
    display_name VARCHAR(100),
    chains JSONB,
    tvl_usd BIGINT,
    volume_30d_usd BIGINT,
    rank INTEGER,
    hacks JSONB,
    fetched_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL
);
```

**Колонки `provider`, `data`, `updated_at` НЕ СУЩЕСТВУЮТ!**

## Использование в проекте

### 1. `activity/bridge_manager.py` (строки 686-744)
Использует **ПРАВИЛЬНУЮ** структуру через прямые SQL запросы:

```python
# _get_cached_provider() - строка 686
query = """
    SELECT tvl_usd, rank, hacks, chains
    FROM defillama_bridges_cache
    WHERE bridge_name = %s AND expires_at > NOW()
    LIMIT 1
"""

# _save_cached_provider() - строка 719
query = """
    INSERT INTO defillama_bridges_cache 
        (bridge_name, tvl_usd, rank, hacks, chains, fetched_at)
    VALUES (%s, %s, %s, %s, %s, NOW())
    ON CONFLICT (bridge_name) 
    DO UPDATE SET 
        tvl_usd = EXCLUDED.tvl_usd,
        rank = EXCLUDED.rank,
        hacks = EXCLUDED.hacks,
        chains = EXCLUDED.chains,
        fetched_at = NOW()
"""
```

### 2. `database/db_manager.py` (строки 1030-1043)
Использует **НЕВЕРНУЮ** структуру (не соответствует схеме!)

## Решение

### Шаг 1: Удалить неправильные методы из db_manager.py
Удалить строки 1030-1043:
- `get_defillama_bridge_cache()`
- `update_defillama_bridge_cache()`

### Шаг 2: Добавить правильные CRUD методы в db_manager.py

```python
# ========================================================================
# DEFILLAMA BRIDGES CACHE QUERIES
# ========================================================================

def get_defillama_bridges_cache(
    self,
    bridge_name: str,
    allow_expired: bool = False
) -> Optional[Dict]:
    """
    Get cached DeFiLlama bridge data by bridge name.
    
    Args:
        bridge_name: Bridge provider name (e.g., 'across', 'stargate')
        allow_expired: If True, return expired cache as fallback
    
    Returns:
        Dict with keys: tvl_usd, rank, hacks, chains, fetched_at, expires_at
        or None if not found
    """
    if allow_expired:
        query = """
            SELECT bridge_name, tvl_usd, rank, hacks, chains, fetched_at, expires_at
            FROM defillama_bridges_cache
            WHERE bridge_name = %s
            LIMIT 1
        """
    else:
        query = """
            SELECT bridge_name, tvl_usd, rank, hacks, chains, fetched_at, expires_at
            FROM defillama_bridges_cache
            WHERE bridge_name = %s AND expires_at > NOW()
            LIMIT 1
        """
    
    result = self.execute_query(query, (bridge_name,), fetch='one')
    
    if result and 'chains' in result:
        # Parse JSONB if needed
        chains = result['chains']
        if isinstance(chains, str):
            import json
            chains = json.loads(chains)
        result['chains'] = chains
    
    if result and 'hacks' in result:
        hacks = result['hacks']
        if isinstance(hacks, str):
            import json
            hacks = json.loads(hacks)
        result['hacks'] = hacks
    
    return result


def set_defillama_bridges_cache(
    self,
    bridge_name: str,
    tvl_usd: int,
    rank: int,
    hacks: List[Dict],
    chains: List[str],
    display_name: Optional[str] = None,
    volume_30d_usd: Optional[int] = None
) -> None:
    """
    Save or update DeFiLlama bridge cache.
    
    The expires_at is automatically set by trigger (fetched_at + 6 hours).
    
    Args:
        bridge_name: Bridge provider name (e.g., 'across', 'stargate')
        tvl_usd: Total Value Locked in USD
        rank: Rank in DeFiLlama bridges list
        hacks: List of hack incidents (can be empty list)
        chains: List of supported chain names
        display_name: Optional display name
        volume_30d_usd: Optional 30-day volume
    """
    import json
    
    query = """
        INSERT INTO defillama_bridges_cache 
            (bridge_name, display_name, chains, tvl_usd, volume_30d_usd, rank, hacks, fetched_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
        ON CONFLICT (bridge_name) 
        DO UPDATE SET 
            display_name = COALESCE(EXCLUDED.display_name, defillama_bridges_cache.display_name),
            tvl_usd = EXCLUDED.tvl_usd,
            volume_30d_usd = COALESCE(EXCLUDED.volume_30d_usd, defillama_bridges_cache.volume_30d_usd),
            rank = EXCLUDED.rank,
            hacks = EXCLUDED.hacks,
            chains = EXCLUDED.chains,
            fetched_at = NOW()
    """
    
    self.execute_query(
        query,
        (
            bridge_name,
            display_name,
            json.dumps(chains),
            tvl_usd,
            volume_30d_usd,
            rank,
            json.dumps(hacks)
        )
    )
    
    logger.debug(
        f"DeFiLlama cache saved | {bridge_name} | "
        f"TVL: ${tvl_usd:,.0f} | Rank: #{rank}"
    )


def clear_expired_defillama_cache(self, days_old: int = 7) -> int:
    """
    Delete expired cache entries older than specified days.
    
    Args:
        days_old: Delete entries expired more than this many days ago
    
    Returns:
        Number of deleted entries
    """
    query = """
        DELETE FROM defillama_bridges_cache
        WHERE expires_at < NOW() - INTERVAL '%s days'
        RETURNING id
    """
    with self.get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(query, (days_old,))
            deleted = cur.rowcount
            logger.info(f"Cleared {deleted} expired DeFiLlama cache entries (older than {days_old} days)")
            return deleted
```

### Шаг 3: Обновить bridge_manager.py

Заменить прямые SQL запросы на методы db_manager:

#### В `_get_cached_provider()` (строка 683):
```python
# БЫЛО:
result = self.db.execute_query(query, (provider_name,), fetch='one')

# СТАНЕТ:
result = self.db.get_defillama_bridges_cache(provider_name, allow_expired=False)
```

#### В `_save_cached_provider()` (строка 716):
```python
# БЫЛО:
self.db.execute_query(query, (provider_name, data.get('tvl', 0), ...))

# СТАНЕТ:
self.db.set_defillama_bridges_cache(
    bridge_name=provider_name,
    tvl_usd=data.get('tvl', 0),
    rank=data.get('rank', 999),
    hacks=[],  # hacks list from API
    chains=data.get('chains', [])
)
```

## Проверка

После внесения изменений:

1. Проверить, что методы в db_manager.py соответствуют схеме таблицы
2. Убедиться, что bridge_manager.py использует новые методы
3. Запустить тесты (если есть)

## Итог

- Удалить 2 неправильных метода из db_manager.py
- Добавить 3 правильных CRUD метода
- Обновить 2 места в bridge_manager.py
- Нет новых файлов
- Хардкод не трогаем