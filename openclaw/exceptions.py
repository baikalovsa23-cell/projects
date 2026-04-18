#!/usr/bin/env python3
"""
OpenClaw Exceptions — Custom Exceptions for Browser Automation
===============================================================

Custom exceptions for OpenClaw browser automation tasks.

Author: System Architect + Senior Developer
Created: 2026-03-06
"""

from typing import Optional, Dict, Any


class OpenClawError(Exception):
    """Base exception for OpenClaw errors."""
    
    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        self.message = message
        self.details = details or {}
        super().__init__(self.message)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert exception to dictionary for JSON response."""
        return {
            "error": self.__class__.__name__,
            "message": self.message,
            "details": self.details
        }


# =============================================================================
# ELEMENT NOT FOUND ERRORS
# =============================================================================

class ElementNotFoundError(OpenClawError):
    """
    Element not found on page.
    
    Used when a CSS selector or element cannot be found.
    Triggers LLM Vision fallback.
    """
    
    def __init__(self, selector: str, page_url: str = "", timeout: int = 0):
        message = f"Element not found: {selector}"
        if page_url:
            message += f" on page {page_url}"
        if timeout:
            message += f" (timeout: {timeout}ms)"
        
        super().__init__(
            message=message,
            details={
                "selector": selector,
                "page_url": page_url,
                "timeout": timeout
            }
        )
        self.selector = selector
        self.page_url = page_url
        self.timeout = timeout


class MultipleElementsFoundError(OpenClawError):
    """
    Multiple elements found when expecting one.
    """
    
    def __init__(self, selector: str, count: int):
        super().__init__(
            message=f"Expected 1 element, found {count}: {selector}",
            details={"selector": selector, "count": count}
        )
        self.selector = selector
        self.count = count


# =============================================================================
# TASK EXECUTION ERRORS
# =============================================================================

class TaskExecutionError(OpenClawError):
    """
    Base class for task execution errors.
    """
    pass


class TaskFailedError(TaskExecutionError):
    """
    Task cannot be completed.
    
    Used when LLM returns 'fail' action or max retries exceeded.
    """
    
    def __init__(self, reason: str, task_id: Optional[int] = None):
        super().__init__(
            message=f"Task failed: {reason}",
            details={"reason": reason, "task_id": task_id}
        )
        self.reason = reason
        self.task_id = task_id


class MaxIterationsExceededError(TaskExecutionError):
    """
    Maximum LLM iterations exceeded.
    
    Used when LLM cannot complete task in max_iterations.
    """
    
    def __init__(self, max_iterations: int, task_type: str = ""):
        message = f"Max iterations ({max_iterations}) exceeded"
        if task_type:
            message += f" for task: {task_type}"
        
        super().__init__(
            message=message,
            details={"max_iterations": max_iterations, "task_type": task_type}
        )
        self.max_iterations = max_iterations
        self.task_type = task_type


class TaskTimeoutError(TaskExecutionError):
    """
    Task execution timeout.
    """
    
    def __init__(self, timeout_seconds: int, task_type: str = ""):
        message = f"Task timeout after {timeout_seconds}s"
        if task_type:
            message += f" for task: {task_type}"
        
        super().__init__(
            message=message,
            details={"timeout_seconds": timeout_seconds, "task_type": task_type}
        )
        self.timeout_seconds = timeout_seconds


# =============================================================================
# BROWSER ERRORS
# =============================================================================

class BrowserError(OpenClawError):
    """Base class for browser errors."""
    pass


class BrowserLaunchError(BrowserError):
    """
    Failed to launch browser.
    """
    
    def __init__(self, reason: str):
        super().__init__(
            message=f"Failed to launch browser: {reason}",
            details={"reason": reason}
        )


class PageLoadError(BrowserError):
    """
    Page failed to load.
    """
    
    def __init__(self, url: str, error: str = ""):
        message = f"Failed to load page: {url}"
        if error:
            message += f" ({error})"
        
        super().__init__(
            message=message,
            details={"url": url, "error": error}
        )
        self.url = url


class NavigationError(BrowserError):
    """
    Navigation failed.
    """
    
    def __init__(self, from_url: str, to_url: str, reason: str = ""):
        message = f"Navigation failed: {from_url} → {to_url}"
        if reason:
            message += f" ({reason})"
        
        super().__init__(
            message=message,
            details={"from_url": from_url, "to_url": to_url, "reason": reason}
        )


class ScreenshotError(BrowserError):
    """
    Failed to take screenshot.
    """
    
    def __init__(self, reason: str):
        super().__init__(
            message=f"Failed to take screenshot: {reason}",
            details={"reason": reason}
        )


# =============================================================================
# LLM ERRORS
# =============================================================================

class LLMError(OpenClawError):
    """Base class for LLM errors."""
    pass


class LLMRateLimitError(LLMError):
    """
    LLM API rate limit exceeded.
    """
    
    def __init__(self, retry_after: Optional[int] = None):
        message = "LLM API rate limit exceeded"
        if retry_after:
            message += f" (retry after {retry_after}s)"
        
        super().__init__(
            message=message,
            details={"retry_after": retry_after}
        )
        self.retry_after = retry_after


class LLMResponseParseError(LLMError):
    """
    Failed to parse LLM response.
    """
    
    def __init__(self, raw_response: str, expected_format: str = "JSON"):
        super().__init__(
            message=f"Failed to parse LLM response as {expected_format}",
            details={"raw_response": raw_response[:500], "expected_format": expected_format}
        )
        self.raw_response = raw_response


class LLMAPIError(LLMError):
    """
    LLM API error.
    """
    
    def __init__(self, status_code: int, error_message: str):
        super().__init__(
            message=f"LLM API error ({status_code}): {error_message}",
            details={"status_code": status_code, "error_message": error_message}
        )
        self.status_code = status_code


class LLMCostLimitExceededError(LLMError):
    """
    LLM cost limit exceeded.
    """
    
    def __init__(self, current_cost: float, limit: float):
        super().__init__(
            message=f"LLM cost limit exceeded: ${current_cost:.2f} > ${limit:.2f}",
            details={"current_cost": current_cost, "limit": limit}
        )
        self.current_cost = current_cost
        self.limit = limit


# =============================================================================
# AUTHENTICATION ERRORS
# =============================================================================

class AuthenticationError(OpenClawError):
    """Base class for authentication errors."""
    pass


class OAuthError(AuthenticationError):
    """
    OAuth authentication failed.
    """
    
    def __init__(self, provider: str, reason: str = ""):
        message = f"OAuth failed for {provider}"
        if reason:
            message += f": {reason}"
        
        super().__init__(
            message=message,
            details={"provider": provider, "reason": reason}
        )
        self.provider = provider


class WalletConnectionError(AuthenticationError):
    """
    Wallet connection failed.
    """
    
    def __init__(self, wallet_address: str, reason: str = ""):
        message = f"Wallet connection failed: {wallet_address[:10]}..."
        if reason:
            message += f" ({reason})"
        
        super().__init__(
            message=message,
            details={"wallet_address": wallet_address, "reason": reason}
        )


# =============================================================================
# VALIDATION ERRORS
# =============================================================================

class ValidationError(OpenClawError):
    """Base class for validation errors."""
    pass


class InvalidSelectorError(ValidationError):
    """
    Invalid CSS selector.
    """
    
    def __init__(self, selector: str, reason: str = ""):
        message = f"Invalid selector: {selector}"
        if reason:
            message += f" ({reason})"
        
        super().__init__(
            message=message,
            details={"selector": selector, "reason": reason}
        )


class InvalidActionError(ValidationError):
    """
    Invalid action from LLM.
    """
    
    def __init__(self, action: str, valid_actions: list):
        super().__init__(
            message=f"Invalid action: {action}. Valid actions: {valid_actions}",
            details={"action": action, "valid_actions": valid_actions}
        )


# =============================================================================
# PROXY ERRORS
# =============================================================================

class ProxyError(OpenClawError):
    """Base class for proxy errors."""
    pass


class ProxyConnectionError(ProxyError):
    """
    Proxy connection failed.
    """
    
    def __init__(self, proxy_url: str, reason: str = ""):
        # Hide credentials in URL
        safe_url = proxy_url.split('@')[0] + '@***' if '@' in proxy_url else proxy_url
        
        message = f"Proxy connection failed: {safe_url}"
        if reason:
            message += f" ({reason})"
        
        super().__init__(
            message=message,
            details={"proxy_url": safe_url, "reason": reason}
        )


class ProxyBlockedError(ProxyError):
    """
    Proxy blocked by target site.
    """
    
    def __init__(self, proxy_url: str, site: str):
        safe_url = proxy_url.split('@')[0] + '@***' if '@' in proxy_url else proxy_url
        
        super().__init__(
            message=f"Proxy blocked by {site}",
            details={"proxy_url": safe_url, "site": site}
        )


# =============================================================================
# FINGERPRINT ERRORS
# =============================================================================

class FingerprintError(OpenClawError):
    """Base class for fingerprint errors."""
    pass


class FingerprintNotUniqueError(FingerprintError):
    """
    Fingerprint collision detected.
    """
    
    def __init__(self, wallet_id_1: int, wallet_id_2: int):
        super().__init__(
            message=f"Fingerprint collision: wallet {wallet_id_1} and {wallet_id_2}",
            details={"wallet_id_1": wallet_id_1, "wallet_id_2": wallet_id_2}
        )


class FingerprintInjectionError(FingerprintError):
    """
    Failed to inject fingerprint script.
    """
    
    def __init__(self, wallet_id: int, reason: str = ""):
        message = f"Failed to inject fingerprint for wallet {wallet_id}"
        if reason:
            message += f": {reason}"
        
        super().__init__(
            message=message,
            details={"wallet_id": wallet_id, "reason": reason}
        )
