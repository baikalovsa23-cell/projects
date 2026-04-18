"""
Master Node Orchestrator — Module 21
====================================

Airdrop Farming System v4.0

Coordinates all system components on the Master Node through unified APScheduler.
Provides lifecycle management, job scheduling, and system monitoring.

Usage:
    python -m master_node.orchestrator --config /opt/farming/.env

Author: Airdrop Farming System v4.0
Created: 2026-02-26
"""

from master_node.orchestrator import MasterOrchestrator

__version__ = "4.0.0"
__all__ = ["MasterOrchestrator"]
