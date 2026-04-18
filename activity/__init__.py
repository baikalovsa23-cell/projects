"""
Activity Module — Модули 9-13
==============================
Планирование и выполнение транзакций для 90 кошельков

Модули:
    - scheduler.py (Модуль 11): Gaussian-планировщик транзакций
    - tx_types.py (Модуль 10): Transaction builders (SWAP, WRAP, APPROVE, etc.)
    - executor.py (Модуль 12): TransactionExecutor для on-chain TX через web3.py
    - adaptive.py (Модуль 13): Unified Adaptive Gas Controller (gas + balance management)

Consolidated from:
    - infrastructure/gas_logic.py (DEPRECATED)
    - infrastructure/gas_controller.py (DEPRECATED)
    - infrastructure/gas_manager.py (DEPRECATED)

Author: Airdrop Farming System v4.0
"""

__version__ = '0.8.0'
__all__ = [
    # Main classes
    'ActivityScheduler',
    'TransactionExecutor',
    'AdaptiveGasController',
    
    # Backward compatibility aliases
    'GasManager',           # Alias for AdaptiveGasController
    'GasBalanceController', # Alias for AdaptiveGasController
    'GasLogic',             # Alias for AdaptiveGasController
    
    # Enums
    'GasStatus',
    'NetworkType',
    
    # Data classes
    'GasCheckResult',
    'GasSnapshot',
    'GasAnalysis',
    'NetworkDescriptor',
    
    # Transaction builders
    'SwapBuilder',
    'WrapBuilder',
    'ApproveBuilder',
    'get_builder',
    
    # Configuration
    'TIER_THRESHOLDS',
    'GAS_THRESHOLDS',
    'GAS_THRESHOLDS_BY_CHAIN',
    'DEFAULT_MULTIPLIERS',
    
    # Convenience functions
    'check_chain_gas'
]

from .scheduler import ActivityScheduler
from .executor import TransactionExecutor
from .adaptive import (
    # Main class
    AdaptiveGasController,
    
    # Backward compatibility aliases
    GasManager,
    GasBalanceController,
    GasLogic,
    
    # Enums
    GasStatus,
    NetworkType,
    
    # Data classes
    GasCheckResult,
    GasSnapshot,
    GasAnalysis,
    NetworkDescriptor,
    
    # Configuration
    TIER_THRESHOLDS,
    GAS_THRESHOLDS,
    GAS_THRESHOLDS_BY_CHAIN,
    DEFAULT_MULTIPLIERS,
    
    # Convenience functions
    check_chain_gas
)
from .tx_types import SwapBuilder, WrapBuilder, ApproveBuilder, get_builder
