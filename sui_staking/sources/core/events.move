/// Events emitted by the staking module
module sui_staking::events {
    use sui::event;

    // ═══════════════════════════════════════════════════════════════════════
    // ORIGIN CONSTANTS - Track how pool was created
    // ═══════════════════════════════════════════════════════════════════════

    /// Pool created directly by user (independent)
    const ORIGIN_INDEPENDENT: u8 = 0;
    /// Pool created via launchpad graduation
    const ORIGIN_LAUNCHPAD: u8 = 1;
    /// Pool created via partner platform
    const ORIGIN_PARTNER: u8 = 2;

    /// Get origin constant for independent creation
    public fun origin_independent(): u8 { ORIGIN_INDEPENDENT }
    /// Get origin constant for launchpad creation
    public fun origin_launchpad(): u8 { ORIGIN_LAUNCHPAD }
    /// Get origin constant for partner creation
    public fun origin_partner(): u8 { ORIGIN_PARTNER }

    // ═══════════════════════════════════════════════════════════════════════
    // POOL EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emitted when a new staking pool is created
    public struct PoolCreated has copy, drop {
        pool_id: ID,
        creator: address,
        stake_token_type: std::ascii::String,
        reward_token_type: std::ascii::String,
        total_rewards: u64,
        start_time_ms: u64,
        end_time_ms: u64,
        min_stake_duration_ms: u64,
        early_unstake_fee_bps: u64,
        stake_fee_bps: u64,
        unstake_fee_bps: u64,
        // Origin tracking
        origin: u8,              // 0=independent, 1=launchpad, 2=partner
        origin_id: Option<ID>,   // Optional: launchpad pool ID or partner ID
        created_at: u64,         // Timestamp of creation
    }

    /// Emitted when a governance-only pool is created (no rewards, just voting power)
    public struct GovernancePoolCreated has copy, drop {
        pool_id: ID,
        creator: address,
        stake_token_type: std::ascii::String,
        min_stake_duration_ms: u64,
        early_unstake_fee_bps: u64,
        stake_fee_bps: u64,
        unstake_fee_bps: u64,
        // Origin tracking
        origin: u8,              // 0=independent, 1=launchpad, 2=partner
        origin_id: Option<ID>,   // Optional: launchpad pool ID or partner ID
        created_at: u64,         // Timestamp of creation
    }

    /// Emitted when rewards are added to a pool
    public struct RewardsAdded has copy, drop {
        pool_id: ID,
        amount: u64,
        new_total_rewards: u64,
        added_by: address,
    }

    /// Emitted when pool configuration is updated
    public struct PoolConfigUpdated has copy, drop {
        pool_id: ID,
        min_stake_duration_ms: u64,
        early_unstake_fee_bps: u64,
        stake_fee_bps: u64,
        unstake_fee_bps: u64,
        updated_by: address,
    }

    /// Emitted when a pool is paused or unpaused
    public struct PoolPauseToggled has copy, drop {
        pool_id: ID,
        paused: bool,
        toggled_by: address,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emitted when tokens are staked
    public struct Staked has copy, drop {
        pool_id: ID,
        position_id: ID,
        staker: address,
        amount: u64,
        total_staked_in_pool: u64,
    }

    /// Emitted when tokens are unstaked
    public struct Unstaked has copy, drop {
        pool_id: ID,
        position_id: ID,
        staker: address,
        amount: u64,
        fee_amount: u64,
        total_staked_in_pool: u64,
    }

    /// Emitted when rewards are claimed
    public struct RewardsClaimed has copy, drop {
        pool_id: ID,
        position_id: ID,
        claimer: address,
        reward_amount: u64,
    }

    /// Emitted when more tokens are staked to existing position
    public struct StakeAdded has copy, drop {
        pool_id: ID,
        position_id: ID,
        staker: address,
        added_amount: u64,
        new_total_staked: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PLATFORM EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emitted when platform fee is collected
    public struct PlatformFeeCollected has copy, drop {
        pool_id: ID,
        fee_amount: u64,
        fee_recipient: address,
    }

    /// Emitted when platform configuration is updated
    public struct PlatformConfigUpdated has copy, drop {
        setup_fee: u64,
        platform_fee_bps: u64,
        updated_by: address,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMIT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    public fun emit_pool_created(
        pool_id: ID,
        creator: address,
        stake_token_type: std::ascii::String,
        reward_token_type: std::ascii::String,
        total_rewards: u64,
        start_time_ms: u64,
        end_time_ms: u64,
        min_stake_duration_ms: u64,
        early_unstake_fee_bps: u64,
        stake_fee_bps: u64,
        unstake_fee_bps: u64,
        origin: u8,
        origin_id: Option<ID>,
        created_at: u64,
    ) {
        event::emit(PoolCreated {
            pool_id,
            creator,
            stake_token_type,
            reward_token_type,
            total_rewards,
            start_time_ms,
            end_time_ms,
            min_stake_duration_ms,
            early_unstake_fee_bps,
            stake_fee_bps,
            unstake_fee_bps,
            origin,
            origin_id,
            created_at,
        });
    }

    public fun emit_rewards_added(
        pool_id: ID,
        amount: u64,
        new_total_rewards: u64,
        added_by: address,
    ) {
        event::emit(RewardsAdded {
            pool_id,
            amount,
            new_total_rewards,
            added_by,
        });
    }

    public fun emit_pool_config_updated(
        pool_id: ID,
        min_stake_duration_ms: u64,
        early_unstake_fee_bps: u64,
        stake_fee_bps: u64,
        unstake_fee_bps: u64,
        updated_by: address,
    ) {
        event::emit(PoolConfigUpdated {
            pool_id,
            min_stake_duration_ms,
            early_unstake_fee_bps,
            stake_fee_bps,
            unstake_fee_bps,
            updated_by,
        });
    }

    public fun emit_pool_pause_toggled(
        pool_id: ID,
        paused: bool,
        toggled_by: address,
    ) {
        event::emit(PoolPauseToggled {
            pool_id,
            paused,
            toggled_by,
        });
    }

    public fun emit_staked(
        pool_id: ID,
        position_id: ID,
        staker: address,
        amount: u64,
        total_staked_in_pool: u64,
    ) {
        event::emit(Staked {
            pool_id,
            position_id,
            staker,
            amount,
            total_staked_in_pool,
        });
    }

    public fun emit_unstaked(
        pool_id: ID,
        position_id: ID,
        staker: address,
        amount: u64,
        fee_amount: u64,
        total_staked_in_pool: u64,
    ) {
        event::emit(Unstaked {
            pool_id,
            position_id,
            staker,
            amount,
            fee_amount,
            total_staked_in_pool,
        });
    }

    public fun emit_rewards_claimed(
        pool_id: ID,
        position_id: ID,
        claimer: address,
        reward_amount: u64,
    ) {
        event::emit(RewardsClaimed {
            pool_id,
            position_id,
            claimer,
            reward_amount,
        });
    }

    public fun emit_stake_added(
        pool_id: ID,
        position_id: ID,
        staker: address,
        added_amount: u64,
        new_total_staked: u64,
    ) {
        event::emit(StakeAdded {
            pool_id,
            position_id,
            staker,
            added_amount,
            new_total_staked,
        });
    }

    public fun emit_platform_fee_collected(
        pool_id: ID,
        fee_amount: u64,
        fee_recipient: address,
    ) {
        event::emit(PlatformFeeCollected {
            pool_id,
            fee_amount,
            fee_recipient,
        });
    }

    public fun emit_platform_config_updated(
        setup_fee: u64,
        platform_fee_bps: u64,
        updated_by: address,
    ) {
        event::emit(PlatformConfigUpdated {
            setup_fee,
            platform_fee_bps,
            updated_by,
        });
    }

    public fun emit_governance_pool_created(
        pool_id: ID,
        creator: address,
        stake_token_type: std::ascii::String,
        min_stake_duration_ms: u64,
        early_unstake_fee_bps: u64,
        stake_fee_bps: u64,
        unstake_fee_bps: u64,
        origin: u8,
        origin_id: Option<ID>,
        created_at: u64,
    ) {
        event::emit(GovernancePoolCreated {
            pool_id,
            creator,
            stake_token_type,
            min_stake_duration_ms,
            early_unstake_fee_bps,
            stake_fee_bps,
            unstake_fee_bps,
            origin,
            origin_id,
            created_at,
        });
    }
}
