"""
News Aggregator for Protocol Research Engine
============================================
Collects protocol mentions from:
1. Crypto News API (free tier)
2. DefiLlama API (TVL, no-token detection)
3. RSS feeds (The Block, CoinDesk, L2Beat)
4. Manual sources (Twitter via RSS, Discord announcements)

Anti-Sybil protection:
- Rate limiting (1 request per source per 5 seconds)
- Random delays (2-8 seconds) between sources
- User-agent rotation
- Retry with exponential backoff
"""

import asyncio
import json
import os
import random
import numpy as np
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass
from enum import Enum

import aiohttp
import feedparser
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type

from database.db_manager import get_db_manager


class NewsSource(Enum):
    """Supported news sources."""
    COINDESK_API = "coindesk_api"  # CoinDesk Data API (ex-CryptoCompare)
    DEFILLAMA = "defillama"
    RSS_THEBLOCK = "rss_theblock"
    RSS_COINDESK = "rss_coindesk"
    RSS_L2BEAT = "rss_l2beat"
    MANUAL_TWITTER = "manual_twitter"
    MANUAL_DISCORD = "manual_discord"
    # Legacy - removed CRYPTO_NEWS_API


@dataclass
class ProtocolCandidate:
    """Raw protocol candidate from news aggregation."""
    name: str
    source: NewsSource
    article_url: Optional[str] = None
    article_title: Optional[str] = None
    article_published_at: Optional[datetime] = None
    raw_text: Optional[str] = None
    chains: List[str] = None
    category: Optional[str] = None
    tvl_usd: Optional[float] = None
    has_token: Optional[bool] = None
    points_program_url: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for LLM analysis."""
        return {
            "name": self.name,
            "source": self.source.value,
            "article_url": self.article_url,
            "article_title": self.article_title,
            "article_published_at": self.article_published_at.isoformat() if self.article_published_at else None,
            "raw_text": self.raw_text,
            "chains": self.chains or [],
            "category": self.category,
            "tvl_usd": self.tvl_usd,
            "has_token": self.has_token,
            "points_program_url": self.points_program_url,
        }


class NewsAggregator:
    """
    Aggregates protocol mentions from multiple sources.
    """

    def __init__(self, db_manager=None):
        """
        Initialize news aggregator.
        
        Args:
            db_manager: DatabaseManager instance (optional)
        """
        self.db = db_manager or get_db_manager()
        self.session: Optional[aiohttp.ClientSession] = None
        self.user_agents = [
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        ]
        self.rate_limits = {
            NewsSource.COINDESK_API: 5,  # requests per minute (CoinDesk Data API)
            NewsSource.DEFILLAMA: 10,
            NewsSource.RSS_THEBLOCK: 2,
            NewsSource.RSS_COINDESK: 2,
            NewsSource.RSS_L2BEAT: 2,
        }
        self.last_request_time: Dict[NewsSource, float] = {}
        self._target_chains_cache: Optional[set] = None
    
    def _load_target_chains(self) -> set:
        """
        Load target chains from database (Smart Risk Engine integration).
        
        Returns chains with farm_status IN ('ACTIVE', 'TARGET') instead of hardcoded list.
        
        Returns:
            Set of chain names (e.g., {'base', 'arbitrum', 'optimism', ...})
        """
        if self._target_chains_cache is not None:
            return self._target_chains_cache
        
        try:
            rows = self.db.get_active_farming_chains()
            if rows:
                # Normalize chain names to match DeFiLlama format
                self._target_chains_cache = set()
                for row in rows:
                    chain = row['chain']
                    # Map database names to DeFiLlama names
                    chain_mapping = {
                        'arbitrum': 'Arbitrum',
                        'base': 'Base',
                        'optimism': 'Optimism',
                        'polygon': 'Polygon',
                        'bnb': 'BNB Chain',
                        'bsc': 'BNB Chain',
                        'avalanche': 'Avalanche',
                        'zksync': 'zkSync',
                        'starknet': 'Starknet',
                        'ink': 'Ink',
                        'megaeth': 'MegaETH',
                    }
                    normalized = chain_mapping.get(chain.lower(), chain.capitalize())
                    self._target_chains_cache.add(normalized)
                logger.debug(f"Loaded {len(self._target_chains_cache)} target chains from DB")
            else:
                # Fallback to empty set if DB query fails
                self._target_chains_cache = set()
                logger.warning("No target chains found in database")
        except Exception as e:
            logger.error(f"Failed to load target chains: {e}")
            self._target_chains_cache = set()
        
        return self._target_chains_cache

    async def __aenter__(self):
        """Async context manager entry."""
        self.session = aiohttp.ClientSession()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.session:
            await self.session.close()

    async def _rate_limit(self, source: NewsSource):
        """Respect rate limits with random jitter."""
        if source not in self.last_request_time:
            self.last_request_time[source] = 0
        
        elapsed = time.time() - self.last_request_time[source]
        min_delay = 60.0 / self.rate_limits.get(source, 5)
        if elapsed < min_delay:
            jitter = np.random.normal(mean=1.25, std=0.375)  # mean=(0.5+2.0)/2, std=range/4
            jitter = max(0.5, min(2.0, jitter))  # Clip to range
            wait_time = min_delay - elapsed + jitter
            logger.debug(f"Rate limiting {source.value} | Wait {wait_time:.1f}s")
            await asyncio.sleep(wait_time)
        
        self.last_request_time[source] = time.time()

    @retry(
        retry=retry_if_exception_type((aiohttp.ClientError, asyncio.TimeoutError)),
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        reraise=True
    )
    async def _fetch_json(self, url: str, headers: Optional[Dict] = None) -> Dict:
        """Fetch JSON from URL with retry logic."""
        if not self.session:
            self.session = aiohttp.ClientSession()
        
        headers = headers or {}
        headers.setdefault("User-Agent", random.choice(self.user_agents))
        
        async with self.session.get(url, headers=headers, timeout=30) as response:
            response.raise_for_status()
            return await response.json()

    @retry(
        retry=retry_if_exception_type((aiohttp.ClientError, asyncio.TimeoutError)),
        stop=stop_after_attempt(2),
        wait=wait_exponential(multiplier=1, min=1, max=5),
        reraise=True
    )
    async def _fetch_rss(self, url: str) -> feedparser.FeedParserDict:
        """Fetch RSS feed."""
        if not self.session:
            self.session = aiohttp.ClientSession()
        
        headers = {"User-Agent": random.choice(self.user_agents)}
        async with self.session.get(url, headers=headers, timeout=20) as response:
            response.raise_for_status()
            content = await response.text()
            return feedparser.parse(content)

    async def fetch_coindesk_api(self) -> List[ProtocolCandidate]:
        """
        Fetch recent crypto news from CoinDesk Data API (ex-CryptoCompare/CCData).
        API key must be set in environment variable COINDESK_API_KEY.
        
        Endpoint: https://data-api.coindesk.com/news/v1/article/list
        Auth: Authorization: Apikey {key} in headers
        """
        api_key = os.getenv("COINDESK_API_KEY")
        if not api_key:
            logger.warning("COINDESK_API_KEY not set, skipping CoinDesk API")
            return []
        
        await self._rate_limit(NewsSource.COINDESK_API)
        
        url = "https://data-api.coindesk.com/news/v1/article/list?lang=EN"
        headers = {
            "Authorization": f"Apikey {api_key}",
            "User-Agent": random.choice(self.user_agents)
        }
        
        try:
            if not self.session:
                self.session = aiohttp.ClientSession()
            
            async with self.session.get(url, headers=headers, timeout=20) as response:
                response.raise_for_status()
                data = await response.json()
            
            candidates = []
            
            # CoinDesk returns Data array with articles
            articles = data.get("Data") or data.get("data") or []
            
            for article in articles:
                # Extract fields with fallbacks (CoinDesk uses uppercase field names)
                title = article.get("TITLE") or article.get("title") or ""
                body = article.get("BODY") or article.get("body") or ""
                url = article.get("URL") or article.get("url") or ""
                # CoinDesk uses CREATED_ON (Unix timestamp)
                created_on = article.get("CREATED_ON") or article.get("created_on")
                
                if not title:
                    continue
                
                # Check for farming-relevant keywords
                text = f"{title} {body}"
                if any(keyword in text.lower() for keyword in ["launch", "mainnet", "airdrop", "points", "protocol", "defi"]):
                    # Parse date from Unix timestamp
                    published_at = None
                    if created_on:
                        try:
                            if isinstance(created_on, (int, float)):
                                published_at = datetime.fromtimestamp(int(created_on))
                            elif isinstance(created_on, str) and created_on.isdigit():
                                published_at = datetime.fromtimestamp(int(created_on))
                        except Exception as e:
                            logger.debug(f"Failed to parse date {created_on}: {e}")
                    
                    candidate = ProtocolCandidate(
                        name=title[:100],
                        source=NewsSource.COINDESK_API,
                        article_url=url,
                        article_title=title,
                        article_published_at=published_at,
                        raw_text=body[:500] if body else title[:500],
                    )
                    candidates.append(candidate)
            
            logger.info(f"CoinDesk API: {len(candidates)} candidates found")
            return candidates
            
        except Exception as e:
            logger.error(f"CoinDesk API error: {e}")
            return []
    
    # Legacy method - replaced by fetch_coindesk_api above
    async def fetch_crypto_news_api(self) -> List[ProtocolCandidate]:
        """DEPRECATED: Use fetch_coindesk_api instead."""
        return await self.fetch_coindesk_api()

    async def fetch_defillama(self) -> List[ProtocolCandidate]:
        """
        Fetch protocols from DefiLlama API (TVL > $1M, no token).
        Focus on L2 networks (Base, Arbitrum, Optimism, Polygon, BNB Chain).
        """
        await self._rate_limit(NewsSource.DEFILLAMA)
        
        url = "https://api.llama.fi/protocols"
        
        try:
            data = await self._fetch_json(url)
            candidates = []
            
            for protocol in data:
                # Filter: TVL > $1M, no token, L2 chains
                tvl = protocol.get("tvl", 0)
                chains = protocol.get("chains", [])
                has_token = protocol.get("symbol") is not None
                
                # Check if any target chain (loaded from DB)
                target_chains = self._load_target_chains()
                is_target = any(chain in target_chains for chain in chains)
                
                if tvl > 1_000_000 and not has_token and is_target:
                    candidate = ProtocolCandidate(
                        name=protocol.get("name", "Unknown"),
                        source=NewsSource.DEFILLAMA,
                        article_url=f"https://defillama.com/protocol/{protocol.get('slug')}",
                        article_title=f"{protocol.get('name')} - TVL ${tvl:,.0f}",
                        article_published_at=None,  # DefiLlama doesn't provide publish date
                        raw_text=f"Category: {protocol.get('category', 'Unknown')} | Chains: {', '.join(chains)}",
                        chains=chains,
                        category=protocol.get("category"),
                        tvl_usd=tvl,
                        has_token=False,
                        points_program_url=None,
                    )
                    candidates.append(candidate)
            
            logger.info(f"DefiLlama: {len(candidates)} candidates found (TVL > $1M, no token, L2)")
            return candidates
            
        except Exception as e:
            logger.error(f"DefiLlama API error: {e}")
            return []

    async def fetch_rss_theblock(self) -> List[ProtocolCandidate]:
        """Fetch RSS feed from The Block (crypto news)."""
        await self._rate_limit(NewsSource.RSS_THEBLOCK)
        
        url = "https://www.theblock.co/rss"
        
        try:
            feed = await self._fetch_rss(url)
            candidates = []
            
            for entry in feed.entries[:20]:  # Limit to 20 most recent
                title = entry.get("title", "")
                summary = entry.get("summary", "")
                text = f"{title} {summary}"
                
                # Look for protocol launches
                if any(keyword in text.lower() for keyword in ["launch", "debut", "mainnet", "airdrop"]):
                    candidate = ProtocolCandidate(
                        name=title[:100],
                        source=NewsSource.RSS_THEBLOCK,
                        article_url=entry.get("link"),
                        article_title=title,
                        article_published_at=datetime(*entry.get("published_parsed")[:6]) if entry.get("published_parsed") else None,
                        raw_text=text[:500],
                    )
                    candidates.append(candidate)
            
            logger.info(f"The Block RSS: {len(candidates)} candidates found")
            return candidates
            
        except Exception as e:
            logger.error(f"The Block RSS error: {e}")
            return []

    async def fetch_rss_coindesk(self) -> List[ProtocolCandidate]:
        """Fetch RSS feed from CoinDesk."""
        await self._rate_limit(NewsSource.RSS_COINDESK)
        
        url = "https://www.coindesk.com/arc/outboundfeeds/rss/"
        
        try:
            feed = await self._fetch_rss(url)
            candidates = []
            
            for entry in feed.entries[:20]:
                title = entry.get("title", "")
                summary = entry.get("summary", "")
                text = f"{title} {summary}"
                
                if any(keyword in text.lower() for keyword in ["protocol", "defi", "launch", "airdrop"]):
                    candidate = ProtocolCandidate(
                        name=title[:100],
                        source=NewsSource.RSS_COINDESK,
                        article_url=entry.get("link"),
                        article_title=title,
                        article_published_at=datetime(*entry.get("published_parsed")[:6]) if entry.get("published_parsed") else None,
                        raw_text=text[:500],
                    )
                    candidates.append(candidate)
            
            logger.info(f"CoinDesk RSS: {len(candidates)} candidates found")
            return candidates
            
        except Exception as e:
            logger.error(f"CoinDesk RSS error: {e}")
            return []

    async def fetch_rss_l2beat(self) -> List[ProtocolCandidate]:
        """Fetch RSS feed from L2Beat (L2 ecosystem updates)."""
        await self._rate_limit(NewsSource.RSS_L2BEAT)
        
        url = "https://l2beat.com/rss.xml"
        
        try:
            feed = await self._fetch_rss(url)
            candidates = []
            
            for entry in feed.entries[:15]:
                title = entry.get("title", "")
                summary = entry.get("summary", "")
                text = f"{title} {summary}"
                
                # L2Beat focuses on L2 ecosystem, most articles are relevant
                candidate = ProtocolCandidate(
                    name=title[:100],
                    source=NewsSource.RSS_L2BEAT,
                    article_url=entry.get("link"),
                    article_title=title,
                    article_published_at=datetime(*entry.get("published_parsed")[:6]) if entry.get("published_parsed") else None,
                    raw_text=text[:500],
                )
                candidates.append(candidate)
            
            logger.info(f"L2Beat RSS: {len(candidates)} candidates found")
            return candidates
            
        except Exception as e:
            logger.error(f"L2Beat RSS error: {e}")
            return []

    async def run_full_aggregation(self) -> List[ProtocolCandidate]:
        """
        Run aggregation from all sources in parallel.
        
        Returns:
            List of unique protocol candidates (deduplicated by name)
        """
        logger.info("Starting news aggregation from all sources")
        
        tasks = [
            self.fetch_coindesk_api(),  # New CoinDesk Data API (ex-CryptoCompare)
            self.fetch_defillama(),
            self.fetch_rss_theblock(),
            self.fetch_rss_coindesk(),
            self.fetch_rss_l2beat(),
        ]
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Flatten and deduplicate
        all_candidates = []
        seen_names = set()
        
        for result in results:
            if isinstance(result, Exception):
                logger.error(f"Source aggregation error: {result}")
                continue
            
            for candidate in result:
                if candidate.name not in seen_names:
                    seen_names.add(candidate.name)
                    all_candidates.append(candidate)
        
        logger.info(f"Total unique candidates: {len(all_candidates)}")
        return all_candidates

    def filter_recent_candidates(self, candidates: List[ProtocolCandidate], days: int = 30) -> List[ProtocolCandidate]:
        """
        Filter candidates to only those published in the last N days.
        
        Args:
            candidates: List of ProtocolCandidate objects
            days: Maximum age in days
        
        Returns:
            Filtered list
        """
        cutoff = datetime.now() - timedelta(days=days)
        filtered = []
        
        for candidate in candidates:
            if candidate.article_published_at is None:
                # DefiLlama candidates have no date, keep them
                filtered.append(candidate)
            elif candidate.article_published_at >= cutoff:
                filtered.append(candidate)
        
        logger.info(f"Filtered to {len(filtered)} recent candidates (last {days} days)")
        return filtered


# Import os at module level
import os


if __name__ == "__main__":
    """Test the news aggregator."""
    async def test():
        async with NewsAggregator() as aggregator:
            candidates = await aggregator.run_full_aggregation()
            print(f"Found {len(candidates)} candidates")
            for i, cand in enumerate(candidates[:5]):
                print(f"{i+1}. {cand.name} | Source: {cand.source.value}")
                if cand.article_url:
                    print(f"   URL: {cand.article_url}")
                print()
    
    asyncio.run(test())