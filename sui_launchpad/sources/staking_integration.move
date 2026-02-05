/// Staking Integration Module
/// Provides helper functions for PTB-based staking pool creation at graduation
///
/// This module facilitates the integration between sui_launchpad and sui_staking.
/// At graduation, tokens reserved for staking rewards are used to create a staking pool
/// where token holders can stake their tokens and earn rewards.
///
/// ═══════════════════════════════════════════════════════════════════════════════
/// COMPLETE PTB FLOW FOR GRADUATION + STAKING
/// ═══════════════════════════════════════════════════════════════════════════════
///
/// Required Capabilities:
/// - Launchpad AdminCap (for graduation)
/// - Staking AdminCap (for create_pool_free - no setup fee)
///
/// ```
/// // STEP 1: Initiate graduation
/// let mut pending = graduation::initiate_graduation<T>(...);
///
/// // STEP 2: Extract all balances
/// let sui_coin = graduation::extract_all_sui(&mut pending, ctx);
/// let token_coin = graduation::extract_all_tokens(&mut pending, ctx);
/// let staking_coin = graduation::extract_staking_tokens(&mut pending, ctx);
///
/// // STEP 3: Get staking parameters
/// let (start_time, duration, min_stake, early_fee, stake_fee, unstake_fee) =
///     staking_integration::get_staking_pool_params(&pending, clock.timestamp_ms());
///
/// // STEP 4: Create DEX liquidity pool
/// let lp_coin = dex::add_liquidity(token_coin, sui_coin, ...);
///
/// // STEP 5: Create staking pool with extracted tokens
/// let pool_admin_cap = sui_staking::factory::create_pool_free<T, T>(
///     staking_registry,
///     staking_admin_cap,
///     staking_coin,
///     start_time,
///     duration,
///     min_stake,
///     early_fee,
///     stake_fee,
///     unstake_fee,
///     clock,
///     ctx
/// );
///
/// // STEP 6: Transfer PoolAdminCap to appropriate destination
/// let admin_dest = staking_integration::get_admin_destination(&pending, &config);
/// transfer::public_transfer(pool_admin_cap, admin_dest);
///
/// // STEP 7: Split and distribute LP tokens
/// let (creator_lp, protocol_lp, dao_lp) = graduation::split_lp_tokens(&pending, lp_coin, ctx);
/// // ... vest creator_lp, transfer protocol_lp, handle dao_lp
///
/// // STEP 8: Complete graduation (validates all balances are zero)
/// let receipt = graduation::complete_graduation(pending, registry, ...);
/// ```
///
/// ═══════════════════════════════════════════════════════════════════════════════
module sui_launchpad::staking_integration {

    use sui::clock::Clock;
    use sui::coin::Coin;

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::graduation::{Self, PendingGraduation};

    // Re-export sui_staking types for convenience
    use sui_staking::factory::{Self, StakingRegistry};
    use sui_staking::access::{AdminCap as StakingAdminCap, PoolAdminCap};

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS - Admin Destinations
    // ═══════════════════════════════════════════════════════════════════════

    /// Creator receives PoolAdminCap - manages their own staking pool
    const ADMIN_DEST_CREATOR: u8 = 0;

    /// DAO treasury receives PoolAdminCap - community-controlled
    const ADMIN_DEST_DAO: u8 = 1;

    /// Platform receives PoolAdminCap - platform operates for creator
    const ADMIN_DEST_PLATFORM: u8 = 2;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS - Reward Token Types
    // ═══════════════════════════════════════════════════════════════════════

    /// Reward with the same graduated token (most common)
    const REWARD_SAME_TOKEN: u8 = 0;

    /// Reward with SUI
    const REWARD_SUI: u8 = 1;

    /// Custom reward token (requires separate configuration)
    const REWARD_CUSTOM: u8 = 2;

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING POOL CREATION (for PTB)
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a staking pool for the graduated token using extracted staking tokens
    /// This is the main integration function called during graduation PTB
    ///
    /// T = The graduated token type (both stake and reward token for same-token rewards)
    /// Origin is set to LAUNCHPAD with the pool_id for tracking
    public fun create_staking_pool<T>(
        staking_registry: &mut StakingRegistry,
        staking_admin_cap: &StakingAdminCap,
        pending: &PendingGraduation<T>,
        reward_coins: Coin<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): PoolAdminCap {
        let staking_config = graduation::pending_staking_config(pending);
        let launchpad_pool_id = graduation::pending_pool_id(pending);

        // Use create_pool_admin with ORIGIN_LAUNCHPAD for tracking
        factory::create_pool_admin<T, T>(
            staking_registry,
            staking_admin_cap,
            reward_coins,
            clock.timestamp_ms(), // start immediately
            graduation::staking_config_duration_ms(staking_config),
            graduation::staking_config_min_stake_duration_ms(staking_config),
            graduation::staking_config_early_unstake_fee_bps(staking_config),
            graduation::staking_config_stake_fee_bps(staking_config),
            graduation::staking_config_unstake_fee_bps(staking_config),
            sui_staking::events::origin_launchpad(),  // Origin: launchpad
            option::some(launchpad_pool_id),          // Link to launchpad pool
            clock,
            ctx,
        )
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS FOR PTB
    // ═══════════════════════════════════════════════════════════════════════

    /// Get all staking parameters needed for pool creation
    /// Returns: (start_time_ms, duration_ms, min_stake_duration_ms,
    ///           early_unstake_fee_bps, stake_fee_bps, unstake_fee_bps)
    public fun get_staking_pool_params<T>(
        pending: &PendingGraduation<T>,
        current_time_ms: u64,
    ): (u64, u64, u64, u64, u64, u64) {
        let config = graduation::pending_staking_config(pending);

        (
            current_time_ms,  // start_time_ms - start immediately
            graduation::staking_config_duration_ms(config),
            graduation::staking_config_min_stake_duration_ms(config),
            graduation::staking_config_early_unstake_fee_bps(config),
            graduation::staking_config_stake_fee_bps(config),
            graduation::staking_config_unstake_fee_bps(config),
        )
    }

    /// Determine the destination address for the PoolAdminCap
    /// Uses the staking_admin_destination config to decide who receives control
    public fun get_admin_destination<T>(
        pending: &PendingGraduation<T>,
        config: &LaunchpadConfig,
    ): address {
        let staking_config = graduation::pending_staking_config(pending);
        let destination = graduation::staking_config_admin_destination(staking_config);

        if (destination == ADMIN_DEST_CREATOR) {
            graduation::pending_creator(pending)
        } else if (destination == ADMIN_DEST_DAO) {
            config::dao_treasury(config)
        } else {
            // ADMIN_DEST_PLATFORM
            config::treasury(config)
        }
    }

    /// Check if staking should be created for this graduation
    public fun should_create_staking_pool<T>(pending: &PendingGraduation<T>): bool {
        graduation::pending_staking_enabled(pending) &&
        graduation::pending_staking_amount(pending) > 0
    }

    /// Get the reward type for this graduation's staking pool
    public fun get_reward_type<T>(pending: &PendingGraduation<T>): u8 {
        let config = graduation::pending_staking_config(pending);
        graduation::staking_config_reward_type(config)
    }

    /// Check if rewards are in the same token as the graduated token
    public fun is_same_token_reward<T>(pending: &PendingGraduation<T>): bool {
        get_reward_type(pending) == REWARD_SAME_TOKEN
    }

    /// Check if rewards are in SUI
    public fun is_sui_reward<T>(pending: &PendingGraduation<T>): bool {
        get_reward_type(pending) == REWARD_SUI
    }

    /// Check if rewards are in a custom token
    public fun is_custom_reward<T>(pending: &PendingGraduation<T>): bool {
        get_reward_type(pending) == REWARD_CUSTOM
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANT GETTERS (for external use)
    // ═══════════════════════════════════════════════════════════════════════

    // Admin destination constants
    public fun admin_dest_creator(): u8 { ADMIN_DEST_CREATOR }
    public fun admin_dest_dao(): u8 { ADMIN_DEST_DAO }
    public fun admin_dest_platform(): u8 { ADMIN_DEST_PLATFORM }

    // Reward type constants
    public fun reward_same_token(): u8 { REWARD_SAME_TOKEN }
    public fun reward_sui(): u8 { REWARD_SUI }
    public fun reward_custom(): u8 { REWARD_CUSTOM }

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Validate admin destination value
    public fun is_valid_admin_destination(dest: u8): bool {
        dest <= ADMIN_DEST_PLATFORM
    }

    /// Validate reward type value
    public fun is_valid_reward_type(reward_type: u8): bool {
        reward_type <= REWARD_CUSTOM
    }

    /// Validate that staking can be created for this graduation
    /// Checks: staking enabled, same-token rewards, sufficient balance
    public fun validate_staking_setup<T>(pending: &PendingGraduation<T>): bool {
        if (!graduation::pending_staking_enabled(pending)) {
            return false
        };

        // For now, only same-token rewards are supported in automatic graduation
        if (!is_same_token_reward(pending)) {
            return false
        };

        // Must have tokens to stake
        graduation::pending_staking_amount(pending) > 0
    }
}
