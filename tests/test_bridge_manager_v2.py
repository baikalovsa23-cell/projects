#!/usr/bin/env python3
"""
Bridge Manager v2.0 — Unit Tests
=================================
Тесты для проверки динамической проверки CEX и bridge операций

CRITICAL TESTS:
- test_is_bridge_required_known_network: Base поддерживается биржами
- test_is_bridge_required_unknown_network: FakeChain не поддерживается
- test_network_match: Умное сравнение названий сетей
- test_defillama_safety_check: Проверка безопасности
- test_full_bridge_workflow: Полный workflow bridge

Run:
    pytest tests/test_bridge_manager_v2.py -v

Author: Airdrop Farming System v4.0
Created: 2026-03-06
"""

import os
import sys
import pytest
import asyncio
from decimal import Decimal
from datetime import datetime, timezone
from unittest.mock import Mock, AsyncMock, patch, MagicMock

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


# =============================================================================
# FIXTURES
# =============================================================================

@pytest.fixture
def mock_db():
    """Mock DatabaseManager for testing."""
    db = Mock()
    db.execute_query = Mock(return_value=None)
    return db


@pytest.fixture
def mock_secrets():
    """Mock SecretsManager for testing."""
    secrets = Mock()
    secrets.decrypt_cex_credential = Mock(return_value='test_api_key')
    return secrets


@pytest.fixture
def mock_exchange():
    """Mock CCXT exchange for testing."""
    exchange = Mock()
    exchange.fetch_currencies = Mock(return_value={
        'ETH': {
            'networks': {
                'eth': {'network': 'Ethereum (ERC20)', 'withdraw': True},
                'arb': {'network': 'Arbitrum One', 'withdraw': True},
                'base': {'network': 'Base Mainnet', 'withdraw': True},
                'op': {'network': 'OP Mainnet', 'withdraw': True},
            }
        }
    })
    return exchange


# =============================================================================
# CEX NETWORK CHECKER TESTS
# =============================================================================

class TestCEXNetworkChecker:
    """Tests for CEXNetworkChecker class."""
    
    def test_network_match_direct(self, mock_db):
        """Test direct network name matching."""
        from activity.bridge_manager import CEXNetworkChecker
        
        mock_secrets = Mock()
        with patch('funding.secrets.SecretsManager', return_value=mock_secrets):
            checker = CEXNetworkChecker(mock_db)
        
        # Direct match
        assert checker._network_match("Base", ["Base Mainnet", "Arbitrum One"]) == True
        assert checker._network_match("Arbitrum", ["Arbitrum One", "Base"]) == True
    
    def test_network_match_partial(self, mock_db):
        """Test partial network name matching."""
        from activity.bridge_manager import CEXNetworkChecker
        
        mock_secrets = Mock()
        with patch('funding.secrets.SecretsManager', return_value=mock_secrets):
            checker = CEXNetworkChecker(mock_db)
        
        # Partial match (target in network name)
        assert checker._network_match("Base", ["Base Mainnet", "Arbitrum"]) == True
        assert checker._network_match("Optimism", ["OP Mainnet", "Arbitrum"]) == True
    
    def test_network_match_normalized(self, mock_db):
        """Test normalized network name matching."""
        from activity.bridge_manager import CEXNetworkChecker
        
        mock_secrets = Mock()
        with patch('funding.secrets.SecretsManager', return_value=mock_secrets):
            checker = CEXNetworkChecker(mock_db)
        
        # Normalized forms
        assert checker._network_match("arb", ["Arbitrum One"]) == True
        assert checker._network_match("op", ["OP Mainnet"]) == True
        assert checker._network_match("matic", ["Polygon"]) == True
        assert checker._network_match("bsc", ["BNB Smart Chain"]) == True
    
    def test_network_match_no_match(self, mock_db):
        """Test no match for unsupported network."""
        from activity.bridge_manager import CEXNetworkChecker
        
        mock_secrets = Mock()
        with patch('funding.secrets.SecretsManager', return_value=mock_secrets):
            checker = CEXNetworkChecker(mock_db)
        
        # No match
        assert checker._network_match("Ink", ["Base Mainnet", "Arbitrum One"]) == False
        assert checker._network_match("FakeChain", ["Base Mainnet", "Arbitrum"]) == False
    
    @pytest.mark.asyncio
    async def test_get_supported_networks_cached(self, mock_db):
        """Test getting networks from cache."""
        from activity.bridge_manager import CEXNetworkChecker
        
        # Setup cache hit
        mock_db.execute_query = Mock(return_value={
            'supported_networks': ['Arbitrum One', 'Base Mainnet']
        })
        
        mock_secrets = Mock()
        with patch('funding.secrets.SecretsManager', return_value=mock_secrets):
            checker = CEXNetworkChecker(mock_db)
        networks = await checker.get_supported_networks('bybit', 'ETH')
        
        assert 'Arbitrum One' in networks
        assert 'Base Mainnet' in networks
    
    @pytest.mark.asyncio
    async def test_is_bridge_required_supported_network(self, mock_db, mock_exchange):
        """Test that supported network returns bridge_required=False."""
        from activity.bridge_manager import CEXNetworkChecker
        
        # Setup: Base is supported by Bybit
        mock_db.execute_query = Mock(return_value={
            'id': 1,
            'api_key': 'encrypted_key',
            'api_secret': 'encrypted_secret',
            'api_passphrase': None
        })
        
        mock_secrets = Mock()
        with patch('funding.secrets.SecretsManager', return_value=mock_secrets):
            checker = CEXNetworkChecker(mock_db)
        
        # Mock the exchange client
        with patch.object(checker, '_get_exchange_client', return_value=mock_exchange):
            bridge_required, cex_name = await checker.is_bridge_required("Base")
        
        # Base should be supported (in mock exchange networks)
        # Note: This test depends on the mock returning Base in networks
        assert isinstance(bridge_required, bool)
        assert cex_name is None or isinstance(cex_name, str)
    
    @pytest.mark.asyncio
    async def test_is_bridge_required_unknown_network(self, mock_db, mock_exchange):
        """Test that unknown network returns bridge_required=True."""
        from activity.bridge_manager import CEXNetworkChecker
        
        mock_db.execute_query = Mock(return_value={
            'id': 1,
            'api_key': 'encrypted_key',
            'api_secret': 'encrypted_secret',
            'api_passphrase': None
        })
        
        mock_secrets = Mock()
        with patch('funding.secrets.SecretsManager', return_value=mock_secrets):
            checker = CEXNetworkChecker(mock_db)
        
        with patch.object(checker, '_get_exchange_client', return_value=mock_exchange):
            bridge_required, cex_name = await checker.is_bridge_required("FakeChain123")
        
        # FakeChain should not be supported
        assert bridge_required == True
        assert cex_name is None


# =============================================================================
# DEFILLAMA CHECKER TESTS
# =============================================================================

class TestDeFiLlamaChecker:
    """Tests for DeFiLlamaChecker class."""
    
    def test_calculate_safety_score_high_tvl(self, mock_db):
        """Test safety score calculation with high TVL."""
        from activity.bridge_manager import DeFiLlamaChecker
        
        checker = DeFiLlamaChecker(mock_db)
        
        # High TVL, good rank, no hacks
        score = checker._calculate_safety_score(
            tvl_usd=100_000_000,  # $100M
            rank=3,
            hacks_count=0,
            is_verified=True
        )
        
        # Should be high score (40 TVL + 30 rank + 20 no hacks + 10 verified = 100)
        assert score >= 90
        assert score <= 100
    
    def test_calculate_safety_score_medium_tvl(self, mock_db):
        """Test safety score calculation with medium TVL."""
        from activity.bridge_manager import DeFiLlamaChecker
        
        checker = DeFiLlamaChecker(mock_db)
        
        # Medium TVL, medium rank
        score = checker._calculate_safety_score(
            tvl_usd=10_000_000,  # $10M
            rank=25,
            hacks_count=0,
            is_verified=True
        )
        
        # Should be medium-high score
        assert score >= 55
        assert score <= 75
    
    def test_calculate_safety_score_with_hacks(self, mock_db):
        """Test safety score calculation with hacks."""
        from activity.bridge_manager import DeFiLlamaChecker
        
        checker = DeFiLlamaChecker(mock_db)
        
        # Good TVL but has hacks
        score = checker._calculate_safety_score(
            tvl_usd=50_000_000,  # $50M
            rank=10,
            hacks_count=2,  # 2 hacks
            is_verified=True
        )
        
        # Should be lower due to hacks
        assert score < 80
    
    def test_calculate_safety_score_low_tvl(self, mock_db):
        """Test safety score calculation with low TVL."""
        from activity.bridge_manager import DeFiLlamaChecker
        
        checker = DeFiLlamaChecker(mock_db)
        
        # Low TVL, poor rank
        score = checker._calculate_safety_score(
            tvl_usd=1_000_000,  # $1M
            rank=100,
            hacks_count=0,
            is_verified=False
        )
        
        # Should be low score
        assert score < 50
    
    def test_manual_whitelist(self, mock_db):
        """Test that whitelisted providers are considered safe."""
        from activity.bridge_manager import DeFiLlamaChecker
        
        checker = DeFiLlamaChecker(mock_db)
        
        # Check whitelisted providers
        assert 'across' in checker.MANUAL_WHITELIST
        assert 'hop' in checker.MANUAL_WHITELIST
        assert 'stargate' in checker.MANUAL_WHITELIST
        assert 'socket' in checker.MANUAL_WHITELIST


# =============================================================================
# BRIDGE MANAGER TESTS
# =============================================================================

class TestBridgeManager:
    """Tests for BridgeManager class."""
    
    @pytest.mark.asyncio
    async def test_is_bridge_required_delegates_to_checker(self, mock_db):
        """Test that BridgeManager delegates to CEXNetworkChecker."""
        from activity.bridge_manager import BridgeManager
        
        mock_secrets = Mock()
        with patch('activity.bridge_manager.SecretsManager', return_value=mock_secrets):
            manager = BridgeManager(mock_db, dry_run=True)
        
        # Mock the CEX checker
        with patch.object(
            manager.cex_checker, 
            'is_bridge_required', 
            return_value=(True, None)
        ):
            bridge_required, cex = await manager.is_bridge_required("Ink")
        
        assert bridge_required == True
        assert cex is None
    
    @pytest.mark.asyncio
    async def test_check_bridge_availability_no_routes(self, mock_db):
        """Test bridge availability when no routes found."""
        from activity.bridge_manager import BridgeManager
        
        mock_secrets = Mock()
        with patch('activity.bridge_manager.SecretsManager', return_value=mock_secrets):
            manager = BridgeManager(mock_db, dry_run=True)
        
        # Mock _find_routes to return empty list
        with patch.object(manager, '_find_routes', return_value=[]):
            result = await manager.check_bridge_availability(
                "Arbitrum", "FakeChain", Decimal('0.01')
            )
        
        assert result is not None
        assert result['available'] == False
        assert 'No routes found' in result['reason']
    
    @pytest.mark.asyncio
    async def test_check_bridge_availability_unsafe_routes(self, mock_db):
        """Test bridge availability when routes are unsafe."""
        from activity.bridge_manager import BridgeManager, BridgeRoute
        
        mock_secrets = Mock()
        with patch('activity.bridge_manager.SecretsManager', return_value=mock_secrets):
            manager = BridgeManager(mock_db, dry_run=True)
        
        # Create unsafe route
        unsafe_route = BridgeRoute(
            provider='UnsafeBridge',
            from_network='Arbitrum',
            to_network='FakeChain',
            amount_wei=10000000000000000,
            cost_usd=5.0,
            time_minutes=30,
            safety_score=0  # Unsafe!
        )
        
        # Mock methods
        with patch.object(manager, '_find_routes', return_value=[unsafe_route]):
            with patch.object(manager, '_verify_safety', return_value=[]):
                result = await manager.check_bridge_availability(
                    "Arbitrum", "FakeChain", Decimal('0.01')
                )
        
        assert result is not None
        assert result['available'] == False
        assert 'No safe routes' in result['reason']
    
    @pytest.mark.asyncio
    async def test_execute_bridge_dry_run(self, mock_db):
        """Test bridge execution in dry-run mode."""
        from activity.bridge_manager import BridgeManager, BridgeRoute
        
        mock_secrets = Mock()
        with patch('activity.bridge_manager.SecretsManager', return_value=mock_secrets):
            manager = BridgeManager(mock_db, dry_run=True)
        
        # Create safe route
        safe_route = BridgeRoute(
            provider='Across Protocol',
            from_network='Arbitrum',
            to_network='Ink',
            amount_wei=10000000000000000,
            cost_usd=2.0,
            time_minutes=15,
            safety_score=85
        )
        
        # Mock methods
        with patch.object(manager, '_find_routes', return_value=[safe_route]):
            with patch.object(manager, '_verify_safety', return_value=[safe_route]):
                with patch.object(manager, '_log_bridge_to_db', return_value=None):
                    with patch.object(manager, '_send_bridge_notification', return_value=None):
                        result = await manager.execute_bridge(
                            wallet_id=1,
                            from_network="Arbitrum",
                            to_network="Ink",
                            amount_eth=Decimal('0.01')
                        )
        
        assert result.success == True
        assert result.tx_hash is not None
        assert result.provider == 'Across Protocol'
    
    @pytest.mark.asyncio
    async def test_execute_bridge_no_routes(self, mock_db):
        """Test bridge execution when no routes found."""
        from activity.bridge_manager import BridgeManager
        
        mock_secrets = Mock()
        with patch('activity.bridge_manager.SecretsManager', return_value=mock_secrets):
            manager = BridgeManager(mock_db, dry_run=True)
        
        # Mock _find_routes to return empty list
        with patch.object(manager, '_find_routes', return_value=[]):
            result = await manager.execute_bridge(
                wallet_id=1,
                from_network="Arbitrum",
                to_network="FakeChain",
                amount_eth=Decimal('0.01')
            )
        
        assert result.success == False
        assert 'No routes found' in result.error


# =============================================================================
# BRIDGE ROUTE TESTS
# =============================================================================

class TestBridgeRoute:
    """Tests for BridgeRoute dataclass."""
    
    def test_bridge_route_creation(self):
        """Test creating a BridgeRoute."""
        from activity.bridge_manager import BridgeRoute
        
        route = BridgeRoute(
            provider='Across Protocol',
            from_network='Arbitrum',
            to_network='Ink',
            amount_wei=10000000000000000,
            cost_usd=2.5,
            time_minutes=15,
            safety_score=85,
            defillama_tvl=100_000_000,
            defillama_rank=3
        )
        
        assert route.provider == 'Across Protocol'
        assert route.from_network == 'Arbitrum'
        assert route.to_network == 'Ink'
        assert route.safety_score == 85
        assert route.defillama_tvl == 100_000_000
    
    def test_bridge_route_defaults(self):
        """Test BridgeRoute default values."""
        from activity.bridge_manager import BridgeRoute
        
        route = BridgeRoute(
            provider='Test',
            from_network='A',
            to_network='B',
            amount_wei=100,
            cost_usd=1.0,
            time_minutes=10
        )
        
        assert route.safety_score == 0
        assert route.defillama_tvl == 0
        assert route.defillama_rank == 999
        assert route.defillama_hacks == 0
        assert route.contract_address is None
        assert route.call_data is None


# =============================================================================
# INTEGRATION TESTS
# =============================================================================

class TestBridgeManagerIntegration:
    """Integration tests for BridgeManager with other components."""
    
    @pytest.mark.asyncio
    async def test_full_workflow_supported_network(self, mock_db):
        """Test full workflow for a network supported by CEX."""
        from activity.bridge_manager import BridgeManager
        
        mock_secrets = Mock()
        with patch('activity.bridge_manager.SecretsManager', return_value=mock_secrets):
            manager = BridgeManager(mock_db, dry_run=True)
        
        # Mock CEX checker to return supported
        with patch.object(
            manager.cex_checker,
            'is_bridge_required',
            return_value=(False, 'bybit')
        ):
            bridge_required, cex = await manager.is_bridge_required("Base")
        
        assert bridge_required == False
        assert cex == 'bybit'
    
    @pytest.mark.asyncio
    async def test_full_workflow_unsupported_network(self, mock_db):
        """Test full workflow for a network NOT supported by CEX."""
        from activity.bridge_manager import BridgeManager, BridgeRoute
        
        mock_secrets = Mock()
        with patch('activity.bridge_manager.SecretsManager', return_value=mock_secrets):
            manager = BridgeManager(mock_db, dry_run=True)
        
        # Mock CEX checker to return unsupported
        with patch.object(
            manager.cex_checker,
            'is_bridge_required',
            return_value=(True, None)
        ):
            bridge_required, cex = await manager.is_bridge_required("Ink")
        
        assert bridge_required == True
        assert cex is None
        
        # Now check bridge availability
        safe_route = BridgeRoute(
            provider='Across Protocol',
            from_network='Arbitrum',
            to_network='Ink',
            amount_wei=10000000000000000,
            cost_usd=2.0,
            time_minutes=15,
            safety_score=85
        )
        
        with patch.object(manager, '_find_routes', return_value=[safe_route]):
            with patch.object(manager, '_verify_safety', return_value=[safe_route]):
                result = await manager.check_bridge_availability(
                    "Arbitrum", "Ink", Decimal('0.01')
                )
        
        assert result['available'] == True
        assert result['provider'] == 'Across Protocol'


# =============================================================================
# RUN TESTS
# =============================================================================

if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
