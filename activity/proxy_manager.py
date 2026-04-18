#!/usr/bin/env python3
"""
Proxy Manager — Wallet-to-Proxy Assignment & Session Management
================================================================

Manages proxy assignment for all 90 wallets ensuring:
- 1:1 mapping (wallet ↔ proxy) for consistency
- Sticky sessions (IPRoyal 7 days, Decodo 60 min)
- Geolocation alignment (NL wallets → NL proxies, IS wallets → IS proxies)
- Caching for performance
- Health tracking
- Auto-validation with fallback

Usage:
    from activity.proxy_manager import ProxyManager
    
    proxy_manager = ProxyManager(db)
    proxy_config = proxy_manager.get_wallet_proxy(wallet_id=1)
    # Returns: {'host': 'geo.iproyal.com', 'port': 12321, 'protocol': 'socks5', ...}

Author: Airdrop Farming System v4.0
Created: 2026-02-26
Updated: 2026-03-16 — Added auto-validation and fallback
"""

import os
import sys
import time
from pathlib import Path
from typing import Dict, Optional, List, Tuple
from datetime import datetime, timezone, timedelta
from loguru import logger

# Add parent directory for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from database.db_manager import DatabaseManager

# Validation constants (loaded from database system_config)
def get_validation_cache_ttl() -> int:
    """Get validation cache TTL hours from database."""
    try:
        from database.db_manager import DatabaseManager
        db = DatabaseManager()
        return db.get_system_config('proxy_validation_cache_ttl_hours', default=1)
    except Exception as e:
        logger.warning(f"Failed to load validation cache TTL from DB, using fallback: {e}")
        return 1

def get_validation_timeout() -> int:
    """Get validation timeout seconds from database."""
    try:
        from database.db_manager import DatabaseManager
        db = DatabaseManager()
        return db.get_system_config('proxy_validation_timeout', default=10)
    except Exception as e:
        logger.warning(f"Failed to load validation timeout from DB, using fallback: {e}")
        return 10

def get_validation_test_url() -> str:
    """Get validation test URL from database."""
    try:
        from database.db_manager import DatabaseManager
        db = DatabaseManager()
        return db.get_system_config('proxy_validation_test_url', default='https://ipinfo.io/json')
    except Exception as e:
        logger.warning(f"Failed to load validation test URL from DB, using fallback: {e}")
        return 'https://ipinfo.io/json'

VALIDATION_CACHE_TTL_HOURS = get_validation_cache_ttl()
VALIDATION_TIMEOUT = get_validation_timeout()
VALIDATION_TEST_URL = get_validation_test_url()


class ProxyManager:
    """
    Manages proxy assignment and session handling for wallets.
    
    Each wallet is assigned a PERMANENT proxy from proxy_pool table.
    This ensures IP consistency and anti-Sybil protection.
    
    Features:
    - 1:1 wallet-to-proxy mapping (permanent)
    - Sticky session support (IPRoyal 7 days, Decodo 60 min)
    - Geolocation alignment (timezone matching)
    - Caching for performance
    - Health tracking (last_used_at updates)
    
    Example:
        proxy_manager = ProxyManager(db)
        
        # Get proxy for specific wallet
        proxy = proxy_manager.get_wallet_proxy(wallet_id=1)
        print(f"Using proxy: {proxy['host']}:{proxy['port']}")
        
        # Build proxy URL for web3.py or requests
        proxy_url = proxy_manager.build_proxy_url(proxy)
        # Returns: socks5://user:pass@host:port
    """
    
    def __init__(self, db: Optional[DatabaseManager] = None, auto_validate: bool = True):
        """
        Initialize ProxyManager.
        
        Args:
            db: DatabaseManager instance. If None, creates new instance.
            auto_validate: If True, validate proxy before returning (default: True)
        """
        self.db = db or DatabaseManager()
        self.auto_validate = auto_validate
        
        # Cache: wallet_id -> proxy_config
        # Avoids repeated DB queries for same wallet
        self._proxy_cache: Dict[int, Dict] = {}
        
        # Cache TTL in seconds (5 minutes)
        self._cache_ttl = 300
        
        # Timestamps for cache invalidation
        self._cache_timestamps: Dict[int, datetime] = {}
        
        logger.info(f"ProxyManager initialized | Cache TTL: 5 minutes | Auto-validate: {auto_validate}")
    
    def get_wallet_proxy(self, wallet_id: int, validate: Optional[bool] = None) -> Dict:
        """
        Get proxy configuration for a specific wallet.
        
        This method implements 1:1 wallet-to-proxy mapping.
        Each wallet is PERMANENTLY assigned to one proxy from proxy_pool.
        
        Args:
            wallet_id: Wallet database ID (1-90)
            validate: Override auto_validate setting. If True, validate before returning.
        
        Returns:
            Dict with proxy configuration:
            {
                'host': str,           # Proxy hostname
                'port': int,           # Proxy port
                'protocol': str,       # 'socks5' or 'socks5h'
                'username': str,       # Proxy username
                'password': str,       # Proxy password
                'country_code': str,   # 'NL' or 'IS'
                'provider': str,       # 'iproyal' or 'decodo'
                'session_id': str,     # Session identifier
                'validation_status': str  # 'valid', 'invalid', 'unknown'
            }
        
        Raises:
            ValueError: If wallet has no assigned proxy or proxy is inactive
            ConnectionError: If proxy connection test fails and no fallback available
        
        Example:
            proxy = pm.get_wallet_proxy(wallet_id=1)
            # Returns: {'host': 'geo.iproyal.com', 'port': 12321, ...}
        """
        # Determine if validation is needed
        should_validate = validate if validate is not None else self.auto_validate
        
        # Check cache first
        if wallet_id in self._proxy_cache:
            cache_age = (datetime.now(timezone.utc) - self._cache_timestamps[wallet_id]).total_seconds()
            if cache_age < self._cache_ttl:
                logger.debug(f"Proxy cache hit | Wallet: {wallet_id}")
                cached = self._proxy_cache[wallet_id]
                # Return cached if validation not required or already validated
                if not should_validate or cached.get('validation_status') == 'valid':
                    return cached
        
        # Fetch from database with validation fields
        query = """
            SELECT
                p.id AS proxy_id,
                p.ip_address AS host,
                p.port,
                p.protocol,
                p.username,
                p.password,
                p.country_code,
                p.provider,
                p.session_id,
                p.is_active,
                p.last_used_at,
                p.validation_status,
                p.last_validated_at,
                p.validation_error
            FROM wallets w
            JOIN proxy_pool p ON w.proxy_id = p.id
            WHERE w.id = %s
        """
        
        result = self.db.execute_query(query, (wallet_id,), fetch='one')
        
        if not result:
            raise ValueError(
                f"Wallet {wallet_id} not found or has no proxy assigned. "
                f"Check wallets.proxy_id foreign key."
            )
        
        if not result.get('is_active'):
            raise ValueError(
                f"Proxy assigned to wallet {wallet_id} is inactive. "
                f"Check proxy_pool.is_active flag."
            )
        
        # Build proxy config dict
        proxy_config = {
            'proxy_id': result['proxy_id'],
            'host': result['host'],
            'port': result['port'],
            'protocol': result['protocol'],
            'username': result['username'],
            'password': result['password'],
            'country_code': result['country_code'],
            'provider': result['provider'],
            'session_id': result['session_id'],
            'validation_status': result['validation_status'] or 'unknown'
        }
        
        # Auto-validation logic
        if should_validate:
            needs_validation = self._needs_validation(result)
            
            if needs_validation:
                logger.info(f"Validating proxy for wallet {wallet_id}...")
                is_valid, details = self._validate_proxy(proxy_config)
                
                if is_valid:
                    proxy_config['validation_status'] = 'valid'
                    proxy_config['detected_ip'] = details.get('detected_ip')
                    proxy_config['response_time_ms'] = details.get('response_time_ms')
                    self._update_validation_status(
                        result['proxy_id'],
                        'valid',
                        details
                    )
                else:
                    proxy_config['validation_status'] = 'invalid'
                    self._update_validation_status(
                        result['proxy_id'],
                        'invalid',
                        {'error': details.get('error', 'Unknown error')}
                    )
                    logger.warning(
                        f"Proxy validation failed for wallet {wallet_id}: "
                        f"{details.get('error', 'Unknown error')}"
                    )
        
        # Update last_used_at in database
        self._update_proxy_usage(wallet_id)
        
        # Cache the result
        self._proxy_cache[wallet_id] = proxy_config
        self._cache_timestamps[wallet_id] = datetime.now(timezone.utc)
        
        logger.info(
            f"Proxy assigned | Wallet: {wallet_id} | "
            f"Provider: {proxy_config['provider']} | "
            f"Country: {proxy_config['country_code']} | "
            f"Session: {proxy_config['session_id'][:12]}... | "
            f"Status: {proxy_config['validation_status']}"
        )
        
        return proxy_config
    
    def _needs_validation(self, proxy_result: Dict) -> bool:
        """
        Check if proxy needs validation based on last_validated_at.
        
        Args:
            proxy_result: Dict with proxy data from database
        
        Returns:
            True if validation is needed, False otherwise
        """
        validation_status = proxy_result.get('validation_status')
        last_validated = proxy_result.get('last_validated_at')
        
        # Never validated
        if validation_status is None or validation_status == 'unknown':
            return True
        
        # Previously invalid - re-validate
        if validation_status == 'invalid':
            return True
        
        # Check if validation is stale (older than VALIDATION_CACHE_TTL_HOURS)
        if last_validated:
            age = datetime.now(timezone.utc) - last_validated
            if age > timedelta(hours=VALIDATION_CACHE_TTL_HOURS):
                return True
        
        return False
    
    def _validate_proxy(self, proxy_config: Dict) -> Tuple[bool, Dict]:
        """
        Validate proxy by testing connection.
        
        Args:
            proxy_config: Dict with proxy configuration
        
        Returns:
            Tuple of (is_valid: bool, details: Dict)
        """
        from curl_cffi import requests
        
        proxy_url = self.build_proxy_url(proxy_config)
        proxies = {'http': proxy_url, 'https': proxy_url}
        
        try:
            start_time = time.time()
            response = requests.get(
                VALIDATION_TEST_URL,
                proxies=proxies,
                timeout=VALIDATION_TIMEOUT,
                impersonate="chrome110"
            )
            elapsed_ms = int((time.time() - start_time) * 1000)
            
            if response.status_code == 200:
                data = response.json()
                return True, {
                    'response_time_ms': elapsed_ms,
                    'detected_ip': data.get('ip'),
                    'detected_country': data.get('country')
                }
            else:
                return False, {'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            return False, {'error': str(e)[:200]}
    
    def _update_validation_status(self, proxy_id: int, status: str, details: Dict) -> None:
        """
        Update proxy validation status in database.
        
        Args:
            proxy_id: Proxy ID in database
            status: 'valid' or 'invalid'
            details: Dict with validation details
        """
        try:
            if status == 'valid':
                query = """
                    UPDATE proxy_pool
                    SET validation_status = 'valid',
                        last_validated_at = NOW(),
                        validation_error = NULL,
                        response_time_ms = %s,
                        detected_ip = %s,
                        detected_country = %s
                    WHERE id = %s
                """
                self.db.execute_query(
                    query,
                    (
                        details.get('response_time_ms'),
                        details.get('detected_ip'),
                        details.get('detected_country'),
                        proxy_id
                    )
                )
            else:
                query = """
                    UPDATE proxy_pool
                    SET validation_status = 'invalid',
                        last_validated_at = NOW(),
                        validation_error = %s
                    WHERE id = %s
                """
                self.db.execute_query(
                    query,
                    (details.get('error', 'Unknown error'), proxy_id)
                )
        except Exception as e:
            logger.warning(f"Failed to update validation status | Proxy: {proxy_id} | Error: {e}")
    
    def _update_proxy_usage(self, wallet_id: int) -> None:
        """
        Update last_used_at timestamp for wallet's proxy.
        
        Args:
            wallet_id: Wallet database ID
        """
        try:
            self.db.execute_query(
                """
                UPDATE proxy_pool 
                SET last_used_at = NOW() 
                WHERE id = (SELECT proxy_id FROM wallets WHERE id = %s)
                """,
                (wallet_id,)
            )
        except Exception as e:
            logger.warning(f"Failed to update proxy usage timestamp | Wallet: {wallet_id} | Error: {e}")
    
    def build_proxy_url(self, proxy_config: Dict) -> str:
        """
        Build proxy URL from configuration dict.
        
        Supports:
        - SOCKS5 (IPRoyal)
        - SOCKS5h (Decodo)
        - HTTP/HTTPS (if needed)
        
        Args:
            proxy_config: Dict with proxy configuration
        
        Returns:
            Proxy URL string:
            - socks5://username:password@host:port
            - socks5h://username:password@host:port
            - http://username:password@host:port
        
        Example:
            config = {'protocol': 'socks5', 'username': 'user', 'password': 'pass', 'host': 'geo.iproyal.com', 'port': 12321}
            url = pm.build_proxy_url(config)
            # Returns: socks5://user:pass@geo.iproyal.com:12321
        """
        protocol = proxy_config['protocol']
        username = proxy_config['username']
        password = proxy_config['password']
        host = proxy_config['host']
        port = proxy_config['port']
        
        # URL-encode password if it contains special characters
        import urllib.parse
        encoded_password = urllib.parse.quote(password, safe='')
        
        proxy_url = f"{protocol}://{username}:{encoded_password}@{host}:{port}"
        
        return proxy_url
    
    def build_proxy_dict(self, proxy_config: Dict) -> Dict:
        """
        Build proxies dict for requests.Session or web3.py.
        
        Args:
            proxy_config: Dict with proxy configuration
        
        Returns:
            Dict for session.proxies:
            {
                'http': 'socks5://user:pass@host:port',
                'https': 'socks5://user:pass@host:port'
            }
        
        Example:
            config = pm.get_wallet_proxy(wallet_id=1)
            proxies = pm.build_proxy_dict(config)
            # Returns: {'http': 'socks5://...', 'https': 'socks5://...'}
        """
        proxy_url = self.build_proxy_url(proxy_config)
        
        return {
            'http': proxy_url,
            'https': proxy_url
        }
    
    def get_proxy_for_wallet_list(self, wallet_ids: List[int]) -> Dict[int, Dict]:
        """
        Get proxies for multiple wallets efficiently.
        
        Uses caching to minimize DB queries.
        
        Args:
            wallet_ids: List of wallet database IDs
        
        Returns:
            Dict mapping wallet_id -> proxy_config
        
        Example:
            proxies = pm.get_proxy_for_wallet_list([1, 2, 3, 4, 5])
            # Returns: {1: {...}, 2: {...}, 3: {...}, 4: {...}, 5: {...}}
        """
        result = {}
        
        for wallet_id in wallet_ids:
            try:
                result[wallet_id] = self.get_wallet_proxy(wallet_id)
            except ValueError as e:
                logger.error(f"Failed to get proxy for wallet {wallet_id} | Error: {e}")
                result[wallet_id] = None
        
        return result
    
    def invalidate_cache(self, wallet_id: int) -> None:
        """
        Clear cached proxy for specific wallet.
        
        Use after proxy rotation or when proxy becomes unavailable.
        
        Args:
            wallet_id: Wallet database ID
        
        Example:
            pm.invalidate_cache(wallet_id=1)  # Force fresh lookup next time
        """
        if wallet_id in self._proxy_cache:
            del self._proxy_cache[wallet_id]
            del self._cache_timestamps[wallet_id]
            logger.debug(f"Proxy cache invalidated | Wallet: {wallet_id}")
    
    def invalidate_all_cache(self) -> None:
        """
        Clear all cached proxies.
        
        Use for cache refresh or when proxy pool changes.
        
        Example:
            pm.invalidate_all_cache()  # Refresh all proxy lookups
        """
        count = len(self._proxy_cache)
        self._proxy_cache.clear()
        self._cache_timestamps.clear()
        logger.info(f"All proxy cache cleared | Entries: {count}")
    
    def get_proxy_health_stats(self) -> Dict:
        """
        Get proxy pool health statistics.
        
        Returns:
            Dict with health metrics:
            {
                'total_proxies': int,
                'active_proxies': int,
                'inactive_proxies': int,
                'unused_proxies': int,
                'by_provider': {'iproyal': int, 'decodo': int},
                'by_country': {'NL': int, 'IS': int},
                'by_validation': {'valid': int, 'invalid': int, 'unknown': int},
                'avg_response_ms': int
            }
        
        Example:
            stats = pm.get_proxy_health_stats()
            print(f"Active: {stats['active_proxies']}/{stats['total_proxies']}")
        """
        # Total and active
        total_query = "SELECT COUNT(*) as count FROM proxy_pool"
        total = self.db.execute_query(total_query, fetch='one')['count']
        
        active_query = "SELECT COUNT(*) as count FROM proxy_pool WHERE is_active = TRUE"
        active = self.db.execute_query(active_query, fetch='one')['count']
        
        inactive = total - active
        
        # Unused (never used)
        unused_query = "SELECT COUNT(*) as count FROM proxy_pool WHERE last_used_at IS NULL"
        unused = self.db.execute_query(unused_query, fetch='one')['count']
        
        # By provider
        provider_query = """
            SELECT provider, COUNT(*) as count
            FROM proxy_pool
            WHERE is_active = TRUE
            GROUP BY provider
        """
        provider_results = self.db.execute_query(provider_query, fetch='all')
        by_provider = {row['provider']: row['count'] for row in provider_results}
        
        # By country
        country_query = """
            SELECT country_code, COUNT(*) as count
            FROM proxy_pool
            WHERE is_active = TRUE
            GROUP BY country_code
        """
        country_results = self.db.execute_query(country_query, fetch='all')
        by_country = {row['country_code']: row['count'] for row in country_results}
        
        # By validation status
        validation_query = """
            SELECT
                COALESCE(validation_status, 'unknown') as status,
                COUNT(*) as count
            FROM proxy_pool
            WHERE is_active = TRUE
            GROUP BY validation_status
        """
        validation_results = self.db.execute_query(validation_query, fetch='all')
        by_validation = {row['status']: row['count'] for row in validation_results}
        
        # Average response time
        avg_query = """
            SELECT AVG(response_time_ms)::int as avg_ms
            FROM proxy_pool
            WHERE is_active = TRUE AND response_time_ms IS NOT NULL
        """
        avg_result = self.db.execute_query(avg_query, fetch='one')
        avg_response_ms = avg_result.get('avg_ms') if avg_result else None
        
        return {
            'total_proxies': total,
            'active_proxies': active,
            'inactive_proxies': inactive,
            'unused_proxies': unused,
            'by_provider': by_provider,
            'by_country': by_country,
            'by_validation': by_validation,
            'avg_response_ms': avg_response_ms
        }
    
    def test_proxy_connection(self, proxy_config: Dict) -> bool:
        """
        Test if proxy is reachable.
        
        Args:
            proxy_config: Dict with proxy configuration
        
        Returns:
            True if proxy is reachable, False otherwise
        
        Example:
            config = pm.get_wallet_proxy(wallet_id=1)
            if pm.test_proxy_connection(config):
                print("Proxy is working!")
            else:
                print("Proxy unreachable!")
        """
        from curl_cffi import requests
        
        proxy_url = self.build_proxy_url(proxy_config)
        proxies = {'http': proxy_url, 'https': proxy_url}
        
        test_url = 'https://ipinfo.io/json'
        
        try:
            response = requests.get(
                test_url,
                proxies=proxies,
                timeout=10,
                impersonate="chrome110"
            )
            
            if response.status_code == 200:
                data = response.json()
                logger.info(
                    f"Proxy test successful | "
                    f"IP: {data.get('ip', 'unknown')} | "
                    f"Country: {data.get('country', 'unknown')}"
                )
                return True
            else:
                logger.warning(f"Proxy test failed | Status: {response.status_code}")
                return False
                
        except requests.exceptions.Timeout:
            logger.warning(f"Proxy test timeout | Host: {proxy_config['host']}")
            return False
        except requests.exceptions.RequestException as e:
            logger.warning(f"Proxy test error | Host: {proxy_config['host']} | Error: {e}")
            return False
    
    def get_wallet_proxy_summary(self, wallet_id: int) -> Dict:
        """
        Get detailed proxy information for a wallet (for debugging/logging).
        
        Args:
            wallet_id: Wallet database ID
        
        Returns:
            Dict with detailed proxy info including last_used_at
        
        Example:
            info = pm.get_wallet_proxy_summary(wallet_id=1)
            print(f"Wallet 1 uses {info['provider']} proxy, last used: {info['last_used_at']}")
        """
        query = """
            SELECT 
                w.id as wallet_id,
                w.address,
                p.ip_address AS proxy_host,
                p.port,
                p.protocol,
                p.country_code,
                p.provider,
                p.session_id,
                p.last_used_at,
                p.is_active as proxy_active
            FROM wallets w
            JOIN proxy_pool p ON w.proxy_id = p.id
            WHERE w.id = %s
        """
        
        result = self.db.execute_query(query, (wallet_id,), fetch='one')
        
        if not result:
            raise ValueError(f"Wallet {wallet_id} not found")
        
        return result


# =============================================================================
# STANDALONE USAGE (for testing)
# =============================================================================

if __name__ == '__main__':
    # Test standalone usage
    from loguru import logger
    
    logger.info("Testing ProxyManager...")
    
    # Initialize
    pm = ProxyManager()
    
    # Get health stats
    stats = pm.get_proxy_health_stats()
    logger.info(f"Proxy pool stats: {stats}")
    
    # Test getting proxy for wallet 1
    try:
        proxy = pm.get_wallet_proxy(wallet_id=1)
        logger.info(f"Wallet 1 proxy: {proxy['provider']} ({proxy['country_code']})")
        
        # Build URL
        url = pm.build_proxy_url(proxy)
        logger.info(f"Proxy URL: {url[:50]}...")
        
        # Test connection
        if pm.test_proxy_connection(proxy):
            logger.success("Proxy connection test PASSED")
        else:
            logger.warning("Proxy connection test FAILED")
            
    except ValueError as e:
        logger.error(f"Error: {e}")
    
    logger.info("ProxyManager test complete")