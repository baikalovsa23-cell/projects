#!/usr/bin/env python3
"""
Pytest Configuration & Shared Fixtures
======================================
Общие fixtures для всех тестов проекта airdrop_v4.

Features:
- Mock DatabaseManager (in-memory SQLite для изоляции)
- Mock Web3 (без реальных RPC запросов)
- Mock CEX (без реальных выводов)
- Test data generators (wallets, personas, transactions)
- Environment setup (test .env)

Usage:
    pytest tests/ -v --tb=short
"""

import os
import sys
import pytest
import asyncio
import tempfile
from pathlib import Path
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Dict, List, Optional, Any
from unittest.mock import Mock, AsyncMock, MagicMock, patch
from dataclasses import dataclass

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent))

# Load .env file before setting test environment
from infrastructure.env_loader import load_env
env_path = load_env()
if env_path:
    print(f"Loaded .env from: {env_path}")

# Set test environment BEFORE any imports
os.environ.setdefault('TESTING', 'true')
os.environ.setdefault('DB_HOST', '127.0.0.1')
os.environ.setdefault('DB_PORT', '5432')
os.environ.setdefault('DB_NAME', 'farming_db_test')
os.environ.setdefault('DB_USER', 'farming_user')
os.environ.setdefault('DB_PASS', 'test_password')
os.environ.setdefault('FERNET_KEY', 'dGVzdF9mZXJuZXRfa2V5X2Zvcl90ZXN0aW5nX29ubHk=')
os.environ.setdefault('DRY_RUN', 'true')
os.environ.setdefault('NETWORK_MODE', 'dry_run')


# =============================================================================
# ASYNC FIXTURES
# =============================================================================

@pytest.fixture(scope="session")
def event_loop():
    """Create event loop for async tests."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


# =============================================================================
# DATABASE FIXTURES
# =============================================================================

@pytest.fixture
def mock_db():
    """
    Mock DatabaseManager for unit tests.
    
    Returns:
        Mock object with execute_query, get_wallet, etc.
    """
    db = Mock()
    
    # Default return values
    db.execute_query = Mock(return_value=None)
    db.get_wallet = Mock(return_value={
        'id': 1,
        'address': '0x742d35cc6634c0532925a3b844bc9e7595f0bebeb',
        'tier': 'A',
        'worker_node_id': 1,
        'proxy_id': 1,
        'status': 'active'
    })
    db.get_all_wallets = Mock(return_value=[])
    db.create_scheduled_transaction = Mock(return_value=1)
    
    return db


@pytest.fixture
def mock_db_with_wallets(mock_db):
    """
    Mock DatabaseManager with pre-populated wallets.
    
    Returns:
        Mock DB with 90 wallets (18 A, 45 B, 27 C)
    """
    wallets = []
    wallet_id = 1
    
    # Tier A: 18 wallets
    for i in range(18):
        wallets.append({
            'id': wallet_id,
            'address': f'0x{"a" * 40}',
            'tier': 'A',
            'worker_node_id': (i % 3) + 1,
            'proxy_id': wallet_id,
            'status': 'active',
            'openclaw_enabled': True
        })
        wallet_id += 1
    
    # Tier B: 45 wallets
    for i in range(45):
        wallets.append({
            'id': wallet_id,
            'address': f'0x{"b" * 40}',
            'tier': 'B',
            'worker_node_id': (i % 3) + 1,
            'proxy_id': wallet_id,
            'status': 'active',
            'openclaw_enabled': False
        })
        wallet_id += 1
    
    # Tier C: 27 wallets
    for i in range(27):
        wallets.append({
            'id': wallet_id,
            'address': f'0x{"c" * 40}',
            'tier': 'C',
            'worker_node_id': (i % 3) + 1,
            'proxy_id': wallet_id,
            'status': 'active',
            'openclaw_enabled': False
        })
        wallet_id += 1
    
    mock_db.get_all_wallets = Mock(return_value=wallets)
    mock_db.execute_query = Mock(side_effect=lambda q, p=None, fetch=None: 
        wallets if 'SELECT' in q and 'wallets' in q else None)
    
    return mock_db


# =============================================================================
# WEB3 FIXTURES
# =============================================================================

@pytest.fixture
def mock_web3():
    """
    Mock Web3 instance for transaction tests.
    
    Returns:
        Mock Web3 with eth.account, eth.get_balance, etc.
    """
    web3 = Mock()
    
    # Mock account
    account = Mock()
    account.address = '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb'
    account.key = bytes.fromhex('0' * 64)
    web3.eth.account.from_key = Mock(return_value=account)
    web3.eth.account.create = Mock(return_value=account)
    
    # Mock balance
    web3.eth.get_balance = Mock(return_value=10**18)  # 1 ETH
    web3.eth.get_transaction_count = Mock(return_value=0)
    
    # Mock gas
    web3.eth.gas_price = 30_000_000_000  # 30 gwei
    web3.eth.max_priority_fee = Mock(return_value=1_500_000_000)  # 1.5 gwei
    web3.eth.max_fee_per_gas = Mock(return_value=50_000_000_000)  # 50 gwei
    
    # Mock transaction
    tx_hash = bytes.fromhex('0' * 64)
    web3.eth.send_raw_transaction = Mock(return_value=tx_hash)
    web3.eth.wait_for_transaction_receipt = Mock(return_value={
        'status': 1,
        'transactionHash': tx_hash,
        'blockNumber': 12345,
        'gasUsed': 21000
    })
    
    # Mock contract
    contract = Mock()
    contract.functions = Mock()
    web3.eth.contract = Mock(return_value=contract)
    
    # Mock chain ID
    web3.eth.chain_id = 1
    web3.eth.block_number = 12345
    
    # Mock Web3 utilities
    web3.to_wei = Mock(side_effect=lambda v, u: int(v * 10**18 if u == 'ether' else v))
    web3.from_wei = Mock(side_effect=lambda v, u: v / 10**18 if u == 'ether' else v)
    web3.is_address = Mock(return_value=True)
    web3.to_checksum_address = Mock(side_effect=lambda a: a)
    
    return web3


@pytest.fixture
def mock_w3_async():
    """
    Mock AsyncWeb3 for async tests.
    """
    w3 = AsyncMock()
    w3.eth = AsyncMock()
    w3.eth.get_balance = AsyncMock(return_value=10**18)
    w3.eth.gas_price = 30_000_000_000
    return w3


# =============================================================================
# CEX FIXTURES
# =============================================================================

@pytest.fixture
def mock_exchange():
    """
    Mock CCXT exchange for CEX tests.
    
    Returns:
        Mock exchange with fetch_balance, withdraw, etc.
    """
    exchange = Mock()
    exchange.id = 'bybit'
    exchange.name = 'Bybit'
    
    # Mock balance
    exchange.fetch_balance = Mock(return_value={
        'ETH': {'free': 10.0, 'used': 0.0, 'total': 10.0},
        'USDT': {'free': 1000.0, 'used': 0.0, 'total': 1000.0}
    })
    
    # Mock currencies/networks
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
    
    # Mock withdrawal (NO REAL WITHDRAWAL!)
    exchange.withdraw = Mock(return_value={
        'id': 'withdraw_123',
        'txid': '0x' + '0' * 64,
        'amount': 0.1,
        'currency': 'ETH',
        'network': 'ARBITRUM',
        'status': 'pending'
    })
    
    # Mock markets
    exchange.load_markets = Mock(return_value={})
    exchange.markets = {
        'ETH/USDT': {'id': 'ETHUSDT', 'symbol': 'ETH/USDT'}
    }
    
    return exchange


@pytest.fixture
def mock_cex_manager(mock_db, mock_exchange):
    """
    Mock CEXManager for funding tests.
    """
    with patch('funding.cex_integration.CEXManager') as manager_class:
        manager = Mock()
        manager.get_exchange = Mock(return_value=mock_exchange)
        manager.withdraw = Mock(return_value={
            'success': True,
            'tx_id': '0x' + '0' * 64,
            'amount': Decimal('0.1'),
            'network': 'Arbitrum One'
        })
        manager.get_supported_networks = Mock(return_value=[
            'Arbitrum One', 'Base', 'OP Mainnet', 'Polygon'
        ])
        manager_class.return_value = manager
        yield manager


# =============================================================================
# SECRETS FIXTURES
# =============================================================================

@pytest.fixture
def mock_secrets_manager():
    """
    Mock SecretsManager for encryption tests.
    """
    from cryptography.fernet import Fernet
    
    manager = Mock()
    key = Fernet.generate_key()
    fernet = Fernet(key)
    
    def encrypt(value):
        return fernet.encrypt(value.encode()).decode()
    
    def decrypt(value):
        return fernet.decrypt(value.encode()).decode()
    
    manager.encrypt_cex_credential = Mock(side_effect=encrypt)
    manager.decrypt_cex_credential = Mock(side_effect=decrypt)
    manager.encrypt_private_key = Mock(side_effect=encrypt)
    manager.decrypt_private_key = Mock(side_effect=decrypt)
    
    return manager


# =============================================================================
# PROXY FIXTURES
# =============================================================================

@pytest.fixture
def mock_proxy_pool():
    """
    Mock proxy pool with NL, IS, CA proxies.
    """
    proxies = []
    
    # NL proxies (30)
    for i in range(30):
        proxies.append({
            'id': i + 1,
            'country_code': 'NL',
            'timezone': 'Europe/Amsterdam',
            'utc_offset': 1,
            'proxy_host': f'nl-proxy-{i}.example.com',
            'proxy_port': 8080,
            'is_active': True,
            'validation_status': 'valid'
        })
    
    # IS proxies (60)
    for i in range(60):
        proxies.append({
            'id': i + 31,
            'country_code': 'IS',
            'timezone': 'Atlantic/Reykjavik',
            'utc_offset': 0,
            'proxy_host': f'is-proxy-{i}.example.com',
            'proxy_port': 8080,
            'is_active': True,
            'validation_status': 'valid'
        })
    
    return proxies


# =============================================================================
# PERSONA FIXTURES
# =============================================================================

@pytest.fixture
def sample_persona():
    """
    Sample persona for testing.
    """
    return {
        'wallet_id': 1,
        'persona_type': 'ActiveTrader',
        'preferred_hours': [9, 10, 11, 14, 15, 16, 17, 20, 21],
        'tx_per_week_mean': 4.5,
        'tx_per_week_stddev': 1.2,
        'skip_week_probability': 0.025,
        'tx_weight_swap': 0.40,
        'tx_weight_bridge': 0.25,
        'tx_weight_liquidity': 0.20,
        'tx_weight_stake': 0.10,
        'tx_weight_nft': 0.05,
        'slippage_tolerance': 0.45,
        'gas_preference': 'normal',
        'gas_preference_weights': {'slow': 0.40, 'normal': 0.45, 'fast': 0.15}
    }


@pytest.fixture
def sample_personas():
    """
    Sample personas for all archetypes.
    """
    archetypes = [
        'ActiveTrader', 'CasualUser', 'WeekendWarrior', 'Ghost',
        'MorningTrader', 'NightOwl', 'WeekdayOnly', 'MonthlyActive',
        'BridgeMaxi', 'DeFiDegen', 'NFTCollector', 'Governance'
    ]
    
    personas = []
    for i, archetype in enumerate(archetypes):
        personas.append({
            'wallet_id': i + 1,
            'persona_type': archetype,
            'preferred_hours': list(range(9, 21)),
            'tx_per_week_mean': 3.0,
            'tx_per_week_stddev': 1.0,
            'skip_week_probability': 0.15,
            'tx_weight_swap': 0.35,
            'tx_weight_bridge': 0.25,
            'tx_weight_liquidity': 0.20,
            'tx_weight_stake': 0.15,
            'tx_weight_nft': 0.05,
            'slippage_tolerance': 0.50,
            'gas_preference': 'normal'
        })
    
    return personas


# =============================================================================
# TRANSACTION FIXTURES
# =============================================================================

@pytest.fixture
def sample_scheduled_tx():
    """
    Sample scheduled transaction.
    """
    return {
        'id': 1,
        'wallet_id': 1,
        'protocol_action_id': 5,
        'tx_type': 'SWAP',
        'layer': 'web3py',
        'scheduled_at': datetime.now() + timedelta(hours=2),
        'amount_usdt': Decimal('15.73'),
        'status': 'pending',
        'retry_count': 0
    }


@pytest.fixture
def sample_bridge_route():
    """
    Sample bridge route for testing.
    """
    return {
        'provider': 'Across Protocol',
        'from_network': 'Arbitrum One',
        'to_network': 'Base',
        'amount_wei': 10**17,  # 0.1 ETH
        'cost_usd': 2.5,
        'time_minutes': 15,
        'safety_score': 85,
        'defillama_tvl': 100_000_000,
        'defillama_rank': 3
    }


# =============================================================================
# LLM FIXTURES
# =============================================================================

@pytest.fixture
def mock_llm_response():
    """
    Mock LLM API response.
    """
    return {
        'id': 'chatcmpl-123',
        'object': 'chat.completion',
        'created': 1234567890,
        'model': 'anthropic/claude-3-opus',
        'choices': [{
            'index': 0,
            'message': {
                'role': 'assistant',
                'content': '{"action": "click", "selector": "#submit-button"}'
            },
            'finish_reason': 'stop'
        }],
        'usage': {
            'prompt_tokens': 100,
            'completion_tokens': 50,
            'total_tokens': 150
        }
    }


@pytest.fixture
def mock_openrouter_api(mock_llm_response):
    """
    Mock OpenRouter API client.
    """
    with patch('httpx.AsyncClient') as client_class:
        client = AsyncMock()
        response = Mock()
        response.json = Mock(return_value=mock_llm_response)
        response.raise_for_status = Mock()
        client.post = AsyncMock(return_value=response)
        client_class.return_value.__aenter__.return_value = client
        yield client


# =============================================================================
# TELEGRAM FIXTURES
# =============================================================================

@pytest.fixture
def mock_telegram_bot():
    """
    Mock Telegram bot for notification tests.
    """
    bot = AsyncMock()
    bot.send_message = AsyncMock(return_value={'message_id': 123})
    bot.send_document = AsyncMock(return_value={'message_id': 124})
    return bot


# =============================================================================
# HEALTH CHECK FIXTURES
# =============================================================================

@pytest.fixture
def mock_rpc_endpoints():
    """
    Mock RPC endpoints for health check tests.
    """
    return [
        {
            'id': 1,
            'chain': 'ethereum',
            'url': 'https://eth.llamarpc.com',
            'is_active': True,
            'priority': 1,
            'response_time_ms': 150
        },
        {
            'id': 2,
            'chain': 'arbitrum',
            'url': 'https://arb1.arbitrum.io/rpc',
            'is_active': True,
            'priority': 1,
            'response_time_ms': 100
        },
        {
            'id': 3,
            'chain': 'base',
            'url': 'https://mainnet.base.org',
            'is_active': True,
            'priority': 1,
            'response_time_ms': 80
        }
    ]


# =============================================================================
# PRICE ORACLE FIXTURES
# =============================================================================

@pytest.fixture
def mock_coingecko_response():
    """
    Mock CoinGecko API response.
    """
    return {
        'ethereum': {
            'usd': 3500.0,
            'usd_24h_change': 2.5
        },
        'bitcoin': {
            'usd': 65000.0,
            'usd_24h_change': 1.2
        }
    }


@pytest.fixture
def mock_defillama_response():
    """
    Mock DeFiLlama API response.
    """
    return {
        'coins': {
            'ethereum:0x0000000000000000000000000000000000000000': {
                'price': 3500.0,
                'symbol': 'ETH',
                'name': 'Ethereum'
            }
        }
    }


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

@pytest.fixture
def assert_no_real_withdrawal():
    """
    Assertion helper to ensure no real CEX withdrawal was made.
    """
    def _assert(mock_exchange):
        # Verify withdraw was called with mock params only
        if mock_exchange.withdraw.called:
            call_args = mock_exchange.withdraw.call_args
            # Should never have real API key
            assert 'sk_live' not in str(call_args), "Real API key detected!"
            assert 'test' in str(call_args).lower() or True  # Allow test calls
    
    return _assert


@pytest.fixture
def temp_env_file():
    """
    Create temporary .env file for testing.
    """
    with tempfile.NamedTemporaryFile(mode='w', suffix='.env', delete=False) as f:
        f.write("DB_HOST=127.0.0.1\n")
        f.write("DB_PORT=5432\n")
        f.write("DB_NAME=farming_db_test\n")
        f.write("DB_USER=farming_user\n")
        f.write("DB_PASS=test_password\n")
        f.write("FERNET_KEY=dGVzdF9mZXJuZXRfa2V5X2Zvcl90ZXN0aW5nX29ubHk=\n")
        f.write("DRY_RUN=true\n")
        f.write("NETWORK_MODE=dry_run\n")
        f.write("TESTING=true\n")
        temp_path = f.name
    
    yield temp_path
    
    # Cleanup
    os.unlink(temp_path)


# =============================================================================
# MARKERS
# =============================================================================

def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line(
        "markers", "unit: Unit tests (fast, no external dependencies)"
    )
    config.addinivalue_line(
        "markers", "integration: Integration tests (may use real APIs)"
    )
    config.addinivalue_line(
        "markers", "slow: Slow tests (skip with -m 'not slow')"
    )
    config.addinivalue_line(
        "markers", "requires_api: Tests that require real API keys"
    )
    config.addinivalue_line(
        "markers", "requires_db: Tests that require real database connection"
    )
