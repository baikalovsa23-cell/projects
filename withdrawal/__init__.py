"""
Withdrawal Module — Module 19
=============================

Withdrawal Orchestrator for safe fund extraction with human-in-the-loop approval.

Features:
- Tier-specific withdrawal strategies (A: 4 steps, B: 3, C: 2)
- Temporal isolation with Gaussian distribution
- Telegram approval workflow
- Safety checks (balance, gas, network)
- Dry-run mode for testing

Usage:
    from withdrawal import WithdrawalOrchestrator
    
    orchestrator = WithdrawalOrchestrator(db_manager, telegram_bot)
    plan_id = orchestrator.create_withdrawal_plan(
        wallet_id=42,
        destination_address='0xYOUR_COLD_WALLET'
    )

Author: Airdrop Farming System v4.0
Created: 2026-02-26
"""

from withdrawal.orchestrator import WithdrawalOrchestrator
from withdrawal.strategies import TierStrategy, get_all_strategies
from withdrawal.validator import WithdrawalValidator

__all__ = [
    'WithdrawalOrchestrator',
    'TierStrategy', 
    'get_all_strategies',
    'WithdrawalValidator'
]

__version__ = '1.0.0'
__module__ = 'withdrawal'
__description__ = 'Withdrawal Orchestrator with human-in-the-loop approval'

# Module metadata
METADATA = {
    'module_id': 19,
    'name': 'Withdrawal Orchestrator',
    'tier_strategies': {
        'A': {'steps': 4, 'percentages': [15, 25, 30, 30], 'delay_days': '30-60'},
        'B': {'steps': 3, 'percentages': [20, 40, 40], 'delay_days': '21-45'},
        'C': {'steps': 2, 'percentages': [50, 50], 'delay_days': '14-30'}
    },
    'features': [
        'Human-in-the-loop approval via Telegram',
        'Tier-specific withdrawal strategies',
        'Temporal isolation with Gaussian distribution',
        'Safety checks (balance, gas, network)',
        'Dry-run mode for testing',
        'Audit trail in database and logs'
    ],
    'dependencies': [
        'database.db_manager',
        'notifications.telegram_bot',
        'worker.api'
    ]
}