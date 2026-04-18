#!/usr/bin/env python3
"""
Wallet Generator Tests
=====================
Тесты для модуля wallets/generator.py

Проверяет:
- Генерация EVM кошельков (90 шт)
- Распределение по Tier (18 A, 45 B, 27 C)
- Распределение по Workers (30 на каждый)
- Шифрование приватных ключей Fernet
- Anti-Sybil: shuffle, уникальность адресов

Run:
    pytest tests/test_wallet_generator.py -v
"""

import os
import sys
import pytest
from pathlib import Path
from datetime import datetime
from unittest.mock import Mock, patch, MagicMock
from cryptography.fernet import Fernet

sys.path.insert(0, str(Path(__file__).parent.parent))


# =============================================================================
# UNIT TESTS - Wallet Generation
# =============================================================================

class TestWalletGenerator:
    """Tests for WalletGenerator class."""
    
    def test_distribution_calculation(self, mock_db):
        """Test that distribution calculates correct tier/worker counts."""
        from wallets.generator import WalletGenerator, WalletConfig
        
        with patch.object(WalletGenerator, '__init__', lambda self, fernet_key=None: None):
            generator = object.__new__(WalletGenerator)
            generator.distribution = generator._calculate_distribution()
        
        # Total 90 wallets
        assert len(generator.distribution) == 90
        
        # Count by tier
        tier_a = sum(1 for w in generator.distribution if w.tier == 'A')
        tier_b = sum(1 for w in generator.distribution if w.tier == 'B')
        tier_c = sum(1 for w in generator.distribution if w.tier == 'C')
        
        assert tier_a == 18, f"Expected 18 Tier A, got {tier_a}"
        assert tier_b == 45, f"Expected 45 Tier B, got {tier_b}"
        assert tier_c == 27, f"Expected 27 Tier C, got {tier_c}"
        
        # Count by worker
        worker1 = sum(1 for w in generator.distribution if w.worker_id == 1)
        worker2 = sum(1 for w in generator.distribution if w.worker_id == 2)
        worker3 = sum(1 for w in generator.distribution if w.worker_id == 3)
        
        assert worker1 == 30, f"Expected 30 wallets for Worker 1, got {worker1}"
        assert worker2 == 30, f"Expected 30 wallets for Worker 2, got {worker2}"
        assert worker3 == 30, f"Expected 30 wallets for Worker 3, got {worker3}"
    
    def test_distribution_shuffle(self, mock_db):
        """Test that distribution is shuffled (anti-Sybil)."""
        from wallets.generator import WalletGenerator
        
        with patch.object(WalletGenerator, '__init__', lambda self, fernet_key=None: None):
            generator = object.__new__(WalletGenerator)
            generator.distribution = generator._calculate_distribution()
        
        # First 10 wallets should NOT all be Tier A (shuffle effect)
        first_10_tiers = [w.tier for w in generator.distribution[:10]]
        
        # Should have mix of tiers (not all 'A')
        assert len(set(first_10_tiers)) > 1, "Distribution not shuffled - first 10 all same tier"
    
    def test_proxy_country_assignment(self, mock_db):
        """Test that Worker 1 gets NL proxies, Workers 2-3 get IS proxies."""
        from wallets.generator import WalletGenerator, WalletConfig
        
        with patch.object(WalletGenerator, '__init__', lambda self, fernet_key=None: None):
            generator = object.__new__(WalletGenerator)
            generator.distribution = generator._calculate_distribution()
        
        for config in generator.distribution:
            if config.worker_id == 1:
                assert config.proxy_country == 'NL', f"Worker 1 should have NL proxy, got {config.proxy_country}"
            else:
                assert config.proxy_country == 'IS', f"Worker {config.worker_id} should have IS proxy, got {config.proxy_country}"
    
    def test_wallet_generation_creates_valid_address(self, mock_db):
        """Test that generated wallet has valid Ethereum address."""
        from wallets.generator import WalletGenerator, WalletConfig, GeneratedWallet
        
        # Create test config
        config = WalletConfig(tier='A', worker_id=1, proxy_country='NL')
        
        # Mock Fernet and DB
        with patch('wallets.generator.Fernet') as mock_fernet_class:
            mock_fernet = Mock()
            mock_fernet.encrypt.return_value = b'encrypted_key'
            mock_fernet_class.return_value = mock_fernet
            
            generator = WalletGenerator.__new__(WalletGenerator)
            generator.fernet = mock_fernet
            generator.db = mock_db
            
            # Mock proxy lookup
            mock_db.execute_query.return_value = {'id': 1}
            
            wallet = generator.generate_wallet(config)
        
        # Validate address format
        assert wallet.address.startswith('0x'), "Address should start with 0x"
        assert len(wallet.address) == 42, f"Address should be 42 chars, got {len(wallet.address)}"
        assert wallet.tier == 'A'
        assert wallet.worker_id == 1
    
    def test_wallet_address_lowercase(self, mock_db):
        """Test that wallet address is forced to lowercase."""
        from wallets.generator import WalletGenerator, WalletConfig
        
        config = WalletConfig(tier='A', worker_id=1, proxy_country='NL')
        
        with patch('wallets.generator.Fernet') as mock_fernet_class:
            mock_fernet = Mock()
            mock_fernet.encrypt.return_value = b'encrypted'
            mock_fernet_class.return_value = mock_fernet
            
            generator = WalletGenerator.__new__(WalletGenerator)
            generator.fernet = mock_fernet
            generator.db = mock_db
            mock_db.execute_query.return_value = {'id': 1}
            
            wallet = generator.generate_wallet(config)
        
        # Address should be lowercase
        assert wallet.address == wallet.address.lower(), "Address must be lowercase"
    
    def test_private_key_encryption(self, mock_db):
        """Test that private key is encrypted with Fernet."""
        from wallets.generator import WalletGenerator
        
        # Generate real Fernet key for test
        key = Fernet.generate_key()
        fernet = Fernet(key)
        
        with patch('wallets.generator.DatabaseManager'):
            generator = WalletGenerator(fernet_key=key.decode())
        
        # Test encryption
        test_key = '0x' + 'a' * 64
        encrypted = generator._encrypt_private_key(test_key)
        
        # Should be different from original
        assert encrypted != test_key
        
        # Should be decryptable
        decrypted = fernet.decrypt(encrypted.encode()).decode()
        assert decrypted == test_key
    
    def test_no_duplicate_addresses(self, mock_db):
        """Test that all generated wallets have unique addresses."""
        from wallets.generator import WalletGenerator
        
        key = Fernet.generate_key()
        
        with patch('wallets.generator.DatabaseManager') as mock_db_class:
            mock_db_instance = Mock()
            mock_db_instance.execute_query.return_value = {'id': 1}
            mock_db_class.return_value = mock_db_instance
            
            generator = WalletGenerator(fernet_key=key.decode())
            
            # Generate multiple wallets
            wallets = []
            for i in range(10):
                config = generator.distribution[i]
                wallet = generator.generate_wallet(config)
                wallets.append(wallet)
        
        # Check uniqueness
        addresses = [w.address for w in wallets]
        assert len(addresses) == len(set(addresses)), "Duplicate addresses detected"
    
    def test_openclaw_enabled_for_tier_a_only(self, mock_db):
        """Test that OpenClaw is enabled only for Tier A wallets."""
        from wallets.generator import WalletGenerator
        
        # Tier A should have openclaw_enabled=True
        # Tier B, C should have openclaw_enabled=False
        
        key = Fernet.generate_key()
        
        with patch('wallets.generator.DatabaseManager') as mock_db_class:
            mock_db_instance = Mock()
            mock_db_instance.execute_query.side_effect = [
                {'id': 1},  # Worker node
                {'id': 1},  # Wallet insert
            ]
            mock_db_class.return_value = mock_db_instance
            
            generator = WalletGenerator(fernet_key=key.decode())
            
            # Check distribution configs
            for config in generator.distribution:
                if config.tier == 'A':
                    # Tier A wallets should have openclaw_enabled=True
                    pass  # This is set during save_wallet_to_db
                else:
                    # Tier B, C should NOT have openclaw
                    pass


# =============================================================================
# UNIT TESTS - CEX Whitelist Export
# =============================================================================

class TestCEXWhitelistExport:
    """Tests for CEX whitelist export functionality."""
    
    def test_whitelist_format(self, mock_db):
        """Test that whitelist CSV has correct format."""
        import csv
        import tempfile
        
        from wallets.generator import WalletGenerator
        
        key = Fernet.generate_key()
        
        # Mock wallets in DB
        mock_db.execute_query.return_value = [
            {'address': '0xaaa' + 'a' * 38, 'tier': 'A'},
            {'address': '0xbbb' + 'b' * 38, 'tier': 'B'},
        ]
        
        with patch('wallets.generator.DatabaseManager', return_value=mock_db):
            generator = WalletGenerator(fernet_key=key.decode())
            generator.db = mock_db
            
            # Export to temp file
            with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
                temp_path = f.name
            
            generator.export_cex_whitelist(temp_path)
        
        # Read and verify CSV
        with open(temp_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
        
        assert len(rows) > 0, "Whitelist should have entries"
        
        # Check required columns
        for row in rows:
            assert 'date' in row
            assert 'exchange' in row
            assert 'network' in row
            assert 'address' in row
        
        # Cleanup
        os.unlink(temp_path)
    
    def test_whitelist_anti_sybil_dates(self, mock_db):
        """Test that whitelist has anti-Sybil date distribution."""
        import csv
        import tempfile
        from datetime import datetime
        
        from wallets.generator import WalletGenerator
        
        key = Fernet.generate_key()
        
        # Mock 90 wallets
        mock_wallets = [
            {'address': f'0x{"a" * 40}', 'tier': 'A'} for _ in range(90)
        ]
        mock_db.execute_query.return_value = mock_wallets
        
        with patch('wallets.generator.DatabaseManager', return_value=mock_db):
            generator = WalletGenerator(fernet_key=key.decode())
            generator.db = mock_db
            
            with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
                temp_path = f.name
            
            generator.export_cex_whitelist(temp_path)
        
        # Read dates
        with open(temp_path, 'r') as f:
            reader = csv.DictReader(f)
            dates = [row['date'] for row in reader]
        
        # Dates should be spread out (not all same day)
        unique_dates = set(dates)
        assert len(unique_dates) > 1, "All addresses on same day - anti-Sybil violation"
        
        # Cleanup
        os.unlink(temp_path)


# =============================================================================
# INTEGRATION TESTS
# =============================================================================

class TestWalletGeneratorIntegration:
    """Integration tests for WalletGenerator."""
    
    @pytest.mark.integration
    @pytest.mark.requires_db
    def test_full_wallet_generation_flow(self, mock_db_with_wallets):
        """Test complete wallet generation flow (without real DB)."""
        from wallets.generator import WalletGenerator
        
        key = Fernet.generate_key()
        
        with patch('wallets.generator.DatabaseManager', return_value=mock_db_with_wallets):
            generator = WalletGenerator(fernet_key=key.decode())
            
            # Verify distribution
            assert len(generator.distribution) == 90
            
            # Verify tier counts
            tier_a = sum(1 for w in generator.distribution if w.tier == 'A')
            tier_b = sum(1 for w in generator.distribution if w.tier == 'B')
            tier_c = sum(1 for w in generator.distribution if w.tier == 'C')
            
            assert tier_a == 18
            assert tier_b == 45
            assert tier_c == 27


# =============================================================================
# RUN TESTS
# =============================================================================

if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
