#!/bin/bash
# ============================================================================
# curl-cffi Installation Script for TLS Fingerprinting Migration
# ============================================================================
# 
# Purpose: Install curl-cffi on all nodes (Master + Workers 1-3)
# Requirements: libcurl with HTTP/2 support, Python 3.11+
# 
# Usage:
#   chmod +x install_curl_cffi.sh
#   ./install_curl_cffi.sh
# 
# Author: Senior Developer
# Created: 2026-02-26
# ============================================================================

set -e  # Exit on error

echo "=========================================================================="
echo "curl-cffi Installation для TLS Fingerprinting Migration v2.2"
echo "=========================================================================="

# Detect node type
if [ -f "/etc/hostname" ]; then
    HOSTNAME=$(cat /etc/hostname)
    echo "🖥️  Node: $HOSTNAME"
else
    echo "⚠️  Cannot detect hostname"
fi

# Check Python version
echo ""
echo "1️⃣  Checking Python version..."
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)

echo "   Python version: $PYTHON_VERSION"

if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 11 ]); then
    echo "   ❌ ERROR: Python 3.11+ required, found $PYTHON_VERSION"
    exit 1
else
    echo "   ✅ Python version OK"
fi

# Install system dependencies
echo ""
echo "2️⃣  Installing system dependencies (libcurl with HTTP/2)..."
apt-get update -qq
apt-get install -y -qq libcurl4-openssl-dev curl build-essential >/dev/null 2>&1

# Verify HTTP/2 support
echo ""
echo "3️⃣  Verifying libcurl HTTP/2 support..."
if curl --version | grep -q "HTTP2"; then
    echo "   ✅ libcurl has HTTP/2 support"
else
    echo "   ❌ ERROR: libcurl does not have HTTP/2 support"
    echo "   Trying to install libcurl4..."
    apt-get install -y libcurl4 >/dev/null 2>&1
    
    if curl --version | grep -q "HTTP2"; then
        echo "   ✅ libcurl HTTP/2 now available"
    else
        echo "   ❌ FAILED: Cannot enable HTTP/2 support"
        exit 1
    fi
fi

# Install curl-cffi
echo ""
echo "4️⃣  Installing curl-cffi==0.7.0..."
pip3 install --quiet --break-system-packages curl-cffi==0.7.0

# Verify installation
echo ""
echo "5️⃣  Verifying curl-cffi installation..."
CFFI_VERSION=$(python3 -c "from curl_cffi import requests; print(requests.__version__)" 2>&1)

if [ $? -eq 0 ]; then
    echo "   ✅ curl-cffi installed: version $CFFI_VERSION"
else
    echo "   ❌ FAILED: curl-cffi import error"
    exit 1
fi

# Test Chrome impersonation
echo ""
echo "6️⃣  Testing Chrome impersonation..."
python3 -c "
from curl_cffi import requests
session = requests.Session(impersonate='chrome120')
print('   ✅ Chrome impersonation test passed')
" 2>&1

if [ $? -ne 0 ]; then
    echo "   ❌ Chrome impersonation test FAILED"
    exit 1
fi

# Optional: Test with Identity Manager (if in project directory)
if [ -f "infrastructure/identity_manager.py" ]; then
    echo ""
    echo "7️⃣  Testing IdentityManager integration..."
    python3 -c "
import sys
sys.path.insert(0, '.')
from infrastructure.identity_manager import identity_manager
config = identity_manager.get_config(5)
print(f'   ✅ IdentityManager OK: {config[\"impersonate\"]} on {config[\"platform\"]}')
" 2>&1
    
    if [ $? -ne 0 ]; then
        echo "   ⚠️  IdentityManager test FAILED (may be OK if not in project dir)"
    fi
fi

# Final summary
echo ""
echo "=========================================================================="
echo "✅ INSTALLATION COMPLETE"
echo "=========================================================================="
echo ""
echo "📋 Summary:"
echo "   - curl-cffi version: $CFFI_VERSION"
echo "   - HTTP/2 support: ✅ Enabled"
echo "   - Chrome impersonation: ✅ Working"
echo ""
echo "🚀 Next steps:"
echo "   1. Run verification test: python3 tests/verify_tls_distribution.py"
echo "   2. Run sync test: python3 tests/test_tier_a_sync.py"
echo "   3. Test RPC connection with wallet_id parameter"
echo "   4. Deploy to other nodes (if Master) or restart services (if Worker)"
echo ""
echo "📖 Documentation:"
echo "   - Architecture: plans/TLS_FINGERPRINTING_ARCHITECTURE.md"
echo "   - Implementation: plans/TLS_FINGERPRINTING_IMPLEMENTATION_GUIDE.md"
echo "   - Security Audit: docs/TLS_SECURITY_AUDIT.md"
echo ""
echo "=========================================================================="
