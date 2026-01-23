# Sui Vesting Package

Claim-based vesting module for Sui blockchain. Supports vesting for both fungible tokens (`Coin<T>`) and NFTs (CLMM positions).

**Status:** COMPLETE - 65 tests passing (integrated with Launchpad)

---

## Overview

The `sui_vesting` package provides a flexible vesting system that supports:

- **Fungible Token Vesting** (`vesting.move`): For any `Coin<T>` type (LP tokens, reward tokens, etc.)
- **NFT Vesting** (`nft_vesting.move`): For NFTs and Position objects with `key + store` abilities (CLMM positions)

---

## Integration with Launchpad

The vesting package is fully integrated with `sui_launchpad` for graduation LP distribution:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    GRADUATION LP DISTRIBUTION                                │
└─────────────────────────────────────────────────────────────────────────────┘

                         DEX LP TOKENS (100%)
                              │
    ┌─────────────────────────┼─────────────────────────┐
    │                         │                         │
    ▼                         ▼                         ▼
┌────────────┐         ┌────────────┐           ┌────────────┐
│  CREATOR   │         │  PROTOCOL  │           │    DAO     │
│   2.5%     │         │   2.5%     │           │   95%      │
│  (VESTED)  │         │  (DIRECT)  │           │  (CONFIG)  │
└─────┬──────┘         └─────┬──────┘           └─────┬──────┘
      │                      │                        │
      ▼                      ▼                        ▼
┌────────────┐         ┌────────────┐           ┌────────────┐
│sui_vesting │         │  Protocol  │           │ Burn/DAO/  │
│::vesting:: │         │  Treasury  │           │ Stake/Vest │
│create_     │         │  (Direct)  │           │ (Config)   │
│schedule()  │         └────────────┘           └────────────┘
└────────────┘
     │
     ▼
VestingSchedule<LP>
  - 6 month cliff
  - 12 month linear
  - Non-revocable
```

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
         │ Imported by:
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
    ├── vesting_tests.move     # Coin vesting tests
    ├── nft_vesting_tests.move # NFT vesting tests
    └── strict_vesting_tests.move # Strict integration tests
```

---

## Use Cases

### Fungible Token Vesting
- **LP Token Vesting** - Creator LP at graduation (primary use case)
- Team token vesting (cliff + linear)
- Investor token lockups
- Instant unlocks for airdrops

### NFT Vesting
- **CLMM Position Vesting** - Cetus/FlowX positions at graduation
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

Example: Creator LP vesting - 6 month cliff, 12 month vesting
├── Month 0-6:   0 LP claimable (cliff)
├── Month 6:     0 LP (cliff just ended)
├── Month 7:     8.33% LP claimable (1/12 of vesting)
├── Month 12:    50% LP claimable
├── Month 18:    100% LP claimable (fully vested)
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

Example: CLMM Position NFT - 6 month cliff
├── Month 0-6:  Position locked (cannot claim or transfer)
├── Month 6+:   Position fully claimable
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

---

## Admin Configurable Parameters

The launchpad admin can configure vesting parameters:

| Parameter | Default | Range | Admin Function |
|-----------|---------|-------|----------------|
| `creator_lp_bps` | 250 (2.5%) | 0-3000 (30%) | `set_creator_lp_bps()` |
| `protocol_lp_bps` | 250 (2.5%) | 0-3000 (30%) | `set_protocol_lp_bps()` |
| `dao_lp_bps` | 9500 (95%) | AUTO | _(calculated)_ |
| `creator_lp_cliff_ms` | 6 months | >= min_lock | `set_creator_lp_vesting()` |
| `creator_lp_vesting_ms` | 12 months | >= 0 | |
| `dao_lp_destination` | 0 (burn) | 0-3 | `set_dao_lp_destination()` |
| `dao_lp_cliff_ms` | 0 | >= 0 | `set_dao_lp_vesting()` |
| `dao_lp_vesting_ms` | 0 | >= 0 | |

### DAO LP Destination Options

| Value | Constant | Action |
|-------|----------|--------|
| 0 | `LP_DEST_BURN` | Burn (transfer to 0x0) |
| 1 | `LP_DEST_DAO` | Direct to DAO treasury |
| 2 | `LP_DEST_STAKE` | Send to staking contract |
| 3 | `LP_DEST_VEST` | Vest to DAO treasury |

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
| 505 | `ENotRevocable` | Schedule is not revocable / NFT claimable |
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

## Test Coverage

**Total: 65 tests passing**

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

### Strict Integration Tests (14 tests)

| Category | Tests |
|----------|-------|
| LP Vesting | `test_strict_lp_vesting_full_lifecycle`, `test_strict_multiple_lp_vesting_parallel` |
| External Coin | `test_strict_external_coin_vesting`, `test_strict_external_coin_revoke_before_cliff`, `test_strict_external_coin_revoke_during_vesting` |
| Position NFT | `test_strict_position_nft_vesting_lifecycle`, `test_strict_position_nft_revoke_before_cliff`, `test_strict_position_nft_revoke_after_cliff_fails` |
| External NFT | `test_strict_external_nft_vesting` |
| Edge Cases | `test_strict_instant_cliff`, `test_strict_long_vesting_period`, `test_strict_non_beneficiary_cannot_claim`, `test_strict_cannot_claim_zero`, `test_strict_nft_cannot_claim_during_cliff` |

---

## DEX LP Token Support

| DEX | LP Type | Module to Use |
|-----|---------|---------------|
| SuiDex | `Coin<LP>` | `vesting.move` |
| FlowX | `Coin<LP<X,Y>>` | `vesting.move` |
| Cetus CLMM | `Position` NFT | `nft_vesting.move` |
| Turbos CLMM | `Position` NFT | `nft_vesting.move` |
| FlowX CLMM | `Position` NFT | `nft_vesting.move` |

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
| Strict tests | DONE | 14 tests |
| Launchpad Integration | DONE | Full PTB flow documented |
| Documentation | DONE | This document |
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
