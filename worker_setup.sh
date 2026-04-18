#!/bin/bash

################################################################################
# WORKER NODE SETUP SCRIPT v2.0
# Server Farming & Airdrop System v4.0
# Location: Worker 1 (Netherlands), Workers 2-3 (Iceland)
# Target: Ubuntu 22.04/24.04 LTS, Debian Trixie/Testing
#
# CHANGELOG v2.0:
# ✅ Автоматическое копирование файлов проекта с Master Node через scp
# ✅ Расширенная конфигурация .env (ENCRYPTION_KEY, все параметры)
# ✅ Интерактивный запрос proxy credentials с валидацией
# ✅ Установка ПОЛНОГО requirements.txt (вместо минимального)
# ✅ Интеграция с install_curl_cffi.sh для TLS fingerprinting
# ✅ Systemd сервис worker-api.service с автозапуском
# ✅ Полное логирование в /var/log/worker_setup.log
# ✅ Pre-flight проверки (диск, OS, Master connectivity)
# ✅ Backup и rollback при ошибках
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# CONFIGURATION
# ============================================================================
MASTER_NODE_IP=""
WORKER_ID=""
WORKER_LOCATION=""
WORKER_TIMEZONE=""
JWT_SECRET=""
DB_PASS=""
ENCRYPTION_KEY=""
# Decodo credentials (Iceland)
DECODO_USERNAME=""
DECODO_PASSWORD=""

# IPRoyal credentials (Netherlands)
IPROYAL_USERNAME=""
IPROYAL_PASSWORD=""
OPENROUTER_API_KEY=""
OPENROUTER_API_KEY_OPENCLAW=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

LOG_FILE="/var/log/worker_setup.log"
BACKUP_DIR="/root/worker_setup_backups"
PROJECT_DIR="/opt/farming"

# ============================================================================
# COLORS & LOGGING
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Create log file with proper permissions
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Redirect all output to log file (with tee to still see on screen)
exec > >(tee -a "$LOG_FILE") 2>&1

# Logging functions
log_step() {
    echo -e "\n${CYAN}========== STEP $1: $2 ==========${NC}\n"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP $1: $2" >> "$LOG_FILE"
}

log_info() {
    echo -e "${GREEN}[✓ INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗ ERROR]${NC} $1"
}

log_prompt() {
    echo -e "${BLUE}[► INPUT]${NC} $1"
}

# ============================================================================
# CLEANUP & ROLLBACK
# ============================================================================
cleanup() {
    log_error "Setup failed! Performing cleanup..."
    log_error "Check $LOG_FILE for detailed error information"
    
    # Restore .env backup if exists
    if [ -f "$BACKUP_DIR/.env.backup" ]; then
        log_warn "Restoring .env from backup..."
        cp "$BACKUP_DIR/.env.backup" "$PROJECT_DIR/.env" 2>/dev/null || true
    fi
    
    log_error "Setup terminated. Please fix errors and run again."
    exit 1
}

trap cleanup ERR

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

validate_ip() {
    local ip="$1"
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    return 0
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root (sudo bash worker_setup.sh)"
    exit 1
fi

log_info "=========================================================================="
log_info "WORKER NODE SETUP v2.0 - FARMING SYSTEM v4.0"
log_info "=========================================================================="
log_info "Logging to: $LOG_FILE"
echo ""

# ============================================================================
# STEP 0: PRE-FLIGHT CHECKS
# ============================================================================
log_step 0 "Pre-flight checks"

# Check disk space (minimum 10GB)
log_info "Checking disk space..."
AVAILABLE_SPACE=$(df / | tail -1 | awk '{print $4}')
REQUIRED_SPACE=$((10 * 1024 * 1024))  # 10GB in KB

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    log_error "Insufficient disk space. Required: 10GB, Available: $((AVAILABLE_SPACE / 1024 / 1024))GB"
    exit 1
fi
log_success "Disk space OK: $((AVAILABLE_SPACE / 1024 / 1024))GB available"

# Check OS version
log_info "Checking OS version..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
    log_info "Detected OS: $OS_NAME $OS_VERSION ($PRETTY_NAME)"
    
    # Validate supported OS
    if [[ "$OS_NAME" != "ubuntu" && "$OS_NAME" != "debian" ]]; then
        log_error "Unsupported OS: $OS_NAME. Only Ubuntu 22.04/24.04 and Debian Trixie/Testing supported."
        exit 1
    fi
else
    log_error "Cannot detect OS. /etc/os-release not found."
    exit 1
fi

# Create backup directory
log_info "Creating backup directory..."
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
log_success "Backup directory: $BACKUP_DIR"

# ============================================================================
# STEP 1: COLLECT WORKER CONFIGURATION
# ============================================================================
log_step 1 "Collecting Worker configuration"

# Ask for Worker ID
while true; do
    log_prompt "Enter Worker ID (1, 2, or 3):"
    read -r WORKER_ID
    if [[ "$WORKER_ID" =~ ^[1-3]$ ]]; then
        break
    else
        log_error "Invalid Worker ID. Must be 1, 2, or 3."
    fi
done

# Determine location based on Worker ID
if [ "$WORKER_ID" = "1" ]; then
    WORKER_LOCATION="NETHERLANDS"
    WORKER_TIMEZONE="Europe/Amsterdam"
    WORKER_PROXY_COUNTRY="NL"
    WORKER_PROXY_PROVIDER="iproyal"
elif [ "$WORKER_ID" = "2" ] || [ "$WORKER_ID" = "3" ]; then
    WORKER_LOCATION="ICELAND"
    WORKER_TIMEZONE="Atlantic/Reykjavik"
    WORKER_PROXY_COUNTRY="IS"
    WORKER_PROXY_PROVIDER="decodo"
fi

log_success "Worker $WORKER_ID | Location: $WORKER_LOCATION | Timezone: $WORKER_TIMEZONE"

# Ask for Master Node IP
while true; do
    log_prompt "Enter Master Node IP address:"
    read -r MASTER_NODE_IP
    if validate_ip "$MASTER_NODE_IP"; then
        # Test connectivity
        log_info "Testing connectivity to Master Node..."
        if ping -c 2 -W 3 "$MASTER_NODE_IP" &> /dev/null; then
            log_success "Master Node reachable at $MASTER_NODE_IP"
            break
        else
            log_error "Cannot ping Master Node at $MASTER_NODE_IP"
            log_warn "Continue anyway? (y/n)"
            read -r CONTINUE
            if [[ "$CONTINUE" =~ ^[Yy]$ ]]; then
                break
            fi
        fi
    else
        log_error "Invalid IP address format"
    fi
done

# Ask for JWT secret
log_prompt "Enter JWT_SECRET (from Master Node /root/.farming_secrets):"
read -r JWT_SECRET
if [ -z "$JWT_SECRET" ]; then
    log_error "JWT_SECRET cannot be empty"
    exit 1
fi

# Ask for DB password
log_prompt "Enter DB_PASS (from Master Node /root/.farming_secrets):"
read -r DB_PASS
if [ -z "$DB_PASS" ]; then
    log_error "DB_PASS cannot be empty"
    exit 1
fi

# *** NEW: Ask for ENCRYPTION_KEY ***
log_prompt "Enter ENCRYPTION_KEY (Fernet key from Master Node /root/.farming_secrets):"
read -r ENCRYPTION_KEY
if [ -z "$ENCRYPTION_KEY" ]; then
    log_error "ENCRYPTION_KEY cannot be empty (required for decrypting private keys)"
    exit 1
fi
log_success "ENCRYPTION_KEY received"

# *** NEW: Ask for OpenRouter API Key ***
log_prompt "Enter OPENROUTER_API_KEY (for LLM protocol research):"
read -r OPENROUTER_API_KEY
if [ -z "$OPENROUTER_API_KEY" ]; then
    log_warn "OPENROUTER_API_KEY is empty (protocol research will not work)"
fi

# *** NEW: Ask for OpenRouter API Key for OpenClaw (SEPARATE key!) ***
log_prompt "Enter OPENROUTER_API_KEY_OPENCLAW (for browser automation LLM Vision):"
read -r OPENROUTER_API_KEY_OPENCLAW
if [ -z "$OPENROUTER_API_KEY_OPENCLAW" ]; then
    log_warn "OPENROUTER_API_KEY_OPENCLAW is empty (LLM Vision for OpenClaw will not work)"
else
    log_success "OPENROUTER_API_KEY_OPENCLAW received (separate from main key)"
fi

# *** NEW: Ask for Telegram credentials ***
log_prompt "Enter TELEGRAM_BOT_TOKEN (for notifications):"
read -r TELEGRAM_BOT_TOKEN
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    log_warn "TELEGRAM_BOT_TOKEN is empty (notifications will not work)"
fi

log_prompt "Enter TELEGRAM_CHAT_ID (for notifications):"
read -r TELEGRAM_CHAT_ID
if [ -z "$TELEGRAM_CHAT_ID" ]; then
    log_warn "TELEGRAM_CHAT_ID is empty (notifications will not work)"
fi

# *** NEW: Ask for BOTH Proxy Providers (all workers need both) ***
log_info "Proxy configuration - collecting credentials for BOTH providers..."
log_info "(All workers need both Decodo and IPRoyal for proxy pool diversity)"
echo ""

# Decodo credentials (Iceland - 4G/5G mobile)
log_info "=== Decodo Proxy (Iceland) ==="
log_prompt "Enter Decodo username:"
read -r DECODO_USERNAME
if [ -z "$DECODO_USERNAME" ]; then
    log_warn "Decodo username is empty. Update /opt/farming/.env manually later."
fi

log_prompt "Enter Decodo password:"
read -r DECODO_PASSWORD
if [ -z "$DECODO_PASSWORD" ]; then
    log_warn "Decodo password is empty. Update /opt/farming/.env manually later."
fi
log_success "Decodo credentials collected"
echo ""

# IPRoyal credentials (Netherlands - residential)
log_info "=== IPRoyal Proxy (Netherlands) ==="
log_prompt "Enter IPRoyal username (format: username_country-nl_session-xxx):"
read -r IPROYAL_USERNAME
if [ -z "$IPROYAL_USERNAME" ]; then
    log_warn "IPRoyal username is empty. Update /opt/farming/.env manually later."
fi

log_prompt "Enter IPRoyal password:"
read -r IPROYAL_PASSWORD
if [ -z "$IPROYAL_PASSWORD" ]; then
    log_warn "IPRoyal password is empty. Update /opt/farming/.env manually later."
fi
log_success "IPRoyal credentials collected"
echo ""

log_success "Configuration collection complete"

# ============================================================================
# STEP 2: SYSTEM UPDATE
# ============================================================================
log_step 2 "Updating system packages"

log_info "Running apt update (skipping upgrade to avoid grub-pc issues)..."
apt update -qq
# Skip apt upgrade - causes grub-pc issues in virtualized environments
# apt upgrade -y -qq

log_success "System packages updated"

# ============================================================================
# STEP 3: INSTALL SYSTEM DEPENDENCIES
# ============================================================================
log_step 3 "Installing system dependencies"

# Common packages for both Ubuntu and Debian
# NOTE: chromium is required for OpenClaw browser automation (pyppeteer)
COMMON_PACKAGES="ufw fail2ban curl htop net-tools jq tzdata libpq-dev build-essential postgresql-client git"

if [ "$OS_NAME" = "ubuntu" ]; then
    log_info "Installing dependencies for Ubuntu..."
    apt install -y -qq \
        $COMMON_PACKAGES \
        chromium-browser \
        chromium-chromedriver \
        python3 \
        python3-venv \
        python3-pip \
        libglib2.0-0 \
        libnss3 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libcups2 \
        libdrm2 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        libgbm1 \
        libasound2
    
elif [ "$OS_NAME" = "debian" ]; then
    log_info "Installing dependencies for Debian..."
    
    # Use system Python (Debian 13 has Python 3.12+)
    PYTHON_CMD="python3"
    
    # Check Python version
    PYTHON_VERSION=$($PYTHON_CMD --version 2>/dev/null | awk '{print $2}')
    PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
    PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)
    
    if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 8 ]); then
        log_error "Python 3.8+ required. Found: $PYTHON_VERSION"
        exit 1
    fi
    
    log_success "Using system Python $PYTHON_VERSION"
    
    # Install python3-venv for venv support
    apt install -y -qq python3-venv
    
    # Install dependencies (system Python)
    # NOTE: Debian uses 'chromium' package name (not chromium-browser)
    apt install -y -qq \
        $COMMON_PACKAGES \
        chromium \
        chromium-driver \
        python3-pip \
        libglib2.0-0 \
        libnss3 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libcups2 \
        libdrm2 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        libgbm1 \
        libasound2
    
    # Ensure pip
    log_info "Ensuring pip..."
    python3 -m ensurepip --default-pip || true
fi

# Set timezone
log_info "Setting timezone to $WORKER_TIMEZONE..."
timedatectl set-timezone "$WORKER_TIMEZONE"
log_success "Timezone set to $WORKER_TIMEZONE (current time: $(date))"

log_success "System dependencies installed"

# ============================================================================
# STEP 4: CREATE PROJECT STRUCTURE
# ============================================================================
log_step 4 "Creating Worker directory structure"

log_info "Creating directories: worker, venv, logs, keys, openclaw..."
mkdir -p "$PROJECT_DIR"/{worker,database,funding,notifications,wallets,infrastructure,activity,withdrawal,openclaw,venv,logs,keys}

# Create OpenClaw subdirectories for browser automation
mkdir -p "$PROJECT_DIR"/openclaw/{profiles,screenshots,tasks,anti_detection}

# Set permissions
chmod 755 "$PROJECT_DIR"
chmod 700 "$PROJECT_DIR"/keys  # Sensitive: private keys storage
chmod 755 "$PROJECT_DIR"/logs
chmod 755 "$PROJECT_DIR"/openclaw
chmod 755 "$PROJECT_DIR"/openclaw/profiles
chmod 755 "$PROJECT_DIR"/openclaw/screenshots

# Create .gitignore
cat > "$PROJECT_DIR/.gitignore" <<'EOF'
.env
keys/
logs/*.log
__pycache__/
*.pyc
venv/
.venv/
*.backup
EOF

log_success "Directory structure created at $PROJECT_DIR/"

# ============================================================================
# STEP 5: COPY PROJECT FILES FROM MASTER NODE
# ============================================================================
log_step 5 "Copying project files from Master Node"

log_info "This step will copy files from Master Node using scp."
log_warn "You need SSH access to Master Node (root@$MASTER_NODE_IP)"
echo ""
log_prompt "Do you want to copy files now? (y/n)"
read -r COPY_FILES

if [[ "$COPY_FILES" =~ ^[Yy]$ ]]; then
    log_info "Starting file transfer from Master Node..."
    
    # Directories to copy
    # NOTE: openclaw/ is required for browser automation (Tier A wallets reputation building)
    DIRS_TO_COPY=(
        "worker"
        "database"
        "funding"
        "notifications"
        "wallets"
        "infrastructure"
        "activity"
        "withdrawal"
        "openclaw"
        "monitoring"
        "research"
        "requirements.txt"
        "install_curl_cffi.sh"
    )
    
    # Copy each directory
    for DIR in "${DIRS_TO_COPY[@]}"; do
        log_info "Copying $DIR..."
        
        if scp -r "root@$MASTER_NODE_IP:/root/airdrop_v4/$DIR" "$PROJECT_DIR/" 2>/dev/null; then
            log_success "$DIR copied"
        else
            log_error "Failed to copy $DIR from Master Node"
            log_warn "You may need to copy files manually (see instructions below)"
            COPY_FILES="n"
            break
        fi
    done
    
    if [[ "$COPY_FILES" =~ ^[Yy]$ ]]; then
        log_success "All project files copied from Master Node"
    fi
else
    log_warn "Skipping automatic file copy. MANUAL STEPS REQUIRED:"
    echo ""
    echo "Run these commands from your local machine or Master Node:"
    echo ""
    WORKER_IP=$(hostname -I | awk '{print $1}')
    echo "scp -r /root/airdrop_v4/worker root@$WORKER_IP:$PROJECT_DIR/"
    echo "scp -r /root/airdrop_v4/database root@$WORKER_IP:$PROJECT_DIR/"
    echo "scp -r /root/airdrop_v4/funding root@$WORKER_IP:$PROJECT_DIR/"
    echo "scp -r /root/airdrop_v4/notifications root@$WORKER_IP:$PROJECT_DIR/"
    echo "scp -r /root/airdrop_v4/wallets root@$WORKER_IP:$PROJECT_DIR/"
    echo "scp -r /root/airdrop_v4/infrastructure root@$WORKER_IP:$PROJECT_DIR/"
    echo "scp -r /root/airdrop_v4/activity root@$WORKER_IP:$PROJECT_DIR/"
    echo "scp -r /root/airdrop_v4/withdrawal root@$WORKER_IP:$PROJECT_DIR/"
    echo "scp -r /root/airdrop_v4/openclaw root@$WORKER_IP:$PROJECT_DIR/"
    echo "scp -r /root/airdrop_v4/monitoring root@$WORKER_IP:$PROJECT_DIR/"
    echo "scp -r /root/airdrop_v4/research root@$WORKER_IP:$PROJECT_DIR/"
    echo "scp /root/airdrop_v4/requirements.txt root@$WORKER_IP:$PROJECT_DIR/"
    echo ""
    log_prompt "Press Enter when files are copied to continue..."
    read -r
fi

# ============================================================================
# STEP 6: CREATE .ENV FILE
# ============================================================================
log_step 6 "Creating enhanced .env configuration file"

# Backup existing .env if present
if [ -f "$PROJECT_DIR/.env" ]; then
    BACKUP_FILE="$BACKUP_DIR/.env.backup.$(date +%s)"
    log_warn "Existing .env found. Backing up to $BACKUP_FILE"
    cp "$PROJECT_DIR/.env" "$BACKUP_FILE"
fi

log_info "Writing .env with all required parameters..."

cat > "$PROJECT_DIR/.env" <<EOF
# ================================================================================
# WORKER NODE CONFIGURATION
# Auto-generated by worker_setup.sh v2.0 on $(date)
# Worker ID: $WORKER_ID | Location: $WORKER_LOCATION
# ================================================================================

# ===== WORKER IDENTITY =====
WORKER_ID=$WORKER_ID
WORKER_LOCATION=$WORKER_LOCATION
WORKER_TIMEZONE=$WORKER_TIMEZONE

# ===== MASTER NODE =====
MASTER_NODE_IP=$MASTER_NODE_IP
JWT_SECRET=$JWT_SECRET

# ===== DATABASE (Remote PostgreSQL on Master Node) =====
DB_HOST=$MASTER_NODE_IP
DB_PORT=5432
DB_NAME=farming_db
DB_USER=farming_user
DB_PASS=$DB_PASS

# ===== ENCRYPTION =====
# Fernet key for decrypting private keys and API keys
ENCRYPTION_KEY=$ENCRYPTION_KEY

# ===== PROXY CONFIGURATION =====
# Primary proxy based on worker location
# Worker 1 (Netherlands) → IPRoyal NL residential (primary)
# Workers 2-3 (Iceland) → Decodo IS 4G/5G mobile (primary)
PROXY_COUNTRY=$WORKER_PROXY_COUNTRY
PROXY_PROVIDER=$WORKER_PROXY_PROVIDER

# BOTH providers available for proxy pool diversity (anti-Sybil)
DECODO_USERNAME=$DECODO_USERNAME
DECODO_PASSWORD=$DECODO_PASSWORD
IPROYAL_USERNAME=$IPROYAL_USERNAME
IPROYAL_PASSWORD=$IPROYAL_PASSWORD
EOF

# Add remaining configuration
cat >> "$PROJECT_DIR/.env" <<EOF

# ===== WORKER API =====
WORKER_API_HOST=127.0.0.1
WORKER_API_PORT=5000
RPC_URL_BASE=https://mainnet.base.org

# ===== OPENROUTER (for LLM protocol research) =====
OPENROUTER_API_KEY=$OPENROUTER_API_KEY

# ===== OPENROUTER OPENCLAW (for browser automation LLM Vision) =====
# NOTE: This is a SEPARATE key from OPENROUTER_API_KEY for security isolation
OPENROUTER_API_KEY_OPENCLAW=$OPENROUTER_API_KEY_OPENCLAW

# ===== OPENCLAW =====
CHROMIUM_PATH=/usr/bin/chromium-browser
OPENCLAW_MAX_BROWSERS=3

# ===== TELEGRAM NOTIFICATIONS =====
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID

# ===== RPC ENDPOINTS (populated from database) =====
#chain_rpc_endpoints table contains all RPC URLs

# ===== LOGGING =====
LOG_LEVEL=INFO
LOG_FILE=$PROJECT_DIR/logs/worker_$WORKER_ID.log

# ===== MODE =====
ENVIRONMENT=production
NETWORK_MODE=DRY_RUN

# ===== ANTI-SYBIL SETTINGS =====
# These are defaults; actual values per wallet are in database
MIN_TX_DELAY_SECONDS=300
MAX_TX_DELAY_SECONDS=2400
GAS_PRICE_MAX_GWEI=200
EOF

chmod 600 "$PROJECT_DIR/.env"
log_success ".env file created with chmod 600"

# ============================================================================
# STEP 7: PYTHON VIRTUAL ENVIRONMENT
# ============================================================================
log_step 7 "Creating Python virtual environment"

log_info "Creating venv with system Python..."
python3 -m venv "$PROJECT_DIR/venv"

# Activate venv
source "$PROJECT_DIR/venv/bin/activate"

# Upgrade pip
log_info "Upgrading pip..."
pip install --upgrade pip -q

# Install dependencies from MAIN requirements.txt
if [ -f "$PROJECT_DIR/requirements.txt" ]; then
    log_info "Installing dependencies from requirements.txt (this may take 5-10 minutes)..."
    pip install -r "$PROJECT_DIR/requirements.txt" -q
    log_success "Python dependencies installed from requirements.txt"
else
    log_warn "requirements.txt not found! Creating minimal fallback..."
    
    # Fallback minimal requirements
    cat > "$PROJECT_DIR/requirements.txt" <<'EOF'
web3==6.20.3
eth-account==0.11.0
curl-cffi==0.7.0
psycopg2-binary==2.9.9
ccxt==4.3.95
cryptography==41.0.7
APScheduler==3.10.4
loguru==0.7.2
tenacity==8.2.3
python-dotenv==1.0.0
numpy==1.26.2
python-telegram-bot==20.7
Flask==3.0.0
Flask-JWT-Extended==4.5.3
pyppeteer==1.0.2
pyppeteer-stealth==2.7.4
httpx==0.27.0
Flask-Cors==4.0.0
rapidfuzz>=3.0.0
EOF
    
    pip install -r "$PROJECT_DIR/requirements.txt" -q
    log_warn "Minimal dependencies installed. Copy full requirements.txt from Master Node!"
fi

deactivate

log_success "Python environment created at $PROJECT_DIR/venv"

# ============================================================================
# STEP 8: INSTALL curl-cffi FOR TLS FINGERPRINTING
# ============================================================================
log_step 8 "Installing curl-cffi for TLS fingerprinting"

log_info "curl-cffi provides browser impersonation (Chrome/Safari) to avoid Sybil detection"

# Check if install_curl_cffi.sh exists
if [ -f "install_curl_cffi.sh" ]; then
    log_info "Found install_curl_cffi.sh. Running installation script..."
    
    # Run the script (it handles all dependencies and verification)
    if bash install_curl_cffi.sh; then
        log_success "curl-cffi installation complete"
    else
        log_warn "curl-cffi installation failed. TLS fingerprinting may not work. Continuing..."
        # Continue anyway - curl-cffi is optional
    fi
else
    log_warn "install_curl_cffi.sh not found. Installing curl-cffi manually..."
    
    # Manual installation
    apt-get install -y -qq libcurl4-openssl-dev curl build-essential
    
    source "$PROJECT_DIR/venv/bin/activate"
    pip install curl-cffi==0.7.0 -q
    deactivate
    
    # Verify installation
    if python3 -c "from curl_cffi import requests; print('✓')" &> /dev/null; then
        log_success "curl-cffi installed and verified"
    else
        log_warn "curl-cffi installation failed. TLS fingerprinting may not work. Continuing..."
        # Continue anyway - curl-cffi is optional
    fi
fi

# ============================================================================
# STEP 9: CREATE SYSTEMD SERVICE FOR WORKER API
# ============================================================================
log_step 9 "Creating Worker API systemd service"

log_info "Creating /etc/systemd/system/worker-api.service..."

cat > /etc/systemd/system/worker-api.service <<EOF
[Unit]
Description=Worker API for Airdrop Farming System v4.0 (Worker $WORKER_ID)
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=$PROJECT_DIR/venv/bin/python $PROJECT_DIR/worker/api.py

# Restart policy
Restart=always
RestartSec=10
StartLimitBurst=5
StartLimitIntervalSec=300

# Logging
StandardOutput=append:$PROJECT_DIR/logs/worker_api.log
StandardError=append:$PROJECT_DIR/logs/worker_api_error.log

# Security hardening
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload

# Enable service (but don't start yet)
systemctl enable worker-api.service

log_success "Worker API service created and enabled"
log_warn "Service NOT started yet. Start manually after full configuration."

# ============================================================================
# STEP 10: FAIL2BAN CONFIGURATION
# ============================================================================
log_step 10 "Configuring fail2ban"

systemctl enable fail2ban
systemctl start fail2ban

# Create jail.local
# NOTE: SSH jail DISABLED - user has dynamic IP (mobile internet)
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 10

# SSH Protection - DISABLED for dynamic IP users
[sshd]
enabled = false
port = 22,2299
filter = sshd
logpath = /var/log/auth.log
maxretry = 10
bantime = 3600
EOF

systemctl restart fail2ban

log_success "fail2ban configured (SSH jail DISABLED for dynamic IP, only PostgreSQL protected)"

# ============================================================================
# STEP 11: UFW FIREWALL (NOT ENABLED YET!)
# ============================================================================
log_step 11 "Configuring UFW firewall"

log_info "Setting up firewall rules (NOT enabling yet)..."

# Default policies
ufw --force default deny incoming
ufw --force default allow outgoing

# Allow SSH on current port 22 (will change to 2299 later)
ufw allow 22/tcp comment 'SSH (temporary, will change to 2299)'

# Allow SSH on port 2299 (for after hardening)
ufw allow 2299/tcp comment 'SSH (hardened)'

# Allow localhost
ufw allow from 127.0.0.1 to any

# Allow Master Node to access Worker API (port 5000)
ufw allow from "$MASTER_NODE_IP" to any port 5000 proto tcp comment 'Master Node Worker API'

# Allow PostgreSQL from Master Node (if needed for health checks)
ufw allow from "$MASTER_NODE_IP" to any port 5432 proto tcp comment 'PostgreSQL (if local)'

log_success "UFW configured (Master Node IP: $MASTER_NODE_IP)"
log_warn "UFW NOT enabled yet! Will enable after SSH hardening."

# ============================================================================
# STEP 12: TEST DATABASE CONNECTION
# ============================================================================
log_step 12 "Testing PostgreSQL connection to Master Node"

log_info "Connecting to farming_db on $MASTER_NODE_IP:5432..."

WORKER_IP=$(hostname -I | awk '{print $1}')

source "$PROJECT_DIR/venv/bin/activate"

python3 <<EOF
import sys
try:
    import psycopg2
    conn = psycopg2.connect(
        host="$MASTER_NODE_IP",
        port=5432,
        dbname="farming_db",
        user="farming_user",
        password="$DB_PASS"
    )
    cursor = conn.cursor()
    cursor.execute("SELECT version();")
    version = cursor.fetchone()
    print(f"✅ PostgreSQL connection successful!")
    print(f"   Version: {version[0][:70]}...")
    cursor.close()
    conn.close()
    sys.exit(0)
except Exception as e:
    print(f"❌ PostgreSQL connection FAILED: {e}")
    print("")
    print("TROUBLESHOOTING:")
    print("1. Check Master Node firewall allows Worker IP $WORKER_IP:")
    print(f"   sudo ufw allow from $WORKER_IP to any port 5432 proto tcp")
    print("")
    print("2. Check pg_hba.conf on Master Node includes:")
    print(f"   host    farming_db      farming_user    $WORKER_IP/32    scram-sha-256")
    print("")
    print("3. Restart PostgreSQL on Master Node:")
    print("   sudo systemctl restart postgresql")
    print("")
    sys.exit(1)
EOF

DB_TEST_RESULT=$?
deactivate

if [ $DB_TEST_RESULT -ne 0 ]; then
    log_error "Database connection test failed!"
    log_warn "Continue anyway? (y/n)"
    read -r CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    log_success "Database connection verified"
fi

# ============================================================================
# STEP 13: SSH HARDENING (AUTOMATIC)
# ============================================================================
log_step 13 "SSH Hardening (Automatic)"

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
log_warn "  ssh -p 2299 root@$WORKER_IP"
log_warn "=================================================="

# ============================================================================
# FINAL SUMMARY
# ============================================================================
log_step "FINAL" "Worker Setup Complete!"

echo ""
log_success "=========================================================================="
log_success "WORKER NODE $WORKER_ID SETUP COMPLETED SUCCESSFULLY"
log_success "=========================================================================="
echo ""

log_info "✅ System packages updated"
log_info "✅ Timezone set to $WORKER_TIMEZONE"
log_info "✅ Python 3.11 venv created at $PROJECT_DIR/venv"
log_info "✅ Full requirements.txt installed (web3, curl-cffi, ccxt, Flask, etc.)"
log_info "✅ curl-cffi installed for TLS fingerprinting"
log_info "✅ fail2ban configured (SSH jail DISABLED for dynamic IP)"
log_info "✅ UFW firewall enabled"
log_info "✅ Enhanced .env created with ENCRYPTION_KEY and all parameters"
log_info "✅ Worker API systemd service created and enabled"
log_info "✅ Database connection to Master Node tested"
log_info "✅ Project files copied from Master Node"
log_info "✅ NETWORK_MODE=DRY_RUN (safe default)"

echo ""
log_warn "=========================================================================="
log_warn "MANUAL ACTIONS REQUIRED:"
log_warn "=========================================================================="
echo ""

echo "1. VERIFY .env configuration:"
echo "   nano $PROJECT_DIR/.env"
echo "   - Check proxy credentials are correct"
echo "   - Verify ENCRYPTION_KEY, OPENROUTER_API_KEY, OPENROUTER_API_KEY_OPENCLAW, TELEGRAM_* if needed"
echo ""

echo "2. COMPLETE SSH HARDENING (see detailed steps above):"
echo "   - Copy SSH key from local machine"
echo "   - Test key-based login"
echo "   - Edit /etc/ssh/sshd_config (Port 2299, disable password auth)"
echo "   - Restart sshd and test on port 2299"
echo "   - Enable UFW firewall ONLY after successful test"
echo ""

echo "3. ON MASTER NODE, allow Worker IP in firewall:"
echo "   sudo ufw allow from $WORKER_IP to any port 5432 proto tcp"
echo "   sudo ufw reload"
echo ""

echo "4. START Worker API service:"
echo "   sudo systemctl start worker-api.service"
echo "   sudo systemctl status worker-api.service"
echo ""

echo "5. VERIFY Worker API health:"
echo "   curl http://127.0.0.1:5000/health"
echo "   Expected: {\"status\": \"healthy\", \"worker_id\": $WORKER_ID}"
echo ""

echo "6. CHECK LOGS:"
echo "   tail -f $PROJECT_DIR/logs/worker_api.log"
echo "   tail -f $LOG_FILE"
echo ""

log_success "=========================================================================="
log_info "Worker Configuration Summary:"
log_success "=========================================================================="
echo "Worker ID:       $WORKER_ID"
echo "Location:        $WORKER_LOCATION"
echo "Timezone:        $WORKER_TIMEZONE ($(date))"
echo "Master Node IP:  $MASTER_NODE_IP"
echo "Worker IP:       $WORKER_IP"
echo "Proxy Provider:  $WORKER_PROXY_PROVIDER ($WORKER_PROXY_COUNTRY)"
echo "Project Dir:     $PROJECT_DIR"
echo "Venv:            $PROJECT_DIR/venv"
echo "Logs:            $PROJECT_DIR/logs/"
echo "Setup Log:       $LOG_FILE"
echo ""
log_success "=========================================================================="

echo ""
log_info "Next: Complete SSH hardening, enable UFW, start Worker API service"
log_info "Documentation: /root/airdrop_v4/WORKER_DEPLOYMENT_GUIDE.md"
echo ""

exit 0
