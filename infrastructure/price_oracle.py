#!/usr/bin/env python3
"""
Price Oracle Service
====================
Fetches ETH/USD price from multiple sources with caching.

Sources (priority order):
1. CoinGecko API (free, no key required)
2. DeFiLlama API (free)
3. Database cache (fallback)
4. Hardcoded fallback ($3000)

Features:
- 5-minute cache in database
- Automatic fallback on API failure
- Used by all modules for ETH price

Author: Airdrop Farming System v4.0
Created: 2026-03-23
"""

import os
import sys
from pathlib import Path
from typing import Optional, Dict
from decimal import Decimal
from datetime import datetime, timezone, timedelta
import time

import aiohttp
from loguru import logger

sys.path.insert(0, str(Path(__file__).parent.parent))

from infrastructure.env_loader import load_env

# Load .env file (supports both production and local dev)
load_env()


class PriceOracle:
    """
    ETH/USD price oracle with caching and fallbacks.
    
    Usage:
        oracle = PriceOracle(db_manager)
        eth_price = await oracle.get_eth_price()  # Returns Decimal('3200.50')
    """
    
    CACHE_KEY = 'eth_price_usd'
    CACHE_TTL_MINUTES = 5
    FALLBACK_PRICE = Decimal('3000')
    
    # API endpoints
    COINGECKO_URL = "https://api.coingecko.com/api/v3/simple/price"
    DEFILLAMA_URL = "https://coins.llama.fi/prices"
    
    def __init__(self, db_manager=None):
        """
        Initialize Price Oracle.
        
        Args:
            db_manager: DatabaseManager instance for caching
        """
        self.db = db_manager
        self._memory_cache: Optional[Dict] = None
        
    async def get_eth_price(self, force_refresh: bool = False) -> Decimal:
        """
        Get current ETH/USD price.
        
        Args:
            force_refresh: Skip cache and fetch fresh price
            
        Returns:
            Decimal price in USD (e.g., Decimal('3200.50'))
        """
        # Check memory cache first
        if not force_refresh and self._memory_cache:
            if self._is_cache_valid(self._memory_cache):
                logger.debug(f"ETH price from memory cache: ${self._memory_cache['price']}")
                return self._memory_cache['price']
        
        # Check database cache
        if not force_refresh and self.db:
            db_price = self._get_from_db_cache()
            if db_price:
                self._memory_cache = {
                    'price': db_price,
                    'timestamp': datetime.now(timezone.utc)
                }
                logger.debug(f"ETH price from DB cache: ${db_price}")
                return db_price
        
        # Fetch from APIs
        price = await self._fetch_from_apis()
        
        if price:
            # Cache the result
            self._cache_price(price)
            return price
        
        # Fallback to cached or hardcoded
        if self._memory_cache:
            logger.warning("Using stale memory cache due to API failure")
            return self._memory_cache['price']
        
        logger.warning(f"All APIs failed, using fallback price: ${self.FALLBACK_PRICE}")
        return self.FALLBACK_PRICE
    
    async def _fetch_from_apis(self) -> Optional[Decimal]:
        """Try fetching price from multiple APIs."""
        
        # Try CoinGecko first
        try:
            price = await self._fetch_coingecko()
            if price:
                logger.info(f"ETH price from CoinGecko: ${price}")
                return price
        except Exception as e:
            logger.warning(f"CoinGecko API failed: {e}")
        
        # Try DeFiLlama as backup
        try:
            price = await self._fetch_defillama()
            if price:
                logger.info(f"ETH price from DeFiLlama: ${price}")
                return price
        except Exception as e:
            logger.warning(f"DeFiLlama API failed: {e}")
        
        return None
    
    async def _fetch_coingecko(self) -> Optional[Decimal]:
        """Fetch ETH price from CoinGecko."""
        params = {
            'ids': 'ethereum',
            'vs_currencies': 'usd'
        }
        
        async with aiohttp.ClientSession() as session:
            async with session.get(
                self.COINGECKO_URL,
                params=params,
                timeout=aiohttp.ClientTimeout(total=10)
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    if 'ethereum' in data and 'usd' in data['ethereum']:
                        return Decimal(str(data['ethereum']['usd']))
        
        return None
    
    async def _fetch_defillama(self) -> Optional[Decimal]:
        """Fetch ETH price from DeFiLlama."""
        # DeFiLlama uses chain addresses
        params = {
            'coins': 'coingecko:ethereum'
        }
        
        async with aiohttp.ClientSession() as session:
            async with session.get(
                self.DEFILLAMA_URL,
                params=params,
                timeout=aiohttp.ClientTimeout(total=10)
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    if 'coins' in data and 'coingecko:ethereum' in data['coins']:
                        return Decimal(str(data['coins']['coingecko:ethereum']['price']))
        
        return None
    
    def _is_cache_valid(self, cache_entry: Dict) -> bool:
        """Check if cache entry is still valid."""
        if not cache_entry:
            return False
        
        timestamp = cache_entry.get('timestamp')
        if not timestamp:
            return False
        
        age = datetime.now(timezone.utc) - timestamp
        return age < timedelta(minutes=self.CACHE_TTL_MINUTES)
    
    def _get_from_db_cache(self) -> Optional[Decimal]:
        """Get cached price from database."""
        if not self.db:
            return None
        
        try:
            result = self.db.execute_query(
                """
                SELECT value, updated_at 
                FROM system_config 
                WHERE key = %s
                """,
                (self.CACHE_KEY,),
                fetch='one'
            )
            
            if result:
                updated_at = result.get('updated_at')
                if updated_at:
                    age = datetime.now(timezone.utc) - updated_at
                    if age < timedelta(minutes=self.CACHE_TTL_MINUTES):
                        return Decimal(result['value'])
        
        except Exception as e:
            logger.warning(f"Failed to get price from DB cache: {e}")
        
        return None
    
    def _cache_price(self, price: Decimal):
        """Cache price in memory and database."""
        # Memory cache
        self._memory_cache = {
            'price': price,
            'timestamp': datetime.now(timezone.utc)
        }
        
        # Database cache
        if self.db:
            try:
                self.db.execute_query(
                    """
                    INSERT INTO system_config (key, value, value_type, category, description)
                    VALUES (%s, %s, 'float', 'price', 'ETH/USD price from oracle')
                    ON CONFLICT (key) 
                    DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()
                    """,
                    (self.CACHE_KEY, str(price))
                )
            except Exception as e:
                logger.warning(f"Failed to cache price in DB: {e}")


# Singleton instance for sync access (for modules that can't use async)
_oracle_instance: Optional[PriceOracle] = None


def get_price_oracle(db_manager=None) -> PriceOracle:
    """Get singleton PriceOracle instance."""
    global _oracle_instance
    if _oracle_instance is None:
        _oracle_instance = PriceOracle(db_manager)
    return _oracle_instance


async def get_eth_price_async(db_manager=None) -> Decimal:
    """
    Convenience function to get ETH price.
    
    Usage:
        from infrastructure.price_oracle import get_eth_price_async
        eth_price = await get_eth_price_async(db)
    """
    oracle = get_price_oracle(db_manager)
    return await oracle.get_eth_price()


def get_eth_price_sync(db_manager=None) -> Decimal:
    """
    Synchronous wrapper for modules that can't use async.
    Uses cached value or fallback.
    
    Usage:
        from infrastructure.price_oracle import get_eth_price_sync
        eth_price = get_eth_price_sync(db)
    """
    # Try memory cache first
    oracle = get_price_oracle(db_manager)
    if oracle._memory_cache and oracle._is_cache_valid(oracle._memory_cache):
        return oracle._memory_cache['price']
    
    # Try DB cache
    if db_manager:
        db_price = oracle._get_from_db_cache()
        if db_price:
            return db_price
    
    # Return fallback
    logger.debug(f"Using fallback ETH price: ${PriceOracle.FALLBACK_PRICE}")
    return PriceOracle.FALLBACK_PRICE
