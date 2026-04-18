#!/usr/bin/env python3
"""
Wallet Generator — Module 5
===========================
Генерация 90 EVM кошельков с Anti-Sybil защитой

Features:
- 90 кошельков: 18 Tier A, 45 Tier B, 27 Tier C
- Распределение по 3 Workers (по 30 каждому)
- Назначение уникальных proxies (NL для Worker1, IS для Workers 2-3)
- Шифрование приватных ключей с Fernet
- Сохранение в PostgreSQL (таблица wallets)
- Генерация CEX whitelist CSV (Anti-Sybil: 1-7 дней между адресами)

Usage:
    python wallets/generator.py generate --count 90
    python wallets/generator.py export-whitelist --output cex_whitelist.csv

Author: Airdrop Farming System v4.0
Created: 2026-02-24
"""

import os
import sys
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
import random
import csv

# Добавить parent directory для импорта
sys.path.insert(0, str(Path(__file__).parent.parent))

from eth_account import Account
from cryptography.fernet import Fernet
from loguru import logger
from infrastructure.env_loader import load_env

# Load .env file (supports both production and local dev)
load_env()

from database.db_manager import DatabaseManager


# =============================================================================
# DATA STRUCTURES
# =============================================================================

@dataclass
class WalletConfig:
    """Configuration for wallet generation."""
    tier: str  # 'A', 'B', 'C'
    worker_id: int  # 1, 2, 3
    proxy_country: str  # 'NL' или 'IS'


@dataclass
class GeneratedWallet:
    """Generated wallet data."""
    address: str
    private_key: str
    tier: str
    worker_id: int
    proxy_id: int


# =============================================================================
# WALLET GENERATOR
# =============================================================================

class WalletGenerator:
    """
    Генератор EVM кошельков с Anti-Sybil защитой.
    
    Архитектура:
    - 90 кошельков: 18 Tier A (high-value), 45 Tier B (medium), 27 Tier C (low)
    - Распределение: 30 кошельков на Worker (6 A, 15 B, 9 C)
    - Proxy: Worker1 → NL proxies, Workers 2-3 → IS proxies
    - Приватные ключи шифруются Fernet перед сохранением в БД
    """
    
    def __init__(self, fernet_key: Optional[str] = None):
        """
        Initialize WalletGenerator.
        
        Args:
            fernet_key: Fernet encryption key (defaults to FERNET_KEY env var)
        """
        # Load Fernet key from .env
        fernet_key = fernet_key or os.getenv('FERNET_KEY')
        if not fernet_key:
            raise ValueError("Fernet key not provided. Set FERNET_KEY environment variable.")
        
        # Fernet key already base64 string, encode to bytes
        if isinstance(fernet_key, str):
            fernet_key = fernet_key.encode()
        
        self.fernet = Fernet(fernet_key)
        self.db = DatabaseManager()
        
        # Distribution configuration
        self.distribution = self._calculate_distribution()
        
        logger.info("WalletGenerator initialized | Total wallets: 90 (18 A, 45 B, 27 C)")
    
    def _calculate_distribution(self) -> List[WalletConfig]:
        """
        Calculate wallet distribution across Workers and Tiers.
        
        Returns:
            List of WalletConfig for all 90 wallets
        
        Distribution:
            Worker 1 (NL): 30 wallets (6 A, 15 B, 9 C)
            Worker 2 (IS): 30 wallets (6 A, 15 B, 9 C)
            Worker 3 (IS): 30 wallets (6 A, 15 B, 9 C)
        """
        distribution = []
        
        # For each Worker
        for worker_id in [1, 2, 3]:
            proxy_country = 'NL' if worker_id == 1 else 'IS'
            
            # Tier A: 6 wallets per Worker
            for _ in range(6):
                distribution.append(WalletConfig('A', worker_id, proxy_country))
            
            # Tier B: 15 wallets per Worker
            for _ in range(15):
                distribution.append(WalletConfig('B', worker_id, proxy_country))
            
            # Tier C: 9 wallets per Worker
            for _ in range(9):
                distribution.append(WalletConfig('C', worker_id, proxy_country))
        
        # Shuffle to avoid sequential patterns (Anti-Sybil)
        random.shuffle(distribution)
        
        logger.debug(f"Distribution calculated | Workers: 3 | Total configs: {len(distribution)}")
        return distribution
    
    def _get_available_proxy(self, country_code: str) -> Optional[int]:
        """
        Get an available proxy ID for the specified country.
        
        Args:
            country_code: 'NL' or 'IS'
        
        Returns:
            Proxy ID or None if no proxies available
        """
        # Get proxies that haven't been assigned to wallets yet
        query = """
            SELECT pp.id 
            FROM proxy_pool pp
            LEFT JOIN wallets w ON w.proxy_id = pp.id
            WHERE pp.country_code = %s 
              AND pp.is_active = TRUE
              AND w.id IS NULL
            LIMIT 1
        """
        result = self.db.execute_query(query, (country_code,), fetch='one')
        
        if result:
            return result['id']
        
        logger.warning(f"No available proxies for {country_code}")
        return None
    
    def generate_wallet(self, config: WalletConfig) -> GeneratedWallet:
        """
        Generate a single EVM wallet.
        
        Args:
            config: Wallet configuration (tier, worker, proxy country)
        
        Returns:
            GeneratedWallet with address, private key, and metadata
        """
        # Generate EVM account (uses secure random entropy)
        account = Account.create()
        
        # Get available proxy
        proxy_id = self._get_available_proxy(config.proxy_country)
        if not proxy_id:
            raise ValueError(f"No available proxy for {config.proxy_country}")
        
        wallet = GeneratedWallet(
            address=account.address.lower(),  # ← CRITICAL: Force lowercase for DB constraint
            private_key=account.key.hex(),
            tier=config.tier,
            worker_id=config.worker_id,
            proxy_id=proxy_id
        )
        
        logger.debug(
            f"Wallet generated | Address: {wallet.address[:10]}... | "
            f"Tier: {wallet.tier} | Worker: {wallet.worker_id} | Proxy: {proxy_id}"
        )
        
        return wallet
    
    def _encrypt_private_key(self, private_key: str) -> str:
        """
        Encrypt private key with Fernet.
        
        Args:
            private_key: Hex string private key
        
        Returns:
            Encrypted private key (base64 string)
        """
        return self.fernet.encrypt(private_key.encode()).decode()
    
    def save_wallet_to_db(self, wallet: GeneratedWallet, max_retries: int = 3) -> int:
        """
        Save wallet to PostgreSQL database.
        
        Args:
            wallet: Generated wallet data
            max_retries: Maximum retries on address collision (default 3)
        
        Returns:
            Wallet ID from database
        
        Note:
            Retries on IntegrityError (address collision) by regenerating wallet.
            Probability of collision is ~0 for 90 wallets, but we handle it for safety.
        """
        from tenacity import retry, stop_after_attempt, retry_if_exception_type
        import psycopg2
        
        # Encrypt private key
        encrypted_key = self._encrypt_private_key(wallet.private_key)
        
        # Get worker_node.id from worker_id
        worker_query = "SELECT id FROM worker_nodes WHERE worker_id = %s"
        worker_result = self.db.execute_query(worker_query, (wallet.worker_id,), fetch='one')
        
        if not worker_result:
            # Worker node doesn't exist yet, create it
            logger.warning(f"Worker {wallet.worker_id} not in DB, creating...")
            worker_node_id = self._create_worker_node(wallet.worker_id)
        else:
            worker_node_id = worker_result['id']
        
        # Insert wallet with retry on collision
        for attempt in range(max_retries):
            try:
                insert_query = """
                    INSERT INTO wallets (
                        address, 
                        encrypted_private_key, 
                        tier, 
                        worker_node_id, 
                        proxy_id,
                        status,
                        openclaw_enabled,
                        created_at
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
                    RETURNING id
                """
                
                # OpenClaw enabled only for Tier A
                openclaw_enabled = (wallet.tier == 'A')
                
                result = self.db.execute_query(
                    insert_query,
                    (
                        wallet.address,
                        encrypted_key,
                        wallet.tier,
                        worker_node_id,
                        wallet.proxy_id,
                        'inactive',  # Initial status
                        openclaw_enabled
                    ),
                    fetch='one'
                )
                
                wallet_id = result['id']
                
                logger.info(
                    f"Wallet saved | ID: {wallet_id} | Address: {wallet.address[:10]}... | "
                    f"Tier: {wallet.tier} | Worker: {wallet.worker_id}"
                )
                
                return wallet_id
                
            except psycopg2.IntegrityError as e:
                if 'wallets_address_key' in str(e) and attempt < max_retries - 1:
                    # Address collision - regenerate wallet
                    logger.warning(f"Address collision detected, regenerating (attempt {attempt + 1}/{max_retries})")
                    account = Account.create()
                    wallet.address = account.address.lower()
                    wallet.private_key = account.key.hex()
                    encrypted_key = self._encrypt_private_key(wallet.private_key)
                    continue
                else:
                    # Re-raise if not address collision or max retries reached
                    raise
        
        # Should never reach here
        raise RuntimeError(f"Failed to save wallet after {max_retries} attempts")
    
    def _create_worker_node(self, worker_id: int) -> int:
        """
        Create worker node entry in database.
        
        Args:
            worker_id: Worker ID (1, 2, or 3)
        
        Returns:
            Worker node DB ID
        """
        # Worker metadata - loaded from database worker_nodes table
        # Fallback defaults if not in DB yet
        worker_defaults = {
            1: {'location': 'Amsterdam, NL', 'timezone': 'Europe/Amsterdam', 'utc_offset': 1},
            2: {'location': 'Reykjavik, IS', 'timezone': 'Atlantic/Reykjavik', 'utc_offset': 0},
            3: {'location': 'Reykjavik, IS', 'timezone': 'Atlantic/Reykjavik', 'utc_offset': 0}
        }
        
        # Try to get worker info from database
        worker_db = self.db.execute_query(
            "SELECT ip_address, location, timezone, utc_offset FROM worker_nodes WHERE worker_id = %s",
            (worker_id,),
            fetch='one'
        )
        
        if worker_db:
            ip_address = str(worker_db['ip_address'])
            location = worker_db['location']
            timezone = worker_db['timezone']
            utc_offset = worker_db['utc_offset']
        else:
            # Fallback to defaults (for initial setup)
            defaults = worker_defaults.get(worker_id, worker_defaults[1])
            location = defaults['location']
            timezone = defaults['timezone']
            utc_offset = defaults['utc_offset']
            # IP will be set when worker connects
            ip_address = '0.0.0.0'  # Placeholder, updated on first connection
        
        query = """
            INSERT INTO worker_nodes (
                worker_id, 
                hostname, 
                ip_address, 
                location, 
                timezone, 
                utc_offset,
                status,
                created_at
            ) VALUES (%s, %s, %s, %s, %s, %s, 'active', NOW())
            RETURNING id
        """
        
        hostname = f"worker{worker_id}.farming.local"
        
        result = self.db.execute_query(
            query,
            (worker_id, hostname, ip_address, location, timezone, utc_offset),
            fetch='one'
        )
        
        logger.info(f"Worker node created | ID: {result['id']} | Worker: {worker_id}")
        return result['id']
    
    def generate_all_wallets(self, save_to_db: bool = True) -> List[GeneratedWallet]:
        """
        Generate all 90 wallets.
        
        Args:
            save_to_db: Whether to save wallets to database
        
        Returns:
            List of all generated wallets
        """
        logger.info("Starting wallet generation | Total: 90")
        
        wallets = []
        
        for i, config in enumerate(self.distribution, 1):
            try:
                wallet = self.generate_wallet(config)
                wallets.append(wallet)
                
                if save_to_db:
                    self.save_wallet_to_db(wallet)
                
                # Progress logging every 10 wallets
                if i % 10 == 0:
                    logger.info(f"Progress: {i}/90 wallets generated")
            
            except Exception as e:
                logger.error(f"Failed to generate wallet {i} | Error: {e}")
                raise
        
        logger.success(f"All wallets generated | Total: {len(wallets)}")
        return wallets
    
    def export_cex_whitelist(self, output_file: str = 'cex_whitelist.csv'):
        """
        Export CEX whitelist CSV with Anti-Sybil dates.
        
        CSV Format:
            date, exchange, network, address
        
        Anti-Sybil Strategy:
            - Random pause 1-7 days between addresses
            - Shuffle addresses (not sequential)
            - Different networks for diversity
        
        Args:
            output_file: Path to CSV file
        """
        logger.info(f"Exporting CEX whitelist | Output: {output_file}")
        
        # Get all wallet addresses from DB
        query = "SELECT address, tier FROM wallets ORDER BY RANDOM()"  # Shuffle
        wallets = self.db.execute_query(query, fetch='all')
        
        if not wallets:
            logger.error("No wallets found in database")
            return
        
        # CEX exchanges and networks (based on funding chains)
        cex_networks = [
            ('binance', 'Ink'),
            ('binance', 'BNB Chain'),
            ('binance', 'Polygon'),
            ('bybit', 'Base'),
            ('bybit', 'Polygon'),
            ('bybit', 'BNB Chain'),
            ('okx', 'MegaETH'),
            ('okx', 'Arbitrum'),
            ('okx', 'Polygon'),
            ('kucoin', 'Polygon'),
            ('kucoin', 'BNB Chain'),
            ('mexc', 'Polygon'),
            ('mexc', 'BNB Chain')
        ]
        
        # Target: 10 days window for all 90 addresses
        TARGET_DAYS = 10
        start_date = datetime.now()
        
        # Calculate average days per address to fit in 10 days
        # We have 90 addresses, need to fit in 10 days
        # With random 1-3 hours паузы average = 2.5 hours per wallet
        # But sum of all pauses must not exceed 10 days
        
        # Strategy: randomly distribute 90 addresses within 10 days
        # Use weighted random to ensure we don't exceed 10 days
        
        whitelist_entries = []
        remaining_days = TARGET_DAYS
        remaining_wallets = len(wallets)
        current_date = start_date
        
        for i, wallet in enumerate(wallets):
            # Random CEX and network
            exchange, network = random.choice(cex_networks)
            
            whitelist_entries.append({
                'date': current_date.strftime('%Y-%m-%d'),
                'exchange': exchange,
                'network': network,
                'address': wallet['address'],
                'tier': wallet['tier']
            })
            
            # Anti-Sybil: smart pause calculation
            # Ensure remaining addresses fit within remaining days
            if remaining_wallets > 1:
                # Max pause to leave room for remaining wallets
                max_pause = min(7, remaining_days - remaining_wallets + 1)
                max_pause = max(1, max_pause)  # At least 1 day
                
                pause_days = random.randint(1, max_pause)
                current_date += timedelta(days=pause_days)
                remaining_days -= pause_days
                remaining_wallets -= 1
        
        # Write to CSV
        output_path = Path(output_file)
        with open(output_path, 'w', newline='') as csvfile:
            fieldnames = ['date', 'exchange', 'network', 'address']
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            
            writer.writeheader()
            for entry in whitelist_entries:
                writer.writerow({
                    'date': entry['date'],
                    'exchange': entry['exchange'],
                    'network': entry['network'],
                    'address': entry['address']
                })
        
        logger.success(
            f"CEX whitelist exported | File: {output_file} | "
            f"Entries: {len(whitelist_entries)} | "
            f"Date range: {whitelist_entries[0]['date']} to {whitelist_entries[-1]['date']}"
        )


# =============================================================================
# CLI INTERFACE
# =============================================================================

def main():
    """CLI entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Wallet Generator Module 5')
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    # Generate command
    generate_parser = subparsers.add_parser('generate', help='Generate wallets')
    generate_parser.add_argument('--count', type=int, default=90, help='Number of wallets (default: 90)')
    generate_parser.add_argument('--no-save', action='store_true', help='Do not save to database')
    
    # Export whitelist command
    export_parser = subparsers.add_parser('export-whitelist', help='Export CEX whitelist CSV')
    export_parser.add_argument('--output', type=str, default='cex_whitelist.csv', help='Output CSV file')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    try:
        generator = WalletGenerator()
        
        if args.command == 'generate':
            save_to_db = not args.no_save
            wallets = generator.generate_all_wallets(save_to_db=save_to_db)
            
            print(f"\n✅ Generated {len(wallets)} wallets")
            print(f"   Tier A: {sum(1 for w in wallets if w.tier == 'A')}")
            print(f"   Tier B: {sum(1 for w in wallets if w.tier == 'B')}")
            print(f"   Tier C: {sum(1 for w in wallets if w.tier == 'C')}")
            
            if save_to_db:
                print(f"\n💾 Wallets saved to database")
                print(f"   Next: python wallets/generator.py export-whitelist")
        
        elif args.command == 'export-whitelist':
            generator.export_cex_whitelist(output_file=args.output)
            print(f"\n✅ CEX whitelist exported to {args.output}")
            print(f"   Upload to exchanges for address whitelisting")
    
    except Exception as e:
        logger.exception(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
