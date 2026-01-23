/// SuiDex v2 Adapter
/// Handles liquidity pool creation on SuiDex (suitrump_dex)
///
/// ## Integration Requirements
/// To use real SuiDex integration:
/// 1. Clone: git clone https://github.com/Mohsinsiddi/suidex-v2.git ../suidex-v2
/// 2. Uncomment dependency in Move.toml: SuiTrumpDex = { local = "../suidex-v2" }
/// 3. Uncomment the imports and real implementation below
///
/// ## SuiDex v2 Architecture
/// - Package: suitrump_dex
/// - Factory: Creates and manages pairs
/// - Router: User-facing interface for create_pair, add_liquidity
/// - Pair<T0, T1>: AMM pool
/// - LPCoin<T0, T1>: LP token type
///
/// ## Key Functions (from suitrump_dex::router)
/// - create_pair<T0, T1>(router, factory, token0_name, token1_name, ctx)
/// - add_liquidity<T0, T1>(router, factory, pair, coin_a, coin_b, amounts..., deadline, clock, ctx)
module sui_launchpad::suidex_adapter {

    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::Clock;

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::graduation::{Self, PendingGraduation, GraduationReceipt};
    use sui_launchpad::registry::Registry;

    // ═══════════════════════════════════════════════════════════════════════════
    // UNCOMMENT WHEN SuiDex DEPENDENCY IS ADDED
    // ═══════════════════════════════════════════════════════════════════════════
    // use suitrump_dex::router::{Self, Router};
    // use suitrump_dex::factory::{Self, Factory};
    // use suitrump_dex::pair::{Self, Pair, LPCoin};

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    const EWrongDexType: u64 = 630;
    const ESuiDexNotConfigured: u64 = 631;
    const EInsufficientLiquidity: u64 = 632;
    const EPairCreationFailed: u64 = 633;
    const ELiquidityAddFailed: u64 = 634;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Default swap fee for SuiDex (0.3%)
    const DEFAULT_SWAP_FEE_BPS: u64 = 30;

    /// Minimum liquidity to prevent division by zero
    const MINIMUM_LIQUIDITY: u64 = 1000;

    /// Slippage tolerance (1% = 100 bps)
    const DEFAULT_SLIPPAGE_BPS: u64 = 100;

    // ═══════════════════════════════════════════════════════════════════════════
    // SUIDEX SHARED OBJECT WRAPPER
    // ═══════════════════════════════════════════════════════════════════════════

    /// Wrapper to hold SuiDex shared object references
    /// These are passed by the caller who has access to the deployed SuiDex objects
    public struct SuiDexObjects<phantom T> has drop {
        factory_id: ID,
        router_id: ID,
        pair_id: Option<ID>, // None if pair doesn't exist yet
    }

    /// Create SuiDex objects reference
    public fun create_suidex_objects<T>(
        factory_id: ID,
        router_id: ID,
        pair_id: Option<ID>,
    ): SuiDexObjects<T> {
        SuiDexObjects { factory_id, router_id, pair_id }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GRADUATION TO SUIDEX - PLACEHOLDER VERSION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Graduate token to SuiDex - Placeholder implementation
    ///
    /// This version extracts liquidity and returns coins for manual DEX interaction.
    /// Use this when SuiDex dependency is not available.
    ///
    /// Flow:
    /// 1. Call this function to get coins
    /// 2. Manually call SuiDex create_pair and add_liquidity
    /// 3. Call complete_graduation_manual with the pool ID
    public fun graduate_to_suidex_extract<T>(
        mut pending: PendingGraduation<T>,
        config: &LaunchpadConfig,
        ctx: &mut TxContext,
    ): (PendingGraduation<T>, Coin<SUI>, Coin<T>) {
        // Validate this is meant for SuiDex
        assert!(graduation::pending_dex_type(&pending) == config::dex_suidex(), EWrongDexType);

        // Validate SuiDex is configured
        assert!(config::suidex_package(config) != @0x0, ESuiDexNotConfigured);

        // Extract liquidity
        let sui_coin = graduation::extract_all_sui(&mut pending, ctx);
        let token_coin = graduation::extract_all_tokens(&mut pending, ctx);

        // Validate minimum liquidity
        assert!(coin::value(&sui_coin) >= MINIMUM_LIQUIDITY, EInsufficientLiquidity);
        assert!(coin::value(&token_coin) >= MINIMUM_LIQUIDITY, EInsufficientLiquidity);

        // Return pending (for later completion) and coins
        (pending, sui_coin, token_coin)
    }

    /// Complete graduation after manually creating SuiDex pool
    ///
    /// Call this after:
    /// 1. graduate_to_suidex_extract() to get coins
    /// 2. SuiDex create_pair() to create the pair
    /// 3. SuiDex add_liquidity() to add liquidity and get LP tokens
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
    // GRADUATION TO SUIDEX - FULL VERSION (REQUIRES DEPENDENCY)
    // ═══════════════════════════════════════════════════════════════════════════

    // /// Graduate token to SuiDex - Full implementation
    // /// Requires SuiTrumpDex dependency in Move.toml
    // ///
    // /// This handles the entire graduation flow:
    // /// 1. Extract SUI and tokens from PendingGraduation
    // /// 2. Create pair on SuiDex (if doesn't exist)
    // /// 3. Add initial liquidity
    // /// 4. Distribute LP tokens (creator vested, community burned/dao)
    // /// 5. Complete graduation with pool ID
    // public fun graduate_to_suidex<T>(
    //     mut pending: PendingGraduation<T>,
    //     config: &LaunchpadConfig,
    //     registry: &mut Registry,
    //     router: &Router,
    //     factory: &mut Factory,
    //     pair: &mut Pair<T, SUI>,
    //     clock: &Clock,
    //     ctx: &mut TxContext,
    // ): GraduationReceipt {
    //     // Validate this is meant for SuiDex
    //     assert!(graduation::pending_dex_type(&pending) == config::dex_suidex(), EWrongDexType);
    //
    //     // Validate SuiDex is configured
    //     assert!(config::suidex_package(config) != @0x0, ESuiDexNotConfigured);
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
    //     // Calculate minimum amounts with slippage tolerance
    //     let min_sui = sui_amount - (sui_amount * DEFAULT_SLIPPAGE_BPS / 10000);
    //     let min_token = token_amount - (token_amount * DEFAULT_SLIPPAGE_BPS / 10000);
    //
    //     // Get token name for SuiDex (type name)
    //     let token_name = std::type_name::into_string(std::type_name::get<T>());
    //     let sui_name = std::ascii::string(b"0x2::sui::SUI");
    //
    //     // Get deadline (current time + 10 minutes)
    //     let deadline = clock.timestamp_ms() + 600_000;
    //
    //     // Add liquidity to SuiDex
    //     // Note: Pair must already exist (created separately or in PTB)
    //     router::add_liquidity<T, SUI>(
    //         router,
    //         factory,
    //         pair,
    //         token_coin,
    //         sui_coin,
    //         (token_amount as u256),
    //         (sui_amount as u256),
    //         (min_token as u256),
    //         (min_sui as u256),
    //         token_name,
    //         sui_name,
    //         deadline,
    //         clock,
    //         ctx,
    //     );
    //
    //     // Get pool ID
    //     let pool_id = object::id(pair);
    //
    //     // TODO: Get LP tokens from the add_liquidity call
    //     // SuiDex mints LP tokens to the sender
    //     // We need to collect them and distribute
    //
    //     // For now, complete with placeholder LP amounts
    //     // In real implementation, query LP balance and distribute
    //     let total_lp_tokens = 0; // Would come from LP balance query
    //     let creator_lp_tokens = 0;
    //     let community_lp_tokens = 0;
    //
    //     // Complete graduation
    //     graduation::complete_graduation(
    //         pending,
    //         registry,
    //         pool_id,
    //         total_lp_tokens,
    //         creator_lp_tokens,
    //         community_lp_tokens,
    //         clock,
    //         ctx,
    //     )
    // }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Get default swap fee in basis points
    public fun default_swap_fee_bps(): u64 {
        DEFAULT_SWAP_FEE_BPS
    }

    /// Get minimum liquidity constant
    public fun minimum_liquidity(): u64 {
        MINIMUM_LIQUIDITY
    }

    /// Get default slippage in basis points
    public fun default_slippage_bps(): u64 {
        DEFAULT_SLIPPAGE_BPS
    }

    /// Calculate minimum amount after slippage
    public fun calculate_min_amount(amount: u64, slippage_bps: u64): u64 {
        amount - (amount * slippage_bps / 10000)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_calculate_min_amount() {
        // 1% slippage on 10000
        let min = calculate_min_amount(10000, 100);
        assert!(min == 9900, 0);

        // 0.5% slippage on 20000
        let min2 = calculate_min_amount(20000, 50);
        assert!(min2 == 19900, 1);

        // 0% slippage
        let min3 = calculate_min_amount(10000, 0);
        assert!(min3 == 10000, 2);
    }

    #[test]
    fun test_constants() {
        assert!(default_swap_fee_bps() == 30, 0);
        assert!(minimum_liquidity() == 1000, 1);
        assert!(default_slippage_bps() == 100, 2);
    }
}
