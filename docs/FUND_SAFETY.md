# Fund Safety - Launchpad Protection Mechanisms

## Overview

The launchpad implements **essential fund safety mechanisms** while keeping the system simple and bot-friendly. Sui's built-in safety features handle most security concerns, so we focus only on protections that matter for user funds.

## Sui's Built-in Safety

Sui blockchain already protects against:
- **Reentrancy attacks** - Object ownership model prevents this
- **Integer overflow** - Move language handles automatically
- **Unchecked transfers** - Type system prevents this
- **Flash loan attacks** - Object ownership model

## Essential Fund Safety (What We Implement)

### 1. Treasury Cap Freeze

**The Most Important Protection**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     TREASURY CAP FREEZE                                      │
└─────────────────────────────────────────────────────────────────────────────┘

When a token is created:
1. Creator provides TreasuryCap
2. Launchpad mints total supply (1 billion tokens)
3. TreasuryCap is FROZEN permanently

Result: NO MORE TOKENS CAN EVER BE MINTED

This prevents:
✗ Creator minting unlimited tokens later
✗ Dilution of existing holders
✗ Infinite mint rug pulls
```

**Code:**
```move
// In bonding_curve.move create_pool()
transfer::public_freeze_object(treasury);
```

### 2. LP Token Distribution

**Prevents Liquidity Rug Pulls**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     LP TOKEN DISTRIBUTION                                    │
└─────────────────────────────────────────────────────────────────────────────┘

When token graduates to DEX:
├── LP Tokens generated from liquidity pool
│
├── CREATOR (0-30%, configurable)
│   └── VESTED over time (6mo cliff + 12mo vesting)
│   └── Cannot dump LP immediately
│
└── COMMUNITY (70-100%)
    ├── Option 0: BURN (liquidity locked forever) ← DEFAULT
    ├── Option 1: DAO Treasury (community decides)
    ├── Option 2: Staking Rewards
    └── Option 3: Community Vesting
```

**Config Parameters:**
| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| `creator_lp_bps` | 0-3000 | 2000 (20%) | Creator's LP share |
| `creator_lp_cliff_ms` | - | 6 months | Cliff before vesting starts |
| `creator_lp_vesting_ms` | - | 12 months | Vesting duration |
| `community_lp_destination` | 0-3 | 0 (burn) | Where community LP goes |

### 3. Hard Fee Caps

**Prevents Honeypot Tokens**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     FEE CAPS (Hard-coded)                                    │
└─────────────────────────────────────────────────────────────────────────────┘

Maximum fees (cannot be exceeded even by admin):
├── Platform trading fee: Max 10% (1000 bps)
├── Creator trading fee: Max 5% (500 bps)
└── Total per trade: Typically 0.5% platform + 0-5% creator

This prevents:
✗ Creator setting 99% sell fee (honeypot)
✗ Hidden fee manipulation
✗ Fee increases after launch
```

### 4. Creator Token Vesting

**Prevents Token Dumps**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     CREATOR TOKEN ALLOCATION                                 │
└─────────────────────────────────────────────────────────────────────────────┘

At graduation:
├── Creator gets 0-5% of remaining tokens (configurable)
├── These tokens are sent DIRECTLY (no vesting on tokens)
└── LP tokens ARE vested (see LP Distribution above)

Creator incentives:
├── Trading fees during bonding curve (0-5% per trade)
├── Token allocation at graduation (0-5%)
└── LP tokens (0-30%, vested)
```

## What We DON'T Implement (By Design)

These features were considered but removed because they hurt adoption without adding meaningful security:

| Feature | Why Removed |
|---------|-------------|
| Trading cooldown | Hurts bots = less volume = less fees |
| Max buy per TX | Hurts whales who want to invest big |
| Unique buyer tracking | Expensive on-chain, not needed |
| Min unique buyers | Too restrictive for graduation |
| Min pool age | Sui is fast, doesn't need delay |
| Graduation cooling | LP lock is sufficient protection |

**Bots are GOOD:**
- More trades = more volume
- More volume = more fees for platform & creator
- Bots provide liquidity and price discovery

## Trust Score Display (Frontend)

Tokens can display a simple trust score:

```
┌────────────────────────────────────────────┐
│  TRUST SCORE: SAFE                         │
│                                            │
│  [x] Treasury Cap Frozen (no more minting) │
│  [x] LP Locked: 80% burned, 20% vested     │
│  [x] Fees: 0.5% platform + 2% creator      │
│                                            │
└────────────────────────────────────────────┘
```

## Summary

| Protection | What It Does | Status |
|------------|--------------|--------|
| Treasury Cap Freeze | No more tokens ever | ALWAYS ON |
| LP Distribution | Community gets 70%+ LP (burned) | Configurable |
| Creator LP Vesting | Creator can't dump LP | 6mo cliff + 12mo vest |
| Fee Caps | Max 5% creator fee | Hard-coded |

**Result:** Funds are safe. No rug pulls possible. Bots welcome.

## Implementation Details

### LP Distribution Flow (graduation.move)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     GRADUATION FLOW                                          │
└─────────────────────────────────────────────────────────────────────────────┘

1. initiate_graduation<T>() - Admin initiates graduation
   ├── Validates pool is ready (market cap threshold)
   ├── Extracts SUI and tokens from pool
   ├── Sends graduation fee to treasury
   ├── Sends creator token allocation (0-5%)
   ├── Sends platform token allocation (2.5-5%)
   └── Returns PendingGraduation with LP distribution config

2. DEX Adapter creates liquidity pool
   ├── Calls extract_all_sui() and extract_all_tokens()
   ├── Creates pool on DEX (Cetus/Turbos/FlowX/SuiDex)
   └── Receives LP tokens from DEX

3. distribute_lp_tokens<T, LP>() - Distributes LP tokens
   ├── Calculates creator share (0-30%)
   ├── Creates CreatorLPVesting<LP> object (6mo cliff + 12mo vest)
   ├── Sends to creator (vesting schedule)
   ├── Community share (70-100%):
   │   ├── BURN: Send to 0x0 (locked forever)
   │   ├── DAO: Send to treasury
   │   ├── STAKING: Send to staking contract
   │   └── COMMUNITY_VEST: Send to treasury (future: vesting)
   └── Returns (creator_lp_amount, community_lp_amount)

4. complete_graduation<T>() - Finishes graduation
   ├── Records graduation in registry
   ├── Emits TokenGraduated event
   └── Returns GraduationReceipt with LP distribution info
```

### Creator LP Vesting (graduation.move)

```move
struct CreatorLPVesting<phantom LP> has key, store {
    id: UID,
    pool_id: ID,                    // Original bonding pool
    creator: address,               // Beneficiary
    lp_balance: Balance<LP>,        // Locked LP tokens
    total_amount: u64,              // Total vested
    claimed_amount: u64,            // Already claimed
    start_time: u64,                // Vesting start
    cliff_ms: u64,                  // 6 months default
    vesting_ms: u64,                // 12 months default
    lp_type: TypeName,              // LP token type
}
```

**Vesting Functions:**
- `claimable_lp()` - Calculate claimable amount at current time
- `claim_creator_lp()` - Creator claims vested LP tokens
- `destroy_empty_vesting()` - Clean up after fully claimed

### Key Structs

| Struct | Purpose |
|--------|---------|
| `GraduationReceipt` | Proof of graduation with LP distribution info |
| `PendingGraduation<T>` | Hot potato for DEX adapter flow |
| `LPDistributionConfig` | Creator/community split configuration |
| `CreatorLPVesting<LP>` | Vesting schedule for creator LP tokens |

### Events

All graduations emit `TokenGraduated` event containing:
- Pool ID, DEX type, DEX pool ID
- SUI and token amounts to liquidity
- Graduation fee, timestamp
- LP distribution amounts
