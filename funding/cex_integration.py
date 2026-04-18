#!/usr/bin/env python3
"""
CEX Integration — Module 6
===========================
Единый интерфейс к 5 CEX биржам через CCXT

Features:
- 5 exchanges: Binance, Bybit, OKX, KuCoin, MEXC
- 18 subaccounts (4+4+4+3+3)
- Withdrawal через L2 сети (Ink, Base, MegaETH, Arbitrum, Polygon, BNB Chain)
- ❌ БЛОКИРОВКА Ethereum mainnet (только L2!)
- Fernet decryption для API keys
- Retry logic для rate limits и network errors
- Full logging для аудита

Usage:
    from funding.cex_integration import CEXManager
    
    cex = CEXManager()
    cex.withdraw(
        subaccount_id=1,
        address='0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb',
        amount=3.75,
        network='Base'
    )

Author: Airdrop Farming System v4.0
Created: 2026-02-24
"""

import os
import sys
from pathlib import Path
from typing import Dict, Optional, Literal
from dataclasses import dataclass
from decimal import Decimal

# Добавить parent directory для импорта
sys.path.insert(0, str(Path(__file__).parent.parent))

import ccxt
from ccxt.base.errors import (
    InsufficientFunds,
    InvalidAddress,
    NetworkError,
    RateLimitExceeded,
    ExchangeError
)
from loguru import logger
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential,
    retry_if_exception_type
)
from infrastructure.env_loader import load_env

# Load .env file (supports both production and local dev)
load_env()

from database.db_manager import DatabaseManager
from funding.secrets import SecretsManager


# =============================================================================
# DATA STRUCTURES
# =============================================================================

@dataclass
class WithdrawalResult:
    """Result of withdrawal operation."""
    success: bool
    tx_id: Optional[str]  # Transaction ID from exchange
    amount: Decimal
    fee: Optional[Decimal]
    network: str
    error: Optional[str] = None


# Supported networks (L2 ONLY)
# CRITICAL: Ink and MegaETH are NOT available for direct withdrawal on ANY exchange.
# These networks require bridging after receiving funds on L2 networks.
# BSC and Polygon are withdrawal-only (not for farming).
ALLOWED_NETWORKS = {
    'Arbitrum One', 'Base', 'OP Mainnet', 'zkSync Era', 'SCROLL', 'Linea', 'BSC', 'Polygon'
}

# CCXT network code mapping (exchange-specific)
# Network names must match withdrawal_network in cex_subaccounts table
NETWORK_CODES = {
    'binance': {
        'Arbitrum One': 'ARBITRUM',  # Binance naming
        'Base': 'BASE',
        'OP Mainnet': 'OPTIMISM',   # Binance uses OPTIMISM
        'SCROLL': 'SCROLL',
        'zkSync Era': 'ZKSYNC',     # If supported
        'Linea': 'LINEA',           # If supported
        'BSC': 'BSC',               # BNB Chain
        'Polygon': 'MATIC'          # Polygon
    },
    'bybit': {
        'Base': 'BASE',
        'Arbitrum One': 'ARBITRUM',
        'OP Mainnet': 'OPTIMISM',
        'zkSync Era': 'ZKSYNC',
        'SCROLL': 'SCROLL',
        'Linea': 'LINEA',
        'BSC': 'BSC',
        'Polygon': 'POLYGON'
    },
    'okx': {
        'Arbitrum One': 'USDT-Arbitrum One',  # OKX format
        'Base': 'USDT-Base',
        'OP Mainnet': 'USDT-Optimism',
        'Linea': 'USDT-Linea',
        'zkSync Era': 'USDT-zkSync Era',
        'SCROLL': 'USDT-Scroll',
        'BSC': 'USDT-BSC',
        'Polygon': 'USDT-Polygon'
    },
    'kucoin': {
        'Arbitrum One': 'ARBITRUM',
        'OP Mainnet': 'OPTIMISM',
        'Base': 'BASE',
        'zkSync Era': 'ZKSYNC',
        'SCROLL': 'SCROLL',
        'Linea': 'LINEA',
        'BSC': 'BSC',
        'Polygon': 'MATIC'
    },
    'mexc': {
        'Base': 'BASE',
        'OP Mainnet': 'OPTIMISM',
        'Arbitrum One': 'ARBITRUM',
        'Linea': 'LINEA',
        'zkSync Era': 'ZKSYNC',
        'SCROLL': 'SCROLL',
        'BSC': 'BSC',
        'Polygon': 'MATIC'
    }
}

# =============================================================================
# BYBIT DIRECT CLIENT
# =============================================================================

class BybitDirectClient:
    """
    Direct Bybit V5 API client bypassing CCXT V3 query-api check.
    
    This client directly calls Bybit V5 endpoints without going through
    CCXT's initialization which triggers the problematic /user/v3/private/query-api
    endpoint that requires special permissions.
    """
    
    def __init__(self, api_key: str, api_secret: str):
        """
        Initialize BybitDirectClient.
        
        Args:
            api_key: Bybit API key
            api_secret: Bybit API secret
        """
        self.api_key = api_key
        self.api_secret = api_secret
        self.base_url = 'https://api.bybit.com'
    
    def _generate_signature(self, params: dict, timestamp: str) -> str:
        """
        Generate HMAC-SHA256 signature for Bybit V5 API.
        
        Args:
            params: Request parameters
            timestamp: Current timestamp in milliseconds
        
        Returns:
            Hexadecimal signature string
        """
        import hmac
        import hashlib
        
        # Sort parameters and create query string
        param_str = '&'.join([f"{k}={v}" for k, v in sorted(params.items())])
        
        # Create signature string: timestamp + api_key + recv_window + param_str
        sign_str = timestamp + self.api_key + '5000' + param_str
        
        # Generate HMAC-SHA256 signature
        signature = hmac.new(
            self.api_secret.encode('utf-8'),
            sign_str.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()
        
        return signature
    
    def _make_request(self, endpoint: str, params: dict = None) -> dict:
        """
        Make authenticated request to Bybit V5 API.
        
        Args:
            endpoint: API endpoint (e.g., '/v5/account/wallet-balance')
            params: Request parameters
        
        Returns:
            API response as dict
        """
        from curl_cffi import requests
        import time
        
        if params is None:
            params = {}
        
        # Generate timestamp
        timestamp = str(int(time.time() * 1000))
        
        # Generate signature
        signature = self._generate_signature(params, timestamp)
        
        # Prepare headers
        headers = {
            'X-BAPI-API-KEY': self.api_key,
            'X-BAPI-SIGN': signature,
            'X-BAPI-TIMESTAMP': timestamp,
            'X-BAPI-RECV-WINDOW': '5000',
            'Content-Type': 'application/json'
        }
        
        # Make request with TLS fingerprinting (curl_cffi)
        url = self.base_url + endpoint
        response = requests.get(url, headers=headers, params=params, timeout=10, impersonate="chrome110")
        
        # Parse response
        data = response.json()
        
        # Check for errors
        if data.get('retCode') != 0:
            raise Exception(f"Bybit API error: {data.get('retMsg')} (code: {data.get('retCode')})")
        
        return data
    
    def get_balance(self, account_type: str = 'UNIFIED') -> float:
        """
        Check Bybit API connection via /v5/account/info endpoint.
        
        Returns:
            0.0 — connection ok, balance check not needed
        """
        import time
        import hmac
        import hashlib
        from curl_cffi import requests
        
        timestamp = str(int(time.time() * 1000))
        recv_window = '5000'
        param_str = timestamp + self.api_key + recv_window
        
        signature = hmac.new(
            self.api_secret.encode('utf-8'),
            param_str.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()
        
        headers = {
            'X-BAPI-API-KEY': self.api_key,
            'X-BAPI-SIGN': signature,
            'X-BAPI-TIMESTAMP': timestamp,
            'X-BAPI-RECV-WINDOW': recv_window,
        }
        
        response = requests.get(
            'https://api.bybit.com/v5/account/info',
            headers=headers,
            timeout=10,
            impersonate="chrome110"
        ).json()
        
        if response.get('retCode') != 0:
            raise Exception(
                f"Bybit API error: {response.get('retMsg')} "
                f"(code: {response.get('retCode')})"
            )
        
        return 0.0  # connection ok, balance check not needed


# =============================================================================
# CEX MANAGER
# =============================================================================

class CEXManager:
    """
    Unified interface for CEX withdrawals via CCXT.
    
    Supports:
    - Binance, Bybit, OKX, KuCoin, MEXC
    - L2 networks only (Ethereum mainnet blocked)
    - API key decryption via SecretsManager
    - Retry logic for transient errors
    """
    
    def __init__(self):
        """Initialize CEXManager."""
        self.db = DatabaseManager()
        self.secrets = SecretsManager()
        self._exchanges: Dict[int, ccxt.Exchange] = {}
        
        logger.info("CEXManager initialized | Supported exchanges: 5 (Binance, Bybit, OKX, KuCoin, MEXC)")
    
    def _get_exchange_client(self, subaccount_id: int) -> ccxt.Exchange:
        """
        Get or create CCXT exchange client for subaccount.
        
        Args:
            subaccount_id: Subaccount ID from database
        
        Returns:
            Authenticated CCXT exchange instance
        
        Raises:
            ValueError: If subaccount not found or network not allowed
        """
        # Cache check
        if subaccount_id in self._exchanges:
            return self._exchanges[subaccount_id]
        
        # Get subaccount credentials from DB
        query = """
            SELECT id, exchange, subaccount_name, api_key, api_secret, 
                   api_passphrase, withdrawal_network, balance_usdt
            FROM cex_subaccounts
            WHERE id = %s AND is_active = TRUE
        """
        subaccount = self.db.execute_query(query, (subaccount_id,), fetch='one')
        
        if not subaccount:
            raise ValueError(f"Subaccount {subaccount_id} not found or inactive")
        
        # Verify network is allowed (L2 only)
        network = subaccount['withdrawal_network']
        if network not in ALLOWED_NETWORKS:
            raise ValueError(
                f"Network '{network}' not allowed. Only L2 networks permitted: {ALLOWED_NETWORKS}"
            )
        
        # Decrypt credentials
        api_key = self.secrets.decrypt_cex_credential(subaccount_id, 'api_key')
        api_secret = self.secrets.decrypt_cex_credential(subaccount_id, 'api_secret')
        api_passphrase = self.secrets.decrypt_cex_credential(subaccount_id, 'api_passphrase')
        
        # Debug logging (passphrase value removed for security)
        logger.debug(f"Decrypted credentials for subaccount {subaccount_id} | api_passphrase: {'***SET***' if api_passphrase else 'NONE'}")
        
        # Initialize CCXT exchange
        exchange_name = subaccount['exchange']
        
        # For Bybit, use direct client to bypass CCXT V3 query-api check
        if exchange_name == 'bybit':
            logger.debug(f"Using BybitDirectClient for subaccount {subaccount_id}")
            return BybitDirectClient(api_key, api_secret)
        
        if exchange_name == 'binance':
            exchange = ccxt.binance({
                'apiKey': api_key,
                'secret': api_secret,
                'enableRateLimit': True,
                'options': {'defaultType': 'spot'}
            })
        
        elif exchange_name == 'okx':
            exchange = ccxt.okx({
                'apiKey': api_key,
                'secret': api_secret,
                'password': api_passphrase or '',
                'enableRateLimit': True,
                'options': {
                    'defaultType': 'spot',
                }
            })
        
        elif exchange_name == 'kucoin':
            exchange = ccxt.kucoin({
                'apiKey': api_key,
                'secret': api_secret,
                'password': api_passphrase or '',
                'enableRateLimit': True
            })
        
        elif exchange_name == 'mexc':
            exchange = ccxt.mexc({
                'apiKey': api_key,
                'secret': api_secret,
                'enableRateLimit': True
            })
        
        else:
            raise ValueError(f"Unsupported exchange: {exchange_name}")
        
        # Cache client
        self._exchanges[subaccount_id] = exchange
        
        logger.info(
            f"Exchange client created | Subaccount: {subaccount_id} ({subaccount['subaccount_name']}) | "
            f"Exchange: {exchange_name} | Network: {network}"
        )
        
        return exchange
    
    def _get_network_code(self, exchange_name: str, network: str) -> str:
        """
        Get exchange-specific network code.
        
        Args:
            exchange_name: Exchange identifier (binance, bybit, etc.)
            network: Human-readable network name (Base, Polygon, etc.)
        
        Returns:
            Exchange-specific network code
        
        Raises:
            ValueError: If network not supported by exchange
        """
        if exchange_name not in NETWORK_CODES:
            raise ValueError(f"Exchange '{exchange_name}' not configured")
        
        if network not in NETWORK_CODES[exchange_name]:
            raise ValueError(
                f"Network '{network}' not supported by {exchange_name}. "
                f"Supported: {list(NETWORK_CODES[exchange_name].keys())}"
            )
        
        return NETWORK_CODES[exchange_name][network]
    
    def _internal_transfer_to_funding(self, subaccount_id: int, amount: float) -> bool:
        """
        Internal transfer from Spot to Funding balance before withdrawal.
        
        Args:
            subaccount_id: Subaccount ID
            amount: Amount in USDT to transfer
        
        Returns:
            True if transfer successful, False otherwise
        """
        try:
            exchange = self._get_exchange_client(subaccount_id)
            
            # Try to transfer from Spot to Funding
            # Bybit V5 API: /v5/asset/transfer/transfer-inter-account
            params = {
                'fromMemberId': exchange.uid,  # Current account
                'toMemberId': exchange.uid,  # Same account (Spot to Funding)
                'fromAccountType': 'SPOT',
                'toAccountType': 'CONTRACT',
                'coin': 'USDT',
                'amount': str(amount)
            }
            
            response = exchange.privatePostV5AssetTransferTransferInterAccount(params)
            
            logger.info(
                f"Internal transfer successful | Subaccount: {subaccount_id} | "
                f"Amount: {amount} USDT | SPOT -> CONTRACT"
            )
            
            return True
            
        except Exception as e:
            logger.warning(
                f"Internal transfer failed | Subaccount: {subaccount_id} | "
                f"Amount: {amount} USDT | Error: {e}"
            )
            # Continue with withdrawal even if transfer fails
            return False
    
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=2, min=4, max=60),
        retry=retry_if_exception_type((RateLimitExceeded, NetworkError)),
        reraise=True
    )
    def withdraw(
        self,
        subaccount_id: int,
        address: str,
        amount: float,
        network: Optional[str] = None
    ) -> WithdrawalResult:
        """
        Withdraw USDT from CEX to wallet address.
        
        Args:
            subaccount_id: Subaccount ID from database
            address: Destination wallet address (EVM format)
            amount: Amount in USDT (will be converted to Decimal)
            network: Override withdrawal network (optional, uses DB default)
        
        Returns:
            WithdrawalResult with transaction details
        
        Raises:
            ValueError: Invalid parameters
            InsufficientFunds: Not enough balance
            InvalidAddress: Wallet address not whitelisted or invalid
            ExchangeError: Other exchange-specific errors
        
        Example:
            >>> cex = CEXManager()
            >>> result = cex.withdraw(
            ...     subaccount_id=1,
            ...     address='0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb',
            ...     amount=3.75,
            ...     network='Base'
            ... )
            >>> print(result.tx_id)
        """
        # Get subaccount details
        query = """
            SELECT id, exchange, subaccount_name, withdrawal_network, balance_usdt
            FROM cex_subaccounts
            WHERE id = %s
        """
        subaccount = self.db.execute_query(query, (subaccount_id,), fetch='one')
        
        if not subaccount:
            raise ValueError(f"Subaccount {subaccount_id} not found")
        
        # Use DB network if not specified
        if network is None:
            network = subaccount['withdrawal_network']
        
        # Validate network
        if network not in ALLOWED_NETWORKS:
            error_msg = f"Network '{network}' not allowed. Only L2 networks permitted."
            logger.error(error_msg)
            return WithdrawalResult(
                success=False,
                tx_id=None,
                amount=Decimal(str(amount)),
                fee=None,
                network=network,
                error=error_msg
            )
        
        # Validate balance
        if amount > subaccount['balance_usdt']:
            error_msg = (
                f"Insufficient balance | Subaccount: {subaccount['subaccount_name']} | "
                f"Requested: {amount} USDT | Available: {subaccount['balance_usdt']} USDT"
            )
            logger.error(error_msg)
            return WithdrawalResult(
                success=False,
                tx_id=None,
                amount=Decimal(str(amount)),
                fee=None,
                network=network,
                error=error_msg
            )
        
        # Get exchange client
        exchange = self._get_exchange_client(subaccount_id)
        exchange_name = subaccount['exchange']
        
        # Get network code
        network_code = self._get_network_code(exchange_name, network)
        
        # For Bybit, do internal transfer from Spot to Funding before withdrawal
        if exchange_name == 'bybit':
            self._internal_transfer_to_funding(subaccount_id, amount)
        
        logger.info(
            f"Initiating withdrawal | Subaccount: {subaccount['subaccount_name']} | "
            f"Exchange: {exchange_name} | Network: {network} ({network_code}) | "
            f"Amount: {amount} USDT | Address: {address[:10]}..."
        )
        
        try:
            # Execute withdrawal via CCXT
            # CCXT unified API: withdraw(code, amount, address, tag, params)
            response = exchange.withdraw(
                code='USDT',
                amount=amount,
                address=address,
                tag=None,  # No memo needed for EVM
                params={
                    'network': network_code
                }
            )
            
            # Parse response
            tx_id = response.get('id') or response.get('info', {}).get('id')
            fee = response.get('fee', {}).get('cost')
            
            # Update database balance (optimistic, actual balance checked later)
            new_balance = float(subaccount['balance_usdt']) - amount - (fee or 0)
            self.db.update_cex_balance(subaccount_id, new_balance)
            
            # Log success
            logger.success(
                f"Withdrawal successful | TX ID: {tx_id} | "
                f"Amount: {amount} USDT | Fee: {fee} | "
                f"Network: {network} | Address: {address[:10]}..."
            )
            
            # Log to system_events for audit trail
            self.db.log_system_event(
                event_type='cex_withdrawal',
                severity='info',
                message=f"Withdrawal from {exchange_name} ({subaccount['subaccount_name']}) to {address[:10]}... via {network}",
                metadata={
                    'subaccount_id': subaccount_id,
                    'exchange': exchange_name,
                    'network': network,
                    'amount': amount,
                    'fee': fee,
                    'tx_id': tx_id,
                    'address': address
                }
            )
            
            return WithdrawalResult(
                success=True,
                tx_id=tx_id,
                amount=Decimal(str(amount)),
                fee=Decimal(str(fee)) if fee else None,
                network=network,
                error=None
            )
        
        except InsufficientFunds as e:
            error_msg = f"Insufficient funds: {str(e)}"
            logger.error(error_msg)
            return WithdrawalResult(
                success=False,
                tx_id=None,
                amount=Decimal(str(amount)),
                fee=None,
                network=network,
                error=error_msg
            )
        
        except InvalidAddress as e:
            error_msg = f"Invalid address (not whitelisted?): {str(e)}"
            logger.error(error_msg)
            return WithdrawalResult(
                success=False,
                tx_id=None,
                amount=Decimal(str(amount)),
                fee=None,
                network=network,
                error=error_msg
            )
        
        except RateLimitExceeded as e:
            # Retry decorator will handle this
            logger.warning(f"Rate limit exceeded, retrying... | Error: {str(e)}")
            raise
        
        except NetworkError as e:
            # Retry decorator will handle this
            logger.warning(f"Network error, retrying... | Error: {str(e)}")
            raise
        
        except ExchangeError as e:
            error_msg = f"Exchange error: {str(e)}"
            logger.error(error_msg)
            
            # Log critical error
            self.db.log_system_event(
                event_type='cex_withdrawal_failed',
                severity='error',
                message=f"Withdrawal failed from {exchange_name}",
                metadata={
                    'subaccount_id': subaccount_id,
                    'error': str(e),
                    'amount': amount,
                    'network': network
                }
            )
            
            return WithdrawalResult(
                success=False,
                tx_id=None,
                amount=Decimal(str(amount)),
                fee=None,
                network=network,
                error=error_msg
            )
    
    def get_balance(self, subaccount_id: int) -> Dict[str, float]:
        """
        Get current balance from exchange.
        
        Args:
            subaccount_id: Subaccount ID
        
        Returns:
            Dict with balance info: {'USDT': 123.45, 'total_usd': 123.45}
        """
        exchange = self._get_exchange_client(subaccount_id)
        
        try:
            balance = exchange.fetch_balance()
            usdt_balance = balance.get('USDT', {}).get('free', 0)
            
            logger.debug(f"Balance fetched | Subaccount: {subaccount_id} | USDT: {usdt_balance}")
            
            return {
                'USDT': usdt_balance,
                'total_usd': usdt_balance
            }
        
        except Exception as e:
            logger.error(f"Failed to fetch balance | Subaccount: {subaccount_id} | Error: {e}")
            raise
    
    def verify_whitelist(self, subaccount_id: int, address: str) -> bool:
        """
        Verify if address is in CEX whitelist.
        
        Note: This is a safety check. Most exchanges don't expose whitelist via API,
        so this may need manual verification.
        
        Args:
            subaccount_id: Subaccount ID
            address: Wallet address to verify
        
        Returns:
            True if address is whitelisted (or cannot verify)
        """
        logger.warning(
            f"Whitelist verification not supported via CCXT | "
            f"Subaccount: {subaccount_id} | Address: {address[:10]}... | "
            f"Ensure address is manually whitelisted on exchange!"
        )
        
        # For now, assume address is whitelisted
        # Actual withdrawal will fail if not whitelisted
        return True
    
    def check_all_connections(self) -> Dict[str, any]:
        """
        Check API connections for all CEX subaccounts.
        
        Tests all 18 subaccounts (5 exchanges: OKX, Binance, Bybit, KuCoin, MEXC)
        and returns connection status for each.
        
        Returns:
            Dict with results:
            {
                'success': True,
                'total_subaccounts': 18,
                'checked_at': '2026-03-20T11:30:00Z',
                'results': [
                    {
                        'subaccount_id': 1,
                        'exchange': 'bybit',
                        'subaccount_name': 'AlphaTradingStrategy',
                        'status': 'ok',
                        'balance_usdt': 1250.45,
                        'response_time_ms': 342
                    },
                    ...
                ],
                'summary': {
                    'successful': 16,
                    'failed': 2,
                    'total_response_time_ms': 4521
                }
            }
        """
        import time
        from datetime import datetime, timezone
        
        logger.info("Starting CEX connection check for all subaccounts")
        
        # Get all subaccounts
        query = """
            SELECT id, exchange, subaccount_name, is_active
            FROM cex_subaccounts
            ORDER BY exchange, id
        """
        subaccounts = self.db.execute_query(query, fetch='all')
        
        if not subaccounts:
            logger.warning("No subaccounts found in database")
            return {
                'success': False,
                'error': 'No subaccounts found',
                'total_subaccounts': 0,
                'checked_at': datetime.now(timezone.utc).isoformat()
            }
        
        logger.info(f"Found {len(subaccounts)} subaccounts to check")
        
        # Check each subaccount
        results = []
        successful = 0
        failed = 0
        total_response_time = 0
        
        for subaccount in subaccounts:
            try:
                start_time = time.time()
                
                # Get exchange client (uses existing _get_exchange_client with decryption)
                exchange = self._get_exchange_client(subaccount['id'])
                
                # Test connection via fetch_balance
                if subaccount['exchange'] == 'bybit':
                    usdt_balance = exchange.get_balance()
                elif subaccount['exchange'] == 'okx':
                    # OKX: use privateGetAccountBalance directly to avoid
                    # load_markets() bug in ccxt 4.3.95 (NoneType + str in parse_market)
                    response = exchange.privateGetAccountBalance({'ccy': 'USDT'})
                    if response.get('code') != '0':
                        raise Exception(f"OKX API error: {response.get('msg')} (code: {response.get('code')})")
                    details = response.get('data', [{}])[0].get('details', [])
                    usdt_balance = 0.0
                    for item in details:
                        if item.get('ccy') == 'USDT':
                            usdt_balance = float(item.get('availBal', 0) or 0)
                            break
                else:
                    balance = exchange.fetch_balance()
                    usdt_balance = balance.get('USDT', {}).get('free', 0)
                
                response_time_ms = int((time.time() - start_time) * 1000)
                
                logger.info(
                    f"CEX connection OK | Subaccount: {subaccount['subaccount_name']} | "
                    f"Exchange: {subaccount['exchange']} | Balance: {usdt_balance} USDT | "
                    f"Response time: {response_time_ms}ms"
                )
                
                results.append({
                    'subaccount_id': subaccount['id'],
                    'exchange': subaccount['exchange'],
                    'subaccount_name': subaccount['subaccount_name'],
                    'status': 'ok',
                    'balance_usdt': float(usdt_balance),
                    'response_time_ms': response_time_ms
                })
                
                successful += 1
                total_response_time += response_time_ms
                
            except Exception as e:
                response_time_ms = int((time.time() - start_time) * 1000)
                
                # Determine error code
                error_code = 'UNKNOWN_ERROR'
                error_message = str(e)
                
                if 'API key' in error_message.lower() or 'apikey' in error_message.lower():
                    error_code = 'INVALID_API_KEY'
                elif 'signature' in error_message.lower():
                    error_code = 'INVALID_SIGNATURE'
                elif 'passphrase' in error_message.lower():
                    error_code = 'INVALID_PASSPHRASE'
                elif 'ip' in error_message.lower() and 'whitelist' in error_message.lower():
                    error_code = 'IP_NOT_WHITELISTED'
                elif 'rate limit' in error_message.lower():
                    error_code = 'RATE_LIMIT_EXCEEDED'
                elif 'network' in error_message.lower():
                    error_code = 'NETWORK_ERROR'
                elif 'permission' in error_message.lower():
                    error_code = 'PERMISSION_DENIED'
                
                logger.error(
                    f"CEX connection FAILED | Subaccount: {subaccount['subaccount_name']} | "
                    f"Exchange: {subaccount['exchange']} | Error: {error_code} - {error_message}"
                )
                
                results.append({
                    'subaccount_id': subaccount['id'],
                    'exchange': subaccount['exchange'],
                    'subaccount_name': subaccount['subaccount_name'],
                    'status': 'error',
                    'error_code': error_code,
                    'error_message': error_message,
                    'response_time_ms': response_time_ms
                })
                
                failed += 1
                total_response_time += response_time_ms
        
        # Log overall result
        logger.success(
            f"CEX connection check completed | "
            f"Total: {len(subaccounts)} | Success: {successful} | Failed: {failed}"
        )
        
        # Log to system_events
        try:
            self.db.log_system_event(
                event_type='cex_connection_check',
                severity='info' if failed == 0 else 'warning',
                message=f"CEX connection check: {successful}/{len(subaccounts)} successful",
                metadata={
                    'total_subaccounts': len(subaccounts),
                    'successful': successful,
                    'failed': failed,
                    'failed_exchanges': [r for r in results if r['status'] == 'error'],
                    'total_response_time_ms': total_response_time
                }
            )
        except Exception as log_error:
            logger.warning(f"Failed to log system event: {log_error}")
        
        return {
            'success': True,
            'total_subaccounts': len(subaccounts),
            'checked_at': datetime.now(timezone.utc).isoformat(),
            'results': results,
            'summary': {
                'successful': successful,
                'failed': failed,
                'total_response_time_ms': total_response_time
            }
        }
    
    def list_subaccounts(self) -> list:
        """
        List all active subaccounts from database.
        
        Returns:
            List of subaccount dicts
        """
        query = """
            SELECT id, exchange, subaccount_name, withdrawal_network, 
                   balance_usdt, is_active
            FROM cex_subaccounts
            ORDER BY exchange, id
        """
        subaccounts = self.db.execute_query(query, fetch='all')
        
        logger.info(f"Subaccounts listed | Total: {len(subaccounts)}")
        
        return subaccounts


# =============================================================================
# CLI INTERFACE
# =============================================================================

def main():
    """CLI entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description='CEX Integration Module 6')
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    # List subaccounts
    list_parser = subparsers.add_parser('list', help='List all subaccounts')
    
    # Get balance
    balance_parser = subparsers.add_parser('balance', help='Get subaccount balance')
    balance_parser.add_argument('--subaccount-id', type=int, required=True)
    
    # Withdraw (TEST ONLY)
    withdraw_parser = subparsers.add_parser('withdraw', help='Test withdrawal (use with caution!)')
    withdraw_parser.add_argument('--subaccount-id', type=int, required=True)
    withdraw_parser.add_argument('--address', type=str, required=True)
    withdraw_parser.add_argument('--amount', type=float, required=True)
    withdraw_parser.add_argument('--network', type=str, help='Override network (optional)')
    
    # Check connections
    check_parser = subparsers.add_parser('check-connections', help='Check CEX API connections for all subaccounts')
    check_parser.add_argument('--json', action='store_true', help='Output as JSON')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    try:
        cex = CEXManager()
        
        if args.command == 'list':
            subaccounts = cex.list_subaccounts()
            print("\n📋 CEX Subaccounts:")
            print(f"{'ID':<5} {'Exchange':<10} {'Subaccount':<25} {'Network':<15} {'Balance (USDT)':<15} {'Active'}")
            print("-" * 85)
            for sub in subaccounts:
                print(
                    f"{sub['id']:<5} {sub['exchange']:<10} {sub['subaccount_name']:<25} "
                    f"{sub['withdrawal_network']:<15} {sub['balance_usdt']:<15.2f} "
                    f"{'✅' if sub['is_active'] else '❌'}"
                )
        
        elif args.command == 'balance':
            balance = cex.get_balance(args.subaccount_id)
            print(f"\n💰 Balance for Subaccount {args.subaccount_id}:")
            print(f"   USDT: {balance['USDT']:.2f}")
            print(f"   Total USD: {balance['total_usd']:.2f}")
        
        elif args.command == 'withdraw':
            print("\n⚠️  WARNING: This will execute a REAL withdrawal!")
            confirm = input(f"Withdraw {args.amount} USDT to {args.address[:10]}...? (yes/no): ")
            
            if confirm.lower() != 'yes':
                print("❌ Withdrawal cancelled")
                sys.exit(0)
            
            result = cex.withdraw(
                subaccount_id=args.subaccount_id,
                address=args.address,
                amount=args.amount,
                network=args.network
            )
            
            if result.success:
                print(f"\n✅ Withdrawal successful!")
                print(f"   TX ID: {result.tx_id}")
                print(f"   Amount: {result.amount} USDT")
                print(f"   Fee: {result.fee} USDT")
                print(f"   Network: {result.network}")
            else:
                print(f"\n❌ Withdrawal failed!")
                print(f"   Error: {result.error}")
                sys.exit(1)
        
        elif args.command == 'check-connections':
            result = cex.check_all_connections()
            
            if args.json:
                import json
                print(json.dumps(result, indent=2))
            else:
                print("\n" + "=" * 100)
                print("🔍 CEX Connection Check Results")
                print("=" * 100)
                print(f"Total subaccounts: {result['total_subaccounts']}")
                print(f"Checked at: {result['checked_at']}")
                print(f"Successful: {result['summary']['successful']}")
                print(f"Failed: {result['summary']['failed']}")
                print(f"Total response time: {result['summary']['total_response_time_ms']}ms")
                print("\n" + "-" * 100)
                print(f"{'ID':<5} {'Exchange':<10} {'Subaccount':<25} {'Status':<10} {'Balance (USDT)':<15} {'Response (ms)':<12} {'Error'}")
                print("-" * 100)
                
                for r in result['results']:
                    status_icon = "✅" if r['status'] == 'ok' else "❌"
                    balance = f"{r.get('balance_usdt', 0):.2f}" if r.get('balance_usdt') is not None else "N/A"
                    error = r['error_message'][:30] if r.get('error_message') else ""
                    
                    print(
                        f"{r['subaccount_id']:<5} {r['exchange']:<10} {r['subaccount_name']:<25} "
                        f"{status_icon} {r['status']:<8} {balance:<15} {r['response_time_ms']:<12} {error}"
                    )
                
                print("=" * 100)
    
    except Exception as e:
        logger.exception(f"Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
