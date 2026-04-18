# Анализ распределения кошельков по воркерам

## Цель
Выполнить три SQL-запроса для проверки текущего состояния распределения кошельков в системе.

## SQL-запросы для выполнения

### Запрос 1: Реальное распределение кошельков по воркерам и tier
```sql
SELECT worker_node_id, tier, COUNT(*) as cnt
FROM wallets
GROUP BY worker_node_id, tier
ORDER BY worker_node_id, tier;
```

**Ожидаемый результат:**
- Worker 1: 30 кошельков (10 Tier A, 10 Tier B, 10 Tier C)
- Worker 2: 30 кошельков (10 Tier A, 10 Tier B, 10 Tier C)
- Worker 3: 30 кошельков (10 Tier A, 10 Tier B, 10 Tier C)
- Всего: 90 кошельков (30 Tier A, 30 Tier B, 30 Tier C)

### Запрос 2: Проверка NULL значений в worker_node_id
```sql
SELECT COUNT(*) as null_worker FROM wallets WHERE worker_node_id IS NULL;
```

**Ожидаемый результат:** 0 (все кошельки должны быть привязаны к воркерам)

### Запрос 3: Проверка структуры FK ограничений
```sql
SELECT conname, contype, confdeltype
FROM pg_constraint
WHERE conrelid = 'wallets'::regclass
AND conname LIKE '%worker%';
```

**Ожидаемый результат:**
- Наличие FK ограничения `wallets_worker_node_id_fkey`
- Тип: FOREIGN KEY
- On Delete: RESTRICT или NO ACTION (для предотвращения случайного удаления воркеров)

## Дополнительные проверки

### Информация о worker_nodes
```sql
SELECT id, worker_id, hostname, location, is_active, last_heartbeat
FROM worker_nodes
ORDER BY worker_id;
```

**Ожидаемый результат:**
- 3 активных worker nodes (worker_id: 1, 2, 3)
- Разные локации (NL, IS, и т.д.)
- Актуальные heartbeat timestamps

## Архитектурные рекомендации

### Если обнаружены проблемы:

1. **NULL значения в worker_node_id:**
   - Создать скрипт для перераспределения кошельков
   - Использовать алгоритм балансировки по воркерам
   - Учесть tier при распределении

2. **Неравномерное распределение:**
   - Проверить логику генерации кошельков
   - Убедиться в корректности миграций
   - Перераспределить кошельки при необходимости

3. **Отсутствие FK ограничений:**
   - Создать миграцию для добавления FK
   - Установить подходящую политику ON DELETE
   - Проверить целостность данных

## Следующие шаги

1. Выполнить SQL-запросы через DatabaseManager
2. Проанализировать результаты
3. Сравнить с ожидаемыми значениями
4. Подготовить рекомендации по исправлению (если необходимо)
