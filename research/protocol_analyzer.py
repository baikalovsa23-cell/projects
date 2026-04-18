"""
Protocol Analyzer — LLM Integration for Protocol Research Engine
================================================================
Uses OpenRouter API (GPT-4 Turbo) to analyze protocol candidates and assign:
- Airdrop score (0-100)
- Recommended actions (SWAP, LP, STAKE, etc.)
- Reasoning and risk assessment
- TVL growth analysis
- Bridge availability check (via Bridge Manager v2.0)

Cost tracking: ~$0.01-0.03 per protocol analysis.

Integration with Bridge Manager:
- Checks bridge availability for each protocol's chain
- Adds bridge_required, bridge_available, bridge_cost_usd to analysis
- Unreachable protocols are flagged for weekly recheck
"""

import asyncio
import json
import os
import random
import numpy as np
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Tuple
from decimal import Decimal

import aiohttp
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type

from database.db_manager import get_db_manager


class ProtocolAnalyzer:
    """
    LLM-powered analysis of protocol candidates.
    
    Uses OpenRouter API (GPT-4 Turbo) with structured JSON output.
    """

    def __init__(self, db_manager=None, openrouter_api_key: Optional[str] = None):
        """
        Initialize analyzer.
        
        Args:
            db_manager: DatabaseManager instance (optional)
            openrouter_api_key: OpenRouter API key (defaults to OPENROUTER_API_KEY env var)
        """
        self.db = db_manager or get_db_manager()
        self.api_key = openrouter_api_key or os.getenv("OPENROUTER_API_KEY")
        if not self.api_key:
            # Fallback to reading from api_openrouter.txt
            self.api_key = self._read_api_key_from_file()
        if not self.api_key:
            logger.warning("OpenRouter API key not found. LLM analysis will fail.")
        
        self.base_url = "https://openrouter.ai/api/v1"
        self.model = "deepseek/deepseek-v3.2"  # DeepSeek V3.2 via OpenRouter
        self.session: Optional[aiohttp.ClientSession] = None
        self.cost_per_1k_input = Decimal('0.001')  # $0.001 per 1K input tokens (DeepSeek V3.2)
        self.cost_per_1k_output = Decimal('0.002')  # $0.002 per 1K output tokens
        
        # Statistics
        self.total_tokens_used = 0
        self.total_cost_usd = Decimal('0.00')

    def _read_api_key_from_file(self) -> Optional[str]:
        """Read OpenRouter API key from api_openrouter.txt (legacy)."""
        try:
            with open("api_openrouter.txt", "r") as f:
                content = f.read()
                # Extract primary key (for Protocol Research Agent)
                lines = content.splitlines()
                for i, line in enumerate(lines):
                    if "Основной (для Protocol Research Agent):" in line:
                        # Next line contains key (may be indented)
                        if i + 1 < len(lines):
                            key = lines[i + 1].strip()
                            if key.startswith("sk-or-v1-"):
                                return key
        except FileNotFoundError:
            pass
        return None

    async def __aenter__(self):
        """Async context manager entry."""
        self.session = aiohttp.ClientSession()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.session:
            await self.session.close()

    @retry(
        retry=retry_if_exception_type((aiohttp.ClientError, asyncio.TimeoutError)),
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        reraise=True
    )
    async def _call_openrouter(self, prompt: str, system_prompt: Optional[str] = None) -> Dict[str, Any]:
        """
        Call OpenRouter API with structured prompt.
        
        Returns:
            JSON response from API
        """
        if not self.session:
            self.session = aiohttp.ClientSession()
        
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://github.com/airdrop-farming-v4",  # Required by OpenRouter
            "X-Title": "Protocol Research Engine v4.0",
        }
        
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})
        
        payload = {
            "model": self.model,
            "messages": messages,
            "temperature": 0.3,  # Low temperature for consistent scoring
            "max_tokens": 1500,
            "response_format": {"type": "json_object"},  # Ensure JSON output
        }
        
        async with self.session.post(
            f"{self.base_url}/chat/completions",
            headers=headers,
            json=payload,
            timeout=60
        ) as response:
            response.raise_for_status()
            data = await response.json()
            
            # Track costs
            usage = data.get("usage", {})
            input_tokens = usage.get("prompt_tokens", 0)
            output_tokens = usage.get("completion_tokens", 0)
            
            input_cost = (Decimal(input_tokens) / 1000) * self.cost_per_1k_input
            output_cost = (Decimal(output_tokens) / 1000) * self.cost_per_1k_output
            total_cost = input_cost + output_cost
            
            self.total_tokens_used += input_tokens + output_tokens
            self.total_cost_usd += total_cost
            
            logger.debug(
                f"OpenRouter API call | Input: {input_tokens} | Output: {output_tokens} | "
                f"Cost: ${total_cost:.4f}"
            )
            
            return data

    def _build_protocol_prompt(self, candidate: Dict[str, Any]) -> str:
        """
        Build a detailed prompt for LLM analysis of a protocol.
        
        Args:
            candidate: Protocol candidate dictionary (from NewsAggregator)
        
        Returns:
            Prompt string
        """
        name = candidate.get("name", "Unknown")
        category = candidate.get("category", "Unknown")
        chains = candidate.get("chains", [])
        tvl_usd = candidate.get("tvl_usd")
        has_token = candidate.get("has_token", False)
        points_program_url = candidate.get("points_program_url")
        article_title = candidate.get("article_title", "")
        raw_text = candidate.get("raw_text", "")[:1000]
        
        prompt = f"""
Analyze the following DeFi protocol for airdrop farming potential (2026).

**Protocol Details:**
- Name: {name}
- Category: {category}
- Chains: {', '.join(chains) if chains else 'Unknown'}
- TVL: ${tvl_usd:,.0f if tvl_usd else 'Unknown'}
- Has token already? {has_token}
- Points program URL: {points_program_url if points_program_url else 'None'}
- Source article: {article_title}

**Raw context:**
{raw_text}

**Instructions:**
1. **Airdrop Score (0-100):** Assign a score based on:
   - Likelihood of future token airdrop (no token = higher chance)
   - Points program existence (higher score if present)
   - TVL growth trend (if data available)
   - Team/VC backing (if mentioned)
   - Competitive landscape (unique features)
   - L2 focus (Base, Arbitrum, Optimism, etc. → higher score)

2. **Recommended Actions:** Select 1-3 actions from: ["SWAP", "LP", "STAKE", "BRIDGE", "NFT_MINT", "GOVERNANCE_VOTE"]
   - Choose actions that are likely to qualify for airdrop.
   - Prioritize low-cost, high-impact actions.

3. **Reasoning:** 2-3 sentence explanation of your score and recommendations.

4. **Risk Assessment:** Low/Medium/High (based on rug pull risk, centralization, etc.)

**Output Format:**
```json
{{
  "airdrop_score": 0-100,
  "recommended_actions": ["SWAP", "LP"],
  "reasoning": "Explanation...",
  "risk_assessment": "Low/Medium/High",
  "additional_notes": "Optional notes"
}}
```

Provide ONLY the JSON object, no other text.
"""
        return prompt

    async def _check_bridge_availability(self, chain: Optional[str]) -> Dict[str, Any]:
        """
        Check bridge availability for a protocol's chain.
        
        This method integrates with Bridge Manager v2.0 to determine:
        1. If the chain requires a bridge (no CEX direct support)
        2. If a bridge route is available via aggregators
        3. The cost and safety score of the bridge
        
        Args:
            chain: Chain name to check (e.g., 'Base', 'Ink', 'Arbitrum')
        
        Returns:
            Dict with bridge information:
            {
                'bridge_required': bool,
                'bridge_available': bool,
                'bridge_from_network': str,
                'bridge_provider': str or None,
                'bridge_cost_usd': float or None,
                'bridge_safety_score': int or None,
                'cex_support': str or None,
                'bridge_unreachable_reason': str or None
            }
        """
        # Default result for unknown chains
        if not chain:
            return {
                'bridge_required': False,
                'bridge_available': True,
                'bridge_from_network': 'Arbitrum',
                'bridge_provider': None,
                'bridge_cost_usd': None,
                'bridge_safety_score': None,
                'cex_support': None,
                'bridge_unreachable_reason': None
            }
        
        try:
            # Import BridgeManager (lazy import to avoid circular dependencies)
            from activity.bridge_manager import BridgeManager
            
            # Initialize BridgeManager in dry-run mode (no actual transactions)
            bridge_manager = BridgeManager(db=self.db, dry_run=True)
            
            # Step 1: Check if bridge is required (CEX support check)
            is_required, cex_name = await bridge_manager.is_bridge_required(chain)
            
            if not is_required:
                # CEX supports direct withdrawal to this chain
                logger.info(f"Bridge check for {chain}: NOT REQUIRED (CEX: {cex_name})")
                return {
                    'bridge_required': False,
                    'bridge_available': True,
                    'bridge_from_network': None,
                    'bridge_provider': None,
                    'bridge_cost_usd': None,
                    'bridge_safety_score': None,
                    'cex_support': cex_name,
                    'bridge_unreachable_reason': None
                }
            
            # Step 2: Bridge is required - check availability
            logger.info(f"Bridge check for {chain}: REQUIRED, checking routes...")
            
            route = await bridge_manager.check_bridge_availability(
                from_network='Arbitrum',  # Default source network
                to_network=chain,
                amount_eth=Decimal('0.05')  # Typical amount for estimation
            )
            
            if route:
                # Bridge route found
                logger.info(
                    f"Bridge check for {chain}: AVAILABLE via {route.provider} "
                    f"(cost: ${route.cost_usd:.2f}, safety: {route.safety_score})"
                )
                return {
                    'bridge_required': True,
                    'bridge_available': True,
                    'bridge_from_network': 'Arbitrum',
                    'bridge_provider': route.provider,
                    'bridge_cost_usd': float(route.cost_usd),
                    'bridge_safety_score': route.safety_score,
                    'cex_support': None,
                    'bridge_unreachable_reason': None
                }
            else:
                # No bridge route found
                reason = f"No bridge route found via Socket/Across/Relay. No CEX support."
                logger.warning(f"Bridge check for {chain}: UNAVAILABLE - {reason}")
                return {
                    'bridge_required': True,
                    'bridge_available': False,
                    'bridge_from_network': 'Arbitrum',
                    'bridge_provider': None,
                    'bridge_cost_usd': None,
                    'bridge_safety_score': None,
                    'cex_support': None,
                    'bridge_unreachable_reason': reason
                }
                
        except Exception as e:
            logger.error(f"Bridge check failed for {chain}: {e}")
            # Return conservative result - assume bridge required but unavailable
            return {
                'bridge_required': True,
                'bridge_available': False,
                'bridge_from_network': 'Arbitrum',
                'bridge_provider': None,
                'bridge_cost_usd': None,
                'bridge_safety_score': None,
                'cex_support': None,
                'bridge_unreachable_reason': f"Bridge check error: {str(e)}"
            }

    async def analyze_candidate(self, candidate: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        Analyze a single protocol candidate via LLM + bridge check.
        
        Now includes Smart Risk Engine checks:
        1. Token kill-switch check (skip if token exists)
        2. Risk scoring (BLOCK if critical issues found)
        
        Args:
            candidate: Protocol candidate dictionary
        
        Returns:
            Analysis dictionary with keys: airdrop_score, recommended_actions, reasoning,
            risk_assessment, raw_llm_response, bridge_info, risk_info, or None if analysis failed
        """
        if not self.api_key:
            logger.error("OpenRouter API key missing, skipping analysis")
            return None
        
        name = candidate.get('name', 'Unknown')
        
        # === SMART RISK ENGINE: Token kill-switch ===
        has_token, ticker, source = await self._check_token_quick(name)
        if has_token:
            logger.info(f"Skipping {name}: token {ticker} exists (source: {source})")
            return None
        
        # === SMART RISK ENGINE: Risk scoring ===
        risk_result = await self.score_protocol_risk(candidate)
        if risk_result['recommendation'] == 'BLOCK':
            logger.warning(f"BLOCKED {name}: {risk_result.get('block_reason', 'Unknown reason')}")
            return None
        
        prompt = self._build_protocol_prompt(candidate)
        system_prompt = "You are a DeFi research analyst specializing in airdrop farming. Be objective and data-driven."
        
        try:
            logger.info(f"Analyzing protocol: {candidate.get('name')}")
            response = await self._call_openrouter(prompt, system_prompt)
            
            content = response["choices"][0]["message"]["content"]
            
            # Parse JSON from response
            try:
                analysis = json.loads(content)
            except json.JSONDecodeError:
                # Fallback: extract JSON with regex
                import re
                json_match = re.search(r'\{.*\}', content, re.DOTALL)
                if json_match:
                    analysis = json.loads(json_match.group())
                else:
                    logger.error(f"Failed to parse JSON from LLM response: {content[:200]}")
                    return None
            
            # Validate required fields
            required_fields = ["airdrop_score", "recommended_actions", "reasoning"]
            if not all(field in analysis for field in required_fields):
                logger.error(f"LLM response missing required fields: {analysis}")
                return None
            
            # Ensure score is within bounds
            score = analysis["airdrop_score"]
            if not isinstance(score, int) or score < 0 or score > 100:
                logger.warning(f"Invalid airdrop score {score}, clamping to 0-100")
                analysis["airdrop_score"] = max(0, min(100, score))
            
            # Ensure actions are valid
            valid_actions = {"SWAP", "LP", "STAKE", "BRIDGE", "NFT_MINT", "GOVERNANCE_VOTE"}
            actions = analysis["recommended_actions"]
            if isinstance(actions, str):
                actions = [actions]
            analysis["recommended_actions"] = [a for a in actions if a in valid_actions][:3]
            if not analysis["recommended_actions"]:
                analysis["recommended_actions"] = ["SWAP"]  # Default
            
            # Add raw response for auditing
            analysis["raw_llm_response"] = response
            
            # === SMART RISK ENGINE: Add risk info ===
            analysis["risk_info"] = risk_result
            
            # === NEW: Bridge availability check ===
            chains = candidate.get("chains", [])
            primary_chain = chains[0] if chains else None
            bridge_info = await self._check_bridge_availability(primary_chain)
            analysis["bridge_info"] = bridge_info
            
            logger.info(
                f"Analysis completed | Protocol: {candidate.get('name')} | "
                f"Score: {analysis['airdrop_score']} | Actions: {analysis['recommended_actions']} | "
                f"Bridge: {'required' if bridge_info['bridge_required'] else 'not required'}"
            )
            
            return analysis
            
        except Exception as e:
            logger.error(f"LLM analysis failed for {candidate.get('name')}: {e}")
            return None

    async def analyze_candidates(self, candidates: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Analyze multiple candidates with rate limiting (5 RPM).
        
        Args:
            candidates: List of protocol candidate dictionaries
        
        Returns:
            List of analysis dictionaries (successful only)
        """
        if not candidates:
            return []
        
        logger.info(f"Starting LLM analysis of {len(candidates)} candidates")
        
        successful = []
        failed = []
        
        for i, candidate in enumerate(candidates):
            # Rate limiting: ~5 requests per minute
            if i > 0 and i % 5 == 0:
                logger.debug("Rate limiting: waiting 60 seconds after 5 requests")
                await asyncio.sleep(60)
            
            # Random delay 2-8 seconds between requests (anti‑detection)
            if i > 0:
                delay = np.random.normal(mean=5.0, std=1.5)  # mean=(2+8)/2, std=range/4
                delay = max(2, min(8, delay))  # Clip to original range
                await asyncio.sleep(delay)
            
            analysis = await self.analyze_candidate(candidate)
            if analysis:
                successful.append({
                    **candidate,
                    **analysis,
                    "analysis_timestamp": datetime.now().isoformat(),
                })
            else:
                failed.append(candidate.get("name", "Unknown"))
        
        logger.info(
            f"LLM analysis completed | Successful: {len(successful)} | Failed: {len(failed)} | "
            f"Total cost: ${self.total_cost_usd:.4f}"
        )
        
        if failed:
            logger.warning(f"Failed analyses: {failed}")
        
        return successful

    async def save_to_pending(self, analyses: List[Dict[str, Any]]) -> int:
        """
        Save LLM analyses to protocol_research_pending table.
        
        Now includes bridge information from Bridge Manager v2.0 integration.
        
        Args:
            analyses: List of analysis dictionaries (from analyze_candidates)
        
        Returns:
            Number of successfully saved protocols
        """
        saved_count = 0
        
        for analysis in analyses:
            try:
                # Extract bridge info
                bridge_info = analysis.get("bridge_info", {})
                
                # Extract risk info (Smart Risk Engine)
                risk_info = analysis.get("risk_info", {})
                
                # Prepare fields for create_pending_protocol
                pending_data = {
                    "name": analysis.get("name"),
                    "category": analysis.get("category", "Unknown"),
                    "chains": analysis.get("chains", []),
                    "website_url": None,  # Not available from news aggregator
                    "twitter_url": None,
                    "discord_url": None,
                    "airdrop_score": analysis.get("airdrop_score", 50),
                    "has_points_program": bool(analysis.get("points_program_url")),
                    "points_program_url": analysis.get("points_program_url"),
                    "has_token": analysis.get("has_token", False),
                    "current_tvl_usd": analysis.get("tvl_usd"),
                    "tvl_change_30d_pct": None,  # Not available
                    "launch_date": None,
                    "recommended_actions": analysis.get("recommended_actions", ["SWAP"]),
                    "reasoning": analysis.get("reasoning", "No reasoning provided."),
                    "raw_llm_response": analysis.get("raw_llm_response"),
                    "discovered_from": analysis.get("source", "unknown"),
                    "source_article_url": analysis.get("article_url"),
                    "source_article_title": analysis.get("article_title"),
                    "source_published_at": analysis.get("article_published_at"),
                    
                    # Bridge fields (new in migration 032)
                    "bridge_required": bridge_info.get("bridge_required", False),
                    "bridge_from_network": bridge_info.get("bridge_from_network"),
                    "bridge_provider": bridge_info.get("bridge_provider"),
                    "bridge_cost_usd": bridge_info.get("bridge_cost_usd"),
                    "bridge_safety_score": bridge_info.get("bridge_safety_score"),
                    "bridge_available": bridge_info.get("bridge_available", True),
                    "bridge_checked_at": datetime.now(),
                    "bridge_unreachable_reason": bridge_info.get("bridge_unreachable_reason"),
                    "cex_support": bridge_info.get("cex_support"),
                    
                    # Risk fields (Smart Risk Engine - migration 045)
                    "risk_level": risk_info.get("risk_level", "MEDIUM"),
                    "risk_tags": risk_info.get("risk_tags", []),
                    "requires_manual": risk_info.get("requires_manual", False),
                    "risk_score": risk_info.get("risk_score"),
                }
                
                # For unreachable protocols, set recheck date
                if not bridge_info.get("bridge_available", True):
                    pending_data["bridge_recheck_after"] = datetime.now() + timedelta(days=7)
                    pending_data["bridge_recheck_count"] = 0
                
                # Convert datetime to string if needed
                if pending_data["source_published_at"] and isinstance(pending_data["source_published_at"], datetime):
                    pending_data["source_published_at"] = pending_data["source_published_at"].isoformat()
                
                # Save to database
                pending_id = self.db.create_pending_protocol(**pending_data)
                saved_count += 1
                
                # Log with bridge status
                bridge_status = "unreachable" if not bridge_info.get("bridge_available", True) else (
                    f"via {bridge_info.get('bridge_provider')}" if bridge_info.get("bridge_required") else "direct CEX"
                )
                logger.info(
                    f"Saved pending protocol ID {pending_id}: {analysis.get('name')} | "
                    f"Bridge: {bridge_status}"
                )
                
            except Exception as e:
                logger.error(f"Failed to save analysis for {analysis.get('name')}: {e}")
        
        logger.info(f"Saved {saved_count} protocols to pending approval queue")
        return saved_count
    
    # ========================================================================
    # PROTOCOL ACTION RESOLVER (Module 1)
    # ========================================================================
    
    async def resolve_action_type(self, protocol_name: str, chain: str) -> Dict[str, Any]:
        """
        Resolve protocol action type based on category from DefiLlama or LLM.
        
        This method determines what actions (SWAP, STAKE, LP, BRIDGE, etc.)
        are allowed for a protocol based on its category.
        
        Args:
            protocol_name: Protocol name (e.g., 'uniswap', 'aave-v3')
            chain: Chain name (e.g., 'arbitrum', 'base')
        
        Returns:
            Dict with keys:
            - category: Protocol category (DEX, LENDING, STAKING, BRIDGE, NFT, YIELD, DERIVATIVES, INSURANCE)
            - allowed_actions: List of allowed tx_type strings
            - source: 'defillama' or 'llm' or 'cache'
            - needs_classification: bool if manual classification needed
        
        Example:
            >>> result = await analyzer.resolve_action_type('uniswap', 'arbitrum')
            >>> print(result)
            {
                'category': 'DEX',
                'allowed_actions': ['SWAP', 'LP', 'APPROVE'],
                'source': 'defillama',
                'needs_classification': False
            }
        """
        # Step 1: Check cache in protocols table
        cached_protocol = self.db.get_protocol_by_name(protocol_name)
        if cached_protocol and cached_protocol.get('category'):
            category = cached_protocol['category']
            allowed_actions = self._map_category_to_actions(category)
            logger.info(
                f"Protocol action resolved from cache | "
                f"Protocol: {protocol_name} | Category: {category} | "
                f"Actions: {allowed_actions}"
            )
            return {
                'category': category,
                'allowed_actions': allowed_actions,
                'source': 'cache',
                'needs_classification': False
            }
        
        # Step 2: Query DefiLlama API for category
        category = await self._fetch_defillama_category(protocol_name)
        
        if category:
            # Category found in DefiLlama
            allowed_actions = self._map_category_to_actions(category)
            
            # Update cache in protocols table
            try:
                self.db.execute_query(
                    "UPDATE protocols SET category = %s WHERE name = %s",
                    (category, protocol_name)
                )
                logger.debug(f"Updated protocol category in cache | {protocol_name}: {category}")
            except Exception as e:
                logger.warning(f"Failed to cache protocol category: {e}")
            
            logger.info(
                f"Protocol action resolved from DefiLlama | "
                f"Protocol: {protocol_name} | Category: {category} | "
                f"Actions: {allowed_actions}"
            )
            return {
                'category': category,
                'allowed_actions': allowed_actions,
                'source': 'defillama',
                'needs_classification': False
            }
        
        # Step 3: Fallback to LLM classification
        logger.info(f"DefiLlama category not found for {protocol_name}, using LLM fallback")
        category = await self._classify_protocol_via_llm(protocol_name, chain)
        
        if category and category != 'UNKNOWN':
            allowed_actions = self._map_category_to_actions(category)
            
            # Update cache
            try:
                self.db.execute_query(
                    "UPDATE protocols SET category = %s WHERE name = %s",
                    (category, protocol_name)
                )
            except Exception as e:
                logger.warning(f"Failed to cache protocol category: {e}")
            
            logger.info(
                f"Protocol action resolved from LLM | "
                f"Protocol: {protocol_name} | Category: {category} | "
                f"Actions: {allowed_actions}"
            )
            return {
                'category': category,
                'allowed_actions': allowed_actions,
                'source': 'llm',
                'needs_classification': False
            }
        
        # Step 4: LLM uncertain - mark for manual classification
        logger.warning(
            f"LLM unable to classify protocol {protocol_name} on {chain}. "
            f"Marking for manual classification."
        )
        
        # Send Telegram notification (warning level)
        try:
            from notifications.telegram_bot import send_alert
            message = (
                f"⚠️ *Protocol Classification Needed*\n\n"
                f"*Protocol:* {protocol_name}\n"
                f"*Chain:* {chain}\n\n"
                f"Unable to auto-classify. Please review and set category manually.\n\n"
                f"Categories: DEX, LENDING, STAKING, BRIDGE, NFT, YIELD, DERIVATIVES, INSURANCE"
            )
            send_alert('warning', message)
        except Exception as e:
            logger.error(f"Failed to send Telegram alert: {e}")
        
        # Record in protocol_research_pending
        try:
            self.db.execute_query(
                """
                INSERT INTO protocol_research_pending 
                (name, category, chains, status, reasoning, discovered_from)
                VALUES (%s, %s, %s, 'needs_classification', %s, 'auto_classification')
                ON CONFLICT (name) DO UPDATE SET
                    status = 'needs_classification',
                    reasoning = %s,
                    discovered_from = 'auto_classification'
                """,
                (protocol_name, 'Unknown', [chain], 
                 f"Auto-classification failed for {protocol_name} on {chain}",
                 f"Auto-classification failed for {protocol_name} on {chain}")
            )
        except Exception as e:
            logger.error(f"Failed to record pending classification: {e}")
        
        return {
            'category': 'Unknown',
            'allowed_actions': ['SWAP'],  # Default fallback (safe)
            'source': 'llm',
            'needs_classification': True
        }
    
    async def _fetch_defillama_category(self, protocol_name: str) -> Optional[str]:
        """
        Fetch protocol category from DefiLlama API using aiohttp session.
        
        Args:
            protocol_name: Protocol slug (e.g., 'uniswap', 'aave-v3')
        
        Returns:
            Category string or None if not found
        """
        try:
            if not self.session:
                self.session = aiohttp.ClientSession()
            
            # DefiLlama API endpoint
            url = f"https://api.llama.fi/protocol/{protocol_name}"
            
            async with self.session.get(url, timeout=30) as response:
                if response.status == 200:
                    data = await response.json()
                    category = data.get('category')
                    
                    if category:
                        logger.debug(f"DefiLlama category found | {protocol_name}: {category}")
                        return category
                    else:
                        logger.debug(f"DefiLlama response missing category for {protocol_name}")
                        return None
                else:
                    logger.warning(
                        f"DefiLlama API returned status {response.status} for {protocol_name}"
                    )
                    return None
        except Exception as e:
            logger.error(f"DefiLlama API request failed for {protocol_name}: {e}")
            return None
    
    async def _classify_protocol_via_llm(self, protocol_name: str, chain: str) -> Optional[str]:
        """
        Classify protocol category using LLM.
        
        Args:
            protocol_name: Protocol name
            chain: Chain name
        
        Returns:
            Category string or None if uncertain
        """
        prompt = f"""
Protocol: {protocol_name}
Chain: {chain}

What category does this protocol belong to?
Answer only one of: DEX / LENDING / STAKING / BRIDGE / NFT / YIELD / DERIVATIVES / INSURANCE / UNKNOWN
"""
        
        try:
            response = await self._call_openrouter(prompt)
            content = response["choices"][0]["message"]["content"].strip().upper()
            
            # Validate response
            valid_categories = {
                'DEX', 'LENDING', 'STAKING', 'BRIDGE', 'NFT', 
                'YIELD', 'DERIVATIVES', 'INSURANCE', 'UNKNOWN'
            }
            
            if content in valid_categories:
                logger.debug(f"LLM classified {protocol_name} as {content}")
                return content
            else:
                logger.warning(f"LLM returned invalid category: {content}")
                return 'UNKNOWN'
        except Exception as e:
            logger.error(f"LLM classification failed for {protocol_name}: {e}")
            return None
    
    def _map_category_to_actions(self, category: str) -> List[str]:
        """
        Map protocol category to allowed transaction types.
        
        Args:
            category: Protocol category (DEX, LENDING, STAKING, BRIDGE, NFT, YIELD, DERIVATIVES, INSURANCE)
        
        Returns:
            List of allowed tx_type strings
        
        Mapping:
            DEX         → [SWAP, LP, APPROVE]
            LENDING      → [STAKE, APPROVE]  ← SWAP запрещён
            STAKING      → [STAKE]
            BRIDGE       → [BRIDGE]
            NFT          → [NFT_MINT]
            YIELD        → [STAKE, LP]
            DERIVATIVES  → [SWAP, APPROVE]
            INSURANCE    → [STAKE, APPROVE]
            Unknown       → [SWAP]  # Default fallback (safe)
        """
        category_mapping = {
            'DEX': ['SWAP', 'LP', 'APPROVE'],
            'LENDING': ['STAKE', 'APPROVE'],
            'STAKING': ['STAKE'],
            'BRIDGE': ['BRIDGE'],
            'NFT': ['NFT_MINT'],
            'YIELD': ['STAKE', 'LP'],
            'DERIVATIVES': ['SWAP', 'APPROVE'],
            'INSURANCE': ['STAKE', 'APPROVE'],
            'Unknown': ['SWAP']  # Default fallback (safe)
        }
        
        return category_mapping.get(category, ['SWAP'])
    
    # ========================================================================
    # SMART RISK ENGINE (Module 2)
    # ========================================================================
    
    async def score_protocol_risk(self, candidate: Dict[str, Any]) -> Dict[str, Any]:
        """
        Comprehensive risk scoring for protocol candidates.
        
        Smart Risk Engine integration - multi-layer risk checks.
        Stops at first BLOCK condition.
        
        Args:
            candidate: Protocol candidate dictionary
        
        Returns:
            {
                "recommendation": "APPROVE|PENDING|REJECT|BLOCK",
                "risk_level": "LOW|MEDIUM|HIGH|CRITICAL",
                "risk_tags": [...],
                "risk_score": 0-100,
                "block_reason": "...",  # if BLOCK
                "requires_manual": bool
            }
        """
        name = candidate.get('name', 'Unknown')
        chains = candidate.get('chains', [])
        primary_chain = chains[0] if chains else None
        
        score = 100  # Start with perfect score
        risk_tags = []
        warnings = []
        
        # === CHECK 1: TVL CHECK (DeFiLlama) ===
        try:
            tvl_data = await self._check_tvl(name)
            if tvl_data['tvl_usd'] is not None:
                if tvl_data['tvl_usd'] < 500_000:
                    return {
                        "recommendation": "BLOCK",
                        "risk_level": "CRITICAL",
                        "risk_tags": ["TVL_TOO_LOW"],
                        "risk_score": 0,
                        "block_reason": f"TVL too low: ${tvl_data['tvl_usd']:,.0f} < $500K minimum",
                        "requires_manual": False
                    }
                elif tvl_data['tvl_usd'] < 1_000_000:
                    score -= 20
                    risk_tags.append("TVL_LOW")
                    warnings.append(f"TVL ${tvl_data['tvl_usd']:,.0f} (warning threshold)")
        except Exception as e:
            logger.debug(f"TVL check failed for {name}: {e}")
        
        # === CHECK 2: HACK HISTORY (DeFiLlama) ===
        try:
            hack_data = await self._check_hack_history(name)
            if hack_data['recent_hack']:
                if hack_data['months_ago'] <= 12:
                    return {
                        "recommendation": "BLOCK",
                        "risk_level": "CRITICAL",
                        "risk_tags": ["HACK_RECENT"],
                        "risk_score": 0,
                        "block_reason": f"Protocol was hacked {hack_data['months_ago']} months ago",
                        "requires_manual": False
                    }
                else:
                    score -= 20
                    risk_tags.append("HACK_HISTORY")
                    warnings.append(f"Hack occurred {hack_data['months_ago']} months ago")
        except Exception as e:
            logger.debug(f"Hack history check failed for {name}: {e}")
        
        # === CHECK 3: CONTRACT AGE (via RPC) ===
        if primary_chain:
            try:
                age_data = await self._check_contract_age(name, primary_chain)
                if age_data['age_days'] is not None:
                    if age_data['age_days'] < 14:
                        return {
                            "recommendation": "BLOCK",
                            "risk_level": "CRITICAL",
                            "risk_tags": ["CONTRACT_TOO_NEW"],
                            "risk_score": 0,
                            "block_reason": f"Contract only {age_data['age_days']} days old (< 14 days minimum)",
                            "requires_manual": False
                        }
                    elif age_data['age_days'] < 30:
                        score -= 15
                        risk_tags.append("CONTRACT_NEW")
                        warnings.append(f"Contract age: {age_data['age_days']} days")
            except Exception as e:
                logger.debug(f"Contract age check failed for {name}: {e}")
        
        # === CHECK 4: KYC CHECK (LLM) ===
        try:
            kyc_result = await self._check_kyc_requirement(name, primary_chain)
            if kyc_result == "YES":
                return {
                    "recommendation": "BLOCK",
                    "risk_level": "CRITICAL",
                    "risk_tags": ["KYC_REQUIRED"],
                    "risk_score": 0,
                    "block_reason": "Protocol requires KYC/identity verification",
                    "requires_manual": False
                }
            elif kyc_result == "UNKNOWN":
                score -= 10
                risk_tags.append("KYC_UNKNOWN")
                warnings.append("KYC status unknown - manual verification recommended")
        except Exception as e:
            logger.debug(f"KYC check failed for {name}: {e}")
        
        # === CHECK 5: SYBIL PATTERNS (regex) ===
        raw_text = candidate.get('raw_text', '') or ''
        description = f"{candidate.get('article_title', '')} {raw_text}".lower()
        
        sybil_patterns = {
            r'gitcoin.{0,10}passport': ('SYBIL_GITCOIN', -30),
            r'proof.{0,10}humanity': ('BLOCK_PROOF_HUMANITY', 'BLOCK'),
            r'sybil.{0,10}detect': ('SYBIL_DETECTION', -30),
            r'kyc.{0,10}required': ('BLOCK_KYC', 'BLOCK'),
            r'perpetual|options.{0,10}trading': ('BLOCK_PERP', 'BLOCK'),
        }
        
        import re
        for pattern, (tag, penalty) in sybil_patterns.items():
            if re.search(pattern, description, re.IGNORECASE):
                if penalty == 'BLOCK':
                    return {
                        "recommendation": "BLOCK",
                        "risk_level": "CRITICAL",
                        "risk_tags": [tag],
                        "risk_score": 0,
                        "block_reason": f"Sybil/KYC pattern detected: {tag}",
                        "requires_manual": False
                    }
                else:
                    score += penalty  # penalty is negative
                    risk_tags.append(tag)
        
        # === CHECK 6: GOPLUS SECURITY ===
        if primary_chain:
            try:
                goplus_data = await self._check_goplus_security(name, primary_chain)
                if goplus_data.get('is_honeypot'):
                    return {
                        "recommendation": "BLOCK",
                        "risk_level": "CRITICAL",
                        "risk_tags": ["HONEYPOT"],
                        "risk_score": 0,
                        "block_reason": "Token flagged as honeypot by GoPlus",
                        "requires_manual": False
                    }
                if goplus_data.get('is_blacklisted'):
                    return {
                        "recommendation": "BLOCK",
                        "risk_level": "CRITICAL",
                        "risk_tags": ["BLACKLISTED"],
                        "risk_score": 0,
                        "block_reason": "Token is blacklisted",
                        "requires_manual": False
                    }
                sell_tax = goplus_data.get('sell_tax', 0)
                if sell_tax > 10:
                    score -= 20
                    risk_tags.append("HIGH_SELL_TAX")
                    warnings.append(f"Sell tax: {sell_tax}%")
            except Exception as e:
                logger.debug(f"GoPlus check failed for {name}: {e}")
        
        # === FINAL SCORE CALCULATION ===
        score = max(0, min(100, score))
        
        # Determine recommendation based on score
        if score >= 60:
            recommendation = "APPROVE"
            risk_level = "LOW"
            requires_manual = False
        elif score >= 40:
            recommendation = "PENDING"
            risk_level = "MEDIUM"
            requires_manual = True
        else:
            recommendation = "REJECT"
            risk_level = "HIGH"
            requires_manual = True
        
        result = {
            "recommendation": recommendation,
            "risk_level": risk_level,
            "risk_tags": risk_tags,
            "risk_score": score,
            "requires_manual": requires_manual
        }
        
        if warnings:
            result["warnings"] = warnings
        
        logger.info(
            f"Risk scoring complete | {name} | Score: {score} | "
            f"Recommendation: {recommendation} | Tags: {risk_tags}"
        )
        
        return result
    
    async def _check_tvl(self, protocol_name: str) -> Dict[str, Any]:
        """Check TVL from DeFiLlama."""
        if not self.session:
            self.session = aiohttp.ClientSession()
        
        try:
            # Try to get protocol by slug
            url = f"https://api.llama.fi/protocol/{protocol_name.lower().replace(' ', '-')}"
            async with self.session.get(url, timeout=15) as response:
                if response.status == 200:
                    data = await response.json()
                    return {"tvl_usd": data.get("tvl", 0)}
        except Exception:
            pass
        
        return {"tvl_usd": None}
    
    async def _check_hack_history(self, protocol_name: str) -> Dict[str, Any]:
        """Check hack history from DeFiLlama hacks API."""
        if not self.session:
            self.session = aiohttp.ClientSession()
        
        try:
            url = "https://api.llama.fi/hacks"
            async with self.session.get(url, timeout=15) as response:
                if response.status == 200:
                    hacks = await response.json()
                    
                    for hack in hacks:
                        if protocol_name.lower() in hack.get('name', '').lower():
                            hack_date = datetime.fromisoformat(hack.get('date', '').replace('Z', '+00:00'))
                            months_ago = (datetime.now() - hack_date).days // 30
                            return {
                                "recent_hack": True,
                                "months_ago": months_ago,
                                "amount_lost": hack.get('amount', 0)
                            }
        except Exception:
            pass
        
        return {"recent_hack": False, "months_ago": None}
    
    async def _check_contract_age(self, protocol_name: str, chain: str) -> Dict[str, Any]:
        """
        Check contract deployment age via RPC.
        Note: This is a simplified check - requires contract address.
        """
        # This would require fetching contract address from DeFiLlama or Etherscan
        # For now, return None - actual implementation would need contract address
        return {"age_days": None}
    
    async def _check_kyc_requirement(self, protocol_name: str, chain: Optional[str]) -> str:
        """
        Check if protocol requires KYC via LLM.
        
        Returns: "YES", "NO", or "UNKNOWN"
        """
        prompt = f"""Protocol: {protocol_name}
Chain: {chain or 'Unknown'}

Does this protocol require KYC or identity verification for users?
Answer only one word: YES / NO / UNKNOWN"""
        
        try:
            response = await self._call_openrouter(prompt)
            content = response["choices"][0]["message"]["content"].strip().upper()
            
            if content in ["YES", "NO", "UNKNOWN"]:
                return content
            return "UNKNOWN"
        except Exception:
            return "UNKNOWN"
    
    async def _check_goplus_security(self, protocol_name: str, chain: str) -> Dict[str, Any]:
        """
        Check token security via GoPlus Labs API.
        
        Note: Requires contract address. Returns empty result if no address available.
        """
        # Chain ID mapping for GoPlus
        chain_id_map = {
            'arbitrum': 42161,
            'base': 8453,
            'optimism': 10,
            'polygon': 137,
            'bnb': 56,
            'bsc': 56,
        }
        
        chain_id = chain_id_map.get(chain.lower())
        if not chain_id:
            return {}
        
        # Would need contract address to query GoPlus
        # For now, return empty - actual implementation needs address lookup
        return {}
    
    async def _check_token_quick(self, name: str) -> Tuple[bool, str, str]:
        """
        Quick token existence check using cache + CoinGecko.
        
        Args:
            name: Protocol name to check
        
        Returns:
            Tuple of (has_token, ticker, source)
        """
        # Step 1: Check cache
        cached = self.db.get_token_cache(name)
        if cached:
            return (cached['has_token'], cached['ticker'] or '', 'cache')
        
        # Step 2: Check CoinGecko
        if not self.session:
            self.session = aiohttp.ClientSession()
        
        try:
            url = "https://api.coingecko.com/api/v3/coins/markets"
            params = {
                'vs_currency': 'usd',
                'query': name,
                'per_page': 5,
                'page': 1
            }
            
            async with self.session.get(url, params=params, timeout=10) as response:
                if response.status == 200:
                    data = await response.json()
                    
                    for coin in data:
                        coin_name = coin.get('name', '').lower()
                        coin_symbol = coin.get('symbol', '').upper()
                        coin_id = coin.get('id', '').lower()
                        market_cap = coin.get('market_cap', 0) or 0
                        
                        if name.lower() in coin_name or name.lower() in coin_id:
                            has_token = market_cap > 0
                            ticker = coin_symbol
                            
                            # Cache result
                            self.db.set_token_cache(
                                protocol_name=name,
                                has_token=has_token,
                                ticker=ticker,
                                market_cap=float(market_cap),
                                source='coingecko'
                            )
                            
                            return (has_token, ticker, 'coingecko')
        except Exception as e:
            logger.debug(f"CoinGecko token check failed for {name}: {e}")
        
        # Cache negative result
        self.db.set_token_cache(name, False, None, None, 'none')
        return (False, '', 'none')


if __name__ == "__main__":
    """Test the protocol analyzer with a mock candidate."""
    async def test():
        mock_candidate = {
            "name": "TestProtocol",
            "category": "DEX",
            "chains": ["Base", "Arbitrum"],
            "tvl_usd": 25000000.00,
            "has_token": False,
            "points_program_url": "https://testprotocol.xyz/points",
            "article_title": "TestProtocol Raises $50M Series A",
            "raw_text": "TestProtocol, a new DEX on Base and Arbitrum, raised $50M from a16z. No token yet, but points program active.",
            "source": "manual_testing",
            "article_url": "https://example.com/article",
            "article_published_at": datetime.now().isoformat(),
        }
        
        async with ProtocolAnalyzer() as analyzer:
            analysis = await analyzer.analyze_candidate(mock_candidate)
            if analysis:
                print("✅ Analysis successful:")
                print(f"  Score: {analysis['airdrop_score']}")
                print(f"  Actions: {analysis['recommended_actions']}")
                print(f"  Reasoning: {analysis['reasoning'][:100]}...")
                print(f"  Cost so far: ${analyzer.total_cost_usd:.4f}")
            else:
                print("❌ Analysis failed")
    
    asyncio.run(test())