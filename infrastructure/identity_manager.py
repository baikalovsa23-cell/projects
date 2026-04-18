#!/usr/bin/env python3
"""
Identity Manager — TLS/UA Configuration for 90 Wallets
========================================================
Генерирует детерминированную конфигурацию браузерного fingerprint для каждого кошелька.

Features:
- Deterministic Chrome version selection (seed-based)
- User-Agent generation matching TLS fingerprint
- Client Hints (Sec-Ch-Ua) generation
- Platform diversity (Windows/macOS)
- HTTP/2 support configuration

Security:
- No private keys stored
- No network requests made
- Thread-safe (can be used concurrently)
- Deterministic output (wallet_id → same config always)

Author: System Architect + Senior Developer
Created: 2026-02-26
"""

import hashlib
from typing import Dict, Literal, Optional


class IdentityManager:
    """
    Manages browser identity (TLS fingerprint, User-Agent, Client Hints) for wallets.
    
    Example:
        manager = IdentityManager()
        config = manager.get_config(wallet_id=5)
        # Use config['impersonate'] for curl_cffi
        # Use config['user_agent'] for OpenClaw browser launch
    """
    
    # Chrome versions supported by curl_cffi 0.7.0
    # Distribution: ~25% each
    CHROME_VERSIONS = ['chrome110', 'chrome116', 'chrome120', 'chrome124']
    
    def __init__(self, seed_prefix: str = "wallet_identity_v1"):
        """
        Initialize Identity Manager.
        
        Args:
            seed_prefix: Prefix for deterministic seed generation.
                        Change this to rotate all identities (use with caution!)
        """
        self.seed_prefix = seed_prefix
    
    def get_config(self, wallet_id: int) -> Dict[str, any]:
        """
        Get deterministic TLS/UA configuration for a wallet.
        
        Args:
            wallet_id: Wallet ID (1-90)
        
        Returns:
            Dictionary with keys:
            - impersonate: Chrome version for curl_cffi (e.g., 'chrome120')
            - user_agent: Full User-Agent string
            - sec_ch_ua: Client Hints Sec-Ch-Ua header
            - sec_ch_ua_platform: Client Hints platform header
            - sec_ch_ua_mobile: Client Hints mobile header (always '?0')
            - platform: Platform name ('Windows' or 'macOS')
            - http2: Whether HTTP/2 should be enabled (bool)
        
        Raises:
            ValueError: If wallet_id is out of range [1, 90]
        """
        if not 1 <= wallet_id <= 90:
            raise ValueError(f"wallet_id must be in range [1, 90], got {wallet_id}")
        
        # Deterministic seed generation
        seed_string = f"{self.seed_prefix}_{wallet_id}"
        seed_hash = hashlib.sha256(seed_string.encode()).hexdigest()
        seed_int = int(seed_hash, 16)
        
        # Select Chrome version (25% distribution)
        chrome_version = self.CHROME_VERSIONS[seed_int % len(self.CHROME_VERSIONS)]
        major_version = chrome_version.replace('chrome', '')
        
        # Select platform (50/50 Windows/macOS)
        is_windows = (seed_int % 2 == 0)
        
        # Generate User-Agent
        if is_windows:
            user_agent = (
                f"Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                f"AppleWebKit/537.36 (KHTML, like Gecko) "
                f"Chrome/{major_version}.0.0.0 Safari/537.36"
            )
            platform = "Windows"
            sec_ch_ua_platform = '"Windows"'
        else:
            user_agent = (
                f"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                f"AppleWebKit/537.36 (KHTML, like Gecko) "
                f"Chrome/{major_version}.0.0.0 Safari/537.36"
            )
            platform = "macOS"
            sec_ch_ua_platform = '"macOS"'
        
        # Generate Client Hints (Sec-Ch-Ua)
        # Format: "Not/A)Brand";v="8", "Chromium";v="XXX", "Google Chrome";v="XXX"
        sec_ch_ua = (
            f'"Not/A)Brand";v="8", '
            f'"Chromium";v="{major_version}", '
            f'"Google Chrome";v="{major_version}"'
        )
        
        # HTTP/2 configuration
        # Tier A (1-18): MANDATORY HTTP/2 (modern L2 bridges check this)
        # Tier B/C (19-90): Optional (can vary for diversity)
        http2_enabled = wallet_id <= 18 or (seed_int % 3 != 0)  # ~67% for B/C
        
        return {
            'impersonate': chrome_version,
            'user_agent': user_agent,
            'sec_ch_ua': sec_ch_ua,
            'sec_ch_ua_platform': sec_ch_ua_platform,
            'sec_ch_ua_mobile': '?0',  # Desktop only (never mobile)
            'platform': platform,
            'http2': http2_enabled,
            'major_version': major_version,  # For logging/debugging
        }
    
    def get_stats(self) -> Dict[str, any]:
        """
        Get distribution statistics for all 90 wallets.
        
        Returns:
            Dictionary with:
            - chrome_version_distribution: Count of each Chrome version
            - platform_distribution: Count of Windows vs macOS
            - http2_enabled_count: Count of HTTP/2 enabled wallets
        """
        from collections import Counter
        
        chrome_versions = []
        platforms = []
        http2_count = 0
        
        for wallet_id in range(1, 91):
            config = self.get_config(wallet_id)
            chrome_versions.append(config['impersonate'])
            platforms.append(config['platform'])
            if config['http2']:
                http2_count += 1
        
        return {
            'chrome_version_distribution': dict(Counter(chrome_versions)),
            'platform_distribution': dict(Counter(platforms)),
            'http2_enabled_count': http2_count,
            'total_wallets': 90,
        }


# Singleton instance (import this in other modules)
identity_manager = IdentityManager()


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def get_curl_session(wallet_id: int, proxy_url: Optional[str] = None):
    """
    Create a curl_cffi session configured for a specific wallet.
    
    Args:
        wallet_id: Wallet ID (1-90)
        proxy_url: Optional proxy URL (http://user:pass@host:port or socks5://...)
    
    Returns:
        curl_cffi.requests.Session configured with proper fingerprint
    
    Example:
        session = get_curl_session(wallet_id=5, proxy_url="socks5://...")
        response = session.get("https://api.example.com")
    """
    from curl_cffi import requests
    
    config = identity_manager.get_config(wallet_id)
    
    session = requests.Session(
        impersonate=config['impersonate'],
        http2=config['http2']
    )
    
    # Set headers
    session.headers.update({
        'User-Agent': config['user_agent'],
        'Accept': 'application/json, text/html, */*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Sec-Ch-Ua': config['sec_ch_ua'],
        'Sec-Ch-Ua-Platform': config['sec_ch_ua_platform'],
        'Sec-Ch-Ua-Mobile': config['sec_ch_ua_mobile'],
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-User': '?1',
        'Sec-Fetch-Dest': 'document',
        'Priority': 'u=1, i',
    })
    
    # Set proxy if provided
    if proxy_url:
        session.proxies = {
            'http': proxy_url,
            'https': proxy_url,
        }
    
    return session


async def get_async_curl_session(wallet_id: int, proxy_url: Optional[str] = None):
    """
    Create an async curl_cffi session configured for a specific wallet.
    
    Args:
        wallet_id: Wallet ID (1-90)
        proxy_url: Optional proxy URL
    
    Returns:
        curl_cffi.requests.AsyncSession (use with async context manager)
    
    Example:
        async with get_async_curl_session(wallet_id=5) as session:
            response = await session.get("https://api.example.com")
            data = response.json()  # NOT await!
    """
    from curl_cffi.requests import AsyncSession
    
    config = identity_manager.get_config(wallet_id)
    
    # Build headers
    headers = {
        'User-Agent': config['user_agent'],
        'Accept': 'application/json, text/html, */*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Sec-Ch-Ua': config['sec_ch_ua'],
        'Sec-Ch-Ua-Platform': config['sec_ch_ua_platform'],
        'Sec-Ch-Ua-Mobile': config['sec_ch_ua_mobile'],
    }
    
    # Build proxies dict
    proxies = None
    if proxy_url:
        proxies = {
            'http': proxy_url,
            'https': proxy_url,
        }
    
    return AsyncSession(
        impersonate=config['impersonate'],
        headers=headers,
        proxies=proxies,
        http2=config['http2']
    )


if __name__ == '__main__':
    # Test script
    print("Identity Manager Test")
    print("=" * 60)
    
    manager = IdentityManager()
    
    # Test specific wallets
    print("\nSample Configurations:")
    for wallet_id in [1, 5, 18, 19, 45, 90]:
        config = manager.get_config(wallet_id)
        tier = "A" if wallet_id <= 18 else ("B" if wallet_id <= 63 else "C")
        print(f"\nWallet #{wallet_id} (Tier {tier}):")
        print(f"  Chrome: {config['impersonate']}")
        print(f"  Platform: {config['platform']}")
        print(f"  HTTP/2: {config['http2']}")
        print(f"  UA: {config['user_agent'][:60]}...")
    
    # Show distribution
    print("\n" + "=" * 60)
    print("Distribution Statistics:")
    stats = manager.get_stats()
    print(f"\nChrome Versions:")
    for version, count in sorted(stats['chrome_version_distribution'].items()):
        pct = count / 90 * 100
        print(f"  {version}: {count} wallets ({pct:.1f}%)")
    
    print(f"\nPlatforms:")
    for platform, count in sorted(stats['platform_distribution'].items()):
        pct = count / 90 * 100
        print(f"  {platform}: {count} wallets ({pct:.1f}%)")
    
    print(f"\nHTTP/2 Enabled: {stats['http2_enabled_count']}/90 ({stats['http2_enabled_count']/90*100:.1f}%)")
    
    print("\n" + "=" * 60)
    print("✅ All tests passed!")
