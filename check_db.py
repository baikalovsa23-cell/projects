#!/usr/bin/env python3
import psycopg2
import sys

try:
    conn = psycopg2.connect(
        host='82.40.60.131',
        user='farming_user',
        password='U5e8xXLTX7zm0v5KDu2oVsJuvdW478',
        database='farming_db',
        connect_timeout=10
    )
    cur = conn.cursor()
    
    cur.execute('SELECT COUNT(*) FROM protocols')
    protocols_count = cur.fetchone()[0]
    
    cur.execute('SELECT COUNT(*) FROM protocol_actions')
    actions_count = cur.fetchone()[0]
    
    cur.execute("SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'wallet_transactions')")
    wt_exists = cur.fetchone()[0]
    
    cur.execute('SELECT name, priority_score FROM protocols ORDER BY priority_score DESC LIMIT 5')
    top_protocols = cur.fetchall()
    
    conn.close()
    
    # Write to file
    with open('/tmp/db_status.txt', 'w') as f:
        f.write(f"protocols: {protocols_count}\n")
        f.write(f"protocol_actions: {actions_count}\n")
        f.write(f"wallet_transactions exists: {wt_exists}\n")
        f.write(f"\nTop protocols:\n")
        for name, score in top_protocols:
            f.write(f"  {name}: {score}\n")
    
    print(f"protocols: {protocols_count}")
    print(f"protocol_actions: {actions_count}")
    print(f"wallet_transactions exists: {wt_exists}")
    sys.exit(0)
    
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
