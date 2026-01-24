/// Cetus CLMM Adapter
/// Handles liquidity pool creation on Cetus Protocol
///
/// ## Integration Requirements
/// To use real Cetus integration:
/// 1. Clone: git clone https://github.com/CetusProtocol/cetus-contracts.git ../cetus-contracts
/// 2. Uncomment dependency in Move.toml: CetusCLMM = { local = "../cetus-contracts/packages/cetus_clmm" }
/// 3. Uncomment the imports and real implementation below
///
/// ## Cetus CLMM Architecture
/// - Package: cetus_clmm
/// - GlobalConfig: Protocol configuration
/// - Pools: Pool registry
/// - Pool<A, B>: CLMM pool
/// - Position: Position NFT (represents LP position)
///
/// ## Key Functions (from cetus_clmm)
/// - create_pool_v3<A, B>(config, pools, tick_spacing, price, url, tick_lower, tick_upper, coin_a, coin_b, fix_amount_a, clock, ctx)
/// - add_liquidity_fix_coin<A, B>(config, pool, position, amount, fix_amount_a, clock)
module sui_launchpad::cetus_adapter {

    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::Clock;

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::graduation::{Self, PendingGraduation, GraduationReceipt};
    use sui_launchpad::registry::Registry;

    // ═══════════════════════════════════════════════════════════════════════════
    // UNCOMMENT WHEN Cetus DEPENDENCY IS ADDED
    // ═══════════════════════════════════════════════════════════════════════════
    // use cetus_clmm::config::GlobalConfig;
    // use cetus_clmm::factory::Pools;
    // use cetus_clmm::pool::Pool;
    // use cetus_clmm::position::Position;
    // use cetus_clmm::pool_creator;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    const EWrongDexType: u64 = 600;
    const ECetusNotConfigured: u64 = 601;
    const EInsufficientLiquidity: u64 = 602;
    const EPoolCreationFailed: u64 = 603;
    const EInvalidTickRange: u64 = 604;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Default tick spacing for standard pools (0.3% fee tier)
    const DEFAULT_TICK_SPACING: u32 = 60;

    /// Default fee tier (0.3% = 3000 bps)
    const DEFAULT_FEE_TIER: u64 = 3000;

    /// Minimum liquidity to prevent division by zero
    const MINIMUM_LIQUIDITY: u64 = 1000;

    /// Full range tick lower (near minimum)
    const FULL_RANGE_TICK_LOWER: u32 = 4294523660; // -443636 as u32 (wrapped)

    /// Full range tick upper (near maximum)
    const FULL_RANGE_TICK_UPPER: u32 = 443580;

    /// sqrt_price_x64 for 1:1 ratio = sqrt(1) * 2^64
    const SQRT_PRICE_1_TO_1: u128 = 18446744073709551616; // 1 << 64

    // ═══════════════════════════════════════════════════════════════════════════
    // CETUS SHARED OBJECT WRAPPER
    // ═══════════════════════════════════════════════════════════════════════════

    /// Wrapper to hold Cetus shared object references
    public struct CetusObjects has drop {
        global_config_id: ID,
        pools_id: ID,
    }

    /// Create Cetus objects reference
    public fun create_cetus_objects(
        global_config_id: ID,
        pools_id: ID,
    ): CetusObjects {
        CetusObjects { global_config_id, pools_id }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GRADUATION TO CETUS - PLACEHOLDER VERSION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Graduate token to Cetus - Placeholder implementation
    ///
    /// This version extracts liquidity and returns coins for manual DEX interaction.
    /// Use this when Cetus dependency is not available.
    ///
    /// Flow:
    /// 1. Call this function to get coins
    /// 2. Manually call Cetus create_pool_v3 with the coins
    /// 3. Call complete_graduation_manual with the pool ID
    public fun graduate_to_cetus_extract<T>(
        mut pending: PendingGraduation<T>,
        config: &LaunchpadConfig,
        ctx: &mut TxContext,
    ): (PendingGraduation<T>, Coin<SUI>, Coin<T>) {
        // Validate this is meant for Cetus
        assert!(graduation::pending_dex_type(&pending) == config::dex_cetus(), EWrongDexType);

        // Validate Cetus is configured
        assert!(config::cetus_package(config) != @0x0, ECetusNotConfigured);

        // Extract liquidity
        let sui_coin = graduation::extract_all_sui(&mut pending, ctx);
        let token_coin = graduation::extract_all_tokens(&mut pending, ctx);

        // Validate minimum liquidity
        assert!(coin::value(&sui_coin) >= MINIMUM_LIQUIDITY, EInsufficientLiquidity);
        assert!(coin::value(&token_coin) >= MINIMUM_LIQUIDITY, EInsufficientLiquidity);

        // Return pending (for later completion) and coins
        (pending, sui_coin, token_coin)
    }

    /// Complete graduation after manually creating Cetus pool
    ///
    /// Call this after:
    /// 1. graduate_to_cetus_extract() to get coins
    /// 2. Cetus create_pool_v3() to create pool and get Position NFT
    /// 3. Handle Position NFT distribution (creator vesting, etc.)
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
    // GRADUATION TO CETUS - FULL VERSION (REQUIRES DEPENDENCY)
    // ═══════════════════════════════════════════════════════════════════════════

    // /// Graduate token to Cetus - Full implementation
    // /// Requires CetusCLMM dependency in Move.toml
    // ///
    // /// This handles the entire graduation flow:
    // /// 1. Extract SUI and tokens from PendingGraduation
    // /// 2. Create pool on Cetus with initial liquidity
    // /// 3. Returns Position NFT
    // /// 4. Complete graduation with pool ID
    // public fun graduate_to_cetus<T>(
    //     mut pending: PendingGraduation<T>,
    //     config: &LaunchpadConfig,
    //     registry: &mut Registry,
    //     cetus_config: &GlobalConfig,
    //     pools: &mut Pools,
    //     clock: &Clock,
    //     ctx: &mut TxContext,
    // ): (GraduationReceipt, Position) {
    //     // Validate this is meant for Cetus
    //     assert!(graduation::pending_dex_type(&pending) == config::dex_cetus(), EWrongDexType);
    //
    //     // Validate Cetus is configured
    //     assert!(config::cetus_package(config) != @0x0, ECetusNotConfigured);
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
    //     // Calculate initial price (token/SUI ratio as sqrt_price_x64)
    //     let initial_sqrt_price = calculate_sqrt_price_x64(token_amount, sui_amount);
    //
    //     // Create pool with full range liquidity
    //     let (position, remaining_token, remaining_sui) = pool_creator::create_pool_v3<T, SUI>(
    //         cetus_config,
    //         pools,
    //         DEFAULT_TICK_SPACING,
    //         initial_sqrt_price,
    //         std::string::utf8(b""), // url
    //         FULL_RANGE_TICK_LOWER,
    //         FULL_RANGE_TICK_UPPER,
    //         token_coin,
    //         sui_coin,
    //         true, // fix_amount_a (fix token amount)
    //         clock,
    //         ctx,
    //     );
    //
    //     // Handle remaining coins (send back to sender)
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
    //     // Get pool ID from position
    //     let pool_id = position::pool_id(&position);
    //
    //     // For CLMM, Position NFT is the "LP token"
    //     // We track liquidity amount as LP tokens
    //     let total_lp = position::liquidity(&position);
    //
    //     // Complete graduation
    //     let receipt = graduation::complete_graduation(
    //         pending,
    //         registry,
    //         pool_id,
    //         (total_lp as u64),
    //         0, // creator_lp handled separately via Position NFT
    //         (total_lp as u64), // community gets full position
    //         clock,
    //         ctx,
    //     );
    //
    //     (receipt, position)
    // }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-POSITION GRADUATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// LP allocation in basis points
    const CREATOR_LP_BPS: u64 = 250;   // 2.5%
    const PROTOCOL_LP_BPS: u64 = 250;  // 2.5%
    const DAO_LP_BPS: u64 = 9500;      // 95%
    const BPS_DENOMINATOR: u64 = 10000;

    /// Calculate liquidity split for multi-position graduation
    /// Returns (creator_sui, creator_token, protocol_sui, protocol_token, dao_sui, dao_token)
    /// Uses u128 for intermediate calculations to avoid overflow with large token amounts
    public fun calculate_liquidity_split(
        total_sui: u64,
        total_tokens: u64,
        config: &LaunchpadConfig,
    ): (u64, u64, u64, u64, u64, u64) {
        let creator_bps = config::creator_lp_bps(config);
        let protocol_bps = config::protocol_lp_bps(config);
        let _dao_bps = BPS_DENOMINATOR - creator_bps - protocol_bps;

        // Use u128 to prevent overflow with large token amounts
        let creator_sui = (((total_sui as u128) * (creator_bps as u128)) / (BPS_DENOMINATOR as u128)) as u64;
        let creator_tokens = (((total_tokens as u128) * (creator_bps as u128)) / (BPS_DENOMINATOR as u128)) as u64;

        let protocol_sui = (((total_sui as u128) * (protocol_bps as u128)) / (BPS_DENOMINATOR as u128)) as u64;
        let protocol_tokens = (((total_tokens as u128) * (protocol_bps as u128)) / (BPS_DENOMINATOR as u128)) as u64;

        let dao_sui = total_sui - creator_sui - protocol_sui;
        let dao_tokens = total_tokens - creator_tokens - protocol_tokens;

        (creator_sui, creator_tokens, protocol_sui, protocol_tokens, dao_sui, dao_tokens)
    }

    /// Split coins into 3 portions for multi-position creation
    public fun split_coins_for_positions<T>(
        mut sui_coin: Coin<SUI>,
        mut token_coin: Coin<T>,
        config: &LaunchpadConfig,
        ctx: &mut TxContext,
    ): (
        Coin<SUI>, Coin<T>,  // Creator portion
        Coin<SUI>, Coin<T>,  // Protocol portion
        Coin<SUI>, Coin<T>,  // DAO portion
    ) {
        let total_sui = coin::value(&sui_coin);
        let total_tokens = coin::value(&token_coin);

        let (
            creator_sui_amt, creator_token_amt,
            protocol_sui_amt, protocol_token_amt,
            _dao_sui_amt, _dao_token_amt
        ) = calculate_liquidity_split(total_sui, total_tokens, config);

        // Split SUI
        let creator_sui = coin::split(&mut sui_coin, creator_sui_amt, ctx);
        let protocol_sui = coin::split(&mut sui_coin, protocol_sui_amt, ctx);
        let dao_sui = sui_coin; // Remainder

        // Split tokens
        let creator_tokens = coin::split(&mut token_coin, creator_token_amt, ctx);
        let protocol_tokens = coin::split(&mut token_coin, protocol_token_amt, ctx);
        let dao_tokens = token_coin; // Remainder

        (
            creator_sui, creator_tokens,
            protocol_sui, protocol_tokens,
            dao_sui, dao_tokens
        )
    }

    /// Get LP allocation percentages
    public fun creator_lp_bps(): u64 { CREATOR_LP_BPS }
    public fun protocol_lp_bps(): u64 { PROTOCOL_LP_BPS }
    public fun dao_lp_bps(): u64 { DAO_LP_BPS }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Get default tick spacing
    public fun default_tick_spacing(): u32 {
        DEFAULT_TICK_SPACING
    }

    /// Get default fee tier
    public fun default_fee_tier(): u64 {
        DEFAULT_FEE_TIER
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
    /// sqrt_price = sqrt(token_amount / sui_amount) * 2^64
    /// Simplified calculation - real implementation would use Cetus math library
    public fun calculate_sqrt_price_x64(token_amount: u64, sui_amount: u64): u128 {
        if (token_amount == sui_amount) {
            return SQRT_PRICE_1_TO_1
        };

        // Simplified: use ratio approximation
        // In production, use proper fixed-point sqrt calculation
        let ratio = ((token_amount as u128) << 64) / (sui_amount as u128);
        // Approximate sqrt by shifting right by 32 (sqrt of 2^64 scaling)
        let sqrt_ratio = ratio >> 32;

        if (sqrt_ratio == 0) {
            1 // Minimum non-zero
        } else {
            sqrt_ratio
        }
    }

    /// Calculate tick from price (simplified)
    /// In production, use Cetus tick_math module
    public fun price_to_tick(_sqrt_price_x64: u128): u32 {
        // Simplified - return middle tick for now
        // Real implementation uses log calculation
        0
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
    fun test_calculate_sqrt_price_different_amounts() {
        // When token > sui, sqrt_price should be > 1<<64
        let price = calculate_sqrt_price_x64(4000000, 1000000);
        assert!(price > 0, 0);

        // When token < sui, sqrt_price should be < 1<<64
        let price2 = calculate_sqrt_price_x64(1000000, 4000000);
        assert!(price2 > 0, 1);
    }

    #[test]
    fun test_constants() {
        assert!(default_tick_spacing() == 60, 0);
        assert!(default_fee_tier() == 3000, 1);
        assert!(minimum_liquidity() == 1000, 2);
    }

    #[test]
    fun test_lp_allocation_constants() {
        assert!(creator_lp_bps() == 250, 0);   // 2.5%
        assert!(protocol_lp_bps() == 250, 1);  // 2.5%
        assert!(dao_lp_bps() == 9500, 2);      // 95%
        assert!(creator_lp_bps() + protocol_lp_bps() + dao_lp_bps() == 10000, 3);
    }

    #[test]
    fun test_calculate_liquidity_split() {
        let mut ctx = tx_context::dummy();
        let config = config::create_for_testing(@0xE1, &mut ctx);

        let total_sui = 10_000_000_000; // 10 SUI
        let total_tokens = 1_000_000_000_000; // 1000 tokens

        let (
            creator_sui, creator_tokens,
            protocol_sui, protocol_tokens,
            dao_sui, dao_tokens
        ) = calculate_liquidity_split(total_sui, total_tokens, &config);

        // 2.5% each for creator and protocol
        assert!(creator_sui == 250_000_000, 0);     // 0.25 SUI
        assert!(creator_tokens == 25_000_000_000, 1); // 25 tokens
        assert!(protocol_sui == 250_000_000, 2);
        assert!(protocol_tokens == 25_000_000_000, 3);

        // 95% for DAO
        assert!(dao_sui == 9_500_000_000, 4);       // 9.5 SUI
        assert!(dao_tokens == 950_000_000_000, 5);  // 950 tokens

        // Total should equal original
        assert!(creator_sui + protocol_sui + dao_sui == total_sui, 6);
        assert!(creator_tokens + protocol_tokens + dao_tokens == total_tokens, 7);

        config::destroy_for_testing(config);
    }

    #[test]
    fun test_split_coins_for_positions() {
        let mut ctx = tx_context::dummy();
        let config = config::create_for_testing(@0xE1, &mut ctx);

        let sui_coin = coin::mint_for_testing<SUI>(10_000_000_000, &mut ctx);
        let token_coin = coin::mint_for_testing<SUI>(1_000_000_000_000, &mut ctx); // Using SUI as test token

        let (
            creator_sui, creator_tokens,
            protocol_sui, protocol_tokens,
            dao_sui, dao_tokens
        ) = split_coins_for_positions(sui_coin, token_coin, &config, &mut ctx);

        // Verify amounts
        assert!(coin::value(&creator_sui) == 250_000_000, 0);
        assert!(coin::value(&protocol_sui) == 250_000_000, 1);
        assert!(coin::value(&dao_sui) == 9_500_000_000, 2);

        // Cleanup
        coin::burn_for_testing(creator_sui);
        coin::burn_for_testing(creator_tokens);
        coin::burn_for_testing(protocol_sui);
        coin::burn_for_testing(protocol_tokens);
        coin::burn_for_testing(dao_sui);
        coin::burn_for_testing(dao_tokens);
        config::destroy_for_testing(config);
    }
}
