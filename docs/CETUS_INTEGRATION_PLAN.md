# Cetus CLMM Integration Plan

## Overview

Integrate Cetus Concentrated Liquidity Market Maker (CLMM) with the Launchpad graduation flow. Unlike SuiDex (AMM) which uses fungible `LPCoin<A,B>`, Cetus uses non-fungible `Position` NFTs.

**Date:** 2026-01-24
**Status:** Planning

---

## Key Difference: Position NFT vs LP Coin

| Aspect | SuiDex (AMM) | Cetus (CLMM) |
|--------|--------------|--------------|
| LP Token Type | `LPCoin<A, B>` (Coin - fungible) | `Position` NFT (non-fungible) |
| Splittable | Yes - split coins by amount | No - one NFT per position |
| Price Range | Full range (0, ∞) | Concentrated (tick_lower, tick_upper) |
| Capital Efficiency | Lower | Higher |
| Distribution | Split single LP coin | Create multiple positions |

---

## Chosen Approach: Multiple Positions (Option B)

Create 3 separate Position NFTs during graduation, each with proportional liquidity:

```
┌─────────────────────────────────────────────────────────────────┐
│ CETUS MULTI-POSITION GRADUATION                                  │
└─────────────────────────────────────────────────────────────────┘

Total Liquidity from Bonding Curve:
├── SUI: X amount
└── Token: Y amount

Position Distribution:
├── Creator Position (2.5%)
│   ├── Liquidity: 2.5% of total
│   ├── Destination: Vest via nft_vesting (6mo cliff)
│   └── Beneficiary: Token creator
│
├── Protocol Position (2.5%)
│   ├── Liquidity: 2.5% of total
│   ├── Destination: Platform treasury (direct)
│   └── Owner: Platform admin
│
└── DAO Position (95%)
    ├── Liquidity: 95% of total
    ├── Destination: DAO treasury
    └── Owner: DAO governance
```

---

## Cetus CLMM Concepts

### Position NFT Structure

```move
// From cetus_clmm::position
public struct Position has key, store {
    id: UID,
    pool_id: ID,                    // Which pool this belongs to
    tick_lower: I32,                // Lower price bound
    tick_upper: I32,                // Upper price bound
    liquidity: u128,                // Liquidity amount
    fee_growth_inside_a: u128,      // Accumulated fees token A
    fee_growth_inside_b: u128,      // Accumulated fees token B
    tokens_owed_a: u64,             // Uncollected fees token A
    tokens_owed_b: u64,             // Uncollected fees token B
}
```

### Key Functions

```move
// Create pool with initial position
pool_creator::create_pool_v3<A, B>(
    config: &GlobalConfig,
    pools: &mut Pools,
    tick_spacing: u32,           // Fee tier (60 = 0.3%)
    sqrt_price: u128,            // Initial price
    url: String,
    tick_lower: I32,
    tick_upper: I32,
    coin_a: Coin<A>,
    coin_b: Coin<B>,
    fix_amount_a: bool,
    clock: &Clock,
    ctx: &mut TxContext,
) -> (Position, Coin<A>, Coin<B>)

// Add liquidity to existing pool
liquidity::add_liquidity_fix_coin<A, B>(
    config: &GlobalConfig,
    pool: &mut Pool<A, B>,
    position: &mut Position,
    coin_a: Coin<A>,
    coin_b: Coin<B>,
    amount: u64,
    fix_amount_a: bool,
    clock: &Clock,
) -> (Coin<A>, Coin<B>)

// Open new position in existing pool
position_manager::open_position<A, B>(
    config: &GlobalConfig,
    pool: &mut Pool<A, B>,
    tick_lower: I32,
    tick_upper: I32,
    ctx: &mut TxContext,
) -> Position
```

---

## Implementation Plan

### Phase 1: Update cetus_adapter.move

```move
module sui_launchpad::cetus_adapter {
    // ... existing code ...

    /// Multi-position graduation result
    public struct CetusGraduationResult<phantom T> {
        pool_id: ID,
        creator_position_id: ID,
        protocol_position_id: ID,
        dao_position_id: ID,
        total_liquidity: u128,
    }

    /// Graduate to Cetus with multiple positions
    /// Returns 3 Position NFTs for distribution
    public fun graduate_to_cetus_multi_position<T>(
        pending: PendingGraduation<T>,
        config: &LaunchpadConfig,
        cetus_config: &GlobalConfig,
        pools: &mut Pools,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (
        GraduationReceipt,
        Position,  // Creator position (2.5%)
        Position,  // Protocol position (2.5%)
        Position,  // DAO position (95%)
    )

    /// Calculate liquidity split for each position
    public fun calculate_liquidity_split(
        total_sui: u64,
        total_tokens: u64,
        config: &LaunchpadConfig,
    ): (
        u64, u64,  // Creator SUI, tokens
        u64, u64,  // Protocol SUI, tokens
        u64, u64,  // DAO SUI, tokens
    )
}
```

### Phase 2: PTB Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ CETUS GRADUATION PTB                                             │
└─────────────────────────────────────────────────────────────────┘

STEP 1: Initiate Graduation
        graduation::initiate_graduation()
        → PendingGraduation<T>

STEP 2: Extract Liquidity & Calculate Splits
        cetus_adapter::graduate_to_cetus_extract()
        → (pending, sui_coin, token_coin)

        Split coins into 3 portions:
        - Creator: 2.5%
        - Protocol: 2.5%
        - DAO: 95%

STEP 3: Create Pool with DAO Position (95%)
        pool_creator::create_pool_v3<T, SUI>()
        → (dao_position, remaining_sui, remaining_token)

STEP 4: Open Creator Position (2.5%)
        position_manager::open_position()
        → creator_position

        liquidity::add_liquidity_fix_coin()
        → Add creator's 2.5% liquidity

STEP 5: Open Protocol Position (2.5%)
        position_manager::open_position()
        → protocol_position

        liquidity::add_liquidity_fix_coin()
        → Add protocol's 2.5% liquidity

STEP 6: Extract Staking Tokens (if enabled)
        graduation::extract_staking_tokens()
        → staking_reward_tokens

STEP 7: Create Staking Pool
        sui_staking::factory::create_pool_free()
        → PoolAdminCap

STEP 8: Create DAO
        sui_dao::governance::create_dao()
        → DAOAdminCap, Treasury

STEP 9: Vest Creator Position NFT
        sui_vesting::nft_vesting::create_nft_schedule()
        → NFTVestingSchedule<Position>
        (6 month cliff, then fully claimable)

STEP 10: Transfer Protocol Position
         transfer::public_transfer(protocol_position, platform_treasury)

STEP 11: Deposit DAO Position to Treasury
         sui_dao::treasury::deposit_nft()
         → Position stored in DAO treasury

STEP 12: Complete Graduation
         graduation::complete_graduation()
         → GraduationReceipt
```

---

## Files to Modify/Create

| File | Changes |
|------|---------|
| `sui_launchpad/sources/dex_adapters/cetus.move` | Add multi-position graduation functions |
| `sui_launchpad/tests/e2e_cetus_tests.move` | NEW - Full E2E tests with Position NFTs |
| `sui_dao/sources/treasury.move` | Verify NFT deposit support (should work with Bag) |
| `docs/CETUS_INTEGRATION_PLAN.md` | This plan document |

---

## Test Cases

### E2E Flow Tests
1. `test_cetus_graduation_creates_three_positions` - Verify 3 positions created
2. `test_cetus_creator_position_vested` - Creator Position in NFTVestingSchedule
3. `test_cetus_protocol_position_transferred` - Protocol Position to treasury
4. `test_cetus_dao_position_in_treasury` - DAO Position in DAO treasury
5. `test_cetus_position_liquidity_ratios` - Verify 2.5%/2.5%/95% split
6. `test_cetus_full_graduation_flow` - Complete end-to-end

### Creator Vesting Tests
7. `test_creator_cannot_claim_before_cliff` - Cliff enforcement
8. `test_creator_claims_after_cliff` - Successful claim
9. `test_creator_position_revocation` - Revoke before cliff (if revocable)

### DAO Integration Tests
10. `test_dao_position_withdrawal_proposal` - DAO votes to withdraw Position
11. `test_dao_can_collect_fees` - Collect trading fees from Position

### Staking Integration
12. `test_cetus_graduation_with_staking` - Staking pool creation works

---

## Tick Range Strategy

For graduation, use **full range** positions to maximize liquidity depth:

```move
// Full range for tick_spacing = 60 (0.3% fee tier)
const TICK_LOWER: I32 = i32::from(-887220);  // Near min tick
const TICK_UPPER: I32 = i32::from(887220);   // Near max tick
```

This ensures:
- Liquidity available at any price
- No need to manage positions
- Similar behavior to AMM

---

## Price Calculation

Initial price based on graduation amounts:

```move
// sqrt_price_x64 = sqrt(token_amount / sui_amount) * 2^64
public fun calculate_initial_sqrt_price(
    token_amount: u64,
    sui_amount: u64,
): u128 {
    // Use Cetus math library for accurate calculation
    let ratio = (token_amount as u128) << 64 / (sui_amount as u128);
    tick_math::get_sqrt_price_at_tick(price_to_tick(ratio))
}
```

---

## Dependencies

```toml
# Move.toml - Uncomment when Cetus is available
[dependencies]
CetusCLMM = { git = "https://github.com/CetusProtocol/cetus-clmm-interface.git", subdir = "sui/cetus-clmm", rev = "main" }
IntegerMate = { git = "https://github.com/CetusProtocol/integer-mate.git", subdir = "sui/integer_mate", rev = "main" }
```

---

## Mock Implementation for Testing

Since Cetus dependency may not be available, create mock structures:

```move
#[test_only]
module sui_launchpad::mock_cetus {
    /// Mock Position for testing
    public struct MockPosition has key, store {
        id: UID,
        pool_id: ID,
        tick_lower: u32,
        tick_upper: u32,
        liquidity: u128,
    }

    public fun create_mock_position(
        pool_id: ID,
        liquidity: u128,
        ctx: &mut TxContext,
    ): MockPosition {
        MockPosition {
            id: object::new(ctx),
            pool_id,
            tick_lower: 0,
            tick_upper: 887220,
            liquidity,
        }
    }
}
```

---

## Verification Checklist

- [ ] 3 Position NFTs created with correct liquidity ratios
- [ ] Creator Position in NFTVestingSchedule with 6mo cliff
- [ ] Protocol Position transferred to platform treasury
- [ ] DAO Position deposited in DAO treasury
- [ ] Staking pool created with reward tokens
- [ ] DAO governance created
- [ ] Trading blocked on bonding curve after graduation
- [ ] All events emitted correctly
- [ ] All 541+ tests passing

---

## Next Steps

1. Create mock Cetus structures for testing
2. Implement multi-position graduation in cetus_adapter.move
3. Create e2e_cetus_tests.move
4. Verify integration with sui_vesting::nft_vesting
5. Verify integration with sui_dao::treasury
6. Update documentation
