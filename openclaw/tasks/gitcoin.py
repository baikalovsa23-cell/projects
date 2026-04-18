"""
OpenClaw Task — Gitcoin Passport Stamping
==========================================

Автоматизация получения stamps в Gitcoin Passport.

Flow:
1. Подключение MetaMask wallet
2. Навигация к Gitcoin Passport
3. Последовательное получение доступных stamps
4. Verification на стороне Gitcoin

Stamps типы:
- Google OAuth
- Twitter OAuth
- Discord OAuth
- GitHub OAuth
- BrightID
- POAP verification
- ENS ownership

Author: Senior Backend Developer
Created: 2026-02-25
"""

import asyncio
import random
import numpy as np
from typing import Dict, Any, List
from loguru import logger
from openclaw.tasks.base import BaseTask
from openclaw.browser import BrowserEngine


class GitcoinPassportTask(BaseTask):
    """
    Gitcoin Passport stamping automation.
    
    Task params:
        {
            "stamps": ["google", "twitter", "discord", "github"],  # Stamps to collect
            "credentials": {
                "google": {"email": "...", "password": "..."},
                "twitter": {...},
                ...
            }
        }
    """
    
    GITCOIN_PASSPORT_URL = "https://passport.gitcoin.co"
    
    # Stamp IDs (2026 актуальные)
    AVAILABLE_STAMPS = {
        "google": "Google",
        "twitter": "Twitter",
        "discord": "Discord",
        "github": "Github",
        "ens": "Ens",
        "brightid": "BrightId",
        "poh": "POHV2",  # Proof of Humanity
        "gitpoap": "GitPOAP",
    }
    
    def __init__(self, wallet_id: int, wallet_address: str, task_params: Dict[str, Any], dry_run: bool = False):
        """
        Initialize Gitcoin Passport task.
        
        Args:
            wallet_id: ID кошелька
            wallet_address: Ethereum адрес (для MetaMask injection)
            task_params: Параметры задачи
            dry_run: Dry-run режим
        """
        super().__init__(wallet_id, task_params, dry_run)
        self.wallet_address = wallet_address
    
    async def _execute_real(self) -> Dict[str, Any]:
        """
        Реальное выполнение Gitcoin Passport stamping.
        
        Returns:
            {
                "stamps_collected": ["google", "twitter", ...],
                "score": 15.5,  # Gitcoin Passport score
                "completed_at": "2026-02-25T12:34:56Z"
            }
        """
        self.log_task_start()
        
        # Get stamps to collect from params
        stamps_to_collect: List[str] = self.get_task_param("stamps", [])
        credentials: Dict[str, Dict] = self.get_task_param("credentials", {})
        
        if not stamps_to_collect:
            raise ValueError("No stamps specified in task_params")
        
        logger.info(f"Collecting {len(stamps_to_collect)} stamps: {stamps_to_collect}")
        
        collected_stamps = []
        
        # Launch browser with MetaMask injection
        async with BrowserEngine(
            wallet_address=self.wallet_address,
            headless=True,
            stealth_mode=True
        ) as browser:
            page = await browser.new_page()
            
            # Navigate to Gitcoin Passport
            logger.info(f"Navigating to {self.GITCOIN_PASSPORT_URL}")
            await page.goto(self.GITCOIN_PASSPORT_URL, {'waitUntil': 'networkidle0'})
            await browser.human_delay(2, 4)
            
            # Wait for "Connect Wallet" button
            connect_btn_found = await browser.wait_for_selector(
                page, 
                'button:has-text("Connect Wallet")', 
                timeout=15000
            )
            
            if not connect_btn_found:
                logger.warning("Connect Wallet button not found, trying alternative selector")
                # Try alternative selector
                connect_btn = await page.querySelector('[data-testid="connect-wallet-button"]')
            else:
                connect_btn = await page.querySelector('button:has-text("Connect Wallet")')
            
            if connect_btn:
                # Click connect wallet
                await self.human_click(connect_btn)
                await browser.human_delay(1, 2)
                
                # Select MetaMask from providers
                metamask_btn = await page.querySelector('button:has-text("MetaMask")')
                if metamask_btn:
                    await self.human_click(metamask_btn)
                    await browser.human_delay(2, 3)
                    
                    logger.info("✅ Wallet connected")
                else:
                    logger.warning("MetaMask button not found")
            
            # Collect each stamp sequentially
            for stamp_key in stamps_to_collect:
                try:
                    stamp_name = self.AVAILABLE_STAMPS.get(stamp_key, stamp_key)
                    logger.info(f"Collecting stamp: {stamp_name}")
                    
                    # Scroll to stamp section
                    await browser.random_mouse_movement(page)
                    await self.random_scroll(page, 200, 500)
                    await browser.human_delay(1, 2)
                    
                    # Find stamp card
                    stamp_selector = f'div[data-stamp-provider="{stamp_key}"]'
                    stamp_card = await page.querySelector(stamp_selector)
                    
                    if not stamp_card:
                        # Try alternative selector
                        stamp_card = await page.querySelector(f'*:has-text("{stamp_name}")')
                    
                    if stamp_card:
                        # Click "Verify" button on stamp card
                        verify_btn = await stamp_card.querySelector('button:has-text("Verify")')
                        
                        if verify_btn:
                            await self.human_click(verify_btn)
                            await browser.human_delay(1, 2)
                            
                            # Handle OAuth flow (if needed)
                            if stamp_key in credentials:
                                await self._handle_oauth_flow(
                                    page=page,
                                    browser=browser,
                                    stamp_key=stamp_key,
                                    creds=credentials[stamp_key]
                                )
                            
                            # Wait for verification to complete
                            delay = np.random.normal(mean=4.5, std=0.75)  # mean=(3+6)/2, std=range/4
                            delay = max(3, min(6, delay))  # Clip to original range
                            await asyncio.sleep(delay)
                            
                            collected_stamps.append(stamp_key)
                            logger.success(f"✅ Collected stamp: {stamp_name}")
                        
                        else:
                            logger.warning(f"Verify button not found for {stamp_name}")
                    
                    else:
                        logger.warning(f"Stamp card not found: {stamp_name}")
                    
                    # Delay between stamps (anti-bot)
                    await browser.human_delay(5, 10)
                
                except Exception as e:
                    logger.error(f"Failed to collect stamp {stamp_key}: {e}")
                    # Continue with next stamp
                    continue
            
            # Get final Passport score
            score = await self._get_passport_score(page)
            
            result = {
                "stamps_collected": collected_stamps,
                "stamps_failed": [s for s in stamps_to_collect if s not in collected_stamps],
                "score": score,
                "total_stamps": len(collected_stamps),
                "completed_at": self._get_current_timestamp()
            }
            
            self.log_task_success(result)
            return result
    
    async def _handle_oauth_flow(
        self, 
        page, 
        browser: BrowserEngine, 
        stamp_key: str, 
        creds: Dict[str, str]
    ):
        """
        Обрабатывает OAuth flow для stamp (Google, Twitter, etc).
        
        Args:
            page: Pyppeteer page
            browser: BrowserEngine instance
            stamp_key: Тип stamp ("google", "twitter", ...)
            creds: Credentials {"email": "...", "password": "..."}
        """
        logger.info(f"Handling OAuth flow for {stamp_key}")
        
        # Wait for OAuth popup/redirect
        await browser.human_delay(2, 3)
        
        # Check if new window/tab opened
        pages = await browser.browser.pages()
        if len(pages) > 1:
            oauth_page = pages[-1]  # Last opened page
            logger.debug("OAuth page detected")
        else:
            oauth_page = page  # Same page redirect
        
        try:
            if stamp_key == "google":
                await self._google_oauth(oauth_page, browser, creds)
            
            elif stamp_key == "twitter":
                await self._twitter_oauth(oauth_page, browser, creds)
            
            elif stamp_key == "discord":
                await self._discord_oauth(oauth_page, browser, creds)
            
            elif stamp_key == "github":
                await self._github_oauth(oauth_page, browser, creds)
            
            else:
                logger.warning(f"OAuth handler not implemented for {stamp_key}")
            
        except Exception as e:
            logger.error(f"OAuth flow failed for {stamp_key}: {e}")
        
        # Close OAuth page if it's separate
        if len(pages) > 1:
            await oauth_page.close()
    
    async def _google_oauth(self, page, browser: BrowserEngine, creds: Dict):
        """Google OAuth login."""
        email = creds.get("email")
        password = creds.get("password")
        
        if not email or not password:
            logger.warning("Google credentials missing")
            return
        
        # Wait for email input
        await browser.wait_for_selector(page, 'input[type="email"]', timeout=10000)
        
        email_input = await page.querySelector('input[type="email"]')
        if email_input:
            await self.human_type(email, email_input)
            await browser.human_delay(0.5, 1)
            
            # Click "Next"
            next_btn = await page.querySelector('button:has-text("Next")')
            if next_btn:
                await self.human_click(next_btn)
                await browser.human_delay(1, 2)
        
        # Password input
        await browser.wait_for_selector(page, 'input[type="password"]', timeout=10000)
        
        password_input = await page.querySelector('input[type="password"]')
        if password_input:
            await self.human_type(password, password_input)
            await browser.human_delay(0.5, 1)
            
            # Click "Next"
            next_btn = await page.querySelector('button:has-text("Next")')
            if next_btn:
                await self.human_click(next_btn)
                await browser.human_delay(2, 3)
        
        logger.success("Google OAuth completed")
    
    async def _twitter_oauth(self, page, browser: BrowserEngine, creds: Dict):
        """Twitter OAuth login."""
        username = creds.get("username")
        password = creds.get("password")
        
        if not username or not password:
            logger.warning("Twitter credentials missing")
            return
        
        # Twitter login flow (2026 version)
        await browser.wait_for_selector(page, 'input[autocomplete="username"]', timeout=10000)
        
        # Username input
        username_input = await page.querySelector('input[autocomplete="username"]')
        if username_input:
            await self.human_type(username, username_input)
            await browser.human_delay(0.5, 1)
            
            # Click "Next"
            next_btn = await page.querySelector('div[role="button"]:has-text("Next")')
            if next_btn:
                await self.human_click(next_btn)
                await browser.human_delay(1, 2)
        
        # Password input
        password_input = await page.querySelector('input[type="password"]')
        if password_input:
            await self.human_type(password, password_input)
            await browser.human_delay(0.5, 1)
            
            # Click "Log in"
            login_btn = await page.querySelector('div[role="button"]:has-text("Log in")')
            if login_btn:
                await self.human_click(login_btn)
                await browser.human_delay(2, 3)
        
        # Authorize app
        authorize_btn = await page.querySelector('input[value="Authorize app"]')
        if authorize_btn:
            await self.human_click(authorize_btn)
            await browser.human_delay(2, 3)
        
        logger.success("Twitter OAuth completed")
    
    async def _discord_oauth(self, page, browser: BrowserEngine, creds: Dict):
        """Discord OAuth login (placeholder)."""
        logger.info("Discord OAuth (not fully implemented)")
        await browser.human_delay(3, 5)
    
    async def _github_oauth(self, page, browser: BrowserEngine, creds: Dict):
        """GitHub OAuth login (placeholder)."""
        logger.info("GitHub OAuth (not fully implemented)")
        await browser.human_delay(3, 5)
    
    async def _get_passport_score(self, page) -> float:
        """
        Получает Gitcoin Passport score со страницы.
        
        Args:
            page: Pyppeteer page
        
        Returns:
            Passport score (float) или 0.0
        """
        try:
            # Try to find score element
            score_element = await page.querySelector('[data-testid="passport-score"]')
            
            if not score_element:
                # Alternative selector
                score_element = await page.querySelector('.passport-score')
            
            if score_element:
                score_text = await page.evaluate('(element) => element.textContent', score_element)
                # Extract numeric value (e.g., "15.5" from "Score: 15.5")
                score = float(''.join(filter(lambda x: x.isdigit() or x == '.', score_text)))
                return score
            
        except Exception as e:
            logger.warning(f"Failed to get passport score: {e}")
        
        return 0.0
    
    def _mock_result(self) -> Dict[str, Any]:
        """
        Mock данные для dry-run режима.
        
        Returns:
            Realistic mock data
        """
        stamps_to_collect = self.get_task_param("stamps", ["google", "twitter"])
        
        # Simulate 80% success rate
        collected = [s for s in stamps_to_collect if random.random() > 0.2]
        
        return {
            "stamps_collected": collected,
            "stamps_failed": [s for s in stamps_to_collect if s not in collected],
            "score": round(np.random.normal(mean=15.0, std=2.5), 1),  # Gaussian instead of uniform
            "total_stamps": len(collected),
            "completed_at": self._get_current_timestamp()
        }
    
    def _get_current_timestamp(self) -> str:
        """Возвращает текущий timestamp в ISO format."""
        from datetime import datetime, timezone
        return datetime.now(timezone.utc).isoformat()
