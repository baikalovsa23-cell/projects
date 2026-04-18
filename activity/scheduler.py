#!/usr/bin/env python3
"""
Activity Scheduler — Модуль 11
===============================
Gaussian-планировщик транзакций для имитации человеческого поведения

КРИТИЧЕСКИ ВАЖНО ДЛЯ ANTI-SYBIL:
- Каждый кошелёк = уникальное расписание (Gaussian µ и σ зависят от персоны)
- НЕТ синхронности: если 2+ TX на одно время → сдвиг на 10-25 минут
- Bridge emulation: первая TX не ранее 12-24 часов после funding (P0 FIX 2026-02-28)
- skip_week_probability: шанс пропустить неделю целиком

Архитектура:
    ActivityScheduler → загружает персоны из БД
                      → генерирует недельное расписание
                      → сохраняет в weekly_plans + scheduled_transactions

Usage:
    # Генерация расписания для всех 90 кошельков
    python activity/scheduler.py generate-all --week 2026-03-03
    
    # Генерация для одного кошелька
    python activity/scheduler.py generate-one --wallet-id 42 --week 2026-03-03

Author: Airdrop Farming System v4.0
Created: 2026-02-25
"""

import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta, timezone
from decimal import Decimal
import random
import numpy as np
from loguru import logger
from infrastructure.env_loader import load_env

# Load .env file (supports both production and local dev)
load_env()

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from database.db_manager import DatabaseManager
from activity.bridge_manager import BridgeManager
from activity.adaptive import AdaptiveGasController


# =============================================================================
# CONFIGURATION
# =============================================================================

# Temporal isolation для предотвращения синхронности (минуты)
MIN_SYNC_OFFSET = 10
MAX_SYNC_OFFSET = 25

# P0 CRITICAL FIX (2026-02-28): Bridge emulation delay после funding
# OLD: 2-4 hours = UNREALISTIC (real users wait longer after bridge)
# NEW: 12-24 hours = HUMAN-LIKE behavior (users sleep, work, wait for gas)
# Impact: Prevents bridge→activity timing pattern detection (Sybil score +0.5)
MIN_BRIDGE_DELAY_HOURS = 12
MAX_BRIDGE_DELAY_HOURS = 24


# =============================================================================
# ACTIVITY SCHEDULER
# =============================================================================

class ActivityScheduler:
    """
    Генератор недельных расписаний транзакций с Gaussian распределением.
    
    Каждый кошелёк получает уникальное расписание на основе:
    - persona_type (ActiveTrader, CasualUser, WeekendWarrior, Ghost)
    - tx_per_week_mean и tx_per_week_stddev (Gaussian параметры)
    - preferred_hours (активные часы в UTC)
    - skip_week_probability (шанс пропустить неделю)
    """
    
    def __init__(self):
        self.db = DatabaseManager()
        self.gas_controller = AdaptiveGasController(self.db)
        logger.info("ActivityScheduler initialized with gas controller")
    
    def _get_wallet_timezone_offset(self, wallet_id: int) -> int:
        """
        Get wallet's UTC timezone offset from proxy_pool.
        
        P0 FIX (Migration 033): Timezone is taken from proxy_pool,
        NOT from worker_nodes. This ensures:
        - CA wallets use America/Toronto (UTC-5)
        - NL wallets use Europe/Amsterdam (UTC+1)
        - IS wallets use Atlantic/Reykjavik (UTC+0)
        
        Args:
            wallet_id: Wallet database ID
        
        Returns:
            UTC offset (-5 for CA, 0 for IS, 1 for NL)
        """
        query = """
            SELECT pp.utc_offset, pp.timezone, pp.country_code
            FROM wallets w
            JOIN proxy_pool pp ON w.proxy_id = pp.id
            WHERE w.id = %s
        """
        result = self.db.execute_query(query, (wallet_id,), fetch='one')
        
        if not result:
            logger.warning(f"Proxy timezone not found for wallet {wallet_id}, defaulting to 0")
            return 0
        
        logger.debug(
            f"Wallet {wallet_id} timezone | Country: {result['country_code']} | "
            f"Timezone: {result['timezone']} | UTC offset: {result['utc_offset']}"
        )
        
        return result['utc_offset']
    
    def _get_wallet_persona(self, wallet_id: int) -> Optional[Dict]:
        """
        Загрузить персону кошелька из БД.
        
        Args:
            wallet_id: ID кошелька
        
        Returns:
            Dict с данными персоны или None
        """
        query = """
            SELECT wp.*, w.address, w.tier, w.last_funded_at
            FROM wallet_personas wp
            JOIN wallets w ON w.id = wp.wallet_id
            WHERE wp.wallet_id = %s
        """
        persona = self.db.execute_query(query, (wallet_id,), fetch='one')
        
        if not persona:
            logger.error(f"Persona not found for wallet {wallet_id}")
            return None
        
        logger.debug(f"Loaded persona | Wallet: {wallet_id} | Type: {persona['persona_type']}")
        return persona
    
    def _check_bridge_emulation_delay(self, persona: Dict) -> bool:
        """
        Проверить bridge emulation delay.
        
        После получения средств с CEX, кошелёк должен подождать 2-4 часа
        перед первой активностью (имитация официального моста).
        
        Args:
            persona: Данные персоны кошелька
        
        Returns:
            True если можно планировать TX, False если нужно ждать
        """
        last_funded = persona.get('last_funded_at')
        
        if not last_funded:
            # Кошелёк ещё не финансировался → можно планировать,
            # но первая TX будет отложена в _generate_schedule()
            return True
        
        # Проверить: прошло ли MIN_BRIDGE_DELAY_HOURS с момента funding
        if isinstance(last_funded, str):
            last_funded = datetime.fromisoformat(last_funded.replace('Z', '+00:00'))
        
        delay_hours = (datetime.now(timezone.utc) - last_funded).total_seconds() / 3600
        
        if delay_hours < MIN_BRIDGE_DELAY_HOURS:
            logger.warning(
                f"Bridge emulation active | Wallet: {persona['wallet_id']} | "
                f"Funded {delay_hours:.1f}h ago | Need: {MIN_BRIDGE_DELAY_HOURS}h"
            )
            return False
        
        return True
    
    def _calculate_weekly_tx_count(self, persona: Dict) -> int:
        """
        Рассчитать количество транзакций на неделю (Gaussian).
        
        Args:
            persona: Данные персоны
        
        Returns:
            Количество транзакций (int, clipped к min=0)
        """
        mean = persona['tx_per_week_mean']
        stddev = persona['tx_per_week_stddev']
        
        # Gaussian sampling
        count = np.random.normal(mean, stddev)
        
        # Clip к разумным значениям (min=0, max=50 для ActiveTrader)
        count = int(np.clip(count, 0, 50))
        
        logger.debug(
            f"Weekly TX count calculated | Wallet: {persona['wallet_id']} | "
            f"Mean: {mean} | StdDev: {stddev} | Sampled: {count}"
        )
        
        return count
    
    def _should_skip_week(self, persona: Dict) -> bool:
        """
        Проверить нужно ли пропустить неделю (вероятностно).
        
        Args:
            persona: Данные персоны
        
        Returns:
            True если неделя пропускается
        """
        skip_prob = persona['skip_week_probability']
        roll = random.random()
        
        skip = roll < skip_prob
        
        if skip:
            logger.info(
                f"Week skipped | Wallet: {persona['wallet_id']} | "
                f"Probability: {skip_prob:.2%} | Roll: {roll:.2%}"
            )
        
        return skip
    
    def _generate_tx_timestamps(
        self,
        persona: Dict,
        week_start: datetime,
        count: int
    ) -> List[datetime]:
        """
        Сгенерировать timestamp'ы для транзакций недели.
        
        Распределяет транзакции по preferred_hours с учётом:
        - Timezone кошелька (UTC часы)
        - Случайное распределение по дням
        - Случайные минуты внутри часа
        
        Args:
            persona: Данные персоны
            week_start: Начало недели (datetime, Monday 00:00 UTC)
            count: Количество транзакций
        
        Returns:
            List[datetime] отсортированных timestamp'ов
        """
        preferred_hours = persona['preferred_hours']
        
        if not preferred_hours:
            logger.error(f"No preferred_hours for wallet {persona['wallet_id']}")
            # Fallback: случайные часы 10-22 UTC
            preferred_hours = list(range(10, 23))
        
        # CRITICAL: Get wallet timezone offset from proxy_pool (NOT worker_nodes!)
        # This ensures CA wallets use America/Toronto timezone for sleep window
        wallet_offset = self._get_wallet_timezone_offset(persona['wallet_id'])
        
        timestamps = []
        max_attempts = count * 10  # Prevent infinite loop
        attempts = 0
        
        while len(timestamps) < count and attempts < max_attempts:
            attempts += 1
            
            # Случайный день недели (0-6)
            day_offset = random.randint(0, 6)
            
            # P0 FIX 2026-03-01: Weekend activity check
            # Reduce weekend activity by ~40% (imitate human behavior)
            day_date = week_start + timedelta(days=day_offset)
            if day_date.weekday() in [5, 6]:  # Saturday=5, Sunday=6
                # 40% chance to skip weekend TX
                if random.random() < 0.4:
                    continue
            
            # Случайный час из preferred_hours
            hour = random.choice(preferred_hours)
            
            # Случайные минуты (0-59)
            minute = random.randint(0, 59)
            
            # Случайные секунды (0-59) для ещё большей рандомизации
            second = random.randint(0, 59)
            
            # Собрать timestamp
            tx_time = week_start + timedelta(
                days=day_offset,
                hours=hour,
                minutes=minute,
                seconds=second
            )
            
            # CRITICAL: Enforce sleep window (03:00-06:00 local time)
            # Convert to local time using wallet's proxy timezone offset
            # Example: CA wallet (UTC-5) at 10am UTC = 5am Toronto time (sleep window!)
            local_hour = (tx_time.hour + wallet_offset) % 24
            
            if local_hour in [3, 4, 5, 6]:
                # Skip this timestamp (falls in sleep window)
                logger.debug(
                    f"Skipping timestamp (sleep window) | UTC hour: {tx_time.hour} | "
                    f"Local hour: {local_hour} | Wallet: {persona['wallet_id']}"
                )
                continue
            
            timestamps.append(tx_time)
        
        if len(timestamps) < count:
            logger.warning(
                f"Could not generate full schedule (sleep window constraints) | "
                f"Wallet: {persona['wallet_id']} | Generated: {len(timestamps)}/{count}"
            )
        
        # Сортировать хронологически
        timestamps.sort()
        
        return timestamps
    
    def _apply_bridge_emulation_to_first_tx(
        self,
        timestamps: List[datetime],
        persona: Dict
    ) -> List[datetime]:
        """
        Применить bridge emulation delay к первой транзакции.
        
        Если кошелёк недавно получил средства с CEX (last_funded_at),
        первая транзакция должна быть отложена на 2-4 часа.
        
        Args:
            timestamps: Список timestamp'ов транзакций
            persona: Данные персоны
        
        Returns:
            Обновлённый список timestamp'ов
        """
        if not timestamps:
            return timestamps
        
        last_funded = persona.get('last_funded_at')
        
        if not last_funded:
            # Кошелёк не финансировался → пропустить
            return timestamps
        
        if isinstance(last_funded, str):
            last_funded = datetime.fromisoformat(last_funded.replace('Z', '+00:00'))
        
        # Минимальная задержка перед первой TX (Gaussian вместо uniform)
        # mean=18 hours, std=3 → covers 12-24 hour range (±2σ = 95% coverage)
        delay_hours = np.random.normal(18.0, 3.0)
        delay_hours = max(MIN_BRIDGE_DELAY_HOURS, min(MAX_BRIDGE_DELAY_HOURS, delay_hours))
        
        min_first_tx = last_funded + timedelta(hours=delay_hours)
        
        # Если первая TX запланирована раньше → перенести
        if timestamps[0] < min_first_tx:
            offset = min_first_tx - timestamps[0]
            logger.info(
                f"Bridge emulation applied | Wallet: {persona['wallet_id']} | "
                f"First TX delayed by {offset.total_seconds() / 3600:.1f}h"
            )
            timestamps[0] = min_first_tx
        
        return timestamps
    
    def _remove_sync_conflicts(
        self,
        wallet_id: int,
        timestamps: List[datetime]
    ) -> List[datetime]:
        """
        Удалить конфликты синхронности (anti-sync logic).
        
        Если 2+ транзакции разных кошельков запланированы на одно время
        (с точностью до минуты), одна из них сдвигается на 10-25 минут.
        
        Args:
            wallet_id: ID текущего кошелька
            timestamps: Список timestamp'ов
        
        Returns:
            Обновлённый список без конфликтов
        """
        updated = []
        
        for ts in timestamps:
            # Проверить существующие запланированные TX в этом времени
            # (с точностью до минуты)
            ts_minute = ts.replace(second=0, microsecond=0)
            
            query = """
                SELECT COUNT(*) as count
                FROM scheduled_transactions
                WHERE wallet_id != %s
                  AND scheduled_at >= %s
                  AND scheduled_at < %s
                  AND status = 'pending'
            """
            result = self.db.execute_query(
                query,
                (wallet_id, ts_minute, ts_minute + timedelta(minutes=1)),
                fetch='one'
            )
            
            conflict_count = result['count'] if result else 0
            
            if conflict_count > 0:
                # Конфликт! Сдвинуть на случайное время (Gaussian distribution)
                # Gaussian: mean=17.5 min (midpoint of 10-25), std=4 min
                offset_minutes = int(np.random.normal(17.5, 4))
                # Clamp to range [MIN_SYNC_OFFSET, MAX_SYNC_OFFSET]
                offset_minutes = max(MIN_SYNC_OFFSET, min(MAX_SYNC_OFFSET, offset_minutes))
                ts = ts + timedelta(minutes=offset_minutes)
                
                logger.warning(
                    f"Sync conflict resolved | Wallet: {wallet_id} | "
                    f"Shifted by {offset_minutes} minutes (Gaussian)"
                )
            
            updated.append(ts)
        
        return updated
    
    def _select_protocol_actions(self, persona: Dict, count: int) -> List[int]:
        """
        Выбрать protocol_actions для транзакций на основе tx_weights.
        
        Args:
            persona: Данные персоны
            count: Количество транзакций
        
        Returns:
            List[int] protocol_action_id
        """
        # Получить веса из персоны
        weights = {
            'swap': persona['tx_weight_swap'],
            'bridge': persona['tx_weight_bridge'],
            'liquidity': persona['tx_weight_liquidity'],
            'stake': persona['tx_weight_stake'],
            'nft': persona['tx_weight_nft']
        }
        
        # Получить доступные protocol_actions из БД
        query = """
            SELECT pa.id, pa.action_name, pa.tx_type
            FROM protocol_actions pa
            JOIN protocols p ON p.id = pa.protocol_id
            WHERE p.is_active = TRUE
              AND pa.is_enabled = TRUE
            ORDER BY p.priority DESC
        """
        actions = self.db.execute_query(query, fetch='all')
        
        if not actions:
            logger.critical("No active protocol_actions found in database!")
            return []
        
        # Маппинг tx_type → protocol_actions
        type_to_actions = {}
        for action in actions:
            tx_type = action['tx_type'].lower()
            if tx_type not in type_to_actions:
                type_to_actions[tx_type] = []
            type_to_actions[tx_type].append(action['id'])
        
        # Выбрать protocol_actions пропорционально весам
        selected = []
        
        for _ in range(count):
            # Рандомный выбор типа транзакции по весам
            tx_type = random.choices(
                list(weights.keys()),
                weights=list(weights.values()),
                k=1
            )[0]
            
            # Получить доступные actions для этого типа
            available = type_to_actions.get(tx_type, [])
            
            if not available:
                logger.warning(f"No protocol_actions for type '{tx_type}', fallback to swap")
                available = type_to_actions.get('swap', [])
            
            if available:
                selected.append(random.choice(available))
        
        return selected
    
    def generate_weekly_schedule(
        self,
        wallet_id: int,
        week_start: datetime
    ) -> Optional[int]:
        """
        Сгенерировать недельное расписание для кошелька.
        
        Args:
            wallet_id: ID кошелька
            week_start: Начало недели (datetime, Monday 00:00 UTC)
        
        Returns:
            weekly_plan_id или None при ошибке
        """
        logger.info(f"Generating schedule | Wallet: {wallet_id} | Week: {week_start.date()}")
        
        # 1. Загрузить персону
        persona = self._get_wallet_persona(wallet_id)
        if not persona:
            return None
        
        # 2. Проверить bridge emulation delay
        if not self._check_bridge_emulation_delay(persona):
            logger.warning(f"Skipping schedule (bridge emulation) | Wallet: {wallet_id}")
            return None
        
        # 3. Проверить skip_week_probability
        if self._should_skip_week(persona):
            # Создать weekly_plan с is_skipped=True
            query = """
                INSERT INTO weekly_plans (wallet_id, week_start_date, planned_tx_count, is_skipped)
                VALUES (%s, %s, 0, TRUE)
                RETURNING id
            """
            result = self.db.execute_query(
                query,
                (wallet_id, week_start.date()),
                fetch='one'
            )
            
            logger.success(f"Week skipped | Wallet: {wallet_id} | Plan ID: {result['id']}")
            return result['id']
        
        # 5. Проверить газ перед планированием
        should_exec, gas_reason = self.gas_controller.should_execute_transaction(
            persona.get('preferred_chain', 'base'),
            priority='normal'
        )
        if not should_exec:
            logger.warning(f"High gas, delaying schedule | Wallet: {wallet_id} | Reason: {gas_reason}")
            # Still create plan but mark for later execution
        else:
            logger.debug(f"Gas OK | Wallet: {wallet_id} | {gas_reason}")
        
        # 6. Рассчитать количество транзакций (Gaussian)
        tx_count = self._calculate_weekly_tx_count(persona)
        
        if tx_count == 0:
            logger.warning(f"Zero TX count sampled | Wallet: {wallet_id}")
            # Создать weekly_plan с 0 транзакций
            query = """
                INSERT INTO weekly_plans (wallet_id, week_start_date, planned_tx_count)
                VALUES (%s, %s, 0)
                RETURNING id
            """
            result = self.db.execute_query(
                query,
                (wallet_id, week_start.date()),
                fetch='one'
            )
            return result['id']
        
        # 7. Сгенерировать timestamp'ы транзакций
        timestamps = self._generate_tx_timestamps(persona, week_start, tx_count)
        
        # 8. Применить bridge emulation к первой TX
        timestamps = self._apply_bridge_emulation_to_first_tx(timestamps, persona)
        
        # 9. Убрать конфликты синхронности
        timestamps = self._remove_sync_conflicts(wallet_id, timestamps)
        
        # 10. Выбрать protocol_actions
        protocol_actions = self._select_protocol_actions(persona, tx_count)
        
        if len(protocol_actions) < tx_count:
            logger.error(f"Not enough protocol_actions selected | Wallet: {wallet_id}")
            return None
        
        # 11. Создать weekly_plan
        query = """
            INSERT INTO weekly_plans (wallet_id, week_start_date, planned_tx_count)
            VALUES (%s, %s, %s)
            RETURNING id
        """
        plan_result = self.db.execute_query(
            query,
            (wallet_id, week_start.date(), tx_count),
            fetch='one'
        )
        
        plan_id = plan_result['id']
        
        # 10. Создать scheduled_transactions
        for i, ts in enumerate(timestamps):
            action_id = protocol_actions[i]
            
            # Получить tx_type и layer для protocol_action
            action_query = """
                SELECT tx_type, action_layer
                FROM protocol_actions
                WHERE id = %s
            """
            action_data = self.db.execute_query(action_query, (action_id,), fetch='one')
            
            if not action_data:
                logger.error(f"Protocol action {action_id} not found")
                continue
            
            # Создать запись
            tx_query = """
                INSERT INTO scheduled_transactions (
                    wallet_id,
                    protocol_action_id,
                    tx_type,
                    layer,
                    scheduled_at,
                    status
                )
                VALUES (%s, %s, %s, %s, %s, 'pending')
            """
            
            self.db.execute_query(
                tx_query,
                (
                    wallet_id,
                    action_id,
                    action_data['tx_type'],
                    action_data['action_layer'],
                    ts
                )
            )
        
        logger.success(
            f"Schedule created | Wallet: {wallet_id} | Plan ID: {plan_id} | "
            f"TX count: {tx_count}"
        )
        
        return plan_id
    
    def generate_for_all_wallets(self, week_start: datetime) -> int:
        """
        Сгенерировать расписание для всех 90 кошельков.
        
        Args:
            week_start: Начало недели (datetime, Monday 00:00 UTC)
        
        Returns:
            Количество успешно созданных планов
        """
        logger.info(f"Generating schedules for ALL wallets | Week: {week_start.date()}")
        
        # Получить все кошельки
        query = "SELECT id FROM wallets WHERE status = 'active' ORDER BY id"
        wallets = self.db.execute_query(query, fetch='all')
        
        if not wallets:
            logger.error("No active wallets found")
            return 0
        
        success_count = 0
        
        for wallet in wallets:
            wallet_id = wallet['id']
            
            try:
                plan_id = self.generate_weekly_schedule(wallet_id, week_start)
                
                if plan_id:
                    success_count += 1
                
                # Прогресс каждые 10 кошельков
                if success_count % 10 == 0:
                    logger.info(f"Progress: {success_count}/{len(wallets)}")
            
            except Exception as e:
                logger.exception(f"Error generating schedule for wallet {wallet_id}: {e}")
                continue
        
        logger.success(
            f"Schedules generated | Success: {success_count}/{len(wallets)} | "
            f"Week: {week_start.date()}"
        )
        
        return success_count
    
    async def schedule_protocol_farming(
        self,
        protocol_id: int,
        wallet_ids: List[int],
        week_start: datetime
    ) -> int:
        """
        Schedule farming tasks for a protocol with automatic bridge planning.
        
        This method integrates with BridgeManager v2.0 to:
        1. Check if bridge is required for protocol's chain (dynamic CEX check!)
        2. Schedule bridge transactions if needed
        3. Schedule farming tasks that depend on bridge completion
        
        UPDATED: Now uses bridge fields from protocols table (migration 031, 032)
        and performs FINAL bridge check before scheduling.
        
        Args:
            protocol_id: Protocol database ID
            wallet_ids: List of wallet IDs to schedule for
            week_start: Week start date for scheduling
        
        Returns:
            Number of successfully scheduled wallets
        
        Example:
            >>> scheduler = ActivityScheduler()
            >>> await scheduler.schedule_protocol_farming(
            ...     protocol_id=5,
            ...     wallet_ids=[1, 2, 3],
            ...     week_start=datetime(2026, 3, 3, tzinfo=timezone.utc)
            ... )
        """
        logger.info(
            f"Scheduling protocol farming | Protocol: {protocol_id} | "
            f"Wallets: {len(wallet_ids)} | Week: {week_start.date()}"
        )
        
        # Get protocol details with bridge fields (migration 031)
        protocol_query = """
            SELECT id, name, chains, is_active,
                   bridge_required, bridge_from_network, bridge_provider,
                   bridge_cost_usd, cex_support
            FROM protocols
            WHERE id = %s
        """
        protocol = self.db.execute_query(protocol_query, (protocol_id,), fetch='one')
        
        if not protocol:
            logger.error(f"Protocol {protocol_id} not found")
            return 0
        
        if not protocol['is_active']:
            logger.warning(f"Protocol {protocol['name']} is not active")
            return 0
        
        # Get primary chain from chains array
        chains = protocol.get('chains', [])
        protocol_chain = chains[0] if chains else None
        
        if not protocol_chain:
            logger.error(f"Protocol {protocol['name']} has no chains defined")
            return 0
        
        # Initialize BridgeManager for FINAL dynamic check
        bridge_manager = BridgeManager(db=self.db, dry_run=True)
        
        # CRITICAL: FINAL bridge check (data could have changed since protocol research)
        # This ensures we have up-to-date bridge availability
        bridge_required, cex_name = await bridge_manager.is_bridge_required(protocol_chain)
        
        # Use protocol's stored bridge_from_network or default to Arbitrum
        bridge_from_network = protocol.get('bridge_from_network') or 'Arbitrum'
        
        if bridge_required:
            logger.info(
                f"🔍 Bridge REQUIRED for {protocol_chain} | "
                f"No CEX supports this network"
            )
            
            # FINAL check: Verify bridge route is still available
            bridge_route = await bridge_manager.check_bridge_availability(
                from_network=bridge_from_network,
                to_network=protocol_chain,
                amount_eth=Decimal('0.05')  # Default bridge amount
            )
            
            if not bridge_route:
                logger.error(
                    f"❌ Bridge NOT available for {protocol_chain} | "
                    f"Protocol {protocol['name']} cannot be farmed"
                )
                
                # Update protocol bridge status
                self.db.execute_query(
                    """
                    UPDATE protocols
                    SET bridge_required = TRUE,
                        cex_support = NULL
                    WHERE id = %s
                    """,
                    (protocol_id,)
                )
                
                # Send alert
                await self._send_bridge_unavailable_alert(protocol, protocol_chain)
                return 0
            
            # Update protocol with latest bridge info
            self.db.execute_query(
                """
                UPDATE protocols
                SET bridge_required = TRUE,
                    bridge_from_network = %s,
                    bridge_provider = %s,
                    bridge_cost_usd = %s,
                    cex_support = NULL
                WHERE id = %s
                """,
                (bridge_from_network, bridge_route.provider,
                 bridge_route.cost_usd, protocol_id)
            )
            
            logger.info(
                f"✅ Bridge available | Provider: {bridge_route.provider} | "
                f"Cost: ${bridge_route.cost_usd:.2f} | "
                f"Safety: {bridge_route.safety_score}/100"
            )
        else:
            logger.info(
                f"✅ {protocol_chain} is supported by {cex_name} | "
                f"No bridge needed - direct CEX withdrawal possible"
            )
            
            # Update protocol with CEX support info
            self.db.execute_query(
                """
                UPDATE protocols
                SET bridge_required = FALSE,
                    cex_support = %s
                WHERE id = %s
                """,
                (cex_name, protocol_id)
            )
        
        # Schedule tasks for each wallet
        success_count = 0
        bridge_tx_ids = {}  # Track bridge TX IDs for dependency
        
        for wallet_id in wallet_ids:
            try:
                bridge_tx_id = None
                
                # If bridge required, schedule bridge transaction first
                if bridge_required:
                    # Schedule bridge with temporal isolation (1-24 hours from week start)
                    bridge_scheduled_at = week_start + timedelta(
                        hours=random.randint(1, 24)
                    )
                    
                    bridge_tx_id = self._schedule_bridge_transaction(
                        wallet_id=wallet_id,
                        from_network=bridge_from_network,
                        to_network=protocol_chain,
                        amount_eth=Decimal('0.05'),
                        scheduled_at=bridge_scheduled_at,
                        bridge_provider=bridge_route.provider if bridge_route else None
                    )
                    
                    if not bridge_tx_id:
                        logger.warning(f"Failed to schedule bridge for wallet {wallet_id}")
                        continue
                    
                    bridge_tx_ids[wallet_id] = bridge_tx_id
                    
                    logger.info(
                        f"Bridge scheduled | Wallet: {wallet_id} | "
                        f"{bridge_from_network} → {protocol_chain} | TX ID: {bridge_tx_id}"
                    )
                
                # Schedule farming tasks
                # If bridge was required, farming tasks depend on bridge completion
                # Add 24-72 hours delay after bridge for human-like behavior
                farming_scheduled_at = week_start + timedelta(
                    hours=random.randint(24, 72) if bridge_required else random.randint(1, 24)
                )
                
                # Get protocol actions for this protocol
                actions_query = """
                    SELECT id, tx_type, action_layer
                    FROM protocol_actions
                    WHERE protocol_id = %s AND is_enabled = TRUE
                    LIMIT 1
                """
                action = self.db.execute_query(actions_query, (protocol_id,), fetch='one')
                
                if not action:
                    logger.warning(f"No enabled actions for protocol {protocol_id}")
                    continue
                
                # Create scheduled transaction with bridge dependency
                tx_query = """
                    INSERT INTO scheduled_transactions (
                        wallet_id,
                        protocol_action_id,
                        tx_type,
                        layer,
                        scheduled_at,
                        status,
                        from_network,
                        to_network,
                        depends_on_tx_id,
                        bridge_required,
                        bridge_provider,
                        bridge_status
                    )
                    VALUES (%s, %s, %s, %s, %s, 'pending', %s, %s, %s, %s, %s, %s)
                    RETURNING id
                """
                
                result = self.db.execute_query(
                    tx_query,
                    (
                        wallet_id,
                        action['id'],
                        action['tx_type'],
                        action['action_layer'],
                        farming_scheduled_at,
                        bridge_from_network if bridge_required else None,
                        protocol_chain if bridge_required else None,
                        bridge_tx_id if bridge_required else None,
                        bridge_required,
                        bridge_route.provider if bridge_required and bridge_route else None,
                        'completed' if not bridge_required else 'pending'
                    ),
                    fetch='one'
                )
                
                if result:
                    success_count += 1
                    logger.debug(
                        f"Farming scheduled | Wallet: {wallet_id} | "
                        f"Protocol: {protocol['name']} | TX ID: {result['id']}"
                    )
            
            except Exception as e:
                logger.error(f"Error scheduling for wallet {wallet_id}: {e}")
                continue
        
        logger.success(
            f"Protocol farming scheduled | Protocol: {protocol['name']} | "
            f"Success: {success_count}/{len(wallet_ids)} | "
            f"Bridge required: {bridge_required}"
        )
        
        return success_count
    
    async def _send_bridge_unavailable_alert(self, protocol: Dict, chain: str):
        """Send Telegram alert when bridge becomes unavailable."""
        try:
            from notifications.telegram_bot import send_alert
            send_alert(
                'warning',
                f"⚠️ *Bridge Unavailable*\n\n"
                f"Protocol: {protocol['name']}\n"
                f"Chain: {chain}\n\n"
                f"No bridge route found. Protocol cannot be farmed until bridge becomes available."
            )
        except ImportError:
            logger.warning("Telegram bot not available for alert")
        except Exception as e:
            logger.error(f"Failed to send bridge alert: {e}")
    
    def _schedule_bridge_transaction(
        self,
        wallet_id: int,
        from_network: str,
        to_network: str,
        amount_eth: Decimal,
        scheduled_at: datetime,
        bridge_provider: Optional[str] = None
    ) -> Optional[int]:
        """
        Schedule a bridge transaction for a wallet.
        
        Updated to include bridge_provider and bridge_status fields
        from migration 031.
        
        Args:
            wallet_id: Wallet database ID
            from_network: Source network
            to_network: Destination network
            amount_eth: Amount to bridge
            scheduled_at: When to execute the bridge
            bridge_provider: Bridge aggregator (socket, across, relay)
        
        Returns:
            scheduled_transactions ID or None on failure
        """
        try:
            query = """
                INSERT INTO scheduled_transactions (
                    wallet_id,
                    tx_type,
                    layer,
                    scheduled_at,
                    status,
                    from_network,
                    to_network,
                    bridge_required,
                    bridge_provider,
                    bridge_status
                )
                VALUES (%s, 'BRIDGE', 'L1', %s, 'pending', %s, %s, TRUE, %s, 'pending')
                RETURNING id
            """
            
            result = self.db.execute_query(
                query,
                (wallet_id, scheduled_at, from_network, to_network, bridge_provider),
                fetch='one'
            )
            
            if result:
                logger.info(
                    f"Bridge TX scheduled | ID: {result['id']} | Wallet: {wallet_id} | "
                    f"{from_network} → {to_network} | Provider: {bridge_provider or 'auto'}"
                )
            
            return result['id'] if result else None
        
        except Exception as e:
            logger.error(f"Failed to schedule bridge: {e}")
            return None


# =============================================================================
# CLI INTERFACE
# =============================================================================

def main():
    import argparse
    from dateutil.parser import parse as parse_date
    
    parser = argparse.ArgumentParser(
        description="Activity Scheduler — Gaussian transaction scheduling"
    )
    
    subparsers = parser.add_subparsers(dest='command', required=True)
    
    # Command: generate-all
    generate_all_parser = subparsers.add_parser(
        'generate-all',
        help='Generate schedules for all 90 wallets'
    )
    generate_all_parser.add_argument(
        '--week',
        type=str,
        required=True,
        help='Week start date (YYYY-MM-DD, must be Monday)'
    )
    
    # Command: generate-one
    generate_one_parser = subparsers.add_parser(
        'generate-one',
        help='Generate schedule for one wallet'
    )
    generate_one_parser.add_argument(
        '--wallet-id',
        type=int,
        required=True,
        help='Wallet ID'
    )
    generate_one_parser.add_argument(
        '--week',
        type=str,
        required=True,
        help='Week start date (YYYY-MM-DD, must be Monday)'
    )
    
    args = parser.parse_args()
    
    try:
        # Parse week start date
        week_start = parse_date(args.week)
        
        # Ensure it's Monday
        if week_start.weekday() != 0:
            logger.error(f"Week start must be Monday, got: {week_start.strftime('%A')}")
            sys.exit(1)
        
        # Convert to UTC datetime
        week_start = week_start.replace(hour=0, minute=0, second=0, microsecond=0, tzinfo=timezone.utc)
        
        # Initialize scheduler
        scheduler = ActivityScheduler()
        
        # Execute command
        if args.command == 'generate-all':
            count = scheduler.generate_for_all_wallets(week_start)
            print(f"\n✅ Schedules generated: {count}/90")
        
        elif args.command == 'generate-one':
            plan_id = scheduler.generate_weekly_schedule(args.wallet_id, week_start)
            
            if plan_id:
                print(f"\n✅ Schedule created | Wallet: {args.wallet_id} | Plan ID: {plan_id}")
            else:
                print(f"\n❌ Failed to create schedule for wallet {args.wallet_id}")
                sys.exit(1)
    
    except Exception as e:
        logger.exception(f"Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
