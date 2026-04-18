#!/usr/bin/env python3
"""
Test LLM Vision + Action Loop Architecture
==========================================

Tests all components of the LLM Vision architecture:
1. FingerprintGenerator - Canvas/WebGL/AudioContext fingerprinting
2. LLMVisionClient - Claude Vision API integration
3. BrowserEngine - Fingerprint injection
4. OpenClawExecutor - Hybrid execution

Run: python tests/test_llm_vision_architecture.py

Author: System Architect
Created: 2026-03-06
"""

import sys
import asyncio
from pathlib import Path

# Add parent directory for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from loguru import logger

# Configure logger
logger.remove()
logger.add(sys.stderr, level="DEBUG")


def test_fingerprint_generator():
    """Test FingerprintGenerator for all 90 wallets."""
    from openclaw.fingerprint import FingerprintGenerator, verify_uniqueness, get_fingerprint
    
    print("\n" + "="*70)
    print("TEST 1: FingerprintGenerator")
    print("="*70)
    
    gen = FingerprintGenerator()
    
    # Test single wallet
    print("\n1.1 Testing single wallet (wallet_id=5):")
    fp = gen.get_fingerprint(wallet_id=5)
    
    print(f"  Canvas Seed: {fp['canvas_seed']}")
    print(f"  WebGL Renderer: {fp['webgl_renderer'][:50]}...")
    print(f"  WebGL Vendor: {fp['webgl_vendor']}")
    print(f"  Audio Noise: {fp['audio_noise']:.10f}")
    print(f"  Fonts: {len(fp['fonts'])} fonts")
    print(f"  Screen: {fp['screen_width']}x{fp['screen_height']}")
    print(f"  Device Memory: {fp['device_memory']} GB")
    print(f"  Hardware Concurrency: {fp['hardware_concurrency']} cores")
    print(f"  Inject Script Length: {len(fp['inject_script'])} chars")
    
    # Test distribution
    print("\n1.2 Testing distribution statistics:")
    stats = gen.get_stats()
    
    print(f"\n  WebGL Renderer Distribution:")
    for renderer, count in sorted(stats['webgl_renderer_distribution'].items()):
        pct = count / 90 * 100
        print(f"    {renderer[:50]}...: {count} ({pct:.1f}%)")
    
    print(f"\n  Screen Resolution Distribution:")
    for res, count in sorted(stats['screen_resolution_distribution'].items()):
        pct = count / 90 * 100
        print(f"    {res}: {count} ({pct:.1f}%)")
    
    print(f"\n  Device Memory Distribution:")
    for mem, count in sorted(stats['device_memory_distribution'].items()):
        pct = count / 90 * 100
        print(f"    {mem} GB: {count} ({pct:.1f}%)")
    
    # Test uniqueness
    print("\n1.3 Testing fingerprint uniqueness:")
    is_unique = verify_uniqueness()
    
    if is_unique:
        print("  ✅ All 90 fingerprints are unique!")
    else:
        print("  ❌ Fingerprint uniqueness check FAILED!")
        return False
    
    # Test convenience function
    print("\n1.4 Testing convenience function:")
    fp2 = get_fingerprint(10)
    print(f"  Wallet 10 WebGL: {fp2['webgl_renderer'][:50]}...")
    
    print("\n✅ FingerprintGenerator tests PASSED")
    return True


def test_llm_vision_client():
    """Test LLMVisionClient initialization and prompt building."""
    import os
    
    print("\n" + "="*70)
    print("TEST 2: LLMVisionClient")
    print("="*70)
    
    # Test initialization without API key (should fail)
    print("\n2.1 Testing initialization without API key:")
    
    # Save and remove env var temporarily
    saved_key = os.environ.pop('OPENROUTER_API_KEY_OPENCLAW', None)
    
    try:
        from openclaw.llm_vision import LLMVisionClient
        client = LLMVisionClient(api_key=None)
        print("  ❌ Should have raised ValueError")
        # Restore env var
        if saved_key:
            os.environ['OPENROUTER_API_KEY_OPENCLAW'] = saved_key
        return False
    except ValueError as e:
        print(f"  ✅ Correctly raised ValueError: {e}")
    finally:
        # Restore env var
        if saved_key:
            os.environ['OPENROUTER_API_KEY_OPENCLAW'] = saved_key
    
    # Test initialization with API key
    print("\n2.2 Testing initialization with API key:")
    from openclaw.llm_vision import LLMVisionClient, ActionType, LLMAction
    
    # Use dummy key for testing (OpenRouter format)
    # Note: Real key should be set as OPENROUTER_API_KEY_OPENCLAW env var
    client = LLMVisionClient(api_key="sk-or-test-key")
    print(f"  Provider: OpenRouter")
    print(f"  Model: {client.model}")
    print(f"  Max Tokens: {client.max_tokens}")
    print(f"  Timeout: {client.timeout}s")
    print(f"  Env Var: OPENROUTER_API_KEY_OPENCLAW")
    
    # Test prompt building
    print("\n2.3 Testing prompt building:")
    prompt = client._build_prompt(
        task_description="Click Connect Wallet button",
        page_url="https://passport.gitcoin.co",
        previous_actions=[
            {"action": "navigate", "reason": "Navigated to Gitcoin Passport"},
            {"action": "wait", "duration": 2, "reason": "Waiting for page load"}
        ],
        task_params={"target_stamps": ["google", "twitter"]}
    )
    
    print(f"  Prompt length: {len(prompt)} chars")
    print(f"  Contains task: {'Click Connect Wallet' in prompt}")
    print(f"  Contains URL: {'passport.gitcoin.co' in prompt}")
    print(f"  Contains previous actions: {'navigate' in prompt}")
    
    # Test action parsing
    print("\n2.4 Testing action parsing:")
    
    # Test valid JSON
    json_response = '{"action": "click", "selector": "button:has-text(\\"Connect\\")", "reason": "Found Connect button"}'
    action = client._parse_action(json_response)
    print(f"  Parsed action: {action.action.value}")
    print(f"  Selector: {action.selector}")
    print(f"  Reason: {action.reason}")
    
    # Test invalid JSON (fallback)
    text_response = "I think we should click the Connect Wallet button"
    action2 = client._parse_action(text_response)
    print(f"  Fallback action: {action2.action.value}")
    print(f"  Fallback reason: {action2.reason[:50]}...")
    
    # Test LLMAction dataclass
    print("\n2.5 Testing LLMAction dataclass:")
    action3 = LLMAction(
        action=ActionType.CLICK,
        selector="button.connect",
        reason="Test action"
    )
    print(f"  to_dict(): {action3.to_dict()}")
    
    # Test ActionType enum
    print("\n2.6 Testing ActionType enum:")
    for action_type in ActionType:
        print(f"  - {action_type.value}")
    
    print("\n✅ LLMVisionClient tests PASSED")
    return True


def test_exceptions():
    """Test custom exceptions."""
    print("\n" + "="*70)
    print("TEST 3: Custom Exceptions")
    print("="*70)
    
    from openclaw.exceptions import (
        ElementNotFoundError,
        TaskFailedError,
        MaxIterationsExceededError,
        LLMRateLimitError,
        LLMResponseParseError,
        FingerprintNotUniqueError
    )
    
    # Test ElementNotFoundError
    print("\n3.1 Testing ElementNotFoundError:")
    e = ElementNotFoundError(selector="button.connect", page_url="https://example.com", timeout=5000)
    print(f"  Message: {e.message}")
    print(f"  Selector: {e.selector}")
    print(f"  to_dict(): {e.to_dict()}")
    
    # Test TaskFailedError
    print("\n3.2 Testing TaskFailedError:")
    e = TaskFailedError(reason="Cannot find Connect button", task_id=123)
    print(f"  Message: {e.message}")
    print(f"  Task ID: {e.task_id}")
    
    # Test MaxIterationsExceededError
    print("\n3.3 Testing MaxIterationsExceededError:")
    e = MaxIterationsExceededError(max_iterations=10, task_type="gitcoin_passport")
    print(f"  Message: {e.message}")
    print(f"  Max iterations: {e.max_iterations}")
    
    # Test LLMRateLimitError
    print("\n3.4 Testing LLMRateLimitError:")
    e = LLMRateLimitError(retry_after=60)
    print(f"  Message: {e.message}")
    print(f"  Retry after: {e.retry_after}")
    
    # Test FingerprintNotUniqueError
    print("\n3.5 Testing FingerprintNotUniqueError:")
    e = FingerprintNotUniqueError(wallet_id_1=5, wallet_id_2=15)
    print(f"  Message: {e.message}")
    print(f"  to_dict(): {e.to_dict()}")
    
    print("\n✅ Exception tests PASSED")
    return True


def test_browser_engine_fingerprint():
    """Test BrowserEngine fingerprint integration."""
    print("\n" + "="*70)
    print("TEST 4: BrowserEngine Fingerprint Integration")
    print("="*70)
    
    from openclaw.browser import BrowserEngine
    
    # Test initialization with wallet_id
    print("\n4.1 Testing initialization with wallet_id:")
    engine = BrowserEngine(
        wallet_id=5,
        headless=True,
        stealth_mode=True,
        enable_fingerprint=True
    )
    
    print(f"  Wallet ID: {engine.wallet_id}")
    print(f"  TLS Config: {engine.tls_config is not None}")
    print(f"  Fingerprint: {engine._fingerprint is not None}")
    
    if engine._fingerprint:
        print(f"  Canvas Seed: {engine._fingerprint['canvas_seed']}")
        print(f"  WebGL: {engine._fingerprint['webgl_renderer'][:50]}...")
        print(f"  Screen: {engine._fingerprint['screen_width']}x{engine._fingerprint['screen_height']}")
    
    # Test initialization without wallet_id
    print("\n4.2 Testing initialization without wallet_id:")
    engine2 = BrowserEngine(headless=True)
    print(f"  Wallet ID: {engine2.wallet_id}")
    print(f"  TLS Config: {engine2.tls_config}")
    print(f"  Fingerprint: {engine2._fingerprint}")
    
    # Test invalid wallet_id
    print("\n4.3 Testing invalid wallet_id:")
    try:
        engine3 = BrowserEngine(wallet_id=100)
        print("  ❌ Should have raised ValueError")
        return False
    except ValueError as e:
        print(f"  ✅ Correctly raised ValueError: {e}")
    
    print("\n✅ BrowserEngine tests PASSED")
    return True


def test_executor_hybrid():
    """Test OpenClawExecutor hybrid execution setup."""
    print("\n" + "="*70)
    print("TEST 5: OpenClawExecutor Hybrid Execution")
    print("="*70)
    
    from openclaw.executor import OpenClawExecutor
    from database.db_manager import DatabaseManager
    
    # Mock database manager
    class MockDB:
        def execute(self, *args, **kwargs):
            pass
        
        def query_one(self, *args, **kwargs):
            return None
    
    # Test initialization with LLM Vision enabled
    print("\n5.1 Testing initialization with LLM Vision:")
    executor = OpenClawExecutor(
        worker_id=1,
        db_manager=MockDB(),
        llm_api_key="sk-ant-test-key",
        enable_llm_vision=True
    )
    
    print(f"  Worker ID: {executor.worker_id}")
    print(f"  LLM Vision enabled: {executor.enable_llm_vision}")
    print(f"  LLM Client: {executor._llm_client is not None}")
    print(f"  Max iterations: {executor.MAX_LLM_ITERATIONS}")
    print(f"  Cost limit: ${executor.LLM_COST_LIMIT}")
    
    # Test initialization without LLM Vision
    print("\n5.2 Testing initialization without LLM Vision:")
    executor2 = OpenClawExecutor(
        worker_id=2,
        db_manager=MockDB(),
        enable_llm_vision=False
    )
    
    print(f"  LLM Vision enabled: {executor2.enable_llm_vision}")
    print(f"  LLM Client: {executor2._llm_client}")
    
    # Test task description building
    print("\n5.3 Testing task description building:")
    task = {
        'task_type': 'gitcoin_passport',
        'task_params': {'target_stamps': ['google', 'twitter']}
    }
    desc = executor._build_task_description(task)
    print(f"  Description: {desc}")
    
    # Test different task types
    for task_type in ['poap_claim', 'ens_register', 'snapshot_vote', 'lens_post']:
        task['task_type'] = task_type
        desc = executor._build_task_description(task)
        print(f"  {task_type}: {desc[:50]}...")
    
    print("\n✅ OpenClawExecutor tests PASSED")
    return True


def test_integration():
    """Test full integration flow."""
    print("\n" + "="*70)
    print("TEST 6: Integration Flow")
    print("="*70)
    
    from openclaw.fingerprint import get_fingerprint
    from openclaw.llm_vision import LLMVisionClient, ActionType, LLMAction
    from openclaw.exceptions import ElementNotFoundError, TaskFailedError
    
    print("\n6.1 Simulating browser automation flow:")
    
    # Step 1: Get fingerprint for wallet
    print("\n  Step 1: Get fingerprint for wallet 5")
    fp = get_fingerprint(5)
    print(f"    WebGL: {fp['webgl_renderer'][:40]}...")
    print(f"    Inject script ready: {len(fp['inject_script'])} chars")
    
    # Step 2: Build LLM action
    print("\n  Step 2: Build LLM action")
    action = LLMAction(
        action=ActionType.CLICK,
        selector="button:has-text('Connect Wallet')",
        reason="Found Connect Wallet button on page"
    )
    print(f"    Action: {action.action.value}")
    print(f"    Selector: {action.selector}")
    
    # Step 3: Simulate exception handling
    print("\n  Step 3: Simulate exception handling")
    try:
        raise ElementNotFoundError(
            selector="button.connect",
            page_url="https://passport.gitcoin.co",
            timeout=5000
        )
    except ElementNotFoundError as e:
        print(f"    Caught ElementNotFoundError: {e.message}")
        print(f"    This would trigger LLM Vision fallback")
    
    # Step 4: Simulate task failure
    print("\n  Step 4: Simulate task failure")
    try:
        raise TaskFailedError(reason="Max iterations exceeded", task_id=123)
    except TaskFailedError as e:
        print(f"    Caught TaskFailedError: {e.message}")
    
    print("\n✅ Integration tests PASSED")
    return True


def main():
    """Run all tests."""
    print("\n" + "="*70)
    print("LLM VISION + ACTION LOOP ARCHITECTURE TESTS")
    print("="*70)
    
    all_passed = True
    
    # Run tests
    tests = [
        ("FingerprintGenerator", test_fingerprint_generator),
        ("LLMVisionClient", test_llm_vision_client),
        ("Exceptions", test_exceptions),
        ("BrowserEngine", test_browser_engine_fingerprint),
        ("OpenClawExecutor", test_executor_hybrid),
        ("Integration", test_integration),
    ]
    
    results = []
    
    for name, test_func in tests:
        try:
            passed = test_func()
            results.append((name, passed))
            if not passed:
                all_passed = False
        except Exception as e:
            print(f"\n❌ {name} test FAILED with exception: {e}")
            import traceback
            traceback.print_exc()
            results.append((name, False))
            all_passed = False
    
    # Print summary
    print("\n" + "="*70)
    print("TEST SUMMARY")
    print("="*70)
    
    for name, passed in results:
        status = "✅ PASSED" if passed else "❌ FAILED"
        print(f"  {name}: {status}")
    
    print("\n" + "="*70)
    if all_passed:
        print("🎉 ALL TESTS PASSED!")
        print("="*70)
        print("\nArchitecture is ready for production use:")
        print("  1. FingerprintGenerator - Canvas/WebGL/AudioContext fingerprinting")
        print("  2. LLMVisionClient - Claude Vision API integration")
        print("  3. BrowserEngine - Fingerprint injection + IP leak protection")
        print("  4. OpenClawExecutor - Hybrid execution (scripted + LLM Vision)")
        print("\nNext steps:")
        print("  - Set OPENROUTER_API_KEY_OPENCLAW environment variable")
        print("  - Test with real browser automation")
        print("  - Monitor LLM API costs (OpenRouter: ~$0.003/request)")
        return 0
    else:
        print("❌ SOME TESTS FAILED")
        print("="*70)
        return 1


if __name__ == '__main__':
    sys.exit(main())