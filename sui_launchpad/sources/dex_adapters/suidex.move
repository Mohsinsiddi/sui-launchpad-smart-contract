/// SuiDex Adapter
/// Handles liquidity pool creation on SuiDex
module sui_launchpad::suidex_adapter {

    use sui::coin::Coin;
    use sui::sui::SUI;
    use sui::clock::Clock;

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::graduation::{Self, PendingGraduation, GraduationReceipt};
    use sui_launchpad::registry::Registry;

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    const EWrongDexType: u64 = 630;
    const ESuiDexNotConfigured: u64 = 631;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Default swap fee for SuiDex (0.25%)
    const DEFAULT_SWAP_FEE_BPS: u64 = 25;

    // ═══════════════════════════════════════════════════════════════════════
    // GRADUATION TO SUIDEX
    // ═══════════════════════════════════════════════════════════════════════

    /// Graduate token to SuiDex
    /// This is a placeholder - actual implementation requires SuiDex SDK calls
    ///
    /// In production, this would:
    /// 1. Extract SUI and tokens from PendingGraduation
    /// 2. Call SuiDex to create a new pool
    /// 3. Add initial liquidity
    /// 4. Distribute LP tokens (creator vested, community burned)
    /// 5. Complete graduation with the new pool ID
    public fun graduate_to_suidex<T>(
        mut pending: PendingGraduation<T>,
        config: &LaunchpadConfig,
        registry: &mut Registry,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (GraduationReceipt, Coin<SUI>, Coin<T>) {
        // Validate this is meant for SuiDex
        assert!(graduation::pending_dex_type(&pending) == config::dex_suidex(), EWrongDexType);

        // Validate SuiDex is configured
        assert!(config::suidex_package(config) != @0x0, ESuiDexNotConfigured);

        // Extract liquidity
        let sui_coin = graduation::extract_all_sui(&mut pending, ctx);
        let token_coin = graduation::extract_all_tokens(&mut pending, ctx);

        // In production: Call SuiDex here to create pool
        // let suidex_pool_id = suidex::create_pool<T, SUI>(...);
        // let lp_tokens = suidex::add_liquidity(...);
        //
        // Then distribute LP tokens:
        // let (creator_lp, community_lp) = graduation::distribute_lp_tokens(
        //     &pending,
        //     lp_tokens,
        //     suidex_pool_id,
        //     clock,
        //     ctx,
        // );

        // Placeholder pool ID
        let placeholder_pool_id = object::id_from_address(@0x4);

        // Placeholder LP amounts (in production, these come from distribute_lp_tokens)
        let total_lp_tokens = 0;
        let creator_lp_tokens = 0;
        let community_lp_tokens = 0;

        // Complete graduation
        let receipt = graduation::complete_graduation(
            pending,
            registry,
            placeholder_pool_id,
            total_lp_tokens,
            creator_lp_tokens,
            community_lp_tokens,
            clock,
            ctx,
        );

        // Return receipt and remaining coins
        (receipt, sui_coin, token_coin)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get default swap fee in basis points
    public fun default_swap_fee_bps(): u64 {
        DEFAULT_SWAP_FEE_BPS
    }
}
