"""
OpenClaw Manager — Master Node Orchestration
==============================================

Runs on Master Node только.
Обязан НЕ запускать browser (только планирование задач).

Обязанности:
- Планирование задач для 18 Tier A кошельков
- Запись задач в openclaw tasks таблицу
- Temporal isolation: 60-240 минут между задачами (КРИТИЧНО!)
- Мониторинг выполнения задач
- Worker assignment (кошельки 1-6 → Worker 1, 7-12 → Worker 2, 13-18 → Worker 3)

ВАЖНО: Этот модуль НЕ выполняет задачи, только планирует их.
Выполнение делается на Workers через openclaw/executor.py
"""

import random
import numpy as np
from datetime import datetime, timedelta
from typing import List, Dict, Optional
from loguru import logger

from database.db_manager import DatabaseManager


class OpenClawOrchestrator:
    """
    Orchestrator для OpenClaw задач.
    
    Запускается на Master Node.
    Планирует задачи, но НЕ выполняет их (browser automation на Workers).
    """
    
    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager
        
        # КРИТИЧНО: Temporal isolation 60-240 минут (NOT 30-90!)
        self.min_delay_seconds = 60 * 60  # 1 hour
        self.max_delay_seconds = 240 * 60  # 4 hours
        self.long_pause_probability = 0.25  # 25% chance of 5-10 hour delay
        self.long_pause_min = 5 * 60 * 60  # 5 hours
        self.long_pause_max = 10 * 60 * 60  # 10 hours
        
        logger.info("✅ OpenClawOrchestrator initialized (temporal isolation: 60-240 min)")
    
    def schedule_gitcoin_passport_batch(self, tier_a_wallets: List[Dict]) -> int:
        """
        Планирует Gitcoin Passport stamping для всех 18 Tier A кошельков.
        
        Стратегия:
        1. Shuffle кошельков (избежать sequential patterns)
        2. Temporal isolation: 1-4 часа между tasks
        3. 25% шанс длинной паузы (5-10 hours)
        
        Args:
            tier_a_wallets: Список Tier A кошельков (должно быть 18)
        
        Returns:
            Количество запланированных задач
        """
        if len(tier_a_wallets) != 18:
            logger.warning(f"⚠️ Expected 18 Tier A wallets, got {len(tier_a_wallets)}")
        
        # Shuffle для непредсказуемости
        shuffled = random.sample(tier_a_wallets, len(tier_a_wallets))
        
        base_time = datetime.utcnow() + timedelta(minutes=5)  # Начало через 5 минут
        cumulative_delay = 0
        tasks_scheduled = 0
        
        for i, wallet in enumerate(shuffled):
            # Вычисляем delay до следующей задачи
            delay_seconds = self._calculate_next_task_delay()
            cumulative_delay += delay_seconds
            
            scheduled_at = base_time + timedelta(seconds=cumulative_delay)
            
            # Вставляем задачу в очередь
            task_params = {
                'target_stamps': ['github', 'twitter', 'discord', 'google', 'linkedin'],
                'min_score': 15
            }
            
            task_id = self._insert_task(
                wallet_id=wallet['id'],
                task_type='gitcoin_passport',
                task_params=task_params,
                scheduled_at=scheduled_at,
                priority=1  # Highest priority (Gitcoin is critical)
            )
            
            logger.info(
                f"📅 Scheduled Gitcoin task #{task_id} | "
                f"Wallet {wallet['id']:02d} | "
                f"At {scheduled_at.strftime('%Y-%m-%d %H:%M UTC')} | "
                f"Delay: {delay_seconds/3600:.2f}h"
            )
            
            tasks_scheduled += 1
        
        logger.success(
            f"✅ Scheduled {tasks_scheduled} Gitcoin Passport tasks | "
            f"Spread over {cumulative_delay/3600:.1f} hours ({cumulative_delay/3600/24:.1f} days)"
        )
        
        return tasks_scheduled
    
    def schedule_poap_claim_batch(
        self, 
        tier_a_wallets: List[Dict], 
        event_ids: List[int],
        event_names: List[str]
    ) -> int:
        """
        Планирует POAP claiming для 18 Tier A кошельков.
        
        Args:
            tier_a_wallets: Список Tier A кошельков
            event_ids: Список POAP event IDs (например, [12345, 67890, 11111])
            event_names: Список названий событий
        
        Returns:
            Количество запланированных задач
        """
        shuffled = random.sample(tier_a_wallets, len(tier_a_wallets))
        
        base_time = datetime.utcnow() + timedelta(minutes=10)
        cumulative_delay = 0
        tasks_scheduled = 0
        
        for wallet in shuffled:
            # Для каждого кошелька создаем задачи для 3-5 POAPs
            poap_count = random.randint(3, min(5, len(event_ids)))
            selected_events = random.sample(list(zip(event_ids, event_names)), poap_count)
            
            for event_id, event_name in selected_events:
                delay_seconds = self._calculate_next_task_delay()
                cumulative_delay += delay_seconds
                scheduled_at = base_time + timedelta(seconds=cumulative_delay)
                
                task_params = {
                    'event_id': event_id,
                    'event_name': event_name
                }
                
                task_id = self._insert_task(
                    wallet_id=wallet['id'],
                    task_type='poap_claim',
                    task_params=task_params,
                    scheduled_at=scheduled_at,
                    priority=3  # Medium priority
                )
                
                logger.info(
                    f"📅 Scheduled POAP task #{task_id} | "
                    f"Wallet {wallet['id']:02d} | "
                    f"Event: {event_name}"
                )
                
                tasks_scheduled += 1
        
        logger.success(f"✅ Scheduled {tasks_scheduled} POAP claim tasks")
        return tasks_scheduled
    
    def schedule_coinbase_id_batch(self, tier_a_wallets: List[Dict]) -> int:
        """
        Планирует Coinbase ID (cb.id) registration — FREE alternative to ENS.
        
        Преимущества:
        - Полностью бесплатно (только gas на Base L2 ~$0.01)
        - Reputation score: +9 (почти как ENS +10)
        - Экономия: $90/year (18 wallets × $5)
        
        Args:
            tier_a_wallets: Список Tier A кошельков
        
        Returns:
            Количество запланированных задач
        """
        shuffled = random.sample(tier_a_wallets, len(tier_a_wallets))
        
        base_time = datetime.utcnow() + timedelta(minutes=15)
        cumulative_delay = 0
        tasks_scheduled = 0
        
        for wallet in shuffled:
            delay_seconds = self._calculate_next_task_delay()
            cumulative_delay += delay_seconds
            scheduled_at = base_time + timedelta(seconds=cumulative_delay)
            
            # Генерируем unique username для кошелька
            # Добавляем random suffix для избежания collisions
            name_suffixes = ['alpha', 'beta', 'gamma', 'delta', 'sigma', 'omega', 'theta', 'lambda']
            username = f"wallet{wallet['id']:03d}{random.choice(name_suffixes)}"
            
            task_params = {
                'username': username,
                'set_as_primary': random.choice([True, False])  # 50% chance
            }
            
            task_id = self._insert_task(
                wallet_id=wallet['id'],
                task_type='coinbase_id',
                task_params=task_params,
                scheduled_at=scheduled_at,
                priority=1  # Same as Gitcoin (high priority)
            )
            
            logger.info(
                f"📅 Scheduled Coinbase ID task #{task_id} | "
                f"Wallet {wallet['id']:02d} | "
                f"Username: {username}.cb.id | "
                f"Cost: FREE (gas only ~$0.01)"
            )
            
            tasks_scheduled += 1
        
        logger.success(f"✅ Scheduled {tasks_scheduled} Coinbase ID registration tasks (FREE)")
        return tasks_scheduled
    
    def schedule_ens_registration_batch(self, tier_a_wallets: List[Dict]) -> int:
        """
        [DEPRECATED] Планирует ENS subdomain registration.
        
        ⚠️ УСТАРЕЛО: Используйте schedule_coinbase_id_batch() для экономии $90/year
        
        Args:
            tier_a_wallets: Список Tier A кошельков
        
        Returns:
            Количество запланированных задач
        """
        logger.warning("⚠️ ENS registration is DEPRECATED. Use Coinbase ID instead (FREE)")
        shuffled = random.sample(tier_a_wallets, len(tier_a_wallets))
        
        base_time = datetime.utcnow() + timedelta(minutes=15)
        cumulative_delay = 0
        tasks_scheduled = 0
        
        for wallet in shuffled:
            delay_seconds = self._calculate_next_task_delay()
            cumulative_delay += delay_seconds
            scheduled_at = base_time + timedelta(seconds=cumulative_delay)
            
            # 80% chance FREE subdomain (cb.id or base.eth), 20% premium ($5-10)
            if random.random() < 0.8:
                parent_domain = random.choice(['cb.id', 'base.eth'])
                cost = 0.0
            else:
                parent_domain = 'myproject.eth'
                # Gaussian instead of uniform for cost: mean=0.0065, std=0.002 → 0.003-0.01 range
                cost = np.random.normal(0.0065, 0.002)
                cost = max(0.003, min(0.01, cost))  # Clip to range
            
            # Генерируем unique name для кошелька
            name_suffix = random.choice(['alpha', 'beta', 'gamma', 'delta', 'sigma'])
            ens_name = f"wallet{wallet['id']}{name_suffix}.{parent_domain}"
            
            task_params = {
                'ens_name': ens_name,
                'parent_domain': parent_domain,
                'cost_eth': cost
            }
            
            task_id = self._insert_task(
                wallet_id=wallet['id'],
                task_type='ens_register',
                task_params=task_params,
                scheduled_at=scheduled_at,
                priority=1  # Same as Gitcoin (high priority)
            )
            
            logger.info(
                f"📅 Scheduled ENS task #{task_id} | "
                f"Wallet {wallet['id']:02d} | "
                f"Name: {ens_name} | "
                f"Cost: {'FREE' if cost == 0 else f'{cost:.4f} ETH'}"
            )
            
            tasks_scheduled += 1
        
        logger.success(f"✅ Scheduled {tasks_scheduled} ENS registration tasks")
        return tasks_scheduled
    
    def schedule_snapshot_voting_batch(
        self, 
        tier_a_wallets: List[Dict], 
        proposals: List[Dict]
    ) -> int:
        """
        Планирует Snapshot voting (5-10 proposals per wallet).
        
        Args:
            tier_a_wallets: Список Tier A кошельков
            proposals: Список proposals [{"proposal_id": "...", "space": "aave.eth", "title": "..."}]
        
        Returns:
            Количество запланированных задач
        """
        shuffled = random.sample(tier_a_wallets, len(tier_a_wallets))
        
        base_time = datetime.utcnow() + timedelta(minutes=20)
        cumulative_delay = 0
        tasks_scheduled = 0
        
        for wallet in shuffled:
            # Каждый кошелек голосует за 5-10 proposals
            vote_count = random.randint(5, min(10, len(proposals)))
            selected_proposals = random.sample(proposals, vote_count)
            
            for proposal in selected_proposals:
                delay_seconds = self._calculate_next_task_delay()
                cumulative_delay += delay_seconds
                scheduled_at = base_time + timedelta(seconds=cumulative_delay)
                
                # Randomize vote choice (60% yes, 30% no, 10% abstain)
                rand_choice = random.random()
                if rand_choice < 0.6:
                    choice = 'for'
                elif rand_choice < 0.9:
                    choice = 'against'
                else:
                    choice = 'abstain'
                
                task_params = {
                    'proposal_id': proposal['proposal_id'],
                    'space': proposal['space'],
                    'title': proposal.get('title', 'Untitled Proposal'),
                    'choice': choice
                }
                
                task_id = self._insert_task(
                    wallet_id=wallet['id'],
                    task_type='snapshot_vote',
                    task_params=task_params,
                    scheduled_at=scheduled_at,
                    priority=5  # Low priority (Snapshot is nice-to-have)
                )
                
                logger.info(
                    f"📅 Scheduled Snapshot vote #{task_id} | "
                    f"Wallet {wallet['id']:02d} | "
                    f"Space: {proposal['space']} | "
                    f"Choice: {choice}"
                )
                
                tasks_scheduled += 1
        
        logger.success(f"✅ Scheduled {tasks_scheduled} Snapshot voting tasks")
        return tasks_scheduled
    
    def assign_tasks_to_workers(self) -> int:
        """
        Назначает unassigned tasks на Workers основываясь на wallet assignment.
        
        Worker assignment logic:
        - Worker 1: wallets 1-6 (Tier A)
        - Worker 2: wallets 7-12 (Tier A)
        - Worker 3: wallets 13-18 (Tier A)
        
        Returns:
            Количество назначенных задач
        """
        # Получаем tasks без assigned_worker_id
        unassigned_tasks = self.db.query("""
            SELECT 
                t.id AS task_id,
                t.wallet_id,
                w.worker_id
            FROM openclaw_tasks t
            JOIN wallets w ON t.wallet_id = w.id
            WHERE t.status = 'queued' 
              AND t.assigned_worker_id IS NULL
        """)
        
        assigned_count = 0
        
        for task in unassigned_tasks:
            self.db.execute("""
                UPDATE openclaw_tasks
                SET assigned_worker_id = %s
                WHERE id = %s
            """, [task['worker_id'], task['task_id']])
            
            assigned_count += 1
        
        if assigned_count > 0:
            logger.info(f"✅ Assigned {assigned_count} tasks to Workers")
        
        return assigned_count
    
    def get_task_stats(self) -> Dict:
        """
        Получает статистику по задачам.
        
        Returns:
            Dict с статистикой: {queued: X, running: Y, completed: Z, failed: W}
        """
        stats = self.db.query_one("""
            SELECT 
                COUNT(*) FILTER (WHERE status = 'queued') AS queued,
                COUNT(*) FILTER (WHERE status = 'running') AS running,
                COUNT(*) FILTER (WHERE status = 'completed') AS completed,
                COUNT(*) FILTER (WHERE status = 'failed') AS failed,
                COUNT(*) FILTER (WHERE status = 'skipped') AS skipped,
                COUNT(*) AS total
            FROM openclaw_tasks
        """)
        
        return stats or {
            'queued': 0,
            'running': 0,
            'completed': 0,
            'failed': 0,
            'skipped': 0,
            'total': 0
        }
    
    def _calculate_next_task_delay(self) -> int:
        """
        Вычисляет delay до следующей задачи (КРИТИЧЕСКАЯ ФУНКЦИЯ).
        
        Логика (согласно architectural review):
        - Базовая задержка: 60-240 минут (1-4 часа)
        - 25% шанс длинной паузы: 5-10 часов
        - Добавление Gaussian noise: ±20 минут
        - Минимум: 1 hour
        
        Returns:
            Delay в seconds
        """
        # Anti-Sybil: Use Gaussian distribution instead of uniform
        # Базовая задержка: 1-4 часа - Gaussian distribution
        # mean=150 min (2.5 hours), std=45 min
        base_delay = np.random.normal(150 * 60, 45 * 60)
        base_delay = max(self.min_delay_seconds, min(self.max_delay_seconds, base_delay))
        
        # 25% шанс длинной паузы (5-10 hours) — имитация "ушел спать"
        if random.random() < self.long_pause_probability:
            # Gaussian: mean=7.5 hours, std=1.5 hours
            base_delay = np.random.normal(7.5 * 60 * 60, 1.5 * 60 * 60)
            base_delay = max(self.long_pause_min, min(self.long_pause_max, base_delay))
            logger.debug(f"🌙 Long pause triggered: {base_delay/3600:.2f}h")
        
        # Добавляем Gaussian noise (±20 минут) - using numpy for consistency
        noise = np.random.normal(0, 20 * 60)  # mean=0, std=20 min
        
        # Финальная задержка (минимум 1 hour)
        final_delay = max(self.min_delay_seconds, base_delay + noise)
        
        return int(final_delay)
    
    def _insert_task(
        self, 
        wallet_id: int, 
        task_type: str, 
        task_params: Dict, 
        scheduled_at: datetime,
        priority: int = 5,
        max_retries: int = 3
    ) -> int:
        """
        Вставляет task в openclaw_tasks таблицу.
        
        Args:
            wallet_id: ID кошелька
            task_type: Тип задачи (gitcoin_passport, poap_claim, etc.)
            task_params: JSONB параметры задачи
            scheduled_at: Время выполнения
            priority: Приоритет (1 = highest, 10 = lowest)
            max_retries: Максимум попыток
        
        Returns:
            ID созданной задачи
        """
        result = self.db.query_one("""
            INSERT INTO openclaw_tasks (
                wallet_id, 
                task_type, 
                task_params, 
                scheduled_at, 
                priority,
                max_retries,
                status
            ) VALUES (%s, %s, %s, %s, %s, %s, 'queued')
            RETURNING id
        """, [wallet_id, task_type, task_params, scheduled_at, priority, max_retries])
        
        return result['id'] if result else None
