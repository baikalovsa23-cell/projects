"""
Research Scheduler — Protocol Research Engine
======================================================================
Weekly automated research cycles (Monday 00:00 UTC) with:
- News aggregation from all sources
- LLM analysis of candidates
- Saving to pending approval queue
- Cost tracking and logging
- Telegram notifications

Integration:
    - Master Orchestrator (Module 21) handles scheduling
    - This module provides the research cycle logic only

Dependencies:
    asyncio integration
    DatabaseManager
    NewsAggregator, ProtocolAnalyzer, NewsAnalyzer
"""

import asyncio
import sys
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from decimal import Decimal

from loguru import logger

from database.db_manager import get_db_manager
from research.news_aggregator import NewsAggregator
from research.protocol_analyzer import ProtocolAnalyzer
from research.news_analyzer import NewsAnalyzer


class ResearchScheduler:
    """
    Runs weekly protocol research cycles.
    
    Note:
        This class no longer manages scheduling. Use MasterOrchestrator
        to schedule the run_research_cycle() method.
    
    Usage (Master Orchestrator):
        from research.scheduler import ResearchScheduler
        scheduler = ResearchScheduler(db_manager=db)
        stats = await scheduler.run_research_cycle()
    
    Usage (Standalone - deprecated):
        scheduler = ResearchScheduler()
        scheduler.run_manual_cycle()  # For testing only
    """

    def __init__(self, db_manager=None):
        """
        Initialize research scheduler.
        
        Args:
            db_manager: DatabaseManager instance (optional)
        """
        self.db = db_manager or get_db_manager()
        self.aggregator = None
        self.analyzer = None
        
        logger.info("Research scheduler initialized")

    async def run_research_cycle(self) -> Dict[str, Any]:
        """
        Execute a full research cycle (async).
        
        Steps:
            1. Create research log entry
            2. Aggregate news from all sources
            3. Filter recent candidates
            4. LLM analysis of candidates
            5. Save high‑scoring protocols to pending queue
            6. Update research log with statistics
            7. Send Telegram notification
        
        Returns:
            Dictionary with cycle statistics
        """
        logger.info("Starting research cycle")
        cycle_start = datetime.now()
        
        # Create research log entry
        log_id = self.db.create_research_log(
            cycle_start_at=cycle_start,
            cycle_end_at=None,
            status='running',
            summary_report="Research cycle started"
        )
        
        stats = {
            'log_id': log_id,
            'total_candidates_found': 0,
            'total_analyzed_by_llm': 0,
            'total_added_to_pending': 0,
            'total_duplicates': 0,
            'total_rejected_low_score': 0,
            'total_filtered_by_news_analyzer': 0,
            'total_rejected_by_news_analyzer': 0,
            'estimated_cost_usd': Decimal('0.00'),
            'errors_encountered': 0,
            'error_details': []
        }
        
        try:
            # Step 1: News aggregation
            async with NewsAggregator(self.db) as aggregator:
                self.aggregator = aggregator
                all_candidates = await aggregator.run_full_aggregation()
                stats['total_candidates_found'] = len(all_candidates)
            
            if not all_candidates:
                logger.warning("No candidates found, ending cycle")
                self._complete_cycle(log_id, stats, cycle_start, "No candidates found")
                return stats
            
            # Step 2: Filter recent candidates (last 30 days)
            recent_candidates = self.aggregator.filter_recent_candidates(all_candidates, days=30)
            logger.info(f"Recent candidates (last 30 days): {len(recent_candidates)}")
            
            # Step 3: Convert to dict for LLM analysis
            candidate_dicts = [candidate.to_dict() for candidate in recent_candidates]
            
            # Step 3.5: Filter with NewsAnalyzer (Module 16)
            news_analyzer = NewsAnalyzer()
            filtered_candidates = news_analyzer.batch_analyze(candidate_dicts)
            stats['total_filtered_by_news_analyzer'] = len(filtered_candidates)
            stats['total_rejected_by_news_analyzer'] = len(candidate_dicts) - len(filtered_candidates)
            
            # Log filtering statistics
            if filtered_candidates:
                relevance_scores = [c['relevance'].score for c in filtered_candidates]
                avg_score = sum(relevance_scores) / len(relevance_scores)
                logger.info(
                    f"NewsAnalyzer filtered {len(candidate_dicts)} → {len(filtered_candidates)} articles "
                    f"(avg score: {avg_score:.1f}, savings: {stats['total_rejected_by_news_analyzer']} articles)"
                )
            
            # Step 4: LLM analysis (only on filtered candidates)
            async with ProtocolAnalyzer(self.db) as analyzer:
                self.analyzer = analyzer
                analyses = await analyzer.analyze_candidates(filtered_candidates)
                stats['total_analyzed_by_llm'] = len(analyses)
                stats['estimated_cost_usd'] = analyzer.total_cost_usd
            
            if not analyses:
                logger.warning("No successful LLM analyses, ending cycle")
                self._complete_cycle(log_id, stats, cycle_start, "No successful analyses")
                return stats
            
            # Step 5: Filter high‑scoring protocols (>= 50)
            high_scoring = [a for a in analyses if a.get('airdrop_score', 0) >= 50]
            low_scoring = [a for a in analyses if a.get('airdrop_score', 0) < 50]
            
            stats['total_rejected_low_score'] = len(low_scoring)
            
            # Step 6: Check for duplicates (by name) before saving
            unique_protocols = []
            seen_names = set()
            for analysis in high_scoring:
                name = analysis.get('name')
                if name in seen_names:
                    stats['total_duplicates'] += 1
                    continue
                seen_names.add(name)
                unique_protocols.append(analysis)
            
            # Step 7: Save to pending queue
            saved_count = await analyzer.save_to_pending(unique_protocols)
            stats['total_added_to_pending'] = saved_count
            
            # Step 8: Update research log
            summary = (
                f"Research cycle completed: {saved_count} new protocols pending approval. "
                f"Cost: ${stats['estimated_cost_usd']:.4f}"
            )
            self._complete_cycle(log_id, stats, cycle_start, summary)
            
            # Step 9: Send Telegram notification
            await self._send_telegram_notification(stats, summary)
            
            logger.success(f"Research cycle completed | Protocols added: {saved_count}")
            return stats
            
        except Exception as e:
            logger.exception(f"Research cycle failed: {e}")
            stats['errors_encountered'] += 1
            stats['error_details'].append(str(e))
            
            # Update log with error
            self.db.update_research_log(
                log_id,
                cycle_end_at=datetime.now(),
                status='failed',
                errors_encountered=stats['errors_encountered'],
                error_details=stats['error_details'],
                summary_report=f"Research cycle failed: {e}"
            )
            
            # Send error alert
            await self._send_error_notification(e)
            raise

    def _complete_cycle(self, log_id: int, stats: Dict[str, Any], start_time: datetime, summary: str):
        """Update research log with completed cycle statistics."""
        self.db.update_research_log(
            log_id,
            cycle_end_at=datetime.now(),
            status='completed',
            total_candidates_found=stats['total_candidates_found'],
            total_analyzed_by_llm=stats['total_analyzed_by_llm'],
            total_added_to_pending=stats['total_added_to_pending'],
            total_duplicates=stats['total_duplicates'],
            total_rejected_low_score=stats['total_rejected_low_score'],
            llm_api_calls=stats['total_analyzed_by_llm'],  # Approximate
            llm_tokens_used=0,  # Not tracked granularly
            estimated_cost_usd=stats['estimated_cost_usd'],
            errors_encountered=stats['errors_encountered'],
            error_details=stats['error_details'] if stats['errors_encountered'] else None,
            summary_report=summary
        )
        duration = (datetime.now() - start_time).total_seconds()
        logger.info(f"Cycle {log_id} completed in {duration:.1f}s | {summary}")

    async def _send_telegram_notification(self, stats: Dict[str, Any], summary: str):
        """Send research cycle completion alert via Telegram."""
        try:
            from notifications.telegram_bot import send_alert
            
            message = (
                f"🔬 *Protocol Research Cycle Completed*\n\n"
                f"*Statistics:*\n"
                f"• Candidates found: {stats['total_candidates_found']}\n"
                f"• Analyzed by LLM: {stats['total_analyzed_by_llm']}\n"
                f"• Added to pending: {stats['total_added_to_pending']}\n"
                f"• Low‑score rejected: {stats['total_rejected_low_score']}\n"
                f"• Duplicates skipped: {stats['total_duplicates']}\n"
                f"• Estimated cost: ${stats['estimated_cost_usd']:.4f}\n\n"
                f"{summary}"
            )
            
            send_alert('info', message)
            logger.debug("Telegram notification sent")
        except ImportError:
            logger.warning("Telegram bot not available, skipping notification")
        except Exception as e:
            logger.error(f"Failed to send Telegram notification: {e}")

    async def _send_error_notification(self, error: Exception):
        """Send error alert via Telegram."""
        try:
            from notifications.telegram_bot import send_alert
            send_alert('error', f"Research cycle failed: {str(error)}")
        except ImportError:
            pass

    def run_manual_cycle(self):
        """
        Run a research cycle immediately (blocking).
        
        Used for testing and `/force_research_cycle` command.
        Note: This is for standalone testing only. Use MasterOrchestrator
        for production scheduling.
        """
        logger.info("Starting manual research cycle")
        loop = asyncio.get_event_loop()
        if loop.is_running():
            # If already in an event loop (e.g., from async context), create task
            task = asyncio.create_task(self.run_research_cycle())
            return task
        else:
            # Otherwise run in new event loop
            return loop.run_until_complete(self.run_research_cycle())


if __name__ == "__main__":
    """Test the scheduler with a manual run."""
    async def test():
        scheduler = ResearchScheduler()
        print("Starting manual research cycle...")
        stats = await scheduler.run_research_cycle()
        print(f"✅ Cycle completed | Protocols added: {stats['total_added_to_pending']}")
    
    asyncio.run(test())