"""
Module 16: News Analyzer — Relevance Filtering for Airdrop Farming

Analyzes aggregated news articles for airdrop/points program relevance using
keyword matching and scoring algorithms. Filters out irrelevant articles
before expensive LLM analysis in Module 15 (Protocol Research Engine).

Usage:
    python -m research.news_analyzer --test-keywords
    python -m research.news_analyzer --analyze-file articles.json --show-stats

Integration:
    Called by research/scheduler.py between NewsAggregator and ProtocolAnalyzer.
"""

import re
import json
import logging
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Set, Any
from datetime import datetime

from loguru import logger

# Configure module-level logger
logger = logger.bind(module="news_analyzer")


@dataclass
class RelevanceScore:
    """
    Relevance analysis result for a single article.
    """
    score: int                          # 0-100 relevance score
    matched_keywords: List[str]         # Keywords that triggered match
    matched_groups: List[str]           # Keyword groups matched
    category: str                       # "high" (≥80), "medium" (60-79), "low" (<60)
    confidence: float                   # 0.0-1.0 confidence level
    blacklisted: bool = False           # True if spam/irrelevant
    
    @property
    def is_relevant(self) -> bool:
        """Article passes relevance threshold (≥60 and not blacklisted)."""
        return self.score >= 60 and not self.blacklisted
    
    @property
    def category_emoji(self) -> str:
        """Emoji for Telegram alerts."""
        if self.score >= 80:
            return "🔥"  # High relevance
        elif self.score >= 60:
            return "⚡"  # Medium relevance
        else:
            return "📰"  # Low relevance
    
    def to_dict(self) -> Dict[str, Any]:
        """Serialize to dictionary for JSON storage."""
        return {
            "score": self.score,
            "matched_keywords": self.matched_keywords,
            "matched_groups": self.matched_groups,
            "category": self.category,
            "confidence": self.confidence,
            "blacklisted": self.blacklisted,
            "is_relevant": self.is_relevant
        }


@dataclass
class FilteredArticle:
    """
    News article with relevance metadata.
    """
    title: str
    url: str
    source: str
    published_at: datetime
    content: str
    relevance: RelevanceScore
    
    def to_dict(self) -> Dict[str, Any]:
        """Serialize to dictionary."""
        return {
            "title": self.title,
            "url": self.url,
            "source": self.source,
            "published_at": self.published_at.isoformat() if self.published_at else None,
            "content": self.content,
            "relevance": self.relevance.to_dict()
        }


class NewsAnalyzer:
    """
    Analyzes news articles for airdrop/points program relevance.
    
    Filters aggregated news using keyword matching and scoring algorithms
    before sending to expensive LLM analysis. Reduces LLM API costs by 70-80%.
    
    Keyword groups (from ТЗ v4.0):
        - airdrop
        - token launch
        - layer 2 / L2
        - points / points program
    """
    
    # Keyword groups with weights (from architecture document)
    KEYWORD_GROUPS = {
        "airdrop_direct": {
            "keywords": [
                "airdrop",
                "airdropping",
                "token distribution",
                "retroactive reward",
                "free tokens",
                "claim",
                "eligibility",
                "whitelist",
                "qualify",
                "snapshot",
                "retroactive",
                "allocation",
            ],
            "weight": 40,  # High weight (direct indicator)
            "case_insensitive": True
        },
        
        "points_programs": {
            "keywords": [
                "points program",
                "loyalty points",
                "rewards program",
                "earn points",
                "point system",
                "xp system",
                "leaderboard",
                "engagement rewards",
                "quests",
                "tasks",
                "season",
                "campaign",
            ],
            "weight": 35,  # High weight (strong proxy for airdrop)
            "case_insensitive": True
        },
        
        "l2_ecosystem": {
            "keywords": [
                "layer 2",
                "l2",
                "rollup",
                "optimistic rollup",
                "zk-rollup",
                "base chain",
                "arbitrum",
                "optimism",
                "polygon",
                "ink chain",
                "megaeth",
                "unichain",
                "robinhood chain",
                "zkSync",
                "scroll",
                "taiko",
                "linea",
                "mantle",
                "mode",
                "blast",
                "apechain",
            ],
            "weight": 20,  # Medium weight (context-dependent)
            "case_insensitive": True
        },
        
        "token_launch": {
            "keywords": [
                "token launch",
                "token sale",
                "mainnet launch",
                "genesis",
                "initial distribution",
                "tge",  # Token Generation Event
                "tokenomics",
                "no token yet",
                "token coming soon",
                "pre-market",
                "ido",
                "ieo",
            ],
            "weight": 30,  # High weight (airdrop likely follows launch)
            "case_insensitive": True
        }
    }
    
    # Blacklist patterns (spam, irrelevant topics)
    BLACKLIST_PATTERNS = [
        # Regulatory/Legal (not relevant for farming)
        r"\b(sec filing|lawsuit|regulation|banned|illegal|arrested|charged)\b",
        
        # Price analysis (not actionable)
        r"\b(price prediction|technical analysis|bullish|bearish|market analysis|trading volume)\b",
        
        # Exchange listings (not airdrops)
        r"\b(listed on binance|kraken listing|coinbase listing|exchange listing)\b",
        
        # Scams (obvious red flags)
        r"\b(guaranteed profit|double your coins|get rich quick|free money|scam|rugpull)\b",
        
        # Completed airdrops (in past tense)
        r"\b(airdrop ended|claim period closed|snapshot taken|distribution completed|finished)\b",
        
        # Generic crypto news (no specific protocol)
        r"\b(bitcoin|ethereum|btc|eth) (hits|reaches|drops|surges|falls|crashes)\b",
        
        # FUD / negative sentiment
        r"\b(hacked|exploited|vulnerability|security breach|stolen funds)\b",
        
        # Politics / Macro
        r"\b(regulation|government|congress|bill|law|policy)\b",
        
        # Meme coins / jokes
        r"\b(dogecoin|shiba inu|pepe|memecoin|shitcoin)\b",
    ]
    
    def __init__(self, relevance_threshold: int = 60):
        """
        Initialize NewsAnalyzer.
        
        Args:
            relevance_threshold: Minimum score (0-100) for article to be
                                 considered relevant. Default: 60.
        """
        self.relevance_threshold = relevance_threshold
        
        # Pre-compile regex patterns for performance
        self.blacklist_patterns = [
            re.compile(pattern, re.IGNORECASE) for pattern in self.BLACKLIST_PATTERNS
        ]
        
        # Pre-process keywords for case-insensitive matching
        self._keyword_cache = {}
        for group_name, group_config in self.KEYWORD_GROUPS.items():
            keywords = group_config["keywords"]
            if group_config["case_insensitive"]:
                keywords = [kw.lower() for kw in keywords]
            self._keyword_cache[group_name] = keywords
        
        logger.info(f"NewsAnalyzer initialized with threshold={relevance_threshold}")
    
    def _extract_keywords(self, text: str) -> Set[str]:
        """
        Extract keywords from text.
        
        Args:
            text: Text to analyze
            
        Returns:
            Set of lowercase keywords found in text
        """
        text_lower = text.lower()
        found_keywords = set()
        
        for group_name, group_config in self.KEYWORD_GROUPS.items():
            keywords = self._keyword_cache[group_name]
            for keyword in keywords:
                if keyword in text_lower:
                    found_keywords.add(keyword)
        
        return found_keywords
    
    def _is_blacklisted(self, article: Dict[str, Any]) -> bool:
        """
        Check if article matches spam/irrelevant patterns.
        
        Args:
            article: Article dictionary
            
        Returns:
            True if blacklisted (should be filtered out)
        """
        # Combine title and content for blacklist checking
        text = f"{article.get('title', '')} {article.get('content', '')}".lower()
        
        for pattern in self.blacklist_patterns:
            if pattern.search(text):
                logger.debug(f"Blacklisted article: {article.get('title', 'No title')[:50]}... (matched: {pattern.pattern})")
                return True
        
        return False
    
    def _calculate_relevance_score(self, article: Dict[str, Any]) -> RelevanceScore:
        """
        Calculate 0-100 relevance score based on keyword matches.
        
        Algorithm:
        1. Scan title and content for keywords
        2. Add weight for each matched keyword group
        3. Apply multipliers:
           - Title match: 1.5x
           - Multiple keywords from same group: 1.2x cap
        4. Cap at 100
        
        Args:
            article: Article dictionary
            
        Returns:
            RelevanceScore object with score and metadata
        """
        score = 0
        matched_keywords = []
        matched_groups = []
        
        title = article.get('title', '').lower()
        content = article.get('content', '').lower()
        
        # Helper function to find matches in text
        def find_matches_in_text(text: str, group_name: str) -> List[str]:
            """Find which keywords from a group match in text."""
            keywords = self._keyword_cache[group_name]
            return [kw for kw in keywords if kw in text]
        
        # Check title first (gets 1.5x weight)
        title_matches_by_group = {}
        for group_name, group_config in self.KEYWORD_GROUPS.items():
            matches = find_matches_in_text(title, group_name)
            if matches:
                title_matches_by_group[group_name] = matches
        
        # Calculate score for title matches
        for group_name, matches in title_matches_by_group.items():
            weight = self.KEYWORD_GROUPS[group_name]["weight"]
            # Title gets 1.5x weight
            group_score = weight * 1.5
            # Multiple keywords from same group: diminishing returns (max 1.2x)
            if len(matches) > 1:
                group_score = min(group_score * 1.2, weight * 1.8)
            
            score += group_score
            matched_keywords.extend(matches)
            matched_groups.append(group_name)
        
        # Check content (skip groups already matched in title)
        content_matches_by_group = {}
        for group_name, group_config in self.KEYWORD_GROUPS.items():
            if group_name in matched_groups:
                continue  # Already counted in title
            
            matches = find_matches_in_text(content, group_name)
            if matches:
                content_matches_by_group[group_name] = matches
        
        # Calculate score for content matches
        for group_name, matches in content_matches_by_group.items():
            weight = self.KEYWORD_GROUPS[group_name]["weight"]
            group_score = weight
            # Multiple keywords from same group: diminishing returns
            if len(matches) > 1:
                group_score = min(group_score * 1.2, weight * 1.2)
            
            score += group_score
            matched_keywords.extend(matches)
            matched_groups.append(group_name)
        
        # Cap at 100
        score = min(int(score), 100)
        
        # Determine category
        if score >= 80:
            category = "high"
        elif score >= self.relevance_threshold:
            category = "medium"
        else:
            category = "low"
        
        # Confidence based on score and number of keyword groups matched
        confidence = min(score / 100 + (len(matched_groups) * 0.1), 1.0)
        
        # Check if blacklisted
        blacklisted = self._is_blacklisted(article)
        
        return RelevanceScore(
            score=score,
            matched_keywords=matched_keywords,
            matched_groups=matched_groups,
            category=category,
            confidence=confidence,
            blacklisted=blacklisted
        )
    
    def analyze_article(self, article: Dict[str, Any]) -> RelevanceScore:
        """
        Analyze single article for airdrop relevance.
        
        Args:
            article: Dict with 'title', 'content', 'url', 'source', 'published_at'
            
        Returns:
            RelevanceScore object
            
        Raises:
            ValueError: If article missing required fields
        """
        # Validate required fields (support both article_title/title and article_url/url)
        required_fields = ['title', 'url', 'source']
        
        # Map alternative field names
        field_mapping = {
            'title': ['title', 'article_title', 'name'],
            'url': ['url', 'article_url', 'source_article_url'],
            'source': ['source', 'source_name']
        }
        
        # Check for required fields with fallbacks
        missing_fields = []
        for required, alternatives in field_mapping.items():
            found = False
            for alt in alternatives:
                if alt in article and article[alt]:
                    found = True
                    # Normalize to standard field name if different
                    if alt != required and required not in article:
                        article[required] = article[alt]
                    break
            if not found:
                missing_fields.append(required)
        
        if missing_fields:
            raise ValueError(f"Article missing required fields: {', '.join(missing_fields)}")
        
        logger.debug(f"Analyzing article: {article['title'][:80]}...")
        relevance = self._calculate_relevance_score(article)
        
        if relevance.blacklisted:
            logger.debug(f"Article blacklisted: {article['title'][:50]}...")
        elif relevance.is_relevant:
            logger.debug(f"Article relevant (score={relevance.score}): {article['title'][:50]}...")
        else:
            logger.debug(f"Article not relevant (score={relevance.score}): {article['title'][:50]}...")
        
        return relevance
    
    def batch_analyze(self, articles: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Filter batch of articles, return only relevant ones.
        
        Args:
            articles: List of raw news articles from NewsAggregator
            
        Returns:
            Filtered list (score >= threshold, not blacklisted),
            sorted by score DESC. Each article has 'relevance' key added.
        """
        if not articles:
            return []
        
        logger.info(f"Analyzing batch of {len(articles)} articles...")
        
        processed_articles = []
        relevant_count = 0
        blacklisted_count = 0
        
        for article in articles:
            relevance = self.analyze_article(article)
            
            # Add relevance metadata to article
            article_copy = article.copy()
            article_copy['relevance'] = relevance
            
            if relevance.blacklisted:
                blacklisted_count += 1
            elif relevance.is_relevant:
                relevant_count += 1
                processed_articles.append(article_copy)
        
        # Sort by relevance score descending
        processed_articles.sort(key=lambda a: a['relevance'].score, reverse=True)
        
        # Log statistics
        total_articles = len(articles)
        filtered_out = total_articles - relevant_count
        
        logger.info(f"Analysis complete:")
        logger.info(f"  Total articles: {total_articles}")
        logger.info(f"  Blacklisted: {blacklisted_count} ({blacklisted_count/total_articles*100:.1f}%)")
        logger.info(f"  Relevant (≥{self.relevance_threshold}): {relevant_count} ({relevant_count/total_articles*100:.1f}%)")
        logger.info(f"  Filtered out: {filtered_out} ({filtered_out/total_articles*100:.1f}%)")
        
        if total_articles > 0:
            # Calculate LLM cost savings
            llm_cost_per_article = 0.008  # $0.008 per LLM analysis
            potential_cost = total_articles * llm_cost_per_article
            actual_cost = relevant_count * llm_cost_per_article
            savings = potential_cost - actual_cost
            savings_percent = (savings / potential_cost * 100) if potential_cost > 0 else 0
            
            logger.info(f"  LLM cost savings: ${savings:.3f} ({savings_percent:.1f}%)")
        
        return processed_articles
    
    def filter_relevant(self, articles: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Alias for batch_analyze() for backward compatibility.
        
        Args:
            articles: List of raw news articles
            
        Returns:
            Filtered list (score >= threshold, not blacklisted)
        """
        return self.batch_analyze(articles)


# Sample test data for CLI testing
SAMPLE_ARTICLES = [
    {
        'title': "New L2 protocol announces airdrop for early users",
        'content': "The protocol will distribute 10% of tokens to users who interacted before February 2026. Eligibility requires at least one transaction.",
        'url': "https://example.com/1",
        'source': "CryptoNews",
        'published_at': datetime.now()
    },
    {
        'title': "Bitcoin reaches new all-time high",
        'content': "Technical analysis shows Bitcoin could reach $100,000 by end of year.",
        'url': "https://example.com/2",
        'source': "PriceNews",
        'published_at': datetime.now()
    },
    {
        'title': "Protocol launches points program for liquidity providers",
        'content': "Users can earn points by providing liquidity to the new DEX on Base chain. Points may be convertible to tokens in the future.",
        'url': "https://example.com/3",
        'source': "L2News",
        'published_at': datetime.now()
    },
    {
        'title': "SEC sues exchange for unregistered securities",
        'content': "The Securities and Exchange Commission has filed a lawsuit against a major crypto exchange.",
        'url': "https://example.com/4",
        'source': "RegulationNews",
        'published_at': datetime.now()
    }
]


def main():
    """CLI interface for testing."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Analyze crypto news for airdrop relevance")
    
    parser.add_argument('--test-keywords', action='store_true',
                       help="Test keyword matching on sample articles")
    
    parser.add_argument('--analyze-file', type=str,
                       help="Analyze articles from JSON file")
    
    parser.add_argument('--threshold', type=int, default=60,
                       help="Relevance score threshold (default: 60)")
    
    parser.add_argument('--show-stats', action='store_true',
                       help="Show filtering statistics")
    
    parser.add_argument('--debug', action='store_true',
                       help="Enable debug logging")
    
    args = parser.parse_args()
    
    # Configure logging
    if args.debug:
        logger.level("DEBUG")
    else:
        logger.level("INFO")
    
    analyzer = NewsAnalyzer(relevance_threshold=args.threshold)
    
    if args.test_keywords:
        print("\n" + "="*80)
        print("Testing NewsAnalyzer on sample articles")
        print("="*80)
        
        for i, article in enumerate(SAMPLE_ARTICLES):
            relevance = analyzer.analyze_article(article)
            
            print(f"\n{i+1}. {relevance.category_emoji} {article['title']}")
            print(f"   Score: {relevance.score}/100")
            print(f"   Category: {relevance.category}")
            print(f"   Matched keywords: {', '.join(relevance.matched_keywords) if relevance.matched_keywords else 'None'}")
            print(f"   Blacklisted: {relevance.blacklisted}")
            print(f"   Is relevant: {relevance.is_relevant}")
    
    elif args.analyze_file:
        print(f"\nAnalyzing articles from: {args.analyze_file}")
        
        try:
            with open(args.analyze_file, 'r') as f:
                articles = json.load(f)
            
            filtered = analyzer.batch_analyze(articles)
            
            print(f"\nResults:")
            print(f"  Total articles: {len(articles)}")
            print(f"  Passed filter: {len(filtered)} ({len(filtered)/len(articles)*100:.1f}%)")
            
            if args.show_stats and filtered:
                print(f"\nTop articles (by relevance score):")
                for i, article in enumerate(filtered[:10]):
                    relevance = article['relevance']
                    print(f"  {i+1}. {relevance.category_emoji} [{relevance.score}] {article['title'][:80]}...")
        
        except FileNotFoundError:
            print(f"Error: File not found: {args.analyze_file}")
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON in file: {e}")
    
    else:
        print("\nNews Analyzer CLI - Module 16")
        print("Usage:")
        print("  python -m research.news_analyzer --test-keywords")
        print("  python -m research.news_analyzer --analyze-file articles.json --show-stats")
        print("\nOptions:")
        print("  --threshold N      Set relevance threshold (default: 60)")
        print("  --debug           Enable debug logging")
        print("  --show-stats      Show filtering statistics")


if __name__ == '__main__':
    main()