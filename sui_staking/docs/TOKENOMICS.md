# Staking Tokenomics

A comprehensive guide to the mathematical model and economic design of the staking system.

## Table of Contents

1. [Overview](#overview)
2. [MasterChef Reward Model](#masterchef-reward-model)
3. [Mathematical Formulas](#mathematical-formulas)
4. [Precision & Fixed-Point Math](#precision--fixed-point-math)
5. [Reward Distribution Examples](#reward-distribution-examples)
6. [Fee Structure](#fee-structure)
7. [APR/APY Calculations](#aprapy-calculations)
8. [Edge Cases & Limitations](#edge-cases--limitations)
9. [Recommended Configurations](#recommended-configurations)

---

## Overview

The staking system uses a **MasterChef-style accumulated reward per share** model, originally pioneered by SushiSwap. This model enables:

- **Gas-efficient** reward distribution (O(1) per claim)
- **Fair** proportional rewards based on stake weight
- **Real-time** reward accrual without per-block transactions
- **Flexible** support for any token pair

### Key Invariants

1. Total rewards distributed = Σ(reward_rate × time_elapsed)
2. User rewards ∝ (user_stake / total_stake) × time_staked
3. No tokens are created or destroyed (conservation)

---

## MasterChef Reward Model

### Core Concept

Instead of tracking each user's rewards individually, we track a single global value:

```
accumulated_reward_per_share (acc)
```

This represents "how many reward tokens each staked token has earned since the pool started."

### How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                         POOL STATE                               │
│                                                                  │
│   acc_reward_per_share = 2.5e18  (2.5 rewards per staked token)│
│   total_staked = 1,000,000       (1M tokens staked)             │
│   last_update_time = T1                                          │
└─────────────────────────────────────────────────────────────────┘
                              │
           ┌──────────────────┼──────────────────┐
           ▼                  ▼                  ▼
    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
    │  POSITION A │    │  POSITION B │    │  POSITION C │
    │             │    │             │    │             │
    │ staked: 400K│    │ staked: 350K│    │ staked: 250K│
    │ debt: 1e18  │    │ debt: 1.5e18│    │ debt: 2e18  │
    │ (joined at  │    │ (joined at  │    │ (joined at  │
    │  acc=1e18)  │    │  acc=1.5e18)│    │  acc=2e18)  │
    └─────────────┘    └─────────────┘    └─────────────┘

    Pending A:         Pending B:         Pending C:
    400K×(2.5-1)       350K×(2.5-1.5)     250K×(2.5-2)
    = 600K rewards     = 350K rewards     = 125K rewards
```

### State Updates

**When rewards are distributed:**
```
acc += (new_rewards × PRECISION) / total_staked
```

**When user stakes:**
```
position.reward_debt = staked_amount × acc / PRECISION
```

**When user claims:**
```
pending = (staked × acc / PRECISION) - reward_debt
reward_debt = staked × acc / PRECISION  // Reset debt
```

---

## Mathematical Formulas

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| PRECISION | 10^18 | Fixed-point scaling factor |
| BPS_DENOMINATOR | 10,000 | Basis points (100% = 10000) |
| MS_PER_DAY | 86,400,000 | Milliseconds per day |

### Reward Rate

```
reward_rate = total_rewards / duration_ms
```

**Example:**
- Total rewards: 100,000,000,000 (100B tokens)
- Duration: 604,800,000 ms (7 days)
- Rate: 100B / 604.8M = 165 tokens/ms

### Accumulated Reward Per Share

```
acc_new = acc_old + (rewards × PRECISION) / total_staked
```

**Example:**
- Current acc: 0
- New rewards: 1,000,000
- Total staked: 500,000
- New acc: 0 + (1M × 10^18) / 500K = 2 × 10^18

This means each staked token has earned 2 reward tokens.

### Pending Rewards

```
pending = (staked × acc / PRECISION) - reward_debt
```

**Example:**
- Staked: 100,000
- Current acc: 2.5 × 10^18
- Reward debt: 1 × 10^18 (joined when acc was 1)
- Pending: (100K × 2.5) - (100K × 1) = 150,000 rewards

### Reward Debt

```
reward_debt = staked × acc / PRECISION
```

This represents "rewards already accounted for" when the user staked.

### Early Unstake Fee

```
if (current_time < stake_time + min_duration):
    fee = amount × fee_bps / 10000
else:
    fee = 0
```

---

## Precision & Fixed-Point Math

### Why 10^18?

Using PRECISION = 10^18 allows:
- **18 decimal places** of precision
- Support for tokens with any decimal configuration (6, 9, 18)
- Minimal rounding errors across operations

### Integer Division Effects

All calculations use integer division, which truncates:

```
5 / 3 = 1  (not 1.67)
```

**Precision Loss Scenarios:**

| Scenario | Loss | Mitigation |
|----------|------|------------|
| Small rewards / large stake | High | Use larger reward amounts |
| Short duration / low rate | High | Use longer durations |
| Many small distributions | Cumulative | Batch updates |

### Recommended Minimums

| Parameter | Minimum | Reason |
|-----------|---------|--------|
| Total rewards | 10^12 | Meaningful rate over week |
| Stake amount | 1,000 | Dust protection |
| Duration | 7 days | Reasonable rate precision |

---

## Reward Distribution Examples

### Example 1: Single Staker

```
Pool Setup:
- Total rewards: 1,000,000
- Duration: 7 days
- Rate: 1,000,000 / 604,800,000 = 1.65 tokens/ms

Day 0: Alice stakes 100,000 tokens
- acc = 0
- Alice.debt = 0

Day 7: Alice claims
- Time elapsed: 604,800,000 ms
- New rewards: 1.65 × 604,800,000 ≈ 999,720 (some loss)
- acc = 999,720 × 10^18 / 100,000 = 9.9972 × 10^18
- Alice pending = 100,000 × 9.9972 = 999,720 tokens
```

### Example 2: Two Equal Stakers

```
Pool: 1,000,000 rewards over 7 days

Day 0: Alice stakes 50,000
Day 0: Bob stakes 50,000 (same time)
- total_staked = 100,000

Day 7: Both claim
- Total rewards distributed: ~1,000,000
- acc = 10^19 (10 rewards per token)
- Alice pending = 50,000 × 10 = 500,000
- Bob pending = 50,000 × 10 = 500,000

Result: 50/50 split ✓
```

### Example 3: Late Joiner

```
Pool: 1,000,000 rewards over 10 days (100,000/day)

Day 0: Alice stakes 100,000
- acc = 0
- Alice.debt = 0

Day 5: Bob stakes 100,000
- Rewards so far: 500,000
- acc = 500,000 × 10^18 / 100,000 = 5 × 10^18
- Bob.debt = 100,000 × 5 × 10^18 / 10^18 = 500,000

Day 10: Both claim
- Total rewards: 1,000,000
- acc at day 5: 5 × 10^18
- Rewards day 5-10: 500,000 (split between 200K staked)
- acc delta: 500,000 × 10^18 / 200,000 = 2.5 × 10^18
- Final acc: 7.5 × 10^18

Alice: 100,000 × 7.5 - 0 = 750,000 rewards (75%)
Bob: 100,000 × 7.5 - 500,000 = 250,000 rewards (25%)

Breakdown:
- Day 0-5: Alice gets 100% of 500,000 = 500,000
- Day 5-10: Each gets 50% of 500,000 = 250,000 each
- Total: Alice 750K, Bob 250K ✓
```

### Example 4: Proportional Stakes

```
Pool: 1,000,000 rewards over 7 days

Day 0:
- Alice stakes 750,000 (75%)
- Bob stakes 250,000 (25%)
- total_staked = 1,000,000

Day 7:
- acc = 1,000,000 × 10^18 / 1,000,000 = 10^18 (1 per token)
- Alice: 750,000 × 1 = 750,000 rewards (75%)
- Bob: 250,000 × 1 = 250,000 rewards (25%)

Result: Proportional distribution ✓
```

---

## Fee Structure

The staking system supports multiple configurable fee types to provide flexible monetization options for pool creators.

### Fee Types Summary

| Fee Type | Applied When | Max | Default |
|----------|--------------|-----|---------|
| Platform Setup | Pool creation | - | 1 SUI |
| Platform Fee | On rewards | 5% (500 bps) | 1% |
| Stake Fee | On deposit | 5% (500 bps) | 0% |
| Unstake Fee | On withdrawal | 5% (500 bps) | 0% |
| Early Unstake Fee | Early withdrawal | 10% (1000 bps) | 0% |

### Platform Setup Fee

```
Default: 1 SUI per pool creation
Max platform fee: 5% (500 bps) on rewards
```

### Stake Fee (Deposit Fee)

Applied when users deposit tokens into the pool:

```
stake_fee = deposit_amount × stake_fee_bps / 10000
net_staked = deposit_amount - stake_fee
Max: 5% (500 bps)
```

**Example:**
- Deposit: 100,000 tokens
- Stake fee: 2% (200 bps)

```
Fee = 100,000 × 200 / 10000 = 2,000 tokens
Net staked = 98,000 tokens
```

### Unstake Fee (Withdrawal Fee)

Applied on ALL withdrawals (both full and partial):

```
unstake_fee = withdraw_amount × unstake_fee_bps / 10000
Max: 5% (500 bps)
```

**Example:**
- Withdraw: 100,000 tokens
- Unstake fee: 3% (300 bps)

```
Fee = 100,000 × 300 / 10000 = 3,000 tokens
Net received = 97,000 tokens
```

### Early Unstake Fee

Applied only when unstaking before the minimum stake duration:

```
Condition: unstake_time < stake_time + min_stake_duration
Fee: amount × early_fee_bps / 10000
Max: 10% (1000 bps)
```

**Example:**
- Staked: 100,000 tokens
- Min duration: 7 days
- Early fee: 5% (500 bps)
- Unstake after 3 days

```
Fee = 100,000 × 500 / 10000 = 5,000 tokens
Net received = 95,000 tokens
```

### Combined Fees on Early Withdrawal

When unstaking early, **both** early fee and unstake fee apply:

```
total_fee = early_unstake_fee + unstake_fee
```

**Example:**
- Staked: 100,000 tokens
- Early fee: 5% (500 bps)
- Unstake fee: 2% (200 bps)
- Unstaking before min duration

```
Early fee = 100,000 × 500 / 10000 = 5,000 tokens
Unstake fee = 100,000 × 200 / 10000 = 2,000 tokens
Total fee = 7,000 tokens (7%)
Net received = 93,000 tokens
```

### Fee Flow Diagram

```
┌─────────────────┐                     ┌─────────────────┐
│   User Stake    │                     │  User Unstake   │
│   (deposit)     │                     │  (withdrawal)   │
└────────┬────────┘                     └────────┬────────┘
         │                                       │
         │ stake_fee                             │ unstake_fee + early_fee
         ▼                                       ▼
┌─────────────────────────────────────────────────────────┐
│                    collected_fees                        │
│                  (Pool's fee balance)                    │
└────────────────────────────┬────────────────────────────┘
                             │
                             │ Admin withdrawable
                             ▼
                    ┌─────────────────┐
                    │   Pool Admin    │
                    │   (protocol)    │
                    └─────────────────┘
```

### Protocol Revenue Model

Pool creators can use these fees to fund protocol operations:

1. **Stake Fee**: Revenue on user deposits
2. **Unstake Fee**: Revenue on user withdrawals
3. **Early Unstake Fee**: Penalty for early exit (discourages short-term speculation)

**Recommended configurations for protocol revenue:**

| Pool Type | Stake Fee | Unstake Fee | Early Fee |
|-----------|-----------|-------------|-----------|
| Community | 0% | 0% | 0-5% |
| Premium | 1% | 1% | 5% |
| High-yield | 2% | 2% | 10% |

---

## APR/APY Calculations

### APR (Annual Percentage Rate)

```
APR = (yearly_rewards / total_staked) × 100%
```

**Example:**
- Total staked: 1,000,000 tokens
- Yearly rewards: 100,000 tokens
- APR: 100,000 / 1,000,000 = 10%

### APY (Annual Percentage Yield)

For simple staking (no compounding):
```
APY = APR
```

For auto-compounding:
```
APY = (1 + APR/n)^n - 1
```

Where n = compounding frequency per year.

### Dynamic APR

APR changes with total staked:

| Total Staked | Yearly Rewards | APR |
|--------------|----------------|-----|
| 100,000 | 100,000 | 100% |
| 500,000 | 100,000 | 20% |
| 1,000,000 | 100,000 | 10% |
| 10,000,000 | 100,000 | 1% |

### APR Formula by Duration

```
APR = (total_rewards / total_staked) × (365 days / duration_days) × 100%
```

**Example: 7-day pool**
- Rewards: 10,000 tokens
- Staked: 100,000 tokens
- APR: (10,000 / 100,000) × (365 / 7) = 5.21 × 100% = 521%

---

## Edge Cases & Limitations

### Precision Loss

| Scenario | Issue | Solution |
|----------|-------|----------|
| Tiny rewards | Rate truncates to 0 | Use larger reward amounts |
| Whale joins | Dilutes existing acc | Expected behavior |
| Dust stakes | Negligible rewards | MIN_STAKE_AMOUNT = 1000 |

### Minimum Effective Configuration

For meaningful reward distribution:

```
total_rewards / duration_ms ≥ 1
```

**Minimum examples:**
- 7 days: 604,800,000 tokens minimum
- 30 days: 2,592,000,000 tokens minimum
- 1 year: 31,536,000,000 tokens minimum

Or use tokens with more decimals (9-18) for smaller nominal amounts.

### Maximum Values

```
max_u64 = 18,446,744,073,709,551,615
max_u128 = 340,282,366,920,938,463,463,374,607,431,768,211,455
```

Safe operating limits (with PRECISION = 10^18):
- Max stake per user: ~10^18 tokens
- Max rewards: ~10^18 tokens
- Max acc: ~10^38 (u128 limit)

---

## Recommended Configurations

### Conservative Pool (Community)

```
Duration: 30 days
Min stake duration: 7 days
Stake fee: 0% (0 bps)
Unstake fee: 0% (0 bps)
Early fee: 3% (300 bps)
Rewards: 5% of circulating supply
```

### Aggressive Pool (Premium)

```
Duration: 7 days
Min stake duration: 3 days
Stake fee: 1% (100 bps)
Unstake fee: 1% (100 bps)
Early fee: 5% (500 bps)
Rewards: 20% of circulating supply
```

### Long-term Lock (High-yield)

```
Duration: 365 days
Min stake duration: 90 days
Stake fee: 2% (200 bps)
Unstake fee: 2% (200 bps)
Early fee: 10% (1000 bps)
Rewards: 15% of circulating supply
```

### Token Launch Pool

For newly launched tokens via launchpad:

```
Start: 7 days after DEX graduation
Duration: 90 days
Min stake duration: 14 days
Stake fee: 1% (100 bps)
Unstake fee: 1% (100 bps)
Early fee: 5% (500 bps)
Rewards: 10-20% of token supply

Rationale:
- Delay allows DEX liquidity to stabilize
- 90-day duration provides sustained incentive
- 14-day lock discourages quick dumps
- 5% early fee deters gaming
- 1% stake/unstake fees generate protocol revenue
```

---

## Summary

| Aspect | Value |
|--------|-------|
| Model | MasterChef accumulated reward per share |
| Precision | 10^18 (fixed-point) |
| Gas efficiency | O(1) per operation |
| Min stake | 1,000 units |
| Max stake fee | 5% (500 bps) |
| Max unstake fee | 5% (500 bps) |
| Max early fee | 10% (1000 bps) |
| Max platform fee | 5% (500 bps) |
| Min duration | 7 days |
| Max duration | 2 years |

The staking system is designed for fairness, gas efficiency, and flexibility while maintaining mathematical precision across all operations. The configurable fee structure (stake, unstake, early) allows pool creators to customize economics for their specific use case and generate protocol revenue.
