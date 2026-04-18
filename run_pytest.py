#!/usr/bin/env python3
import subprocess
import sys

result = subprocess.run(
    [sys.executable, '-m', 'pytest', 
     'tests/test_simulator.py', 
     'tests/test_withdrawal_validator.py', 
     'tests/test_scheduler.py',
     '--tb=short', '-q'],
    cwd='/opt/farming',
    capture_output=True,
    text=True
)

print(result.stdout)
print(result.stderr)
print(f"\nExit code: {result.returncode}")

with open('/tmp/pytest_result.txt', 'w') as f:
    f.write(result.stdout)
    f.write(result.stderr)
    f.write(f"\nExit code: {result.returncode}\n")
