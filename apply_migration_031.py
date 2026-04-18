#!/usr/bin/env python3
"""
Apply Bridge Manager v2.0 Migration
====================================
Применяет миграцию 031_bridge_manager_v2.sql к БД

Run:
    python3 apply_migration_031.py
"""

import os
import sys
import psycopg2
from psycopg2 import sql

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Database connection parameters
DB_CONFIG = {
    'host': 'localhost',
    'database': 'farming_db',
    'user': 'postgres',  # Use postgres superuser
    'password': None  # Will be read from secrets
}


def get_postgres_password():
    """Get postgres password from secrets."""
    # Try to read from .pgpass
    pgpass_path = os.path.expanduser('~/.pgpass')
    if os.path.exists(pgpass_path):
        with open(pgpass_path, 'r') as f:
            for line in f:
                if 'postgres' in line:
                    parts = line.strip().split(':')
                    if len(parts) >= 5:
                        return parts[4]
    
    # Try environment variable
    if os.getenv('POSTGRES_PASSWORD'):
        return os.getenv('POSTGRES_PASSWORD')
    
    return None


def apply_migration():
    """Apply the migration file."""
    # Get password
    password = get_postgres_password()
    if not password:
        print("ERROR: Could not find postgres password")
        print("Please set POSTGRES_PASSWORD environment variable or create ~/.pgpass")
        return False
    
    DB_CONFIG['password'] = password
    
    # Read migration file
    migration_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        'database/migrations/031_bridge_manager_v2.sql'
    )
    
    if not os.path.exists(migration_path):
        print(f"ERROR: Migration file not found: {migration_path}")
        return False
    
    with open(migration_path, 'r') as f:
        migration_sql = f.read()
    
    # Connect to database
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        conn.autocommit = False
        cursor = conn.cursor()
        
        print("Connected to database as postgres")
        
        # Execute migration
        success = 0
        skipped = 0
        errors = 0
        
        # Split by semicolons and execute each statement
        statements = [s.strip() for s in migration_sql.split(';') if s.strip() and not s.strip().startswith('--')]
        
        for i, stmt in enumerate(statements):
            if not stmt:
                continue
            
            try:
                cursor.execute(stmt)
                conn.commit()
                success += 1
                
                # Print progress every 10 statements
                if (i + 1) % 10 == 0:
                    print(f"Progress: {i+1}/{len(statements)} statements")
            
            except psycopg2.Error as e:
                conn.rollback()
                err_str = str(e).lower()
                
                # Skip "already exists" errors
                if 'already exists' in err_str or 'duplicate' in err_str:
                    skipped += 1
                else:
                    errors += 1
                    print(f"ERROR in statement {i+1}: {str(e)[:100]}")
        
        cursor.close()
        conn.close()
        
        print(f"\n{'='*50}")
        print(f"Migration completed!")
        print(f"  Success: {success}")
        print(f"  Skipped: {skipped}")
        print(f"  Errors: {errors}")
        print(f"{'='*50}")
        
        return errors == 0
    
    except psycopg2.Error as e:
        print(f"Database error: {e}")
        return False


if __name__ == '__main__':
    success = apply_migration()
    sys.exit(0 if success else 1)
