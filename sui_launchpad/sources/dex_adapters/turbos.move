/// Turbos CLMM Adapter
/// Handles liquidity pool creation on Turbos Finance
///
/// ## IMPORTANT: NOT DEPLOYABLE LOCALLY
/// Turbos Finance only provides interface stubs (all functions `abort 0`).
/// The full implementation is NOT open-source.
///
/// ## Usage Options
/// 1. **Testnet/Mainnet**: Use this adapter when Turbos contracts are already deployed
/// 2. **Local Testing**: Use SuiDex, Cetus, or FlowX instead (they have full implementations)
///
/// ## Turbos Architecture (for reference)
/// - Package: turbos_clmm
/// - PoolConfig: Pool factory configuration
/// - Positions: Position registry
/// - Pool<A, B>: CLMM pool
/// - Position: Position NFT
///
/// ## Key Functions (from turbos_clmm - interface only)
/// - create_pool<A, B>(pool_config, fee_type, sqrt_price, positions, coin_a, coin_b, tick_lower, tick_upper, clock, ctx)
/// - increase_liquidity<A, B>(pool, positions, position, coin_a, coin_b, amount_a_min, amount_b_min, deadline, clock, ctx)
module sui_launchpad::turbos_adapter {

    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::Clock;

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::graduation::{Self, PendingGraduation, GraduationReceipt};
    use sui_launchpad::registry::Registry;

    // ═══════════════════════════════════════════════════════════════════════════
    // NOTE: Turbos interface repo (turbos-sui-move-interface) only contains stubs
    // All functions abort with `abort 0` - NOT a real implementation
    // Use on testnet/mainnet where Turbos contracts are already deployed
    // ═══════════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    const EWrongDexType: u64 = 610;
    const ETurbosNotConfigured: u64 = 611;
    const EInsufficientLiquidity: u64 = 612;
    const ETurbosNotDeployableLocally: u64 = 613;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Default tick spacing for standard pools (0.3% fee tier)
    const DEFAULT_TICK_SPACING: u32 = 60;

    /// Default fee tier (0.3% = 3000 bps)
    const DEFAULT_FEE_BPS: u64 = 3000;

    /// Minimum liquidity to prevent division by zero
    const MINIMUM_LIQUIDITY: u64 = 1000;

    /// Full range tick lower
    const FULL_RANGE_TICK_LOWER: u32 = 4294523660;

    /// Full range tick upper
    const FULL_RANGE_TICK_UPPER: u32 = 443580;

    /// sqrt_price_x64 for 1:1 ratio
    const SQRT_PRICE_1_TO_1: u128 = 18446744073709551616;

    // ═══════════════════════════════════════════════════════════════════════════
    // GRADUATION TO TURBOS - PLACEHOLDER VERSION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Graduate token to Turbos - Placeholder implementation
    ///
    /// This extracts liquidity and returns coins for manual DEX interaction.
    /// On testnet/mainnet, construct a PTB to:
    /// 1. Call this function to get coins
    /// 2. Call Turbos create_pool
    /// 3. Call complete_graduation_manual with pool ID
    public fun graduate_to_turbos_extract<T>(
        mut pending: PendingGraduation<T>,
        config: &LaunchpadConfig,
        ctx: &mut TxContext,
    ): (PendingGraduation<T>, Coin<SUI>, Coin<T>) {
        // Validate this is meant for Turbos
        assert!(graduation::pending_dex_type(&pending) == config::dex_turbos(), EWrongDexType);

        // Validate Turbos is configured
        assert!(config::turbos_package(config) != @0x0, ETurbosNotConfigured);

        // Extract liquidity
        let sui_coin = graduation::extract_all_sui(&mut pending, ctx);
        let token_coin = graduation::extract_all_tokens(&mut pending, ctx);

        // Validate minimum liquidity
        assert!(coin::value(&sui_coin) >= MINIMUM_LIQUIDITY, EInsufficientLiquidity);
        assert!(coin::value(&token_coin) >= MINIMUM_LIQUIDITY, EInsufficientLiquidity);

        // Return pending (for later completion) and coins
        (pending, sui_coin, token_coin)
    }

    /// Complete graduation after manually creating Turbos pool
    ///
    /// Call this after:
    /// 1. graduate_to_turbos_extract() to get coins
    /// 2. Turbos create_pool() on testnet/mainnet
    /// 3. Handle Position NFT distribution
    public fun complete_graduation_manual<T>(
        pending: PendingGraduation<T>,
        registry: &mut Registry,
        dex_pool_id: ID,
        sui_to_liquidity: u64,
        tokens_to_liquidity: u64,
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
            sui_to_liquidity,
            tokens_to_liquidity,
            total_lp_tokens,
            creator_lp_tokens,
            community_lp_tokens,
            clock,
            ctx,
        )
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Get default tick spacing
    public fun default_tick_spacing(): u32 {
        DEFAULT_TICK_SPACING
    }

    /// Get default fee in basis points
    public fun default_fee_bps(): u64 {
        DEFAULT_FEE_BPS
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

    /// Calculate sqrt_price_x64 from token amounts
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

    // ═══════════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_constants() {
        assert!(default_tick_spacing() == 60, 0);
        assert!(default_fee_bps() == 3000, 1);
        assert!(minimum_liquidity() == 1000, 2);
    }

    #[test]
    fun test_calculate_sqrt_price_1_to_1() {
        let price = calculate_sqrt_price_x64(1000000, 1000000);
        assert!(price == SQRT_PRICE_1_TO_1, 0);
    }
}
