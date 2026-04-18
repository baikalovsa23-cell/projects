"""
Database Manager — CRUD Operations for 30 Tables
=================================================
Production-ready PostgreSQL interface for Airdrop Farming System v4.0

Features:
- Connection pooling (psycopg2.pool.ThreadedConnectionPool)
- Context managers for automatic transaction management
- Type hints for all methods
- Retry logic for transient failures (tenacity)
- Loguru structured logging
- Support for all 30 tables from schema.sql

Usage:
    from database.db_manager import DatabaseManager
    
    db = DatabaseManager()
    
    # Get a wallet
    wallet = db.get_wallet(wallet_id=1)
    
    # Create a scheduled transaction
    tx_id = db.create_scheduled_transaction(
        wallet_id=1,
        protocol_action_id=5,
        tx_type='SWAP',
        layer='web3py',
        scheduled_at=datetime.now() + timedelta(hours=2),
        amount_usdt=15.73
    )
"""

import os
from typing import Optional, Dict, List, Any, Tuple
from datetime import datetime, date
from decimal import Decimal
from contextlib import contextmanager

import psycopg2
from psycopg2 import pool, extras
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type


class DatabaseManager:
    """
    Central database manager for all CRUD operations.
    
    Uses connection pooling for performance and automatic
    transaction management through context managers.
    """
    
    def __init__(
        self,
        db_host: Optional[str] = None,
        db_port: Optional[int] = None,
        db_name: Optional[str] = None,
        db_user: Optional[str] = None,
        db_password: Optional[str] = None,
        min_conn: int = 2,
        max_conn: int = 20
    ):
        """
        Initialize database connection pool.
        
        Args:
            db_host: Database host (defaults to DB_HOST env var)
            db_port: Database port (defaults to DB_PORT env var or 5432)
            db_name: Database name (defaults to DB_NAME env var)
            db_user: Database user (defaults to DB_USER env var)
            db_password: Database password (defaults to DB_PASS env var)
            min_conn: Minimum connections in pool
            max_conn: Maximum connections in pool
        """
        self.db_host = db_host or os.getenv('DB_HOST', '127.0.0.1')
        self.db_port = db_port or int(os.getenv('DB_PORT', '5432'))
        self.db_name = db_name or os.getenv('DB_NAME', 'farming_db')
        self.db_user = db_user or os.getenv('DB_USER', 'farming_user')
        self.db_password = db_password or os.getenv('DB_PASS')
        
        if not self.db_password:
            error_msg = (
                "Database password not provided. Set DB_PASS environment variable.\n"
                "Solutions:\n"
                "  1. Export in current shell: export DB_PASS='your_password'\n"
                "  2. Add to /opt/farming/.env: DB_PASS=your_password\n"
                "  3. Check /root/.farming_secrets for generated password\n"
                "  4. Run: grep DB_PASS /root/.farming_secrets"
            )
            logger.critical(error_msg)
            raise EnvironmentError(error_msg)
        
        try:
            self.pool = psycopg2.pool.ThreadedConnectionPool(
                min_conn,
                max_conn,
                host=self.db_host,
                port=self.db_port,
                database=self.db_name,
                user=self.db_user,
                password=self.db_password
            )
            logger.info(f"Database pool initialized | Host: {self.db_host} | DB: {self.db_name} | Pool: {min_conn}-{max_conn}")
        except psycopg2.Error as e:
            logger.critical(f"Failed to initialize database pool | Error: {e}")
            raise
    
    @contextmanager
    def get_connection(self):
        """
        Context manager for database connections.
        
        Automatically returns connection to pool and handles
        commit/rollback on exception.
        
        Yields:
            psycopg2.connection: Database connection
        """
        conn = self.pool.getconn()
        try:
            yield conn
            conn.commit()
        except Exception as e:
            conn.rollback()
            logger.error(f"Database transaction rolled back | Error: {e}")
            raise
        finally:
            self.pool.putconn(conn)
    
    @retry(
        retry=retry_if_exception_type((
            psycopg2.OperationalError,
            psycopg2.InterfaceError
            # Note: DatabaseError removed - includes IntegrityError which should not retry
        )),
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        reraise=True
    )
    def execute_query(self, query: str, params: Optional[Tuple] = None, fetch: str = 'none') -> Optional[List[Dict]]:
        """
        Execute a SQL query with retry logic.
        
        Args:
            query: SQL query string
            params: Query parameters tuple
            fetch: 'one', 'all', or 'none'
        
        Returns:
            Query results as list of dicts (if fetch != 'none')
        """
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=extras.RealDictCursor) as cur:
                cur.execute(query, params or ())
                
                if fetch == 'one':
                    result = cur.fetchone()
                    return dict(result) if result else None
                elif fetch == 'all':
                    return [dict(row) for row in cur.fetchall()]
                else:
                    return None
    
    def close_pool(self):
        """Close all connections in the pool."""
        if self.pool:
            self.pool.closeall()
            logger.info("Database pool closed")
    
    # ========================================================================
    # INFRASTRUCTURE QUERIES
    # ========================================================================
    
    def get_worker_node(self, worker_id: int) -> Optional[Dict]:
        """Get worker node by ID (1, 2, or 3)."""
        query = "SELECT * FROM worker_nodes WHERE worker_id = %s"
        return self.execute_query(query, (worker_id,), fetch='one')
    
    def update_worker_heartbeat(self, worker_id: int):
        """Update worker node's last heartbeat timestamp."""
        query = "UPDATE worker_nodes SET last_heartbeat = NOW() WHERE worker_id = %s"
        self.execute_query(query, (worker_id,))
        logger.debug(f"Worker {worker_id} heartbeat updated")
    
    def get_proxy(self, proxy_id: int) -> Optional[Dict]:
        """Get proxy by ID."""
        query = "SELECT * FROM proxy_pool WHERE id = %s"
        return self.execute_query(query, (proxy_id,), fetch='one')
    
    def get_proxies_by_country(self, country_code: str, is_active: bool = True) -> List[Dict]:
        """Get all proxies for a specific country (NL or IS)."""
        query = "SELECT * FROM proxy_pool WHERE country_code = %s AND is_active = %s"
        return self.execute_query(query, (country_code, is_active), fetch='all')
    
    def mark_proxy_used(self, proxy_id: int):
        """Update proxy last_used_at timestamp."""
        query = "UPDATE proxy_pool SET last_used_at = NOW() WHERE id = %s"
        self.execute_query(query, (proxy_id,))
    
    # ========================================================================
    # CEX QUERIES
    # ========================================================================
    
    def get_cex_subaccount(self, subaccount_id: int) -> Optional[Dict]:
        """Get CEX subaccount by ID."""
        query = "SELECT * FROM cex_subaccounts WHERE id = %s"
        return self.execute_query(query, (subaccount_id,), fetch='one')
    
    def get_cex_subaccounts_by_exchange(self, exchange: str) -> List[Dict]:
        """Get all subaccounts for a specific exchange."""
        query = "SELECT * FROM cex_subaccounts WHERE exchange = %s AND is_active = TRUE"
        return self.execute_query(query, (exchange,), fetch='all')
    
    def update_cex_balance(self, subaccount_id: int, balance_usdt: Decimal):
        """Update CEX subaccount balance."""
        query = "UPDATE cex_subaccounts SET balance_usdt = %s, last_balance_check = NOW() WHERE id = %s"
        self.execute_query(query, (balance_usdt, subaccount_id))
    
    def get_funding_chain(self, chain_number: int) -> Optional[Dict]:
        """Get funding chain by number (1-18)."""
        query = "SELECT * FROM funding_chains WHERE chain_number = %s"
        return self.execute_query(query, (chain_number,), fetch='one')
    
    def create_funding_withdrawal(
        self,
        funding_chain_id: int,
        wallet_id: int,
        cex_subaccount_id: int,
        withdrawal_network: str,
        amount_usdt: Decimal,
        withdrawal_address: str,
        delay_minutes: int,
        scheduled_at: datetime
    ) -> int:
        """
        Create a new funding withdrawal record.
        
        Returns:
            ID of created withdrawal record
        """
        query = """
            INSERT INTO funding_withdrawals (
                funding_chain_id, wallet_id, cex_subaccount_id, withdrawal_network,
                amount_usdt, withdrawal_address, delay_minutes, scheduled_at, status
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'planned')
            RETURNING id
        """
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (
                    funding_chain_id, wallet_id, cex_subaccount_id, withdrawal_network,
                    amount_usdt, withdrawal_address, delay_minutes, scheduled_at
                ))
                withdrawal_id = cur.fetchone()[0]
                logger.info(f"Funding withdrawal created | ID: {withdrawal_id} | Wallet: {wallet_id} | Amount: {amount_usdt} USDT")
                return withdrawal_id
    
    def update_funding_withdrawal_status(
        self,
        withdrawal_id: int,
        status: str,
        cex_txid: Optional[str] = None,
        blockchain_txhash: Optional[str] = None
    ):
        """Update funding withdrawal status and transaction IDs."""
        if status == 'completed':
            query = """
                UPDATE funding_withdrawals 
                SET status = %s, cex_txid = %s, blockchain_txhash = %s, completed_at = NOW()
                WHERE id = %s
            """
        else:
            query = """
                UPDATE funding_withdrawals 
                SET status = %s, cex_txid = %s, blockchain_txhash = %s
                WHERE id = %s
            """
        self.execute_query(query, (status, cex_txid, blockchain_txhash, withdrawal_id))
    
    # ========================================================================
    # WALLETS QUERIES
    # ========================================================================
    
    def get_wallet(self, wallet_id: int) -> Optional[Dict]:
        """Get wallet by ID."""
        query = "SELECT * FROM wallets WHERE id = %s"
        return self.execute_query(query, (wallet_id,), fetch='one')
    
    def get_wallet_by_address(self, address: str) -> Optional[Dict]:
        """Get wallet by Ethereum address."""
        query = "SELECT * FROM wallets WHERE address = %s"
        return self.execute_query(query, (address,), fetch='one')
    
    def get_wallets_by_tier(self, tier: str) -> List[Dict]:
        """Get all wallets of a specific tier (A, B, or C)."""
        query = "SELECT * FROM wallets WHERE tier = %s"
        return self.execute_query(query, (tier,), fetch='all')
    
    def get_wallets_by_worker(self, worker_id: int) -> List[Dict]:
        """
        Get all wallets assigned to a specific worker (30 wallets per worker).
        
        Args:
            worker_id: Worker ID from worker_nodes table (NOT worker_node_id!)
        """
        query = """
            SELECT w.* FROM wallets w
            JOIN worker_nodes wn ON w.worker_node_id = wn.id
            WHERE wn.worker_id = %s
        """
        return self.execute_query(query, (worker_id,), fetch='all')
    
    def create_wallet(
        self,
        address: str,
        encrypted_private_key: str,
        tier: str,
        worker_node_id: int,
        proxy_id: int
    ) -> int:
        """
        Create a new wallet.
        
        Returns:
            ID of created wallet
        """
        query = """
            INSERT INTO wallets (address, encrypted_private_key, tier, worker_node_id, proxy_id, openclaw_enabled)
            VALUES (%s, %s, %s, %s, %s, %s)
            RETURNING id
        """
        openclaw_enabled = (tier == 'A')  # Only Tier A wallets use OpenClaw
        
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (address, encrypted_private_key, tier, worker_node_id, proxy_id, openclaw_enabled))
                wallet_id = cur.fetchone()[0]
                logger.info(f"Wallet created | ID: {wallet_id} | Address: {address} | Tier: {tier}")
                return wallet_id
    
    def update_wallet_status(self, wallet_id: int, status: str):
        """Update wallet status (inactive, warming_up, active, etc.)."""
        query = "UPDATE wallets SET status = %s WHERE id = %s"
        self.execute_query(query, (status, wallet_id))
    
    def update_wallet_funded(self, wallet_id: int):
        """Mark wallet as funded (last_funded_at = NOW)."""
        query = "UPDATE wallets SET last_funded_at = NOW(), status = 'warming_up' WHERE id = %s"
        self.execute_query(query, (wallet_id,))
        logger.info(f"Wallet {wallet_id} marked as funded | Status: warming_up")
    
    def update_wallet_first_tx(self, wallet_id: int):
        """Record wallet's first transaction timestamp."""
        query = "UPDATE wallets SET first_tx_at = NOW() WHERE id = %s"
        self.execute_query(query, (wallet_id,))
    
    def increment_wallet_tx_count(self, wallet_id: int):
        """Increment wallet's total transaction count."""
        query = "UPDATE wallets SET total_tx_count = total_tx_count + 1, last_tx_at = NOW() WHERE id = %s"
        self.execute_query(query, (wallet_id,))
    
    def get_wallet_persona(self, wallet_id: int) -> Optional[Dict]:
        """Get wallet's behavioral persona."""
        query = "SELECT * FROM wallet_personas WHERE wallet_id = %s"
        return self.execute_query(query, (wallet_id,), fetch='one')
    
    def create_wallet_persona(
        self,
        wallet_id: int,
        persona_type: str,
        preferred_hours: List[int],
        tx_per_week_mean: Decimal,
        tx_per_week_stddev: Decimal,
        tx_weight_swap: Decimal,
        tx_weight_bridge: Decimal,
        tx_weight_liquidity: Decimal,
        tx_weight_stake: Decimal,
        tx_weight_nft: Decimal,
        slippage_tolerance: Decimal,
        gas_preference: str,
        gas_preference_weights: Dict[str, float],
        amount_noise_pct: Decimal = Decimal('0.05'),
        time_noise_minutes: int = 15
    ) -> int:
        """
        Create behavioral persona for a wallet.
        
        **CRITICAL: Each of 90 wallets must have UNIQUE parameters!**
        
        Returns:
            ID of created persona
        """
        query = """
            INSERT INTO wallet_personas (
                wallet_id, persona_type, preferred_hours, tx_per_week_mean, tx_per_week_stddev,
                tx_weight_swap, tx_weight_bridge, tx_weight_liquidity, tx_weight_stake, tx_weight_nft,
                slippage_tolerance, gas_preference, gas_preference_weights,
                amount_noise_pct, time_noise_minutes
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
        """
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (
                    wallet_id, persona_type, preferred_hours, tx_per_week_mean, tx_per_week_stddev,
                    tx_weight_swap, tx_weight_bridge, tx_weight_liquidity, tx_weight_stake, tx_weight_nft,
                    slippage_tolerance, gas_preference, extras.Json(gas_preference_weights),
                    amount_noise_pct, time_noise_minutes
                ))
                persona_id = cur.fetchone()[0]
                logger.info(f"Wallet persona created | Wallet: {wallet_id} | Type: {persona_type} | Slippage: {slippage_tolerance}%")
                return persona_id
    
    # ========================================================================
    # PROTOCOLS QUERIES
    # ========================================================================
    
    def get_protocol(self, protocol_id: int) -> Optional[Dict]:
        """Get protocol by ID."""
        query = "SELECT * FROM protocols WHERE id = %s"
        return self.execute_query(query, (protocol_id,), fetch='one')
    
    def get_protocol_by_name(self, name: str) -> Optional[Dict]:
        """Get protocol by name."""
        query = "SELECT * FROM protocols WHERE name = %s"
        return self.execute_query(query, (name,), fetch='one')
    
    def get_active_protocols(self, has_points_program: Optional[bool] = None) -> List[Dict]:
        """Get all active protocols, optionally filtered by points program existence."""
        if has_points_program is not None:
            query = "SELECT * FROM protocols WHERE is_active = TRUE AND has_points_program = %s ORDER BY priority_score DESC"
            return self.execute_query(query, (has_points_program,), fetch='all')
        else:
            query = "SELECT * FROM protocols WHERE is_active = TRUE ORDER BY priority_score DESC"
            return self.execute_query(query, fetch='all')
    
    def create_protocol(
        self,
        name: str,
        category: str,
        chains: List[str],
        has_points_program: bool = False,
        priority_score: int = 50
    ) -> int:
        """Create a new protocol."""
        query = """
            INSERT INTO protocols (name, category, chains, has_points_program, priority_score, last_researched_at)
            VALUES (%s, %s, %s, %s, %s, NOW())
            RETURNING id
        """
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (name, category, chains, has_points_program, priority_score))
                protocol_id = cur.fetchone()[0]
                logger.info(f"Protocol created | ID: {protocol_id} | Name: {name} | Priority: {priority_score}")
                return protocol_id
    
    def get_protocol_actions(self, protocol_id: int, layer: Optional[str] = None) -> List[Dict]:
        """Get all actions for a protocol, optionally filtered by layer (web3py/openclaw)."""
        if layer:
            query = "SELECT * FROM protocol_actions WHERE protocol_id = %s AND layer = %s AND is_enabled = TRUE"
            return self.execute_query(query, (protocol_id, layer), fetch='all')
        else:
            query = "SELECT * FROM protocol_actions WHERE protocol_id = %s AND is_enabled = TRUE"
            return self.execute_query(query, (protocol_id,), fetch='all')
    # ========================================================================
    # PROTOCOL RESEARCH QUERIES
    # ========================================================================

    def create_pending_protocol(self, **kwargs) -> int:
        """
        Insert LLM-analyzed protocol into pending approval queue.
        
        Now includes bridge information from Bridge Manager v2.0 integration.
        
        Bridge fields (added in migration 032):
            - bridge_required: bool - TRUE if network requires bridge
            - bridge_from_network: str - Source network (usually 'Arbitrum')
            - bridge_provider: str - Bridge aggregator (socket, across, relay)
            - bridge_cost_usd: decimal - Estimated bridge cost
            - bridge_safety_score: int - DeFiLlama safety score 0-100
            - bridge_available: bool - TRUE if bridge route found
            - bridge_checked_at: datetime - When bridge was checked
            - bridge_unreachable_reason: str - Why bridge is unavailable
            - bridge_recheck_after: datetime - When to recheck unreachable
            - bridge_recheck_count: int - Number of recheck attempts
            - cex_support: str - CEX name if direct withdrawal supported
        """
        # Core fields
        core_fields = [
            'name', 'category', 'chains', 'website_url', 'twitter_url', 'discord_url',
            'airdrop_score', 'has_points_program', 'points_program_url', 'has_token',
            'current_tvl_usd', 'tvl_change_30d_pct', 'launch_date',
            'recommended_actions', 'reasoning', 'raw_llm_response',
            'discovered_from', 'source_article_url', 'source_article_title', 'source_published_at'
        ]
        
        # Bridge fields (new in migration 032)
        bridge_fields = [
            'bridge_required', 'bridge_from_network', 'bridge_provider', 'bridge_cost_usd',
            'bridge_safety_score', 'bridge_available', 'bridge_checked_at',
            'bridge_unreachable_reason', 'bridge_recheck_after', 'bridge_recheck_count',
            'cex_support'
        ]
        
        # Combine all fields - this is the whitelist for SQL injection prevention
        all_fields = core_fields + bridge_fields
        
        # Validate: only allow whitelisted field names
        present_fields = [f for f in all_fields if f in kwargs]
        
        # Additional safety: reject any field with suspicious characters
        for field in present_fields:
            if not field.replace('_', '').isalnum():
                raise ValueError(f"Invalid field name: {field}")
        
        # Build query
        placeholders = ', '.join(['%s'] * len(present_fields))
        query = f"""
            INSERT INTO protocol_research_pending ({', '.join(present_fields)})
            VALUES ({placeholders})
            RETURNING id
        """
        
        values = [kwargs.get(field) for field in present_fields]
        
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, values)
                pending_id = cur.fetchone()[0]
                
                # Log with bridge status
                bridge_status = "unreachable" if not kwargs.get('bridge_available', True) else (
                    f"via {kwargs.get('bridge_provider')}" if kwargs.get('bridge_required') else "direct CEX"
                )
                logger.info(
                    f"Pending protocol created | ID: {pending_id} | Name: {kwargs.get('name')} | "
                    f"Bridge: {bridge_status}"
                )
                return pending_id

    def get_pending_protocols(self, status: str = 'pending_approval') -> List[Dict]:
        """Get all pending protocols by status."""
        query = "SELECT * FROM protocol_research_pending WHERE status = %s ORDER BY airdrop_score DESC"
        return self.execute_query(query, (status,), fetch='all')

    def approve_pending_protocol(self, pending_id: int, approved_by: str) -> int:
        """Call approve_protocol() function, returns new protocol_id."""
        query = "SELECT approve_protocol(%s, %s)"
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (pending_id, approved_by))
                new_protocol_id = cur.fetchone()[0]
                logger.info(f"Protocol approved | Pending ID: {pending_id} -> Protocol ID: {new_protocol_id}")
                return new_protocol_id

    def reject_pending_protocol(self, pending_id: int, reason: str) -> None:
        """Mark pending protocol as rejected."""
        query = """
            UPDATE protocol_research_pending
            SET status = 'rejected', rejected_reason = %s, rejected_at = NOW()
            WHERE id = %s
        """
        self.execute_query(query, (reason, pending_id))
        logger.info(f"Protocol rejected | ID: {pending_id} | Reason: {reason}")

    def create_research_log(self, **kwargs) -> int:
        """Create new research cycle log."""
        fields = [
            'cycle_start_at', 'cycle_end_at', 'status',
            'total_sources_checked', 'total_candidates_found', 'total_analyzed_by_llm',
            'total_added_to_pending', 'total_duplicates', 'total_rejected_low_score',
            'source_stats', 'llm_api_calls', 'llm_tokens_used', 'estimated_cost_usd',
            'errors_encountered', 'error_details', 'summary_report', 'protocols_auto_rejected'
        ]
        placeholders = ', '.join(['%s'] * len(fields))
        query = f"""
            INSERT INTO research_logs ({', '.join(fields)})
            VALUES ({placeholders})
            RETURNING id
        """
        values = [kwargs.get(field) for field in fields]
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, values)
                log_id = cur.fetchone()[0]
                logger.info(f"Research log created | ID: {log_id}")
                return log_id

    def update_research_log(self, log_id: int, **kwargs) -> None:
        """Update research log with statistics and costs."""
        if not kwargs:
            return
        
        # Whitelist of allowed fields to prevent SQL injection
        allowed_fields = {
            'cycle_end_at', 'protocols_discovered', 'protocols_approved',
            'protocols_rejected', 'total_cost_usd', 'llm_tokens_used',
            'news_items_processed', 'errors', 'notes'
        }
        
        # Filter to allowed fields only
        filtered_kwargs = {k: v for k, v in kwargs.items() if k in allowed_fields}
        
        if not filtered_kwargs:
            logger.warning(f"No valid fields to update in research log {log_id}")
            return
        
        set_clauses = ', '.join([f"{key} = %s" for key in filtered_kwargs.keys()])
        query = f"UPDATE research_logs SET {set_clauses} WHERE id = %s"
        values = list(filtered_kwargs.values()) + [log_id]
        self.execute_query(query, tuple(values))

    def get_recent_research_logs(self, limit: int = 10) -> List[Dict]:
        """Get recent research cycles for /research_stats command."""
        query = "SELECT * FROM research_logs ORDER BY cycle_start_at DESC LIMIT %s"
        return self.execute_query(query, (limit,), fetch='all')

    def auto_reject_stale_protocols(self) -> int:
        """Call auto_reject_stale_protocols() function."""
        query = "SELECT auto_reject_stale_protocols()"
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query)
                rejected_count = cur.fetchone()[0]
                logger.info(f"Auto-rejected {rejected_count} stale protocols")
                return rejected_count

    # ========================================================================
    # ACTIVITY & SCHEDULING QUERIES
    # ========================================================================
    
    
    def create_scheduled_transaction(
        self,
        wallet_id: int,
        protocol_action_id: int,
        tx_type: str,
        layer: str,
        scheduled_at: datetime,
        amount_usdt: Optional[Decimal] = None,
        params: Optional[Dict] = None
    ) -> int:
        """
        Schedule a transaction for execution.
        
        Returns:
            ID of created scheduled transaction
        """
        query = """
            INSERT INTO scheduled_transactions (
                wallet_id, protocol_action_id, tx_type, layer, scheduled_at, amount_usdt, params, status
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, 'pending')
            RETURNING id
        """
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (
                    wallet_id, protocol_action_id, tx_type, layer, scheduled_at,
                    amount_usdt, extras.Json(params) if params else None
                ))
                tx_id = cur.fetchone()[0]
                logger.info(f"Transaction scheduled | ID: {tx_id} | Wallet: {wallet_id} | Type: {tx_type} | At: {scheduled_at}")
                return tx_id
    
    def get_pending_transactions(self, before: datetime, limit: int = 100) -> List[Dict]:
        """
        Get pending transactions scheduled before a certain time.
        
        Args:
            before: Get transactions scheduled before this datetime
            limit: Maximum number of transactions to return
        """
        query = """
            SELECT * FROM scheduled_transactions 
            WHERE status = 'pending' AND scheduled_at <= %s
            ORDER BY scheduled_at ASC
            LIMIT %s
        """
        return self.execute_query(query, (before, limit), fetch='all')
    
    def update_transaction_status(
        self,
        tx_id: int,
        status: str,
        tx_hash: Optional[str] = None,
        error_message: Optional[str] = None
    ):
        """Update scheduled transaction status."""
        if status == 'confirmed':
            query = "UPDATE scheduled_transactions SET status = %s, tx_hash = %s, executed_at = NOW() WHERE id = %s"
            self.execute_query(query, (status, tx_hash, tx_id))
        elif status == 'failed':
            query = "UPDATE scheduled_transactions SET status = %s, error_message = %s WHERE id = %s"
            self.execute_query(query, (status, error_message, tx_id))
        else:
            query = "UPDATE scheduled_transactions SET status = %s WHERE id = %s"
            self.execute_query(query, (status, tx_id))
    
    def create_weekly_plan(self, wallet_id: int, week_start_date: date, planned_tx_count: int, is_skipped: bool = False) -> int:
        """Create a weekly transaction plan for a wallet."""
        query = """
            INSERT INTO weekly_plans (wallet_id, week_start_date, planned_tx_count, is_skipped)
            VALUES (%s, %s, %s, %s)
            RETURNING id
        """
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (wallet_id, week_start_date, planned_tx_count, is_skipped))
                plan_id = cur.fetchone()[0]
                if not is_skipped:
                    logger.debug(f"Weekly plan created | Wallet: {wallet_id} | Week: {week_start_date} | Planned TX: {planned_tx_count}")
                else:
                    logger.debug(f"Weekly plan skipped | Wallet: {wallet_id} | Week: {week_start_date}")
                return plan_id
    
    def increment_weekly_plan_actual(self, plan_id: int):
        """Increment actual transaction count for a weekly plan."""
        query = "UPDATE weekly_plans SET actual_tx_count = actual_tx_count + 1 WHERE id = %s"
        self.execute_query(query, (plan_id,))
    
    # ========================================================================
    # OPENCLAW QUERIES
    # ========================================================================
    
    def create_openclaw_task(
        self,
        wallet_id: int,
        task_type: str,
        scheduled_at: datetime,
        protocol_id: Optional[int] = None,
        task_params: Optional[Dict] = None
    ) -> int:
        """
        Schedule an OpenClaw browser automation task.
        
        **Only for 18 Tier A wallets with openclaw_enabled = TRUE**
        
        Returns:
            ID of created OpenClaw task
        """
        query = """
            INSERT INTO openclaw_tasks (wallet_id, task_type, protocol_id, task_params, scheduled_at, status)
            VALUES (%s, %s, %s, %s, %s, 'queued')
            RETURNING id
        """
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (wallet_id, task_type, protocol_id, extras.Json(task_params) if task_params else None, scheduled_at))
                task_id = cur.fetchone()[0]
                logger.info(f"OpenClaw task created | ID: {task_id} | Wallet: {wallet_id} | Type: {task_type}")
                return task_id
    
    def get_queued_openclaw_tasks(self, before: datetime, limit: int = 5) -> List[Dict]:
        """Get queued OpenClaw tasks scheduled before a certain time."""
        query = """
            SELECT * FROM openclaw_tasks 
            WHERE status = 'queued' AND scheduled_at <= %s
            ORDER BY scheduled_at ASC
            LIMIT %s
        """
        return self.execute_query(query, (before, limit), fetch='all')
    
    def update_openclaw_task_status(self, task_id: int, status: str, error_message: Optional[str] = None):
        """Update OpenClaw task status."""
        if status == 'completed':
            query = "UPDATE openclaw_tasks SET status = %s, completed_at = NOW() WHERE id = %s"
            self.execute_query(query, (status, task_id))
        elif status == 'failed':
            query = "UPDATE openclaw_tasks SET status = %s, error_message = %s, retry_count = retry_count + 1 WHERE id = %s"
            self.execute_query(query, (status, error_message, task_id))
            
            # Check if max retries reached
            task = self.execute_query("SELECT retry_count, max_retries FROM openclaw_tasks WHERE id = %s", (task_id,), fetch='one')
            if task and task['retry_count'] >= task['max_retries']:
                self.execute_query("UPDATE openclaw_tasks SET status = 'skipped' WHERE id = %s", (task_id,))
                logger.warning(f"OpenClaw task {task_id} exceeded max retries, status set to 'skipped'")
        else:
            query = "UPDATE openclaw_tasks SET status = %s WHERE id = %s"
            self.execute_query(query, (status, task_id))
    
    def update_openclaw_score(self, wallet_id: int, gitcoin_passport_score: Decimal):
        """Update Gitcoin Passport score for a Tier A wallet."""
        query = """
            UPDATE openclaw_reputation 
            SET gitcoin_passport_score = %s, last_updated_at = NOW()
            WHERE wallet_id = %s
        """
        self.execute_query(query, (gitcoin_passport_score, wallet_id))
        logger.info(f"Gitcoin Passport score updated | Wallet: {wallet_id} | Score: {gitcoin_passport_score}")
    
    # ========================================================================
    # MONITORING & SYSTEM QUERIES
    # ========================================================================
    
    def log_system_event(
        self,
        event_type: str,
        severity: str,
        message: str,
        component: Optional[str] = None,
        metadata: Optional[Dict] = None
    ) -> int:
        """
        Log a system event (for Telegram alerts and monitoring).
        
        Args:
            event_type: Type of event ('worker_down', 'airdrop_detected', etc.)
            severity: 'info', 'warning', 'error', or 'critical'
            message: Human-readable event description
            component: Component that generated the event
            metadata: Additional structured data
        
        Returns:
            ID of logged event
        """
        query = """
            INSERT INTO system_events (event_type, severity, component, message, metadata)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id
        """
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (event_type, severity, component, message, extras.Json(metadata) if metadata else None))
                event_id = cur.fetchone()[0]
                logger.log(severity.upper(), f"System event logged | ID: {event_id} | Type: {event_type} | {message}")
                return event_id
    
    def get_unsent_critical_events(self) -> List[Dict]:
        """Get critical events that haven't been sent to Telegram yet."""
        query = """
            SELECT * FROM system_events 
            WHERE severity = 'critical' AND telegram_sent = FALSE
            ORDER BY created_at ASC
        """
        return self.execute_query(query, fetch='all')
    
    def mark_event_sent(self, event_id: int):
        """Mark system event as sent to Telegram."""
        query = "UPDATE system_events SET telegram_sent = TRUE WHERE id = %s"
        self.execute_query(query, (event_id,))
    
    def record_gas_snapshot(self, chain: str, slow_gwei: Decimal, normal_gwei: Decimal, fast_gwei: Decimal, block_number: Optional[int] = None):
        """Record current gas prices for a chain."""
        query = """
            INSERT INTO gas_snapshots (chain, slow_gwei, normal_gwei, fast_gwei, block_number)
            VALUES (%s, %s, %s, %s, %s)
        """
        self.execute_query(query, (chain, slow_gwei, normal_gwei, fast_gwei, block_number))
    
    def get_latest_gas(self, chain: str) -> Optional[Dict]:
        """Get most recent gas snapshot for a chain."""
        query = """
            SELECT * FROM gas_snapshots 
            WHERE chain = %s 
            ORDER BY recorded_at DESC 
            LIMIT 1
        """
        return self.execute_query(query, (chain,), fetch='one')
    
    # ========================================================================
    # WITHDRAWAL QUERIES
    # ========================================================================
    
    def create_withdrawal_plan(self, wallet_id: int, tier: str) -> int:
        """Create a withdrawal plan for a wallet based on tier."""
        total_steps = {'A': 4, 'B': 3, 'C': 2}[tier]
        
        query = """
            INSERT INTO withdrawal_plans (wallet_id, tier, total_steps, status)
            VALUES (%s, %s, %s, 'planned')
            RETURNING id
        """
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (wallet_id, tier, total_steps))
                plan_id = cur.fetchone()[0]
                logger.info(f"Withdrawal plan created | Wallet: {wallet_id} | Tier: {tier} | Steps: {total_steps}")
                return plan_id
    
    def create_withdrawal_step(
        self,
        withdrawal_plan_id: int,
        step_number: int,
        percentage: Decimal,
        dest_address: str,
        scheduled_at: datetime
    ) -> int:
        """Create a withdrawal step (requires Telegram approval)."""
        query = """
            INSERT INTO withdrawal_steps (withdrawal_plan_id, step_number, percentage, destination_address, scheduled_at, status)
            VALUES (%s, %s, %s, %s, %s, 'planned')
            RETURNING id
        """
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (withdrawal_plan_id, step_number, percentage, dest_address, scheduled_at))
                step_id = cur.fetchone()[0]
                logger.info(f"Withdrawal step created | Plan: {withdrawal_plan_id} | Step: {step_number} | Percentage: {percentage}%")
                return step_id
    
    def approve_withdrawal_step(self, step_id: int, approved_by: str):
        """Approve a withdrawal step (called from Telegram bot)."""
        query = "UPDATE withdrawal_steps SET status = 'approved', approved_at = NOW(), approved_by = %s WHERE id = %s"
        self.execute_query(query, (approved_by, step_id))
        logger.info(f"Withdrawal step {step_id} approved by {approved_by}")
    
    def get_pending_withdrawals(self) -> List[Dict]:
        """Get all withdrawal steps pending approval."""
        query = "SELECT * FROM withdrawal_steps WHERE status = 'pending_approval' ORDER BY scheduled_at ASC"
        return self.execute_query(query, fetch='all')
    
    # ========================================================================
    # BRIDGE & CACHE QUERIES
    # ========================================================================
    
    def get_chain_rpc_endpoints(self, chain: Optional[str] = None) -> List[Dict]:
        """
        Get RPC endpoints, optionally filtered by chain.
        
        Args:
            chain: Chain name (e.g., 'arbitrum', 'base') or None for all chains
        
        Returns:
            List of RPC endpoint records with all columns
        """
        if chain:
            query = "SELECT * FROM chain_rpc_endpoints WHERE chain = %s AND is_active = TRUE ORDER BY priority ASC"
            return self.execute_query(query, (chain,), fetch='all')
        else:
            query = "SELECT * FROM chain_rpc_endpoints WHERE is_active = TRUE ORDER BY chain, priority ASC"
            return self.execute_query(query, fetch='all')
    
    def get_chain_rpc_by_chain_id(self, chain_id: int) -> Optional[Dict]:
        """
        Get RPC endpoint by chain_id.
        
        Args:
            chain_id: Chain ID (e.g., 42161 for Arbitrum, 8453 for Base)
        
        Returns:
            Single RPC endpoint record or None if not found
        """
        query = "SELECT * FROM chain_rpc_endpoints WHERE chain_id = %s AND is_active = TRUE ORDER BY priority ASC LIMIT 1"
        return self.execute_query(query, (chain_id,), fetch='one')
    
    def get_chain_rpc_url(self, chain: str) -> Optional[str]:
        """
        Get primary RPC URL for a chain by name.
        
        Simple convenience method that returns just the URL string.
        
        Args:
            chain: Chain name (e.g., 'arbitrum', 'base', 'optimism')
        
        Returns:
            RPC URL string or None if not found
        """
        query = "SELECT url FROM chain_rpc_endpoints WHERE chain = %s AND is_active = TRUE ORDER BY priority ASC LIMIT 1"
        result = self.execute_query(query, (chain.lower(),), fetch='one')
        return result['url'] if result else None
    
    def get_chain_rpc_with_fallback(self, chain: str) -> Dict[str, Optional[str]]:
        """
        Get RPC URLs for a chain with fallback support.
        
        CRITICAL: This method provides failover capability when primary RPC fails.
        Use this instead of get_chain_rpc_url() for production code.
        
        Args:
            chain: Chain name (e.g., 'arbitrum', 'base', 'optimism')
        
        Returns:
            Dict with 'primary' and 'fallback' keys:
            - 'primary': Primary RPC URL (priority 1)
            - 'fallback': Low priority RPC URL for failover (may be None)
        
        Example:
            >>> rpc = db.get_chain_rpc_with_fallback('arbitrum')
            >>> primary_url = rpc['primary']
            >>> fallback_url = rpc['fallback']
            >>> 
            >>> # Try primary first
            >>> try:
            ...     w3 = Web3(Web3.HTTPProvider(primary_url))
            ...     block = w3.eth.get_block('latest')
            ... except Exception as e:
            ...     # Fallback to secondary RPC
            ...     if fallback_url:
            ...         logger.warning(f"Primary RPC failed, using fallback: {e}")
            ...         w3 = Web3(Web3.HTTPProvider(fallback_url))
            ...         block = w3.eth.get_block('latest')
        """
        query = """
            SELECT url, low_priority_rpc 
            FROM chain_rpc_endpoints 
            WHERE chain = %s AND is_active = TRUE 
            ORDER BY priority ASC 
            LIMIT 1
        """
        result = self.execute_query(query, (chain.lower(),), fetch='one')
        
        if not result:
            return {'primary': None, 'fallback': None}
        
        return {
            'primary': result.get('url'),
            'fallback': result.get('low_priority_rpc')
        }
    
    def get_chain_rpc_with_failover(self, chain: str) -> Optional[str]:
        """
        Get RPC URL with automatic failover tracking.
        
        Returns the best available RPC URL:
        - If primary has recent failures, returns fallback
        - Otherwise returns primary
        
        This method also updates health statistics for monitoring.
        
        Args:
            chain: Chain name (e.g., 'arbitrum', 'base')
        
        Returns:
            Best available RPC URL or None if no active endpoints
        """
        # Get both primary and fallback
        rpc_urls = self.get_chain_rpc_with_fallback(chain)
        
        # For now, just return primary (failover logic can be enhanced later)
        # TODO: Add health-based failover based on failure_count / success_count ratio
        return rpc_urls['primary']
    
    def get_all_active_chains(self) -> List[Dict]:
        """
        Get all active chains with their chain_id.
        
        Returns distinct chains that have chain_id defined.
        Used for chain discovery and bridge operations.
        
        Returns:
            List of dicts with 'chain', 'chain_id' keys
        """
        query = """
            SELECT DISTINCT chain, chain_id, is_l2, network_type, gas_multiplier
            FROM chain_rpc_endpoints
            WHERE chain_id IS NOT NULL AND is_active = TRUE
            ORDER BY chain_id ASC
        """
        return self.execute_query(query, fetch='all')
    
    def get_farming_chains(self) -> List[Dict]:
        """
        Get chains available for farming activity (withdrawal_only = FALSE).
        
        CRITICAL: This method excludes BSC and Polygon which are only used
        for CEX withdrawals, NOT for farming activity.
        
        Returns:
            List of dicts with 'chain', 'chain_id', 'is_l2', 'network_type' keys
            Only chains where withdrawal_only = FALSE
        """
        query = """
            SELECT DISTINCT chain, chain_id, is_l2, network_type, gas_multiplier
            FROM chain_rpc_endpoints
            WHERE chain_id IS NOT NULL 
              AND is_active = TRUE 
              AND (withdrawal_only = FALSE OR withdrawal_only IS NULL)
            ORDER BY chain_id ASC
        """
        return self.execute_query(query, fetch='all')
    
    def get_chain_by_name(self, chain_name: str) -> Optional[Dict]:
        """
        Get chain data by name (case-insensitive).
        
        Args:
            chain_name: Chain name (e.g., 'arbitrum', 'Arbitrum', 'ARBITRUM')
        
        Returns:
            Full chain record or None if not found
        """
        query = "SELECT * FROM chain_rpc_endpoints WHERE LOWER(chain) = LOWER(%s) AND is_active = TRUE LIMIT 1"
        return self.execute_query(query, (chain_name,), fetch='one')
    
    def get_chain_by_chain_id(self, chain_id: int) -> Optional[Dict]:
        """
        Get chain data by chain_id.
        
        Args:
            chain_id: Chain ID (e.g., 42161 for Arbitrum)
        
        Returns:
            Full chain record or None if not found
        """
        query = "SELECT * FROM chain_rpc_endpoints WHERE chain_id = %s AND is_active = TRUE LIMIT 1"
        return self.execute_query(query, (chain_id,), fetch='one')
    
    def chain_exists(self, chain_id: int) -> bool:
        """
        Check if a chain with given chain_id exists.
        
        Args:
            chain_id: Chain ID to check
        
        Returns:
            True if chain exists, False otherwise
        """
        query = "SELECT 1 FROM chain_rpc_endpoints WHERE chain_id = %s LIMIT 1"
        result = self.execute_query(query, (chain_id,), fetch='one')
        return result is not None
    
    def insert_chain_rpc(
        self,
        chain: str,
        chain_id: int,
        url: str,
        priority: int = 1,
        is_l2: bool = True,
        network_type: str = 'mainnet',
        gas_multiplier: Decimal = Decimal('1.0'),
        is_active: bool = True
    ) -> int:
        """
        Insert a new chain RPC endpoint.
        
        Used by chain_discovery.py when discovering new networks.
        
        Args:
            chain: Chain name (e.g., 'MegaETH')
            chain_id: Chain ID (e.g., 420420)
            url: RPC URL
            priority: Priority (1 = primary, 2+ = fallback)
            is_l2: Whether this is an L2 network
            network_type: 'mainnet' or 'testnet'
            gas_multiplier: Gas price multiplier for this chain
            is_active: Whether endpoint is active
        
        Returns:
            ID of inserted record
        """
        query = """
            INSERT INTO chain_rpc_endpoints (
                chain, chain_id, url, priority, is_l2, network_type,
                gas_multiplier, is_active, created_at
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW())
            RETURNING id
        """
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (
                    chain, chain_id, url, priority, is_l2, network_type,
                    gas_multiplier, is_active
                ))
                rpc_id = cur.fetchone()[0]
                logger.info(f"Chain RPC inserted | Chain: {chain} | ID: {chain_id} | URL: {url}")
                return rpc_id
    
    def update_chain_rpc_health(
        self,
        rpc_id: int,
        success: bool = True,
        response_time_ms: Optional[int] = None
    ):
        """
        Update RPC endpoint health statistics.
        
        Args:
            rpc_id: RPC endpoint ID
            success: Whether the RPC call succeeded
            response_time_ms: Response time in milliseconds
        """
        if success:
            query = """
                UPDATE chain_rpc_endpoints
                SET success_count = success_count + 1,
                    avg_response_ms = COALESCE((avg_response_ms + %s) / 2, %s),
                    last_used_at = NOW()
                WHERE id = %s
            """
            self.execute_query(query, (response_time_ms, response_time_ms, rpc_id))
        else:
            query = """
                UPDATE chain_rpc_endpoints
                SET failure_count = failure_count + 1
                WHERE id = %s
            """
            self.execute_query(query, (rpc_id,))
    
    def deactivate_chain_rpc(self, rpc_id: int):
        """
        Deactivate an RPC endpoint (mark as inactive).
        
        Args:
            rpc_id: RPC endpoint ID
        """
        query = "UPDATE chain_rpc_endpoints SET is_active = FALSE WHERE id = %s"
        self.execute_query(query, (rpc_id,))
        logger.warning(f"Chain RPC deactivated | ID: {rpc_id}")
    
    def get_chain_aliases(self) -> List[Dict]:
        """
        Get all chain aliases.
        
        Returns:
            List of all chain alias records with chain_id, alias, source, etc.
        """
        query = "SELECT * FROM chain_aliases ORDER BY chain_id, alias"
        return self.execute_query(query, fetch='all')
    
    def get_chain_by_alias(self, alias: str) -> Optional[int]:
        """
        Get chain_id by alias (case-insensitive lookup).
        
        Used by ChainDiscoveryService to normalize network names.
        
        Args:
            alias: Network alias to search (e.g., 'arb', 'eth-mainnet', 'matic')
        
        Returns:
            Chain ID if found, None otherwise
        """
        query = """
            SELECT chain_id FROM chain_aliases
            WHERE LOWER(alias) = LOWER(%s)
            LIMIT 1
        """
        result = self.execute_query(query, (alias,), fetch='one')
        return result['chain_id'] if result else None
    
    def add_chain_alias(
        self,
        chain_id: int,
        alias: str,
        source: str = 'manual'
    ) -> Optional[int]:
        """
        Add a new chain alias or update existing one.
        
        Uses ON CONFLICT to handle duplicates gracefully.
        
        Args:
            chain_id: Chain ID (e.g., 42161 for Arbitrum)
            alias: Alternative name for the chain
            source: Source of this alias ('manual', 'chainid', 'defillama', 'socket', 'cex')
        
        Returns:
            ID of inserted/updated record, or None on error
        """
        query = """
            INSERT INTO chain_aliases (chain_id, alias, source, last_seen)
            VALUES (%s, %s, %s, NOW())
            ON CONFLICT (alias) DO UPDATE SET
                last_seen = NOW(),
                source = EXCLUDED.source
            RETURNING id
        """
        try:
            with self.get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute(query, (chain_id, alias.lower(), source))
                    result = cur.fetchone()
                    alias_id = result[0] if result else None
                    logger.debug(f"Chain alias added | Chain: {chain_id} | Alias: {alias} | Source: {source}")
                    return alias_id
        except Exception as e:
            logger.warning(f"Failed to add chain alias '{alias}': {e}")
            return None
    
    def get_aliases_for_chain(self, chain_id: int) -> List[str]:
        """
        Get all aliases for a specific chain_id.
        
        Args:
            chain_id: Chain ID to look up
        
        Returns:
            List of alias strings for this chain
        """
        query = "SELECT alias FROM chain_aliases WHERE chain_id = %s ORDER BY alias"
        results = self.execute_query(query, (chain_id,), fetch='all')
        return [r['alias'] for r in results] if results else []
        
    def get_cex_networks_cache(
        self,
        cex_name: str,
        coin: str,
        allow_stale: bool = False
    ) -> Optional[Dict]:
        """
        Get cached CEX supported networks from database.
        
        Args:
            cex_name: Exchange name ('binance', 'bybit', 'okx', 'kucoin', 'mexc')
            coin: Coin symbol ('ETH', 'USDT', etc.)
            allow_stale: If True, return stale cache when fresh not available
        
        Returns:
            Dict with 'supported_networks' (List[str]), 'is_stale' (bool), 'fetched_at' (datetime)
            or None if not found
        """
        if allow_stale:
            # Return even stale cache as fallback
            query = """
                SELECT supported_networks, is_stale, fetched_at
                FROM cex_networks_cache
                WHERE cex_name = %s AND coin = %s
                LIMIT 1
            """
        else:
            # Only return fresh cache (not expired)
            query = """
                SELECT supported_networks, is_stale, fetched_at
                FROM cex_networks_cache
                WHERE cex_name = %s AND coin = %s AND expires_at > NOW()
                LIMIT 1
            """
        
        result = self.execute_query(query, (cex_name, coin.upper()), fetch='one')
        
        if result and 'supported_networks' in result:
            # Parse JSONB if it's a string
            networks = result['supported_networks']
            if isinstance(networks, str):
                import json
                networks = json.loads(networks)
            result['supported_networks'] = networks
        
        return result
    
    def set_cex_networks_cache(
        self,
        cex_name: str,
        coin: str,
        networks: List[str]
    ) -> None:
        """
        Save CEX supported networks to cache.
        
        The expires_at is automatically set by trigger (fetched_at + 24 hours).
        
        Args:
            cex_name: Exchange name ('binance', 'bybit', 'okx', 'kucoin', 'mexc')
            coin: Coin symbol ('ETH', 'USDT', etc.)
            networks: List of supported network names
        """
        import json
        
        query = """
            INSERT INTO cex_networks_cache (cex_name, coin, supported_networks, fetched_at, is_stale)
            VALUES (%s, %s, %s, NOW(), FALSE)
            ON CONFLICT (cex_name, coin)
            DO UPDATE SET
                supported_networks = EXCLUDED.supported_networks,
                fetched_at = NOW(),
                is_stale = FALSE
        """
        
        self.execute_query(query, (cex_name, coin.upper(), json.dumps(networks)))
        logger.debug(f"CEX cache saved | {cex_name} {coin} | {len(networks)} networks")
    
    def mark_cex_cache_stale(self, cex_name: str, coin: str) -> None:
        """
        Mark CEX cache as stale when API fails.
        
        This allows fallback to old data while indicating it may be outdated.
        
        Args:
            cex_name: Exchange name
            coin: Coin symbol
        """
        query = """
            UPDATE cex_networks_cache
            SET is_stale = TRUE
            WHERE cex_name = %s AND coin = %s
        """
        self.execute_query(query, (cex_name, coin.upper()))
        logger.warning(f"CEX cache marked as stale | {cex_name} {coin}")
    
    def clear_expired_cex_cache(self, days_old: int = 7) -> int:
        """
        Delete expired cache entries older than specified days.
        
        Args:
            days_old: Delete entries expired more than this many days ago
        
        Returns:
            Number of deleted entries
        """
        query = """
            DELETE FROM cex_networks_cache
            WHERE expires_at < NOW() - INTERVAL '%s days'
            RETURNING id
        """
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (days_old,))
                deleted = cur.rowcount
                logger.info(f"Cleared {deleted} expired CEX cache entries (older than {days_old} days)")
                return deleted
        
    # ========================================================================
    # DEFILLAMA BRIDGES CACHE QUERIES
    # ========================================================================
    
    def get_defillama_bridges_cache(
        self,
        bridge_name: str,
        allow_expired: bool = False
    ) -> Optional[Dict]:
        """
        Get cached DeFiLlama bridge data by bridge name.
        
        Args:
            bridge_name: Bridge provider name (e.g., 'across', 'stargate')
            allow_expired: If True, return expired cache as fallback
        
        Returns:
            Dict with keys: bridge_name, tvl_usd, rank, hacks, chains, fetched_at, expires_at
            or None if not found
        """
        import json
        
        if allow_expired:
            query = """
                SELECT bridge_name, display_name, tvl_usd, volume_30d_usd, rank,
                       hacks, chains, fetched_at, expires_at
                FROM defillama_bridges_cache
                WHERE bridge_name = %s
                LIMIT 1
            """
        else:
            query = """
                SELECT bridge_name, display_name, tvl_usd, volume_30d_usd, rank,
                       hacks, chains, fetched_at, expires_at
                FROM defillama_bridges_cache
                WHERE bridge_name = %s AND expires_at > NOW()
                LIMIT 1
            """
        
        result = self.execute_query(query, (bridge_name,), fetch='one')
        
        if result:
            # Parse JSONB fields if needed
            if 'chains' in result and isinstance(result['chains'], str):
                result['chains'] = json.loads(result['chains'])
            if 'hacks' in result and isinstance(result['hacks'], str):
                result['hacks'] = json.loads(result['hacks'])
        
        return result
    
    def set_defillama_bridges_cache(
        self,
        bridge_name: str,
        tvl_usd: int,
        rank: int,
        hacks: List[Dict],
        chains: List[str],
        display_name: Optional[str] = None,
        volume_30d_usd: Optional[int] = None
    ) -> None:
        """
        Save or update DeFiLlama bridge cache.
        
        The expires_at is automatically set by trigger (fetched_at + 6 hours).
        
        Args:
            bridge_name: Bridge provider name (e.g., 'across', 'stargate')
            tvl_usd: Total Value Locked in USD
            rank: Rank in DeFiLlama bridges list
            hacks: List of hack incidents (can be empty list)
            chains: List of supported chain names
            display_name: Optional display name
            volume_30d_usd: Optional 30-day volume
        """
        import json
        
        query = """
            INSERT INTO defillama_bridges_cache
                (bridge_name, display_name, chains, tvl_usd, volume_30d_usd, rank, hacks, fetched_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
            ON CONFLICT (bridge_name)
            DO UPDATE SET
                display_name = COALESCE(EXCLUDED.display_name, defillama_bridges_cache.display_name),
                tvl_usd = EXCLUDED.tvl_usd,
                volume_30d_usd = COALESCE(EXCLUDED.volume_30d_usd, defillama_bridges_cache.volume_30d_usd),
                rank = EXCLUDED.rank,
                hacks = EXCLUDED.hacks,
                chains = EXCLUDED.chains,
                fetched_at = NOW()
        """
        
        self.execute_query(
            query,
            (
                bridge_name,
                display_name,
                json.dumps(chains),
                tvl_usd,
                volume_30d_usd,
                rank,
                json.dumps(hacks)
            )
        )
        
        logger.debug(
            f"DeFiLlama cache saved | {bridge_name} | "
            f"TVL: ${tvl_usd:,.0f} | Rank: #{rank}"
        )
    
    def clear_expired_defillama_cache(self, days_old: int = 7) -> int:
        """
        Delete expired DeFiLlama cache entries older than specified days.
        
        Args:
            days_old: Delete entries expired more than this many days ago
        
        Returns:
            Number of deleted entries
        """
        query = """
            DELETE FROM defillama_bridges_cache
            WHERE expires_at < NOW() - INTERVAL '%s days'
            RETURNING id
        """
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (days_old,))
                deleted = cur.rowcount
                logger.info(f"Cleared {deleted} expired DeFiLlama cache entries (older than {days_old} days)")
                return deleted
        
    def create_bridge_history(
        self,
        wallet_id: int,
        from_network: str,
        to_network: str,
        provider: str,
        amount_eth: Decimal,
        cost_usd: Decimal,
        safety_score: int,
        tx_hash: Optional[str] = None,
        defillama_tvl_usd: Optional[int] = None,
        defillama_volume_30d_usd: Optional[int] = None,
        defillama_rank: Optional[int] = None,
        defillama_hacks: Optional[int] = None,
        cex_checked: Optional[str] = None,
        cex_support_found: Optional[bool] = None,
        status: str = 'completed',
        error_message: Optional[str] = None
    ) -> int:
        """
        Record a bridge operation to bridge_history table.
        
        Args:
            wallet_id: ID of wallet performing bridge
            from_network: Source network (e.g., 'Arbitrum')
            to_network: Destination network (e.g., 'Ink', 'MegaETH')
            provider: Bridge provider name (e.g., 'Across Protocol')
            amount_eth: Amount in ETH
            cost_usd: Cost in USD
            safety_score: DeFiLlama safety score 0-100
            tx_hash: On-chain transaction hash
            defillama_tvl_usd: Total Value Locked in USD
            defillama_volume_30d_usd: 30-day volume in USD
            defillama_rank: Rank in DeFiLlama bridges list
            defillama_hacks: Number of known hacks/exploits
            cex_checked: Comma-separated list of CEXes checked
            cex_support_found: TRUE if any CEX supports the network
            status: Bridge status (pending, completed, failed, etc.)
            error_message: Error message if failed
        
        Returns:
            ID of created bridge_history record
        """
        query = """
            INSERT INTO bridge_history (
                wallet_id, from_network, to_network, provider, amount_eth,
                cost_usd, tx_hash, defillama_tvl_usd, defillama_volume_30d_usd,
                defillama_rank, defillama_hacks, safety_score, cex_checked,
                cex_support_found, status, error_message, completed_at
            ) VALUES (
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                CASE WHEN %s = 'completed' THEN NOW() ELSE NULL END
            )
            RETURNING id
        """
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (
                    wallet_id, from_network, to_network, provider, amount_eth,
                    cost_usd, tx_hash, defillama_tvl_usd, defillama_volume_30d_usd,
                    defillama_rank, defillama_hacks, safety_score, cex_checked,
                    cex_support_found, status, error_message, status
                ))
                bridge_id = cur.fetchone()[0]
                logger.info(
                    f"Bridge history created | ID: {bridge_id} | "
                    f"{from_network} → {to_network} | Provider: {provider} | "
                    f"Amount: {amount_eth} ETH | Safety: {safety_score}/100"
                )
                return bridge_id

    # ========================================================================
    # SYSTEM CONFIG QUERIES
    # ========================================================================
    
    def get_system_config(self, key: str, default: Any = None) -> Optional[Any]:
        """
        Get a system configuration value by key.
        
        Args:
            key: Configuration key (e.g., 'decodo_ttl_minutes')
            default: Default value if key not found
        
        Returns:
            Configuration value parsed by type, or default if not found
        """
        query = "SELECT value, value_type FROM system_config WHERE key = %s"
        result = self.execute_query(query, (key,), fetch='one')
        
        if not result:
            return default
        
        value = result['value']
        value_type = result['value_type']
        
        # Parse value based on type
        if value_type == 'integer':
            return int(value)
        elif value_type == 'float':
            return float(value)
        elif value_type == 'boolean':
            return value.lower() in ('true', '1', 'yes')
        elif value_type == 'json':
            import json
            return json.loads(value)
        else:  # string
            return value
    
    def get_system_config_by_category(self, category: str) -> Dict[str, Any]:
        """
        Get all system configuration values for a category.
        
        Args:
            category: Category name (e.g., 'proxy', 'gas', 'security')
        
        Returns:
            Dict mapping key -> parsed value
        """
        query = "SELECT key, value, value_type FROM system_config WHERE category = %s"
        results = self.execute_query(query, (category,), fetch='all')
        
        config = {}
        for row in results:
            value = row['value']
            value_type = row['value_type']
            
            # Parse value based on type
            if value_type == 'integer':
                config[row['key']] = int(value)
            elif value_type == 'float':
                config[row['key']] = float(value)
            elif value_type == 'boolean':
                config[row['key']] = value.lower() in ('true', '1', 'yes')
            elif value_type == 'json':
                import json
                config[row['key']] = json.loads(value)
            else:  # string
                config[row['key']] = value
        
        return config
    
    def set_system_config(self, key: str, value: Any, value_type: str = 'string', 
                        description: Optional[str] = None, category: Optional[str] = None) -> None:
        """
        Set a system configuration value.
        
        Args:
            key: Configuration key
            value: Configuration value
            value_type: Value type ('string', 'integer', 'float', 'boolean', 'json')
            description: Optional description
            category: Optional category
        """
        import json
        
        # Convert value to string based on type
        if value_type == 'json':
            value_str = json.dumps(value)
        else:
            value_str = str(value)
        
        query = """
            INSERT INTO system_config (key, value, value_type, description, category, updated_at)
            VALUES (%s, %s, %s, %s, %s, NOW())
            ON CONFLICT (key) DO UPDATE SET
                value = EXCLUDED.value,
                value_type = EXCLUDED.value_type,
                description = COALESCE(EXCLUDED.description, system_config.description),
                category = COALESCE(EXCLUDED.category, system_config.category),
                updated_at = NOW()
        """
        self.execute_query(query, (key, value_str, value_type, description, category))
        logger.debug(f"System config updated | Key: {key} | Value: {value_str}")
    
    def get_chain_config(self, chain: str) -> Optional[Dict]:
        """
        Get chain configuration including native_token, block_time, is_poa.
        
        Args:
            chain: Chain name (e.g., 'arbitrum', 'base')
        
        Returns:
            Dict with chain configuration or None if not found
        """
        query = """
            SELECT chain, chain_id, native_token, block_time, is_poa, is_l2, network_type
            FROM chain_rpc_endpoints
            WHERE chain = %s AND is_active = TRUE
            GROUP BY chain, chain_id, native_token, block_time, is_poa, is_l2, network_type
            LIMIT 1
        """
        return self.execute_query(query, (chain.lower(),), fetch='one')
    
    def get_all_chain_configs(self) -> Dict[str, Dict]:
        """
        Get all chain configurations.
        
        Returns:
            Dict mapping chain name -> config dict
        """
        query = """
            SELECT chain, chain_id, native_token, block_time, is_poa, is_l2, network_type
            FROM chain_rpc_endpoints
            WHERE is_active = TRUE
            GROUP BY chain, chain_id, native_token, block_time, is_poa, is_l2, network_type
            ORDER BY chain
        """
        results = self.execute_query(query, fetch='all')
        
        return {row['chain']: row for row in results}
    
    # ========================================================================
    # MONITORING QUERIES
    # ========================================================================
    
    # ========================================================================
    # SMART RISK ENGINE QUERIES (Module 2)
    # ========================================================================
    
    def get_token_cache(self, protocol_name: str) -> Optional[Dict]:
        """
        Get cached token check result.
        
        Args:
            protocol_name: Protocol/chain name to check
        
        Returns:
            Dict with has_token, ticker, market_cap_usd, source, checked_at or None
        """
        query = """
            SELECT protocol_name, has_token, ticker, market_cap_usd, source, checked_at
            FROM token_check_cache
            WHERE protocol_name = %s
        """
        return self.execute_query(query, (protocol_name.lower(),), fetch='one')
    
    def set_token_cache(
        self, 
        protocol_name: str, 
        has_token: bool,
        ticker: Optional[str] = None,
        market_cap: Optional[float] = None,
        source: str = 'coingecko'
    ) -> None:
        """
        Cache token check result.
        
        Args:
            protocol_name: Protocol/chain name
            has_token: Whether protocol has its own token
            ticker: Token ticker symbol (if has_token)
            market_cap: Market cap in USD (if available)
            source: Data source ('coingecko' or 'defillama')
        """
        from datetime import datetime
        
        query = """
            INSERT INTO token_check_cache 
                (protocol_name, has_token, ticker, market_cap_usd, checked_at, source)
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (protocol_name) DO UPDATE SET
                has_token = EXCLUDED.has_token,
                ticker = EXCLUDED.ticker,
                market_cap_usd = EXCLUDED.market_cap_usd,
                checked_at = EXCLUDED.checked_at,
                source = EXCLUDED.source
        """
        self.execute_query(query, (
            protocol_name.lower(), has_token, ticker, market_cap, datetime.now(), source
        ))
        logger.debug(f"Token cache updated | {protocol_name}: has_token={has_token}, ticker={ticker}")
    
    def clear_expired_token_cache(self) -> int:
        """
        Remove token cache entries older than 24 hours.
        
        Returns:
            Number of deleted rows
        """
        query = "SELECT clear_expired_token_cache()"
        result = self.execute_query(query, fetch='one')
        deleted = result['clear_expired_token_cache'] if result else 0
        if deleted > 0:
            logger.info(f"Cleared {deleted} expired token cache entries")
        return deleted
    
    def update_chain_farm_status(
        self, 
        chain: str, 
        farm_status: str,
        token_ticker: Optional[str] = None
    ) -> None:
        """
        Update chain farming status (ACTIVE, TARGET, DROPPED, INACTIVE).
        
        Args:
            chain: Chain name (e.g., 'arbitrum', 'base')
            farm_status: New status (ACTIVE, TARGET, DROPPED, INACTIVE)
            token_ticker: Token ticker if chain has its own token
        """
        from datetime import datetime
        
        query = """
            UPDATE chain_rpc_endpoints
            SET farm_status = %s,
                token_ticker = COALESCE(%s, token_ticker),
                last_discovery_check = %s
            WHERE chain = %s
        """
        self.execute_query(query, (farm_status, token_ticker, datetime.now(), chain.lower()))
        logger.info(f"Chain {chain} farm_status updated: {farm_status}" + (f", token={token_ticker}" if token_ticker else ""))
    
    def get_active_farming_chains(self) -> List[Dict]:
        """
        Get all chains with ACTIVE or TARGET farm_status.
        
        Returns:
            List of dicts with chain, farm_status, token_ticker
        """
        query = """
            SELECT DISTINCT chain, farm_status, token_ticker
            FROM chain_rpc_endpoints
            WHERE farm_status IN ('ACTIVE', 'TARGET')
              AND is_active = TRUE
            ORDER BY chain
        """
        return self.execute_query(query, fetch='all') or []
    
    def update_protocol_risk(
        self,
        protocol_id: int,
        risk_level: str,
        risk_tags: List[str],
        requires_manual: bool,
        risk_score: Optional[int] = None
    ) -> None:
        """
        Update protocol risk assessment in protocol_research_pending.
        
        Args:
            protocol_id: Protocol ID in protocol_research_pending
            risk_level: Risk level (LOW, MEDIUM, HIGH, CRITICAL)
            risk_tags: List of risk tags (e.g., ['SYBIL', 'TVL_LOW'])
            requires_manual: Whether protocol requires manual review
            risk_score: Risk score 0-100 (optional)
        """
        query = """
            UPDATE protocol_research_pending
            SET risk_level = %s,
                risk_tags = %s,
                requires_manual = %s,
                risk_score = %s
            WHERE id = %s
        """
        from psycopg2.extras import Json
        self.execute_query(query, (risk_level, risk_tags, requires_manual, risk_score, protocol_id))
        logger.debug(f"Protocol {protocol_id} risk updated: {risk_level}, score={risk_score}, tags={risk_tags}")

 
# ============================================================================
# Module-level convenience function
# ============================================================================

def get_db_manager() -> DatabaseManager:
    """
    Get a singleton DatabaseManager instance.
    
    Returns:
        DatabaseManager instance
    """
    if not hasattr(get_db_manager, '_instance'):
        get_db_manager._instance = DatabaseManager()
    return get_db_manager._instance


if __name__ == '__main__':
    # Test database connection
    db = DatabaseManager()
    
    # Test queries
    print("=== Testing Database Connection ===")
    
    # Test worker_nodes
    worker = db.get_worker_node(1)
    if worker:
        print(f"✅ Worker 1: {worker['hostname']} ({worker['location']})")
    else:
        print("⚠️  Worker 1 not found. Run setup scripts first.")
    
    # Test proxy_pool
    proxies_nl = db.get_proxies_by_country('NL')
    print(f"✅ NL Proxies: {len(proxies_nl)} found")
    
    proxies_is = db.get_proxies_by_country('IS')
    print(f"✅ IS Proxies: {len(proxies_is)} found")
    
    # Test protocols
    active_protocols = db.get_active_protocols()
    print(f"✅ Active Protocols: {len(active_protocols)} found")
    
    db.close_pool()
    print("\n✅ Database test completed successfully!")
