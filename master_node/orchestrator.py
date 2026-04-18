"""
Master Node Orchestrator — Module 21
====================================

Coordinates all system components on the Master Node.

Features:
- Unified APScheduler for all modules
- Lifecycle management (startup/shutdown)
- Health monitoring integration
- Telegram bot integration
- CLI interface for system control

Author: Airdrop Farming System v4.0
Created: 2026-02-26
"""

import os
import sys
import signal
import asyncio
from pathlib import Path
from typing import Optional
from datetime import datetime

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger
from loguru import logger
from dotenv import load_dotenv

# Add parent directory for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from database.db_manager import DatabaseManager
from monitoring.health_check import HealthCheckOrchestrator
from notifications.telegram_bot import TelegramBot
from master_node.jobs import (
    run_activity_scheduler_job,
    run_research_cycle_job,
    run_airdrop_scan_job,
    run_withdrawal_processor_job,
    run_direct_funding_withdrawals_job,
    run_cleanup_jobs
)
from infrastructure.network_mode import (
    NetworkModeManager,
    NetworkMode,
    is_dry_run,
    is_testnet,
    is_mainnet
)
from infrastructure.chain_discovery import ChainDiscoveryService # Import ChainDiscoveryService


# Whitelisting policy constant
WHITELISTING_HOLD_DAYS = 10  # T + 10 days after whitelisting before first withdrawal


class MasterOrchestrator:
    """
    Master Node orchestrator — coordinates all system components.
    
    Responsibilities:
    - Initialize all core services (DB, Health Check, Telegram Bot)
    - Configure APScheduler with all scheduled jobs
    - Manage system lifecycle (startup, shutdown)
    - Provide CLI interface for system control
    
    Anti-Sybil Design:
    - Each module runs independently with temporal isolation
    - No direct coupling between wallet operations
    - Jobs scheduled with appropriate intervals to avoid patterns
    """
    
    def __init__(self):
        """Initialize orchestrator with core dependencies."""
        logger.info("Initializing Master Orchestrator...")
        
        # Core services
        self.db: Optional[DatabaseManager] = None
        self.health_check: Optional[HealthCheckOrchestrator] = None
        self.telegram_bot: Optional[TelegramBot] = None
        self.scheduler: Optional[AsyncIOScheduler] = None
        self.chain_discovery: Optional[ChainDiscoveryService] = None # Initialize ChainDiscoveryService
        
        # Initialize network mode manager
        self.network_mode = NetworkModeManager()
        
        # Shutdown event for graceful cleanup
        self._shutdown_event = asyncio.Event()
        
        # Register signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
        # Log system startup with mode
        mode = self.network_mode.get_mode()
        logger.info(f"═══════════════════════════════════════════════════")
        logger.info(f"    AIRDROP FARMING ORCHESTRATOR STARTING")
        logger.info(f"    NETWORK MODE: {mode.value.upper()}")
        logger.info(f"═══════════════════════════════════════════════════")
        
        if is_dry_run():
            logger.info("🔒 DRY-RUN MODE: No real transactions will be executed")
        elif is_testnet():
            logger.info("🧪 TESTNET MODE: Using Sepolia testnet")
        else:
            logger.warning("⚠️ MAINNET MODE: Safety gates check required")
        
        logger.info("Master Orchestrator initialized")
    
    def _signal_handler(self, signum, frame):
        """
        Handle SIGINT/SIGTERM for graceful shutdown.
        
        Args:
            signum: Signal number
            frame: Current stack frame
        """
        logger.warning(f"Received signal {signum} — initiating graceful shutdown...")
        # Create task to avoid blocking signal handler
        asyncio.create_task(self.shutdown())
    
    async def start(self):
        """
        Start all system components in correct order.
        
        Startup sequence:
        0. Network mode validation
        1. Database health check
        2. RPC health check
        3. Health Check System (background threads)
        4. Telegram Bot (background thread)
        5. APScheduler with all jobs
        6. Log startup complete
        
        Raises:
            SystemExit: If database health check fails or safety gates not passed
        """
        
        try:
            # 0. Network mode validation
            logger.info("Step 0/6: Network mode validation...")
            mode = self.network_mode.get_mode()
            
            if mode == NetworkMode.MAINNET:
                # Database must be initialized first for safety gates check
                logger.info("MAINNET mode detected - initializing database for safety gates check...")
                self.db = DatabaseManager()
                
                # Check safety gates BEFORE starting mainnet operations
                if not await self.check_safety_gates():
                    logger.error("⛔ Cannot start in MAINNET mode - safety gates not passed")
                    logger.info("   Set NETWORK_MODE=DRY_RUN or NETWORK_MODE=TESTNET to continue")
                    raise SystemError("Mainnet safety gates not passed")
            
            # 1. Database health check
            logger.info("Step 1/6: Database health check...")
            if not self._check_database():
                logger.error("Database health check failed — aborting startup")
                sys.exit(1)
            
            # Initialize ChainDiscoveryService after DB is ready
            self.chain_discovery = ChainDiscoveryService(db=self.db)
            
            # 2. RPC health check
            logger.info("Step 2/6: Performing RPC health check...")
            active_chains = await self.chain_discovery.check_rpc_health()
            if not active_chains:
                logger.warning("No active RPC endpoints found for any chain. System will proceed, but activity may be limited.")
                if self.telegram_bot:
                    await self.telegram_bot.send_alert(
                        'WARNING',
                        '⚠️ *RPC Health Check Warning*\n\n'
                        'No active RPC endpoints found for any chain. System will proceed, but activity may be limited.'
                    )
            else:
                logger.success(f"RPC health check passed. Active chains: {', '.join(active_chains)}")
            
            # 3. Start Health Check System
            logger.info("Step 3/6: Starting Health Check System...")
            self.health_check = HealthCheckOrchestrator()
            self.health_check.start()
            
            # 4. Start Telegram Bot
            logger.info("Step 4/6: Starting Telegram Bot...")
            self.telegram_bot = TelegramBot()
            self.telegram_bot.start_background()
            
            # 5. Initialize and start APScheduler
            logger.info("Step 5/6: Initializing APScheduler...")
            self.scheduler = AsyncIOScheduler(timezone="UTC")
            self._register_jobs()
            self.scheduler.start()
            
            # 6. Startup complete
            logger.success("Step 6/6: Master Node Orchestrator started successfully!")
            
            # Send Telegram notification with network mode
            mode = self.network_mode.get_mode()
            mode_emoji = "🔒" if is_dry_run() else ("🧪" if is_testnet() else "⚠️")
            
            self.telegram_bot.send_alert(
                'INFO',
                f'{mode_emoji} *MASTER NODE STARTED*\n\n'
                f'*Network Mode:* `{mode.value.upper()}`\n\n'
                'All systems operational:\n'
                '• Database: Connected\n'
                '• RPCs: Checked\n'
                '• Health Check: Running\n'
                '• APScheduler: Active\n'
                '• Telegram Bot: Listening'
            )
            
            # Log next scheduled jobs
            self._log_next_jobs()
            
            # Wait for shutdown signal
            await self._shutdown_event.wait()
            
        except Exception as e:
            logger.exception(f"Fatal error during startup: {e}")
            await self.shutdown()
            sys.exit(1)
    
    def _check_database(self) -> bool:
        """
        Verify database connectivity and critical tables.
        
        Returns:
            True if database is healthy, False otherwise
        """
        try:
            # Initialize database manager
            self.db = DatabaseManager()
            
            # Test connection
            result = self.db.execute_query("SELECT 1 AS test", fetch='one')
            if result['test'] != 1:
                logger.error("Database connection test failed")
                return False
            
            # Check critical tables exist
            critical_tables = [
                'wallets', 'scheduled_transactions', 'worker_nodes',
                'chain_rpc_endpoints', 'withdrawal_plans', 'wallet_tokens'
            ]
            
            for table in critical_tables:
                try:
                    count = self.db.execute_query(
                        f"SELECT COUNT(*) as count FROM {table}",
                        fetch='one'
                    )
                    logger.debug(f"Table {table}: {count['count']} rows")
                except Exception as e:
                    logger.warning(f"Table {table} check failed: {e}")
            
            logger.success("Database health check passed")
            return True
            
        except Exception as e:
            logger.error(f"Database health check failed: {e}")
            return False
    
    def _register_jobs(self):
        """
        Register all scheduled jobs with APScheduler.
        
        Jobs:
        - Activity Scheduler: Weekly (Sunday 18 :00 UTC)
        - Research Cycle: Weekly (Monday 00:00 UTC)
        - Airdrop Scanner: Every 6 hours
        - Withdrawal Processor: Every 6 hours
        - Direct Funding Withdrawals (v3.0): Every 1 hour
        - Cleanup Jobs: Weekly (Sunday 02:00 UTC)
        
        Anti-Sybil Considerations:
        - Temporal isolation between jobs (no overlapping execution)
        - Different intervals prevent pattern detection
        - Misfire grace periods allow for natural timing variations
        """
        
        # Activity Scheduler (Module 11) - Sunday 18:00 UTC
        self.scheduler.add_job(
            run_activity_scheduler_job,
            trigger=CronTrigger(day_of_week='sun', hour=18, minute=0, timezone='UTC'),
            id='activity_scheduler',
            name='Weekly Activity Scheduler',
            kwargs={'db': self.db, 'telegram_bot': self.telegram_bot},
            replace_existing=True,
            misfire_grace_time=3600  # 1 hour grace period
        )
        
        # Research Cycle (Module 15) - Monday 00:00 UTC
        self.scheduler.add_job(
            run_research_cycle_job,
            trigger=CronTrigger(day_of_week='mon', hour=0, minute=0, timezone='UTC'),
            id='research_cycle',
            name='Weekly Research Cycle',
            kwargs={'db': self.db, 'telegram_bot': self.telegram_bot},
            replace_existing=True,
            misfire_grace_time=3600
        )
        
        # Airdrop Scanner (Module 17) - Every 6 hours
        self.scheduler.add_job(
            run_airdrop_scan_job,
            trigger=IntervalTrigger(hours=6, timezone='UTC'),
            id='airdrop_scanner',
            name='Airdrop Scanner (6h)',
            kwargs={'db': self.db, 'telegram_bot': self.telegram_bot},
            replace_existing=True,
            misfire_grace_time=1800  # 30 min grace
        )
        
        # Withdrawal Processor (Module 19) - Every 6 hours
        self.scheduler.add_job(
            run_withdrawal_processor_job,
            trigger=IntervalTrigger(hours=6, timezone='UTC'),
            id='withdrawal_processor',
            name='Withdrawal Processor (6h)',
            kwargs={'db': self.db, 'telegram_bot': self.telegram_bot},
            replace_existing=True,
            misfire_grace_time=1800
        )
        
        # Direct Funding Withdrawals (v3.0 - Module 7) - Every 1 hour
        self.scheduler.add_job(
            run_direct_funding_withdrawals_job,
            trigger=IntervalTrigger(hours=1, timezone='UTC'),
            id='direct_funding_withdrawals',
            name='Direct CEX Withdrawals (1h)',
            kwargs={'db': self.db, 'telegram_bot': self.telegram_bot},
            replace_existing=True,
            misfire_grace_time=1800  # 30 min grace
        )
        
        # Cleanup Jobs (stale protocols, old logs) - Sunday 02:00 UTC
        self.scheduler.add_job(
            run_cleanup_jobs,
            trigger=CronTrigger(day_of_week='sun', hour=2, minute=0, timezone='UTC'),
            id='cleanup_jobs',
            name='Weekly Cleanup Jobs',
            kwargs={'db': self.db},
            replace_existing=True,
            misfire_grace_time=7200  # 2 hour grace
        )
        
        logger.success("All jobs registered with APScheduler")
    
    def _log_next_jobs(self):
        """Log next scheduled execution times for all jobs."""
        jobs = self.scheduler.get_jobs()
        
        logger.info("Next scheduled jobs:")
        for job in jobs:
            next_run = job.next_run_time
            logger.info(
                f"  • {job.name}: {next_run.strftime('%Y-%m-%d %H:%M UTC') if next_run else 'N/A'}"
            )
    
    async def shutdown(self):
        """
        Gracefully shutdown all system components.
        
        Shutdown sequence:
        1. Stop APScheduler (wait for running jobs)
        2. Shutdown Health Check threads
        3. Shutdown Telegram Bot thread
        4. Close database connection pool
        5. Log shutdown complete
        
        Note:
        - Waits for running jobs to complete (no interruption)
        - Always sets shutdown event (even on error)
        """
        
        logger.warning("Initiating graceful shutdown...")
        
        try:
            # 1. Stop APScheduler
            if self.scheduler and self.scheduler.running:
                logger.info("Stopping APScheduler...")
                self.scheduler.shutdown(wait=True)  # Wait for jobs to finish
                logger.success("APScheduler stopped")
            
            # 2. Shutdown Health Check
            if self.health_check:
                logger.info("Stopping Health Check System...")
                # Health check uses daemon threads → auto-cleanup
                logger.success("Health Check System stopped")
            
            # 3. Shutdown Telegram Bot
            if self.telegram_bot:
                logger.info("Stopping Telegram Bot...")
                self.telegram_bot.stop()
                logger.success("Telegram Bot stopped")
            
            # 4. Close database pool
            if self.db:
                logger.info("Closing database connection pool...")
                self.db.close()
                logger.success("Database connections closed")
            
            logger.success("Graceful shutdown complete")
            
        except Exception as e:
            logger.exception(f"Error during shutdown: {e}")
        
        finally:
            # Signal event loop to exit
            self._shutdown_event.set()
    
    async def check_safety_gates(self) -> bool:
        """
        Check if all safety gates are passed for mainnet operations.
        
        Returns:
            True if safety gates passed or not in mainnet mode, False otherwise
        
        Raises:
            None - fails safely by denying mainnet operations
        
        Security:
            Three-gate validation required for mainnet:
            - dry_run_validation: Must complete dry-run first
            - testnet_validation: Must validate on testnet
            - human_approval: Manual approval required
        """
        if not is_mainnet():
            return True  # No gates needed for dry-run/testnet
        
        try:
            gates_passed = await self.network_mode.check_mainnet_allowed(self.db)
            
            if not gates_passed:
                logger.error("❌ MAINNET BLOCKED: Safety gates not passed")
                logger.error("   Required gates: dry_run_validation, testnet_validation, human_approval")
                
                # Send Telegram alert
                if self.telegram_bot:
                    await self.telegram_bot.send_critical_alert(
                        "🚫 MAINNET OPERATION BLOCKED\n"
                        "Safety gates not passed. Run validation first:\n"
                        "1. DRY_RUN validation\n"
                        "2. TESTNET validation\n"
                        "3. Human approval"
                    )
                return False
            
            logger.info("✅ Safety gates passed - mainnet operations allowed")
            return True
            
        except Exception as e:
            logger.error(f"Error checking safety gates: {e}")
            return False  # Fail-safe: deny mainnet on error
    
    def get_system_status(self) -> dict:
        """
        Get current system status including network mode.
        
        Returns:
            Dictionary with system status information
        """
        return {
            'orchestrator_running': self.scheduler.running if self.scheduler else False,
            'database_connected': self.db is not None,
            'health_check_active': self.health_check is not None,
            'telegram_bot_active': self.telegram_bot is not None,
            'network_mode': self.network_mode.get_mode().value,
            'is_dry_run': is_dry_run(),
            'is_testnet': is_testnet(),
            'is_mainnet': is_mainnet()
        }


def check_withdrawal_readiness(wallet_id: int, db: DatabaseManager) -> bool:
    """
    Check if wallet is ready for withdrawal (T + 10 days after whitelisting).
    
    Args:
        wallet_id: Wallet database ID
        db: DatabaseManager instance
    
    Returns:
        True if wallet can perform withdrawals, False otherwise
    
    Security Policy:
        - CEX exchanges require whitelisted addresses to wait 10 days before first withdrawal
        - This prevents unauthorized access even if API keys are compromised
        - Enforced at database level + application level (double verification)
    
    Example:
        >>> check_withdrawal_readiness(wallet_id=1, db=db_manager)
        False  # If whitelisted < 10 days ago
    """
    from datetime import datetime, timezone, timedelta
    
    try:
        # Get wallet whitelisting date from database
        wallet = db.execute_query(
            "SELECT whitelisted_at FROM wallets WHERE id = %s",
            params=(wallet_id,),
            fetch='one'
        )
        
        if not wallet or not wallet.get('whitelisted_at'):
            logger.warning(f"Wallet {wallet_id} has no whitelisting date — withdrawal DENIED")
            return False
        
        whitelisted_at = wallet['whitelisted_at']
        if whitelisted_at.tzinfo is None:
            # Assume UTC if timezone-naive
            whitelisted_at = whitelisted_at.replace(tzinfo=timezone.utc)
        
        # Calculate days since whitelisting
        now = datetime.now(timezone.utc)
        days_elapsed = (now - whitelisted_at).total_seconds() / 86400  # seconds to days
        
        if days_elapsed >= WHITELISTING_HOLD_DAYS:
            logger.debug(
                f"Wallet {wallet_id} ready for withdrawal | "
                f"Whitelisted: {days_elapsed:.1f} days ago (>= {WHITELISTING_HOLD_DAYS} days)"
            )
            return True
        else:
            remaining_days = WHITELISTING_HOLD_DAYS - days_elapsed
            logger.warning(
                f"Wallet {wallet_id} NOT ready for withdrawal | "
                f"Whitelisted: {days_elapsed:.1f} days ago | "
                f"Remaining: {remaining_days:.1f} days"
            )
            return False
    
    except Exception as e:
        logger.error(f"Error checking withdrawal readiness for wallet {wallet_id}: {e}")
        return False  # Fail-safe: deny withdrawal on error


# CLI Interface
async def main():
    """
    Main entry point for Master Node Orchestrator.
    
    Parses command-line arguments and starts the orchestrator.
    
    Arguments:
        --config: Path to .env configuration file (default: /opt/farming/.env)
        --log-level: Logging level (DEBUG, INFO, WARNING, ERROR)
    
    Environment:
        Loads configuration from .env file
        Configures loguru for structured logging
    """
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Master Node Orchestrator — Airdrop Farming System v4.0'
    )
    parser.add_argument(
        '--config',
        default='/opt/farming/.env',
        help='Path to .env configuration file'
    )
    parser.add_argument(
        '--log-level',
        default='INFO',
        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
        help='Log level'
    )
    
    args = parser.parse_args()
    
    # Load environment
    load_dotenv(args.config)
    
    # Configure logging
    logger.remove()
    logger.add(
        sys.stderr,
        level=args.log_level,
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan> - <level>{message}</level>"
    )
    logger.add(
        "/opt/farming/logs/master_orchestrator.log",
        rotation="100 MB",
        retention="30 days",
        level=args.log_level
    )
    
    logger.info(f"Starting Master Node Orchestrator with config: {args.config}")
    
    # Start orchestrator
    orchestrator = MasterOrchestrator()
    await orchestrator.start()


if __name__ == "__main__":
    asyncio.run(main())