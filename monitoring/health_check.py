"""
Health Check System — Module 20
================================

Monitors critical system components:
- Worker nodes (heartbeat tracking)
- RPC endpoints (health + automatic failover)
- Database connection
- Proxy pool (validation status)

Features:
- Background monitoring threads (60s Workers, 5min RPC, 2min DB, 6h Proxy)
- Automatic RPC failover when primary fails
- Proxy validation with status tracking
- Telegram alerts on status changes
- Alert throttling (5min cooldown)

Usage:
    from monitoring.health_check import HealthCheckOrchestrator
    
    orchestrator = HealthCheckOrchestrator()
    orchestrator.start()  # Start background monitoring
    
    # Get status for Telegram dashboard
    status = orchestrator.get_system_status()

Integration:
    - APScheduler: Runs as background threads (not APScheduler jobs)
    - Telegram: Sends alerts via notifications.telegram_bot
    - Database: Uses existing worker_nodes, chain_rpc_endpoints, proxy_pool tables
"""

import os
import time
import threading
import random
from curl_cffi import requests
from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta, timezone
from dataclasses import dataclass, field
from loguru import logger

# Try to import web3, but don't fail if not available
try:
    from web3 import Web3
    WEB3_AVAILABLE = True
except ImportError:
    WEB3_AVAILABLE = False
    logger.warning("web3.py not available - RPC health checks will use HTTP only")


# ============================================================================
# DATA CLASSES
# ============================================================================

@dataclass
class WorkerStatus:
    """Worker health status."""
    worker_id: int
    hostname: str
    ip_address: str
    location: str
    status: str  # 'healthy', 'degraded', 'offline'
    last_heartbeat: Optional[datetime]
    seconds_since_heartbeat: Optional[int]
    assigned_wallets: int = 30


@dataclass
class RPCEndpointStatus:
    """RPC endpoint health status."""
    endpoint_id: int
    chain: str
    url: str
    status: str  # 'healthy', 'degraded', 'offline'
    is_active: bool
    priority: int
    response_time_ms: Optional[int]
    last_health_check: Optional[datetime]
    consecutive_failures: int


@dataclass
class DatabaseStatus:
    """Database connection health status."""
    status: str  # 'healthy', 'degraded', 'offline'
    connection_pool_available: int
    last_check: datetime
    query_time_ms: Optional[int] = None


@dataclass
class ProxyStatus:
    """Proxy pool health status."""
    total_proxies: int
    valid_proxies: int
    invalid_proxies: int
    unknown_proxies: int
    avg_response_ms: Optional[int]
    last_check: datetime


@dataclass
class SystemHealthStatus:
    """Complete system health status."""
    timestamp: str
    overall_status: str
    database: DatabaseStatus
    workers: List[WorkerStatus]
    rpc_endpoints: List[RPCEndpointStatus]
    proxies: Optional[ProxyStatus] = None


# ============================================================================
# WORKER HEALTH MONITOR
# ============================================================================

class WorkerHealthMonitor:
    """
    Monitors Worker nodes via heartbeat tracking.
    
    Checks every 60 seconds:
    - If last_heartbeat < 2 minutes ago → healthy
    - If last_heartbeat > 2 minutes ago → offline
    
    Uses existing worker_nodes.last_heartbeat column from schema.
    """
    
    def __init__(self, db_manager):
        """
        Initialize Worker health monitor.
        
        Args:
            db_manager: DatabaseManager instance
        """
        self.db = db_manager
        self._status_cache: Dict[int, str] = {}
        logger.info("WorkerHealthMonitor initialized")
    
    def check_all_workers(self) -> Dict[int, str]:
        """
        Check health status of all workers.
        
        Returns:
            Dict[worker_id, status] — 'healthy' or 'offline'
        """
        try:
            # Get all workers from database
            query = """
                SELECT id, worker_id, hostname, ip_address, location, 
                       last_heartbeat, status as worker_status
                FROM worker_nodes 
                ORDER BY worker_id
            """
            workers = self.db.execute_query(query, fetch='all')
            
            results = {}
            now = datetime.now(timezone.utc)
            
            for worker in workers:
                worker_id = worker['worker_id']
                last_heartbeat = worker['last_heartbeat']
                
                # Calculate time since last heartbeat
                if last_heartbeat is None:
                    status = 'offline'
                    seconds_ago = None
                else:
                    # Ensure timezone-aware comparison
                    if last_heartbeat.tzinfo is None:
                        last_heartbeat = last_heartbeat.replace(tzinfo=timezone.utc)
                    
                    seconds_ago = int((now - last_heartbeat).total_seconds())
                    
                    if seconds_ago < 120:  # 2 minutes
                        status = 'healthy'
                    else:
                        status = 'offline'
                
                results[worker_id] = status
                
                # Cache for quick lookups
                self._status_cache[worker_id] = status
                
                # Log status changes
                if self._status_cache.get(worker_id) != status:
                    logger.warning(
                        f"Worker {worker_id} status changed: {self._status_cache.get(worker_id, 'unknown')} → {status} "
                        f"(last heartbeat: {seconds_ago}s ago)"
                    )
            
            return results
            
        except Exception as e:
            logger.error(f"Worker health check failed: {e}")
            return {}
    
    def get_worker_details(self) -> List[WorkerStatus]:
        """Get detailed worker status for dashboard."""
        try:
            query = """
                SELECT wn.id, wn.worker_id, wn.hostname, wn.ip_address, wn.location,
                       wn.last_heartbeat, wn.status as worker_status,
                       COUNT(w.id) as wallet_count
                FROM worker_nodes wn
                LEFT JOIN wallets w ON w.worker_node_id = wn.id
                GROUP BY wn.id, wn.worker_id, wn.hostname, wn.ip_address, wn.location, 
                         wn.last_heartbeat, wn.status
                ORDER BY wn.worker_id
            """
            workers = self.db.execute_query(query, fetch='all')
            
            now = datetime.now(timezone.utc)
            results = []
            
            for worker in workers:
                last_heartbeat = worker['last_heartbeat']
                
                if last_heartbeat is None:
                    status = 'offline'
                    seconds_ago = None
                else:
                    if last_heartbeat.tzinfo is None:
                        last_heartbeat = last_heartbeat.replace(tzinfo=timezone.utc)
                    
                    seconds_ago = int((now - last_heartbeat).total_seconds())
                    status = 'healthy' if seconds_ago < 120 else 'offline'
                
                results.append(WorkerStatus(
                    worker_id=worker['worker_id'],
                    hostname=worker['hostname'],
                    ip_address=str(worker['ip_address']),
                    location=worker['location'],
                    status=status,
                    last_heartbeat=last_heartbeat,
                    seconds_since_heartbeat=seconds_ago,
                    assigned_wallets=worker['wallet_count'] or 0
                ))
            
            return results
            
        except Exception as e:
            logger.error(f"Failed to get worker details: {e}")
            return []


# ============================================================================
# RPC HEALTH MONITOR
# ============================================================================

class RPCHealthMonitor:
    """
    Monitors RPC endpoints for all supported chains.
    
    Checks every 5 minutes:
    - Tests eth_blockNumber RPC call
    - Measures response time
    - Tracks consecutive failures
    - Automatic failover to backup endpoint
    
    Uses existing chain_rpc_endpoints table columns.
    """
    
    # Chains to monitor
    SUPPORTED_CHAINS = [
        'arbitrum', 'base', 'optimism', 'polygon', 
        'bnb', 'ink', 'megaeth', 'ethereum'
    ]
    
    def __init__(self, db_manager):
        """
        Initialize RPC health monitor.
        
        Args:
            db_manager: DatabaseManager instance
        """
        self.db = db_manager
        self._status_cache: Dict[int, str] = {}
        self._consecutive_failures: Dict[int, int] = {}
        logger.info("RPCHealthMonitor initialized")
    
    def check_all_endpoints(self) -> Dict[int, str]:
        """
        Test all RPC endpoints with proxy for anti-Sybil protection.
        
        Returns:
            Dict[endpoint_id, status] — 'healthy', 'degraded', or 'offline'
        """
        try:
            # Get monitoring proxy
            import random
            from activity.proxy_manager import get_proxy_url
            
            # Используем случайный wallet_id для TLS рандомизации
            monitoring_wallet_id = random.randint(1, 90)
            proxy_url = get_proxy_url(monitoring_wallet_id)
            
            # Get all active endpoints ordered by chain and priority
            query = """
                SELECT id, chain, url, priority, is_active,
                       avg_response_ms, failure_count
                FROM chain_rpc_endpoints
                WHERE is_active = TRUE
                ORDER BY chain, priority
            """
            endpoints = self.db.execute_query(query, fetch='all')
            
            results = {}
            
            for endpoint in endpoints:
                endpoint_id = endpoint['id']
                url = endpoint['url']
                chain = endpoint['chain']
                
                try:
                    # Test RPC call with timeout and proxy
                    start_time = time.time()
                    
                    if WEB3_AVAILABLE:
                        w3 = Web3(Web3.HTTPProvider(url, request_kwargs={'timeout': 10}))
                        block_number = w3.eth.block_number
                    else:
                        # HTTP request with TLS fingerprinting and proxy
                        response = requests.post(
                            url,
                            json={
                                "jsonrpc": "2.0",
                                "method": "eth_blockNumber",
                                "params": [],
                                "id": 1
                            },
                            timeout=10,
                            proxies={'http': proxy_url, 'https': proxy_url} if proxy_url else None,
                            impersonate="chrome120",
                            http2=True
                        )
                        response.raise_for_status()
                    
                    elapsed_ms = int((time.time() - start_time) * 1000)
                    
                    # Success - determine status based on response time
                    if elapsed_ms < 5000:  # 5 seconds
                        status = 'healthy'
                    else:
                        status = 'degraded'
                    
                    # Reset consecutive failures
                    self._consecutive_failures[endpoint_id] = 0
                    
                    # Update database
                    self._update_endpoint_status(
                        endpoint_id, status, elapsed_ms, 
                        increment_success=True
                    )
                    
                    logger.debug(f"RPC {chain} OK ({elapsed_ms}ms)")
                    
                except Exception as e:
                    # Failure
                    logger.warning(f"RPC {chain} failed: {e}")
                    
                    # Increment consecutive failures
                    failures = self._consecutive_failures.get(endpoint_id, 0) + 1
                    self._consecutive_failures[endpoint_id] = failures
                    
                    if failures >= 3:
                        status = 'offline'
                        # Trigger failover
                        self._failover_to_backup(chain, endpoint_id)
                    else:
                        status = 'degraded'
                    
                    # Update database
                    self._update_endpoint_status(
                        endpoint_id, status, None,
                        increment_failure=True
                    )
                
                results[endpoint_id] = status
                self._status_cache[endpoint_id] = status
            
            return results
            
        except Exception as e:
            logger.error(f"RPC health check failed: {e}")
            return {}
    
    def _update_endpoint_status(
        self, 
        endpoint_id: int, 
        status: str, 
        response_time_ms: Optional[int],
        increment_success: bool = False,
        increment_failure: bool = False
    ):
        """Update endpoint status in database."""
        try:
            if increment_success:
                query = """
                    UPDATE chain_rpc_endpoints 
                    SET success_count = success_count + 1,
                        avg_response_ms = %s,
                        last_used_at = NOW()
                    WHERE id = %s
                """
                self.db.execute_query(query, (response_time_ms, endpoint_id))
                
            elif increment_failure:
                query = """
                    UPDATE chain_rpc_endpoints 
                    SET failure_count = failure_count + 1
                    WHERE id = %s
                """
                self.db.execute_query(query, (endpoint_id,))
                
        except Exception as e:
            logger.error(f"Failed to update endpoint status: {e}")
    
    def _failover_to_backup(self, chain: str, failed_endpoint_id: int):
        """
        Disable failed RPC and activate backup endpoint.
        
        Args:
            chain: Chain name (e.g., 'arbitrum')
            failed_endpoint_id: ID of failed endpoint
        """
        try:
            # Disable failed endpoint
            self.db.execute_query(
                "UPDATE chain_rpc_endpoints SET is_active = FALSE WHERE id = %s",
                (failed_endpoint_id,)
            )
            
            logger.warning(f"RPC failover: Disabled endpoint {failed_endpoint_id} for chain {chain}")
            
            # Find backup endpoint (priority > 1, same chain)
            backup = self.db.execute_query(
                """SELECT id, url FROM chain_rpc_endpoints 
                   WHERE chain = %s AND priority > 1 AND is_active = FALSE
                   ORDER BY priority ASC LIMIT 1""",
                (chain,),
                fetch='one'
            )
            
            if backup:
                # Activate backup
                self.db.execute_query(
                    "UPDATE chain_rpc_endpoints SET is_active = TRUE WHERE id = %s",
                    (backup['id'],)
                )
                
                logger.warning(f"RPC failover: Activated backup {backup['url'][:50]}...")
                
                # Send Telegram alert
                try:
                    from notifications.telegram_bot import send_alert
                    send_alert(
                        'WARNING',
                        f"⚠️ RPC Failover\nChain: {chain}\nBackup activated: {backup['url'][:50]}..."
                    )
                except ImportError:
                    pass
            else:
                # NO BACKUP AVAILABLE
                logger.critical(f"NO BACKUP RPC FOR {chain}!")
                
                try:
                    from notifications.telegram_bot import send_alert
                    send_alert(
                        'CRITICAL',
                        f"🚨 RPC CRITICAL\nChain: {chain}\nNo backup available — MANUAL INTERVENTION REQUIRED"
                    )
                except ImportError:
                    pass
                    
        except Exception as e:
            logger.error(f"RPC failover failed: {e}")
    
    def get_endpoint_details(self) -> List[RPCEndpointStatus]:
        """Get detailed RPC endpoint status for dashboard."""
        try:
            query = """
                SELECT id, chain, url, priority, is_active, 
                       avg_response_ms, failure_count, last_used_at
                FROM chain_rpc_endpoints 
                ORDER BY chain, priority
            """
            endpoints = self.db.execute_query(query, fetch='all')
            
            results = []
            
            for endpoint in endpoints:
                endpoint_id = endpoint['id']
                
                # Determine status from cache or calculate
                status = self._status_cache.get(endpoint_id, 'healthy')
                
                # If not in cache, use failure count
                if endpoint_id not in self._status_cache:
                    if endpoint['failure_count'] >= 3:
                        status = 'offline'
                    elif endpoint['failure_count'] > 0:
                        status = 'degraded'
                
                results.append(RPCEndpointStatus(
                    endpoint_id=endpoint_id,
                    chain=endpoint['chain'],
                    url=endpoint['url'],
                    status=status,
                    is_active=endpoint['is_active'],
                    priority=endpoint['priority'],
                    response_time_ms=endpoint['avg_response_ms'],
                    last_health_check=endpoint['last_used_at'],
                    consecutive_failures=self._consecutive_failures.get(endpoint_id, 0)
                ))
            
            return results
            
        except Exception as e:
            logger.error(f"Failed to get endpoint details: {e}")
            return []


# ============================================================================
# DATABASE HEALTH MONITOR
# ============================================================================

class DatabaseHealthMonitor:
    """
    Monitors PostgreSQL database connection.
    
    Checks every 2 minutes:
    - Tests simple query (SELECT 1)
    - Measures query time
    - Checks connection pool availability
    """
    
    def __init__(self, db_manager):
        """
        Initialize Database health monitor.
        
        Args:
            db_manager: DatabaseManager instance
        """
        self.db = db_manager
        self._status_cache: str = 'healthy'
        logger.info("DatabaseHealthMonitor initialized")
    
    def check_connection(self) -> str:
        """
        Test database connection.
        
        Returns:
            'healthy', 'degraded', or 'offline'
        """
        try:
            start_time = time.time()
            
            # Test simple query
            result = self.db.execute_query("SELECT 1 AS test", fetch='one')
            elapsed_ms = int((time.time() - start_time) * 1000)
            
            if result and result['test'] == 1:
                if elapsed_ms < 1000:  # 1 second
                    status = 'healthy'
                else:
                    status = 'degraded'
                    logger.warning(f"Database slow: {elapsed_ms}ms")
            else:
                status = 'offline'
            
            self._status_cache = status
            return status
            
        except Exception as e:
            logger.error(f"Database health check failed: {e}")
            self._status_cache = 'offline'
            return 'offline'
    
    def get_status(self) -> DatabaseStatus:
        """Get detailed database status for dashboard."""
        try:
            start_time = time.time()
            result = self.db.execute_query("SELECT 1 AS test", fetch='one')
            elapsed_ms = int((time.time() - start_time) * 1000)
            
            # Get connection pool info
            pool = getattr(self.db, 'pool', None)
            available = pool.nconn if pool else 0
            
            status = 'healthy' if elapsed_ms < 1000 else 'degraded'
            
            return DatabaseStatus(
                status=status,
                connection_pool_available=available,
                last_check=datetime.now(timezone.utc),
                query_time_ms=elapsed_ms
            )
            
        except Exception as e:
            logger.error(f"Failed to get database status: {e}")
            return DatabaseStatus(
                status='offline',
                connection_pool_available=0,
                last_check=datetime.now(timezone.utc),
                query_time_ms=None
            )


# ============================================================================
# PROXY HEALTH MONITOR
# ============================================================================

class ProxyHealthMonitor:
    """
    Monitors proxy pool health and validates proxies.
    
    Checks every 6 hours:
    - Validates random 10% of proxies
    - Updates validation_status in database
    - Alerts if >10% of proxies are invalid
    
    Full validation on Sunday 03:00 UTC.
    """
    
    TEST_URL = 'https://ipinfo.io/json'
    TIMEOUT = 10
    
    def __init__(self, db_manager):
        """
        Initialize Proxy health monitor.
        
        Args:
            db_manager: DatabaseManager instance
        """
        self.db = db_manager
        self._status_cache: Dict[str, int] = {}
        logger.info("ProxyHealthMonitor initialized")
    
    def get_proxy_stats(self) -> ProxyStatus:
        """
        Get proxy pool statistics from database.
        
        Returns:
            ProxyStatus with current pool health
        """
        try:
            # Get validation status counts
            query = """
                SELECT
                    COUNT(*) as total,
                    COUNT(*) FILTER (WHERE validation_status = 'valid') as valid,
                    COUNT(*) FILTER (WHERE validation_status = 'invalid') as invalid,
                    COUNT(*) FILTER (WHERE validation_status = 'unknown' OR validation_status IS NULL) as unknown,
                    AVG(response_time_ms)::int as avg_response_ms
                FROM proxy_pool
                WHERE is_active = TRUE
            """
            result = self.db.execute_query(query, fetch='one')
            
            return ProxyStatus(
                total_proxies=result['total'] or 0,
                valid_proxies=result['valid'] or 0,
                invalid_proxies=result['invalid'] or 0,
                unknown_proxies=result['unknown'] or 0,
                avg_response_ms=result['avg_response_ms'],
                last_check=datetime.now(timezone.utc)
            )
            
        except Exception as e:
            logger.error(f"Failed to get proxy stats: {e}")
            return ProxyStatus(
                total_proxies=0,
                valid_proxies=0,
                invalid_proxies=0,
                unknown_proxies=0,
                avg_response_ms=None,
                last_check=datetime.now(timezone.utc)
            )
    
    def validate_random_proxies(self, percentage: float = 0.1) -> Dict[str, int]:
        """
        Validate a random subset of proxies.
        
        Args:
            percentage: Fraction of proxies to validate (default: 10%)
        
        Returns:
            Dict with validation results: {'valid': int, 'invalid': int}
        """
        try:
            # Get random subset of proxies to validate
            query = """
                SELECT id, ip_address, port, protocol, username, password, session_id
                FROM proxy_pool
                WHERE is_active = TRUE
                ORDER BY RANDOM()
                LIMIT (SELECT CEIL(COUNT(*) * %s) FROM proxy_pool WHERE is_active = TRUE)::int
            """
            proxies = self.db.execute_query(query, (percentage,), fetch='all')
            
            if not proxies:
                logger.warning("No proxies found to validate")
                return {'valid': 0, 'invalid': 0}
            
            results = {'valid': 0, 'invalid': 0}
            
            for proxy in proxies:
                is_valid, details = self._validate_single_proxy(proxy)
                
                if is_valid:
                    results['valid'] += 1
                    self._update_proxy_status(
                        proxy['id'],
                        'valid',
                        details
                    )
                else:
                    results['invalid'] += 1
                    self._update_proxy_status(
                        proxy['id'],
                        'invalid',
                        details
                    )
            
            logger.info(
                f"Proxy validation complete | Valid: {results['valid']} | "
                f"Invalid: {results['invalid']}"
            )
            
            return results
            
        except Exception as e:
            logger.error(f"Proxy validation failed: {e}")
            return {'valid': 0, 'invalid': 0}
    
    def _validate_single_proxy(self, proxy: Dict) -> tuple:
        """
        Validate a single proxy connection.
        
        Args:
            proxy: Dict with proxy configuration
        
        Returns:
            Tuple of (is_valid: bool, details: Dict)
        """
        import urllib.parse
        
        # Build proxy URL
        protocol = proxy['protocol']
        username = proxy['username']
        password = proxy['password']
        host = proxy['ip_address']
        port = proxy['port']
        encoded_password = urllib.parse.quote(password, safe='')
        proxy_url = f"{protocol}://{username}:{encoded_password}@{host}:{port}"
        proxies = {'http': proxy_url, 'https': proxy_url}
        
        try:
            start_time = time.time()
            response = requests.get(
                self.TEST_URL,
                proxies=proxies,
                timeout=self.TIMEOUT,
                impersonate="chrome110"
            )
            elapsed_ms = int((time.time() - start_time) * 1000)
            
            if response.status_code == 200:
                data = response.json()
                return True, {
                    'response_time_ms': elapsed_ms,
                    'detected_ip': data.get('ip'),
                    'detected_country': data.get('country')
                }
            else:
                return False, {'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            return False, {'error': str(e)[:200]}
    
    def _update_proxy_status(self, proxy_id: int, status: str, details: Dict) -> None:
        """Update proxy validation status in database."""
        try:
            if status == 'valid':
                query = """
                    UPDATE proxy_pool
                    SET validation_status = 'valid',
                        last_validated_at = NOW(),
                        validation_error = NULL,
                        response_time_ms = %s,
                        detected_ip = %s,
                        detected_country = %s
                    WHERE id = %s
                """
                self.db.execute_query(
                    query,
                    (
                        details.get('response_time_ms'),
                        details.get('detected_ip'),
                        details.get('detected_country'),
                        proxy_id
                    )
                )
            else:
                query = """
                    UPDATE proxy_pool
                    SET validation_status = 'invalid',
                        last_validated_at = NOW(),
                        validation_error = %s
                    WHERE id = %s
                """
                self.db.execute_query(
                    query,
                    (details.get('error', 'Unknown error'), proxy_id)
                )
        except Exception as e:
            logger.warning(f"Failed to update proxy status | ID: {proxy_id} | Error: {e}")


# ============================================================================
# HEALTH CHECK ORCHESTRATOR
# ============================================================================

class HealthCheckOrchestrator:
    """
    Central orchestrator for all health checks.
    
    Coordinates:
    - WorkerHealthMonitor (60s interval)
    - RPCHealthMonitor (5min interval)
    - DatabaseHealthMonitor (2min interval)
    - ProxyHealthMonitor (6h interval)
    
    Features:
    - Background monitoring threads
    - Alert throttling (5min cooldown)
    - System status dashboard
    - Graceful shutdown
    """
    
    def __init__(self, db_manager=None):
        """Initialize health check orchestrator.
        
        Args:
            db_manager: Optional DatabaseManager instance. If not provided,
                       creates a new one. Pass existing instance to reuse
                       connection pool and avoid creating new pools on each call.
        """
        if db_manager is not None:
            self.db = db_manager
        else:
            from database.db_manager import DatabaseManager
            self.db = DatabaseManager()
        
        # Initialize monitors
        self.worker_monitor = WorkerHealthMonitor(self.db)
        self.rpc_monitor = RPCHealthMonitor(self.db)
        self.db_monitor = DatabaseHealthMonitor(self.db)
        self.proxy_monitor = ProxyHealthMonitor(self.db)
        
        # Status caches
        self._worker_status: Dict[int, str] = {}
        self._rpc_status: Dict[int, str] = {}
        self._db_status: str = 'healthy'
        self._proxy_status: Optional[ProxyStatus] = None
        
        # Alert throttling
        self._last_alert_time: Dict[str, datetime] = {}
        self._alert_cooldown = timedelta(minutes=5)
        
        # Running flag
        self._running = False
        self._threads: List[threading.Thread] = []
        
        logger.info("HealthCheckOrchestrator initialized")
    
    def start(self):
        """Start all health check monitors in background threads."""
        if self._running:
            logger.warning("HealthCheckOrchestrator already running")
            return
        
        self._running = True
        logger.info("Starting Health Check Orchestrator...")
        
        # Worker heartbeat monitoring (every 60 seconds)
        worker_thread = threading.Thread(
            target=self._run_worker_checks,
            daemon=True,
            name="WorkerHealthCheck"
        )
        worker_thread.start()
        self._threads.append(worker_thread)
        
        # RPC endpoint monitoring (every 5 minutes)
        rpc_thread = threading.Thread(
            target=self._run_rpc_checks,
            daemon=True,
            name="RPCHealthCheck"
        )
        rpc_thread.start()
        self._threads.append(rpc_thread)
        
        # Database connection monitoring (every 2 minutes)
        db_thread = threading.Thread(
            target=self._run_db_checks,
            daemon=True,
            name="DBHealthCheck"
        )
        db_thread.start()
        self._threads.append(db_thread)
        
        # Proxy pool monitoring (every 6 hours)
        proxy_thread = threading.Thread(
            target=self._run_proxy_checks,
            daemon=True,
            name="ProxyHealthCheck"
        )
        proxy_thread.start()
        self._threads.append(proxy_thread)
        
        logger.info("Health Check Orchestrator started successfully")
    
    def stop(self):
        """Stop all health check monitors."""
        self._running = False
        logger.info("Stopping Health Check Orchestrator...")
        
        # Wait for threads to finish
        for thread in self._threads:
            thread.join(timeout=5)
        
        logger.info("Health Check Orchestrator stopped")
    
    def _run_worker_checks(self):
        """Background thread: check Worker heartbeats every 60 seconds."""
        while self._running:
            try:
                results = self.worker_monitor.check_all_workers()
                
                for worker_id, status in results.items():
                    # Status change detection
                    if self._worker_status.get(worker_id) != status:
                        self._handle_worker_status_change(worker_id, status)
                        self._worker_status[worker_id] = status
                        
            except Exception as e:
                logger.error(f"Worker health check thread error: {e}")
            
            time.sleep(60)  # 1 minute interval
    
    def _run_rpc_checks(self):
        """Background thread: check RPC endpoints every 5 minutes."""
        while self._running:
            try:
                results = self.rpc_monitor.check_all_endpoints()
                
                for endpoint_id, status in results.items():
                    if self._rpc_status.get(endpoint_id) != status:
                        self._handle_rpc_status_change(endpoint_id, status)
                        self._rpc_status[endpoint_id] = status
                        
            except Exception as e:
                logger.error(f"RPC health check thread error: {e}")
            
            time.sleep(300)  # 5 minutes
    
    def _run_db_checks(self):
        """Background thread: check database connection every 2 minutes."""
        while self._running:
            try:
                status = self.db_monitor.check_connection()
                
                if self._db_status != status:
                    self._handle_db_status_change(status)
                    self._db_status = status
                    
            except Exception as e:
                logger.error(f"Database health check thread error: {e}")
            
            time.sleep(120)  # 2 minutes
    
    def _run_proxy_checks(self):
        """Background thread: validate proxies every 6 hours."""
        while self._running:
            try:
                # Get current stats
                self._proxy_status = self.proxy_monitor.get_proxy_stats()
                
                # Validate random 10% of proxies
                results = self.proxy_monitor.validate_random_proxies(percentage=0.1)
                
                # Check if too many invalid
                total_checked = results['valid'] + results['invalid']
                if total_checked > 0:
                    invalid_rate = results['invalid'] / total_checked
                    if invalid_rate > 0.1:  # >10% invalid
                        self._handle_proxy_alert(invalid_rate, results)
                
                # Update stats after validation
                self._proxy_status = self.proxy_monitor.get_proxy_stats()
                    
            except Exception as e:
                logger.error(f"Proxy health check thread error: {e}")
            
            time.sleep(21600)  # 6 hours
    
    def _handle_proxy_alert(self, invalid_rate: float, results: Dict[str, int]):
        """Handle proxy validation alert."""
        alert_key = "proxy_pool"
        if self._should_skip_alert(alert_key):
            return
        
        severity = 'WARNING' if invalid_rate < 0.25 else 'CRITICAL'
        message = (
            f"⚠️ Proxy Pool Warning\n"
            f"Invalid rate: {invalid_rate*100:.1f}%\n"
            f"Valid: {results['valid']} | Invalid: {results['invalid']}"
        )
        
        self._send_alert(severity, message, alert_key)
        
        # Log to database
        self.db.log_system_event(
            event_type='PROXY_VALIDATION_WARNING',
            severity=severity,
            message=message,
            metadata={'invalid_rate': invalid_rate, 'results': results}
        )
    
    def _handle_worker_status_change(self, worker_id: int, new_status: str):
        """Handle Worker status change."""
        # Throttle alerts
        alert_key = f"worker_{worker_id}"
        if self._should_skip_alert(alert_key):
            return
        
        # Send Telegram alert
        if new_status == 'offline':
            severity = 'CRITICAL'
            message = f"🚨 Worker {worker_id} OFFLINE\nLast heartbeat: 5+ minutes ago"
        else:
            severity = 'INFO'
            message = f"✅ Worker {worker_id} RECOVERED"
        
        self._send_alert(severity, message, alert_key)
        
        # Log to database
        self.db.log_system_event(
            event_type='HEALTH_CHECK_FAILURE' if new_status == 'offline' else 'HEALTH_CHECK_RECOVERY',
            severity=severity,
            message=message,
            metadata={'worker_id': worker_id, 'status': new_status}
        )
    
    def _handle_rpc_status_change(self, endpoint_id: int, new_status: str):
        """Handle RPC endpoint status change."""
        alert_key = f"rpc_{endpoint_id}"
        if self._should_skip_alert(alert_key):
            return
        
        # Get endpoint details
        endpoints = self.rpc_monitor.get_endpoint_details()
        endpoint = next((e for e in endpoints if e.endpoint_id == endpoint_id), None)
        
        if endpoint:
            if new_status == 'offline':
                severity = 'CRITICAL'
                message = f"🚨 RPC {endpoint.chain} OFFLINE\nEndpoint: {endpoint.url[:40]}..."
            else:
                severity = 'WARNING'
                message = f"⚠️ RPC {endpoint.chain} degraded\nResponse time: {endpoint.response_time_ms}ms"
            
            self._send_alert(severity, message, alert_key)
    
    def _handle_db_status_change(self, new_status: str):
        """Handle database status change."""
        alert_key = "database"
        if self._should_skip_alert(alert_key):
            return
        
        if new_status == 'offline':
            severity = 'CRITICAL'
            message = "🚨 Database OFFLINE\nSystem may be non-functional!"
        elif new_status == 'degraded':
            severity = 'WARNING'
            message = "⚠️ Database degraded\nQuery time > 1 second"
        else:
            severity = 'INFO'
            message = "✅ Database recovered"
        
        self._send_alert(severity, message, alert_key)
        
        # Log to database
        self.db.log_system_event(
            event_type='HEALTH_CHECK_FAILURE' if new_status == 'offline' else 'HEALTH_CHECK_RECOVERY',
            severity=severity,
            message=message,
            metadata={'component': 'database', 'status': new_status}
        )
    
    def _should_skip_alert(self, alert_key: str) -> bool:
        """Check if alert should be skipped due to cooldown."""
        if alert_key in self._last_alert_time:
            if datetime.now() - self._last_alert_time[alert_key] < self._alert_cooldown:
                return True
        return False
    
    def _send_alert(self, severity: str, message: str, alert_key: str):
        """Send Telegram alert."""
        try:
            from notifications.telegram_bot import send_alert
            send_alert(severity, message)
            self._last_alert_time[alert_key] = datetime.now()
            logger.info(f"Alert sent: {message}")
        except ImportError:
            logger.warning(f"Telegram bot not available - alert not sent: {message}")
        except Exception as e:
            logger.error(f"Failed to send alert: {e}")
    
    def get_system_status(self) -> SystemHealthStatus:
        """
        Get current health status for Telegram /health command.
        
        Returns:
            SystemHealthStatus with all component statuses
        """
        # Get worker details
        workers = self.worker_monitor.get_worker_details()
        
        # Get RPC endpoint details
        rpc_endpoints = self.rpc_monitor.get_endpoint_details()
        
        # Get database status
        db_status = self.db_monitor.get_status()
        
        # Get proxy status
        proxy_status = self.proxy_monitor.get_proxy_stats()
        
        # Calculate overall status
        overall = 'healthy'
        
        # Check workers
        offline_workers = sum(1 for w in workers if w.status == 'offline')
        if offline_workers > 0:
            overall = 'critical'
        
        # Check RPC
        offline_rpc = sum(1 for r in rpc_endpoints if r.status == 'offline')
        if offline_rpc > 0:
            overall = 'critical'
        
        # Check database
        if db_status.status == 'offline':
            overall = 'critical'
        elif db_status.status == 'degraded' and overall == 'healthy':
            overall = 'degraded'
        
        # Check proxies
        if proxy_status.total_proxies > 0:
            invalid_rate = proxy_status.invalid_proxies / proxy_status.total_proxies
            if invalid_rate > 0.25:  # >25% invalid
                overall = 'critical'
            elif invalid_rate > 0.1 and overall == 'healthy':  # >10% invalid
                overall = 'degraded'
        
        return SystemHealthStatus(
            timestamp=datetime.now(timezone.utc).isoformat(),
            overall_status=overall,
            database=db_status,
            workers=workers,
            rpc_endpoints=rpc_endpoints,
            proxies=proxy_status
        )


# ============================================================================
# CLI INTERFACE
# ============================================================================

def main():
    """CLI interface for health check system."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Health Check System')
    parser.add_argument('command', choices=['status', 'workers', 'rpc', 'database'],
                        help='Command to execute')
    args = parser.parse_args()
    
    orchestrator = HealthCheckOrchestrator()
    
    if args.command == 'status':
        status = orchestrator.get_system_status()
        print(f"\n🏥 System Health Report")
        print(f"Timestamp: {status.timestamp}")
        print(f"Overall: {status.overall_status.upper()}")
        print(f"\nDatabase: {status.database.status} (pool: {status.database.connection_pool_available})")
        
        print(f"\nWorkers:")
        for worker in status.workers:
            emoji = "✅" if worker.status == 'healthy' else "🚨"
            print(f"  {emoji} Worker {worker.worker_id}: {worker.status} ({worker.location})")
        
        print(f"\nRPC Endpoints:")
        for rpc in status.rpc_endpoints:
            emoji = "✅" if rpc.status == 'healthy' else "⚠️" if rpc.status == 'degraded' else "🚨"
            print(f"  {emoji} {rpc.chain}: {rpc.status} ({rpc.response_time_ms}ms)")
    
    elif args.command == 'workers':
        workers = orchestrator.worker_monitor.get_worker_details()
        for worker in workers:
            print(f"Worker {worker.worker_id}: {worker.status} - {worker.last_heartbeat}")
    
    elif args.command == 'rpc':
        endpoints = orchestrator.rpc_monitor.get_endpoint_details()
        for endpoint in endpoints:
            print(f"{endpoint.chain}: {endpoint.status} - {endpoint.response_time_ms}ms")
    
    elif args.command == 'database':
        status = orchestrator.db_monitor.get_status()
        print(f"Database: {status.status}")
        print(f"Pool available: {status.connection_pool_available}")
        print(f"Query time: {status.query_time_ms}ms")


if __name__ == '__main__':
    main()