# sui_staking

A flexible staking pool system for Sui Move with MasterChef-style reward distribution.

## Overview

sui_staking enables creating staking pools where users can stake tokens and earn rewards over time. It supports:

- **Dual token pools**: Stake Token A, earn Token B (or same token)
- **NFT-based positions**: Transferable staking positions
- **Configurable fees**: Early unstake, stake, and unstake fees
- **Origin tracking**: Track if pool was created via launchpad or independently
- **Governance pools**: Pools without rewards for voting power only

## Architecture

```
sui_staking/
├── sources/
│   ├── factory.move          # Pool creation & platform config
│   └── core/
│       ├── pool.move         # Core staking logic
│       ├── position.move     # NFT position management
│       ├── math.move         # Reward calculations
│       ├── access.move       # Capability definitions
│       ├── events.move       # Event definitions
│       └── errors.move       # Error codes
```

## Key Concepts

### StakingRegistry

Global shared object that tracks all pools and platform configuration.

```move
public struct StakingRegistry has key {
    id: UID,
    config: PlatformConfig,
    pool_ids: vector<ID>,
    pool_metadata: Table<ID, PoolMetadata>,
    collected_fees: Balance<SUI>,
    total_pools: u64,
    paused: bool,
}
```

### StakingPool

Each pool is a shared object that holds staked tokens and reward tokens.

```move
public struct StakingPool<phantom StakeToken, phantom RewardToken> has key, store {
    id: UID,
    config: PoolConfig,
    total_staked: u64,
    stake_balance: Balance<StakeToken>,
    reward_balance: Balance<RewardToken>,
    acc_reward_per_share: u128,    // MasterChef accumulator
    last_reward_time_ms: u64,
    reward_rate: u64,              // tokens per ms
    total_rewards_distributed: u64,
    collected_fees: Balance<StakeToken>,
}
```

### StakingPosition

NFT representing a user's stake. Transferable and can be used across wallets.

```move
public struct StakingPosition<phantom StakeToken> has key, store {
    id: UID,
    pool_id: ID,
    staked_amount: u64,
    reward_debt: u128,
    stake_time_ms: u64,
    last_claim_time_ms: u64,
}
```

## Creating Pools

### Public Pool Creation (with fee)

```move
let pool_admin_cap = factory::create_pool<STAKE, REWARD>(
    &mut registry,
    reward_coins,           // Coin<REWARD> with total rewards
    setup_fee,              // Coin<SUI> for platform fee
    start_time_ms,          // When rewards start
    duration_ms,            // Reward distribution period
    min_stake_duration_ms,  // Minimum stake before fee-free unstake
    early_unstake_fee_bps,  // Fee for early unstake (max 10%)
    stake_fee_bps,          // Fee on deposits (max 5%)
    unstake_fee_bps,        // Fee on withdrawals (max 5%)
    clock,
    ctx,
);
```

### Admin Pool Creation (no fee, with origin tracking)

```move
let pool_admin_cap = factory::create_pool_admin<STAKE, REWARD>(
    &mut registry,
    &admin_cap,             // Platform AdminCap
    reward_coins,
    start_time_ms,
    duration_ms,
    min_stake_duration_ms,
    early_unstake_fee_bps,
    stake_fee_bps,
    unstake_fee_bps,
    origin,                 // 0=independent, 1=launchpad, 2=partner
    origin_id,              // Optional<ID> linking to source
    clock,
    ctx,
);
```

## Staking Operations

### Stake Tokens

```move
let position = pool::stake<STAKE, REWARD>(
    &mut pool,
    tokens,     // Coin<STAKE> to stake
    clock,
    ctx,
);
```

### Add to Existing Position

```move
pool::stake_more<STAKE, REWARD>(
    &mut pool,
    &mut position,
    additional_tokens,
    clock,
    ctx,
);
```

### Claim Rewards

```move
let rewards = pool::claim_rewards<STAKE, REWARD>(
    &mut pool,
    &mut position,
    clock,
    ctx,
);
```

### Unstake

```move
let (returned_tokens, rewards) = pool::unstake<STAKE, REWARD>(
    &mut pool,
    position,   // Position NFT is burned
    clock,
    ctx,
);
```

## Fee Structure

| Fee Type | Max | Description |
|----------|-----|-------------|
| Setup Fee | Configurable | SUI fee to create a pool (default: 1 SUI) |
| Early Unstake Fee | 10% (1000 bps) | Fee if unstaking before min_stake_duration |
| Stake Fee | 5% (500 bps) | Fee deducted when depositing |
| Unstake Fee | 5% (500 bps) | Fee deducted when withdrawing |
| Platform Fee | 5% (500 bps) | Platform fee on rewards |

## Origin Tracking

Pools can be tagged with their creation origin for analytics:

```move
// Origin constants
const ORIGIN_INDEPENDENT: u8 = 0;  // Direct creation
const ORIGIN_LAUNCHPAD: u8 = 1;    // Created via launchpad graduation
const ORIGIN_PARTNER: u8 = 2;      // Created via partner integration

// Access via events module
sui_staking::events::origin_independent()
sui_staking::events::origin_launchpad()
sui_staking::events::origin_partner()
```

## Duration Constraints

| Parameter | Min | Max |
|-----------|-----|-----|
| Pool Duration | 7 days | 2 years |
| Min Stake Duration | 0 | (no max) |

## Capabilities

### AdminCap

Platform-level admin capability for:
- Creating pools without fees
- Updating platform configuration
- Pausing/unpausing the platform
- Collecting platform fees

### PoolAdminCap

Pool-level admin capability for:
- Updating pool configuration
- Pausing/unpausing the pool
- Adding more rewards
- Collecting pool fees

## Events

```move
// Pool events
PoolCreated { pool_id, creator, stake_token_type, reward_token_type, ... }
GovernancePoolCreated { pool_id, creator, stake_token_type, ... }
RewardsAdded { pool_id, amount, new_total_rewards, added_by }
PoolConfigUpdated { pool_id, ... }
PoolPauseToggled { pool_id, paused, toggled_by }

// Staking events
Staked { pool_id, position_id, staker, amount, total_staked_in_pool }
Unstaked { pool_id, position_id, staker, amount, fee_amount, ... }
RewardsClaimed { pool_id, position_id, claimer, reward_amount }
StakeAdded { pool_id, position_id, staker, added_amount, new_total_staked }

// Platform events
PlatformFeeCollected { pool_id, fee_amount, fee_recipient }
PlatformConfigUpdated { setup_fee, platform_fee_bps, updated_by }
```

## Error Codes

| Range | Category |
|-------|----------|
| 100-199 | Pool errors (paused, ended, invalid duration, etc.) |
| 200-299 | Staking errors (zero amount, nothing to claim, wrong pool) |
| 300-399 | Access errors (not owner, not admin) |
| 400-499 | Fee errors (insufficient fee, fee too high) |
| 500-599 | Platform errors (paused, invalid config) |

## Integration with Launchpad

When a token graduates from the launchpad, a staking pool can be automatically created:

```move
// In graduation PTB:
let pool_admin_cap = staking_integration::create_staking_pool<T>(
    &mut staking_registry,
    &staking_admin_cap,
    &pending,           // PendingGraduation
    reward_coins,       // Tokens reserved for staking rewards
    clock,
    ctx,
);
```

## Building & Testing

```bash
cd sui_staking
sui move build
sui move test
```

## License

Apache 2.0
