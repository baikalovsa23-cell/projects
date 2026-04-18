#!/usr/bin/env python3
"""
Network Mode Manager — Testnet/Dry-Run Infrastructure
======================================================
Manages execution mode (DRY_RUN, TESTNET, MAINNET) and safety gates.

Features:
- NetworkMode enum (DRY_RUN, TESTNET, MAINNET)
- Singleton NetworkModeManager for global access
- Safety gate enforcement for mainnet
- Chain configuration per mode (Sepolia vs production RPCs)
- Mode restriction decorators

Author: Airdrop Farming System v4.0
Created: 2026-02-27
"""

import os
from enum import Enum
from typing import Dict, List, Optional, Callable, Any
from functools import wraps
from decimal import Decimal

from loguru import logger
from infrastructure.env_loader import load_env

# Load .env file (supports both production and local dev)
load_env()


class NetworkMode(Enum):
    """Execution modes for the airdrop farming system."""
    DRY_RUN = "dry_run"      # Simulation only, no actual transactions
    TESTNET = "testnet"       # Sepolia testnet transactions
    MAINNET = "mainnet"       # Production L2 chains (requires safety gates)


# Sepolia Testnet Configuration
SEPOLIA_CONFIG = {
    'chain_id': 11155111,
    'chain_name': 'sepolia',
    'native_token': 'ETH',
    'rpc_urls': [
        'https://eth-sepolia.g.alchemy.com/v2/demo',
        'https://rpc.sepolia.org',
        'https://ethereum-sepolia.publicnode.com',
        'https://rpc2.sepolia.org'
    ],
    'block_explorer': 'https://sepolia.etherscan.io',
    'faucets': [
        'https://faucet.sepolia.dev',
        'https://sepoliafaucet.com',
        'https://sepolia-faucet.pk910.de'
    ],
    'test_tokens': {
        'USDC': '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',  # Sepolia USDC (example)
        'USDT': '0x7169D38820dfd117C3FA1f22a697dBA58d90BA06',  # Sepolia USDT (example)
    }
}

# Mock configuration for dry-run mode
DRY_RUN_CONFIG = {
    'chain_id': 999999,
    'chain_name': 'dry_run',
    'native_token': 'ETH',
    'rpc_urls': ['mock://localhost'],
    'block_explorer': 'mock://explorer',
    'faucets': []
}


class MainnetBlockedError(Exception):
    """Raised when mainnet execution is attempted without safety gate approval."""
    pass


class NetworkModeManager:
    """
    Singleton manager for network mode configuration.
    
    Features:
    - Read mode from NETWORK_MODE environment variable
    - Provide mode check helpers (is_dry_run, is_testnet, is_mainnet)
    - Enforce safety gates for mainnet execution
    - Return appropriate chain configs per mode
    
    Usage:
        mode_manager = NetworkModeManager()
        if mode_manager.is_dry_run():
            # Simulate transaction
        elif mode_manager.is_mainnet():
            # Check safety gates first
            mode_manager.check_mainnet_allowed(db)
    """
    
    _instance = None
    _initialized = False
    
    def __new__(cls):
        """Singleton pattern: ensure only one instance exists."""
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    def __init__(self):
        """Initialize network mode manager."""
        if self._initialized:
            return
        
        # Read mode from environment variable
        mode_str = os.getenv('NETWORK_MODE', 'DRY_RUN').upper()
        
        # Parse mode
        try:
            if mode_str == 'DRY_RUN':
                self.mode = NetworkMode.DRY_RUN
            elif mode_str == 'TESTNET':
                self.mode = NetworkMode.TESTNET
            elif mode_str == 'MAINNET':
                self.mode = NetworkMode.MAINNET
            else:
                logger.warning(f"Unknown NETWORK_MODE: {mode_str}, defaulting to DRY_RUN")
                self.mode = NetworkMode.DRY_RUN
        except Exception as e:
            logger.error(f"Failed to parse NETWORK_MODE: {e}, defaulting to DRY_RUN")
            self.mode = NetworkMode.DRY_RUN
        
        logger.info(f"NetworkModeManager initialized | Mode: {self.mode.value.upper()}")
        self._initialized = True
    
    def get_mode(self) -> NetworkMode:
        """
        Get current network mode.
        
        Returns:
            NetworkMode enum value
        """
        return self.mode
    
    def is_dry_run(self) -> bool:
        """Check if in dry-run mode."""
        return self.mode == NetworkMode.DRY_RUN
    
    def is_testnet(self) -> bool:
        """Check if in testnet mode."""
        return self.mode == NetworkMode.TESTNET
    
    def is_mainnet(self) -> bool:
        """Check if in mainnet mode."""
        return self.mode == NetworkMode.MAINNET
    
    def check_mainnet_allowed(self, db_manager) -> bool:
        """
        Check if mainnet execution is allowed based on safety gates.
        
        Query the safety_gates table:
        - All gates must be status = 'open' for mainnet to execute
        - If ANY gate is 'closed' → raise MainnetBlockedError
        
        Args:
            db_manager: DatabaseManager instance
        
        Returns:
            True if all gates are open
        
        Raises:
            MainnetBlockedError: If any safety gate is closed
        """
        if not self.is_mainnet():
            # Non-mainnet modes don't need safety gate checks
            return True
        
        logger.info("Checking mainnet safety gates...")
        
        # Query all safety gates
        query = """
            SELECT gate_name, is_open
            FROM safety_gates
            ORDER BY gate_name
        """
        
        gates = db_manager.execute_query(query, fetch='all')
        
        if not gates:
            logger.error("No safety gates found in database!")
            raise MainnetBlockedError(
                "Mainnet blocked: Safety gates table is empty. "
                "Run database migration 042_safety_gates_seed.sql first."
            )
        
        closed_gates = [g for g in gates if not g['is_open']]
        
        if closed_gates:
            gate_names = [g['gate_name'] for g in closed_gates]
            
            logger.error(
                f"Mainnet execution BLOCKED | Closed gates: {gate_names}"
            )
            
            raise MainnetBlockedError(
                f"Mainnet execution blocked. The following safety gates are closed: "
                f"{', '.join(gate_names)}. Open them before mainnet operations."
            )
        
        logger.success("All safety gates are OPEN | Mainnet execution allowed")
        return True
    
    def get_chain_config(self, chain_name: str, db_manager=None) -> Dict[str, Any]:
        """
        Get chain configuration based on current mode.
        
        Args:
            chain_name: Chain name (e.g., 'base', 'arbitrum', 'sepolia')
            db_manager: DatabaseManager instance (required for MAINNET mode)
        
        Returns:
            Chain configuration dict with keys:
            - chain_id: int
            - rpc_urls: List[str]
            - block_explorer: str
            - native_token: str
        
        Raises:
            ValueError: If chain config not found
        """
        if self.is_dry_run():
            # Return mock config for dry-run mode
            logger.debug(f"Returning mock config for chain: {chain_name}")
            mock_config = DRY_RUN_CONFIG.copy()
            mock_config['chain_name'] = chain_name
            return mock_config
        
        elif self.is_testnet():
            # Always return Sepolia config for testnet mode
            logger.debug(f"Returning Sepolia testnet config (requested: {chain_name})")
            return SEPOLIA_CONFIG.copy()
        
        elif self.is_mainnet():
            # Query production RPC endpoints from database
            if db_manager is None:
                raise ValueError("db_manager required for MAINNET mode chain config")
            
            logger.debug(f"Querying production RPC config for chain: {chain_name}")
            
            # Use db_manager method instead of direct SQL
            endpoints = db_manager.get_chain_rpc_endpoints(chain_name)
            
            if not endpoints:
                raise ValueError(f"No active RPC endpoints found for chain: {chain_name}")
            
            # All endpoints use 'url' column (http/wss URLs are mixed in the table)
            # Note: The table doesn't have rpc_type column, so we include all URLs
            rpc_urls = [e['url'] for e in endpoints]
            
            config = {
                'chain_name': chain_name,
                'chain_id': endpoints[0]['chain_id'],
                'rpc_urls': rpc_urls,
                'native_token': 'ETH'  # All L2s use ETH as native token
            }
            
            logger.info(
                f"Loaded mainnet config | Chain: {chain_name} | "
                f"Chain ID: {config['chain_id']} | RPCs: {len(rpc_urls)}"
            )
            
            return config
        
        else:
            raise ValueError(f"Unknown network mode: {self.mode}")


def require_mode(allowed_modes: List[NetworkMode]) -> Callable:
    """
    Decorator to restrict function execution to specific network modes.
    
    Args:
        allowed_modes: List of NetworkMode values that are allowed
    
    Raises:
        RuntimeError: If current mode is not in allowed_modes
    
    Example:
        @require_mode([NetworkMode.DRY_RUN, NetworkMode.TESTNET])
        def test_transaction():
            # This function can only run in DRY_RUN or TESTNET mode
            pass
        
        @require_mode([NetworkMode.MAINNET])
        def production_withdrawal():
            # This function ONLY runs in MAINNET mode
            pass
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            mode_manager = NetworkModeManager()
            current_mode = mode_manager.get_mode()
            
            if current_mode not in allowed_modes:
                allowed_names = [m.value for m in allowed_modes]
                raise RuntimeError(
                    f"Function {func.__name__} requires mode in {allowed_names}, "
                    f"but current mode is {current_mode.value}"
                )
            
            logger.debug(
                f"Mode check passed | Function: {func.__name__} | "
                f"Mode: {current_mode.value}"
            )
            
            return func(*args, **kwargs)
        
        return wrapper
    return decorator


# Global singleton instance
network_mode_manager = NetworkModeManager()


# Convenience functions for quick mode checks
def is_dry_run() -> bool:
    """Quick check if in dry-run mode."""
    return network_mode_manager.is_dry_run()


def is_testnet() -> bool:
    """Quick check if in testnet mode."""
    return network_mode_manager.is_testnet()


def is_mainnet() -> bool:
    """Quick check if in mainnet mode."""
    return network_mode_manager.is_mainnet()


if __name__ == '__main__':
    # Test mode detection
    logger.info("=== Network Mode Manager Test ===")
    
    manager = NetworkModeManager()
    
    logger.info(f"Current mode: {manager.get_mode().value}")
    logger.info(f"Is dry-run: {manager.is_dry_run()}")
    logger.info(f"Is testnet: {manager.is_testnet()}")
    logger.info(f"Is mainnet: {manager.is_mainnet()}")
    
    # Test chain config (mock)
    if manager.is_dry_run():
        config = manager.get_chain_config('base')
        logger.info(f"Base config (dry-run): {config}")
    
    if manager.is_testnet():
        config = manager.get_chain_config('arbitrum')  # Will return Sepolia
        logger.info(f"Arbitrum config (testnet): {config}")
    
    logger.success("Network mode manager test complete")
