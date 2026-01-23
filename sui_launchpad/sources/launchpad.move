/// Main launchpad module - entry points and initialization
module sui_launchpad::launchpad {

    use sui::coin::{Coin, TreasuryCap, CoinMetadata};
    use sui::sui::SUI;
    use sui::clock::Clock;

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::{Self, AdminCap};
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::registry::{Self, Registry};
    use sui_launchpad::graduation::{Self, GraduationReceipt};
    // Vesting integration pending - see docs/VESTING.md
    // use sui_vesting::vesting::{Self, VestingSchedule};

    // ═══════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Called once on module publish
    /// Creates and shares config and registry, transfers AdminCap to deployer
    fun init(ctx: &mut TxContext) {
        let treasury = ctx.sender();

        // Create admin cap and transfer to deployer
        let admin_cap = access::create_admin_cap(ctx);
        transfer::public_transfer(admin_cap, treasury);

        // Create and share config
        let config = config::create_config(treasury, ctx);
        transfer::public_share_object(config);

        // Create and share registry
        let registry = registry::create_registry(ctx);
        transfer::public_share_object(registry);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TOKEN CREATION ENTRY POINTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new token pool and share it
    /// Creator provides TreasuryCap with no tokens minted
    #[allow(lint(share_owned))]
    public fun create_token<T>(
        config: &LaunchpadConfig,
        registry: &mut Registry,
        treasury_cap: TreasuryCap<T>,
        metadata: &CoinMetadata<T>,
        creator_fee_bps: u64,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Create pool
        let pool = bonding_curve::create_pool<T>(
            config,
            treasury_cap,
            metadata,
            creator_fee_bps,
            payment,
            clock,
            ctx,
        );

        // Register in registry
        registry::register_pool(registry, &pool, ctx);

        // Share pool
        transfer::public_share_object(pool);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRADING ENTRY POINTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Buy tokens from bonding curve
    public fun buy<T>(
        pool: &mut BondingPool<T>,
        config: &LaunchpadConfig,
        payment: Coin<SUI>,
        min_tokens_out: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        bonding_curve::buy(pool, config, payment, min_tokens_out, clock, ctx)
    }

    /// Buy tokens and send to buyer
    #[allow(lint(self_transfer))]
    public fun buy_and_transfer<T>(
        pool: &mut BondingPool<T>,
        config: &LaunchpadConfig,
        payment: Coin<SUI>,
        min_tokens_out: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let tokens = buy(pool, config, payment, min_tokens_out, clock, ctx);
        transfer::public_transfer(tokens, ctx.sender());
    }

    /// Sell tokens to bonding curve
    public fun sell<T>(
        pool: &mut BondingPool<T>,
        config: &LaunchpadConfig,
        tokens: Coin<T>,
        min_sui_out: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        bonding_curve::sell(pool, config, tokens, min_sui_out, clock, ctx)
    }

    /// Sell tokens and send SUI to seller
    #[allow(lint(self_transfer))]
    public fun sell_and_transfer<T>(
        pool: &mut BondingPool<T>,
        config: &LaunchpadConfig,
        tokens: Coin<T>,
        min_sui_out: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let sui = sell(pool, config, tokens, min_sui_out, clock, ctx);
        transfer::public_transfer(sui, ctx.sender());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get current token price
    public fun get_price<T>(pool: &BondingPool<T>): u64 {
        bonding_curve::get_price(pool)
    }

    /// Get market cap
    public fun get_market_cap<T>(pool: &BondingPool<T>): u64 {
        bonding_curve::get_market_cap(pool)
    }

    /// Estimate tokens out for SUI input
    public fun estimate_buy<T>(
        pool: &BondingPool<T>,
        config: &LaunchpadConfig,
        sui_in: u64
    ): u64 {
        bonding_curve::estimate_buy(pool, config, sui_in)
    }

    /// Estimate SUI out for token input
    public fun estimate_sell<T>(
        pool: &BondingPool<T>,
        config: &LaunchpadConfig,
        tokens_in: u64
    ): u64 {
        bonding_curve::estimate_sell(pool, config, tokens_in)
    }

    /// Check if pool can graduate
    public fun can_graduate<T>(
        pool: &BondingPool<T>,
        config: &LaunchpadConfig
    ): bool {
        graduation::can_graduate(pool, config)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GRADUATION ENTRY POINTS - TWO PHASE PATTERN
    // ═══════════════════════════════════════════════════════════════════════
    //
    // Graduation follows a two-phase pattern for flexibility with different DEXes:
    //
    // Phase 1: Extract
    //   - Call `initiate_graduation_to_*()` to get PendingGraduation + coins
    //   - This locks the pool and extracts liquidity
    //
    // Phase 2: Complete (in a PTB with DEX calls)
    //   - Use the coins to create DEX pool (call DEX directly)
    //   - Call `complete_graduation_*()` with the pool ID
    //
    // Example PTB flow:
    //   1. launchpad::initiate_graduation_to_cetus() → (pending, sui, tokens)
    //   2. cetus::create_pool() → pool_id
    //   3. cetus::add_liquidity() → position
    //   4. launchpad::complete_graduation_cetus(pending, pool_id, ...)
    // ═══════════════════════════════════════════════════════════════════════

    use sui_launchpad::graduation::PendingGraduation;

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 1: INITIATE GRADUATION (Extract coins)
    // ═══════════════════════════════════════════════════════════════════════

    /// Initiate graduation to Cetus - Phase 1
    /// Returns PendingGraduation and extracted coins for DEX pool creation
    public fun initiate_graduation_to_cetus<T>(
        admin: &AdminCap,
        pool: &mut BondingPool<T>,
        config: &LaunchpadConfig,
        ctx: &mut TxContext,
    ): (PendingGraduation<T>, Coin<SUI>, Coin<T>) {
        use sui_launchpad::cetus_adapter;

        let pending = graduation::initiate_graduation(
            admin,
            pool,
            config,
            config::dex_cetus(),
            ctx,
        );

        cetus_adapter::graduate_to_cetus_extract(pending, config, ctx)
    }

    /// Initiate graduation to Turbos - Phase 1
    /// Returns PendingGraduation and extracted coins for DEX pool creation
    public fun initiate_graduation_to_turbos<T>(
        admin: &AdminCap,
        pool: &mut BondingPool<T>,
        config: &LaunchpadConfig,
        ctx: &mut TxContext,
    ): (PendingGraduation<T>, Coin<SUI>, Coin<T>) {
        use sui_launchpad::turbos_adapter;

        let pending = graduation::initiate_graduation(
            admin,
            pool,
            config,
            config::dex_turbos(),
            ctx,
        );

        turbos_adapter::graduate_to_turbos_extract(pending, config, ctx)
    }

    /// Initiate graduation to FlowX - Phase 1
    /// Returns PendingGraduation and extracted coins for DEX pool creation
    public fun initiate_graduation_to_flowx<T>(
        admin: &AdminCap,
        pool: &mut BondingPool<T>,
        config: &LaunchpadConfig,
        ctx: &mut TxContext,
    ): (PendingGraduation<T>, Coin<SUI>, Coin<T>) {
        use sui_launchpad::flowx_adapter;

        let pending = graduation::initiate_graduation(
            admin,
            pool,
            config,
            config::dex_flowx(),
            ctx,
        );

        flowx_adapter::graduate_to_flowx_extract(pending, config, ctx)
    }

    /// Initiate graduation to SuiDex - Phase 1
    /// Returns PendingGraduation and extracted coins for DEX pool creation
    public fun initiate_graduation_to_suidex<T>(
        admin: &AdminCap,
        pool: &mut BondingPool<T>,
        config: &LaunchpadConfig,
        ctx: &mut TxContext,
    ): (PendingGraduation<T>, Coin<SUI>, Coin<T>) {
        use sui_launchpad::suidex_adapter;

        let pending = graduation::initiate_graduation(
            admin,
            pool,
            config,
            config::dex_suidex(),
            ctx,
        );

        suidex_adapter::graduate_to_suidex_extract(pending, config, ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 2: COMPLETE GRADUATION (After DEX pool creation)
    // ═══════════════════════════════════════════════════════════════════════

    /// Complete graduation to Cetus - Phase 2
    /// Call after creating Cetus pool and adding liquidity
    public fun complete_graduation_cetus<T>(
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
        use sui_launchpad::cetus_adapter;

        cetus_adapter::complete_graduation_manual(
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

    /// Complete graduation to Turbos - Phase 2
    /// Call after creating Turbos pool and adding liquidity
    public fun complete_graduation_turbos<T>(
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
        use sui_launchpad::turbos_adapter;

        turbos_adapter::complete_graduation_manual(
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

    /// Complete graduation to FlowX - Phase 2
    /// Call after creating FlowX pool and adding liquidity
    public fun complete_graduation_flowx<T>(
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
        use sui_launchpad::flowx_adapter;

        flowx_adapter::complete_graduation_manual(
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

    /// Complete graduation to SuiDex - Phase 2
    /// Call after creating SuiDex pair and adding liquidity
    public fun complete_graduation_suidex<T>(
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
        use sui_launchpad::suidex_adapter;

        suidex_adapter::complete_graduation_manual(
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

    // ═══════════════════════════════════════════════════════════════════════
    // VESTING ENTRY POINTS - PLACEHOLDER
    // ═══════════════════════════════════════════════════════════════════════
    //
    // Vesting functionality will be provided by the standalone sui_vesting package.
    // See docs/VESTING.md for full specification and integration plan.
    //
    // FUTURE INTEGRATION:
    // When sui_vesting is deployed, add these entry points:
    //
    // ```
    // /// Create vesting schedule for LP tokens
    // public fun create_vesting<T>(
    //     pool_id: ID,
    //     beneficiary: address,
    //     tokens: Coin<T>,
    //     cliff_duration: u64,
    //     vesting_duration: u64,
    //     revocable: bool,
    //     clock: &Clock,
    //     ctx: &mut TxContext,
    // ) {
    //     let schedule = sui_vesting::vesting::create_vesting_now(
    //         pool_id,
    //         beneficiary,
    //         tokens,
    //         cliff_duration,
    //         vesting_duration,
    //         revocable,
    //         clock,
    //         ctx,
    //     );
    //     transfer::public_transfer(schedule, beneficiary);
    // }
    //
    // /// Claim vested tokens
    // public fun claim_vested<T>(
    //     schedule: &mut VestingSchedule<T>,
    //     clock: &Clock,
    //     ctx: &mut TxContext,
    // ): Coin<T> {
    //     sui_vesting::vesting::claim(schedule, clock, ctx)
    // }
    // ```
    //
    // ═══════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Pause a pool
    public fun pause_pool<T>(
        admin: &AdminCap,
        pool: &mut BondingPool<T>,
        clock: &Clock,
    ) {
        bonding_curve::set_paused(admin, pool, true, clock);
    }

    /// Unpause a pool
    public fun unpause_pool<T>(
        admin: &AdminCap,
        pool: &mut BondingPool<T>,
        clock: &Clock,
    ) {
        bonding_curve::set_paused(admin, pool, false, clock);
    }

    /// Pause the entire platform
    public fun pause_platform(
        admin: &AdminCap,
        config: &mut LaunchpadConfig,
    ) {
        config::set_paused(admin, config, true);
    }

    /// Unpause the platform
    public fun unpause_platform(
        admin: &AdminCap,
        config: &mut LaunchpadConfig,
    ) {
        config::set_paused(admin, config, false);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REGISTRY VIEWS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get total tokens launched
    public fun total_tokens(registry: &Registry): u64 {
        registry::total_tokens(registry)
    }

    /// Get total graduated tokens
    public fun total_graduated(registry: &Registry): u64 {
        registry::total_graduated(registry)
    }

    /// Check if token is registered
    public fun is_registered<T>(registry: &Registry): bool {
        registry::is_registered<T>(registry)
    }
}
