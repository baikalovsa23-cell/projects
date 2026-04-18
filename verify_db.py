#!/usr/bin/env python3
import psycopg2

conn = psycopg2.connect(
    host='82.40.60.131',
    user='farming_user',
    password='U5e8xXLTX7zm0v5KDu2oVsJuvdW478',
    database='farming_db'
)
cur = conn.cursor()

cur.execute('SELECT COUNT(*) FROM protocols')
p = cur.fetchone()[0]

cur.execute('SELECT COUNT(*) FROM protocol_actions')
pa = cur.fetchone()[0]

cur.execute("SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'wallet_transactions')")
wt = cur.fetchone()[0]

conn.close()

print(f'protocols: {p}')
print(f'protocol_actions: {pa}')
print(f'wallet_transactions exists: {wt}')
