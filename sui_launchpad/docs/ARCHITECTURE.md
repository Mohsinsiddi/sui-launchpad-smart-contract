# Architecture - Sui Launchpad

**Last Updated:** January 2026

---

## Overview

Sui Launchpad is a token launch platform with:
1. **Bonding Curve** - Fair price discovery through algorithmic trading
2. **Graduation** - Automatic DEX listing when market cap threshold reached
3. **Fund Safety** - Built-in protections against rugs and exploits

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SUI LAUNCHPAD FLOW                                  │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────┐     ┌──────────────────┐     ┌──────────────────────────┐
│  1. TOKEN        │     │  2. BONDING      │     │  3. GRADUATION           │
│     CREATION     │ ──▶ │     CURVE        │ ──▶ │     TO DEX               │
│                  │     │     TRADING      │     │                          │
└──────────────────┘     └──────────────────┘     └──────────────────────────┘
```

---

## Phase 1: Token Creation

### Function: `bonding_curve::create_pool<T>()`

**Location:** `sources/bonding_curve.move:118`

```
Creator calls create_pool<T>() with:
├── TreasuryCap<T>     (fresh, 0 supply - REQUIRED)
├── CoinMetadata<T>    (name, symbol, decimals)
├── creator_fee_bps    (0-500 = 0-5% per trade)
└── payment            (creation fee in SUI)
```

### Token Distribution at Creation

```
┌─────────────────────────────────────────────────────────────────┐
│                    TOKEN MINTING                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Total Supply: 1,000,000,000 tokens (configurable)             │
│                                                                 │
│   ├── Platform Allocation (1%)                                  │
│   │   └── 10,000,000 tokens → Treasury address                  │
│   │                                                             │
│   └── Pool Allocation (99%)                                     │
│       └── 990,000,000 tokens → BondingPool for trading          │
│                                                                 │
│   TreasuryCap: FROZEN after minting                             │
│   └── No more tokens can EVER be minted                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Fund Safety at Creation

| Protection | Implementation |
|------------|----------------|
| No pre-mint | `assert!(total_supply(&treasury_cap) == 0)` |
| Fixed supply | Treasury cap frozen after mint |
| Max creator fee | `MAX_CREATOR_FEE_BPS = 500` (5%) |
| Creation fee | Sent to platform treasury |

---

## Phase 2: Bonding Curve Trading

### Functions
- `bonding_curve::buy()` - Buy tokens with SUI
- `bonding_curve::sell()` - Sell tokens for SUI

**Location:** `sources/bonding_curve.move:200+`

### Bonding Curve Formula

```
Linear Curve: price = base_price + (slope × circulating_supply)

   Price
     ▲
     │                                          ┌────────────┐
     │                                     ●────│ Graduation │
     │                                ●         │ Threshold  │
     │                           ●              └────────────┘
     │                      ●
     │                 ●         price = base + slope × supply
     │            ●
     │       ●
     │  ●
     └────────────────────────────────────────────▶ Supply
```

### Buy Flow

```
┌─────────┐                    ┌─────────────────────────────────────────┐
│  Buyer  │ ──── SUI ────────▶ │              BondingPool                │
└─────────┘                    ├─────────────────────────────────────────┤
                               │                                         │
     ◀──── Tokens ──────────── │  1. Calculate tokens_out from SUI      │
                               │  2. Deduct fees:                        │
                               │     ├── Platform: 0.5% → Treasury       │
                               │     └── Creator: 0-5% → Creator addr    │
                               │  3. Add net SUI to pool balance         │
                               │  4. Transfer tokens to buyer            │
                               │  5. Update circulating_supply           │
                               │                                         │
                               └─────────────────────────────────────────┘
```

### Sell Flow

```
┌─────────┐                    ┌─────────────────────────────────────────┐
│ Seller  │ ──── Tokens ─────▶ │              BondingPool                │
└─────────┘                    ├─────────────────────────────────────────┤
                               │                                         │
     ◀──── SUI ──────────────  │  1. Calculate gross_sui from tokens     │
                               │  2. Deduct fees:                        │
                               │     ├── Platform: 0.5%                  │
                               │     └── Creator: 0-5%                   │
                               │  3. Return tokens to pool               │
                               │  4. Transfer net SUI to seller          │
                               │  5. Update circulating_supply           │
                               │                                         │
                               └─────────────────────────────────────────┘
```

### Fee Structure

| Fee | Rate | Recipient | Deducted From |
|-----|------|-----------|---------------|
| Platform Fee | 0.5% (50 bps) | Treasury | Each trade |
| Creator Fee | 0-5% (0-500 bps) | Token Creator | Each trade |

---

## Phase 3: Graduation to DEX

When `sui_balance >= graduation_threshold`, admin triggers graduation.

### Graduation Architecture (PTB)

**Why PTB (Programmable Transaction Block)?**

DEX router functions are `public entry` - they cannot be called from Move code directly. PTB allows combining multiple operations atomically.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ATOMIC PTB TRANSACTION                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Command 1: graduation::initiate_graduation()                               │
│  ├── Validate pool reached threshold                                        │
│  ├── Mark pool as graduated                                                 │
│  ├── Calculate fee splits                                                   │
│  ├── Send graduation fee (SUI) to treasury                                  │
│  ├── Send creator tokens to creator                                         │
│  ├── Send platform tokens to treasury                                       │
│  └── Return PendingGraduation<T> (hot potato)                               │
│                                                                             │
│  Command 2: graduation::extract_all_sui()                                   │
│  └── Extract Coin<SUI> from PendingGraduation                               │
│                                                                             │
│  Command 3: graduation::extract_all_tokens()                                │
│  └── Extract Coin<T> from PendingGraduation                                 │
│                                                                             │
│  Command 4: DEX create_pair / create_pool (varies by DEX)                   │
│  ├── SuiDex:  suidex_router::create_pair<T, SUI>()                          │
│  ├── Cetus:   pool_creator::create_pool_v3<SUI, T>()                        │
│  └── FlowX:   flowx_pool_manager::create_and_initialize_pool<T, SUI>()      │
│                                                                             │
│  Command 5: DEX add_liquidity (varies by DEX)                               │
│  ├── SuiDex:  add_liquidity() → Returns Coin<LPCoin<T, SUI>>                │
│  ├── Cetus:   (included in create_pool_v3) → Returns Position NFT           │
│  └── FlowX:   open_position() + add_liquidity() → Returns Position NFT      │
│                                                                             │
│  Command 6: graduation::complete_graduation()                               │
│  ├── Consume PendingGraduation (hot potato)                                 │
│  ├── Record in Registry                                                     │
│  ├── Emit TokenGraduated event                                              │
│  └── Return GraduationReceipt                                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Token Distribution at Graduation

**Location:** `sources/graduation.move:123-210`

```
┌─────────────────────────────────────────────────────────────────┐
│                 GRADUATION DISTRIBUTION                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FROM: BondingPool                                              │
│  ├── sui_balance: 100 SUI (example)                             │
│  └── token_balance: 800M tokens (unsold)                        │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  SUI Distribution:                                              │
│  ├── 5% (5 SUI) → Treasury (graduation_fee)                     │
│  └── 95% (95 SUI) → DEX liquidity                               │
│                                                                 │
│  Token Distribution:                                            │
│  ├── 0-5% (0-40M) → Creator (creator_graduation_bps)            │
│  ├── 2.5-5% (20-40M) → Treasury (platform_graduation_bps)       │
│  └── ~92% (720M) → DEX liquidity                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### DEX-Specific Outputs

| DEX | Pool Type | LP Token Type | Notes |
|-----|-----------|---------------|-------|
| SuiDex | AMM (x*y=k) | `Coin<LPCoin<T, SUI>>` | Fungible LP token |
| Cetus | CLMM | `Position` NFT | Concentrated liquidity |
| FlowX | CLMM | `Position` NFT | Concentrated liquidity |
| Turbos | CLMM | `Position` NFT | Concentrated liquidity |

---

## LP Token Distribution (Planned)

**Status:** Code exists but NOT integrated

```
┌─────────────────────────────────────────────────────────────────┐
│                LP TOKEN DISTRIBUTION (PLANNED)                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Total LP Tokens (100%)                                        │
│                                                                 │
│   ├── Creator: 0-30% (creator_lp_bps)                           │
│   │   └── VESTED via CreatorLPVesting<LP>                       │
│   │       ├── Cliff: 6 months (configurable)                    │
│   │       └── Vesting: 12 months linear (configurable)          │
│   │                                                             │
│   └── Community: 70-100%                                        │
│       └── Destination (configurable):                           │
│           ├── BURN (0x0) - locked forever [DEFAULT]             │
│           ├── DAO treasury                                      │
│           ├── Staking contract                                  │
│           └── Community vesting                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Function:** `graduation::distribute_lp_tokens()`
**Location:** `sources/graduation.move:443`

---

## Module Dependency Graph

```
                                ┌─────────────┐
                                │   config    │
                                │  (shared)   │
                                └──────┬──────┘
                                       │
           ┌───────────────────────────┼───────────────────────────┐
           │                           │                           │
           ▼                           ▼                           ▼
    ┌─────────────┐             ┌─────────────┐             ┌─────────────┐
    │   access    │             │    math     │             │   events    │
    │ (AdminCap)  │             │ (pure math) │             │  (emits)    │
    └──────┬──────┘             └──────┬──────┘             └──────┬──────┘
           │                           │                           │
           └───────────────────────────┼───────────────────────────┘
                                       │
                                       ▼
                              ┌─────────────────┐
                              │  bonding_curve  │
                              │  (BondingPool)  │
                              └────────┬────────┘
                                       │
                                       ▼
                              ┌─────────────────┐
                              │   graduation    │
                              │ (PendingGrad)   │
                              └────────┬────────┘
                                       │
           ┌───────────────────────────┼───────────────────────────┐
           │                           │                           │
           ▼                           ▼                           ▼
    ┌─────────────┐             ┌─────────────┐             ┌─────────────┐
    │   suidex    │             │    cetus    │             │    flowx    │
    │  (adapter)  │             │  (adapter)  │             │  (adapter)  │
    └─────────────┘             └─────────────┘             └─────────────┘
                                       │
                                       ▼
                              ┌─────────────────┐
                              │    registry     │
                              │ (tracks pools)  │
                              └─────────────────┘
```

---

## Shared Objects

| Object | Module | Description |
|--------|--------|-------------|
| `LaunchpadConfig` | config | Platform settings, fees, thresholds |
| `Registry` | registry | Pool tracking, graduation records |
| `BondingPool<T>` | bonding_curve | Per-token trading pool |

## Owned Objects

| Object | Module | Description |
|--------|--------|-------------|
| `AdminCap` | access | Admin privileges |
| `OperatorCap` | access | Limited operator privileges |
| `GraduationReceipt` | graduation | Proof of graduation |
| `CreatorLPVesting<LP>` | graduation | LP token vesting schedule |

---

## Security Model

### Access Control

```
┌─────────────────────────────────────────────────────────────────┐
│                      ACCESS CONTROL                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  AdminCap (Single owner)                                        │
│  ├── Pause/unpause platform                                     │
│  ├── Pause/unpause individual pools                             │
│  ├── Update config parameters                                   │
│  ├── Emergency withdrawal (only when paused)                    │
│  └── Initiate graduation                                        │
│                                                                 │
│  OperatorCap (Can have multiple)                                │
│  └── Limited operations (future use)                            │
│                                                                 │
│  Anyone                                                         │
│  ├── Create pool (with TreasuryCap + fee)                       │
│  ├── Buy tokens                                                 │
│  └── Sell tokens                                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Fund Safety Guarantees

| Threat | Protection | Implementation |
|--------|------------|----------------|
| Infinite mint | Treasury cap frozen | `treasury_cap_frozen = true` |
| Honeypot (high fees) | Max fee caps | `MAX_CREATOR_FEE_BPS = 500` |
| Rug pull (LP dump) | LP vesting | `CreatorLPVesting<LP>` (not integrated) |
| Reentrancy | Lock flag | `locked` in BondingPool |
| Flash loan voting | N/A | No governance yet |
| Admin abuse | Emergency requires pause | Can't drain active pools |

---

## Events

**Location:** `sources/events.move`

| Event | When | Data |
|-------|------|------|
| `PoolCreated` | Pool creation | pool_id, creator, token_type |
| `TokensBought` | Buy | pool_id, buyer, sui_in, tokens_out |
| `TokensSold` | Sell | pool_id, seller, tokens_in, sui_out |
| `PoolPaused` | Admin pause | pool_id |
| `PoolUnpaused` | Admin unpause | pool_id |
| `TokenGraduated` | Graduation | pool_id, dex_type, dex_pool_id, amounts |

---

## Configuration Defaults

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `creation_fee` | 0.5 SUI | Any | Fee to create pool |
| `trading_fee_bps` | 50 | 0-1000 | Platform fee (0.5%) |
| `graduation_threshold` | 69,000 SUI | Any | Market cap to graduate |
| `graduation_fee_bps` | 500 | 0-1000 | Fee on graduation (5%) |
| `creator_graduation_bps` | 0 | 0-500 | Creator token share (0-5%) |
| `platform_graduation_bps` | 250 | 250-500 | Platform token share (2.5-5%) |
| `creator_lp_bps` | 2000 | 0-3000 | Creator LP share (0-30%) |
| `default_total_supply` | 1B | Any | Tokens per pool |
| `default_base_price` | 1000 | Any | Starting price |
| `default_slope` | 1M | Any | Price increase rate |
