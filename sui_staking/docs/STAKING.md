# Sui Staking Module

A flexible, gas-efficient staking module for Sui blockchain using the MasterChef-style accumulated reward per share model.

## Overview

The staking module allows projects to create staking pools where users can:
- Stake any fungible token to earn rewards
- Receive transferable Position NFTs representing their stake
- Claim rewards proportional to their stake over time
- Unstake with optional early withdrawal penalties

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       StakingRegistry                           │
│  (Shared Object - tracks all pools and platform config)         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              StakingPool<StakeToken, RewardToken>               │
│  (Shared Object - holds stake/reward balances)                  │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │stake_balance│  │reward_balance│ │ acc_reward  │             │
│  │   Balance   │  │   Balance    │ │ _per_share  │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              StakingPosition<StakeToken>                        │
│  (Owned NFT - transferable, tracks stake & reward debt)         │
│                                                                 │
│  ┌──────────────┐  ┌────────────┐  ┌─────────────┐             │
│  │staked_amount │  │reward_debt │  │stake_time_ms│             │
│  └──────────────┘  └────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

## Module Structure

```
sui_staking/
├── sources/
│   ├── core/
│   │   ├── math.move      # Reward calculations, fee math
│   │   ├── access.move    # AdminCap, PoolAdminCap
│   │   ├── errors.move    # Error codes
│   │   ├── events.move    # Event definitions
│   │   ├── position.move  # StakingPosition NFT
│   │   └── pool.move      # StakingPool, stake/unstake/claim
│   └── factory.move       # Registry, pool creation
├── tests/
│   └── staking_tests.move # Comprehensive tests
└── docs/
    └── STAKING.md         # This file
```

## Key Concepts

### MasterChef Reward Model

The module uses an accumulated reward per share model:

```
acc_reward_per_share += (new_rewards × PRECISION) / total_staked
pending_rewards = (staked_amount × acc_reward_per_share / PRECISION) - reward_debt
```

Where `PRECISION = 1e18` for fixed-point math precision.

### Position NFT

Each stake creates a transferable NFT that:
- Tracks staked amount and reward debt
- Records stake timestamp for early withdrawal fees
- Can be transferred to trade positions
- Must be returned to unstake

### Early Withdrawal Fees

Pools can configure:
- `min_stake_duration_ms`: Time before free withdrawals
- `early_unstake_fee_bps`: Fee (basis points) for early unstaking

## Usage

### Creating a Pool

```move
// Via factory (collects setup fee)
let admin_cap = factory::create_pool<STAKE, REWARD>(
    &mut registry,
    reward_coins,
    setup_fee,
    start_time_ms,
    duration_ms,
    min_stake_duration_ms,
    early_unstake_fee_bps,
    &clock,
    ctx,
);
```

### Staking

```move
let position = pool::stake(
    &mut pool,
    stake_coins,
    &clock,
    ctx,
);
// Transfer position NFT to user
```

### Claiming Rewards

```move
let reward_coin = pool::claim_rewards(
    &mut pool,
    &mut position,
    &clock,
    ctx,
);
```

### Unstaking

```move
// Full unstake (destroys position)
let (stake_coin, reward_coin) = pool::unstake(
    &mut pool,
    position,
    &clock,
    ctx,
);

// Partial unstake (keeps position)
let (stake_coin, reward_coin) = pool::unstake_partial(
    &mut pool,
    &mut position,
    amount,
    &clock,
    ctx,
);
```

### Adding to Existing Position

```move
let reward_coin = pool::add_stake(
    &mut pool,
    &mut position,
    more_stake_coins,
    &clock,
    ctx,
);
```

## Configuration

### Pool Config

| Parameter | Description | Constraints |
|-----------|-------------|-------------|
| `duration_ms` | Reward distribution period | 7 days - 2 years |
| `min_stake_duration_ms` | Min time before free unstake | Any |
| `early_unstake_fee_bps` | Early withdrawal fee | 0 - 1000 (0-10%) |

### Platform Config

| Parameter | Description | Default |
|-----------|-------------|---------|
| `setup_fee` | Fee to create pool (SUI) | 1 SUI |
| `platform_fee_bps` | Platform fee on rewards | 100 (1%) |

## Error Codes

| Range | Category |
|-------|----------|
| 100-199 | Pool errors (paused, ended, invalid duration) |
| 200-299 | Staking errors (zero amount, nothing to claim) |
| 300-399 | Access errors (not owner, wrong admin) |
| 400-499 | Fee errors (insufficient, too high) |
| 500-599 | Platform errors (paused, invalid config) |

## Events

- `PoolCreated` - New pool deployed
- `Staked` - Tokens staked
- `Unstaked` - Tokens unstaked (with fee info)
- `RewardsClaimed` - Rewards claimed
- `RewardsAdded` - More rewards added to pool
- `PoolConfigUpdated` - Config changed
- `PoolPauseToggled` - Pool paused/unpaused

## Security Considerations

1. **Precision Loss**: Use large reward amounts to minimize rounding errors
2. **Early Fee**: Capped at 10% to protect users
3. **Dust Protection**: Minimum stake of 1000 units
4. **Admin Controls**: Pool creators can pause but not withdraw user funds
5. **Transferable Positions**: Users can sell/transfer their stake positions

## Testing

Run tests:
```bash
sui move test
```

27 tests covering:
- Pool creation (direct and via factory)
- Staking and position creation
- Reward claiming
- Full and partial unstaking
- Early withdrawal fees
- Multi-user proportional rewards
- Admin functions
- Edge cases and error conditions
