"""
Environment Loader — Universal .env loading with fallbacks
============================================================

Loads .env from multiple locations in order:
1. /opt/farming/.env (production on workers/master)
2. ~/.farming/.env (local development)
3. .env in project root (local development)
4. Parent directories (monorepo setups)

Usage:
    from infrastructure.env_loader import load_env
    load_env()  # Call once at module startup
"""

import os
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from loguru import logger


def load_env() -> Optional[Path]:
    """
    Load .env file from multiple possible locations.
    
    Returns:
        Path to loaded .env file, or None if not found
    """
    # Search paths in priority order
    search_paths = [
        Path('/opt/farming/.env'),           # Production (workers/master)
        Path.home() / '.farming' / '.env',   # Local dev (user home)
        Path.cwd() / '.env',                  # Current directory
        Path(__file__).parent.parent / '.env',  # Project root
    ]
    
    for env_path in search_paths:
        if env_path.exists():
            load_dotenv(env_path)
            logger.debug(f"Loaded .env from: {env_path}")
            return env_path
    
    # No .env found - this is OK if env vars are already set
    logger.debug("No .env file found, using existing environment variables")
    return None


def get_env_path() -> Optional[Path]:
    """
    Find .env path without loading.
    
    Returns:
        Path to .env file, or None if not found
    """
    search_paths = [
        Path('/opt/farming/.env'),
        Path.home() / '.farming' / '.env',
        Path.cwd() / '.env',
        Path(__file__).parent.parent / '.env',
    ]
    
    for env_path in search_paths:
        if env_path.exists():
            return env_path
    
    return None


# Auto-load on import (optional, can be disabled)
# load_env()
