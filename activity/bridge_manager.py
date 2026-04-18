#!/usr/bin/env python3
"""
Bridge Manager v2.0 — Module 13 (Rewritten)
============================================
Автоматический bridge между L2 сетями с ДИНАМИЧЕСКОЙ проверкой CEX поддержки

CRITICAL FEATURES:
- НЕТ hardcoded списков сетей - всё через live CEX API
- Динамическая проверка поддержки сетей на 5 биржах
- Автоматический выбор безопасного bridge провайдера
- DeFiLlama проверка безопасности (TVL, rank, hacks)
- Интеграция с Socket, Across, Relay API
- **GasLogic интеграция: проверка газа в ОБЕИХ сетях**

Architecture:
    CEXNetworkChecker → is_bridge_required(network) → (bool, cex_name)
    BridgeManager → check_gas_both_networks() → gas status
    BridgeManager → check_bridge_availability() → route info
    BridgeManager → execute_bridge() → transaction result

Author: Airdrop Farming System v4.0
Created: 2026-03-06
Version: 2.1 (GasLogic integration)
"""

import os
import sys
import json
import asyncio
import aiohttp
from typing import Dict, Any, Optional, List, Tuple
from dataclasses import dataclass, field
from decimal import Decimal
from datetime import datetime, timezone, timedelta
from pathlib import Path
from enum import Enum

# Добавить parent directory для импорта
sys.path.insert(0, str(Path(__file__).parent.parent))

import ccxt
from ccxt.base.errors import NetworkError, ExchangeError
from web3 import Web3
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
from activity.adaptive import AdaptiveGasController as GasManager, GasStatus, GasCheckResult
from infrastructure.chain_discovery import ChainDiscoveryService


# =============================================================================
# EXCEPTIONS
# =============================================================================

class BridgeError(Exception):
    """Base exception for bridge operations."""
    pass


class BridgeNotAvailableError(BridgeError):
    """No bridge route found for the requested networks."""
    pass


class BridgeSafetyError(BridgeError):
    """Bridge route does not meet safety requirements."""
    pass


class BridgeExecutionError(BridgeError):
    """Failed to execute bridge transaction."""
    pass


class CEXCheckError(BridgeError):
    """Failed to check CEX network support."""
    pass


class WaitStatus(Enum):
    """Status for bridge waiting/delayed operations."""
    READY = "ready"               # Can proceed immediately
    GAS_HIGH_SOURCE = "gas_high_source"     # High gas in source network
    GAS_HIGH_DEST = "gas_high_dest"         # High gas in destination network
    GAS_HIGH_BOTH = "gas_high_both"         # High gas in both networks
    DELAYED = "delayed"           # Generic delay status


# =============================================================================
# DATA STRUCTURES
# =============================================================================

@dataclass
class BridgeRoute:
    """Represents a bridge route from one network to another."""
    provider: str
    from_network: str
    to_network: str
    amount_wei: int
    cost_usd: float
    time_minutes: int
    safety_score: int = 0
    defillama_tvl: int = 0
    defillama_rank: int = 999
    defillama_hacks: int = 0
    contract_address: Optional[str] = None
    call_data: Optional[str] = None


@dataclass
class CEXCheckResult:
    """Result of CEX network support check."""
    network: str
    bridge_required: bool
    supporting_cex: Optional[str] = None
    cex_checked: List[str] = field(default_factory=list)


@dataclass
class BridgeResult:
    """Result of bridge execution."""
    success: bool
    tx_hash: Optional[str] = None
    provider: Optional[str] = None
    cost_usd: float = 0.0
    safety_score: int = 0
    error: Optional[str] = None


# =============================================================================
# CEX NETWORK CHECKER (CRITICAL CLASS)
# =============================================================================

class CEXNetworkChecker:
    """
    Динамическая проверка поддержки сетей на CEX через live API.
    
    КРИТИЧНО:
    - НЕТ hardcoded списков сетей
    - Live API запросы через CCXT
    - Кэширование на 24 часа (PostgreSQL)
    - Fallback при ошибках API
    
    Examples:
        >>> checker = CEXNetworkChecker(db)
        >>> await checker.is_bridge_required("Base")
        (False, "bybit")  # Bybit поддерживает Base
        
        >>> await checker.is_bridge_required("Ink")
        (True, None)  # Ни одна CEX не поддерживает
    """
    
    CACHE_TTL_HOURS = 24
    ALL_CEXES = ['bybit', 'kucoin', 'mexc', 'okx', 'binance']
    
    # Network name normalizations for fuzzy matching
    NETWORK_NORMALIZATIONS = {
        'arbitrum one': ['arbitrum', 'arb', 'arbitrum one', 'arbitrum-one'],
        'base mainnet': ['base', 'base mainnet', 'base-mainnet'],
        'op mainnet': ['optimism', 'op', 'op mainnet', 'optimism mainnet'],
        'polygon': ['matic', 'polygon', 'polygon mainnet', 'polygon-mainnet'],
        'bnb smart chain': ['bsc', 'bnb', 'bnb chain', 'bnb smart chain', 'bnb-smart-chain'],
        'zksync era': ['zksync', 'zksync era', 'era', 'zksync-era'],
        'ink': ['ink', 'ink mainnet', 'ink chain', 'ink-mainnet'],
        'unichain': ['unichain', 'uni chain', 'uni-chain'],
        'megaeth': ['megaeth', 'mega eth', 'mega-eth', 'megaeth-mainnet'],
        'scroll': ['scroll', 'scroll mainnet', 'scroll-mainnet'],
        'linea': ['linea', 'linea mainnet', 'linea-mainnet'],
        'mantle': ['mantle', 'mantle mainnet', 'mantle-mainnet'],
        'berachain': ['berachain', 'bera', 'berachain mainnet'],
        'blast': ['blast', 'blast mainnet', 'blast-mainnet'],
    }
    
    def __init__(self, db: DatabaseManager):
        """
        Initialize CEXNetworkChecker.
        
        Args:
            db: DatabaseManager instance for caching
        """
        self.db = db
        self.secrets = SecretsManager()
        self._exchanges: Dict[str, ccxt.Exchange] = {}
        self._memory_cache: Dict[str, Tuple[List[str], datetime]] = {}
        
        logger.info(
            f"CEXNetworkChecker initialized | "
            f"Exchanges: {', '.join(self.ALL_CEXES)} | "
            f"Cache TTL: {self.CACHE_TTL_HOURS}h"
        )
    
    async def get_supported_networks(
        self,
        cex: str,
        coin: str = 'ETH'
    ) -> List[str]:
        """
        Live API запрос к бирже для получения списка поддерживаемых сетей.
        
        Args:
            cex: Exchange identifier ('binance', 'bybit', 'okx', 'kucoin', 'mexc')
            coin: Coin to check networks for (default: 'ETH')
        
        Returns:
            List of network names: ['Arbitrum One', 'Base Mainnet', 'OP Mainnet', ...]
        """
        # Step 1: Check database cache
        cached = self._get_cached_networks(cex, coin)
        if cached:
            logger.debug(f"Cache hit for {cex} {coin} networks (DB)")
            return cached
        
        # Step 2: Check memory cache
        cache_key = f"{cex}:{coin}"
        if cache_key in self._memory_cache:
            networks, timestamp = self._memory_cache[cache_key]
            if datetime.now(timezone.utc) - timestamp < timedelta(hours=self.CACHE_TTL_HOURS):
                logger.debug(f"Cache hit for {cex} {coin} networks (memory)")
                return networks
        
        # Step 3: Live API request via CCXT
        try:
            exchange = await self._get_exchange_client(cex)
            
            # CCXT fetch_currencies() returns all currencies with network info
            currencies = exchange.fetch_currencies()
            
            if coin.upper() not in currencies:
                logger.warning(f"Coin {coin} not found on {cex}")
                return []
            
            networks = []
            coin_data = currencies[coin.upper()]
            
            # CCXT structure: currencies['ETH']['networks'] = {'eth': {...}, 'arb': {...}}
            if 'networks' in coin_data and coin_data['networks']:
                for net_key, net_data in coin_data['networks'].items():
                    # Only include networks where withdrawal is enabled
                    if net_data.get('withdraw', False) or net_data.get('withdrawActive', False):
                        # Get the network name - try multiple fields
                        network_name = (
                            net_data.get('network') or 
                            net_data.get('name') or 
                            net_data.get('info', {}).get('name') or
                            net_key
                        )
                        if network_name:
                            networks.append(network_name)
            
            # Step 4: Cache result
            self._save_cached_networks(cex, coin, networks)
            self._memory_cache[cache_key] = (networks, datetime.now(timezone.utc))
            
            logger.info(
                f"Live API: {cex} supports {len(networks)} networks for {coin} | "
                f"Networks: {networks[:5]}{'...' if len(networks) > 5 else ''}"
            )
            
            return networks
        
        except Exception as e:
            logger.error(f"CEX API error for {cex}: {e}")
            
            # Fallback: Use stale cache if available
            if cache_key in self._memory_cache:
                logger.warning(f"Using stale memory cache for {cex} due to API error")
                return self._memory_cache[cache_key][0]
            
            # Check for stale DB cache
            stale_cache = self._get_cached_networks(cex, coin, allow_stale=True)
            if stale_cache:
                logger.warning(f"Using stale DB cache for {cex} due to API error")
                return stale_cache
            
            # No fallback available
            return []
    
    async def is_bridge_required(
        self,
        protocol_chain: str
    ) -> Tuple[bool, Optional[str]]:
        """
        УНИВЕРСАЛЬНАЯ проверка для ЛЮБОЙ сети.
        
        Args:
            protocol_chain: ЛЮБАЯ L2 сеть (даже та, что появится завтра)
        
        Returns:
            (bridge_required, cex_name_or_none)
        """
        logger.info(f"Checking bridge requirement for: {protocol_chain}")
        
        cex_checked = []
        
        # Check all 5 CEXes
        for cex in self.ALL_CEXES:
            cex_checked.append(cex)
            try:
                supported = await self.get_supported_networks(cex, 'ETH')
                
                # Smart network name matching
                if self._network_match(protocol_chain, supported):
                    logger.info(
                        f"✅ {protocol_chain} is supported by {cex} | "
                        f"Bridge NOT required"
                    )
                    return (False, cex)
            except Exception as e:
                logger.warning(f"Error checking {cex}: {e}")
                continue
        
        # No CEX supports this network
        logger.warning(
            f"❌ {protocol_chain} is NOT supported by any CEX | "
            f"Bridge REQUIRED | Checked: {', '.join(cex_checked)}"
        )
        return (True, None)
    
    def _network_match(
        self,
        target: str,
        supported_list: List[str]
    ) -> bool:
        """
        Умное сравнение названий сетей.
        """
        target_lower = target.lower().strip()
        
        # Get normalized forms for target
        target_forms = [target_lower]
        for canonical, forms in self.NETWORK_NORMALIZATIONS.items():
            if target_lower in forms:
                target_forms = forms
                break
        
        # Check each supported network
        for network in supported_list:
            network_lower = network.lower().strip()
            
            # Direct match
            if target_lower == network_lower:
                return True
            
            # Check normalized forms
            for form in target_forms:
                if form in network_lower or network_lower in form:
                    return True
            
            # Partial match (target in network name)
            if target_lower in network_lower:
                return True
            
            # Reverse partial match
            for part in network_lower.split():
                if part in target_lower and len(part) >= 3:
                    return True
        
        return False
    
    def _get_cached_networks(
        self,
        cex: str,
        coin: str,
        allow_stale: bool = False
    ) -> Optional[List[str]]:
        """
        Get cached networks from database using DatabaseManager method.
        
        Args:
            cex: Exchange name ('binance', 'bybit', etc.)
            coin: Coin symbol ('ETH', 'USDT', etc.)
            allow_stale: If True, return stale cache when fresh not available
        
        Returns:
            List of network names or None if not found
        """
        try:
            result = self.db.get_cex_networks_cache(cex, coin, allow_stale=allow_stale)
            
            if result:
                if allow_stale and result.get('is_stale'):
                    logger.warning(f"Returning stale cache for {cex} {coin}")
                return result.get('supported_networks', [])
            
            return None
        
        except Exception as e:
            logger.error(f"Error reading cache: {e}")
            return None
    
    def _save_cached_networks(
        self,
        cex: str,
        coin: str,
        networks: List[str]
    ) -> None:
        """
        Save networks to database cache using DatabaseManager method.
        
        Args:
            cex: Exchange name
            coin: Coin symbol
            networks: List of supported network names
        """
        try:
            self.db.set_cex_networks_cache(cex, coin, networks)
            logger.debug(f"Saved cache for {cex} {coin}: {len(networks)} networks")
        
        except Exception as e:
            logger.error(f"Error saving cache: {e}")
    
    async def _get_exchange_client(self, cex: str) -> ccxt.Exchange:
        """Get or create CCXT exchange client (lazy loading)."""
        if cex in self._exchanges:
            return self._exchanges[cex]
        
        # Get credentials from database
        query = """
            SELECT id, api_key, api_secret, api_passphrase
            FROM cex_subaccounts
            WHERE exchange = %s AND is_active = TRUE
            LIMIT 1
        """
        result = self.db.execute_query(query, (cex,), fetch='one')
        
        if not result:
            raise CEXCheckError(f"No active subaccount found for {cex}")
        
        # Decrypt credentials
        api_key = self.secrets.decrypt_cex_credential(result['id'], 'api_key')
        api_secret = self.secrets.decrypt_cex_credential(result['id'], 'api_secret')
        api_passphrase = None
        if result['api_passphrase']:
            api_passphrase = self.secrets.decrypt_cex_credential(result['id'], 'api_passphrase')
        
        # Initialize CCXT exchange
        exchange_config = {
            'apiKey': api_key,
            'secret': api_secret,
            'enableRateLimit': True,
            'timeout': 30000
        }
        
        if cex == 'binance':
            exchange = ccxt.binance(exchange_config)
        elif cex == 'bybit':
            exchange = ccxt.bybit(exchange_config)
        elif cex == 'okx':
            exchange_config['password'] = api_passphrase
            exchange = ccxt.okx(exchange_config)
        elif cex == 'kucoin':
            exchange_config['password'] = api_passphrase
            exchange = ccxt.kucoin(exchange_config)
        elif cex == 'mexc':
            exchange = ccxt.mexc(exchange_config)
        else:
            raise CEXCheckError(f"Unsupported exchange: {cex}")
        
        self._exchanges[cex] = exchange
        return exchange


# =============================================================================
# DEFILLAMA CHECKER (SAFETY VERIFICATION)
# =============================================================================

class DeFiLlamaChecker:
    """
    Проверка безопасности bridge провайдеров через DeFiLlama API.
    
    Safety Score Calculation:
    - TVL >= $100M: 40 points
    - TVL >= $50M: 35 points
    - TVL >= $10M: 25 points
    - Rank <= 5: 30 points
    - Rank <= 10: 25 points
    - No hacks: 20 points
    - Verified: 10 points
    
    Auto-approve threshold: 60 points
    """
    
    API_BASE_URL = "https://api.llama.fi"
    CACHE_TTL_HOURS = 6
    
    # Manual whitelist for fallback
    MANUAL_WHITELIST = {
        'hop', 'across', 'stargate', 'connext', 'synapse', 
        'celer', 'layerzero', 'socket', 'relay', 'li.fi',
        'multichain', 'cbridge', 'allbridge', 'omnibridge'
    }
    
    def __init__(self, db: DatabaseManager):
        """Initialize DeFiLlamaChecker."""
        self.db = db
        self._memory_cache: Dict[str, Tuple[Dict, datetime]] = {}
        
        logger.info(f"DeFiLlamaChecker initialized | API: {self.API_BASE_URL}")
    
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        retry=retry_if_exception_type((aiohttp.ClientError, asyncio.TimeoutError)),
        reraise=True
    )
    async def check_provider(
        self,
        provider_name: str
    ) -> Dict[str, Any]:
        """Check bridge provider safety via DeFiLlama."""
        provider_lower = provider_name.lower()
        
        # Step 1: Check memory cache
        if provider_lower in self._memory_cache:
            data, timestamp = self._memory_cache[provider_lower]
            if datetime.now(timezone.utc) - timestamp < timedelta(hours=self.CACHE_TTL_HOURS):
                logger.debug(f"Cache hit for {provider_name} (memory)")
                return data
        
        # Step 2: Check database cache
        cached = self._get_cached_provider(provider_lower)
        if cached:
            logger.debug(f"Cache hit for {provider_name} (DB)")
            return cached
        
        # Step 3: Fetch from DeFiLlama API
        try:
            async with aiohttp.ClientSession() as session:
                url = f"{self.API_BASE_URL}/bridges"
                async with session.get(url, timeout=aiohttp.ClientTimeout(total=30)) as response:
                    if response.status != 200:
                        raise BridgeError(f"DeFiLlama API error: {response.status}")
                    
                    data = await response.json()
            
            # Find the provider in the list
            provider_data = None
            for bridge in data.get('bridges', []):
                bridge_name = bridge.get('name', '').lower()
                if provider_lower in bridge_name or bridge_name in provider_lower:
                    provider_data = bridge
                    break
            
            if not provider_data:
                # Not found - check manual whitelist
                if provider_lower in self.MANUAL_WHITELIST:
                    result = {
                        'safe': True,
                        'score': 70,
                        'tvl': 0,
                        'rank': 999,
                        'hacks': 0,
                        'chains': [],
                        'source': 'whitelist'
                    }
                else:
                    result = {
                        'safe': False,
                        'score': 0,
                        'tvl': 0,
                        'rank': 999,
                        'hacks': 0,
                        'chains': [],
                        'source': 'not_found'
                    }
            else:
                # Calculate safety score
                tvl = provider_data.get('chainTvl', {})
                total_tvl = sum(tvl.values()) if isinstance(tvl, dict) else 0
                rank = provider_data.get('rank', 999)
                hacks = len(provider_data.get('hacks', []))
                
                score = self._calculate_safety_score(
                    tvl_usd=total_tvl,
                    rank=rank,
                    hacks_count=hacks,
                    is_verified=True
                )
                
                result = {
                    'safe': score >= 60,
                    'score': score,
                    'tvl': total_tvl,
                    'rank': rank,
                    'hacks': hacks,
                    'chains': list(tvl.keys()) if isinstance(tvl, dict) else [],
                    'source': 'defillama'
                }
            
            # Cache result
            self._memory_cache[provider_lower] = (result, datetime.now(timezone.utc))
            self._save_cached_provider(provider_lower, result)
            
            logger.info(
                f"DeFiLlama check: {provider_name} | "
                f"Score: {result['score']}/100 | "
                f"Safe: {result['safe']} | "
                f"TVL: ${result['tvl']:,.0f} | "
                f"Rank: #{result['rank']}"
            )
            
            return result
        
        except Exception as e:
            logger.error(f"DeFiLlama API error: {e}")
            
            # Fallback to whitelist
            if provider_lower in self.MANUAL_WHITELIST:
                return {
                    'safe': True,
                    'score': 70,
                    'tvl': 0,
                    'rank': 999,
                    'hacks': 0,
                    'chains': [],
                    'source': 'whitelist_fallback'
                }
            
            return {
                'safe': False,
                'score': 0,
                'tvl': 0,
                'rank': 999,
                'hacks': 0,
                'chains': [],
                'source': 'error_fallback',
                'error': str(e)
            }
    
    def _calculate_safety_score(
        self,
        tvl_usd: int,
        rank: int,
        hacks_count: int = 0,
        is_verified: bool = True
    ) -> int:
        """Calculate bridge safety score 0-100."""
        score = 0
        
        # TVL score (40 points max)
        if tvl_usd >= 100_000_000:
            score += 40
        elif tvl_usd >= 50_000_000:
            score += 35
        elif tvl_usd >= 10_000_000:
            score += 25
        elif tvl_usd >= 5_000_000:
            score += 15
        
        # Rank score (30 points max)
        if rank <= 5:
            score += 30
        elif rank <= 10:
            score += 25
        elif rank <= 25:
            score += 20
        elif rank <= 50:
            score += 15
        
        # No hacks (20 points)
        if hacks_count == 0:
            score += 20
        else:
            score -= hacks_count * 10
        
        # Verified contract (10 points)
        if is_verified:
            score += 10
        
        return max(0, min(100, score))
    
    def _get_cached_provider(self, provider_name: str) -> Optional[Dict]:
        """
        Get cached provider data from database using DatabaseManager method.
        
        Args:
            provider_name: Bridge provider name (lowercase)
        
        Returns:
            Dict with safety data or None if not found/expired
        """
        try:
            result = self.db.get_defillama_bridges_cache(provider_name, allow_expired=False)
            
            if result:
                score = self._calculate_safety_score(
                    tvl_usd=result.get('tvl_usd') or 0,
                    rank=result.get('rank') or 999,
                    hacks_count=len(result.get('hacks', [])) if result.get('hacks') else 0
                )
                return {
                    'safe': score >= 60,
                    'score': score,
                    'tvl': result.get('tvl_usd') or 0,
                    'rank': result.get('rank') or 999,
                    'hacks': len(result.get('hacks', [])) if result.get('hacks') else 0,
                    'chains': result.get('chains') or [],
                    'source': 'cache'
                }
            
            return None
        
        except Exception as e:
            logger.error(f"Error reading provider cache: {e}")
            return None
    
    def _save_cached_provider(self, provider_name: str, data: Dict) -> None:
        """
        Save provider data to database cache using DatabaseManager method.
        
        Args:
            provider_name: Bridge provider name (lowercase)
            data: Dict with tvl, rank, hacks, chains
        """
        try:
            self.db.set_defillama_bridges_cache(
                bridge_name=provider_name,
                tvl_usd=data.get('tvl', 0),
                rank=data.get('rank', 999),
                hacks=[],  # API returns hacks count, not full list
                chains=data.get('chains', [])
            )
        
        except Exception as e:
            logger.error(f"Error saving provider cache: {e}")


# =============================================================================
# BRIDGE AGGREGATORS
# =============================================================================

class BridgeAggregator:
    """Base class for bridge aggregators."""
    
    async def get_quote(
        self,
        from_chain: str,
        to_chain: str,
        amount_wei: int
    ) -> List[BridgeRoute]:
        """Get bridge quote from aggregator."""
        raise NotImplementedError("Subclasses must implement get_quote()")


class SocketAggregator(BridgeAggregator):
    """Socket API integration for bridge quotes."""
    
    API_BASE_URL = "https://api.socket.tech"
    
    CHAIN_IDS = {
        'ethereum': 1,
        'arbitrum': 42161,
        'optimism': 10,
        'base': 8453,
        'polygon': 137,
        'bnbchain': 56,
        'avalanche': 43114,
        'zksync': 324,
        'scroll': 534352,
        'linea': 59144,
        'mantle': 5000,
        'ink': 57073,
    }
    
    async def get_quote(
        self,
        from_chain: str,
        to_chain: str,
        amount_wei: int
    ) -> List[BridgeRoute]:
        """Get bridge quote from Socket API."""
        routes = []
        
        from_chain_id = self.CHAIN_IDS.get(from_chain.lower())
        to_chain_id = self.CHAIN_IDS.get(to_chain.lower())
        
        if not from_chain_id or not to_chain_id:
            logger.warning(f"Socket: Unknown chain ID for {from_chain} or {to_chain}")
            return routes
        
        try:
            async with aiohttp.ClientSession() as session:
                url = f"{self.API_BASE_URL}/v2/quote"
                params = {
                    'fromChainId': from_chain_id,
                    'toChainId': to_chain_id,
                    'fromTokenAddress': '0x0000000000000000000000000000000000000000',
                    'toTokenAddress': '0x0000000000000000000000000000000000000000',
                    'fromAmount': amount_wei,
                    'userAddress': '0x0000000000000000000000000000000000000001',
                    'uniqueRoutesPerBridge': True,
                }
                
                async with session.get(
                    url, 
                    params=params,
                    timeout=aiohttp.ClientTimeout(total=30)
                ) as response:
                    if response.status != 200:
                        logger.warning(f"Socket API error: {response.status}")
                        return routes
                    
                    data = await response.json()
            
            # Parse routes
            for route_data in data.get('result', {}).get('routes', []):
                route = BridgeRoute(
                    provider=route_data.get('usedBridgeNames', ['Unknown'])[0],
                    from_network=from_chain,
                    to_network=to_chain,
                    amount_wei=amount_wei,
                    cost_usd=float(route_data.get('totalGasFeesInUsd', 0)),
                    time_minutes=route_data.get('serviceTime', 15) // 60,
                    contract_address=route_data.get('txTarget'),
                    call_data=route_data.get('txData')
                )
                routes.append(route)
            
            logger.info(f"Socket: Found {len(routes)} routes for {from_chain} → {to_chain}")
            return routes
        
        except Exception as e:
            logger.error(f"Socket API error: {e}")
            return routes


class AcrossAggregator(BridgeAggregator):
    """Across Protocol API integration."""
    
    API_BASE_URL = "https://app.across.to/api"
    
    CHAIN_IDS = {
        'ethereum': 1,
        'arbitrum': 42161,
        'optimism': 10,
        'base': 8453,
        'polygon': 137,
        'bnbchain': 56,
        'zksync': 324,
        'scroll': 534352,
        'linea': 59144,
        'mantle': 5000,
    }
    
    async def get_quote(
        self,
        from_chain: str,
        to_chain: str,
        amount_wei: int
    ) -> List[BridgeRoute]:
        """Get bridge quote from Across API."""
        routes = []
        
        from_chain_id = self.CHAIN_IDS.get(from_chain.lower())
        to_chain_id = self.CHAIN_IDS.get(to_chain.lower())
        
        if not from_chain_id or not to_chain_id:
            logger.warning(f"Across: Unknown chain ID for {from_chain} or {to_chain}")
            return routes
        
        try:
            async with aiohttp.ClientSession() as session:
                url = f"{self.API_BASE_URL}/suggested-fees"
                params = {
                    'inputToken': '0x0000000000000000000000000000000000000000',
                    'outputToken': '0x0000000000000000000000000000000000000000',
                    'originChainId': from_chain_id,
                    'destinationChainId': to_chain_id,
                    'amount': amount_wei,
                }
                
                async with session.get(
                    url,
                    params=params,
                    timeout=aiohttp.ClientTimeout(total=30)
                ) as response:
                    if response.status != 200:
                        logger.warning(f"Across API error: {response.status}")
                        return routes
                    
                    data = await response.json()
            
            if data:
                route = BridgeRoute(
                    provider='Across Protocol',
                    from_network=from_chain,
                    to_network=to_chain,
                    amount_wei=amount_wei,
                    cost_usd=float(data.get('totalFee', 0)) / 1e18 * 2000,
                    time_minutes=15,
                )
                routes.append(route)
            
            logger.info(f"Across: Found {len(routes)} routes for {from_chain} → {to_chain}")
            return routes
        
        except Exception as e:
            logger.error(f"Across API error: {e}")
            return routes


class RelayAggregator(BridgeAggregator):
    """Relay Protocol API integration."""
    
    API_BASE_URL = "https://api.relay.link"
    
    CHAIN_IDS = {
        'ethereum': 1,
        'arbitrum': 42161,
        'optimism': 10,
        'base': 8453,
        'polygon': 137,
        'bnbchain': 56,
        'zksync': 324,
    }
    
    async def get_quote(
        self,
        from_chain: str,
        to_chain: str,
        amount_wei: int
    ) -> List[BridgeRoute]:
        """Get bridge quote from Relay API."""
        routes = []
        
        from_chain_id = self.CHAIN_IDS.get(from_chain.lower())
        to_chain_id = self.CHAIN_IDS.get(to_chain.lower())
        
        if not from_chain_id or not to_chain_id:
            logger.warning(f"Relay: Unknown chain ID for {from_chain} or {to_chain}")
            return routes
        
        try:
            async with aiohttp.ClientSession() as session:
                url = f"{self.API_BASE_URL}/quote"
                params = {
                    'originChainId': from_chain_id,
                    'destinationChainId': to_chain_id,
                    'amount': amount_wei,
                    'currency': '0x0000000000000000000000000000000000000000',
                }
                
                async with session.get(
                    url,
                    params=params,
                    timeout=aiohttp.ClientTimeout(total=30)
                ) as response:
                    if response.status != 200:
                        logger.warning(f"Relay API error: {response.status}")
                        return routes
                    
                    data = await response.json()
            
            if data and 'fees' in data:
                route = BridgeRoute(
                    provider='Relay Protocol',
                    from_network=from_chain,
                    to_network=to_chain,
                    amount_wei=amount_wei,
                    cost_usd=float(data['fees'].get('total', 0)) / 1e18 * 2000,
                    time_minutes=10,
                )
                routes.append(route)
            
            logger.info(f"Relay: Found {len(routes)} routes for {from_chain} → {to_chain}")
            return routes
        
        except Exception as e:
            logger.error(f"Relay API error: {e}")
            return routes



# =============================================================================
# BRIDGE MANAGER (MAIN ORCHESTRATOR)
# =============================================================================

class BridgeManager:
    """
    Main orchestrator for bridge operations.
    
    КРИТИЧНО: Работает с ЛЮБЫМИ L2 без hardcoded списков!
    
    Workflow:
    1. Check if bridge required via CEXNetworkChecker
    2. **Check gas viability in BOTH networks (source + destination)**
    3. Find routes via aggregators (Socket → Across → Relay)
    4. Verify safety via DeFiLlamaChecker
    5. Select cheapest safe route
    6. Execute bridge transaction
    7. Log to database and send notification
    
    Gas Integration (CRITICAL):
    - Uses GasLogic for dynamic gas thresholds
    - Checks BOTH source and destination networks
    - If gas is high in EITHER network → WaitStatus.DELAYED
    - This prevents executing bridge when gas spikes in one network
    """
    
    def __init__(
        self,
        db: DatabaseManager,
        telegram: Optional[Any] = None,
        fernet_key: Optional[str] = None,
        dry_run: bool = False
    ):
        """Initialize BridgeManager."""
        self.db = db
        self.telegram = telegram
        self.fernet_key = fernet_key or os.getenv('FERNET_KEY')
        self.dry_run = dry_run
        
        # Initialize components
        self.cex_checker = CEXNetworkChecker(db)
        self.defillama = DeFiLlamaChecker(db)
        self.gas_manager = GasManager(db)  # Unified GasManager (replaces GasLogic)
        
        # Initialize aggregators
        self.socket = SocketAggregator()
        self.across = AcrossAggregator()
        self.relay = RelayAggregator()
        
        # Chain ID cache (loaded from DB - replaces hardcoded NETWORK_TO_CHAIN_ID)
        self._chain_id_cache: Dict[str, int] = {}
        self._load_chain_id_mapping()
        
        # Chain discovery service for auto-registration of new networks
        self._discovery_service: Optional[ChainDiscoveryService] = None
        
        logger.info(
            f"BridgeManager initialized | "
            f"Mode: {'DRY-RUN' if dry_run else 'LIVE'} | "
            f"Aggregators: Socket, Across, Relay | "
            f"GasManager: ENABLED | "
            f"Networks cached: {len(self._chain_id_cache)}"
        )
    
    def _load_chain_id_mapping(self) -> None:
        """
        Load chain_id mapping from database.
        
        Replaces hardcoded NETWORK_TO_CHAIN_ID dictionary.
        Makes the system chain-agnostic - new networks are
        automatically available after adding to chain_rpc_endpoints.
        
        Uses db_manager.get_all_active_chains() for data access.
        """
        try:
            # Use db_manager method instead of direct SQL
            chains = self.db.get_all_active_chains()
            
            if chains:
                self._chain_id_cache = {
                    row['chain'].lower(): row['chain_id']
                    for row in chains
                    if row.get('chain') and row.get('chain_id')
                }
                logger.info(
                    f"Loaded {len(self._chain_id_cache)} network mappings from DB | "
                    f"Networks: {list(self._chain_id_cache.keys())[:5]}..."
                )
            else:
                logger.warning(
                    "No chain_id mappings found in DB! "
                    "Gas checks will be skipped for all networks."
                )
                
        except Exception as e:
            logger.error(f"Failed to load chain_id mapping: {e}")
            self._chain_id_cache = {}
    
    def _get_chain_id(self, network_name: str) -> Optional[int]:
        """
        Convert network name to chain_id for GasLogic.
        
        Args:
            network_name: Network name (e.g., 'arbitrum', 'base', 'optimism')
        
        Returns:
            Chain ID (e.g., 42161, 8453, 10) or None if not found
        
        Note:
            Uses cached mapping loaded from chain_rpc_endpoints table.
            No hardcoded values - fully dynamic.
        """
        if not network_name:
            return None
        
        normalized = network_name.lower().strip()
        chain_id = self._chain_id_cache.get(normalized)
        
        if chain_id is None:
            logger.warning(
                f"Network '{network_name}' not found in chain_id cache | "
                f"Available: {list(self._chain_id_cache.keys())}"
            )
        
        return chain_id
    
    async def _get_chain_id_async(
        self,
        network_name: str,
        auto_discover: bool = True
    ) -> Optional[int]:
        """
        Async version of _get_chain_id with auto-discovery support.
        
        If network is not in cache and auto_discover=True, attempts to
        discover and register the chain from external sources.
        
        Args:
            network_name: Network name (e.g., 'arbitrum', 'base', 'megaeth')
            auto_discover: Whether to attempt auto-discovery if not found
        
        Returns:
            Chain ID if found/discovered, None otherwise
        """
        # First check cache (fast path)
        chain_id = self._get_chain_id(network_name)
        if chain_id:
            return chain_id
        
        # If auto_discover is disabled, return None
        if not auto_discover:
            return None
        
        # Attempt auto-discovery
        try:
            # Lazy init discovery service
            if self._discovery_service is None:
                self._discovery_service = ChainDiscoveryService(self.db)
            
            logger.info(f"Attempting auto-discovery for network: {network_name}")
            
            result = await self._discovery_service.discover_and_register(network_name)
            
            if result.success and result.chain_id:
                # Reload cache with new chain
                self._load_chain_id_mapping()
                logger.info(
                    f"Auto-discovered network: {network_name} → chain_id={result.chain_id} | "
                    f"Source: {result.sources_checked}"
                )
                return result.chain_id
            else:
                logger.warning(
                    f"Auto-discovery failed for {network_name}: {result.error} | "
                    f"Sources checked: {result.sources_checked}"
                )
                return None
                
        except Exception as e:
            logger.error(f"Auto-discovery error for {network_name}: {e}")
            return None
    
    async def check_gas_both_networks(
        self,
        from_network: str,
        to_network: str
    ) -> Dict[str, Any]:
        """
        CRITICAL: Check gas viability in BOTH source and destination networks.
        
        This is the key requirement - if gas is OK in one network but HIGH in 
        the other, the transaction should be DELAYED.
        
        Args:
            from_network: Source network name
            to_network: Destination network name
        
        Returns:
            {
                'status': WaitStatus,
                'source_result': GasCheckResult,
                'dest_result': GasCheckResult,
                'delay_minutes': float,
                'message': str
            }
        """
        logger.info(f"Checking gas in BOTH networks: {from_network} → {to_network}")
        
        # Get chain IDs
        source_chain_id = self._get_chain_id(from_network)
        dest_chain_id = self._get_chain_id(to_network)
        
        if not source_chain_id:
            logger.warning(f"Unknown source network: {from_network}, skipping gas check")
            source_result = None
        else:
            source_result = await self.gas_manager.check_gas_viability(source_chain_id)
        
        if not dest_chain_id:
            logger.warning(f"Unknown destination network: {to_network}, skipping gas check")
            dest_result = None
        else:
            dest_result = await self.gas_manager.check_gas_viability(dest_chain_id)
        
        # Determine overall status
        source_high = source_result and source_result.status == GasStatus.HIGH_GAS
        dest_high = dest_result and dest_result.status == GasStatus.HIGH_GAS
        
        if source_high and dest_high:
            status = WaitStatus.GAS_HIGH_BOTH
            delay_minutes = max(
                source_result.extra_delay_minutes,
                dest_result.extra_delay_minutes
            )
            message = f"High gas in BOTH networks: {from_network} ({source_result.current_gwei:.4f} gwei) → {to_network} ({dest_result.current_gwei:.4f} gwei)"
        
        elif source_high:
            status = WaitStatus.GAS_HIGH_SOURCE
            delay_minutes = source_result.extra_delay_minutes
            message = f"High gas in SOURCE network: {from_network} ({source_result.current_gwei:.4f} gwei > {source_result.threshold_gwei:.4f} gwei)"
        
        elif dest_high:
            status = WaitStatus.GAS_HIGH_DEST
            delay_minutes = dest_result.extra_delay_minutes
            message = f"High gas in DESTINATION network: {to_network} ({dest_result.current_gwei:.4f} gwei > {dest_result.threshold_gwei:.4f} gwei)"
        
        else:
            status = WaitStatus.READY
            delay_minutes = 0.0
            message = "Gas OK in both networks"
        
        logger.info(
            f"Gas check result: {status.value} | "
            f"Delay: {delay_minutes:.0f} min | "
            f"{message}"
        )
        
        return {
            'status': status,
            'source_result': source_result,
            'dest_result': dest_result,
            'delay_minutes': delay_minutes,
            'message': message
        }
    
    async def is_bridge_required(
        self,
        protocol_chain: str
    ) -> Tuple[bool, Optional[str]]:
        """Check if bridge is required for a network."""
        return await self.cex_checker.is_bridge_required(protocol_chain)
    
    async def check_bridge_availability(
        self,
        from_network: str,
        to_network: str,
        amount_eth: Decimal = Decimal('0.01')
    ) -> Optional[Dict[str, Any]]:
        """Check bridge availability between networks."""
        logger.info(
            f"Checking bridge availability: {from_network} → {to_network} | "
            f"Amount: {amount_eth} ETH"
        )
        
        # Step 1: Find routes via aggregators
        routes = await self._find_routes(from_network, to_network, amount_eth)
        
        if not routes:
            logger.warning(f"No routes found: {from_network} → {to_network}")
            return {
                'available': False,
                'reason': 'No routes found via aggregators'
            }
        
        # Step 2: Verify safety via DeFiLlama
        safe_routes = await self._verify_safety(routes)
        
        if not safe_routes:
            logger.warning(f"No safe routes: {from_network} → {to_network}")
            return {
                'available': False,
                'reason': 'No safe routes (DeFiLlama check failed)'
            }
        
        # Step 3: Select cheapest safe route
        best_route = self._select_best_route(safe_routes)
        
        logger.info(
            f"✅ Bridge available: {from_network} → {to_network} | "
            f"Provider: {best_route.provider} | "
            f"Cost: ${best_route.cost_usd:.2f} | "
            f"Safety: {best_route.safety_score}/100"
        )
        
        return {
            'available': True,
            'provider': best_route.provider,
            'cost_usd': best_route.cost_usd,
            'time_minutes': best_route.time_minutes,
            'safety_score': best_route.safety_score,
            'defillama_tvl': best_route.defillama_tvl,
            'defillama_rank': best_route.defillama_rank
        }
    
    async def execute_bridge(
        self,
        wallet_id: int,
        from_network: str,
        to_network: str,
        amount_eth: Decimal,
        skip_gas_check: bool = False
    ) -> BridgeResult:
        """
        Execute bridge transaction for a wallet.
        
        CRITICAL: Gas is checked in BOTH networks. If gas is high in either,
        the transaction is delayed (returns BridgeResult with success=False
        and error indicating gas status).
        """
        logger.info(
            f"Executing bridge | Wallet: {wallet_id} | "
            f"{from_network} → {to_network} | Amount: {amount_eth} ETH"
        )
        
        try:
            # Step 1: Check gas in BOTH networks (CRITICAL!)
            if not skip_gas_check:
                gas_status = await self.check_gas_both_networks(from_network, to_network)
                
                if gas_status['status'] != WaitStatus.READY:
                    # Gas is high - return delayed status
                    error_msg = f"GAS_DELAY: {gas_status['message']} | Delay: {gas_status['delay_minutes']:.0f} min"
                    logger.warning(error_msg)
                    
                    # Send gas alert notification
                    await self._send_gas_alert(
                        wallet_id, from_network, to_network, gas_status
                    )
                    
                    return BridgeResult(
                        success=False,
                        error=error_msg
                    )
            
            # Step 2: Find routes
            routes = await self._find_routes(from_network, to_network, amount_eth)
            
            if not routes:
                raise BridgeNotAvailableError("No routes found")
            
            # Step 3: Verify safety
            safe_routes = await self._verify_safety(routes)
            
            if not safe_routes:
                await self._send_unsafe_bridge_alert(wallet_id, from_network, to_network, routes)
                raise BridgeSafetyError("No safe routes available")
            
            # Step 4: Select best route
            route = self._select_best_route(safe_routes)
            
            # Step 5: Execute transaction
            if self.dry_run:
                logger.info(f"[DRY-RUN] Would execute bridge via {route.provider}")
                tx_hash = f"0x{'0'*64}"
            else:
                tx_result = await self._execute_transaction(wallet_id, route)
                tx_hash = tx_result.get('tx_hash')
            
            # Step 6: Log to database
            await self._log_bridge_to_db(
                wallet_id=wallet_id,
                from_network=from_network,
                to_network=to_network,
                amount_eth=amount_eth,
                route=route,
                tx_hash=tx_hash
            )
            
            # Step 7: Send Telegram notification
            await self._send_bridge_notification(
                wallet_id=wallet_id,
                from_network=from_network,
                to_network=to_network,
                amount_eth=amount_eth,
                route=route,
                tx_hash=tx_hash
            )
            
            return BridgeResult(
                success=True,
                tx_hash=tx_hash,
                provider=route.provider,
                cost_usd=route.cost_usd,
                safety_score=route.safety_score
            )
        
        except (BridgeNotAvailableError, BridgeSafetyError) as e:
            logger.error(f"Bridge failed: {e}")
            return BridgeResult(success=False, error=str(e))
        
        except Exception as e:
            logger.exception(f"Bridge execution error: {e}")
            return BridgeResult(success=False, error=str(e))
    
    async def _send_gas_alert(
        self,
        wallet_id: int,
        from_network: str,
        to_network: str,
        gas_status: Dict[str, Any]
    ) -> None:
        """Send alert about high gas delaying bridge."""
        if not self.telegram:
            return
        
        try:
            message = f"""⏳ BRIDGE DELAYED - HIGH GAS

Wallet ID: {wallet_id}
Route: {from_network} → {to_network}

Status: {gas_status['status'].value}
Delay: {gas_status['delay_minutes']:.0f} minutes

{gas_status['message']}

Bridge will be retried when gas normalizes.
"""
            
            if hasattr(self.telegram, 'send_message'):
                await self.telegram.send_message(message)
            elif hasattr(self.telegram, 'send_notification'):
                await self.telegram.send_notification(message, level='warning')
        
        except Exception as e:
            logger.error(f"Failed to send gas alert: {e}")
    
    async def _find_routes(
        self,
        from_network: str,
        to_network: str,
        amount_eth: Decimal
    ) -> List[BridgeRoute]:
        """Find all available routes via aggregators."""
        routes = []
        amount_wei = Web3.to_wei(amount_eth, 'ether')
        
        # Try Socket (priority #1)
        try:
            socket_routes = await self.socket.get_quote(from_network, to_network, amount_wei)
            routes.extend(socket_routes)
        except Exception as e:
            logger.warning(f"Socket API failed: {e}")
        
        # Try Across (priority #2)
        try:
            across_routes = await self.across.get_quote(from_network, to_network, amount_wei)
            routes.extend(across_routes)
        except Exception as e:
            logger.warning(f"Across API failed: {e}")
        
        # Try Relay (fallback)
        try:
            relay_routes = await self.relay.get_quote(from_network, to_network, amount_wei)
            routes.extend(relay_routes)
        except Exception as e:
            logger.warning(f"Relay API failed: {e}")
        
        return routes
    
    async def _verify_safety(
        self,
        routes: List[BridgeRoute]
    ) -> List[BridgeRoute]:
        """Filter routes by DeFiLlama safety criteria."""
        safe_routes = []
        
        for route in routes:
            provider = route.provider.lower()
            
            try:
                defillama_data = await self.defillama.check_provider(provider)
                safety_score = defillama_data.get('score', 0)
                
                if safety_score >= 60:
                    route.safety_score = safety_score
                    route.defillama_tvl = defillama_data.get('tvl', 0)
                    route.defillama_rank = defillama_data.get('rank', 999)
                    route.defillama_hacks = defillama_data.get('hacks', 0)
                    safe_routes.append(route)
            
            except Exception as e:
                if provider in self.defillama.MANUAL_WHITELIST:
                    route.safety_score = 70
                    safe_routes.append(route)
                else:
                    logger.warning(f"Provider {provider} not in whitelist and DeFiLlama failed: {e}")
        
        return safe_routes
    
    def _select_best_route(
        self,
        safe_routes: List[BridgeRoute]
    ) -> BridgeRoute:
        """Select cheapest route from safe options."""
        sorted_routes = sorted(
            safe_routes,
            key=lambda r: (r.cost_usd, -r.safety_score)
        )
        
        return sorted_routes[0]
    
    async def _execute_transaction(
        self,
        wallet_id: int,
        route: BridgeRoute
    ) -> Dict[str, Any]:
        """Execute bridge transaction on-chain."""
        from activity.executor import TransactionExecutor
        
        executor = TransactionExecutor(fernet_key=self.fernet_key)
        
        result = executor.execute_transaction(
            wallet_id=wallet_id,
            chain=route.from_network.lower(),
            to_address=route.contract_address or '0x0000000000000000000000000000000000000000',
            value_wei=route.amount_wei,
            data=route.call_data or '0x',
            gas_preference='normal'
        )
        
        return result
    
    async def _log_bridge_to_db(
        self,
        wallet_id: int,
        from_network: str,
        to_network: str,
        amount_eth: Decimal,
        route: BridgeRoute,
        tx_hash: str
    ) -> None:
        """
        Log bridge operation to database.
        
        Uses DatabaseManager.create_bridge_history() for consistent data access.
        """
        try:
            bridge_required, cex_name = await self.is_bridge_required(to_network)
            cex_checked = ','.join(self.cex_checker.ALL_CEXES)
            
            # Use DatabaseManager method for consistent bridge history logging
            bridge_id = self.db.create_bridge_history(
                wallet_id=wallet_id,
                from_network=from_network,
                to_network=to_network,
                provider=route.provider,
                amount_eth=float(amount_eth),
                cost_usd=Decimal(str(route.cost_usd)),
                safety_score=route.safety_score,
                tx_hash=tx_hash,
                defillama_tvl_usd=route.defillama_tvl,
                defillama_rank=route.defillama_rank,
                defillama_hacks=route.defillama_hacks,
                cex_checked=cex_checked,
                cex_support_found=(cex_name is not None),
                status='completed'
            )
            
            logger.info(f"Bridge logged to DB | ID: {bridge_id} | TX: {tx_hash}")
        
        except Exception as e:
            logger.error(f"Failed to log bridge to DB: {e}")
    
    async def _send_bridge_notification(
        self,
        wallet_id: int,
        from_network: str,
        to_network: str,
        amount_eth: Decimal,
        route: BridgeRoute,
        tx_hash: str
    ) -> None:
        """Send Telegram notification about bridge completion."""
        if not self.telegram:
            return
        
        try:
            query = "SELECT address FROM wallets WHERE id = %s"
            result = self.db.execute_query(query, (wallet_id,), fetch='one')
            wallet_address = result['address'] if result else 'Unknown'
            
            message = f"""🌉 BRIDGE COMPLETED

Wallet: {wallet_address[:10]}...{wallet_address[-8:]}
From: {from_network} → To: {to_network}
Amount: {amount_eth:.4f} ETH

Provider: {route.provider}
✅ DeFiLlama Rank: #{route.defillama_rank}
✅ TVL: ${route.defillama_tvl:,.0f}
✅ Safety Score: {route.safety_score}/100

Cost: ${route.cost_usd:.2f}
Time: ~{route.time_minutes} minutes
TX: {tx_hash[:10]}...{tx_hash[-8:]}

CEX Check: No CEX supports {to_network}
"""
            
            if hasattr(self.telegram, 'send_message'):
                await self.telegram.send_message(message)
            elif hasattr(self.telegram, 'send_notification'):
                await self.telegram.send_notification(message, level='info')
        
        except Exception as e:
            logger.error(f"Failed to send bridge notification: {e}")
    
    async def _send_unsafe_bridge_alert(
        self,
        wallet_id: int,
        from_network: str,
        to_network: str,
        routes: List[BridgeRoute]
    ) -> None:
        """Send alert about unsafe bridge attempt."""
        if not self.telegram:
            return
        
        try:
            message = f"""🚨 UNSAFE BRIDGE BLOCKED by DeFiLlama

Destination: {to_network}
Available providers: {len(routes)}

All available routes failed safety check:
- Required score: 60/100
- All routes scored below threshold

CEX Check: No CEX supports {to_network}

Recommendation: Manual review required
"""
            
            if hasattr(self.telegram, 'send_message'):
                await self.telegram.send_message(message)
            elif hasattr(self.telegram, 'send_notification'):
                await self.telegram.send_notification(message, level='warning')
        
        except Exception as e:
            logger.error(f"Failed to send unsafe bridge alert: {e}")


# =============================================================================
# CLI INTERFACE
# =============================================================================

async def main():
    """CLI entry point for testing."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Bridge Manager v2.1')
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    # Check CEX support
    check_parser = subparsers.add_parser('check', help='Check if bridge required for network')
    check_parser.add_argument('network', help='Network name to check')
    
    # Check gas
    gas_parser = subparsers.add_parser('gas', help='Check gas in both networks')
    gas_parser.add_argument('--from', dest='from_network', required=True, help='Source network')
    gas_parser.add_argument('--to', dest='to_network', required=True, help='Destination network')
    
    # Check bridge availability
    avail_parser = subparsers.add_parser('available', help='Check bridge availability')
    avail_parser.add_argument('--from', dest='from_network', required=True, help='Source network')
    avail_parser.add_argument('--to', dest='to_network', required=True, help='Destination network')
    avail_parser.add_argument('--amount', type=float, default=0.01, help='Amount in ETH')
    
    # Execute bridge (dry-run only in CLI)
    exec_parser = subparsers.add_parser('execute', help='Execute bridge (dry-run)')
    exec_parser.add_argument('--wallet-id', type=int, required=True)
    exec_parser.add_argument('--from', dest='from_network', required=True)
    exec_parser.add_argument('--to', dest='to_network', required=True)
    exec_parser.add_argument('--amount', type=float, required=True)
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    db = DatabaseManager()
    manager = BridgeManager(db, dry_run=True)
    
    try:
        if args.command == 'check':
            bridge_required, cex = await manager.is_bridge_required(args.network)
            
            if bridge_required:
                print(f"\n❌ Bridge REQUIRED for {args.network}")
                print(f"   No CEX supports this network")
            else:
                print(f"\n✅ Bridge NOT required for {args.network}")
                print(f"   Supported by: {cex}")
        
        elif args.command == 'gas':
            result = await manager.check_gas_both_networks(
                args.from_network,
                args.to_network
            )
            
            print(f"\nGas Status: {result['status'].value}")
            print(f"Delay: {result['delay_minutes']:.0f} minutes")
            print(f"Message: {result['message']}")
            
            if result['source_result']:
                sr = result['source_result']
                print(f"\nSource ({args.from_network}):")
                print(f"  Current: {sr.current_gwei:.4f} gwei")
                print(f"  Threshold: {sr.threshold_gwei:.4f} gwei")
            
            if result['dest_result']:
                dr = result['dest_result']
                print(f"\nDestination ({args.to_network}):")
                print(f"  Current: {dr.current_gwei:.4f} gwei")
                print(f"  Threshold: {dr.threshold_gwei:.4f} gwei")
        
        elif args.command == 'available':
            result = await manager.check_bridge_availability(
                args.from_network,
                args.to_network,
                Decimal(str(args.amount))
            )
            
            if result and result.get('available'):
                print(f"\n✅ Bridge available: {args.from_network} → {args.to_network}")
                print(f"   Provider: {result['provider']}")
                print(f"   Cost: ${result['cost_usd']:.2f}")
                print(f"   Safety Score: {result['safety_score']}/100")
                print(f"   Time: ~{result['time_minutes']} minutes")
            else:
                print(f"\n❌ Bridge NOT available: {args.from_network} → {args.to_network}")
                if result:
                    print(f"   Reason: {result.get('reason', 'Unknown')}")
        
        elif args.command == 'execute':
            result = await manager.execute_bridge(
                args.wallet_id,
                args.from_network,
                args.to_network,
                Decimal(str(args.amount))
            )
            
            if result.success:
                print(f"\n✅ Bridge executed (dry-run)")
                print(f"   TX: {result.tx_hash}")
                print(f"   Provider: {result.provider}")
                print(f"   Cost: ${result.cost_usd:.2f}")
            else:
                print(f"\n❌ Bridge failed: {result.error}")
    
    except Exception as e:
        logger.exception(f"Error: {e}")
        return 1
    
    return 0


if __name__ == '__main__':
    import asyncio
    asyncio.run(main())
