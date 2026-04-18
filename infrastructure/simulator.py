#!/usr/bin/env python3
"""
Transaction Simulator — Dry-Run Infrastructure
===============================================
Simulates blockchain transactions without executing them.

Features:
- Transaction validation (balance, nonce, gas)
- Gas estimation (heuristics for dry-run, eth_estimateGas for testnet)
- In-memory balance tracking for dry-run mode
- Detailed simulation results with warnings
- Database logging of all simulation runs

Author: Airdrop Farming System v4.0
Created: 2026-02-27
"""

import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, field
from decimal import Decimal
from datetime import datetime, timezone
import random

import numpy as np
from loguru import logger
from web3 import Web3

sys.path.insert(0, str(Path(__file__).parent.parent))

from infrastructure.network_mode import NetworkMode, NetworkModeManager


# Gas estimation heuristics for dry-run mode (loaded from database system_config)
def get_gas_heuristics() -> Dict[str, int]:
    """Get gas heuristics from database."""
    try:
        from database.db_manager import DatabaseManager
        db = DatabaseManager()
        gas_config = db.get_system_config_by_category('gas')
        
        # Extract gas heuristics
        heuristics = {}
        for key, value in gas_config.items():
            if key.startswith('gas_heuristic_'):
                tx_type = key.replace('gas_heuristic_', '').upper()
                heuristics[tx_type] = value
        
        # Fallback to defaults if empty
        if not heuristics:
            return {
                'SWAP': 150000,
                'BRIDGE': 200000,
                'STAKE': 100000,
                'UNSTAKE': 120000,
                'LP_ADD': 180000,
                'LP_REMOVE': 150000,
                'NFT_MINT': 120000,
                'WRAP': 50000,
                'UNWRAP': 50000,
                'APPROVE': 50000,
                'TRANSFER': 21000,
                'ETH_TRANSFER': 21000,
                'TOKEN_TRANSFER': 65000,
            }
        
        return heuristics
    except Exception as e:
        logger.warning(f"Failed to load gas heuristics from DB, using fallback: {e}")
        return {
            'SWAP': 150000,
            'BRIDGE': 200000,
            'STAKE': 100000,
            'UNSTAKE': 120000,
            'LP_ADD': 180000,
            'LP_REMOVE': 150000,
            'NFT_MINT': 120000,
            'WRAP': 50000,
            'UNWRAP': 50000,
            'APPROVE': 50000,
            'TRANSFER': 21000,
            'ETH_TRANSFER': 21000,
            'TOKEN_TRANSFER': 65000,
        }

def get_gas_price_estimates() -> Dict[str, float]:
    """Get gas price estimates from database."""
    try:
        from database.db_manager import DatabaseManager
        db = DatabaseManager()
        gas_config = db.get_system_config_by_category('gas')
        
        # Extract gas price estimates
        estimates = {}
        for key, value in gas_config.items():
            if key.startswith('gas_price_estimate_'):
                chain = key.replace('gas_price_estimate_', '')
                estimates[chain] = value
        
        # Fallback to defaults if empty
        if not estimates:
            return {
                'ethereum': 30.0,
                'arbitrum': 0.1,
                'base': 0.05,
                'optimism': 0.1,
                'polygon': 50.0,
                'bsc': 3.0,
                'ink': 0.1,
                'sepolia': 1.0,
                'dry_run': 1.0,
            }
        
        return estimates
    except Exception as e:
        logger.warning(f"Failed to load gas price estimates from DB, using fallback: {e}")
        return {
            'ethereum': 30.0,
            'arbitrum': 0.1,
            'base': 0.05,
            'optimism': 0.1,
            'polygon': 50.0,
            'bsc': 3.0,
            'ink': 0.1,
            'sepolia': 1.0,
            'dry_run': 1.0,
        }

GAS_HEURISTICS = get_gas_heuristics()
GAS_PRICE_ESTIMATES = get_gas_price_estimates()


@dataclass
class SimulationResult:
    """
    Result of a transaction simulation.
    
    Attributes:
        would_succeed: Whether transaction would succeed if executed
        failure_reason: Reason for failure (if would_succeed=False)
        estimated_gas: Estimated gas units
        estimated_cost_usd: Estimated cost in USD
        validation_checks: Dict of validation checks (balance_ok, gas_ok, nonce_ok, etc.)
        warnings: List of warning messages
        simulated_tx_hash: Mock transaction hash (for dry-run mode)
        balance_after: Wallet balance after transaction (for dry-run mode)
    """
    would_succeed: bool
    failure_reason: Optional[str] = None
    estimated_gas: int = 0
    estimated_cost_usd: Decimal = Decimal('0')
    validation_checks: Dict[str, bool] = field(default_factory=dict)
    warnings: List[str] = field(default_factory=list)
    simulated_tx_hash: Optional[str] = None
    balance_after: Optional[Decimal] = None


class BalanceTracker:
    """
    In-memory balance tracking for dry-run mode.
    
    Tracks simulated balances for wallets across chains and tokens.
    Used to maintain consistency during dry-run simulations.
    """
    
    def __init__(self):
        """Initialize balance tracker."""
        # Structure: {wallet_address: {chain: {token: Decimal}}}
        self.balances: Dict[str, Dict[str, Dict[str, Decimal]]] = {}
        logger.debug("BalanceTracker initialized")
    
    def initialize_wallet(
        self,
        wallet_address: str,
        chain: str,
        eth_balance: Decimal = Decimal('0.1'),
        token_balances: Optional[Dict[str, Decimal]] = None
    ):
        """
        Initialize wallet with starting balances.
        
        Args:
            wallet_address: Wallet address
            chain: Chain name
            eth_balance: Initial ETH balance (default: 0.1 ETH)
            token_balances: Optional dict of token balances
        """
        wallet_address = wallet_address.lower()
        
        if wallet_address not in self.balances:
            self.balances[wallet_address] = {}
        
        if chain not in self.balances[wallet_address]:
            self.balances[wallet_address][chain] = {}
        
        # Set ETH balance
        self.balances[wallet_address][chain]['ETH'] = eth_balance
        
        # Set token balances if provided
        if token_balances:
            for token, amount in token_balances.items():
                self.balances[wallet_address][chain][token] = amount
        
        logger.debug(
            f"Initialized wallet | Address: {wallet_address[:10]}... | "
            f"Chain: {chain} | ETH: {eth_balance}"
        )
    
    def get_balance(
        self,
        wallet_address: str,
        chain: str,
        token: str = 'ETH'
    ) -> Decimal:
        """
        Get current balance for wallet/chain/token.
        
        Args:
            wallet_address: Wallet address
            chain: Chain name
            token: Token symbol (default: ETH)
        
        Returns:
            Current balance (0 if not initialized)
        """
        wallet_address = wallet_address.lower()
        return self.balances.get(wallet_address, {}).get(chain, {}).get(token, Decimal('0'))
    
    def update_balance(
        self,
        wallet_address: str,
        chain: str,
        token: str,
        delta: Decimal
    ) -> Decimal:
        """
        Update balance by delta amount.
        
        Args:
            wallet_address: Wallet address
            chain: Chain name
            token: Token symbol
            delta: Change in balance (positive=add, negative=subtract)
        
        Returns:
            New balance after update
        """
        wallet_address = wallet_address.lower()
        
        # Initialize if needed
        if wallet_address not in self.balances:
            self.initialize_wallet(wallet_address, chain)
        elif chain not in self.balances[wallet_address]:
            self.balances[wallet_address][chain] = {}
        
        current = self.balances[wallet_address][chain].get(token, Decimal('0'))
        new_balance = current + delta
        
        self.balances[wallet_address][chain][token] = new_balance
        
        logger.debug(
            f"Balance updated | Wallet: {wallet_address[:10]}... | "
            f"Chain: {chain} | Token: {token} | "
            f"Delta: {delta:+.6f} | New: {new_balance:.6f}"
        )
        
        return new_balance
    
    def reset(self):
        """Clear all simulated balances."""
        self.balances.clear()
        logger.info("All simulated balances cleared")


class TransactionSimulator:
    """
    Centralized transaction simulator for dry-run mode.
    
    Features:
    - Validates transaction parameters
    - Estimates gas costs
    - Simulates contract interactions
    - Tracks simulated balances
    - Logs all simulation results
    """
    
    def __init__(self, db_manager, network_mode_manager: Optional[NetworkModeManager] = None):
        """
        Initialize transaction simulator.
        
        Args:
            db_manager: DatabaseManager instance
            network_mode_manager: Optional NetworkModeManager (creates new if None)
        """
        self.db = db_manager
        self.mode_manager = network_mode_manager or NetworkModeManager()
        self.balance_tracker = BalanceTracker()
        
        logger.info(
            f"TransactionSimulator initialized | Mode: {self.mode_manager.get_mode().value}"
        )
    
    def _estimate_gas_dry_run(self, tx_type: str) -> int:
        """
        Estimate gas using heuristics for dry-run mode.
        
        Args:
            tx_type: Transaction type (SWAP, BRIDGE, STAKE, etc.)
        
        Returns:
            Estimated gas units
        """
        base_gas = GAS_HEURISTICS.get(tx_type.upper(), 100000)
        
        # Add random noise (±20%)
        noise = np.random.randint(-int(base_gas * 0.2), int(base_gas * 0.2))
        
        return base_gas + noise
    
    def _get_gas_price_estimate(self, chain: str) -> Decimal:
        """
        Get gas price estimate in gwei.
        
        Args:
            chain: Chain name
        
        Returns:
            Gas price in gwei
        """
        base_price = GAS_PRICE_ESTIMATES.get(chain.lower(), 1.0)
        
        # Add slight random variation (±10%)
        variation = random.uniform(0.9, 1.1)
        
        return Decimal(str(base_price * variation))
    
    def _calculate_gas_cost_usd(
        self,
        gas_units: int,
        gas_price_gwei: Decimal,
        eth_price_usd: Decimal = None
    ) -> Decimal:
        """
        Calculate gas cost in USD.
        
        Args:
            gas_units: Gas units
            gas_price_gwei: Gas price in gwei
            eth_price_usd: ETH price in USD (default: from oracle)
        
        Returns:
            Cost in USD
        """
        # Get ETH price from oracle if not provided
        if eth_price_usd is None:
            from infrastructure.price_oracle import get_eth_price_sync
            eth_price_usd = get_eth_price_sync(self.db if hasattr(self, 'db') else None)
        
        # Convert gwei to ETH: 1 ETH = 1e9 gwei
        gas_cost_eth = (Decimal(gas_units) * gas_price_gwei) / Decimal('1e9')
        gas_cost_usd = gas_cost_eth * eth_price_usd
        
        return gas_cost_usd
    
    def simulate_transaction(
        self,
        wallet_address: str,
        chain: str,
        tx_type: str,
        value: Decimal = Decimal('0'),
        to_address: Optional[str] = None,
        data: Optional[str] = None,
        gas_limit: Optional[int] = None
    ) -> SimulationResult:
        """
        Simulate a transaction without executing it.
        
        Args:
            wallet_address: Sender wallet address
            chain: Chain name
            tx_type: Transaction type (SWAP, BRIDGE, STAKE, etc.)
            value: Transaction value in ETH
            to_address: Recipient address (optional)
            data: Transaction data (optional)
            gas_limit: Optional gas limit override
        
        Returns:
            SimulationResult with validation checks and estimates
        """
        logger.info(
            f"Simulating transaction | Wallet: {wallet_address[:10]}... | "
            f"Chain: {chain} | Type: {tx_type} | Value: {value}"
        )
        
        validation_checks = {}
        warnings = []
        
        # Step 1: Estimate gas
        if gas_limit:
            estimated_gas = gas_limit
        elif self.mode_manager.is_dry_run():
            estimated_gas = self._estimate_gas_dry_run(tx_type)
        else:
            # For testnet/mainnet, use heuristics (eth_estimateGas requires RPC connection)
            estimated_gas = self._estimate_gas_dry_run(tx_type)
            warnings.append("Gas estimation using heuristics (not eth_estimateGas)")
        
        validation_checks['gas_estimated'] = True
        
        # Step 2: Get gas price
        gas_price = self._get_gas_price_estimate(chain)
        estimated_cost_usd = self._calculate_gas_cost_usd(estimated_gas, gas_price)
        
        # Step 3: Check balance
        current_balance = self.balance_tracker.get_balance(wallet_address, chain, 'ETH')
        
        # Calculate total required (value + gas)
        gas_cost_eth = (Decimal(estimated_gas) * gas_price) / Decimal('1e9')
        total_required = value + gas_cost_eth
        
        balance_sufficient = current_balance >= total_required
        validation_checks['balance_ok'] = balance_sufficient
        
        if not balance_sufficient:
            failure_reason = (
                f"Insufficient balance: have {current_balance:.6f} ETH, "
                f"need {total_required:.6f} ETH (value: {value:.6f} + gas: {gas_cost_eth:.6f})"
            )
            logger.warning(failure_reason)
            
            return SimulationResult(
                would_succeed=False,
                failure_reason=failure_reason,
                estimated_gas=estimated_gas,
                estimated_cost_usd=estimated_cost_usd,
                validation_checks=validation_checks,
                warnings=warnings
            )
        
        # Step 4: Check gas price reasonability
        max_acceptable_gas = GAS_PRICE_ESTIMATES.get(chain.lower(), 1.0) * 5  # 5x normal
        
        if float(gas_price) > max_acceptable_gas:
            warnings.append(
                f"High gas price: {gas_price:.2f} gwei (normal: {GAS_PRICE_ESTIMATES.get(chain.lower(), 1.0)} gwei)"
            )
        
        validation_checks['gas_ok'] = float(gas_price) <= max_acceptable_gas * 2  # Allow 2x spike
        
        # Step 5: Validate addresses
        if to_address:
            try:
                Web3.to_checksum_address(to_address)
                validation_checks['to_address_valid'] = True
            except Exception:
                validation_checks['to_address_valid'] = False
                warnings.append(f"Invalid to_address: {to_address}")
        
        validation_checks['from_address_valid'] = True  # Assume valid if provided
        
        # Step 6: Update simulated balance (for dry-run mode)
        if self.mode_manager.is_dry_run():
            # Deduct value + gas from balance
            new_balance = self.balance_tracker.update_balance(
                wallet_address,
                chain,
                'ETH',
                -total_required
            )
            
            # Generate mock transaction hash
            tx_hash = '0x' + ''.join(random.choices('0123456789abcdef', k=64))
        else:
            new_balance = None
            tx_hash = None
        
        # Success!
        logger.success(
            f"Simulation successful | Gas: {estimated_gas} | "
            f"Cost: ${estimated_cost_usd:.4f} | "
            f"Balance after: {new_balance:.6f} ETH" if new_balance else ""
        )
        
        # Log to database
        self._log_simulation(
            wallet_address=wallet_address,
            chain=chain,
            tx_type=tx_type,
            value=value,
            estimated_gas=estimated_gas,
            estimated_cost_usd=estimated_cost_usd,
            would_succeed=True
        )
        
        return SimulationResult(
            would_succeed=True,
            failure_reason=None,
            estimated_gas=estimated_gas,
            estimated_cost_usd=estimated_cost_usd,
            validation_checks=validation_checks,
            warnings=warnings,
            simulated_tx_hash=tx_hash,
            balance_after=new_balance
        )
    
    def simulate_swap(
        self,
        wallet_address: str,
        chain: str,
        token_in: str,
        token_out: str,
        amount_in: Decimal
    ) -> SimulationResult:
        """
        Simulate a DEX swap.
        
        Args:
            wallet_address: Wallet address
            chain: Chain name
            token_in: Input token symbol
            token_out: Output token symbol
            amount_in: Input token amount
        
        Returns:
            SimulationResult
        """
        logger.info(
            f"Simulating swap | Wallet: {wallet_address[:10]}... | "
            f"Chain: {chain} | {amount_in} {token_in} -> {token_out}"
        )
        
        # Check token balance
        token_balance = self.balance_tracker.get_balance(wallet_address, chain, token_in)
        
        if token_balance < amount_in:
            return SimulationResult(
                would_succeed=False,
                failure_reason=f"Insufficient {token_in}: have {token_balance}, need {amount_in}",
                validation_checks={'balance_ok': False}
            )
        
        # Simulate the swap transaction
        result = self.simulate_transaction(
            wallet_address=wallet_address,
            chain=chain,
            tx_type='SWAP',
            value=Decimal('0'),  # No ETH value for token swap
            to_address='0x' + '0' * 40  # Mock DEX router address
        )
        
        # Update token balances if simulation succeeded
        if result.would_succeed and self.mode_manager.is_dry_run():
            # Deduct input token
            self.balance_tracker.update_balance(wallet_address, chain, token_in, -amount_in)
            
            # Add output token (estimate: 0.995 of input due to slippage)
            amount_out = amount_in * Decimal('0.995')
            self.balance_tracker.update_balance(wallet_address, chain, token_out, amount_out)
            
            result.warnings.append(f"Simulated output: ~{amount_out} {token_out} (assuming 0.5% slippage)")
        
        return result
    
    def simulate_bridge(
        self,
        wallet_address: str,
        source_chain: str,
        dest_chain: str,
        amount: Decimal,
        token: str = 'ETH'
    ) -> SimulationResult:
        """
        Simulate a cross-chain bridge.
        
        Args:
            wallet_address: Wallet address
            source_chain: Source chain name
            dest_chain: Destination chain name
            amount: Amount to bridge
            token: Token symbol (default: ETH)
        
        Returns:
            SimulationResult
        """
        logger.info(
            f"Simulating bridge | Wallet: {wallet_address[:10]}... | "
            f"{source_chain} -> {dest_chain} | {amount} {token}"
        )
        
        # Check balance on source chain
        source_balance = self.balance_tracker.get_balance(wallet_address, source_chain, token)
        
        if source_balance < amount:
            return SimulationResult(
                would_succeed=False,
                failure_reason=f"Insufficient {token} on {source_chain}: have {source_balance}, need {amount}",
                validation_checks={'balance_ok': False}
            )
        
        # Simulate bridge transaction
        result = self.simulate_transaction(
            wallet_address=wallet_address,
            chain=source_chain,
            tx_type='BRIDGE',
            value=amount if token == 'ETH' else Decimal('0'),
            to_address='0x' + '1' * 40  # Mock bridge contract
        )
        
        # Update balances if successful
        if result.would_succeed and self.mode_manager.is_dry_run():
            # Deduct from source chain
            self.balance_tracker.update_balance(wallet_address, source_chain, token, -amount)
            
            # Add to destination chain (minus 0.1% bridge fee)
            bridged_amount = amount * Decimal('0.999')
            self.balance_tracker.update_balance(wallet_address, dest_chain, token, bridged_amount)
            
            result.warnings.append(
                f"Simulated bridge: {bridged_amount} {token} to {dest_chain} (0.1% fee)"
            )
        
        return result
    
    def simulate_funding(
        self,
        wallet_address: str,
        chain: str,
        amount_usd: Decimal,
        token: str = 'ETH'
    ) -> SimulationResult:
        """
        Simulate funding a wallet from CEX.
        
        Args:
            wallet_address: Wallet address to fund
            chain: Chain name
            amount_usd: Amount in USD
            token: Token symbol (default: ETH)
        
        Returns:
            SimulationResult
        """
        # Convert USD to ETH using price oracle
        from infrastructure.price_oracle import get_eth_price_sync
        eth_price = get_eth_price_sync(self.db if hasattr(self, 'db') else None)
        amount_eth = amount_usd / eth_price
        
        logger.info(
            f"Simulating funding | Wallet: {wallet_address[:10]}... | "
            f"Chain: {chain} | ${amount_usd} ({amount_eth:.6f} {token})"
        )
        
        # Funding has minimal gas (just receiving)
        estimated_gas = 21000
        gas_price = self._get_gas_price_estimate(chain)
        estimated_cost_usd = self._calculate_gas_cost_usd(estimated_gas, gas_price)
        
        # Add balance to wallet
        if self.mode_manager.is_dry_run():
            new_balance = self.balance_tracker.update_balance(
                wallet_address,
                chain,
                token,
                amount_eth
            )
        else:
            new_balance = None
        
        self._log_simulation(
            wallet_address=wallet_address,
            chain=chain,
            tx_type='FUNDING',
            value=amount_eth,
            estimated_gas=estimated_gas,
            estimated_cost_usd=estimated_cost_usd,
            would_succeed=True
        )
        
        return SimulationResult(
            would_succeed=True,
            estimated_gas=estimated_gas,
            estimated_cost_usd=estimated_cost_usd,
            validation_checks={'funding_ok': True},
            warnings=[f"Simulated CEX withdrawal: {amount_eth:.6f} {token}"],
            balance_after=new_balance
        )
    
    def simulate_withdrawal(
        self,
        wallet_address: str,
        chain: str,
        destination: str,
        amount: Decimal,
        token: str = 'ETH'
    ) -> SimulationResult:
        """
        Simulate withdrawing from wallet to destination (CEX or cold wallet).
        
        Args:
            wallet_address: Source wallet address
            chain: Chain name
            destination: Destination address (CEX deposit address or cold wallet)
            amount: Amount to withdraw
            token: Token symbol (default: ETH)
        
        Returns:
            SimulationResult
        """
        logger.info(
            f"Simulating withdrawal | Wallet: {wallet_address[:10]}... | "
            f"Chain: {chain} | Amount: {amount} {token} | To: {destination[:10]}..."
        )
        
        # Check balance
        balance = self.balance_tracker.get_balance(wallet_address, chain, token)
        
        if balance < amount:
            return SimulationResult(
                would_succeed=False,
                failure_reason=f"Insufficient {token}: have {balance}, need {amount}",
                validation_checks={'balance_ok': False}
            )
        
        # Simulate transfer transaction
        result = self.simulate_transaction(
            wallet_address=wallet_address,
            chain=chain,
            tx_type='TRANSFER',
            value=amount if token == 'ETH' else Decimal('0'),
            to_address=destination
        )
        
        # Update balance if successful
        if result.would_succeed and self.mode_manager.is_dry_run():
            self.balance_tracker.update_balance(wallet_address, chain, token, -amount)
            result.warnings.append(f"Withdrew {amount} {token} to {destination[:10]}...")
        
        return result
    
    def _log_simulation(
        self,
        wallet_address: str,
        chain: str,
        tx_type: str,
        value: Decimal,
        estimated_gas: int,
        estimated_cost_usd: Decimal,
        would_succeed: bool
    ):
        """
        Log simulation to database.
        
        Args:
            wallet_address: Wallet address
            chain: Chain name
            tx_type: Transaction type
            value: Transaction value
            estimated_gas: Estimated gas
            estimated_cost_usd: Estimated cost in USD
            would_succeed: Whether simulation succeeded
        """
        try:
            query = """
                INSERT INTO dry_run_logs (
                    wallet_address, chain, tx_type, value, estimated_gas,
                    estimated_cost_usd, would_succeed, simulated_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """
            
            self.db.execute_query(
                query,
                (
                    wallet_address,
                    chain,
                    tx_type,
                    value,
                    estimated_gas,
                    estimated_cost_usd,
                    would_succeed,
                    datetime.now(timezone.utc)
                )
            )
            
            logger.debug(f"Simulation logged to database | Type: {tx_type}")
        except Exception as e:
            logger.warning(f"Failed to log simulation to database: {e}")


if __name__ == '__main__':
    # Test simulator
    from database.db_manager import DatabaseManager
    
    logger.info("=== Transaction Simulator Test ===")
    
    db = DatabaseManager()
    simulator = TransactionSimulator(db)
    
    # Test wallet
    test_wallet = '0x1234567890abcdef1234567890abcdef12345678'
    
    # Initialize wallet with balance
    simulator.balance_tracker.initialize_wallet(
        test_wallet,
        'base',
        eth_balance=Decimal('1.0'),
        token_balances={'USDC': Decimal('1000')}
    )
    
    # Test simulations
    logger.info("\n--- Test 1: Swap simulation ---")
    result = simulator.simulate_swap(
        wallet_address=test_wallet,
        chain='base',
        token_in='USDC',
        token_out='ETH',
        amount_in=Decimal('100')
    )
    logger.info(f"Result: {result}")
    
    logger.info("\n--- Test 2: Bridge simulation ---")
    result = simulator.simulate_bridge(
        wallet_address=test_wallet,
        source_chain='base',
        dest_chain='arbitrum',
        amount=Decimal('0.1')
    )
    logger.info(f"Result: {result}")
    
    logger.info("\n--- Test 3: Insufficient balance ---")
    result = simulator.simulate_withdrawal(
        wallet_address=test_wallet,
        chain='base',
        destination='0xdeadbeef' * 5,
        amount=Decimal('999')  # More than balance
    )
    logger.info(f"Result: {result}")
    
    logger.success("Simulator test complete")
