#!/usr/bin/env python3
"""
Transaction Types Module — Module 10
====================================
Transaction builders для различных типов on-chain активности

Types:
- SWAP: Token swaps через DEX (Uniswap, Curve, etc.)
- BRIDGE: Cross-chain transfers (Stargate, Across, etc.)
- STAKE: Staking protocols (Lido, Rocket Pool, etc.)
- LP: Liquidity provision (add/remove liquidity)
- NFT_MINT: NFT minting
- WRAP/UNWRAP: ETH ↔ WETH conversions
- APPROVE: ERC20 token approvals
- GOVERNANCE: On-chain voting

Features:
- Transaction parameter builders
- ABI encoding helpers
- Common DEX/protocol patterns
- Anti-Sybil amount randomization
- Slippage calculation
- Gas estimation helpers

Author: Airdrop Farming System v4.0
Created: 2026-02-25
"""

import os
import sys
import random
from typing import Dict, Any, Optional, List, Tuple
from decimal import Decimal
from pathlib import Path

# Добавить parent directory для импорта
sys.path.insert(0, str(Path(__file__).parent.parent))

from web3 import Web3
from eth_abi import encode
from loguru import logger


# =============================================================================
# COMMON ABIs (simplified versions)
# =============================================================================

# ERC20 standard
ERC20_ABI = [
    {
        "constant": False,
        "inputs": [
            {"name": "spender", "type": "address"},
            {"name": "amount", "type": "uint256"}
        ],
        "name": "approve",
        "outputs": [{"name": "", "type": "bool"}],
        "type": "function"
    },
    {
        "constant": True,
        "inputs": [{"name": "account", "type": "address"}],
        "name": "balanceOf",
        "outputs": [{"name": "", "type": "uint256"}],
        "type": "function"
    }
]

# WETH9 (Wrapped ETH)
WETH_ABI = [
    {
        "constant": False,
        "inputs": [],
        "name": "deposit",
        "outputs": [],
        "payable": True,
        "type": "function"
    },
    {
        "constant": False,
        "inputs": [{"name": "wad", "type": "uint256"}],
        "name": "withdraw",
        "outputs": [],
        "type": "function"
    }
]

# Uniswap V2 Router (simplified)
UNISWAP_V2_ROUTER_ABI = [
    {
        "constant": False,
        "inputs": [
            {"name": "amountOutMin", "type": "uint256"},
            {"name": "path", "type": "address[]"},
            {"name": "to", "type": "address"},
            {"name": "deadline", "type": "uint256"}
        ],
        "name": "swapExactETHForTokens",
        "outputs": [{"name": "amounts", "type": "uint256[]"}],
        "payable": True,
        "type": "function"
    },
    {
        "constant": False,
        "inputs": [
            {"name": "amountIn", "type": "uint256"},
            {"name": "amountOutMin", "type": "uint256"},
            {"name": "path", "type": "address[]"},
            {"name": "to", "type": "address"},
            {"name": "deadline", "type": "uint256"}
        ],
        "name": "swapExactTokensForETH",
        "outputs": [{"name": "amounts", "type": "uint256[]"}],
        "type": "function"
    }
]


# =============================================================================
# TRANSACTION BUILDERS
# =============================================================================

class TransactionBuilder:
    """
    Base class для transaction builders.
    
    Все builders наследуют от этого класса и реализуют build() метод.
    """
    
    def __init__(self, w3: Web3):
        """
        Initialize builder.
        
        Args:
            w3: Web3 instance
        """
        self.w3 = w3
    
    def add_amount_noise(
        self,
        base_amount: int,
        noise_percent: float = 0.08
    ) -> int:
        """
        Add random noise to amount (Anti-Sybil).
        
        Uses Gaussian distribution instead of uniform for better anti-Sybil protection.
        
        Args:
            base_amount: Base amount in wei
            noise_percent: Noise percentage (default 8% = std deviation)
        
        Returns:
            Amount with noise
        
        Example:
            >>> builder.add_amount_noise(1000000, 0.08)
            1067234  # +6.7% Gaussian noise
        """
        import numpy as np
        
        # Gaussian noise: mean=0, std=noise_percent
        # 95% of values within ±1.96*std (±15.7% for std=0.08)
        noise = np.random.normal(0, noise_percent)
        
        # Clip to ±25% to avoid extreme values
        noise = max(-0.25, min(0.25, noise))
        
        noisy_amount = int(base_amount * (1 + noise))
        
        logger.debug(
            f"Amount noise added | Base: {base_amount} | "
            f"Noise: {noise*100:.1f}% | Result: {noisy_amount}"
        )
        
        return noisy_amount
    
    def calculate_min_amount_out(
        self,
        amount_in: int,
        slippage_percent: float
    ) -> int:
        """
        Calculate minimum output amount with slippage.
        
        Args:
            amount_in: Input amount
            slippage_percent: Slippage tolerance (0.5 = 0.5%)
        
        Returns:
            Minimum output amount
        
        Example:
            >>> builder.calculate_min_amount_out(1000000, 0.5)
            995000  # -0.5% slippage
        """
        min_out = int(amount_in * (1 - slippage_percent / 100))
        
        logger.debug(
            f"Min amount calculated | In: {amount_in} | "
            f"Slippage: {slippage_percent}% | Min out: {min_out}"
        )
        
        return min_out
    
    def get_deadline(self, minutes: int = 20) -> int:
        """
        Get transaction deadline (current timestamp + minutes).
        
        Args:
            minutes: Minutes from now (default 20)
        
        Returns:
            Unix timestamp
        """
        import time
        deadline = int(time.time()) + (minutes * 60)
        return deadline


class SwapBuilder(TransactionBuilder):
    """Builder для DEX swaps (ETH ↔ tokens)."""
    
    def build_swap_eth_for_tokens(
        self,
        router_address: str,
        amount_eth_wei: int,
        token_out_address: str,
        recipient: str,
        slippage_percent: float = 0.5,
        add_noise: bool = True
    ) -> Dict[str, Any]:
        """
        Build swap ETH → Token transaction.
        
        Args:
            router_address: DEX router contract address
            amount_eth_wei: ETH amount to swap (wei)
            token_out_address: Output token address
            recipient: Recipient address
            slippage_percent: Slippage tolerance
            add_noise: Add amount randomization
        
        Returns:
            Transaction dict for executor
        """
        # Add noise to amount if enabled
        if add_noise:
            amount_eth_wei = self.add_amount_noise(amount_eth_wei)
        
        # Build path: WETH → Token
        weth_address = self._get_weth_address()
        path = [weth_address, token_out_address]
        
        # Calculate minimum output (requires price oracle in production)
        # Simplified: assume 1:1 ratio, apply slippage
        amount_out_min = self.calculate_min_amount_out(amount_eth_wei, slippage_percent)
        
        # Get deadline
        deadline = self.get_deadline(20)
        
        # Build contract instance
        router = self.w3.eth.contract(
            address=Web3.to_checksum_address(router_address),
            abi=UNISWAP_V2_ROUTER_ABI
        )
        
        # Encode function call
        try:
            function_call = router.functions.swapExactETHForTokens(
                amount_out_min,
                path,
                Web3.to_checksum_address(recipient),
                deadline
            )
            
            transaction = function_call.build_transaction({
                'from': recipient,  # Will be overridden by executor
                'value': amount_eth_wei,
                'gas': 0,  # Will be estimated by executor
                'nonce': 0  # Will be set by executor
            })
            
            logger.info(
                f"Swap ETH→Token built | Amount: {self.w3.from_wei(amount_eth_wei, 'ether')} ETH | "
                f"Token: {token_out_address[:10]}... | Slippage: {slippage_percent}%"
            )
            
            return {
                'to': router_address,
                'value': amount_eth_wei,
                'data': transaction['data'],
                'type': 'SWAP'
            }
        
        except Exception as e:
            logger.error(f"Swap build failed | Error: {e}")
            raise
    
    def build_swap_tokens_for_eth(
        self,
        router_address: str,
        token_in_address: str,
        amount_token_wei: int,
        recipient: str,
        slippage_percent: float = 0.5,
        add_noise: bool = True
    ) -> Dict[str, Any]:
        """
        Build swap Token → ETH transaction.
        
        Args:
            router_address: DEX router contract address
            token_in_address: Input token address
            amount_token_wei: Token amount to swap
            recipient: Recipient address
            slippage_percent: Slippage tolerance
            add_noise: Add amount randomization
        
        Returns:
            Transaction dict
        """
        if add_noise:
            amount_token_wei = self.add_amount_noise(amount_token_wei)
        
        weth_address = self._get_weth_address()
        path = [token_in_address, weth_address]
        
        amount_eth_min = self.calculate_min_amount_out(amount_token_wei, slippage_percent)
        deadline = self.get_deadline(20)
        
        router = self.w3.eth.contract(
            address=Web3.to_checksum_address(router_address),
            abi=UNISWAP_V2_ROUTER_ABI
        )
        
        try:
            function_call = router.functions.swapExactTokensForETH(
                amount_token_wei,
                amount_eth_min,
                path,
                Web3.to_checksum_address(recipient),
                deadline
            )
            
            transaction = function_call.build_transaction({
                'from': recipient,
                'value': 0,
                'gas': 0,
                'nonce': 0
            })
            
            logger.info(
                f"Swap Token→ETH built | Amount: {amount_token_wei} | "
                f"Token: {token_in_address[:10]}... | Slippage: {slippage_percent}%"
            )
            
            return {
                'to': router_address,
                'value': 0,
                'data': transaction['data'],
                'type': 'SWAP'
            }
        
        except Exception as e:
            logger.error(f"Swap build failed | Error: {e}")
            raise
    
    def _get_weth_address(self) -> str:
        """
        Get WETH address for current chain from database.
        
        Returns:
            WETH contract address
        """
        chain_id = self.w3.eth.chain_id
        
        try:
            from database.db_manager import DatabaseManager
            db = DatabaseManager()
            
            token = db.execute_query(
                "SELECT token_address FROM chain_tokens WHERE chain_id = %s AND is_native_wrapped = TRUE",
                (chain_id,),
                fetch='one'
            )
            
            if token:
                logger.debug(f"WETH address loaded from DB | Chain: {chain_id} | Address: {token['token_address'][:10]}...")
                return token['token_address']
        except Exception as e:
            logger.warning(f"Failed to load WETH address from DB: {e}")
        
        # Fallback to hardcoded values
        WETH_ADDRESSES = {
            1: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',  # Ethereum
            42161: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',  # Arbitrum
            8453: '0x4200000000000000000000000000000000000006',  # Base
            10: '0x4200000000000000000000000000000000000006',  # Optimism
            137: '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270',  # Polygon (WMATIC)
            56: '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c',  # BNB Chain (WBNB)
            57073: '0x4200000000000000000000000000000000000006',  # Ink (WETH)
            1088: '0x4200000000000000000000000000000000000006'   # MegaETH (WETH)
        }
        
        logger.warning(f"Using fallback WETH address | Chain: {chain_id}")
        return WETH_ADDRESSES.get(chain_id, WETH_ADDRESSES[1])  # Fallback to ETH mainnet


class WrapBuilder(TransactionBuilder):
    """Builder для WRAP/UNWRAP (ETH ↔ WETH)."""
    
    def build_wrap_eth(
        self,
        weth_address: str,
        amount_wei: int,
        add_noise: bool = True
    ) -> Dict[str, Any]:
        """
        Build WRAP transaction (ETH → WETH).
        
        Args:
            weth_address: WETH contract address
            amount_wei: ETH amount to wrap
            add_noise: Add amount randomization
        
        Returns:
            Transaction dict
        """
        if add_noise:
            amount_wei = self.add_amount_noise(amount_wei)
        
        weth = self.w3.eth.contract(
            address=Web3.to_checksum_address(weth_address),
            abi=WETH_ABI
        )
        
        try:
            function_call = weth.functions.deposit()
            
            transaction = function_call.build_transaction({
                'from': '0x0000000000000000000000000000000000000000',  # Placeholder
                'value': amount_wei,
                'gas': 0,
                'nonce': 0
            })
            
            logger.info(f"WRAP built | Amount: {self.w3.from_wei(amount_wei, 'ether')} ETH")
            
            return {
                'to': weth_address,
                'value': amount_wei,
                'data': transaction['data'],
                'type': 'WRAP'
            }
        
        except Exception as e:
            logger.error(f"WRAP build failed | Error: {e}")
            raise
    
    def build_unwrap_weth(
        self,
        weth_address: str,
        amount_wei: int,
        add_noise: bool = True
    ) -> Dict[str, Any]:
        """
        Build UNWRAP transaction (WETH → ETH).
        
        Args:
            weth_address: WETH contract address
            amount_wei: WETH amount to unwrap
            add_noise: Add amount randomization
        
        Returns:
            Transaction dict
        """
        if add_noise:
            amount_wei = self.add_amount_noise(amount_wei)
        
        weth = self.w3.eth.contract(
            address=Web3.to_checksum_address(weth_address),
            abi=WETH_ABI
        )
        
        try:
            function_call = weth.functions.withdraw(amount_wei)
            
            transaction = function_call.build_transaction({
                'from': '0x0000000000000000000000000000000000000000',
                'value': 0,
                'gas': 0,
                'nonce': 0
            })
            
            logger.info(f"UNWRAP built | Amount: {self.w3.from_wei(amount_wei, 'ether')} WETH")
            
            return {
                'to': weth_address,
                'value': 0,
                'data': transaction['data'],
                'type': 'WRAP'
            }
        
        except Exception as e:
            logger.error(f"UNWRAP build failed | Error: {e}")
            raise


class ApproveBuilder(TransactionBuilder):
    """Builder для ERC20 approvals."""
    
    def build_approve(
        self,
        token_address: str,
        spender_address: str,
        amount: Optional[int] = None
    ) -> Dict[str, Any]:
        """
        Build ERC20 approval transaction.
        
        Args:
            token_address: Token contract address
            spender_address: Spender address (router, protocol, etc.)
            amount: Amount to approve (None = infinite approval)
        
        Returns:
            Transaction dict
        """
        # Infinite approval if amount not specified
        if amount is None:
            amount = 2**256 - 1  # Max uint256
        
        token = self.w3.eth.contract(
            address=Web3.to_checksum_address(token_address),
            abi=ERC20_ABI
        )
        
        try:
            function_call = token.functions.approve(
                Web3.to_checksum_address(spender_address),
                amount
            )
            
            transaction = function_call.build_transaction({
                'from': '0x0000000000000000000000000000000000000000',
                'value': 0,
                'gas': 0,
                'nonce': 0
            })
            
            approval_type = 'infinite' if amount == 2**256 - 1 else f'{amount} wei'
            
            logger.info(
                f"APPROVE built | Token: {token_address[:10]}... | "
                f"Spender: {spender_address[:10]}... | Amount: {approval_type}"
            )
            
            return {
                'to': token_address,
                'value': 0,
                'data': transaction['data'],
                'type': 'APPROVE'
            }
        
        except Exception as e:
            logger.error(f"APPROVE build failed | Error: {e}")
            raise


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def get_builder(tx_type: str, w3: Web3) -> TransactionBuilder:
    """
    Get transaction builder для указанного типа.
    
    Args:
        tx_type: Transaction type ('SWAP', 'WRAP', 'APPROVE', etc.)
        w3: Web3 instance
    
    Returns:
        Appropriate builder instance
    
    Raises:
        ValueError: If tx_type not supported
    """
    builders = {
        'SWAP': SwapBuilder,
        'WRAP': WrapBuilder,
        'APPROVE': ApproveBuilder
    }
    
    builder_class = builders.get(tx_type.upper())
    
    if not builder_class:
        raise ValueError(
            f"Unsupported transaction type: {tx_type}. "
            f"Supported: {', '.join(builders.keys())}"
        )
    
    return builder_class(w3)


def randomize_percentage(
    base_value: float,
    noise_percent: float = 0.08
) -> float:
    """
    Add random noise to percentage value (Anti-Sybil Gaussian).
    
    Uses Gaussian distribution instead of uniform for better anti-Sybil protection.
    
    Args:
        base_value: Base percentage (e.g., 0.5 for 0.5%)
        noise_percent: Noise std deviation (default 8%)
    
    Returns:
        Randomized percentage
    
    Example:
        >>> randomize_percentage(0.5, 0.08)
        0.54  # 0.5% + 8% Gaussian noise
    """
    import numpy as np
    
    # Gaussian noise: mean=0, std=noise_percent
    noise = np.random.normal(0, noise_percent)
    
    # Clip to ±25% to avoid extreme values
    noise = max(-0.25, min(0.25, noise))
    
    return base_value * (1 + noise)


# =============================================================================
# CLI INTERFACE (для тестирования)
# =============================================================================

def main():
    """CLI entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Transaction Types Module 10')
    parser.add_argument('--test', action='store_true', help='Run builder tests')
    
    args = parser.parse_args()
    
    if args.test:
        # Example: Test builders
        from web3 import Web3
        from database.db_manager import DatabaseManager
        
        # Connect to Arbitrum (example) - uses RPC from database
        db = DatabaseManager()
        rpc_result = db.get_chain_by_name('arbitrum')
        
        if not rpc_result:
            print("ERROR: No Arbitrum RPC configured in database")
            print("Please add an RPC endpoint to chain_rpc_endpoints table first")
            sys.exit(1)
        
        print(f"Connected to Arbitrum via: {rpc_result['url'][:50]}...")
        w3 = Web3(Web3.HTTPProvider(rpc_result['url']))
        
        if not w3.is_connected():
            print(f"ERROR: Failed to connect to RPC: {rpc_result['url']}")
            sys.exit(1)
        
        # Test SwapBuilder
        swap_builder = SwapBuilder(w3)
        
        tx = swap_builder.build_swap_eth_for_tokens(
            router_address='0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506',  # Sushiswap Arbitrum
            amount_eth_wei=w3.to_wei(0.01, 'ether'),
            token_out_address='0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',  # USDC Arbitrum
            recipient='0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb',  # Example
            slippage_percent=0.5
        )
        
        print(f"\n✅ Swap transaction built:")
        print(f"   To: {tx['to']}")
        print(f"   Value: {w3.from_wei(tx['value'], 'ether')} ETH")
        print(f"   Data: {tx['data'][:66]}...")
        print(f"   Type: {tx['type']}")
        
        # Test WrapBuilder
        wrap_builder = WrapBuilder(w3)
        
        wrap_tx = wrap_builder.build_wrap_eth(
            weth_address='0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',  # WETH Arbitrum
            amount_wei=w3.to_wei(0.005, 'ether')
        )
        
        print(f"\n✅ WRAP transaction built:")
        print(f"   To: {wrap_tx['to']}")
        print(f"   Value: {w3.from_wei(wrap_tx['value'], 'ether')} ETH")
        print(f"   Type: {wrap_tx['type']}")
    
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
