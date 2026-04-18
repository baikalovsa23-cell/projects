# Подключение PostgreSQL через SQLTools в VS Code

## Параметры подключения

| Параметр | Значение |
|----------|----------|
| **Host** | `82.40.60.131` (Master Node, Netherlands) |
| **Port** | `5432` |
| **Database** | `farming_db` |
| **User** | `farming_user` |
| **Password** | `U5e8xXLTX7zm0v5KDu2oVsJuvdW478` |

## SSH-туннель

| Параметр | Значение |
|----------|----------|
| **SSH Host** | `82.40.60.131` |
| **SSH User** | `root` |
| **SSH Password** | `yIFdCq9812%` |
| **SSH Key** | `ssh-ed25519` |

## Требуемые расширения VS Code

1. **SQLTools** (`mtxr.sqltools`) - основной extension
2. **SQLTools PostgreSQL Driver** (`mtxr.sqltools-driver-pg`) - драйвер PostgreSQL
3. **Remote - SSH** (`ms-vscode-remote.remote-ssh`) - для SSH-туннеля (опционально)

## Способы подключения

### Способ 1: Прямое подключение (если PostgreSQL открыт externally)

```json
{
  "sqltools.connections": [
    {
      "previewLimit": 50,
      "driver": "PostgreSQL",
      "name": "farming_db - Master Node NL",
      "server": "82.40.60.131",
      "port": 5432,
      "database": "farming_db",
      "username": "farming_user",
      "password": "U5e8xXLTX7zm0v5KDu2oVsJuvdW478"
    }
  ]
}
```

### Способ 2: Через SSH-туннель (рекомендуется для безопасности)

**Шаг 1**: Создать SSH-туннель в терминале:

```bash
ssh -L 15432:localhost:5432 root@82.40.60.131
```

**Шаг 2**: Подключиться через SQLTools к localhost:15432:

```json
{
  "sqltools.connections": [
    {
      "previewLimit": 50,
      "driver": "PostgreSQL",
      "name": "farming_db - SSH Tunnel",
      "server": "localhost",
      "port": 15432,
      "database": "farming_db",
      "username": "farming_user",
      "password": "U5e8xXLTX7zm0v5KDu2oVsJuvdW478"
    }
  ]
}
```

### Способ 3: Через SSH extension в VS Code

1. Установить расширение Remote - SSH
2. Добавить хост в `~/.ssh/config`:

```
Host master-node-nl
    HostName 82.40.60.131
    User root
    IdentityFile ~/.ssh/master_node_farm
```

3. Подключиться к удалённому хосту через VS Code
4. Установить SQLTools на удалённом хосте
5. Подключиться к `localhost:5432`

## Структура базы данных

Согласно [`database/schema.sql`](../database/schema.sql):

- **30 таблиц** (21 базовая + 3 personas + 6 protocols)
- **14 ENUM типов**
- **35+ индексов**

### Ключевые таблицы для мониторинга:

| Таблица | Описание |
|---------|----------|
| `wallets` | 90 кошельков (18 Tier A, 45 Tier B, 27 Tier C) |
| `wallet_personas` | Уникальные поведенческие персоны |
| `worker_nodes` | 3 worker nodes (1 NL, 2 IS) |
| `proxy_pool` | 200 прокси (45 NL + 125 IS + 30 CA) |
| `cex_subaccounts` | 18 субаккаунтов (OKX-4, Binance-4, Bybit-4, KuCoin-3, MEXC-3) |
| `funding_chains` | 18 цепочек финансирования |
| `scheduled_transactions` | Очередь транзакций |
| `system_events` | Системные события и алерты |

## Полезные SQL-запросы для проверки

### Проверка статуса кошельков:

```sql
SELECT 
    tier,
    status,
    COUNT(*) as count
FROM wallets
GROUP BY tier, status
ORDER BY tier, status;
```

### Проверка worker nodes:

```sql
SELECT 
    worker_id,
    hostname,
    location,
    timezone,
    last_heartbeat
FROM worker_nodes
ORDER BY worker_id;
```

### Проверка протоколов:

```sql
SELECT 
    name,
    category,
    has_points_program,
    priority_score
FROM protocols
WHERE is_active = TRUE
ORDER BY priority_score DESC
LIMIT 20;
```

### Проверка scheduled transactions:

```sql
SELECT 
    status,
    COUNT(*) as count,
    MIN(scheduled_at) as earliest,
    MAX(scheduled_at) as latest
FROM scheduled_transactions
GROUP BY status;
```

## Файлы конфигурации для создания

1. `.vscode/settings.json` - настройки SQLTools
2. `.vscode/launch.json` - конфигурации запуска (если нужно)

## Безопасность

⚠️ **ВАЖНО**: Пароль базы данных хранится в открытом виде в настройках VS Code. 

**Рекомендации**:
1. Использовать переменную окружения `DB_PASS` вместо хардкода
2. Ограничить доступ к файлу `.vscode/settings.json` через `.gitignore`
3. Использовать SSH-туннель вместо прямого подключения

## Выполненные шаги

1. [x] Создать `.vscode/settings.json` с конфигурацией SQLTools
2. [x] Проверить `.vscode/` в `.gitignore` (уже есть на строке 129)
3. [x] Протестировать подключение через SSH-туннель
4. [x] Создать часто используемые SQL-запросы в `.vscode/sqltools.json`
5. [x] Создать рекомендации расширений в `.vscode/extensions.json`

## Результаты тестирования подключения

```
PostgreSQL 17.8 (Debian 17.8-0+deb13u1) on x86_64-pc-linux-gnu

wallets: 90
protocols: 0
```

✅ **Подключение успешно!**

## Созданные файлы

| Файл | Описание |
|------|----------|
| `.vscode/settings.json` | Конфигурация SQLTools с 2 подключениями |
| `.vscode/sqltools.json` | 15 часто используемых SQL-запросов |
| `.vscode/extensions.json` | Рекомендованные расширения VS Code |

## Как использовать SQLTools

1. Установите расширения:
   - `mtxr.sqltools`
   - `mtxr.sqltools-driver-pg`

2. Откройте панель SQLTools: `Ctrl+Shift+P` → "SQLTools: Focus on Connection Explorer"

3. Выберите подключение:
   - **farming_db - Master Node NL** - прямое подключение
   - **farming_db - SSH Tunnel** - через SSH-туннель (безопаснее)

4. Для SSH-туннеля сначала выполните:
   ```bash
   ssh -L 15432:localhost:5432 root@82.40.60.131
   ```

5. Выберите таблицу для просмотра данных или выполните SQL-запрос
