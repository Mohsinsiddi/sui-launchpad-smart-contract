# sui_vesting

A flexible token and NFT vesting system for Sui Move with cliff and linear vesting support.

## Overview

sui_vesting enables creating vesting schedules for both fungible tokens and NFTs. It supports:

- **Cliff + Linear vesting**: Lock tokens for a cliff period, then release linearly
- **Instant unlock**: Release all tokens after cliff ends
- **NFT vesting**: Vest CLMM positions, NFTs, and other non-fungible assets
- **Revocable schedules**: Creator can reclaim unvested tokens
- **Origin tracking**: Track if schedule was created via launchpad

## Architecture

```
sui_vesting/
├── sources/
│   ├── vesting.move          # Fungible token vesting
│   ├── nft_vesting.move      # NFT/position vesting
│   ├── events.move           # Event definitions
│   └── core/
│       ├── access.move       # Capability definitions
│       └── errors.move       # Error codes
```

## Key Concepts

### Vesting Formula

```
if current_time < start_time:
    claimable = 0
elif current_time < start_time + cliff:
    claimable = 0
elif current_time >= start_time + cliff + vesting_duration:
    claimable = total_amount - already_claimed
else:
    elapsed = current_time - (start_time + cliff)
    vested = total_amount * elapsed / vesting_duration
    claimable = vested - already_claimed
```

### VestingSchedule (Fungible Tokens)

Each schedule is an owned object transferred to the beneficiary.

```move
public struct VestingSchedule<phantom T> has key, store {
    id: UID,
    creator: address,
    beneficiary: address,
    balance: Balance<T>,       // Remaining tokens
    total_amount: u64,
    claimed: u64,
    start_time: u64,           // When vesting starts
    cliff_duration: u64,       // Lock period
    vesting_duration: u64,     // Linear release period
    revocable: bool,
    revoked: bool,
    paused: bool,
    created_at: u64,
}
```

### NFTVestingSchedule (Non-Fungible Assets)

For CLMM positions, NFTs, and other non-fungible assets.

```move
public struct NFTVestingSchedule<T: key + store> has key, store {
    id: UID,
    creator: address,
    beneficiary: address,
    nft: Option<T>,            // The locked NFT
    start_time: u64,
    cliff_duration: u64,       // NFT unlocks after cliff
    revocable: bool,
    revoked: bool,
    claimed: bool,
    paused: bool,
    created_at: u64,
}
```

## Creating Vesting Schedules

### Token Vesting

```move
let creator_cap = vesting::create_schedule<T>(
    &mut config,
    tokens,              // Coin<T> to vest
    beneficiary,         // Address that can claim
    start_time,          // When vesting starts (ms)
    cliff_duration,      // Cliff period (ms)
    vesting_duration,    // Linear vesting period (ms)
    revocable,           // Can creator revoke?
    clock,
    ctx,
);
```

### Token Vesting with Origin Tracking

```move
let creator_cap = vesting::create_schedule_with_origin<T>(
    &mut config,
    tokens,
    beneficiary,
    start_time,
    cliff_duration,
    vesting_duration,
    revocable,
    origin,              // 0=independent, 1=launchpad, 2=partner
    origin_id,           // Optional<ID> linking to source
    clock,
    ctx,
);
```

### NFT Vesting

```move
let creator_cap = nft_vesting::create_nft_schedule<PositionNFT>(
    position_nft,        // NFT to lock
    beneficiary,
    start_time,
    cliff_duration,      // NFT unlocks after cliff ends
    revocable,
    clock,
    ctx,
);
```

## Claiming Tokens

### Claim from Token Schedule

```move
let claimed_coins = vesting::claim<T>(
    &mut schedule,
    clock,
    ctx,
);
```

### Claim NFT

```move
let nft = nft_vesting::claim_nft<PositionNFT>(
    &mut schedule,
    clock,
    ctx,
);
```

## Revoking Schedules

Only revocable schedules can be revoked, and only by the creator.

### Revoke Token Schedule

```move
let returned_tokens = vesting::revoke<T>(
    &creator_cap,
    &mut schedule,
    clock,
    ctx,
);
```

### Revoke NFT Schedule

```move
let nft = nft_vesting::revoke_nft<PositionNFT>(
    &creator_cap,
    &mut schedule,
    clock,
    ctx,
);
```

## Vesting Patterns

### 6-Month Cliff + 12-Month Linear

```move
let cliff = MS_PER_MONTH * 6;    // 6 months cliff
let vesting = MS_PER_MONTH * 12; // 12 months linear vesting

vesting::create_schedule<T>(
    config, tokens, beneficiary,
    start_time,
    cliff,
    vesting,
    true,  // revocable
    clock, ctx,
);
```

### Instant Unlock After Cliff

```move
// Tokens fully unlock after 3 months
vesting::create_schedule<T>(
    config, tokens, beneficiary,
    start_time,
    MS_PER_MONTH * 3,  // 3 month cliff
    0,                  // No linear vesting
    false,              // Non-revocable
    clock, ctx,
);
```

### LP Position Vesting (CLMM)

```move
// Vest CLMM position NFT for 6 months
nft_vesting::create_nft_schedule<CetusPosition>(
    position_nft,
    creator_address,
    start_time,
    MS_PER_MONTH * 6,  // 6 month cliff
    true,               // Revocable
    clock, ctx,
);
```

## Origin Tracking

Schedules can be tagged with their creation origin for analytics:

```move
// Origin constants
const ORIGIN_INDEPENDENT: u8 = 0;  // Direct creation
const ORIGIN_LAUNCHPAD: u8 = 1;    // Created via launchpad graduation
const ORIGIN_PARTNER: u8 = 2;      // Created via partner integration

// Access via events module
sui_vesting::events::origin_independent()
sui_vesting::events::origin_launchpad()
sui_vesting::events::origin_partner()
```

## Capabilities

### AdminCap

Platform-level admin capability for:
- Pausing/unpausing the platform
- Pausing individual schedules

### CreatorCap

Schedule-level capability for:
- Revoking the schedule (if revocable)
- Managing schedule settings

## Events

```move
// Schedule events
ScheduleCreated { schedule_id, token_type, creator, beneficiary, total_amount, ... }
TokensClaimed { schedule_id, token_type, beneficiary, amount, total_claimed, remaining }
ScheduleRevoked { schedule_id, token_type, revoker, beneficiary, amount_returned, ... }
ScheduleCompleted { schedule_id, token_type, beneficiary, total_claimed }

// NFT events
NFTScheduleCreated { schedule_id, creator, beneficiary, nft_id, start_time, ... }
NFTClaimed { schedule_id, beneficiary, nft_id, timestamp }
NFTScheduleRevoked { schedule_id, revoker, nft_id, timestamp }

// Admin events
PlatformPauseToggled { paused, admin, timestamp }
SchedulePauseToggled { schedule_id, paused, admin, timestamp }
```

## Error Codes

| Code | Error |
|------|-------|
| 100 | ENotClaimable - Nothing available to claim |
| 101 | EScheduleEmpty - Schedule has no remaining tokens |
| 105 | EZeroAmount - Cannot create schedule with zero tokens |
| 107 | EInvalidBeneficiary - Invalid beneficiary address |
| 108 | EAlreadyRevoked - Schedule already revoked |
| 109 | ENotRevocable - Schedule is not revocable |
| 200 | ENotBeneficiary - Caller is not the beneficiary |
| 300 | ESchedulePaused - Schedule is paused |
| 400 | ECreatorCapMismatch - Wrong CreatorCap for schedule |
| 501-509 | NFT vesting specific errors |

## Time Constants

```move
const MS_PER_DAY: u64 = 86_400_000;
const MS_PER_MONTH: u64 = 2_592_000_000;    // 30 days
const MS_PER_YEAR: u64 = 31_536_000_000;    // 365 days
```

## Integration with Launchpad

At graduation, creator LP tokens can be vested:

```move
// In graduation PTB:
let creator_cap = vesting::create_schedule_with_origin<LP<T, SUI>>(
    &mut vesting_config,
    creator_lp_tokens,
    creator_address,
    current_time,          // start now
    MS_PER_MONTH * 6,      // 6 month cliff
    MS_PER_MONTH * 12,     // 12 month linear
    false,                 // non-revocable
    sui_vesting::events::origin_launchpad(),
    option::some(pool_id),
    clock,
    ctx,
);
```

## Building & Testing

```bash
cd sui_vesting
sui move build
sui move test
```

## License

Apache 2.0
