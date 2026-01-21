# Staking Service - Detailed Specification

## Overview

Staking as a Service (StaaS) - A standalone product that allows any token project to create staking pools for their community. Projects deposit reward tokens, users stake, and earn rewards over time.

---

## Business Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    STAKING AS A SERVICE (B2B)                            │
└─────────────────────────────────────────────────────────────────────────┘

WHO USES IT:
════════════
• Graduated launchpad tokens (seamless integration)
• External token projects (pay setup fee)
• Any Sui token wanting staking functionality

REVENUE MODEL:
══════════════
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   1. SETUP FEE (One-time)                                               │
│      └── 10-50 SUI per pool                                             │
│      └── Paid by project when creating staking pool                     │
│                                                                         │
│   2. PLATFORM FEE (Ongoing)                                             │
│      └── 2% of rewards distributed                                      │
│      └── Deducted automatically when users claim                        │
│                                                                         │
│   Example:                                                              │
│   ─────────                                                             │
│   Project deposits 1,000,000 tokens as rewards                          │
│   Over 12 months, all rewards distributed                               │
│   Platform earns: 1,000,000 * 2% = 20,000 tokens                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Module Structure

```
sui-staking/
├── Move.toml
└── sources/
    │
    ├── core/                    # Self-contained utilities
    │   ├── math.move           # Reward calculations, safe math
    │   └── access.move         # AdminCap, PoolAdminCap
    │
    ├── factory.move            # Pool creation & registry
    ├── pool.move               # Staking pool logic
    ├── position.move           # User staking position (NFT)
    ├── emissions.move          # Reward distribution logic
    └── events.move             # All events
```

---

## Core Concepts

### Staking Pool

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         STAKING POOL                                     │
└─────────────────────────────────────────────────────────────────────────┘

StakingPool<StakeToken, RewardToken>
══════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   Pool Configuration:                                                   │
│   ├── stake_token_type: TypeName          (e.g., PEPE)                 │
│   ├── reward_token_type: TypeName         (e.g., PEPE or different)    │
│   ├── start_time: u64                     (when rewards start)         │
│   ├── end_time: u64                       (when rewards end)           │
│   ├── reward_rate: u64                    (tokens per second)          │
│   └── pool_admin: address                 (who can manage)             │
│                                                                         │
│   Pool State:                                                           │
│   ├── total_staked: u64                   (total tokens staked)        │
│   ├── reward_reserve: Balance<RewardToken> (remaining rewards)         │
│   ├── acc_reward_per_share: u128          (accumulated rewards/share)  │
│   ├── last_update_time: u64               (last reward calculation)    │
│   └── total_distributed: u64              (lifetime rewards given)     │
│                                                                         │
│   Fees:                                                                 │
│   ├── early_unstake_fee_bps: u64          (e.g., 500 = 5%)             │
│   ├── min_stake_duration: u64             (seconds before no fee)      │
│   └── platform_fee_bps: u64               (2% of rewards)              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Staking Position (NFT)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    STAKING POSITION (NFT)                                │
└─────────────────────────────────────────────────────────────────────────┘

Each staker receives an NFT representing their position:

StakingPosition
═══════════════
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   Position Info:                                                        │
│   ├── pool_id: ID                         (which pool)                 │
│   ├── owner: address                      (who owns)                   │
│   ├── staked_amount: u64                  (how much staked)            │
│   ├── stake_time: u64                     (when staked)                │
│   ├── reward_debt: u128                   (for reward calculation)     │
│   └── last_claim_time: u64                (last reward claim)          │
│                                                                         │
│   Benefits of NFT:                                                      │
│   ├── Transferable (can sell position on marketplace)                  │
│   ├── Composable (can use in other DeFi protocols)                     │
│   ├── Visual (shows in wallet as collectible)                          │
│   └── Can be used for DAO voting power                                 │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## User Flows

### Project Creates Staking Pool

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    CREATE STAKING POOL                                   │
└─────────────────────────────────────────────────────────────────────────┘

STEP 1: Project calls create_pool()
════════════════════════════════════

    Transaction:
    ────────────
    Package:  staking
    Module:   factory
    Function: create_pool<StakeToken, RewardToken>

    Arguments:
    ├── registry: &mut StakingRegistry
    ├── reward_tokens: Coin<RewardToken>      ← Project deposits rewards
    ├── duration_seconds: u64                 ← How long pool runs
    ├── setup_fee: Coin<SUI>                  ← 10-50 SUI
    ├── early_unstake_fee_bps: u64           ← Optional early exit fee
    ├── min_stake_duration: u64              ← Optional lock period
    └── ctx: &mut TxContext

    What happens:
    ─────────────
    1. Validate setup fee
    2. Calculate reward_rate = reward_amount / duration
    3. Create StakingPool object
    4. Store reward tokens in pool
    5. Issue PoolAdminCap to creator
    6. Register pool in registry
    7. Emit PoolCreated event


STEP 2: Pool is now active
══════════════════════════

    Pool Info:
    ├── Pool ID: 0xPOOL123...
    ├── Stake Token: PEPE
    ├── Reward Token: PEPE
    ├── Total Rewards: 1,000,000 PEPE
    ├── Duration: 365 days
    ├── Reward Rate: ~31.7 PEPE/second
    └── Status: ACTIVE

    Users can now stake!
```

### User Stakes Tokens

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         USER STAKES                                      │
└─────────────────────────────────────────────────────────────────────────┘

User calls stake()
══════════════════

    Transaction:
    ────────────
    Package:  staking
    Module:   pool
    Function: stake<StakeToken, RewardToken>

    Arguments:
    ├── pool: &mut StakingPool<StakeToken, RewardToken>
    ├── tokens: Coin<StakeToken>              ← Tokens to stake
    └── ctx: &mut TxContext

    What happens:
    ─────────────
    1. Update pool's accumulated rewards (important!)
    2. Create StakingPosition NFT
    3. Set position.reward_debt = staked_amount * acc_reward_per_share
    4. Add tokens to pool's total_staked
    5. Transfer position NFT to user
    6. Emit Staked event

    User receives:
    ──────────────
    StakingPosition NFT showing:
    ├── Pool: PEPE Staking
    ├── Staked: 10,000 PEPE
    ├── Since: Jan 20, 2026
    └── Pending Rewards: 0 PEPE (just staked)
```

### User Claims Rewards

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       CLAIM REWARDS                                      │
└─────────────────────────────────────────────────────────────────────────┘

User calls claim()
══════════════════

    Transaction:
    ────────────
    Package:  staking
    Module:   pool
    Function: claim<StakeToken, RewardToken>

    Arguments:
    ├── pool: &mut StakingPool<StakeToken, RewardToken>
    ├── position: &mut StakingPosition
    ├── clock: &Clock
    └── ctx: &mut TxContext

    Reward Calculation:
    ───────────────────
    1. Update pool's acc_reward_per_share based on time elapsed

       new_rewards = (current_time - last_update_time) * reward_rate
       acc_reward_per_share += (new_rewards * 1e18) / total_staked

    2. Calculate user's pending rewards

       pending = (position.staked_amount * acc_reward_per_share / 1e18)
                 - position.reward_debt

    3. Deduct platform fee

       platform_fee = pending * platform_fee_bps / 10000
       user_reward = pending - platform_fee

    4. Update position.reward_debt

    5. Transfer rewards to user

    Example:
    ────────
    User staked: 10,000 PEPE
    Time staked: 30 days
    Total pool staked: 1,000,000 PEPE
    Pool reward rate: 31.7 PEPE/second

    User's share: 10,000 / 1,000,000 = 1%
    30 days rewards: 31.7 * 86400 * 30 = 82,166,400 PEPE total
    User's rewards: 82,166,400 * 1% = 821,664 PEPE
    Platform fee (2%): 16,433 PEPE
    User receives: 805,231 PEPE
```

### User Unstakes

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           UNSTAKE                                        │
└─────────────────────────────────────────────────────────────────────────┘

User calls unstake()
════════════════════

    Transaction:
    ────────────
    Package:  staking
    Module:   pool
    Function: unstake<StakeToken, RewardToken>

    Arguments:
    ├── pool: &mut StakingPool<StakeToken, RewardToken>
    ├── position: StakingPosition             ← NFT consumed/burned
    ├── clock: &Clock
    └── ctx: &mut TxContext

    What happens:
    ─────────────
    1. Claim any pending rewards first

    2. Check for early unstake fee
       if (current_time - stake_time) < min_stake_duration:
           early_fee = staked_amount * early_unstake_fee_bps / 10000
           return_amount = staked_amount - early_fee
       else:
           return_amount = staked_amount

    3. Remove tokens from pool's total_staked

    4. Burn/delete StakingPosition NFT

    5. Transfer staked tokens back to user

    6. Emit Unstaked event

    User receives:
    ──────────────
    ├── Pending rewards (minus platform fee)
    └── Staked tokens (minus early unstake fee if applicable)
```

---

## Reward Distribution Math

### Accumulated Reward Per Share Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    REWARD MATH (MasterChef Style)                        │
└─────────────────────────────────────────────────────────────────────────┘

This model efficiently calculates rewards for any number of stakers
without iterating through all positions.

Key Variables:
══════════════
• acc_reward_per_share (pool) - Accumulated rewards per staked token
• reward_debt (position) - Offset to calculate pending rewards
• PRECISION = 1e18 - For fixed-point math

Update Pool (called on any state change):
═════════════════════════════════════════

    function update_pool():
        if total_staked == 0:
            last_update_time = current_time
            return

        time_elapsed = current_time - last_update_time
        rewards = time_elapsed * reward_rate

        acc_reward_per_share += (rewards * PRECISION) / total_staked
        last_update_time = current_time


Calculate Pending Rewards:
══════════════════════════

    function pending_rewards(position):
        // First update pool to current time
        accumulated = position.staked_amount * pool.acc_reward_per_share / PRECISION
        pending = accumulated - position.reward_debt
        return pending


On Stake:
═════════

    function stake(amount):
        update_pool()

        // Set reward_debt so user doesn't get rewards from before staking
        position.reward_debt = amount * acc_reward_per_share / PRECISION
        position.staked_amount = amount
        pool.total_staked += amount


On Claim:
═════════

    function claim(position):
        update_pool()

        pending = (position.staked_amount * acc_reward_per_share / PRECISION)
                  - position.reward_debt

        // Reset reward_debt to current accumulated
        position.reward_debt = position.staked_amount * acc_reward_per_share / PRECISION

        transfer(pending, user)


Example Walkthrough:
════════════════════

Time 0: Pool created
    - reward_rate: 100 tokens/second
    - acc_reward_per_share: 0
    - total_staked: 0

Time 10: Alice stakes 1000 tokens
    - update_pool(): no change (total_staked was 0)
    - alice.reward_debt = 1000 * 0 = 0
    - total_staked: 1000

Time 20: Bob stakes 1000 tokens
    - update_pool():
      - time_elapsed = 10
      - rewards = 10 * 100 = 1000
      - acc_reward_per_share = 0 + (1000 * 1e18 / 1000) = 1e18
    - bob.reward_debt = 1000 * 1e18 / 1e18 = 1000
    - total_staked: 2000

Time 30: Alice claims
    - update_pool():
      - time_elapsed = 10
      - rewards = 10 * 100 = 1000
      - acc_reward_per_share = 1e18 + (1000 * 1e18 / 2000) = 1.5e18
    - alice.pending = (1000 * 1.5e18 / 1e18) - 0 = 1500
    - Alice receives 1500 tokens! (10 sec alone + 5 sec shared with Bob)

Time 30: Bob claims
    - bob.pending = (1000 * 1.5e18 / 1e18) - 1000 = 500
    - Bob receives 500 tokens! (only 10 sec shared with Alice)
```

---

## Pool Types

### Single Token Staking

```
Stake PEPE → Earn PEPE

Common for:
• Community rewards
• Token burns (stake to earn from buy tax)
• Loyalty programs
```

### Dual Token Staking

```
Stake PEPE → Earn SUI (or another token)

Common for:
• Partnership rewards
• Protocol revenue sharing
• Cross-promotion
```

### LP Token Staking

```
Stake PEPE-SUI LP → Earn PEPE

Common for:
• Liquidity mining
• DEX incentives
• Bootstrapping liquidity
```

---

## Events

```move
module staking::events {

    struct PoolCreated has copy, drop {
        pool_id: ID,
        stake_token: TypeName,
        reward_token: TypeName,
        reward_amount: u64,
        duration: u64,
        reward_rate: u64,
        creator: address,
        setup_fee_paid: u64,
        timestamp: u64,
    }

    struct Staked has copy, drop {
        pool_id: ID,
        position_id: ID,
        staker: address,
        amount: u64,
        total_staked: u64,
        timestamp: u64,
    }

    struct Unstaked has copy, drop {
        pool_id: ID,
        position_id: ID,
        staker: address,
        amount: u64,
        early_fee: u64,
        total_staked: u64,
        timestamp: u64,
    }

    struct RewardsClaimed has copy, drop {
        pool_id: ID,
        position_id: ID,
        staker: address,
        amount: u64,
        platform_fee: u64,
        timestamp: u64,
    }

    struct RewardsAdded has copy, drop {
        pool_id: ID,
        amount: u64,
        new_end_time: u64,
        added_by: address,
        timestamp: u64,
    }

    struct PoolConfigUpdated has copy, drop {
        pool_id: ID,
        field: String,
        old_value: u64,
        new_value: u64,
        updated_by: address,
        timestamp: u64,
    }
}
```

---

## Security

### Access Control

| Function | Who Can Call | Capability Required |
|----------|--------------|---------------------|
| `create_pool` | Anyone | Pays setup fee |
| `stake` | Anyone | Has tokens |
| `unstake` | Position owner | Owns StakingPosition |
| `claim` | Position owner | Owns StakingPosition |
| `add_rewards` | Pool admin | PoolAdminCap |
| `update_pool_config` | Pool admin | PoolAdminCap |
| `pause_pool` | Platform admin | AdminCap |
| `update_platform_fee` | Platform admin | AdminCap |
| `emergency_withdraw` | Platform admin | AdminCap + timelock |

### Validation

```move
// On create_pool
assert!(reward_amount > 0, EZeroRewards);
assert!(duration >= MIN_DURATION, EDurationTooShort);
assert!(duration <= MAX_DURATION, EDurationTooLong);
assert!(coin::value(&setup_fee) >= registry.setup_fee, EInsufficientFee);
assert!(early_unstake_fee_bps <= MAX_EARLY_FEE, EFeeTooHigh);

// On stake
assert!(!pool.paused, EPoolPaused);
assert!(amount >= MIN_STAKE, EAmountTooSmall);
assert!(clock::timestamp_ms(clock) < pool.end_time, EPoolEnded);

// On unstake
assert!(position.pool_id == object::id(pool), EWrongPool);
assert!(tx_context::sender(ctx) == position.owner, ENotOwner);

// On claim
assert!(pending > 0, ENothingToClaim);
assert!(pool.reward_reserve >= pending, EInsufficientRewards);
```

---

## Configuration

```move
struct StakingRegistry has key {
    id: UID,

    // Platform fees
    setup_fee: u64,              // SUI amount for pool creation
    platform_fee_bps: u64,       // % of rewards (e.g., 200 = 2%)

    // Limits
    min_duration: u64,           // Min pool duration (e.g., 7 days)
    max_duration: u64,           // Max pool duration (e.g., 2 years)
    min_stake: u64,              // Min stake amount (dust protection)
    max_early_fee_bps: u64,      // Max early unstake fee (e.g., 1000 = 10%)

    // Admin
    treasury: address,           // Where platform fees go
    paused: bool,                // Global pause
}
```

---

## Integration with DAO

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    STAKING + DAO INTEGRATION                             │
└─────────────────────────────────────────────────────────────────────────┘

StakingPosition can be used for DAO voting power:

Option 1: Direct Integration
════════════════════════════
DAO queries staking contract for user's staked amount

    dao::vote(proposal_id, position_id)
        └── staking::get_voting_power(position_id)
            └── returns position.staked_amount


Option 2: Snapshot
══════════════════
DAO takes snapshot of all positions at proposal creation

    On proposal create:
    └── Record staked amounts for all positions

    On vote:
    └── Use snapshot amount (prevents flash-stake attacks)


Benefits:
═════════
• Staked tokens have governance rights
• Encourages long-term holding
• Aligns incentives (stakers = committed holders)
```

---

## Estimated Lines of Code

| File | Lines | Description |
|------|-------|-------------|
| core/math.move | ~80 | Safe math, reward calculations |
| core/access.move | ~60 | AdminCap, PoolAdminCap |
| factory.move | ~150 | Pool creation, registry |
| pool.move | ~350 | Stake, unstake, claim logic |
| position.move | ~100 | Position NFT, metadata |
| emissions.move | ~120 | Reward rate, distribution |
| events.move | ~80 | Event definitions |
| **Total** | **~940** | |

---

## Status

| Component | Status | Notes |
|-----------|--------|-------|
| Core utilities | Not started | |
| Factory | Not started | |
| Pool | Not started | |
| Position | Not started | |
| Emissions | Not started | |
| Events | Not started | |
| Tests | Not started | |
| Audit | Not started | |
