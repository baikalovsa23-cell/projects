"""
Wallets Module — Generation & Persona Management
================================================

Components:
- generator: 90 wallet generation with unique personas
- personas: 12 archetypes with Gaussian noise for anti-Sybil
"""

from .generator import WalletGenerator, GeneratedWallet
from .personas import PersonaGenerator, ARCHETYPES

__all__ = ['WalletGenerator', 'GeneratedWallet', 'PersonaGenerator', 'ARCHETYPES']
