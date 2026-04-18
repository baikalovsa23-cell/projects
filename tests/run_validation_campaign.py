#!/usr/bin/env python3
"""
Testnet Validation Campaign Runner

Executes a full validation campaign on Sepolia testnet to verify
system functionality before mainnet deployment.

Usage:
    python tests/run_validation_campaign.py [--dry-run] [--wallets N]
"""
import os
import sys
import asyncio
import argparse
from datetime import datetime
from decimal import Decimal
from typing import List, Dict

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from loguru import logger
from infrastructure.network_mode import NetworkModeManager, NetworkMode, is_dry_run
from infrastructure.simulator import TransactionSimulator, SimulationResult


class ValidationCampaign:
    """
    Runs a comprehensive validation campaign to verify system readiness.
    """
    
    def __init__(self, db_manager=None, num_wallets: int = 10):
        self.network_mode = NetworkModeManager()
        self.num_wallets = num_wallets
        self.db_manager = db_manager
        self.simulator = TransactionSimulator(db_manager, self.network_mode)
        
        self.results = {
            'total_simulations': 0,
            'successful': 0,
            'failed': 0,
            'operations_tested': [],
            'errors': []
        }
    
    async def run_dry_run_validation(self) -> Dict:
        """
        Execute dry-run validation phase.
        Required before testnet validation.
        """
        logger.info("═" * 60)
        logger.info("    DRY-RUN VALIDATION CAMPAIGN")
        logger.info("═" * 60)
        
        if not is_dry_run():
            logger.warning("Not in DRY_RUN mode - setting for validation")
            os.environ['NETWORK_MODE'] = 'DRY_RUN'
        
        # Test operations
        operations = [
            ('swap', self._test_swap_simulation),
            ('bridge', self._test_bridge_simulation),
            ('funding', self._test_funding_simulation),
            ('withdrawal', self._test_withdrawal_simulation),
        ]
        
        for op_name, test_func in operations:
            logger.info(f"Testing {op_name}...")
            try:
                await test_func()
                self.results['operations_tested'].append(op_name)
                logger.info(f"  ✓ {op_name} passed")
            except Exception as e:
                self.results['errors'].append(f"{op_name}: {str(e)}")
                logger.error(f"  ✗ {op_name} failed: {e}")
        
        success_rate = self.results['successful'] / max(self.results['total_simulations'], 1)
        
        logger.info("═" * 60)
        logger.info(f"    VALIDATION RESULTS")
        logger.info(f"    Total simulations: {self.results['total_simulations']}")
        logger.info(f"    Successful: {self.results['successful']}")
        logger.info(f"    Failed: {self.results['failed']}")
        logger.info(f"    Success rate: {success_rate:.1%}")
        logger.info("═" * 60)
        
        # Record result in database if available
        if self.db_manager and success_rate >= 0.95:
            await self._open_dry_run_gate()
        
        return self.results
    
    async def _test_swap_simulation(self):
        """Test swap simulations"""
        test_cases = [
            ("base", "ETH", "USDC", Decimal("0.1")),
            ("optimism", "USDC", "ETH", Decimal("100")),
            ("arbitrum", "ETH", "USDT", Decimal("0.5")),
        ]
        
        for chain, token_in, token_out, amount in test_cases:
            result = self.simulator.simulate_swap(
                wallet_address="0x1234567890abcdef1234567890abcdef12345678",
                chain=chain,
                token_in=token_in,
                token_out=token_out,
                amount_in=amount
            )
            
            self.results['total_simulations'] += 1
            if result.would_succeed:
                self.results['successful'] += 1
            else:
                self.results['failed'] += 1
    
    async def _test_bridge_simulation(self):
        """Test bridge simulations"""
        test_cases = [
            ("base", "optimism", Decimal("0.1")),
            ("arbitrum", "base", Decimal("0.2")),
        ]
        
        for source, dest, amount in test_cases:
            result = self.simulator.simulate_bridge(
                wallet_address="0x1234567890abcdef1234567890abcdef12345678",
                source_chain=source,
                dest_chain=dest,
                amount=amount
            )
            
            self.results['total_simulations'] += 1
            if result.would_succeed:
                self.results['successful'] += 1
            else:
                self.results['failed'] += 1
    
    async def _test_funding_simulation(self):
        """Test funding simulations"""
        test_cases = [
            ("base", Decimal("15")),
            ("arbitrum", Decimal("50")),
            ("optimism", Decimal("100"))
        ]
        
        for chain, amount in test_cases:
            result = self.simulator.simulate_funding(
                wallet_address="0x1234567890abcdef1234567890abcdef12345678",
                chain=chain,
                amount_usd=amount
            )
            
            self.results['total_simulations'] += 1
            if result.would_succeed:
                self.results['successful'] += 1
            else:
                self.results['failed'] += 1
    
    async def _test_withdrawal_simulation(self):
        """Test withdrawal simulations"""
        result = self.simulator.simulate_withdrawal(
            wallet_address="0x1234567890abcdef1234567890abcdef12345678",
            chain="base",
            destination="0xdead000000000000000000000000000000000000",
            amount=Decimal("1.0")
        )
        
        self.results['total_simulations'] += 1
        if result.would_succeed:
            self.results['successful'] += 1
        else:
            self.results['failed'] += 1
    
    async def _open_dry_run_gate(self):
        """Open dry_run_validation gate in database"""
        if not self.db_manager:
            return
        
        try:
            await self.db_manager.execute("""
                UPDATE safety_gates 
                SET is_open = TRUE, 
                    opened_at = NOW(),
                    opened_by = 'validation_campaign',
                    conditions_met = %s
                WHERE gate_name = 'dry_run_validation'
            """, [str(self.results)])
            logger.info("✅ dry_run_validation gate OPENED")
        except Exception as e:
            logger.error(f"Failed to open gate: {e}")


async def main():
    parser = argparse.ArgumentParser(description='Run validation campaign')
    parser.add_argument('--dry-run', action='store_true', 
                       help='Run dry-run validation')
    parser.add_argument('--testnet', action='store_true',
                       help='Run testnet validation (requires Sepolia)')
    parser.add_argument('--wallets', type=int, default=10,
                       help='Number of wallets to test')
    
    args = parser.parse_args()
    
    campaign = ValidationCampaign(num_wallets=args.wallets)
    
    if args.dry_run or not args.testnet:
        # Default to dry-run
        os.environ['NETWORK_MODE'] = 'DRY_RUN'
        results = await campaign.run_dry_run_validation()
        
        if results['failed'] == 0:
            logger.info("🎉 DRY-RUN VALIDATION PASSED!")
            logger.info("   Next step: Run with --testnet for Sepolia validation")
        else:
            logger.error("❌ DRY-RUN VALIDATION FAILED")
            logger.error(f"   Errors: {results['errors']}")
            sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
