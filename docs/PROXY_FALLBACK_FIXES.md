# Proxy Fallback Security Fixes

**Date:** 2026-02-26  
**Priority:** CRITICAL  
**Status:** ✅ COMPLETED

## Executive Summary

Fixed 3 critical proxy fallback vulnerabilities that could expose VPS IP addresses and compromise anti-Sybil protection for all 90 wallets. All direct connection fallbacks have been eliminated and replaced with immediate exception raising.

## Issues Fixed

### 1. ❌ activity/executor.py:273-274 → ✅ FIXED

**Before (DANGEROUS):**
```python
except ValueError as e:
    logger.error(f"Failed to get proxy for wallet {wallet_id}: {e}")
    logger.warning("Falling back to direct connection (no proxy, no TLS fingerprint)")
    w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={'timeout': 60}))
```

**After (SECURE):**
```python
except ValueError as e:
    logger.error(f"Failed to get proxy for wallet {wallet_id}: {e}")
    raise ProxyRequiredError(
        f"Cannot execute transaction without proxy for wallet {wallet_id}. "
        f"Direct connections forbidden for anti-Sybil protection. Error: {e}"
    )
```

**Impact:** Any transaction attempt without a valid proxy now fails immediately with a clear error message instead of silently falling back to VPS IP.

---

### 2. ❌ worker/api.py:224-229 → ✅ FIXED

**Before (DANGEROUS):**
```python
except ValueError as e:
    logger.error(f"Failed to get proxy for wallet {wallet_id}: {e}")
    logger.warning("Falling back to direct connection (no proxy)")
    w3 = Web3(Web3.HTTPProvider(rpc_url))
else:
    # No wallet_id provided - use direct connection
    w3 = Web3(Web3.HTTPProvider(rpc_url))
```

**After (SECURE):**
```python
except ValueError as e:
    logger.error(f"Failed to get proxy for wallet {wallet_id}: {e}")
    raise ProxyRequiredError(
        f"Cannot execute transaction without proxy for wallet {wallet_id}. "
        f"All transactions must use wallet-specific proxy. Error: {e}"
    )
else:
    # No wallet_id provided - this should not happen in production
    raise ProxyRequiredError(
        "wallet_id is required for all withdrawal operations. "
        "Direct connections are forbidden."
    )
```

**Impact:** Withdrawal operations, which are the most critical security-wise, now enforce strict proxy requirements with no fallback path.

---

### 3. ❌ openclaw/executor.py:462-464 → ✅ FIXED

**Before (DANGEROUS):**
```python
if not proxy:
    logger.warning(f"⚠️ No proxy assigned to wallet {wallet_id}, using direct connection")
    return {}
```

**After (SECURE):**
```python
if not proxy:
    raise ProxyRequiredError(
        f"Wallet {wallet_id} has no proxy assigned. "
        f"OpenClaw tasks require proxy for anti-Sybil protection. "
        f"Check wallets.proxy_id foreign key in database."
    )
```

**Impact:** OpenClaw browser automation tasks (Gitcoin, POAP, ENS, etc.) now enforce proxy requirement, preventing identity leakage through direct browser connections.

---

## New Security Infrastructure

### activity/exceptions.py (NEW FILE)

Created custom exception class for better error handling:

```python
class ProxyRequiredError(Exception):
    """
    Raised when a proxy is required but not available or failed.
    
    This exception is critical for anti-Sybil protection. All wallet transactions
    must use wallet-specific proxies to avoid IP-based clustering detection.
    
    Direct connections are FORBIDDEN as they would expose the VPS IP and link
    all 90 wallets together, destroying the anti-Sybil protection strategy.
    """
    pass
```

**Usage across modules:**
- `activity/executor.py`: Imported and used for transaction execution
- `worker/api.py`: Imported and used for withdrawal operations
- `openclaw/executor.py`: Imported and used for browser automation

---

## Verification

### Search Results for Remaining Fallbacks

✅ **No fallback patterns found:**
- Search: `(?i)(fallback|fall.*back).*connection` → **0 results**
- Search: `(?i)direct.*connection.*no.*proxy` → **0 results**
- Search: `(?i)use.*direct.*connection` → **1 result** (only in docstring, now updated)

✅ **All "no proxy" references are now security-positive:**
- Error messages from `ProxyRequiredError` (raises exception)
- Validation logic in `proxy_manager.py` (raises exception)
- Database field names (neutral)
- Wallet generator validation (raises exception)

### Remaining Safe Direct Connection

**activity/tx_types.py:635** - Test code only (CLI `--test` mode):
```python
# Example test - NOT used in production
w3 = Web3(Web3.HTTPProvider('https://arb1.arbitrum.io/rpc'))
```

This is acceptable as it's only used in development/testing, not in production wallet operations.

---

## Impact Assessment

### Before Fixes (CRITICAL RISK):
- ❌ Proxy failure → Silent fallback to VPS IP
- ❌ All 90 wallets could be linked by IP address
- ❌ Anti-Sybil protection completely bypassed
- ❌ Single network issue → entire farm compromised
- ❌ No alerts when proxy failures occur

### After Fixes (SECURE):
- ✅ Proxy failure → Immediate exception with clear error
- ✅ No fallback path to direct connections
- ✅ Anti-Sybil protection enforced at code level
- ✅ Proxy issues caught early before transaction broadcast
- ✅ Clear error messages for debugging
- ✅ Human-in-the-loop for proxy configuration issues

---

## Testing Strategy

### Unit Tests (Recommended):
```python
def test_executor_proxy_required():
    """Test that executor raises exception without proxy"""
    executor = TransactionExecutor(db_manager, proxy_manager)
    
    with pytest.raises(ProxyRequiredError):
        executor._get_web3(chain='arbitrum', wallet_id=None)

def test_withdrawal_proxy_required():
    """Test that withdrawal raises exception without wallet_id"""
    with pytest.raises(ProxyRequiredError):
        execute_withdrawal_transaction(
            private_key='0x...',
            destination='0x...',
            amount_wei=1000000,
            chain='base',
            wallet_id=None  # Should raise
        )
```

### Integration Tests (Recommended):
1. **Test proxy failure handling:**
   - Disable proxy for test wallet
   - Attempt transaction
   - Verify ProxyRequiredError is raised
   - Verify NO transaction was broadcast to chain

2. **Test 90-wallet isolation:**
   - Run transaction on wallet A
   - Run transaction on wallet B
   - Verify different source IPs in RPC logs
   - Verify no IP clustering

---

## Deployment Checklist

- [x] Create `activity/exceptions.py` with `ProxyRequiredError`
- [x] Fix `activity/executor.py` proxy fallback
- [x] Fix `worker/api.py` proxy fallback  
- [x] Fix `openclaw/executor.py` empty proxy return
- [x] Update docstrings to reflect new security requirements
- [x] Verify no remaining fallback patterns in codebase
- [ ] Deploy to Master Node
- [ ] Deploy to Worker 1
- [ ] Deploy to Worker 2
- [ ] Deploy to Worker 3
- [ ] Test proxy failure behavior in staging
- [ ] Monitor first 24h for ProxyRequiredError alerts

---

## Monitoring Recommendations

### Telegram Alerts (CRITICAL):
Monitor for `ProxyRequiredError` exceptions and alert immediately:

```python
# In notifications/telegram_bot.py
if isinstance(error, ProxyRequiredError):
    send_critical_alert(
        f"🚨 PROXY FAILURE: Wallet {wallet_id}\n"
        f"Error: {error}\n"
        f"Action: Check proxy_pool table and wallet assignment"
    )
```

### Grafana Dashboard:
- **Metric:** `proxy_failures_total` (counter)
- **Threshold:** Alert if > 0 in 1 hour
- **Action:** Investigate proxy pool health

### Log Analysis:
```bash
# Check for proxy failures
grep -r "ProxyRequiredError" /opt/farming/logs/

# Verify all transactions use proxies
grep -r "Using proxy for transaction" /opt/farming/logs/ | wc -l
# Should equal total transactions count
```

---

## Recovery Procedures

### If ProxyRequiredError Occurs in Production:

1. **Immediate:** Transaction is automatically rejected (no broadcast)
2. **Check:** Wallet's proxy assignment in database:
   ```sql
   SELECT w.id, w.address, w.proxy_id, p.is_active, p.country_code
   FROM wallets w
   LEFT JOIN proxy_pool p ON w.proxy_id = p.id
   WHERE w.id = <wallet_id>;
   ```

3. **Fix:** Reassign proxy if missing/inactive:
   ```sql
   UPDATE wallets 
   SET proxy_id = (SELECT id FROM proxy_pool WHERE is_active=true LIMIT 1)
   WHERE id = <wallet_id>;
   ```

4. **Verify:** Test proxy connection:
   ```bash
   curl --proxy socks5://user:pass@proxy:port https://api.ipify.org
   ```

5. **Retry:** Transaction will automatically retry with working proxy

---

## Conclusion

All proxy fallback vulnerabilities have been eliminated. The system now enforces **strict proxy requirements** at the code level, preventing the most critical anti-Sybil protection bypass.

**Risk Reduction:**
- Before: 🔴 CRITICAL (single proxy failure = farm compromise)
- After: 🟢 SECURE (proxy failures caught early, no IP exposure)

**Next Steps:**
1. Deploy fixes to all nodes
2. Monitor for ProxyRequiredError in logs (indicates proxy pool issues)
3. Add unit tests for proxy requirement enforcement
4. Document proxy pool maintenance procedures
