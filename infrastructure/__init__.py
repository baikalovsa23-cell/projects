"""Infrastructure utilities (gas controller, balance monitoring, identity management, network mode)"""

from infrastructure.identity_manager import (
    identity_manager,
    get_curl_session,
    get_async_curl_session
)

from infrastructure.network_mode import (
    NetworkMode,
    NetworkModeManager,
    network_mode_manager,
    require_mode,
    is_dry_run,
    is_testnet,
    is_mainnet,
    MainnetBlockedError,
    SEPOLIA_CONFIG
)

from infrastructure.simulator import (
    TransactionSimulator,
    SimulationResult,
    BalanceTracker
)

__all__ = [
    # Identity management
    'identity_manager',
    'get_curl_session',
    'get_async_curl_session',
    
    # Network mode
    'NetworkMode',
    'NetworkModeManager',
    'network_mode_manager',
    'require_mode',
    'is_dry_run',
    'is_testnet',
    'is_mainnet',
    'MainnetBlockedError',
    'SEPOLIA_CONFIG',
    
    # Transaction simulator
    'TransactionSimulator',
    'SimulationResult',
    'BalanceTracker',
]
