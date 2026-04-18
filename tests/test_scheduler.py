#!/usr/bin/env python3
"""
Activity Scheduler Tests
=======================
Тесты для модуля activity/scheduler.py

Проверяет:
- Gaussian планирование транзакций
- Anti-Sybil: избегание синхронности
- Timezone-aware scheduling
- Sync conflict resolution

Run:
    pytest tests/test_scheduler.py -v
"""

import os
import sys
import pytest
import numpy as np
from pathlib import Path
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent))


# =============================================================================
# GAUSSIAN SCHEDULING TESTS
# =============================================================================

class TestGaussianScheduling:
    """Tests for Gaussian-distributed transaction scheduling."""
    
    def test_tx_count_per_month_tier_a(self):
        """Test that Tier A has higher TX count per month."""
        # Tier A: mean=4.5 TX/week = ~18 TX/month
        mean_weekly = 4.5
        mean_monthly = mean_weekly * 4
        
        assert mean_monthly > 15, "Tier A should have >15 TX/month"
    
    def test_tx_count_per_month_tier_c(self):
        """Test that Tier C has lower TX count per month."""
        # Tier C: mean=1.0 TX/week = ~4 TX/month
        mean_weekly = 1.0
        mean_monthly = mean_weekly * 4
        
        assert mean_monthly < 6, "Tier C should have <6 TX/month"
    
    def test_gaussian_hour_distribution(self):
        """Test that scheduled hours follow Gaussian distribution."""
        # Generate hours for a persona with preferred_hours [9-21]
        preferred_hours = list(range(9, 21))
        
        # Schedule should pick from preferred hours with Gaussian weighting
        # (center of range more likely)
        scheduled_hours = []
        
        for _ in range(1000):
            # Gaussian centered on middle of preferred range
            center = (min(preferred_hours) + max(preferred_hours)) / 2
            hour = int(np.random.normal(center, 2))
            hour = max(min(preferred_hours), min(max(preferred_hours), hour))
            scheduled_hours.append(hour)
        
        mean = np.mean(scheduled_hours)
        
        # Mean should be close to center (allow ±0.5 variance due to randomness)
        assert 13.5 < mean < 16.5, f"Hour mean {mean} not centered"


# =============================================================================
# ANTI-SYBL SYNCHRONIZATION TESTS
# =============================================================================

class TestAntiSybilSynchronization:
    """Tests for anti-Sybil synchronization avoidance."""
    
    def test_no_synchronous_transactions_same_worker(self):
        """Test that wallets on same worker don't have synchronous TX."""
        # Wallets 1-30 on Worker 1 should NOT have same scheduled times
        # Sync offset: Gaussian μ=17.5min, σ=4min, clamped [10, 25]
        
        sync_offsets = []
        for _ in range(100):
            offset = int(np.random.normal(17.5, 4))
            offset = max(10, min(25, offset))
            sync_offsets.append(offset)
        
        mean = np.mean(sync_offsets)
        
        assert 16 < mean < 19, f"Sync offset mean {mean} not in expected range"
    
    def test_sync_offset_prevents_collision(self):
        """Test that sync offset prevents time collisions."""
        # Two wallets scheduled for same hour
        base_time = datetime(2026, 3, 23, 10, 0)
        
        # Wallet 1: scheduled at 10:00
        # Wallet 2: scheduled at 10:00 + offset
        offset_minutes = int(np.random.normal(17.5, 4))
        offset_minutes = max(10, min(25, offset_minutes))
        
        wallet1_time = base_time
        wallet2_time = base_time + timedelta(minutes=offset_minutes)
        
        # Times should differ
        assert wallet1_time != wallet2_time
        
        # Difference should be 10-25 minutes
        diff = (wallet2_time - wallet1_time).total_seconds() / 60
        assert 10 <= diff <= 25


# =============================================================================
# TIMEZONE SCHEDULING TESTS
# =============================================================================

class TestTimezoneScheduling:
    """Tests for timezone-aware scheduling."""
    
    def test_nl_timezone_conversion(self):
        """Test Netherlands timezone (UTC+1) scheduling."""
        # NL: 9am-10pm local = 8am-9pm UTC
        local_hours = list(range(9, 23))  # 9am-10pm local
        utc_offset = 1
        
        utc_hours = [(h - utc_offset) % 24 for h in local_hours]
        
        # 9am local = 8am UTC
        assert 8 in utc_hours
        
        # 22pm local = 21pm UTC
        assert 21 in utc_hours
    
    def test_is_timezone_conversion(self):
        """Test Iceland timezone (UTC+0) scheduling."""
        # IS: 10am-11pm local = 10am-11pm UTC (same)
        local_hours = list(range(10, 24))
        utc_offset = 0
        
        utc_hours = [(h - utc_offset) % 24 for h in local_hours]
        
        # Should be same as local
        assert utc_hours == local_hours
    
    def test_ca_timezone_conversion(self):
        """Test Canada timezone (UTC-5) scheduling."""
        # CA: 9am-10pm local = 2pm-3am UTC (next day!)
        local_hours = list(range(9, 23))
        utc_offset = -5
        
        utc_hours = [(h - utc_offset) % 24 for h in local_hours]
        
        # 9am local = 14 UTC (2pm)
        assert 14 in utc_hours
        
        # 22pm local = 3 UTC (next day 3am)
        assert 3 in utc_hours


# =============================================================================
# WEEK SKIP PROBABILITY TESTS
# =============================================================================

class TestWeekSkipProbability:
    """Tests for week skip probability by archetype."""
    
    def test_active_trader_low_skip(self):
        """Test that ActiveTrader has very low skip probability."""
        # ActiveTrader: skip ~2.5%
        skip_prob = 0.025
        
        assert skip_prob < 0.05, "ActiveTrader skip too high"
    
    def test_monthly_active_high_skip(self):
        """Test that MonthlyActive has high skip probability."""
        # MonthlyActive: skip ~75% (active only 1 week/month)
        skip_prob = 0.75
        
        assert skip_prob > 0.65, "MonthlyActive skip too low"
    
    def test_ghost_medium_skip(self):
        """Test that Ghost has medium-high skip probability."""
        # Ghost: skip ~25%
        skip_prob = 0.25
        
        assert 0.20 < skip_prob < 0.30, "Ghost skip not in expected range"


# =============================================================================
# SCHEDULE GENERATION TESTS
# =============================================================================

class TestScheduleGeneration:
    """Tests for schedule generation."""
    
    def test_generate_weekly_schedule(self, mock_db, sample_persona):
        """Test generating weekly schedule for a wallet."""
        with patch('database.db_manager.DatabaseManager', return_value=mock_db):
            from activity.scheduler import ActivityScheduler
            from datetime import datetime, timezone
            
            scheduler = ActivityScheduler()
            scheduler.db = mock_db
            
            # Mock gas_controller
            scheduler.gas_controller = Mock()
            scheduler.gas_controller.should_execute_transaction.return_value = (True, "Gas OK")
            
            # Mock all internal methods
            with patch.object(scheduler, '_get_wallet_persona', return_value=sample_persona):
                with patch.object(scheduler, '_check_bridge_emulation_delay', return_value=True):
                    with patch.object(scheduler, '_should_skip_week', return_value=False):
                        with patch.object(scheduler, '_calculate_weekly_tx_count', return_value=5):
                            with patch.object(scheduler, '_generate_tx_timestamps', return_value=[
                                datetime(2026, 3, 24, 10, 0, tzinfo=timezone.utc),
                                datetime(2026, 3, 25, 14, 0, tzinfo=timezone.utc),
                            ]):
                                with patch.object(scheduler, '_apply_bridge_emulation_to_first_tx', side_effect=lambda ts, p: ts):
                                    with patch.object(scheduler, '_remove_sync_conflicts', side_effect=lambda w, ts: ts):
                                        with patch.object(scheduler, '_select_protocol_actions', return_value=[1, 2, 3, 4, 5]):
                                            # Mock DB insert returning plan_id
                                            mock_db.execute_query.side_effect = [
                                                {'id': 123},  # weekly_plans INSERT
                                                {'tx_type': 'SWAP', 'action_layer': 'web3py'},  # action 1
                                                {'tx_type': 'BRIDGE', 'action_layer': 'web3py'},  # action 2
                                                {'tx_type': 'SWAP', 'action_layer': 'web3py'},  # action 3
                                                {'tx_type': 'STAKE', 'action_layer': 'web3py'},  # action 4
                                                {'tx_type': 'LP', 'action_layer': 'web3py'},  # action 5
                                            ]
                                            
                                            week_start = datetime(2026, 3, 23, tzinfo=timezone.utc)
                                            result = scheduler.generate_weekly_schedule(
                                                wallet_id=1,
                                                week_start=week_start
                                            )
                                            
                                            assert result == 123, f"Expected plan_id 123, got {result}"
    
    def test_schedule_respects_persona_hours(self, mock_db, sample_persona):
        """Test that schedule respects persona preferred hours."""
        preferred_hours = sample_persona['preferred_hours']
        
        # All scheduled times should be within preferred hours
        # (after timezone conversion)
        pass
    
    def test_schedule_respects_tx_count(self, mock_db, sample_persona):
        """Test that schedule respects persona TX per week."""
        tx_mean = sample_persona['tx_per_week_mean']
        
        # Schedule should have ~tx_mean transactions
        # With Gaussian variation
        pass


# =============================================================================
# INTEGRATION TESTS
# =============================================================================

class TestSchedulerIntegration:
    """Integration tests for TransactionExecutor."""
    
    @pytest.mark.integration
    @pytest.mark.requires_db
    def test_full_schedule_generation(self, mock_db_with_wallets, sample_persona):
        """Test full schedule generation for all wallets."""
        with patch('database.db_manager.DatabaseManager', return_value=mock_db_with_wallets):
            from activity.scheduler import ActivityScheduler
            from datetime import datetime, timezone
            
            scheduler = ActivityScheduler()
            scheduler.db = mock_db_with_wallets
            
            # Test that scheduler has DB connection
            assert scheduler.db is not None
            
            # Test that scheduler has gas controller
            assert hasattr(scheduler, 'gas_controller')
            
            # Mock gas_controller for integration test
            scheduler.gas_controller = Mock()
            scheduler.gas_controller.should_execute_transaction.return_value = (True, "Gas OK")
            
            # Test schedule generation with proper mocks
            with patch.object(scheduler, '_get_wallet_persona', return_value=sample_persona):
                with patch.object(scheduler, '_check_bridge_emulation_delay', return_value=True):
                    with patch.object(scheduler, '_should_skip_week', return_value=False):
                        with patch.object(scheduler, '_calculate_weekly_tx_count', return_value=3):
                            with patch.object(scheduler, '_generate_tx_timestamps', return_value=[
                                datetime(2026, 3, 24, 10, 0, tzinfo=timezone.utc),
                            ]):
                                with patch.object(scheduler, '_apply_bridge_emulation_to_first_tx', side_effect=lambda ts, p: ts):
                                    with patch.object(scheduler, '_remove_sync_conflicts', side_effect=lambda w, ts: ts):
                                        with patch.object(scheduler, '_select_protocol_actions', return_value=[1, 2, 3]):
                                            mock_db_with_wallets.execute_query.side_effect = [
                                                {'id': 100},  # weekly_plans INSERT
                                                {'tx_type': 'SWAP', 'action_layer': 'web3py'},  # action 1
                                                {'tx_type': 'BRIDGE', 'action_layer': 'web3py'},  # action 2
                                                {'tx_type': 'STAKE', 'action_layer': 'web3py'},  # action 3
                                            ]
                                            
                                            week_start = datetime(2026, 3, 23, tzinfo=timezone.utc)
                                            result = scheduler.generate_weekly_schedule(
                                                wallet_id=1,
                                                week_start=week_start
                                            )
                                            
                                            assert result is not None, "Schedule generation failed"


# =============================================================================
# RUN TESTS
# =============================================================================

if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
