#!/usr/bin/env python3
"""
Worker API — Module 8
=====================
Flask REST API на Workers для выполнения транзакций от Master Node

КРИТИЧНО:
- Слушает ТОЛЬКО 127.0.0.1:5000 (localhost only!)
- JWT authentication (токен от Master Node)
- Доступ через SSH tunnel: ssh -L 5000:127.0.0.1:5000 worker1
- web3.py integration для выполнения on-chain транзакций

Architecture:
    Master Node → SSH Tunnel → Worker API (127.0.0.1:5000) → web3.py → EVM Networks

Endpoints:
   POST /execute_transaction       — Execute on-chain transaction (web3.py)
   POST /api/execute_withdrawal   — Execute withdrawal to cold wallet (CRITICAL SECURITY)
   GET  /health                    — Health check (status, balances, last_tx)
   GET  /balances                  — Get balances for all assigned wallets (30)
   POST /pause                     — Pause Worker activity
   POST /resume                    — Resume Worker activity
   GET  /check_cex_connections     — Check CEX API connections for all 18 subaccounts

Security:
    - JWT required для всех endpoints (кроме /health)
    - Whitelist Master Node IP (через UFW)
    - No external access (127.0.0.1 only)
    - Private keys encrypted (decryption on-demand)

Usage:
    # Start Worker API (production):
    python worker/api.py --worker-id 1 --host 127.0.0.1 --port 5000
    
    # Start Worker API (development, with debug):
    python worker/api.py --worker-id 1 --debug

Author: Airdrop Farming System v4.0
Created: 2026-02-24
"""

import os
import sys
from pathlib import Path
from typing import Dict, Optional, List, Tuple
from decimal import Decimal
from datetime import datetime, timedelta, timezone

# Добавить parent directory для импорта
sys.path.insert(0, str(Path(__file__).parent.parent))

from flask import Flask, request, jsonify
from flask_jwt_extended import (
    JWTManager,
    jwt_required,
    create_access_token,
    get_jwt_identity
)
from loguru import logger
from infrastructure.env_loader import load_env

# Load .env file (supports both production and local dev)
load_env()

from database.db_manager import DatabaseManager
from activity.proxy_manager import ProxyManager

# Import CEXManager for CEX API connection checks
from funding.cex_integration import CEXManager

# Import TransactionExecutor for on-chain transaction execution
from activity.executor import TransactionExecutor

# Web3 and crypto imports for withdrawal transactions
from web3 import Web3
from eth_account import Account
from cryptography.fernet import Fernet

# Import custom exceptions for proxy security
from activity.exceptions import ProxyRequiredError


# =============================================================================
# CONFIGURATION
# =============================================================================

JWT_SECRET = os.getenv('JWT_SECRET')
WORKER_ID = int(os.getenv('WORKER_ID', '0'))
FERNET_KEY = os.getenv('FERNET_KEY') or os.getenv('ENCRYPTION_KEY')  # Backward compat

if not JWT_SECRET:
    logger.critical("JWT_SECRET not set in .env. Worker API cannot start.")
    sys.exit(1)

if WORKER_ID == 0:
    logger.warning("WORKER_ID not set in .env. Specify --worker-id argument.")

# Initialize Fernet for key decryption
if FERNET_KEY:
    fernet = Fernet(FERNET_KEY.encode())
else:
    logger.critical("FERNET_KEY not set in .env. Cannot decrypt private keys.")
    fernet = None


# Global pause flag
WORKER_PAUSED = False


# =============================================================================
# FLASK APP INITIALIZATION
# =============================================================================

app = Flask(__name__)
app.config['JWT_SECRET_KEY'] = JWT_SECRET
# Security fix: JWT tokens now expire after 24 hours
app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(hours=24)

jwt = JWTManager(app)

# Database connection
db = DatabaseManager()

# Proxy Manager for wallet-to-proxy mapping
proxy_manager = ProxyManager(db=db)

# CEX Manager for API connection checks
cex_manager = CEXManager()

# Transaction Executor for on-chain operations
executor = TransactionExecutor()


# =============================================================================
# HELPER FUNCTIONS FOR WITHDRAWAL
# =============================================================================

def decrypt_private_key(encrypted_key: str) -> str:
    """
    Decrypt private key from database.
    
    Args:
        encrypted_key: Encrypted private key (base64 string)
    
    Returns:
        Decrypted private key (hex string)
    
    Raises:
        ValueError: If encryption key not set or decryption fails
    
    Security:
        - Uses Fernet symmetric encryption
        - Requires ENCRYPTION_KEY from .env
        - Raises ValueError on decryption failure
    """
    global fernet
    
    if not fernet:
        raise ValueError("ENCRYPTION_KEY not configured. Cannot decrypt private keys.")
    
    try:
        return fernet.decrypt(encrypted_key.encode()).decode()
    except Exception as e:
        logger.error(f"Failed to decrypt private key | Error: {e}")
        raise ValueError("Invalid encryption key or corrupted private key")


def execute_withdrawal_tx(
    private_key: str,
    destination: str,
    amount_usdt: Decimal,
    chain_id: Optional[int] = None,  # Required - no default
    wallet_id: Optional[int] = None  # for proxy lookup
) -> Tuple[str, int, float]:
    """
    Execute withdrawal transaction via web3.py with wallet's assigned proxy.
    
    CRITICAL: Each wallet uses its own proxy for anti-Sybil protection.
    This ensures 90 unique IP addresses (1 per wallet) instead of 3 Worker IPs.
    
    Args:
        private_key: Decrypted private key (hex string)
        destination: Destination address (cold wallet)
        amount_usdt: Amount in USDT
        chain_id: EVM chain ID (required - loaded from wallet's withdrawal_network)
        wallet_id: Wallet database ID. If provided, uses wallet's proxy.
    
    Returns:
        Tuple: (tx_hash, gas_used, gas_price_gwei)
    
    Raises:
        ValueError: If chain_id not provided, balance insufficient, gas too high, or transaction fails
    
    Security:
        - Balance check before execution
        - Gas estimation with +20% buffer
        - Destination address validation (checksum)
        - Private key NEVER logged
    """
    global proxy_manager, db
    
    # Validate chain_id is provided
    if chain_id is None:
        raise ValueError("chain_id is required - must be loaded from wallet's withdrawal_network")
    
    # ✅ Get RPC URL from database by chain_id
    try:
        chain_info = db.execute_query(
            "SELECT url FROM chain_rpc_endpoints WHERE chain_id = %s AND is_active = TRUE LIMIT 1",
            (chain_id,),
            fetch='one'
        )
        
        if not chain_info:
            raise ValueError(f"No active RPC endpoint found for chain_id: {chain_id}")
        
        rpc_url = chain_info['url']
        logger.info(f"Using RPC from DB | Chain ID: {chain_id} | RPC: {rpc_url[:50]}...")
    except Exception as e:
        logger.error(f"Failed to get RPC URL for chain {chain_id}: {e}")
        raise ValueError(f"Cannot get RPC URL for chain {chain_id}: {e}")
    
    # Initialize web3 with or without proxy
    if wallet_id:
        # ✅ Get wallet's assigned proxy
        try:
            proxy_config = proxy_manager.get_wallet_proxy(wallet_id)
            proxy_dict = proxy_manager.build_proxy_dict(proxy_config)
            
            logger.info(
                f"Using proxy for withdrawal | Wallet: {wallet_id} | "
                f"Provider: {proxy_config['provider']} | "
                f"Country: {proxy_config['country_code']}"
            )
            
            # Create session with proxy using curl_cffi
            from infrastructure.identity_manager import get_curl_session
            
            proxy_url = f"{proxy_config['protocol']}://{proxy_config['username']}:{proxy_config['password']}@{proxy_config['ip_address']}:{proxy_config['port']}"
            session = get_curl_session(wallet_id, proxy_url)
            
            # Create Web3 with proxy
            w3 = Web3(
                Web3.HTTPProvider(
                    rpc_url,
                    request_kwargs={'timeout': 60},
                    session=session
                )
            )
            
        except ValueError as e:
            logger.error(f"Failed to get proxy for wallet {wallet_id}: {e}")
            raise ProxyRequiredError(
                f"Cannot execute transaction without proxy for wallet {wallet_id}. "
                f"All transactions must use wallet-specific proxy. Error: {e}"
            )
    else:
        # No wallet_id provided - this should not happen in production
        raise ProxyRequiredError(
            "wallet_id is required for all withdrawal operations. "
            "Direct connections are forbidden."
        )
    
    if not w3.is_connected():
        raise ValueError(f"Cannot connect to RPC: {rpc_url}")
    
    # Create account from private key
    account = Account.from_key(private_key)
    
    # Validate destination address
    if not Web3.is_checksum_address(destination):
        destination = Web3.to_checksum_address(destination)
    
    # Get ETH price from oracle (with fallback to $3000)
    from infrastructure.price_oracle import get_eth_price_sync
    eth_price = get_eth_price_sync(db)
    
    # Convert USDT to ETH
    amount_eth = amount_usdt / eth_price
    
    # Check balance
    balance_wei = w3.eth.get_balance(account.address)
    balance_eth = Decimal(str(w3.from_wei(balance_wei, 'ether')))
    
    if balance_eth < amount_eth:
        raise ValueError(
            f"Insufficient balance: {balance_eth:.4f} ETH < {amount_eth:.4f} ETH required"
        )
    
    # Estimate gas
    try:
        gas_estimate = w3.eth.estimate_gas({
            'from': account.address,
            'to': destination,
            'value': w3.to_wei(amount_eth, 'ether')
        })
    except Exception as e:
        raise ValueError(f"Gas estimation failed: {e}")
    
    gas_limit = int(gas_estimate * 1.2)  # +20% buffer
    
    # Get gas price
    gas_price_wei = w3.eth.gas_price
    gas_price_gwei = float(w3.from_wei(gas_price_wei, 'gwei'))
    
    # Check gas price (max 200 gwei for safety)
    if gas_price_gwei > 200:
        raise ValueError(
            f"Gas price too high: {gas_price_gwei:.1f} gwei > 200 gwei (max allowed)"
        )
    
    # Build transaction
    tx = {
        'from': account.address,
        'to': destination,
        'value': w3.to_wei(amount_eth, 'ether'),
        'gas': gas_limit,
        'gasPrice': gas_price_wei,
        'nonce': w3.eth.get_transaction_count(account.address),
        'chainId': chain_id
    }
    
    # Sign and send transaction
    signed_tx = account.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed_tx.rawTransaction)
    
    # Wait for receipt (timeout: 120 seconds)
    try:
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
    except Exception as e:
        raise ValueError(f"Transaction receipt timeout: {e}")
    
    if receipt['status'] != 1:
        raise ValueError(f"Transaction failed on-chain: status = {receipt['status']}")
    
    return (
        tx_hash.hex(),
        receipt['gasUsed'],
        gas_price_gwei
    )


# =============================================================================
# ENDPOINTS
# =============================================================================

@app.route('/health', methods=['GET'])
def health_check():
    """
    Health check endpoint (NO JWT required).
    
    Returns:
        JSON with status, worker_id, last_heartbeat, paused
    
    Example:
        $ curl http://127.0.0.1:5000/health
        {"status": "healthy", "worker_id": 1, "paused": false, ...}
    """
    try:
        # Update heartbeat
        if WORKER_ID > 0:
            db.update_worker_heartbeat(WORKER_ID)
        
        # Get worker info
        worker = db.get_worker_node(WORKER_ID) if WORKER_ID > 0 else None
        
        response = {
            'status': 'healthy',
            'worker_id': WORKER_ID,
            'paused': WORKER_PAUSED,
            'last_heartbeat': worker['last_heartbeat'].isoformat() if worker and worker['last_heartbeat'] else None,
            'location': worker['location'] if worker else 'Unknown',
            'timezone': worker['timezone'] if worker else 'Unknown',
            'timestamp': datetime.utcnow().isoformat()
        }
        
        return jsonify(response), 200
    
    except Exception as e:
        logger.error(f"Health check failed | Error: {e}")
        return jsonify({
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }), 500


@app.route('/execute_transaction', methods=['POST'])
@jwt_required()
def execute_transaction():
    """
    Execute on-chain transaction via web3.py.
    
    JWT required. Called by Master Node's TaskExecutor.
    
    Request JSON:
        {
            "wallet_id": 42,
            "tx_type": "SWAP",
            "protocol_action_id": 15,
            "amount_usdt": 12.34,
            "params": {
                "token_in": "ETH",
                "token_out": "0x1234...",
                "slippage": 0.5
            }
        }
    
    Response JSON (success):
        {
            "success": true,
            "tx_hash": "0xabcd...",
            "gas_used": 150000,
            "gas_price_gwei": 15.3,
            "timestamp": "2026-02-24T18:15:00Z"
        }
    
    Response JSON (failure):
        {
            "success": false,
            "error": "Insufficient gas"
        }
    """
    current_identity = get_jwt_identity()
    
    try:
        # Validate request
        data = request.get_json()
        if not data:
            return jsonify({'success': False, 'error': 'No JSON data provided'}), 400
        
        wallet_id = data.get('wallet_id')
        tx_type = data.get('tx_type')
        protocol_action_id = data.get('protocol_action_id')
        amount_usdt = data.get('amount_usdt')
        params = data.get('params', {})
        
        if not all([wallet_id, tx_type, protocol_action_id]):
            return jsonify({'success': False, 'error': 'Missing required fields'}), 400
        
        # Check if Worker is paused
        if WORKER_PAUSED:
            logger.warning(f"Transaction rejected (Worker paused) | Wallet: {wallet_id}")
            return jsonify({'success': False, 'error': 'Worker is paused'}), 403
        
        logger.info(
            f"Transaction request received | Wallet: {wallet_id} | "
            f"Type: {tx_type} | Protocol Action: {protocol_action_id} | "
            f"Requested by: {current_identity}"
        )
        
        # Execute transaction via TransactionExecutor
        result = executor.execute_contract_function(
            wallet_id=wallet_id,
            protocol_action_id=protocol_action_id,
            params=params or {},
            gas_preference=params.get('gas_preference', 'normal') if params else 'normal'
        )
        
        return jsonify({
            'success': True,
            'tx_hash': result['tx_hash'],
            'gas_used': result['gas_used'],
            'gas_price_gwei': float(result.get('gas_price_gwei', 0)),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }), 200
    
    except Exception as e:
        logger.exception(f"Transaction execution error | Error: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/execute_withdrawal', methods=['POST'])
@jwt_required()
def execute_withdrawal():
    """
    Execute withdrawal transaction (CRITICAL: NO PRIVATE KEY IN REQUEST)
    
    JWT required. Called by Master Node's WithdrawalOrchestrator.
    
    КРИТИЧНО:
    - Private key NEVER transmitted over network
    - Worker retrieves encrypted key from local DB
    - Decrypts in-memory only
    - Immediately discards key after signing
    
    Request JSON:
        {
            "wallet_address": "0x1234...",
            "destination": "0xABCD...",
            "amount_usdt": "123.45",
            "operation": "withdrawal"
        }
    
    Response JSON (success):
        {
            "status": "success",
            "tx_hash": "0xabcd...",
            "gas_used": 21000,
            "gas_price_gwei": 15.3,
            "timestamp": "2026-02-26T12:00:00Z"
        }
    
    Response JSON (failure):
        {
            "status": "error",
            "error": "Insufficient balance"
        }
    """
    current_identity = get_jwt_identity()
    private_key = None  # For cleanup in finally block
    
    try:
        # 1. Validate request
        data = request.get_json()
        if not data:
            return jsonify({'status': 'error', 'error': 'No JSON data provided'}), 400
        
        wallet_address = data.get('wallet_address')
        destination = data.get('destination')
        amount_usdt_str = data.get('amount_usdt', '0')
        
        if not all([wallet_address, destination, amount_usdt_str]):
            return jsonify({
                'status': 'error',
                'error': 'Missing required fields: wallet_address, destination, amount_usdt'
            }), 400
        
        # Parse amount
        try:
            amount_usdt = Decimal(amount_usdt_str)
        except Exception:
            return jsonify({'status': 'error', 'error': 'Invalid amount format'}), 400
        
        # Minimum amount check ($10)
        if amount_usdt < Decimal('10'):
            return jsonify({
                'status': 'error',
                'error': f'Amount too low: {amount_usdt} USDT (minimum: $10)'
            }), 400
        
        # 2. Check if Worker is paused
        if WORKER_PAUSED:
            logger.warning(
                f"Withdrawal rejected (Worker paused) | Wallet: {wallet_address[:10]}..."
            )
            return jsonify({'status': 'error', 'error': 'Worker is paused'}), 403
        
        logger.info(
            f"Withdrawal request received | Wallet: {wallet_address[:10]}... | "
            f"Amount: {amount_usdt} USDT | Destination: {destination[:10]}... | "
            f"Requested by: {current_identity}"
        )
        
        # 3. CRITICAL: Anti-Sybil guard - check if destination is another farm wallet
        internal_wallet_check = db.execute_query(
            "SELECT id FROM wallets WHERE address = %s",
            (destination.lower(),),
            fetch='one'
        )
        
        if internal_wallet_check:
            logger.error(
                f"Internal transfer blocked | Destination {destination[:10]}... is farm wallet ID {internal_wallet_check['id']}"
            )
            return jsonify({
                'status': 'error',
                'error': 'Internal transfers blocked: destination is another farm wallet. Use CEX-only funding.'
            }), 403
        
        # 4. ⚠️ CRITICAL: Retrieve encrypted key FROM LOCAL DB
        # JOIN with worker_nodes to get worker_id (1/2/3) instead of serial id
        wallet = db.execute_query(
            """SELECT w.id, w.encrypted_private_key, wn.worker_id 
               FROM wallets w 
               JOIN worker_nodes wn ON w.worker_node_id = wn.id 
               WHERE w.address = %s""",
            (wallet_address,),
            fetch='one'
        )
        
        if not wallet:
            logger.error(f"Wallet not found | Address: {wallet_address}")
            return jsonify({'status': 'error', 'error': 'Wallet not found'}), 404
        
        # Renumbered: 5. Verify wallet is assigned to THIS worker
        if wallet['worker_id'] != WORKER_ID:
            logger.warning(
                f"Wallet {wallet_address} not assigned to this Worker | "
                f"Expected Worker: {wallet['worker_id']} | Current: {WORKER_ID}"
            )
            return jsonify({
                'status': 'error',
                'error': 'Wallet not assigned to this worker'
            }), 403
        
        # Renumbered: 6. ⚠️ CRITICAL: Decrypt private key (in-memory only)
        encrypted_key = wallet['encrypted_private_key']
        
        try:
            private_key = decrypt_private_key(encrypted_key)
        except ValueError as e:
            logger.error(f"Failed to decrypt private key for {wallet_address[:10]}... | Error: {e}")
            return jsonify({'status': 'error', 'error': 'Failed to decrypt wallet key'}), 500
        
        # Renumbered: 7. Get withdrawal network from wallet
        try:
            wallet_network = db.execute_query(
                "SELECT withdrawal_network FROM wallets WHERE id = %s",
                (wallet['id'],),
                fetch='one'
            )
            
            if wallet_network and wallet_network['withdrawal_network']:
                # Get chain_id by network name
                chain_info = db.execute_query(
                    "SELECT chain_id FROM chain_rpc_endpoints WHERE chain_name = %s LIMIT 1",
                    (wallet_network['withdrawal_network'],),
                    fetch='one'
                )
                
                if chain_info:
                    withdrawal_chain_id = chain_info['chain_id']
                    logger.info(f"Using wallet withdrawal network | Wallet: {wallet['id']} | Network: {wallet_network['withdrawal_network']} | Chain ID: {withdrawal_chain_id}")
                else:
                    logger.error(f"Chain not found for network: {wallet_network['withdrawal_network']}")
                    return jsonify({'status': 'error', 'error': f'Unknown withdrawal network: {wallet_network["withdrawal_network"]}'}), 400
            else:
                logger.error(f"No withdrawal_network set for wallet {wallet['id']}")
                return jsonify({'status': 'error', 'error': 'Wallet has no withdrawal_network configured'}), 400
            
            # Renumbered: 8. Execute withdrawal transaction WITH wallet's proxy and correct chain
            tx_hash, gas_used, gas_price = execute_withdrawal_tx(
                private_key=private_key,
                destination=destination,
                amount_usdt=amount_usdt,
                chain_id=withdrawal_chain_id,  # ✅ Use wallet's withdrawal network
                wallet_id=wallet['id']  # Use wallet's assigned proxy
            )
        except ValueError as e:
            logger.warning(f"Withdrawal failed | Wallet: {wallet_address[:10]}... | Error: {e}")
            return jsonify({'status': 'error', 'error': str(e)}), 400
        except Exception as e:
            logger.exception(f"Withdrawal execution error | Wallet: {wallet_address[:10]}... | Error: {e}")
            return jsonify({'status': 'error', 'error': f'Execution error: {e}'}), 500
        
        # Renumbered: 9. ⚠️ CRITICAL: Immediately discard private key from memory
        del private_key
        private_key = None
        
        # Renumbered: 10. Log to system_events
        try:
            db.log_system_event(
                event_type='withdrawal_completed',
                severity='info',
                message=f"Withdrawal completed: {amount_usdt} USDT",
                metadata={
                    'wallet_address': wallet_address,
                    'destination': destination,
                    'amount_usdt': str(amount_usdt),
                    'tx_hash': tx_hash,
                    'gas_used': gas_used,
                    'gas_price_gwei': gas_price
                }
            )
        except Exception as log_error:
            logger.warning(f"Failed to log withdrawal event: {log_error}")
        
        # Renumbered: 11. Return success
        logger.info(
            f"Withdrawal completed | TX: {tx_hash[:10]}... | "
            f"Wallet: {wallet_address[:10]}... | Amount: {amount_usdt} USDT | "
            f"Gas: {gas_used} @ {gas_price:.1f} gwei"
        )
        
        return jsonify({
            'status': 'success',
            'tx_hash': tx_hash,
            'gas_used': gas_used,
            'gas_price_gwei': gas_price,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }), 200
    
    except Exception as e:
        logger.exception(f"Withdrawal execution error | Error: {e}")
        return jsonify({'status': 'error', 'error': str(e)}), 500
    
    finally:
        # ⚠️ CRITICAL: Always clean up private key from memory
        if private_key is not None:
            try:
                del private_key
            except Exception:
                pass


@app.route('/balances', methods=['GET'])
@jwt_required()
def get_balances():
    """
    Get balances for all wallets assigned to this Worker.
    
    JWT required.
    
    Response JSON:
        {
            "worker_id": 1,
            "total_wallets": 30,
            "balances": [
                {"wallet_id": 1, "address": "0x...", "balance_eth": 0.15, "balance_usd": 450.0},
                ...
            ],
            "total_usd": 13500.0
        }
    """
    current_identity = get_jwt_identity()
    
    try:
        # Get wallets assigned to this Worker
        wallets = db.get_wallets_by_worker(WORKER_ID)
        
        if not wallets:
            return jsonify({
                'worker_id': WORKER_ID,
                'total_wallets': 0,
                'balances': [],
                'total_usd': 0.0
            }), 200
        
        logger.info(f"Balance request | Worker: {WORKER_ID} | Wallets: {len(wallets)} | Requested by: {current_identity}")
        
        # Fetch actual on-chain balances via web3.py
        from infrastructure.identity_manager import get_curl_session
        
        balances = []
        total_usd = 0.0
        
        # Get ETH price from oracle
        from infrastructure.price_oracle import get_eth_price_sync
        eth_price = float(get_eth_price_sync(db))
        
        for wallet in wallets:
            try:
                proxy_config = proxy_manager.get_wallet_proxy(wallet['id'])
                proxy_url = (
                    f"{proxy_config['protocol']}://"
                    f"{proxy_config['username']}:{proxy_config['password']}"
                    f"@{proxy_config['ip_address']}:{proxy_config['port']}"
                )
                session = get_curl_session(wallet['id'], proxy_url)
                
                rpc_url = os.getenv('RPC_URL_BASE', 'https://mainnet.base.org')
                w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={'timeout': 10}, session=session))
                
                balance_wei = w3.eth.get_balance(Web3.to_checksum_address(wallet['address']))
                balance_eth = float(w3.from_wei(balance_wei, 'ether'))
                balance_usd = balance_eth * eth_price
                total_usd += balance_usd
                
                balances.append({
                    'wallet_id': wallet['id'],
                    'address': wallet['address'],
                    'balance_eth': balance_eth,
                    'balance_usd': balance_usd
                })
            except Exception as e:
                logger.warning(f"Balance fetch failed | Wallet: {wallet['id']} | Error: {e}")
                balances.append({
                    'wallet_id': wallet['id'],
                    'address': wallet['address'],
                    'balance_eth': 0.0,
                    'balance_usd': 0.0,
                    'error': str(e)
                })
        
        return jsonify({
            'worker_id': WORKER_ID,
            'total_wallets': len(wallets),
            'balances': balances,
            'total_usd': total_usd,
            'timestamp': datetime.utcnow().isoformat()
        }), 200
    
    except Exception as e:
        logger.exception(f"Balance fetch error | Error: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/pause', methods=['POST'])
@jwt_required()
def pause_worker():
    """
    Pause Worker activity (emergency).
    
    JWT required. Typically called during /panic command.
    """
    current_identity = get_jwt_identity()
    global WORKER_PAUSED
    
    WORKER_PAUSED = True
    
    logger.warning(f"Worker PAUSED | Worker: {WORKER_ID} | Requested by: {current_identity}")
    
    return jsonify({
        'success': True,
        'worker_id': WORKER_ID,
        'paused': True,
        'timestamp': datetime.utcnow().isoformat()
    }), 200


@app.route('/resume', methods=['POST'])
@jwt_required()
def resume_worker():
    """
    Resume Worker activity after pause.
    
    JWT required. Called after /panic → /resume.
    """
    current_identity = get_jwt_identity()
    global WORKER_PAUSED
    
    WORKER_PAUSED = False
    
    logger.info(f"Worker RESUMED | Worker: {WORKER_ID} | Requested by: {current_identity}")
    
    return jsonify({
        'success': True,
        'worker_id': WORKER_ID,
        'paused': False,
        'timestamp': datetime.utcnow().isoformat()
    }), 200


@app.route('/check_cex_connections', methods=['GET'])
@jwt_required()
def check_cex_connections():
    """
    Проверка подключений ко всем CEX субаккаунтам.
    
    JWT required. Используется для мониторинга и диагностики.
    
    Проверяет все 18 субаккаунтов (5 бирж: OKX, Binance, Bybit, KuCoin, MEXC)
    и возвращает статус подключения для каждого.
    
    Response JSON (success):
        {
            "success": true,
            "total_subaccounts": 18,
            "checked_at": "2026-03-20T11:30:00Z",
            "results": [
                {
                    "subaccount_id": 1,
                    "exchange": "bybit",
                    "subaccount_name": "AlphaTradingStrategy",
                    "status": "ok",
                    "balance_usdt": 1250.45,
                    "response_time_ms": 342
                },
                {
                    "subaccount_id": 2,
                    "exchange": "binance",
                    "subaccount_name": "BetaFarming",
                    "status": "error",
                    "error_code": "INVALID_API_KEY",
                    "error_message": "API key expired or invalid",
                    "response_time_ms": 156
                }
            ],
            "summary": {
                "successful": 16,
                "failed": 2,
                "total_response_time_ms": 4521
            }
        }
    
    Response JSON (failure):
        {
            "success": false,
            "error": "Database connection failed",
            "timestamp": "2026-03-20T11:30:00Z"
        }
    """
    current_identity = get_jwt_identity()
    
    try:
        logger.info(f"CEX connection check requested by {current_identity}")
        
        # Проверить все подключения через CEXManager
        result = cex_manager.check_all_connections()
        
        return jsonify(result), 200
    
    except Exception as e:
        logger.exception(f"CEX connection check failed | Error: {e}")
        return jsonify({
            'success': False,
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }), 500


# =============================================================================
# JWT TOKEN GENERATION (для Master Node)
# =============================================================================

@app.route('/generate_token', methods=['POST'])
def generate_token():
    """
    Generate JWT token for Master Node.
    
    Request JSON:
        {"secret": "JWT_SECRET_FROM_ENV"}
    
    Response JSON:
        {"access_token": "eyJ0eXAiOi..."}
    
    NOTE: This endpoint should be called ONCE during setup, then token stored in Master Node.
    В production можно удалить после initial setup.
    """
    data = request.get_json()
    
    # Use JWT_SECRET for authorization (same as master node)
    jwt_secret = os.getenv('JWT_SECRET')
    
    if not jwt_secret:
        logger.critical("JWT_SECRET not configured in environment")
        return jsonify({'error': 'Server configuration error'}), 500
    
    if data.get('secret') != jwt_secret:
        logger.warning("Token generation failed | Invalid secret")
        return jsonify({'error': 'Unauthorized'}), 401
    
    # Create token with identity='master_node'
    access_token = create_access_token(identity='master_node')
    
    logger.info(f"JWT token generated for Master Node | Worker: {WORKER_ID}")
    
    return jsonify({'access_token': access_token}), 200


# =============================================================================
# ERROR HANDLERS
# =============================================================================

@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors."""
    return jsonify({'error': 'Endpoint not found'}), 404


@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors."""
    logger.error(f"Internal server error | Error: {error}")
    return jsonify({'error': 'Internal server error'}), 500


@jwt.unauthorized_loader
def unauthorized_callback(error):
    """Handle unauthorized requests (missing JWT)."""
    logger.warning(f"Unauthorized API request | Error: {error}")
    return jsonify({'error': 'Authorization required (JWT token missing)'}), 401


@jwt.invalid_token_loader
def invalid_token_callback(error):
    """Handle invalid JWT tokens."""
    logger.warning(f"Invalid JWT token | Error: {error}")
    return jsonify({'error': 'Invalid JWT token'}), 401


# =============================================================================
# CLI INTERFACE
# =============================================================================

def main():
    """CLI entry point — start Worker API server."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Worker API — Module 8')
    parser.add_argument('--worker-id', type=int, help='Worker ID (1, 2, or 3)')
    parser.add_argument('--host', type=str, default='127.0.0.1', help='Host to bind (default: 127.0.0.1)')
    parser.add_argument('--port', type=int, default=5000, help='Port to bind (default: 5000)')
    parser.add_argument('--debug', action='store_true', help='Enable Flask debug mode')
    
    args = parser.parse_args()
    
    # Override WORKER_ID if provided
    global WORKER_ID
    if args.worker_id:
        WORKER_ID = args.worker_id
        logger.info(f"Worker ID set from argument: {WORKER_ID}")
    
    if WORKER_ID == 0:
        print("❌ ERROR: WORKER_ID not set")
        print("Solutions:")
        print("  1. Set WORKER_ID in .env: WORKER_ID=1")
        print("  2. Use --worker-id argument: python worker/api.py --worker-id 1")
        sys.exit(1)
    
    # Verify JWT secret
    if not JWT_SECRET:
        print("❌ ERROR JWT_SECRET not set in .env")
        print("Run: grep JWT_SECRET /root/.farming_secrets")
        sys.exit(1)
    
    # Security warning if not localhost
    if args.host != '127.0.0.1':
        logger.critical(
            f"⚠️  SECURITY WARNING: Binding to {args.host} instead of 127.0.0.1!\n"
            f"   This exposes Worker API to external access.\n"
            f"   Recommended: Only bind to 127.0.0.1 for security."
        )
        
        confirm = input(f"Proceed with host={args.host}? (yes/no): ")
        if confirm.lower() != 'yes':
            print("❌ Aborted. Use --host 127.0.0.1")
            sys.exit(0)
    
    print(f"\n{'=' * 60}")
    print(f"🚀 Worker API Server — Module 8")
    print(f"{'=' * 60}")
    print(f"Worker ID:  {WORKER_ID}")
    print(f"Host:       {args.host}")
    print(f"Port:       {args.port}")
    print(f"Debug:      {args.debug}")
    print(f"JWT Auth:   ✅ Enabled")
    print(f"{'=' * 60}\n")
    
    # Log startup
    logger.info(
        f"Worker API starting | Worker: {WORKER_ID} | "
        f"Host: {args.host} | Port: {args.port}"
    )
    
    # Start Flask server
    try:
        app.run(
            host=args.host,
            port=args.port,
            debug=args.debug,
            threaded=True  # Handle concurrent requests
        )
    except KeyboardInterrupt:
        print("\n⏹  Worker API stopped")
        logger.info("Worker API shut down gracefully")
    except Exception as e:
        logger.exception(f"Worker API crashed | Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
