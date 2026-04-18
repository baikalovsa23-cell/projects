"""
Monitoring Module — Airdrop Detection, Token Verification, and Health Checks
===============================================================================

This module provides:
- Module 17: Airdrop Detector (async scanning of 90 wallets)
- Module 18: Token Verifier (CoinGecko + heuristics)
- Module 20: Health Check System (Workers, RPC, Database monitoring)

Usage:
    from monitoring.airdrop_detector import AirdropDetector
    from monitoring.token_verifier import TokenVerifier
    from monitoring.health_check import HealthCheckOrchestrator

Integration:
    - APScheduler: Runs every 6 hours (00:00, 06:00, 12:00, 18:00 UTC)
    - Telegram: Sends alerts for verified airdrops (confidence > 0.6)
    - Database: Stores token balances in wallet_tokens table
    - Health checks: Background threads (60s Workers, 5min RPC, 2min DB)
"""

from monitoring.airdrop_detector import AirdropDetector, TokenBalance, ScanCycleStats
from monitoring.token_verifier import TokenVerifier, VerificationResult
from monitoring.health_check import (
    HealthCheckOrchestrator,
    WorkerHealthMonitor,
    RPCHealthMonitor,
    DatabaseHealthMonitor,
    WorkerStatus,
    RPCEndpointStatus,
    DatabaseStatus,
    SystemHealthStatus
)

__all__ = [
    # Airdrop Detection (Module 17)
    "AirdropDetector",
    "TokenBalance", 
    "ScanCycleStats",
    # Token Verification (Module 18)
    "TokenVerifier",
    "VerificationResult",
    # Health Check System (Module 20)
    "HealthCheckOrchestrator",
    "WorkerHealthMonitor",
    "RPCHealthMonitor",
    "DatabaseHealthMonitor",
    "WorkerStatus",
    "RPCEndpointStatus",
    "DatabaseStatus",
    "SystemHealthStatus",
]

__version__ = "0.20.0"
