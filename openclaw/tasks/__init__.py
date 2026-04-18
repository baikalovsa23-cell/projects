"""
OpenClaw Tasks Package
======================

All available OpenClaw automation tasks.

Exports:
- BaseTask: Abstract base class
- GitcoinPassportTask: Gitcoin Passport stamping
- POAPTask: POAP NFT claiming
- ENSTask: ENS domain registration (deprecated, use CoinbaseIDTask)
- CoinbaseIDTask: Coinbase ID (cb.id) registration — FREE alternative to ENS
- SnapshotTask: Snapshot DAO voting
- LensTask: Lens Protocol interactions
"""

from openclaw.tasks.base import BaseTask
from openclaw.tasks.gitcoin import GitcoinPassportTask
from openclaw.tasks.poap import POAPTask
from openclaw.tasks.ens import ENSTask
from openclaw.tasks.coinbase_id import CoinbaseIDTask
from openclaw.tasks.snapshot import SnapshotTask
from openclaw.tasks.lens import LensTask

__all__ = [
    'BaseTask',
    'GitcoinPassportTask',
    'POAPTask',
    'ENSTask',
    'CoinbaseIDTask',
    'SnapshotTask',
    'LensTask',
]
