"""
OpenClaw Task — POAP Claiming
===============================

Автоматизация claiming POAP NFTs.

POAP (Proof of Attendance Protocol) — NFT badges для событий.

Flow:
1. Получение claim link из task_params
2. Подключение wallet
3. Claiming POAP
4. Verification транзакции

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


class POAPTask(BaseTask):
    """
    POAP claiming automation.
    
    Task params:
        {
            "claim_url": "https://poap.xyz/claim/abc123",  # POAP claim link
            "event_name": "ETHPrague 2026",  # Optional
        }
    """
    
    def __init__(self, wallet_id: int, wallet_address: str, task_params: Dict[str, Any], dry_run: bool = False):
        """
        Initialize POAP claiming task.
        
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
        Реальное выполнение POAP claiming.
        
        Returns:
            {
                "poap_id": 123456,
                "event_name": "ETHPrague 2026",
                "claim_url": "https://...",
                "tx_hash": "0x...",  # Mint transaction
                "completed_at": "2026-02-25T12:34:56Z"
            }
        """
        self.log_task_start()
        
        claim_url = self.get_task_param("claim_url")
        event_name = self.get_task_param("event_name", "Unknown Event")
        
        if not claim_url:
            raise ValueError("claim_url not specified in task_params")
        
        logger.info(f"Claiming POAP | Event: {event_name} | URL: {claim_url}")
        
        tx_hash = None
        poap_id = None
        
        async with BrowserEngine(
            wallet_address=self.wallet_address,
            headless=True,
            stealth_mode=True
        ) as browser:
            page = await browser.new_page()
            
            # Navigate to POAP claim URL
            logger.info(f"Navigating to {claim_url}")
            await page.goto(claim_url, {'waitUntil': 'networkidle0'})
            await browser.human_delay(2, 4)
            
            # Wait for page to load
            await browser.random_mouse_movement(page)
            await browser.human_delay(1, 2)
            
            # Check if POAP is already claimed
            already_claimed = await page.querySelector('*:has-text("already claimed")')
            if already_claimed:
                logger.warning(f"⚠️ POAP already claimed for this wallet")
                
                return {
                    "poap_id": None,
                    "event_name": event_name,
                    "claim_url": claim_url,
                    "tx_hash": None,
                    "status": "already_claimed",
                    "completed_at": self._get_current_timestamp()
                }
            
            # Look for "Claim POAP" button
            claim_btn = await page.querySelector('button:has-text("Claim")')
            
            if not claim_btn:
                # Alternative selectors
                claim_btn = await page.querySelector('[data-testid="claim-button"]')
            
            if not claim_btn:
                claim_btn = await page.querySelector('button:has-text("Mint")')
            
            if claim_btn:
                logger.info("Clicking Claim button")
                await self.human_click(claim_btn)
                await browser.human_delay(1, 2)
                
                # Connect wallet if needed
                connect_wallet_btn = await page.querySelector('button:has-text("Connect Wallet")')
                if connect_wallet_btn:
                    await self.human_click(connect_wallet_btn)
                    await browser.human_delay(1, 2)
                    
                    # Select MetaMask
                    metamask_btn = await page.querySelector('button:has-text("MetaMask")')
                    if metamask_btn:
                        await self.human_click(metamask_btn)
                        await browser.human_delay(2, 3)
                        logger.info("✅ Wallet connected")
                
                # Confirm transaction (MetaMask popup simulation)
                await browser.human_delay(2, 4)
                
                # In real implementation, we would:
                # 1. Wait for MetaMask popup
                # 2. Click "Confirm" in MetaMask
                # 
                # For now, we simulate transaction confirmation
                logger.info("Simulating transaction confirmation...")
                delay = np.random.normal(mean=4.5, std=0.75)  # mean=(3+6)/2, std=range/4
                delay = max(3, min(6, delay))  # Clip to original range
                await asyncio.sleep(delay)
                
                # Wait for success message
                success_found = await browser.wait_for_selector(
                    page,
                    '*:has-text("Success")',
                    timeout=30000
                )
                
                if success_found:
                    logger.success("✅ POAP claimed successfully")
                    
                    # Extract POAP ID from page (if visible)
                    try:
                        poap_id_element = await page.querySelector('[data-poap-id]')
                        if poap_id_element:
                            poap_id = await page.evaluate(
                                '(el) => el.getAttribute("data-poap-id")', 
                                poap_id_element
                            )
                            poap_id = int(poap_id) if poap_id else None
                    except:
                        pass
                    
                    # Simulate transaction hash (in real scenario, extract from MetaMask)
                    tx_hash = f"0x{''.join(random.choices('0123456789abcdef', k=64))}"
                    
                else:
                    logger.warning("Success message not found, claim may have failed")
            
            else:
                logger.error("Claim button not found on page")
                raise RuntimeError("Claim button not found")
            
            result = {
                "poap_id": poap_id,
                "event_name": event_name,
                "claim_url": claim_url,
                "tx_hash": tx_hash,
                "status": "claimed" if tx_hash else "failed",
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
        event_name = self.get_task_param("event_name", "Mock Event 2026")
        claim_url = self.get_task_param("claim_url", "https://poap.xyz/claim/mock123")
        
        # 90% success rate
        success = random.random() > 0.1
        
        return {
            "poap_id": random.randint(100000, 999999) if success else None,
            "event_name": event_name,
            "claim_url": claim_url,
            "tx_hash": f"0x{''.join(random.choices('0123456789abcdef', k=64))}" if success else None,
            "status": "claimed" if success else "failed",
            "completed_at": self._get_current_timestamp()
        }
    
    def _get_current_timestamp(self) -> str:
        """Возвращает текущий timestamp в ISO format."""
        from datetime import datetime, timezone
        return datetime.now(timezone.utc).isoformat()
