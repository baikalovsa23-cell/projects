#!/usr/bin/env python3
"""
Apply Migration 034: Gas Logic Refactoring
"""

import os
import sys

# Load .env
env_file = '/opt/farming/.env'
if os.path.exists(env_file):
    with open(env_file) as f:
        for line in f:
            if '=' in line and not line.startswith('#'):
                key, val = line.strip().split('=', 1)
                os.environ[key] = val

sys.path.insert(0, '/root/airdrop_v4')

import psycopg2
from loguru import logger

def get_connection():
    """Get database connection."""
    return psycopg2.connect(
        host=os.getenv('DB_HOST', 'localhost'),
        port=int(os.getenv('DB_PORT', 5432)),
        database=os.getenv('DB_NAME', 'farming_db'),
        user=os.getenv('DB_USER', 'farming_user'),
        password=os.getenv('DB_PASS')
    )

def apply_migration():
    """Apply migration 034."""
    conn = get_connection()
    cur = conn.cursor()
    
    try:
        # Section 1: Add columns to chain_rpc_endpoints
        logger.info("Adding columns to chain_rpc_endpoints...")
        
        columns = [
            ("chain_id", "INTEGER"),
            ("is_l2", "BOOLEAN DEFAULT FALSE"),
            ("l1_data_fee", "BOOLEAN DEFAULT FALSE"),
            ("network_type", "VARCHAR(20) DEFAULT 'sidechain'"),
            ("gas_multiplier", "DECIMAL(3, 1) DEFAULT 2.0"),
        ]
        
        for col_name, col_type in columns:
            try:
                cur.execute(f"ALTER TABLE chain_rpc_endpoints ADD COLUMN IF NOT EXISTS {col_name} {col_type}")
                logger.info(f"  ✓ Added column {col_name}")
            except Exception as e:
                if "already exists" in str(e).lower():
                    logger.info(f"  ✓ Column {col_name} already exists")
                else:
                    logger.warning(f"  ⚠ {col_name}: {e}")
        
        conn.commit()
        
        # Section 2: Populate chain_id for known networks
        logger.info("Populating chain_id for known networks...")
        
        chain_updates = [
            (1, False, False, 'l1', 1.5, ['ethereum', 'Ethereum']),
            (42161, True, True, 'l2', 5.0, ['arbitrum', 'Arbitrum', 'arbitrum one']),
            (8453, True, True, 'l2', 5.0, ['base', 'Base']),
            (10, True, True, 'l2', 5.0, ['optimism', 'Optimism', 'op', 'OP Mainnet']),
            (137, False, False, 'sidechain', 2.0, ['polygon', 'Polygon', 'matic']),
            (56, False, False, 'sidechain', 2.0, ['bnbchain', 'BNB Chain', 'bsc', 'BSC']),
            (57073, True, True, 'l2', 5.0, ['ink', 'Ink']),
            (420420, True, True, 'l2', 5.0, ['megaeth', 'MegaETH']),
            (324, True, True, 'l2', 5.0, ['zksync', 'zkSync', 'zksync era']),
            (534352, True, True, 'l2', 5.0, ['scroll', 'Scroll']),
            (59144, True, True, 'l2', 5.0, ['linea', 'Linea']),
            (5000, True, True, 'l2', 5.0, ['mantle', 'Mantle']),
            (43114, False, False, 'sidechain', 2.0, ['avalanche', 'Avalanche', 'avax']),
        ]
        
        for chain_id, is_l2, l1_data_fee, network_type, gas_mult, chain_names in chain_updates:
            for chain_name in chain_names:
                cur.execute("""
                    UPDATE chain_rpc_endpoints 
                    SET chain_id = %s, is_l2 = %s, l1_data_fee = %s, 
                        network_type = %s, gas_multiplier = %s
                    WHERE LOWER(chain) = LOWER(%s)
                """, (chain_id, is_l2, l1_data_fee, network_type, gas_mult, chain_name))
        
        conn.commit()
        logger.info(f"  ✓ Updated {cur.rowcount} chain records")
        
        # Section 3: Create gas_history table
        logger.info("Creating gas_history table...")
        
        cur.execute("""
            CREATE TABLE IF NOT EXISTS gas_history (
                id SERIAL PRIMARY KEY,
                chain_id INTEGER NOT NULL,
                gas_price_gwei DECIMAL(10, 4) NOT NULL,
                recorded_at TIMESTAMPTZ DEFAULT NOW()
            )
        """)
        
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_gas_history_chain_time 
            ON gas_history(chain_id, recorded_at DESC)
        """)
        
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_gas_history_retention 
            ON gas_history(recorded_at)
        """)
        
        conn.commit()
        logger.info("  ✓ Created gas_history table with indexes")
        
        # Section 4: Create chain_id index
        logger.info("Creating chain_id index...")
        
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_chain_rpc_chain_id 
            ON chain_rpc_endpoints(chain_id) 
            WHERE chain_id IS NOT NULL
        """)
        
        conn.commit()
        logger.info("  ✓ Created chain_id index")
        
        # Section 5: Add gas check columns to bridge_history if exists
        logger.info("Checking bridge_history table...")
        
        cur.execute("""
            SELECT EXISTS (
                SELECT 1 FROM information_schema.tables 
                WHERE table_name = 'bridge_history'
            )
        """)
        
        if cur.fetchone()[0]:
            bridge_columns = [
                ("source_chain_gas_ok", "BOOLEAN"),
                ("dest_chain_gas_ok", "BOOLEAN"),
                ("gas_check_at", "TIMESTAMPTZ"),
            ]
            
            for col_name, col_type in bridge_columns:
                try:
                    cur.execute(f"ALTER TABLE bridge_history ADD COLUMN IF NOT EXISTS {col_name} {col_type}")
                except Exception as e:
                    if "already exists" not in str(e).lower():
                        logger.warning(f"  ⚠ bridge_history.{col_name}: {e}")
            
            conn.commit()
            logger.info("  ✓ Updated bridge_history table")
        else:
            logger.info("  ℹ bridge_history table does not exist, skipping")
        
        # Section 6: Verification
        logger.info("Verifying migration...")
        
        cur.execute("SELECT COUNT(*) FROM chain_rpc_endpoints")
        total_chains = cur.fetchone()[0]
        
        cur.execute("SELECT COUNT(*) FROM chain_rpc_endpoints WHERE chain_id IS NOT NULL")
        chains_with_id = cur.fetchone()[0]
        
        cur.execute("SELECT COUNT(*) FROM chain_rpc_endpoints WHERE is_l2 = TRUE")
        l2_chains = cur.fetchone()[0]
        
        logger.info(f"  Total chains: {total_chains}")
        logger.info(f"  Chains with chain_id: {chains_with_id}")
        logger.info(f"  L2 chains: {l2_chains}")
        
        # Show sample data
        cur.execute("""
            SELECT chain, chain_id, network_type, gas_multiplier 
            FROM chain_rpc_endpoints 
            WHERE chain_id IS NOT NULL 
            LIMIT 5
        """)
        
        logger.info("  Sample data:")
        for row in cur.fetchall():
            logger.info(f"    {row[0]}: chain_id={row[1]}, type={row[2]}, mult={row[3]}")
        
        logger.success("✅ Migration 034 applied successfully!")
        
    except Exception as e:
        conn.rollback()
        logger.error(f"Migration failed: {e}")
        raise
    finally:
        cur.close()
        conn.close()

if __name__ == '__main__':
    apply_migration()
