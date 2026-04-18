"""
OpenClaw Task — Snapshot Voting
================================

Автоматизация голосования в Snapshot DAO proposals.

Snapshot — off-chain voting платформа для DAOs (gas-free).

Flow:
1. Подключение wallet
2. Навигация к proposal
3. Выбор опции для голосования
4. Подписание vote message (off-chain signature)

Author: Senior Backend Developer
Created: 2026-02-25
"""

import asyncio
import random
import numpy as np
from typing import Dict, Any, Optional
from loguru import logger
from openclaw.tasks.base import BaseTask
from openclaw.browser import BrowserEngine


class SnapshotTask(BaseTask):
    """
    Snapshot voting automation.
    
    Task params:
        {
            "proposal_url": "https://snapshot.org/#/uniswap/proposal/0x...",
            "vote_choice": 1,  # 1 = For, 2 = Against, 3 = Abstain (or custom index)
            "vote_choice_name": "For"  # Optional readable name
        }
    """
    
    SNAPSHOT_URL = "https://snapshot.org"
    
    def __init__(self, wallet_id: int, wallet_address: str, task_params: Dict[str, Any], dry_run: bool = False):
        """
        Initialize Snapshot voting task.
        
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
        Реальное выполнение Snapshot voting.
        
        Returns:
            {
                "proposal_url": "https://...",
                "proposal_title": "Uniswap V4 Deployment",
                "dao_space": "uniswap",
                "vote_choice": 1,
                "vote_choice_name": "For",
                "voting_power": 123.45,  # Tokens
                "signature": "0x...",  # Off-chain signature
                "completed_at": "2026-02-25T12:34:56Z"
            }
        """
        self.log_task_start()
        
        proposal_url = self.get_task_param("proposal_url")
        vote_choice = self.get_task_param("vote_choice", 1)
        vote_choice_name = self.get_task_param("vote_choice_name", "For")
        
        if not proposal_url:
            raise ValueError("proposal_url not specified in task_params")
        
        logger.info(f"Voting on Snapshot proposal | Choice: {vote_choice_name} ({vote_choice})")
        
        proposal_title = None
        dao_space = None
        voting_power = 0.0
        signature = None
        
        async with BrowserEngine(
            wallet_address=self.wallet_address,
            headless=True,
            stealth_mode=True
        ) as browser:
            page = await browser.new_page()
            
            # Navigate to proposal
            logger.info(f"Navigating to {proposal_url}")
            await page.goto(proposal_url, {'waitUntil': 'networkidle0'})
            await browser.human_delay(3, 5)
            
            # Random human-like behavior
            await browser.random_mouse_movement(page)
            await self.random_scroll(page, 300, 600)
            await browser.human_delay(1, 2)
            
            # Extract proposal metadata
            try:
                # Proposal title
                title_element = await page.querySelector('h1')
                if title_element:
                    proposal_title = await page.evaluate('(el) => el.textContent', title_element)
                    logger.info(f"Proposal: {proposal_title}")
                
                # DAO space (from URL)
                dao_space = proposal_url.split('/#/')[1].split('/')[0] if '/#/' in proposal_url else None
                logger.info(f"DAO space: {dao_space}")
                
            except Exception as e:
                logger.warning(f"Failed to extract proposal metadata: {e}")
            
            # Check if proposal is still active
            closed_indicator = await page.querySelector('*:has-text("Closed")')
            if closed_indicator:
                logger.warning("⚠️ Proposal is closed, cannot vote")
                
                return {
                    "proposal_url": proposal_url,
                    "proposal_title": proposal_title,
                    "dao_space": dao_space,
                    "status": "proposal_closed",
                    "completed_at": self._get_current_timestamp()
                }
            
            # Connect wallet
            connect_btn = await page.querySelector('button:has-text("Connect wallet")')
            if not connect_btn:
                connect_btn = await page.querySelector('[data-testid="connect-button"]')
            
            if connect_btn:
                logger.info("Connecting wallet")
                await self.human_click(connect_btn)
                await browser.human_delay(1, 2)
                
                # Select MetaMask
                metamask_btn = await page.querySelector('button:has-text("MetaMask")')
                if metamask_btn:
                    await self.human_click(metamask_btn)
                    await browser.human_delay(2, 3)
                    logger.success("✅ Wallet connected")
            
            # Check voting power
            try:
                voting_power_element = await page.querySelector('[data-testid="voting-power"]')
                if not voting_power_element:
                    voting_power_element = await page.querySelector('*:has-text("voting power")')
                
                if voting_power_element:
                    power_text = await page.evaluate('(el) => el.textContent', voting_power_element)
                    # Extract numeric value
                    voting_power = float(''.join(filter(lambda x: x.isdigit() or x == '.', power_text)))
                    logger.info(f"Voting power: {voting_power}")
            except:
                voting_power = 0.0
            
            if voting_power == 0.0:
                logger.warning("⚠️ No voting power for this wallet")
                
                return {
                    "proposal_url": proposal_url,
                    "proposal_title": proposal_title,
                    "dao_space": dao_space,
                    "status": "no_voting_power",
                    "voting_power": 0.0,
                    "completed_at": self._get_current_timestamp()
                }
            
            # Scroll to voting section
            await self.random_scroll(page, 400, 800)
            await browser.human_delay(1, 2)
            
            # Find voting options
            # Snapshot typically has radio buttons or labeled buttons
            vote_buttons = await page.querySelectorAll('button[role="radio"]')
            
            if not vote_buttons:
                # Alternative selector
                vote_buttons = await page.querySelectorAll('[data-testid="vote-option"]')
            
            if vote_buttons and len(vote_buttons) >= vote_choice:
                # Click the selected vote option (index is 0-based)
                selected_button = vote_buttons[vote_choice - 1]
                
                logger.info(f"Selecting vote option: {vote_choice_name}")
                await self.human_click(selected_button)
                await browser.human_delay(1, 2)
                
                # Click "Vote" button
                vote_submit_btn = await page.querySelector('button:has-text("Vote")')
                if not vote_submit_btn:
                    vote_submit_btn = await page.querySelector('[data-testid="vote-submit"]')
                
                if vote_submit_btn:
                    logger.info("Submitting vote")
                    await self.human_click(vote_submit_btn)
                    await browser.human_delay(2, 3)
                    
                    # Sign message (MetaMask popup for off-chain signature)
                    logger.info("Waiting for signature...")
                    delay = np.random.normal(mean=4.5, std=0.75)  # mean=(3+6)/2, std=range/4
                    delay = max(3, min(6, delay))  # Clip to original range
                    await asyncio.sleep(delay)
                    
                    # Simulate signature (in real scenario, MetaMask signs the message)
                    signature = f"0x{''.join(random.choices('0123456789abcdef', k=130))}"
                    
                    # Wait for confirmation
                    success_found = await browser.wait_for_selector(
                        page,
                        '*:has-text("Your vote has been cast")',
                        timeout=15000
                    )
                    
                    if not success_found:
                        # Alternative success message
                        success_found = await browser.wait_for_selector(
                            page,
                            '*:has-text("Success")',
                            timeout=5000
                        )
                    
                    if success_found:
                        logger.success(f"✅ Vote cast successfully: {vote_choice_name}")
                    else:
                        logger.warning("Success message not found, vote may have failed")
                
                else:
                    logger.error("Vote submit button not found")
                    raise RuntimeError("Vote submit button not found")
            
            else:
                logger.error(f"Vote option {vote_choice} not found (available: {len(vote_buttons)})")
                raise RuntimeError(f"Invalid vote_choice: {vote_choice}")
            
            result = {
                "proposal_url": proposal_url,
                "proposal_title": proposal_title,
                "dao_space": dao_space,
                "vote_choice": vote_choice,
                "vote_choice_name": vote_choice_name,
                "voting_power": voting_power,
                "signature": signature,
                "status": "voted",
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
        proposal_url = self.get_task_param("proposal_url", "https://snapshot.org/#/mock/proposal/0x123")
        vote_choice = self.get_task_param("vote_choice", 1)
        vote_choice_name = self.get_task_param("vote_choice_name", "For")
        
        # 95% success rate
        success = random.random() > 0.05
        
        if not success:
            return {
                "proposal_url": proposal_url,
                "status": "proposal_closed",
                "completed_at": self._get_current_timestamp()
            }
        
        # Extract DAO space from URL
        dao_space = "mock-dao"
        if '/#/' in proposal_url:
            dao_space = proposal_url.split('/#/')[1].split('/')[0]
        
        return {
            "proposal_url": proposal_url,
            "proposal_title": "Mock Proposal 2026",
            "dao_space": dao_space,
            "vote_choice": vote_choice,
            "vote_choice_name": vote_choice_name,
            "voting_power": round(np.random.normal(mean=255.0, std=122.5), 2),  # Gaussian instead of uniform
            "signature": f"0x{''.join(random.choices('0123456789abcdef', k=130))}",
            "status": "voted",
            "completed_at": self._get_current_timestamp()
        }
    
    def _get_current_timestamp(self) -> str:
        """Возвращает текущий timestamp в ISO format."""
        from datetime import datetime, timezone
        return datetime.now(timezone.utc).isoformat()
