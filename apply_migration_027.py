#!/usr/bin/env python3
"""
Apply Migration 027: Fix Preferred Hours Diversity
===================================================
Исправляет критическую проблему P0.3: одинаковые preferred_hours
внутри каждого архетипа.

ПЕРЕД запуском убедитесь, что:
- Migration 021 уже применена (90 персон распределены по 12 архетипам)
- Migration 027_fix_preferred_hours_diversity.sql существует

Usage:
    python apply_migration_027.py

Author: System Architect
Date: 2026-03-01
"""

import sys
import os
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent))

from database.db_manager import DatabaseManager
from loguru import logger


def apply_migration():
    """Apply migration 027."""
    db = DatabaseManager()
    
    migration_path = Path(__file__).parent / 'database' / 'migrations' / '027_fix_preferred_hours_diversity.sql'
    
    if not migration_path.exists():
        logger.error(f"Migration file not found: {migration_path}")
        return False
    
    logger.info(f"Applying migration: {migration_path}")
    
    try:
        # Read migration SQL
        with open(migration_path, 'r') as f:
            sql = f.read()
        
        # Execute migration
        logger.info("Executing migration SQL...")
        db.execute_query(sql)
        
        logger.success("✅ Migration 027 applied successfully!")
        
        # Verification queries
        logger.info("\n" + "=" * 70)
        logger.info("VERIFICATION: Preferred Hours Diversity")
        logger.info("=" * 70)
        
        # Check diversity within each archetype
        query = """
        SELECT 
            persona_type,
            COUNT(DISTINCT preferred_hours) as unique_hour_combinations,
            COUNT(*) as total_wallets,
            ROUND(COUNT(DISTINCT preferred_hours)::NUMERIC / COUNT(*) * 100, 2) as diversity_percentage
        FROM wallet_personas
        GROUP BY persona_type
        ORDER BY persona_type;
        """
        
        results = db.execute_query(query, fetch='all')
        
        logger.info("\nDiversity within each archetype:")
        for row in results:
            status = "✅" if row['diversity_percentage'] >= 80 else "⚠️"
            logger.info(
                f"{status} {row['persona_type']:20} | "
                f"Unique combinations: {row['unique_hour_combinations']}/{row['total_wallets']} "
                f"({row['diversity_percentage']}%)"
            )
        
        # Check skip_week_probability variety
        logger.info("\n" + "=" * 70)
        logger.info("VERIFICATION: Skip Week Probability Variety")
        logger.info("=" * 70)
        
        query2 = """
        SELECT 
            persona_type,
            skip_week_probability,
            COUNT(*) as wallet_count
        FROM wallet_personas
        GROUP BY persona_type, skip_week_probability
        ORDER BY skip_week_probability DESC, persona_type;
        """
        
        results2 = db.execute_query(query2, fetch='all')
        
        logger.info("\nSkip week probability by archetype:")
        for row in results2:
            logger.info(
                f"  {row['persona_type']:20} | "
                f"Skip prob: {row['skip_week_probability']*100:5.1f}% | "
                f"Wallets: {row['wallet_count']}"
            )
        
        return True
    
    except Exception as e:
        logger.error(f"❌ Migration failed: {e}")
        logger.exception(e)
        return False


def verify_wallet_persona_mapping():
    """Verify that all 90 wallets have personas assigned."""
    db = DatabaseManager()
    
    logger.info("\n" + "=" * 70)
    logger.info("VERIFICATION: Wallet → Persona Mapping")
    logger.info("=" * 70)
    
    query = """
    SELECT 
        COUNT(w.id) as total_wallets,
        COUNT(wp.id) as wallets_with_personas
    FROM wallets w
    LEFT JOIN wallet_personas wp ON wp.wallet_id = w.id;
    """
    
    result = db.execute_query(query, fetch='one')
    
    if result['total_wallets'] == result['wallets_with_personas']:
        logger.success(
            f"✅ All {result['total_wallets']} wallets have personas assigned"
        )
        return True
    else:
        logger.error(
            f"❌ Mismatch: {result['total_wallets']} wallets, "
            f"but only {result['wallets_with_personas']} personas"
        )
        return False


def main():
    logger.info("=" * 70)
    logger.info("MIGRATION 027: Fix Preferred Hours Diversity")
    logger.info("=" * 70)
    logger.info("")
    
    # Step 1: Verify wallet-persona mapping
    if not verify_wallet_persona_mapping():
        logger.error("❌ Prerequisites not met. Please run migration 021 first.")
        sys.exit(1)
    
    # Step 2: Apply migration
    if not apply_migration():
        logger.error("❌ Migration failed")
        sys.exit(1)
    
    logger.info("\n" + "=" * 70)
    logger.success("✅ MIGRATION 027 COMPLETED SUCCESSFULLY")
    logger.info("=" * 70)
    logger.info("\nNext steps:")
    logger.info("  1. Review verification output above")
    logger.info("  2. Test scheduler: python activity/scheduler.py generate-one --wallet-id 1 --week 2026-03-10")
    logger.info("  3. Run audit: python audit_anti_sybil_comprehensive.py --stage 1")
    logger.info("")


if __name__ == '__main__':
    main()
