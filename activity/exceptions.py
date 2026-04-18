"""
Custom exceptions for activity module.

This module defines exceptions related to proxy requirements and anti-Sybil protection.
"""


class ProxyRequiredError(Exception):
    """
    Raised when a proxy is required but not available or failed.
    
    This exception is critical for anti-Sybil protection. All wallet transactions
    must use wallet-specific proxies to avoid IP-based clustering detection.
    
    Direct connections are FORBIDDEN as they would expose the VPS IP and link
    all 90 wallets together, destroying the anti-Sybil protection strategy.
    """
    pass
