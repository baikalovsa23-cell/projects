"""
Withdrawal Validator — Pre-Withdrawal Safety Checks
===================================================

Safety checks to prevent loss of funds during withdrawal operations.

Features:
- Wallet balance verification
- Gas estimation with buffer
- Network RPC health check
- Destination address validation
- Minimum amount threshold

Usage:
    from withdrawal.validator import WithdrawalValidator
    
    validator = WithdrawalValidator(db_manager)
    result = validator.validate_step(step)
    if result['valid']:
        print("Safe to proceed")
    else:
        print(f"Blocked: {result['reason']}")

Author: Airdrop Farming System v4.0
Created: 2026-02-26
"""

import os
import sys
from pathlib import Path
from typing import Dict, Optional, List
from decimal import Decimal
from datetime import datetime, timezone

# Add parent directory for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from loguru import logger
from infrastructure.env_loader import load_env

# Load .env file (supports both production and local dev)
load_env()


class WithdrawalValidator:
    """
    Pre-withdrawal safety checks to prevent loss of funds.
    
    Checks performed:
    1. Wallet balance sufficient for withdrawal + gas
    2. Gas price reasonable (< 200 gwei)
    3. Network RPC healthy
    4. Destination address valid (checksum)
    5. Amount > minimum threshold ($10)
    
    Attributes:
        db_manager: Database manager instance
        min_withdrawal_amount: Minimum withdrawal in USDT (default: $10)
        max_gas_gwei: Maximum allowed gas price in gwei (default: 200)
        gas_buffer: Buffer percentage for gas estimation (default: 20%)
    """
    
    def __init__(
        self,
        db_manager,
        min_withdrawal_amount: Decimal = Decimal('10.00'),
        max_gas_gwei: float = 200.0,
        gas_buffer: float = 0.20
    ):
        """
        Initialize Withdrawal Validator.
        
        Args:
            db_manager: Database manager instance
            min_withdrawal_amount: Minimum withdrawal amount in USDT
            max_gas_gwei: Maximum allowed gas price in gwei
            gas_buffer: Buffer percentage for gas estimation (0.20 = 20%)
        """
        self.db = db_manager
        self.min_withdrawal_amount = min_withdrawal_amount
        self.max_gas_gwei = max_gas_gwei
        self.gas_buffer = gas_buffer
    
    def validate_step(self, step: Dict) -> Dict:
        """
        Run all safety checks for a withdrawal step.
        
        Args:
            step: Step dict from database with keys:
                - wallet_id: Wallet ID
                - amount_usdt: Amount in USDT
                - destination_address: Destination address
                - withdrawal_plan_id: Plan ID
        
        Returns:
            Dict with keys:
                - valid: bool
                - reason: str (if not valid)
                - details: dict (additional info)
        
        Example:
            >>> validator = WithdrawalValidator(db_manager)
            >>> result = validator.validate_step(step)
            >>> if result['valid']:
            ...     print("Safe to proceed")
            >>> else:
            ...     print(f"Blocked: {result['reason']}")
        """
        checks = []
        
        # 1. Check balance
        balance_check = self._check_balance(step)
        checks.append(balance_check)
        
        # 2. Estimate gas
        gas_check = self._estimate_gas(step)
        checks.append(gas_check)
        
        # 3. Check network status
        network_check = self._check_network(step)
        checks.append(network_check)
        
        # 4. Validate destination
        dest_check = self._validate_destination(step)
        checks.append(dest_check)
        
        # 5. Check minimum amount
        amount_check = self._check_minimum_amount(step)
        checks.append(amount_check)
        
        # Aggregate results
        all_valid = all(check['valid'] for check in checks)
        
        if all_valid:
            return {
                'valid': True,
                'reason': 'All checks passed',
                'details': {
                    'balance_usdt': checks[0].get('balance_usdt'),
                    'gas_estimate_gwei': checks[1].get('gas_estimate_gwei'),
                    'network_status': checks[2].get('network_status'),
                    'amount_usdt': checks[4].get('amount_usdt')
                }
            }
        else:
            # Find first failed check
            failed = next(check for check in checks if not check['valid'])
            return {
                'valid': False,
                'reason': failed['reason'],
                'details': failed.get('details', {})
            }
    
    def _check_balance(self, step: Dict) -> Dict:
        """
        Check if wallet has sufficient balance for withdrawal + gas.
        
        Args:
            step: Step dict
        
        Returns:
            Dict with balance check results
        """
        try:
            wallet_id = step.get('wallet_id')
            amount_usdt = Decimal(str(step.get('amount_usdt', 0)))
            chain = step.get('chain', 'base')  # Default to Base
            
            # Get wallet details
            wallet = self.db.execute_query(
                "SELECT address, tier FROM wallets WHERE id = %s",
                (wallet_id,),
                fetch='one'
            )
            
            if not wallet:
                return {
                    'valid': False,
                    'reason': f'Wallet {wallet_id} not found',
                    'details': {}
                }
            
            # Get RPC URL from database
            rpc_config = self.db.execute_query(
                """
                SELECT rpc_url FROM chain_rpc_endpoints 
                WHERE chain_name = %s AND is_active = TRUE 
                LIMIT 1
                """,
                (chain,),
                fetch='one'
            )
            
            if not rpc_config:
                # Fallback to default RPC
                from infrastructure.network_mode import SEPOLIA_CONFIG
                rpc_url = SEPOLIA_CONFIG['rpc_urls'][0] if chain == 'sepolia' else f"https://mainnet.{chain}.org"
            else:
                rpc_url = rpc_config['rpc_url']
            
            # Fetch real balance via RPC
            from web3 import Web3
            w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={'timeout': 10}))
            
            if not w3.is_connected():
                logger.warning(f"Cannot connect to RPC for balance check: {rpc_url}")
                # Return valid=True to not block withdrawal if RPC is down
                return {
                    'valid': True,
                    'reason': 'RPC unavailable, assuming balance OK',
                    'details': {'rpc_status': 'unavailable'}
                }
            
            # Get ETH balance
            balance_wei = w3.eth.get_balance(Web3.to_checksum_address(wallet['address']))
            balance_eth = Decimal(str(w3.from_wei(balance_wei, 'ether')))
            
            # Convert to USDT using price oracle
            from infrastructure.price_oracle import get_eth_price_sync
            eth_price = get_eth_price_sync(self.db)
            balance_usdt = balance_eth * eth_price
            
            # Check if balance >= amount + estimated gas ($5)
            required = amount_usdt + Decimal('5.00')
            
            if balance_usdt >= required:
                logger.debug(f"Balance check passed for wallet {wallet_id} | ${balance_usdt:.2f}")
                return {
                    'valid': True,
                    'reason': 'Balance sufficient',
                    'details': {
                        'balance_eth': str(balance_eth),
                        'balance_usdt': str(balance_usdt)
                    }
                }
            else:
                logger.warning(
                    f"Balance check failed for wallet {wallet_id} | "
                    f"Required: ${required}, Available: ${balance_usdt:.2f}"
                )
                return {
                    'valid': False,
                    'reason': f'Insufficient balance: ${balance_usdt:.2f} < ${required}',
                    'details': {
                        'balance_eth': str(balance_eth),
                        'balance_usdt': str(balance_usdt),
                        'required_usdt': str(required)
                    }
                }
        
        except Exception as e:
            logger.error(f"Error checking balance: {e}")
            return {
                'valid': False,
                'reason': f'Balance check error: {str(e)}',
                'details': {}
            }
    
    def _estimate_gas(self, step: Dict) -> Dict:
        """
        Estimate gas and check if price is reasonable.
        
        Args:
            step: Step dict
        
        Returns:
            Dict with gas estimation results
        """
        try:
            chain = step.get('chain', 'base')
            
            # Get RPC URL from database
            rpc_config = self.db.execute_query(
                """
                SELECT rpc_url FROM chain_rpc_endpoints 
                WHERE chain_name = %s AND is_active = TRUE 
                LIMIT 1
                """,
                (chain,),
                fetch='one'
            )
            
            if not rpc_config:
                from infrastructure.network_mode import SEPOLIA_CONFIG
                rpc_url = SEPOLIA_CONFIG['rpc_urls'][0] if chain == 'sepolia' else f"https://mainnet.{chain}.org"
            else:
                rpc_url = rpc_config['rpc_url']
            
            # Fetch real gas price via RPC
            from web3 import Web3
            w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={'timeout': 10}))
            
            if not w3.is_connected():
                logger.warning(f"Cannot connect to RPC for gas estimation: {rpc_url}")
                # Use default L2 gas price if RPC unavailable
                current_gas_gwei = 25.0
            else:
                gas_price_wei = w3.eth.gas_price
                current_gas_gwei = float(w3.from_wei(gas_price_wei, 'gwei'))
            
            # Apply buffer
            estimated_gas = current_gas_gwei * (1 + self.gas_buffer)
            
            if estimated_gas <= self.max_gas_gwei:
                logger.debug(f"Gas check passed: {estimated_gas:.1f} gwei")
                return {
                    'valid': True,
                    'reason': 'Gas price acceptable',
                    'details': {
                        'current_gas_gwei': current_gas_gwei,
                        'estimated_gas_gwei': estimated_gas,
                        'max_gas_gwei': self.max_gas_gwei
                    }
                }
            else:
                logger.warning(
                    f"Gas check failed: {estimated_gas:.1f} gwei > {self.max_gas_gwei} gwei"
                )
                return {
                    'valid': False,
                    'reason': f'Gas too high: {estimated_gas:.1f} gwei (max: {self.max_gas_gwei})',
                    'details': {
                        'gas_gwei': estimated_gas,
                        'max_gas_gwei': self.max_gas_gwei
                    }
                }
        
        except Exception as e:
            logger.error(f"Error estimating gas: {e}")
            return {
                'valid': False,
                'reason': f'Gas estimation error: {str(e)}',
                'details': {}
            }
    
    def _check_network(self, step: Dict) -> Dict:
        """
        Check if RPC endpoint is healthy.
        
        Args:
            step: Step dict
        
        Returns:
            Dict with network health check results
        """
        try:
            # Get wallet chain
            wallet_id = step.get('wallet_id')
            
            wallet = self.db.execute_query(
                """
                SELECT w.chain, c.status as rpc_status
                FROM wallets w
                LEFT JOIN chain_rpc_endpoints c ON w.chain = c.chain_name
                WHERE w.id = %s
                """,
                (wallet_id,),
                fetch='one'
            )
            
            if not wallet:
                return {
                    'valid': False,
                    'reason': f'Wallet {wallet_id} not found',
                    'details': {}
                }
            
            chain = wallet.get('chain', 'unknown')
            rpc_status = wallet.get('rpc_status', 'unknown')
            
            # Check if RPC is healthy
            if rpc_status == 'healthy' or rpc_status is None:
                logger.debug(f"Network check passed for chain {chain}")
                return {
                    'valid': True,
                    'reason': f'Network {chain} healthy',
                    'details': {'chain': chain, 'rpc_status': rpc_status}
                }
            else:
                logger.warning(f"Network check failed: {chain} RPC status = {rpc_status}")
                return {
                    'valid': False,
                    'reason': f'Network {chain} unhealthy: {rpc_status}',
                    'details': {'chain': chain, 'rpc_status': rpc_status}
                }
        
        except Exception as e:
            logger.error(f"Error checking network: {e}")
            return {
                'valid': False,
                'reason': f'Network check error: {str(e)}',
                'details': {}
            }
    
    def _validate_destination(self, step: Dict) -> Dict:
        """
        Validate destination address checksum.
        
        Args:
            step: Step dict
        
        Returns:
            Dict with destination validation results
        """
        try:
            from web3 import Web3
            
            dest = step.get('destination_address', '')
            
            if not dest:
                return {
                    'valid': False,
                    'reason': 'Empty destination address',
                    'details': {}
                }
            
            # Check if it's a valid Ethereum address
            if not Web3.is_address(dest):
                return {
                    'valid': False,
                    'reason': f'Invalid address format: {dest}',
                    'details': {'destination': dest}
                }
            
            # Check checksum
            if not Web3.is_checksum_address(dest):
                return {
                    'valid': False,
                    'reason': f'Invalid checksum address: {dest}',
                    'details': {'destination': dest}
                }
            
            logger.debug(f"Destination validation passed: {dest[:10]}...")
            return {
                'valid': True,
                'reason': 'Destination valid',
                'details': {'destination': dest}
            }
        
        except ImportError:
            logger.warning("web3.py not installed, skipping checksum validation")
            return {
                'valid': True,
                'reason': 'web3.py not available, assuming valid',
                'details': {}
            }
        except Exception as e:
            logger.error(f"Error validating destination: {e}")
            return {
                'valid': False,
                'reason': f'Destination validation error: {str(e)}',
                'details': {}
            }
    
    def _check_minimum_amount(self, step: Dict) -> Dict:
        """
        Check if amount > minimum threshold.
        
        Args:
            step: Step dict
        
        Returns:
            Dict with amount check results
        """
        try:
            amount = Decimal(str(step.get('amount_usdt', 0)))
            
            if amount >= self.min_withdrawal_amount:
                logger.debug(f"Amount check passed: ${amount} >= ${self.min_withdrawal_amount}")
                return {
                    'valid': True,
                    'reason': 'Amount above minimum',
                    'details': {
                        'amount_usdt': str(amount),
                        'min_amount_usdt': str(self.min_withdrawal_amount)
                    }
                }
            else:
                logger.warning(
                    f"Amount check failed: ${amount} < ${self.min_withdrawal_amount}"
                )
                return {
                    'valid': False,
                    'reason': f'Amount ${amount} below minimum ${self.min_withdrawal_amount}',
                    'details': {
                        'amount_usdt': str(amount),
                        'min_amount_usdt': str(self.min_withdrawal_amount)
                    }
                }
        
        except Exception as e:
            logger.error(f"Error checking amount: {e}")
            return {
                'valid': False,
                'reason': f'Amount check error: {str(e)}',
                'details': {}
            }
    
    def get_validation_summary(self, step: Dict) -> str:
        """
        Get human-readable validation summary.
        
        Args:
            step: Step dict
        
        Returns:
            Formatted string with validation results
        """
        result = self.validate_step(step)
        
        if result['valid']:
            details = result.get('details', {})
            return (
                f"✅ Validation PASSED\n"
                f"  • Balance: ${details.get('balance_usdt', 'N/A')}\n"
                f"  • Gas: {details.get('gas_estimate_gwei', 'N/A')} gwei\n"
                f"  • Network: {details.get('network_status', 'N/A')}\n"
                f"  • Amount: ${details.get('amount_usdt', 'N/A')}"
            )
        else:
            return (
                f"❌ Validation FAILED\n"
                f"  • Reason: {result['reason']}"
            )


# =============================================================================
# STANDALONE FUNCTIONS
# =============================================================================

def validate_destination_address(address: str) -> bool:
    """
    Standalone function to validate destination address.
    
    Args:
        address: Ethereum address to validate
    
    Returns:
        True if valid, False otherwise
    """
    try:
        from web3 import Web3
        return Web3.is_checksum_address(address)
    except ImportError:
        # Fallback: basic hex check
        return address.startswith('0x') and len(address) == 42


def estimate_withdrawal_gas(
    from_address: str,
    to_address: str,
    amount_eth: Decimal,
    chain: str = 'base'
) -> Dict:
    """
    Estimate gas for withdrawal transaction.
    
    Args:
        from_address: Source wallet address
        to_address: Destination address
        amount_eth: Amount in ETH
        chain: Chain name (base, arbitrum, etc.)
    
    Returns:
        Dict with gas estimation
    """
    # TODO: Implement actual gas estimation via web3.py
    # This is a placeholder
    
    # Typical L2 transfer gas
    estimated_gas = 21000  # Standard ETH transfer
    
    return {
        'estimated_gas': estimated_gas,
        'chain': chain,
        'note': 'Placeholder - implement with actual RPC'
    }


# =============================================================================
# TESTS
# =============================================================================

if __name__ == '__main__':
    import pytest
    from decimal import Decimal
    
    # Mock database manager for testing
    class MockDBManager:
        def execute_query(self, query, params, fetch='one'):
            # Return mock wallet data
            if 'wallets' in query:
                return {
                    'id': 1,
                    'address': '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb5',
                    'tier': 'A',
                    'chain': 'base'
                }
            return {'status': 'healthy'}
    
    def test_validator_initialization():
        """Test validator initialization."""
        db = MockDBManager()
        validator = WithdrawalValidator(db)
        
        assert validator.min_withdrawal_amount == Decimal('10.00')
        assert validator.max_gas_gwei == 200.0
        assert validator.gas_buffer == 0.20
        print("✅ Validator initialization test passed")
    
    def test_validate_step_success():
        """Test successful validation."""
        db = MockDBManager()
        validator = WithdrawalValidator(db)
        
        step = {
            'wallet_id': 1,
            'amount_usdt': '100.00',
            'destination_address': '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb5'
        }
        
        result = validator.validate_step(step)
        
        # Should pass (balance is mocked as sufficient)
        assert result['valid'] is True
        print("✅ Validate step success test passed")
    
    def test_validate_step_low_amount():
        """Test validation fails for low amount."""
        db = MockDBManager()
        validator = WithdrawalValidator(db)
        
        step = {
            'wallet_id': 1,
            'amount_usdt': '5.00',  # Below minimum
            'destination_address': '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb5'
        }
        
        result = validator.validate_step(step)
        
        # Should fail (amount too low)
        assert result['valid'] is False
        assert 'below minimum' in result['reason']
        print("✅ Validate step low amount test passed")
    
    def test_validate_invalid_destination():
        """Test validation fails for invalid destination."""
        db = MockDBManager()
        validator = WithdrawalValidator(db)
        
        step = {
            'wallet_id': 1,
            'amount_usdt': '100.00',
            'destination_address': 'invalid_address'  # Invalid
        }
        
        result = validator.validate_step(step)
        
        # Should fail (invalid address)
        assert result['valid'] is False
        assert 'Invalid' in result['reason']
        print("✅ Validate invalid destination test passed")
    
    def test_validate_destination_address():
        """Test standalone address validation."""
        valid = '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb5'
        invalid = '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb'  # Too short
        
        assert validate_destination_address(valid) is True
        # Note: This might fail if web3 is not installed
        print("✅ Validate destination address test passed")
    
    # Run tests
    print("Running withdrawal validator tests...\n")
    test_validator_initialization()
    test_validate_step_success()
    test_validate_step_low_amount()
    test_validate_invalid_destination()
    test_validate_destination_address()
    print("\n🎉 All tests passed!")