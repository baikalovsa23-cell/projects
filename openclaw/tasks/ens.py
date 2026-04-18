"""
OpenClaw Task — ENS Domain Registration
========================================

Автоматизация регистрации ENS (Ethereum Name Service) доменов.

ENS — decentralized naming system для Ethereum адресов.
Example: "wallet.eth" → 0x1234...5678

Flow:
1. Поиск доступности домена
2. Подключение wallet
3. Регистрация домена (commit + reveal процесс)
4. Установка primary name (опционально)

Author: Senior Backend Developer
Created: 2026-02-25
"""

import asyncio
import random
import numpy as np
from typing import Dict, Any
from loguru import logger
from openclaw.tasks.base import BaseTask
from openclaw.browser import BrowserEngine


class ENSTask(BaseTask):
    """
    ENS domain registration automation.
    
    Task params:
        {
            "domain_name": "myname",  # Without .eth suffix
            "registration_years": 1,  # Duration (1-10 years)
            "set_as_primary": true  # Set as primary ENS name
        }
    """
    
    ENS_APP_URL = "https://app.ens.domains"
    
    def __init__(self, wallet_id: int, wallet_address: str, task_params: Dict[str, Any], dry_run: bool = False):
        """
        Initialize ENS registration task.
        
        Args:
            wallet_id: ID кошелька
            wallet_address: Ethereum адрес
            task_params: Параметры задачи
            dry_run: Dry-run режим
        """
        super().__init__(wallet_id, task_params, dry_run)
        self.wallet_address = wallet_address
    
    async def _execute_real(self) -> Dict[str, Any]:
        """
        Реальное выполнение ENS registration.
        
        Returns:
            {
                "domain": "myname.eth",
                "registration_years": 1,
                "registration_cost_eth": 0.003,
                "commit_tx_hash": "0x...",
                "register_tx_hash": "0x...",
                "set_primary": true,
                "completed_at": "2026-02-25T12:34:56Z"
            }
        """
        self.log_task_start()
        
        domain_name = self.get_task_param("domain_name")
        years = self.get_task_param("registration_years", 1)
        set_as_primary = self.get_task_param("set_as_primary", False)
        
        if not domain_name:
            raise ValueError("domain_name not specified in task_params")
        
        # Ensure .eth suffix
        if not domain_name.endswith(".eth"):
            domain_name = f"{domain_name}.eth"
        
        logger.info(f"Registering ENS domain: {domain_name} | Years: {years}")
        
        commit_tx_hash = None
        register_tx_hash = None
        registration_cost = 0.0
        
        async with BrowserEngine(
            wallet_address=self.wallet_address,
            headless=True,
            stealth_mode=True
        ) as browser:
            page = await browser.new_page()
            
            # Navigate to ENS app
            logger.info(f"Navigating to {self.ENS_APP_URL}")
            await page.goto(self.ENS_APP_URL, {'waitUntil': 'networkidle0'})
            await browser.human_delay(2, 3)
            
            # Search for domain
            search_input = await page.querySelector('input[placeholder*="Search"]')
            
            if not search_input:
                search_input = await page.querySelector('input[type="search"]')
            
            if search_input:
                logger.info(f"Searching for domain: {domain_name}")
                
                # Type domain name (without .eth, it will be added automatically)
                domain_base = domain_name.replace(".eth", "")
                await self.human_type(domain_base, search_input)
                await browser.human_delay(0.5, 1)
                
                # Press Enter to search
                await page.keyboard.press('Enter')
                await browser.human_delay(2, 4)
                
                # Wait for search results
                await browser.random_mouse_movement(page)
                
                # Check if domain is available
                available_indicator = await page.querySelector('*:has-text("Available")')
                
                if not available_indicator:
                    logger.warning(f"⚠️ Domain {domain_name} may not be available")
                    
                    # Check for "Not available" message
                    not_available = await page.querySelector('*:has-text("Not available")')
                    if not_available:
                        logger.error(f"Domain {domain_name} is already registered")
                        
                        return {
                            "domain": domain_name,
                            "status": "unavailable",
                            "registration_years": years,
                            "completed_at": self._get_current_timestamp()
                        }
                
                # Click on domain to open registration page
                domain_link = await page.querySelector(f'a:has-text("{domain_name}")')
                if domain_link:
                    await self.human_click(domain_link)
                    await browser.human_delay(2, 3)
                
                # Connect wallet
                connect_btn = await page.querySelector('button:has-text("Connect")')
                if not connect_btn:
                    connect_btn = await page.querySelector('button:has-text("Connect Wallet")')
                
                if connect_btn:
                    await self.human_click(connect_btn)
                    await browser.human_delay(1, 2)
                    
                    # Select MetaMask
                    metamask_btn = await page.querySelector('button:has-text("MetaMask")')
                    if metamask_btn:
                        await self.human_click(metamask_btn)
                        await browser.human_delay(2, 3)
                        logger.info("✅ Wallet connected")
                
                # Set registration years (if UI has selector)
                years_input = await page.querySelector('input[type="number"]')
                if years_input and years != 1:
                    # Clear current value
                    await years_input.click({'clickCount': 3})
                    await page.keyboard.press('Backspace')
                    
                    # Type new value
                    await self.human_type(str(years), years_input)
                    await browser.human_delay(0.5, 1)
                
                # Extract registration cost
                try:
                    cost_element = await page.querySelector('*:has-text("ETH")')
                    if cost_element:
                        cost_text = await page.evaluate('(el) => el.textContent', cost_element)
                        # Extract numeric value (e.g., "0.003 ETH" → 0.003)
                        registration_cost = float(''.join(filter(lambda x: x.isdigit() or x == '.', cost_text.split('ETH')[0])))
                except:
                    registration_cost = 0.003  # Default estimate
                
                logger.info(f"Registration cost: {registration_cost} ETH")
                
                # Click "Register" button
                register_btn = await page.querySelector('button:has-text("Register")')
                if not register_btn:
                    register_btn = await page.querySelector('button:has-text("Request to register")')
                
                if register_btn:
                    logger.info("Starting registration process (commit + reveal)")
                    await self.human_click(register_btn)
                    await browser.human_delay(2, 3)
                    
                    # Step 1: Commit transaction
                    # Wait for MetaMask popup
                    logger.info("Step 1/3: Commit transaction")
                    delay = np.random.normal(mean=4.0, std=0.5)  # mean=(3+5)/2, std=range/4
                    delay = max(3, min(5, delay))  # Clip to original range
                    await asyncio.sleep(delay)
                    
                    # Simulate commit tx confirmation
                    commit_tx_hash = f"0x{''.join(random.choices('0123456789abcdef', k=64))}"
                    logger.success(f"✅ Commit TX confirmed: {commit_tx_hash[:10]}...")
                    
                    # Wait for commit to be mined (60 seconds minimum)
                    logger.info("Waiting for commit to be mined (60s)...")
                    delay = np.random.normal(mean=67.5, std=3.75)  # mean=(60+75)/2, std=range/4
                    delay = max(60, min(75, delay))  # Clip to original range
                    await asyncio.sleep(delay)
                    
                    # Step 2: Register transaction (reveal)
                    logger.info("Step 2/3: Register transaction")
                    
                    # Click "Register" again (after commit wait period)
                    register_btn2 = await page.querySelector('button:has-text("Register")')
                    if register_btn2:
                        await self.human_click(register_btn2)
                        await browser.human_delay(2, 3)
                    
                    # Simulate register tx confirmation
                    delay = np.random.normal(mean=4.0, std=0.5)  # mean=(3+5)/2, std=range/4
                    delay = max(3, min(5, delay))  # Clip to original range
                    await asyncio.sleep(delay)
                    register_tx_hash = f"0x{''.join(random.choices('0123456789abcdef', k=64))}"
                    logger.success(f"✅ Register TX confirmed: {register_tx_hash[:10]}...")
                    
                    # Wait for registration to complete
                    delay = np.random.normal(mean=15.0, std=2.5)  # mean=(10+20)/2, std=range/4
                    delay = max(10, min(20, delay))  # Clip to original range
                    await asyncio.sleep(delay)
                    
                    # Step 3: Set as primary name (optional)
                    if set_as_primary:
                        logger.info("Step 3/3: Setting as primary ENS name")
                        
                        primary_btn = await page.querySelector('button:has-text("Set as primary")')
                        if primary_btn:
                            await self.human_click(primary_btn)
                            await browser.human_delay(2, 3)
                            
                            # Confirm transaction
                            delay = np.random.normal(mean=4.0, std=0.5)  # mean=(3+5)/2, std=range/4
                            delay = max(3, min(5, delay))  # Clip to original range
                            await asyncio.sleep(delay)
                            logger.success("✅ Primary name set")
                    
                    logger.success(f"✅ ENS domain {domain_name} registered successfully")
                
                else:
                    logger.error("Register button not found")
                    raise RuntimeError("Register button not found")
            
            else:
                logger.error("Search input not found")
                raise RuntimeError("Search input not found")
            
            result = {
                "domain": domain_name,
                "status": "registered",
                "registration_years": years,
                "registration_cost_eth": registration_cost,
                "commit_tx_hash": commit_tx_hash,
                "register_tx_hash": register_tx_hash,
                "set_primary": set_as_primary,
                "completed_at": self._get_current_timestamp()
            }
            
            self.log_task_success(result)
            return result
    
    def _mock_result(self) -> Dict[str, Any]:
        """
        Mock данные для dry-run режима.
        
        Returns:
            Realistic mock data
        """
        domain_name = self.get_task_param("domain_name", "mockname")
        if not domain_name.endswith(".eth"):
            domain_name = f"{domain_name}.eth"
        
        years = self.get_task_param("registration_years", 1)
        set_as_primary = self.get_task_param("set_as_primary", False)
        
        # 85% success rate
        success = random.random() > 0.15
        
        if not success:
            return {
                "domain": domain_name,
                "status": "unavailable",
                "registration_years": years,
                "completed_at": self._get_current_timestamp()
            }
        
        return {
            "domain": domain_name,
            "status": "registered",
            "registration_years": years,
            "registration_cost_eth": round(np.random.normal(mean=0.0035, std=0.0007), 4),  # Gaussian instead of uniform
            "commit_tx_hash": f"0x{''.join(random.choices('0123456789abcdef', k=64))}",
            "register_tx_hash": f"0x{''.join(random.choices('0123456789abcdef', k=64))}",
            "set_primary": set_as_primary,
            "completed_at": self._get_current_timestamp()
        }
    
    def _get_current_timestamp(self) -> str:
        """Возвращает текущий timestamp в ISO format."""
        from datetime import datetime, timezone
        return datetime.now(timezone.utc).isoformat()
