#!/usr/bin/env python3
"""
LLM Vision Client — OpenRouter API for Browser Automation
==========================================================

Клиент для интеграции OpenRouter API (Claude Haiku) в OpenClaw Executor.

Features:
- Screenshot analysis for UI understanding
- Action generation (click, type, wait, complete, fail)
- JSON response parsing
- Retry logic with exponential backoff
- Cost tracking (tokens used)

Security:
- NO access to private keys
- NO access to wallet addresses
- NO access to database
- NO access to file system
- ONLY receives: screenshot (base64), task description, page URL

OpenRouter Configuration:
- API URL: https://openrouter.ai/api/v1/chat/completions
- Model: anthropic/claude-haiku-4.5 (for OpenClaw tasks)
- Separate API key from research module (OPENROUTER_OPENCLAW_API_KEY)

Author: System Architect + Senior Developer
Created: 2026-03-06
Updated: 2026-03-06 — OpenRouter integration
"""

import os
import json
import re
import base64
import asyncio
from typing import Dict, List, Optional, Any
from datetime import datetime, timezone
from dataclasses import dataclass, field
from enum import Enum

import httpx
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential


class ActionType(Enum):
    """Available actions for LLM to return."""
    CLICK = "click"
    TYPE = "type"
    WAIT = "wait"
    COMPLETE = "complete"
    FAIL = "fail"
    SCROLL = "scroll"
    NAVIGATE = "navigate"


@dataclass
class LLMAction:
    """
    Parsed action from LLM response.
    
    Attributes:
        action: Action type (click, type, wait, complete, fail)
        selector: CSS selector for element (optional)
        coordinates: x, y coordinates for click (optional)
        text: Text to type (for type action)
        duration: Wait duration in seconds (for wait action)
        reason: Explanation for the action
        result: Result data (for complete action)
    """
    action: ActionType
    selector: Optional[str] = None
    coordinates: Optional[Dict[str, int]] = None
    text: Optional[str] = None
    duration: Optional[float] = None
    reason: Optional[str] = None
    result: Optional[Dict[str, Any]] = None
    
    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization."""
        data = {"action": self.action.value}
        if self.selector:
            data["selector"] = self.selector
        if self.coordinates:
            data["coordinates"] = self.coordinates
        if self.text:
            data["text"] = self.text
        if self.duration:
            data["duration"] = self.duration
        if self.reason:
            data["reason"] = self.reason
        if self.result:
            data["result"] = self.result
        return data


@dataclass
class LLMUsage:
    """Token usage tracking."""
    input_tokens: int = 0
    output_tokens: int = 0
    total_tokens: int = 0
    cost_usd: float = 0.0


@dataclass
class LLMVisionResponse:
    """
    Full response from LLM Vision API.
    
    Attributes:
        action: Parsed action
        raw_response: Raw text response from LLM
        usage: Token usage
        model: Model used
        timestamp: Response timestamp
    """
    action: LLMAction
    raw_response: str = ""
    usage: LLMUsage = field(default_factory=LLMUsage)
    model: str = ""
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())


class LLMVisionClient:
    """
    Client for OpenRouter API (Claude Haiku for OpenClaw).
    
    SECURITY BOUNDARY: This client has NO access to:
    - Private keys
    - Wallet credentials
    - Database connection
    - Any sensitive data
    
    It ONLY receives:
    - Screenshot (base64)
    - Task description
    - Current page URL
    - Previous actions (for context)
    
    OpenRouter Configuration:
    - Uses OPENROUTER_API_KEY_OPENCLAW (separate from research)
    - Model: anthropic/claude-haiku-4.5
    - Cost-effective for browser automation tasks
    
    Example:
        >>> client = LLMVisionClient()  # Uses OPENROUTER_API_KEY_OPENCLAW
        >>> response = await client.analyze_screenshot(
        ...     screenshot_base64="...",
        ...     task_description="Click Connect Wallet button",
        ...     page_url="https://passport.gitcoin.co"
        ... )
        >>> print(response.action.action)  # ActionType.CLICK
        >>> print(response.action.selector)  # "button:has-text('Connect')"
    """
    
    # OpenRouter API configuration
    API_URL = "https://openrouter.ai/api/v1/chat/completions"
    
    # Model for OpenClaw tasks (separate from research)
    MODEL_CLAUDE_HAIKU = "anthropic/claude-haiku-4.5"
    
    # Pricing (Claude Haiku via OpenRouter, as of 2026-03)
    # Haiku is much cheaper than Sonnet: ~$0.25/1M input, ~$1.25/1M output
    PRICE_PER_1K_INPUT = 0.00025  # $0.00025 per 1K input tokens
    PRICE_PER_1K_OUTPUT = 0.00125  # $0.00125 per 1K output tokens
    
    def __init__(
        self,
        api_key: Optional[str] = None,
        model: str = None,
        max_tokens: int = 1024,
        timeout: float = 30.0
    ):
        """
        Initialize LLM Vision Client.
        
        Args:
            api_key: OpenRouter API key (defaults to OPENROUTER_OPENCLAW_API_KEY env var)
            model: Model to use (defaults to anthropic/claude-haiku-4.5)
            max_tokens: Maximum tokens in response
            timeout: Request timeout in seconds
        """
        # Use OPENROUTER_API_KEY_OPENCLAW (separate from research)
        self.api_key = api_key or os.getenv('OPENROUTER_API_KEY_OPENCLAW')
        if not self.api_key:
            raise ValueError(
                "OpenRouter API key not provided. "
                "Set OPENROUTER_API_KEY_OPENCLAW environment variable or pass api_key parameter. "
                "Note: This is a SEPARATE key from OPENROUTER_API_KEY used by research module."
            )
        
        self.model = model or self.MODEL_CLAUDE_HAIKU
        self.max_tokens = max_tokens
        self.timeout = timeout
        
        # Usage tracking
        self.total_usage = LLMUsage()
        
        logger.info(f"LLMVisionClient initialized | Provider: OpenRouter | Model: {self.model}")
    
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        reraise=True
    )
    async def analyze_screenshot(
        self,
        screenshot_base64: str,
        task_description: str,
        page_url: str,
        previous_actions: Optional[List[Dict]] = None,
        task_params: Optional[Dict] = None
    ) -> LLMVisionResponse:
        """
        Send screenshot to LLM and get action.
        
        Uses OpenRouter API with Claude Haiku model.
        
        Args:
            screenshot_base64: Base64-encoded PNG screenshot
            task_description: Human-readable task description
            page_url: Current page URL
            previous_actions: List of previous actions (for context)
            task_params: Additional task parameters
        
        Returns:
            LLMVisionResponse with parsed action
        
        Raises:
            httpx.HTTPStatusError: If API request fails
            ValueError: If response cannot be parsed
        """
        # Build prompt
        prompt = self._build_prompt(
            task_description=task_description,
            page_url=page_url,
            previous_actions=previous_actions or [],
            task_params=task_params
        )
        
        # Build request payload for OpenRouter (OpenAI-compatible format)
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://github.com/airdrop-farming-system",  # Optional, for rankings
            "X-Title": "Airdrop Farming System - OpenClaw"  # Optional, for rankings
        }
        
        # OpenRouter uses OpenAI-compatible format with vision support
        payload = {
            "model": self.model,
            "max_tokens": self.max_tokens,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/png;base64,{screenshot_base64}"
                            }
                        },
                        {
                            "type": "text",
                            "text": prompt
                        }
                    ]
                }
            ]
        }
        
        logger.debug(f"Sending screenshot to LLM via OpenRouter | Task: {task_description[:50]}...")
        
        # Make API request
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(
                self.API_URL,
                headers=headers,
                json=payload
            )
            response.raise_for_status()
            data = response.json()
        
        # Parse response (OpenAI-compatible format)
        text_response = data['choices'][0]['message']['content']
        
        # Extract usage
        usage_data = data.get('usage', {})
        usage = LLMUsage(
            input_tokens=usage_data.get('prompt_tokens', 0),
            output_tokens=usage_data.get('completion_tokens', 0),
            total_tokens=usage_data.get('total_tokens', 0)
        )
        usage.cost_usd = self._calculate_cost(usage)
        
        # Update total usage
        self.total_usage.input_tokens += usage.input_tokens
        self.total_usage.output_tokens += usage.output_tokens
        self.total_usage.total_tokens += usage.total_tokens
        self.total_usage.cost_usd += usage.cost_usd
        
        # Parse action
        action = self._parse_action(text_response)
        
        logger.info(
            f"LLM response | Action: {action.action.value} | "
            f"Reason: {action.reason[:50] if action.reason else 'N/A'}... | "
            f"Tokens: {usage.total_tokens} | Cost: ${usage.cost_usd:.6f}"
        )
        
        return LLMVisionResponse(
            action=action,
            raw_response=text_response,
            usage=usage,
            model=self.model
        )
    
    def _build_prompt(
        self,
        task_description: str,
        page_url: str,
        previous_actions: List[Dict],
        task_params: Optional[Dict] = None
    ) -> str:
        """
        Build prompt for LLM.
        
        CRITICAL: Prompt does NOT contain sensitive data.
        No private keys, wallet addresses, or credentials.
        """
        previous_actions_str = self._format_previous_actions(previous_actions)
        task_params_str = self._format_task_params(task_params)
        
        prompt = f"""You are a browser automation agent. Analyze the screenshot and determine the next action to complete the task.

TASK: {task_description}
CURRENT URL: {page_url}
{task_params_str}

PREVIOUS ACTIONS:
{previous_actions_str}

AVAILABLE ACTIONS (respond with JSON only):

1. CLICK - Click on an element
   {{"action": "click", "selector": "button:has-text('Connect')", "reason": "Found Connect Wallet button"}}
   OR use coordinates:
   {{"action": "click", "coordinates": {{"x": 100, "y": 200}}, "reason": "Clicking at specific position"}}

2. TYPE - Type text into an input field
   {{"action": "type", "selector": "input[name='email']", "text": "user@example.com", "reason": "Entering email"}}

3. SCROLL - Scroll the page
   {{"action": "scroll", "direction": "down", "amount": 500, "reason": "Scrolling to find element"}}

4. WAIT - Wait for page to load or element to appear
   {{"action": "wait", "duration": 3, "reason": "Waiting for page to load"}}

5. NAVIGATE - Navigate to a URL
   {{"action": "navigate", "url": "https://example.com", "reason": "Navigating to target page"}}

6. COMPLETE - Task completed successfully
   {{"action": "complete", "result": {{"stamps_collected": ["google", "twitter"], "score": 15.5}}, "reason": "All stamps collected"}}

7. FAIL - Task cannot be completed
   {{"action": "fail", "reason": "Cannot find Connect Wallet button after 3 attempts"}}

RULES:
- Prefer CSS selectors over coordinates (more reliable)
- Use specific selectors (e.g., "button[data-testid='connect']" not just "button")
- If element not found, try alternative selectors before failing
- Maximum 10 iterations before fail
- Always provide a clear reason for your action
- For COMPLETE action, include relevant result data

SELECTOR EXAMPLES:
- Button with text: "button:has-text('Connect Wallet')"
- Input by name: "input[name='email']"
- Input by placeholder: "input[placeholder='Enter email']"
- Element by test ID: "[data-testid='connect-button']"
- Element by class: ".connect-wallet-btn"
- Element by ID: "#connect-button"

RESPOND WITH JSON ONLY. No explanations outside JSON.
"""
        return prompt
    
    def _format_previous_actions(self, actions: List[Dict]) -> str:
        """Format previous actions for prompt."""
        if not actions:
            return "None (first iteration)"
        
        lines = []
        for i, action in enumerate(actions[-5:], 1):  # Last 5 actions
            action_type = action.get('action', 'unknown')
            reason = action.get('reason', 'No reason provided')
            lines.append(f"{i}. {action_type.upper()}: {reason}")
        
        return "\n".join(lines)
    
    def _format_task_params(self, params: Optional[Dict]) -> str:
        """Format task parameters for prompt."""
        if not params:
            return ""
        
        # Filter out sensitive data
        safe_params = {}
        sensitive_keys = ['password', 'secret', 'key', 'token', 'credential', 'private']
        
        for key, value in params.items():
            if any(sensitive in key.lower() for sensitive in sensitive_keys):
                safe_params[key] = "***REDACTED***"
            else:
                safe_params[key] = value
        
        return f"TASK PARAMETERS: {json.dumps(safe_params, indent=2)}"
    
    def _parse_action(self, text_response: str) -> LLMAction:
        """
        Parse LLM text response into action.
        
        Args:
            text_response: Raw text from LLM
        
        Returns:
            Parsed LLMAction
        """
        # Try to extract JSON from response
        json_match = re.search(r'\{[^{}]*\}', text_response, re.DOTALL)
        
        if not json_match:
            # Try to find JSON with nested braces
            json_match = re.search(r'\{.*\}', text_response, re.DOTALL)
        
        if json_match:
            try:
                data = json.loads(json_match.group())
                return self._dict_to_action(data)
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse LLM JSON: {e}")
                logger.debug(f"Raw response: {text_response}")
        
        # Fallback: try to infer action from text
        return self._infer_action_from_text(text_response)
    
    def _dict_to_action(self, data: Dict) -> LLMAction:
        """Convert dictionary to LLMAction."""
        action_str = data.get('action', 'fail').lower()
        
        try:
            action_type = ActionType(action_str)
        except ValueError:
            action_type = ActionType.FAIL
        
        return LLMAction(
            action=action_type,
            selector=data.get('selector'),
            coordinates=data.get('coordinates'),
            text=data.get('text'),
            duration=data.get('duration'),
            reason=data.get('reason', 'No reason provided'),
            result=data.get('result')
        )
    
    def _infer_action_from_text(self, text: str) -> LLMAction:
        """
        Fallback: Infer action from text when JSON parsing fails.
        """
        text_lower = text.lower()
        
        if 'click' in text_lower:
            return LLMAction(action=ActionType.FAIL, reason=f"Could not parse click action: {text[:100]}")
        elif 'complete' in text_lower or 'success' in text_lower:
            return LLMAction(action=ActionType.COMPLETE, reason="Inferred completion from text")
        elif 'fail' in text_lower or 'error' in text_lower:
            return LLMAction(action=ActionType.FAIL, reason=f"Inferred failure: {text[:100]}")
        else:
            return LLMAction(action=ActionType.FAIL, reason=f"Could not parse response: {text[:100]}")
    
    def _calculate_cost(self, usage: LLMUsage) -> float:
        """Calculate cost in USD."""
        input_cost = (usage.input_tokens / 1000) * self.PRICE_PER_1K_INPUT
        output_cost = (usage.output_tokens / 1000) * self.PRICE_PER_1K_OUTPUT
        return input_cost + output_cost
    
    def get_total_usage(self) -> LLMUsage:
        """Get total usage statistics."""
        return self.total_usage
    
    def reset_usage(self):
        """Reset usage tracking."""
        self.total_usage = LLMUsage()


class LLMVisionError(Exception):
    """Base exception for LLM Vision errors."""
    pass


class LLMRateLimitError(LLMVisionError):
    """Rate limit exceeded."""
    pass


class LLMResponseParseError(LLMVisionError):
    """Failed to parse LLM response."""
    pass


class LLMMaxIterationsError(LLMVisionError):
    """Maximum iterations exceeded."""
    pass


# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

async def analyze_and_act(
    client: LLMVisionClient,
    screenshot_base64: str,
    task_description: str,
    page_url: str,
    previous_actions: Optional[List[Dict]] = None
) -> LLMAction:
    """
    Convenience function to analyze screenshot and get action.
    
    Args:
        client: LLMVisionClient instance
        screenshot_base64: Base64-encoded screenshot
        task_description: Task description
        page_url: Current page URL
        previous_actions: Previous actions for context
    
    Returns:
        Parsed LLMAction
    """
    response = await client.analyze_screenshot(
        screenshot_base64=screenshot_base64,
        task_description=task_description,
        page_url=page_url,
        previous_actions=previous_actions
    )
    return response.action


# =============================================================================
# CLI INTERFACE
# =============================================================================

async def test_llm_vision():
    """Test LLM Vision with a sample screenshot."""
    import sys
    
    api_key = os.getenv('OPENROUTER_API_KEY_OPENCLAW')
    if not api_key:
        print("Error: OPENROUTER_API_KEY_OPENCLAW not set")
        print("Note: This is a SEPARATE key from OPENROUTER_API_KEY used by research module.")
        sys.exit(1)
    
    client = LLMVisionClient(api_key=api_key)
    
    # Create a simple test screenshot (1x1 white pixel)
    test_screenshot = base64.b64encode(
        b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01'
        b'\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f'
        b'\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82'
    ).decode()
    
    print("Testing LLM Vision Client (OpenRouter)...")
    print(f"Model: {client.model}")
    
    try:
        response = await client.analyze_screenshot(
            screenshot_base64=test_screenshot,
            task_description="Test task: describe what you see",
            page_url="https://example.com"
        )
        
        print(f"\nResponse:")
        print(f"  Action: {response.action.action.value}")
        print(f"  Reason: {response.action.reason}")
        print(f"  Tokens: {response.usage.total_tokens}")
        print(f"  Cost: ${response.usage.cost_usd:.6f}")
        
    except Exception as e:
        print(f"Error: {e}")


def main():
    """CLI entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description='LLM Vision Client (OpenRouter)')
    parser.add_argument('--test', action='store_true', help='Run test')
    parser.add_argument('--api-key', type=str, help='OpenRouter API key (OPENROUTER_OPENCLAW_API_KEY)')
    
    args = parser.parse_args()
    
    if args.test:
        asyncio.run(test_llm_vision())
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
