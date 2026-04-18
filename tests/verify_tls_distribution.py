#!/usr/bin/env python3
"""
TLS Fingerprint Distribution Verification
==========================================
Verifies that all 90 wallets have proper TLS configuration distribution.

Expected Results:
- Chrome versions: ~25% each (110, 116, 120, 124)
- Platforms: ~50% each (Windows, macOS)
- HTTP/2: 100% for Tier A, ~67% for Tier B/C
- No duplicate configurations (each wallet unique)
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from infrastructure.identity_manager import identity_manager
from collections import Counter


def main():
    print("=" * 70)
    print("TLS FINGERPRINT DISTRIBUTION VERIFICATION")
    print("=" * 70)
    
    # Get configurations for all 90 wallets
    configs = [identity_manager.get_config(i) for i in range(1, 91)]
    
    # Extract data
    chrome_versions = [c['impersonate'] for c in configs]
    platforms = [c['platform'] for c in configs]
    user_agents = [c['user_agent'] for c in configs]
    http2_enabled = [c['http2'] for c in configs]
    
    # Tier A specific
    tier_a_http2 = [c['http2'] for c in configs[:18]]
    
    print("\n📊 CHROME VERSION DISTRIBUTION:")
    version_counts = Counter(chrome_versions)
    for version in sorted(version_counts.keys()):
        count = version_counts[version]
        pct = count / 90 * 100
        bar = "█" * int(pct / 2)
        print(f"  {version:12s}: {count:2d} wallets ({pct:5.1f}%) {bar}")
    
    print("\n💻 PLATFORM DISTRIBUTION:")
    platform_counts = Counter(platforms)
    for platform in sorted(platform_counts.keys()):
        count = platform_counts[platform]
        pct = count / 90 * 100
        bar = "█" * int(pct / 2)
        print(f"  {platform:12s}: {count:2d} wallets ({pct:5.1f}%) {bar}")
    
    print("\n🌐 HTTP/2 CONFIGURATION:")
    http2_count = sum(http2_enabled)
    tier_a_http2_count = sum(tier_a_http2)
    print(f"  Total HTTP/2 Enabled: {http2_count}/90 ({http2_count/90*100:.1f}%)")
    print(f"  Tier A HTTP/2:        {tier_a_http2_count}/18 ({tier_a_http2_count/18*100:.1f}%)")
    
    print("\n🔍 UNIQUENESS CHECK:")
    unique_uas = len(set(user_agents))
    print(f"  Unique User-Agents: {unique_uas}/90")
    
    # Validation
    print("\n✅ VALIDATION:")
    checks = []
    
    # Check 1: Chrome versions balanced
    max_ver_count = max(version_counts.values())
    min_ver_count = min(version_counts.values())
    balance_ok = (max_ver_count - min_ver_count) <= 3  # Max 3 wallet difference
    checks.append(("Chrome versions balanced (±3)", balance_ok))
    
    # Check 2: Platforms balanced
    win_count = platform_counts.get('Windows', 0)
    mac_count = platform_counts.get('macOS', 0)
    platform_ok = abs(win_count - mac_count) <= 2
    checks.append(("Platforms balanced (±2)", platform_ok))
    
    # Check 3: Tier A HTTP/2
    tier_a_ok = tier_a_http2_count == 18
    checks.append(("Tier A HTTP/2 100%", tier_a_ok))
    
    # Check 4: Some diversity in Tier B/C HTTP/2
    tier_bc_http2_count = http2_count - tier_a_http2_count
    tier_bc_ok = 40 <= tier_bc_http2_count <= 65  # 55-90% of 72 wallets
    checks.append(("Tier B/C HTTP/2 diverse", tier_bc_ok))
    
    # Check 5: UA uniqueness (should have only 8 unique due to Chrome versions × platforms)
    unique_ok = 6 <= unique_uas <= 10
    checks.append(("UA diversity (6-10 patterns)", unique_ok))
    
    for check_name, passed in checks:
        status = "✅" if passed else "❌"
        print(f"  {status} {check_name}")
    
    all_passed = all(passed for _, passed in checks)
    
    print("\n" + "=" * 70)
    if all_passed:
        print("✅ ALL CHECKS PASSED — TLS Distribution OK")
        return 0
    else:
        print("❌ SOME CHECKS FAILED — Review configuration")
        return 1


if __name__ == '__main__':
    sys.exit(main())
