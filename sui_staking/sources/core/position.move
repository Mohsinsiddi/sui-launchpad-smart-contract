/// Staking Position NFT - represents a user's stake in a pool
/// Transferable NFT that tracks staked amount, reward debt, and stake time
/// Supports tiered locking with boost multipliers for rewards and voting power
module sui_staking::position {
    use sui_staking::math;
    use sui_staking::errors;

    // ═══════════════════════════════════════════════════════════════════════
    // LOCK TIER CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// No lock - 1.0x multiplier (base)
    const LOCK_TIER_NONE: u8 = 0;
    /// 30 day lock - 1.0x multiplier
    const LOCK_TIER_30D: u8 = 1;
    /// 90 day lock - 1.5x multiplier
    const LOCK_TIER_90D: u8 = 2;
    /// 180 day lock - 2.0x multiplier
    const LOCK_TIER_180D: u8 = 3;
    /// 365 day lock - 3.0x multiplier
    const LOCK_TIER_365D: u8 = 4;

    /// Lock durations in milliseconds
    const LOCK_DURATION_30D_MS: u64 = 2_592_000_000;   // 30 days
    const LOCK_DURATION_90D_MS: u64 = 7_776_000_000;   // 90 days
    const LOCK_DURATION_180D_MS: u64 = 15_552_000_000; // 180 days
    const LOCK_DURATION_365D_MS: u64 = 31_536_000_000; // 365 days

    /// Boost multipliers in basis points (10000 = 1.0x)
    const BOOST_NONE_BPS: u64 = 10000;   // 1.0x
    const BOOST_30D_BPS: u64 = 10000;    // 1.0x
    const BOOST_90D_BPS: u64 = 15000;    // 1.5x
    const BOOST_180D_BPS: u64 = 20000;   // 2.0x
    const BOOST_365D_BPS: u64 = 30000;   // 3.0x

    // ═══════════════════════════════════════════════════════════════════════
    // POSITION NFT
    // ═══════════════════════════════════════════════════════════════════════

    /// NFT representing a staking position
    /// Generic over StakeToken type for type safety
    public struct StakingPosition<phantom StakeToken> has key, store {
        id: UID,
        /// The pool this position belongs to
        pool_id: ID,
        /// Amount of tokens staked
        staked_amount: u64,
        /// Reward debt for MasterChef calculation
        /// reward_debt = staked_amount * acc_reward_per_share / PRECISION
        reward_debt: u128,
        /// Timestamp when position was created (for early unstake fee)
        stake_time_ms: u64,
        /// Last time rewards were claimed
        last_claim_time_ms: u64,
        /// Lock tier (0=none, 1=30d, 2=90d, 3=180d, 4=365d)
        lock_tier: u8,
        /// Timestamp when lock expires (0 if no lock)
        lock_until_ms: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new staking position (no lock)
    public fun create<StakeToken>(
        pool_id: ID,
        staked_amount: u64,
        acc_reward_per_share: u128,
        current_time_ms: u64,
        ctx: &mut TxContext,
    ): StakingPosition<StakeToken> {
        create_with_lock(pool_id, staked_amount, acc_reward_per_share, current_time_ms, LOCK_TIER_NONE, ctx)
    }

    /// Create a new staking position with optional lock tier
    /// Lock tier: 0=none, 1=30d, 2=90d, 3=180d, 4=365d
    public fun create_with_lock<StakeToken>(
        pool_id: ID,
        staked_amount: u64,
        acc_reward_per_share: u128,
        current_time_ms: u64,
        lock_tier: u8,
        ctx: &mut TxContext,
    ): StakingPosition<StakeToken> {
        assert!(lock_tier <= LOCK_TIER_365D, errors::invalid_config());

        let reward_debt = math::calculate_reward_debt(staked_amount, acc_reward_per_share);
        let lock_until_ms = calculate_lock_until(current_time_ms, lock_tier);

        StakingPosition {
            id: object::new(ctx),
            pool_id,
            staked_amount,
            reward_debt,
            stake_time_ms: current_time_ms,
            last_claim_time_ms: current_time_ms,
            lock_tier,
            lock_until_ms,
        }
    }

    /// Calculate when lock expires based on tier
    fun calculate_lock_until(current_time_ms: u64, lock_tier: u8): u64 {
        if (lock_tier == LOCK_TIER_NONE) {
            0
        } else if (lock_tier == LOCK_TIER_30D) {
            current_time_ms + LOCK_DURATION_30D_MS
        } else if (lock_tier == LOCK_TIER_90D) {
            current_time_ms + LOCK_DURATION_90D_MS
        } else if (lock_tier == LOCK_TIER_180D) {
            current_time_ms + LOCK_DURATION_180D_MS
        } else {
            current_time_ms + LOCK_DURATION_365D_MS
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get position ID
    public fun id<StakeToken>(position: &StakingPosition<StakeToken>): ID {
        object::uid_to_inner(&position.id)
    }

    /// Get the pool ID this position belongs to
    public fun pool_id<StakeToken>(position: &StakingPosition<StakeToken>): ID {
        position.pool_id
    }

    /// Get staked amount
    public fun staked_amount<StakeToken>(position: &StakingPosition<StakeToken>): u64 {
        position.staked_amount
    }

    /// Get reward debt
    public fun reward_debt<StakeToken>(position: &StakingPosition<StakeToken>): u128 {
        position.reward_debt
    }

    /// Get stake time
    public fun stake_time_ms<StakeToken>(position: &StakingPosition<StakeToken>): u64 {
        position.stake_time_ms
    }

    /// Get last claim time
    public fun last_claim_time_ms<StakeToken>(position: &StakingPosition<StakeToken>): u64 {
        position.last_claim_time_ms
    }

    /// Get lock tier (0=none, 1=30d, 2=90d, 3=180d, 4=365d)
    public fun lock_tier<StakeToken>(position: &StakingPosition<StakeToken>): u8 {
        position.lock_tier
    }

    /// Get lock expiry timestamp
    public fun lock_until_ms<StakeToken>(position: &StakingPosition<StakeToken>): u64 {
        position.lock_until_ms
    }

    /// Check if position is currently locked
    public fun is_locked<StakeToken>(position: &StakingPosition<StakeToken>, current_time_ms: u64): bool {
        position.lock_tier > LOCK_TIER_NONE && current_time_ms < position.lock_until_ms
    }

    /// Get boost multiplier in basis points (10000 = 1.0x)
    public fun boost_multiplier_bps<StakeToken>(position: &StakingPosition<StakeToken>): u64 {
        get_boost_for_tier(position.lock_tier)
    }

    /// Get boosted staked amount (for rewards and voting power)
    /// Returns: staked_amount * boost_multiplier / 10000
    public fun boosted_amount<StakeToken>(position: &StakingPosition<StakeToken>): u64 {
        let boost = get_boost_for_tier(position.lock_tier);
        (((position.staked_amount as u128) * (boost as u128) / 10000) as u64)
    }

    /// Get voting power (same as boosted amount for locked positions)
    public fun voting_power<StakeToken>(position: &StakingPosition<StakeToken>): u64 {
        boosted_amount(position)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LOCK TIER HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get boost multiplier for a lock tier (in basis points)
    public fun get_boost_for_tier(lock_tier: u8): u64 {
        if (lock_tier == LOCK_TIER_NONE) {
            BOOST_NONE_BPS
        } else if (lock_tier == LOCK_TIER_30D) {
            BOOST_30D_BPS
        } else if (lock_tier == LOCK_TIER_90D) {
            BOOST_90D_BPS
        } else if (lock_tier == LOCK_TIER_180D) {
            BOOST_180D_BPS
        } else {
            BOOST_365D_BPS
        }
    }

    /// Get lock duration for a tier in milliseconds
    public fun get_duration_for_tier(lock_tier: u8): u64 {
        if (lock_tier == LOCK_TIER_NONE) {
            0
        } else if (lock_tier == LOCK_TIER_30D) {
            LOCK_DURATION_30D_MS
        } else if (lock_tier == LOCK_TIER_90D) {
            LOCK_DURATION_90D_MS
        } else if (lock_tier == LOCK_TIER_180D) {
            LOCK_DURATION_180D_MS
        } else {
            LOCK_DURATION_365D_MS
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LOCK TIER CONSTANT GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun lock_tier_none(): u8 { LOCK_TIER_NONE }
    public fun lock_tier_30d(): u8 { LOCK_TIER_30D }
    public fun lock_tier_90d(): u8 { LOCK_TIER_90D }
    public fun lock_tier_180d(): u8 { LOCK_TIER_180D }
    public fun lock_tier_365d(): u8 { LOCK_TIER_365D }

    public fun lock_duration_30d_ms(): u64 { LOCK_DURATION_30D_MS }
    public fun lock_duration_90d_ms(): u64 { LOCK_DURATION_90D_MS }
    public fun lock_duration_180d_ms(): u64 { LOCK_DURATION_180D_MS }
    public fun lock_duration_365d_ms(): u64 { LOCK_DURATION_365D_MS }

    public fun boost_none_bps(): u64 { BOOST_NONE_BPS }
    public fun boost_30d_bps(): u64 { BOOST_30D_BPS }
    public fun boost_90d_bps(): u64 { BOOST_90D_BPS }
    public fun boost_180d_bps(): u64 { BOOST_180D_BPS }
    public fun boost_365d_bps(): u64 { BOOST_365D_BPS }

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Verify position belongs to the specified pool
    public fun assert_pool_match<StakeToken>(
        position: &StakingPosition<StakeToken>,
        expected_pool_id: ID,
    ) {
        assert!(position.pool_id == expected_pool_id, errors::wrong_pool());
    }

    /// Verify position is not locked (can be unstaked)
    public fun assert_not_locked<StakeToken>(
        position: &StakingPosition<StakeToken>,
        current_time_ms: u64,
    ) {
        assert!(!is_locked(position, current_time_ms), errors::position_locked());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MUTATORS (called by pool module)
    // ═══════════════════════════════════════════════════════════════════════

    /// Add more stake to existing position
    /// Updates staked_amount and reward_debt
    /// Note: Should claim pending rewards before calling this
    public fun add_stake<StakeToken>(
        position: &mut StakingPosition<StakeToken>,
        additional_amount: u64,
        acc_reward_per_share: u128,
    ) {
        position.staked_amount = position.staked_amount + additional_amount;
        // Recalculate reward debt based on new total staked
        position.reward_debt = math::calculate_reward_debt(
            position.staked_amount,
            acc_reward_per_share,
        );
    }

    /// Remove stake from position (partial or full unstake)
    /// Updates staked_amount and reward_debt
    /// Note: Should claim pending rewards before calling this
    public fun remove_stake<StakeToken>(
        position: &mut StakingPosition<StakeToken>,
        amount_to_remove: u64,
        acc_reward_per_share: u128,
    ) {
        assert!(amount_to_remove <= position.staked_amount, errors::zero_amount());
        position.staked_amount = position.staked_amount - amount_to_remove;
        // Recalculate reward debt based on new total staked
        position.reward_debt = math::calculate_reward_debt(
            position.staked_amount,
            acc_reward_per_share,
        );
    }

    /// Update reward debt after claiming rewards
    public fun update_reward_debt<StakeToken>(
        position: &mut StakingPosition<StakeToken>,
        acc_reward_per_share: u128,
        current_time_ms: u64,
    ) {
        position.reward_debt = math::calculate_reward_debt(
            position.staked_amount,
            acc_reward_per_share,
        );
        position.last_claim_time_ms = current_time_ms;
    }

    /// Calculate pending rewards for this position
    public fun calculate_pending_rewards<StakeToken>(
        position: &StakingPosition<StakeToken>,
        acc_reward_per_share: u128,
    ): u64 {
        math::calculate_pending_rewards(
            position.staked_amount,
            acc_reward_per_share,
            position.reward_debt,
        )
    }

    /// Calculate early unstake fee for this position
    public fun calculate_early_fee<StakeToken>(
        position: &StakingPosition<StakeToken>,
        amount: u64,
        current_time_ms: u64,
        min_stake_duration_ms: u64,
        early_fee_bps: u64,
    ): u64 {
        math::calculate_early_unstake_fee(
            amount,
            position.stake_time_ms,
            current_time_ms,
            min_stake_duration_ms,
            early_fee_bps,
        )
    }

    /// Check if position can unstake without fee
    public fun can_unstake_without_fee<StakeToken>(
        position: &StakingPosition<StakeToken>,
        current_time_ms: u64,
        min_stake_duration_ms: u64,
    ): bool {
        current_time_ms >= position.stake_time_ms + min_stake_duration_ms
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LOCK MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /// Extend lock to a higher tier (cannot reduce lock)
    /// Returns new lock_until_ms
    public fun extend_lock<StakeToken>(
        position: &mut StakingPosition<StakeToken>,
        new_tier: u8,
        current_time_ms: u64,
    ): u64 {
        assert!(new_tier <= LOCK_TIER_365D, errors::invalid_lock_tier());
        assert!(new_tier > position.lock_tier, errors::cannot_reduce_lock());

        position.lock_tier = new_tier;
        position.lock_until_ms = calculate_lock_until(current_time_ms, new_tier);
        position.lock_until_ms
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DESTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// Destroy an empty position (after full unstake)
    public fun destroy_empty<StakeToken>(position: StakingPosition<StakeToken>) {
        assert!(position.staked_amount == 0, errors::zero_amount());
        let StakingPosition {
            id,
            pool_id: _,
            staked_amount: _,
            reward_debt: _,
            stake_time_ms: _,
            last_claim_time_ms: _,
            lock_tier: _,
            lock_until_ms: _,
        } = position;
        object::delete(id);
    }

    /// Force destroy a position (used by pool during full unstake)
    /// The stake has already been removed from the pool balance
    public(package) fun destroy_empty_force<StakeToken>(position: StakingPosition<StakeToken>) {
        let StakingPosition {
            id,
            pool_id: _,
            staked_amount: _,
            reward_debt: _,
            stake_time_ms: _,
            last_claim_time_ms: _,
            lock_tier: _,
            lock_until_ms: _,
        } = position;
        object::delete(id);
    }

    /// Destroy a position regardless of staked amount (emergency use)
    /// Should only be called after tokens have been extracted
    public(package) fun destroy_position<StakeToken>(position: StakingPosition<StakeToken>) {
        let StakingPosition {
            id,
            pool_id: _,
            staked_amount: _,
            reward_debt: _,
            stake_time_ms: _,
            last_claim_time_ms: _,
            lock_tier: _,
            lock_until_ms: _,
        } = position;
        object::delete(id);
    }

    /// Set staked amount (package level for emergency use)
    public(package) fun set_staked_amount<StakeToken>(
        position: &mut StakingPosition<StakeToken>,
        amount: u64,
    ) {
        position.staked_amount = amount;
    }

    /// Set reward debt (package level for emergency use)
    public(package) fun set_reward_debt<StakeToken>(
        position: &mut StakingPosition<StakeToken>,
        debt: u128,
    ) {
        position.reward_debt = debt;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public struct TestToken has drop {}

    #[test]
    fun test_create_position() {
        let mut ctx = tx_context::dummy();
        let pool_id = object::id_from_address(@0x123);

        let position = create<TestToken>(
            pool_id,
            1000, // staked amount
            0,    // initial acc_reward_per_share
            1000, // current time
            &mut ctx,
        );

        assert!(staked_amount(&position) == 1000, 0);
        assert!(reward_debt(&position) == 0, 1);
        assert!(stake_time_ms(&position) == 1000, 2);
        assert!(pool_id(&position) == pool_id, 3);
        assert!(lock_tier(&position) == LOCK_TIER_NONE, 4);
        assert!(lock_until_ms(&position) == 0, 5);

        // Clean up - need to unstake first
        let StakingPosition {
            id,
            pool_id: _,
            staked_amount: _,
            reward_debt: _,
            stake_time_ms: _,
            last_claim_time_ms: _,
            lock_tier: _,
            lock_until_ms: _,
        } = position;
        object::delete(id);
    }

    #[test]
    fun test_create_position_with_lock() {
        let mut ctx = tx_context::dummy();
        let pool_id = object::id_from_address(@0x123);
        let current_time = 1000u64;

        // Create position with 90-day lock (1.5x boost)
        let position = create_with_lock<TestToken>(
            pool_id,
            1000,
            0,
            current_time,
            LOCK_TIER_90D,
            &mut ctx,
        );

        assert!(staked_amount(&position) == 1000, 0);
        assert!(lock_tier(&position) == LOCK_TIER_90D, 1);
        assert!(lock_until_ms(&position) == current_time + LOCK_DURATION_90D_MS, 2);
        assert!(boost_multiplier_bps(&position) == BOOST_90D_BPS, 3);
        // Boosted amount = 1000 * 1.5 = 1500
        assert!(boosted_amount(&position) == 1500, 4);
        assert!(voting_power(&position) == 1500, 5);
        // Position is locked
        assert!(is_locked(&position, current_time + 1000), 6);
        // Position is not locked after expiry
        assert!(!is_locked(&position, current_time + LOCK_DURATION_90D_MS + 1), 7);

        let StakingPosition {
            id,
            pool_id: _,
            staked_amount: _,
            reward_debt: _,
            stake_time_ms: _,
            last_claim_time_ms: _,
            lock_tier: _,
            lock_until_ms: _,
        } = position;
        object::delete(id);
    }

    #[test]
    fun test_extend_lock() {
        let mut ctx = tx_context::dummy();
        let pool_id = object::id_from_address(@0x123);
        let current_time = 1000u64;

        // Create with 30-day lock
        let mut position = create_with_lock<TestToken>(
            pool_id,
            1000,
            0,
            current_time,
            LOCK_TIER_30D,
            &mut ctx,
        );

        assert!(lock_tier(&position) == LOCK_TIER_30D, 0);
        assert!(boost_multiplier_bps(&position) == BOOST_30D_BPS, 1);

        // Extend to 365-day lock (3x boost)
        let new_lock = extend_lock(&mut position, LOCK_TIER_365D, current_time);
        assert!(new_lock == current_time + LOCK_DURATION_365D_MS, 2);
        assert!(lock_tier(&position) == LOCK_TIER_365D, 3);
        assert!(boost_multiplier_bps(&position) == BOOST_365D_BPS, 4);
        // Boosted amount = 1000 * 3 = 3000
        assert!(boosted_amount(&position) == 3000, 5);

        let StakingPosition {
            id,
            pool_id: _,
            staked_amount: _,
            reward_debt: _,
            stake_time_ms: _,
            last_claim_time_ms: _,
            lock_tier: _,
            lock_until_ms: _,
        } = position;
        object::delete(id);
    }

    #[test]
    #[expected_failure(abort_code = 206)] // ECannotReduceLock
    fun test_cannot_reduce_lock() {
        let mut ctx = tx_context::dummy();
        let pool_id = object::id_from_address(@0x123);

        // Create with 90-day lock
        let mut position = create_with_lock<TestToken>(
            pool_id,
            1000,
            0,
            1000,
            LOCK_TIER_90D,
            &mut ctx,
        );

        // Try to reduce to 30-day lock - should fail
        extend_lock(&mut position, LOCK_TIER_30D, 2000);

        let StakingPosition {
            id,
            pool_id: _,
            staked_amount: _,
            reward_debt: _,
            stake_time_ms: _,
            last_claim_time_ms: _,
            lock_tier: _,
            lock_until_ms: _,
        } = position;
        object::delete(id);
    }

    #[test]
    fun test_add_stake() {
        let mut ctx = tx_context::dummy();
        let pool_id = object::id_from_address(@0x123);

        let mut position = create<TestToken>(
            pool_id,
            1000,
            0,
            1000,
            &mut ctx,
        );

        // Add 500 more stake
        add_stake(&mut position, 500, 0);
        assert!(staked_amount(&position) == 1500, 0);

        let StakingPosition {
            id,
            pool_id: _,
            staked_amount: _,
            reward_debt: _,
            stake_time_ms: _,
            last_claim_time_ms: _,
            lock_tier: _,
            lock_until_ms: _,
        } = position;
        object::delete(id);
    }

    #[test]
    fun test_remove_stake() {
        let mut ctx = tx_context::dummy();
        let pool_id = object::id_from_address(@0x123);

        let mut position = create<TestToken>(
            pool_id,
            1000,
            0,
            1000,
            &mut ctx,
        );

        // Remove 400 stake
        remove_stake(&mut position, 400, 0);
        assert!(staked_amount(&position) == 600, 0);

        let StakingPosition {
            id,
            pool_id: _,
            staked_amount: _,
            reward_debt: _,
            stake_time_ms: _,
            last_claim_time_ms: _,
            lock_tier: _,
            lock_until_ms: _,
        } = position;
        object::delete(id);
    }

    #[test]
    fun test_pending_rewards_calculation() {
        let mut ctx = tx_context::dummy();
        let pool_id = object::id_from_address(@0x123);

        // Create position with 1000 staked, initial acc = 0
        let position = create<TestToken>(
            pool_id,
            1000,
            0,    // initial acc_reward_per_share
            1000,
            &mut ctx,
        );

        // After pool accumulates rewards: acc = 2e18 (2 tokens per 1 staked)
        let acc = 2_000_000_000_000_000_000u128; // 2e18
        let pending = calculate_pending_rewards(&position, acc);

        // pending = (1000 * 2e18 / 1e18) - 0 = 2000
        assert!(pending == 2000, 0);

        let StakingPosition {
            id,
            pool_id: _,
            staked_amount: _,
            reward_debt: _,
            stake_time_ms: _,
            last_claim_time_ms: _,
            lock_tier: _,
            lock_until_ms: _,
        } = position;
        object::delete(id);
    }

    #[test]
    fun test_early_unstake_fee() {
        let mut ctx = tx_context::dummy();
        let pool_id = object::id_from_address(@0x123);

        let position = create<TestToken>(
            pool_id,
            1000,
            0,
            0,  // staked at time 0
            &mut ctx,
        );

        let ms_per_day = 86_400_000u64;

        // Unstaking after 1 day, min duration is 7 days, 5% fee
        let fee = calculate_early_fee(
            &position,
            1000,
            ms_per_day,      // current time: 1 day later
            ms_per_day * 7,  // min: 7 days
            500,             // 5% fee
        );
        assert!(fee == 50, 0); // 5% of 1000

        // Unstaking after 7 days, no fee
        let fee2 = calculate_early_fee(
            &position,
            1000,
            ms_per_day * 7,  // current time: 7 days later
            ms_per_day * 7,  // min: 7 days
            500,
        );
        assert!(fee2 == 0, 1);

        let StakingPosition {
            id,
            pool_id: _,
            staked_amount: _,
            reward_debt: _,
            stake_time_ms: _,
            last_claim_time_ms: _,
            lock_tier: _,
            lock_until_ms: _,
        } = position;
        object::delete(id);
    }

    #[test]
    fun test_destroy_empty() {
        let mut ctx = tx_context::dummy();
        let pool_id = object::id_from_address(@0x123);

        let mut position = create<TestToken>(
            pool_id,
            1000,
            0,
            1000,
            &mut ctx,
        );

        // Remove all stake
        remove_stake(&mut position, 1000, 0);
        assert!(staked_amount(&position) == 0, 0);

        // Now can destroy
        destroy_empty(position);
    }

    #[test]
    fun test_all_lock_tiers() {
        let mut ctx = tx_context::dummy();
        let pool_id = object::id_from_address(@0x123);
        let current_time = 1000u64;

        // Test each lock tier
        let tiers = vector[LOCK_TIER_NONE, LOCK_TIER_30D, LOCK_TIER_90D, LOCK_TIER_180D, LOCK_TIER_365D];
        let boosts = vector[BOOST_NONE_BPS, BOOST_30D_BPS, BOOST_90D_BPS, BOOST_180D_BPS, BOOST_365D_BPS];
        let durations = vector[0u64, LOCK_DURATION_30D_MS, LOCK_DURATION_90D_MS, LOCK_DURATION_180D_MS, LOCK_DURATION_365D_MS];

        let mut i = 0;
        while (i < 5) {
            let tier = *vector::borrow(&tiers, i);
            let expected_boost = *vector::borrow(&boosts, i);
            let expected_duration = *vector::borrow(&durations, i);

            let position = create_with_lock<TestToken>(
                pool_id,
                1000,
                0,
                current_time,
                tier,
                &mut ctx,
            );

            assert!(lock_tier(&position) == tier, i);
            assert!(boost_multiplier_bps(&position) == expected_boost, i + 10);

            let expected_lock_until = if (tier == LOCK_TIER_NONE) { 0 } else { current_time + expected_duration };
            assert!(lock_until_ms(&position) == expected_lock_until, i + 20);

            let StakingPosition {
                id,
                pool_id: _,
                staked_amount: _,
                reward_debt: _,
                stake_time_ms: _,
                last_claim_time_ms: _,
                lock_tier: _,
                lock_until_ms: _,
            } = position;
            object::delete(id);

            i = i + 1;
        };
    }
}
