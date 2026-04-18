"""
APScheduler Job Definitions — Module 21
=======================================

Defines all scheduled jobs for the Master Node Orchestrator.

Each job is a wrapper function that:
1. Initializes the required module
2. Executes the job
3. Handles errors
4. Logs results
5. Sends Telegram notifications

Anti-Sybil Considerations:
- Each job runs independently with temporal isolation
- No cross-job dependencies that could create patterns
- Error handling prevents cascading failures

Author: Airdrop Farming System v4.0
Created: 2026-02-26
"""

import os
import asyncio
from typing import Dict, Any
from loguru import logger
from datetime import datetime, timedelta


# ============================================================================
# JOB 1: Activity Scheduler (Module 11)
# ============================================================================

async def run_activity_scheduler_job(db, telegram_bot):
    """
    Generate weekly activity schedule for all 90 wallets.
    
    Trigger: Sunday 18:00 UTC
    Duration: ~2-5 minutes
    
    Anti-Sybil Design:
    - Uses Gaussian scheduling per wallet persona
    - Each wallet gets unique transaction timing
    - No synchronous patterns across wallets
    
    Args:
        db: DatabaseManager instance
        telegram_bot: TelegramBot instance
    
    Returns:
        None (logs results)
    """
    
    job_name = "Activity Scheduler"
    logger.info(f"Starting job: {job_name}")
    
    try:
        from activity.scheduler import ActivityScheduler
        
        scheduler = ActivityScheduler(db_manager=db)
        
        # Calculate next week start (Monday 00:00 UTC)
        today = datetime.utcnow()
        days_ahead = 1 - today.weekday()  # 1 = Monday
        if days_ahead <= 0:
            days_ahead += 7
        week_start = (today + timedelta(days=days_ahead)).replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        
        # Generate schedules for all wallets
        count = scheduler.generate_for_all_wallets(week_start)
        
        logger.success(f"Job completed: {job_name} | Wallets scheduled: {count}/90")
        
        # Send Telegram notification
        telegram_bot.send_alert(
            'INFO',
            f'📅 *Activity Scheduler Complete*\n\n'
            f'Scheduled: {count}/90 wallets\n'
            f'Week: {week_start.strftime("%Y-%m-%d")}'
        )
        
    except Exception as e:
        logger.exception(f"Job failed: {job_name} — {e}")
        telegram_bot.send_alert(
            'CRITICAL',
            f'🚨 *Activity Scheduler Failed*\n\n'
            f'Error: {str(e)[:200]}\n'
            f'Check logs for details.'
        )


# ============================================================================
# JOB 2: Research Cycle (Module 15)
# ============================================================================

async def run_research_cycle_job(db, telegram_bot):
    """
    Run weekly protocol research cycle.
    
    Trigger: Monday 00:00 UTC
    Duration: ~10-30 minutes
    
    Pipeline:
    1. Aggregate protocol candidates (news, DefiLlama)
    2. Filter by relevance (Module 16)
    3. LLM analysis (Module 15)
    4. Add to pending approval queue
    
    Anti-Sybil Design:
    - Research is independent of wallet operations
    - LLM analysis adds natural randomness
    - No correlation with funding/activity patterns
    
    Args:
        db: DatabaseManager instance
        telegram_bot: TelegramBot instance
    
    Returns:
        None (logs results)
    """
    
    job_name = "Research Cycle"
    logger.info(f"Starting job: {job_name}")
    
    try:
        from research.scheduler import ResearchScheduler
        
        scheduler = ResearchScheduler(db_manager=db)
        stats = await scheduler.run_research_cycle()
        
        logger.success(
            f"Job completed: {job_name} | "
            f"Protocols added: {stats['total_added_to_pending']} | "
            f"LLM cost: ${stats['total_llm_cost']:.4f}"
        )
        
        # Send Telegram notification
        telegram_bot.send_alert(
            'INFO',
            f'🔬 *Research Cycle Complete*\n\n'
            f'Protocols analyzed: {stats["total_candidates"]}\n'
            f'Added to queue: {stats["total_added_to_pending"]}\n'
            f'LLM cost: ${stats["total_llm_cost"]:.4f}\n\n'
            f'Use `/research_status` to review.'
        )
        
    except Exception as e:
        logger.exception(f"Job failed: {job_name} — {e}")
        telegram_bot.send_alert(
            'CRITICAL',
            f'🚨 *Research Cycle Failed*\n\n'
            f'Error: {str(e)[:200]}\n'
            f'Check logs for details.'
        )


# ============================================================================
# JOB 3: Airdrop Scanner (Module 17)
# ============================================================================

async def run_airdrop_scan_job(db, telegram_bot):
    """
    Scan all wallets for new token balances (potential airdrops).
    
    Trigger: Every 6 hours
    Duration: ~2 minutes
    
    Scans:
    - 90 wallets × 7 chains = 630 API calls
    - Explorer APIs (Etherscan, Basescan, etc.)
    - Token verification (Module 18)
    
    Anti-Sybil Design:
    - Random rate limiting between API calls
    - Staggered scanning across chains
    - No predictable timing patterns
    
    Args:
        db: DatabaseManager instance
        telegram_bot: TelegramBot instance
    
    Returns:
        None (logs results)
    """
    
    job_name = "Airdrop Scanner"
    logger.info(f"Starting job: {job_name}")
    
    try:
        from monitoring.airdrop_detector import AirdropDetector
        
        detector = AirdropDetector(db_manager=db)
        stats = await detector.scan_all_wallets()
        
        logger.success(
            f"Job completed: {job_name} | "
            f"New tokens: {stats['new_tokens_found']} | "
            f"Scan time: {stats['scan_duration_seconds']:.1f}s"
        )
        
        # Telegram notification only if NEW airdrops found
        if stats['new_tokens_found'] > 0:
            telegram_bot.send_alert(
                'INFO',
                f'🎁 *New Airdrops Detected*\n\n'
                f'New tokens: {stats["new_tokens_found"]}\n'
                f'Verified: {stats["verified_tokens"]}\n\n'
                f'Use `/withdrawals` to create exit plan.'
            )
        
    except Exception as e:
        logger.exception(f"Job failed: {job_name} — {e}")
        # Don't spam on every failure (might be RPC issue)
        if "CRITICAL" in str(e).upper():
            telegram_bot.send_alert(
                'WARNING',
                f'⚠️ *Airdrop Scanner Failed*\n\n'
                f'Error: {str(e)[:200]}\n'
                f'Will retry in 6 hours.'
            )


# ============================================================================
# JOB 4: Withdrawal Processor (Module 19)
# ============================================================================

async def run_withdrawal_processor_job(db, telegram_bot):
    """
    Process pending withdrawal steps (check if ready for approval).
    
    Trigger: Every 6 hours
    Duration: ~30 seconds
    
    Workflow:
    1. Find steps with status='planned' AND scheduled_at <= NOW()
    2. Run safety checks (balance, gas, network)
    3. Set status='pending_approval'
    4. Send Telegram notification for human approval
    
    Anti-Sybil Design:
    - Human-in-the-loop for all withdrawals
    - Tier-based isolation between withdrawals
    - Temporal spacing to avoid pattern detection
    
    Args:
        db: DatabaseManager instance
        telegram_bot: TelegramBot instance
    
    Returns:
        None (logs results)
    """
    
    job_name = "Withdrawal Processor"
    logger.info(f"Starting job: {job_name}")
    
    try:
        from withdrawal.orchestrator import WithdrawalOrchestrator
        
        orchestrator = WithdrawalOrchestrator(
            db_manager=db,
            telegram_bot=telegram_bot,
            dry_run=False
        )
        
        # Process pending steps
        processed = orchestrator.process_pending_steps()
        
        logger.success(
            f"Job completed: {job_name} | "
            f"Steps processed: {processed}"
        )
        
        # Notification sent by orchestrator for each step
        
    except Exception as e:
        logger.exception(f"Job failed: {job_name} — {e}")
        telegram_bot.send_alert(
            'CRITICAL',
            f'🚨 *Withdrawal Processor Failed*\n\n'
            f'Error: {str(e)[:200]}\n'
            f'Manual intervention may be required.'
        )


# ============================================================================
# JOB 5: Direct Funding Withdrawals (v3.0 - Module 7)
# ============================================================================

async def run_direct_funding_withdrawals_job(db, telegram_bot):
    """
    Execute DIRECT CEX → wallet withdrawals per interleaved schedule (v3.0).
    
    Trigger: Every 1 hour
    Duration: ~1-5 minutes (depending on ready withdrawals)
    
    Workflow:
    1. Find funding_withdrawals with status='planned' AND cex_withdrawal_scheduled_at <= NOW()
    2. Execute direct CEX withdrawal via API
    3. Mark as 'processing' → 'completed' when confirmed on-chain
    
    Anti-Sybil Design:
    - No intermediate wallets (Star patterns eliminated)
    - Interleaved execution across exchanges
    - 7-day temporal spread with Gaussian delays
    - Each withdrawal processed independence (no batching)
    
    Args:
        db: DatabaseManager instance
        telegram_bot: TelegramBot instance
    
    Returns:
        None (logs results)
    """
    
    job_name = "Direct Funding Withdrawals (v3.0)"
    logger.info(f"Starting job: {job_name}")
    
    try:
        from funding.engine_v3 import DirectFundingEngineV3
        
        engine = DirectFundingEngineV3()
        
        # Find withdrawals ready to execute
        query = """
            SELECT
                fw.id,
                fw.wallet_id,
                fw.amount_usdt,
                fw.withdrawal_network,
                fw.withdrawal_address,
                fw.interleave_round,
                cs.exchange,
                cs.subaccount_name,
                w.tier,
                COUNT(*) OVER() as total_ready
            FROM funding_withdrawals fw
            JOIN cex_subaccounts cs ON fw.cex_subaccount_id = cs.id
            JOIN wallets w ON fw.wallet_id = w.id
            WHERE fw.direct_cex_withdrawal = TRUE
              AND fw.status = 'planned'
              AND fw.cex_withdrawal_scheduled_at <= NOW()
            ORDER BY fw.cex_withdrawal_scheduled_at ASC
            LIMIT 5
        """
        
        ready_withdrawals = db.execute_query(query, fetch='all')
        
        if not ready_withdrawals:
            logger.info(f"Job completed: {job_name} | No withdrawals ready")
            return
        
        total_ready = ready_withdrawals[0]['total_ready'] if ready_withdrawals else 0
        logger.info(
            f"Found {len(ready_withdrawals)} withdrawals to process | "
            f"Total ready: {total_ready}"
        )
        
        processed_count = 0
        failed_count = 0
        
        for withdrawal in ready_withdrawals:
            try:
                logger.info(
                    f"Processing withdrawal {withdrawal['id']} | "
                    f"Exchange: {withdrawal['exchange']} | "
                    f"Amount: ${withdrawal['amount_usdt']:.2f} | "
                    f"Network: {withdrawal['withdrawal_network']} | "
                    f"To: {withdrawal['withdrawal_address'][:10]}..."
                )
                
                # Execute direct CEX withdrawal
                result = await engine.execute_direct_cex_withdrawal(
                    withdrawal_id=withdrawal['id']
                )
                
                processed_count += 1
                
                logger.success(
                    f"Withdrawal processed | "
                    f"ID: {withdrawal['id']} | "
                    f"Exchange: {withdrawal['exchange']} | "
                    f"Tier: {withdrawal['tier']}"
                )
                
                # Small delay between withdrawals (anti-burst)
                if withdrawal != ready_withdrawals[-1]:
                    delay_seconds = random.uniform(30, 120)
                    logger.debug(f"Waiting {delay_seconds:.0f}s before next withdrawal...")
                    await asyncio.sleep(delay_seconds)
                
            except Exception as e:
                failed_count += 1
                logger.exception(
                    f"Failed to process withdrawal {withdrawal['id']} | "
                    f"Error: {e}"
                )
                
                # Mark as failed
                db.execute_query(
                    """
                    UPDATE funding_withdrawals
                    SET status = 'failed'
                    WHERE id = %s
                    """,
                    (withdrawal['id'],)
                )
                
                # Send alert for failures
                telegram_bot.send_alert(
                    'WARNING',
                    f'⚠️ *Direct Withdrawal Failed*\n\n'
                    f'ID: {withdrawal["id"]}\n'
                    f'Exchange: {withdrawal["exchange"]}\n'
                    f'Amount: ${withdrawal["amount_usdt"]:.2f}\n'
                    f'Error: {str(e)[:200]}'
                )
        
        logger.success(
            f"Job completed: {job_name} | "
            f"Processed: {processed_count} | "
            f"Failed: {failed_count} | "
            f"Remaining: {total_ready - processed_count - failed_count}"
        )
        
        # Send summary notification
        if processed_count > 0:
            telegram_bot.send_alert(
                'INFO',
                f'💰 *Direct Funding Withdrawals*\n\n'
                f'Processed: {processed_count}\n'
                f'Failed: {failed_count}\n'
                f'Remaining in queue: {total_ready - processed_count - failed_count}'
            )
        
    except Exception as e:
        logger.exception(f"Job failed: {job_name} — {e}")
        telegram_bot.send_alert(
            'CRITICAL',
            f'🚨 *Direct Funding Job Failed*\n\n'
            f'Error: {str(e)[:200]}\n'
            f'Check logs immediately.'
        )


# ============================================================================
# JOB 6: Cleanup Jobs (Maintenance)
# ============================================================================

async def run_cleanup_jobs(db):
    """
    Maintenance jobs (executed weekly).
    
    Trigger: Sunday 02:00 UTC
    Duration: ~10 seconds
    
    Tasks:
    1. Auto-reject protocols pending approval > 7 days
    2. Archive old logs (>30 days)
    3. VACUUM analyze database (optional)
    
    Anti-Sybil Design:
    - Low priority, runs during low-activity period
    - No impact on wallet operations
    - Database maintenance only
    
    Args:
        db: DatabaseManager instance
    
    Returns:
        None (logs results)
    """
    
    job_name = "Cleanup Jobs"
    logger.info(f"Starting job: {job_name}")
    
    try:
        # Check if auto_reject_stale_protocols function exists
        try:
            # Auto-reject stale protocols
            result = db.execute_query(
                "SELECT auto_reject_stale_protocols()",
                fetch='one'
            )
            if result and 'auto_reject_stale_protocols' in result:
                rejected = result['auto_reject_stale_protocols']
                logger.info(f"Auto-rejected stale protocols: {rejected}")
        except Exception as e:
            logger.debug(f"Auto-reject function not available: {e}")
        
        # Archive old system events (older than 90 days)
        try:
            archived = db.execute_query(
                """
                DELETE FROM system_events 
                WHERE created_at < NOW() - INTERVAL '90 days'
                RETURNING COUNT(*) as count
                """,
                fetch='one'
            )
            if archived:
                logger.info(f"Archived old events: {archived['count']}")
        except Exception as e:
            logger.debug(f"System events cleanup not available: {e}")
        
        logger.success(f"Job completed: {job_name}")
        
    except Exception as e:
        logger.exception(f"Job failed: {job_name} — {e}")
        # Non-critical job, don't alert


# ============================================================================
# JOB 7: Recheck Unreachable Protocols (Bridge Integration)
# ============================================================================

async def recheck_unreachable_protocols_job(db, telegram_bot):
    """
    Recheck unreachable protocols for bridge availability.
    
    Trigger: Monday 00:00 UTC (before research cycle)
    Duration: ~1-5 minutes
    
    Workflow:
    1. Find protocols with bridge_available=FALSE and bridge_recheck_after <= NOW()
    2. Check bridge availability via BridgeManager
    3. Update bridge info if now available
    4. Auto-reject after 4 failed attempts (30 days)
    
    Integration:
    - Uses BridgeManager v2.0 for dynamic CEX and bridge checking
    - Updates protocol_research_pending table (migration 032)
    - Sends Telegram alerts when bridge becomes available
    
    Args:
        db: DatabaseManager instance
        telegram_bot: TelegramBot instance
    
    Returns:
        None (logs results)
    """
    
    job_name = "Recheck Unreachable Protocols"
    logger.info(f"Starting job: {job_name}")
    
    try:
        from activity.bridge_manager import BridgeManager
        from decimal import Decimal
        
        # Get unreachable protocols for recheck
        protocols = db.execute_query(
            """
            SELECT
                id, name, chains, bridge_from_network, bridge_recheck_count,
                airdrop_score, bridge_unreachable_reason
            FROM protocol_research_pending
            WHERE bridge_available = FALSE
              AND status = 'pending_approval'
              AND bridge_recheck_after <= NOW()
              AND bridge_recheck_count < 4
            ORDER BY airdrop_score DESC
            """,
            fetch='all'
        )
        
        if not protocols:
            logger.info(f"Job completed: {job_name} | No unreachable protocols to recheck")
            return
        
        logger.info(f"Found {len(protocols)} unreachable protocols to recheck")
        
        # Initialize BridgeManager in dry-run mode (only checking, not executing)
        bridge_manager = BridgeManager(db=db, dry_run=True)
        
        available_count = 0
        rejected_count = 0
        still_unreachable_count = 0
        
        for protocol in protocols:
            protocol_id = protocol['id']
            protocol_name = protocol['name']
            chains = protocol.get('chains', [])
            primary_chain = chains[0] if chains else None
            
            if not primary_chain:
                logger.warning(f"Protocol {protocol_name} has no chains, skipping")
                continue
            
            logger.info(
                f"Rechecking bridge for {protocol_name} | "
                f"Chain: {primary_chain} | Attempt: {protocol['bridge_recheck_count'] + 1}/4"
            )
            
            try:
                # Check if bridge is required
                bridge_required, cex_name = await bridge_manager.is_bridge_required(primary_chain)
                
                if not bridge_required:
                    # CEX now supports this network!
                    logger.success(
                        f"🎉 Bridge NO LONGER REQUIRED for {primary_chain} | "
                        f"CEX support: {cex_name}"
                    )
                    
                    # Update protocol
                    db.execute_query(
                        """
                        UPDATE protocol_research_pending
                        SET bridge_required = FALSE,
                            bridge_available = TRUE,
                            cex_support = %s,
                            bridge_checked_at = NOW(),
                            bridge_unreachable_reason = NULL,
                            bridge_recheck_after = NULL
                        WHERE id = %s
                        """,
                        (cex_name, protocol_id)
                    )
                    
                    available_count += 1
                    
                    # Send Telegram alert
                    telegram_bot.send_alert(
                        'INFO',
                        f'🎉 *Bridge Now Available!*\n\n'
                        f'Protocol: {protocol_name}\n'
                        f'Chain: {primary_chain}\n'
                        f'CEX Support: {cex_name}\n\n'
                        f'Protocol is ready for approval.\n'
                        f'/approve_protocol_{protocol_id}'
                    )
                    
                    continue
                
                # Bridge still required - check availability
                from_network = protocol.get('bridge_from_network') or 'Arbitrum'
                route = await bridge_manager.check_bridge_availability(
                    from_network=from_network,
                    to_network=primary_chain,
                    amount_eth=Decimal('0.05')
                )
                
                if route:
                    # Bridge route found!
                    logger.success(
                        f"🎉 Bridge NOW AVAILABLE for {protocol_name} | "
                        f"Provider: {route.provider} | Cost: ${route.cost_usd:.2f}"
                    )
                    
                    # Update protocol
                    db.execute_query(
                        """
                        UPDATE protocol_research_pending
                        SET bridge_available = TRUE,
                            bridge_provider = %s,
                            bridge_cost_usd = %s,
                            bridge_safety_score = %s,
                            bridge_checked_at = NOW(),
                            bridge_unreachable_reason = NULL,
                            bridge_recheck_after = NULL
                        WHERE id = %s
                        """,
                        (route.provider, route.cost_usd, route.safety_score, protocol_id)
                    )
                    
                    available_count += 1
                    
                    # Send Telegram alert
                    telegram_bot.send_alert(
                        'INFO',
                        f'🎉 *Bridge Now Available!*\n\n'
                        f'Protocol: {protocol_name}\n'
                        f'Chain: {primary_chain}\n'
                        f'Provider: {route.provider}\n'
                        f'Cost: ${route.cost_usd:.2f}\n'
                        f'Safety: {route.safety_score}/100\n\n'
                        f'Protocol is ready for approval.\n'
                        f'/approve_protocol_{protocol_id}'
                    )
                
                else:
                    # Still unreachable
                    new_count = protocol['bridge_recheck_count'] + 1
                    
                    if new_count >= 4:
                        # Auto-reject after 4 attempts (30 days)
                        logger.warning(
                            f"❌ Auto-rejecting {protocol_name} | "
                            f"Bridge unavailable for 30 days (4 attempts)"
                        )
                        
                        db.execute_query(
                            """
                            UPDATE protocol_research_pending
                            SET status = 'auto_rejected',
                                rejected_reason = 'Bridge unavailable for 30 days (4 recheck attempts)',
                                rejected_at = NOW(),
                                bridge_recheck_count = %s,
                                bridge_checked_at = NOW()
                            WHERE id = %s
                            """,
                            (new_count, protocol_id)
                        )
                        
                        rejected_count += 1
                        
                        # Send Telegram alert
                        telegram_bot.send_alert(
                            'WARNING',
                            f'⚠️ *Protocol Auto-Rejected*\n\n'
                            f'Protocol: {protocol_name}\n'
                            f'Chain: {primary_chain}\n'
                            f'Reason: Bridge unavailable for 30 days\n\n'
                            f'Use /force_approve_unreachable_{protocol_id} if needed.'
                        )
                    
                    else:
                        # Schedule next recheck
                        logger.info(
                            f"Bridge still unavailable for {protocol_name} | "
                            f"Scheduling recheck #{new_count + 1}"
                        )
                        
                        db.execute_query(
                            """
                            UPDATE protocol_research_pending
                            SET bridge_recheck_count = %s,
                                bridge_recheck_after = NOW() + INTERVAL '7 days',
                                bridge_checked_at = NOW()
                            WHERE id = %s
                            """,
                            (new_count, protocol_id)
                        )
                        
                        still_unreachable_count += 1
            
            except Exception as e:
                logger.error(f"Failed to recheck {protocol_name}: {e}")
                continue
        
        logger.success(
            f"Job completed: {job_name} | "
            f"Now available: {available_count} | "
            f"Auto-rejected: {rejected_count} | "
            f"Still unreachable: {still_unreachable_count}"
        )
        
        # Send summary notification
        if available_count > 0 or rejected_count > 0:
            telegram_bot.send_alert(
                'INFO',
                f'🔄 *Unreachable Protocols Recheck*\n\n'
                f'Now available: {available_count}\n'
                f'Auto-rejected: {rejected_count}\n'
                f'Still unreachable: {still_unreachable_count}\n\n'
                f'Total checked: {len(protocols)}'
            )
        
    except Exception as e:
        logger.exception(f"Job failed: {job_name} — {e}")
        telegram_bot.send_alert(
            'CRITICAL',
            f'🚨 *Recheck Unreachable Protocols Failed*\n\n'
            f'Error: {str(e)[:200]}\n'
            f'Check logs for details.'
        )