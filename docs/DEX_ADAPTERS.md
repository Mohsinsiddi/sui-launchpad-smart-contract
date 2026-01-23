# DEX Adapters Documentation

This document covers the DEX adapter integrations for the Launchpad graduation system. When a token reaches its bonding curve target, it graduates to a DEX where a liquidity pool is created.

---

## Overview

| DEX | Type | LP Return | Repository | Deployable Locally? |
|-----|------|-----------|------------|---------------------|
| **SuiDex v2** | AMM | `Coin<LPCoin<T0,T1>>` | [Mohsinsiddi/suidex-v2](https://github.com/Mohsinsiddi/suidex-v2) | **Yes** - Full implementation |
| **Cetus** | CLMM | Position NFT | [CetusProtocol/cetus-contracts](https://github.com/CetusProtocol/cetus-contracts) | **Yes** - Full implementation (open-sourced June 2025) |
| **FlowX** | CLMM | Position NFT | [FlowX-Finance/clmm-contracts](https://github.com/FlowX-Finance/clmm-contracts) | **Yes** - Full implementation |

> **Note**: Turbos Finance only provides interface stubs (all functions `abort 0`), so it cannot be deployed locally. Use Turbos on testnet/mainnet only, or skip it for local testing.

---

## Move.toml Dependencies

Add these dependencies to integrate with DEX contracts:

```toml
[dependencies]
# SuiDex v2 (AMM) - Full implementation
SuiDex = { git = "https://github.com/Mohsinsiddi/suidex-v2.git", rev = "main" }

# Cetus CLMM - Full implementation (open-sourced June 2025)
CetusCLMM = { git = "https://github.com/CetusProtocol/cetus-contracts.git", subdir = "packages/cetus_clmm", rev = "main" }

# FlowX CLMM - Full implementation
FlowXCLMM = { git = "https://github.com/FlowX-Finance/clmm-contracts.git", rev = "main" }
```

---

## Local Deployment Plan

### Step 1: Clone All DEX Repositories

```bash
# Create a dexes directory for all DEX contracts
mkdir -p ~/dexes && cd ~/dexes

# Clone SuiDex v2 (your repo)
git clone https://github.com/Mohsinsiddi/suidex-v2.git

# Clone Cetus CLMM (full implementation)
git clone https://github.com/CetusProtocol/cetus-contracts.git

# Clone FlowX CLMM (full implementation)
git clone https://github.com/FlowX-Finance/clmm-contracts.git
```

### Step 2: Deploy SuiDex v2 (AMM)

```bash
cd ~/dexes/suidex-v2

# Build
sui move build

# Deploy
sui client publish --gas-budget 500000000

# Save these object IDs from output:
# - Package ID
# - Factory (shared object)
# - Router (shared object)
```

**Expected Output Objects:**
| Object | Type | Notes |
|--------|------|-------|
| Package | - | SuiDex package ID |
| Factory | `suidex::factory::Factory` | Shared object, created in init() |
| Router | `suidex::router::Router` | Shared object, created in init() |

### Step 3: Deploy Cetus CLMM

```bash
cd ~/dexes/cetus-contracts/packages/cetus_clmm

# Build
sui move build

# Deploy
sui client publish --gas-budget 500000000

# Save these object IDs from output:
# - Package ID
# - GlobalConfig (shared object)
# - Pools (shared object)
```

**Repository Structure:**
```
cetus-contracts/packages/cetus_clmm/
├── Move.toml
├── Move.lock
├── sources/
│   ├── acl.move              # Permission management
│   ├── config.move           # GlobalConfig
│   ├── factory.move          # Pool creation
│   ├── pool.move             # Core pool logic
│   ├── pool_creator.move     # create_pool functions
│   ├── position.move         # Position NFT
│   ├── position_snapshot.move
│   ├── rewarder.move         # Rewards
│   ├── partner.move          # Partner fees
│   ├── tick.move             # Tick management
│   ├── utils.move            # Utilities
│   └── math/
│       ├── clmm_math.move    # CLMM calculations
│       └── tick_math.move    # Tick math
└── tests/
```

**Expected Output Objects:**
| Object | Type | Notes |
|--------|------|-------|
| Package | - | Cetus CLMM package ID |
| GlobalConfig | `cetus_clmm::config::GlobalConfig` | Shared object |
| Pools | `cetus_clmm::factory::Pools` | Shared object, pool registry |

### Step 4: Deploy FlowX CLMM

```bash
cd ~/dexes/clmm-contracts

# Build
sui move build

# Deploy
sui client publish --gas-budget 500000000

# Save these object IDs from output:
# - Package ID
# - PoolRegistry (shared object)
# - PositionRegistry (shared object)
# - Versioned (shared object)
```

**Repository Structure:**
```
clmm-contracts/
├── Move.toml
├── Move.lock
├── FlowX Audit Report.pdf
├── sources/
│   ├── pool_manager.move      # Pool registry, create_pool
│   ├── pool.move              # Individual pool logic
│   ├── position_manager.move  # Position lifecycle
│   ├── swap_router.move       # Swap execution
│   └── ...
└── deployments/
```

**Expected Output Objects:**
| Object | Type | Notes |
|--------|------|-------|
| Package | - | FlowX CLMM package ID |
| PoolRegistry | `flowx_clmm::pool_manager::PoolRegistry` | Shared object |
| PositionRegistry | `flowx_clmm::position_manager::PositionRegistry` | Shared object |
| Versioned | `flowx_clmm::versioned::Versioned` | Shared object |

### Step 5: Deploy Launchpad

```bash
cd ~/your-project/sui_launchpad

# Update Move.toml with local DEX dependencies (or use deployed package IDs)
# Build
sui move build

# Deploy
sui client publish --gas-budget 500000000

# Save: CONFIG_ID, REGISTRY_ID
```

### Step 6: Configure Launchpad with DEX Object IDs

After deploying all DEXes, configure the launchpad with the deployed object IDs:

```bash
# Configure SuiDex
sui client call \
    --package <LAUNCHPAD_PACKAGE> \
    --module config \
    --function set_suidex_config \
    --args <CONFIG_ID> <SUIDEX_PACKAGE> <FACTORY_ID> <ROUTER_ID>

# Configure Cetus
sui client call \
    --package <LAUNCHPAD_PACKAGE> \
    --module config \
    --function set_cetus_config \
    --args <CONFIG_ID> <CETUS_PACKAGE> <GLOBAL_CONFIG_ID> <POOLS_ID>

# Configure FlowX
sui client call \
    --package <LAUNCHPAD_PACKAGE> \
    --module config \
    --function set_flowx_config \
    --args <CONFIG_ID> <FLOWX_PACKAGE> <POOL_REGISTRY_ID> <POSITION_REGISTRY_ID> <VERSIONED_ID>
```

---

## 1. SuiDex v2 (AMM)

### Repository
- **URL**: https://github.com/Mohsinsiddi/suidex-v2
- **Type**: Full implementation
- **Deployable**: Yes

### Source Files
| File | Purpose |
|------|---------|
| `sources/router.move` | `create_pair`, `add_liquidity`, `remove_liquidity`, swaps |
| `sources/factory.move` | Factory management, pair registry |
| `sources/pair.move` | AMM pool logic, LPCoin minting |
| `sources/library.move` | AMM math utilities |
| `sources/math_utils.move` | sqrt calculations |

### Key Structs
```move
struct Factory has key { ... }           // DEX factory - shared object
struct Router has key { ... }            // Router - shared object
struct Pair<T0, T1> has key { ... }      // AMM pool - shared object
struct LPCoin<T0, T1> has drop { }       // LP token type (phantom)
```

### Core Functions

#### Create Pair
```move
// Location: sources/router.move
public entry fun create_pair<T0, T1>(
    _router: &Router,
    factory: &mut Factory,
    token0_name: String,
    token1_name: String,
    ctx: &mut TxContext
)
```

#### Add Liquidity
```move
// Location: sources/router.move
public entry fun add_liquidity<T0, T1>(
    _router: &Router,
    factory: &mut Factory,
    pair: &mut Pair<T0, T1>,
    coin_a: Coin<T0>,
    coin_b: Coin<T1>,
    amount_a_desired: u256,
    amount_b_desired: u256,
    amount_a_min: u256,
    amount_b_min: u256,
    token0_name: String,
    token1_name: String,
    deadline: u64,
    clock: &Clock,
    ctx: &mut TxContext
)
```

#### Remove Liquidity
```move
// Location: sources/router.move
public entry fun remove_liquidity<T0, T1>(
    _router: &Router,
    factory: &Factory,
    pair: &mut Pair<T0, T1>,
    lp_coins: vector<Coin<LPCoin<T0, T1>>>,
    amount_to_burn: u256,
    amount_a_min: u256,
    amount_b_min: u256,
    deadline: u64,
    clock: &Clock,
    ctx: &mut TxContext
)
```

### Fee Structure
- Total swap fee: 0.3%
  - LP providers: 0.15%
  - Team: 0.09%
  - Locker: 0.03%
  - Buyback: 0.03%

### Integration Notes
- Returns `Coin<LPCoin<T0, T1>>` - standard LP tokens
- Simpler integration than CLMM (no tick ranges needed)
- Requires Router and Factory shared objects
- Slippage protection via `amount_min` parameters
- Deadline enforcement for transaction expiry

---

## 2. Cetus CLMM

### Repository
- **URL**: https://github.com/CetusProtocol/cetus-contracts
- **Path**: `packages/cetus_clmm/`
- **Type**: Full implementation (open-sourced June 2025)
- **Deployable**: Yes

### Source Files
| File | Purpose |
|------|---------|
| `sources/pool_creator.move` | `create_pool_v2`, `create_pool_v3` |
| `sources/pool.move` | Core pool operations, `add_liquidity`, `remove_liquidity` |
| `sources/position.move` | Position NFT management |
| `sources/config.move` | GlobalConfig |
| `sources/factory.move` | Pool registry (Pools) |
| `sources/tick.move` | Tick management |
| `sources/math/clmm_math.move` | CLMM calculations |
| `sources/math/tick_math.move` | Tick math |

### Key Structs
```move
struct GlobalConfig has key { ... }                    // Global config - shared
struct Pools has key { ... }                           // Pool registry - shared
struct Pool<CoinTypeA, CoinTypeB> has key { ... }      // Individual pool
struct Position has key, store { ... }                 // Position NFT (LP)
```

### Core Functions

#### Create Pool (with initial liquidity)
```move
// Location: sources/pool_creator.move
public fun create_pool_v3<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pools: &mut Pools,
    tick_spacing: u32,
    initialize_price: u128,          // sqrt_price_x64 format
    url: String,
    tick_lower_idx: u32,
    tick_upper_idx: u32,
    coin_a: Coin<CoinTypeA>,
    coin_b: Coin<CoinTypeB>,
    fix_amount_a: bool,
    clock: &Clock,
    ctx: &mut TxContext,
): (Position, Coin<CoinTypeA>, Coin<CoinTypeB>)
```

#### Add Liquidity (to existing position)
```move
// Location: sources/pool.move
public fun add_liquidity_fix_coin<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position_nft: &mut Position,
    amount: u64,
    fix_amount_a: bool,
    clock: &Clock
): AddLiquidityReceipt<CoinTypeA, CoinTypeB>

// Must call repay after add_liquidity_fix_coin
public fun repay_add_liquidity<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    coin_a: Coin<CoinTypeA>,
    coin_b: Coin<CoinTypeB>,
    receipt: AddLiquidityReceipt<CoinTypeA, CoinTypeB>
)
```

#### Remove Liquidity
```move
// Location: sources/pool.move
public fun remove_liquidity<CoinTypeA, CoinTypeB>(
    config: &GlobalConfig,
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position_nft: &mut Position,
    delta_liquidity: u128,
    clock: &Clock
): (Coin<CoinTypeA>, Coin<CoinTypeB>)
```

### Price Calculation
```move
// sqrt_price_x64 = sqrt(price) * 2^64
// For 1:1 ratio: 1 << 64 = 18446744073709551616
// Tick range: -443636 < tick_lower < tick_upper < 443636
```

### Fee Tiers (Tick Spacing)
| Fee | Tick Spacing | Use Case |
|-----|--------------|----------|
| 0.01% | 1 | Stable pairs |
| 0.05% | 10 | Low volatility |
| 0.3% | 60 | Standard pairs |
| 1% | 200 | High volatility |

### Integration Notes
- Returns **Position NFT** instead of LP tokens
- Requires tick range specification (concentrated liquidity)
- Uses flash loan receipt pattern for add_liquidity
- More complex but higher capital efficiency
- Common tick spacings: 1, 10, 60, 200

---

## 3. FlowX CLMM

### Repository
- **URL**: https://github.com/FlowX-Finance/clmm-contracts
- **Type**: Full implementation
- **Deployable**: Yes
- **Audit**: Included in repo (FlowX Audit Report.pdf)

### Source Files
| File | Purpose |
|------|---------|
| `sources/pool_manager.move` | Pool registry, `create_pool_v2`, `create_and_initialize_pool_v2` |
| `sources/pool.move` | Individual pool logic |
| `sources/position_manager.move` | `open_position`, `increase_liquidity`, `decrease_liquidity` |
| `sources/swap_router.move` | Swap execution |

### Key Structs
```move
struct PoolRegistry has key { ... }       // Pool registry - shared
struct Pool<X, Y> has key { ... }         // Pool instance
struct Position has key, store { ... }    // Position NFT
struct Versioned has key { ... }          // Version control
```

### Core Functions

#### Create Pool
```move
// Location: sources/pool_manager.move
public fun create_pool_v2<X, Y>(
    pool_registry: &mut PoolRegistry,
    fee_rate: u64,                    // e.g., 3000 = 0.3%
    metadata_x: &CoinMetadata<X>,
    metadata_y: &CoinMetadata<Y>,
    versioned: &Versioned,
    ctx: &mut TxContext
)

// Create and initialize with price in one call
public fun create_and_initialize_pool_v2<X, Y>(
    pool_registry: &mut PoolRegistry,
    fee_rate: u64,
    sqrt_price: u128,
    metadata_x: &CoinMetadata<X>,
    metadata_y: &CoinMetadata<Y>,
    versioned: &Versioned,
    clock: &Clock,
    ctx: &mut TxContext
)
```

#### Open Position
```move
// Location: sources/position_manager.move
public fun open_position<X, Y>(
    position_registry: &mut PositionRegistry,
    pool_registry: &PoolRegistry,
    fee_rate: u64,
    tick_lower_index: I32,
    tick_upper_index: I32,
    versioned: &Versioned,
    ctx: &mut TxContext
): Position
```

#### Add Liquidity
```move
// Location: sources/position_manager.move
public fun increase_liquidity<X, Y>(
    pool_registry: &mut PoolRegistry,
    position: &mut Position,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    amount_x_min: u64,
    amount_y_min: u64,
    deadline: u64,
    versioned: &Versioned,
    clock: &Clock,
    ctx: &mut TxContext
): (Coin<X>, Coin<Y>)
```

#### Remove Liquidity
```move
// Location: sources/position_manager.move
public fun decrease_liquidity<X, Y>(
    pool_registry: &mut PoolRegistry,
    position: &mut Position,
    liquidity: u128,
    amount_x_min: u64,
    amount_y_min: u64,
    deadline: u64,
    versioned: &Versioned,
    clock: &Clock,
    ctx: &mut TxContext
): (Coin<X>, Coin<Y>)
```

### Fee Tiers
| Fee Rate | Basis Points | Use Case |
|----------|--------------|----------|
| 0.01% | 100 | Stable pairs |
| 0.05% | 500 | Low volatility |
| 0.3% | 3000 | Standard pairs |
| 1% | 10000 | High volatility |

### Integration Notes
- CLMM returns **Position NFT**
- Requires CoinMetadata for pool creation
- Uses Versioned object for upgrades
- Supports TWAP oracle

---

## Graduation Flow

### For AMM DEXes (SuiDex v2)

```
1. Token reaches bonding curve target
2. Call start_graduation() → PendingGraduation<T>
3. Call graduate_to_suidex():
   a. Extract SUI and tokens from PendingGraduation
   b. Call create_pair<T, SUI>() on SuiDex
   c. Call add_liquidity<T, SUI>() with extracted funds
   d. Receive Coin<LPCoin<T, SUI>>
   e. Distribute LP tokens:
      - Creator portion → Vesting contract
      - Community portion → Burn / DAO / Staking
   f. Call complete_graduation() with pool ID
4. Token now tradeable on SuiDex
```

### For CLMM DEXes (Cetus, FlowX)

```
1. Token reaches bonding curve target
2. Call start_graduation() → PendingGraduation<T>
3. Call graduate_to_cetus():
   a. Extract SUI and tokens from PendingGraduation
   b. Calculate tick range (full range or custom)
   c. Call create_pool_v3<T, SUI>() with initial liquidity
   d. Receive Position NFT + remaining coins
   e. Handle Position NFT:
      - Creator portion → Transfer/Vest the NFT
      - Community portion → Hold in DAO or protocol
   f. Call complete_graduation() with pool ID
4. Token now tradeable on Cetus
```

---

## LP Distribution

### AMM (LP Tokens)
| Recipient | Percentage | Handling |
|-----------|------------|----------|
| Creator | 10% | Vested over 6 months |
| Community | 90% | Burn / DAO Treasury / Staking Rewards |

### CLMM (Position NFT)
Since CLMM returns a single Position NFT (not divisible tokens), options are:
1. **Single Position for Protocol**: Protocol holds the NFT, distributes fees
2. **Create Multiple Positions**: Split initial liquidity into multiple positions
3. **Wrap Position**: Create wrapper that issues shares against the Position

---

## End-to-End Local Testing

### Prerequisites
```bash
# Ensure Sui CLI is installed
sui --version

# Create local network (optional, or use devnet)
# sui-test-validator
```

### Complete Test Script

```bash
#!/bin/bash
# test_graduation_flow.sh

# ============================================
# STEP 1: Deploy SuiDex v2
# ============================================
echo "Deploying SuiDex v2..."
cd ~/dexes/suidex-v2
sui move build
SUIDEX_OUTPUT=$(sui client publish --gas-budget 500000000 --json)
SUIDEX_PACKAGE=$(echo $SUIDEX_OUTPUT | jq -r '.objectChanges[] | select(.type=="published") | .packageId')
SUIDEX_FACTORY=$(echo $SUIDEX_OUTPUT | jq -r '.objectChanges[] | select(.objectType | contains("Factory")) | .objectId')
SUIDEX_ROUTER=$(echo $SUIDEX_OUTPUT | jq -r '.objectChanges[] | select(.objectType | contains("Router")) | .objectId')
echo "SuiDex Package: $SUIDEX_PACKAGE"
echo "SuiDex Factory: $SUIDEX_FACTORY"
echo "SuiDex Router: $SUIDEX_ROUTER"

# ============================================
# STEP 2: Deploy Cetus CLMM
# ============================================
echo "Deploying Cetus CLMM..."
cd ~/dexes/cetus-contracts/packages/cetus_clmm
sui move build
CETUS_OUTPUT=$(sui client publish --gas-budget 500000000 --json)
CETUS_PACKAGE=$(echo $CETUS_OUTPUT | jq -r '.objectChanges[] | select(.type=="published") | .packageId')
CETUS_CONFIG=$(echo $CETUS_OUTPUT | jq -r '.objectChanges[] | select(.objectType | contains("GlobalConfig")) | .objectId')
CETUS_POOLS=$(echo $CETUS_OUTPUT | jq -r '.objectChanges[] | select(.objectType | contains("Pools")) | .objectId')
echo "Cetus Package: $CETUS_PACKAGE"
echo "Cetus GlobalConfig: $CETUS_CONFIG"
echo "Cetus Pools: $CETUS_POOLS"

# ============================================
# STEP 3: Deploy FlowX CLMM
# ============================================
echo "Deploying FlowX CLMM..."
cd ~/dexes/clmm-contracts
sui move build
FLOWX_OUTPUT=$(sui client publish --gas-budget 500000000 --json)
FLOWX_PACKAGE=$(echo $FLOWX_OUTPUT | jq -r '.objectChanges[] | select(.type=="published") | .packageId')
FLOWX_POOL_REG=$(echo $FLOWX_OUTPUT | jq -r '.objectChanges[] | select(.objectType | contains("PoolRegistry")) | .objectId')
FLOWX_POS_REG=$(echo $FLOWX_OUTPUT | jq -r '.objectChanges[] | select(.objectType | contains("PositionRegistry")) | .objectId')
FLOWX_VERSIONED=$(echo $FLOWX_OUTPUT | jq -r '.objectChanges[] | select(.objectType | contains("Versioned")) | .objectId')
echo "FlowX Package: $FLOWX_PACKAGE"
echo "FlowX PoolRegistry: $FLOWX_POOL_REG"
echo "FlowX PositionRegistry: $FLOWX_POS_REG"
echo "FlowX Versioned: $FLOWX_VERSIONED"

# ============================================
# STEP 4: Deploy Launchpad
# ============================================
echo "Deploying Launchpad..."
cd ~/your-project/sui_launchpad
sui move build
LAUNCHPAD_OUTPUT=$(sui client publish --gas-budget 500000000 --json)
LAUNCHPAD_PACKAGE=$(echo $LAUNCHPAD_OUTPUT | jq -r '.objectChanges[] | select(.type=="published") | .packageId')
echo "Launchpad Package: $LAUNCHPAD_PACKAGE"

# ============================================
# STEP 5: Create Token & Test Graduation
# ============================================
echo "Creating token on launchpad..."
# sui client call --function create_token ...

echo "Buying tokens to reach graduation threshold..."
# sui client call --function buy ...

echo "Triggering graduation to SuiDex..."
# sui client call --function graduate_to_suidex ...

echo "Testing swap on new pool..."
# sui client call --function swap_exact_tokens0_for_tokens1 ...

echo "Done!"
```

---

## Shared Objects Summary

### SuiDex v2
| Object | Type | Created By |
|--------|------|------------|
| Factory | `suidex::factory::Factory` | Package init |
| Router | `suidex::router::Router` | Package init |
| Pair<T0,T1> | `suidex::pair::Pair<T0,T1>` | create_pair |

### Cetus CLMM
| Object | Type | Created By |
|--------|------|------------|
| GlobalConfig | `cetus_clmm::config::GlobalConfig` | Package init |
| Pools | `cetus_clmm::factory::Pools` | Package init |

### FlowX CLMM
| Object | Type | Created By |
|--------|------|------------|
| PoolRegistry | `flowx_clmm::pool_manager::PoolRegistry` | Package init |
| PositionRegistry | `flowx_clmm::position_manager::PositionRegistry` | Package init |
| Versioned | `flowx_clmm::versioned::Versioned` | Package init |

---

## Error Codes

### SuiDex Adapter
| Code | Name | Description |
|------|------|-------------|
| 630 | EWrongDexType | Wrong DEX type for this adapter |
| 631 | ESuiDexNotConfigured | SuiDex package not configured |

### Cetus Adapter
| Code | Name | Description |
|------|------|-------------|
| 600 | EWrongDexType | Wrong DEX type for this adapter |
| 601 | ECetusNotConfigured | Cetus package not configured |

### FlowX Adapter
| Code | Name | Description |
|------|------|-------------|
| 620 | EWrongDexType | Wrong DEX type for this adapter |
| 621 | EFlowXNotConfigured | FlowX package not configured |

---

## Implementation Status

### Adapters Implemented (Two-Phase Pattern)

All adapters now use a two-phase graduation pattern for flexibility:

| Adapter | Phase 1 (Extract) | Phase 2 (Complete) | Tests |
|---------|-------------------|-------------------|-------|
| **SuiDex v2** | `initiate_graduation_to_suidex()` | `complete_graduation_suidex()` | 11 |
| **Cetus** | `initiate_graduation_to_cetus()` | `complete_graduation_cetus()` | 11 |
| **FlowX** | `initiate_graduation_to_flowx()` | `complete_graduation_flowx()` | 10 |
| **Turbos** | `initiate_graduation_to_turbos()` | `complete_graduation_turbos()` | 8 |

**Total Tests: 192** (including 44 adapter-specific tests in `tests/dex_adapter_tests.move`)

### Two-Phase Graduation Pattern

The adapters follow a PTB-friendly two-phase pattern:

**Phase 1: Extract**
```move
// launchpad.move
public fun initiate_graduation_to_<dex><T>(
    admin: &AdminCap,
    pool: &mut BondingPool<T>,
    config: &LaunchpadConfig,
    ctx: &mut TxContext,
): (PendingGraduation<T>, Coin<SUI>, Coin<T>)
```

**Phase 2: Complete**
```move
// launchpad.move
public fun complete_graduation_<dex><T>(
    pending: PendingGraduation<T>,
    registry: &mut Registry,
    dex_pool_id: ID,
    total_lp_tokens: u64,
    creator_lp_tokens: u64,
    community_lp_tokens: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): GraduationReceipt
```

### Example PTB Flow (SuiDex)

```typescript
// 1. Initiate graduation
const [pending, sui, tokens] = tx.moveCall({
    target: `${LAUNCHPAD}::launchpad::initiate_graduation_to_suidex`,
    typeArguments: [TOKEN_TYPE],
    arguments: [adminCap, pool, config],
});

// 2. Create pair on SuiDex
tx.moveCall({
    target: `${SUIDEX}::router::create_pair`,
    typeArguments: [TOKEN_TYPE, '0x2::sui::SUI'],
    arguments: [router, factory, tokenName, suiName],
});

// 3. Add liquidity
tx.moveCall({
    target: `${SUIDEX}::router::add_liquidity`,
    typeArguments: [TOKEN_TYPE, '0x2::sui::SUI'],
    arguments: [router, factory, pair, tokens, sui, ...],
});

// 4. Complete graduation
tx.moveCall({
    target: `${LAUNCHPAD}::launchpad::complete_graduation_suidex`,
    typeArguments: [TOKEN_TYPE],
    arguments: [pending, registry, poolId, totalLp, creatorLp, communityLp, clock],
});
```

---

## Next Steps

1. ~~Deploy SuiDex v2 locally~~ - Adapter implemented
2. ~~Deploy Cetus CLMM locally~~ - Adapter implemented
3. ~~Deploy FlowX CLMM locally~~ - Adapter implemented
4. ~~Implement SuiDex adapter~~ - **DONE**
5. ~~Implement Cetus adapter~~ - **DONE**
6. ~~Implement FlowX adapter~~ - **DONE**
7. **Clone DEX repos and deploy locally** - For end-to-end testing
8. **Full integration tests** - End-to-end graduation flow with deployed DEXes
9. **Deploy to testnet** - Real-world testing
