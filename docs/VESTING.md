# Vesting Service - Standalone Package Specification

## Overview

The Vesting Service (`sui_vesting`) is a **standalone, reusable package** for token vesting on Sui blockchain. It will be deployed separately and can be integrated by the Launchpad, Staking, DAO, or any external project.

**Status:** NOT STARTED - Placeholder in Launchpad

---

## Why Standalone?

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         STANDALONE BENEFITS                                  │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│   sui_vesting    │ ◄── Standalone Package
│   (Reusable)     │
└────────┬─────────┘
         │
         │ Can be imported by:
         │
    ┌────┴────┬────────────┬────────────┬────────────────┐
    │         │            │            │                │
    ▼         ▼            ▼            ▼                ▼
┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐     ┌──────────────┐
│Launch- │ │Staking │ │  DAO   │ │External│     │  Sold as     │
│  pad   │ │        │ │        │ │Projects│     │  Service     │
└────────┘ └────────┘ └────────┘ └────────┘     └──────────────┘

BENEFITS:
├── Sell vesting as standalone B2B service
├── Independent versioning and upgrades
├── Smaller audit scope per package
├── Reusable across all your products
└── External projects can integrate
```

---

## Module Structure

```
sui_vesting/                          # STANDALONE PACKAGE
├── Move.toml
└── sources/
    ├── vesting.move                  # Core vesting logic
    ├── linear.move                   # Linear vesting implementation
    ├── milestone.move                # Milestone-based vesting (future)
    ├── batch.move                    # Batch operations
    ├── admin.move                    # Admin functions
    └── events.move                   # Event definitions
```

---

## Vesting Types

### 1. Linear Vesting with Cliff (Primary)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    LINEAR VESTING WITH CLIFF                                 │
└─────────────────────────────────────────────────────────────────────────────┘

                    CLIFF PERIOD              LINEAR VESTING PERIOD
                    (No claims)               (Gradual unlock)
    ├──────────────────────┼────────────────────────────────────────┤
    │                      │                                        │
 start_time           cliff_end                               vesting_end
    │                      │                                        │
    ▼                      ▼                                        ▼
┌───────────────────┬──────────────────────────────────────────────────┐
│   0% claimable    │     Linear unlock from 0% → 100%                 │
│   (locked)        │     ████████████████████████████████████████████ │
└───────────────────┴──────────────────────────────────────────────────┘

Formula:
─────────
vested_amount = (time_since_cliff / vesting_duration) × total_amount
claimable = vested_amount - already_claimed

Example: 1M tokens, 6 month cliff, 12 month vesting
├── Month 0-6:   0 tokens claimable (cliff)
├── Month 6:     0 tokens (cliff just ended)
├── Month 9:     250K tokens (25% of vesting period)
├── Month 12:    500K tokens (50%)
├── Month 15:    750K tokens (75%)
└── Month 18:    1M tokens (100% vested)
```

### 2. Milestone-Based Vesting (Future)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    MILESTONE-BASED VESTING                                   │
└─────────────────────────────────────────────────────────────────────────────┘

Tokens unlock at specific milestones:

    │ Milestone 1  │ Milestone 2  │ Milestone 3  │ Milestone 4  │
    │    25%       │    25%       │    25%       │    25%       │
    ▼              ▼              ▼              ▼              ▼
┌───────────┬────────────┬────────────┬────────────┬────────────┐
│ Month 3   │  Month 6   │  Month 9   │  Month 12  │            │
│ TGE+3mo   │  TGE+6mo   │  TGE+9mo   │  TGE+12mo  │  COMPLETE  │
└───────────┴────────────┴────────────┴────────────┴────────────┘

Use cases:
├── Team token distribution
├── Investor unlock schedules
└── Performance-based vesting
```

---

## Core Data Structures

### VestingSchedule

```move
/// Main vesting schedule struct - holds tokens and tracks claims
public struct VestingSchedule<phantom T> has key, store {
    id: UID,

    /// Reference to source (pool_id, dao_id, etc.)
    source_id: ID,

    /// Address that can claim tokens
    beneficiary: address,

    /// Total tokens to be vested
    total_amount: u64,

    /// Tokens already claimed
    claimed_amount: u64,

    /// Tokens held in vesting
    balance: Balance<T>,

    /// Vesting start time (timestamp in ms)
    start_time: u64,

    /// Cliff duration in ms (no tokens claimable before cliff)
    cliff_duration: u64,

    /// Total vesting duration in ms (after cliff)
    vesting_duration: u64,

    /// Whether vesting is revocable by admin
    revocable: bool,

    /// Whether vesting has been revoked
    revoked: bool,

    /// Creation timestamp
    created_at: u64,
}
```

### VestingConfig

```move
/// Global configuration for vesting service
public struct VestingConfig has key {
    id: UID,

    /// Minimum cliff duration (e.g., 0 for no minimum)
    min_cliff_duration: u64,

    /// Maximum cliff duration (e.g., 2 years)
    max_cliff_duration: u64,

    /// Minimum vesting duration
    min_vesting_duration: u64,

    /// Maximum vesting duration
    max_vesting_duration: u64,

    /// Fee for creating vesting schedule (optional)
    creation_fee: u64,

    /// Treasury for fees
    treasury: address,

    /// Pause state
    paused: bool,
}
```

---

## Core Functions

### Creation

```move
/// Create a new vesting schedule
public fun create_vesting<T>(
    source_id: ID,
    beneficiary: address,
    tokens: Coin<T>,
    start_time: u64,
    cliff_duration: u64,
    vesting_duration: u64,
    revocable: bool,
    clock: &Clock,
    ctx: &mut TxContext,
): VestingSchedule<T>

/// Create vesting that starts immediately
public fun create_vesting_now<T>(
    source_id: ID,
    beneficiary: address,
    tokens: Coin<T>,
    cliff_duration: u64,
    vesting_duration: u64,
    revocable: bool,
    clock: &Clock,
    ctx: &mut TxContext,
): VestingSchedule<T>

/// Batch create multiple vesting schedules
public fun create_batch<T>(
    source_id: ID,
    beneficiaries: vector<address>,
    amounts: vector<u64>,
    tokens: Coin<T>,
    cliff_duration: u64,
    vesting_duration: u64,
    revocable: bool,
    clock: &Clock,
    ctx: &mut TxContext,
): vector<VestingSchedule<T>>
```

### Claiming

```move
/// Claim vested tokens (returns Coin)
public fun claim<T>(
    vesting: &mut VestingSchedule<T>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T>

/// Claim and transfer to beneficiary
public fun claim_all<T>(
    vesting: &mut VestingSchedule<T>,
    clock: &Clock,
    ctx: &mut TxContext,
)

/// Get claimable amount without claiming
public fun claimable<T>(
    vesting: &VestingSchedule<T>,
    clock: &Clock,
): u64
```

### Admin Functions

```move
/// Revoke vesting and return unvested tokens (admin only)
/// Only works if vesting was created as revocable
public fun revoke<T>(
    admin: &AdminCap,
    vesting: &mut VestingSchedule<T>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T>

/// Transfer beneficiary to new address
public fun transfer_beneficiary<T>(
    vesting: &mut VestingSchedule<T>,
    new_beneficiary: address,
    ctx: &TxContext,
)
```

### View Functions

```move
public fun beneficiary<T>(vesting: &VestingSchedule<T>): address
public fun total_amount<T>(vesting: &VestingSchedule<T>): u64
public fun claimed_amount<T>(vesting: &VestingSchedule<T>): u64
public fun remaining_amount<T>(vesting: &VestingSchedule<T>): u64
public fun start_time<T>(vesting: &VestingSchedule<T>): u64
public fun cliff_duration<T>(vesting: &VestingSchedule<T>): u64
public fun vesting_duration<T>(vesting: &VestingSchedule<T>): u64
public fun cliff_end<T>(vesting: &VestingSchedule<T>): u64
public fun vesting_end<T>(vesting: &VestingSchedule<T>): u64
public fun is_revocable<T>(vesting: &VestingSchedule<T>): bool
public fun is_revoked<T>(vesting: &VestingSchedule<T>): bool
```

---

## Events

```move
/// Emitted when vesting schedule is created
public struct VestingCreated has copy, drop {
    vesting_id: ID,
    source_id: ID,
    beneficiary: address,
    total_amount: u64,
    start_time: u64,
    cliff_duration: u64,
    vesting_duration: u64,
    revocable: bool,
    timestamp: u64,
}

/// Emitted when tokens are claimed
public struct VestingClaimed has copy, drop {
    vesting_id: ID,
    beneficiary: address,
    amount_claimed: u64,
    total_claimed: u64,
    remaining: u64,
    timestamp: u64,
}

/// Emitted when vesting is revoked
public struct VestingRevoked has copy, drop {
    vesting_id: ID,
    beneficiary: address,
    vested_amount: u64,
    unvested_returned: u64,
    revoked_by: address,
    timestamp: u64,
}

/// Emitted when beneficiary is transferred
public struct BeneficiaryTransferred has copy, drop {
    vesting_id: ID,
    old_beneficiary: address,
    new_beneficiary: address,
    timestamp: u64,
}
```

---

## Integration with Launchpad

### At Graduation

When a token graduates to DEX, creator tokens can be vested:

```move
// In graduation.move (future integration)

// Import sui_vesting
use sui_vesting::vesting;

public fun initiate_graduation_with_vesting<T>(
    admin: &AdminCap,
    pool: &mut BondingPool<T>,
    config: &LaunchpadConfig,
    vesting_config: &VestingConfig,
    cliff_duration: u64,
    vesting_duration: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // ... graduation logic ...

    // Instead of direct transfer to creator:
    // transfer::public_transfer(creator_tokens, creator);

    // Create vesting schedule for creator tokens
    if (creator_tokens > 0) {
        let creator_coin = coin::from_balance(creator_balance, ctx);
        let schedule = vesting::create_vesting_now(
            object::id(pool),
            bonding_curve::creator(pool),
            creator_coin,
            cliff_duration,      // e.g., 6 months
            vesting_duration,    // e.g., 12 months
            true,                // revocable
            clock,
            ctx,
        );
        transfer::public_transfer(schedule, bonding_curve::creator(pool));
    };

    // ... rest of graduation ...
}
```

---

## Use Cases

### 1. Launchpad Creator Vesting

```
Creator gets 2.5% tokens at graduation
├── Vested over 12 months
├── 6 month cliff
├── Revocable (in case creator abandons)
└── Incentivizes long-term commitment
```

### 2. Team Token Distribution

```
Team allocation: 15% of total supply
├── Multiple beneficiaries
├── Batch creation
├── 1 year cliff
├── 3 year vesting
└── Revocable if team member leaves
```

### 3. Investor Allocations

```
Seed/Private sale tokens
├── Per-investor schedules
├── TGE unlock (e.g., 10%)
├── Remaining vested
└── Non-revocable
```

### 4. Staking Rewards Vesting

```
Large reward claims can be vested
├── Prevents immediate dumps
├── Short cliff (e.g., 1 week)
├── Linear vesting (e.g., 1 month)
└── Non-revocable
```

### 5. DAO Treasury Unlocks

```
DAO treasury can vest tokens to contributors
├── Milestone-based or linear
├── Community-controlled via proposals
└── Transparent unlock schedule
```

---

## Revenue Model (B2B Service)

| Fee Type | Amount | When |
|----------|--------|------|
| Setup Fee | 1-5 SUI | Per vesting schedule created |
| Batch Discount | 50% off | For 10+ schedules |
| Enterprise | Custom | White-label integration |

---

## Security Features

| Feature | Implementation |
|---------|----------------|
| Only beneficiary can claim | `assert!(ctx.sender() == beneficiary)` |
| Admin-only revocation | Requires AdminCap |
| Revocable flag immutable | Set at creation, cannot change |
| Balance integrity | Tokens in Balance<T>, not external |
| Cliff enforcement | Cannot claim before cliff ends |
| Overflow protection | u128 intermediate calculations |

---

## Move.toml

```toml
[package]
name = "sui_vesting"
edition = "2024.beta"
version = "1.0.0"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet" }

[addresses]
sui_vesting = "0x0"
```

---

## Estimated Lines of Code

| File | Lines | Description |
|------|-------|-------------|
| vesting.move | ~250 | Core VestingSchedule logic |
| linear.move | ~100 | Linear vesting calculations |
| milestone.move | ~150 | Milestone-based (future) |
| batch.move | ~80 | Batch operations |
| admin.move | ~100 | Admin functions, config |
| events.move | ~80 | Event definitions |
| **Total** | **~760** | |

---

## Development Status

| Component | Status | Notes |
|-----------|--------|-------|
| Specification | DONE | This document |
| Core vesting logic | NOT STARTED | |
| Linear vesting | NOT STARTED | |
| Milestone vesting | NOT STARTED | Future phase |
| Batch operations | NOT STARTED | |
| Admin functions | NOT STARTED | |
| Events | NOT STARTED | |
| Tests | NOT STARTED | |
| Integration with Launchpad | NOT STARTED | After core complete |
| Audit | NOT STARTED | |

---

## Integration Checklist

When sui_vesting is ready, update these files in sui_launchpad:

- [ ] `Move.toml` - Add sui_vesting dependency
- [ ] `graduation.move` - Import and use vesting
- [ ] `launchpad.move` - Uncomment vesting entry points
- [ ] `vesting.move` - Remove placeholder, re-export from sui_vesting
- [ ] Update tests
- [ ] Update documentation

---

## Links

| Resource | Link |
|----------|------|
| Placeholder Code | `sui_launchpad/sources/vesting.move` |
| Architecture | [ARCHITECTURE.md](./ARCHITECTURE.md) |
| Launchpad Spec | [LAUNCHPAD.md](./LAUNCHPAD.md) |
| Status Tracker | [STATUS.md](./STATUS.md) |
