#!/bin/bash
# =============================================================================
# Deploy script for airdrop_v4
# Applies migration, syncs files to master and workers, restarts services
# =============================================================================
set -euo pipefail

# --- Configuration ---
MASTER_IP="82.40.60.131"
MASTER_PASS="yIFdCq9812%"
MASTER_SSH_PORT=22

WORKER1_IP="82.40.60.132"
WORKER1_PASS="ma1-jWlSHT"

WORKER2_IP="82.22.53.183"
WORKER2_PASS="nlX8+5t8aC"

WORKER3_IP="82.22.53.184"
WORKER3_PASS="Sd7t+oA5VM"

WORKER_SSH_PORT=2299

DB_PASS="U5e8xXLTX7zm0v5KDu2oVsJuvdW478"
DB_USER="farming_user"
DB_NAME="farming_db"

LOCAL_DIR="/home/hoco/airdrop_v4"
REMOTE_DIR="/opt/farming"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# Helper: SSH to master
master_ssh() {
    sshpass -p "$MASTER_PASS" ssh $SSH_OPTS -p $MASTER_SSH_PORT root@$MASTER_IP "$@"
}

# Helper: SSH to worker
worker_ssh() {
    local ip=$1; local pass=$2; shift 2
    sshpass -p "$pass" ssh $SSH_OPTS -p $WORKER_SSH_PORT root@$ip "$@"
}

echo "=========================================="
echo " DEPLOY START: $(date)"
echo "=========================================="

# =============================================================================
# Step 1: Apply migration 043_system_state.sql
# =============================================================================
echo ""
echo ">>> Step 1: Applying migration 043_system_state.sql on master..."
master_ssh "PGPASSWORD='$DB_PASS' psql -h 127.0.0.1 -U $DB_USER -d $DB_NAME -c \"
CREATE TABLE IF NOT EXISTS system_state (
    key VARCHAR(100) PRIMARY KEY,
    value BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by VARCHAR(255),
    metadata JSONB
);
\" && \
PGPASSWORD='$DB_PASS' psql -h 127.0.0.1 -U $DB_USER -d $DB_NAME -c \"
INSERT INTO system_state (key, value, updated_at, updated_by)
VALUES ('panic_mode', FALSE, NOW(), 'system'),
       ('maintenance_mode', FALSE, NOW(), 'system')
ON CONFLICT (key) DO NOTHING;
\" && \
PGPASSWORD='$DB_PASS' psql -h 127.0.0.1 -U $DB_USER -d $DB_NAME -c 'SELECT * FROM system_state;'"
echo "--- Step 1 DONE ---"

# =============================================================================
# Step 2: Rsync files local -> master
# =============================================================================
echo ""
echo ">>> Step 2: Syncing files to master node ($MASTER_IP)..."
sshpass -p "$MASTER_PASS" rsync -avz --delete \
    --exclude='.git' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.env' \
    --exclude='.farming_secrets' \
    --exclude='logs/' \
    --exclude='*.log' \
    --exclude='deploy.sh' \
    --exclude='input_worker*.txt' \
    --exclude='venv/' \
    -e "ssh $SSH_OPTS -p $MASTER_SSH_PORT" \
    "$LOCAL_DIR/" "root@$MASTER_IP:$REMOTE_DIR/"
echo "--- Step 2 DONE ---"

# =============================================================================
# Step 3: Rsync master -> workers
# =============================================================================
echo ""
echo ">>> Step 3: Syncing files from master to workers..."

for WDATA in "$WORKER1_IP:$WORKER1_PASS" "$WORKER2_IP:$WORKER2_PASS" "$WORKER3_IP:$WORKER3_PASS"; do
    WIP=$(echo $WDATA | cut -d: -f1)
    WPASS=$(echo $WDATA | cut -d: -f2)
    echo "  -> Syncing to worker $WIP..."
    sshpass -p "$WPASS" rsync -avz --delete \
        --exclude='__pycache__' \
        --exclude='*.pyc' \
        --exclude='.env' \
        --exclude='.farming_secrets' \
        --exclude='logs/' \
        --exclude='*.log' \
        --exclude='venv/' \
        -e "ssh $SSH_OPTS -p $WORKER_SSH_PORT" \
        "$LOCAL_DIR/" "root@$WIP:$REMOTE_DIR/"
    echo "  -> Worker $WIP synced."
done
echo "--- Step 3 DONE ---"

# =============================================================================
# Step 4: Restart worker-api on all workers
# =============================================================================
echo ""
echo ">>> Step 4: Restarting worker-api services..."

for WDATA in "$WORKER1_IP:$WORKER1_PASS" "$WORKER2_IP:$WORKER2_PASS" "$WORKER3_IP:$WORKER3_PASS"; do
    WIP=$(echo $WDATA | cut -d: -f1)
    WPASS=$(echo $WDATA | cut -d: -f2)
    echo "  -> Restarting worker-api on $WIP..."
    worker_ssh "$WIP" "$WPASS" "systemctl restart worker-api.service 2>&1 && systemctl is-active worker-api.service 2>&1 || echo 'RESTART FAILED'"
    echo "  -> Worker $WIP restarted."
done
echo "--- Step 4 DONE ---"

echo ""
echo "=========================================="
echo " DEPLOY COMPLETE: $(date)"
echo "=========================================="
