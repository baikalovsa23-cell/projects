#!/usr/bin/env python3
"""
Direct Funding Engine v3.1 — Interleaved CEX Withdrawals
===========================================================
Direct CEX → wallet withdrawals with interleaved execution.

ELIMINATES Star Patterns by:
- No intermediate wallets
- Cross-exchange interleaving (no single-C bundles)
- 7-day temporal spread (Gaussian delays 2-10h)
- Variable cluster sizes (3-7 wallets per chain)

ENHANCED v3.1 (2026-03-08):
- Gas-based Triggering: DYNAMIC thresholds via GasLogic (NO HARDCODE!)
- Amount precision: hard limit 6 decimal places
- ChainId-based operations (no network name dependencies)

Author: Airdrop Farming System v4.0
Created: 2026-03-01
Migration: 026_direct_funding_architecture.sql, 034_gas_logic_refactoring.sql
"""

import os
import random
import numpy as np
from decimal import Decimal, ROUND_HALF_UP
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass
from loguru import logger
import asyncio

from database.db_manager import DatabaseManager
from funding.cex_integration import CEXManager
from cryptography.fernet import Fernet
from infrastructure.network_mode import NetworkModeManager, NetworkMode, is_dry_run, is_mainnet
from infrastructure.simulator import TransactionSimulator, SimulationResult
from activity.adaptive import AdaptiveGasController as GasManager, GasStatus, NetworkType


# =============================================================================
# ANTI-SYBIL CONFIGURATION (v3.2)
# =============================================================================

# CEX Whitelist Waves: Spread 90 addresses over 22 days in 3 waves
# Avoids "burst whitelist" pattern that triggers Sybil detection
CEX_WHITELIST_WAVES = [
    {'wave': 1, 'wallets': 30, 'start_day': 1, 'duration_days': 7},     # Wave 1: days 1-7
    {'wave': 2, 'wallets': 30, 'start_day': 8, 'duration_days': 7},     # Wave 2: days 8-14
    {'wave': 3, 'wallets': 30, 'start_day': 15, 'duration_days': 7},    # Wave 3: days 15-21
]
# Total: 22 days for 90 addresses (instead of 10 days previously)


# Amount precision: 6 decimal places max
AMOUNT_DECIMAL_PLACES = 6

# Max bridge fee threshold (configurable via env)
MAX_BRIDGE_FEE_USDT = float(os.getenv('BRIDGE_MAX_FEE', 1.0))


@dataclass
class FundingDryRunResult:
    """Result for dry-run funding operations."""
    simulation: 'SimulationResult'
    operation: str
    is_dry_run: bool = True
    cex_withdrawal_id: Optional[str] = None
    tx_hash: Optional[str] = None


@dataclass
class TaskResult:
    """Result of prepare_funding_task."""
    status: str  # 'ready', 'sleep', 'retry'
    route: Optional[Dict] = None
    retry_after: Optional[timedelta] = None
    reason: Optional[str] = None
    gas_result: Optional[Dict] = None


class TaskStatus:
    """Task status constants."""
    READY = 'ready'
    SLEEP = 'sleep'
    RETRY = 'retry'


class FundingSimulationFailed(Exception):
    """Raised when funding simulation fails."""
    pass


class MainnetFundingNotAllowed(Exception):
    """Raised when mainnet funding attempted without safety gates."""
    pass


class HighGasPriceDetected(Exception):
    """Raised when gas price exceeds threshold and withdrawal should be delayed."""
    pass


class BridgeFeeTooHigh(Exception):
    """Raised when bridge fee exceeds threshold."""
    pass


class DirectFundingEngineV3:
    """
    Direct funding engine with interleaved CEX withdrawals (v3.1).
    
    Anti-Sybil Features:
    - NO intermediate wallets (Star patterns eliminated)
    - Interleaved execution across 5 exchanges
    - 21-day temporal spread (v3.2: 7→21 days + jitter)
    - Variable cluster sizes (3-7 wallets per chain)
    - Geo-chaos (30/30/30 NL/IS/CA proxy distribution)
    - Network diversity (6 L2 networks)
    - CEX whitelist waves (v3.2: 3 waves over 22 days)
    
    Enhanced v3.1:
    - Gas-based Triggering: DYNAMIC thresholds via GasLogic
    - Amount precision: hard limit 6 decimal places
    - ChainId-based operations (no hardcoded network names)
    """
    
    # Network name to chain_id mapping (for backward compatibility)
    NETWORK_TO_CHAIN_ID = {
        'ethereum': 1,
        'arbitrum': 42161,
        'base': 8453,
        'optimism': 10,
        'polygon': 137,
        'bnb chain': 56,
        'bsc': 56,
        'bnbchain': 56,
        'ink': 57073,
        'megaeth': 420420,
        'zksync': 324,
        'scroll': 534352,
        'linea': 59144,
        'mantle': 5000,
    }
    
    def __init__(self, fernet_key: Optional[str] = None):
        self.db = DatabaseManager()
        self.cex = CEXManager()
        
        fernet_key = fernet_key or os.getenv('FERNET_KEY')
        if isinstance(fernet_key, str):
            fernet_key = fernet_key.encode()
        self.fernet = Fernet(fernet_key)
        
        # Initialize network mode and simulator for dry-run support
        self.network_mode = NetworkModeManager()
        self.simulator = TransactionSimulator(self.db, self.network_mode)
        
        # Initialize GasManager for dynamic gas thresholds
        self.gas_manager = GasManager(self.db)
        
        # Log current network mode at startup
        current_mode = self.network_mode.get_mode()
        logger.info(
            f"DirectFundingEngineV3 initialized | "
            f"Network mode: {current_mode.name} | "
            f"Dry-run: {is_dry_run()} | "
            f"Mainnet: {is_mainnet()} | "
            f"Max bridge fee: ${MAX_BRIDGE_FEE_USDT}"
        )
    
    @staticmethod
    def _round_amount(amount: float, decimals: int = AMOUNT_DECIMAL_PLACES) -> float:
        """
        Round amount to specified decimal places.
        
        Uses ROUND_HALF_UP for consistent rounding behavior.
        
        Args:
            amount: Amount to round
            decimals: Number of decimal places (default: 6)
        
        Returns:
            Rounded amount
        
        Example:
            >>> DirectFundingEngineV3._round_amount(19.123456789)
            19.123457
        """
        if amount == 0:
            return 0.0
        
        decimal_amount = Decimal(str(amount))
        quantize_str = '0.' + '0' * decimals
        rounded = decimal_amount.quantize(
            Decimal(quantize_str),
            rounding=ROUND_HALF_UP
        )
        return float(rounded)
    
    def _network_to_chain_id(self, network: str) -> int:
        """
        Convert network name to chain_id.
        
        Args:
            network: Network name (e.g., 'Arbitrum', 'Base')
        
        Returns:
            Chain ID (e.g., 42161, 8453)
        """
        network_lower = network.lower().strip()
        return self.NETWORK_TO_CHAIN_ID.get(network_lower, 0)
    
    async def check_gas_viability(
        self, 
        network: str
    ) -> Tuple[bool, float, Dict]:
        """
        Check if gas is acceptable for a network.
        
        Uses GasLogic for dynamic threshold calculation.
        
        Args:
            network: Network name
        
        Returns:
            Tuple of (is_ok, extra_delay_minutes, gas_info)
        """
        chain_id = self._network_to_chain_id(network)
        
        if chain_id == 0:
            logger.warning(f"Unknown network: {network}, skipping gas check")
            return True, 0.0, {'error': 'unknown_network'}
        
        result = await self.gas_manager.check_gas_viability(chain_id)
        
        gas_info = {
            'chain_id': chain_id,
            'current_gwei': result.current_gwei,
            'threshold_gwei': result.threshold_gwei,
            'network_type': result.network_type.value,
            'status': result.status.value,
            'ma_24h_available': result.ma_24h_available
        }
        
        if result.status == GasStatus.HIGH_GAS:
            return False, result.extra_delay_minutes, gas_info
        
        return True, 0.0, gas_info
    
    def _generate_variable_cluster_sizes(self, total_wallets: int = 90) -> List[int]:
        """
        Generate variable cluster sizes that sum to total_wallets.
        
        Args:
            total_wallets: Total wallets to distribute (default: 90)
        
        Returns:
            List of cluster sizes (e.g., [5, 3, 7, 4, 6, ...])
        """
        sizes = []
        remaining = total_wallets
        
        while remaining > 0:
            if remaining <= 7:
                sizes.append(remaining)
                break
            
            size = int(np.random.normal(5.0, 1.2))
            size = max(3, min(7, size))
            
            if remaining - size < 3 and remaining - size > 0:
                size = remaining
            
            sizes.append(size)
            remaining -= size
        
        random.shuffle(sizes)
        
        logger.info(
            f"Variable cluster sizes generated | "
            f"Clusters: {len(sizes)} | "
            f"Sizes: {sizes} | "
            f"Total: {sum(sizes)}"
        )
        
        return sizes
    
    def setup_direct_funding_with_interleaving(
        self,
        total_wallets: int = 90,
        duration_days: int = 21,  # Anti-Sybil: 7 → 21 days (3 weeks)
        duration_jitter_days: int = 7  # Anti-Sybil: random ±7 days per chain
    ) -> Dict:
        """
        Setup DIRECT CEX → wallet funding with interleaved execution (v3.1).
        
        Args:
            total_wallets: Total wallets to fund (default: 90)
            duration_days: Duration to spread funding over (default: 21 days)
            duration_jitter_days: Random jitter per chain (default: ±7 days)
        
        Returns:
            Dict with statistics
        
        Anti-Sybil v3.2:
            - Extended window 7→21 days to avoid "burst funding" pattern
            - Added jitter to prevent synchronized chain funding
        """
        logger.info("=" * 70)
        logger.info("Direct Funding Setup v3.1 (Dynamic Gas Logic)")
        logger.info("=" * 70)
        
        # STEP 1: Generate variable cluster sizes
        cluster_sizes = self._generate_variable_cluster_sizes(total_wallets)
        num_chains = len(cluster_sizes)
        
        logger.info(f"Funding chains to create: {num_chains}")
        logger.info(f"Cluster sizes: {cluster_sizes}")
        
        # STEP 2: Get all wallets shuffled
        wallets = self.db.execute_query(
            "SELECT id, address, tier, worker_node_id FROM wallets ORDER BY id",
            fetch='all'
        )
        wallet_ids = [w['id'] for w in wallets]
        
        if len(wallet_ids) != total_wallets:
            raise ValueError(f"Expected {total_wallets} wallets, found {len(wallet_ids)}")
        
        random.shuffle(wallet_ids)
        
        # STEP 3: Assign wallets to chains
        wallet_idx = 0
        # Ink and MegaETH are NOT available for direct withdrawal on ANY exchange
        # Use only L2 networks that support direct CEX withdrawal
        networks = ['BNB Chain', 'Polygon', 'Base', 'Arbitrum', 'Optimism', 'zkSync']
        cex_exchanges = ['binance', 'bybit', 'okx', 'kucoin', 'mexc']
        
        used_subaccounts = set()
        chains_data = []
        withdrawals_data = []
        
        for chain_num, cluster_size in enumerate(cluster_sizes, start=1):
            chain_wallets = wallet_ids[wallet_idx:wallet_idx + cluster_size]
            wallet_idx += cluster_size
            
            network = random.choice(networks)
            cex_exchange = random.choice(cex_exchanges)
            
            subaccount = self.db.execute_query(
                """SELECT id, subaccount_name FROM cex_subaccounts
                   WHERE exchange = %s AND id NOT IN %s
                   ORDER BY RANDOM() LIMIT 1""",
                (cex_exchange, tuple(used_subaccounts) if used_subaccounts else (0,)),
                fetch='one'
            )
            
            if not subaccount:
                logger.error(f"No available subaccount for {cex_exchange}")
                continue
            
            subaccount_id = subaccount['id']
            used_subaccounts.add(subaccount_id)
            
            base_amount = Decimal('19.00') * cluster_size / 5
            
            chain_query = """
                INSERT INTO funding_chains (
                    chain_number, cex_subaccount_id, withdrawal_network,
                    base_amount_usdt, wallets_count, actual_wallet_count,
                    status
                ) VALUES (%s, %s, %s, %s, %s, %s, 'pending')
                RETURNING id
            """
            
            result = self.db.execute_query(
                chain_query,
                (chain_num, subaccount_id, network, float(base_amount), cluster_size, cluster_size),
                fetch='one'
            )
            
            funding_chain_id = result['id']
            
            chains_data.append({
                'id': funding_chain_id,
                'chain_number': chain_num,
                'cex_exchange': cex_exchange,
                'subaccount_id': subaccount_id,
                'network': network,
                'cluster_size': cluster_size
            })
            
            for wallet_id in chain_wallets:
                wallet = self.db.execute_query(
                    "SELECT address FROM wallets WHERE id = %s",
                    (wallet_id,),
                    fetch='one'
                )
                wallet_address = wallet['address']
                
                amount_per_wallet = base_amount / cluster_size
                noise = random.uniform(-0.25, 0.25)
                actual_amount_raw = float(amount_per_wallet * (1 + Decimal(str(noise))))
                actual_amount = self._round_amount(actual_amount_raw)
                
                withdrawal_query = """
                    INSERT INTO funding_withdrawals (
                        funding_chain_id, wallet_id, cex_subaccount_id,
                        withdrawal_network, amount_usdt, withdrawal_address,
                        direct_cex_withdrawal, status
                    ) VALUES (%s, %s, %s, %s, %s, %s, TRUE, 'planned')
                    RETURNING id
                """
                
                w_result = self.db.execute_query(
                    withdrawal_query,
                    (funding_chain_id, wallet_id, subaccount_id, network, actual_amount, wallet_address),
                    fetch='one'
                )
                
                withdrawals_data.append({
                    'id': w_result['id'],
                    'chain_id': funding_chain_id,
                    'wallet_id': wallet_id,
                    'subaccount_id': subaccount_id,
                    'exchange': cex_exchange,
                    'network': network,
                    'amount': actual_amount
                })
            
            logger.info(
                f"Chain {chain_num}/{num_chains} created | "
                f"Wallets: {cluster_size} | "
                f"CEX: {cex_exchange} ({subaccount['subaccount_name']}) | "
                f"Network: {network} | "
                f"Amount: ${float(base_amount):.1f}"
            )
        
        logger.success(f"Funding chains created: {len(chains_data)}")
        
        # STEP 4: Generate INTERLEAVED schedule
        logger.info("")
        logger.info("Generating interleaved schedule...")
        
        self._generate_interleaved_schedule(
            withdrawals_data=withdrawals_data,
            duration_days=duration_days
        )
        
        logger.success("✅ Direct funding setup complete!")
        logger.info("")
        logger.info(f"📊 Statistics:")
        logger.info(f"   - Funding chains: {len(chains_data)}")
        logger.info(f"   - Total withdrawals: {len(withdrawals_data)}")
        logger.info(f"   - Duration: {duration_days} days")
        logger.info(f"   - Exchanges used: {len(set(c['cex_exchange'] for c in chains_data))}")
        logger.info(f"   - Networks used: {len(set(c['network'] for c in chains_data))}")
        
        return {
            'chains': len(chains_data),
            'withdrawals': len(withdrawals_data),
            'duration': duration_days,
            'exchanges': len(set(c['cex_exchange'] for c in chains_data))
        }
    
    def _generate_interleaved_schedule(
        self,
        withdrawals_data: List[Dict],
        duration_days: int = 21,
        duration_jitter_days: int = 7
    ):
        """
        Generate interleaved schedule for withdrawals.
        
        Anti-Sybil v3.2:
            - Extended window 7→21 days
            - Added jitter per chain to prevent synchronized funding
        """
        logger.info(f"Generating interleaved schedule for {len(withdrawals_data)} withdrawals...")
        logger.info(f"Duration: {duration_days} days (±{duration_jitter_days} days jitter)")
        
        random.shuffle(withdrawals_data)
        
        # Group by chain for jitter assignment
        chain_ids = list(set(w['chain_id'] for w in withdrawals_data))
        chain_jitter = {cid: np.random.randint(0, duration_jitter_days) for cid in chain_ids}
        
        exchange_queues = {
            'binance': [],
            'bybit': [],
            'okx': [],
            'kucoin': [],
            'mexc': []
        }
        
        for w in withdrawals_data:
            exchange_queues[w['exchange']].append(w)
        
        interleaved_withdrawals = []
        round_num = 0
        position = 0
        
        while any(exchange_queues.values()):
            available_exchanges = [ex for ex, queue in exchange_queues.items() if queue]
            
            if not available_exchanges:
                break
            
            exchange = random.choice(available_exchanges)
            withdrawal = exchange_queues[exchange].pop(0)
            
            withdrawal['interleave_round'] = round_num
            withdrawal['interleave_position'] = position
            
            interleaved_withdrawals.append(withdrawal)
            
            position += 1
            
            if position >= random.randint(4, 6):
                round_num += 1
                position = 0
        
        logger.info(f"Interleaved into {round_num + 1} rounds")
        
        start_time = datetime.now(timezone.utc) + timedelta(hours=1)
        
        # Calculate base interval for spreading over duration_days
        total_minutes = duration_days * 24 * 60
        base_interval = total_minutes / len(interleaved_withdrawals)
        
        for i, withdrawal in enumerate(interleaved_withdrawals):
            # Get chain-specific jitter (in days)
            jitter_days = chain_jitter.get(withdrawal['chain_id'], 0)
            jitter_minutes = jitter_days * 24 * 60
            
            # Base position in schedule + Gaussian noise
            base_position = i * base_interval
            noise_minutes = np.random.normal(0, base_interval * 0.3)  # 30% noise
            
            # Additional random delays
            delay_minutes = random.uniform(60, 240)
            if random.random() < 0.25:
                delay_minutes = random.uniform(300, 600)
            
            # Skip night hours (03:00-06:00 local time enforcement)
            hour_offset = 0
            if start_time.hour in [2, 3, 4, 5]:
                hour_offset = random.uniform(20, 60)
            
            # Weekend slowdown
            weekend_offset = 0
            if start_time.weekday() in [5, 6]:
                if random.random() < 0.3:
                    weekend_offset = random.uniform(360, 720)
            
            # Calculate final scheduled time
            total_offset = base_position + noise_minutes + jitter_minutes + delay_minutes + hour_offset + weekend_offset
            scheduled_time = start_time + timedelta(minutes=total_offset)
            
            self.db.execute_query(
                """
                UPDATE funding_withdrawals
                SET cex_withdrawal_scheduled_at = %s,
                    interleave_round = %s,
                    interleave_position = %s
                WHERE id = %s
                """,
                (scheduled_time, withdrawal['interleave_round'], withdrawal['interleave_position'], withdrawal['id'])
            )
            
            if i % 10 == 0:
                logger.debug(
                    f"Scheduled {i}/{len(interleaved_withdrawals)} | "
                    f"Time: {scheduled_time.strftime('%Y-%m-%d %H:%M UTC')} | "
                    f"Delay: {delay_minutes/60:.1f}h"
                )
        
        total_duration_hours = (current_time - start_time).total_seconds() / 3600
        logger.success(
            f"Schedule generated | "
            f"Withdrawals: {len(interleaved_withdrawals)} | "
            f"Duration: {total_duration_hours/24:.1f} days | "
            f"Rounds: {round_num + 1}"
        )
    
    async def simulate_wallet_funding(
        self,
        wallet_address: str,
        amount_usd: float,
        chain: str
    ) -> SimulationResult:
        """Simulate wallet funding operation."""
        simulation = await self.simulator.simulate_funding(
            wallet_address=wallet_address,
            amount_usd=amount_usd
        )
        
        logger.info(
            f"Funding simulation | "
            f"Wallet: {wallet_address[:10]}... | "
            f"Amount: ${amount_usd:.2f} | "
            f"Chain: {chain} | "
            f"Success: {simulation.would_succeed}"
        )
        
        return simulation
    
    async def prepare_funding_task(
        self,
        wallet_id: int,
        target_network: str
    ) -> TaskResult:
        """
        Prepare funding task with gas validation.
        
        Chain of Command:
        1. Check gas (Dynamic via GasLogic)
        2. Return status (ready/sleep/retry)
        
        Args:
            wallet_id: Wallet database ID
            target_network: Target network name
        
        Returns:
            TaskResult with status and gas info
        """
        # Step 1: Check gas (Dynamic)
        is_ok, extra_delay, gas_info = await self.check_gas_viability(target_network)
        
        if not is_ok:
            logger.info(
                f"High gas for {target_network} | "
                f"Delay: {extra_delay:.0f} min | "
                f"Chain ID: {gas_info.get('chain_id')}"
            )
            return TaskResult(
                status=TaskStatus.SLEEP,
                retry_after=timedelta(minutes=extra_delay),
                gas_result=gas_info
            )
        
        # Step 2: All checks passed
        return TaskResult(
            status=TaskStatus.READY,
            gas_result=gas_info
        )
    
    async def execute_direct_cex_withdrawal(
        self,
        withdrawal_id: int,
        check_gas: bool = True
    ) -> Dict:
        """
        Execute a single direct CEX → wallet withdrawal.
        
        Enhanced v3.1: Uses GasLogic for dynamic gas thresholds.
        
        Args:
            withdrawal_id: ID from funding_withdrawals table
            check_gas: Whether to check gas price before execution (default: True)
        
        Returns:
            Dict with withdrawal result
        
        Raises:
            ValueError: If withdrawal not found or invalid
            HighGasPriceDetected: If gas price exceeds dynamic threshold
        """
        # Get withdrawal details
        withdrawal = self.db.execute_query(
            """
            SELECT fw.*, cs.exchange, cs.encrypted_api_credentials, w.address as wallet_address
            FROM funding_withdrawals fw
            JOIN cex_subaccounts cs ON fw.cex_subaccount_id = cs.id
            JOIN wallets w ON fw.wallet_id = w.id
            WHERE fw.id = %s AND fw.direct_cex_withdrawal = TRUE
            """,
            (withdrawal_id,),
            fetch='one'
        )
        
        if not withdrawal:
            raise ValueError(f"Direct withdrawal {withdrawal_id} not found")
        
        network = withdrawal['withdrawal_network']
        
        # GAS-BASED TRIGGERING (v3.1 - Dynamic via GasLogic)
        if check_gas:
            is_ok, extra_delay, gas_info = await self.check_gas_viability(network)
            
            if not is_ok:
                new_scheduled_time = datetime.now(timezone.utc) + timedelta(minutes=extra_delay)
                
                self.db.execute_query(
                    """
                    UPDATE funding_withdrawals
                    SET cex_withdrawal_scheduled_at = %s,
                        status = 'delayed_high_gas'
                    WHERE id = %s
                    """,
                    (new_scheduled_time, withdrawal_id)
                )
                
                logger.warning(
                    f"Withdrawal {withdrawal_id} delayed due to high gas | "
                    f"Network: {network} | "
                    f"Chain ID: {gas_info.get('chain_id')} | "
                    f"Current: {gas_info.get('current_gwei'):.4f} gwei | "
                    f"Threshold: {gas_info.get('threshold_gwei'):.4f} gwei | "
                    f"New scheduled time: {new_scheduled_time.strftime('%Y-%m-%d %H:%M UTC')}"
                )
                
                raise HighGasPriceDetected(
                    f"Gas price too high for {network} (chain_id={gas_info.get('chain_id')}). "
                    f"Current: {gas_info.get('current_gwei'):.4f} gwei, "
                    f"Threshold: {gas_info.get('threshold_gwei'):.4f} gwei. "
                    f"Withdrawal rescheduled to {new_scheduled_time.strftime('%Y-%m-%d %H:%M UTC')}"
                )
        
        # Simulate first
        simulation = await self.simulate_wallet_funding(
            wallet_address=withdrawal['wallet_address'],
            amount_usd=withdrawal['amount_usdt'],
            chain=network
        )
        
        # Check mode - return dry-run result if applicable
        if is_dry_run():
            logger.info(
                f"[DRY-RUN] Would execute direct withdrawal | "
                f"ID: {withdrawal_id} | "
                f"Exchange: {withdrawal['exchange']} | "
                f"Amount: ${withdrawal['amount_usdt']:.6f} | "
                f"Network: {network} | "
                f"To: {withdrawal['wallet_address'][:10]}..."
            )
            return {
                'withdrawal_id': withdrawal_id,
                'dry_run': True,
                'simulation': simulation
            }
        
        # Validate simulation
        if not simulation.would_succeed:
            raise FundingSimulationFailed(f"Simulation failed: {simulation.failure_reason}")
        
        # Safety check for mainnet
        if is_mainnet():
            if not self.network_mode.check_mainnet_allowed(self.db):
                raise MainnetFundingNotAllowed("Safety gates not passed for mainnet")
            logger.warning(
                f"[MAINNET] Real withdrawal | "
                f"Amount: ${withdrawal['amount_usdt']:.6f} | "
                f"To: {withdrawal['wallet_address'][:10]}..."
            )
        
        # Execute actual CEX withdrawal
        logger.info(
            f"Executing direct CEX withdrawal | "
            f"ID: {withdrawal_id} | "
            f"Exchange: {withdrawal['exchange']} | "
            f"Amount: ${withdrawal['amount_usdt']:.6f} | "
            f"Network: {network}"
        )
        
        # Update status to processing
        self.db.execute_query(
            "UPDATE funding_withdrawals SET status = 'processing' WHERE id = %s",
            (withdrawal_id,)
        )
        
        # Verify whitelist before withdrawal (safety check)
        # Note: Most exchanges don't expose whitelist via API, so this is informational
        whitelist_ok = self.cex.verify_whitelist(
            subaccount_id=withdrawal['cex_subaccount_id'],
            address=withdrawal['wallet_address']
        )
        
        if not whitelist_ok:
            # This shouldn't happen as verify_whitelist returns True by default
            # but we handle it for safety
            self.db.execute_query(
                "UPDATE funding_withdrawals SET status = 'failed' WHERE id = %s",
                (withdrawal_id,)
            )
            raise ValueError(
                f"Address {withdrawal['wallet_address'][:10]}... not whitelisted "
                f"on {withdrawal['exchange']}. Please whitelist manually."
            )
            
        # Check balance before withdrawal
        current_balance = self.cex.get_balance(withdrawal['cex_subaccount_id'])
        if current_balance.get('USDT', 0) < float(withdrawal['amount_usdt']):
            self.db.execute_query(
                "UPDATE funding_withdrawals SET status = 'failed', error_message = 'Insufficient balance' WHERE id = %s",
                (withdrawal_id,)
            )
            raise ValueError(
                f"Insufficient balance on CEX. Required: {withdrawal['amount_usdt']}, "
                f"Available: {current_balance.get('USDT', 0)}"
            )
        
        # Execute withdrawal via CEXManager
        try:
            cex_result = self.cex.withdraw(
                subaccount_id=withdrawal['cex_subaccount_id'],
                address=withdrawal['wallet_address'],
                amount=float(withdrawal['amount_usdt']),
                network=network
            )
            
            if not cex_result.success:
                # Withdrawal failed
                self.db.execute_query(
                    """
                    UPDATE funding_withdrawals
                    SET status = 'failed',
                        error_message = %s
                    WHERE id = %s
                    """,
                    (cex_result.error, withdrawal_id)
                )
                
                logger.error(
                    f"CEX withdrawal failed | "
                    f"ID: {withdrawal_id} | "
                    f"Error: {cex_result.error}"
                )
                
                return {
                    'withdrawal_id': withdrawal_id,
                    'exchange': withdrawal['exchange'],
                    'amount': float(withdrawal['amount_usdt']),
                    'network': network,
                    'wallet_address': withdrawal['wallet_address'],
                    'timestamp': datetime.now(timezone.utc),
                    'status': 'failed',
                    'error': cex_result.error
                }
            
            # Withdrawal successful - update database
            self.db.execute_query(
                """
                UPDATE funding_withdrawals
                SET status = 'completed',
                    cex_txid = %s,
                    completed_at = %s
                WHERE id = %s
                """,
                (cex_result.tx_id, datetime.now(timezone.utc), withdrawal_id)
            )
            
            # Update wallet's last_funded_at
            self.db.execute_query(
                """
                UPDATE wallets
                SET last_funded_at = %s,
                    status = 'active'
                WHERE id = %s
                """,
                (datetime.now(timezone.utc), withdrawal['wallet_id'])
            )
            
            logger.success(
                f"✅ CEX withdrawal completed | "
                f"ID: {withdrawal_id} | "
                f"TX: {cex_result.tx_id} | "
                f"Amount: ${cex_result.amount:.6f} | "
                f"Fee: ${cex_result.fee or 0:.6f} | "
                f"Network: {network}"
            )
            
            return {
                'withdrawal_id': withdrawal_id,
                'exchange': withdrawal['exchange'],
                'amount': float(cex_result.amount),
                'fee': float(cex_result.fee) if cex_result.fee else None,
                'network': network,
                'wallet_address': withdrawal['wallet_address'],
                'tx_id': cex_result.tx_id,
                'timestamp': datetime.now(timezone.utc),
                'status': 'completed'
            }
            
        except Exception as e:
            # Unexpected error during withdrawal
            self.db.execute_query(
                """
                UPDATE funding_withdrawals
                SET status = 'failed',
                    error_message = %s
                WHERE id = %s
                """,
                (str(e), withdrawal_id)
            )
            
            logger.exception(
                f"Unexpected error during CEX withdrawal | "
                f"ID: {withdrawal_id} | "
                f"Error: {e}"
            )
            
            raise
    
    async def get_gas_status(self, networks: Optional[List[str]] = None) -> Dict[str, Dict]:
        """
        Get current gas status for networks.
        
        Uses GasLogic for dynamic threshold calculation.
        
        Args:
            networks: List of networks to check (default: all supported)
        
        Returns:
            Dict mapping network name to gas status
        """
        if networks is None:
            networks = list(self.NETWORK_TO_CHAIN_ID.keys())
        
        result = {}
        
        for network in networks:
            chain_id = self._network_to_chain_id(network)
            
            if chain_id == 0:
                continue
            
            gas_result = await self.gas_manager.check_gas_viability(chain_id)
            
            result[network] = {
                'chain_id': chain_id,
                'current_gwei': round(gas_result.current_gwei, 6),
                'threshold_gwei': round(gas_result.threshold_gwei, 6),
                'network_type': gas_result.network_type.value,
                'is_high': gas_result.status == GasStatus.HIGH_GAS,
                'extra_delay_minutes': gas_result.extra_delay_minutes,
                'ma_24h_available': gas_result.ma_24h_available
            }
        
        return result


# ========== USAGE EXAMPLE ==========
if __name__ == '__main__':
    engine = DirectFundingEngineV3()
    result = engine.setup_direct_funding_with_interleaving(
        total_wallets=90,
        duration_days=7
    )
    print(f"✅ Setup complete | {result['withdrawals']} withdrawals over {result['duration']} days")
