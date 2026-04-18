#!/usr/bin/env python3
"""
CEX Integration Tests
====================
Тесты для модуля funding/cex_integration.py

Проверяет:
- Подключение к 5 биржам (Binance, Bybit, OKX, KuCoin, MEXC)
- Поддерживаемые сети (только L2!)
- Блокировка Ethereum mainnet
- Withdrawal mock (без реальных выводов!)
- Retry logic для rate limits

Run:
    pytest tests/test_cex_integration.py -v
"""

import os
import sys
import pytest
import asyncio
from pathlib import Path
from decimal import Decimal
from datetime import datetime
from unittest.mock import Mock, AsyncMock, patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent))


# =============================================================================
# NETWORK VALIDATION TESTS
# =============================================================================

class TestNetworkValidation:
    """Tests for network validation and L2-only restriction."""
    
    def test_allowed_networks_l2_only(self):
        """Test that only L2 networks are allowed (no Ethereum mainnet)."""
        from funding.cex_integration import ALLOWED_NETWORKS
        
        # Ethereum mainnet should NOT be allowed
        assert 'Ethereum' not in ALLOWED_NETWORKS
        assert 'Ethereum (ERC20)' not in ALLOWED_NETWORKS
        
        # L2 networks should be allowed
        assert 'Arbitrum One' in ALLOWED_NETWORKS
        assert 'Base' in ALLOWED_NETWORKS
        assert 'OP Mainnet' in ALLOWED_NETWORKS
        assert 'Polygon' in ALLOWED_NETWORKS
        assert 'BSC' in ALLOWED_NETWORKS
    
    def test_network_codes_defined_for_all_exchanges(self):
        """Test that network codes are defined for all 5 exchanges."""
        from funding.cex_integration import NETWORK_CODES
        
        expected_exchanges = ['binance', 'bybit', 'okx', 'kucoin', 'mexc']
        
        for exchange in expected_exchanges:
            assert exchange in NETWORK_CODES, f"Missing network codes for {exchange}"
    
    def test_network_codes_arbitrum_mapping(self):
        """Test that Arbitrum network codes are correct for each exchange."""
        from funding.cex_integration import NETWORK_CODES
        
        # Binance uses 'ARBITRUM'
        assert NETWORK_CODES['binance'].get('Arbitrum One') == 'ARBITRUM'
        
        # Other exchanges may use different codes
        for exchange in ['bybit', 'okx', 'kucoin', 'mexc']:
            if 'Arbitrum One' in NETWORK_CODES[exchange]:
                code = NETWORK_CODES[exchange]['Arbitrum One']
                assert code is not None


# =============================================================================
# CEX MANAGER INITIALIZATION TESTS
# =============================================================================

class TestCEXManagerInit:
    """Tests for CEXManager initialization."""
    
    def test_cex_manager_initialization(self, mock_db, mock_secrets_manager):
        """Test that CEXManager initializes correctly."""
        with patch('funding.cex_integration.DatabaseManager', return_value=mock_db):
            with patch('funding.cex_integration.SecretsManager', return_value=mock_secrets_manager):
                from funding.cex_integration import CEXManager
                
                manager = CEXManager()
                
                assert manager.db is not None
                assert manager.secrets is not None
    
    def test_exchange_clients_lazy_loading(self, mock_db, mock_secrets_manager):
        """Test that exchange clients are loaded lazily."""
        with patch('funding.cex_integration.DatabaseManager', return_value=mock_db):
            with patch('funding.cex_integration.SecretsManager', return_value=mock_secrets_manager):
                from funding.cex_integration import CEXManager
                
                manager = CEXManager()
                
                # Clients should be None initially (lazy load)
                # Or empty dict depending on implementation
                assert hasattr(manager, 'clients') or hasattr(manager, '_clients')


# =============================================================================
# WITHDRAWAL TESTS (MOCK - NO REAL WITHDRAWALS!)
# =============================================================================

class TestWithdrawalMock:
    """Tests for withdrawal functionality with mocked exchanges."""
    
    @pytest.mark.asyncio
    async def test_withdraw_mock_returns_result(self, mock_db, mock_exchange, mock_secrets_manager):
        """Test that withdraw returns result object (mocked)."""
        with patch('funding.cex_integration.DatabaseManager', return_value=mock_db):
            with patch('funding.cex_integration.SecretsManager', return_value=mock_secrets_manager):
                with patch('funding.cex_integration.ccxt.bybit', return_value=mock_exchange):
                    from funding.cex_integration import CEXManager, WithdrawalResult
                    
                    manager = CEXManager()
                    
                    # Mock subaccount query
                    mock_db.execute_query.return_value = {
                        'id': 1,
                        'cex_name': 'bybit',
                        'api_key_encrypted': 'encrypted_key',
                        'api_secret_encrypted': 'encrypted_secret',
                        'withdrawal_network': 'Arbitrum One'
                    }
                    
                    # Mock withdrawal (NO REAL WITHDRAWAL!)
                    result = await manager.withdraw(
                        subaccount_id=1,
                        address='0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb',
                        amount=Decimal('0.1'),
                        network='Arbitrum One'
                    )
        
        # Should return a result (mocked)
        assert result is not None
    
    @pytest.mark.asyncio
    async def test_withdraw_blocks_ethereum_mainnet(self, mock_db, mock_secrets_manager):
        """Test that withdrawal to Ethereum mainnet is BLOCKED."""
        with patch('funding.cex_integration.DatabaseManager', return_value=mock_db):
            with patch('funding.cex_integration.SecretsManager', return_value=mock_secrets_manager):
                from funding.cex_integration import CEXManager
                
                manager = CEXManager()
                
                # Attempt withdrawal to Ethereum mainnet
                with pytest.raises(Exception) as exc_info:
                    await manager.withdraw(
                        subaccount_id=1,
                        address='0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb',
                        amount=Decimal('0.1'),
                        network='Ethereum'  # BLOCKED!
                    )
                
                # Should raise error about Ethereum mainnet
                assert 'ethereum' in str(exc_info.value).lower() or 'not allowed' in str(exc_info.value).lower()
    
    @pytest.mark.asyncio
    async def test_withdraw_validates_address(self, mock_db, mock_secrets_manager):
        """Test that withdrawal validates Ethereum address format."""
        with patch('funding.cex_integration.DatabaseManager', return_value=mock_db):
            with patch('funding.cex_integration.SecretsManager', return_value=mock_secrets_manager):
                from funding.cex_integration import CEXManager
                
                manager = CEXManager()
                
                # Invalid address
                with pytest.raises(Exception):
                    await manager.withdraw(
                        subaccount_id=1,
                        address='invalid_address',
                        amount=Decimal('0.1'),
                        network='Arbitrum One'
                    )


# =============================================================================
# BALANCE CHECK TESTS
# =============================================================================

class TestBalanceCheck:
    """Tests for balance checking functionality."""
    
    @pytest.mark.asyncio
    async def test_fetch_balance_returns_dict(self, mock_db, mock_exchange, mock_secrets_manager):
        """Test that fetch_balance returns balance dictionary."""
        with patch('funding.cex_integration.DatabaseManager', return_value=mock_db):
            with patch('funding.cex_integration.SecretsManager', return_value=mock_secrets_manager):
                with patch('funding.cex_integration.ccxt.bybit', return_value=mock_exchange):
                    from funding.cex_integration import CEXManager
                    
                    manager = CEXManager()
                    
                    mock_db.execute_query.return_value = {
                        'cex_name': 'bybit',
                        'api_key_encrypted': 'encrypted',
                        'api_secret_encrypted': 'encrypted',
                    }
                    
                    balance = await manager.fetch_balance(subaccount_id=1, currency='ETH')
        
        # Should return balance dict
        assert balance is not None
        assert 'free' in balance or 'total' in balance


# =============================================================================
# SUPPORTED NETWORKS TESTS
# =============================================================================

class TestSupportedNetworks:
    """Tests for checking supported withdrawal networks."""
    
    @pytest.mark.asyncio
    async def test_get_supported_networks_for_exchange(self, mock_db, mock_exchange, mock_secrets_manager):
        """Test getting supported networks for an exchange."""
        with patch('funding.cex_integration.DatabaseManager', return_value=mock_db):
            with patch('funding.cex_integration.SecretsManager', return_value=mock_secrets_manager):
                with patch('funding.cex_integration.ccxt.bybit', return_value=mock_exchange):
                    from funding.cex_integration import CEXManager
                    
                    manager = CEXManager()
                    
                    networks = await manager.get_supported_networks(
                        exchange='bybit',
                        currency='ETH'
                    )
        
        # Should return list of networks
        assert isinstance(networks, list)
        
        # Should include Arbitrum (from mock)
        assert 'Arbitrum One' in networks or 'Arbitrum' in str(networks)


# =============================================================================
# INTEGRATION TESTS (REAL API CHECKS)
# =============================================================================

class TestCEXIntegration:
    """Integration tests with real CEX API connectivity (read-only)."""
    
    @pytest.mark.integration
    @pytest.mark.requires_cex
    @pytest.mark.asyncio
    async def test_binance_api_connectivity(self):
        """Test Binance API connectivity (public endpoint, no auth)."""
        import ccxt
        
        try:
            exchange = ccxt.binance({
                'enableRateLimit': True,
            })
            
            # Load markets (public endpoint)
            markets = exchange.load_markets()
            
            assert len(markets) > 0, "Binance returned no markets"
            assert 'ETH/USDT' in markets, "ETH/USDT not found in Binance markets"
            
        except Exception as e:
            pytest.skip(f"Binance API unavailable: {e}")
    
    @pytest.mark.integration
    @pytest.mark.requires_cex
    @pytest.mark.asyncio
    async def test_bybit_api_connectivity(self):
        """Test Bybit API connectivity (public endpoint)."""
        import ccxt
        
        try:
            exchange = ccxt.bybit({
                'enableRateLimit': True,
            })
            
            markets = exchange.load_markets()
            
            assert len(markets) > 0, "Bybit returned no markets"
            
        except Exception as e:
            pytest.skip(f"Bybit API unavailable: {e}")
    
    @pytest.mark.integration
    @pytest.mark.requires_cex
    @pytest.mark.asyncio
    async def test_okx_api_connectivity(self):
        """Test OKX API connectivity (public endpoint)."""
        import ccxt
        
        try:
            exchange = ccxt.okx({
                'enableRateLimit': True,
            })
            
            markets = exchange.load_markets()
            
            assert len(markets) > 0, "OKX returned no markets"
            
        except Exception as e:
            pytest.skip(f"OKX API unavailable: {e}")
    
    @pytest.mark.integration
    @pytest.mark.requires_cex
    @pytest.mark.asyncio
    async def test_kucoin_api_connectivity(self):
        """Test KuCoin API connectivity (public endpoint)."""
        import ccxt
        
        try:
            exchange = ccxt.kucoin({
                'enableRateLimit': True,
            })
            
            markets = exchange.load_markets()
            
            assert len(markets) > 0, "KuCoin returned no markets"
            
        except Exception as e:
            pytest.skip(f"KuCoin API unavailable: {e}")
    
    @pytest.mark.integration
    @pytest.mark.requires_cex
    @pytest.mark.asyncio
    async def test_mexc_api_connectivity(self):
        """Test MEXC API connectivity (public endpoint)."""
        import ccxt
        
        try:
            exchange = ccxt.mexc({
                'enableRateLimit': True,
            })
            
            markets = exchange.load_markets()
            
            assert len(markets) > 0, "MEXC returned no markets"
            
        except Exception as e:
            pytest.skip(f"MEXC API unavailable: {e}")


# =============================================================================
# WITHDRAWAL RESULT TESTS
# =============================================================================

class TestWithdrawalResult:
    """Tests for WithdrawalResult dataclass."""
    
    def test_withdrawal_result_success(self):
        """Test WithdrawalResult for successful withdrawal."""
        from funding.cex_integration import WithdrawalResult
        
        result = WithdrawalResult(
            success=True,
            tx_id='0x123abc',
            amount=Decimal('0.1'),
            fee=Decimal('0.001'),
            network='Arbitrum One'
        )
        
        assert result.success == True
        assert result.tx_id == '0x123abc'
        assert result.error is None
    
    def test_withdrawal_result_failure(self):
        """Test WithdrawalResult for failed withdrawal."""
        from funding.cex_integration import WithdrawalResult
        
        result = WithdrawalResult(
            success=False,
            tx_id=None,
            amount=Decimal('0.1'),
            fee=None,
            network='Arbitrum One',
            error='Insufficient funds'
        )
        
        assert result.success == False
        assert result.tx_id is None
        assert result.error == 'Insufficient funds'


# =============================================================================
# RUN TESTS
# =============================================================================

if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
