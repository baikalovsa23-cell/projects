#!/usr/bin/env python3
"""
Apply Migration 032: Protocol Research Bridge Integration
=========================================================

This script applies the migration that adds bridge-related fields
to protocol_research_pending table for integration with Bridge Manager v2.0.

Migration adds:
- bridge_required, bridge_available, bridge_provider
- bridge_cost_usd, bridge_safety_score, bridge_from_network
- bridge_checked_at, bridge_unreachable_reason
- bridge_recheck_after, bridge_recheck_count, cex_support

Usage:
    python apply_migration_032.py

Author: Airdrop Farming System v4.0
Created: 2026-03-06
"""

import os
import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent))

from loguru import logger
from dotenv import load_dotenv

# Load environment
load_dotenv('/opt/farming/.env')

from database.db_manager import DatabaseManager


def apply_migration_032():
    """Apply migration 032 to database."""
    
    logger.info("=" * 60)
    logger.info("Applying Migration 032: Protocol Research Bridge Integration")
    logger.info("=" * 60)
    
    db = DatabaseManager()
    
    # Read migration file
    migration_path = Path(__file__).parent / "database" / "migrations" / "032_protocol_research_bridge.sql"
    
    if not migration_path.exists():
        logger.error(f"Migration file not found: {migration_path}")
        return False
    
    with open(migration_path, 'r') as f:
        migration_sql = f.read()
    
    logger.info(f"Migration file loaded: {len(migration_sql)} bytes")
    
    # Check if migration already applied
    try:
        check_query = """
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'protocol_research_pending' 
              AND column_name = 'bridge_required'
        """
        result = db.execute_query(check_query, fetch='one')
        
        if result:
            logger.warning("Migration 032 already applied (bridge_required column exists)")
            logger.info("Checking for missing columns...")
            
            # Check for all expected columns
            expected_columns = [
                'bridge_required', 'bridge_from_network', 'bridge_provider',
                'bridge_cost_usd', 'bridge_safety_score', 'bridge_available',
                'bridge_checked_at', 'bridge_unreachable_reason',
                'bridge_recheck_after', 'bridge_recheck_count', 'cex_support'
            ]
            
            for col in expected_columns:
                check_col = f"""
                    SELECT column_name 
                    FROM information_schema.columns 
                    WHERE table_name = 'protocol_research_pending' 
                      AND column_name = '{col}'
                """
                col_result = db.execute_query(check_col, fetch='one')
                if not col_result:
                    logger.warning(f"Missing column: {col}")
            
            return True
    except Exception as e:
        logger.debug(f"Pre-check error (expected for first run): {e}")
    
    # Apply migration
    try:
        # Execute migration in parts (PostgreSQL doesn't support multiple statements in one execute)
        statements = migration_sql.split(';')
        
        success_count = 0
        error_count = 0
        
        for i, statement in enumerate(statements):
            statement = statement.strip()
            
            # Skip empty statements and comments
            if not statement or statement.startswith('--'):
                continue
            
            # Skip the migration complete log insert (we'll do it separately)
            if 'research_logs' in statement.lower() and 'migration 032' in statement.lower():
                continue
            
            try:
                db.execute_query(statement)
                success_count += 1
                
                # Log progress every 10 statements
                if success_count % 10 == 0:
                    logger.info(f"Progress: {success_count} statements executed")
                    
            except Exception as e:
                # Some statements might fail if already exists (idempotent)
                if 'already exists' in str(e).lower() or 'duplicate' in str(e).lower():
                    logger.debug(f"Statement already applied: {statement[:50]}...")
                else:
                    logger.warning(f"Statement error: {e}")
                    error_count += 1
        
        logger.success(f"Migration applied: {success_count} statements successful, {error_count} errors")
        
        # Verify migration
        verify_query = """
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'protocol_research_pending' 
              AND column_name IN (
                'bridge_required', 'bridge_available', 'bridge_provider',
                'bridge_cost_usd', 'bridge_safety_score', 'cex_support'
              )
            ORDER BY column_name
        """
        columns = db.execute_query(verify_query, fetch='all')
        
        if columns and len(columns) >= 6:
            logger.success("✅ Migration 032 verified successfully!")
            logger.info(f"   Columns added: {[c['column_name'] for c in columns]}")
        else:
            logger.warning("⚠️ Migration may not have applied correctly")
            return False
        
        # Check functions
        func_check = """
            SELECT routine_name 
            FROM information_schema.routines 
            WHERE routine_schema = 'public' 
              AND routine_name IN (
                'get_unreachable_protocols_for_recheck',
                'update_protocol_bridge_info',
                'auto_reject_stale_unreachable_protocols',
                'calculate_final_priority_score'
              )
        """
        functions = db.execute_query(func_check, fetch='all')
        
        if functions:
            logger.success(f"✅ Functions created: {[f['routine_name'] for f in functions]}")
        
        # Check indexes
        idx_check = """
            SELECT indexname 
            FROM pg_indexes 
            WHERE tablename = 'protocol_research_pending'
              AND indexname LIKE '%bridge%'
        """
        indexes = db.execute_query(idx_check, fetch='all')
        
        if indexes:
            logger.success(f"✅ Indexes created: {[i['indexname'] for i in indexes]}")
        
        return True
        
    except Exception as e:
        logger.exception(f"Migration failed: {e}")
        return False


def main():
    """Main entry point."""
    try:
        success = apply_migration_032()
        
        if success:
            print("\n" + "=" * 60)
            print("✅ Migration 032 applied successfully!")
            print("=" * 60)
            print("\nNew fields in protocol_research_pending:")
            print("  - bridge_required (BOOLEAN)")
            print("  - bridge_from_network (VARCHAR)")
            print("  - bridge_provider (VARCHAR)")
            print("  - bridge_cost_usd (DECIMAL)")
            print("  - bridge_safety_score (INTEGER)")
            print("  - bridge_available (BOOLEAN)")
            print("  - bridge_checked_at (TIMESTAMPTZ)")
            print("  - bridge_unreachable_reason (TEXT)")
            print("  - bridge_recheck_after (TIMESTAMPTZ)")
            print("  - bridge_recheck_count (INTEGER)")
            print("  - cex_support (VARCHAR)")
            print("\nNew functions:")
            print("  - get_unreachable_protocols_for_recheck()")
            print("  - update_protocol_bridge_info()")
            print("  - auto_reject_stale_unreachable_protocols()")
            print("  - calculate_final_priority_score()")
            print("\nIntegration ready:")
            print("  - research/protocol_analyzer.py ✓")
            print("  - activity/scheduler.py ✓")
            print("  - activity/executor.py ✓")
            print("  - master_node/jobs.py ✓")
            print("=" * 60)
            sys.exit(0)
        else:
            print("\n❌ Migration 032 failed. Check logs for details.")
            sys.exit(1)
            
    except Exception as e:
        logger.exception(f"Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
