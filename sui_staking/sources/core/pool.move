/// Staking Pool - core staking logic with MasterChef-style rewards
/// Supports any StakeToken/RewardToken pair
module sui_staking::pool {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;

    use sui_staking::math;
    use sui_staking::errors;
    use sui_staking::events;
    use sui_staking::access::{Self, PoolAdminCap};
    use sui_staking::position::{Self, StakingPosition};

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Minimum stake amount (dust protection)
    const MIN_STAKE_AMOUNT: u64 = 1000;

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING POOL
    // ═══════════════════════════════════════════════════════════════════════

    /// Staking pool with dual token support
    public struct StakingPool<phantom StakeToken, phantom RewardToken> has key, store {
        id: UID,
        /// Pool configuration
        config: PoolConfig,
        /// Total tokens staked in the pool
        total_staked: u64,
        /// Balance of staked tokens
        stake_balance: Balance<StakeToken>,
        /// Balance of reward tokens
        reward_balance: Balance<RewardToken>,
        /// Accumulated reward per share (scaled by PRECISION)
        acc_reward_per_share: u128,
        /// Last time rewards were calculated
        last_reward_time_ms: u64,
        /// Reward rate (tokens per millisecond)
        reward_rate: u64,
        /// Total rewards distributed so far
        total_rewards_distributed: u64,
        /// Collected early unstake fees
        collected_fees: Balance<StakeToken>,
    }

    /// Pool configuration
    public struct PoolConfig has store, copy, drop {
        /// Pool creator
        creator: address,
        /// Start time of reward distribution
        start_time_ms: u64,
        /// End time of reward distribution
        end_time_ms: u64,
        /// Total reward tokens for distribution
        total_rewards: u64,
        /// Minimum stake duration before free unstake (ms)
        min_stake_duration_ms: u64,
        /// Early unstake fee in basis points (max 10%)
        early_unstake_fee_bps: u64,
        /// Stake fee in basis points (max 5%) - fee on deposit
        stake_fee_bps: u64,
        /// Unstake fee in basis points (max 5%) - fee on withdrawal
        unstake_fee_bps: u64,
        /// Whether pool is paused
        paused: bool,
        /// Whether this is a governance-only pool (no rewards, just voting power)
        governance_only: bool,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new staking pool
    public fun create<StakeToken, RewardToken>(
        reward_coins: Coin<RewardToken>,
        start_time_ms: u64,
        duration_ms: u64,
        min_stake_duration_ms: u64,
        early_unstake_fee_bps: u64,
        stake_fee_bps: u64,
        unstake_fee_bps: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (StakingPool<StakeToken, RewardToken>, PoolAdminCap) {
        let total_rewards = coin::value(&reward_coins);

        // Validations
        assert!(total_rewards > 0, errors::zero_rewards());
        assert!(math::is_valid_duration(duration_ms), errors::invalid_duration());
        assert!(math::is_valid_early_fee(early_unstake_fee_bps), errors::fee_too_high());
        assert!(math::is_valid_stake_fee(stake_fee_bps), errors::fee_too_high());
        assert!(math::is_valid_unstake_fee(unstake_fee_bps), errors::fee_too_high());

        let current_time = sui::clock::timestamp_ms(clock);
        assert!(start_time_ms >= current_time, errors::pool_not_started());

        let end_time_ms = start_time_ms + duration_ms;
        let reward_rate = math::calculate_reward_rate(total_rewards, duration_ms);

        let config = PoolConfig {
            creator: tx_context::sender(ctx),
            start_time_ms,
            end_time_ms,
            total_rewards,
            min_stake_duration_ms,
            early_unstake_fee_bps,
            stake_fee_bps,
            unstake_fee_bps,
            paused: false,
            governance_only: false,
        };

        let pool = StakingPool {
            id: object::new(ctx),
            config,
            total_staked: 0,
            stake_balance: balance::zero(),
            reward_balance: coin::into_balance(reward_coins),
            acc_reward_per_share: 0,
            last_reward_time_ms: start_time_ms,
            reward_rate,
            total_rewards_distributed: 0,
            collected_fees: balance::zero(),
        };

        let pool_id = object::uid_to_inner(&pool.id);
        let admin_cap = access::create_pool_admin_cap(pool_id, ctx);

        pool_emit_created(&pool, ctx);

        (pool, admin_cap)
    }

    /// Create a governance-only staking pool (no rewards, just voting power)
    /// Users stake tokens to gain voting power in DAO governance
    /// No reward token required - staking is purely for governance participation
    public fun create_governance_pool<StakeToken>(
        min_stake_duration_ms: u64,
        early_unstake_fee_bps: u64,
        stake_fee_bps: u64,
        unstake_fee_bps: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (StakingPool<StakeToken, StakeToken>, PoolAdminCap) {
        // Validations
        assert!(math::is_valid_early_fee(early_unstake_fee_bps), errors::fee_too_high());
        assert!(math::is_valid_stake_fee(stake_fee_bps), errors::fee_too_high());
        assert!(math::is_valid_unstake_fee(unstake_fee_bps), errors::fee_too_high());

        let current_time = sui::clock::timestamp_ms(clock);

        // Governance pools have no end time (run indefinitely)
        // Use max u64 as end time
        let start_time_ms = current_time;
        let end_time_ms = 18446744073709551615u64; // u64::MAX

        let config = PoolConfig {
            creator: tx_context::sender(ctx),
            start_time_ms,
            end_time_ms,
            total_rewards: 0,
            min_stake_duration_ms,
            early_unstake_fee_bps,
            stake_fee_bps,
            unstake_fee_bps,
            paused: false,
            governance_only: true,
        };

        let pool = StakingPool {
            id: object::new(ctx),
            config,
            total_staked: 0,
            stake_balance: balance::zero(),
            reward_balance: balance::zero(), // No rewards for governance pools
            acc_reward_per_share: 0,
            last_reward_time_ms: start_time_ms,
            reward_rate: 0, // No rewards
            total_rewards_distributed: 0,
            collected_fees: balance::zero(),
        };

        let pool_id = object::uid_to_inner(&pool.id);
        let admin_cap = access::create_pool_admin_cap(pool_id, ctx);

        pool_emit_governance_created(&pool, ctx);

        (pool, admin_cap)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Stake tokens and receive a position NFT
    public fun stake<StakeToken, RewardToken>(
        pool: &mut StakingPool<StakeToken, RewardToken>,
        stake_coins: Coin<StakeToken>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): StakingPosition<StakeToken> {
        let amount = coin::value(&stake_coins);
        let current_time = sui::clock::timestamp_ms(clock);

        // Validations
        assert!(!pool.config.paused, errors::pool_paused());
        assert!(current_time >= pool.config.start_time_ms, errors::pool_not_started());
        // Governance-only pools have no end time (they run indefinitely)
        if (!pool.config.governance_only) {
            assert!(current_time < pool.config.end_time_ms, errors::pool_ended());
        };
        assert!(amount >= MIN_STAKE_AMOUNT, errors::amount_too_small());

        // Update pool rewards before any state changes
        update_pool_rewards(pool, current_time);

        // Calculate and collect stake fee
        let stake_fee = math::calculate_fee_bps(amount, pool.config.stake_fee_bps);
        let net_stake_amount = amount - stake_fee;

        // Validate net amount after fee
        assert!(net_stake_amount >= MIN_STAKE_AMOUNT, errors::amount_too_small());

        // Split stake into fee and net amount
        let mut stake_balance = coin::into_balance(stake_coins);
        if (stake_fee > 0) {
            let fee_balance = balance::split(&mut stake_balance, stake_fee);
            balance::join(&mut pool.collected_fees, fee_balance);
        };

        // Add net stake to pool
        balance::join(&mut pool.stake_balance, stake_balance);
        pool.total_staked = pool.total_staked + net_stake_amount;

        // Create position NFT with net staked amount
        let pool_id = object::uid_to_inner(&pool.id);
        let position = position::create<StakeToken>(
            pool_id,
            net_stake_amount,
            pool.acc_reward_per_share,
            current_time,
            ctx,
        );

        events::emit_staked(
            pool_id,
            position::id(&position),
            tx_context::sender(ctx),
            net_stake_amount,
            pool.total_staked,
        );

        position
    }

    /// Add more stake to an existing position
    public fun add_stake<StakeToken, RewardToken>(
        pool: &mut StakingPool<StakeToken, RewardToken>,
        position: &mut StakingPosition<StakeToken>,
        stake_coins: Coin<StakeToken>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<RewardToken> {
        let amount = coin::value(&stake_coins);
        let current_time = sui::clock::timestamp_ms(clock);
        let pool_id = object::uid_to_inner(&pool.id);

        // Validations
        assert!(!pool.config.paused, errors::pool_paused());
        position::assert_pool_match(position, pool_id);
        assert!(amount >= MIN_STAKE_AMOUNT, errors::amount_too_small());

        // Update pool rewards
        update_pool_rewards(pool, current_time);

        // Claim pending rewards first (only if pool has sufficient balance)
        let pending = position::calculate_pending_rewards(position, pool.acc_reward_per_share);
        let available_rewards = balance::value(&pool.reward_balance);
        let reward_coin = if (pending > 0 && available_rewards >= pending) {
            let reward_balance = balance::split(&mut pool.reward_balance, pending);
            pool.total_rewards_distributed = pool.total_rewards_distributed + pending;
            coin::from_balance(reward_balance, ctx)
        } else {
            // If insufficient rewards, still allow staking but return zero rewards
            coin::zero(ctx)
        };

        // Calculate and collect stake fee
        let stake_fee = math::calculate_fee_bps(amount, pool.config.stake_fee_bps);
        let net_stake_amount = amount - stake_fee;

        // Validate net amount after fee
        assert!(net_stake_amount >= MIN_STAKE_AMOUNT, errors::amount_too_small());

        // Split stake into fee and net amount
        let mut stake_balance = coin::into_balance(stake_coins);
        if (stake_fee > 0) {
            let fee_balance = balance::split(&mut stake_balance, stake_fee);
            balance::join(&mut pool.collected_fees, fee_balance);
        };

        // Add net stake to pool
        balance::join(&mut pool.stake_balance, stake_balance);
        pool.total_staked = pool.total_staked + net_stake_amount;
        position::add_stake(position, net_stake_amount, pool.acc_reward_per_share);

        events::emit_stake_added(
            pool_id,
            position::id(position),
            tx_context::sender(ctx),
            net_stake_amount,
            position::staked_amount(position),
        );

        reward_coin
    }

    /// Unstake tokens from a position (full unstake)
    public fun unstake<StakeToken, RewardToken>(
        pool: &mut StakingPool<StakeToken, RewardToken>,
        position: StakingPosition<StakeToken>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Coin<StakeToken>, Coin<RewardToken>) {
        let current_time = sui::clock::timestamp_ms(clock);
        let pool_id = object::uid_to_inner(&pool.id);

        // Validations
        position::assert_pool_match(&position, pool_id);

        // Update pool rewards
        update_pool_rewards(pool, current_time);

        let staked_amount = position::staked_amount(&position);

        // Calculate and claim pending rewards
        let pending = position::calculate_pending_rewards(&position, pool.acc_reward_per_share);
        let reward_coin = if (pending > 0 && balance::value(&pool.reward_balance) >= pending) {
            let reward_balance = balance::split(&mut pool.reward_balance, pending);
            pool.total_rewards_distributed = pool.total_rewards_distributed + pending;

            events::emit_rewards_claimed(
                pool_id,
                position::id(&position),
                tx_context::sender(ctx),
                pending,
            );

            coin::from_balance(reward_balance, ctx)
        } else {
            coin::zero(ctx)
        };

        // Calculate early unstake fee (only if before min duration)
        let early_fee = position::calculate_early_fee(
            &position,
            staked_amount,
            current_time,
            pool.config.min_stake_duration_ms,
            pool.config.early_unstake_fee_bps,
        );

        // Calculate standard unstake fee (always applied)
        let unstake_fee = math::calculate_fee_bps(staked_amount, pool.config.unstake_fee_bps);

        // Total fee = early_fee + unstake_fee
        let total_fee = early_fee + unstake_fee;

        // Remove stake from pool
        pool.total_staked = pool.total_staked - staked_amount;
        let mut stake_balance = balance::split(&mut pool.stake_balance, staked_amount);

        // Collect total fee if applicable
        if (total_fee > 0) {
            let fee_balance = balance::split(&mut stake_balance, total_fee);
            balance::join(&mut pool.collected_fees, fee_balance);
        };

        let stake_coin = coin::from_balance(stake_balance, ctx);

        events::emit_unstaked(
            pool_id,
            position::id(&position),
            tx_context::sender(ctx),
            staked_amount,
            total_fee,
            pool.total_staked,
        );

        // Destroy position
        position::destroy_empty_force(position);

        (stake_coin, reward_coin)
    }

    /// Partial unstake from a position
    public fun unstake_partial<StakeToken, RewardToken>(
        pool: &mut StakingPool<StakeToken, RewardToken>,
        position: &mut StakingPosition<StakeToken>,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Coin<StakeToken>, Coin<RewardToken>) {
        let current_time = sui::clock::timestamp_ms(clock);
        let pool_id = object::uid_to_inner(&pool.id);

        // Validations
        position::assert_pool_match(position, pool_id);
        assert!(amount > 0, errors::zero_amount());
        assert!(amount <= position::staked_amount(position), errors::zero_amount());

        // Update pool rewards
        update_pool_rewards(pool, current_time);

        // Calculate and claim pending rewards first
        let pending = position::calculate_pending_rewards(position, pool.acc_reward_per_share);
        let reward_coin = if (pending > 0 && balance::value(&pool.reward_balance) >= pending) {
            let reward_balance = balance::split(&mut pool.reward_balance, pending);
            pool.total_rewards_distributed = pool.total_rewards_distributed + pending;

            events::emit_rewards_claimed(
                pool_id,
                position::id(position),
                tx_context::sender(ctx),
                pending,
            );

            coin::from_balance(reward_balance, ctx)
        } else {
            coin::zero(ctx)
        };

        // Calculate early unstake fee (only if before min duration)
        let early_fee = position::calculate_early_fee(
            position,
            amount,
            current_time,
            pool.config.min_stake_duration_ms,
            pool.config.early_unstake_fee_bps,
        );

        // Calculate standard unstake fee (always applied)
        let unstake_fee = math::calculate_fee_bps(amount, pool.config.unstake_fee_bps);

        // Total fee = early_fee + unstake_fee
        let total_fee = early_fee + unstake_fee;

        // Remove stake from pool
        pool.total_staked = pool.total_staked - amount;
        let mut stake_balance = balance::split(&mut pool.stake_balance, amount);

        // Collect total fee if applicable
        if (total_fee > 0) {
            let fee_balance = balance::split(&mut stake_balance, total_fee);
            balance::join(&mut pool.collected_fees, fee_balance);
        };

        // Update position
        position::remove_stake(position, amount, pool.acc_reward_per_share);

        let stake_coin = coin::from_balance(stake_balance, ctx);

        events::emit_unstaked(
            pool_id,
            position::id(position),
            tx_context::sender(ctx),
            amount,
            total_fee,
            pool.total_staked,
        );

        (stake_coin, reward_coin)
    }

    /// Claim pending rewards without unstaking
    public fun claim_rewards<StakeToken, RewardToken>(
        pool: &mut StakingPool<StakeToken, RewardToken>,
        position: &mut StakingPosition<StakeToken>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<RewardToken> {
        let current_time = sui::clock::timestamp_ms(clock);
        let pool_id = object::uid_to_inner(&pool.id);

        // Validations
        position::assert_pool_match(position, pool_id);

        // Update pool rewards
        update_pool_rewards(pool, current_time);

        // Calculate pending rewards
        let pending = position::calculate_pending_rewards(position, pool.acc_reward_per_share);
        assert!(pending > 0, errors::nothing_to_claim());
        assert!(balance::value(&pool.reward_balance) >= pending, errors::insufficient_rewards());

        // Claim rewards
        let reward_balance = balance::split(&mut pool.reward_balance, pending);
        pool.total_rewards_distributed = pool.total_rewards_distributed + pending;

        // Update position reward debt
        position::update_reward_debt(position, pool.acc_reward_per_share, current_time);

        events::emit_rewards_claimed(
            pool_id,
            position::id(position),
            tx_context::sender(ctx),
            pending,
        );

        coin::from_balance(reward_balance, ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POOL MANAGEMENT (Admin)
    // ═══════════════════════════════════════════════════════════════════════

    /// Add more rewards to the pool
    public fun add_rewards<StakeToken, RewardToken>(
        pool: &mut StakingPool<StakeToken, RewardToken>,
        admin_cap: &PoolAdminCap,
        reward_coins: Coin<RewardToken>,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let pool_id = object::uid_to_inner(&pool.id);
        assert!(access::pool_admin_cap_pool_id(admin_cap) == pool_id, errors::pool_admin_mismatch());

        let amount = coin::value(&reward_coins);
        assert!(amount > 0, errors::zero_amount());

        let current_time = sui::clock::timestamp_ms(clock);
        update_pool_rewards(pool, current_time);

        balance::join(&mut pool.reward_balance, coin::into_balance(reward_coins));
        pool.config.total_rewards = pool.config.total_rewards + amount;

        // Recalculate reward rate
        let remaining_time = if (current_time < pool.config.end_time_ms) {
            pool.config.end_time_ms - current_time
        } else {
            0
        };

        if (remaining_time > 0) {
            let remaining_rewards = balance::value(&pool.reward_balance);
            pool.reward_rate = math::calculate_reward_rate(remaining_rewards, remaining_time);
        };

        events::emit_rewards_added(
            pool_id,
            amount,
            pool.config.total_rewards,
            tx_context::sender(ctx),
        );
    }

    /// Update pool configuration
    public fun update_config<StakeToken, RewardToken>(
        pool: &mut StakingPool<StakeToken, RewardToken>,
        admin_cap: &PoolAdminCap,
        min_stake_duration_ms: u64,
        early_unstake_fee_bps: u64,
        stake_fee_bps: u64,
        unstake_fee_bps: u64,
        ctx: &TxContext,
    ) {
        let pool_id = object::uid_to_inner(&pool.id);
        assert!(access::pool_admin_cap_pool_id(admin_cap) == pool_id, errors::pool_admin_mismatch());
        assert!(math::is_valid_early_fee(early_unstake_fee_bps), errors::fee_too_high());
        assert!(math::is_valid_stake_fee(stake_fee_bps), errors::fee_too_high());
        assert!(math::is_valid_unstake_fee(unstake_fee_bps), errors::fee_too_high());

        pool.config.min_stake_duration_ms = min_stake_duration_ms;
        pool.config.early_unstake_fee_bps = early_unstake_fee_bps;
        pool.config.stake_fee_bps = stake_fee_bps;
        pool.config.unstake_fee_bps = unstake_fee_bps;

        events::emit_pool_config_updated(
            pool_id,
            min_stake_duration_ms,
            early_unstake_fee_bps,
            stake_fee_bps,
            unstake_fee_bps,
            tx_context::sender(ctx),
        );
    }

    /// Pause/unpause the pool
    public fun set_paused<StakeToken, RewardToken>(
        pool: &mut StakingPool<StakeToken, RewardToken>,
        admin_cap: &PoolAdminCap,
        paused: bool,
        ctx: &TxContext,
    ) {
        let pool_id = object::uid_to_inner(&pool.id);
        assert!(access::pool_admin_cap_pool_id(admin_cap) == pool_id, errors::pool_admin_mismatch());

        pool.config.paused = paused;

        events::emit_pool_pause_toggled(
            pool_id,
            paused,
            tx_context::sender(ctx),
        );
    }

    /// Withdraw collected fees
    public fun withdraw_fees<StakeToken, RewardToken>(
        pool: &mut StakingPool<StakeToken, RewardToken>,
        admin_cap: &PoolAdminCap,
        ctx: &mut TxContext,
    ): Coin<StakeToken> {
        let pool_id = object::uid_to_inner(&pool.id);
        assert!(access::pool_admin_cap_pool_id(admin_cap) == pool_id, errors::pool_admin_mismatch());

        let fee_amount = balance::value(&pool.collected_fees);
        assert!(fee_amount > 0, errors::zero_amount());

        let fee_balance = balance::split(&mut pool.collected_fees, fee_amount);
        coin::from_balance(fee_balance, ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Update accumulated reward per share
    fun update_pool_rewards<StakeToken, RewardToken>(
        pool: &mut StakingPool<StakeToken, RewardToken>,
        current_time: u64,
    ) {
        // Cap time at end time
        let effective_time = if (current_time > pool.config.end_time_ms) {
            pool.config.end_time_ms
        } else {
            current_time
        };

        // No update needed if before start or already up to date
        if (effective_time <= pool.last_reward_time_ms || effective_time < pool.config.start_time_ms) {
            return
        };

        // Calculate time elapsed since last update
        let time_elapsed = effective_time - pool.last_reward_time_ms;

        // Calculate new rewards
        let new_rewards = math::calculate_rewards_earned(time_elapsed, pool.reward_rate);

        // Update accumulated reward per share
        if (new_rewards > 0) {
            pool.acc_reward_per_share = math::calculate_acc_reward_per_share(
                pool.acc_reward_per_share,
                new_rewards,
                pool.total_staked,
            );
        };

        pool.last_reward_time_ms = effective_time;
    }

    /// Emit pool created event with type info
    fun pool_emit_created<StakeToken, RewardToken>(
        pool: &StakingPool<StakeToken, RewardToken>,
        ctx: &TxContext,
    ) {
        let stake_type = std::type_name::with_original_ids<StakeToken>();
        let reward_type = std::type_name::with_original_ids<RewardToken>();

        events::emit_pool_created(
            object::uid_to_inner(&pool.id),
            tx_context::sender(ctx),
            std::type_name::into_string(stake_type),
            std::type_name::into_string(reward_type),
            pool.config.total_rewards,
            pool.config.start_time_ms,
            pool.config.end_time_ms,
            pool.config.min_stake_duration_ms,
            pool.config.early_unstake_fee_bps,
            pool.config.stake_fee_bps,
            pool.config.unstake_fee_bps,
        );
    }

    /// Emit governance pool created event
    fun pool_emit_governance_created<StakeToken, RewardToken>(
        pool: &StakingPool<StakeToken, RewardToken>,
        ctx: &TxContext,
    ) {
        let stake_type = std::type_name::with_original_ids<StakeToken>();

        events::emit_governance_pool_created(
            object::uid_to_inner(&pool.id),
            tx_context::sender(ctx),
            std::type_name::into_string(stake_type),
            pool.config.min_stake_duration_ms,
            pool.config.early_unstake_fee_bps,
            pool.config.stake_fee_bps,
            pool.config.unstake_fee_bps,
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun pool_id<StakeToken, RewardToken>(pool: &StakingPool<StakeToken, RewardToken>): ID {
        object::uid_to_inner(&pool.id)
    }

    public fun total_staked<StakeToken, RewardToken>(pool: &StakingPool<StakeToken, RewardToken>): u64 {
        pool.total_staked
    }

    public fun reward_balance<StakeToken, RewardToken>(pool: &StakingPool<StakeToken, RewardToken>): u64 {
        balance::value(&pool.reward_balance)
    }

    public fun acc_reward_per_share<StakeToken, RewardToken>(pool: &StakingPool<StakeToken, RewardToken>): u128 {
        pool.acc_reward_per_share
    }

    public fun reward_rate<StakeToken, RewardToken>(pool: &StakingPool<StakeToken, RewardToken>): u64 {
        pool.reward_rate
    }

    public fun total_rewards_distributed<StakeToken, RewardToken>(pool: &StakingPool<StakeToken, RewardToken>): u64 {
        pool.total_rewards_distributed
    }

    public fun collected_fees<StakeToken, RewardToken>(pool: &StakingPool<StakeToken, RewardToken>): u64 {
        balance::value(&pool.collected_fees)
    }

    public fun config<StakeToken, RewardToken>(pool: &StakingPool<StakeToken, RewardToken>): &PoolConfig {
        &pool.config
    }

    public fun is_paused<StakeToken, RewardToken>(pool: &StakingPool<StakeToken, RewardToken>): bool {
        pool.config.paused
    }

    public fun is_active<StakeToken, RewardToken>(pool: &StakingPool<StakeToken, RewardToken>, current_time: u64): bool {
        !pool.config.paused &&
        current_time >= pool.config.start_time_ms &&
        current_time < pool.config.end_time_ms
    }

    // Config getters
    public fun config_creator(config: &PoolConfig): address { config.creator }
    public fun config_start_time_ms(config: &PoolConfig): u64 { config.start_time_ms }
    public fun config_end_time_ms(config: &PoolConfig): u64 { config.end_time_ms }
    public fun config_total_rewards(config: &PoolConfig): u64 { config.total_rewards }
    public fun config_min_stake_duration_ms(config: &PoolConfig): u64 { config.min_stake_duration_ms }
    public fun config_early_unstake_fee_bps(config: &PoolConfig): u64 { config.early_unstake_fee_bps }
    public fun config_stake_fee_bps(config: &PoolConfig): u64 { config.stake_fee_bps }
    public fun config_unstake_fee_bps(config: &PoolConfig): u64 { config.unstake_fee_bps }
    public fun config_governance_only(config: &PoolConfig): bool { config.governance_only }

    /// Check if pool is governance-only (no rewards)
    public fun is_governance_only<StakeToken, RewardToken>(pool: &StakingPool<StakeToken, RewardToken>): bool {
        pool.config.governance_only
    }

    /// Calculate pending rewards for a position (view function)
    public fun pending_rewards<StakeToken, RewardToken>(
        pool: &StakingPool<StakeToken, RewardToken>,
        position: &StakingPosition<StakeToken>,
        current_time: u64,
    ): u64 {
        // Calculate what acc_reward_per_share would be at current_time
        let effective_time = if (current_time > pool.config.end_time_ms) {
            pool.config.end_time_ms
        } else {
            current_time
        };

        let mut simulated_acc = pool.acc_reward_per_share;

        if (effective_time > pool.last_reward_time_ms && effective_time >= pool.config.start_time_ms) {
            let time_elapsed = effective_time - pool.last_reward_time_ms;
            let new_rewards = math::calculate_rewards_earned(time_elapsed, pool.reward_rate);

            if (new_rewards > 0 && pool.total_staked > 0) {
                simulated_acc = math::calculate_acc_reward_per_share(
                    simulated_acc,
                    new_rewards,
                    pool.total_staked,
                );
            };
        };

        position::calculate_pending_rewards(position, simulated_acc)
    }

    public fun min_stake_amount(): u64 { MIN_STAKE_AMOUNT }
}
