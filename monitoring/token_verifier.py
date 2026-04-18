"""
Module 18: Token Verifier — CoinGecko Integration and Scam Detection

Verifies detected tokens against CoinGecko API and applies heuristics to detect
scam tokens. Used by Module 17 (Airdrop Detector) to filter false positives.

Usage:
    verifier = TokenVerifier()
    result = await verifier.verify_token(
        contract_address="0x912CE59144191C1204E64559FE8253a0e49E6548",
        chain="arbitrum",
        symbol="ARB"
    )

Integration:
    - Module 17: Called when new token detected on wallet
    - CoinGecko API: Free tier (10k calls/month)
    - Telegram: Alerts only for high-confidence airdrops (>0.6)
"""

import os
import re
from dataclasses import dataclass
from typing import Dict, List, Optional, Any

import aiohttp
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential

from database.db_manager import get_db_manager


# ============================================================================
# DATACLASS DEFINITIONS
# ============================================================================

@dataclass
class VerificationResult:
    """
    Result of token verification.
    """
    contract_address: str
    symbol: str
    chain: str
    confidence_score: float  # 0.0-1.0
    is_on_coingecko: bool
    coin_name: Optional[str]
    market_cap: Optional[float]
    price: Optional[float]
    is_scam_heuristic: bool
    scam_reasons: List[str]
    
    @property
    def is_verified_airdrop(self) -> bool:
        """Token passes verification threshold."""
        return self.confidence_score > 0.6 and not self.is_scam_heuristic


# ============================================================================
# TOKEN VERIFIER CLASS
# ============================================================================

class TokenVerifier:
    """
    Verifies tokens using CoinGecko API and heuristic analysis.
    
    Confidence scoring:
    - CoinGecko listed + high market cap = high confidence
    - CoinGecko listed + low market cap = medium confidence
    - Not on CoinGecko + scam heuristics = low confidence
    - Not on CoinGecko + no red flags = medium confidence
    """
    
    # CoinGecko API configuration
    COINGECKO_BASE_URL = "https://api.coingecko.com/api/v3"
    API_KEY = os.getenv('COINGECKO_API_KEY', '')
    
    # Scam detection heuristics
    SCAM_PATTERNS = [
        # Generic scam keywords in token name
        (r'\b(airdrop|free|claim|reward)\b.*\b(token|coin|eth|btc)\b', 'Suspicious airdrop keyword'),
        (r'\b(1000x|100x|10x|pump|moon)\b', 'Pump and dump keyword'),
        (r'\b(guaranteed|profit|dividend|staking)\b.*\b(return|yield)\b', 'Guaranteed return scam'),
        
        # Suspicious name patterns
        (r'^[A-Z]{20,}$', 'All caps suspicious name'),
        (r'^(fake|scam|rug|meme|shit)\w*$', 'Obvious scam name'),
        
        # Very short or very long names
        (r'^.{30,}$', 'Suspiciously long name'),
    ]
    
    # Known legitimate token patterns (reduce false positives)
    LEGITIMATE_PATTERNS = [
        r'\b(usdc|usdt|dai|busd|usdp)\b',  # Stablecoins
        r'\b(eth|weth|btc|wbtc)\b',  # Native/wrapped
        r'\b(arb|op|matic|avax|bnb)\b',  # Major L2/native tokens
        r'\b(aave|comp|uni|sushi|crv|maker)\b',  # DeFi blue chips
    ]
    
    def __init__(self, db_manager=None):
        """
        Initialize TokenVerifier.
        
        Args:
            db_manager: DatabaseManager instance (optional)
        """
        self.db = db_manager or get_db_manager()
        self.session: Optional[aiohttp.ClientSession] = None
        
        logger.info("TokenVerifier initialized")
    
    async def verify_token(
        self,
        contract_address: str,
        chain: str,
        symbol: str
    ) -> VerificationResult:
        """
        Verify a token using CoinGecko and heuristics.
        
        Args:
            contract_address: Token contract address (0x...)
            chain: Chain identifier ('arbitrum', 'base', etc.)
            symbol: Token symbol ('ARB', 'USDC', etc.)
            
        Returns:
            VerificationResult with confidence score and scam detection
        """
        logger.debug(f"Verifying token: {symbol} ({contract_address}) on {chain}")
        
        # Step 1: Check CoinGecko
        coin_data = await self._check_coingecko(contract_address, chain, symbol)
        
        # Step 2: Run scam heuristics
        scam_result = self._run_scam_heuristics(symbol, contract_address)
        
        # Step 3: Calculate confidence score
        confidence = self._calculate_confidence(
            coin_data=coin_data,
            is_scam=scam_result['is_scam'],
            scam_reasons=scam_result['reasons']
        )
        
        return VerificationResult(
            contract_address=contract_address,
            symbol=symbol,
            chain=chain,
            confidence_score=confidence,
            is_on_coingecko=coin_data is not None,
            coin_name=coin_data.get('name') if coin_data else None,
            market_cap=coin_data.get('market_cap') if coin_data else None,
            price=coin_data.get('price') if coin_data else None,
            is_scam_heuristic=scam_result['is_scam'],
            scam_reasons=scam_result['reasons']
        )
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=8))
    async def _check_coingecko(
        self,
        contract_address: str,
        chain: str,
        symbol: str
    ) -> Optional[Dict[str, Any]]:
        """
        Check if token is listed on CoinGecko.
        
        Args:
            contract_address: Token contract address
            chain: Chain identifier
            symbol: Token symbol
            
        Returns:
            Coin data dict if found, None if not listed
        """
        # Map chain to CoinGecko ID
        chain_id_map = {
            'arbitrum': 'arbitrum',
            'base': 'base',
            'optimism': 'optimism',
            'polygon': 'matic-network',
            'bnbchain': 'binancecoin',
            'ink': None,  # Not on CoinGecko
            'megaeth': None,  # Not on CoinGecko
        }
        
        coingecko_chain = chain_id_map.get(chain)
        if not coingecko_chain:
            return None
        
        # Build API URL
        endpoint = f"{self.COINGECKO_BASE_URL}/coins/{coingecko_chain}/contract/{contract_address}"
        
        params = {}
        if self.API_KEY:
            params['x_cg_demo_api_key'] = self.API_KEY
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(endpoint, params=params, timeout=10) as response:
                    if response.status == 404:
                        return None
                    if response.status == 429:
                        logger.warning("CoinGecko rate limit, using cached/default data")
                        return None
                    
                    response.raise_for_status()
                    data = await response.json()
            
            return {
                'name': data.get('name'),
                'symbol': data.get('symbol'),
                'market_cap': data.get('market_data', {}).get('market_cap', {}).get('usd'),
                'price': data.get('market_data', {}).get('current_price', {}).get('usd'),
            }
            
        except Exception as e:
            logger.debug(f"CoinGecko lookup failed for {symbol}: {e}")
            return None
    
    def _run_scam_heuristics(
        self,
        symbol: str,
        contract_address: str
    ) -> Dict[str, Any]:
        """
        Run heuristic checks to detect scam tokens.
        
        Args:
            symbol: Token symbol
            contract_address: Token contract address
            
        Returns:
            Dict with 'is_scam' bool and 'reasons' list
        """
        reasons = []
        
        # Check against scam patterns
        for pattern, reason in self.SCAM_PATTERNS:
            if re.search(pattern, f"{symbol} {contract_address}", re.IGNORECASE):
                reasons.append(reason)
        
        # Check if appears legitimate
        is_legitimate = any(
            re.search(pattern, symbol, re.IGNORECASE)
            for pattern in self.LEGITIMATE_PATTERNS
        )
        
        # Additional checks
        # Very short symbol (often scam)
        if len(symbol) <= 2:
            reasons.append("Very short symbol (potential spam)")
        
        # Suspicious address (very new, no transactions)
        # Note: This would require on-chain analysis in production
        
        is_scam = len(reasons) >= 2 and not is_legitimate
        
        return {
            'is_scam': is_scam,
            'reasons': reasons
        }
    
    def _calculate_confidence(
        self,
        coin_data: Optional[Dict],
        is_scam: bool,
        scam_reasons: List[str]
    ) -> float:
        """
        Calculate confidence score based on verification results.
        
        Args:
            coin_data: CoinGecko data (or None)
            is_scam: Whether scam heuristics triggered
            scam_reasons: List of scam detection reasons
            
        Returns:
            Confidence score 0.0-1.0
        """
        score = 0.5  # Base score
        
        # CoinGecko verification
        if coin_data:
            score += 0.3  # Listed on CoinGecko
            
            # High market cap = higher confidence
            market_cap = coin_data.get('market_cap', 0)
            if market_cap and market_cap > 1_000_000_000:  # > $1B
                score += 0.1
            elif market_cap and market_cap > 100_000_000:  # > $100M
                score += 0.05
        else:
            score -= 0.1  # Not on CoinGecko
        
        # Scam detection
        if is_scam:
            score -= 0.3 * len(scam_reasons)
        
        # Cap at 0.0-1.0
        return max(0.0, min(1.0, score))
    
    async def verify_batch(
        self,
        tokens: List[Dict[str, str]]
    ) -> List[VerificationResult]:
        """
        Verify multiple tokens at once.
        
        Args:
            tokens: List of dicts with 'contract_address', 'chain', 'symbol'
            
        Returns:
            List of VerificationResult
        """
        results = []
        
        for token in tokens:
            result = await self.verify_token(
                contract_address=token['contract_address'],
                chain=token['chain'],
                symbol=token['symbol']
            )
            results.append(result)
            
            # Rate limiting (CoinGecko free tier: 10-50 calls/min)
            await asyncio.sleep(1.5)
        
        return results


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

async def verify_token_simple(
    contract_address: str,
    chain: str,
    symbol: str
) -> VerificationResult:
    """
    Simple wrapper for token verification (for quick CLI usage).
    
    Args:
        contract_address: Token contract address
        chain: Chain identifier
        symbol: Token symbol
        
    Returns:
        VerificationResult
    """
    verifier = TokenVerifier()
    return await verifier.verify_token(contract_address, chain, symbol)


# ============================================================================
# CLI INTERFACE
# ============================================================================

async def main():
    """CLI interface for token verification."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Verify token via CoinGecko")
    parser.add_argument('--address', required=True, help='Token contract address')
    parser.add_argument('--chain', required=True, help='Chain (arbitrum, base, etc.)')
    parser.add_argument('--symbol', required=True, help='Token symbol')
    
    args = parser.parse_args()
    
    result = await verify_token_simple(args.address, args.chain, args.symbol)
    
    print(f"\n{'='*60}")
    print(f"Token Verification: {result.symbol}")
    print(f"{'='*60}")
    print(f"Contract: {result.contract_address}")
    print(f"Chain: {result.chain}")
    print(f"CoinGecko: {'✅ Listed' if result.is_on_coingecko else '❌ Not Listed'}")
    print(f"Confidence: {result.confidence_score:.2f}")
    print(f"Scam Heuristic: {'⚠️ YES' if result.is_scam_heuristic else '✅ NO'}")
    
    if result.scam_reasons:
        print(f"Scam Reasons:")
        for reason in result.scam_reasons:
            print(f"  - {reason}")
    
    if result.is_verified_airdrop:
        print(f"\n✅ Verified Airdrop (confidence > 0.6)")
    else:
        print(f"\n❌ Not Verified (confidence <= 0.6)")
    
    print(f"{'='*60}\n")


if __name__ == '__main__':
    import asyncio
    asyncio.run(main())
