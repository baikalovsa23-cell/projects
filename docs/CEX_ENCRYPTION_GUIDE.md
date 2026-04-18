# CEX API Keys Encryption Guide

> **Модуль:** `funding/secrets.py`  
> **Цель:** Защита API ключей бирж через Fernet шифрование  
> **Статус:** ✅ Готов к использованию

---

## 🔐 Обзор

Этот guide описывает процесс безопасного хранения и использования API ключей от 18 субаккаунтов на 5 биржах (Binance, Bybit, OKX, KuCoin, MEXC).

### Почему Нужно Шифрование

**Без шифрования:**
- ❌ API ключи в plain text в БД → риск утечки при дампе БД
- ❌ Любой с доступом к PostgreSQL может вывести все средства
- ❌ Сложно контролировать доступ (либо весь доступ к БД, либо никакого)

**С Fernet шифрованием:**
- ✅ Ключи зашифрованы в БД (ключ шифрования отдельно в `/root/.farming_secrets`)
- ✅ Даже при утечке дампа БД невозможно извлечь API ключи без Fernet key
- ✅ Granular access control: доступ к БД ≠ доступ к API ключам

---

## 📋 Пошаговая Инструкция

### Шаг 1: Генерация Fernet Ключа (Автоматически)

Fernet ключ генерируется автоматически при запуске [`master_setup.sh`](../master_setup.sh):

```bash
# Внутри master_setup.sh (строки 147-154)
# Генерация Fernet ключа для шифрования приватных ключей
FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
echo "FERNET_KEY=$FERNET_KEY" >> /root/.farming_secrets
```

**После развёртывания Master Node:**

```bash
# Проверить, что ключ создан
cat /root/.farming_secrets | grep FERNET_KEY
# Вывод: FERNET_KEY=xGdK7vH9... (44 символа base64)
```

---

### Шаг 2: Загрузка CEX Subaccounts в БД

**⚠️ ВАЖНО:** Сначала загрузи plain text ключи в БД, затем зашифруй их. Не храни plain text файл после шифрования.

```bash
# На Master Node
cd /opt/farming

# Загрузить seed data (18 subaccounts с plain text ключами)
psql -U farming_user -d farming_db -f database/seed_cex_subaccounts.sql

# Проверить загрузку
psql -U farming_user -d farming_db -c \
  "SELECT id, exchange, subaccount_name, LENGTH(api_key) as key_len FROM cex_subaccounts LIMIT 5;"

# Ожидаемый результат (plain text, ключи короткие):
#  id | exchange | subaccount_name        | key_len
# ----+----------+------------------------+--------
#   1 | okx      | AlphaTradingStrategy   |     36
#   2 | okx      | LongTermStakingVault   |     36
#   3 | okx      | MarketMakingNode       |     36
```

---

### Шаг 3: Шифрование API Ключей

```bash
# Запустить encryption script
python funding/secrets.py encrypt-cex-keys

# Ожидаемый вывод:
# [INFO] SecretsManager initialized | Secrets file: /root/.farming_secrets
# [INFO] Starting CEX API keys encryption...
# [INFO] Encrypted subaccount 1 | Exchange: okx | Name: AlphaTradingStrategy
# [INFO] Encrypted subaccount 2 | Exchange: okx | Name: LongTermStakingVault
# ...
# [SUCCESS] Encryption completed | Total encrypted: 18
#
# ✅ Encryption completed: 18 subaccounts encrypted
#
# Next steps:
# 1. Run verification: python funding/secrets.py verify-encryption
# 2. Backup Fernet key: grep FERNET_KEY /root/.farming_secrets
# 3. Delete plain text files: rm database/seed_cex_subaccounts.sql
```

---

### Шаг 4: Верификация Шифрования

```bash
# Запустить verification
python funding/secrets.py verify-encryption

# Ожидаемый вывод:
# [INFO] Verifying CEX keys encryption...
# [DEBUG] Subaccount 1 (okx) | Encryption valid | Key length: 124 chars
# [DEBUG] Subaccount 2 (okx) | Encryption valid | Key length: 124 chars
# ...
# [SUCCESS] Verification passed | All keys encrypted and decryptable
#
# ✅ Verification PASSED: All keys are encrypted and decryptable
```

**Альтернативная проверка через SQL:**

```bash
psql -U farming_user -d farming_db -c \
  "SELECT id, exchange, subaccount_name, LENGTH(api_key) as key_len FROM cex_subaccounts LIMIT 5;"

# Ожидаемый результат (зашифрованные ключи, длина > 100):
#  id | exchange | subaccount_name        | key_len
# ----+----------+------------------------+--------
#   1 | okx      | AlphaTradingStrategy   |     124
#   2 | okx      | LongTermStakingVault   |     124
#   3 | okx      | MarketMakingNode       |     124
```

---

### Шаг 5: Backup Fernet Ключа (КРИТИЧНО!)

**⚠️ ЕСЛИ ПОТЕРЯЕШЬ FERNET_KEY, ПОТЕРЯЕШЬ ДОСТУП К API КЛЮЧАМ!**

```bash
# Показать Fernet ключ
grep FERNET_KEY /root/.farming_secrets

# Вывод: FERNET_KEY=xGdK7vH9Qm2Lp8jN5k3Ws1Yt4Uv6Zr7Ae9Cf0Bg=
```

**Сохрани ключ в 2 местах:**

1. **Password Manager** (1Password, Bitwarden, KeePass):
   - Создай секретную запись "Airdrop Farming - Fernet Key"
   - Скопируй весь FERNET_KEY=... туда

2. **Offline Backup** (USB флешка / зашифрованный файл на локальном компьютере):
   ```bash
   # Локально на твоём компьютере (не на сервере!)
   echo "FERNET_KEY=xGdK7vH9..." > ~/airdrop_fernet_backup.txt
   
   # Зашифровать с GPG (потребует passphrase)
   gpg --symmetric --cipher-algo AES256 ~/airdrop_fernet_backup.txt
   # → создаст airdrop_fernet_backup.txt.gpg
   
   # Удалить plain text
   rm ~/airdrop_fernet_backup.txt
   
   # Скопировать на USB флешку
   cp ~/airdrop_fernet_backup.txt.gpg /media/usb/
   ```

---

### Шаг 6: Удаление Plain Text Файлов

После успешного шифрования удали файлы с plain text ключами:

```bash
# На сервере
rm /opt/farming/database/seed_cex_subaccounts.sql

# Опционально: зашифровать для backup
cd /opt/farming/database
gpg --symmetric --cipher-algo AES256 seed_cex_subaccounts.sql
# → создаст seed_cex_subaccounts.sql.gpg
rm seed_cex_subaccounts.sql

# Переместить Subaccaunt.md в защищённое место
mkdir -p /root/.farming_secrets_backup
mv /root/airdrop_v4/Subaccaunt.md /root/.farming_secrets_backup/
chmod 600 /root/.farming_secrets_backup/Subaccaunt.md

# Опционально: тоже зашифровать
cd /root/.farming_secrets_backup
gpg --symmetric --cipher-algo AES256 Subaccaunt.md
rm Subaccaunt.md
```

---

## 💻 Использование в Коде

### Расшифровка Credentials для CCXT

**Модуль:** `funding/cex_integration.py` (будет создан позже)

```python
from funding.secrets import SecretsManager
import ccxt

# Инициализация
secrets = SecretsManager()

# Получить credentials для subaccount ID 1 (OKX AlphaTradingStrategy)
creds = secrets.decrypt_cex_credentials(subaccount_id=1)

# Результат:
# {
#     'exchange': 'okx',
#     'subaccount_name': 'AlphaTradingStrategy',
#     'api_key': 'fcbc32ed-4923-4152-93e3-e7ef130a9d3d',
#     'api_secret': '2142F386984C039F492013EBBCA54CCC',
#     'api_passphrase': 'yIFdCq9812!'
# }

# Создать CCXT exchange instance
exchange = ccxt.okx({
    'apiKey': creds['api_key'],
    'secret': creds['api_secret'],
    'password': creds.get('api_passphrase')  # Только для OKX/KuCoin
})

# Проверить баланс
balance = exchange.fetch_balance()
print(balance['USDT'])
```

---

## 🔧 Troubleshooting

### Ошибка: "Secrets file not found"

```
❌ Error: Secrets file /root/.farming_secrets not found
```

**Решение:**
```bash
# Проверить, что файл существует
ls -la /root/.farming_secrets

# Если нет, перезапустить master_setup.sh
sudo bash /root/master_setup.sh
```

---

### Ошибка: "Failed to decrypt (invalid token)"

```
[ERROR] Subaccount 1 | Failed to decrypt (invalid token, wrong Fernet key?)
```

**Причины:**
1. Fernet ключ в `/root/.farming_secrets` не совпадает с тем, которым шифровали
2. Данные в БД повреждены

**Решение:**
```bash
# Проверить Fernet ключ
cat /root/.farming_secrets | grep FERNET_KEY

# Если ключ изменился, восстановить из backup
# Если backup нет, придётся пересоздавать API ключи на биржах
```

---

### Ошибка: "No subaccounts found in database"

```
[WARNING] No subaccounts found in database
```

**Решение:**
```bash
# Загрузить seed data
psql -U farming_user -d farming_db -f database/seed_cex_subaccounts.sql
```

---

## 🛡️ Security Best Practices

### ✅ DO

- ✅ **Создай backup Fernet ключа** в 2+ местах (password manager + offline storage)
- ✅ **Удали plain text файлы** после шифрования
- ✅ **Проверяй permissions** на `/root/.farming_secrets` (должно быть 600)
- ✅ **Используй GPG encryption** для backup файлов с ключами
- ✅ **Регулярно тестируй** расшифровку (1 раз в месяц)

### ❌ DON'T

- ❌ **НЕ коммить** Subaccaunt.md или seed_cex_subaccounts.sql в git
- ❌ **НЕ хранить** Fernet ключ в `.env` (используй `/root/.farming_secrets`)
- ❌ **НЕ делиться** Fernet ключом через email/Telegram
- ❌ **НЕ хранить** plain text ключи после шифрования
- ❌ **НЕ использовать** один и тот же Fernet ключ для разных проектов

---

## 📊 Спецификация Шифрования

| Параметр | Значение |
|----------|----------|
| **Алгоритм** | Fernet (AES-128 CBC + HMAC SHA256) |
| **Длина ключа** | 256 бит (32 байта) в base64 (44 символа) |
| **Режим** | CBC (Cipher Block Chaining) |
| **Аутентификация** | HMAC-SHA256 |
| **IV** | Генерируется случайно для каждого шифрования |
| **Формат** | Base64 (версия \|\| timestamp \|\| IV \|\| ciphertext \|\| HMAC) |

**Почему Fernet:**
- ✅ Современный стандарт (часть cryptography.io)
- ✅ Authenticated encryption (защита от tampering)
- ✅ Встроенная ротация ключей (timestamp в токене)
- ✅ Простота использования (1 строка для encrypt/decrypt)

---

## 🔄 Процесс Восстановления

### Сценарий: Потеря Fernet Ключа

**Если есть backup Fernet ключа:**

```bash
# 1. Расшифровать backup
gpg --decrypt ~/airdrop_fernet_backup.txt.gpg > /tmp/fernet_key.txt

# 2. Восстановить в /root/.farming_secrets
cat /tmp/fernet_key.txt >> /root/.farming_secrets

# 3. Удалить временный файл
rm /tmp/fernet_key.txt

# 4. Проверить расшифровку
python funding/secrets.py verify-encryption
```

**Если backup нет (worst case):**

1. Войти во все 18 субаккаунтов на биржах
2. Удалить старые API ключи
3. Создать новые API ключи
4. Обновить `database/seed_cex_subaccounts.sql`
5. Пересоздать БД или обновить вручную
6. Перезапустить шифрование

---

## 📝 Changelog

- **2026-02-24:** Создан модуль `funding/secrets.py`
- **2026-02-24:** Добавлено шифрование 18 CEX subaccounts
- **2026-02-24:** Реализована верификация шифрования

---

**Следующие шаги:** После завершения шифрования переходи к созданию `funding/cex_integration.py` (Модуль 6).
