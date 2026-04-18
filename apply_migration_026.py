#!/usr/bin/env python3
"""
Apply Migration 026: Direct Funding Architecture (v3.0)
Removes intermediate wallet infrastructure, enables direct CEX withdrawals.
"""

import sys
import os

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from database.db_manager import DatabaseManager
from loguru import logger

def main():
    """Apply migration 026."""
    logger.info("=" * 60)
    logger.info("Applying Migration 026: Direct Funding Architecture")
    logger.info("=" * 60)
    
    db = DatabaseManager()
    
    try:
        # Read migration file
        migration_path = 'database/migrations/026_direct_funding_architecture.sql'
        logger.info(f"Reading migration from: {migration_path}")
        
        with open(migration_path, 'r') as f:
            migration_sql = f.read()
        
        # Execute migration
        logger.info("Executing migration...")
        db.execute_query(migration_sql, fetch=None)
        
        logger.success("✅ Migration 026 applied successfully!")
        
        # Verify migration
        logger.info("")
        logger.info("Verifying migration results...")
        
        # Check if intermediate columns removed from funding_chains
        chains_columns = db.execute_query("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'funding_chains'
            ORDER BY column_name
        """, fetch='all')
        
        intermediate_cols = [c['column_name'] for c in chains_columns 
                             if 'intermediate' in c['column_name'].lower()]
        
        if intermediate_cols:
            logger.warning(f"⚠️  Intermediate columns still exist: {intermediate_cols}")
        else:
            logger.success("✅ Intermediate columns removed from funding_chains")
        
        # Check if new columns added to funding_withdrawals
        withdrawals_columns = db.execute_query("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'funding_withdrawals'
            AND column_name IN (
                'direct_cex_withdrawal',
                'cex_withdrawal_scheduled_at',
                'cex_withdrawal_completed_at',
                'cex_txid',
                'interleave_round',
                'interleave_position'
            )
            ORDER BY column_name
        """, fetch='all')
        
        new_cols = [c['column_name'] for c in withdrawals_columns]
        logger.info(f"New columns in funding_withdrawals: {len(new_cols)}/6")
        
        for col in new_cols:
            logger.success(f"  ✅ {col}")
        
        # Check if deprecated tables renamed
        deprecated_tables = db.execute_query("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public'
            AND table_name LIKE '%deprecated%'
        """, fetch='all')
        
        if deprecated_tables:
            logger.info(f"\nDeprecated tables (kept for audit):")
            for table in deprecated_tables:
                logger.info(f"  📦 {table['table_name']}")
        
        # Check if views created
        views = db.execute_query("""
            SELECT table_name 
            FROM information_schema.views 
            WHERE table_schema = 'public'
            AND table_name LIKE 'v_direct_funding%' OR table_name LIKE 'v_funding_%'
        """, fetch='all')
        
        logger.info(f"\nMonitoring views created: {len(views)}")
        for view in views:
            logger.success(f"  ✅ {view['table_name']}")
        
        # Check if validation function exists
        validation_func = db.execute_query("""
            SELECT routine_name 
            FROM information_schema.routines 
            WHERE routine_schema = 'public'
            AND routine_name = 'validate_direct_funding_schedule'
        """, fetch='one')
        
        if validation_func:
            logger.success("\n✅ Validation function created: validate_direct_funding_schedule()")
        
        logger.info("")
        logger.info("=" * 60)
        logger.success("Migration 026 Complete!")
        logger.info("=" * 60)
        logger.info("")
        logger.info("Next Steps:")
        logger.info("1. Run: python setup_direct_funding.py")
        logger.info("2. Verify: SELECT * FROM validate_direct_funding_schedule()")
        logger.info("3. Review: SELECT * FROM v_direct_funding_schedule")
        logger.info("")
        
    except Exception as e:
        logger.error(f"❌ Migration failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
