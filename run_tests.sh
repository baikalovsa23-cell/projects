#!/bin/bash
cd /opt/farming
source venv/bin/activate
python3 -m pytest tests/test_simulator.py tests/test_withdrawal_validator.py tests/test_scheduler.py --tb=short -q 2>&1
