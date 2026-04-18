#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))

print("Testing imports...")

try:
    from infrastructure.simulator import TransactionSimulator
    print("✓ TransactionSimulator imported")
except Exception as e:
    print(f"✗ TransactionSimulator import failed: {e}")

try:
    from withdrawal.validator import WithdrawalValidator
    print("✓ WithdrawalValidator imported")
except Exception as e:
    print(f"✗ WithdrawalValidator import failed: {e}")

try:
    from activity.scheduler import ActivityScheduler
    print("✓ ActivityScheduler imported")
except Exception as e:
    print(f"✗ ActivityScheduler import failed: {e}")

print("\nRunning simple test...")
import pytest
sys.exit(pytest.main([
    'tests/test_scheduler.py::TestGaussianScheduling::test_gaussian_hour_distribution',
    '-xvs', '--tb=short'
]))
