#!/usr/bin/env python3
"""Wallet Personas Generator — Module 8"""

import os, sys, random, json
from pathlib import Path
import numpy as np
from loguru import logger
from infrastructure.env_loader import load_env

# Load .env file (supports both production and local dev)
load_env()
sys.path.insert(0, str(Path(__file__).parent.parent))
from database.db_manager import DatabaseManager

# Expanded archetypes: 12 instead of 4 (for better anti-Sybil diversity)
ARCHETYPES = [
    'ActiveTrader',     # High frequency, all hours
    'CasualUser',       # Medium frequency, daytime
    'WeekendWarrior',   # Low frequency, weekends only
    'Ghost',            # Very low frequency
    'MorningTrader',    # Active 6-12pm local
    'NightOwl',         # Active 8pm-2am local
    'WeekdayOnly',      # No weekend activity (Mon-Fri)
    'MonthlyActive',    # Bursts once per month
    'BridgeMaxi',       # 50% bridges, low swaps
    'DeFiDegen',        # 60% LP, high stake
    'NFTCollector',     # 30% NFT mints
    'Governance',       # High snapshot/vote activity
]

TIMEZONE_HOURS = {
    'Europe/Amsterdam': list(range(9, 23)),      # NL: 9am-10pm local = 8am-9pm UTC
    'Atlantic/Reykjavik': list(range(10, 24)),   # IS: 10am-11pm local = 10am-11pm UTC
    'America/Toronto': list(range(9, 23)),       # CA: 9am-10pm local = 2pm-3am UTC (next day!)
}

# Archetype-specific hour ranges (for MorningTrader, NightOwl, etc.)
ARCHETYPE_HOURS = {
    'MorningTrader': list(range(6, 13)),   # 6am-12pm
    'NightOwl': list(range(20, 24)) + list(range(0, 3)),  # 8pm-2am
}

# Archetype-specific gas preference profiles (Anti-Sybil: diverse behavior patterns)
GAS_PROFILES = {
    'ActiveTrader': {'slow': 0.20, 'normal': 0.50, 'fast': 0.30},    # Impatient - needs fast confirmation
    'CasualUser': {'slow': 0.50, 'normal': 0.40, 'fast': 0.10},      # Patient - cost-conscious
    'WeekendWarrior': {'slow': 0.45, 'normal': 0.45, 'fast': 0.10},  # Balanced
    'Ghost': {'slow': 0.60, 'normal': 0.35, 'fast': 0.05},           # Very patient - rarely active
    'MorningTrader': {'slow': 0.30, 'normal': 0.50, 'fast': 0.20},   # Moderate speed
    'NightOwl': {'slow': 0.35, 'normal': 0.45, 'fast': 0.20},        # Moderate speed
    'WeekdayOnly': {'slow': 0.40, 'normal': 0.45, 'fast': 0.15},     # Default-like
    'MonthlyActive': {'slow': 0.55, 'normal': 0.35, 'fast': 0.10},   # Patient - sporadic activity
    'BridgeMaxi': {'slow': 0.45, 'normal': 0.40, 'fast': 0.15},      # Bridge-focused, moderate
    'DeFiDegen': {'slow': 0.25, 'normal': 0.45, 'fast': 0.30},       # Impatient - time-sensitive ops
    'NFTCollector': {'slow': 0.40, 'normal': 0.45, 'fast': 0.15},    # Default-like
    'Governance': {'slow': 0.50, 'normal': 0.40, 'fast': 0.10},      # Patient - votes not urgent
}

class PersonaGenerator:
    def __init__(self, db_manager=None):
        self.db = db_manager if db_manager else DatabaseManager()
        logger.info("PersonaGenerator initialized")
    
    def _add_noise(self, weights, noise_pct=0.08):
        noisy = {}
        total = 0
        for key, val in weights.items():
            noise = np.random.normal(0, noise_pct)
            noisy[key] = max(0.01, val * (1 + noise))
            total += noisy[key]
        for key in noisy:
            noisy[key] /= total
        return noisy
    
    def _get_archetype_distribution_balanced(self):
        """
        Get balanced archetype distribution (avoid >15% in any single archetype).
        
        Tracks current distribution and weights selection toward less-used archetypes.
        """
        # Get current archetype counts
        query = "SELECT persona_type, COUNT(*) as count FROM wallet_personas GROUP BY persona_type"
        result = self.db.execute_query(query, fetch='all')
        
        counts = {archetype: 0 for archetype in ARCHETYPES}
        for row in result:
            if row['persona_type'] in counts:
                counts[row['persona_type']] = row['count']
        
        # Weight inversely to count (less used = higher weight)
        weights = [1.0 / (count + 1) for count in counts.values()]
        
        return random.choices(ARCHETYPES, weights=weights, k=1)[0]
    
    def generate_persona(self, wallet_id: int):
        """
        Generate unique persona for wallet based on proxy timezone.
        
        CRITICAL FIX (Migration 033): Timezone is taken from proxy_pool,
        NOT from worker_nodes. This ensures activity matches proxy geography.
        
        Args:
            wallet_id: Wallet database ID
            
        Returns:
            Dict with persona parameters
        """
        # P0 FIX: Get timezone from proxy_pool, not worker_nodes!
        # This ensures CA wallets use America/Toronto timezone
        wallet = self.db.execute_query(
            "SELECT w.id, w.tier, pp.country_code, pp.timezone, pp.utc_offset "
            "FROM wallets w "
            "JOIN proxy_pool pp ON w.proxy_id = pp.id "
            "WHERE w.id = %s",
            (wallet_id,), fetch='one'
        )
        
        if not wallet:
            logger.error(f"Wallet {wallet_id} not found")
            return None
        
        # Balanced archetype selection (anti-clustering)
        archetype = self._get_archetype_distribution_balanced()
        
        # Get timezone from proxy (CRITICAL for CA wallets!)
        timezone_name = wallet.get('timezone', 'Atlantic/Reykjavik')
        utc_offset = wallet.get('utc_offset', 0)
        
        # Archetype-specific hour selection
        if archetype in ARCHETYPE_HOURS:
            # MorningTrader, NightOwl use specific LOCAL hours
            # CRITICAL: Convert LOCAL hours to UTC before storing!
            local_hours = ARCHETYPE_HOURS[archetype]
            
            # Convert local → UTC: UTC = local - offset
            # Example for CA (UTC-5): 9am local = 9 - (-5) = 14 UTC
            available_hours = [(h - utc_offset) % 24 for h in local_hours]
            
            logger.debug(
                f"Archetype {archetype} | Proxy: {wallet['country_code']} | "
                f"Timezone: {timezone_name} (UTC{utc_offset:+d}) | "
                f"Local hours: {local_hours} | UTC hours: {sorted(available_hours)}"
            )
        else:
            # Other archetypes use timezone-based hours
            # TIMEZONE_HOURS contains LOCAL hours, need to convert to UTC
            local_hours = TIMEZONE_HOURS.get(timezone_name, TIMEZONE_HOURS['Atlantic/Reykjavik'])
            
            # Convert local → UTC for storage
            available_hours = [(h - utc_offset) % 24 for h in local_hours]
            
            logger.debug(
                f"Archetype {archetype} | Proxy: {wallet['country_code']} | "
                f"Timezone: {timezone_name} (UTC{utc_offset:+d}) | "
                f"UTC hours: {sorted(available_hours)}"
            )
        
        # Archetype-specific active hour count
        max_hours = len(available_hours)
        if archetype in ('ActiveTrader', 'DeFiDegen'):
            k = min(random.randint(14, 18), max_hours)
        elif archetype in ('CasualUser', 'MorningTrader', 'NightOwl'):
            k = min(random.randint(8, 12), max_hours)
        elif archetype in ('WeekendWarrior', 'WeekdayOnly', 'BridgeMaxi', 'NFTCollector'):
            k = min(random.randint(6, 10), max_hours)
        elif archetype in ('Ghost', 'MonthlyActive', 'Governance'):
            k = min(random.randint(3, 7), max_hours)
        else:
            k = min(random.randint(8, 12), max_hours)  # Default
        
        hours = random.sample(available_hours, k)
        
        # Tier-specific TX per week (adjusted for new archetypes)
        if wallet['tier'] == 'A':
            if archetype == 'MonthlyActive':
                mean, std = 1.5, 0.5  # Low weekly (bursts monthly)
            else:
                mean, std = 4.5, 1.2
        elif wallet['tier'] == 'B':
            if archetype == 'MonthlyActive':
                mean, std = 0.8, 0.3
            else:
                mean, std = 2.5, 0.8
        else:
            if archetype == 'MonthlyActive':
                mean, std = 0.5, 0.2
            else:
                mean, std = 1.0, 0.5
        
        # Archetype-specific TX weights (anti-clustering diversity)
        if archetype == 'BridgeMaxi':
            base = {'swap': 0.20, 'bridge': 0.50, 'liquidity': 0.15, 'stake': 0.10, 'nft': 0.05}
        elif archetype == 'DeFiDegen':
            base = {'swap': 0.15, 'bridge': 0.10, 'liquidity': 0.50, 'stake': 0.20, 'nft': 0.05}
        elif archetype == 'NFTCollector':
            base = {'swap': 0.30, 'bridge': 0.15, 'liquidity': 0.10, 'stake': 0.15, 'nft': 0.30}
        elif archetype == 'Governance':
            base = {'swap': 0.30, 'bridge': 0.20, 'liquidity': 0.15, 'stake': 0.30, 'nft': 0.05}
        else:
            # Default for ActiveTrader, CasualUser, WeekendWarrior, Ghost, etc.
            base = {'swap': 0.40, 'bridge': 0.25, 'liquidity': 0.20, 'stake': 0.10, 'nft': 0.05}
        
        weights = self._add_noise(base)
        
        # Slippage (Gaussian distribution instead of uniform)
        if wallet['tier'] == 'A':
            # mean=0.465, std=0.07 → covers 0.33-0.60 range (±1.96σ)
            slippage = round(np.random.normal(0.465, 0.07), 2)
            slippage = max(0.33, min(0.60, slippage))
        elif wallet['tier'] == 'B':
            # mean=0.675, std=0.09 → covers 0.50-0.85 range
            slippage = round(np.random.normal(0.675, 0.09), 2)
            slippage = max(0.50, min(0.85, slippage))
        else:
            # mean=0.90, std=0.10 → covers 0.70-1.10 range
            slippage = round(np.random.normal(0.90, 0.10), 2)
            slippage = max(0.70, min(1.10, slippage))
        
        # Gas - use archetype-specific profile with increased noise for diversity
        base_weights = GAS_PROFILES.get(archetype, {'slow': 0.40, 'normal': 0.45, 'fast': 0.15})
        gas_weights = self._add_noise(base_weights, noise_pct=0.12)  # Increased 6% → 12%
        gas_choice = random.choices(['slow', 'normal', 'fast'], 
                                   weights=[gas_weights['slow'], gas_weights['normal'], gas_weights['fast']])[0]
        
        # Skip week probability (archetype-specific, Gaussian distribution)
        if archetype in ('ActiveTrader', 'DeFiDegen'):
            # Very low skip probability
            skip = round(np.random.normal(0.025, 0.015), 2)
            skip = max(0.00, min(0.05, skip))
        elif archetype in ('CasualUser', 'MorningTrader', 'NightOwl', 'BridgeMaxi'):
            # Medium-low skip probability
            skip = round(np.random.normal(0.10, 0.025), 2)
            skip = max(0.05, min(0.15, skip))
        elif archetype in ('WeekendWarrior', 'WeekdayOnly', 'NFTCollector'):
            # Medium skip probability
            skip = round(np.random.normal(0.15, 0.025), 2)
            skip = max(0.10, min(0.20, skip))
        elif archetype in ('Ghost', 'Governance'):
            # Medium-high skip probability
            skip = round(np.random.normal(0.25, 0.025), 2)
            skip = max(0.20, min(0.30, skip))
        elif archetype == 'MonthlyActive':
            # Very high skip probability (active only 1 week per month)
            skip = round(np.random.normal(0.75, 0.05), 2)
            skip = max(0.65, min(0.85, skip))
        else:
            # Default
            skip = round(np.random.normal(0.15, 0.025), 2)
            skip = max(0.10, min(0.20, skip))
        
        return {
            'wallet_id': wallet_id, 'persona_type': archetype, 'preferred_hours': hours,
            'tx_per_week_mean': mean, 'tx_per_week_stddev': std, 'skip_week_probability': skip,
            'tx_weight_swap': round(weights['swap'], 2), 'tx_weight_bridge': round(weights['bridge'], 2),
            'tx_weight_liquidity': round(weights['liquidity'], 2), 'tx_weight_stake': round(weights['stake'], 2),
            'tx_weight_nft': round(weights['nft'], 2), 'slippage_tolerance': slippage,
            'gas_preference': gas_choice, 'gas_preference_weights': {k: round(v, 4) for k, v in gas_weights.items()}  # ← Return dict, NOT json.dumps()
        }
    
    def save_persona(self, p):
        from psycopg2 import extras  # Import для Json()
        
        query = """INSERT INTO wallet_personas (wallet_id, persona_type, preferred_hours, tx_per_week_mean,
                    tx_per_week_stddev, skip_week_probability, tx_weight_swap, tx_weight_bridge, tx_weight_liquidity,
                    tx_weight_stake, tx_weight_nft, slippage_tolerance, gas_preference, gas_preference_weights)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING id"""
        result = self.db.execute_query(query, (p['wallet_id'], p['persona_type'], p['preferred_hours'],
            p['tx_per_week_mean'], p['tx_per_week_stddev'], p['skip_week_probability'],
            p['tx_weight_swap'], p['tx_weight_bridge'], p['tx_weight_liquidity'],
            p['tx_weight_stake'], p['tx_weight_nft'], p['slippage_tolerance'],
            p['gas_preference'], extras.Json(p['gas_preference_weights'])), fetch='one')  # ← extras.Json() для dict
        logger.info(f"Persona saved | Wallet: {p['wallet_id']} | Type: {p['persona_type']}")
        return result['id']
    
    def generate_all(self):
        logger.info("Generating personas...")
        wallets = self.db.execute_query("SELECT id FROM wallets ORDER BY id", fetch='all')
        count = 0
        for w in wallets:
            persona = self.generate_persona(w['id'])
            self.save_persona(persona)
            count += 1
            if count % 10 == 0:
                logger.info(f"Progress: {count}/90")
        logger.success(f"Personas: {count}")
        return count

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['generate'])
    args = parser.parse_args()
    try:
        gen = PersonaGenerator()
        if args.command == 'generate':
            count = gen.generate_all()
            print(f"\n✅ {count} personas")
    except Exception as e:
        logger.exception(f"Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
