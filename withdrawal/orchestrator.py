"""
Withdrawal Orchestrator — Main Module 19
=========================================

Orchestrates withdrawal operations with human-in-the-loop approval.

Features:
- Tier-specific strategies (A: 4 steps, B: 3, C: 2)
- Temporal isolation (14-60 days between steps) with Gaussian distribution
- Telegram approval workflow
- Safety checks (gas, balance, network)
- Dry-run mode for testing

Usage:
    from withdrawal.orchestrator import WithdrawalOrchestrator
    
    orchestrator = WithdrawalOrchestrator(db_manager, telegram_bot, dry_run=False)
    plan_id = orchestrator.create_withdrawal_plan(
        wallet_id=42,
        destination_address='0xYOUR_COLD_WALLET'
    )

Author: Airdrop Farming System v4.0
Created: 2026-02-26
"""

import os
import sys
from pathlib import Path
from typing import Dict, List, Optional
from decimal import Decimal
from datetime import datetime, timezone, timedelta

# Add parent directory for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from loguru import logger
from infrastructure.env_loader import load_env

# Load .env file (supports both production and local dev)
load_env()

from withdrawal.strategies import TierStrategy
from withdrawal.validator import WithdrawalValidator
from infrastructure.network_mode import NetworkModeManager, NetworkMode, is_dry_run, is_mainnet
from infrastructure.simulator import TransactionSimulator, SimulationResult


# =============================================================================
# DRY-RUN HELPER CLASSES
# =============================================================================

class WithdrawalDryRunResult:
    """Result for dry-run withdrawal operations"""
    def __init__(self, simulation: 'SimulationResult', operation: str, wallet_address: str):
        self.simulation = simulation
        self.operation = operation
        self.wallet_address = wallet_address
        self.is_dry_run = True
        self.tx_hash = None
        self.destination = None
        self.amount = Decimal('0')


class WithdrawalSimulationFailed(Exception):
    """Raised when withdrawal simulation fails"""
    pass


class MainnetWithdrawalNotAllowed(Exception):
    """Raised when mainnet withdrawal attempted without safety gates"""
    pass


# =============================================================================
# MAIN ORCHESTRATOR CLASS
# =============================================================================

class WithdrawalOrchestrator:
    """
    Orchestrates withdrawal operations with human-in-the-loop approval.
    
    Features:
    - Tier-specific strategies (A: 4 steps, B: 3, C: 2)
    - Temporal isolation (14-60 days between steps)
    - Telegram approval workflow
    - Safety checks (gas, balance, network)
    - Dry-run mode for testing
    
    Attributes:
        db_manager: Database manager instance
        telegram_bot: Telegram bot for approvals
        dry_run: If True, simulate without real transactions
    """
    
    def __init__(
        self,
        db_manager,
        telegram_bot,
        dry_run: bool = False
    ):
        """
        Initialize Withdrawal Orchestrator.
        
        Args:
            db_manager: Database connection
            telegram_bot: Telegram bot for approvals
            dry_run: If True, simulate without real transactions
        """
        self.db = db_manager
        self.telegram = telegram_bot
        self.dry_run = dry_run
        self.validator = WithdrawalValidator(db_manager)
        
        # Initialize network mode manager and simulator
        self.network_mode = NetworkModeManager()
        self.simulator = TransactionSimulator(db_manager, self.network_mode)
        
        mode_str = self.network_mode.get_mode().value
        logger.info(
            f"WithdrawalOrchestrator initialized | "
            f"mode={mode_str} | dry_run={dry_run}"
        )
    
    def create_withdrawal_plan(
        self,
        wallet_id: int,
        destination_address: str,
        trigger_type: str = 'airdrop_detected'
    ) -> int:
        """
        Create tier-specific withdrawal plan for a wallet.
        
        Args:
            wallet_id: Wallet ID from wallets table
            destination_address: Master cold wallet address
            trigger_type: 'airdrop_detected', 'manual', 'time_based'
        
        Returns:
            withdrawal_plan_id
        
        Raises:
            ValueError: If wallet not found or invalid tier
        
        Example:
            >>> orchestrator = WithdrawalOrchestrator(db, telegram)
            >>> plan_id = orchestrator.create_withdrawal_plan(
            ...     wallet_id=42,
            ...     destination_address='0xYOUR_COLD_WALLET_ADDRESS'
            ... )
            >>> print(f"Created plan {plan_id} with 4 steps (Tier A)")
        """
        # 1. Get wallet details
        wallet = self.db.execute_query(
            "SELECT id, address, tier, worker_id FROM wallets WHERE id = %s",
            (wallet_id,),
            fetch='one'
        )
        
        if not wallet:
            raise ValueError(f"Wallet {wallet_id} not found")
        
        tier = wallet['tier']
        
        # 2. Get tier-specific strategy
        strategy = TierStrategy.get_strategy(tier)
        
        # 3. Create withdrawal plan
        plan_result = self.db.execute_query(
            """
            INSERT INTO withdrawal_plans (wallet_id, tier, total_steps, status)
            VALUES (%s, %s, %s, 'planned')
            RETURNING id
            """,
            (wallet_id, tier, strategy.total_steps),
            fetch='one'
        )
        plan_id = plan_result['id']
        
        # 4. Create withdrawal steps
        for i, percentage in enumerate(strategy.percentages, start=1):
            scheduled_at = self._calculate_scheduled_time(i, strategy)
            
            self.db.execute_query(
                """
                INSERT INTO withdrawal_steps (
                    withdrawal_plan_id, step_number, percentage,
                    destination_address, scheduled_at, status
                ) VALUES (%s, %s, %s, %s, %s, 'planned')
                """,
                (plan_id, i, percentage, destination_address, scheduled_at)
            )
        
        # 5. Log system event
        self.db.log_system_event(
            event_type='withdrawal_plan_created',
            severity='info',
            message=f"Created withdrawal plan {plan_id} for wallet {wallet_id}",
            metadata={
                'wallet_id': wallet_id,
                'tier': tier,
                'total_steps': strategy.total_steps,
                'trigger_type': trigger_type
            }
        )
        
        logger.info(
            f"Created withdrawal plan {plan_id} for wallet {wallet_id} | "
            f"Tier: {tier} | Steps: {strategy.total_steps}"
        )
        
        return plan_id
    
    def process_pending_steps(self) -> List[int]:
        """
        Process all withdrawal steps that are ready for approval.
        
        Identifies steps where:
        - status = 'planned'
        - scheduled_at <= NOW()
        - Previous step is 'completed' (or step_number = 1)
        
        For each step:
        1. Run safety checks (balance, gas, network)
        2. Change status to 'pending_approval'
        3. Send Telegram notification
        
        Returns:
            List of step IDs sent for approval
        
        Called by:
            master_node.py APScheduler every 6 hours
        """
        steps_for_approval = []
        
        query = """
            SELECT ws.id, ws.withdrawal_plan_id, ws.step_number, 
                   ws.percentage, ws.destination_address,
                   wp.wallet_id, w.address, w.tier
            FROM withdrawal_steps ws
            JOIN withdrawal_plans wp ON ws.withdrawal_plan_id = wp.id
            JOIN wallets w ON wp.wallet_id = w.id
            WHERE ws.status = 'planned'
              AND ws.scheduled_at <= NOW()
            ORDER BY ws.scheduled_at ASC
        """
        
        steps = self.db.execute_query(query, fetch='all')
        
        for step in steps:
            try:
                # Check if previous step is completed
                if step['step_number'] > 1:
                    prev_step = self.db.execute_query(
                        """
                        SELECT status FROM withdrawal_steps 
                        WHERE withdrawal_plan_id = %s AND step_number = %s
                        """,
                        (step['withdrawal_plan_id'], step['step_number'] - 1),
                        fetch='one'
                    )
                    
                    if prev_step and prev_step['status'] != 'completed':
                        logger.debug(
                            f"Skipping step {step['id']}: "
                            f"previous step not completed (status: {prev_step['status']})"
                        )
                        continue
                
                # CRITICAL: Burn-address validation (before any other checks)
                BURN_ADDRESSES = {
                    '0x0000000000000000000000000000000000000000',
                    '0x000000000000000000000000000000000000dead',
                    '0xdead000000000000000042069420694206942069'
                }
                
                if step['destination_address'].lower() in BURN_ADDRESSES:
                    logger.critical(
                        f"BURN ADDRESS BLOCKED | Step {step['id']} | "
                        f"Destination: {step['destination_address']}"
                    )
                    
                    self.telegram.send_alert(
                        severity='critical',
                        message=f"🚨 Burn address blocked in withdrawal step {step['id']}",
                        details={
                            'Wallet': step['address'][:10] + '...',
                            'Destination': step['destination_address']
                        }
                    )
                    
                    # Mark step as rejected
                    self.db.execute_query(
                        "UPDATE withdrawal_steps SET status = 'rejected' WHERE id = %s",
                        (step['id'],)
                    )
                    continue
                
                # Run safety checks
                validation_result = self.validator.validate_step(step)
                
                if not validation_result['valid']:
                    logger.warning(
                        f"Step {step['id']} failed validation: "
                        f"{validation_result['reason']}"
                    )
                    
                    # Send alert to Telegram
                    self.telegram.send_alert(
                        severity='warning',
                        message=f"Withdrawal step {step['id']} validation failed",
                        details={
                            'Wallet': step['address'][:10] + '...',
                            'Reason': validation_result['reason']
                        }
                    )
                    continue
                
                # Calculate actual amount
                amount_usdt = self._calculate_amount(step)
                
                # Update status to pending_approval
                self.db.execute_query(
                    """
                    UPDATE withdrawal_steps 
                    SET status = 'pending_approval', amount_usdt = %s
                    WHERE id = %s
                    """,
                    (amount_usdt, step['id'])
                )
                
                # Send Telegram notification
                total_steps = self._get_total_steps(step['withdrawal_plan_id'])
                
                self.telegram.send_withdrawal_request(
                    step_id=step['id'],
                    wallet_address=step['address'],
                    amount=amount_usdt,
                    destination=step['destination_address'],
                    step_number=step['step_number'],
                    total_steps=total_steps
                )
                
                steps_for_approval.append(step['id'])
                logger.info(
                    f"Step {step['id']} marked for approval | "
                    f"Amount: {amount_usdt} USDT | "
                    f"Step: {step['step_number']}/{total_steps}"
                )
            
            except Exception as e:
                logger.error(f"Error processing step {step['id']}: {e}")
                continue
        
        return steps_for_approval
    
    def execute_withdrawal_step(self, step_id: int) -> bool:
        """
        Execute approved withdrawal step.
        
        Args:
            step_id: Withdrawal step ID
        
        Returns:
            True if successful, False otherwise
        
        Called by:
            Telegram bot after /approve_<ID>
        
        Process:
        1. Verify status = 'approved'
        2. Get wallet details and private key
        3. Calculate gas and fees
        4. Execute transaction via Worker API
        5. Update database with tx_hash
        6. Send Telegram confirmation
        """
        try:
            # Get step details
            step = self.db.execute_query(
                """
                SELECT ws.*, wp.wallet_id, w.address, w.tier, w.worker_id
                FROM withdrawal_steps ws
                JOIN withdrawal_plans wp ON ws.withdrawal_plan_id = wp.id
                JOIN wallets w ON wp.wallet_id = w.id
                WHERE ws.id = %s
                """,
                (step_id,),
                fetch='one'
            )
            
            if not step:
                raise ValueError(f"Step {step_id} not found")
            
            if step['status'] != 'approved':
                raise ValueError(
                    f"Step {step_id} status: {step['status']} (not approved)"
                )
            
            # CRITICAL: Burn-address validation (double-check before execution)
            BURN_ADDRESSES = {
                '0x0000000000000000000000000000000000000000',
                '0x000000000000000000000000000000000000dead',
                '0xdead000000000000000042069420694206942069'
            }
            
            if step['destination_address'].lower() in BURN_ADDRESSES:
                logger.critical(
                    f"BURN ADDRESS BLOCKED at execution | Step {step_id} | "
                    f"Destination: {step['destination_address']}"
                )
                
                self.db.execute_query(
                    "UPDATE withdrawal_steps SET status = 'rejected' WHERE id = %s",
                    (step_id,)
                )
                
                self.telegram.send_alert(
                    severity='critical',
                    message=f"🚨 Execution ABORTED: burn address in step {step_id}",
                    details={'Destination': step['destination_address']}
                )
                
                raise ValueError(f"Burn address detected: {step['destination_address']}")
            
            # STEP 1: Simulate withdrawal before execution
            try:
                simulation = self.simulator.simulate_withdrawal(
                    wallet_address=step['address'],
                    destination=step['destination_address'],
                    amount=step['amount_usdt']
                )
                
                logger.info(
                    f"Withdrawal simulation | Step {step_id} | "
                    f"Success: {simulation.would_succeed} | "
                    f"Gas: {simulation.estimated_gas} | "
                    f"Cost: ${simulation.estimated_cost_usd:.2f}"
                )
            except Exception as sim_error:
                logger.error(f"Withdrawal simulation failed for step {step_id}: {sim_error}")
                simulation = None
            
            # STEP 2: Check network mode - DRY-RUN
            if is_dry_run():
                logger.info(
                    f"[DRY-RUN] Would execute withdrawal step {step_id} | "
                    f"Wallet: {step['address'][:10]}... | "
                    f"Destination: {step['destination_address'][:10]}... | "
                    f"Amount: ${step['amount_usdt']}"
                )
                
                # Mark as completed in dry-run mode
                self.db.execute_query(
                    """
                    UPDATE withdrawal_steps
                    SET status = 'completed',
                        executed_at = NOW(),
                        tx_hash = 'DRY_RUN_SIMULATION_TX'
                    WHERE id = %s
                    """,
                    (step_id,)
                )
                
                # Update plan current_step
                self.db.execute_query(
                    """
                    UPDATE withdrawal_plans
                    SET current_step = %s, updated_at = NOW()
                    WHERE id = %s
                    """,
                    (step['step_number'], step['withdrawal_plan_id'])
                )
                
                # Log event
                self.db.log_system_event(
                    event_type='withdrawal_dry_run',
                    severity='info',
                    message=f"[DRY-RUN] Withdrawal step {step_id} simulated",
                    metadata={
                        'wallet_id': step['wallet_id'],
                        'amount_usdt': str(step['amount_usdt']),
                        'simulation_success': simulation.would_succeed if simulation else None
                    }
                )
                
                return True
            
            # STEP 3: Validate simulation results
            if simulation and not simulation.would_succeed:
                logger.error(
                    f"Withdrawal simulation failed | Step {step_id} | "
                    f"Reason: {simulation.failure_reason}"
                )
                raise WithdrawalSimulationFailed(
                    f"Simulation failed for step {step_id}: {simulation.failure_reason}"
                )
            
            # STEP 4: CRITICAL - Mainnet safety check
            if is_mainnet():
                if not self.network_mode.check_mainnet_allowed(self.db):
                    logger.critical(
                        f"⚠️ MAINNET WITHDRAWAL BLOCKED | Step {step_id} | "
                        f"Safety gates not passed"
                    )
                    
                    self.telegram.send_alert(
                        severity='critical',
                        message=f"🚨 MAINNET WITHDRAWAL BLOCKED: Step {step_id}",
                        details={
                            'Wallet': step['address'][:10] + '...',
                            'Amount': f"${step['amount_usdt']}",
                            'Reason': 'Safety gates not passed'
                        }
                    )
                    
                    raise MainnetWithdrawalNotAllowed(
                        "BLOCKED: Mainnet withdrawals require all safety gates to be passed"
                    )
                
                # Extra warning for mainnet
                logger.warning(
                    f"⚠️ MAINNET WITHDRAWAL | Step {step_id} | "
                    f"Wallet: {step['address'][:10]}... | "
                    f"Amount: ${step['amount_usdt']}"
                )
            
            # STEP 5: Update status to 'executing'
            self.db.execute_query(
                "UPDATE withdrawal_steps SET status = 'executing' WHERE id = %s",
                (step_id,)
            )
            
            logger.info(f"Executing withdrawal step {step_id}")
            
            # STEP 6: OLD DRY RUN MODE (for  backward compatibility)
            if self.dry_run:
                logger.info(f"[LEGACY DRY RUN] Would execute withdrawal step {step_id}")
                
                self.db.execute_query(
                    """
                    UPDATE withdrawal_steps 
                    SET status = 'completed', 
                        executed_at = NOW(),
                        tx_hash = 'DRY_RUN_TX_HASH'
                    WHERE id = %s
                    """,
                    (step_id,)
                )
                
                # Update plan current_step
                self.db.execute_query(
                    """
                    UPDATE withdrawal_plans 
                    SET current_step = %s, updated_at = NOW()
                    WHERE id = %s
                    """,
                    (step['step_number'], step['withdrawal_plan_id'])
                )
                
                # Log event
                self.db.log_system_event(
                    event_type='withdrawal_completed',
                    severity='info',
                    message=f"[DRY RUN] Withdrawal step {step_id} completed",
                    metadata={
                        'wallet_id': step['wallet_id'],
                        'amount_usdt': str(step['amount_usdt']),
                        'dry_run': True
                    }
                )
                
                return True
            
            # REAL EXECUTION
            # Get worker details
            worker = self.db.execute_query(
                "SELECT * FROM worker_nodes WHERE id = %s",
                (step['worker_id'],),
                fetch='one'
            )
            
            if not worker:
                raise ValueError(f"Worker {step['worker_id']} not found")
            
            # Send transaction via Worker API
            response = self._send_to_worker(
                worker_url=worker['api_url'],
                wallet_address=step['address'],
                destination=step['destination_address'],
                amount_usdt=step['amount_usdt']
            )
            
            if response['status'] == 'success':
                tx_hash = response.get('tx_hash', '')
                
                # Update step with tx_hash
                self.db.execute_query(
                    """
                    UPDATE withdrawal_steps 
                    SET status = 'completed', 
                        executed_at = NOW(),
                        tx_hash = %s
                    WHERE id = %s
                    """,
                    (tx_hash, step_id)
                )
                
                # Update plan current_step
                self.db.execute_query(
                    """
                    UPDATE withdrawal_plans 
                    SET current_step = %s, updated_at = NOW()
                    WHERE id = %s
                    """,
                    (step['step_number'], step['withdrawal_plan_id'])
                )
                
                # Log event
                self.db.log_system_event(
                    event_type='withdrawal_completed',
                    severity='info',
                    message=f"Withdrawal step {step_id} completed",
                    metadata={
                        'wallet_id': step['wallet_id'],
                        'amount_usdt': str(step['amount_usdt']),
                        'tx_hash': tx_hash
                    }
                )
                
                # Send Telegram confirmation
                total_steps = self._get_total_steps(step['withdrawal_plan_id'])
                
                self.telegram.send_alert(
                    severity='info',
                    message=f"✅ Withdrawal step {step_id} completed",
                    details={
                        'Wallet': step['address'][:10] + '...',
                        'Amount': f"{step['amount_usdt']} USDT",
                        'TX Hash': tx_hash[:10] + '...' if tx_hash else 'N/A',
                        'Step': f"{step['step_number']}/{total_steps}"
                    }
                )
                
                logger.info(
                    f"Withdrawal step {step_id} completed | "
                    f"TX: {tx_hash[:10] if tx_hash else 'N/A'}..."
                )
                return True
            
            else:
                # Transaction failed
                error_msg = response.get('error', 'Unknown error')
                
                self.db.execute_query(
                    """
                    UPDATE withdrawal_steps 
                    SET status = 'failed'
                    WHERE id = %s
                    """,
                    (step_id,)
                )
                
                # Send Telegram alert
                self.telegram.send_alert(
                    severity='error',
                    message=f"❌ Withdrawal step {step_id} failed",
                    details={
                        'Error': error_msg,
                        'Wallet': step['address'][:10] + '...'
                    }
                )
                
                logger.error(
                    f"Withdrawal step {step_id} failed | "
                    f"Error: {error_msg}"
                )
                return False
        
        except Exception as e:
            logger.error(f"Error executing withdrawal step {step_id}: {e}")
            
            # Rollback to 'approved' status for retry
            try:
                self.db.execute_query(
                    "UPDATE withdrawal_steps SET status = 'approved' WHERE id = %s",
                    (step_id,)
                )
            except Exception as rollback_error:
                logger.error(f"Failed to rollback step {step_id}: {rollback_error}")
            
            return False
    
    def _calculate_scheduled_time(
        self,
        step_number: int,
        strategy: TierStrategy
    ) -> datetime:
        """
        Calculate scheduled_at timestamp with Gaussian randomization.
        
        Args:
            step_number: 1, 2, 3, or 4
            strategy: TierStrategy instance
        
        Returns:
            datetime (UTC)
        
        Anti-Sybil:
            - Tier A: 30-60 days between steps (mean=45, std=7.5)
            - Tier B: 21-45 days (mean=33, std=6)
            - Tier C: 14-30 days (mean=22, std=4)
        """
        import numpy as np
        
        delay_days = strategy.get_next_delay_days(step_number)
        
        return datetime.now(timezone.utc) + timedelta(days=delay_days)
    
    def _calculate_amount(self, step: Dict) -> Decimal:
        """
        Calculate withdrawal amount in USDT for a step.
        
        Args:
            step: Step dict from database
        
        Returns:
            Decimal amount in USDT
        
        Logic:
        1. Get wallet's total balance (ETH + stablecoins + airdrop tokens)
        2. Convert to USDT equivalent
        3. Apply step percentage
        4. Subtract gas fees
        """
        # Get wallet ID from step
        wallet_id = step.get('wallet_id')
        chain = step.get('chain', 'base')
        
        if not wallet_id:
            return Decimal('0.00')
        
        # Get wallet address
        wallet = self.db.execute_query(
            "SELECT address FROM wallets WHERE id = %s",
            (wallet_id,),
            fetch='one'
        )
        
        if not wallet:
            return Decimal('0.00')
        
        # Get RPC URL from database
        rpc_config = self.db.execute_query(
            """
            SELECT url FROM chain_rpc_endpoints 
            WHERE chain = %s AND is_active = TRUE 
            LIMIT 1
            """,
            (chain,),
            fetch='one'
        )
        
        if rpc_config:
            rpc_url = rpc_config['url']
        else:
            from infrastructure.network_mode import SEPOLIA_CONFIG
            rpc_url = SEPOLIA_CONFIG['rpc_urls'][0] if chain == 'sepolia' else f"https://mainnet.{chain}.org"
        
        # Fetch real balance via RPC with proxy (anti-Sybil compliance)
        from web3 import Web3
        from infrastructure.price_oracle import get_eth_price_sync
        from infrastructure.identity_manager import get_curl_session
        from activity.proxy_manager import ProxyManager
        
        # Get proxy for this wallet
        proxy_manager = ProxyManager(self.db)
        proxy_config = proxy_manager.get_wallet_proxy(wallet_id)
        proxy_url = proxy_manager.build_proxy_url(proxy_config) if proxy_config else None
        
        # Create Web3 session with proxy
        session = get_curl_session(wallet_id=wallet_id, proxy_url=proxy_url)
        w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={'timeout': 10}, session=session))
        
        total_balance_usdt = Decimal('0.00')
        
        if w3.is_connected():
            balance_wei = w3.eth.get_balance(Web3.to_checksum_address(wallet['address']))
            balance_eth = Decimal(str(w3.from_wei(balance_wei, 'ether')))
            eth_price = get_eth_price_sync(self.db)
            total_balance_usdt = balance_eth * eth_price
        else:
            logger.warning(f"Cannot connect to RPC for balance: {rpc_url}")
        
        # Apply percentage
        percentage = Decimal(str(step.get('percentage', 0)))
        amount = total_balance_usdt * (percentage / Decimal('100'))
        
        # Subtract estimated gas fees ($2-5)
        gas_fee = Decimal('3.50')
        amount -= gas_fee
        
        return max(Decimal('0'), amount)
    
    def _send_to_worker(
        self,
        worker_url: str,
        wallet_address: str,
        destination: str,
        amount_usdt: Decimal
    ) -> Dict:
        """
        Send withdrawal transaction to Worker via JWT API.
        
        Args:
            worker_url: Worker API URL (http://worker_ip:5000)
            wallet_address: Source wallet
            destination: Destination address
            amount_usdt: Amount in USDT
        
        Returns:
            Dict: {'status': 'success', 'tx_hash': '0x...'}
                  or {'status': 'error', 'error': 'reason'}
        """
        from curl_cffi import requests
        
        # Get JWT token
        jwt_token = self._get_jwt_token()
        
        # Prepare payload
        payload = {
            'wallet_address': wallet_address,
            'destination': destination,
            'amount_usdt': str(amount_usdt),
            'operation': 'withdrawal'
        }
        
        headers = {
            'Authorization': f'Bearer {jwt_token}',
            'Content-Type': 'application/json'
        }
        
        try:
            response = requests.post(
                f"{worker_url}/api/execute_withdrawal",
                json=payload,
                headers=headers,
                timeout=30
            )
            
            if response.status_code == 200:
                return response.json()
            else:
                return {
                    'status': 'error',
                    'error': f"HTTP {response.status_code}: {response.text}"
                }
        
        except Exception as e:
            return {'status': 'error', 'error': str(e)}
    
    def _get_jwt_token(self) -> str:
        """
        Get JWT token for Worker API authentication.
        
        Returns:
            JWT token string
        """
        # TODO: Implement actual JWT token retrieval
        # This would use the JWT_SECRET from .env
        
        import jwt
        from datetime import datetime, timedelta
        
        JWT_SECRET = os.getenv('JWT_SECRET')
        if not JWT_SECRET:
            raise ValueError("JWT_SECRET not set in .env")
        
        payload = {
            'sub': 'master_node',
            'exp': datetime.now(timezone.utc) + timedelta(hours=1)
        }
        
        return jwt.encode(payload, JWT_SECRET, algorithm='HS256')
    
    def _get_total_steps(self, plan_id: int) -> int:
        """Get total steps for a withdrawal plan."""
        result = self.db.execute_query(
            "SELECT total_steps FROM withdrawal_plans WHERE id = %s",
            (plan_id,),
            fetch='one'
        )
        return result['total_steps'] if result else 0
    
    def get_pending_approvals(self) -> List[Dict]:
        """
        Get all withdrawal steps awaiting approval.
        
        Returns:
            List of dicts with step details
        
        Used by:
            Telegram bot /status command
        """
        query = """
            SELECT ws.id, ws.step_number, ws.amount_usdt, ws.scheduled_at,
                   w.address, w.tier
            FROM withdrawal_steps ws
            JOIN withdrawal_plans wp ON ws.withdrawal_plan_id = wp.id
            JOIN wallets w ON wp.wallet_id = w.id
            WHERE ws.status = 'pending_approval'
            ORDER BY ws.scheduled_at ASC
        """
        
        return self.db.execute_query(query, fetch='all')
    
    def get_withdrawal_stats(self) -> Dict:
        """
        Get withdrawal statistics for the system.
        
        Returns:
            Dict with statistics
        """
        stats = {}
        
        # Total plans
        result = self.db.execute_query(
            "SELECT COUNT(*) as total FROM withdrawal_plans",
            fetch='one'
        )
        stats['total_plans'] = result['total'] if result else 0
        
        # Plans by status
        result = self.db.execute_query(
            """
            SELECT status, COUNT(*) as count 
            FROM withdrawal_plans 
            GROUP BY status
            """,
            fetch='all'
        )
        stats['plans_by_status'] = {r['status']: r['count'] for r in result}
        
        # Steps by status
        result = self.db.execute_query(
            """
            SELECT status, COUNT(*) as count 
            FROM withdrawal_steps 
            GROUP BY status
            """,
            fetch='all'
        )
        stats['steps_by_status'] = {r['status']: r['count'] for r in result}
        
        # Pending approvals
        result = self.db.execute_query(
            "SELECT COUNT(*) as count FROM withdrawal_steps WHERE status = 'pending_approval'",
            fetch='one'
        )
        stats['pending_approvals'] = result['count'] if result else 0
        
        return stats
    
    def cancel_withdrawal_plan(self, plan_id: int, reason: str) -> bool:
        """
        Cancel a withdrawal plan.
        
        Args:
            plan_id: Withdrawal plan ID
            reason: Cancellation reason
        
        Returns:
            True if successful
        """
        try:
            # Update plan status
            self.db.execute_query(
                "UPDATE withdrawal_plans SET status = 'rejected' WHERE id = %s",
                (plan_id,)
            )
            
            # Update all steps
            self.db.execute_query(
                "UPDATE withdrawal_steps SET status = 'rejected' WHERE withdrawal_plan_id = %s",
                (plan_id,)
            )
            
            # Log event
            self.db.log_system_event(
                event_type='withdrawal_plan_cancelled',
                severity='warning',
                message=f"Withdrawal plan {plan_id} cancelled",
                metadata={'reason': reason}
            )
            
            logger.warning(f"Withdrawal plan {plan_id} cancelled | Reason: {reason}")
            return True
        
        except Exception as e:
            logger.error(f"Error cancelling withdrawal plan {plan_id}: {e}")
            return False


# =============================================================================
# STANDALONE FUNCTIONS
# =============================================================================

def create_withdrawal_plan(
    db_manager,
    wallet_id: int,
    destination_address: str,
    trigger_type: str = 'airdrop_detected'
) -> int:
    """
    Convenience function to create withdrawal plan.
    
    Args:
        db_manager: Database manager
        wallet_id: Wallet ID
        destination_address: Destination address
        trigger_type: Trigger type
    
    Returns:
        Plan ID
    """
    # This would need telegram_bot passed in real implementation
    # For now, return a placeholder
    raise NotImplementedError(
        "Use WithdrawalOrchestrator class for full functionality"
    )


# =============================================================================
# TESTS
# =============================================================================

if __name__ == '__main__':
    import pytest
    from decimal import Decimal
    
    # Mock database manager for testing
    class MockDBManager:
        def __init__(self):
            self.wallets = {
                1: {'id': 1, 'address': '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb5', 'tier': 'A', 'worker_id': 1},
                2: {'id': 2, 'address': '0x1234567890abcdef1234567890abcdef12345678', 'tier': 'B', 'worker_id': 1},
                3: {'id': 3, 'address': '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd', 'tier': 'C', 'worker_id': 1}
            }
            self.plans = []
            self.steps = []
            self.plan_id_counter = 1
            self.step_id_counter = 1
        
        def execute_query(self, query, params, fetch='one'):
            # Handle INSERT with RETURNING
            if 'INSERT INTO withdrawal_plans' in query:
                plan = {
                    'id': self.plan_id_counter,
                    'wallet_id': params[0],
                    'tier': params[1],
                    'total_steps': params[2],
                    'status': 'planned'
                }
                self.plans.append(plan)
                self.plan_id_counter += 1
                return {'id': plan['id']}
            
            # Handle INSERT INTO withdrawal_steps
            if 'INSERT INTO withdrawal_steps' in query:
                step = {
                    'id': self.step_id_counter,
                    'withdrawal_plan_id': params[0],
                    'step_number': params[1],
                    'percentage': params[2],
                    'destination_address': params[3],
                    'scheduled_at': params[4],
                    'status': 'planned'
                }
                self.steps.append(step)
                self.step_id_counter += 1
                return None
            
            # Handle SELECT from wallets
            if 'FROM wallets' in query:
                wallet_id = params[0]
                return self.wallets.get(wallet_id)
            
            # Handle SELECT total_steps
            if 'total_steps' in query:
                plan_id = params[0]
                for plan in self.plans:
                    if plan['id'] == plan_id:
                        return {'total_steps': plan['total_steps']}
                return {'total_steps': 0}
            
            return None
        
        def log_system_event(self, event_type, severity, message, details):
            print(f"[EVENT] {event_type}: {message}")
    
    # Mock Telegram bot for testing
    class MockTelegramBot:
        def send_withdrawal_request(self, step_id, wallet_address, amount, destination, step_number, total_steps):
            print(f"[TELEGRAM] Withdrawal request: step {step_id}, ${amount}")
        
        def send_alert(self, severity, message, details=None):
            print(f"[TELEGRAM] Alert ({severity}): {message}")
    
    def test_orchestrator_initialization():
        """Test orchestrator initialization."""
        db = MockDBManager()
        telegram = MockTelegramBot()
        
        orchestrator = WithdrawalOrchestrator(db, telegram, dry_run=True)
        
        assert orchestrator.dry_run is True
        assert orchestrator.db is db
        assert orchestrator.telegram is telegram
        print("✅ Orchestrator initialization test passed")
    
    def test_create_withdrawal_plan_tier_a():
        """Test creating withdrawal plan for Tier A."""
        db = MockDBManager()
        telegram = MockTelegramBot()
        
        orchestrator = WithdrawalOrchestrator(db, telegram, dry_run=True)
        
        plan_id = orchestrator.create_withdrawal_plan(
            wallet_id=1,
            destination_address='0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb5'
        )
        
        assert plan_id > 0
        assert len(db.plans) == 1
        assert db.plans[0]['tier'] == 'A'
        assert db.plans[0]['total_steps'] == 4
        assert len(db.steps) == 4  # 4 steps for Tier A
        
        print("✅ Create withdrawal plan Tier A test passed")
    
    def test_create_withdrawal_plan_tier_b():
        """Test creating withdrawal plan for Tier B."""
        db = MockDBManager()
        telegram = MockTelegramBot()
        
        orchestrator = WithdrawalOrchestrator(db, telegram, dry_run=True)
        
        plan_id = orchestrator.create_withdrawal_plan(
            wallet_id=2,
            destination_address='0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb5'
        )
        
        assert plan_id > 0
        assert db.plans[0]['tier'] == 'B'
        assert db.plans[0]['total_steps'] == 3
        assert len(db.steps) == 3  # 3 steps for Tier B
        
        print("✅ Create withdrawal plan Tier B test passed")
    
    def test_create_withdrawal_plan_tier_c():
        """Test creating withdrawal plan for Tier C."""
        db = MockDBManager()
        telegram = MockTelegramBot()
        
        orchestrator = WithdrawalOrchestrator(db, telegram, dry_run=True)
        
        plan_id = orchestrator.create_withdrawal_plan(
            wallet_id=3,
            destination_address='0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb5'
        )
        
        assert plan_id > 0
        assert db.plans[0]['tier'] == 'C'
        assert db.plans[0]['total_steps'] == 2
        assert len(db.steps) == 2  # 2 steps for Tier C
        
        print("✅ Create withdrawal plan Tier C test passed")
    
    def test_get_withdrawal_stats():
        """Test getting withdrawal statistics."""
        db = MockDBManager()
        telegram = MockTelegramBot()
        
        orchestrator = WithdrawalOrchestrator(db, telegram, dry_run=True)
        
        # Create some plans
        orchestrator.create_withdrawal_plan(1, '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb5')
        orchestrator.create_withdrawal_plan(2, '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb5')
        
        stats = orchestrator.get_withdrawal_stats()
        
        assert stats['total_plans'] == 2
        assert 'plans_by_status' in stats
        assert 'steps_by_status' in stats
        
        print("✅ Get withdrawal stats test passed")
    
    # Run tests
    print("Running withdrawal orchestrator tests...\n")
    test_orchestrator_initialization()
    test_create_withdrawal_plan_tier_a()
    test_create_withdrawal_plan_tier_b()
    test_create_withdrawal_plan_tier_c()
    test_get_withdrawal_stats()
    print("\n🎉 All tests passed!")