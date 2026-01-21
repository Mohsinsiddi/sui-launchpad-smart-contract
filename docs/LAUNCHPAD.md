# Launchpad - Detailed Specification

## Overview

The Launchpad is the core product that enables permissionless token creation and fair launch trading via bonding curves. When tokens reach a target market cap, they "graduate" to a real DEX with locked liquidity.

---

## Module Structure

```
sui-launchpad/
├── Move.toml
└── sources/
    │
    ├── core/                        # Internal utilities
    │   ├── math.move               # Safe math operations
    │   ├── access.move             # Capability definitions
    │   └── errors.move             # Error codes
    │
    ├── config.move                 # Platform configuration
    ├── registry.move               # Token registry
    ├── bonding_curve.move          # Trading pool & curve logic
    ├── graduation.move             # DEX migration logic
    ├── vesting.move                # PLACEHOLDER → see sui_vesting
    │
    ├── dex_adapters/               # DEX integrations
    │   ├── cetus.move
    │   ├── turbos.move
    │   ├── flowx.move
    │   └── suidex.move
    │
    └── events.move                 # All events

NOTE: Vesting is a standalone package (sui_vesting) for reusability.
      See VESTING.md for full specification.
```

---

## Token Creation Flow (PBT - Publish By Template)

### Why PBT?

On Sui, each token type requires its own Move module with a unique `struct`. You cannot dynamically create new coin types at runtime. Therefore, we use **Publish By Template (PBT)**:

1. User copies a coin template
2. User modifies token details (name, symbol, etc.)
3. User publishes their own coin module
4. User registers the coin with Launchpad

### Step-by-Step Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    TOKEN CREATION FLOW (PBT)                             │
└─────────────────────────────────────────────────────────────────────────┘

STEP 1: USER GETS TEMPLATE
══════════════════════════

    User downloads/copies coin template from:
    • Your website (download button)
    • GitHub repo
    • CLI tool (auto-generates)

    Template file: coin_template.move


STEP 2: USER MODIFIES TEMPLATE
══════════════════════════════

    User edits template with their token details:

    ┌─────────────────────────────────────────────────────────────────┐
    │  module user_token::pepe {                                      │
    │                                                                 │
    │      use sui::coin::{Self, TreasuryCap, CoinMetadata};         │
    │      use sui::url;                                              │
    │                                                                 │
    │      /// One-time witness for the coin                          │
    │      struct PEPE has drop {}                                    │
    │                                                                 │
    │      fun init(witness: PEPE, ctx: &mut TxContext) {            │
    │          let (treasury_cap, metadata) = coin::create_currency( │
    │              witness,                                           │
    │              9,                          // decimals            │
    │              b"PEPE",                    // symbol              │
    │              b"Pepe Token",              // name                │
    │              b"The most memeable...",    // description         │
    │              option::some(url::new_unsafe_from_bytes(           │
    │                  b"https://example.com/pepe.png"               │
    │              )),                                                │
    │              ctx                                                │
    │          );                                                     │
    │                                                                 │
    │          // Transfer TreasuryCap to publisher (user)            │
    │          transfer::public_transfer(treasury_cap, tx_context::sender(ctx)); │
    │                                                                 │
    │          // Freeze metadata (immutable)                         │
    │          transfer::public_freeze_object(metadata);              │
    │      }                                                          │
    │  }                                                              │
    └─────────────────────────────────────────────────────────────────┘


STEP 3: USER PUBLISHES MODULE
═════════════════════════════

    $ sui client publish ./user_token --gas-budget 100000000

    Result:
    ├── Package ID: 0xUSER_TOKEN_PKG...
    ├── TreasuryCap<PEPE>: 0xTREASURY_CAP...  (owned by user)
    └── CoinMetadata<PEPE>: 0xMETADATA...     (frozen/immutable)


STEP 4: USER REGISTERS WITH LAUNCHPAD
═════════════════════════════════════

    User calls launchpad::registry::register_token<PEPE>()

    ┌─────────────────────────────────────────────────────────────────┐
    │                                                                 │
    │  Transaction:                                                   │
    │  ─────────────                                                  │
    │  Package:  launchpad                                            │
    │  Module:   registry                                             │
    │  Function: register_token<0xUSER_TOKEN_PKG::pepe::PEPE>        │
    │                                                                 │
    │  Arguments:                                                     │
    │  ├── registry: &mut LaunchpadRegistry                          │
    │  ├── config: &LaunchpadConfig                                  │
    │  ├── treasury_cap: TreasuryCap<PEPE>      ← Transferred!       │
    │  ├── metadata: &CoinMetadata<PEPE>                             │
    │  ├── creation_fee: Coin<SUI>              ← 0.5 SUI            │
    │  ├── twitter_url: Option<String>                               │
    │  ├── telegram_url: Option<String>                              │
    │  ├── website_url: Option<String>                               │
    │  └── ctx: &mut TxContext                                       │
    │                                                                 │
    │  What happens:                                                  │
    │  ─────────────                                                  │
    │  1. Validate TreasuryCap (no tokens minted yet)                │
    │  2. Collect creation fee                                        │
    │  3. Create BondingPool<PEPE>                                   │
    │  4. Mint initial supply using TreasuryCap                      │
    │  5. Store TreasuryCap in pool (locked forever)                 │
    │  6. Register token in registry                                  │
    │  7. Emit TokenCreated event                                     │
    │                                                                 │
    └─────────────────────────────────────────────────────────────────┘


STEP 5: TRADING BEGINS
══════════════════════

    BondingPool<PEPE> is now active:

    ├── Token supply in pool: 800,000,000 (80%)
    ├── Platform allocation:   10,000,000 (1%)
    ├── Creator allocation:    10,000,000 (1%)  [optional]
    ├── Reserve for graduation: remaining
    │
    └── Users can now buy() and sell()
```

---

## Token Template

```move
// FILE: token_template/sources/coin_template.move
//
// INSTRUCTIONS:
// 1. Copy this file to a new directory
// 2. Rename the module (line 1) to your token name
// 3. Rename the struct (line 8) to your TOKEN_SYMBOL (UPPERCASE)
// 4. Update decimals, symbol, name, description, icon URL
// 5. Run: sui client publish --gas-budget 100000000
// 6. Register with launchpad using the TreasuryCap

module token_template::TEMPLATE {
    use sui::coin::{Self, TreasuryCap, CoinMetadata};
    use sui::url;

    /// The OTW (One-Time Witness) for this token
    /// MUST match module name in UPPERCASE
    struct TEMPLATE has drop {}

    /// Called once when module is published
    fun init(witness: TEMPLATE, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness,
            9,                                      // decimals (9 = standard)
            b"SYMBOL",                              // symbol (e.g., "PEPE")
            b"Token Name",                          // name (e.g., "Pepe Token")
            b"Description of your token",           // description
            option::some(url::new_unsafe_from_bytes(
                b"https://your-domain.com/icon.png" // icon URL
            )),
            ctx
        );

        // Transfer TreasuryCap to publisher
        // You will transfer this to the launchpad during registration
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));

        // Freeze metadata so it cannot be changed
        transfer::public_freeze_object(metadata);
    }
}
```

---

## Bonding Curve

### Curve Formula

We use a **linear bonding curve** for simplicity and predictability:

```
Price = BasePrice + (Slope * CurrentSupply)

Where:
- BasePrice: Starting price (e.g., 0.000001 SUI)
- Slope: Price increase per token (e.g., 0.0000000001)
- CurrentSupply: Tokens currently in circulation
```

### Buy Calculation

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         BUY CALCULATION                                  │
└─────────────────────────────────────────────────────────────────────────┘

Input: sui_amount (how much SUI user wants to spend)

1. Calculate tokens out using integral of price curve:

   tokens_out = (-slope + sqrt(slope² + 2*slope*(sui_amount + current_area))) / slope

   Simplified for linear curve:
   tokens_out = solve_quadratic(sui_amount, current_supply, slope, base_price)

2. Deduct fees:
   platform_fee = sui_amount * 0.5%
   creator_fee = sui_amount * creator_fee_bps (if set)
   net_sui = sui_amount - platform_fee - creator_fee

3. Update pool state:
   pool.sui_reserve += net_sui
   pool.token_reserve -= tokens_out
   pool.current_supply += tokens_out

4. Return tokens to user
```

### Sell Calculation

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         SELL CALCULATION                                 │
└─────────────────────────────────────────────────────────────────────────┘

Input: token_amount (how many tokens user wants to sell)

1. Calculate SUI out using integral of price curve:

   sui_out = integrate price from (supply - token_amount) to supply

2. Deduct fees:
   platform_fee = sui_out * 0.5%
   creator_fee = sui_out * creator_fee_bps (if set)
   net_sui = sui_out - platform_fee - creator_fee

3. Update pool state:
   pool.sui_reserve -= net_sui
   pool.token_reserve += token_amount
   pool.current_supply -= token_amount

4. Return SUI to user
```

---

## Graduation

### Graduation Threshold

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    GRADUATION CONDITIONS                                 │
└─────────────────────────────────────────────────────────────────────────┘

Token graduates when BOTH conditions met:

1. Market Cap Threshold:
   current_price * total_supply >= GRADUATION_MARKET_CAP

   Example: $69,000 USD equivalent in SUI

2. Liquidity Threshold:
   pool.sui_reserve >= MIN_GRADUATION_LIQUIDITY

   Example: 10,000 SUI minimum

Additional checks:
• Cannot graduate if already graduated
• Cannot graduate if pool is paused
• Must have sufficient tokens for LP creation
```

### Graduation Process

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    GRADUATION PROCESS                                    │
└─────────────────────────────────────────────────────────────────────────┘

TRIGGER: Market cap threshold reached during buy()

STEP 1: HALT TRADING
════════════════════
    pool.graduated = true;
    pool.trading_enabled = false;

    // No more buy/sell allowed

STEP 2: CALCULATE SPLITS
════════════════════════
    Total SUI in pool: pool.sui_reserve

    graduation_fee = pool.sui_reserve * 5%          → Platform treasury
    liquidity_sui = pool.sui_reserve - graduation_fee → Goes to DEX

    Tokens for LP: Calculated based on target price
    Platform tokens: 1% of total supply

STEP 3: SELECT DEX
══════════════════
    Based on config or creator preference:
    • Cetus (default - highest volume)
    • Turbos
    • FlowX

STEP 4: CREATE LP ON DEX
════════════════════════
    Call appropriate DEX adapter:

    dex_adapters::cetus::create_pool_and_add_liquidity(
        sui_coins,
        token_coins,
        price_sqrt,  // Initial price
        tick_spacing,
        ...
    )

    Returns: LP tokens (position NFT for Cetus)

STEP 5: HANDLE LP TOKENS
════════════════════════
    Options (configurable):

    Option A: LOCK FOREVER
    └── Transfer LP to a burn address or lock contract

    Option B: VEST TO CREATOR
    └── Create vesting schedule (e.g., 12 months linear)
    └── Creator claims gradually

    Option C: PARTIAL BURN + VEST
    └── 50% locked forever
    └── 50% vested to creator

STEP 6: EMIT EVENTS
═══════════════════
    TokenGraduated {
        token_type,
        dex,
        lp_tokens,
        final_price,
        total_sui_raised,
        graduation_fee_collected,
        timestamp
    }
```

---

## LP Vesting (Standalone Package)

> **IMPORTANT:** Vesting is now a standalone package (`sui_vesting`) for reusability.
> See [VESTING.md](./VESTING.md) for complete specification.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    LP VESTING (Post-Graduation)                          │
│                    → Provided by sui_vesting package                     │
└─────────────────────────────────────────────────────────────────────────┘

INTEGRATION FLOW:
─────────────────

At Graduation:
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  1. graduation.move calculates token allocations                        │
│     ├── Creator tokens: 0-5% (configurable)                            │
│     ├── Platform tokens: 2.5-5% (configurable)                         │
│     └── DEX liquidity: remaining tokens                                │
│                                                                         │
│  2. For creator tokens, call sui_vesting:                              │
│                                                                         │
│     let schedule = sui_vesting::create_vesting_now(                    │
│         pool_id,                                                       │
│         creator_address,                                               │
│         creator_tokens,                                                │
│         6_months,        // cliff                                      │
│         12_months,       // vesting                                    │
│         true,            // revocable                                  │
│         clock,                                                         │
│         ctx,                                                           │
│     );                                                                 │
│                                                                         │
│  3. Transfer VestingSchedule to creator                                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

CURRENT STATUS: Placeholder in launchpad, awaiting sui_vesting deployment
```

For complete vesting documentation including:
- Linear vesting with cliff
- Milestone-based vesting
- Batch operations
- Admin functions

**See: [VESTING.md](./VESTING.md)**

---

## DEX Adapters

### Adapter Interface

```move
// Each DEX adapter must implement these core functions

module launchpad::dex_adapter_trait {

    /// Create a new liquidity pool
    public fun create_pool<CoinA, CoinB>(
        config: &DEXConfig,
        initial_price: u128,
        ctx: &mut TxContext
    ): PoolID;

    /// Add liquidity to existing pool
    public fun add_liquidity<CoinA, CoinB>(
        pool: &mut Pool,
        coin_a: Coin<CoinA>,
        coin_b: Coin<CoinB>,
        ctx: &mut TxContext
    ): LPToken;

    /// Get current price from pool
    public fun get_price<CoinA, CoinB>(
        pool: &Pool
    ): u128;
}
```

### Cetus Adapter (Primary)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CETUS INTEGRATION                                │
└─────────────────────────────────────────────────────────────────────────┘

Cetus uses Concentrated Liquidity (CLMM):
• Liquidity provided in price ranges
• More capital efficient
• LP position = NFT

Integration flow:
1. Create pool with initial tick/price
2. Add full-range liquidity (simple mode)
3. Receive Position NFT as LP token
4. Lock or vest the Position NFT

Key Cetus functions we'll call:
• clmm_pool::create_pool()
• clmm_pool::add_liquidity()
• position::open_position()
```

---

## Events

```move
module launchpad::events {

    // Token lifecycle events
    struct TokenCreated has copy, drop {
        token_type: TypeName,
        creator: address,
        name: String,
        symbol: String,
        total_supply: u64,
        creation_fee: u64,
        pool_id: ID,
        timestamp: u64,
    }

    struct Trade has copy, drop {
        token_type: TypeName,
        pool_id: ID,
        trader: address,
        is_buy: bool,
        sui_amount: u64,
        token_amount: u64,
        price: u64,
        platform_fee: u64,
        creator_fee: u64,
        new_supply: u64,
        timestamp: u64,
    }

    struct TokenGraduated has copy, drop {
        token_type: TypeName,
        pool_id: ID,
        dex: String,
        dex_pool_id: ID,
        final_price: u64,
        total_sui_raised: u64,
        sui_to_liquidity: u64,
        tokens_to_liquidity: u64,
        graduation_fee: u64,
        platform_tokens: u64,
        lp_handling: String,  // "locked" | "vested" | "partial"
        timestamp: u64,
    }

    // Admin events
    struct ConfigUpdated has copy, drop {
        field: String,
        old_value: u64,
        new_value: u64,
        updated_by: address,
        timestamp: u64,
    }

    struct PoolPaused has copy, drop {
        pool_id: ID,
        reason: String,
        paused_by: address,
        timestamp: u64,
    }
}
```

---

## Security Measures

### Access Control

| Function | Who Can Call | How |
|----------|--------------|-----|
| `register_token` | Anyone | Pays fee, transfers TreasuryCap |
| `buy` | Anyone | Pool not graduated, not paused |
| `sell` | Token holders | Has tokens, pool not graduated |
| `graduate` | Internal only | Called automatically on threshold |
| `admin_force_graduate` | AdminCap holder | Emergency only |
| `pause_pool` | AdminCap holder | Emergency |
| `update_config` | AdminCap holder | With timelock |
| `withdraw_fees` | AdminCap holder | To treasury |

### Reentrancy Protection

```move
struct BondingPool has key, store {
    id: UID,
    // ...
    locked: bool,  // Reentrancy guard
}

public fun buy<T>(...) {
    assert!(!pool.locked, EPoolLocked);
    pool.locked = true;

    // ... all logic ...

    // Check graduation AFTER state updates
    if (should_graduate(pool)) {
        execute_graduation_internal(pool, ...);
    };

    pool.locked = false;
}
```

### Input Validation

```move
// In register_token
assert!(coin::total_supply(treasury_cap) == 0, ETokensAlreadyMinted);
assert!(coin::value(&creation_fee) >= config.creation_fee, EInsufficientFee);

// In buy
assert!(!pool.graduated, EPoolGraduated);
assert!(sui_amount >= MIN_TRADE_AMOUNT, EAmountTooSmall);
assert!(sui_amount <= MAX_TRADE_AMOUNT, EAmountTooLarge);

// In sell
assert!(token_amount > 0, EZeroAmount);
assert!(token_amount <= pool.current_supply, EInsufficientLiquidity);
```

---

## Configuration

```move
struct LaunchpadConfig has key {
    id: UID,

    // Fees (in basis points, 100 = 1%)
    creation_fee: u64,           // SUI amount for token creation
    trading_fee_bps: u64,        // Fee on each trade (e.g., 50 = 0.5%)
    graduation_fee_bps: u64,     // Fee on graduation (e.g., 500 = 5%)

    // Token allocation (in basis points)
    platform_allocation_bps: u64, // Platform gets X% of supply

    // Graduation settings
    graduation_market_cap: u64,  // Target MC in SUI
    min_graduation_liquidity: u64, // Min SUI for graduation

    // LP handling
    default_lp_handling: u8,     // 0=lock, 1=vest, 2=partial
    default_vesting_duration: u64, // If vesting

    // Curve parameters
    default_base_price: u64,
    default_slope: u64,

    // DEX preference
    default_dex: u8,             // 0=Cetus, 1=Turbos, 2=FlowX

    // Admin
    treasury: address,           // Where fees go
    paused: bool,                // Global pause
}
```

---

## Estimated Lines of Code

| File | Lines | Description |
|------|-------|-------------|
| core/math.move | ~200 | Safe math, curve calculations |
| core/access.move | ~215 | AdminCap, OperatorCap, TreasuryCap |
| core/errors.move | ~195 | Error constants |
| config.move | ~408 | Platform configuration |
| registry.move | ~251 | Token registration |
| bonding_curve.move | ~577 | Pool, buy, sell |
| graduation.move | ~353 | DEX migration |
| vesting.move | ~109 | **PLACEHOLDER** (see sui_vesting) |
| launchpad.move | ~405 | Entry points |
| dex_adapters/cetus.move | ~101 | Cetus integration |
| dex_adapters/turbos.move | ~84 | Turbos integration |
| dex_adapters/flowx.move | ~84 | FlowX integration |
| dex_adapters/suidex.move | ~84 | SuiDex integration |
| events.move | ~247 | Event definitions |
| **Total** | **~3,313** | |

> **Note:** Vesting functionality (~760 lines) moved to standalone `sui_vesting` package.
> See [VESTING.md](./VESTING.md) for specifications.

---

## Status

| Component | Status | Notes |
|-----------|--------|-------|
| Core utilities | DONE | math, access, errors |
| Config | DONE | With graduation allocations |
| Registry | DONE | Token registration |
| Bonding curve | DONE | Pool, buy, sell |
| Graduation | DONE | DEX migration + token allocations |
| Vesting | PLACEHOLDER | Moved to sui_vesting |
| Cetus adapter | DONE | Placeholder implementation |
| Turbos adapter | DONE | Placeholder implementation |
| FlowX adapter | DONE | Placeholder implementation |
| SuiDex adapter | DONE | Placeholder implementation |
| Events | DONE | All events defined |
| Tests | In Progress | Unit tests |
| Audit | Not Started | |

**Overall Progress: 85%**

**Next Steps:**
1. Complete unit tests
2. Deploy to testnet
3. Integrate sui_vesting when ready
4. Implement actual DEX SDK calls
