"""
OpenClaw Base Task — Abstract Class
=====================================

Базовый класс для всех OpenClaw задач (Gitcoin, POAP, ENS, Snapshot, Lens).

Предоставляет:
- Единый интерфейс для задач
- Dry-run режим (simulation without real execution)
- Error handling framework
- CAPTCHA solving integration (placeholder)
- Human-like behavior helpers
"""

import asyncio
import random
import numpy as np
from abc import ABC, abstractmethod
from typing import Dict, Optional, Any
from datetime import datetime
from loguru import logger


class BaseTask(ABC):
    """
    Abstract base class для всех OpenClaw tasks.
    
    Подклассы должны реализовать:
    - execute_real() — реальное выполнение задачи
    - mock_result() — mock данные для dry-run режима
    """
    
    def __init__(
        self, 
        wallet_id: int, 
        task_params: Dict[str, Any],
        dry_run: bool = False
    ):
        """
        Initialize task.
        
        Args:
            wallet_id: ID кошелька
            task_params: JSONB параметры задачи
            dry_run: Если True → simulation mode (no real execution)
        """
        self.wallet_id = wallet_id
        self.task_params = task_params
        self.dry_run = dry_run
        self.task_name = self.__class__.__name__
        
        logger.debug(f"Initialized {self.task_name} | Wallet: {wallet_id} | Dry-run: {dry_run}")
    
    async def execute(self) -> Dict[str, Any]:
        """
        Execute task (dry-run или real).
        
        Returns:
            Dict с результатом выполнения:
            {
                "status": "success" | "failed",
                "data": {...},  # Task-specific data
                "dry_run": bool
            }
        """
        if self.dry_run:
            logger.info(f"[DRY-RUN] Simulating {self.task_name} for wallet {self.wallet_id}")
            
            # Simulate execution time (1-3 seconds)
            delay = np.random.normal(mean=2.0, std=0.5)  # mean=(1+3)/2, std=range/4
            delay = max(1, min(3, delay))  # Clip to original range
            await asyncio.sleep(delay)
            
            # Return mock result
            mock_data = self._mock_result()
            return {
                "status": "success",
                "data": mock_data,
                "dry_run": True
            }
        
        # Real execution
        logger.info(f"🚀 Executing {self.task_name} for wallet {self.wallet_id}")
        
        try:
            result_data = await self._execute_real()
            
            return {
                "status": "success",
                "data": result_data,
                "dry_run": False
            }
        
        except Exception as e:
            logger.error(f"❌ Task {self.task_name} failed: {e}")
            raise
    
    @abstractmethod
    async def _execute_real(self) -> Dict[str, Any]:
        """
        Реальное выполнение задачи (MUST OVERRIDE в подклассах).
        
        Returns:
            Dict с данными результата (будет сохранен в task_history.metadata)
        
        Raises:
            Exception при ошибке выполнения
        """
        raise NotImplementedError(f"{self.task_name}._execute_real() not implemented")
    
    @abstractmethod
    def _mock_result(self) -> Dict[str, Any]:
        """
        Генерирует mock данные для dry-run режима (MUST OVERRIDE в подклассах).
        
        Returns:
            Dict с mock данными (realistic format)
        """
        raise NotImplementedError(f"{self.task_name}._mock_result() not implemented")
    
    # === Helper Methods (используются подклассами) ===
    
    async def human_delay(self, min_seconds: float = 0.5, max_seconds: float = 2.0):
        """
        Human-like delay (random паузы для антидетекта).
        
        Args:
            min_seconds: Минимальная пауза
            max_seconds: Максимальная пауза
        """
        mean = (min_seconds + max_seconds) / 2
        std = (max_seconds - min_seconds) / 4
        delay = np.random.normal(mean=mean, std=std)
        delay = max(min_seconds, min(max_seconds, delay))  # Clip to range
        await asyncio.sleep(delay)
    
    async def human_type(self, text: str, element, min_delay: float = 0.05, max_delay: float = 0.15):
        """
        Human-like typing (посимвольный ввод с паузами).
        
        Args:
            text: Текст для ввода
            element: Pyppeteer element для type()
            min_delay: Минимальная пауза между символами
            max_delay: Максимальная пауза между символами
        """
        for char in text:
            await element.type(char)
            mean = (min_delay + max_delay) / 2
            std = (max_delay - min_delay) / 4
            delay = np.random.normal(mean=mean, std=std)
            delay = max(min_delay, min(max_delay, delay))  # Clip to range
            await asyncio.sleep(delay)
    
    async def human_click(self, element):
        """
        Human-like click (click с предварительным hover и паузой).
        
        Args:
            element: Pyppeteer element для click()
        """
        # Hover перед click
        await element.hover()
        
        # Random пауза перед click (100-500ms)
        delay = np.random.normal(mean=0.3, std=0.1)  # mean=(0.1+0.5)/2, std=range/4
        delay = max(0.1, min(0.5, delay))  # Clip to range
        await asyncio.sleep(delay)
        
        # Click
        await element.click()
    
    async def random_scroll(self, page, min_pixels: int = 300, max_pixels: int = 800):
        """
        Random scroll (имитация browsing behavior).
        
        Args:
            page: Pyppeteer page object
            min_pixels: Минимальная дистанция scroll
            max_pixels: Максимальная дистанция scroll
        """
        scroll_distance = random.randint(min_pixels, max_pixels)
        steps = random.randint(10, 30)
        
        for i in range(steps):
            await page.evaluate(f'window.scrollBy(0, {scroll_distance / steps})')
            delay = np.random.normal(mean=0.05, std=0.015)  # mean=(0.02+0.08)/2, std=range/4
            delay = max(0.02, min(0.08, delay))  # Clip to range
            await asyncio.sleep(delay)
    
    def get_task_param(self, key: str, default: Any = None) -> Any:
        """
        Получает параметр задачи из task_params JSONB.
        
        Args:
            key: Ключ параметра
            default: Значение по умолчанию
        
        Returns:
            Значение параметра или default
        """
        return self.task_params.get(key, default)
    
    async def solve_captcha(self, captcha_type: str, site_key: str, url: str) -> Optional[str]:
        """
        Решает CAPTCHA через 2captcha API (placeholder).
        
        TODO: Implement реальную интеграцию с 2captcha/CapSolver
        
        Args:
            captcha_type: Тип CAPTCHA ('recaptcha_v2', 'hcaptcha', 'recaptcha_v3')
            site_key: Site key (из HTML)
            url: URL страницы с CAPTCHA
        
        Returns:
            CAPTCHA solution token или None
        """
        if self.dry_run:
            logger.debug(f"[DRY-RUN] Skipping CAPTCHA solving")
            return "mock_captcha_token_12345"
        
        logger.warning(f"⚠️ CAPTCHA solving not yet implemented (type: {captcha_type})")
        
        # TODO: Implement real CAPTCHA solving
        # Example: use 2captcha API
        # api_key = os.getenv('CAPTCHA_API_KEY')
        # solver = TwoCaptcha(api_key)
        # result = solver.recaptcha(sitekey=site_key, url=url)
        # return result['code']
        
        return None
    
    def log_task_start(self):
        """Логирует начало выполнения задачи."""
        logger.info(
            f"📝 Starting {self.task_name} |  "
            f"Wallet: {self.wallet_id} | "
            f"Params: {self.task_params}"
        )
    
    def log_task_success(self, result_data: Dict):
        """Логирует успешное выполнение задачи."""
        logger.success(
            f"✅ {self.task_name} completed | "
            f"Wallet: {self.wallet_id} | "
            f"Result: {result_data}"
        )
    
    def log_task_error(self, error: Exception):
        """Логирует ошибку выполнения задачи."""
        logger.error(
            f"❌ {self.task_name} failed | "
            f"Wallet: {self.wallet_id} | "
            f"Error: {error}"
        )
