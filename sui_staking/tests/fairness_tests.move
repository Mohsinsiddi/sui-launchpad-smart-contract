/// Strict fairness tests for the staking reward system
/// Verifies that the reward debt model is mathematically fair and correct
#[test_only]
module sui_staking::fairness_tests {
    use sui_staking::math;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    const PRECISION: u128 = 1_000_000_000_000_000_000; // 1e18
    const MS_PER_DAY: u64 = 86_400_000;

    // ═══════════════════════════════════════════════════════════════════════
    // INVARIANT 1: TOTAL REWARDS CONSERVATION
    // Sum of all user rewards must equal total distributed rewards
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_invariant_reward_conservation_two_users() {
        // Setup: 1,000,000 rewards distributed
        let total_rewards = 1_000_000u64;
        let alice_stake = 600_000u64; // 60%
        let bob_stake = 400_000u64;   // 40%
        let total_staked = alice_stake + bob_stake;

        // Calculate accumulated reward per share
        let acc = math::calculate_acc_reward_per_share(0, total_rewards, total_staked);

        // Calculate each user's rewards
        let alice_rewards = math::calculate_pending_rewards(alice_stake, acc, 0);
        let bob_rewards = math::calculate_pending_rewards(bob_stake, acc, 0);

        // INVARIANT: alice_rewards + bob_rewards == total_rewards
        assert!(alice_rewards + bob_rewards == total_rewards, 0);
    }

    #[test]
    fun test_invariant_reward_conservation_three_users() {
        let total_rewards = 1_000_000u64;
        let alice_stake = 500_000u64; // 50%
        let bob_stake = 300_000u64;   // 30%
        let charlie_stake = 200_000u64; // 20%
        let total_staked = alice_stake + bob_stake + charlie_stake;

        let acc = math::calculate_acc_reward_per_share(0, total_rewards, total_staked);

        let alice_rewards = math::calculate_pending_rewards(alice_stake, acc, 0);
        let bob_rewards = math::calculate_pending_rewards(bob_stake, acc, 0);
        let charlie_rewards = math::calculate_pending_rewards(charlie_stake, acc, 0);

        // INVARIANT: sum of all rewards == total_rewards
        assert!(alice_rewards + bob_rewards + charlie_rewards == total_rewards, 0);
    }

    #[test]
    fun test_invariant_reward_conservation_many_users() {
        let total_rewards = 10_000_000u64;
        let num_users = 10u64;
        let stake_per_user = 100_000u64;
        let total_staked = stake_per_user * num_users;

        let acc = math::calculate_acc_reward_per_share(0, total_rewards, total_staked);

        // Each user should get exactly 1/10 of rewards
        let rewards_per_user = math::calculate_pending_rewards(stake_per_user, acc, 0);

        // INVARIANT: each user gets equal share
        assert!(rewards_per_user == total_rewards / num_users, 0);

        // INVARIANT: total distributed == total_rewards
        assert!(rewards_per_user * num_users == total_rewards, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INVARIANT 2: PROPORTIONALITY
    // Rewards must be proportional to stake weight
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_invariant_proportional_rewards() {
        let total_rewards = 1_000_000u64;

        // Alice stakes 3x more than Bob
        let alice_stake = 750_000u64;
        let bob_stake = 250_000u64;
        let total_staked = alice_stake + bob_stake;

        let acc = math::calculate_acc_reward_per_share(0, total_rewards, total_staked);

        let alice_rewards = math::calculate_pending_rewards(alice_stake, acc, 0);
        let bob_rewards = math::calculate_pending_rewards(bob_stake, acc, 0);

        // INVARIANT: alice_rewards == 3 * bob_rewards
        assert!(alice_rewards == 3 * bob_rewards, 0);

        // INVARIANT: alice gets 75%, bob gets 25%
        assert!(alice_rewards == 750_000, 1);
        assert!(bob_rewards == 250_000, 2);
    }

    #[test]
    fun test_invariant_proportional_large_difference() {
        let total_rewards = 10_000_000u64;

        // Whale: 99%, Minnow: 1%
        let whale_stake = 99_000_000u64;
        let minnow_stake = 1_000_000u64;
        let total_staked = whale_stake + minnow_stake;

        let acc = math::calculate_acc_reward_per_share(0, total_rewards, total_staked);

        let whale_rewards = math::calculate_pending_rewards(whale_stake, acc, 0);
        let minnow_rewards = math::calculate_pending_rewards(minnow_stake, acc, 0);

        // INVARIANT: whale gets 99x minnow's rewards
        assert!(whale_rewards == 99 * minnow_rewards, 0);

        // INVARIANT: correct percentages
        assert!(whale_rewards == 9_900_000, 1);
        assert!(minnow_rewards == 100_000, 2);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INVARIANT 3: REWARD DEBT PREVENTS DOUBLE CLAIMING
    // Users cannot claim rewards from before they staked
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_invariant_no_retroactive_rewards() {
        let rewards_per_period = 500_000u64;
        let alice_stake = 100_000u64;

        // Period 1: Only Alice staked
        let acc1 = math::calculate_acc_reward_per_share(0, rewards_per_period, alice_stake);

        // Bob joins at acc1 - his debt should prevent claiming period 1 rewards
        let bob_stake = 100_000u64;
        let bob_debt = math::calculate_reward_debt(bob_stake, acc1);

        // Period 2: Both staked
        let total_staked = alice_stake + bob_stake;
        let acc2 = math::calculate_acc_reward_per_share(acc1, rewards_per_period, total_staked);

        // Calculate rewards
        let alice_rewards = math::calculate_pending_rewards(alice_stake, acc2, 0);
        let bob_rewards = math::calculate_pending_rewards(bob_stake, acc2, bob_debt);

        // INVARIANT: Bob only gets period 2 rewards (250,000)
        assert!(bob_rewards == 250_000, 0);

        // INVARIANT: Alice gets period 1 (500,000) + half of period 2 (250,000) = 750,000
        assert!(alice_rewards == 750_000, 1);

        // INVARIANT: Total distributed == total_rewards
        assert!(alice_rewards + bob_rewards == rewards_per_period * 2, 2);
    }

    #[test]
    fun test_invariant_debt_updates_on_claim() {
        let total_rewards = 1_000_000u64;
        let stake = 100_000u64;

        // Initial accumulation
        let acc1 = math::calculate_acc_reward_per_share(0, total_rewards, stake);

        // User's first claim
        let pending1 = math::calculate_pending_rewards(stake, acc1, 0);
        assert!(pending1 == total_rewards, 0);

        // After claim, debt is updated
        let new_debt = math::calculate_reward_debt(stake, acc1);

        // More rewards accumulate
        let acc2 = math::calculate_acc_reward_per_share(acc1, total_rewards, stake);

        // Second claim should only get new rewards
        let pending2 = math::calculate_pending_rewards(stake, acc2, new_debt);

        // INVARIANT: Second claim only gets second period's rewards
        assert!(pending2 == total_rewards, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INVARIANT 4: TIME-WEIGHTED REWARDS
    // Longer staking = proportionally more rewards
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_invariant_time_weighted_single_staker() {
        let reward_rate = 1000u64; // 1000 tokens per ms
        let duration = MS_PER_DAY;

        let earned = math::calculate_rewards_earned(duration, reward_rate);

        // INVARIANT: earned == rate * time
        assert!(earned == reward_rate * duration, 0);
    }

    #[test]
    fun test_invariant_time_weighted_multiple_periods() {
        let reward_rate = 1000u64;
        let stake = 100_000u64;

        // Period 1: full day
        let rewards1 = math::calculate_rewards_earned(MS_PER_DAY, reward_rate);
        let acc1 = math::calculate_acc_reward_per_share(0, rewards1, stake);

        // Period 2: half day
        let rewards2 = math::calculate_rewards_earned(MS_PER_DAY / 2, reward_rate);
        let acc2 = math::calculate_acc_reward_per_share(acc1, rewards2, stake);

        let total_pending = math::calculate_pending_rewards(stake, acc2, 0);

        // INVARIANT: total_pending == rewards1 + rewards2
        assert!(total_pending == rewards1 + rewards2, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INVARIANT 5: STAKE CHANGES DON'T AFFECT PAST REWARDS
    // Adding/removing stake doesn't change already-earned rewards
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_invariant_add_stake_preserves_earnings() {
        let initial_stake = 100_000u64;
        let rewards = 500_000u64;

        // Accumulate rewards with initial stake
        let acc1 = math::calculate_acc_reward_per_share(0, rewards, initial_stake);

        // Pending before adding stake
        let pending_before = math::calculate_pending_rewards(initial_stake, acc1, 0);

        // Add more stake (should claim pending first in real implementation)
        let additional_stake = 100_000u64;
        let new_total_stake = initial_stake + additional_stake;
        let new_debt = math::calculate_reward_debt(new_total_stake, acc1);

        // More rewards accumulate
        let acc2 = math::calculate_acc_reward_per_share(acc1, rewards, new_total_stake);

        // Calculate new pending
        let pending_after = math::calculate_pending_rewards(new_total_stake, acc2, new_debt);

        // INVARIANT: User effectively got pending_before (from claim) + pending_after (new earnings)
        // pending_after should be rewards (from period 2) since new_debt accounts for acc1
        assert!(pending_after == rewards, 0);
        assert!(pending_before == rewards, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INVARIANT 6: FEE CALCULATIONS ARE CORRECT
    // Fees must not exceed configured limits
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_invariant_fee_never_exceeds_amount() {
        let amount = 1000u64;

        // Test various fee rates
        let fee_0 = math::calculate_fee_bps(amount, 0);
        let fee_1 = math::calculate_fee_bps(amount, 100); // 1%
        let fee_5 = math::calculate_fee_bps(amount, 500); // 5%
        let fee_10 = math::calculate_fee_bps(amount, 1000); // 10%
        let fee_100 = math::calculate_fee_bps(amount, 10000); // 100%

        // INVARIANT: fee <= amount for any valid bps
        assert!(fee_0 <= amount, 0);
        assert!(fee_1 <= amount, 1);
        assert!(fee_5 <= amount, 2);
        assert!(fee_10 <= amount, 3);
        assert!(fee_100 <= amount, 4);

        // INVARIANT: 100% fee == amount
        assert!(fee_100 == amount, 5);
    }

    #[test]
    fun test_invariant_amount_after_fee_plus_fee_equals_original() {
        let amount = 10000u64;
        let fee_bps = 500u64; // 5%

        let fee = math::calculate_fee_bps(amount, fee_bps);
        let net = math::calculate_amount_after_fee(amount, fee_bps);

        // INVARIANT: fee + net == amount
        assert!(fee + net == amount, 0);
    }

    #[test]
    fun test_invariant_early_fee_respects_duration() {
        let amount = 100_000u64;
        let stake_time = 0u64;
        let min_duration = MS_PER_DAY * 7; // 7 days
        let fee_bps = 500u64; // 5%

        // Before min duration: fee applies
        let fee_early = math::calculate_early_unstake_fee(
            amount, stake_time, MS_PER_DAY, min_duration, fee_bps
        );
        assert!(fee_early == 5000, 0); // 5% of 100,000

        // At min duration: no fee
        let fee_at_min = math::calculate_early_unstake_fee(
            amount, stake_time, min_duration, min_duration, fee_bps
        );
        assert!(fee_at_min == 0, 1);

        // After min duration: no fee
        let fee_after = math::calculate_early_unstake_fee(
            amount, stake_time, min_duration * 2, min_duration, fee_bps
        );
        assert!(fee_after == 0, 2);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INVARIANT 7: PRECISION DOES NOT CAUSE UNFAIRNESS
    // Rounding should not systematically favor any party
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_invariant_precision_rounding_fair() {
        // Small rewards that may cause rounding
        let total_rewards = 100u64;
        let stake_a = 33u64;
        let stake_b = 33u64;
        let stake_c = 34u64;
        let total_staked = stake_a + stake_b + stake_c; // 100

        let acc = math::calculate_acc_reward_per_share(0, total_rewards, total_staked);

        let rewards_a = math::calculate_pending_rewards(stake_a, acc, 0);
        let rewards_b = math::calculate_pending_rewards(stake_b, acc, 0);
        let rewards_c = math::calculate_pending_rewards(stake_c, acc, 0);

        // INVARIANT: total distributed <= total_rewards (never more)
        assert!(rewards_a + rewards_b + rewards_c <= total_rewards, 0);

        // INVARIANT: equal stakes get equal rewards
        assert!(rewards_a == rewards_b, 1);

        // INVARIANT: slightly larger stake gets slightly more
        assert!(rewards_c >= rewards_a, 2);
    }

    #[test]
    fun test_invariant_large_numbers_no_overflow() {
        // Test with large but valid numbers
        let total_rewards = 1_000_000_000_000u64; // 1T
        let total_staked = 10_000_000_000u64; // 10B

        // This should not overflow
        let acc = math::calculate_acc_reward_per_share(0, total_rewards, total_staked);

        // Each token should earn 100 rewards (1T / 10B = 100)
        let pending_per_token = math::calculate_pending_rewards(1, acc, 0);
        assert!(pending_per_token == 100, 0);

        // Verify with larger stake
        let large_stake = 1_000_000u64;
        let pending_large = math::calculate_pending_rewards(large_stake, acc, 0);
        assert!(pending_large == 100_000_000, 1); // 1M * 100
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INVARIANT 8: ZERO EDGE CASES
    // System handles zero values correctly
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_invariant_zero_staked_no_accumulation() {
        let rewards = 1_000_000u64;

        // With zero staked, acc should not change
        let acc = math::calculate_acc_reward_per_share(PRECISION, rewards, 0);

        // INVARIANT: acc unchanged when total_staked = 0
        assert!(acc == PRECISION, 0);
    }

    #[test]
    fun test_invariant_zero_rewards_no_accumulation() {
        let staked = 1_000_000u64;

        let acc = math::calculate_acc_reward_per_share(PRECISION, 0, staked);

        // INVARIANT: acc unchanged when rewards = 0
        assert!(acc == PRECISION, 0);
    }

    #[test]
    fun test_invariant_zero_stake_zero_pending() {
        let acc = 2 * PRECISION; // 2 rewards per token

        let pending = math::calculate_pending_rewards(0, acc, 0);

        // INVARIANT: zero stake = zero rewards
        assert!(pending == 0, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COMPLEX SCENARIO: FULL STAKING LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_complex_scenario_full_lifecycle() {
        // Scenario: 3 users over 3 periods with varying stakes

        // PERIOD 1: Alice stakes alone
        let alice_stake = 100_000u64;
        let period1_rewards = 300_000u64;
        let acc1 = math::calculate_acc_reward_per_share(0, period1_rewards, alice_stake);
        let alice_debt1 = 0u128;

        // PERIOD 2: Bob joins
        let bob_stake = 200_000u64;
        let bob_debt2 = math::calculate_reward_debt(bob_stake, acc1);
        let total_staked_p2 = alice_stake + bob_stake; // 300,000
        let period2_rewards = 300_000u64;
        let acc2 = math::calculate_acc_reward_per_share(acc1, period2_rewards, total_staked_p2);

        // PERIOD 3: Charlie joins
        let charlie_stake = 300_000u64;
        let charlie_debt3 = math::calculate_reward_debt(charlie_stake, acc2);
        let total_staked_p3 = total_staked_p2 + charlie_stake; // 600,000
        let period3_rewards = 600_000u64;
        let acc3 = math::calculate_acc_reward_per_share(acc2, period3_rewards, total_staked_p3);

        // Calculate final rewards
        let alice_total = math::calculate_pending_rewards(alice_stake, acc3, alice_debt1);
        let bob_total = math::calculate_pending_rewards(bob_stake, acc3, bob_debt2);
        let charlie_total = math::calculate_pending_rewards(charlie_stake, acc3, charlie_debt3);

        // INVARIANT: Total distributed equals all rewards
        let total_distributed = alice_total + bob_total + charlie_total;
        let total_rewards = period1_rewards + period2_rewards + period3_rewards;
        assert!(total_distributed == total_rewards, 0);

        // INVARIANT: Alice's breakdown
        // P1: 300,000 (100% of 300K)
        // P2: 100,000 (1/3 of 300K)
        // P3: 100,000 (1/6 of 600K)
        // Total: 500,000
        assert!(alice_total == 500_000, 1);

        // INVARIANT: Bob's breakdown
        // P1: 0 (not staked)
        // P2: 200,000 (2/3 of 300K)
        // P3: 200,000 (2/6 of 600K)
        // Total: 400,000
        assert!(bob_total == 400_000, 2);

        // INVARIANT: Charlie's breakdown
        // P1: 0 (not staked)
        // P2: 0 (not staked)
        // P3: 300,000 (3/6 of 600K)
        // Total: 300,000
        assert!(charlie_total == 300_000, 3);
    }

    #[test]
    fun test_complex_scenario_partial_unstake() {
        // Alice stakes 1000, earns, partial unstakes 500, earns more

        let initial_stake = 1000u64;
        let rewards1 = 1000u64;

        // Period 1
        let acc1 = math::calculate_acc_reward_per_share(0, rewards1, initial_stake);
        let pending1 = math::calculate_pending_rewards(initial_stake, acc1, 0);
        assert!(pending1 == 1000, 0);

        // Alice claims and unstakes 500
        let remaining_stake = 500u64;
        let new_debt = math::calculate_reward_debt(remaining_stake, acc1);

        // Period 2
        let rewards2 = 1000u64;
        let acc2 = math::calculate_acc_reward_per_share(acc1, rewards2, remaining_stake);

        let pending2 = math::calculate_pending_rewards(remaining_stake, acc2, new_debt);

        // INVARIANT: Alice gets all of period 2 rewards (only staker)
        assert!(pending2 == 1000, 1);

        // INVARIANT: Total earned = rewards1 + rewards2
        assert!(pending1 + pending2 == rewards1 + rewards2, 2);
    }
}
