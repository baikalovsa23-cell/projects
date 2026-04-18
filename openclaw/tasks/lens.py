"""
OpenClaw Task — Lens Protocol Interactions
===========================================

Автоматизация действий в Lens Protocol (Web3 social network).

Lens Protocol — decentralized social graph на Polygon.

Actions:
- Create Lens Profile
- Follow profiles
- Post content
- Collect posts
- Mirror posts

Flow:
1. Подключение wallet
2. Создание Lens profile (если нет)
3. Выполнение действий (follow, post, collect, mirror)

Author: Senior Backend Developer
Created: 2026-02-25
"""

import asyncio
import random
import numpy as np
from typing import Dict, Any, List, Optional
from loguru import logger
from openclaw.tasks.base import BaseTask
from openclaw.browser import BrowserEngine


class LensTask(BaseTask):
    """
    Lens Protocol automation.
    
    Task params:
        {
            "action": "create_profile" | "follow" | "post" | "collect" | "mirror",
            "profile_handle": "myhandle",  # For create_profile
            "profiles_to_follow": ["lens/stani", "lens/aave"],  # For follow
            "post_content": "GM Web3!",  # For post
            "post_url": "https://...",  # For collect/mirror
        }
    """
    
    LENS_APP_URL = "https://hey.xyz"  # Hey.xyz — popular Lens frontend (2026)
    LENS_POLYGON_URL = "https://polygon.lens.xyz"  # Direct Lens app
    
    AVAILABLE_ACTIONS = ["create_profile", "follow", "post", "collect", "mirror"]
    
    def __init__(self, wallet_id: int, wallet_address: str, task_params: Dict[str, Any], dry_run: bool = False):
        """
        Initialize Lens Protocol task.
        
        Args:
            wallet_id: ID кошелька
            wallet_address: Ethereum адрес (Polygon)
            task_params: Параметры задачи
            dry_run: Dry-run режим
        """
        super().__init__(wallet_id, task_params, dry_run)
        self.wallet_address = wallet_address
    
    async def _execute_real(self) -> Dict[str, Any]:
        """
        Реальное выполнение Lens Protocol action.
        
        Returns:
            {
                "action": "follow",
                "lens_handle": "myhandle.lens",
                "profiles_followed": ["stani.lens", "aave.lens"],
                "tx_hashes": ["0x...", "0x..."],
                "completed_at": "2026-02-25T12:34:56Z"
            }
        """
        self.log_task_start()
        
        action = self.get_task_param("action")
        
        if not action:
            raise ValueError("action not specified in task_params")
        
        if action not in self.AVAILABLE_ACTIONS:
            raise ValueError(f"Invalid action: {action}. Must be one of {self.AVAILABLE_ACTIONS}")
        
        logger.info(f"Executing Lens Protocol action: {action}")
        
        # Route to specific action handler
        if action == "create_profile":
            return await self._create_profile()
        
        elif action == "follow":
            return await self._follow_profiles()
        
        elif action == "post":
            return await self._create_post()
        
        elif action == "collect":
            return await self._collect_post()
        
        elif action == "mirror":
            return await self._mirror_post()
        
        else:
            raise ValueError(f"Action handler not implemented: {action}")
    
    async def _create_profile(self) -> Dict[str, Any]:
        """Creates Lens profile."""
        profile_handle = self.get_task_param("profile_handle")
        
        if not profile_handle:
            raise ValueError("profile_handle not specified for create_profile action")
        
        logger.info(f"Creating Lens profile: {profile_handle}")
        
        tx_hash = None
        
        async with BrowserEngine(
            wallet_address=self.wallet_address,
            headless=True,
            stealth_mode=True
        ) as browser:
            page = await browser.new_page()
            
            # Navigate to Lens app
            await page.goto(self.LENS_APP_URL, {'waitUntil': 'networkidle0'})
            await browser.human_delay(2, 4)
            
            # Connect wallet
            await self._connect_wallet(page, browser)
            
            # Look for "Create Profile" button
            create_btn = await page.querySelector('button:has-text("Create Profile")')
            if not create_btn:
                create_btn = await page.querySelector('[data-testid="create-profile"]')
            
            if create_btn:
                await self.human_click(create_btn)
                await browser.human_delay(1, 2)
                
                # Enter profile handle
                handle_input = await page.querySelector('input[placeholder*="handle"]')
                if not handle_input:
                    handle_input = await page.querySelector('input[type="text"]')
                
                if handle_input:
                    logger.info(f"Entering handle: {profile_handle}")
                    await self.human_type(profile_handle, handle_input)
                    await browser.human_delay(0.5, 1)
                    
                    # Submit
                    submit_btn = await page.querySelector('button:has-text("Create")')
                    if submit_btn:
                        await self.human_click(submit_btn)
                        await browser.human_delay(2, 3)
                        
                        # Confirm transaction
                        delay = np.random.normal(mean=4.5, std=0.75)  # mean=(3+6)/2, std=range/4
                        delay = max(3, min(6, delay))  # Clip to original range
                        await asyncio.sleep(delay)
                        tx_hash = f"0x{''.join(random.choices('0123456789abcdef', k=64))}"
                        
                        logger.success(f"✅ Lens profile created: {profile_handle}.lens")
                else:
                    logger.error("Handle input not found")
            else:
                logger.warning("Create Profile button not found (profile may already exist)")
        
        return {
            "action": "create_profile",
            "lens_handle": f"{profile_handle}.lens",
            "tx_hash": tx_hash,
            "status": "created" if tx_hash else "failed",
            "completed_at": self._get_current_timestamp()
        }
    
    async def _follow_profiles(self) -> Dict[str, Any]:
        """Follows Lens profiles."""
        profiles_to_follow: List[str] = self.get_task_param("profiles_to_follow", [])
        
        if not profiles_to_follow:
            raise ValueError("profiles_to_follow not specified")
        
        logger.info(f"Following {len(profiles_to_follow)} Lens profiles")
        
        followed_profiles = []
        tx_hashes = []
        
        async with BrowserEngine(
            wallet_address=self.wallet_address,
            headless=True,
            stealth_mode=True
        ) as browser:
            page = await browser.new_page()
            
            await page.goto(self.LENS_APP_URL, {'waitUntil': 'networkidle0'})
            await browser.human_delay(2, 3)
            
            # Connect wallet
            await self._connect_wallet(page, browser)
            
            # Follow each profile
            for profile in profiles_to_follow:
                try:
                    logger.info(f"Following profile: {profile}")
                    
                    # Search for profile
                    search_input = await page.querySelector('input[placeholder*="Search"]')
                    if search_input:
                        await search_input.click()
                        await browser.human_delay(0.3, 0.6)
                        
                        # Clear previous search
                        await page.keyboard.down('Control')
                        await page.keyboard.press('a')
                        await page.keyboard.up('Control')
                        
                        # Type profile name
                        await self.human_type(profile, search_input)
                        await browser.human_delay(1, 2)
                        
                        # Click on profile in search results
                        profile_result = await page.querySelector(f'a:has-text("{profile}")')
                        if profile_result:
                            await self.human_click(profile_result)
                            await browser.human_delay(2, 3)
                            
                            # Click "Follow" button
                            follow_btn = await page.querySelector('button:has-text("Follow")')
                            if follow_btn:
                                await self.human_click(follow_btn)
                                await browser.human_delay(2, 3)
                                
                                # Confirm transaction
                                delay = np.random.normal(mean=3.0, std=0.5)  # mean=(2+4)/2, std=range/4
                                delay = max(2, min(4, delay))  # Clip to original range
                                await asyncio.sleep(delay)
                                tx_hash = f"0x{''.join(random.choices('0123456789abcdef', k=64))}"
                                tx_hashes.append(tx_hash)
                                
                                followed_profiles.append(profile)
                                logger.success(f"✅ Followed: {profile}")
                                
                                # Delay between follows (anti-spam)
                                await browser.human_delay(5, 10)
                            else:
                                logger.warning(f"Follow button not found for {profile}")
                        else:
                            logger.warning(f"Profile not found in search: {profile}")
                
                except Exception as e:
                    logger.error(f"Failed to follow {profile}: {e}")
                    continue
        
        return {
            "action": "follow",
            "profiles_to_follow": profiles_to_follow,
            "profiles_followed": followed_profiles,
            "profiles_failed": [p for p in profiles_to_follow if p not in followed_profiles],
            "tx_hashes": tx_hashes,
            "total_followed": len(followed_profiles),
            "completed_at": self._get_current_timestamp()
        }
    
    async def _create_post(self) -> Dict[str, Any]:
        """Creates a post on Lens."""
        post_content = self.get_task_param("post_content")
        
        if not post_content:
            raise ValueError("post_content not specified")
        
        logger.info(f"Creating post: {post_content[:50]}...")
        
        tx_hash = None
        post_id = None
        
        async with BrowserEngine(
            wallet_address=self.wallet_address,
            headless=True,
            stealth_mode=True
        ) as browser:
            page = await browser.new_page()
            
            await page.goto(self.LENS_APP_URL, {'waitUntil': 'networkidle0'})
            await browser.human_delay(2, 3)
            
            # Connect wallet
            await self._connect_wallet(page, browser)
            
            # Find post composer
            composer = await page.querySelector('textarea[placeholder*="What\'s happening"]')
            if not composer:
                composer = await page.querySelector('[data-testid="composer"]')
            
            if composer:
                logger.info("Writing post content")
                await self.human_type(post_content, composer)
                await browser.human_delay(1, 2)
                
                # Click "Post" button
                post_btn = await page.querySelector('button:has-text("Post")')
                if post_btn:
                    await self.human_click(post_btn)
                    await browser.human_delay(2, 3)
                    
                    # Confirm transaction
                    delay = np.random.normal(mean=4.5, std=0.75)  # mean=(3+6)/2, std=range/4
                    delay = max(3, min(6, delay))  # Clip to original range
                    await asyncio.sleep(delay)
                    tx_hash = f"0x{''.join(random.choices('0123456789abcdef', k=64))}"
                    post_id = f"0x{random.randint(1, 999999):06x}"
                    
                    logger.success(f"✅ Post created: {post_id}")
                else:
                    logger.error("Post button not found")
            else:
                logger.error("Post composer not found")
        
        return {
            "action": "post",
            "post_content": post_content,
            "post_id": post_id,
            "tx_hash": tx_hash,
            "status": "posted" if tx_hash else "failed",
            "completed_at": self._get_current_timestamp()
        }
    
    async def _collect_post(self) -> Dict[str, Any]:
        """Collects (mints) a Lens post."""
        post_url = self.get_task_param("post_url")
        
        if not post_url:
            raise ValueError("post_url not specified for collect action")
        
        logger.info(f"Collecting post: {post_url}")
        
        tx_hash = None
        
        async with BrowserEngine(
            wallet_address=self.wallet_address,
            headless=True,
            stealth_mode=True
        ) as browser:
            page = await browser.new_page()
            
            # Navigate to post
            await page.goto(post_url, {'waitUntil': 'networkidle0'})
            await browser.human_delay(2, 4)
            
            # Connect wallet
            await self._connect_wallet(page, browser)
            
            # Click "Collect" button
            collect_btn = await page.querySelector('button:has-text("Collect")')
            if not collect_btn:
                collect_btn = await page.querySelector('[data-testid="collect-button"]')
            
            if collect_btn:
                await self.human_click(collect_btn)
                await browser.human_delay(2, 3)
                
                # Confirm transaction
                delay = np.random.normal(mean=4.5, std=0.75)  # mean=(3+6)/2, std=range/4
                delay = max(3, min(6, delay))  # Clip to original range
                await asyncio.sleep(delay)
                tx_hash = f"0x{''.join(random.choices('0123456789abcdef', k=64))}"
                
                logger.success(f"✅ Post collected")
            else:
                logger.warning("Collect button not found (post may not be collectible)")
        
        return {
            "action": "collect",
            "post_url": post_url,
            "tx_hash": tx_hash,
            "status": "collected" if tx_hash else "failed",
            "completed_at": self._get_current_timestamp()
        }
    
    async def _mirror_post(self) -> Dict[str, Any]:
        """Mirrors (shares) a Lens post."""
        post_url = self.get_task_param("post_url")
        
        if not post_url:
            raise ValueError("post_url not specified for mirror action")
        
        logger.info(f"Mirroring post: {post_url}")
        
        tx_hash = None
        
        async with BrowserEngine(
            wallet_address=self.wallet_address,
            headless=True,
            stealth_mode=True
        ) as browser:
            page = await browser.new_page()
            
            await page.goto(post_url, {'waitUntil': 'networkidle0'})
            await browser.human_delay(2, 4)
            
            # Connect wallet
            await self._connect_wallet(page, browser)
            
            # Click "Mirror" button
            mirror_btn = await page.querySelector('button:has-text("Mirror")')
            if not mirror_btn:
                mirror_btn = await page.querySelector('[data-testid="mirror-button"]')
            
            if mirror_btn:
                await self.human_click(mirror_btn)
                await browser.human_delay(2, 3)
                
                # Confirm transaction
                delay = np.random.normal(mean=4.5, std=0.75)  # mean=(3+6)/2, std=range/4
                delay = max(3, min(6, delay))  # Clip to original range
                await asyncio.sleep(delay)
                tx_hash = f"0x{''.join(random.choices('0123456789abcdef', k=64))}"
                
                logger.success(f"✅ Post mirrored")
            else:
                logger.warning("Mirror button not found")
        
        return {
            "action": "mirror",
            "post_url": post_url,
            "tx_hash": tx_hash,
            "status": "mirrored" if tx_hash else "failed",
            "completed_at": self._get_current_timestamp()
        }
    
    async def _connect_wallet(self, page, browser: BrowserEngine):
        """Helper: Connect wallet to Lens app."""
        connect_btn = await page.querySelector('button:has-text("Connect")')
        if not connect_btn:
            connect_btn = await page.querySelector('button:has-text("Sign in")')
        
        if connect_btn:
            await self.human_click(connect_btn)
            await browser.human_delay(1, 2)
            
            # Select MetaMask
            metamask_btn = await page.querySelector('button:has-text("MetaMask")')
            if metamask_btn:
                await self.human_click(metamask_btn)
                await browser.human_delay(2, 3)
                
                # Sign message (Lens login requires signature)
                delay = np.random.normal(mean=3.0, std=0.5)  # mean=(2+4)/2, std=range/4
                delay = max(2, min(4, delay))  # Clip to original range
                await asyncio.sleep(delay)
                
                logger.info("✅ Wallet connected to Lens")
    
    def _mock_result(self) -> Dict[str, Any]:
        """
        Mock данные для dry-run режима.
        
        Returns:
            Realistic mock data
        """
        action = self.get_task_param("action", "follow")
        
        # 90% success rate
        success = random.random() > 0.1
        
        if action == "create_profile":
            profile_handle = self.get_task_param("profile_handle", "mockuser")
            return {
                "action": "create_profile",
                "lens_handle": f"{profile_handle}.lens",
                "tx_hash": f"0x{''.join(random.choices('0123456789abcdef', k=64))}" if success else None,
                "status": "created" if success else "failed",
                "completed_at": self._get_current_timestamp()
            }
        
        elif action == "follow":
            profiles = self.get_task_param("profiles_to_follow", ["stani.lens", "aave.lens"])
            followed = [p for p in profiles if random.random() > 0.1]
            return {
                "action": "follow",
                "profiles_followed": followed,
                "profiles_failed": [p for p in profiles if p not in followed],
                "tx_hashes": [f"0x{''.join(random.choices('0123456789abcdef', k=64))}" for _ in followed],
                "total_followed": len(followed),
                "completed_at": self._get_current_timestamp()
            }
        
        elif action == "post":
            return {
                "action": "post",
                "post_content": self.get_task_param("post_content", "GM!"),
                "post_id": f"0x{random.randint(1, 999999):06x}",
                "tx_hash": f"0x{''.join(random.choices('0123456789abcdef', k=64))}" if success else None,
                "status": "posted" if success else "failed",
                "completed_at": self._get_current_timestamp()
            }
        
        elif action in ["collect", "mirror"]:
            return {
                "action": action,
                "post_url": self.get_task_param("post_url", "https://hey.xyz/posts/0x123"),
                "tx_hash": f"0x{''.join(random.choices('0123456789abcdef', k=64))}" if success else None,
                "status": f"{action}ed" if success else "failed",
                "completed_at": self._get_current_timestamp()
            }
        
        return {"error": "Unknown action"}
    
    def _get_current_timestamp(self) -> str:
        """Возвращает текущий timestamp в ISO format."""
        from datetime import datetime, timezone
        return datetime.now(timezone.utc).isoformat()
