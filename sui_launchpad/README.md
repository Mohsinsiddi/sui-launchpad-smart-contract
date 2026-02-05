# sui_launchpad

A comprehensive token launchpad for Sui Move with bonding curve, graduation to DEX, staking, DAO, and vesting integration.

## Overview

sui_launchpad enables fair token launches with:

- **Bonding Curve**: Price discovery through automated market maker
- **Graduation**: Automatic migration to DEX (Cetus, FlowX, SuiDex, Turbos)
- **Staking Integration**: Create staking pools at graduation
- **DAO Integration**: Create governance for graduated tokens
- **Vesting**: LP token vesting for creators
- **Operator System**: Role-based admin access for dashboards

## Architecture

```
sui_launchpad/
├── sources/
│   ├── launchpad.move           # Main entry points
│   ├── bonding_curve.move       # Price discovery AMM
│   ├── graduation.move          # DEX migration logic
│   ├── config.move              # Platform configuration
│   ├── registry.move            # Token registry
│   ├── operators.move           # Role-based access control
│   ├── access.move              # Capabilities
│   ├── staking_integration.move # Staking pool creation
│   ├── dao_integration.move     # DAO creation
│   └── dex_adapters/
│       ├── cetus.move           # Cetus CLMM adapter
│       ├── flowx.move           # FlowX CLMM adapter
│       ├── suidex.move          # SuiDex AMM adapter
│       └── turbos.move          # Turbos CLMM adapter
```

## Operator System (Dashboard Access Control)

The operator system provides role-based access for admin dashboards without requiring capability transfers.

### Roles

| Role | ID | Permissions |
|------|-----|-------------|
| `SUPER_ADMIN` | 0 | Everything + manage operators |
| `GRADUATION` | 1 | Graduate pools, create staking/DAO |
| `FEE` | 2 | Update platform fees |
| `PAUSE` | 3 | Pause/unpause platform or pools |
| `TREASURY` | 4 | Update treasury addresses |

### Dashboard Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    ADMIN DASHBOARD                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Connected: 0xABC... (PAUSE_OPERATOR, FEE_OPERATOR)             │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Pause Pool   │  │ Update Fees  │  │ Graduate     │          │
│  │     ✅       │  │     ✅       │  │     ❌       │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                  │
│  Click → Sign Transaction → Executed!                           │
│  (No capability transfer needed)                                │
└─────────────────────────────────────────────────────────────────┘
```

### Operator Management

```move
// Super admin adds operators
add_operator(op_registry, operator_address, role);

// Example: Add a pause operator
add_operator(op_registry, @0xABC, 3); // ROLE_PAUSE = 3

// Example: Add a fee operator
add_operator(op_registry, @0xDEF, 2); // ROLE_FEE = 2

// Remove an operator
remove_operator(op_registry, operator_address, role);

// Add another super admin
add_super_admin(op_registry, new_admin_address);
```

### Operator Entry Points

| Function | Role | Description |
|----------|------|-------------|
| `operator_pause_pool<T>` | PAUSE | Pause a specific pool |
| `operator_unpause_pool<T>` | PAUSE | Unpause a specific pool |
| `operator_pause_platform` | PAUSE | Pause entire platform |
| `operator_unpause_platform` | PAUSE | Unpause platform |
| `operator_set_creation_fee` | FEE | Update token creation fee |
| `operator_set_trading_fee` | FEE | Update trading fee |
| `operator_set_graduation_fee` | FEE | Update graduation fee |
| `operator_set_treasury` | TREASURY | Update platform treasury |
| `operator_set_dao_treasury` | TREASURY | Update DAO treasury |

### Security Features

- **Super admin protection**: Cannot remove the last super admin
- **Role inheritance**: Super admins automatically have all other roles
- **Address-based**: No capability objects to manage/transfer
- **Multi-operator**: Same address can have multiple roles
- **Events**: All operator changes emit events for tracking

## Token Lifecycle

```
1. CREATE TOKEN
   └─> Bonding curve pool created
   └─> Trading begins at base price

2. TRADING PHASE
   └─> Buy: Price increases along curve
   └─> Sell: Price decreases along curve
   └─> Fees collected for platform

3. GRADUATION (when market cap threshold reached)
   └─> Liquidity migrated to DEX
   └─> Staking pool created (optional)
   └─> DAO created (optional)
   └─> LP tokens distributed:
       ├─> Creator: Vested via sui_vesting
       ├─> Protocol: Direct transfer
       └─> DAO: To treasury or vested

4. POST-GRADUATION
   └─> Trading on DEX
   └─> Staking rewards distribution
   └─> DAO governance active
```

## Creating a Token

```move
launchpad::create_token<T>(
    config,
    registry,
    treasury_cap,     // TreasuryCap<T> with 0 supply
    metadata,
    creator_fee_bps,  // Creator's trading fee (0-5%)
    payment,          // SUI for creation fee
    clock,
    ctx,
);
```

## Trading

```move
// Buy tokens
let tokens = bonding_curve::buy<T>(
    config,
    pool,
    payment,          // SUI to spend
    min_tokens_out,   // Slippage protection
    clock,
    ctx,
);

// Sell tokens
let sui = bonding_curve::sell<T>(
    config,
    pool,
    tokens,           // Tokens to sell
    min_sui_out,      // Slippage protection
    clock,
    ctx,
);
```

## Graduation

```move
// Initiate graduation (returns PendingGraduation hot potato)
let pending = graduation::initiate_graduation<T>(
    admin_cap,
    config,
    pool,
    dex_type,
    clock,
    ctx,
);

// Extract balances for DEX
let sui = graduation::extract_all_sui(&mut pending, ctx);
let tokens = graduation::extract_all_tokens(&mut pending, ctx);

// Create DEX pool (via adapter)
// ... DEX-specific calls ...

// Complete graduation
let receipt = graduation::complete_graduation(
    pending,
    registry,
    dex_pool_id,
    // ... distribution info ...
);
```

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `creation_fee` | 0.5 SUI | Fee to create a token |
| `trading_fee_bps` | 100 (1%) | Platform trading fee |
| `graduation_fee_bps` | 500 (5%) | Graduation fee |
| `graduation_threshold` | 69,420 SUI | Market cap to trigger graduation |
| `creator_lp_bps` | 250 (2.5%) | Creator's LP share |
| `protocol_lp_bps` | 250 (2.5%) | Protocol's LP share |
| `staking_enabled` | true | Auto-create staking pool |
| `dao_enabled` | true | Auto-create DAO |

## Supported DEXes

| DEX | Type | LP Token |
|-----|------|----------|
| Cetus | CLMM | Position NFT |
| FlowX | CLMM | Position NFT |
| Turbos | CLMM | Position NFT |
| SuiDex | AMM | LP Coin |

## Origin Tracking

All created resources track their origin:

```move
// Origin constants
ORIGIN_INDEPENDENT = 0  // Created directly
ORIGIN_LAUNCHPAD = 1    // Created via launchpad
ORIGIN_PARTNER = 2      // Created via partner

// Staking pools, DAOs, vesting schedules all track:
// - origin: u8 (0/1/2)
// - origin_id: Option<ID> (launchpad pool ID)
```

## Events

Key events emitted by the system:

```move
// Pool events
PoolCreated { pool_id, creator, token_type, ... }
TokensBought { pool_id, buyer, sui_amount, tokens_received, ... }
TokensSold { pool_id, seller, tokens_amount, sui_received, ... }
PoolGraduated { pool_id, dex_type, dex_pool_id, ... }

// Operator events
OperatorAdded { operator, role, added_by }
OperatorRemoved { operator, role, removed_by }
```

## Integration with Other Packages

### sui_staking
- Automatic staking pool creation at graduation
- Rewards from reserved tokens
- Voting power for DAO

### sui_dao
- Automatic DAO creation at graduation
- Staking-based voting power
- Treasury holds LP tokens

### sui_vesting
- Creator LP vesting (cliff + linear)
- DAO LP vesting (optional)

## Test Coverage

| Category | Tests |
|----------|-------|
| Bonding Curve | 45+ |
| Graduation | 30+ |
| Config | 25+ |
| E2E (Cetus) | 15+ |
| E2E (FlowX) | 15+ |
| E2E (SuiDex) | 15+ |
| Operators | 18 |
| **Total** | **344** |

## Building & Testing

```bash
cd sui_launchpad
sui move build
sui move test

# Run specific test category
sui move test operator
sui move test graduation
sui move test e2e
```

## Security Considerations

1. **Hot Potato Pattern**: Graduation uses hot potato to ensure atomic completion
2. **Slippage Protection**: All trades require min output amounts
3. **Role Separation**: Operators have limited permissions
4. **Fee Caps**: All fees have maximum limits
5. **Pause Functionality**: Platform and individual pools can be paused

## License

Apache 2.0
