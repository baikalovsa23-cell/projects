#!/usr/bin/env python3
"""
IP Guard — Critical Security Module for Proxy IP Verification
==============================================================

Защита от утечек реального IP серверов при сбоях прокси.

Features:
- IP Assertion (Pre-flight): Проверка IP перед любым действием
- TTL Guard: Проверка времени жизни прокси перед сессией
- Heartbeat Check: Периодическая проверка IP во время длинных сессий

Security:
- При обнаружении утечки IP — немедленный sys.exit(1)
- Логирование всех проверок для аудита

Author: Airdrop Farming System v4.0
Created: 2026-03-03
"""

import sys
import time
import asyncio
import threading
from typing import Optional, Dict, Callable
from datetime import datetime, timezone, timedelta
from loguru import logger

# =============================================================================
# CRITICAL: Server IPs that must NEVER be exposed
# =============================================================================

# Load from database system_config table
def get_server_ips() -> Dict[str, str]:
    """
    Get server IPs from database system_config table.
    
    Returns:
        Dict mapping IP -> server name
    """
    try:
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent.parent))
        from database.db_manager import DatabaseManager
        
        db = DatabaseManager()
        server_ips_list = db.get_system_config('server_ips', default='[]')
        
        # Convert list to dict with placeholder names
        server_names = ['master_node_nl', 'worker_1_nl', 'worker_2_is', 'worker_3_is']
        return {ip: server_names[i] if i < len(server_names) else f'server_{i}' 
                for i, ip in enumerate(server_ips_list)}
    except Exception as e:
        logger.warning(f"Failed to load server IPs from DB, using fallback: {e}")
        # Fallback to hardcoded values
        return {
            '82.40.60.131': 'master_node_nl',
            '82.40.60.132': 'worker_1_nl',
            '82.22.53.183': 'worker_2_is',
            '82.22.53.184': 'worker_3_is',
        }

SERVER_IPS = get_server_ips()

# Decodo TTL (loaded from database system_config)
def get_decodo_ttl() -> int:
    """Get Decodo TTL minutes from database."""
    try:
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent.parent))
        from database.db_manager import DatabaseManager
        
        db = DatabaseManager()
        return db.get_system_config('decodo_ttl_minutes', default=60)
    except Exception as e:
        logger.warning(f"Failed to load Decodo TTL from DB, using fallback: {e}")
        return 60

def get_decodo_ttl_buffer() -> int:
    """Get Decodo TTL buffer minutes from database."""
    try:
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent.parent))
        from database.db_manager import DatabaseManager
        
        db = DatabaseManager()
        return db.get_system_config('decodo_ttl_buffer_minutes', default=10)
    except Exception as e:
        logger.warning(f"Failed to load Decodo TTL buffer from DB, using fallback: {e}")
        return 10

DECODO_TTL_MINUTES = get_decodo_ttl()
DECODO_TTL_BUFFER_MINUTES = get_decodo_ttl_buffer()


class IPLeakDetected(Exception):
    """Raised when IP leak is detected - CRITICAL SECURITY ERROR."""
    pass


class ProxyTTLExpired(Exception):
    """Raised when proxy TTL is about to expire."""
    pass


# =============================================================================
# IP ASSERTION (PRE-FLIGHT)
# =============================================================================

def verify_proxy_ip(
    current_ip: str,
    wallet_id: int,
    component: str = "unknown",
    expected_country: Optional[str] = None
) -> bool:
    """
    Проверяет, что текущий IP НЕ принадлежит нашим серверам.
    
    CRITICAL: Вызывается ПЕРЕД любым действием в сети.
    
    Args:
        current_ip: Текущий внешний IP
        wallet_id: ID кошелька
        component: Компонент (openclaw, executor, etc.)
        expected_country: Ожидаемая страна (опционально)
    
    Returns:
        True если IP безопасен
    
    Raises:
        IPLeakDetected: Если IP принадлежит нашим серверам
        SystemExit: При обнаружении утечки (sys.exit(1))
    """
    # Check if IP matches any server IP
    if current_ip in SERVER_IPS:
        server_name = SERVER_IPS[current_ip]
        error_msg = (
            f"🚨 CRITICAL: IP LEAK DETECTED!\n"
            f"   Component: {component}\n"
            f"   Wallet: {wallet_id}\n"
            f"   Leaked IP: {current_ip} ({server_name})\n"
            f"   Action: IMMEDIATE SHUTDOWN"
        )
        logger.critical(error_msg)
        
        # Send Telegram alert (if available)
        try:
            from notifications.telegram_bot import send_critical_alert
            asyncio.create_task(send_critical_alert(error_msg))
        except Exception:
            pass  # Don't fail if Telegram unavailable
        
        # CRITICAL: Exit immediately
        sys.exit(1)
    
    # Log successful verification
    logger.info(
        f"✅ IP verified | Component: {component} | "
        f"Wallet: {wallet_id} | IP: {current_ip}"
    )
    
    return True


def verify_proxy_ip_sync(
    proxy_url: str,
    wallet_id: int,
    component: str = "unknown"
) -> str:
    """
    Синхронная проверка IP через curl_cffi.
    
    Args:
        proxy_url: URL прокси (socks5://user:pass@host:port)
        wallet_id: ID кошелька
        component: Компонент
    
    Returns:
        Текущий внешний IP
    
    Raises:
        IPLeakDetected: При обнаружении утечки
    """
    from curl_cffi import requests
    
    try:
        response = requests.get(
            'https://ifconfig.me',
            proxies={'http': proxy_url, 'https': proxy_url},
            timeout=15,
            impersonate='chrome120'
        )
        current_ip = response.text.strip()
        
        # Verify IP is not server IP
        verify_proxy_ip(current_ip, wallet_id, component)
        
        return current_ip
        
    except Exception as e:
        logger.error(f"Failed to verify proxy IP | Wallet: {wallet_id} | Error: {e}")
        raise


async def verify_proxy_ip_async(
    proxy_url: str,
    wallet_id: int,
    component: str = "unknown"
) -> str:
    """
    Асинхронная проверка IP через curl_cffi.
    
    Args:
        proxy_url: URL прокси
        wallet_id: ID кошелька
        component: Компонент
    
    Returns:
        Текущий внешний IP
    """
    from curl_cffi.requests import AsyncSession
    
    try:
        async with AsyncSession(impersonate='chrome120') as session:
            session.proxies = {'http': proxy_url, 'https': proxy_url}
            response = await session.get('https://ifconfig.me', timeout=15)
            current_ip = response.text.strip()
            
            # Verify IP is not server IP
            verify_proxy_ip(current_ip, wallet_id, component)
            
            return current_ip
            
    except Exception as e:
        logger.error(f"Failed to verify proxy IP async | Wallet: {wallet_id} | Error: {e}")
        raise


# =============================================================================
# TTL GUARD
# =============================================================================

def check_proxy_ttl(
    provider: str,
    last_rotation_at: Optional[datetime] = None
) -> Dict:
    """
    Проверяет время жизни прокси перед запуском сессии.
    
    Для Decodo (60 min TTL):
    - Если осталось < 10 минут — ждать обновления
    
    Для IPRoyal (7 days TTL):
    - Всегда OK
    
    Args:
        provider: Провайдер ('iproyal' или 'decodo')
        last_rotation_at: Время последней ротации (опционально)
    
    Returns:
        Dict с результатом:
        {
            'ok': bool,
            'remaining_minutes': float,
            'should_wait': bool,
            'wait_seconds': int
        }
    """
    now = datetime.now(timezone.utc)
    
    if provider == 'iproyal':
        # IPRoyal: 7 days TTL - always OK
        return {
            'ok': True,
            'remaining_minutes': 7 * 24 * 60,  # 7 days
            'should_wait': False,
            'wait_seconds': 0
        }
    
    elif provider == 'decodo':
        # Decodo: 60 min TTL
        if last_rotation_at is None:
            # No rotation info - assume fresh session
            return {
                'ok': True,
                'remaining_minutes': DECODO_TTL_MINUTES,
                'should_wait': False,
                'wait_seconds': 0
            }
        
        # Calculate remaining time
        elapsed = (now - last_rotation_at).total_seconds() / 60
        remaining = DECODO_TTL_MINUTES - elapsed
        
        if remaining < DECODO_TTL_BUFFER_MINUTES:
            # Less than 10 min remaining - wait for new session
            wait_seconds = int(remaining * 60) + 60  # Wait until TTL expires + 1 min buffer
            
            logger.warning(
                f"⏳ Proxy TTL low | Provider: {provider} | "
                f"Remaining: {remaining:.1f} min | Waiting: {wait_seconds}s"
            )
            
            return {
                'ok': False,
                'remaining_minutes': remaining,
                'should_wait': True,
                'wait_seconds': wait_seconds
            }
        
        return {
            'ok': True,
            'remaining_minutes': remaining,
            'should_wait': False,
            'wait_seconds': 0
        }
    
    else:
        # Unknown provider - assume OK
        logger.warning(f"Unknown proxy provider: {provider}")
        return {
            'ok': True,
            'remaining_minutes': 60,
            'should_wait': False,
            'wait_seconds': 0
        }


def wait_for_ttl_refresh(wait_seconds: int) -> None:
    """
    Ждёт обновления TTL прокси.
    
    Args:
        wait_seconds: Время ожидания в секундах
    """
    logger.info(f"⏳ Waiting for proxy TTL refresh: {wait_seconds}s")
    time.sleep(wait_seconds)
    logger.info("✅ TTL wait complete")


# =============================================================================
# HEARTBEAT CHECK (for long sessions)
# =============================================================================

class IPHeartbeatMonitor:
    """
    Фоновый мониторинг IP для длинных сессий OpenClaw.
    
    Проверяет IP каждые 60 секунд.
    При обнаружении утечки — убивает процесс браузера.
    """
    
    def __init__(
        self,
        wallet_id: int,
        proxy_url: str,
        check_interval_seconds: int = 60,
        on_leak_callback: Optional[Callable] = None
    ):
        """
        Initialize heartbeat monitor.
        
        Args:
            wallet_id: ID кошелька
            proxy_url: URL прокси
            check_interval_seconds: Интервал проверки (default 60s)
            on_leak_callback: Callback при обнаружении утечки
        """
        self.wallet_id = wallet_id
        self.proxy_url = proxy_url
        self.check_interval = check_interval_seconds
        self.on_leak_callback = on_leak_callback
        
        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._last_ip: Optional[str] = None
        self._check_count = 0
    
    def start(self) -> None:
        """Запускает фоновый мониторинг."""
        if self._running:
            logger.warning("Heartbeat monitor already running")
            return
        
        self._running = True
        self._thread = threading.Thread(target=self._monitor_loop, daemon=True)
        self._thread.start()
        
        logger.info(
            f"💓 Heartbeat monitor started | "
            f"Wallet: {self.wallet_id} | "
            f"Interval: {self.check_interval}s"
        )
    
    def stop(self) -> None:
        """Останавливает мониторинг."""
        self._running = False
        if self._thread:
            self._thread.join(timeout=5)
        
        logger.info(
            f"💔 Heartbeat monitor stopped | "
            f"Wallet: {self.wallet_id} | "
            f"Checks: {self._check_count}"
        )
    
    def _monitor_loop(self) -> None:
        """Основной цикл мониторинга."""
        while self._running:
            try:
                # Check IP
                current_ip = verify_proxy_ip_sync(
                    self.proxy_url,
                    self.wallet_id,
                    component="heartbeat"
                )
                
                # Check for IP change (TTL rotation)
                if self._last_ip and current_ip != self._last_ip:
                    logger.warning(
                        f"🔄 IP changed during session | "
                        f"Wallet: {self.wallet_id} | "
                        f"Old: {self._last_ip} → New: {current_ip}"
                    )
                    # Note: This is not a leak, just TTL rotation
                
                self._last_ip = current_ip
                self._check_count += 1
                
            except IPLeakDetected:
                # CRITICAL: IP leak detected
                logger.critical(f"🚨 HEARTBEAT: IP LEAK DETECTED!")
                
                if self.on_leak_callback:
                    self.on_leak_callback()
                
                # Exit immediately
                sys.exit(1)
                
            except Exception as e:
                logger.error(f"Heartbeat check failed: {e}")
            
            # Wait for next check
            time.sleep(self.check_interval)
    
    def get_status(self) -> Dict:
        """Возвращает статус мониторинга."""
        return {
            'running': self._running,
            'wallet_id': self.wallet_id,
            'last_ip': self._last_ip,
            'check_count': self._check_count,
            'check_interval': self.check_interval
        }


# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

def pre_flight_check(
    wallet_id: int,
    proxy_url: str,
    proxy_provider: str,
    component: str = "unknown"
) -> str:
    """
    Полная pre-flight проверка перед любым сетевым действием.
    
    1. Проверяет TTL прокси
    2. Проверяет текущий IP
    
    Args:
        wallet_id: ID кошелька
        proxy_url: URL прокси
        proxy_provider: Провайдер ('iproyal' или 'decodo')
        component: Компонент
    
    Returns:
        Текущий внешний IP
    
    Raises:
        IPLeakDetected: При обнаружении утечки
    """
    logger.info(
        f"🔍 Pre-flight check | Component: {component} | "
        f"Wallet: {wallet_id} | Provider: {proxy_provider}"
    )
    
    # Step 1: Check TTL
    ttl_result = check_proxy_ttl(proxy_provider)
    if ttl_result['should_wait']:
        wait_for_ttl_refresh(ttl_result['wait_seconds'])
    
    # Step 2: Verify IP
    current_ip = verify_proxy_ip_sync(proxy_url, wallet_id, component)
    
    logger.info(
        f"✅ Pre-flight check passed | "
        f"Wallet: {wallet_id} | IP: {current_ip} | "
        f"TTL remaining: {ttl_result['remaining_minutes']:.1f} min"
    )
    
    return current_ip


# =============================================================================
# STANDALONE TEST
# =============================================================================

if __name__ == '__main__':
    print("IP Guard Test")
    print("=" * 60)
    
    # Test 1: Verify server IPs
    print("\n1. Testing server IP detection:")
    for ip in SERVER_IPS:
        print(f"   {ip} → {SERVER_IPS[ip]}")
    
    # Test 2: TTL check
    print("\n2. Testing TTL check:")
    for provider in ['iproyal', 'decodo']:
        result = check_proxy_ttl(provider)
        print(f"   {provider}: {result}")
    
    # Test 3: Pre-flight check (would fail without real proxy)
    print("\n3. Pre-flight check (requires real proxy):")
    print("   Skipped - requires real proxy configuration")
    
    print("\n" + "=" * 60)
    print("✅ IP Guard module loaded successfully")
