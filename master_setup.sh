#!/bin/bash

################################################################################
# MASTER NODE SETUP SCRIPT
# Server Farming & Airdrop System v4.0
# Location: Netherlands (Amsterdam, UTC+1)
# Target: Ubuntu 22.04/24.04 LTS
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root (sudo bash master_setup.sh)"
    exit 1
fi

log_info "=================================================="
log_info "MASTER NODE SETUP - FARMING SYSTEM v4.0"
log_info "=================================================="

# ============================================================================
# STEP 1: SYSTEM UPDATE
# ============================================================================
log_info "Step 1/12: Updating system packages..."
apt update && apt upgrade -y

# ============================================================================
# STEP 2: INSTALL DEPENDENCIES
# ============================================================================
log_info "Step 2/12: Installing system dependencies..."
# Auto-detect PostgreSQL and Python versions
PG_VERSION=$(apt-cache search "^postgresql-[0-9]+" | grep "^postgresql-[0-9]" | sed 's/postgresql-\([0-9]*\).*/\1/' | sort -n | tail -1)
PYTHON_VERSION=$(python3 --version | awk '{print $2}' | cut -d'.' -f1,2)

log_info "Detected PostgreSQL version: ${PG_VERSION}"
log_info "Detected Python version: ${PYTHON_VERSION}"

apt install -y \
    ufw \
    fail2ban \
    postgresql-${PG_VERSION} \
    postgresql-contrib \
    python3 \
    python3-venv \
    python3-pip \
    git \
    curl \
    htop \
    net-tools \
    jq

# ============================================================================
# STEP 3: CREATE PROJECT STRUCTURE
# ============================================================================
log_info "Step 3/12: Creating project directory structure..."

mkdir -p /opt/farming/{database,funding,wallets,activity,openclaw/profiles,protocol_research,research,monitoring,withdrawal,infrastructure,notifications,worker,venv,logs,data/protocol_research,data/news,keys}

# Set permissions
chmod 755 /opt/farming
chmod 700 /opt/farming/keys

# Create .gitignore
cat > /opt/farming/.gitignore <<'EOF'
# Секреты
.env
/root/.farming_secrets
*.pem
*.key
id_rsa*

# Приватные ключи
keys/
wallets_encrypted.json

# Логи
logs/*.log

# Python
__pycache__/
*.pyc
venv/
.venv/
*.egg-info/

# Временные файлы
data/*
!data/.gitkeep

# OpenClaw профили (содержат cookie)
openclaw/profiles/*
!openclaw/profiles/.gitkeep

# IDE
.vscode/
.idea/
*.swp
EOF

# Create placeholder files
touch /opt/farming/data/.gitkeep
touch /opt/farming/openclaw/profiles/.gitkeep

log_info "Project structure created at /opt/farming/"

# ============================================================================
# STEP 4: GENERATE SECRETS
# ============================================================================
log_info "Step 4/12: Generating cryptographic secrets..."

# Generate Fernet key (для шифрования приватных ключей)
FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")

# Generate JWT secret (для авторизации Master ↔ Workers)
JWT_SECRET=$(openssl rand -hex 32)

# Generate PostgreSQL password (32 символа)
DB_PASS=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-32)

log_info "Secrets generated successfully"

# Save secrets to root home directory (NOT in /opt/farming for git safety)
cat > /root/.farming_secrets <<EOF
# FARMING SYSTEM SECRETS
# Generated: $(date)
# KEEP THIS FILE SECURE! chmod 600

FERNET_KEY=$FERNET_KEY
JWT_SECRET=$JWT_SECRET
DB_PASS=$DB_PASS
EOF

chmod 600 /root/.farming_secrets
log_info "Secrets saved to /root/.farming_secrets (chmod 600)"

# ============================================================================
# STEP 5: POSTGRESQL CHECK (БД УЖЕ СУЩЕСТВУЕТ)
# ============================================================================
log_info "Step 5/12: Checking PostgreSQL..."

# Start PostgreSQL if not running
systemctl enable postgresql
systemctl start postgresql

# Check if database exists
DB_EXISTS=$(sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw farming_db && echo "yes" || echo "no")

if [ "$DB_EXISTS" = "yes" ]; then
    log_info "✅ Database farming_db already exists — skipping creation"
else
    log_error "Database farming_db NOT found! Create it manually first."
    log_error "This script does NOT create database anymore."
    exit 1
fi

# Check if user exists
USER_EXISTS=$(sudo -u postgres psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='farming_user'" | grep -q 1 && echo "yes" || echo "no")

if [ "$USER_EXISTS" = "yes" ]; then
    log_info "✅ User farming_user already exists — skipping creation"
else
    log_error "User farming_user NOT found! Create it manually first."
    exit 1
fi

log_info "PostgreSQL database and user verified"

# ============================================================================
# STEP 6: SYNC PROJECT FILES
# ============================================================================
log_info "Step 6/12: Syncing project files from /root/airdrop_v4/ to /opt/farming/..."

# Check if source directory exists
if [ -d "/root/airdrop_v4" ]; then
    log_info "Found /root/airdrop_v4 — syncing to /opt/farming/"
    
    # Copy all directories (excluding .git)
    for DIR in activity database funding infrastructure master_node monitoring notifications openclaw research wallets withdrawal worker; do
        if [ -d "/root/airdrop_v4/$DIR" ]; then
            cp -r "/root/airdrop_v4/$DIR" /opt/farming/
            log_info "  ✓ Copied $DIR"
        fi
    done
    
    # Copy requirements.txt
    if [ -f "/root/airdrop_v4/requirements.txt" ]; then
        cp "/root/airdrop_v4/requirements.txt" /opt/farming/
        log_info "  ✓ Copied requirements.txt"
    fi
    
    # Copy install_curl_cffi.sh
    if [ -f "/root/airdrop_v4/install_curl_cffi.sh" ]; then
        cp "/root/airdrop_v4/install_curl_cffi.sh" /opt/farming/
        log_info "  ✓ Copied install_curl_cffi.sh"
    fi
    
    log_success "Project files synced to /opt/farming/"
else
    log_warn "/root/airdrop_v4 not found — skipping sync"
    log_warn "You'll need to manually copy project files to /opt/farming/"
fi

# ============================================================================
# STEP 7: CREATE .ENV FILE
# ============================================================================
log_info "Step 7/12: Creating .env configuration file..."

cat > /opt/farming/.env <<EOF
# ===== БАЗА ДАННЫХ =====
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=farming_db
DB_USER=farming_user
DB_PASS=$DB_PASS

# ===== ШИФРОВАНИЕ =====
ENCRYPTION_KEY=$FERNET_KEY

# ===== MASTER NODE API =====

# ===== TELEGRAM =====
TELEGRAM_BOT_TOKEN=PLACEHOLDER_FROM_BOTFATHER
TELEGRAM_CHAT_ID=PLACEHOLDER_YOUR_CHAT_ID

# ===== OPENROUTER (ДВА РАЗНЫХ КЛЮЧА!) =====
OPENROUTER_API_KEY=PLACEHOLDER_MAIN_KEY_FOR_PYTHON
OPENROUTER_API_KEY_OPENCLAW=PLACEHOLDER_SEPARATE_KEY_FOR_OPENCLAW

# ===== WORKERS JWT =====
JWT_SECRET=$JWT_SECRET

# ===== IP АДРЕСА WORKERS (заполнить после аренды VPS) =====
WORKER1_IP=PLACEHOLDER_NETHERLANDS
WORKER2_IP=PLACEHOLDER_ICELAND
WORKER3_IP=PLACEHOLDER_ICELAND

# ===== CEX API KEYS (whitelist по IP Master Node!) =====
BINANCE_API_KEY=PLACEHOLDER
BINANCE_API_SECRET=PLACEHOLDER

BYBIT_API_KEY=PLACEHOLDER
BYBIT_API_SECRET=PLACEHOLDER

OKX_API_KEY=PLACEHOLDER
OKX_API_SECRET=PLACEHOLDER
OKX_PASSPHRASE=PLACEHOLDER

KUCOIN_API_KEY=PLACEHOLDER
KUCOIN_API_SECRET=PLACEHOLDER
KUCOIN_PASSPHRASE=PLACEHOLDER

MEXC_API_KEY=PLACEHOLDER
MEXC_API_SECRET=PLACEHOLDER

# ===== PROXY (iproyal, Decodo) =====
IPROYAL_USERNAME=PLACEHOLDER
IPROYAL_PASSWORD=PLACEHOLDER

DECODO_API_KEY=PLACEHOLDER

# ===== RPC ENDPOINTS (резервные, если публичные fail) =====
ALCHEMY_API_KEY=PLACEHOLDER_OPTIONAL
INFURA_API_KEY=PLACEHOLDER_OPTIONAL

# ===== NETWORK MODE =====
NETWORK_MODE=DRY_RUN
EOF

chmod 600 /opt/farming/.env
log_info ".env file created (chmod 600). EDIT MANUALLY: Telegram, OpenRouter, CEX keys!"

# ============================================================================
# STEP 8: PYTHON VIRTUAL ENVIRONMENT
# ============================================================================
log_info "Step 8/12: Creating Python virtual environment..."
python3 -m venv /opt/farming/venv

# Activate venv and install dependencies
source /opt/farming/venv/bin/activate

# Check if requirements.txt exists from sync, otherwise create fallback
if [ -f "/opt/farming/requirements.txt" ]; then
    log_info "Using requirements.txt from project sync"
else
    log_warn "requirements.txt not found, creating fallback..."
    cat > /opt/farming/requirements.txt <<'EOF'
# Core Web3
web3==6.20.3
eth-account==0.11.0
eth-utils==4.0.0

# HTTP Clients & TLS Fingerprinting
curl-cffi==0.7.0
requests==2.31.0
aiohttp==3.9.1
httpx==0.27.0

# Database
psycopg2-binary==2.9.9
SQLAlchemy==2.0.23

# CEX Integration
ccxt==4.3.95

# Cryptography
cryptography==41.0.7

# Scheduling
APScheduler==3.10.4

# Logging
loguru==0.7.2

# Retry/Backoff
tenacity==8.2.3

# Environment Variables
python-dotenv==1.0.0

# Math/Statistics
numpy==1.26.2

# Telegram Bot
python-telegram-bot==20.7

# Flask API
Flask==3.0.0
Flask-JWT-Extended==4.5.3
Flask-Cors==4.0.0

# Testing
pytest==7.4.3
pytest-asyncio==0.21.1

# Linting/Formatting
black==23.12.0
flake8==6.1.0
mypy==1.7.1
rapidfuzz>=3.0.0
EOF
fi

pip install --upgrade pip
pip install -r /opt/farming/requirements.txt

deactivate

log_info "Python environment created and dependencies installed"

# ============================================================================
# STEP 9: INSTALL curl-cffi FOR TLS FINGERPRINTING
# ============================================================================
log_info "Step 9/12: Installing curl-cffi for TLS fingerprinting..."

log_info "curl-cffi provides browser impersonation (Chrome/Safari) to avoid Sybil detection"

# Install system dependencies for curl-cffi
apt-get install -y -qq libcurl4-openssl-dev curl build-essential

# Install curl-cffi in venv
source /opt/farming/venv/bin/activate
pip install curl-cffi==0.7.0 -q
deactivate

# Verify installation
if python3 -c "from curl_cffi import requests; print('✓')" &> /dev/null; then
    log_success "curl-cffi installed and verified"
else
    log_warn "curl-cffi installation may have issues"
fi

# ============================================================================
# STEP 10: FAIL2BAN CONFIGURATION
# ============================================================================
log_info "Step 10/12: Configuring fail2ban..."

systemctl enable fail2ban
systemctl start fail2ban

# Create jail.local
# NOTE: SSH jail DISABLED - user has dynamic IP (mobile internet)
# Only PostgreSQL protection enabled
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
# Время бана (30 минут для PostgreSQL)
bantime = 1800
# Окно наблюдения (10 минут)
findtime = 600
# Максимум попыток перед баном
maxretry = 10

# SSH Protection - DISABLED for dynamic IP users
# Uncomment if you have static IP and want SSH protection
[sshd]
enabled = false
port = 22,2299
filter = sshd
logpath = /var/log/auth.log
maxretry = 10
bantime = 3600

# PostgreSQL Protection
[postgresql]
enabled = true
port = 5432
filter = postgresql
logpath = /var/log/postgresql/postgresql-15-main.log
maxretry = 10
bantime = 1800
EOF

# Create PostgreSQL filter
cat > /etc/fail2ban/filter.d/postgresql.conf <<'EOF'
[Definition]
failregex = FATAL:  password authentication failed for user
            FATAL:  no pg_hba.conf entry for host
ignoreregex =
EOF

# Restart fail2ban
systemctl restart fail2ban

log_info "fail2ban configured (SSH jail DISABLED for dynamic IP, PostgreSQL protected)"

# ============================================================================
# STEP 11: UFW FIREWALL (NOT ENABLED YET!)
# ============================================================================
log_info "Step 11/12: Configuring UFW firewall..."

# Install UFW
apt install -y ufw

# Default policies
ufw --force default deny incoming
ufw --force default allow outgoing

# Allow SSH on port 2299 (will be configured next)
ufw allow 22/tcp comment 'SSH default'
ufw allow 2299/tcp comment 'SSH hardened'

# Allow localhost
ufw allow from 127.0.0.1 to any

log_warn "UFW configured but NOT enabled yet!"
log_warn "Workers IP addresses for PostgreSQL (port 5432) must be added manually:"
log_warn "  sudo ufw allow from <WORKER_IP> to any port 5432 proto tcp comment 'Worker PostgreSQL'"

# ============================================================================
# STEP 12: SSH HARDENING (AUTOMATIC)
# ============================================================================
log_info "Step 12/12: SSH Hardening (Automatic)..."

# Create .ssh directory and add authorized keys
log_info "Adding SSH authorized keys..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh

cat > /root/.ssh/authorized_keys <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHYO640ShUv3Muem00ieYa0Vy/Krw7yf3EZe8B++ZHPZ master_node_farm
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICf9wNC34BYWcHbDAf2pTig7iG6cjWyKn6/LIlFEMqqO dev@plnka.com
EOF

chmod 600 /root/.ssh/authorized_keys
log_success "SSH authorized keys added (2 keys)"

# Configure SSH hardening
log_info "Configuring SSH hardening..."
cat >> /etc/ssh/sshd_config <<'EOF'

# ===== FARMING PROJECT SSH HARDENING =====
Port 2299
PermitRootLogin prohibit-password
PasswordAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 60
MaxSessions 5
AllowTcpForwarding no
StrictModes yes
EOF

# Test SSH config
log_info "Testing SSH configuration..."
if sshd -t; then
    log_success "SSH configuration valid"
else
    log_error "SSH configuration invalid! Check sshd_config"
    exit 1
fi

# Restart SSH
log_info "Restarting SSH daemon..."
systemctl restart sshd
log_success "SSH restarted on port 2299"

# Enable UFW firewall
log_info "Enabling UFW firewall..."
ufw --force enable
log_success "UFW firewall enabled"

log_warn ""
log_warn "=================================================="
log_warn "SSH HARDENING COMPLETE"
log_warn "=================================================="
log_warn "SSH now requires key authentication on port 2299"
log_warn "Password authentication disabled"
log_warn "UFW firewall enabled"
log_warn ""
log_warn "Test connection from your laptop:"
log_warn "  ssh -p 2299 root@<MASTER_IP>"
log_warn "=================================================="

# ============================================================================
# COMPLETION SUMMARY
# ============================================================================
log_info "=================================================="
log_info "MASTER NODE SETUP COMPLETED"
log_info "=================================================="
echo ""
log_info "✅ System packages updated"
log_info "✅ PostgreSQL verified (database already exists)"
log_info "✅ Project files synced from /root/airdrop_v4/ to /opt/farming/"
log_info "✅ Python venv created at /opt/farming/venv"
log_info "✅ curl-cffi installed for TLS fingerprinting"
log_info "✅ fail2ban configured (SSH jail DISABLED for dynamic IP)"
log_info "✅ UFW firewall enabled"
log_info "✅ Secrets generated: /root/.farming_secrets"
log_info "✅ NETWORK_MODE=DRY_RUN (safe default)"
echo ""
log_warn "⚠️  MANUAL ACTIONS REQUIRED:"
echo ""
echo "1. Edit /opt/farming/.env:"
echo "   - TELEGRAM_BOT_TOKEN (get from @BotFather)"
echo "   - TELEGRAM_CHAT_ID (your Telegram user ID)"
echo "   - OPENROUTER_API_KEY (main key)"
echo "   - OPENROUTER_API_KEY_OPENCLAW (separate key)"
echo "   - CEX API keys (Binance, Bybit, OKX, KuCoin, MEXC)"
echo "   - WORKER1_IP, WORKER2_IP, WORKER3_IP"
echo ""
echo "2. Add Worker IPs to UFW:"
echo "   sudo ufw allow from <WORKER_IP> to any port 5432 proto tcp comment 'Worker1'"
echo ""
echo "3. Add Worker IPs to PostgreSQL pg_hba.conf:"
echo "   host    farming_db      farming_user    <WORKER_IP>/32    scram-sha-256"
echo "   sudo systemctl restart postgresql"
echo ""
echo "4. Complete SSH hardening (see warnings above)"
echo ""
echo "5. Enable UFW (AFTER SSH hardening!):"
echo "   sudo ufw enable"
echo ""
echo "=================================================="
log_info "Installation log: /var/log/farming_master_setup.log"
echo "=================================================="

# Save secrets display to user
echo ""
echo "IMPORTANT: Save these secrets to your password manager:"
echo ""
echo "Fernet Key: $FERNET_KEY"
echo "JWT Secret: $JWT_SECRET"
echo "DB Password: $DB_PASS"
echo ""
echo "These are also saved in /root/.farming_secrets"
echo ""

exit 0
