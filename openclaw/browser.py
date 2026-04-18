"""
OpenClaw Browser Engine — Puppeteer Wrapper + Anti-Detection
==============================================================

Управляет headless браузером (pyppeteer) с встроенной защитой от детекции.

Features:
- Stealth mode (anti-fingerprinting)
- Proxy integration (SOCKS5 from DB)
- Human-like behavior (random delays, mouse movements)
- Error handling с retry logic
- MetaMask wallet injection
- IP LEAK PROTECTION (v4.1) — Pre-flight check, TTL guard, Heartbeat
- CANVAS/WebGL/AudioContext Fingerprinting (v4.2) — Deterministic per wallet

Author: Senior Backend Developer
Created: 2026-02-25
Updated: 2026-03-06 — Canvas/WebGL/AudioContext fingerprinting added
"""

import asyncio
import random
import base64
import numpy as np
from typing import Optional, Dict, Any, List
from pyppeteer import launch
from pyppeteer.browser import Browser
from pyppeteer.page import Page
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential

# TLS Fingerprinting synchronization
from infrastructure.identity_manager import identity_manager

# IP LEAK PROTECTION (v4.1)
from infrastructure.ip_guard import (
    pre_flight_check,
    verify_proxy_ip,
    IPHeartbeatMonitor,
    IPLeakDetected
)

# Canvas/WebGL/AudioContext Fingerprinting (v4.2)
from openclaw.fingerprint import FingerprintGenerator, get_fingerprint

# OpenClaw exceptions
from openclaw.exceptions import ElementNotFoundError


class BrowserEngine:
    """
    Puppeteer wrapper с anti-detection механизмами.
    
    Features:
    - TLS fingerprint synchronization with Python scripts
    - Canvas/WebGL/AudioContext fingerprint spoofing
    - IP leak protection with heartbeat monitoring
    - LLM Vision integration for self-healing
    
    Example:
        async with BrowserEngine(wallet_id=5, proxy_url="socks5://...") as engine:
            page = await engine.new_page()
            await page.goto("https://gitcoin.co")
            # ... work with page ...
    """
    
    def __init__(
        self,
        proxy_url: Optional[str] = None,
        proxy_provider: Optional[str] = None,  # 'iproyal' or 'decodo' for TTL check
        headless: bool = True,
        stealth_mode: bool = True,
        wallet_address: Optional[str] = None,
        wallet_id: Optional[int] = None,  # REQUIRED for TLS + Canvas fingerprint
        enable_heartbeat: bool = True,  # Enable IP heartbeat monitoring
        enable_fingerprint: bool = True  # Enable Canvas/WebGL fingerprinting
    ):
        """
        Initialize browser engine with TLS fingerprint matching Python scripts.
        
        Args:
            proxy_url: SOCKS5 прокси URL (socks5://user:pass@host:port)
            proxy_provider: Provider name ('iproyal' or 'decodo') for TTL check
            headless: Headless режим (True for production)
            stealth_mode: Включить anti-detection плагины
            wallet_address: Ethereum адрес для MetaMask injection
            wallet_id: Wallet ID (1-90) for deterministic fingerprint (REQUIRED for Tier A)
            enable_heartbeat: Enable IP heartbeat monitoring for long sessions
            enable_fingerprint: Enable Canvas/WebGL/AudioContext fingerprinting
        """
        self.proxy_url = proxy_url
        self.proxy_provider = proxy_provider
        self.headless = headless
        self.stealth_mode = stealth_mode
        self.wallet_address = wallet_address
        self.wallet_id = wallet_id
        self.enable_heartbeat = enable_heartbeat
        self.enable_fingerprint = enable_fingerprint
        
        # IP Heartbeat Monitor (for long sessions)
        self._heartbeat_monitor: Optional[IPHeartbeatMonitor] = None
        self._verified_ip: Optional[str] = None
        
        # Fingerprint generator (v4.2)
        self._fingerprint_gen = FingerprintGenerator()
        self._fingerprint: Optional[Dict] = None
        
        # Get TLS configuration if wallet_id provided
        if wallet_id is not None:
            if not 1 <= wallet_id <= 90:
                raise ValueError(f"wallet_id must be in range [1, 90], got {wallet_id}")
            self.tls_config = identity_manager.get_config(wallet_id)
            
            # Get Canvas/WebGL fingerprint (v4.2)
            if self.enable_fingerprint:
                self._fingerprint = self._fingerprint_gen.get_fingerprint(wallet_id)
            
            tier = "TIER_A" if wallet_id <= 18 else "TIER_B/C"
            logger.debug(
                f"[{tier}] Browser TLS config: {self.tls_config['impersonate']} "
                f"on {self.tls_config['platform']} | "
                f"WebGL: {self._fingerprint['webgl_renderer'][:30] if self._fingerprint else 'N/A'}..."
            )
        else:
            self.tls_config = None
            logger.warning(
                "BrowserEngine initialized without wallet_id - "
                "TLS fingerprint will NOT match Python scripts!"
            )
        
        self.browser: Optional[Browser] = None
        self.pages: List[Page] = []
        
        logger.debug(f"Initialized BrowserEngine | Proxy: {bool(proxy_url)} | Stealth: {stealth_mode} | Fingerprint: {enable_fingerprint}")
    
    async def __aenter__(self):
        """Async context manager — launch браузера."""
        await self.launch()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager — закрытие браузера."""
        await self.close()
    
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=4, max=10),
        reraise=True
    )
    async def launch(self):
        """
        Запускает headless браузер с anti-detection настройками.
        
        CRITICAL: Includes IP leak protection (v4.1)
        - Pre-flight IP verification
        - TTL guard for Decodo proxies
        - Heartbeat monitoring for long sessions
        
        Raises:
            IPLeakDetected: If IP leak is detected
            Exception: Если браузер не запустился
        """
        # =================================================================
        # CRITICAL: PRE-FLIGHT IP VERIFICATION
        # =================================================================
        if self.proxy_url and self.wallet_id:
            try:
                # Verify proxy IP before launching browser
                self._verified_ip = pre_flight_check(
                    wallet_id=self.wallet_id,
                    proxy_url=self.proxy_url,
                    proxy_provider=self.proxy_provider or 'unknown',
                    component='openclaw_browser'
                )
                logger.success(f"✅ Pre-flight IP check passed | IP: {self._verified_ip}")
            except IPLeakDetected:
                logger.critical("🚨 PRE-FLIGHT CHECK FAILED: IP LEAK DETECTED!")
                raise
            except Exception as e:
                logger.error(f"Pre-flight check error: {e}")
                # Continue anyway - will be caught by heartbeat if leak occurs
        
        # Log TLS fingerprint info
        if self.tls_config:
            tier = "TIER_A" if self.wallet_id <= 18 else "TIER_B/C"
            logger.info(
                f"🚀 [{tier}] Launching browser for wallet {self.wallet_id} | "
                f"TLS: {self.tls_config['impersonate']} | "
                f"Platform: {self.tls_config['platform']} | "
                f"Headless: {self.headless} | "
                f"Proxy: {bool(self.proxy_url)} | "
                f"Verified IP: {self._verified_ip}"
            )
        else:
            logger.info(f"🚀 Launching browser | Headless: {self.headless} | Proxy: {bool(self.proxy_url)}")
        
        # Browser launch arguments
        args = [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-blink-features=AutomationControlled',  # Hide automation
            '--disable-dev-shm-usage',
            '--disable-accelerated-2d-canvas',
            '--disable-gpu',
            '--window-size=1920,1080',
            '--lang=en-US,en;q=0.9',
        ]
        
        # Add User-Agent from TLS config (synchronization with Python scripts)
        if self.tls_config:
            args.append(f'--user-agent={self.tls_config["user_agent"]}')
        
        # Add proxy if provided
        if self.proxy_url:
            # Convert socks5://user:pass@host:port to --proxy-server format
            # Pyppeteer expects: --proxy-server=socks5://host:port
            # Auth will be handled via page.authenticate()
            proxy_host_port = self.proxy_url.split('@')[-1]  # Extract host:port
            args.append(f'--proxy-server=socks5://{proxy_host_port}')
        
        try:
            self.browser = await launch({
                'headless': self.headless,
                'args': args,
                'ignoreHTTPSErrors': True,
                'defaultViewport': {
                    'width': 1920,
                    'height': 1080
                }
            })
            
            logger.success(f"✅ Browser launched successfully")
            
            # =================================================================
            # CRITICAL: START HEARTBEAT MONITORING
            # =================================================================
            if self.enable_heartbeat and self.proxy_url and self.wallet_id:
                self._heartbeat_monitor = IPHeartbeatMonitor(
                    wallet_id=self.wallet_id,
                    proxy_url=self.proxy_url,
                    check_interval_seconds=60  # Check every 60 seconds
                )
                self._heartbeat_monitor.start()
                logger.info(f"💓 Heartbeat monitoring started | Interval: 60s | IP: {self._verified_ip}")
            
        except Exception as e:
            logger.error(f"❌ Failed to launch browser: {e}")
            raise
    
    async def new_page(self) -> Page:
        """
        Создает новую страницу с anti-detection настройками.
        
        CRITICAL: Injects Canvas/WebGL/AudioContext fingerprint BEFORE any page loads.
        
        Returns:
            Pyppeteer Page object
        
        Raises:
            RuntimeError: Если браузер не запущен
        """
        if not self.browser:
            raise RuntimeError("Browser not launched. Call launch() first.")
        
        page = await self.browser.newPage()
        
        # Proxy authentication (если есть credentials в URL)
        if self.proxy_url and '@' in self.proxy_url:
            # Extract username:password from socks5://user:pass@host:port
            creds_part = self.proxy_url.split('//')[1].split('@')[0]
            username, password = creds_part.split(':')
            await page.authenticate({'username': username, 'password': password})
        
        # =================================================================
        # CRITICAL: INJECT FINGERPRINT SCRIPT FIRST (v4.2)
        # This MUST be done BEFORE any page loads to ensure consistent fingerprint
        # =================================================================
        if self._fingerprint and self.enable_fingerprint:
            await page.evaluateOnNewDocument(self._fingerprint['inject_script'])
            logger.debug(
                f"Injected fingerprint script | Wallet: {self.wallet_id} | "
                f"Canvas seed: {self._fingerprint['canvas_seed']} | "
                f"WebGL: {self._fingerprint['webgl_renderer'][:30]}..."
            )
        
        # Apply anti-detection scripts (stealth mode)
        if self.stealth_mode:
            await self._apply_stealth_mode(page)
        
        # Inject MetaMask wallet (if address provided)
        if self.wallet_address:
            await self._inject_metamask(page)
        
        # Set User-Agent matching TLS fingerprint (or fallback to generic)
        if self.tls_config:
            user_agent = self.tls_config['user_agent']
            logger.debug(f"Setting UA for wallet {self.wallet_id}: {user_agent[:60]}...")
        else:
            # Fallback UA (generic Chrome 120)
            user_agent = (
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/120.0.0.0 Safari/537.36'
            )
            logger.warning("Using fallback UA - no TLS fingerprint synchronization!")
        
        await page.setUserAgent(user_agent)
        
        # Set extra headers
        extra_headers = {
            'Accept-Language': 'en-US,en;q=0.9',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        }
        
        # Add Client Hints if TLS config available
        if self.tls_config:
            extra_headers['Sec-Ch-Ua'] = self.tls_config['sec_ch_ua']
            extra_headers['Sec-Ch-Ua-Platform'] = self.tls_config['sec_ch_ua_platform']
            extra_headers['Sec-Ch-Ua-Mobile'] = self.tls_config['sec_ch_ua_mobile']
        
        await page.setExtraHTTPHeaders(extra_headers)
        
        self.pages.append(page)
        logger.debug(f"Created new page | Total pages: {len(self.pages)}")
        
        return page
    
    async def take_screenshot_base64(self, page: Optional[Page] = None) -> str:
        """
        Takes screenshot and returns as base64 string.
        
        Used for LLM Vision analysis.
        
        Args:
            page: Page to screenshot (defaults to last created page)
        
        Returns:
            Base64-encoded PNG screenshot
        """
        if page is None:
            if not self.pages:
                raise RuntimeError("No pages available for screenshot")
            page = self.pages[-1]
        
        screenshot_bytes = await page.screenshot({'encoding': 'binary'})
        return base64.b64encode(screenshot_bytes).decode('utf-8')
    
    async def execute_action(self, action: Dict, page: Optional[Page] = None) -> bool:
        """
        Execute an action from LLM Vision response.
        
        Args:
            action: Action dict from LLM (e.g., {"action": "click", "selector": "button"})
            page: Page to execute on (defaults to last created page)
        
        Returns:
            True if action executed successfully
        
        Raises:
            ElementNotFoundError: If selector not found
            ValueError: If action is invalid
        """
        if page is None:
            if not self.pages:
                raise RuntimeError("No pages available for action execution")
            page = self.pages[-1]
        
        action_type = action.get('action', '').lower()
        
        if action_type == 'click':
            selector = action.get('selector')
            coordinates = action.get('coordinates')
            
            if selector:
                try:
                    await page.click(selector)
                    logger.debug(f"Clicked element: {selector}")
                    return True
                except Exception as e:
                    logger.warning(f"Failed to click {selector}: {e}")
                    raise ElementNotFoundError(selector, str(page.url), timeout=0)
            
            elif coordinates:
                x = coordinates.get('x', 0)
                y = coordinates.get('y', 0)
                await page.mouse.click(x, y)
                logger.debug(f"Clicked at coordinates: ({x}, {y})")
                return True
        
        elif action_type == 'type':
            selector = action.get('selector')
            text = action.get('text', '')
            
            if not selector:
                raise ValueError("Type action requires 'selector'")
            
            try:
                await page.type(selector, text)
                logger.debug(f"Typed '{text[:20]}...' into {selector}")
                return True
            except Exception as e:
                logger.warning(f"Failed to type into {selector}: {e}")
                raise ElementNotFoundError(selector, str(page.url), timeout=0)
        
        elif action_type == 'scroll':
            direction = action.get('direction', 'down')
            amount = action.get('amount', 500)
            
            if direction == 'down':
                await page.evaluate(f'window.scrollBy(0, {amount})')
            elif direction == 'up':
                await page.evaluate(f'window.scrollBy(0, -{amount})')
            
            logger.debug(f"Scrolled {direction} by {amount}px")
            return True
        
        elif action_type == 'wait':
            duration = action.get('duration', 2)
            await asyncio.sleep(duration)
            logger.debug(f"Waited {duration}s")
            return True
        
        elif action_type == 'navigate':
            url = action.get('url')
            if not url:
                raise ValueError("Navigate action requires 'url'")
            
            await page.goto(url, {'waitUntil': 'networkidle0'})
            logger.debug(f"Navigated to {url}")
            return True
        
        elif action_type in ('complete', 'fail'):
            # These are terminal actions, no execution needed
            return True
        
        else:
            raise ValueError(f"Unknown action type: {action_type}")
        
        return False
    
    async def _apply_stealth_mode(self, page: Page):
        """
        Применяет anti-detection скрипты к странице.
        
        Hide:
        - navigator.webdriver
        - window.chrome missing
        - Permissions API
        - Plugins array
        
        Args:
            page: Pyppeteer page
        """
        # Override navigator.webdriver
        await page.evaluateOnNewDocument('''
            () => {
                // Hide webdriver property
                Object.defineProperty(navigator, 'webdriver', {
                    get: () => undefined
                });
                
                // Add chrome object (present in real Chrome)
                window.chrome = {
                    runtime: {}
                };
                
                // Override permissions API
                const originalQuery = window.navigator.permissions.query;
                window.navigator.permissions.query = (parameters) => (
                    parameters.name === 'notifications' ?
                        Promise.resolve({ state: Notification.permission }) :
                        originalQuery(parameters)
                );
                
                // Add plugins (headless Chrome has none)
                Object.defineProperty(navigator, 'plugins', {
                    get: () => [1, 2, 3, 4, 5]
                });
                
                // Override languages
                Object.defineProperty(navigator, 'languages', {
                    get: () => ['en-US', 'en']
                });
            }
        ''')
        
        logger.debug("Applied stealth mode to page")
    
    async def _inject_metamask(self, page: Page):
        """
        Инжектит MetaMask-like ethereum provider в страницу.
        
        Minimal implementation для прохождения wallet connection checks.
        
        Args:
            page: Pyppeteer page
        """
        # Inject window.ethereum object
        await page.evaluateOnNewDocument(f'''
            () => {{
                window.ethereum = {{
                    isMetaMask: true,
                    selectedAddress: "{self.wallet_address}",
                    chainId: "0x1",  // Mainnet
                    networkVersion: "1",
                    
                    request: async ({{ method, params }}) => {{
                        console.log("MetaMask request:", method, params);
                        
                        if (method === "eth_requestAccounts") {{
                            return ["{self.wallet_address}"];
                        }}
                        
                        if (method === "eth_accounts") {{
                            return ["{self.wallet_address}"];
                        }}
                        
                        if (method === "eth_chainId") {{
                            return "0x1";
                        }}
                        
                        // Default response
                        return null;
                    }},
                    
                    // Legacy methods
                    enable: async () => ["{self.wallet_address}"],
                    sendAsync: (payload, callback) => {{
                        console.log("MetaMask sendAsync:", payload);
                        callback(null, {{ result: null }});
                    }}
                }};
                
                // Also inject to window.web3 for legacy dApps
                window.web3 = {{
                    currentProvider: window.ethereum
                }};
            }}
        ''')
        
        logger.debug(f"Injected MetaMask provider | Address: {self.wallet_address}")
    
    async def human_delay(self, min_seconds: float = 1.0, max_seconds: float = 3.0):
        """
        Human-like random delay.
        
        Args:
            min_seconds: Minimum delay
            max_seconds: Maximum delay
        """
        mean = (min_seconds + max_seconds) / 2
        std = (max_seconds - min_seconds) / 4
        delay = np.random.normal(mean=mean, std=std)
        delay = max(min_seconds, min(max_seconds, delay))  # Clip to range
        await asyncio.sleep(delay)
    
    async def random_mouse_movement(self, page: Page):
        """
        Случайное движение мыши (имитация человека).
        
        Args:
            page: Pyppeteer page
        """
        # Random coordinates
        x = random.randint(100, 1800)
        y = random.randint(100, 1000)
        
        # Move mouse in small steps
        steps = random.randint(10, 30)
        await page.mouse.move(x, y, {'steps': steps})
        
        logger.debug(f"Mouse moved to ({x}, {y})")
    
    async def close(self):
        """
        Закрывает браузер и все страницы.
        
        CRITICAL: Stops heartbeat monitoring first (v4.1)
        """
        # =================================================================
        # CRITICAL: STOP HEARTBEAT MONITORING
        # =================================================================
        if self._heartbeat_monitor:
            logger.info("🛑 Stopping heartbeat monitor...")
            self._heartbeat_monitor.stop()
            self._heartbeat_monitor = None
        
        if self.browser:
            logger.info(f"🔒 Closing browser | Pages: {len(self.pages)}")
            
            # Close all pages
            for page in self.pages:
                try:
                    await page.close()
                except Exception as e:
                    logger.warning(f"Error closing page: {e}")
            
            # Close browser
            await self.browser.close()
            
            self.browser = None
            self.pages = []
            
            logger.success("Browser closed")
    
    async def screenshot(self, page: Page, path: str):
        """
        Делает screenshot страницы (debugging).
        
        Args:
            page: Pyppeteer page
            path: Путь для сохранения (e.g., /tmp/screenshot.png)
        """
        await page.screenshot({'path': path})
        logger.debug(f"Screenshot saved: {path}")
    
    async def wait_for_selector(
        self, 
        page: Page, 
        selector: str, 
        timeout: int = 30000
    ) -> bool:
        """
        Ждет появления элемента на странице.
        
        Args:
            page: Pyppeteer page
            selector: CSS selector
            timeout: Таймаут в миллисекундах
        
        Returns:
            True если элемент появился, False если timeout
        """
        try:
            await page.waitForSelector(selector, {'timeout': timeout})
            return True
        except Exception as e:
            logger.warning(f"Selector {selector} not found within {timeout}ms: {e}")
            return False


class BrowserPool:
    """
    Pool of browser instances (для параллельной работы с несколькими кошельками).
    
    TODO: Implement если потребуется одновременная работа с >1 кошельком.
    """
    
    def __init__(self, pool_size: int = 3):
        self.pool_size = pool_size
        self.browsers: list[BrowserEngine] = []
    
    async def initialize(self):
        """Инициализирует pool браузеров."""
        logger.info(f"Initializing browser pool | Size: {self.pool_size}")
        
        for i in range(self.pool_size):
            engine = BrowserEngine(headless=True, stealth_mode=True)
            await engine.launch()
            self.browsers.append(engine)
        
        logger.success(f"Browser pool initialized | {self.pool_size} instances")
    
    async def get_browser(self) -> BrowserEngine:
        """
        Получает свободный браузер из pool.
        
        Returns:
            BrowserEngine instance
        """
        # Simple implementation: return first browser
        # TODO: Implement proper pooling logic
        return self.browsers[0] if self.browsers else None
    
    async def close_all(self):
        """Закрывает все браузеры в pool."""
        logger.info(f"Closing browser pool | Browsers: {len(self.browsers)}")
        
        for browser in self.browsers:
            await browser.close()
        
        self.browsers = []
        logger.success("Browser pool closed")
