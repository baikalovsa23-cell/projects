"""
Withdrawal Strategies — Tier-Specific Configuration
=====================================================

Defines withdrawal strategies for each tier with anti-Sybil protection.

Features:
- Tier A: Conservative (4 steps, 30% HODL long-term)
- Tier B: Moderate (3 steps, balanced)
- Tier C: Aggressive (2 steps, quick profit-taking)
- Gaussian distribution for temporal isolation

Usage:
    from withdrawal.strategies import TierStrategy
    
    strategy = TierStrategy.get_strategy('A')
    print(f"Steps: {strategy.total_steps}")
    print(f"Percentages: {strategy.percentages}")

Author: Airdrop Farming System v4.0
Created: 2026-02-26
"""

from dataclasses import dataclass
from typing import List, Dict
import numpy as np


@dataclass
class TierStrategy:
    """
    Tier-specific withdrawal strategy configuration.
    
    Attributes:
        tier: 'A', 'B', or 'C'
        total_steps: Number of withdrawal steps
        percentages: List of percentages for each step
        delay_mean: Mean days between steps (Gaussian)
        delay_std: Standard deviation for delays (Gaussian)
        delay_min: Minimum days between steps
        delay_max: Maximum days between steps
    """
    tier: str
    total_steps: int
    percentages: List[float]
    delay_mean: int
    delay_std: float
    delay_min: int
    delay_max: int

    @staticmethod
    def get_strategy(tier: str) -> 'TierStrategy':
        """
        Get strategy for a given tier.
        
        Args:
            tier: 'A', 'B', or 'C'
        
        Returns:
            TierStrategy instance
        
        Raises:
            ValueError: If tier is invalid
        
        Example:
            >>> strategy = TierStrategy.get_strategy('A')
            >>> strategy.total_steps
            4
            >>> strategy.percentages
            [15.0, 25.0, 30.0, 30.0]
        """
        strategies = {
            'A': TierStrategy(
                tier='A',
                total_steps=4,
                percentages=[15.0, 25.0, 30.0, 30.0],  # 30% HODL long-term
                delay_mean=45,  # 45 days between steps
                delay_std=7.5,
                delay_min=30,
                delay_max=60
            ),
            'B': TierStrategy(
                tier='B',
                total_steps=3,
                percentages=[20.0, 40.0, 40.0],
                delay_mean=33,  # 33 days
                delay_std=6.0,
                delay_min=21,
                delay_max=45
            ),
            'C': TierStrategy(
                tier='C',
                total_steps=2,
                percentages=[50.0, 50.0],
                delay_mean=22,  # 22 days
                delay_std=4.0,
                delay_min=14,
                delay_max=30
            )
        }
        
        if tier not in strategies:
            raise ValueError(f"Invalid tier: {tier}. Must be 'A', 'B', or 'C'")
        
        return strategies[tier]

    def get_next_delay_days(self, step_number: int) -> float:
        """
        Calculate next delay in days using Gaussian distribution.
        
        Args:
            step_number: Current step number (1-indexed)
        
        Returns:
            Delay in days (float, can be fractional)
        
        Anti-Sybil:
            - Uses Gaussian (normal) distribution, NOT uniform
            - First step has shorter delay (1-7 days)
            - Subsequent steps use tier-specific delays
        """
        if step_number == 1:
            # First step: 1-7 days delay (mean=4, std=1.5)
            delay = np.random.normal(4.0, 1.5)
            delay = max(1, min(7, delay))
        else:
            # Subsequent steps: tier-specific delays
            delay = np.random.normal(self.delay_mean, self.delay_std)
            delay = max(self.delay_min, min(self.delay_max, delay))
        
        return delay

    def to_dict(self) -> Dict:
        """
        Convert strategy to dictionary.
        
        Returns:
            Dict representation of the strategy
        """
        return {
            'tier': self.tier,
            'total_steps': self.total_steps,
            'percentages': self.percentages,
            'delay_mean': self.delay_mean,
            'delay_std': self.delay_std,
            'delay_min': self.delay_min,
            'delay_max': self.delay_max
        }


def get_all_strategies() -> Dict[str, TierStrategy]:
    """
    Get all tier strategies.
    
    Returns:
        Dict mapping tier letter to TierStrategy
    
    Example:
        >>> strategies = get_all_strategies()
        >>> for tier, strategy in strategies.items():
        ...     print(f"Tier {tier}: {strategy.total_steps} steps")
        Tier A: 4 steps
        Tier B: 3 steps
        Tier C: 2 steps
    """
    return {
        'A': TierStrategy.get_strategy('A'),
        'B': TierStrategy.get_strategy('B'),
        'C': TierStrategy.get_strategy('C')
    }


def validate_strategy_percentages(percentages: List[float]) -> bool:
    """
    Validate that percentages sum to 100%.
    
    Args:
        percentages: List of percentage values
    
    Returns:
        True if valid, False otherwise
    """
    total = sum(percentages)
    return abs(total - 100.0) < 0.01  # Allow small floating point error


# =============================================================================
# TESTS
# =============================================================================

if __name__ == '__main__':
    import pytest
    
    def test_tier_a_strategy():
        """Test Tier A strategy configuration."""
        strategy = TierStrategy.get_strategy('A')
        assert strategy.tier == 'A'
        assert strategy.total_steps == 4
        assert strategy.percentages == [15.0, 25.0, 30.0, 30.0]
        assert validate_strategy_percentages(strategy.percentages)
        assert strategy.delay_mean == 45
        assert strategy.delay_min == 30
        assert strategy.delay_max == 60
        print("✅ Tier A strategy test passed")
    
    def test_tier_b_strategy():
        """Test Tier B strategy configuration."""
        strategy = TierStrategy.get_strategy('B')
        assert strategy.tier == 'B'
        assert strategy.total_steps == 3
        assert strategy.percentages == [20.0, 40.0, 40.0]
        assert validate_strategy_percentages(strategy.percentages)
        assert strategy.delay_mean == 33
        assert strategy.delay_min == 21
        assert strategy.delay_max == 45
        print("✅ Tier B strategy test passed")
    
    def test_tier_c_strategy():
        """Test Tier C strategy configuration."""
        strategy = TierStrategy.get_strategy('C')
        assert strategy.tier == 'C'
        assert strategy.total_steps == 2
        assert strategy.percentages == [50.0, 50.0]
        assert validate_strategy_percentages(strategy.percentages)
        assert strategy.delay_mean == 22
        assert strategy.delay_min == 14
        assert strategy.delay_max == 30
        print("✅ Tier C strategy test passed")
    
    def test_invalid_tier():
        """Test that invalid tier raises ValueError."""
        with pytest.raises(ValueError):
            TierStrategy.get_strategy('X')
        print("✅ Invalid tier test passed")
    
    def test_gaussian_delay_distribution():
        """Test that delays follow Gaussian distribution."""
        strategy = TierStrategy.get_strategy('A')
        
        # Generate 1000 samples
        delays = [strategy.get_next_delay_days(2) for _ in range(1000)]
        
        # Check that mean is close to expected
        mean_delay = sum(delays) / len(delays)
        assert 40 <= mean_delay <= 50, f"Mean delay {mean_delay} not in expected range"
        
        # Check that most delays are within min/max
        in_range = sum(1 for d in delays if strategy.delay_min <= d <= strategy.delay_max)
        assert in_range >= 900, f"Only {in_range}/1000 delays in valid range"
        
        print(f"✅ Gaussian delay test passed (mean={mean_delay:.1f}, in_range={in_range}/1000)")
    
    def test_first_step_delay():
        """Test that first step has shorter delay."""
        strategy = TierStrategy.get_strategy('A')
        
        first_delays = [strategy.get_next_delay_days(1) for _ in range(100)]
        mean_first = sum(first_delays) / len(first_delays)
        
        # First step should be 1-7 days
        assert 1 <= mean_first <= 7, f"First step mean {mean_first} not in 1-7 range"
        
        print(f"✅ First step delay test passed (mean={mean_first:.1f})")
    
    # Run tests
    print("Running withdrawal strategies tests...\n")
    test_tier_a_strategy()
    test_tier_b_strategy()
    test_tier_c_strategy()
    test_invalid_tier()
    test_gaussian_delay_distribution()
    test_first_step_delay()
    print("\n🎉 All tests passed!")