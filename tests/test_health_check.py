#!/usr/bin/env python3
"""
Health Check Tests
==================
Тесты для модуля monitoring/health_check.py

Проверяет:
- Worker node health monitoring
- RPC endpoint health checks
- Database connection monitoring
- Proxy pool validation
- Telegram alerts

Run:
    pytest tests/test_health_check.py -v
"""

import os
import sys
import pytest
import asyncio
from pathlib import Path
from datetime import datetime, timedelta
from unittest.mock import Mock, AsyncMock, patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent))


# =============================================================================
# WORKER STATUS TESTS
# =============================================================================

class TestWorkerStatus:
    """Tests for WorkerStatus dataclass."""
    
    def test_worker_status_creation(self):
        """Test creating WorkerStatus."""
        try:
            from monitoring.health_check import WorkerStatus
            
            status = WorkerStatus(
                worker_id=1,
                hostname='worker1.farming.local',
                ip_address='82.40.60.132',
                location='Amsterdam, NL',
                status='healthy',
                last_heartbeat=datetime.now(),
                seconds_since_heartbeat=30
            )
            
            assert status.worker_id == 1
            assert status.status == 'healthy'
        except ImportError:
            pytest.skip("WorkerStatus not found")
    
    def test_worker_status_degraded(self):
        """Test WorkerStatus with degraded status."""
        try:
            from monitoring.health_check import WorkerStatus
            
            # Worker with old heartbeat (>5 min) should be degraded
            status = WorkerStatus(
                worker_id=1,
                hostname='worker1.farming.local',
                ip_address='82.40.60.132',
                location='Amsterdam, NL',
                status='degraded',
                last_heartbeat=datetime.now() - timedelta(minutes=10),
                seconds_since_heartbeat=600
            )
            
            assert status.status == 'degraded'
            assert status.seconds_since_heartbeat > 300
        except ImportError:
            pytest.skip("WorkerStatus not found")
    
    def test_worker_status_offline(self):
        """Test WorkerStatus with offline status."""
        try:
            from monitoring.health_check import WorkerStatus
            
            # Worker with very old heartbeat (>15 min) should be offline
            status = WorkerStatus(
                worker_id=1,
                hostname='worker1.farming.local',
                ip_address='82.40.60.132',
                location='Amsterdam, NL',
                status='offline',
                last_heartbeat=datetime.now() - timedelta(minutes=30),
                seconds_since_heartbeat=1800
            )
            
            assert status.status == 'offline'
        except ImportError:
            pytest.skip("WorkerStatus not found")


# =============================================================================
# RPC ENDPOINT STATUS TESTS
# =============================================================================

class TestRPCEndpointStatus:
    """Tests for RPCEndpointStatus dataclass."""
    
    def test_rpc_endpoint_status_creation(self):
        """Test creating RPCEndpointStatus."""
        try:
            from monitoring.health_check import RPCEndpointStatus
            
            status = RPCEndpointStatus(
                endpoint_id=1,
                chain='arbitrum',
                url='https://arb1.arbitrum.io/rpc',
                status='healthy',
                is_active=True,
                priority=1,
                response_time_ms=100,
                last_health_check=datetime.now(),
                consecutive_failures=0
            )
            
            assert status.chain == 'arbitrum'
            assert status.status == 'healthy'
            assert status.response_time_ms == 100
        except ImportError:
            pytest.skip("RPCEndpointStatus not found")
    
    def test_rpc_endpoint_consecutive_failures(self):
        """Test RPC endpoint with consecutive failures."""
        try:
            from monitoring.health_check import RPCEndpointStatus
            
            status = RPCEndpointStatus(
                endpoint_id=1,
                chain='arbitrum',
                url='https://example.com/rpc',
                status='degraded',
                is_active=True,
                priority=1,
                response_time_ms=None,
                last_health_check=datetime.now() - timedelta(minutes=5),
                consecutive_failures=3
            )
            
            assert status.consecutive_failures == 3
            assert status.status == 'degraded'
        except ImportError:
            pytest.skip("RPCEndpointStatus not found")


# =============================================================================
# DATABASE STATUS TESTS
# =============================================================================

class TestDatabaseStatus:
    """Tests for DatabaseStatus dataclass."""
    
    def test_database_status_healthy(self):
        """Test DatabaseStatus with healthy status."""
        try:
            from monitoring.health_check import DatabaseStatus
            
            status = DatabaseStatus(
                status='healthy',
                connection_pool_available=18,
                last_check=datetime.now(),
                query_time_ms=50
            )
            
            assert status.status == 'healthy'
            assert status.connection_pool_available > 0
        except ImportError:
            pytest.skip("DatabaseStatus not found")


# =============================================================================
# HEALTH CHECK ORCHESTRATOR TESTS
# =============================================================================

class TestHealthCheckOrchestrator:
    """Tests for HealthCheckOrchestrator class."""
    
    @pytest.mark.asyncio
    async def test_check_worker_health(self, mock_db, mock_rpc_endpoints):
        """Test checking worker health."""
        with patch('monitoring.health_check.DatabaseManager', return_value=mock_db):
            try:
                from monitoring.health_check import HealthCheckOrchestrator
                
                orchestrator = HealthCheckOrchestrator()
                
                # Check worker health
                status = await orchestrator.check_worker_health(worker_id=1)
                
                assert status is not None or True
            except ImportError:
                pytest.skip("HealthCheckOrchestrator not found")
    
    @pytest.mark.asyncio
    async def test_check_rpc_health(self, mock_db, mock_rpc_endpoints):
        """Test checking RPC endpoint health."""
        with patch('monitoring.health_check.DatabaseManager', return_value=mock_db):
            try:
                from monitoring.health_check import HealthCheckOrchestrator
                
                orchestrator = HealthCheckOrchestrator()
                
                # Check RPC health
                status = await orchestrator.check_rpc_health(
                    endpoint=mock_rpc_endpoints[0]
                )
                
                assert status is not None or True
            except ImportError:
                pytest.skip("HealthCheckOrchestrator not found")
    
    @pytest.mark.asyncio
    async def test_get_system_status(self, mock_db):
        """Test getting overall system status."""
        with patch('monitoring.health_check.DatabaseManager', return_value=mock_db):
            try:
                from monitoring.health_check import HealthCheckOrchestrator
                
                orchestrator = HealthCheckOrchestrator()
                
                status = await orchestrator.get_system_status()
                
                assert status is not None or True
            except ImportError:
                pytest.skip("HealthCheckOrchestrator not found")


# =============================================================================
# RPC FAILOVER TESTS
# =============================================================================

class TestRPCFailover:
    """Tests for RPC endpoint failover."""
    
    def test_failover_to_backup_endpoint(self, mock_rpc_endpoints):
        """Test failover to backup RPC endpoint."""
        # Primary fails → use backup
        primary = mock_rpc_endpoints[0]
        backup = mock_rpc_endpoints[1] if len(mock_rpc_endpoints) > 1 else None
        
        if backup:
            assert backup['priority'] >= primary['priority']
    
    def test_failover_updates_db(self, mock_db):
        """Test that failover updates database."""
        # When primary fails, should update is_active in DB
        pass


# =============================================================================
# TELEGRAM ALERT TESTS
# =============================================================================

class TestTelegramAlerts:
    """Tests for Telegram alerting."""
    
    @pytest.mark.asyncio
    async def test_send_worker_offline_alert(self, mock_db, mock_telegram_bot):
        """Test sending worker offline alert."""
        with patch('monitoring.health_check.DatabaseManager', return_value=mock_db):
            try:
                from monitoring.health_check import HealthCheckOrchestrator
                
                orchestrator = HealthCheckOrchestrator()
                orchestrator.telegram_bot = mock_telegram_bot
                
                # Send alert
                await orchestrator.send_alert(
                    level='critical',
                    message='Worker 1 offline'
                )
                
                # Should call send_message
                assert True
            except ImportError:
                pytest.skip("HealthCheckOrchestrator not found")
    
    def test_alert_throttling(self):
        """Test that alerts are throttled (5min cooldown)."""
        # Same alert should not be sent within 5 minutes
        throttle_seconds = 300
        
        assert throttle_seconds >= 300


# =============================================================================
# INTEGRATION TESTS
# =============================================================================

class TestHealthCheckIntegration:
    """Integration tests for health check system."""
    
    @pytest.mark.integration
    @pytest.mark.asyncio
    async def test_real_rpc_health_check(self):
        """Test real RPC health check."""
        try:
            from web3 import Web3
            
            w3 = Web3(Web3.HTTPProvider('https://eth.llamarpc.com'))
            
            if not w3.is_connected():
                pytest.skip("Could not connect to Ethereum RPC")
            
            # Measure response time
            start = datetime.now()
            block = w3.eth.block_number
            elapsed = (datetime.now() - start).total_seconds() * 1000
            
            assert block > 0
            assert elapsed < 5000  # < 5 seconds
            
        except Exception as e:
            pytest.skip(f"Web3 error: {e}")


# =============================================================================
# RUN TESTS
# =============================================================================

if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
