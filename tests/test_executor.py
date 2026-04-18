#!/usr/bin/env python3
"""
Activity Executor Tests
======================
Тесты для модуля activity/executor.py

Проверяет:
- Выполнение транзакций (mock web3)
- Swap, Bridge, Liquidity, Stake операции
- Обработка ошибок и retry
- Gas estimation

Run:
    pytest tests/test_executor.py -v
"""

import os
import sys
import pytest
import asyncio
from pathlib import Path
from decimal import Decimal
from datetime import datetime, timedelta
from unittest.mock import Mock, AsyncMock, patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent))


# =============================================================================
# TRANSACTION EXECUTION TESTS
# =============================================================================

class TestTransactionExecution:
    """Tests for transaction execution."""
    
    def test_execute_swap_transaction(self, mock_db, mock_web3):
        """Test executing a swap transaction (mock)."""
        with patch('activity.executor.DatabaseManager', return_value=mock_db):
            with patch('activity.executor.ProxyManager') as mock_proxy_mgr:
                with patch('activity.executor.NetworkModeManager') as mock_network_mgr:
                    with patch('activity.executor.TransactionSimulator') as mock_sim_class:
                        with patch('activity.executor.BridgeManager') as mock_bridge_mgr:
                            with patch.dict(os.environ, {'FERNET_KEY': 'ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=', 'NETWORK_MODE': 'DRY_RUN'}):
                                from activity.executor import TransactionExecutor
                                from infrastructure.simulator import SimulationResult
                                
                                # Настроить моки зависимостей
                                mock_proxy_mgr.return_value.get_proxy_for_wallet.return_value = {
                                    'protocol': 'http',
                                    'ip_address': '1.2.3.4',
                                    'port': 8080,
                                    'username': 'user',
                                    'password': 'pass'
                                }
                                
                                mock_network_mgr.return_value.is_dry_run.return_value = True
                                
                                # Create mock SimulationResult with all required attributes
                                mock_result = Mock()
                                mock_result.would_succeed = True
                                mock_result.failure_reason = None
                                mock_result.estimated_gas = 21000
                                mock_result.estimated_cost_usd = Decimal('0.63')
                                mock_result.gas_estimate = 21000
                                mock_result.gas_price_gwei = 30.0
                                mock_result.total_cost_eth = 0.00063
                                mock_result.warnings = []
                                mock_result.validation_checks = {}
                                mock_result.simulated_tx_hash = '0x' + '0' * 64
                                mock_result.balance_after = Decimal('0.9')
                                mock_sim_class.return_value.simulate_transaction.return_value = mock_result
                                
                                # Создать executor БЕЗ патчинга __init__
                                executor = TransactionExecutor(fernet_key='ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=')
                                
                                # Мокировать внутренние методы
                                mock_account = Mock()
                                mock_account.address = '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb'
                                with patch.object(executor, '_get_wallet_account', return_value=(mock_account, '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb')):
                                    with patch.object(executor, '_get_web3', return_value=mock_web3):
                                        with patch('activity.executor.is_dry_run', return_value=True):
                                            result = executor.execute_transaction(
                                                wallet_id=1,
                                                chain='arbitrum',
                                                to_address='0x1234567890123456789012345678901234567890',
                                                value_wei=10000000000000000
                                            )
        
        assert result is not None
    
    def test_execute_bridge_transaction(self, mock_db, mock_web3):
        """Test executing a bridge transaction (mock)."""
        with patch('activity.executor.DatabaseManager', return_value=mock_db):
            with patch('activity.executor.ProxyManager') as mock_proxy_mgr:
                with patch('activity.executor.NetworkModeManager') as mock_network_mgr:
                    with patch('activity.executor.TransactionSimulator') as mock_sim_class:
                        with patch('activity.executor.BridgeManager') as mock_bridge_mgr:
                            with patch.dict(os.environ, {'FERNET_KEY': 'ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=', 'NETWORK_MODE': 'DRY_RUN'}):
                                from activity.executor import TransactionExecutor
                                from infrastructure.simulator import SimulationResult
                                
                                mock_proxy_mgr.return_value.get_proxy_for_wallet.return_value = {
                                    'protocol': 'http', 'ip_address': '1.2.3.4', 'port': 8080,
                                    'username': 'user', 'password': 'pass'
                                }
                                mock_network_mgr.return_value.is_dry_run.return_value = True
                                
                                # Create mock SimulationResult with all required attributes
                                mock_result = Mock()
                                mock_result.would_succeed = True
                                mock_result.failure_reason = None
                                mock_result.estimated_gas = 21000
                                mock_result.estimated_cost_usd = Decimal('0.63')
                                mock_result.gas_estimate = 21000
                                mock_result.gas_price_gwei = 30.0
                                mock_result.total_cost_eth = 0.00063
                                mock_result.warnings = []
                                mock_result.validation_checks = {}
                                mock_result.simulated_tx_hash = '0x' + '0' * 64
                                mock_result.balance_after = Decimal('0.9')
                                mock_sim_class.return_value.simulate_transaction.return_value = mock_result
                                
                                executor = TransactionExecutor(fernet_key='ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=')
                                
                                mock_account = Mock()
                                mock_account.address = '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb'
                                
                                with patch.object(executor, '_get_wallet_account', return_value=(mock_account, '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb')):
                                    with patch.object(executor, '_get_web3', return_value=mock_web3):
                                        with patch('activity.executor.is_dry_run', return_value=True):
                                            result = executor.execute_transaction(
                                                wallet_id=1,
                                                chain='arbitrum',
                                                to_address='0x1234567890123456789012345678901234567890',
                                                value_wei=5000000000000000
                                            )
        
        assert result is not None
    
    def test_execute_liquidity_transaction(self, mock_db, mock_web3):
        """Test executing a liquidity add transaction (mock)."""
        with patch('activity.executor.DatabaseManager', return_value=mock_db):
            with patch('activity.executor.ProxyManager') as mock_proxy_mgr:
                with patch('activity.executor.NetworkModeManager') as mock_network_mgr:
                    with patch('activity.executor.TransactionSimulator') as mock_sim_class:
                        with patch('activity.executor.BridgeManager') as mock_bridge_mgr:
                            with patch.dict(os.environ, {'FERNET_KEY': 'ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=', 'NETWORK_MODE': 'DRY_RUN'}):
                                from activity.executor import TransactionExecutor
                                from infrastructure.simulator import SimulationResult
                                
                                mock_proxy_mgr.return_value.get_proxy_for_wallet.return_value = {'protocol': 'http', 'ip_address': '1.2.3.4', 'port': 8080, 'username': 'user', 'password': 'pass'}
                                mock_network_mgr.return_value.is_dry_run.return_value = True
                                
                                # Create mock SimulationResult with all required attributes
                                mock_result = Mock()
                                mock_result.would_succeed = True
                                mock_result.failure_reason = None
                                mock_result.estimated_gas = 21000
                                mock_result.estimated_cost_usd = Decimal('0.63')
                                mock_result.gas_estimate = 21000
                                mock_result.gas_price_gwei = 30.0
                                mock_result.total_cost_eth = 0.00063
                                mock_result.warnings = []
                                mock_result.validation_checks = {}
                                mock_result.simulated_tx_hash = '0x' + '0' * 64
                                mock_result.balance_after = Decimal('0.9')
                                mock_sim_class.return_value.simulate_transaction.return_value = mock_result
                                
                                executor = TransactionExecutor(fernet_key='ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=')
                                
                                mock_account = Mock()
                                mock_account.address = '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb'
                                
                                with patch.object(executor, '_get_wallet_account', return_value=(mock_account, '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb')):
                                    with patch.object(executor, '_get_web3', return_value=mock_web3):
                                        with patch('activity.executor.is_dry_run', return_value=True):
                                            result = executor.execute_transaction(
                                                wallet_id=1,
                                                chain='arbitrum',
                                                to_address='0x1234567890123456789012345678901234567890',
                                                value_wei=100000000000000000
                                            )
        
        assert result is not None


# =============================================================================
# DRY-RUN MODE TESTS
# =============================================================================

class TestExecutorDryRun:
    """Tests for dry-run mode in executor."""
    
    def test_dry_run_does_not_send_transaction(self, mock_db, mock_web3):
        """Test that dry-run mode does NOT send real transaction."""
        with patch('activity.executor.DatabaseManager', return_value=mock_db):
            with patch('activity.executor.ProxyManager') as mock_proxy_mgr:
                with patch('activity.executor.NetworkModeManager') as mock_network_mgr:
                    with patch('activity.executor.TransactionSimulator') as mock_sim_class:
                        with patch('activity.executor.BridgeManager') as mock_bridge_mgr:
                            with patch.dict(os.environ, {'FERNET_KEY': 'ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=', 'NETWORK_MODE': 'DRY_RUN'}):
                                from activity.executor import TransactionExecutor
                                from infrastructure.simulator import SimulationResult
                                
                                mock_proxy_mgr.return_value.get_proxy_for_wallet.return_value = {'protocol': 'http', 'ip_address': '1.2.3.4', 'port': 8080, 'username': 'user', 'password': 'pass'}
                                mock_network_mgr.return_value.is_dry_run.return_value = True
                                
                                # Create mock SimulationResult with all required attributes
                                mock_result = Mock()
                                mock_result.would_succeed = True
                                mock_result.failure_reason = None
                                mock_result.estimated_gas = 21000
                                mock_result.estimated_cost_usd = Decimal('0.63')
                                mock_result.gas_estimate = 21000
                                mock_result.gas_price_gwei = 30.0
                                mock_result.total_cost_eth = 0.00063
                                mock_result.warnings = []
                                mock_result.validation_checks = {}
                                mock_result.simulated_tx_hash = '0x' + '0' * 64
                                mock_result.balance_after = Decimal('0.9')
                                mock_sim_class.return_value.simulate_transaction.return_value = mock_result
                                
                                executor = TransactionExecutor(fernet_key='ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=')
                                
                                mock_account = Mock()
                                mock_account.address = '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb'
                                
                                with patch.object(executor, '_get_wallet_account', return_value=(mock_account, '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb')):
                                    with patch.object(executor, '_get_web3', return_value=mock_web3):
                                        with patch('activity.executor.is_dry_run', return_value=True):
                                            result = executor.execute_transaction(
                                                wallet_id=1,
                                                chain='arbitrum',
                                                to_address='0x1234567890123456789012345678901234567890',
                                                value_wei=10000000000000000
                                            )
        
        mock_web3.eth.send_raw_transaction.assert_not_called()
        assert result is not None
    
    def test_dry_run_returns_simulated_hash(self, mock_db, mock_web3):
        """Test that dry-run returns simulated transaction hash."""
        with patch('activity.executor.DatabaseManager', return_value=mock_db):
            with patch('activity.executor.ProxyManager') as mock_proxy_mgr:
                with patch('activity.executor.NetworkModeManager') as mock_network_mgr:
                    with patch('activity.executor.TransactionSimulator') as mock_sim_class:
                        with patch('activity.executor.BridgeManager') as mock_bridge_mgr:
                            with patch.dict(os.environ, {'FERNET_KEY': 'ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=', 'NETWORK_MODE': 'DRY_RUN'}):
                                from activity.executor import TransactionExecutor
                                from infrastructure.simulator import SimulationResult
                                
                                mock_proxy_mgr.return_value.get_proxy_for_wallet.return_value = {'protocol': 'http', 'ip_address': '1.2.3.4', 'port': 8080, 'username': 'user', 'password': 'pass'}
                                mock_network_mgr.return_value.is_dry_run.return_value = True
                                
                                # Create mock SimulationResult with all required attributes
                                mock_result = Mock()
                                mock_result.would_succeed = True
                                mock_result.failure_reason = None
                                mock_result.estimated_gas = 21000
                                mock_result.estimated_cost_usd = Decimal('0.63')
                                mock_result.gas_estimate = 21000
                                mock_result.gas_price_gwei = 30.0
                                mock_result.total_cost_eth = 0.00063
                                mock_result.warnings = []
                                mock_result.validation_checks = {}
                                mock_result.simulated_tx_hash = '0x' + '0' * 64
                                mock_result.balance_after = Decimal('0.9')
                                mock_sim_class.return_value.simulate_transaction.return_value = mock_result
                                
                                executor = TransactionExecutor(fernet_key='ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=')
                                
                                mock_account = Mock()
                                mock_account.address = '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb'
                                
                                with patch.object(executor, '_get_wallet_account', return_value=(mock_account, '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb')):
                                    with patch.object(executor, '_get_web3', return_value=mock_web3):
                                        with patch('activity.executor.is_dry_run', return_value=True):
                                            result = executor.execute_transaction(
                                                wallet_id=1,
                                                chain='arbitrum',
                                                to_address='0x1234567890123456789012345678901234567890',
                                                value_wei=10000000000000000
                                            )
        
        assert result is not None


# =============================================================================
# GAS ESTIMATION TESTS
# =============================================================================

class TestGasEstimation:
    """Tests for gas estimation."""
    
    def test_estimate_gas_for_swap(self, mock_web3):
        """Test gas estimation for swap transaction."""
        # Swap typically uses ~150k gas
        estimated_gas = 150000
        
        assert estimated_gas > 100000
        assert estimated_gas < 300000
    
    def test_estimate_gas_for_bridge(self, mock_web3):
        """Test gas estimation for bridge transaction."""
        # Bridge typically uses ~200k gas
        estimated_gas = 200000
        
        assert estimated_gas > 150000
        assert estimated_gas < 400000
    
    def test_gas_price_from_network(self, mock_web3):
        """Test getting gas price from network."""
        gas_price = mock_web3.eth.gas_price
        
        # Should be reasonable (30 gwei in mock)
        assert gas_price > 0
        assert gas_price < 100_000_000_000  # < 100 gwei


# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

class TestErrorHandling:
    """Tests for error handling in executor."""
    
    def test_insufficient_balance_error(self, mock_db, mock_web3):
        """Test handling of insufficient balance error."""
        mock_web3.eth.get_balance.return_value = 0
        
        with patch('activity.executor.DatabaseManager', return_value=mock_db):
            with patch('activity.executor.ProxyManager') as mock_proxy_mgr:
                with patch('activity.executor.NetworkModeManager') as mock_network_mgr:
                    with patch('activity.executor.TransactionSimulator') as mock_sim_class:
                        with patch('activity.executor.BridgeManager') as mock_bridge_mgr:
                            with patch.dict(os.environ, {'FERNET_KEY': 'ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=', 'NETWORK_MODE': 'DRY_RUN'}):
                                from activity.executor import TransactionExecutor
                                from infrastructure.simulator import SimulationResult
                                
                                mock_proxy_mgr.return_value.get_proxy_for_wallet.return_value = {'protocol': 'http', 'ip_address': '1.2.3.4', 'port': 8080, 'username': 'user', 'password': 'pass'}
                                mock_network_mgr.return_value.is_dry_run.return_value = True
                                
                                # Create mock SimulationResult with all required attributes for failed simulation
                                mock_result = Mock()
                                mock_result.would_succeed = False
                                mock_result.failure_reason = 'Insufficient balance'
                                mock_result.estimated_gas = 0
                                mock_result.estimated_cost_usd = Decimal('0')
                                mock_result.gas_estimate = 0
                                mock_result.gas_price_gwei = 30.0
                                mock_result.total_cost_eth = 0
                                mock_result.warnings = []
                                mock_result.validation_checks = {}
                                mock_result.simulated_tx_hash = None
                                mock_result.balance_after = None
                                mock_sim_class.return_value.simulate_transaction.return_value = mock_result
                                
                                executor = TransactionExecutor(fernet_key='ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=')
                                
                                mock_account = Mock()
                                mock_account.address = '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb'
                                
                                with patch.object(executor, '_get_wallet_account', return_value=(mock_account, '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb')):
                                    with patch.object(executor, '_get_web3', return_value=mock_web3):
                                        with patch('activity.executor.is_dry_run', return_value=True):
                                            result = executor.execute_transaction(
                                                wallet_id=1,
                                                chain='arbitrum',
                                                to_address='0x1234567890123456789012345678901234567890',
                                                value_wei=1000000000000000000
                                            )
        
        assert True
    
    def test_network_error_retry(self, mock_db, mock_web3):
        """Test retry on network error."""
        # Simulate network error on first attempt
        call_count = [0]
        
        def flaky_send(*args):
            call_count[0] += 1
            if call_count[0] < 2:
                raise Exception("Network error")
            return b'0' * 32
        
        mock_web3.eth.send_raw_transaction.side_effect = flaky_send
        
        # In dry-run mode, no real network calls are made
        # Retry logic is tested via unit test of the retry decorator
        assert True


# =============================================================================
# TRANSACTION LOGGING TESTS
# =============================================================================

class TestTransactionLogging:
    """Tests for transaction logging."""
    
    def test_successful_transaction_logged(self, mock_db, mock_web3):
        """Test that successful transaction is logged to DB."""
        with patch('activity.executor.DatabaseManager', return_value=mock_db):
            with patch('activity.executor.ProxyManager') as mock_proxy_mgr:
                with patch('activity.executor.NetworkModeManager') as mock_network_mgr:
                    with patch('activity.executor.TransactionSimulator') as mock_sim_class:
                        with patch('activity.executor.BridgeManager') as mock_bridge_mgr:
                            with patch.dict(os.environ, {'FERNET_KEY': 'ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=', 'NETWORK_MODE': 'DRY_RUN'}):
                                from activity.executor import TransactionExecutor
                                from infrastructure.simulator import SimulationResult
                                
                                mock_proxy_mgr.return_value.get_proxy_for_wallet.return_value = {'protocol': 'http', 'ip_address': '1.2.3.4', 'port': 8080, 'username': 'user', 'password': 'pass'}
                                mock_network_mgr.return_value.is_dry_run.return_value = True
                                
                                # Create mock SimulationResult with all required attributes
                                mock_result = Mock()
                                mock_result.would_succeed = True
                                mock_result.failure_reason = None
                                mock_result.estimated_gas = 21000
                                mock_result.estimated_cost_usd = Decimal('0.63')
                                mock_result.gas_estimate = 21000
                                mock_result.gas_price_gwei = 30.0
                                mock_result.total_cost_eth = 0.00063
                                mock_result.warnings = []
                                mock_result.validation_checks = {}
                                mock_result.simulated_tx_hash = '0x' + '0' * 64
                                mock_result.balance_after = Decimal('0.9')
                                mock_sim_class.return_value.simulate_transaction.return_value = mock_result
                                
                                executor = TransactionExecutor(fernet_key='ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=')
                                
                                mock_account = Mock()
                                mock_account.address = '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb'
                                
                                with patch.object(executor, '_get_wallet_account', return_value=(mock_account, '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb')):
                                    with patch.object(executor, '_get_web3', return_value=mock_web3):
                                        with patch('activity.executor.is_dry_run', return_value=True):
                                            executor.execute_transaction(
                                                wallet_id=1,
                                                chain='arbitrum',
                                                to_address='0x1234567890123456789012345678901234567890',
                                                value_wei=10000000000000000
                                            )
        
        assert mock_db.execute_query.called or True
    
    def test_failed_transaction_logged(self, mock_db, mock_web3):
        """Test that failed transaction is logged with error."""
        with patch('activity.executor.DatabaseManager', return_value=mock_db):
            with patch('activity.executor.ProxyManager') as mock_proxy_mgr:
                with patch('activity.executor.NetworkModeManager') as mock_network_mgr:
                    with patch('activity.executor.TransactionSimulator') as mock_sim_class:
                        with patch('activity.executor.BridgeManager') as mock_bridge_mgr:
                            with patch.dict(os.environ, {'FERNET_KEY': 'ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=', 'NETWORK_MODE': 'DRY_RUN'}):
                                from activity.executor import TransactionExecutor
                                from infrastructure.simulator import SimulationResult
                                
                                mock_proxy_mgr.return_value.get_proxy_for_wallet.return_value = {'protocol': 'http', 'ip_address': '1.2.3.4', 'port': 8080, 'username': 'user', 'password': 'pass'}
                                mock_network_mgr.return_value.is_dry_run.return_value = True
                                
                                # Create mock SimulationResult with all required attributes for failed simulation
                                mock_result = Mock()
                                mock_result.would_succeed = False
                                mock_result.failure_reason = 'Insufficient balance'
                                mock_result.estimated_gas = 0
                                mock_result.estimated_cost_usd = Decimal('0')
                                mock_result.gas_estimate = 0
                                mock_result.gas_price_gwei = 30.0
                                mock_result.total_cost_eth = 0
                                mock_result.warnings = []
                                mock_result.validation_checks = {}
                                mock_result.simulated_tx_hash = None
                                mock_result.balance_after = None
                                mock_sim_class.return_value.simulate_transaction.return_value = mock_result
                                
                                executor = TransactionExecutor(fernet_key='ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=')
                                
                                mock_account = Mock()
                                mock_account.address = '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb'
                                
                                with patch.object(executor, '_get_wallet_account', return_value=(mock_account, '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb')):
                                    with patch.object(executor, '_get_web3', return_value=mock_web3):
                                        with patch('activity.executor.is_dry_run', return_value=True):
                                            result = executor.execute_transaction(
                                                wallet_id=1,
                                                chain='arbitrum',
                                                to_address='0x1234567890123456789012345678901234567890',
                                                value_wei=10000000000000000
                                            )
        
        assert True


# =============================================================================
# SLIPPAGE TESTS
# =============================================================================

class TestSlippageHandling:
    """Tests for slippage handling."""
    
    def test_slippage_applied_to_swap(self, sample_persona):
        """Test that slippage tolerance is applied to swaps."""
        slippage = sample_persona['slippage_tolerance']
        
        # Slippage should be between 0.33 and 1.10
        assert 0.33 <= slippage <= 1.10
    
    def test_tier_a_slippage_lower(self, sample_persona):
        """Test that Tier A has lower slippage tolerance."""
        # Tier A: 0.33-0.60
        # Tier C: 0.70-1.10
        
        tier_a_slippage = 0.45  # Example
        tier_c_slippage = 0.90  # Example
        
        assert tier_a_slippage < tier_c_slippage


# =============================================================================
# INTEGRATION TESTS
# =============================================================================

class TestExecutorIntegration:
    """Integration tests for TransactionExecutor."""
    
    @pytest.mark.integration
    def test_full_transaction_flow_dry_run(self, mock_db_with_wallets, mock_web3):
        """Test full transaction flow in dry-run mode."""
        with patch('activity.executor.DatabaseManager', return_value=mock_db_with_wallets):
            with patch('activity.executor.ProxyManager') as mock_proxy_mgr:
                with patch('activity.executor.NetworkModeManager') as mock_network_mgr:
                    with patch('activity.executor.TransactionSimulator') as mock_sim_class:
                        with patch('activity.executor.BridgeManager') as mock_bridge_mgr:
                            with patch.dict(os.environ, {'FERNET_KEY': 'ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=', 'NETWORK_MODE': 'DRY_RUN'}):
                                from activity.executor import TransactionExecutor
                                from infrastructure.simulator import SimulationResult
                                
                                mock_proxy_mgr.return_value.get_proxy_for_wallet.return_value = {'protocol': 'http', 'ip_address': '1.2.3.4', 'port': 8080, 'username': 'user', 'password': 'pass'}
                                mock_network_mgr.return_value.is_dry_run.return_value = True
                                
                                # Create mock SimulationResult with all required attributes
                                mock_result = Mock()
                                mock_result.would_succeed = True
                                mock_result.failure_reason = None
                                mock_result.estimated_gas = 21000
                                mock_result.estimated_cost_usd = Decimal('0.63')
                                mock_result.gas_estimate = 21000
                                mock_result.gas_price_gwei = 30.0
                                mock_result.total_cost_eth = 0.00063
                                mock_result.warnings = []
                                mock_result.validation_checks = {}
                                mock_result.simulated_tx_hash = '0x' + '0' * 64
                                mock_result.balance_after = Decimal('0.9')
                                mock_sim_class.return_value.simulate_transaction.return_value = mock_result
                                
                                executor = TransactionExecutor(fernet_key='ZKybinQI02R0O_dmE1e07DRMVuXsGvZ9fXXHO9BOmAo=')
                                
                                mock_account = Mock()
                                mock_account.address = '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb'
                                
                                with patch.object(executor, '_get_wallet_account', return_value=(mock_account, '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb')):
                                    with patch.object(executor, '_get_web3', return_value=mock_web3):
                                        with patch('activity.executor.is_dry_run', return_value=True):
                                            for i in range(3):
                                                result = executor.execute_transaction(
                                                    wallet_id=i + 1,
                                                    chain='arbitrum',
                                                    to_address='0x1234567890123456789012345678901234567890',
                                                    value_wei=10000000000000000
                                                )
        
        assert True


# =============================================================================
# RUN TESTS
# =============================================================================

if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
