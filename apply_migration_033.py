#!/usr/bin/env python3
"""
Apply Migration 033: Timezone Architecture Fix

P0 CRITICAL fix for Canada wallets timezone issue.

Usage:
    python3 apply_migration_033.py
"""

import os
import sys
from pathlib import Path
from loguru import logger
from dotenv import load_dotenv

# Load .env
load_dotenv('/opt/farming/.env')

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent))

from database.db_manager import DatabaseManager


def apply_migration():
    """Apply migration 033_timezone_fix.sql"""
    db = DatabaseManager()
    
    logger.info("=" * 60)
    logger.info("Migration 033: Timezone Architecture Fix")
    logger.info("=" * 60)
    
    # Read migration file
    migration_path = Path(__file__).parent / 'database' / 'migrations' / '033_timezone_fix.sql'
    
    if not migration_path.exists():
        logger.error(f"Migration file not found: {migration_path}")
        return False
    
    with open(migration_path, 'r') as f:
        migration_sql = f.read()
    
    logger.info(f"Migration file: {migration_path}")
    
    # Split into individual statements
    # Note: We'll execute step by step for better error handling
    
    try:
        # Step 1: Add timezone columns
        logger.info("Step 1: Adding timezone columns to proxy_pool...")
        db.execute_query("""
            ALTER TABLE proxy_pool 
            ADD COLUMN IF NOT EXISTS timezone VARCHAR(50),
            ADD COLUMN IF NOT EXISTS utc_offset INTEGER
        """)
        logger.success("✅ Columns added")
        
        # Step 2: Update NL proxies
        logger.info("Step 2: Updating Netherlands proxies...")
        result = db.execute_query("""
            UPDATE proxy_pool 
            SET timezone = 'Europe/Amsterdam',
                utc_offset = 1
            WHERE country_code = 'NL'
            RETURNING COUNT(*) as count
        """, fetch='one')
        nl_count = result['count'] if result else 0
        logger.success(f"✅ Updated {nl_count} NL proxies")
        
        # Step 3: Update IS proxies
        logger.info("Step 3: Updating Iceland proxies...")
        result = db.execute_query("""
            UPDATE proxy_pool 
            SET timezone = 'Atlantic/Reykjavik',
                utc_offset = 0
            WHERE country_code = 'IS'
            RETURNING COUNT(*) as count
        """, fetch='one')
        is_count = result['count'] if result else 0
        logger.success(f"✅ Updated {is_count} IS proxies")
        
        # Step 4: Update CA proxies (CRITICAL FIX!)
        logger.info("Step 4: Updating Canada proxies (CRITICAL FIX)...")
        result = db.execute_query("""
            UPDATE proxy_pool 
            SET timezone = 'America/Toronto',
                utc_offset = -5
            WHERE country_code = 'CA'
            RETURNING COUNT(*) as count
        """, fetch='one')
        ca_count = result['count'] if result else 0
        logger.success(f"✅ Updated {ca_count} CA proxies")
        
        # Step 5: Add NOT NULL constraint
        logger.info("Step 5: Adding NOT NULL constraints...")
        db.execute_query("""
            ALTER TABLE proxy_pool 
            ALTER COLUMN timezone SET NOT NULL,
            ALTER COLUMN utc_offset SET NOT NULL
        """)
        logger.success("✅ NOT NULL constraints added")
        
        # Step 6: Create index
        logger.info("Step 6: Creating timezone index...")
        db.execute_query("""
            CREATE INDEX IF NOT EXISTS idx_proxy_pool_timezone 
            ON proxy_pool(timezone)
        """)
        logger.success("✅ Index created")
        
        # Step 7: Verification
        logger.info("Step 7: Verifying timezone distribution...")
        result = db.execute_query("""
            SELECT 
                country_code,
                timezone,
                utc_offset,
                COUNT(*) as proxy_count
            FROM proxy_pool
            GROUP BY country_code, timezone, utc_offset
            ORDER BY country_code
        """, fetch='all')
        
        logger.info("=" * 60)
        logger.info("Timezone Distribution:")
        logger.info("=" * 60)
        
        total_proxies = 0
        for row in result:
            logger.info(
                f"  {row['country_code']} | {row['timezone']} | "
                f"UTC{row['utc_offset']:+d} | {row['proxy_count']} proxies"
            )
            total_proxies += row['proxy_count']
        
        logger.info("=" * 60)
        logger.info(f"Total: {total_proxies} proxies")
        
        # Check for missing timezone data
        missing = db.execute_query("""
            SELECT COUNT(*) as count
            FROM proxy_pool
            WHERE timezone IS NULL OR utc_offset IS NULL
        """, fetch='one')
        
        if missing and missing['count'] > 0:
            logger.error(f"❌ CRITICAL: {missing['count']} proxies missing timezone data!")
            return False
        
        logger.success("✅ All proxies have timezone data")
        
        # Step 8: Check wallet timezone mapping
        logger.info("Step 8: Checking wallet timezone mapping...")
        wallet_result = db.execute_query("""
            SELECT 
                pp.country_code,
                pp.timezone,
                pp.utc_offset,
                COUNT(w.id) as wallet_count
            FROM wallets w
            JOIN proxy_pool pp ON w.proxy_id = pp.id
            GROUP BY pp.country_code, pp.timezone, pp.utc_offset
            ORDER BY pp.country_code
        """, fetch='all')
        
        logger.info("=" * 60)
        logger.info("Wallet Timezone Mapping:")
        logger.info("=" * 60)
        
        for row in wallet_result:
            logger.info(
                f"  {row['country_code']} | {row['timezone']} | "
                f"UTC{row['utc_offset']:+d} | {row['wallet_count']} wallets"
            )
        
        logger.success("✅ Migration 033 applied successfully!")
        
        logger.info("=" * 60)
        logger.info("POST-MIGRATION STEPS:")
        logger.info("=" * 60)
        logger.info("1. Regenerate personas:")
        logger.info("   python3 wallets/personas.py generate")
        logger.info("")
        logger.info("2. Verify CA wallets have correct preferred_hours:")
        logger.info("   SELECT wp.wallet_id, wp.preferred_hours, pp.timezone")
        logger.info("   FROM wallet_personas wp")
        logger.info("   JOIN wallets w ON w.id = wp.wallet_id")
        logger.info("   JOIN proxy_pool pp ON w.proxy_id = pp.id")
        logger.info("   WHERE pp.country_code = 'CA';")
        logger.info("=" * 60)
        
        return True
        
    except Exception as e:
        logger.exception(f"Migration failed: {e}")
        return False


def main():
    try:
        success = apply_migration()
        
        if success:
            print("\n✅ Migration 033 applied successfully!")
            print("\nNext steps:")
            print("  1. python3 wallets/personas.py generate")
            print("  2. Verify CA wallets have correct timezone")
            sys.exit(0)
        else:
            print("\n❌ Migration failed!")
            sys.exit(1)
            
    except Exception as e:
        logger.exception(f"Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
