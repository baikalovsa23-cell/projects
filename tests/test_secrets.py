#!/usr/bin/env python3
"""
Secrets Manager Tests
====================
Тесты для модуля funding/secrets.py

Проверяет:
- Шифрование/дешифрование Fernet
- Шифрование API ключей CEX
- Шифрование приватных ключей кошельков
- Безопасное хранение в .env / .farming_secrets

Run:
    pytest tests/test_secrets.py -v
"""

import os
import sys
import pytest
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock
from cryptography.fernet import Fernet, InvalidToken

sys.path.insert(0, str(Path(__file__).parent.parent))


# =============================================================================
# FERNET ENCRYPTION TESTS
# =============================================================================

class TestFernetEncryption:
    """Tests for Fernet encryption/decryption."""
    
    def test_fernet_key_generation(self):
        """Test that Fernet key can be generated."""
        key = Fernet.generate_key()
        
        assert key is not None
        assert isinstance(key, bytes)
        assert len(key) > 0
    
    def test_fernet_encrypt_decrypt_roundtrip(self):
        """Test that encryption and decryption work correctly."""
        key = Fernet.generate_key()
        fernet = Fernet(key)
        
        original = "my_secret_api_key_12345"
        
        # Encrypt
        encrypted = fernet.encrypt(original.encode())
        
        # Should be different from original
        assert encrypted != original.encode()
        
        # Decrypt
        decrypted = fernet.decrypt(encrypted).decode()
        
        # Should match original
        assert decrypted == original
    
    def test_fernet_invalid_key_raises_error(self):
        """Test that invalid key raises error on decryption."""
        key1 = Fernet.generate_key()
        key2 = Fernet.generate_key()  # Different key!
        
        fernet1 = Fernet(key1)
        fernet2 = Fernet(key2)
        
        original = "secret_data"
        encrypted = fernet1.encrypt(original.encode())
        
        # Decrypting with wrong key should fail
        with pytest.raises(InvalidToken):
            fernet2.decrypt(encrypted)


# =============================================================================
# SECRETS MANAGER TESTS
# =============================================================================

class TestSecretsManager:
    """Tests for SecretsManager class."""
    
    def test_secrets_manager_init(self, mock_db, tmp_path):
        """Test SecretsManager initialization."""
        from cryptography.fernet import Fernet
        
        # Create temp secrets file
        key = Fernet.generate_key().decode()
        secrets_file = tmp_path / ".farming_secrets"
        secrets_file.write_text(f"FERNET_KEY={key}\n")
        
        with patch('funding.secrets.DatabaseManager', return_value=mock_db):
            from funding.secrets import SecretsManager
            
            manager = SecretsManager(secrets_file=str(secrets_file))
            
            assert manager.fernet is not None
    
    def test_encrypt_decrypt_roundtrip(self, mock_db, tmp_path):
        """Test encryption/decryption roundtrip via Fernet."""
        from cryptography.fernet import Fernet
        
        key = Fernet.generate_key().decode()
        secrets_file = tmp_path / ".farming_secrets"
        secrets_file.write_text(f"FERNET_KEY={key}\n")
        
        with patch('funding.secrets.DatabaseManager', return_value=mock_db):
            from funding.secrets import SecretsManager
            
            manager = SecretsManager(secrets_file=str(secrets_file))
            
            # Test direct Fernet encrypt/decrypt
            original = "my_secret_api_key_12345"
            encrypted = manager.fernet.encrypt(original.encode()).decode()
            decrypted = manager.fernet.decrypt(encrypted.encode()).decode()
            
            assert decrypted == original
            assert encrypted != original


# =============================================================================
# ENVIRONMENT VARIABLE TESTS
# =============================================================================

class TestEnvironmentVariables:
    """Tests for environment variable handling."""
    
    def test_fernet_key_from_env(self, temp_env_file):
        """Test loading Fernet key from environment."""
        # Set env variable
        test_key = Fernet.generate_key().decode()
        os.environ['FERNET_KEY'] = test_key
        
        # Load from env
        key = os.getenv('FERNET_KEY')
        
        assert key == test_key
        
        # Cleanup
        del os.environ['FERNET_KEY']
    
    def test_missing_fernet_key_raises_error(self, mock_db, tmp_path):
        """Test that missing FERNET_KEY raises error."""
        # Create empty secrets file
        secrets_file = tmp_path / ".farming_secrets_empty"
        secrets_file.write_text("# no key here\n")
        
        with patch('funding.secrets.DatabaseManager', return_value=mock_db):
            from funding.secrets import SecretsManager
            
            with pytest.raises((ValueError, FileNotFoundError)):
                manager = SecretsManager(secrets_file=str(secrets_file))


# =============================================================================
# SECURE STORAGE TESTS
# =============================================================================

class TestSecureStorage:
    """Tests for secure storage practices."""
    
    def test_encrypted_data_not_readable_as_plaintext(self, mock_db, tmp_path):
        """Test that encrypted data is not readable as plaintext."""
        from cryptography.fernet import Fernet
        
        key = Fernet.generate_key().decode()
        secrets_file = tmp_path / ".farming_secrets"
        secrets_file.write_text(f"FERNET_KEY={key}\n")
        
        with patch('funding.secrets.DatabaseManager', return_value=mock_db):
            from funding.secrets import SecretsManager
            
            manager = SecretsManager(secrets_file=str(secrets_file))
            
            secret = "my_api_secret_key"
            encrypted = manager.fernet.encrypt(secret.encode()).decode()
        
        # Encrypted should not contain original
        assert secret not in encrypted
        assert "api" not in encrypted.lower()
        assert "key" not in encrypted.lower()
    
    def test_multiple_encryptions_produce_different_ciphertext(self, mock_db, tmp_path):
        """Test that same plaintext produces different ciphertext each time."""
        from cryptography.fernet import Fernet
        
        key = Fernet.generate_key().decode()
        secrets_file = tmp_path / ".farming_secrets"
        secrets_file.write_text(f"FERNET_KEY={key}\n")
        
        with patch('funding.secrets.DatabaseManager', return_value=mock_db):
            from funding.secrets import SecretsManager
            
            manager = SecretsManager(secrets_file=str(secrets_file))
            
            secret = "same_secret"
            encrypted1 = manager.fernet.encrypt(secret.encode()).decode()
            encrypted2 = manager.fernet.encrypt(secret.encode()).decode()
        
        # Fernet includes timestamp, so encryptions should differ
        assert encrypted1 != encrypted2


# =============================================================================
# CEX CREDENTIAL FORMAT TESTS
# =============================================================================

class TestCEXCredentialFormats:
    """Tests for CEX credential format validation."""
    
    def test_api_key_format_validation(self, mock_db, tmp_path):
        """Test that API keys can be encrypted/decrypted."""
        from cryptography.fernet import Fernet
        
        key = Fernet.generate_key().decode()
        secrets_file = tmp_path / ".farming_secrets"
        secrets_file.write_text(f"FERNET_KEY={key}\n")
        
        with patch('funding.secrets.DatabaseManager', return_value=mock_db):
            from funding.secrets import SecretsManager
            
            manager = SecretsManager(secrets_file=str(secrets_file))
            
            # Valid API key (various formats)
            valid_keys = [
                "sk_test_12345",
                "api_key_abcdef",
                "AKIAIOSFODNN7EXAMPLE",
            ]
            
            for api_key in valid_keys:
                encrypted = manager.fernet.encrypt(api_key.encode()).decode()
                decrypted = manager.fernet.decrypt(encrypted.encode()).decode()
                assert decrypted == api_key


# =============================================================================
# INTEGRATION TESTS
# =============================================================================

class TestSecretsIntegration:
    """Integration tests for SecretsManager."""
    
    @pytest.mark.integration
    def test_full_encryption_workflow(self, mock_db, tmp_path):
        """Test full encryption workflow for CEX credentials."""
        from cryptography.fernet import Fernet
        
        key = Fernet.generate_key().decode()
        secrets_file = tmp_path / ".farming_secrets"
        secrets_file.write_text(f"FERNET_KEY={key}\n")
        
        with patch('funding.secrets.DatabaseManager', return_value=mock_db):
            from funding.secrets import SecretsManager
            
            manager = SecretsManager(secrets_file=str(secrets_file))
            
            # Simulate storing CEX credentials
            credentials = {
                'binance_api_key': 'binance_key_123',
                'binance_api_secret': 'binance_secret_456',
                'bybit_api_key': 'bybit_key_789',
                'bybit_api_secret': 'bybit_secret_abc',
            }
            
            encrypted_creds = {}
            for name, value in credentials.items():
                encrypted_creds[name] = manager.fernet.encrypt(value.encode()).decode()
            
            # Verify all encrypted
            for name, encrypted in encrypted_creds.items():
                assert encrypted != credentials[name]
            
            # Verify all can be decrypted
            for name, encrypted in encrypted_creds.items():
                decrypted = manager.fernet.decrypt(encrypted.encode()).decode()
                assert decrypted == credentials[name]


# =============================================================================
# RUN TESTS
# =============================================================================

if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
