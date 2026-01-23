/// Staking Integration Module
/// Provides helper functions for PTB-based staking pool creation at graduation
///
/// This module facilitates the integration between sui_launchpad and sui_staking
/// without creating a compile-time dependency. The actual staking pool creation
/// is done via PTB (Programmable Transaction Block) calling sui_staking directly.
///
/// PTB Flow for Graduation with Staking:
/// ─────────────────────────────────────
/// 1. initiate_graduation<T>() → PendingGraduation<T> (includes staking reserve)
/// 2. extract_staking_tokens<T>(&mut pending) → Coin<T> (reward tokens)
/// 3. Create DEX pool (Cetus/SuiDex/etc) → LP tokens
/// 4. sui_staking::factory::create_pool_free<T, T>() → PoolAdminCap
/// 5. Transfer PoolAdminCap to destination (creator/dao/platform)
/// 6. split_lp_tokens() → (creator_lp, protocol_lp, dao_lp)
/// 7. Vest creator LP (sui_vesting)
/// 8. complete_graduation()
module sui_launchpad::staking_integration {

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::graduation::{Self, PendingGraduation, StakingConfig};

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
}
