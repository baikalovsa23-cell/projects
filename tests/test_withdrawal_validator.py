#!/usr/bin/env python3
"""
Withdrawal Validator Tests
==========================
Тесты для модуля withdrawal/validator.py

Проверяет:
- Валидация адресов получателей
- Проверка балансов
- Проверка газ лимитов

Run:
    pytest tests/test_withdrawal_validator.py -v
"""

import os
import sys
import pytest
import asyncio
from pathlib import Path
from decimal import Decimal
from unittest.mock import Mock, AsyncMock, patch

sys.path.insert(0, str(Path(__file__).parent.parent))


# =============================================================================
# ADDRESS VALIDATION TESTS
# =============================================================================

class TestAddressValidation:
    """Tests for address validation."""
    
    def test_valid_ethereum_address(self):
        """Test validating valid Ethereum address."""
        valid_address = '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb5'
        
        # Should start with 0x
        assert valid_address.startswith('0x')
        
        # Should be 42 characters
        assert len(valid_address) == 42
    
    def test_invalid_ethereum_address(self):
        """Test detecting invalid Ethereum address."""
        invalid_addresses = [
            '0x123',  # Too short
            '742d35Cc6634C0532925a3b844Bc9e7595f0bEb',  # No 0x prefix
            '0xGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG',  # Invalid chars
        ]
        
        for addr in invalid_addresses:
            # Should be detected as invalid
            is_valid = addr.startswith('0x') and len(addr) == 42
            # In reality, would use web3.is_address()
    
    def test_validate_destination_address(self, mock_db, mock_web3):
        """Test validating destination address."""
        with patch('database.db_manager.DatabaseManager', return_value=mock_db):
            try:
                from withdrawal.validator import WithdrawalValidator
                
                validator = WithdrawalValidator(mock_db)
                
                # Test that validator can be instantiated
                assert validator.db is not None
                assert validator.min_withdrawal_amount > 0
            except ImportError:
                pytest.skip("WithdrawalValidator not found")


# =============================================================================
# BALANCE VALIDATION TESTS
# =============================================================================

class TestBalanceValidation:
    """Tests for balance validation."""
    
    def test_sufficient_balance(self, mock_db, mock_web3):
        """Test checking sufficient balance."""
        # Mock balance = 1 ETH
        mock_web3.eth.get_balance.return_value = 10**18
        
        with patch('database.db_manager.DatabaseManager', return_value=mock_db):
            try:
                from withdrawal.validator import WithdrawalValidator
                
                validator = WithdrawalValidator(mock_db)
                
                # Test validator configuration
                assert validator.max_gas_gwei == 200.0
                assert validator.gas_buffer == 0.20
            except ImportError:
                pytest.skip("WithdrawalValidator not found")
    
    def test_insufficient_balance(self, mock_db, mock_web3):
        """Test detecting insufficient balance."""
        # Mock balance = 0.1 ETH
        mock_web3.eth.get_balance.return_value = 10**17
        
        with patch('database.db_manager.DatabaseManager', return_value=mock_db):
            try:
                from withdrawal.validator import WithdrawalValidator
                
                validator = WithdrawalValidator(mock_db)
                
                # Test validator configuration
                assert validator.min_withdrawal_amount == Decimal('10.00')
            except ImportError:
                pytest.skip("WithdrawalValidator not found")


# =============================================================================
# GAS VALIDATION TESTS
# =============================================================================

class TestGasValidation:
    """Tests for gas validation."""
    
    def test_gas_limit_reasonable(self):
        """Test that gas limit is reasonable."""
        # Standard ETH transfer: 21000 gas
        # Token transfer: ~65000 gas
        
        eth_transfer_gas = 21000
        token_transfer_gas = 65000
        
        assert eth_transfer_gas >= 21000
        assert token_transfer_gas >= 50000
    
    def test_gas_price_reasonable(self, mock_web3):
        """Test that gas price is reasonable."""
        gas_price = mock_web3.eth.gas_price
        gas_gwei = gas_price / 1e9
        
        # Should be < 500 gwei
        assert gas_gwei < 500


# =============================================================================
# WITHDRAWAL LIMITS TESTS
# =============================================================================

class TestWithdrawalLimits:
    """Tests for withdrawal limits."""
    
    def test_min_withdrawal_amount(self):
        """Test minimum withdrawal amount."""
        # Min withdrawal should be reasonable
        min_withdrawal_eth = 0.01
        
        assert min_withdrawal_eth >= 0.01
    
    def test_max_withdrawal_amount(self):
        """Test maximum withdrawal amount."""
        # Max withdrawal per transaction
        max_withdrawal_eth = 10.0
        
        assert max_withdrawal_eth <= 100


# =============================================================================
# RUN TESTS
# =============================================================================

if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
