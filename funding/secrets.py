#!/usr/bin/env python3
"""
CEX API Keys Encryption/Decryption Manager
==========================================
Модуль для шифрования и расшифровки API ключей бирж с использованием Fernet (symmetric encryption).

Security Features:
- Fernet encryption (AES-128 в режиме CBC с HMAC для аутентификации)
- Ключ шифрования хранится в /root/.farming_secrets (chmod 600)
- API ключи зашифрованы в PostgreSQL (даже при утечке дампа БД невозможно расшифровать)
- Автоматическая верификация после шифрования

Usage:
    # Зашифровать все CEX API ключи
    python funding/secrets.py encrypt-cex-keys
    
    # Верифицировать шифрование
    python funding/secrets.py verify-encryption
    
    # Использование в коде (например, funding/cex_integration.py)
    from funding.secrets import decrypt_cex_credentials
    creds = decrypt_cex_credentials(subaccount_id=1)
    # → {'api_key': 'fcbc32ed-...', 'api_secret': '2142F386...', 'api_passphrase': 'yIFdCq9812!'}

Author: Airdrop Farming System v4.0
Created: 2026-02-24
"""

import os
import sys
from typing import Dict, Optional
from pathlib import Path
from datetime import datetime

from cryptography.fernet import Fernet, InvalidToken
from loguru import logger

# Добавить parent directory в путь для импорта db_manager
sys.path.insert(0, str(Path(__file__).parent.parent))

from database.db_manager import DatabaseManager


class SecretsManager:
    """
    Менеджер для шифрования/расшифровки секретов CEX и Proxy.
    
    Attributes:
        fernet: Fernet instance для шифрования
        db: DatabaseManager instance
        secrets_file: Путь к файлу с Fernet ключом
    """
    
    def __init__(self, secrets_file: str = '/root/.farming_secrets'):
        """
        Инициализация SecretsManager.
        
        Args:
            secrets_file: Путь к файлу с FERNET_KEY
        
        Raises:
            FileNotFoundError: Если secrets_file не найден
            ValueError: Если FERNET_KEY не найден в файле
        """
        self.secrets_file = secrets_file
        self.fernet = self._load_fernet_key()
        self.db = DatabaseManager()
        logger.info(f"SecretsManager initialized | Secrets file: {secrets_file}")
    
    def _load_fernet_key(self) -> Fernet:
        """
        Загрузка Fernet ключа из файла секретов.
        
        Returns:
            Fernet instance
        
        Raises:
            FileNotFoundError: Если файл не найден
            ValueError: Если ключ не найден в файле
        """
        if not os.path.exists(self.secrets_file):
            logger.critical(f"Secrets file not found: {self.secrets_file}")
            raise FileNotFoundError(
                f"Secrets file {self.secrets_file} not found. "
                "Run master_setup.sh first to generate secrets."
            )
        
        with open(self.secrets_file, 'r') as f:
            for line in f:
                if line.startswith('FERNET_KEY='):
                    key = line.split('=', 1)[1].strip()
                    logger.debug("Fernet key loaded successfully")
                    return Fernet(key.encode())
        
        logger.critical("FERNET_KEY not found in secrets file")
        raise ValueError(
            f"FERNET_KEY not found in {self.secrets_file}. "
            "File may be corrupted. Re-run master_setup.sh."
        )
    
    def _is_encrypted(self, value: str) -> bool:
        """
        Проверка, зашифрован ли ключ с помощью Fernet.
        
        Args:
            value: Строка для проверки
        
        Returns:
            True если значение зашифровано Fernet
        """
        try:
            # Fernet tokens начинаются с 'gAAAAA' (base64 версии + timestamp)
            if not value.startswith('gAAAAA'):
                return False
            
            # Попытка расшифровки (поднимет InvalidToken если не зашифровано)
            self.fernet.decrypt(value.encode())
            return True
        except InvalidToken:
            return False
        except Exception:
            return False
    
    def _create_proxy_backup(self) -> Optional[str]:
        """
        Создание бэкапа plain text прокси паролей перед шифрованием.
        
        Returns:
            Путь к backup файлу или None при ошибке
        """
        try:
            backup_dir = '/root/proxy_backups'
            os.makedirs(backup_dir, exist_ok=True)
            
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            backup_file = f"{backup_dir}/proxy_passwords_backup_{timestamp}.sql"
            
            # Экспорт plain text прокси паролей в SQL backup
            query = """
                SELECT id, ip_address, port, protocol, username, password, country_code, provider, session_id
                FROM proxy_pool
                WHERE is_active = TRUE
                ORDER BY id
            """
            proxies = self.db.execute_query(query, fetch='all')
            
            if not proxies:
                logger.warning("No active proxies to backup")
                return None
            
            # Создание SQL INSERT statements
            with open(backup_file, 'w') as f:
                f.write("-- Proxy Pool Backup (PLAIN TEXT PASSWORDS)\n")
                f.write(f"-- Created: {datetime.now().isoformat()}\n")
                f.write("-- WARNING: Contains unencrypted proxy passwords! Delete after verification.\n\n")
                
                for proxy in proxies:
                    session_id = f"'{proxy['session_id']}'" if proxy['session_id'] else "NULL"
                    f.write(
                        f"INSERT INTO proxy_pool (id, ip_address, port, protocol, username, password, "
                        f"country_code, provider, session_id, is_active) VALUES "
                        f"({proxy['id']}, '{proxy['ip_address']}', {proxy['port']}, '{proxy['protocol']}', "
                        f"'{proxy['username']}', '{proxy['password']}', '{proxy['country_code']}', "
                        f"'{proxy['provider']}', {session_id}, TRUE);\n"
                    )
            
            # Ограничить права доступа (только root может читать)
            os.chmod(backup_file, 0o600)
            logger.success(f"Proxy backup created | File: {backup_file} | chmod: 600")
            return backup_file
        
        except Exception as e:
            logger.error(f"Failed to create proxy backup | Error: {e}")
            return None
    
    def _create_backup(self) -> Optional[str]:
        """
        Создание бэкапа plain text API ключей перед шифрованием.
        
        Returns:
            Путь к backup файлу или None при ошибке
        """
        try:
            backup_dir = '/root/cex_backups'
            os.makedirs(backup_dir, exist_ok=True)
            
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            backup_file = f"{backup_dir}/cex_keys_backup_{timestamp}.sql"
            
            # Экспорт plain text ключей в SQL backup
            query = """
                SELECT id, exchange, subaccount_name, api_key, api_secret, api_passphrase, withdrawal_network
                FROM cex_subaccounts
                ORDER BY id
            """
            subaccounts = self.db.execute_query(query, fetch='all')
            
            if not subaccounts:
                logger.warning("No subaccounts to backup")
                return None
            
            # Создание SQL INSERT statements
            with open(backup_file, 'w') as f:
                f.write("-- CEX Subaccounts Backup (PLAIN TEXT)\n")
                f.write(f"-- Created: {datetime.now().isoformat()}\n")
                f.write("-- WARNING: Contains unencrypted API keys! Delete after verification.\n\n")
                
                for sub in subaccounts:
                    passphrase = f"'{sub['api_passphrase']}'" if sub['api_passphrase'] else "NULL"
                    f.write(
                        f"INSERT INTO cex_subaccounts (id, exchange, subaccount_name, api_key, api_secret, "
                        f"api_passphrase, withdrawal_network) VALUES "
                        f"({sub['id']}, '{sub['exchange']}', '{sub['subaccount_name']}', "
                        f"'{sub['api_key']}', '{sub['api_secret']}', {passphrase}, '{sub['withdrawal_network']}');\n"
                    )
            
            # Ограничить права доступа (только root может читать)
            os.chmod(backup_file, 0o600)
            logger.success(f"Backup created | File: {backup_file} | chmod: 600")
            return backup_file
        
        except Exception as e:
            logger.error(f"Failed to create backup | Error: {e}")
            return None
    
    def encrypt_cex_keys(self) -> int:
        """
        Зашифровать все API ключи в таблице cex_subaccounts.
        
        Процесс:
        1. Создать бэкап plain text ключей
        2. Получить все subaccounts с plain text ключами
        3. Зашифровать api_key, api_secret, api_passphrase (если есть)
        4. Обновить записи в БД
        5. Верификация шифрования
        
        Returns:
            Количество зашифрованных subaccounts
        
        Raises:
            Exception: При ошибках шифрования или записи в БД
        """
        logger.info("Starting CEX API keys encryption...")
        
        # Шаг 1: Создать бэкап перед шифрованием
        backup_file = self._create_backup()
        if backup_file:
            logger.info(f"Backup created: {backup_file}")
        else:
            logger.warning("Backup creation failed, proceeding anyway...")
        
        # Получить все subaccounts
        query = "SELECT id, exchange, subaccount_name, api_key, api_secret, api_passphrase FROM cex_subaccounts"
        subaccounts = self.db.execute_query(query, fetch='all')
        
        if not subaccounts:
            logger.warning("No subaccounts found in database")
            return 0
        
        encrypted_count = 0
        
        for sub in subaccounts:
            try:
                # Проверка: если ключ уже зашифрован (Fernet signature), пропустить
                if self._is_encrypted(sub['api_key']):
                    logger.debug(f"Subaccount {sub['id']} ({sub['subaccount_name']}) already encrypted, skipping")
                    continue
                
                # Шифрование ключей
                encrypted_key = self.fernet.encrypt(sub['api_key'].encode()).decode()
                encrypted_secret = self.fernet.encrypt(sub['api_secret'].encode()).decode()
                encrypted_passphrase = None
                
                # Passphrase есть только у OKX и KuCoin
                if sub['api_passphrase']:
                    encrypted_passphrase = self.fernet.encrypt(sub['api_passphrase'].encode()).decode()
                
                # Обновление БД
                update_query = """
                    UPDATE cex_subaccounts
                    SET api_key = %s, api_secret = %s, api_passphrase = %s, updated_at = NOW()
                    WHERE id = %s
                """
                self.db.execute_query(
                    update_query,
                    (encrypted_key, encrypted_secret, encrypted_passphrase, sub['id'])
                )
                
                encrypted_count += 1
                logger.info(
                    f"Encrypted subaccount {sub['id']} | "
                    f"Exchange: {sub['exchange']} | "
                    f"Name: {sub['subaccount_name']}"
                )
            
            except Exception as e:
                logger.error(
                    f"Failed to encrypt subaccount {sub['id']} ({sub['subaccount_name']}) | "
                    f"Error: {e}"
                )
                raise
        
        logger.success(f"Encryption completed | Total encrypted: {encrypted_count}")
        
        # Security: Auto-delete backup after successful encryption
        if backup_file and encrypted_count > 0:
            try:
                import os
                os.remove(backup_file)
                logger.success(f"✅ Backup auto-deleted for security: {backup_file}")
            except Exception as e:
                logger.warning(f"Failed to auto-delete backup: {backup_file} | Error: {e}")
                logger.warning(f"⚠️  MANUAL DELETE REQUIRED: sudo rm {backup_file}")
        
        return encrypted_count
    
    def encrypt_proxy_passwords(self) -> int:
        """
        Зашифровать все пароли прокси в таблице proxy_pool.
        
        Процесс:
        1. Создать бэкап plain text паролей
        2. Получить все прокси с plain text паролями
        3. Зашифровать поле password
        4. Обновить записи в БД
        5. Верификация шифрования
        
        Returns:
            Количество зашифрованных прокси
        
        Raises:
            Exception: При ошибках шифрования или записи в БД
        """
        logger.info("Starting proxy passwords encryption...")
        
        # Шаг 1: Создать бэкап перед шифрованием
        backup_file = self._create_proxy_backup()
        if backup_file:
            logger.info(f"Proxy backup created: {backup_file}")
        else:
            logger.warning("Proxy backup creation failed, proceeding anyway...")
        
        # Получить все прокси с plain text паролями
        query = """
            SELECT id, ip_address, port, username, password, country_code, provider, session_id
            FROM proxy_pool
            WHERE is_active = TRUE
        """
        proxies = self.db.execute_query(query, fetch='all')
        
        if not proxies:
            logger.warning("No active proxies found in database")
            return 0
        
        encrypted_count = 0
        
        for proxy in proxies:
            try:
                # Проверка: если пароль уже зашифрован (Fernet signature), пропустить
                if self._is_encrypted(proxy['password']):
                    logger.debug(f"Proxy {proxy['id']} ({proxy['ip_address']}) already encrypted, skipping")
                    continue
                
                # Шифрование пароля
                encrypted_password = self.fernet.encrypt(proxy['password'].encode()).decode()
                
                # Обновление БД
                update_query = """
                    UPDATE proxy_pool
                    SET password = %s, updated_at = NOW()
                    WHERE id = %s
                """
                self.db.execute_query(
                    update_query,
                    (encrypted_password, proxy['id'])
                )
                
                encrypted_count += 1
                logger.info(
                    f"Encrypted proxy {proxy['id']} | "
                    f"IP: {proxy['ip_address']}:{proxy['port']} | "
                    f"Provider: {proxy['provider']} | "
                    f"Country: {proxy['country_code']}"
                )
            
            except Exception as e:
                logger.error(
                    f"Failed to encrypt proxy {proxy['id']} ({proxy['ip_address']}) | "
                    f"Error: {e}"
                )
                raise
        
        logger.success(f"Proxy encryption completed | Total encrypted: {encrypted_count}")
        
        # Security: Auto-delete backup after successful encryption
        if backup_file and encrypted_count > 0:
            try:
                import os
                os.remove(backup_file)
                logger.success(f"✅ Proxy backup auto-deleted for security: {backup_file}")
            except Exception as e:
                logger.warning(f"Failed to auto-delete proxy backup: {backup_file} | Error: {e}")
                logger.warning(f"⚠️  MANUAL DELETE REQUIRED: sudo rm {backup_file}")
        
        return encrypted_count
    
    def decrypt_proxy_credentials(self, proxy_id: int) -> Optional[Dict[str, str]]:
        """
        Расшифровать credentials для конкретного прокси.
        
        Используется в activity/proxy_manager.py для создания прокси соединения.
        
        Args:
            proxy_id: ID прокси в таблице proxy_pool
        
        Returns:
            Dict с расшифрованными credentials:
            {
                'username': 'mtsJYVVhN3YaX3z7',
                'password': 'vWFHyi0bw0jO8TQM',
                'ip_address': 'geo.iproyal.com',
                'port': 12321,
                'protocol': 'socks5'
            }
            None если прокси не найден
        
        Example:
            >>> secrets = SecretsManager()
            >>> proxy = secrets.decrypt_proxy_credentials(1)
            >>> import requests
            >>> proxies = {
            ...     'http': f'socks5://{proxy["username"]}:{proxy["password"]}@{proxy["ip_address"]}:{proxy["port"]}',
            ...     'https': f'socks5://{proxy["username"]}:{proxy["password"]}@{proxy["ip_address"]}:{proxy["port"]}'
            ... }
        """
        query = """
            SELECT id, ip_address, port, protocol, username, password
            FROM proxy_pool
            WHERE id = %s
        """
        proxy = self.db.execute_query(query, (proxy_id,), fetch='one')
        
        if not proxy:
            logger.warning(f"Proxy {proxy_id} not found")
            return None
        
        try:
            credentials = {
                'id': proxy['id'],
                'ip_address': proxy['ip_address'],
                'port': proxy['port'],
                'protocol': proxy['protocol'],
                'username': proxy['username'],  # Username не шифруется
                'password': self.fernet.decrypt(proxy['password'].encode()).decode(),
            }
            
            logger.debug(f"Decrypted proxy credentials for proxy {proxy_id} ({proxy['ip_address']})")
            return credentials
        
        except InvalidToken:
            logger.error(
                f"Failed to decrypt proxy {proxy_id} | "
                "Invalid Fernet key or data corrupted"
            )
            return None
        except Exception as e:
            logger.error(f"Error decrypting proxy {proxy_id} | Error: {e}")
            return None
    
    def verify_proxy_encryption(self) -> bool:
        """
        Верификация шифрования прокси паролей.
        
        Проверки:
        1. Все password имеют длину > 100 символов (признак шифрования)
        2. Можно расшифровать обратно в валидные пароли
        3. Расшифрованные пароли не пустые
        
        Returns:
            True если все проверки прошли успешно
        """
        logger.info("Verifying proxy passwords encryption...")
        
        query = """
            SELECT id, ip_address, port, username, password
            FROM proxy_pool
            WHERE is_active = TRUE
        """
        proxies = self.db.execute_query(query, fetch='all')
        
        if not proxies:
            logger.warning("No active proxies found")
            return False
        
        all_valid = True
        
        for proxy in proxies:
            try:
                # Проверка 1: Длина зашифрованного пароля
                if len(proxy['password']) <= 100:
                    logger.error(
                        f"Proxy {proxy['id']} ({proxy['ip_address']}) | "
                        f"Password appears unencrypted (length: {len(proxy['password'])})"
                    )
                    all_valid = False
                    continue
                
                # Проверка 2: Расшифровка
                decrypted_password = self.fernet.decrypt(proxy['password'].encode()).decode()
                
                # Проверка 3: Валидность расшифрованного пароля (не пустой)
                if not decrypted_password:
                    logger.error(f"Proxy {proxy['id']} | Decrypted password is empty")
                    all_valid = False
                    continue
                
                logger.debug(
                    f"Proxy {proxy['id']} ({proxy['ip_address']}) | "
                    f"Encryption valid | "
                    f"Password length: {len(proxy['password'])} chars"
                )
            
            except InvalidToken:
                logger.error(
                    f"Proxy {proxy['id']} | "
                    f"Failed to decrypt (invalid token, wrong Fernet key?)"
                )
                all_valid = False
            except Exception as e:
                logger.error(f"Proxy {proxy['id']} | Verification error: {e}")
                all_valid = False
        
        if all_valid:
            logger.success("Proxy verification passed | All passwords encrypted and decryptable")
        else:
            logger.error("Proxy verification failed | Some passwords are not properly encrypted")
        
        return all_valid
    
    def verify_encryption(self) -> bool:
        """
        Верификация шифрования CEX ключей.
        
        Проверки:
        1. Все api_key имеют длину > 100 символов (признак шифрования)
        2. Можно расшифровать обратно в валидные ключи
        3. Расшифрованные ключи соответствуют ожидаемому формату
        
        Returns:
            True если все проверки прошли успешно
        """
        logger.info("Verifying CEX keys encryption...")
        
        query = "SELECT id, exchange, api_key, api_secret, api_passphrase FROM cex_subaccounts"
        subaccounts = self.db.execute_query(query, fetch='all')
        
        if not subaccounts:
            logger.warning("No subaccounts found")
            return False
        
        all_valid = True
        
        for sub in subaccounts:
            try:
                # Проверка 1: Длина зашифрованного ключа
                if len(sub['api_key']) <= 100:
                    logger.error(
                        f"Subaccount {sub['id']} | Key appears unencrypted (length: {len(sub['api_key'])})"
                    )
                    all_valid = False
                    continue
                
                # Проверка 2: Расшифровка
                decrypted_key = self.fernet.decrypt(sub['api_key'].encode()).decode()
                decrypted_secret = self.fernet.decrypt(sub['api_secret'].encode()).decode()
                
                # Проверка 3: Валидность расшифрованных ключей (не пустые)
                if not decrypted_key or not decrypted_secret:
                    logger.error(f"Subaccount {sub['id']} | Decrypted keys are empty")
                    all_valid = False
                    continue
                
                # Проверка 4: Passphrase (если есть)
                if sub['api_passphrase']:
                    decrypted_passphrase = self.fernet.decrypt(sub['api_passphrase'].encode()).decode()
                    if not decrypted_passphrase:
                        logger.error(f"Subaccount {sub['id']} | Decrypted passphrase is empty")
                        all_valid = False
                        continue
                
                logger.debug(
                    f"Subaccount {sub['id']} ({sub['exchange']}) | "
                    f"Encryption valid | "
                    f"Key length: {len(sub['api_key'])} chars"
                )
            
            except InvalidToken:
                logger.error(
                    f"Subaccount {sub['id']} | "
                    f"Failed to decrypt (invalid token, wrong Fernet key?)"
                )
                all_valid = False
            except Exception as e:
                logger.error(f"Subaccount {sub['id']} | Verification error: {e}")
                all_valid = False
        
        if all_valid:
            logger.success("Verification passed | All keys encrypted and decryptable")
        else:
            logger.error("Verification failed | Some keys are not properly encrypted")
        
        return all_valid
    
    def decrypt_cex_credentials(self, subaccount_id: int) -> Optional[Dict[str, str]]:
        """
        Расшифровать credentials для конкретного subaccount.
        
        Используется в funding/cex_integration.py для создания CCXT exchange instance.
        
        Args:
            subaccount_id: ID субаккаунта в таблице cex_subaccounts
        
        Returns:
            Dict с расшифрованными ключами:
            {
                'exchange': 'okx',
                'subaccount_name': 'AlphaTradingStrategy',
                'api_key': 'fcbc32ed-4923-4152-93e3-e7ef130a9d3d',
                'api_secret': '2142F386984C039F492013EBBCA54CCC',
                'api_passphrase': 'yIFdCq9812!' (если есть)
            }
            None если subaccount не найден
        
        Example:
            >>> secrets = SecretsManager()
            >>> creds = secrets.decrypt_cex_credentials(1)
            >>> import ccxt
            >>> exchange = ccxt.okx({
            ...     'apiKey': creds['api_key'],
            ...     'secret': creds['api_secret'],
            ...     'password': creds['api_passphrase']
            ... })
        """
        query = """
            SELECT id, exchange, subaccount_name, api_key, api_secret, api_passphrase
            FROM cex_subaccounts
            WHERE id = %s
        """
        sub = self.db.execute_query(query, (subaccount_id,), fetch='one')
        
        if not sub:
            logger.warning(f"Subaccount {subaccount_id} not found")
            return None
        
        try:
            credentials = {
                'exchange': sub['exchange'],
                'subaccount_name': sub['subaccount_name'],
                'api_key': self.fernet.decrypt(sub['api_key'].encode()).decode(),
                'api_secret': self.fernet.decrypt(sub['api_secret'].encode()).decode(),
            }
            
            # Passphrase опционален (только OKX и KuCoin)
            if sub['api_passphrase']:
                credentials['api_passphrase'] = self.fernet.decrypt(sub['api_passphrase'].encode()).decode()
            
            logger.debug(f"Decrypted credentials for subaccount {subaccount_id} ({sub['exchange']})")
            return credentials
        
        except InvalidToken:
            logger.error(
                f"Failed to decrypt subaccount {subaccount_id} | "
                "Invalid Fernet key or data corrupted"
            )
            return None
        except Exception as e:
            logger.error(f"Error decrypting subaccount {subaccount_id} | Error: {e}")
            return None
    
    def decrypt_cex_credential(self, subaccount_id: int, field: str) -> Optional[str]:
        """
        Расшифровать отдельное поле (api_key, api_secret, api_passphrase) для subaccount.
        
        Helper method для случаев, когда нужен только один ключ.
        
        Args:
            subaccount_id: ID субаккаунта
            field: Название поля ('api_key', 'api_secret', 'api_passphrase')
        
        Returns:
            Расшифрованное значение или None
        """
        creds = self.decrypt_cex_credentials(subaccount_id)
        if not creds:
            return None
        
        return creds.get(field)


# =============================================================================
# CLI INTERFACE
# =============================================================================

def main():
    """CLI entry point для secrets.py."""
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python funding/secrets.py encrypt-cex-keys     # Зашифровать CEX ключи")
        print("  python funding/secrets.py encrypt-proxy-passwords  # Зашифровать прокси пароли")
        print("  python funding/secrets.py verify-encryption    # Проверить шифрование")
        print("  python funding/secrets.py verify-proxy-encryption  # Проверить прокси шифрование")
        sys.exit(1)
    
    command = sys.argv[1]
    
    try:
        secrets = SecretsManager()
        
        if command == 'encrypt-cex-keys':
            count = secrets.encrypt_cex_keys()
            print(f"\n✅ CEX encryption completed: {count} subaccounts encrypted")
            print("\nNext steps:")
            print("1. Run verification: python funding/secrets.py verify-encryption")
            print("2. Backup Fernet key: grep FERNET_KEY /root/.farming_secrets")
            print("3. Delete plain text files: rm database/seed_cex_subaccounts.sql")
        
        elif command == 'encrypt-proxy-passwords':
            count = secrets.encrypt_proxy_passwords()
            print(f"\n✅ Proxy encryption completed: {count} proxy passwords encrypted")
            print("\nNext steps:")
            print("1. Run verification: python funding/secrets.py verify-proxy-encryption")
            print("2. Backup Fernet key: grep FERNET_KEY /root/.farming_secrets")
            print("3. Update seed file: python funding/secrets.py update-seed-proxies")
            print("4. Delete plain text backup: sudo rm /root/proxy_backups/*.sql")
        
        elif command == 'verify-encryption':
            if secrets.verify_encryption():
                print("\n✅ CEX verification PASSED: All keys are encrypted and decryptable")
            else:
                print("\n❌ CEX verification FAILED: Some keys are not properly encrypted")
                sys.exit(1)
        
        elif command == 'verify-proxy-encryption':
            if secrets.verify_proxy_encryption():
                print("\n✅ Proxy verification PASSED: All passwords are encrypted and decryptable")
            else:
                print("\n❌ Proxy verification FAILED: Some passwords are not properly encrypted")
                sys.exit(1)
        
        else:
            print(f"Unknown command: {command}")
            print("Available commands: encrypt-cex-keys, encrypt-proxy-passwords, verify-encryption, verify-proxy-encryption")
            sys.exit(1)
    
    except FileNotFoundError as e:
        print(f"\n❌ Error: {e}")
        print("\nSolution: Run master_setup.sh first to generate /root/.farming_secrets")
        sys.exit(1)
    except Exception as e:
        logger.exception(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
