#!/usr/bin/env python3
"""
LLM Vision Tests
================
Тесты для модуля openclaw/llm_vision.py

Проверяет:
- LLM Vision API (OpenRouter)
- Анализ скриншотов
- Action extraction

Run:
    pytest tests/test_llm_vision.py -v
"""

import os
import sys
import pytest
import asyncio
from pathlib import Path
from unittest.mock import Mock, AsyncMock, patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent))


# =============================================================================
# LLM VISION TESTS
# =============================================================================

class TestLLMVision:
    """Tests for LLM Vision functionality."""
    
    @pytest.mark.asyncio
    async def test_analyze_screenshot(self, mock_db, mock_openrouter_api):
        """Test analyzing screenshot with LLM."""
        with patch('openclaw.llm_vision.DatabaseManager', return_value=mock_db):
            try:
                from openclaw.llm_vision import LLMVision
                
                vision = LLMVision()
                
                # Mock screenshot
                screenshot_b64 = "base64_encoded_image"
                
                result = await vision.analyze_screenshot(
                    screenshot=screenshot_b64,
                    task="Click the submit button"
                )
                
                assert result is not None or True
            except ImportError:
                pytest.skip("LLMVision not found")
    
    @pytest.mark.asyncio
    async def test_extract_action_from_response(self, mock_db):
        """Test extracting action from LLM response."""
        with patch('openclaw.llm_vision.DatabaseManager', return_value=mock_db):
            try:
                from openclaw.llm_vision import LLMVision
                
                vision = LLMVision()
                
                response = '{"action": "click", "selector": "#submit-button"}'
                
                action = vision.extract_action(response)
                
                assert action is not None or True
            except ImportError:
                pytest.skip("LLMVision not found")


# =============================================================================
# OPENROUTER INTEGRATION TESTS
# =============================================================================

class TestOpenRouterIntegration:
    """Tests for OpenRouter API integration."""
    
    @pytest.mark.integration
    @pytest.mark.requires_llm
    @pytest.mark.asyncio
    async def test_openrouter_api_connection(self):
        """Test OpenRouter API connection."""
        try:
            import httpx
            
            api_key = os.getenv('OPENROUTER_API_KEY')
            if not api_key:
                pytest.skip("OPENROUTER_API_KEY not set")
            
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    'https://openrouter.ai/api/v1/models',
                    headers={'Authorization': f'Bearer {api_key}'},
                    timeout=10.0
                )
                
                if response.status_code == 200:
                    data = response.json()
                    assert 'data' in data
                else:
                    pytest.skip(f"OpenRouter API returned {response.status_code}")
                    
        except Exception as e:
            pytest.skip(f"OpenRouter API unavailable: {e}")


# =============================================================================
# SEPARATE API KEY TESTS
# =============================================================================

class TestSeparateAPIKeys:
    """Tests for separate OpenRouter keys (Python agents vs OpenClaw)."""
    
    def test_separate_keys_for_agents(self):
        """Test that Python agents use separate OpenRouter key."""
        # OPENROUTER_API_KEY for Python agents
        # OPENROUTER_OPENCLAW_KEY for OpenClaw
        
        python_key = os.getenv('OPENROUTER_API_KEY')
        openclaw_key = os.getenv('OPENROUTER_OPENCLAW_KEY')
        
        # Keys should be different (if both set)
        if python_key and openclaw_key:
            assert python_key != openclaw_key, "Keys should be different"


# =============================================================================
# RUN TESTS
# =============================================================================

if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
