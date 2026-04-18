"""
Protocol Research Engine — Module 15 + Module 16
================================================
Semi-automated discovery and evaluation of new DeFi protocols (L2-focused, 2026).

Module 15 (Protocol Research Engine):
- News aggregation from Crypto News API, DefiLlama, RSS feeds
- LLM analysis via OpenRouter (GPT-4 Turbo)
- Telegram approval workflow
- Cost tracking and audit logs

Module 16 (News Analyzer):
- Keyword-based relevance filtering (airdrop, points, L2, token launch)
- 80% LLM cost reduction by filtering irrelevant articles
- Blacklist filtering for spam/regulatory news

Weekly research cycles run every Monday 00:00 UTC.
"""

from .news_aggregator import NewsAggregator
from .protocol_analyzer import ProtocolAnalyzer
from .scheduler import ResearchScheduler
from .news_analyzer import NewsAnalyzer, RelevanceScore, FilteredArticle

__all__ = [
    "NewsAggregator", 
    "ProtocolAnalyzer", 
    "ResearchScheduler",
    "NewsAnalyzer",
    "RelevanceScore",
    "FilteredArticle"
]

__version__ = "1.1.0"