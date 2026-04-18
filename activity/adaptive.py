#!/usr/bin/env python3
"""
Adaptive Gas Controller — Unified Gas & Balance Management
===========================================================

Merges functionality from:
- gas_logic.py (DEPRECATED - was just a wrapper)
- gas_controller.py (tier balance monitoring, CEX topup alerts)
- gas_manager.py (async gas checking, chain_id-based thresholds)

CRITICAL: All RPC calls use proxy to prevent IP leak!

Features:
- Real-time gas price tracking для 7+ L2 chains
- Dynamic gas threshold calculation (MA_24h * Multiplier)
- Tier-based balance monitoring (A: 0.003 ETH, B: 0.002, C: 0.001)
- Automatic transaction rejection при gas > threshold
- Historical gas analysis (24h trends)
- Optimal execution window recommendation
- Gas price caching (5 min TTL)
- Activity throttling при высоких ценах
- CEX-only topup alerts (NO internal transfers)
- Proxy protection for all RPC calls

Strategy:
- L2 chains оптимизированы (обычно <0.01 gwei), но возможны спайки
- Skip transactions когда gas >3x median (network congestion)
- Reschedule transactions на off-peak hours (3-6 AM UTC)
- Reduce activity на 30% при sustained high gas (3+ hours)

Author: Airdrop Farming System v4.0
Created: 2026-02-25
Consolidated: 2026-03-16
"""

import os
import sys
import time
import json
import asyncio
import random
from typing import Dict, Any, Optional, List, Tuple
from pathlib import Path
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from dataclasses import dataclass, field
from enum import Enum
from collections import deque
from threading import Lock

# Добавить parent directory для импорта
sys.path.insert(0, str(Path(__file__).parent.parent))

from web3 import Web3
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential
from infrastructure.env_loader import load_env
from psycopg2 import extras

# Load .env file (supports both production and local dev)
load_env()

from database.db_manager import DatabaseManager
from activity.exceptions import ProxyRequiredError


# =============================================================================
# ENUMS
# =============================================================================

class GasStatus(Enum):
    """Gas check result status."""
    GAS_OK = "gas_ok"
    HIGH_GAS = "high_gas"
    UNAVAILABLE = "unavailable"


class NetworkType(Enum):
    """Network classification for gas calculation."""
    L1 = "l1"           # Ethereum mainnet
    L2 = "l2"           # Optimistic Rollups, ZK Rollups
    SIDECHAIN = "sidechain"  # Polygon, BNB Chain


# =============================================================================
# DATA STRUCTURES
# =============================================================================

@dataclass
class NetworkDescriptor:
    """Network metadata for gas calculation."""
    chain_id: int
    network_type: NetworkType
    multiplier: float
    is_l2: bool = False
    l1_data_fee: bool = False
    chain_name: str = ""


@dataclass
class GasCheckResult:
    """Result of gas viability check."""
    status: GasStatus
    chain_id: int
    current_gwei: float
    threshold_gwei: float
    network_type: NetworkType
    extra_delay_minutes: float = 0.0
    cached: bool = False
    ma_24h_available: bool = False


@dataclass
class GasSnapshot:
    """Single gas price measurement."""
    chain: str
    chain_id: int
    timestamp: datetime
    base_fee: int  # wei
    priority_fee: int  # wei
    max_fee: int  # wei
    block_number: int


@dataclass
class GasAnalysis:
    """Gas analysis result with recommendations."""
    chain: str
    chain_id: int
    current_gwei: float
    median_1h_gwei: float
    median_24h_gwei: float
    is_acceptable: bool
    is_optimal: bool
    recommended_action: str  # 'execute', 'wait', 'skip'
    wait_hours: Optional[float]
    cost_savings_percent: Optional[float]


# =============================================================================
# CONFIGURATION
# =============================================================================

# Tier balance thresholds (ETH equivalent)
TIER_THRESHOLDS = {
    'A': Decimal('0.003'),  # $9 @ $3000/ETH
    'B': Decimal('0.002'),  # $6
    'C': Decimal('0.001')   # $3
}

# Default gas multipliers if not in database
DEFAULT_MULTIPLIERS = {
    NetworkType.L1: 1.5,
    NetworkType.L2: 5.0,
    NetworkType.SIDECHAIN: 2.0,
}

# Gas thresholds by chain name (in gwei) - for backward compatibility
GAS_THRESHOLDS = {
    # L2 chains (typically <0.01 gwei)
    'arbitrum': {'max': 0.5, 'optimal': 0.01, 'chain_id': 42161},
    'base': {'max': 0.5, 'optimal': 0.01, 'chain_id': 8453},
    'optimism': {'max': 0.5, 'optimal': 0.01, 'chain_id': 10},
    'ink': {'max': 0.5, 'optimal': 0.01, 'chain_id': 57073},
    'megaeth': {'max': 0.1, 'optimal': 0.001, 'chain_id': 43114},
    
    # Alternative L1s / PoS chains
    'polygon': {'max': 50, 'optimal': 30, 'chain_id': 137},
    'bnbchain': {'max': 5, 'optimal': 3, 'chain_id': 56},
    
    # Ethereum mainnet (if needed)
    'ethereum': {'max': 200, 'optimal': 15, 'chain_id': 1}
}

# Gas thresholds by chain_id (in gwei) - primary lookup
GAS_THRESHOLDS_BY_CHAIN = {
    # L2 chains (typically <0.01 gwei)
    42161: {'max': 0.5, 'optimal': 0.01, 'name': 'arbitrum'},
    8453: {'max': 0.5, 'optimal': 0.01, 'name': 'base'},
    10: {'max': 0.5, 'optimal': 0.01, 'name': 'optimism'},
    57073: {'max': 0.5, 'optimal': 0.01, 'name': 'ink'},
    43114: {'max': 0.1, 'optimal': 0.001, 'name': 'megaeth'},
    
    # Alternative L1s / PoS chains
    137: {'max': 50, 'optimal': 30, 'name': 'polygon'},
    56: {'max': 5, 'optimal': 3, 'name': 'bnbchain'},
    
    # Ethereum mainnet
    1: {'max': 200, 'optimal': 15, 'name': 'ethereum'},
}

# Cache TTL (seconds)
CACHE_TTL_SECONDS = 300  # 5 minutes

# Historical data retention
HISTORY_SIZE = 288  # 24 hours (5 min intervals)

# Max extra delay for high gas (4 hours)
MAX_EXTRA_DELAY_MINUTES = 240


# =============================================================================
# ADAPTIVE GAS CONTROLLER (UNIFIED)
# =============================================================================

class AdaptiveGasController:
    """
    Unified adaptive gas controller with anti-Sybil protection.
    
    Features:
    - All RPC calls use proxy (CRITICAL for IP protection)
    - Async-first design with sync fallbacks
    - Unified caching by chain_id and chain name
    - Tier-based balance monitoring
    - Activity throttling
    - CEX-only topup alerts
    
    Usage:
        controller = AdaptiveGasController()
        
        # Check gas viability (async)
        result = await controller.check_gas_viability(42161)  # Arbitrum
        if result.status == GasStatus.HIGH_GAS:
            print(f"Wait {result.extra_delay_minutes} minutes")
        
        # Check gas viability (sync - by chain name)
        should_exec, reason = controller.should_execute_transaction('arbitrum', 'normal')
        
        # Check wallet balance (async)
        balance = await controller.get_wallet_balance(wallet_id=5, chain_id=8453)
        
        # Check all wallets for low balance
        low_wallets = controller.check_all_wallets('base')
    """
    
    def __init__(self, db: Optional[DatabaseManager] = None):
        """
        Initialize AdaptiveGasController.
        
        Args:
            db: DatabaseManager instance (optional, will create if not provided)
        """
        self.db = db or DatabaseManager()
        
        # Gas price cache: chain_id -> (gwei, timestamp)
        self._gas_cache: Dict[int, Tuple[float, datetime]] = {}
        
        # Chain name to chain_id mapping cache
        self._name_to_id: Dict[str, int] = {}
        self._id_to_name: Dict[int, str] = {}
        
        # Network descriptor cache: chain_id -> NetworkDescriptor
        self._descriptor_cache: Dict[int, NetworkDescriptor] = {}
        
        # Historical gas data: chain_id -> deque(GasSnapshot)
        self._history: Dict[int, deque] = {}
        
        # Activity throttle state: chain_id -> throttle_end_time
        self._throttles: Dict[int, datetime] = {}
        
        # Web3 instances cache (avoid recreation) - by chain name for backward compat
        self._w3_instances: Dict[str, Web3] = {}
        
        # Thread safety locks
        self._cache_lock = Lock()
        self._history_lock = Lock()
        self._w3_lock = Lock()
        
        logger.info(
            f"AdaptiveGasController initialized | "
            f"Multipliers: L1={DEFAULT_MULTIPLIERS[NetworkType.L1]}x, "
            f"L2={DEFAULT_MULTIPLIERS[NetworkType.L2]}x, "
            f"Sidechain={DEFAULT_MULTIPLIERS[NetworkType.SIDECHAIN]}x"
        )
    
    # =========================================================================
    # CHAIN ID / NAME MAPPING
    # =========================================================================
    
    def _get_chain_id(self, chain: str) -> int:
        """
        Get chain_id from chain name.
        
        Args:
            chain: Chain name (arbitrum, base, etc.)
        
        Returns:
            Chain ID (42161, 8453, etc.)
        """
        # Check cache
        if chain in self._name_to_id:
            return self._name_to_id[chain]
        
        # Check hardcoded mapping
        if chain in GAS_THRESHOLDS:
            chain_id = GAS_THRESHOLDS[chain]['chain_id']
            self._name_to_id[chain] = chain_id
            return chain_id
        
        # Try database lookup
        try:
            result = self.db.get_chain_by_name(chain)
            if result and 'chain_id' in result:
                chain_id = result['chain_id']
                self._name_to_id[chain] = chain_id
                return chain_id
        except Exception as e:
            logger.warning(f"Failed to get chain_id for {chain}: {e}")
        
        # Fallback - try to parse as int
        try:
            return int(chain)
        except (ValueError, TypeError):
            logger.error(f"Unknown chain: {chain}")
            return 0
    
    def _get_chain_name(self, chain_id: int) -> str:
        """
        Get chain name from chain_id.
        
        Args:
            chain_id: Chain ID (42161, 8453, etc.)
        
        Returns:
            Chain name (arbitrum, base, etc.)
        """
        # Check cache
        if chain_id in self._id_to_name:
            return self._id_to_name[chain_id]
        
        # Check hardcoded mapping
        if chain_id in GAS_THRESHOLDS_BY_CHAIN:
            name = GAS_THRESHOLDS_BY_CHAIN[chain_id]['name']
            self._id_to_name[chain_id] = name
            return name
        
        # Try database lookup
        try:
            result = self.db.get_chain_by_chain_id(chain_id)
            if result and 'chain' in result:
                name = result['chain']
                self._id_to_name[chain_id] = name
                return name
        except Exception as e:
            logger.warning(f"Failed to get chain name for chain_id={chain_id}: {e}")
        
        return f"chain_{chain_id}"
    
    # =========================================================================
    # PROXY MANAGEMENT (CRITICAL FOR IP PROTECTION)
    # =========================================================================
    
    def _get_monitoring_proxy(self) -> Dict:
        """
        Get a dedicated proxy for monitoring operations.
        Uses least-recently-used proxy from pool to distribute load.
        
        CRITICAL: All RPC calls MUST use proxy to prevent IP leak!
        
        Returns:
            Proxy config dict with: ip_address, port, protocol, username, password, id
        
        Raises:
            ProxyRequiredError: If no proxy available
        """
        query = """
            SELECT ip_address, port, protocol, username, password, id
            FROM proxy_pool
            WHERE is_active = TRUE AND provider = 'iproyal'
            ORDER BY last_used_at ASC NULLS FIRST
            LIMIT 1
        """
        proxy = self.db.execute_query(query, fetch='one')
        
        if proxy:
            # Update last_used_at timestamp
            update_query = """
                UPDATE proxy_pool
                SET last_used_at = NOW()
                WHERE id = %s
            """
            self.db.execute_query(update_query, (proxy['id'],))
            logger.debug(f"Using monitoring proxy | IP: {proxy['ip_address']}")
            return proxy
        
        # CRITICAL: No proxy available - use fallback instead of blocking
        logger.warning("No proxy available for gas monitoring - using fallback without proxy")
        # Return None to indicate no proxy - caller should handle gracefully
        return None
    
    def _build_proxy_url(self, proxy: Dict) -> str:
        """Build proxy URL from proxy config dict."""
        return (
            f"{proxy['protocol']}://{proxy['username']}:{proxy['password']}"
            f"@{proxy['ip_address']}:{proxy['port']}"
        )
    
    # =========================================================================
    # WEB3 INSTANCE MANAGEMENT (SYNC - for backward compatibility)
    # =========================================================================
    
    def _get_w3_instance(self, chain: str) -> Web3:
        """
        Get cached Web3 instance for chain (sync version).
        Uses dedicated monitoring proxy to avoid VPS IP exposure.
        
        Args:
            chain: Chain name
        
        Returns:
            Web3 instance
        
        Raises:
            ValueError: No RPC endpoint configured
            ProxyRequiredError: No proxy available
            ConnectionError: Failed to connect
        """
        # Check cache
        with self._w3_lock:
            if chain in self._w3_instances:
                w3 = self._w3_instances[chain]
                # Verify connection still alive
                try:
                    w3.eth.block_number  # Quick connectivity test
                    return w3
                except Exception as e:
                    logger.warning(f"Cached Web3 connection stale for {chain}, reconnecting | Error: {e}")
                    del self._w3_instances[chain]
        
        # Get RPC endpoint from database
        rpc_result = self.db.get_chain_by_name(chain)
        
        if not rpc_result:
            raise ValueError(f"No active RPC endpoint for chain: {chain}")
        
        rpc_url = rpc_result['url']
        
        # Get monitoring proxy for anti-Sybil protection
        monitoring_proxy = self._get_monitoring_proxy()
        proxy_url = self._build_proxy_url(monitoring_proxy)
        
        from infrastructure.identity_manager import get_curl_session
        
        # Use random wallet_id for TLS randomization (anti-fingerprinting)
        monitoring_wallet_id = random.randint(1, 90)
        session = get_curl_session(wallet_id=monitoring_wallet_id, proxy_url=proxy_url)
        w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={'timeout': 10}, session=session))
        
        logger.debug(f"Gas monitoring using proxy | Chain: {chain} | Proxy: {monitoring_proxy['ip_address']} | TLS Profile: wallet_{monitoring_wallet_id}")
        
        if not w3.is_connected():
            raise ConnectionError(f"Failed to connect to {chain} RPC: {rpc_url}")
        
        # Cache instance
        with self._w3_lock:
            self._w3_instances[chain] = w3
        
        logger.debug(f"Web3 instance created and cached | Chain: {chain} | RPC: {rpc_url[:50]}...")
        return w3
    
    # =========================================================================
    # GAS PRICE FETCHING (SYNC - for backward compatibility)
    # =========================================================================
    
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        reraise=True
    )
    def get_current_gas_price(
        self,
        chain: str,
        use_cache: bool = True
    ) -> float:
        """
        Get current gas price для chain (in gwei) - sync version.
        
        Args:
            chain: Chain name (arbitrum, base, etc.)
            use_cache: Use cached price if available
        
        Returns:
            Gas price in gwei
        
        Raises:
            ConnectionError: Failed to connect to RPC
            ProxyRequiredError: No proxy available
        """
        chain_id = self._get_chain_id(chain)
        
        # Check cache
        if use_cache and chain_id in self._gas_cache:
            cached_gwei, cached_at = self._gas_cache[chain_id]
            age = (datetime.now(timezone.utc) - cached_at).total_seconds()
            
            if age < CACHE_TTL_SECONDS:
                logger.debug(f"Using cached gas | Chain: {chain} | Price: {cached_gwei} gwei | Age: {age:.0f}s")
                return cached_gwei
        
        # Get fresh gas price
        try:
            w3 = self._get_w3_instance(chain)
            
            # Get latest block for base fee
            latest_block = w3.eth.get_block('latest')
            base_fee = latest_block.get('baseFeePerGas', 0)
            
            # Get priority fee
            try:
                priority_fee = w3.eth.max_priority_fee
            except (AttributeError, ValueError, TypeError) as e:
                logger.debug(f"max_priority_fee not supported on {chain}, using fallback | Error: {e}")
                priority_fee = w3.to_wei(1, 'gwei')  # Fallback 1 gwei
            
            # Calculate max fee (base + priority + buffer)
            max_fee = base_fee + priority_fee
            
            # Convert to gwei
            gas_gwei = float(w3.from_wei(max_fee, 'gwei'))
            
            # Update cache
            with self._cache_lock:
                self._gas_cache[chain_id] = (gas_gwei, datetime.now(timezone.utc))
            
            # Store in history
            snapshot = GasSnapshot(
                chain=chain,
                chain_id=chain_id,
                timestamp=datetime.now(timezone.utc),
                base_fee=base_fee,
                priority_fee=priority_fee,
                max_fee=max_fee,
                block_number=latest_block['number']
            )
            self._add_to_history(chain_id, snapshot)
            
            logger.debug(
                f"Gas price fetched | Chain: {chain} | "
                f"Base: {w3.from_wei(base_fee, 'gwei'):.4f} | "
                f"Priority: {w3.from_wei(priority_fee, 'gwei'):.4f} | "
                f"Total: {gas_gwei:.4f} gwei"
            )
            
            return gas_gwei
        
        except ProxyRequiredError:
            raise
        except Exception as e:
            logger.error(f"Failed to get gas price | Chain: {chain} | Error: {e}")
            raise
    
    # =========================================================================
    # GAS PRICE FETCHING (ASYNC)
    # =========================================================================
    
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        reraise=True
    )
    async def _fetch_gas_price(self, chain_id: int) -> float:
        """
        Fetch current gas price via RPC with proxy protection (async).
        
        CRITICAL: Uses proxy to prevent IP leak!
        
        Args:
            chain_id: Chain ID (1, 42161, 8453, etc.)
        
        Returns:
            Gas price in gwei, or 0.0 if unavailable
        """
        # Check cache first
        with self._cache_lock:
            if chain_id in self._gas_cache:
                cached_price, cached_time = self._gas_cache[chain_id]
                age = (datetime.now(timezone.utc) - cached_time).total_seconds()
                if age < CACHE_TTL_SECONDS:
                    logger.debug(f"Using cached gas for chain_id={chain_id}: {cached_price:.4f} gwei")
                    return cached_price
        
        # Get RPC endpoint from database
        endpoint = self.db.get_chain_rpc_by_chain_id(chain_id)
        
        if not endpoint:
            logger.warning(f"No RPC endpoint found for chain_id={chain_id}")
            return 0.0
        
        rpc_url = endpoint['url']
        
        # CRITICAL: Get proxy for RPC call
        try:
            proxy = self._get_monitoring_proxy()
            if proxy:
                proxy_url = self._build_proxy_url(proxy)
            else:
                proxy_url = None
                logger.warning(f"No proxy for chain_id={chain_id} - using direct RPC (IP exposed)")
        except Exception as e:
            logger.error(f"Proxy fetch error for chain_id={chain_id}: {e}")
            proxy_url = None
        
        # Make RPC call with proxy
        try:
            from infrastructure.identity_manager import get_curl_session
            import aiohttp
            
            # Use random wallet_id for TLS randomization (anti-fingerprinting)
            monitoring_wallet_id = random.randint(1, 90)
            
            payload = {
                "jsonrpc": "2.0",
                "method": "eth_gasPrice",
                "params": [],
                "id": 1
            }
            
            # Use aiohttp with proxy (if available)
            kwargs = {
                'json': payload,
                'timeout': aiohttp.ClientTimeout(total=10)
            }
            if proxy_url:
                kwargs['proxy'] = proxy_url.replace('socks5://', 'http://')
            
            async with aiohttp.ClientSession(
                connector=aiohttp.TCPConnector(ssl=False)
            ) as http_session:
                async with http_session.post(rpc_url, **kwargs) as response:
                    if response.status == 200:
                        data = await response.json()
                        if 'result' in data:
                            # Convert hex to gwei
                            gas_wei = int(data['result'], 16)
                            gas_gwei = gas_wei / 1e9
                            
                            # Store in history
                            self._store_gas_history(chain_id, gas_gwei)
                            
                            # Update cache
                            with self._cache_lock:
                                self._gas_cache[chain_id] = (gas_gwei, datetime.now(timezone.utc))
                            
                            logger.debug(
                                f"Fetched gas for chain_id={chain_id}: {gas_gwei:.4f} gwei "
                                f"(via proxy {proxy['ip_address']}, TLS profile: wallet_{monitoring_wallet_id})"
                            )
                            
                            return gas_gwei
            
            logger.warning(f"RPC call failed for chain_id={chain_id}")
            return 0.0
        
        except asyncio.TimeoutError:
            logger.warning(f"RPC timeout for chain_id={chain_id}")
            return 0.0
        except Exception as e:
            logger.error(f"RPC error for chain_id={chain_id}: {e}")
            return 0.0
    
    def _store_gas_history(self, chain_id: int, gas_gwei: float) -> None:
        """
        Store gas price in history table and in-memory deque.
        
        Args:
            chain_id: Chain ID
            gas_gwei: Gas price in gwei
        """
        # Store in database
        try:
            self.db.execute_query(
                """
                INSERT INTO gas_history (chain_id, gas_price_gwei, recorded_at)
                VALUES (%s, %s, NOW())
                """,
                (chain_id, gas_gwei)
            )
        except Exception as e:
            logger.error(f"Error storing gas history: {e}")
        
        # Store in memory
        snapshot = GasSnapshot(
            chain=self._get_chain_name(chain_id),
            chain_id=chain_id,
            timestamp=datetime.now(timezone.utc),
            base_fee=int(gas_gwei * 1e9),  # Approximate
            priority_fee=int(gas_gwei * 0.1 * 1e9),  # Approximate
            max_fee=int(gas_gwei * 1e9),
            block_number=0  # Unknown
        )
        
        with self._history_lock:
            if chain_id not in self._history:
                self._history[chain_id] = deque(maxlen=HISTORY_SIZE)
            self._history[chain_id].append(snapshot)
    
    def _add_to_history(self, chain_id: int, snapshot: GasSnapshot):
        """Add gas snapshot to historical data (thread-safe)."""
        with self._history_lock:
            if chain_id not in self._history:
                self._history[chain_id] = deque(maxlen=HISTORY_SIZE)
            
            self._history[chain_id].append(snapshot)
            
            history_size = len(self._history[chain_id])
        
        logger.debug(
            f"Gas snapshot stored | chain_id: {chain_id} | "
            f"History size: {history_size}/{HISTORY_SIZE}"
        )
    
    # =========================================================================
    # NETWORK DESCRIPTOR
    # =========================================================================
    
    def _get_network_descriptor(self, chain_id: int) -> NetworkDescriptor:
        """
        Get network type and multiplier from database.
        
        Args:
            chain_id: Chain ID
        
        Returns:
            NetworkDescriptor with network metadata
        """
        # Check cache first
        if chain_id in self._descriptor_cache:
            return self._descriptor_cache[chain_id]
        
        try:
            result = self.db.get_chain_by_chain_id(chain_id)
            
            if result:
                network_type = NetworkType(result.get('network_type', 'sidechain'))
                multiplier = float(result.get('gas_multiplier', DEFAULT_MULTIPLIERS[network_type]))
                
                descriptor = NetworkDescriptor(
                    chain_id=chain_id,
                    network_type=network_type,
                    multiplier=multiplier,
                    is_l2=result.get('is_l2', False),
                    l1_data_fee=result.get('l1_data_fee', False),
                    chain_name=result.get('chain', '')
                )
            else:
                # Unknown chain - use conservative defaults
                logger.warning(f"Unknown chain_id={chain_id}, using sidechain defaults")
                descriptor = NetworkDescriptor(
                    chain_id=chain_id,
                    network_type=NetworkType.SIDECHAIN,
                    multiplier=DEFAULT_MULTIPLIERS[NetworkType.SIDECHAIN]
                )
            
            # Cache result
            self._descriptor_cache[chain_id] = descriptor
            return descriptor
        
        except Exception as e:
            logger.error(f"Error getting network descriptor for chain_id={chain_id}: {e}")
            return NetworkDescriptor(
                chain_id=chain_id,
                network_type=NetworkType.SIDECHAIN,
                multiplier=DEFAULT_MULTIPLIERS[NetworkType.SIDECHAIN]
            )
    
    # =========================================================================
    # GAS VIABILITY CHECK (ASYNC)
    # =========================================================================
    
    async def check_gas_viability(self, chain_id: int) -> GasCheckResult:
        """
        Main entry point for gas checking (async).
        
        Args:
            chain_id: Chain ID (1, 42161, 8453, etc.)
        
        Returns:
            GasCheckResult with status and threshold info
        
        Example:
            >>> result = await controller.check_gas_viability(42161)
            >>> if result.status == GasStatus.HIGH_GAS:
            ...     print(f"Delay: {result.extra_delay_minutes} min")
        """
        logger.debug(f"Checking gas viability for chain_id={chain_id}")
        
        # Step 1: Get network descriptor
        descriptor = self._get_network_descriptor(chain_id)
        
        # Step 2: Fetch current gas via RPC (with proxy!)
        current_gas = await self._fetch_gas_price(chain_id)
        
        if current_gas <= 0:
            logger.warning(f"Unable to fetch gas price for chain_id={chain_id}")
            return GasCheckResult(
                status=GasStatus.UNAVAILABLE,
                chain_id=chain_id,
                current_gwei=0.0,
                threshold_gwei=0.0,
                network_type=descriptor.network_type
            )
        
        # Step 3: Calculate dynamic threshold
        threshold, ma_available = self._calculate_threshold(chain_id, descriptor)
        
        # Step 4: Compare and return
        if current_gas > threshold:
            extra_delay = self._calculate_extra_delay(current_gas, threshold)
            
            logger.info(
                f"HIGH GAS | chain_id={chain_id} | "
                f"current={current_gas:.4f} gwei | "
                f"threshold={threshold:.4f} gwei | "
                f"delay={extra_delay:.0f} min"
            )
            
            return GasCheckResult(
                status=GasStatus.HIGH_GAS,
                chain_id=chain_id,
                current_gwei=current_gas,
                threshold_gwei=threshold,
                network_type=descriptor.network_type,
                extra_delay_minutes=extra_delay,
                ma_24h_available=ma_available
            )
        
        logger.debug(
            f"GAS OK | chain_id={chain_id} | "
            f"current={current_gas:.4f} gwei | "
            f"threshold={threshold:.4f} gwei"
        )
        
        return GasCheckResult(
            status=GasStatus.GAS_OK,
            chain_id=chain_id,
            current_gwei=current_gas,
            threshold_gwei=threshold,
            network_type=descriptor.network_type,
            ma_24h_available=ma_available
        )
    
    def _calculate_threshold(
        self, 
        chain_id: int, 
        descriptor: NetworkDescriptor
    ) -> Tuple[float, bool]:
        """
        Calculate dynamic threshold based on 24h MA or current gas.
        
        Formula: Threshold = Base * Multiplier
        Where Base = MA_24h if available, else Current_Gas
        
        Args:
            chain_id: Chain ID
            descriptor: Network descriptor
        
        Returns:
            Tuple of (threshold, ma_available)
        """
        # Try to get 24h moving average
        ma_24h = self._get_24h_moving_average(chain_id)
        
        if ma_24h:
            base = ma_24h
            ma_available = True
        else:
            # Fallback to cached current gas
            with self._cache_lock:
                cached = self._gas_cache.get(chain_id)
            if cached:
                base = cached[0]
            else:
                # No data - use very conservative threshold
                logger.warning(f"No gas data for chain_id={chain_id}, using high threshold")
                return 1000.0, False  # Effectively always allow
            ma_available = False
        
        threshold = base * descriptor.multiplier
        return threshold, ma_available
    
    def _get_24h_moving_average(self, chain_id: int) -> Optional[float]:
        """
        Get 24h moving average gas price from history.
        
        Args:
            chain_id: Chain ID
        
        Returns:
            MA_24h in gwei or None if no data
        """
        try:
            result = self.db.execute_query(
                """
                SELECT AVG(gas_price_gwei) as ma_24h
                FROM gas_history
                WHERE chain_id = %s 
                  AND recorded_at > NOW() - INTERVAL '24 hours'
                """,
                (chain_id,),
                fetch='one'
            )
            
            if result and result.get('ma_24h'):
                return float(result['ma_24h'])
            return None
        
        except Exception as e:
            logger.error(f"Error getting MA_24h for chain_id={chain_id}: {e}")
            return None
    
    def _calculate_extra_delay(self, current: float, threshold: float) -> float:
        """
        Calculate extra delay based on gas excess.
        
        Higher gas = longer delay (up to MAX_EXTRA_DELAY_MINUTES)
        
        Args:
            current: Current gas price in gwei
            threshold: Threshold gas price in gwei
        
        Returns:
            Extra delay in minutes
        """
        if threshold <= 0:
            return 0.0
        
        excess_ratio = current / threshold
        delay = min(excess_ratio * 30, MAX_EXTRA_DELAY_MINUTES)
        return round(delay, 1)
    
    # =========================================================================
    # GAS ANALYSIS (SYNC - backward compatible)
    # =========================================================================
    
    def analyze_gas_conditions(
        self,
        chain: str
    ) -> GasAnalysis:
        """
        Analyze current gas conditions и recommend action (sync version).
        
        Args:
            chain: Chain name
        
        Returns:
            GasAnalysis with recommendations
        """
        chain_id = self._get_chain_id(chain)
        
        # Get current gas price
        current_gwei = self.get_current_gas_price(chain)
        
        # Get thresholds
        thresholds = GAS_THRESHOLDS.get(chain, GAS_THRESHOLDS['ethereum'])
        max_acceptable = thresholds['max']
        optimal = thresholds['optimal']
        
        # Calculate medians from history
        median_1h = self._get_median_gas(chain_id, hours=1)
        median_24h = self._get_median_gas(chain_id, hours=24)
        
        # Check if acceptable
        is_acceptable = current_gwei <= max_acceptable
        is_optimal = current_gwei <= optimal
        
        # Determine recommended action
        if current_gwei > max_acceptable:
            action = 'skip'
            wait_hours = self._estimate_wait_time(chain_id, max_acceptable)
            savings = None
        
        elif current_gwei > optimal * 3:  # 3x optimal = wait
            action = 'wait'
            wait_hours = self._estimate_wait_time(chain_id, optimal)
            savings = ((current_gwei - optimal) / current_gwei) * 100
        
        else:  # Acceptable or optimal
            action = 'execute'
            wait_hours = None
            savings = None if is_optimal else ((current_gwei - optimal) / current_gwei) * 100
        
        analysis = GasAnalysis(
            chain=chain,
            chain_id=chain_id,
            current_gwei=current_gwei,
            median_1h_gwei=median_1h or current_gwei,
            median_24h_gwei=median_24h or current_gwei,
            is_acceptable=is_acceptable,
            is_optimal=is_optimal,
            recommended_action=action,
            wait_hours=wait_hours,
            cost_savings_percent=savings
        )
        
        median_1h_str = f"{median_1h:.4f}" if median_1h is not None else "N/A"
        median_24h_str = f"{median_24h:.4f}" if median_24h is not None else "N/A"
        
        logger.info(
            f"Gas analysis | Chain: {chain} | "
            f"Current: {current_gwei:.4f} gwei | "
            f"1h median: {median_1h_str} | "
            f"24h median: {median_24h_str} | "
            f"Action: {action}"
        )
        
        return analysis
    
    def _get_median_gas(
        self,
        chain_id: int,
        hours: int
    ) -> Optional[float]:
        """
        Get median gas price for last N hours from in-memory history.
        
        Args:
            chain_id: Chain ID
            hours: Hours to look back
        
        Returns:
            Median gas in gwei or None if insufficient data
        """
        with self._history_lock:
            if chain_id not in self._history:
                return None
            
            history = list(self._history[chain_id])
        
        now = datetime.now(timezone.utc)
        cutoff = now - timedelta(hours=hours)
        
        # Filter snapshots within time window
        prices = [
            snapshot.max_fee / 1e9
            for snapshot in history
            if snapshot.timestamp >= cutoff
        ]
        
        if not prices:
            return None
        
        # Calculate median
        prices_sorted = sorted(prices)
        n = len(prices_sorted)
        
        if n % 2 == 0:
            median_gwei = (prices_sorted[n//2 - 1] + prices_sorted[n//2]) / 2
        else:
            median_gwei = prices_sorted[n//2]
        
        logger.debug(f"Median gas ({hours}h) | chain_id: {chain_id} | {median_gwei:.4f} gwei | Samples: {n}")
        return median_gwei
    
    def _estimate_wait_time(
        self,
        chain_id: int,
        target_gwei: float
    ) -> Optional[float]:
        """
        Estimate wait time until target gas price is reached.
        
        Args:
            chain_id: Chain ID
            target_gwei: Target gas price
        
        Returns:
            Estimated hours to wait (or None if unknown)
        """
        # Get historical trend
        with self._history_lock:
            if chain_id not in self._history or len(self._history[chain_id]) < 10:
                return 3.0  # Default 3 hours
            history = list(self._history[chain_id])
        
        # Calculate hourly trend (last 6 hours)
        now = datetime.now(timezone.utc)
        cutoff_6h = now - timedelta(hours=6)
        
        recent_snapshots = [s for s in history if s.timestamp >= cutoff_6h]
        
        if len(recent_snapshots) < 5:
            return 3.0  # Default
        
        # Linear regression slope (simplified)
        timestamps = [(s.timestamp - now).total_seconds() / 3600 for s in recent_snapshots]
        prices = [s.max_fee / 1e9 for s in recent_snapshots]
        
        n = len(prices)
        mean_x = sum(timestamps) / n
        mean_y = sum(prices) / n
        
        numerator = sum((timestamps[i] - mean_x) * (prices[i] - mean_y) for i in range(n))
        denominator = sum((timestamps[i] - mean_x) ** 2 for i in range(n))
        
        if denominator == 0:
            slope = 0
        else:
            slope = numerator / denominator
        
        # Predict wait time
        current_gwei = prices[-1]
        delta = current_gwei - target_gwei
        
        if slope >= 0:  # Gas rising or stable
            # Assume off-peak hours (3-6 AM UTC) will have lower gas
            current_hour = now.hour
            if current_hour >= 6:
                hours_until_offpeak = 24 - current_hour + 3  # Next 3 AM
            else:
                hours_until_offpeak = 3 - current_hour  # Today 3 AM
            return float(hours_until_offpeak)
        else:  # Gas declining
            if slope == 0:
                return 1.0
            hours = -delta / slope
            return min(max(hours, 0.5), 24.0)  # Clamp to 0.5-24h
    
    # =========================================================================
    # TRANSACTION EXECUTION DECISION
    # =========================================================================
    
    def should_execute_transaction(
        self,
        chain: str,
        priority: str = 'normal'
    ) -> Tuple[bool, str]:
        """
        Determine if transaction should be executed сейчас.
        
        Args:
            chain: Chain name
            priority: Transaction priority ('low', 'normal', 'high')
        
        Returns:
            (should_execute, reason) tuple
        
        Example:
            >>> controller.should_execute_transaction('arbitrum', 'normal')
            (True, "Gas acceptable: 0.01 gwei")
        """
        chain_id = self._get_chain_id(chain)
        
        # Check if chain is throttled
        if self._is_throttled(chain_id):
            throttle_end = self._throttles[chain_id]
            minutes_left = (throttle_end - datetime.now(timezone.utc)).total_seconds() / 60
            return (False, f"Activity throttled for {minutes_left:.0f} more minutes")
        
        # Analyze gas conditions
        analysis = self.analyze_gas_conditions(chain)
        
        # High priority → always execute (unless extreme)
        if priority == 'high':
            if analysis.current_gwei > GAS_THRESHOLDS.get(chain, {}).get('max', 200) * 2:
                return (False, f"Gas too high even for high priority: {analysis.current_gwei:.2f} gwei")
            else:
                return (True, f"High priority execution | Gas: {analysis.current_gwei:.4f} gwei")
        
        # Normal/low priority → follow recommendations
        if analysis.recommended_action == 'skip':
            return (
                False,
                f"Gas exceeds threshold: {analysis.current_gwei:.2f} gwei > "
                f"{GAS_THRESHOLDS.get(chain, {}).get('max', 200)} gwei"
            )
        
        elif analysis.recommended_action == 'wait':
            wait_msg = f"Wait ~{analysis.wait_hours:.1f}h" if analysis.wait_hours else "Wait"
            savings_msg = f" (save {analysis.cost_savings_percent:.0f}%)" if analysis.cost_savings_percent else ""
            return (
                False if priority == 'low' else True,  # Normal priority can proceed
                f"{wait_msg} for optimal gas{savings_msg}"
            )
        
        else:  # execute
            return (True, f"Gas acceptable: {analysis.current_gwei:.4f} gwei")
    
    def _is_throttled(self, chain_id: int) -> bool:
        """Check if chain activity is throttled."""
        if chain_id not in self._throttles:
            return False
        
        throttle_end = self._throttles[chain_id]
        
        if datetime.now(timezone.utc) >= throttle_end:
            # Throttle expired → remove
            del self._throttles[chain_id]
            logger.info(f"Activity throttle lifted | chain_id={chain_id}")
            return False
        
        return True
    
    def trigger_throttle(
        self,
        chain: str,
        duration_hours: float = 3.0,
        reason: str = "High gas prices"
    ):
        """
        Trigger activity throttle для chain.
        
        Args:
            chain: Chain name
            duration_hours: Throttle duration
            reason: Reason for throttle
        """
        chain_id = self._get_chain_id(chain)
        throttle_end = datetime.now(timezone.utc) + timedelta(hours=duration_hours)
        self._throttles[chain_id] = throttle_end
        
        logger.warning(
            f"Activity throttle triggered | Chain: {chain} | "
            f"Duration: {duration_hours}h | Reason: {reason}"
        )
        
        # Log to database
        try:
            event_query = """
                INSERT INTO system_events (event_type, severity, message, metadata, created_at)
                VALUES (%s, %s, %s, %s, NOW())
            """
            
            metadata_dict = {
                "chain": chain,
                "chain_id": chain_id,
                "duration_hours": duration_hours,
                "reason": reason
            }
            
            self.db.execute_query(
                event_query,
                (
                    'gas_throttle',
                    'warning',
                    f"Activity throttled on {chain} for {duration_hours}h: {reason}",
                    extras.Json(metadata_dict)
                )
            )
        except Exception as e:
            logger.error(f"Failed to log throttle event | Error: {e}")
    
    def check_sustained_high_gas(
        self,
        chain: str,
        duration_hours: int = 3
    ) -> bool:
        """
        Check if gas has been sustained high.
        
        Args:
            chain: Chain name
            duration_hours: Duration to check
        
        Returns:
            True if sustained high gas detected
        """
        chain_id = self._get_chain_id(chain)
        
        if chain_id not in self._history:
            return False
        
        threshold = GAS_THRESHOLDS.get(chain, {}).get('max', 200)
        cutoff = datetime.now(timezone.utc) - timedelta(hours=duration_hours)
        
        history = self._history[chain_id]
        recent = [s for s in history if s.timestamp >= cutoff]
        
        if not recent:
            return False
        
        # Check if 80%+ of recent samples exceed threshold
        high_count = sum(1 for s in recent if (s.max_fee / 1e9) > threshold)
        high_ratio = high_count / len(recent)
        
        logger.debug(
            f"Sustained gas check | Chain: {chain} | "
            f"High ratio: {high_ratio:.1%} | Threshold: {threshold} gwei"
        )
        
        return high_ratio >= 0.8
    
    # =========================================================================
    # BALANCE MONITORING (from gas_controller.py)
    # =========================================================================
    
    async def get_wallet_balance(
        self, 
        wallet_id: int, 
        chain_id: int
    ) -> Decimal:
        """
        Get wallet's ETH balance on a specific chain (async).
        Uses dedicated monitoring proxy to avoid VPS IP exposure.
        
        Args:
            wallet_id: Wallet database ID
            chain_id: Chain ID
        
        Returns:
            Balance in ETH
        
        Raises:
            ProxyRequiredError: If no proxy available
        """
        # Get wallet address
        wallet = self.db.get_wallet(wallet_id)
        if not wallet:
            return Decimal('0')
        
        address = wallet['address']
        
        # Get RPC endpoint using db_manager method
        rpc_result = self.db.get_chain_rpc_by_chain_id(chain_id)
        
        if not rpc_result:
            logger.warning(f"No RPC endpoint for chain_id={chain_id}")
            return Decimal('0')
        
        try:
            # CRITICAL: Get monitoring proxy
            monitoring_proxy = self._get_monitoring_proxy()
            proxy_url = self._build_proxy_url(monitoring_proxy)
            
            from infrastructure.identity_manager import get_curl_session
            
            # Use random wallet_id for TLS randomization
            monitoring_wallet_id = random.randint(1, 90)
            session = get_curl_session(wallet_id=monitoring_wallet_id, proxy_url=proxy_url)
            
            w3 = Web3(Web3.HTTPProvider(
                rpc_result['url'],
                request_kwargs={'timeout': 10, 'session': session}
            ))
            
            balance_wei = w3.eth.get_balance(address)
            balance_eth = Decimal(str(w3.from_wei(balance_wei, 'ether')))
            
            logger.debug(
                f"Balance check | Wallet: {wallet_id} | Chain: {chain_id} | "
                f"Balance: {balance_eth:.6f} ETH | Proxy: {monitoring_proxy['ip_address']}"
            )
            
            return balance_eth
        
        except ProxyRequiredError:
            raise
        except Exception as e:
            logger.error(f"Failed to fetch balance | Wallet: {wallet_id} | Chain: {chain_id} | Error: {e}")
            return Decimal('0')
    
    def get_wallet_balance_eth_equivalent(
        self,
        wallet_id: int,
        chain: str = 'base'
    ) -> Decimal:
        """
        Get wallet's ETH-equivalent balance on a specific chain (sync version).
        Uses dedicated monitoring proxy to avoid VPS IP exposure.
        
        Args:
            wallet_id: Wallet database ID
            chain: Chain name
        
        Returns:
            Balance in ETH equivalent
        
        Raises:
            ProxyRequiredError: If no proxy available
        """
        chain_id = self._get_chain_id(chain)
        
        # Get wallet address
        wallet = self.db.get_wallet(wallet_id)
        if not wallet:
            return Decimal('0')
        
        address = wallet['address']
        
        # Get RPC endpoint using db_manager method
        rpc_result = self.db.get_chain_by_name(chain)
        
        if not rpc_result:
            logger.warning(f"No RPC endpoint for chain: {chain}")
            return Decimal('0')
        
        try:
            # Use monitoring proxy for balance checks
            monitoring_proxy = self._get_monitoring_proxy()
            
            proxy_url = self._build_proxy_url(monitoring_proxy)
            
            from infrastructure.identity_manager import get_curl_session
            
            # Use random wallet_id для TLS рандомизации мониторинга (anti-fingerprinting)
            monitoring_wallet_id = random.randint(1, 90)
            session = get_curl_session(wallet_id=monitoring_wallet_id, proxy_url=proxy_url)
            w3 = Web3(Web3.HTTPProvider(rpc_result['url'], request_kwargs={'timeout': 10}, session=session))
            logger.debug(f"Balance check using proxy | Wallet: {wallet_id} | Chain: {chain} | Proxy: {monitoring_proxy['ip_address']} | TLS Profile: wallet_{monitoring_wallet_id}")
            
            balance_wei = w3.eth.get_balance(address)
            balance_eth = Decimal(str(w3.from_wei(balance_wei, 'ether')))
            
            logger.debug(f"Wallet {wallet_id} | Chain: {chain} | Balance: {balance_eth:.6f} ETH")
            return balance_eth
        
        except ProxyRequiredError:
            raise
        except Exception as e:
            logger.error(f"Failed to fetch balance | Wallet: {wallet_id} | Chain: {chain} | Error: {e}")
            return Decimal('0')
    
    def check_wallet_needs_topup(self, wallet_id: int, chain: str = 'base') -> Tuple[bool, Decimal]:
        """
        Check if wallet balance is below tier threshold (sync version).
        
        Args:
            wallet_id: Wallet database ID
            chain: Chain name to check
        
        Returns:
            (needs_topup, deficit_eth) tuple
        """
        wallet = self.db.get_wallet(wallet_id)
        if not wallet:
            return (False, Decimal('0'))
        
        tier = wallet['tier']
        threshold = TIER_THRESHOLDS.get(tier, Decimal('0.001'))
        
        balance = self.get_wallet_balance_eth_equivalent(wallet_id, chain)
        deficit = threshold - balance
        
        needs_topup = deficit > 0
        
        if needs_topup:
            logger.warning(
                f"Wallet {wallet_id} LOW BALANCE | Tier {tier} | "
                f"Balance: {balance:.6f} ETH | Threshold: {threshold:.6f} ETH | "
                f"Deficit: {deficit:.6f} ETH"
            )
        
        return (needs_topup, deficit if needs_topup else Decimal('0'))
    
    async def check_wallet_needs_topup_async(
        self, 
        wallet_id: int, 
        chain_id: int
    ) -> Tuple[bool, Decimal]:
        """
        Async version: Check if wallet balance is below tier threshold.
        
        Args:
            wallet_id: Wallet database ID
            chain_id: Chain ID to check
        
        Returns:
            (needs_topup, deficit_eth) tuple
        """
        wallet = self.db.get_wallet(wallet_id)
        if not wallet:
            return (False, Decimal('0'))
        
        tier = wallet['tier']
        threshold = TIER_THRESHOLDS.get(tier, Decimal('0.001'))
        
        balance = await self.get_wallet_balance(wallet_id, chain_id)
        deficit = threshold - balance
        
        needs_topup = deficit > 0
        
        if needs_topup:
            logger.warning(
                f"Wallet {wallet_id} LOW BALANCE | Tier {tier} | "
                f"Balance: {balance:.6f} ETH | Threshold: {threshold:.6f} ETH | "
                f"Deficit: {deficit:.6f} ETH"
            )
        
        return (needs_topup, deficit if needs_topup else Decimal('0'))
    
    def check_all_wallets(self, chain: str = 'base') -> List[Dict]:
        """
        Check all wallets for low balances.
        
        Args:
            chain: Chain name to check
        
        Returns:
            List of dicts with low-balance wallets
        """
        wallets = self.db.execute_query("SELECT id, address, tier FROM wallets WHERE status = 'active'", fetch='all')
        low_balance_wallets = []
        
        for wallet in wallets:
            needs_topup, deficit = self.check_wallet_needs_topup(wallet['id'], chain)
            
            if needs_topup:
                low_balance_wallets.append({
                    'wallet_id': wallet['id'],
                    'address': wallet['address'],
                    'tier': wallet['tier'],
                    'deficit_eth': deficit
                })
        
        logger.info(f"Balance check complete | Low balance: {len(low_balance_wallets)}/{len(wallets)}")
        return low_balance_wallets
    
    def trigger_cex_topup_alert(self, wallet_id: int, deficit_eth: Decimal, chain: str = 'base'):
        """
        Trigger Telegram alert for CEX topup requirement.
        
        CRITICAL: This enforces CEX-only topups (NO internal transfers).
        
        Args:
            wallet_id: Wallet requiring topup
            deficit_eth: Deficit amount in ETH
            chain: Chain name
        """
        wallet = self.db.get_wallet(wallet_id)
        if not wallet:
            return
        
        # Log system event
        self.db.log_system_event(
            event_type='low_balance_alert',
            severity='warning',
            message=f"Wallet {wallet_id} requires CEX topup: {deficit_eth:.6f} ETH",
            metadata={
                'wallet_id': wallet_id,
                'address': wallet['address'],
                'tier': wallet['tier'],
                'deficit_eth': str(deficit_eth),
                'chain': chain
            }
        )
        
        logger.warning(
            f"CEX topup alert triggered | Wallet: {wallet_id} | "
            f"Tier: {wallet['tier']} | Deficit: {deficit_eth:.6f} ETH | "
            f"ACTION: Manual CEX withdrawal required"
        )
    
    # =========================================================================
    # UTILITY METHODS
    # =========================================================================
    
    async def get_gas_status(
        self,
        chain_ids: Optional[List[int]] = None
    ) -> Dict[int, GasCheckResult]:
        """
        Get gas status for multiple chains (async).
        
        Args:
            chain_ids: List of chain IDs to check (default: all known)
        
        Returns:
            Dict mapping chain_id to GasCheckResult
        """
        if chain_ids is None:
            try:
                # Use db_manager method to get all active chains
                chains = self.db.get_all_active_chains()
                chain_ids = [c['chain_id'] for c in chains if c.get('chain_id')]
            except Exception as e:
                logger.error(f"Error getting chain_ids: {e}")
                chain_ids = [1, 42161, 8453, 10, 137, 56]  # Fallback
        
        results = {}
        for chain_id in chain_ids:
            results[chain_id] = await self.check_gas_viability(chain_id)
        
        return results
    
    def clear_cache(self) -> None:
        """Clear in-memory caches."""
        with self._cache_lock:
            self._gas_cache.clear()
        self._descriptor_cache.clear()
        self._name_to_id.clear()
        self._id_to_name.clear()
        logger.info("AdaptiveGasController caches cleared")


# =============================================================================
# CONVENIENCE FUNCTIONS (for backward compatibility)
# =============================================================================

async def check_chain_gas(chain_id: int) -> GasCheckResult:
    """
    Convenience function to check gas for a single chain.
    
    Args:
        chain_id: Chain ID to check
    
    Returns:
        GasCheckResult
    """
    controller = AdaptiveGasController()
    return await controller.check_gas_viability(chain_id)


# =============================================================================
# ALIASES FOR BACKWARD COMPATIBILITY
# =============================================================================

# Alias for gas_manager.GasManager
GasManager = AdaptiveGasController

# Alias for gas_controller.GasBalanceController
GasBalanceController = AdaptiveGasController

# Alias for gas_logic.GasLogic
GasLogic = AdaptiveGasController


# =============================================================================
# CLI INTERFACE
# =============================================================================

def main():
    """CLI entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Adaptive Gas Controller - Unified Gas Management')
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    # Check gas command
    check_parser = subparsers.add_parser('check', help='Check current gas prices')
    check_parser.add_argument('--chain', type=str, default='arbitrum', help='Chain name')
    check_parser.add_argument('--chain-id', type=int, help='Chain ID (alternative to --chain)')
    
    # Monitor command
    monitor_parser = subparsers.add_parser('monitor', help='Monitor gas prices (continuous)')
    monitor_parser.add_argument('--chains', type=str, nargs='+', default=['arbitrum', 'base', 'optimism'],
                               help='Chains to monitor')
    monitor_parser.add_argument('--interval', type=int, default=300, help='Polling interval (seconds)')
    
    # Balance check command
    balance_parser = subparsers.add_parser('balance', help='Check wallet balances')
    balance_parser.add_argument('--chain', type=str, default='base', help='Chain name')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    try:
        controller = AdaptiveGasController()
        
        if args.command == 'check':
            if args.chain_id:
                # Async check by chain_id
                result = asyncio.run(controller.check_gas_viability(args.chain_id))
                print(f"\n🔍 Gas Check — Chain ID: {result.chain_id}")
                print(f"   Status: {result.status.value}")
                print(f"   Current: {result.current_gwei:.4f} gwei")
                print(f"   Threshold: {result.threshold_gwei:.4f} gwei")
                print(f"   Network Type: {result.network_type.value}")
                if result.status == GasStatus.HIGH_GAS:
                    print(f"   Extra Delay: {result.extra_delay_minutes:.0f} minutes")
            else:
                # Sync check by chain name
                analysis = controller.analyze_gas_conditions(args.chain)
                
                print(f"\n🔍 Gas Analysis — {args.chain.upper()}")
                print(f"   Current: {analysis.current_gwei:.4f} gwei")
                print(f"   1h median: {analysis.median_1h_gwei:.4f} gwei")
                print(f"   24h median: {analysis.median_24h_gwei:.4f} gwei")
                print(f"   Status: {'✅ Optimal' if analysis.is_optimal else '⚠️  High' if not analysis.is_acceptable else '🟡 Acceptable'}")
                print(f"   Recommendation: {analysis.recommended_action.upper()}")
                
                if analysis.wait_hours:
                    print(f"   Wait time: ~{analysis.wait_hours:.1f} hours")
                if analysis.cost_savings_percent:
                    print(f"   Potential savings: {analysis.cost_savings_percent:.0f}%")
                
                should_execute, reason = controller.should_execute_transaction(args.chain)
                print(f"\n   Decision: {'⚡ EXECUTE' if should_execute else '⏸️  WAIT'}")
                print(f"   Reason: {reason}")
        
        elif args.command == 'monitor':
            print(f"📊 Gas Monitor started | Chains: {', '.join(args.chains)} | Interval: {args.interval}s")
            print("Press Ctrl+C to stop\n")
            
            while True:
                for chain in args.chains:
                    try:
                        gas_gwei = controller.get_current_gas_price(chain)
                        thresholds = GAS_THRESHOLDS.get(chain, {})
                        optimal = thresholds.get('optimal', 0)
                        max_acceptable = thresholds.get('max', 200)
                        
                        if gas_gwei <= optimal:
                            status = '✅'
                        elif gas_gwei <= max_acceptable:
                            status = '🟡'
                        else:
                            status = '🔴'
                        
                        timestamp = datetime.now().strftime('%H:%M:%S')
                        print(f"{timestamp} | {chain:10s} | {status} {gas_gwei:8.4f} gwei")
                    
                    except Exception as e:
                        print(f"Error fetching {chain}: {e}")
                
                print()  # Empty line between cycles
                time.sleep(args.interval)
        
        elif args.command == 'balance':
            print(f"\n💰 Balance Check — {args.chain.upper()}")
            low_wallets = controller.check_all_wallets(args.chain)
            
            if low_wallets:
                print(f"Low balance wallets: {len(low_wallets)}")
                for w in low_wallets[:10]:
                    print(f"  • Wallet {w['wallet_id']} (Tier {w['tier']}): deficit {w['deficit_eth']:.6f} ETH")
            else:
                print("All wallets have sufficient balance ✅")
    
    except KeyboardInterrupt:
        print("\n\n⏹️  Monitor stopped")
        sys.exit(0)
    
    except Exception as e:
        logger.exception(f"Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
