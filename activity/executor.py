#!/usr/bin/env python3
"""
Transaction Executor — Module 12
=================================
Выполнение on-chain транзакций через web3.py для L2 сетей

Features:
- EVM transaction execution (swap, bridge, stake, LP, NFT mint, etc.)
- Dynamic gas estimation с fallback стратегией
- Nonce management с retry на nonce conflicts
- Transaction receipt waiting с timeout
- Support для 10+ L2 chains (Arbitrum, Base, Ink, Optimism, Polygon, etc.)
- Fernet decryption приватных ключей
- Comprehensive error handling и retry logic
- Database transaction logging (confirmed/failed status)
- Proxy support через HTTP/SOCKS5
- Anti-MEV: randomized gas tips, transaction timing

Security:
- Private keys never logged
- Encrypted storage only
- Transaction signing offline
- Nonce protection (sequential ordering)

Author: Airdrop Farming System v4.0
Created: 2026-02-25
"""

import os
import sys
import time
import threading
from typing import Dict, Any, Optional, List, Tuple
from pathlib import Path
from decimal import Decimal
from datetime import datetime, timezone
import numpy as np

# Добавить parent directory для импорта
sys.path.insert(0, str(Path(__file__).parent.parent))

from web3 import Web3
try:
    from web3.middleware import geth_poa_middleware
except ImportError:
    # web3.py 7.x renamed it
    from web3.middleware import ExtraDataToPOAMiddleware as geth_poa_middleware
from eth_account import Account
from eth_account.signers.local import LocalAccount
from cryptography.fernet import Fernet
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type
from dotenv import load_dotenv

# Import custom exceptions
from activity.exceptions import ProxyRequiredError

# TLS Fingerprinting support
from infrastructure.identity_manager import identity_manager, get_curl_session

# IP LEAK PROTECTION (v4.1)
from infrastructure.ip_guard import (
    pre_flight_check,
    verify_proxy_ip,
    IPLeakDetected
)

# Dry-run and simulation infrastructure
from infrastructure.network_mode import NetworkModeManager, NetworkMode, is_dry_run, is_mainnet
from infrastructure.simulator import TransactionSimulator, SimulationResult

# Bridge Manager v2.0 integration
from activity.bridge_manager import BridgeManager, BridgeResult, BridgeError

from infrastructure.env_loader import load_env

# Load .env file (supports both production and local dev)
load_env()

from database.db_manager import DatabaseManager
from activity.proxy_manager import ProxyManager


# =============================================================================
# EXCEPTIONS
# =============================================================================

class TransactionExecutionError(Exception):
    """Base exception for transaction execution errors."""
    pass


class InsufficientBalanceError(TransactionExecutionError):
    """Wallet has insufficient balance for transaction."""
    pass


class NonceConflictError(TransactionExecutionError):
    """Nonce conflict detected (transaction already used)."""
    pass


class GasEstimationError(TransactionExecutionError):
    """Failed to estimate gas for transaction."""
    pass


class TransactionTimeoutError(TransactionExecutionError):
    """Transaction not confirmed within timeout."""
    pass


class TransactionSimulationFailed(TransactionExecutionError):
    """Raised when transaction simulation fails."""
    pass


class MainnetNotAllowed(TransactionExecutionError):
    """Raised when mainnet operations attempted without safety gates."""
    pass




# =============================================================================
# CHAIN CONFIGURATION
# =============================================================================

# L2 Chains configuration (loaded from database chain_rpc_endpoints)
def get_chain_configs() -> Dict[str, Dict]:
    """
    Get chain configurations from database.
    
    Returns:
        Dict mapping chain name -> config dict
    """
    try:
        from database.db_manager import DatabaseManager
        db = DatabaseManager()
        chain_configs = db.get_all_chain_configs()
        
        # Transform to expected format
        configs = {}
        for chain, config in chain_configs.items():
            configs[chain] = {
                'chain_id': config.get('chain_id'),
                'name': chain.capitalize(),
                'native_token': config.get('native_token', 'ETH'),
                'block_time': float(config.get('block_time', 2.0)),
                'is_poa': config.get('is_poa', False)
            }
        
        # Fallback to defaults if empty
        if not configs:
            return {
                'arbitrum': {
                    'chain_id': 42161,
                    'name': 'Arbitrum One',
                    'native_token': 'ETH',
                    'block_time': 0.25,
                    'is_poa': False
                },
                'base': {
                    'chain_id': 8453,
                    'name': 'Base',
                    'native_token': 'ETH',
                    'block_time': 2.0,
                    'is_poa': False
                },
                'optimism': {
                    'chain_id': 10,
                    'name': 'Optimism',
                    'native_token': 'ETH',
                    'block_time': 2.0,
                    'is_poa': False
                },
                'polygon': {
                    'chain_id': 137,
                    'name': 'Polygon',
                    'native_token': 'MATIC',
                    'block_time': 2.0,
                    'is_poa': True
                },
                'bnbchain': {
                    'chain_id': 56,
                    'name': 'BNB Smart Chain',
                    'native_token': 'BNB',
                    'block_time': 3.0,
                    'is_poa': True
                },
                'ink': {
                    'chain_id': 57073,
                    'name': 'Ink',
                    'native_token': 'ETH',
                    'block_time': 2.0,
                    'is_poa': False
                },
                'megaeth': {
                    'chain_id': 1088,
                    'name': 'MegaETH',
                    'native_token': 'ETH',
                    'block_time': 0.1,
                    'is_poa': False
                }
            }
        
        return configs
    except Exception as e:
        logger.warning(f"Failed to load chain configs from DB, using fallback: {e}")
        return {
            'arbitrum': {
                'chain_id': 42161,
                'name': 'Arbitrum One',
                'native_token': 'ETH',
                'block_time': 0.25,
                'is_poa': False
            },
            'base': {
                'chain_id': 8453,
                'name': 'Base',
                'native_token': 'ETH',
                'block_time': 2.0,
                'is_poa': False
            },
            'optimism': {
                'chain_id': 10,
                'name': 'Optimism',
                'native_token': 'ETH',
                'block_time': 2.0,
                'is_poa': False
            },
            'polygon': {
                'chain_id': 137,
                'name': 'Polygon',
                'native_token': 'MATIC',
                'block_time': 2.0,
                'is_poa': True
            },
            'bnbchain': {
                'chain_id': 56,
                'name': 'BNB Smart Chain',
                'native_token': 'BNB',
                'block_time': 3.0,
                'is_poa': True
            },
            'ink': {
                'chain_id': 57073,
                'name': 'Ink',
                'native_token': 'ETH',
                'block_time': 2.0,
                'is_poa': False
            },
            'megaeth': {
                'chain_id': 1088,
                'name': 'MegaETH',
                'native_token': 'ETH',
                'block_time': 0.1,
                'is_poa': False
            }
        }

CHAIN_CONFIGS = get_chain_configs()


# =============================================================================
# TRANSACTION EXECUTOR
# =============================================================================

class TransactionExecutor:
    """
    Executor для on-chain транзакций через web3.py.
    
    Архитектура:
    - Decryption приватных ключей из БД
    - Dynamic gas estimation с EIP-1559 support
    - Nonce management (автоматический инкремент)
    - Transaction signing и отправка
    - Receipt waiting с configurable timeout
    - Comprehensive error handling
    - Database logging
    """
    
    def __init__(self, fernet_key: Optional[str] = None):
        """
        Initialize TransactionExecutor.
        
        Args:
            fernet_key: Fernet encryption key (defaults to FERNET_KEY env var)
        """
        # Load Fernet key
        fernet_key = fernet_key or os.getenv('FERNET_KEY')
        if not fernet_key:
            raise ValueError("FERNET_KEY not found in environment")
        
        if isinstance(fernet_key, str):
            fernet_key = fernet_key.encode()
        
        self.fernet = Fernet(fernet_key)
        self.db = DatabaseManager()
        
        # Proxy Manager for wallet-to-proxy mapping
        self.proxy_manager = ProxyManager(db=self.db)
        
        # Network mode manager and transaction simulator
        self.network_mode = NetworkModeManager()
        self.simulator = TransactionSimulator(self.db, self.network_mode)
        
        # Web3 instances cache (lazy initialization)
        # Key: (chain, wallet_id) for proxy-specific instances
        self._web3_instances: Dict[Tuple[str, int], Web3] = {}
        
        # CRITICAL: Per-wallet nonce locks to prevent race conditions
        # Key: wallet_id
        self._nonce_locks: Dict[int, threading.Lock] = {}
        
        logger.info(
            f"TransactionExecutor initialized | "
            f"Mode: {self.network_mode.get_mode().value.upper()} | "
            f"ProxyManager: ✓ | Nonce locks: ✓ | Simulator: ✓"
        )
    
    def _get_web3(self, chain: str, wallet_id: Optional[int] = None) -> Web3:
        """
        Get Web3 instance for chain with wallet's assigned proxy.
        
        CRITICAL: Each wallet uses its own proxy for anti-Sybil protection.
        This ensures 90 unique IP addresses (1 per wallet) instead of 3 Worker IPs.
        
        FAILOVER: If primary RPC fails, automatically switches to fallback RPC.
        
        Args:
            chain: Chain name (arbitrum, base, etc.)
            wallet_id: Wallet database ID. REQUIRED for all production transactions.
        
        Returns:
            Web3 instance connected to RPC through wallet's proxy
        
        Raises:
            ProxyRequiredError: If wallet_id not provided or proxy unavailable.
                               Direct connections are FORBIDDEN for anti-Sybil protection.
            ConnectionError: If both primary and fallback RPC fail.
        """
        # Cache key includes wallet_id for proxy-specific instances
        cache_key = (chain, wallet_id if wallet_id else 0)
        
        if cache_key in self._web3_instances:
            return self._web3_instances[cache_key]
        
        # Get RPC endpoint from database with fallback support
        rpc_urls = self.db.get_chain_rpc_with_fallback(chain)
        
        if not rpc_urls or not rpc_urls.get('primary'):
            raise ValueError(f"No active RPC endpoint found for chain: {chain}")
        
        rpc_url = rpc_urls['primary']
        fallback_url = rpc_urls.get('fallback')
        
        # Create Web3 instance with or without proxy
        if wallet_id:
            # ✅ Get wallet's assigned proxy + TLS fingerprint
            try:
                proxy_config = self.proxy_manager.get_wallet_proxy(wallet_id)
                proxy_dict = self.proxy_manager.build_proxy_dict(proxy_config)
                
                # Get browser fingerprint configuration for this wallet
                tls_config = identity_manager.get_config(wallet_id)
                
                # Build proxy URL for curl_cffi
                proxy_url = f"{proxy_config['protocol']}://{proxy_config['username']}:{proxy_config['password']}@{proxy_config['ip_address']}:{proxy_config['port']}"
                
                # =================================================================
                # CRITICAL: PRE-FLIGHT IP VERIFICATION (v4.1)
                # =================================================================
                # Verify proxy IP before any blockchain operation
                # This prevents IP leaks that would expose Worker IP
                try:
                    verified_ip = pre_flight_check(
                        wallet_id=wallet_id,
                        proxy_url=proxy_url,
                        proxy_provider=proxy_config.get('provider', 'unknown'),
                        component='activity_executor'
                    )
                    logger.success(f"✅ Pre-flight IP check passed | Wallet {wallet_id} | IP: {verified_ip}")
                except IPLeakDetected:
                    logger.critical(f"🚨 PRE-FLIGHT CHECK FAILED: IP LEAK DETECTED for wallet {wallet_id}!")
                    raise ProxyRequiredError(
                        f"IP leak detected for wallet {wallet_id}. "
                        f"Proxy configuration may be invalid. Operation blocked."
                    )
                except Exception as e:
                    logger.warning(f"Pre-flight check warning: {e}. Continuing with caution...")
                
                # Create curl_cffi session with browser-like fingerprint
                session = get_curl_session(wallet_id, proxy_url)
                
                # Determine Tier for logging
                tier = "TIER_A" if wallet_id <= 18 else "TIER_B/C"
                
                logger.info(
                    f"[{tier}] Wallet {wallet_id} RPC session | "
                    f"Proxy: {proxy_config['provider']}_{proxy_config['country_code']} | "
                    f"TLS: {tls_config['impersonate']} on {tls_config['platform']} | "
                    f"HTTP/2: {tls_config['http2']} | "
                    f"Verified IP: {verified_ip}"
                )
                
                # Create Web3 with curl_cffi session
                w3 = Web3(
                    Web3.HTTPProvider(
                        rpc_url,
                        request_kwargs={'timeout': 60},
                        session=session
                    )
                )
                
            except ValueError as e:
                logger.error(f"Failed to get proxy for wallet {wallet_id}: {e}")
                raise ProxyRequiredError(
                    f"Cannot execute transaction without proxy for wallet {wallet_id}. "
                    f"Direct connections forbidden for anti-Sybil protection. Error: {e}"
                )
        else:
            # No wallet_id provided - this should not happen in production
            raise ProxyRequiredError(
                "wallet_id is required for all transaction operations. "
                "Direct connections are forbidden for anti-Sybil protection."
            )
        
        # Add PoA middleware if needed (Polygon, BNB Chain)
        chain_config = CHAIN_CONFIGS.get(chain, {})
        if chain_config.get('is_poa', False):
            w3.middleware_onion.inject(geth_poa_middleware, layer=0)
        
        # Verify connection with fallback support
        try:
            if not w3.is_connected():
                raise ConnectionError(f"Primary RPC not responding: {rpc_url[:50]}...")
        except Exception as e:
            # Primary RPC failed - try fallback
            logger.warning(f"Primary RPC failed for {chain}: {e}")
            
            if fallback_url:
                logger.info(f"Switching to fallback RPC for {chain}: {fallback_url[:50]}...")
                
                # Recreate Web3 with fallback URL
                try:
                    if wallet_id:
                        # Reuse proxy session
                        session = get_curl_session(wallet_id, proxy_url)
                        w3 = Web3(
                            Web3.HTTPProvider(
                                fallback_url,
                                request_kwargs={'timeout': 60},
                                session=session
                            )
                        )
                    else:
                        w3 = Web3(Web3.HTTPProvider(fallback_url, request_kwargs={'timeout': 60}))
                    
                    # Add PoA middleware for fallback too
                    if chain_config.get('is_poa', False):
                        w3.middleware_onion.inject(geth_poa_middleware, layer=0)
                    
                    if not w3.is_connected():
                        raise ConnectionError(f"Fallback RPC also failed: {fallback_url[:50]}...")
                    
                    logger.success(f"Connected to fallback RPC for {chain}")
                    
                except Exception as fallback_error:
                    logger.error(f"Both primary and fallback RPC failed for {chain}")
                    raise ConnectionError(
                        f"All RPC endpoints failed for {chain}. "
                        f"Primary: {str(e)[:100]}, Fallback: {str(fallback_error)[:100]}"
                    )
            else:
                # No fallback available
                raise ConnectionError(f"Primary RPC failed and no fallback available for {chain}: {e}")
        
        # Verify chain ID
        expected_chain_id = chain_config.get('chain_id')
        actual_chain_id = w3.eth.chain_id
        
        if expected_chain_id and expected_chain_id != actual_chain_id:
            logger.warning(
                f"Chain ID mismatch | Expected: {expected_chain_id}, Got: {actual_chain_id} | "
                f"Chain: {chain}"
            )
        
        # Cache instance
        self._web3_instances[cache_key] = w3
        
        proxy_info = f" | Proxy: wallet_{wallet_id}" if wallet_id else " | Direct"
        logger.debug(f"Web3 connected | Chain: {chain} | RPC: {rpc_url[:50]}... | Chain ID: {actual_chain_id}{proxy_info}")
        return w3
    
    def _decrypt_private_key(self, encrypted_key: str) -> str:
        """
        Decrypt private key from database.
        
        Args:
            encrypted_key: Encrypted private key (base64 string)
        
        Returns:
            Decrypted private key (hex string)
        """
        try:
            return self.fernet.decrypt(encrypted_key.encode()).decode()
        except Exception as e:
            logger.error(f"Failed to decrypt private key | Error: {e}")
            raise ValueError("Invalid encryption key or corrupted private key")
    
    def _get_wallet_account(self, wallet_id: int) -> Tuple[LocalAccount, str]:
        """
        Get LocalAccount and address for wallet.
        
        Args:
            wallet_id: Wallet database ID
        
        Returns:
            (LocalAccount, address) tuple
        """
        # Get encrypted private key from DB
        query = "SELECT address, encrypted_private_key FROM wallets WHERE id = %s"
        result = self.db.execute_query(query, (wallet_id,), fetch='one')
        
        if not result:
            raise ValueError(f"Wallet not found: {wallet_id}")
        
        # Decrypt private key
        private_key = self._decrypt_private_key(result['encrypted_private_key'])
        
        # Create LocalAccount
        account = Account.from_key(private_key)
        
        # Verify address match
        if account.address.lower() != result['address']:
            raise ValueError(
                f"Address mismatch | DB: {result['address']}, Derived: {account.address}"
            )
        
        logger.debug(f"Wallet account loaded | ID: {wallet_id} | Address: {account.address[:10]}...")
        return account, result['address']
    
    def _estimate_gas(
        self,
        w3: Web3,
        transaction: Dict[str, Any],
        safety_multiplier: float = 1.2
    ) -> int:
        """
        Estimate gas для transaction с anti-fingerprinting protection.
        
        Args:
            w3: Web3 instance
            transaction: Transaction dict
            safety_multiplier: Base safety margin (default 1.2 = +20%)
        
        Returns:
            Estimated gas limit with Gaussian randomization (integer)
        
        Anti-Sybil Strategy:
            Uses Gaussian noise to vary gas limit by ±2.5%, preventing
            transaction linking via consistent gas_limit values.
        """
        import numpy as np
        
        try:
            estimated = w3.eth.estimate_gas(transaction)
            
            # Anti-Sybil: Gaussian noise randomization for gas limit (±2.5%)
            # Prevents fingerprinting by varying gas limit
            noise = np.random.normal(1.0, 0.025)  # mean=1.0, std=2.5%
            dynamic_multiplier = safety_multiplier * max(0.96, min(1.04, noise))  # clip to 0.96-1.04
            gas_limit = int(estimated * dynamic_multiplier)
            
            logger.debug(
                f"Gas estimated | Estimated: {estimated} | "
                f"Dynamic multiplier: {dynamic_multiplier:.4f} | "
                f"Final gas_limit: {gas_limit}"
            )
            
            return gas_limit
        
        except Exception as e:
            logger.error(f"Gas estimation failed | Error: {e}")
            raise GasEstimationError(f"Gas estimation failed: {e}")
    
    def _get_gas_prices(
        self,
        w3: Web3,
        gas_preference: str = 'normal'
    ) -> Dict[str, int]:
        """
        Get gas prices для EIP-1559 transaction.
        
        Args:
            w3: Web3 instance
            gas_preference: 'slow', 'normal', or 'fast'
        
        Returns:
            Dict with maxFeePerGas and maxPriorityFeePerGas (in wei)
        """
        try:
            # Get current base fee
            latest_block = w3.eth.get_block('latest')
            base_fee = latest_block.get('baseFeePerGas', 0)
            
            # Get priority fee suggestion
            try:
                priority_fee = w3.eth.max_priority_fee
            except:
                # Fallback to 1 gwei if maxPriorityFee not supported
                priority_fee = w3.to_wei(1, 'gwei')
            
            # Adjust based on preference
            if gas_preference == 'slow':
                multiplier = 0.8
                priority_multiplier = 0.9
            elif gas_preference == 'fast':
                multiplier = 1.3
                priority_multiplier = 1.5
            else:  # normal
                multiplier = 1.0
                priority_multiplier = 1.0
            
            # Anti-Sybil: Use Gaussian distribution for gas randomization (±5%)
            # mean=1.0, std=0.025 (so 95% within 0.95-1.05)
            random_factor = np.random.normal(1.0, 0.025)
            random_factor = max(0.95, min(1.05, random_factor))  # clip to 0.95-1.05
            
            # Calculate max fee (base fee + priority fee + buffer)
            max_priority_fee = int(priority_fee * priority_multiplier * random_factor)
            max_fee = int((base_fee * 2 + max_priority_fee) * multiplier)
            
            logger.debug(
                f"Gas prices calculated | Base: {w3.from_wei(base_fee, 'gwei'):.2f} gwei | "
                f"Priority: {w3.from_wei(max_priority_fee, 'gwei'):.2f} gwei | "
                f"Max Fee: {w3.from_wei(max_fee, 'gwei'):.2f} gwei | "
                f"Preference: {gas_preference}"
            )
            
            return {
                'maxFeePerGas': max_fee,
                'maxPriorityFeePerGas': max_priority_fee
            }
        
        except Exception as e:
            logger.warning(f"EIP-1559 gas price failed, fallback to legacy | Error: {e}")
            
            # Fallback to legacy gas price
            gas_price = w3.eth.gas_price
            
            if gas_preference == 'slow':
                gas_price = int(gas_price * 0.8)
            elif gas_preference == 'fast':
                gas_price = int(gas_price * 1.3)
            
            return {'gasPrice': gas_price}
    
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        retry=retry_if_exception_type(NonceConflictError),
        reraise=True
    )
    def execute_transaction(
        self,
        wallet_id: int,
        chain: str,
        to_address: str,
        value_wei: int = 0,
        data: str = '0x',
        gas_preference: str = 'normal',
        max_wait_seconds: int = 300
    ) -> Dict[str, Any]:
        """
        Execute on-chain transaction.
        
        Args:
            wallet_id: Wallet database ID
            chain: Chain name (arbitrum, base, etc.)
            to_address: Contract/recipient address
            value_wei: Value to send in wei (default 0)
            data: Transaction data (hex string, default '0x')
            gas_preference: 'slow', 'normal', or 'fast'
            max_wait_seconds: Max seconds to wait for confirmation
        
        Returns:
            Dict with tx_hash, status, gas_used, block_number
        
        Raises:
            InsufficientBalanceError: Wallet balance too low
            NonceConflictError: Nonce already used
            GasEstimationError: Gas estimation failed
            TransactionTimeoutError: TX not confirmed in time
            TransactionExecutionError: Other execution errors
        """
        logger.info(
            f"Executing transaction | Wallet: {wallet_id} | Chain: {chain} | "
            f"To: {to_address[:10]}... | Value: {value_wei} wei | Gas: {gas_preference}"
        )
        
        # Get wallet account for address
        account, from_address = self._get_wallet_account(wallet_id)
        
        # STEP 1: Always simulate first (dry-run, testnet, mainnet)
        value_eth = Decimal(str(value_wei)) / Decimal('1e18')
        simulation = self.simulator.simulate_transaction(
            wallet_address=from_address,
            chain=chain,
            tx_type='TRANSFER',  # Generic transaction type
            value=value_eth,
            to_address=to_address,
            data=data
        )
        
        # STEP 2: Log simulation result
        logger.info(
            f"Simulation result | Would succeed: {simulation.would_succeed} | "
            f"Gas: {simulation.estimated_gas} | Cost: ${simulation.estimated_cost_usd:.4f}"
        )
        
        if simulation.warnings:
            for warning in simulation.warnings:
                logger.warning(f"Simulation warning: {warning}")
        
        # STEP 3: Check mode - return early if dry-run
        if is_dry_run():
            logger.info(
                f"[DRY-RUN] Transaction simulated | Wallet: {wallet_id} | "
                f"Chain: {chain} | To: {to_address[:10]}... | Value: {value_wei} wei"
            )
            # Return simulation as dict for compatibility
            return {
                'would_succeed': simulation.would_succeed,
                'failure_reason': simulation.failure_reason,
                'gas_estimate': simulation.gas_estimate,
                'gas_price_gwei': simulation.gas_price_gwei,
                'total_cost_eth': simulation.total_cost_eth,
                'warnings': simulation.warnings
            }
        
        # STEP 4: Check if simulation passed (required for testnet/mainnet execution)
        if not simulation.would_succeed:
            logger.error(f"Simulation failed: {simulation.failure_reason}")
            raise TransactionSimulationFailed(simulation.failure_reason)
        
        # STEP 5: Safety check for mainnet
        if is_mainnet():
            try:
                self.network_mode.check_mainnet_allowed(self.db)
                logger.success("Mainnet safety gates: PASSED")
            except Exception as e:
                logger.error(f"Mainnet safety gates: FAILED | {e}")
                raise MainnetNotAllowed(str(e))
        
        # STEP 6: Proceed with actual transaction execution
        # Get Web3 instance WITH wallet's assigned proxy
        w3 = self._get_web3(chain, wallet_id=wallet_id)
        
        # CRITICAL: Anti-Sybil guard against internal wallet-to-wallet transfers
        # Check if destination is another farm wallet (violates CEX-only funding rule)
        to_address_lower = to_address.lower()
        internal_wallet_check = self.db.execute_query(
            "SELECT id FROM wallets WHERE address = %s",
            (to_address_lower,),
            fetch='one'
        )
        
        if internal_wallet_check:
            raise TransactionExecutionError(
                f"Internal transfer blocked: destination {to_address[:10]}... is another farm wallet. "
                f"Only CEX-to-wallet funding allowed. Use protocol contracts only."
            )
        
        # Check balance
        balance = w3.eth.get_balance(from_address)
        if balance < value_wei:
            raise InsufficientBalanceError(
                f"Insufficient balance | Have: {w3.from_wei(balance, 'ether')} | "
                f"Need: {w3.from_wei(value_wei, 'ether')}"
            )
        
        # CRITICAL: Acquire per-wallet nonce lock (prevent race conditions)
        if wallet_id not in self._nonce_locks:
            self._nonce_locks[wallet_id] = threading.Lock()
        
        with self._nonce_locks[wallet_id]:
            # Get nonce (thread-safe, inside lock)
            nonce = w3.eth.get_transaction_count(from_address, 'pending')
        
            # Build transaction (still inside nonce lock)
            transaction = {
                'from': from_address,
                'to': Web3.to_checksum_address(to_address),
                'value': value_wei,
                'data': data,
                'nonce': nonce,
                'chainId': w3.eth.chain_id
            }
            
            # Add gas prices
            gas_prices = self._get_gas_prices(w3, gas_preference)
            transaction.update(gas_prices)
            
            # Estimate gas
            try:
                gas_limit = self._estimate_gas(w3, transaction)
                transaction['gas'] = gas_limit
            except GasEstimationError as e:
                logger.error(f"Gas estimation failed | TX: {transaction}")
                raise
            
            # Check if we have enough balance for gas
            if 'maxFeePerGas' in transaction:
                max_gas_cost = gas_limit * transaction['maxFeePerGas']
            else:
                max_gas_cost = gas_limit * transaction.get('gasPrice', 0)
            
            total_cost = value_wei + max_gas_cost
            
            if balance < total_cost:
                raise InsufficientBalanceError(
                    f"Insufficient balance for gas | Balance: {w3.from_wei(balance, 'ether')} | "
                    f"Need: {w3.from_wei(total_cost, 'ether')} (value + gas)"
                )
            
            # Sign transaction
            try:
                signed_tx = account.sign_transaction(transaction)
            except Exception as e:
                logger.error(f"Transaction signing failed | Error: {e}")
                raise TransactionExecutionError(f"Signing failed: {e}")
            
            # Send transaction
            try:
                tx_hash = w3.eth.send_raw_transaction(signed_tx.rawTransaction)
                tx_hash_hex = tx_hash.hex()
                
                logger.info(
                    f"Transaction sent | Hash: {tx_hash_hex} | "
                    f"Nonce: {nonce} | Chain: {chain}"
                )
            
            except ValueError as e:
                error_message = str(e)
                
                # Check for nonce conflict (too low OR too high)
                if 'nonce too low' in error_message.lower() or 'already known' in error_message.lower():
                    logger.warning(f"Nonce too low detected | Nonce: {nonce} | Retrying...")
                    raise NonceConflictError(f"Nonce conflict: {error_message}")
                
                if 'nonce too high' in error_message.lower():
                    # Refetch pending nonce and retry
                    logger.warning(f"Nonce too high detected | Used: {nonce} | Refetching pending nonce...")
                    raise NonceConflictError(f"Nonce too high: {error_message}")
                
                # Check for insufficient funds (shouldn't happen after balance check)
                if 'insufficient funds' in error_message.lower():
                    raise InsufficientBalanceError(f"Insufficient funds: {error_message}")
                
                # Other errors
                logger.error(f"Transaction send failed | Error: {error_message}")
                raise TransactionExecutionError(f"Send failed: {error_message}")
        
        # Wait for receipt
        start_time = time.time()
        receipt = None
        
        while time.time() - start_time < max_wait_seconds:
            try:
                receipt = w3.eth.get_transaction_receipt(tx_hash)
                break
            except Exception:
                # Transaction not mined yet
                time.sleep(2)
        
        if not receipt:
            raise TransactionTimeoutError(
                f"Transaction not confirmed within {max_wait_seconds}s | Hash: {tx_hash_hex}"
            )
        
        # Check status
        status = receipt.get('status', 0)
        gas_used = receipt.get('gasUsed', 0)
        block_number = receipt.get('blockNumber', 0)
        
        if status == 1:
            logger.success(
                f"Transaction confirmed | Hash: {tx_hash_hex} | "
                f"Block: {block_number} | Gas: {gas_used} | Chain: {chain}"
            )
        else:
            logger.error(
                f"Transaction failed | Hash: {tx_hash_hex} | "
                f"Block: {block_number} | Chain: {chain}"
            )
        
        return {
            'tx_hash': tx_hash_hex,
            'status': 'confirmed' if status == 1 else 'failed',
            'gas_used': gas_used,
            'block_number': block_number,
            'chain': chain,
            'from_address': from_address,
            'to_address': to_address,
            'value_wei': value_wei,
            'nonce': nonce,
            'confirmed_at': datetime.now(timezone.utc)
        }
    
    def execute_contract_function(
        self,
        wallet_id: int,
        protocol_action_id: int,
        params: Dict[str, Any],
        gas_preference: str = 'normal'
    ) -> Dict[str, Any]:
        """
        Execute protocol action (swap, stake, etc.) via smart contract.
        
        Production implementation with dynamic function calling.
        
        Args:
            wallet_id: Wallet database ID
            protocol_action_id: Protocol action ID from DB
            params: Function parameters (amounts, addresses, slippage, etc.)
            gas_preference: Gas preference
        
        Returns:
            Transaction result dict
        
        Raises:
            ValueError: Protocol action not found or invalid
            TransactionExecutionError: Contract execution failed
        
        Example params for SWAP:
            {
                'amount_in': 10000000000000000,  # 0.01 ETH in wei
                'token_out': '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                'slippage': 0.5,  # 0.5%
                'recipient': None  # Uses from_address if None
            }
        """
        logger.info(
            f"Executing protocol action | Wallet: {wallet_id} | "
            f"Action: {protocol_action_id} | Params: {params}"
        )
        
        # Get protocol action details
        action_query = """
            SELECT pa.tx_type, pa.chain, pa.function_signature, pa.default_params,
                   pc.contract_address, pc.abi, p.name as protocol_name
            FROM protocol_actions pa
            JOIN protocol_contracts pc ON pc.id = pa.contract_id
            JOIN protocols p ON p.id = pa.protocol_id
            WHERE pa.id = %s AND pa.is_enabled = TRUE
        """
        action = self.db.execute_query(action_query, (protocol_action_id,), fetch='one')
        
        if not action:
            raise ValueError(f"Protocol action not found or disabled: {protocol_action_id}")
        
        tx_type = action['tx_type']
        chain = action['chain']
        contract_address = action['contract_address']
        function_signature = action['function_signature']
        protocol_name = action.get('protocol_name', 'Unknown')
        
        # =================================================================
        # PROTOCOL ACTION RESOLVER (Module 1) - Auto-fix tx_type
        # =================================================================
        try:
            from research.protocol_analyzer import ProtocolAnalyzer
            
            # Use sync instantiation instead of async context
            analyzer = ProtocolAnalyzer(db_manager=self.db)
            # Resolve allowed actions for this protocol (sync call)
            # Note: resolve_action_type may need sync version
            try:
                action_resolution = analyzer.resolve_action_type_sync(protocol_name, chain)
            except AttributeError:
                # Fallback if sync version not available
                action_resolution = {'allowed_actions': ['SWAP']}
            allowed_actions = action_resolution.get('allowed_actions', ['SWAP'])
            
            # Check if requested tx_type is allowed
            if tx_type not in allowed_actions:
                # Auto-fix: use first allowed action
                original_type = tx_type
                fixed_type = allowed_actions[0]
                
                logger.warning(
                    f"Auto-fix: {original_type} → {fixed_type} for {protocol_name} "
                    f"(not in allowed actions: {allowed_actions})"
                )
                
                # Update tx_type to fixed type
                tx_type = fixed_type
        except Exception as e:
            logger.warning(f"Failed to resolve action type for {protocol_name}: {e}. Using original tx_type.")
        
        # Get Web3 instance
        w3 = self._get_web3(chain)
        
        # Get wallet account
        account, from_address = self._get_wallet_account(wallet_id)
        
        # Merge default params with provided params
        default_params = action.get('default_params', {})
        merged_params = {**default_params, **params}
        
        # Set recipient to from_address if not specified
        if 'recipient' not in merged_params or merged_params['recipient'] is None:
            merged_params['recipient'] = from_address
        
        # Build contract instance
        contract_abi = action.get('abi', [])
        contract = w3.eth.contract(
            address=Web3.to_checksum_address(contract_address),
            abi=contract_abi
        )
        
        # Parse function signature to extract function name and param types
        # Example: "swapExactETHForTokens(uint256,address[],address,uint256)"
        function_name = function_signature.split('(')[0]
        
        try:
            # Build transaction based on tx_type
            transaction_data = self._build_contract_call(
                w3=w3,
                contract=contract,
                function_name=function_name,
                tx_type=tx_type,
                params=merged_params,
                from_address=from_address
            )
            
            # Execute transaction
            result = self.execute_transaction(
                wallet_id=wallet_id,
                chain=chain,
                to_address=contract_address,
                value_wei=transaction_data['value'],
                data=transaction_data['data'],
                gas_preference=gas_preference
            )
            
            # Log to database
            self._log_transaction_to_db(wallet_id, protocol_action_id, result)
            
            return result
        
        except Exception as e:
            logger.error(
                f"Contract function execution failed | "
                f"Wallet: {wallet_id} | Action: {protocol_action_id} | Error: {e}"
            )
            raise TransactionExecutionError(f"Contract execution failed: {e}")
    
    async def execute_bridge_transaction(
        self,
        wallet_id: int,
        from_network: str,
        to_network: str,
        amount_eth: Decimal,
        telegram: Optional[Any] = None
    ) -> Dict[str, Any]:
        """
        Execute bridge transaction using Bridge Manager v2.0.
        
        This method integrates with BridgeManager for:
        - Dynamic CEX support checking (no hardcoded lists!)
        - Finding best bridge route via aggregators
        - DeFiLlama safety verification
        - Transaction execution and logging
        
        Args:
            wallet_id: Wallet database ID
            from_network: Source network (e.g., 'Arbitrum')
            to_network: Destination network (e.g., 'Ink') - ANY L2!
            amount_eth: Amount to bridge in ETH
            telegram: Optional TelegramBot for notifications
        
        Returns:
            Dict with bridge result:
            {
                'success': bool,
                'tx_hash': str,
                'provider': str,
                'cost_usd': float,
                'safety_score': int
            }
        
        Raises:
            BridgeError: If bridge operation fails
            BridgeNotAvailableError: No route found
            BridgeSafetyError: Route failed safety check
        
        Example:
            >>> executor = TransactionExecutor()
            >>> result = await executor.execute_bridge_transaction(
            ...     wallet_id=1,
            ...     from_network='Arbitrum',
            ...     to_network='Ink',
            ...     amount_eth=Decimal('0.05')
            ... )
        """
        logger.info(
            f"Executing bridge transaction | Wallet: {wallet_id} | "
            f"{from_network} → {to_network} | Amount: {amount_eth} ETH"
        )
        
        # Initialize BridgeManager
        bridge_manager = BridgeManager(
            db=self.db,
            telegram=telegram,
            fernet_key=os.getenv('FERNET_KEY'),
            dry_run=is_dry_run()
        )
        
        # Execute bridge via BridgeManager
        result = await bridge_manager.execute_bridge(
            wallet_id=wallet_id,
            from_network=from_network,
            to_network=to_network,
            amount_eth=amount_eth
        )
        
        if not result.success:
            raise BridgeError(f"Bridge failed: {result.error}")
        
        return {
            'success': result.success,
            'tx_hash': result.tx_hash,
            'provider': result.provider,
            'cost_usd': result.cost_usd,
            'safety_score': result.safety_score
        }
    
    async def check_bridge_required(
        self,
        network: str
    ) -> Tuple[bool, Optional[str]]:
        """
        Check if bridge is required for a network using dynamic CEX checking.
        
        This is a convenience method that delegates to CEXNetworkChecker.
        
        Args:
            network: Network name to check (e.g., 'Base', 'Ink', 'FutureL2')
        
        Returns:
            (bridge_required, cex_name_or_none)
            
        Example:
            >>> executor = TransactionExecutor()
            >>> required, cex = await executor.check_bridge_required("Base")
            >>> print(required, cex)
            False, "bybit"  # Base is supported by Bybit
        """
        bridge_manager = BridgeManager(db=self.db, dry_run=True)
        return await bridge_manager.is_bridge_required(network)
    
    def _build_contract_call(
        self,
        w3: Web3,
        contract: Any,
        function_name: str,
        tx_type: str,
        params: Dict[str, Any],
        from_address: str
    ) -> Dict[str, Any]:
        """
        Build contract function call dynamically.
        
        Args:
            w3: Web3 instance
            contract: Contract instance
            function_name: Function name to call
            tx_type: Transaction type (SWAP, WRAP, APPROVE, etc.)
            params: Function parameters
            from_address: Caller address
        
        Returns:
            Dict with 'value' (wei) and 'data' (hex)
        
        Raises:
            AttributeError: Function not found in contract ABI
            ValueError: Invalid parameters
        """
        # Get contract function
        try:
            contract_function = getattr(contract.functions, function_name)
        except AttributeError:
            raise ValueError(f"Function '{function_name}' not found in contract ABI")
        
        # Build function call based on tx_type
        if tx_type == 'SWAP':
            return self._build_swap_call(w3, contract_function, params, from_address)
        
        elif tx_type == 'WRAP':
            return self._build_wrap_call(contract_function, params, from_address)
        
        elif tx_type == 'APPROVE':
            return self._build_approve_call(contract_function, params, from_address)
        
        elif tx_type == 'STAKE':
            return self._build_stake_call(contract_function, params, from_address)
        
        elif tx_type == 'LP':
            return self._build_lp_call(w3, contract_function, params, from_address)
        
        elif tx_type == 'BRIDGE':
            return self._build_bridge_call(w3, contract_function, params, from_address)
        
        elif tx_type == 'NFT_MINT':
            return self._build_nft_mint_call(contract_function, params, from_address)
        
        else:
            # Generic fallback для unknown types
            return self._build_generic_call(contract_function, params, from_address)
    
    def _build_swap_call(
        self,
        w3: Web3,
        function: Any,
        params: Dict[str, Any],
        from_address: str
    ) -> Dict[str, Any]:
        """Build SWAP transaction call."""
        import time
        
        amount_in = params.get('amount_in', 0)
        slippage = params.get('slippage', 0.5)
        recipient = params.get('recipient', from_address)
        deadline = params.get('deadline', int(time.time()) + 1200)  # 20 min
        
        # Calculate min amount out (with slippage)
        amount_out_min = int(amount_in * (1 - slippage / 100))
        
        # Build path
        if 'path' in params:
            path = params['path']
        elif 'token_out' in params:
            # Auto-build path: WETH → Token
            from .tx_types import SwapBuilder
            builder = SwapBuilder(w3)
            weth_address = builder._get_weth_address()
            path = [weth_address, params['token_out']]
        else:
            raise ValueError("Missing 'path' or 'token_out' parameter for SWAP")
        
        # Convert addresses to checksum
        path = [Web3.to_checksum_address(addr) for addr in path]
        recipient = Web3.to_checksum_address(recipient)
        
        # Build function call
        function_call = function(
            amount_out_min,
            path,
            recipient,
            deadline
        )
        
        # Build transaction
        tx = function_call.build_transaction({
            'from': from_address,
            'value': amount_in,
            'gas': 0,  # Will be estimated
            'nonce': 0  # Will be set by executor
        })
        
        logger.debug(f"SWAP call built | Amount in: {amount_in} | Min out: {amount_out_min} | Slippage: {slippage}%")
        
        return {
            'value': amount_in,
            'data': tx['data']
        }
    
    def _build_wrap_call(
        self,
        function: Any,
        params: Dict[str, Any],
        from_address: str
    ) -> Dict[str, Any]:
        """Build WRAP/UNWRAP transaction call."""
        amount = params.get('amount', 0)
        is_wrap = params.get('is_wrap', True)  # True = ETH→WETH, False = WETH→ETH
        
        if is_wrap:
            # deposit() — no params needed, just send ETH
            function_call = function()
            tx = function_call.build_transaction({
                'from': from_address,
                'value': amount,
                'gas': 0,
                'nonce': 0
            })
            
            logger.debug(f"WRAP call built | Amount: {amount}")
            return {'value': amount, 'data': tx['data']}
        
        else:
            # withdraw(uint256 wad)
            function_call = function(amount)
            tx = function_call.build_transaction({
                'from': from_address,
                'value': 0,
                'gas': 0,
                'nonce': 0
            })
            
            logger.debug(f"UNWRAP call built | Amount: {amount}")
            return {'value': 0, 'data': tx['data']}
    
    def _build_approve_call(
        self,
        function: Any,
        params: Dict[str, Any],
        from_address: str
    ) -> Dict[str, Any]:
        """Build APPROVE transaction call."""
        spender = params.get('spender')
        amount = params.get('amount', 2**256 - 1)  # Infinite if not specified
        
        if not spender:
            raise ValueError("Missing 'spender' parameter for APPROVE")
        
        spender = Web3.to_checksum_address(spender)
        
        function_call = function(spender, amount)
        tx = function_call.build_transaction({
            'from': from_address,
            'value': 0,
            'gas': 0,
            'nonce': 0
        })
        
        logger.debug(f"APPROVE call built | Spender: {spender[:10]}... | Amount: {amount}")
        return {'value': 0, 'data': tx['data']}
    
    def _build_stake_call(
        self,
        function: Any,
        params: Dict[str, Any],
        from_address: str
    ) -> Dict[str, Any]:
        """Build STAKE transaction call (generic implementation)."""
        amount = params.get('amount', 0)
        
        # Most staking functions accept amount parameter
        function_call = function(amount)
        tx = function_call.build_transaction({
            'from': from_address,
            'value': amount,  # For ETH staking
            'gas': 0,
            'nonce': 0
        })
        
        logger.debug(f"STAKE call built | Amount: {amount}")
        return {'value': amount, 'data': tx['data']}
    
    def _build_lp_call(
        self,
        w3: Web3,
        function: Any,
        params: Dict[str, Any],
        from_address: str
    ) -> Dict[str, Any]:
        """Build LP (add liquidity) transaction call."""
        token_a = params.get('token_a')
        token_b = params.get('token_b')
        amount_a = params.get('amount_a', 0)
        amount_b = params.get('amount_b', 0)
        amount_a_min = params.get('amount_a_min', int(amount_a * 0.995))
        amount_b_min = params.get('amount_b_min', int(amount_b * 0.995))
        recipient = params.get('recipient', from_address)
        deadline = params.get('deadline', int(time.time()) + 1200)
        
        # Convert to checksum
        token_a = Web3.to_checksum_address(token_a)
        token_b = Web3.to_checksum_address(token_b)
        recipient = Web3.to_checksum_address(recipient)
        
        # Typical Uniswap V2 addLiquidity signature
        function_call = function(
            token_a,
            token_b,
            amount_a,
            amount_b,
            amount_a_min,
            amount_b_min,
            recipient,
            deadline
        )
        
        tx = function_call.build_transaction({
            'from': from_address,
            'value': 0,  # Unless adding ETH liquidity
            'gas': 0,
            'nonce': 0
        })
        
        logger.debug(f"LP call built | Amount A: {amount_a} | Amount B: {amount_b}")
        return {'value': 0, 'data': tx['data']}
    
    def _build_bridge_call(
        self,
        w3: Web3,
        function: Any,
        params: Dict[str, Any],
        from_address: str
    ) -> Dict[str, Any]:
        """Build BRIDGE transaction call (generic implementation)."""
        amount = params.get('amount', 0)
        chain_id = params.get('destination_chain_id')
        recipient = params.get('recipient', from_address)
        
        # Example Stargate/LayerZero pattern
        function_call = function(
            chain_id,
            Web3.to_checksum_address(recipient),
            amount
        )
        
        tx = function_call.build_transaction({
            'from': from_address,
            'value': amount,
            'gas': 0,
            'nonce': 0
        })
        
        logger.debug(f"BRIDGE call built | Amount: {amount} | To chain: {chain_id}")
        return {'value': amount, 'data': tx['data']}
    
    def _build_nft_mint_call(
        self,
        function: Any,
        params: Dict[str, Any],
        from_address: str
    ) -> Dict[str, Any]:
        """Build NFT_MINT transaction call."""
        quantity = params.get('quantity', 1)
        mint_price = params.get('mint_price', 0)
        total_value = mint_price * quantity
        
        # Most NFT mints accept quantity parameter
        function_call = function(quantity)
        tx = function_call.build_transaction({
            'from': from_address,
            'value': total_value,
            'gas': 0,
            'nonce': 0
        })
        
        logger.debug(f"NFT_MINT call built | Quantity: {quantity} | Price: {mint_price}")
        return {'value': total_value, 'data': tx['data']}
    
    def _build_generic_call(
        self,
        function: Any,
        params: Dict[str, Any],
        from_address: str
    ) -> Dict[str, Any]:
        """
        Build generic contract call (fallback).
        
        Attempts to call function with params as positional args.
        """
        args = params.get('args', [])
        value = params.get('value', 0)
        
        function_call = function(*args)
        tx = function_call.build_transaction({
            'from': from_address,
            'value': value,
            'gas': 0,
            'nonce': 0
        })
        
        logger.debug(f"GENERIC call built | Args: {args} | Value: {value}")
        return {'value': value, 'data': tx['data']}
    
    def _log_transaction_to_db(
        self,
        wallet_id: int,
        protocol_action_id: int,
        tx_result: Dict[str, Any]
    ):
        """
        Log transaction result to database.
        
        Args:
            wallet_id: Wallet database ID
            protocol_action_id: Protocol action ID
            tx_result: Transaction result from execute_transaction()
        """
        try:
            query = """
                INSERT INTO wallet_transactions (
                    wallet_id, protocol_action_id, tx_hash, chain,
                    from_address, to_address, value, gas_used,
                    status, block_number, confirmed_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """
            
            self.db.execute_query(
                query,
                (
                    wallet_id,
                    protocol_action_id,
                    tx_result['tx_hash'],
                    tx_result['chain'],
                    tx_result['from_address'],
                    tx_result['to_address'],
                    str(tx_result['value_wei']),
                    tx_result['gas_used'],
                    tx_result['status'],
                    tx_result['block_number'],
                    tx_result['confirmed_at']
                )
            )
            
            logger.debug(f"Transaction logged to DB | Hash: {tx_result['tx_hash']}")
        
        except Exception as e:
            logger.error(f"Failed to log transaction to DB | Error: {e}")
            # Non-critical — не поднимаем exception


# =============================================================================
# CLI INTERFACE (для тестирования)
# =============================================================================

def main():
    """CLI entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Transaction Executor Module 12')
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    # Test simple transfer
    test_parser = subparsers.add_parser('test-transfer', help='Test simple ETH transfer')
    test_parser.add_argument('--wallet-id', type=int, required=True, help='Wallet ID')
    test_parser.add_argument('--chain', type=str, required=True, help='Chain name (arbitrum, base, etc.)')
    test_parser.add_argument('--to', type=str, required=True, help='Recipient address')
    test_parser.add_argument('--amount', type=float, required=True, help='Amount in ETH')
    test_parser.add_argument('--gas', type=str, default='normal', help='Gas preference (slow/normal/fast)')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    try:
        executor = TransactionExecutor()
        
        if args.command == 'test-transfer':
            w3 = executor._get_web3(args.chain)
            value_wei = w3.to_wei(args.amount, 'ether')
            
            result = executor.execute_transaction(
                wallet_id=args.wallet_id,
                chain=args.chain,
                to_address=args.to,
                value_wei=value_wei,
                gas_preference=args.gas
            )
            
            print(f"\n✅ Transaction successful")
            print(f"   Hash: {result['tx_hash']}")
            print(f"   Block: {result['block_number']}")
            print(f"   Gas used: {result['gas_used']}")
            print(f"   Status: {result['status']}")
    
    except Exception as e:
        logger.exception(f"Execution failed: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
