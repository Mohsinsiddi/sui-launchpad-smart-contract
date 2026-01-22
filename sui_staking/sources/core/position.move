/// Staking Position NFT - represents a user's stake in a pool
/// Transferable NFT that tracks staked amount, reward debt, and stake time
module sui_staking::position {
    use sui_staking::math;
    use sui_staking::errors;

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
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new staking position
    public fun create<StakeToken>(
        pool_id: ID,
        staked_amount: u64,
        acc_reward_per_share: u128,
        current_time_ms: u64,
        ctx: &mut TxContext,
    ): StakingPosition<StakeToken> {
        let reward_debt = math::calculate_reward_debt(staked_amount, acc_reward_per_share);

        StakingPosition {
            id: object::new(ctx),
            pool_id,
            staked_amount,
            reward_debt,
            stake_time_ms: current_time_ms,
            last_claim_time_ms: current_time_ms,
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
        } = position;
        object::delete(id);
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

        // Clean up - need to unstake first
        let StakingPosition {
            id,
            pool_id: _,
            staked_amount: _,
            reward_debt: _,
            stake_time_ms: _,
            last_claim_time_ms: _,
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
}
