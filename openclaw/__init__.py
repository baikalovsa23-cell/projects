"""
OpenClaw Integration Module
=============================

Browser automation module для Tier A кошельков (18 wallets).

Архитектура:
- manager.py: Runs on Master Node (планирование задач, NO browser)
- executor.py: Runs on Worker Nodes (browser automation, выполнение задач)

Задачи:
- Gitcoin Passport: 5+ stamps (GitHub, Twitter, Discord, etc.)
- POAP Claiming: 3-5 tokens per wallet
- ENS Registration: FREE cb.id or base.eth subdomains
- Snapshot Voting: 5-10 proposals per wallet
- Lens Protocol: Profile + 2-3 posts per wallet

Temporal Isolation:
- 60-240 minutes между задачами (1-4 hours)
- 25% шанс длинной паузы (5-10 hours)
- КРИТИЧНО для anti-Sybil в L2 сетях 2026 года

Usage (Master Node):
    from openclaw.manager import OpenClawOrchestrator
    from database.db_manager import DatabaseManager
    
    db = DatabaseManager()
    orchestrator = OpenClawOrchestrator(db)
    
    # Schedule Gitcoin Passport для всех Tier A wallets
    tier_a_wallets = db.query("SELECT * FROM wallets WHERE tier = 'A'")
    orchestrator.schedule_gitcoin_passport_batch(tier_a_wallets)
    
    # Assign tasks to workers
    orchestrator.assign_tasks_to_workers()

Usage (Worker Node):
    from openclaw.executor import OpenClawExecutor
    from database.db_manager import DatabaseManager
    import asyncio
    
    db = DatabaseManager()
    executor = OpenClawExecutor(worker_id=1, db_manager=db)
    
    # Start polling loop (runs forever)
    asyncio.run(executor.start_polling())
"""

__version__ = "1.0.0"
__author__ = "Airdrop Farming System v4.0"

from .manager import OpenClawOrchestrator
from .executor import OpenClawExecutor

__all__ = [
    'OpenClawOrchestrator',
    'OpenClawExecutor',
]
