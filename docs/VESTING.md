# Sui Vesting Package

Claim-based vesting module for Sui blockchain. Supports vesting for both fungible tokens (`Coin<T>`) and NFTs (CLMM positions).

**Status:** IMPLEMENTED - 51 tests passing

---

## Overview

The `sui_vesting` package provides a flexible vesting system that supports:

- **Fungible Token Vesting** (`vesting.move`): For any `Coin<T>` type
- **NFT Vesting** (`nft_vesting.move`): For NFTs and Position objects with `key + store` abilities

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

## Architecture

```
sui_vesting/
├── Move.toml
├── sources/
│   ├── core/
│   │   ├── access.move        # AdminCap, CreatorCap capabilities
│   │   └── errors.move        # Error code constants
│   ├── events.move            # Event structs and emit functions
│   ├── vesting.move           # Coin<T> vesting schedules
│   └── nft_vesting.move       # NFT/Position vesting schedules
└── tests/
    ├── test_coin.move         # Test coin for unit tests
    ├── test_nft.move          # Test NFT for unit tests
    ├── vesting_tests.move     # Coin vesting tests (32 tests)
    └── nft_vesting_tests.move # NFT vesting tests (19 tests)
```

---

## Use Cases

### Fungible Token Vesting
- Team token vesting (cliff + linear)
- Investor token lockups
- LP token vesting from AMM DEXes (FlowX, SuiDex)
- Instant unlocks for airdrops

### NFT Vesting
- CLMM Position vesting (Cetus, Turbos)
- NFT unlock schedules
- Any non-fungible asset with `key + store` abilities

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
if current_time < start_time:
    claimable = 0
elif current_time < start_time + cliff_duration:
    claimable = 0
elif current_time >= start_time + cliff_duration + vesting_duration:
    claimable = total_amount - claimed
else:
    elapsed_after_cliff = current_time - start_time - cliff_duration
    vested = total_amount * elapsed_after_cliff / vesting_duration
    claimable = vested - claimed

Example: 1.2B tokens, 6 month cliff, 12 month vesting
├── Month 0-6:   0 tokens claimable (cliff)
├── Month 6:     0 tokens (cliff just ended)
├── Month 7:     100M tokens (1/12 = 8.33%)
├── Month 12:    600M tokens (50%)
├── Month 18:    1.2B tokens (100% vested)
```

### 2. NFT Cliff Vesting

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    NFT CLIFF VESTING                                         │
└─────────────────────────────────────────────────────────────────────────────┘

NFTs cannot be partially vested. The NFT is locked until cliff ends:

    CLIFF PERIOD                    CLAIMABLE
    (NFT locked)                    (Full NFT)
    ├────────────────────────┬────────────────────┤
    │                        │                    │
 start_time              cliff_end          anytime after
    │                        │                    │
    ▼                        ▼                    ▼
┌───────────────────────┬────────────────────────────┐
│   NFT locked          │    NFT fully claimable     │
│   ░░░░░░░░░░░░░░░░░░░│    ████████████████████    │
└───────────────────────┴────────────────────────────┘
```

---

## Core Data Structures

### VestingConfig (Shared)

```move
/// Global configuration for the vesting platform
public struct VestingConfig has key {
    id: UID,
    /// Platform paused state
    paused: bool,
    /// Platform admin address
    admin: address,
    /// Total schedules created
    total_schedules: u64,
    /// Total tokens vested (across all token types, in units)
    total_vested_count: u64,
}
```

### VestingSchedule<T> (Owned by beneficiary)

```move
/// A vesting schedule for a specific token type
public struct VestingSchedule<phantom T> has key, store {
    id: UID,
    /// Address that created this schedule
    creator: address,
    /// Address that can claim tokens
    beneficiary: address,
    /// Remaining tokens in the schedule
    balance: Balance<T>,
    /// Original total amount
    total_amount: u64,
    /// Amount already claimed
    claimed: u64,
    /// Timestamp when vesting starts (ms)
    start_time: u64,
    /// Cliff duration in ms (tokens locked until cliff ends)
    cliff_duration: u64,
    /// Linear vesting duration in ms (after cliff)
    vesting_duration: u64,
    /// Whether the schedule can be revoked by creator
    revocable: bool,
    /// Whether the schedule has been revoked
    revoked: bool,
    /// Whether the schedule is paused
    paused: bool,
    /// Creation timestamp
    created_at: u64,
}
```

### NFTVestingSchedule<T> (Owned by beneficiary)

```move
/// NFT Vesting schedule - holds a single NFT/position until cliff ends
public struct NFTVestingSchedule<T: key + store> has key, store {
    id: UID,
    /// Address that created this schedule
    creator: address,
    /// Address that can claim the NFT
    beneficiary: address,
    /// The NFT/position being vested (Option because it can be claimed)
    nft: Option<T>,
    /// Timestamp when vesting starts (ms)
    start_time: u64,
    /// Cliff duration in ms (NFT locked until cliff ends)
    cliff_duration: u64,
    /// Whether the schedule can be revoked by creator (before cliff ends)
    revocable: bool,
    /// Whether the schedule has been revoked
    revoked: bool,
    /// Whether the NFT has been claimed
    claimed: bool,
    /// Whether the schedule is paused
    paused: bool,
    /// Creation timestamp
    created_at: u64,
}
```

### Access Capabilities

```move
/// Admin capability - can pause platform, pause schedules
public struct AdminCap has key, store {
    id: UID,
}

/// Creator capability - issued to schedule creators for management
public struct CreatorCap has key, store {
    id: UID,
    schedule_id: ID,
}
```

---

## Core Functions

### Coin Vesting (`vesting.move`)

| Function | Description |
|----------|-------------|
| `create_schedule<T>()` | Create a vesting schedule with custom parameters |
| `create_schedule_months<T>()` | Create schedule using months for cliff/vesting |
| `create_instant_schedule<T>()` | Create instant unlock schedule (no cliff/vesting) |
| `claim<T>()` | Claim available vested tokens |
| `claim_and_transfer<T>()` | Claim and transfer to beneficiary |
| `revoke<T>()` | Revoke schedule and return unvested tokens (creator only) |
| `revoke_and_transfer<T>()` | Revoke and transfer to creator |
| `set_platform_paused()` | Pause/unpause platform (admin only) |
| `set_schedule_paused<T>()` | Pause/unpause specific schedule (admin only) |
| `delete_empty_schedule<T>()` | Delete schedule after all tokens claimed |

### NFT Vesting (`nft_vesting.move`)

| Function | Description |
|----------|-------------|
| `create_nft_schedule<T>()` | Create NFT schedule with custom cliff |
| `create_nft_schedule_months<T>()` | Create schedule using months for cliff |
| `create_instant_nft_schedule<T>()` | Create instant unlock schedule (no cliff) |
| `claim_nft<T>()` | Claim the NFT after cliff ends |
| `claim_nft_and_transfer<T>()` | Claim and transfer NFT to beneficiary |
| `revoke_nft<T>()` | Revoke schedule before cliff ends (creator only) |
| `revoke_nft_and_transfer<T>()` | Revoke and transfer NFT to creator |
| `set_nft_schedule_paused<T>()` | Pause/unpause schedule (admin only) |
| `delete_empty_nft_schedule<T>()` | Delete schedule after NFT claimed/revoked |

### View Functions

```move
// Coin Vesting
public fun claimable<T>(schedule: &VestingSchedule<T>, clock: &Clock): u64
public fun vested<T>(schedule: &VestingSchedule<T>, clock: &Clock): u64
public fun remaining<T>(schedule: &VestingSchedule<T>): u64
public fun beneficiary<T>(schedule: &VestingSchedule<T>): address
public fun creator<T>(schedule: &VestingSchedule<T>): address
public fun total_amount<T>(schedule: &VestingSchedule<T>): u64
public fun claimed<T>(schedule: &VestingSchedule<T>): u64
public fun is_revocable<T>(schedule: &VestingSchedule<T>): bool
public fun is_revoked<T>(schedule: &VestingSchedule<T>): bool
public fun is_paused<T>(schedule: &VestingSchedule<T>): bool

// NFT Vesting
public fun is_claimable<T>(schedule: &NFTVestingSchedule<T>, clock: &Clock): bool
public fun time_until_claimable<T>(schedule: &NFTVestingSchedule<T>, clock: &Clock): u64
public fun has_nft<T>(schedule: &NFTVestingSchedule<T>): bool
public fun nft_beneficiary<T>(schedule: &NFTVestingSchedule<T>): address
public fun nft_is_claimed<T>(schedule: &NFTVestingSchedule<T>): bool
```

---

## Events

| Event | Module | Trigger |
|-------|--------|---------|
| `ScheduleCreated` | vesting | New vesting schedule created |
| `TokensClaimed` | vesting | Tokens claimed from schedule |
| `ScheduleRevoked` | vesting | Schedule revoked by creator |
| `ScheduleCompleted` | vesting | All tokens claimed |
| `PlatformPauseToggled` | vesting | Platform pause state changed |
| `SchedulePauseToggled` | vesting | Schedule pause state changed |
| `NFTScheduleCreated` | nft_vesting | New NFT schedule created |
| `NFTClaimed` | nft_vesting | NFT claimed from schedule |
| `NFTScheduleRevoked` | nft_vesting | NFT schedule revoked |

---

## Usage Examples

### Creating a Team Vesting Schedule

```move
// 1B tokens, 6 month cliff, 12 month linear vesting
let tokens = coin::mint<MYTOKEN>(1_000_000_000, ctx);
let creator_cap = vesting::create_schedule_months<MYTOKEN>(
    &mut config,
    tokens,
    team_member_address,
    6,    // 6 month cliff
    12,   // 12 month vesting
    true, // revocable
    &clock,
    ctx,
);
// Keep creator_cap to manage the schedule
```

### Creating LP Position Vesting (CLMM)

```move
// Vest a Cetus CLMM position for 6 months
let creator_cap = nft_vesting::create_nft_schedule_months<cetus::Position>(
    cetus_position,
    beneficiary_address,
    6,     // 6 month cliff
    false, // non-revocable
    &clock,
    ctx,
);
```

### Creating Instant Unlock

```move
// Airdrop: tokens claimable immediately
let tokens = coin::mint<MYTOKEN>(1_000_000, ctx);
let creator_cap = vesting::create_instant_schedule<MYTOKEN>(
    &mut config,
    tokens,
    recipient_address,
    &clock,
    ctx,
);
```

### Claiming Tokens (Beneficiary)

```move
// Beneficiary claims available tokens
let tokens = vesting::claim<MYTOKEN>(&mut schedule, &clock, ctx);
transfer::public_transfer(tokens, beneficiary);
```

### Claiming NFT (Beneficiary)

```move
// Beneficiary claims NFT after cliff
let nft = nft_vesting::claim_nft<Position>(&mut schedule, &clock, ctx);
transfer::public_transfer(nft, beneficiary);
```

### Revoking a Schedule (Creator)

```move
// Creator revokes unvested tokens
let returned_tokens = vesting::revoke<MYTOKEN>(
    &creator_cap,
    &mut schedule,
    &clock,
    ctx
);
// Beneficiary keeps vested portion, creator gets unvested
transfer::public_transfer(returned_tokens, creator);
```

---

## Time Constants

| Constant | Value (ms) | Description |
|----------|------------|-------------|
| `MS_PER_DAY` | 86,400,000 | Milliseconds in a day |
| `MS_PER_MONTH` | 2,592,000,000 | Milliseconds in 30 days |
| `MS_PER_YEAR` | 31,536,000,000 | Milliseconds in 365 days |

---

## Error Codes

### Coin Vesting Module (100-400)

| Code | Constant | Description |
|------|----------|-------------|
| 100 | `ENotClaimable` | Nothing available to claim |
| 101 | `EScheduleEmpty` | Cannot delete non-empty schedule |
| 105 | `EZeroAmount` | Cannot create schedule with 0 tokens |
| 107 | `EInvalidBeneficiary` | Invalid beneficiary address (zero) |
| 108 | `EAlreadyRevoked` | Schedule already revoked |
| 109 | `ENotRevocable` | Schedule is not revocable |
| 200 | `ENotBeneficiary` | Caller is not the beneficiary |
| 300 | `ESchedulePaused` | Schedule is paused |
| 400 | `ECreatorCapMismatch` | Wrong creator cap for this schedule |

### NFT Vesting Module (500+)

| Code | Constant | Description |
|------|----------|-------------|
| 501 | `EAlreadyClaimed` | NFT already claimed |
| 502 | `EZeroItems` | Cannot delete non-empty schedule |
| 503 | `EInvalidBeneficiary` | Invalid beneficiary address |
| 504 | `EAlreadyRevoked` | Schedule already revoked |
| 505 | `ENotRevocable` | Schedule is not revocable |
| 506 | `ENotBeneficiary` | Caller is not the beneficiary |
| 507 | `ESchedulePaused` | Schedule is paused |
| 508 | `ECreatorCapMismatch` | Wrong creator cap |
| 509 | `ECliffNotEnded` | Cliff period not yet ended |

---

## Security Features

| Feature | Implementation |
|---------|----------------|
| Only beneficiary can claim | `assert!(ctx.sender() == beneficiary)` |
| Creator-only revocation | Requires matching CreatorCap |
| Revocable flag immutable | Set at creation, cannot change |
| Balance integrity | Tokens in `Balance<T>`, not external |
| Cliff enforcement | Cannot claim before cliff ends |
| Overflow protection | u128 intermediate calculations |
| NFT revocation window | Can only revoke before cliff ends |
| Admin emergency pause | Can pause platform or individual schedules |

---

## DEX LP Token Support

| DEX | LP Type | Module to Use |
|-----|---------|---------------|
| FlowX | `Coin<LP<X,Y>>` | `vesting.move` |
| SuiDex | `Coin<LP>` | `vesting.move` |
| Cetus CLMM | `Position` NFT | `nft_vesting.move` |
| Turbos CLMM | `Position` NFT | `nft_vesting.move` |

---

## Test Coverage

**Total: 51 tests passing**

### Coin Vesting Tests (32 tests)

| Category | Tests |
|----------|-------|
| Schedule Creation | `test_create_schedule_basic`, `test_create_schedule_months`, `test_create_instant_schedule`, `test_create_schedule_zero_beneficiary_fails`, `test_create_schedule_zero_amount_fails` |
| Claiming | `test_claim_instant_unlock`, `test_claimable_during_cliff`, `test_linear_vesting_calculations`, `test_multiple_claims`, `test_claim_non_beneficiary_fails`, `test_claim_nothing_claimable_fails` |
| Revocation | `test_revoke_before_vesting`, `test_revoke_after_partial_vesting`, `test_claim_after_revoke`, `test_revoke_non_revocable_fails`, `test_revoke_wrong_cap_fails`, `test_double_revoke_fails` |
| Admin | `test_platform_pause`, `test_paused_platform_rejects_schedules`, `test_schedule_pause`, `test_paused_schedule_rejects_claims` |
| Edge Cases | `test_cliff_only_schedule`, `test_before_start_time`, `test_large_amounts_no_overflow`, `test_delete_empty_schedule`, `test_delete_non_empty_schedule_fails`, `test_time_constants` |

### NFT Vesting Tests (19 tests)

| Category | Tests |
|----------|-------|
| Schedule Creation | `test_create_nft_schedule_basic`, `test_create_nft_schedule_months`, `test_create_instant_nft_schedule`, `test_create_nft_schedule_zero_beneficiary_fails` |
| Claiming | `test_claim_nft_instant_unlock`, `test_nft_not_claimable_during_cliff`, `test_nft_claimable_after_cliff`, `test_claim_nft_non_beneficiary_fails`, `test_claim_nft_during_cliff_fails`, `test_double_claim_nft_fails` |
| Revocation | `test_revoke_nft_before_cliff`, `test_revoke_nft_after_cliff_fails`, `test_revoke_non_revocable_nft_fails`, `test_revoke_nft_wrong_cap_fails`, `test_double_revoke_nft_fails` |
| Admin | `test_admin_pause_nft_schedule`, `test_paused_nft_schedule_rejects_claims` |
| Edge Cases | `test_nft_schedule_with_custom_ticks`, `test_time_until_claimable_before_start`, `test_delete_empty_nft_schedule`, `test_delete_non_empty_nft_schedule_fails`, `test_nft_time_constants` |

---

## Integration with Launchpad

The vesting module integrates with the launchpad for:

1. **Token Vesting**: Launchpad graduates create team/investor token vesting schedules
2. **LP Vesting**: Locked LP tokens are vested to teams over time
3. **CLMM Support**: Concentrated liquidity positions from Cetus/Turbos can be vested

```
Launchpad Graduate
       │
       ├─────────────────────┬──────────────────┐
       ▼                     ▼                  ▼
  Team Tokens            LP Tokens         CLMM Position
       │                     │                  │
       ▼                     ▼                  ▼
  VestingSchedule<TOKEN>  VestingSchedule<LP>  NFTVestingSchedule<Position>
       │                     │                  │
       ▼                     ▼                  ▼
  claim() over time    claim() over time    claim_nft() after cliff
```

---

## Development Status

| Component | Status | Notes |
|-----------|--------|-------|
| Core vesting logic | DONE | `vesting.move` |
| NFT vesting | DONE | `nft_vesting.move` |
| Events | DONE | `events.move` |
| Access control | DONE | `access.move` |
| Coin vesting tests | DONE | 32 tests |
| NFT vesting tests | DONE | 19 tests |
| Documentation | DONE | This document |
| Integration with Launchpad | PENDING | |
| Audit | NOT STARTED | |

---

## Links

| Resource | Path |
|----------|------|
| Package Source | `sui_vesting/sources/` |
| Tests | `sui_vesting/tests/` |
| Architecture | [ARCHITECTURE.md](./ARCHITECTURE.md) |
| Launchpad Spec | [LAUNCHPAD.md](./LAUNCHPAD.md) |
| Status Tracker | [STATUS.md](./STATUS.md) |
