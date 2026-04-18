#!/usr/bin/env python3
"""
Apply Migration 028: Wallet Warm-Up State Machine
==================================================
Adds warm-up tracking fields to wallets table
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from database.db_manager import DatabaseManager
from loguru import logger

def main():
    """Apply migration 028."""
    db = DatabaseManager()
    
    migration_file = Path(__file__).parent / 'database' / 'migrations' / '028_add_warmup_state.sql'
    
    if not migration_file.exists():
        logger.error(f"Migration file not found: {migration_file}")
        sys.exit(1)
    
    logger.info(f"Reading migration: {migration_file}")
    sql = migration_file.read_text()
    
    try:
        logger.info("Executing migration 028...")
        db.execute_query(sql)
        logger.success("✅ Migration 028 applied successfully")
        
        # Verify
        result = db.execute_query(
            "SELECT warmup_status, COUNT(*) as count FROM wallets GROUP BY warmup_status",
            fetch='all'
        )
        
        logger.info("Warmup status distribution:")
        for row in result:
            logger.info(f"  {row['warmup_status']}: {row['count']} wallets")
        
    except Exception as e:
        logger.error(f"Migration failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
