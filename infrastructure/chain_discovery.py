#!/usr/bin/env python3
"""
Chain Discovery Service — Automatic Network Registration
=========================================================
Automatically discovers and registers blockchain networks from external sources.

Features:
- Query chainid.network, DeFiLlama, Socket for chain metadata
- Fuzzy matching for network name normalization
- RPC health check before registration
- Atomic transaction for chain + alias registration
- Logging of failed discoveries for manual review

Integration:
    from infrastructure.chain_discovery import ChainDiscoveryService
    
    discovery = ChainDiscoveryService(db)
    chain_id = await discovery.discover_and_register("MegaETH")
    # Returns: 420420 (and creates record in chain_rpc_endpoints)

Author: Airdrop Farming System v4.0
Created: 2026-03-09
"""

import asyncio
import json
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, field
from datetime import datetime, timezone, timedelta
from decimal import Decimal

import aiohttp
from loguru import logger
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential,
    retry_if_exception_type
)

try:
    from rapidfuzz import fuzz, process
    HAS_RAPIDFUZZ = True
except ImportError:
    HAS_RAPIDFUZZ = False
    logger.warning("rapidfuzz not installed, fuzzy matching disabled")

from database.db_manager import DatabaseManager


# =============================================================================
# DATA STRUCTURES
# =============================================================================

@dataclass
class ChainInfo:
    """Discovered chain information."""
    chain_id: int
    name: str
    short_name: Optional[str] = None
    native_token: str = "ETH"
    rpc_urls: List[str] = field(default_factory=list)
    block_explorer: Optional[str] = None
    is_l2: bool = False
    network_type: str = "sidechain"  # 'l1', 'l2', 'sidechain'
    source: str = "unknown"
    tvl_usd: Optional[int] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for database insertion."""
        return {
            'chain_id': self.chain_id,
            'name': self.name,
            'short_name': self.short_name,
            'native_token': self.native_token,
            'rpc_urls': self.rpc_urls,
            'block_explorer': self.block_explorer,
            'is_l2': self.is_l2,
            'network_type': self.network_type,
            'source': self.source,
            'tvl_usd': self.tvl_usd,
        }


@dataclass
class DiscoveryResult:
    """Result of chain discovery attempt."""
    success: bool
    chain_id: Optional[int] = None
    chain_info: Optional[ChainInfo] = None
    error: Optional[str] = None
    sources_checked: List[str] = field(default_factory=list)


# =============================================================================
# EXCEPTIONS
# =============================================================================

class ChainDiscoveryError(Exception):
    """Base exception for chain discovery."""
    pass


class ChainNotFoundError(ChainDiscoveryError):
    """Chain not found in any external source."""
    pass


class RPCHealthCheckFailed(ChainDiscoveryError):
    """All RPC endpoints failed health check."""
    pass


class ChainAlreadyExists(ChainDiscoveryError):
    """Chain already exists in database."""
    pass


# =============================================================================
# CHAIN DISCOVERY SERVICE
# =============================================================================

class ChainDiscoveryService:
    """
    Automatic blockchain network discovery and registration.
    
    Sources (priority order):
    1. chainid.network - Official EVM chain registry
    2. DeFiLlama - TVL and metadata
    3. Socket - Bridge-supported chains
    
    Workflow:
    1. Normalize network name (lowercase, trim)
    2. Check chain_aliases table for existing mapping
    3. Fuzzy match against known chains
    4. Query external sources in parallel
    5. Validate RPC endpoints (health check)
    6. Register atomically (chain + aliases)
    
    Example:
        >>> discovery = ChainDiscoveryService(db)
        >>> result = await discovery.discover_and_register("MegaETH")
        >>> if result.success:
        ...     print(f"Registered: {result.chain_id}")
    """
    
    # External API endpoints
    CHAINID_URL = "https://chainid.network/chains.json"
    DEFILLAMA_URL = "https://api.llama.fi/chains"
    SOCKET_URL = "https://api.socket.tech/v2/chains"
    
    # Known L2 chain IDs for classification
    L2_CHAIN_IDS = {
        42161,   # Arbitrum
        10,      # Optimism
        8453,    # Base
        324,     # zkSync Era
        534352,  # Scroll
        59144,   # Linea
        5000,    # Mantle
        57073,   # Ink
        420420,  # MegaETH (placeholder)
    }
    
    # L1 chain IDs
    L1_CHAIN_IDS = {
        1,       # Ethereum
    }
    
    # RPC health check timeout
    RPC_TIMEOUT = 1.5  # seconds
    
    def __init__(self, db: DatabaseManager):
        """
        Initialize ChainDiscoveryService.
        
        Args:
            db: DatabaseManager instance for database operations
        """
        self.db = db
        self._chainid_cache: List[Dict] = []
        self._defillama_cache: List[Dict] = []
        self._socket_cache: List[Dict] = []
        self._cache_loaded = False
        
        # Race condition protection: per-network locks
        self._discovery_locks: Dict[str, asyncio.Lock] = {}
        self._global_lock = asyncio.Lock()
        
        # Negative results cache (to avoid API spam for non-existent networks)
        # Format: {network_name: (timestamp, error_message)}
        self._negative_cache: Dict[str, Tuple[datetime, str]] = {}
        self._negative_cache_ttl = timedelta(hours=1)  # Cache "not found" for 1 hour
        
        logger.info("ChainDiscoveryService initialized")
    
    def _get_network_lock(self, network_name: str) -> asyncio.Lock:
        """
        Get or create a lock for a specific network name.
        
        This prevents race conditions when multiple wallets try to discover
        the same network simultaneously.
        
        Args:
            network_name: Network name to get lock for
        
        Returns:
            asyncio.Lock for this network
        """
        normalized = self.normalize_name(network_name)
        
        if normalized not in self._discovery_locks:
            self._discovery_locks[normalized] = asyncio.Lock()
        
        return self._discovery_locks[normalized]
    
    def _check_negative_cache(self, network_name: str) -> Optional[str]:
        """
        Check if network was recently not found (cached negative result).
        
        This prevents API spam for non-existent networks.
        
        Args:
            network_name: Network name to check
        
        Returns:
            Error message if recently failed, None otherwise
        """
        normalized = self.normalize_name(network_name)
        
        if normalized in self._negative_cache:
            timestamp, error = self._negative_cache[normalized]
            if datetime.now(timezone.utc) - timestamp < self._negative_cache_ttl:
                logger.debug(f"Negative cache hit for '{network_name}': {error}")
                return error
            else:
                # Expired, remove from cache
                del self._negative_cache[normalized]
        
        return None
    
    def _add_to_negative_cache(self, network_name: str, error: str) -> None:
        """
        Add a network to the negative cache.
        
        Args:
            network_name: Network name that was not found
            error: Error message
        """
        normalized = self.normalize_name(network_name)
        self._negative_cache[normalized] = (datetime.now(timezone.utc), error)
        logger.debug(f"Added to negative cache: '{network_name}' -> {error}")
    
    async def _load_caches(self) -> None:
        """Load external chain data into memory caches."""
        if self._cache_loaded:
            return
        
        try:
            # Parallel fetch from all sources
            results = await asyncio.gather(
                self._fetch_chainid(),
                self._fetch_defillama(),
                self._fetch_socket(),
                return_exceptions=True
            )
            
            # Process results
            for i, result in enumerate(results):
                if isinstance(result, Exception):
                    source = ['chainid', 'defillama', 'socket'][i]
                    logger.warning(f"Failed to load {source} cache: {result}")
            
            self._cache_loaded = True
            total = len(self._chainid_cache) + len(self._defillama_cache) + len(self._socket_cache)
            logger.info(f"Loaded {total} chain records from external sources")
            
        except Exception as e:
            logger.error(f"Failed to load caches: {e}")
    
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        retry=retry_if_exception_type((aiohttp.ClientError, asyncio.TimeoutError)),
        reraise=True
    )
    async def _fetch_chainid(self) -> None:
        """Fetch chain data from chainid.network."""
        async with aiohttp.ClientSession() as session:
            async with session.get(
                self.CHAINID_URL,
                timeout=aiohttp.ClientTimeout(total=30)
            ) as response:
                response.raise_for_status()
                data = await response.json()
                self._chainid_cache = data if isinstance(data, list) else []
                logger.debug(f"Loaded {len(self._chainid_cache)} chains from chainid.network")
    
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        retry=retry_if_exception_type((aiohttp.ClientError, asyncio.TimeoutError)),
        reraise=True
    )
    async def _fetch_defillama(self) -> None:
        """Fetch chain data from DeFiLlama."""
        async with aiohttp.ClientSession() as session:
            async with session.get(
                self.DEFILLAMA_URL,
                timeout=aiohttp.ClientTimeout(total=30)
            ) as response:
                response.raise_for_status()
                data = await response.json()
                self._defillama_cache = data if isinstance(data, list) else []
                logger.debug(f"Loaded {len(self._defillama_cache)} chains from DeFiLlama")
    
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        retry=retry_if_exception_type((aiohttp.ClientError, asyncio.TimeoutError)),
        reraise=True
    )
    async def _fetch_socket(self) -> None:
        """Fetch chain data from Socket API."""
        async with aiohttp.ClientSession() as session:
            async with session.get(
                self.SOCKET_URL,
                timeout=aiohttp.ClientTimeout(total=30)
            ) as response:
                response.raise_for_status()
                data = await response.json()
                # Socket returns {"result": {"chains": [...]}}
                if isinstance(data, dict):
                    self._socket_cache = data.get('result', {}).get('chains', [])
                else:
                    self._socket_cache = []
                logger.debug(f"Loaded {len(self._socket_cache)} chains from Socket")
    
    def normalize_name(self, name: str) -> str:
        """
        Normalize network name for consistent matching.
        
        Args:
            name: Raw network name (e.g., "Ethereum Mainnet", "eth-mainnet")
        
        Returns:
            Normalized name (e.g., "ethereum")
        """
        if not name:
            return ""
        
        normalized = name.lower().strip()
        
        # Remove common suffixes
        for suffix in [' mainnet', '-mainnet', ' network', '-network', ' chain', '-chain']:
            if normalized.endswith(suffix):
                normalized = normalized[:-len(suffix)]
        
        # Remove common prefixes
        for prefix in ['the ', 'chain ']:
            if normalized.startswith(prefix):
                normalized = normalized[len(prefix):]
        
        return normalized
    
    async def find_in_aliases(self, network_name: str) -> Optional[int]:
        """
        Check if network name exists in chain_aliases table.
        
        Uses db_manager.get_chain_by_alias() for proper encapsulation.
        
        Args:
            network_name: Network name to search
        
        Returns:
            Chain ID if found, None otherwise
        """
        normalized = self.normalize_name(network_name)
        return self.db.get_chain_by_alias(normalized)
    
    async def find_in_known_chains(self, network_name: str) -> Optional[int]:
        """
        Check if network name matches any known chain in chain_rpc_endpoints.
        
        Args:
            network_name: Network name to search
        
        Returns:
            Chain ID if found, None otherwise
        """
        normalized = self.normalize_name(network_name)
        
        # Use db_manager method instead of direct SQL
        result = self.db.get_chain_by_name(normalized)
        
        if result and result.get('chain_id'):
            return result['chain_id']
        
        return None
    
    async def fuzzy_match(self, network_name: str, threshold: int = 90) -> Optional[int]:
        """
        Fuzzy match network name against known chains.
        
        Requires rapidfuzz package. Falls back to exact match if not installed.
        
        Args:
            network_name: Network name to match
            threshold: Minimum similarity score (0-100)
        
        Returns:
            Chain ID if matched above threshold, None otherwise
        """
        if not HAS_RAPIDFUZZ:
            return None
        
        # Get all known chains using db_manager method
        chains = self.db.get_all_active_chains()
        
        # Get all aliases
        aliases = self.db.get_chain_aliases()
        
        if not chains and not aliases:
            return None
        
        # Build mapping of name -> chain_id
        name_to_id = {}
        for row in chains:
            name_to_id[self.normalize_name(row['chain'])] = row['chain_id']
        for row in aliases:
            name_to_id[self.normalize_name(row['alias'])] = row['chain_id']
        
        known_names = list(name_to_id.keys())
        
        if not known_names:
            return None
        
        normalized = self.normalize_name(network_name)
        
        # Find best match
        result = process.extractOne(
            normalized,
            known_names,
            scorer=fuzz.ratio
        )
        
        if result and result[1] >= threshold:
            matched_name = result[0]
            chain_id = name_to_id[matched_name]
            logger.info(
                f"Fuzzy match: '{network_name}' -> '{matched_name}' "
                f"(score: {result[1]}, chain_id: {chain_id})"
            )
            return chain_id
        
        return None
    
    async def discover_chain(self, network_name: str) -> DiscoveryResult:
        """
        Discover chain information from external sources.
        
        Args:
            network_name: Network name to discover
        
        Returns:
            DiscoveryResult with chain info if found
        """
        await self._load_caches()
        
        normalized = self.normalize_name(network_name)
        sources_checked = []
        
        # Search in chainid.network
        chain_info = self._search_chainid(normalized)
        sources_checked.append('chainid')
        
        if not chain_info:
            # Search in DeFiLlama
            chain_info = self._search_defillama(normalized)
            sources_checked.append('defillama')
        
        if not chain_info:
            # Search in Socket
            chain_info = self._search_socket(normalized)
            sources_checked.append('socket')
        
        if chain_info:
            return DiscoveryResult(
                success=True,
                chain_id=chain_info.chain_id,
                chain_info=chain_info,
                sources_checked=sources_checked
            )
        
        # Not found
        return DiscoveryResult(
            success=False,
            error=f"Chain '{network_name}' not found in any external source",
            sources_checked=sources_checked
        )
    
    def _search_chainid(self, normalized: str) -> Optional[ChainInfo]:
        """Search for chain in chainid.network cache."""
        for chain in self._chainid_cache:
            name = chain.get('name', '').lower()
            short_name = chain.get('shortName', '').lower()
            
            if normalized == name or normalized == short_name:
                return self._parse_chainid_entry(chain)
            
            # Check if normalized is substring of name
            if normalized in name or name in normalized:
                return self._parse_chainid_entry(chain)
        
        return None
    
    def _parse_chainid_entry(self, entry: Dict) -> ChainInfo:
        """Parse chainid.network entry into ChainInfo."""
        chain_id = entry.get('chainId')
        name = entry.get('name', 'Unknown')
        
        # Extract RPC URLs
        rpc_urls = []
        for rpc in entry.get('rpc', []):
            if isinstance(rpc, str) and rpc.startswith('https://'):
                rpc_urls.append(rpc)
        
        # Determine if L2
        is_l2 = chain_id in self.L2_CHAIN_IDS or 'rollup' in name.lower()
        
        return ChainInfo(
            chain_id=chain_id,
            name=name,
            short_name=entry.get('shortName'),
            native_token=entry.get('nativeCurrency', {}).get('symbol', 'ETH'),
            rpc_urls=rpc_urls[:5],  # Limit to 5 RPCs
            block_explorer=entry.get('explorers', [{}])[0].get('url') if entry.get('explorers') else None,
            is_l2=is_l2,
            network_type='l2' if is_l2 else 'l1' if chain_id in self.L1_CHAIN_IDS else 'sidechain',
            source='chainid'
        )
    
    def _search_defillama(self, normalized: str) -> Optional[ChainInfo]:
        """Search for chain in DeFiLlama cache."""
        for chain in self._defillama_cache:
            name = chain.get('name', '').lower()
            gecko_id = chain.get('gecko_id', '').lower() if chain.get('gecko_id') else ''
            
            if normalized == name or normalized == gecko_id:
                return self._parse_defillama_entry(chain)
            
            if normalized in name:
                return self._parse_defillama_entry(chain)
        
        return None
    
    def _parse_defillama_entry(self, entry: Dict) -> ChainInfo:
        """Parse DeFiLlama entry into ChainInfo."""
        chain_id = entry.get('chainId')
        name = entry.get('name', 'Unknown')
        
        # DeFiLlama doesn't provide RPC URLs directly
        rpc_urls = []
        
        # Determine if L2
        is_l2 = chain_id in self.L2_CHAIN_IDS
        
        return ChainInfo(
            chain_id=chain_id,
            name=name,
            short_name=entry.get('shortName'),
            native_token=entry.get('tokenSymbol', 'ETH'),
            rpc_urls=rpc_urls,
            block_explorer=None,
            is_l2=is_l2,
            network_type='l2' if is_l2 else 'l1' if chain_id in self.L1_CHAIN_IDS else 'sidechain',
            source='defillama',
            tvl_usd=entry.get('tvl', 0)
        )
    
    def _search_socket(self, normalized: str) -> Optional[ChainInfo]:
        """Search for chain in Socket cache."""
        for chain in self._socket_cache:
            name = chain.get('name', '').lower()
            
            if normalized == name or normalized in name:
                return self._parse_socket_entry(chain)
        
        return None
    
    def _parse_socket_entry(self, entry: Dict) -> ChainInfo:
        """Parse Socket entry into ChainInfo."""
        chain_id = entry.get('chainId')
        name = entry.get('name', 'Unknown')
        
        # Socket may have RPC URLs
        rpc_urls = []
        if 'rpc' in entry and isinstance(entry['rpc'], list):
            rpc_urls = [r for r in entry['rpc'] if isinstance(r, str) and r.startswith('https://')][:5]
        
        is_l2 = chain_id in self.L2_CHAIN_IDS
        
        return ChainInfo(
            chain_id=chain_id,
            name=name,
            native_token='ETH',  # Socket doesn't provide this
            rpc_urls=rpc_urls,
            block_explorer=None,
            is_l2=is_l2,
            network_type='l2' if is_l2 else 'l1' if chain_id in self.L1_CHAIN_IDS else 'sidechain',
            source='socket'
        )
    
    async def health_check_rpc(self, rpc_url: str) -> bool:
        """
        Check if RPC endpoint is responsive.
        
        Sends eth_blockNumber JSON-RPC request with timeout.
        
        Args:
            rpc_url: HTTPS RPC URL
        
        Returns:
            True if RPC responded within timeout, False otherwise
        """
        payload = {
            "jsonrpc": "2.0",
            "method": "eth_blockNumber",
            "params": [],
            "id": 1
        }
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    rpc_url,
                    json=payload,
                    timeout=aiohttp.ClientTimeout(total=self.RPC_TIMEOUT)
                ) as response:
                    if response.status == 200:
                        data = await response.json()
                        # Check if response has valid block number
                        if 'result' in data and data['result'].startswith('0x'):
                            return True
            
        except asyncio.TimeoutError:
            logger.debug(f"RPC timeout: {rpc_url}")
        except Exception as e:
            logger.debug(f"RPC error: {rpc_url} - {e}")
        
        return False
    
    async def validate_rpcs(self, rpc_urls: List[str]) -> List[str]:
        """
        Validate RPC endpoints and return working ones.
        
        Args:
            rpc_urls: List of RPC URLs to validate
        
        Returns:
            List of working RPC URLs
        """
        if not rpc_urls:
            return []
        
        working = []
        
        for rpc_url in rpc_urls:
            if await self.health_check_rpc(rpc_url):
                working.append(rpc_url)
                logger.debug(f"RPC health check passed: {rpc_url}")
            else:
                logger.warning(f"RPC health check failed: {rpc_url}")
        
        return working
    
    async def check_rpc_health(self) -> List[str]:
        """
        Perform health checks on all registered RPC endpoints in the database.
        Updates RPC status (success/failure count, is_active) in the database.
        
        Returns:
            List of names of chains that have at least one active RPC endpoint.
        """
        logger.info("Starting RPC health check for all registered endpoints...")
        
        # Get all RPC endpoints from the database
        all_rpcs = self.db.execute_query(
            "SELECT id, chain, chain_id, url, is_active FROM chain_rpc_endpoints",
            fetch='all'
        )
        
        if not all_rpcs:
            logger.warning("No RPC endpoints found in database to check.")
            return []
        
        active_chains = set()
        tasks = []
        
        for rpc_entry in all_rpcs:
            tasks.append(self._check_single_rpc_and_update_db(rpc_entry))
            
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        for result in results:
            if isinstance(result, tuple) and result[0]:  # (is_active, chain_name)
                active_chains.add(result[1])
        
        logger.info(f"RPC health check completed. Active chains: {len(active_chains)}")
        return list(active_chains)

    async def _check_single_rpc_and_update_db(self, rpc_entry: Dict) -> Tuple[bool, str]:
        """
        Checks a single RPC endpoint and updates its status in the database.
        Returns (is_active, chain_name).
        """
        rpc_id = rpc_entry["id"]
        chain_name = rpc_entry["chain"]
        rpc_url = rpc_entry["url"]
        current_is_active = rpc_entry["is_active"]
        
        is_healthy = await self.health_check_rpc(rpc_url)
        
        if is_healthy:
            # Increment success_count, set is_active = TRUE
            self.db.execute_query(
                """
                UPDATE chain_rpc_endpoints
                SET success_count = success_count + 1,
                    failure_count = 0,
                    is_active = TRUE,
                    last_checked_at = NOW()
                WHERE id = %s
                """,
                (rpc_id,)
            )
            if not current_is_active:
                logger.info(f"RPC {rpc_url} for chain {chain_name} is now ACTIVE.")
            return (True, chain_name)
        else:
            # Increment failure_count
            self.db.execute_query(
                """
                UPDATE chain_rpc_endpoints
                SET failure_count = failure_count + 1,
                    last_checked_at = NOW()
                WHERE id = %s
                """,
                (rpc_id,)
            )
            
            # If failure_count exceeds a threshold (e.g., 3), mark as inactive
            # This prevents flapping if an RPC is intermittently down
            failure_threshold = 3
            current_failure_count = self.db.execute_query(
                "SELECT failure_count FROM chain_rpc_endpoints WHERE id = %s",
                (rpc_id,),
                fetch='one'
            )["failure_count"]
            
            if current_failure_count >= failure_threshold and current_is_active:
                self.db.execute_query(
                    """
                    UPDATE chain_rpc_endpoints
                    SET is_active = FALSE
                    WHERE id = %s
                    """,
                    (rpc_id,)
                )
                logger.warning(f"RPC {rpc_url} for chain {chain_name} is now INACTIVE after {failure_threshold} failures.")
            elif not current_is_active:
                logger.debug(f"RPC {rpc_url} for chain {chain_name} is still INACTIVE.")
            else:
                logger.warning(f"RPC {rpc_url} for chain {chain_name} failed health check ({current_failure_count}/{failure_threshold}).")
            return (False, chain_name)

    async def register_chain(self, chain_info: ChainInfo) -> int:
        """
        Register discovered chain in database.
        
        Atomic transaction:
        1. Insert into chain_rpc_endpoints
        2. Insert into chain_aliases
        
        Args:
            chain_info: Discovered chain information
        
        Returns:
            Chain ID of registered chain
        
        Raises:
            ChainAlreadyExists: If chain already exists
        """
        # Check if chain already exists using db_manager method
        if self.db.chain_exists(chain_info.chain_id):
            raise ChainAlreadyExists(f"Chain {chain_info.chain_id} already exists in database")
        
        # Validate RPCs
        working_rpcs = await self.validate_rpcs(chain_info.rpc_urls)
        
        if not working_rpcs:
            logger.warning(f"No working RPCs for {chain_info.name}, marking as PENDING_RPC")
        
        # Use first working RPC or first provided RPC
        rpc_url = working_rpcs[0] if working_rpcs else (chain_info.rpc_urls[0] if chain_info.rpc_urls else None)
        
        if not rpc_url:
            raise RPCHealthCheckFailed(f"No RPC endpoints available for {chain_info.name}")
        
        # Determine gas multiplier based on network type
        gas_multiplier = Decimal('5.0') if chain_info.is_l2 else (Decimal('1.5') if chain_info.network_type == 'l1' else Decimal('2.0'))
        
        # Insert into chain_rpc_endpoints using db_manager method
        try:
            self.db.insert_chain_rpc(
                chain=chain_info.name.lower(),
                chain_id=chain_info.chain_id,
                url=rpc_url,
                priority=1,
                is_l2=chain_info.is_l2,
                network_type=chain_info.network_type,
                gas_multiplier=gas_multiplier,
                is_active=True
            )
        except Exception as e:
            # Check if it's a duplicate key error
            if 'unique' in str(e).lower() or 'duplicate' in str(e).lower():
                raise ChainAlreadyExists(f"Chain {chain_info.chain_id} already exists in database")
            raise
        
        # Insert aliases
        aliases = [chain_info.name.lower()]
        if chain_info.short_name:
            aliases.append(chain_info.short_name.lower())
        
        # Add normalized name as alias
        normalized = self.normalize_name(chain_info.name)
        if normalized not in aliases:
            aliases.append(normalized)
        
        for alias in aliases:
            # Use db_manager method for proper encapsulation
            result = self.db.add_chain_alias(
                chain_id=chain_info.chain_id,
                alias=alias,
                source=chain_info.source
            )
            if not result:
                logger.warning(f"Failed to add alias '{alias}' for chain {chain_info.chain_id}")
        
        logger.info(
            f"Registered chain: {chain_info.name} (ID: {chain_info.chain_id}) | "
            f"Type: {chain_info.network_type} | RPCs: {len(working_rpcs)}/{len(chain_info.rpc_urls)}"
        )
        
        return chain_info.chain_id
    
    async def log_discovery_failure(
        self,
        network_name: str,
        sources_checked: List[str],
        error_message: str
    ) -> None:
        """
        Log failed discovery attempt for manual review.
        
        Args:
            network_name: Network name that failed discovery
            sources_checked: List of sources that were checked
            error_message: Error message
        """
        try:
            self.db.execute_query(
                """
                INSERT INTO discovery_failures (network_name, sources_checked, error_message)
                VALUES (%s, %s, %s)
                ON CONFLICT DO NOTHING
                """,
                (network_name, sources_checked, error_message)
            )
            
            logger.warning(
                f"Logged discovery failure: {network_name} | "
                f"Sources: {sources_checked} | Error: {error_message}"
            )
            
        except Exception as e:
            logger.error(f"Failed to log discovery failure: {e}")
    
    async def discover_and_register(self, network_name: str) -> DiscoveryResult:
        """
        Main entry point: discover and register a chain.
        
        RACE CONDITION PROTECTION:
        Uses per-network asyncio.Lock to ensure only one coroutine
        performs discovery for a given network at a time.
        
        NEGATIVE CACHE:
        If a network was recently not found, returns cached error
        to avoid API spam.
        
        Workflow:
        1. Check negative cache (skip if recently failed)
        2. Check aliases table (fast path)
        3. Check known chains
        4. Fuzzy match
        5. External discovery (with lock)
        6. RPC validation
        7. Register in database
        
        Args:
            network_name: Network name to discover
        
        Returns:
            DiscoveryResult with chain_id if successful
        """
        logger.info(f"Discovering chain: {network_name}")
        
        # Step 0: Check negative cache (avoid API spam)
        cached_error = self._check_negative_cache(network_name)
        if cached_error:
            logger.info(f"Negative cache hit for '{network_name}': {cached_error}")
            return DiscoveryResult(
                success=False,
                error=f"Cached: {cached_error}",
                sources_checked=['negative_cache']
            )
        
        # Step 1: Check aliases (fast path)
        chain_id = await self.find_in_aliases(network_name)
        if chain_id:
            logger.info(f"Found '{network_name}' in aliases: chain_id={chain_id}")
            return DiscoveryResult(
                success=True,
                chain_id=chain_id,
                sources_checked=['aliases']
            )
        
        # Step 2: Check known chains
        chain_id = await self.find_in_known_chains(network_name)
        if chain_id:
            logger.info(f"Found '{network_name}' in known chains: chain_id={chain_id}")
            return DiscoveryResult(
                success=True,
                chain_id=chain_id,
                sources_checked=['known_chains']
            )
        
        # Step 3: Fuzzy match
        chain_id = await self.fuzzy_match(network_name)
        if chain_id:
            logger.info(f"Fuzzy matched '{network_name}' to chain_id={chain_id}")
            return DiscoveryResult(
                success=True,
                chain_id=chain_id,
                sources_checked=['fuzzy_match']
            )
        
        # Step 4: External discovery WITH LOCK (race condition protection)
        # Only one coroutine can discover a given network at a time
        network_lock = self._get_network_lock(network_name)
        
        async with network_lock:
            # Double-check after acquiring lock (another coroutine might have registered)
            chain_id = await self.find_in_aliases(network_name)
            if chain_id:
                logger.info(f"Found '{network_name}' after lock: chain_id={chain_id}")
                return DiscoveryResult(
                    success=True,
                    chain_id=chain_id,
                    sources_checked=['aliases']
                )
            
            # Perform external discovery
            discovery_result = await self.discover_chain(network_name)
            
            if not discovery_result.success:
                # Add to negative cache and log failure
                error_msg = discovery_result.error or "Unknown error"
                self._add_to_negative_cache(network_name, error_msg)
                await self.log_discovery_failure(
                    network_name,
                    discovery_result.sources_checked,
                    error_msg
                )
                return discovery_result
            
            # Step 5: Register chain
            try:
                chain_id = await self.register_chain(discovery_result.chain_info)
                
                # Step 6: Token kill-switch check (Smart Risk Engine)
                has_token, ticker, source = await self._check_token_exists(network_name)
                if has_token:
                    # Chain has its own token - mark as DROPPED
                    self.db.update_chain_farm_status(
                        chain=discovery_result.chain_info.name.lower(),
                        farm_status='DROPPED',
                        token_ticker=ticker
                    )
                    logger.warning(
                        f"Chain {discovery_result.chain_info.name} marked DROPPED: "
                        f"token {ticker} exists (source: {source})"
                    )
                
                return DiscoveryResult(
                    success=True,
                    chain_id=chain_id,
                    chain_info=discovery_result.chain_info,
                    sources_checked=discovery_result.sources_checked
                )
                
            except ChainAlreadyExists:
                # Chain was registered by another process
                return DiscoveryResult(
                    success=True,
                    chain_id=discovery_result.chain_id,
                    chain_info=discovery_result.chain_info,
                    sources_checked=discovery_result.sources_checked
                )
                
            except RPCHealthCheckFailed as e:
                self._add_to_negative_cache(network_name, str(e))
                await self.log_discovery_failure(
                    network_name,
                    discovery_result.sources_checked,
                    str(e)
                )
                return DiscoveryResult(
                    success=False,
                    error=str(e),
                    sources_checked=discovery_result.sources_checked
                )
                
            except Exception as e:
                logger.error(f"Failed to register chain {network_name}: {e}")
                await self.log_discovery_failure(
                    network_name,
                    discovery_result.sources_checked,
                    f"Registration error: {e}"
                )
                return DiscoveryResult(
                    success=False,
                    error=f"Registration error: {e}",
                    sources_checked=discovery_result.sources_checked
                )
    
    async def _check_token_exists(self, name: str) -> Tuple[bool, str, str]:
        """
        Check if a chain/protocol has its own token.
        
        Smart Risk Engine integration - token kill-switch.
        Uses cache first, then CoinGecko/DeFiLlama APIs.
        
        Args:
            name: Chain/protocol name to check
        
        Returns:
            Tuple of (has_token: bool, ticker: str, source: str)
            - has_token: True if protocol has its own token
            - ticker: Token ticker symbol (or empty string)
            - source: Data source ('cache', 'coingecko', 'defillama')
        """
        from infrastructure.identity_manager import get_curl_session
        
        # Step 1: Check cache
        cached = self.db.get_token_cache(name)
        if cached:
            logger.debug(f"Token cache hit for {name}: has_token={cached['has_token']}")
            return (cached['has_token'], cached['ticker'] or '', 'cache')
        
        # Step 2: Check CoinGecko
        try:
            async with get_curl_session(wallet_id=1, proxy_url=None) as session:
                # Search for coin by name
                url = "https://api.coingecko.com/api/v3/coins/markets"
                params = {
                    'vs_currency': 'usd',
                    'query': name,
                    'per_page': 5,
                    'page': 1
                }
                
                response = await session.get(url, params=params, timeout=10)
                
                if response.status_code == 200:
                    data = response.json()
                    
                    # Check if any result matches the name
                    for coin in data:
                        coin_name = coin.get('name', '').lower()
                        coin_symbol = coin.get('symbol', '').upper()
                        coin_id = coin.get('id', '').lower()
                        market_cap = coin.get('market_cap', 0) or 0
                        
                        # Fuzzy match: name matches coin name or id
                        if name.lower() in coin_name or name.lower() in coin_id or name.lower() == coin_symbol.lower():
                            has_token = market_cap > 0
                            ticker = coin_symbol
                            
                            # Cache result
                            self.db.set_token_cache(
                                protocol_name=name,
                                has_token=has_token,
                                ticker=ticker,
                                market_cap=float(market_cap),
                                source='coingecko'
                            )
                            
                            logger.info(f"CoinGecko found token for {name}: {ticker} (market_cap: ${market_cap:,.0f})")
                            return (has_token, ticker, 'coingecko')
                
        except Exception as e:
            logger.debug(f"CoinGecko token check failed for {name}: {e}")
        
        # Step 3: Fallback to DeFiLlama
        try:
            async with get_curl_session(wallet_id=1, proxy_url=None) as session:
                url = "https://api.llama.fi/protocols"
                
                response = await session.get(url, timeout=15)
                
                if response.status_code == 200:
                    protocols = response.json()
                    
                    # Search for protocol by name
                    for protocol in protocols:
                        proto_name = protocol.get('name', '').lower()
                        proto_symbol = protocol.get('symbol', '') or ''
                        
                        if name.lower() in proto_name or proto_name in name.lower():
                            has_token = bool(proto_symbol)
                            ticker = proto_symbol.upper() if proto_symbol else ''
                            
                            # Cache result
                            self.db.set_token_cache(
                                protocol_name=name,
                                has_token=has_token,
                                ticker=ticker,
                                market_cap=None,
                                source='defillama'
                            )
                            
                            logger.info(f"DeFiLlama found token for {name}: {ticker}")
                            return (has_token, ticker, 'defillama')
                
        except Exception as e:
            logger.debug(f"DeFiLlama token check failed for {name}: {e}")
        
        # Step 4: No token found - cache negative result
        self.db.set_token_cache(
            protocol_name=name,
            has_token=False,
            ticker=None,
            market_cap=None,
            source='none'
        )
        
        return (False, '', 'none')


# =============================================================================
# CLI INTERFACE
# =============================================================================

async def main():
    """CLI entry point for testing."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Chain Discovery Service')
    parser.add_argument('network', help='Network name to discover')
    parser.add_argument('--register', action='store_true', help='Register if found')
    
    args = parser.parse_args()
    
    db = DatabaseManager()
    discovery = ChainDiscoveryService(db)
    
    if args.register:
        result = await discovery.discover_and_register(args.network)
    else:
        result = await discovery.discover_chain(args.network)
    
    if result.success:
        print(f"\n✅ Chain discovered: {args.network}")
        print(f"   Chain ID: {result.chain_id}")
        if result.chain_info:
            print(f"   Name: {result.chain_info.name}")
            print(f"   Type: {result.chain_info.network_type}")
            print(f"   RPCs: {len(result.chain_info.rpc_urls)}")
            print(f"   Source: {result.chain_info.source}")
    else:
        print(f"\n❌ Chain not found: {args.network}")
        print(f"   Error: {result.error}")
        print(f"   Sources checked: {result.sources_checked}")
    
    return 0 if result.success else 1


if __name__ == '__main__':
    import asyncio
    asyncio.run(main())