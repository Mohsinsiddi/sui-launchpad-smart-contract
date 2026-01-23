/// FlowX CLMM Adapter
/// Handles liquidity pool creation on FlowX Finance
///
/// ## Integration Requirements
/// To use real FlowX integration:
/// 1. Clone: git clone https://github.com/FlowX-Finance/clmm-contracts.git ../clmm-contracts
/// 2. Uncomment dependency in Move.toml: FlowXCLMM = { local = "../clmm-contracts" }
/// 3. Uncomment the imports and real implementation below
///
/// ## FlowX CLMM Architecture
/// - Package: flowx_clmm
/// - PoolRegistry: Pool registry
/// - PositionRegistry: Position registry
/// - Pool<X, Y>: CLMM pool
/// - Position: Position NFT (represents LP position)
/// - Versioned: Version control for upgrades
///
/// ## Key Functions (from flowx_clmm)
/// - create_and_initialize_pool_v2<X, Y>(pool_registry, fee_rate, sqrt_price, metadata_x, metadata_y, versioned, clock, ctx)
/// - open_position<X, Y>(position_registry, pool_registry, fee_rate, tick_lower, tick_upper, versioned, ctx)
/// - increase_liquidity<X, Y>(pool_registry, position, coin_x, coin_y, amount_x_min, amount_y_min, deadline, versioned, clock, ctx)
module sui_launchpad::flowx_adapter {

    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::Clock;

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::graduation::{Self, PendingGraduation, GraduationReceipt};
    use sui_launchpad::registry::Registry;

    // ═══════════════════════════════════════════════════════════════════════════
    // UNCOMMENT WHEN FlowX DEPENDENCY IS ADDED
    // ═══════════════════════════════════════════════════════════════════════════
    // use flowx_clmm::pool_manager::{Self, PoolRegistry};
    // use flowx_clmm::position_manager::{Self, PositionRegistry};
    // use flowx_clmm::pool::Pool;
    // use flowx_clmm::position::Position;
    // use flowx_clmm::versioned::Versioned;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    const EWrongDexType: u64 = 620;
    const EFlowXNotConfigured: u64 = 621;
    const EInsufficientLiquidity: u64 = 622;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Default fee rate (0.3% = 3000 basis points)
    const DEFAULT_FEE_RATE: u64 = 3000;

    /// Minimum liquidity to prevent division by zero
    const MINIMUM_LIQUIDITY: u64 = 1000;

    /// Full range tick lower (near minimum)
    /// FlowX uses I32 type for ticks
    const FULL_RANGE_TICK_LOWER: u32 = 4294523660; // -443636 as u32

    /// Full range tick upper (near maximum)
    const FULL_RANGE_TICK_UPPER: u32 = 443580;

    /// sqrt_price_x64 for 1:1 ratio
    const SQRT_PRICE_1_TO_1: u128 = 18446744073709551616; // 1 << 64

    /// Default deadline offset (10 minutes in ms)
    const DEFAULT_DEADLINE_OFFSET_MS: u64 = 600_000;

    // ═══════════════════════════════════════════════════════════════════════════
    // FLOWX SHARED OBJECT WRAPPER
    // ═══════════════════════════════════════════════════════════════════════════

    /// Wrapper to hold FlowX shared object references
    public struct FlowXObjects has drop {
        pool_registry_id: ID,
        position_registry_id: ID,
        versioned_id: ID,
    }

    /// Create FlowX objects reference
    public fun create_flowx_objects(
        pool_registry_id: ID,
        position_registry_id: ID,
        versioned_id: ID,
    ): FlowXObjects {
        FlowXObjects { pool_registry_id, position_registry_id, versioned_id }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GRADUATION TO FLOWX - PLACEHOLDER VERSION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Graduate token to FlowX - Placeholder implementation
    ///
    /// This version extracts liquidity and returns coins for manual DEX interaction.
    /// Use this when FlowX dependency is not available.
    ///
    /// Flow:
    /// 1. Call this function to get coins
    /// 2. Manually call FlowX create_and_initialize_pool_v2 + open_position + increase_liquidity
    /// 3. Call complete_graduation_manual with the pool ID
    public fun graduate_to_flowx_extract<T>(
        mut pending: PendingGraduation<T>,
        config: &LaunchpadConfig,
        ctx: &mut TxContext,
    ): (PendingGraduation<T>, Coin<SUI>, Coin<T>) {
        // Validate this is meant for FlowX
        assert!(graduation::pending_dex_type(&pending) == config::dex_flowx(), EWrongDexType);

        // Validate FlowX is configured
        assert!(config::flowx_package(config) != @0x0, EFlowXNotConfigured);

        // Extract liquidity
        let sui_coin = graduation::extract_all_sui(&mut pending, ctx);
        let token_coin = graduation::extract_all_tokens(&mut pending, ctx);

        // Validate minimum liquidity
        assert!(coin::value(&sui_coin) >= MINIMUM_LIQUIDITY, EInsufficientLiquidity);
        assert!(coin::value(&token_coin) >= MINIMUM_LIQUIDITY, EInsufficientLiquidity);

        // Return pending (for later completion) and coins
        (pending, sui_coin, token_coin)
    }

    /// Complete graduation after manually creating FlowX pool
    ///
    /// Call this after:
    /// 1. graduate_to_flowx_extract() to get coins
    /// 2. FlowX create_and_initialize_pool_v2() to create pool
    /// 3. FlowX open_position() to create position
    /// 4. FlowX increase_liquidity() to add liquidity
    /// 5. Handle Position NFT distribution
    public fun complete_graduation_manual<T>(
        pending: PendingGraduation<T>,
        registry: &mut Registry,
        dex_pool_id: ID,
        total_lp_tokens: u64,
        creator_lp_tokens: u64,
        community_lp_tokens: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): GraduationReceipt {
        graduation::complete_graduation(
            pending,
            registry,
            dex_pool_id,
            total_lp_tokens,
            creator_lp_tokens,
            community_lp_tokens,
            clock,
            ctx,
        )
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GRADUATION TO FLOWX - FULL VERSION (REQUIRES DEPENDENCY)
    // ═══════════════════════════════════════════════════════════════════════════

    // /// Graduate token to FlowX - Full implementation
    // /// Requires FlowXCLMM dependency in Move.toml
    // ///
    // /// This handles the entire graduation flow:
    // /// 1. Extract SUI and tokens from PendingGraduation
    // /// 2. Create pool on FlowX
    // /// 3. Open position and add liquidity
    // /// 4. Returns Position NFT
    // /// 5. Complete graduation with pool ID
    // public fun graduate_to_flowx<T>(
    //     mut pending: PendingGraduation<T>,
    //     config: &LaunchpadConfig,
    //     registry: &mut Registry,
    //     pool_registry: &mut PoolRegistry,
    //     position_registry: &mut PositionRegistry,
    //     versioned: &Versioned,
    //     token_metadata: &CoinMetadata<T>,
    //     sui_metadata: &CoinMetadata<SUI>,
    //     clock: &Clock,
    //     ctx: &mut TxContext,
    // ): (GraduationReceipt, Position) {
    //     // Validate this is meant for FlowX
    //     assert!(graduation::pending_dex_type(&pending) == config::dex_flowx(), EWrongDexType);
    //
    //     // Validate FlowX is configured
    //     assert!(config::flowx_package(config) != @0x0, EFlowXNotConfigured);
    //
    //     // Extract liquidity
    //     let sui_coin = graduation::extract_all_sui(&mut pending, ctx);
    //     let token_coin = graduation::extract_all_tokens(&mut pending, ctx);
    //
    //     let sui_amount = coin::value(&sui_coin);
    //     let token_amount = coin::value(&token_coin);
    //
    //     // Validate minimum liquidity
    //     assert!(sui_amount >= MINIMUM_LIQUIDITY, EInsufficientLiquidity);
    //     assert!(token_amount >= MINIMUM_LIQUIDITY, EInsufficientLiquidity);
    //
    //     // Calculate initial sqrt price
    //     let initial_sqrt_price = calculate_sqrt_price_x64(token_amount, sui_amount);
    //
    //     // 1. Create and initialize pool
    //     pool_manager::create_and_initialize_pool_v2<T, SUI>(
    //         pool_registry,
    //         DEFAULT_FEE_RATE,
    //         initial_sqrt_price,
    //         token_metadata,
    //         sui_metadata,
    //         versioned,
    //         clock,
    //         ctx,
    //     );
    //
    //     // 2. Open position with full range
    //     let position = position_manager::open_position<T, SUI>(
    //         position_registry,
    //         pool_registry,
    //         DEFAULT_FEE_RATE,
    //         FULL_RANGE_TICK_LOWER, // tick_lower_index (I32)
    //         FULL_RANGE_TICK_UPPER, // tick_upper_index (I32)
    //         versioned,
    //         ctx,
    //     );
    //
    //     // 3. Add liquidity
    //     let deadline = clock.timestamp_ms() + DEFAULT_DEADLINE_OFFSET_MS;
    //     let (remaining_token, remaining_sui) = position_manager::increase_liquidity<T, SUI>(
    //         pool_registry,
    //         &mut position,
    //         token_coin,
    //         sui_coin,
    //         0, // amount_x_min (accept any)
    //         0, // amount_y_min (accept any)
    //         deadline,
    //         versioned,
    //         clock,
    //         ctx,
    //     );
    //
    //     // Handle remaining coins
    //     if (coin::value(&remaining_token) > 0) {
    //         transfer::public_transfer(remaining_token, ctx.sender());
    //     } else {
    //         coin::destroy_zero(remaining_token);
    //     };
    //
    //     if (coin::value(&remaining_sui) > 0) {
    //         transfer::public_transfer(remaining_sui, ctx.sender());
    //     } else {
    //         coin::destroy_zero(remaining_sui);
    //     };
    //
    //     // Get pool ID (from position or pool registry)
    //     let pool_id = position::pool_id(&position);
    //
    //     // Get liquidity amount as "LP tokens"
    //     let total_lp = position::liquidity(&position);
    //
    //     // Complete graduation
    //     let receipt = graduation::complete_graduation(
    //         pending,
    //         registry,
    //         pool_id,
    //         (total_lp as u64),
    //         0,
    //         (total_lp as u64),
    //         clock,
    //         ctx,
    //     );
    //
    //     (receipt, position)
    // }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Get default fee rate
    public fun default_fee_rate(): u64 {
        DEFAULT_FEE_RATE
    }

    /// Get minimum liquidity constant
    public fun minimum_liquidity(): u64 {
        MINIMUM_LIQUIDITY
    }

    /// Get full range tick lower
    public fun full_range_tick_lower(): u32 {
        FULL_RANGE_TICK_LOWER
    }

    /// Get full range tick upper
    public fun full_range_tick_upper(): u32 {
        FULL_RANGE_TICK_UPPER
    }

    /// Get default deadline offset in ms
    public fun default_deadline_offset_ms(): u64 {
        DEFAULT_DEADLINE_OFFSET_MS
    }

    /// Calculate sqrt_price_x64 from token amounts
    /// Same as Cetus calculation
    public fun calculate_sqrt_price_x64(token_amount: u64, sui_amount: u64): u128 {
        if (token_amount == sui_amount) {
            return SQRT_PRICE_1_TO_1
        };

        let ratio = ((token_amount as u128) << 64) / (sui_amount as u128);
        let sqrt_ratio = ratio >> 32;

        if (sqrt_ratio == 0) {
            1
        } else {
            sqrt_ratio
        }
    }

    /// Calculate deadline timestamp
    public fun calculate_deadline(clock: &Clock): u64 {
        clock.timestamp_ms() + DEFAULT_DEADLINE_OFFSET_MS
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_calculate_sqrt_price_1_to_1() {
        let price = calculate_sqrt_price_x64(1000000, 1000000);
        assert!(price == SQRT_PRICE_1_TO_1, 0);
    }

    #[test]
    fun test_constants() {
        assert!(default_fee_rate() == 3000, 0);
        assert!(minimum_liquidity() == 1000, 1);
        assert!(default_deadline_offset_ms() == 600_000, 2);
    }
}
