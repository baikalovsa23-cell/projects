"""
Module 17: Airdrop Detector — Async Token Balance Scanner

Scans 90 wallets across 7 chains every 6 hours to detect new token balances
(potential airdrops). Integrates with blockchain explorer APIs (Etherscan,
Basescan, Arbiscan, etc.) and triggers Telegram alerts for verified airdrops.

Usage:
    detector = AirdropDetector()
    stats = await detector.scan_all_wallets()

Integration:
    - APScheduler: Every 6 hours (00:00, 06:00, 12:00, 18:00 UTC)
    - Module 18: Token Verifier for scam detection
    - Telegram: Instant alerts for verified airdrops
"""

import asyncio
import os
import time
from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal
from typing import Dict, List, Optional, Any
from urllib.parse import urlencode

from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential

from database.db_manager import get_db_manager

# TLS Fingerprinting support (async)
from infrastructure.identity_manager import get_async_curl_session


# ============================================================================
# DATACLASS DEFINITIONS
# ============================================================================

@dataclass
class TokenBalance:
    """
    Represents a token balance detected on a wallet.
    """
    contract_address: str  # 0x...
    symbol: str  # "ARB", "USDC", etc.
    name: Optional[str]  # "Arbitrum", "USD Coin"
    decimals: int  # 18, 6, etc.
    balance_raw: int  # Raw balance (big integer)
    balance_human: Decimal  # Human-readable balance
    chain: str  # 'arbitrum', 'base', etc.
    
    @property
    def is_airdrop_candidate(self) -> bool:
        """
        Heuristic: Token likely airdrop if balance > 0 and symbol not stablecoin.
        """
        stablecoins = ['USDC', 'USDT', 'DAI', 'BUSD', 'USDbC', 'USDC.e', 'USDT.e']
        wrapped_native = ['WETH', 'WMATIC', 'WBNB', 'WAVAX', 'WETH.e']
        return (
            self.balance_human > 0 and 
            self.symbol not in stablecoins and
            self.symbol not in wrapped_native
        )


@dataclass
class ScanResult:
    """
    Result of a single wallet scan on a chain.
    """
    wallet_address: str
    wallet_id: int
    chain: str
    tokens_found: List[TokenBalance]
    new_tokens: List[TokenBalance]
    scan_timestamp: datetime
    api_response_time_ms: float
    error: Optional[str] = None


@dataclass
class ScanCycleStats:
    """
    Statistics for a complete scan cycle (all wallets, all chains).
    """
    scan_id: int
    start_time: datetime
    end_time: datetime
    total_wallets: int
    total_chains: int
    total_api_calls: int
    new_tokens_detected: int
    alerts_sent: int
    errors_encountered: int
    duration_seconds: float
    chain_stats: Dict[str, Any] = field(default_factory=dict)


# ============================================================================
# EXPLORER API CLIENTS
# ============================================================================

class ExplorerAPI:
    """
    Base class for blockchain explorer API clients.
    """
    
    # API configuration per chain
    EXPLORER_CONFIG = {
        'arbitrum': {
            'name': 'Arbiscan',
            'base_url': 'https://api.arbiscan.io/api',
            'api_key_env': 'ARBISCAN_API_KEY',
        },
        'base': {
            'name': 'Basescan',
            'base_url': 'https://api.basescan.org/api',
            'api_key_env': 'BASESCAN_API_KEY',
        },
        'optimism': {
            'name': 'Optimistic Etherscan',
            'base_url': 'https://api-optimistic.etherscan.io/api',
            'api_key_env': 'OPTIMISM_ETHERSCAN_API_KEY',
        },
        'polygon': {
            'name': 'Polygonscan',
            'base_url': 'https://api.polygonscan.com/api',
            'api_key_env': 'POLYGONSCAN_API_KEY',
        },
        'bnbchain': {
            'name': 'BscScan',
            'base_url': 'https://api.bscscan.com/api',
            'api_key_env': 'BSCSCAN_API_KEY',
        },
    }
    
    # Chains without explorer API (use RPC fallback)
    RPC_ONLY_CHAINS = ['ink', 'megaeth']
    
    def __init__(self):
        self.api_keys = {}
        for chain, config in self.EXPLORER_CONFIG.items():
            self.api_keys[chain] = os.getenv(config['api_key_env'], '')
    
    def get_api_key(self, chain: str) -> str:
        """Get API key for chain, return empty string if not set."""
        return self.api_keys.get(chain, '')
    
    def has_explorer(self, chain: str) -> bool:
        """Check if chain has explorer API."""
        return chain in self.EXPLORER_CONFIG
    
    def get_base_url(self, chain: str) -> str:
        """Get base URL for chain's explorer API."""
        return self.EXPLORER_CONFIG.get(chain, {}).get('base_url', '')


# ============================================================================
# MAIN DETECTOR CLASS
# ============================================================================

class AirdropDetector:
    """
    Scans 90 wallets across 7 chains for new token balances.
    
    Integrates with blockchain explorer APIs to detect airdrops.
    Stores detected tokens in database and triggers Telegram alerts.
    
    Attributes:
        db: Database manager instance
        explorer: ExplorerAPI client for API calls
        chains: List of supported chains
        scan_interval_hours: How often to scan (default: 6)
    """
    
    # Supported chains
    SUPPORTED_CHAINS = ['arbitrum', 'base', 'optimism', 'polygon', 'bnbchain', 'ink', 'megaeth']
    
    # Chains with explorer API (others use RPC fallback)
    EXPLORER_CHAINS = ['arbitrum', 'base', 'optimism', 'polygon', 'bnbchain']
    
    # Rate limit: 5 calls/sec = 0.2s delay between calls
    RATE_LIMIT_DELAY = 0.2
    
    # Minimum balance to consider (filter dust)
    MIN_BALANCE_THRESHOLD = Decimal('0.01')
    
    def __init__(self, db_manager=None):
        """
        Initialize AirdropDetector.
        
        Args:
            db_manager: DatabaseManager instance (optional, uses default if None)
        """
        self.db = db_manager or get_db_manager()
        self.explorer = ExplorerAPI()
        
        logger.info("AirdropDetector initialized")
        logger.info(f"Supported chains: {', '.join(self.SUPPORTED_CHAINS)}")
        logger.info(f"Explorer API chains: {', '.join(self.EXPLORER_CHAINS)}")
        logger.info(f"RPC-only chains: {', '.join(self.RPC_ONLY_CHAINS)}")
    
    async def scan_all_wallets(self) -> ScanCycleStats:
        """
        Scan all 90 wallets across all chains for new tokens.
        
        Returns:
            ScanCycleStats with statistics from the scan cycle
        """
        start_time = datetime.now()
        logger.info("Starting airdrop scan cycle")
        
        # Create scan log entry
        scan_id = self._create_scan_log(start_time)
        
        stats = ScanCycleStats(
            scan_id=scan_id,
            start_time=start_time,
            end_time=datetime.now(),
            total_wallets=0,
            total_chains=len(self.SUPPORTED_CHAINS),
            total_api_calls=0,
            new_tokens_detected=0,
            alerts_sent=0,
            errors_encountered=0,
            duration_seconds=0.0,
            chain_stats={}
        )
        
        try:
            # Get all wallets from database
            wallets = self.db.get_all_wallets()
            stats.total_wallets = len(wallets)
            logger.info(f"Scanning {len(wallets)} wallets across {stats.total_chains} chains")
            
            # Scan each chain
            for chain in self.SUPPORTED_CHAINS:
                chain_start = time.time()
                chain_stats = {
                    'api_calls': 0,
                    'errors': 0,
                    'duration_ms': 0,
                    'new_tokens': 0
                }
                
                for wallet in wallets:
                    try:
                        result = await self.scan_wallet_on_chain(
                            wallet_address=wallet.address,
                            wallet_id=wallet.id,
                            chain=chain
                        )
                        
                        # Process new tokens
                        if result.new_tokens:
                            for token in result.new_tokens:
                                # Filter obvious non-airdrops
                                if self._filter_obvious_non_airdrops(token):
                                    stats.new_tokens_detected += 1
                                    chain_stats['new_tokens'] += 1
                                    
                                    # Send to token verifier and potentially alert
                                    await self._process_new_token(wallet.id, token)
                        
                        stats.total_api_calls += 1
                        chain_stats['api_calls'] += 1
                        
                        # Rate limiting
                        await asyncio.sleep(self.RATE_LIMIT_DELAY)
                        
                    except Exception as e:
                        logger.error(f"Error scanning wallet {wallet.address} on {chain}: {e}")
                        stats.errors_encountered += 1
                        chain_stats['errors'] += 1
                
                chain_duration = (time.time() - chain_start) * 1000
                chain_stats['duration_ms'] = int(chain_duration)
                stats.chain_stats[chain] = chain_stats
                
                logger.info(
                    f"Chain {chain}: {chain_stats['api_calls']} calls, "
                    f"{chain_stats['new_tokens']} new tokens, "
                    f"{chain_stats['duration_ms']}ms"
                )
            
        except Exception as e:
            logger.exception(f"Scan cycle failed: {e}")
            stats.errors_encountered += 1
        
        # Complete scan
        end_time = datetime.now()
        stats.end_time = end_time
        stats.duration_seconds = (end_time - start_time).total_seconds()
        
        # Update scan log
        self._update_scan_log(stats)
        
        logger.info(
            f"Scan cycle completed in {stats.duration_seconds:.1f}s | "
            f"Wallets: {stats.total_wallets}, "
            f"New tokens: {stats.new_tokens_detected}, "
            f"Alerts: {stats.alerts_sent}, "
            f"Errors: {stats.errors_encountered}"
        )
        
        return stats
    
    async def scan_wallet_on_chain(
        self, 
        wallet_address: str,
        wallet_id: int,
        chain: str
    ) -> ScanResult:
        """
        Scan a single wallet on a specific chain.
        
        Args:
            wallet_address: Ethereum address
            wallet_id: Wallet database ID
            chain: Chain identifier ('arbitrum', 'base', etc.)
            
        Returns:
            ScanResult with tokens found and new tokens
        """
        start_time = time.time()
        scan_timestamp = datetime.now()
        
        try:
            if chain in self.EXPLORER_CHAINS:
                tokens = await self._fetch_tokens_via_explorer(wallet_address, wallet_id, chain)
            else:
                tokens = await self._fetch_tokens_via_rpc(wallet_address, chain)
            
            # Get existing tokens from database
            existing_tokens = self._get_existing_tokens(wallet_id, chain)
            existing_contracts = {t['token_contract_address'] for t in existing_tokens}
            
            # Find new tokens
            new_tokens = [
                token for token in tokens
                if token.contract_address not in existing_contracts and token.balance_human > 0
            ]
            
            # Update database with current balances
            for token in tokens:
                self._upsert_wallet_token(
                    wallet_id=wallet_id,
                    chain=chain,
                    token=token
                )
            
            response_time = (time.time() - start_time) * 1000
            
            return ScanResult(
                wallet_address=wallet_address,
                wallet_id=wallet_id,
                chain=chain,
                tokens_found=tokens,
                new_tokens=new_tokens,
                scan_timestamp=scan_timestamp,
                api_response_time_ms=response_time
            )
            
        except Exception as e:
            logger.error(f"Error scanning {wallet_address} on {chain}: {e}")
            return ScanResult(
                wallet_address=wallet_address,
                wallet_id=wallet_id,
                chain=chain,
                tokens_found=[],
                new_tokens=[],
                scan_timestamp=scan_timestamp,
                api_response_time_ms=0,
                error=str(e)
            )
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=8))
    async def _fetch_tokens_via_explorer(
        self,
        wallet_address: str,
        wallet_id: int,
        chain: str
    ) -> List[TokenBalance]:
        """
        Fetch token transfers via explorer API with browser-like TLS fingerprint.
        
        Args:
            wallet_address: Wallet address to scan
            wallet_id: Wallet ID for TLS fingerprint selection
            chain: Chain identifier
            
        Returns:
            List of TokenBalance objects
        """
        base_url = self.explorer.get_base_url(chain)
        api_key = self.explorer.get_api_key(chain)
        
        params = {
            'module': 'account',
            'action': 'tokentx',
            'address': wallet_address,
            'sort': 'desc',  # Most recent first
            'page': 1,
            'offset': 100,  # Get last 100 transactions
        }
        
        if api_key:
            params['apikey'] = api_key
        
        # Build full URL with params
        from urllib.parse import urlencode
        full_url = f"{base_url}?{urlencode(params)}"
        
        # Use curl_cffi with browser-like fingerprint
        async with get_async_curl_session(wallet_id, proxy_url=None) as session:
            try:
                response = await session.get(full_url, timeout=30)
                
                if response.status_code == 429:
                    logger.warning(f"Rate limit hit for {chain}, retrying...")
                    raise Exception("Rate limit exceeded")
                
                response.raise_for_status()
                
                # IMPORTANT: .json() is NOT a coroutine in curl_cffi!
                data = response.json()
            except Exception as e:
                logger.error(f"Explorer API request failed for wallet {wallet_id} on {chain}: {e}")
                raise
        
        if data.get('status') != '1':
            return []
        
        tokens = []
        seen_contracts = set()
        
        for tx in data.get('result', []):
            contract_address = tx.get('contractAddress', '').lower()
            if not contract_address or contract_address in seen_contracts:
                continue
            
            seen_contracts.add(contract_address)
            
            symbol = tx.get('tokenSymbol', 'UNKNOWN')
            decimals = int(tx.get('tokenDecimal', 18))
            raw_balance = int(tx.get('value', 0))
            
            # Calculate human-readable balance
            if decimals > 0:
                balance_human = Decimal(raw_balance) / Decimal(10 ** decimals)
            else:
                balance_human = Decimal(raw_balance)
            
            # Filter dust amounts
            if balance_human < self.MIN_BALANCE_THRESHOLD:
                continue
            
            tokens.append(TokenBalance(
                contract_address=contract_address,
                symbol=symbol,
                name=tx.get('tokenName'),
                decimals=decimals,
                balance_raw=raw_balance,
                balance_human=balance_human,
                chain=chain
            ))
        
        return tokens
    
    async def _fetch_tokens_via_rpc(
        self, 
        wallet_address: str, 
        chain: str
    ) -> List[TokenBalance]:
        """
        Fetch token balances via RPC for chains without explorer API.
        
        Note: This is a simplified implementation. In production, you'd need
        to maintain a list of known token contracts per chain.
        
        Args:
            wallet_address: Wallet address to scan
            chain: Chain identifier
            
        Returns:
            List of TokenBalance objects
        """
        # For now, return empty list - RPC fallback is complex
        # In V2, implement via web3.py contract calls
        logger.debug(f"RPC fallback for {chain} - not implemented yet")
        return []
    
    def _filter_obvious_non_airdrops(self, token: TokenBalance) -> bool:
        """
        Filter out tokens that are obviously not airdrops.
        
        Args:
            token: TokenBalance to check
            
        Returns:
            True if token should be kept (potential airdrop)
        """
        # Filter stablecoins
        stablecoins = {'USDC', 'USDT', 'DAI', 'BUSD', 'USDbC', 'USDC.e', 'USDT.e', 'USDP'}
        if token.symbol in stablecoins:
            return False
        
        # Filter wrapped native tokens
        wrapped_native = {'WETH', 'WMATIC', 'WBNB', 'WAVAX', 'WETH.e', 'MATIC'}
        if token.symbol in wrapped_native:
            return False
        
        # Filter very low balances (dust)
        if token.balance_human < self.MIN_BALANCE_THRESHOLD:
            return False
        
        return True
    
    async def _process_new_token(
        self, 
        wallet_id: int, 
        token: TokenBalance
    ) -> Optional[int]:
        """
        Process newly detected token through verification pipeline.
        
        Args:
            wallet_id: Wallet database ID
            token: Newly detected token
            
        Returns:
            airdrop_id if verified and saved, else None
        """
        # Send to Token Verifier (Module 18)
        try:
            from monitoring.token_verifier import TokenVerifier
            
            verifier = TokenVerifier()
            verification = await verifier.verify_token(
                contract_address=token.contract_address,
                chain=token.chain,
                symbol=token.symbol
            )
            
            # Only create airdrop entry if confidence > 0.6
            if verification.confidence_score > 0.6:
                airdrop_id = self._create_airdrop_entry(
                    wallet_id=wallet_id,
                    token=token,
                    confidence=verification.confidence_score,
                    is_confirmed=verification.is_on_coingecko
                )
                
                # Send Telegram alert
                await self._send_airdrop_alert(wallet_id, token, verification)
                
                return airdrop_id
            
        except ImportError:
            logger.warning("TokenVerifier not available, skipping verification")
        
        return None
    
    def _create_airdrop_entry(
        self,
        wallet_id: int,
        token: TokenBalance,
        confidence: float,
        is_confirmed: bool
    ) -> int:
        """
        Create airdrop entry in database.
        
        Args:
            wallet_id: Wallet ID
            token: Detected token
            confidence: Verification confidence score
            is_confirmed: Whether token is on CoinGecko
            
        Returns:
            Created airdrop ID
        """
        logger.info(
            f"Creating airdrop entry: {token.symbol} on {token.chain} "
            f"(confidence: {confidence:.2f}, confirmed: {is_confirmed})"
        )
        query = """
            INSERT INTO airdrops (
                token_symbol, token_contract_address, chain,
                is_confirmed, confidence_score
            ) VALUES (%s, %s, %s, %s, %s)
            RETURNING id
        """
        with self.db.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (
                    token.symbol, token.contract_address, token.chain,
                    is_confirmed, confidence
                ))
                return cur.fetchone()[0]
    
    async def _send_airdrop_alert(
        self, 
        wallet_id: int, 
        token: TokenBalance,
        verification
    ):
        """
        Send Telegram notification about detected airdrop.
        
        Args:
            wallet_id: Wallet ID
            token: Detected token
            verification: VerificationResult from TokenVerifier
        """
        try:
            from notifications.telegram_bot import send_alert
            
            wallet = self.db.get_wallet(wallet_id)
            wallet_label = f"#{wallet_id}" + (f" ({wallet.tier})" if wallet else "")
            
            message = (
                f"🪂 *New Airdrop Detected!*\n\n"
                f"*Wallet:* {wallet_label}\n"
                f"*Chain:* {token.chain.capitalize()}\n"
                f"*Token:* {token.symbol} ({token.name or 'Unknown'})\n"
                f"*Balance:* {token.balance_human:,.4f} {token.symbol}\n"
                f"*Contract:* `{token.contract_address}`\n\n"
                f"*Confidence:* {verification.confidence_score:.2f} "
                f"({'CoinGecko Listed ✅' if verification.is_on_coingecko else 'Not Listed ⚠️'})\n\n"
                f"*Actions:*\n"
                f"`/approve_withdrawal_{wallet_id}` — Start withdrawal\n"
                f"`/check_token_{token.symbol}` — More info"
            )
            
            send_alert('airdrop', message)
            logger.info(f"Telegram alert sent for {token.symbol} airdrop")
            
        except ImportError:
            logger.warning("Telegram bot not available, skipping alert")
        except Exception as e:
            logger.error(f"Failed to send Telegram alert: {e}")
    
    def _get_existing_tokens(self, wallet_id: int, chain: str) -> List[Dict]:
        """
        Get existing token balances for wallet+chain from database.
        
        Args:
            wallet_id: Wallet ID
            chain: Chain identifier
            
        Returns:
            List of existing token records
        """
        query = """
            SELECT * FROM wallet_tokens
            WHERE wallet_id = %s AND chain = %s
        """
        return self.db.execute_query(query, (wallet_id, chain), fetch='all')
    
    def _upsert_wallet_token(
        self,
        wallet_id: int,
        chain: str,
        token: TokenBalance
    ):
        """
        Insert or update token balance in database.
        
        Args:
            wallet_id: Wallet ID
            chain: Chain identifier
            token: TokenBalance to save
        """
        query = """
            INSERT INTO wallet_tokens (
                wallet_id, token_contract_address, symbol, name,
                decimals, balance_raw, balance_human, chain
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (wallet_id, token_contract_address, chain) DO UPDATE
            SET balance_raw = EXCLUDED.balance_raw,
                balance_human = EXCLUDED.balance_human,
                last_updated = NOW()
        """
        self.db.execute_query(query, (
            wallet_id, token.contract_address, token.symbol, token.name,
            token.decimals, token.balance_raw, token.balance_human, chain
        ))
    
    def _create_scan_log(self, start_time: datetime) -> int:
        """
        Create scan log entry in database.
        
        Args:
            start_time: Scan start timestamp
            
        Returns:
            Created log ID
        """
        query = """
            INSERT INTO airdrop_scan_logs (start_time, status)
            VALUES (%s, 'running')
            RETURNING id
        """
        with self.db.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, (start_time,))
                return cur.fetchone()[0]
    
    def _update_scan_log(self, stats: ScanCycleStats):
        """
        Update scan log with completion statistics.
        
        Args:
            stats: ScanCycleStats with results
        """
        query = """
            UPDATE airdrop_scan_logs
            SET end_time = %s, total_wallets = %s, total_chains = %s,
                total_api_calls = %s, new_tokens_detected = %s,
                alerts_sent = %s, errors_encountered = %s,
                duration_seconds = %s, chain_stats = %s, status = 'completed'
            WHERE id = %s
        """
        from psycopg2.extras import Json
        self.db.execute_query(query, (
            stats.end_time, stats.total_wallets, stats.total_chains,
            stats.total_api_calls, stats.new_tokens_detected,
            stats.alerts_sent, stats.errors_encountered,
            stats.duration_seconds, Json(stats.chain_stats), stats.scan_id
        ))


# ============================================================================
# CLI INTERFACE
# ============================================================================

async def run_manual_scan():
    """
    Run a manual scan cycle (for testing or /force_airdrop_scan command).
    """
    logger.info("Starting manual airdrop scan")
    detector = AirdropDetector()
    stats = await detector.scan_all_wallets()
    
    print(f"\n{'='*60}")
    print(f"Airdrop Scan Complete")
    print(f"{'='*60}")
    print(f"Duration: {stats.duration_seconds:.1f}s")
    print(f"Wallets scanned: {stats.total_wallets}")
    print(f"Chains scanned: {stats.total_chains}")
    print(f"API calls: {stats.total_api_calls}")
    print(f"New tokens: {stats.new_tokens_detected}")
    print(f"Alerts sent: {stats.alerts_sent}")
    print(f"Errors: {stats.errors_encountered}")
    print(f"{'='*60}\n")


if __name__ == '__main__':
    asyncio.run(run_manual_scan())
