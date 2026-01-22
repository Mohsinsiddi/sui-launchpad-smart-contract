/// Comprehensive math tests for staking reward calculations
/// Tests precision, edge cases, and tokenomic scenarios
#[test_only]
module sui_staking::math_tests {
    use sui_staking::math;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS FOR TESTING
    // ═══════════════════════════════════════════════════════════════════════

    const PRECISION: u128 = 1_000_000_000_000_000_000; // 1e18
    const MS_PER_SECOND: u64 = 1_000;
    const MS_PER_MINUTE: u64 = 60_000;
    const MS_PER_HOUR: u64 = 3_600_000;
    const MS_PER_DAY: u64 = 86_400_000;
    const MS_PER_WEEK: u64 = 604_800_000;
    const MS_PER_YEAR: u64 = 31_536_000_000; // 365 days

    // Token decimals (common scenarios)
    const DECIMALS_6: u64 = 1_000_000; // USDC style
    const DECIMALS_9: u64 = 1_000_000_000; // SUI style
    const DECIMALS_18: u64 = 1_000_000_000_000_000_000; // ETH style

    // ═══════════════════════════════════════════════════════════════════════
    // REWARD RATE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_reward_rate_basic() {
        // 1M tokens over 1 week
        // Rate = 1_000_000 / 604_800_000 = 0 (truncated - too small)
        let rate = math::calculate_reward_rate(1_000_000, MS_PER_WEEK);
        assert!(rate == 0, 0);

        // 1B tokens over 1 week = 1_000_000_000 / 604_800_000 = 1
        let rate2 = math::calculate_reward_rate(1_000_000_000, MS_PER_WEEK);
        assert!(rate2 == 1, 1);

        // 100B tokens over 1 day = 100_000_000_000 / 86_400_000 = 1157
        let rate3 = math::calculate_reward_rate(100_000_000_000, MS_PER_DAY);
        assert!(rate3 == 1157, 2);
    }

    #[test]
    fun test_reward_rate_high_precision() {
        // Large rewards over short duration for better precision
        let total_rewards = 1_000_000_000_000u64; // 1T tokens
        let duration = MS_PER_DAY; // 1 day

        let rate = math::calculate_reward_rate(total_rewards, duration);
        // rate = 1T / 86.4M = ~11574 tokens/ms

        // Verify: rate * duration should approximate total_rewards
        let distributed = (rate as u128) * (duration as u128);
        let expected = (total_rewards as u128);

        // distributed = 11574 * 86_400_000 = 999_993_600_000
        // Loss is about 6.4M out of 1T = 0.00064%

        // Should be within 0.1% of expected
        let diff = if (distributed > expected) { distributed - expected } else { expected - distributed };
        let tolerance = expected / 1000; // 0.1%
        assert!(diff <= tolerance, 0);
    }

    #[test]
    fun test_reward_rate_zero_duration() {
        let rate = math::calculate_reward_rate(1_000_000, 0);
        assert!(rate == 0, 0);
    }

    #[test]
    fun test_reward_rate_small_rewards_long_duration() {
        // Edge case: small rewards over long duration = 0 rate
        // 1000 tokens over 1 year
        let rate = math::calculate_reward_rate(1000, MS_PER_YEAR);
        // 1000 / 31_536_000_000 = 0 (truncated)
        assert!(rate == 0, 0);

        // Need larger amounts for meaningful rate
        // 1M tokens over 1 year = 31 tokens/ms
        let rate2 = math::calculate_reward_rate(1_000_000_000_000, MS_PER_YEAR);
        assert!(rate2 > 0, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ACCUMULATED REWARD PER SHARE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_acc_reward_basic() {
        // 1000 rewards, 1000 staked
        // acc = 0 + (1000 * 1e18) / 1000 = 1e18
        let acc = math::calculate_acc_reward_per_share(0, 1000, 1000);
        assert!(acc == PRECISION, 0);
    }

    #[test]
    fun test_acc_reward_accumulates() {
        // First distribution: 1000 rewards, 1000 staked
        let acc1 = math::calculate_acc_reward_per_share(0, 1000, 1000);
        assert!(acc1 == PRECISION, 0);

        // Second distribution: 500 more rewards
        let acc2 = math::calculate_acc_reward_per_share(acc1, 500, 1000);
        // acc2 = 1e18 + (500 * 1e18) / 1000 = 1.5e18
        assert!(acc2 == PRECISION + PRECISION / 2, 1);
    }

    #[test]
    fun test_acc_reward_zero_staked() {
        // No stakers = no change in acc
        let acc = math::calculate_acc_reward_per_share(PRECISION, 1000, 0);
        assert!(acc == PRECISION, 0);
    }

    #[test]
    fun test_acc_reward_large_stake_small_reward() {
        // 1 reward distributed to 1B staked
        // acc = (1 * 1e18) / 1_000_000_000 = 1e9
        let acc = math::calculate_acc_reward_per_share(0, 1, 1_000_000_000);
        assert!(acc == 1_000_000_000, 0);
    }

    #[test]
    fun test_acc_reward_precision_maintained() {
        // Test that precision is maintained across many small updates
        let mut acc: u128 = 0;
        let rewards_per_update = 100u64;
        let total_staked = 10_000_000u64;

        // Simulate 1000 reward distributions
        let mut i = 0;
        while (i < 1000) {
            acc = math::calculate_acc_reward_per_share(acc, rewards_per_update, total_staked);
            i = i + 1;
        };

        // Total rewards = 100 * 1000 = 100,000
        // Expected acc = (100,000 * 1e18) / 10_000_000 = 1e16
        let expected_acc = (100_000u128 * PRECISION) / 10_000_000;
        assert!(acc == expected_acc, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PENDING REWARDS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_pending_rewards_basic() {
        // Staked 1000, acc = 1e18, debt = 0
        // pending = (1000 * 1e18 / 1e18) - 0 = 1000
        let pending = math::calculate_pending_rewards(1000, PRECISION, 0);
        assert!(pending == 1000, 0);
    }

    #[test]
    fun test_pending_rewards_with_debt() {
        // Scenario: User staked when acc = 1e18, now acc = 2e18
        //
        // When user stakes, their debt = staked * acc_at_stake_time
        // Pending = (staked * current_acc) / PRECISION - debt
        //
        // Staked: 1000 tokens at acc = 1e18
        // Debt = math::calculate_reward_debt(1000, 1e18) = 1000 * 1e18 / 1e18 = 1000
        // Wait, debt is stored differently...

        let staked = 1000u64;

        // User's reward debt is calculated as: staked * acc / PRECISION
        // This gives us the "rewards already accounted for"
        let initial_acc = PRECISION; // 1e18
        let debt = math::calculate_reward_debt(staked, initial_acc);
        // debt = 1000 * 1e18 / 1e18 = 1000

        // Now acc doubles to 2e18
        let current_acc = 2 * PRECISION; // 2e18

        // Pending = (staked * current_acc / PRECISION) - debt
        // = (1000 * 2e18 / 1e18) - 1000 = 2000 - 1000 = 1000
        let pending = math::calculate_pending_rewards(staked, current_acc, debt);
        assert!(pending == 1000, 0);
    }

    #[test]
    fun test_pending_rewards_zero_when_debt_exceeds() {
        // Edge case: debt > accumulated (shouldn't happen normally)
        let pending = math::calculate_pending_rewards(
            1000,
            PRECISION,
            2 * PRECISION * 1000, // debt higher than accumulated
        );
        assert!(pending == 0, 0);
    }

    #[test]
    fun test_pending_rewards_large_stake() {
        // 1B staked, acc = 0.001 per token
        let staked = 1_000_000_000u64;
        let acc = PRECISION / 1000; // 0.001 tokens per staked
        let pending = math::calculate_pending_rewards(staked, acc, 0);
        // pending = 1B * 0.001 = 1M
        assert!(pending == 1_000_000, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REWARD DEBT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_reward_debt_basic() {
        // debt = staked * acc / PRECISION
        let debt = math::calculate_reward_debt(1000, PRECISION);
        assert!(debt == 1000 * PRECISION / PRECISION, 0);
    }

    #[test]
    fun test_reward_debt_fractional_acc() {
        // acc = 0.5e18 (half a token per staked)
        let debt = math::calculate_reward_debt(1000, PRECISION / 2);
        // debt = 1000 * 0.5e18 / 1e18 = 500
        assert!(debt == 500, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REWARDS EARNED TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_rewards_earned_basic() {
        // 1 day elapsed, rate = 1000 tokens/ms
        let earned = math::calculate_rewards_earned(MS_PER_DAY, 1000);
        assert!(earned == MS_PER_DAY * 1000, 0);
    }

    #[test]
    fun test_rewards_earned_overflow_protection() {
        // Large time * large rate should not overflow with u128 intermediate
        let earned = math::calculate_rewards_earned(MS_PER_YEAR, 1_000_000);
        // This would overflow u64 multiplication but works with u128
        let expected = ((MS_PER_YEAR as u128) * 1_000_000u128) as u64;
        assert!(earned == expected, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FEE CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_fee_bps_basic() {
        // 5% of 1000 = 50
        let fee = math::calculate_fee_bps(1000, 500);
        assert!(fee == 50, 0);

        // 1% of 10000 = 100
        let fee2 = math::calculate_fee_bps(10000, 100);
        assert!(fee2 == 100, 1);

        // 10% of 1000000 = 100000
        let fee3 = math::calculate_fee_bps(1000000, 1000);
        assert!(fee3 == 100000, 2);
    }

    #[test]
    fun test_fee_bps_zero() {
        let fee = math::calculate_fee_bps(1000, 0);
        assert!(fee == 0, 0);
    }

    #[test]
    fun test_fee_bps_max() {
        // 100% = 10000 bps
        let fee = math::calculate_fee_bps(1000, 10000);
        assert!(fee == 1000, 0);
    }

    #[test]
    fun test_fee_bps_precision() {
        // Small amounts should work correctly
        // 5% of 100 = 5
        let fee = math::calculate_fee_bps(100, 500);
        assert!(fee == 5, 0);

        // 5% of 10 = 0 (truncated)
        let fee2 = math::calculate_fee_bps(10, 500);
        assert!(fee2 == 0, 1);

        // 5% of 20 = 1
        let fee3 = math::calculate_fee_bps(20, 500);
        assert!(fee3 == 1, 2);
    }

    #[test]
    fun test_amount_after_fee() {
        // 1000 with 5% fee = 950
        let net = math::calculate_amount_after_fee(1000, 500);
        assert!(net == 950, 0);

        // 10000 with 1% fee = 9900
        let net2 = math::calculate_amount_after_fee(10000, 100);
        assert!(net2 == 9900, 1);
    }

    #[test]
    fun test_early_unstake_fee() {
        // Before min duration: full fee
        let fee = math::calculate_early_unstake_fee(
            1000,
            0,           // staked at t=0
            MS_PER_DAY,  // current t=1 day
            MS_PER_WEEK, // min = 7 days
            500,         // 5% fee
        );
        assert!(fee == 50, 0); // 5% of 1000

        // After min duration: no fee
        let fee2 = math::calculate_early_unstake_fee(
            1000,
            0,
            MS_PER_WEEK, // current = 7 days
            MS_PER_WEEK, // min = 7 days
            500,
        );
        assert!(fee2 == 0, 1);

        // Well past min duration: no fee
        let fee3 = math::calculate_early_unstake_fee(
            1000,
            0,
            MS_PER_YEAR,
            MS_PER_WEEK,
            500,
        );
        assert!(fee3 == 0, 2);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_valid_duration() {
        // Min: 7 days
        assert!(math::is_valid_duration(MS_PER_WEEK), 0);

        // Max: 2 years
        assert!(math::is_valid_duration(MS_PER_YEAR * 2), 1);

        // Too short: 1 day
        assert!(!math::is_valid_duration(MS_PER_DAY), 2);

        // Too long: 3 years
        assert!(!math::is_valid_duration(MS_PER_YEAR * 3), 3);
    }

    #[test]
    fun test_valid_early_fee() {
        assert!(math::is_valid_early_fee(0), 0);
        assert!(math::is_valid_early_fee(500), 1);  // 5%
        assert!(math::is_valid_early_fee(1000), 2); // 10% max
        assert!(!math::is_valid_early_fee(1001), 3); // >10% invalid
    }

    #[test]
    fun test_valid_platform_fee() {
        assert!(math::is_valid_platform_fee(0), 0);
        assert!(math::is_valid_platform_fee(100), 1);  // 1%
        assert!(math::is_valid_platform_fee(500), 2);  // 5% max
        assert!(!math::is_valid_platform_fee(501), 3); // >5% invalid
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TOKENOMIC SCENARIO TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_scenario_single_staker_full_duration() {
        // Scenario: 1 staker stakes entire duration, gets all rewards
        // Use large rewards to minimize precision loss

        let total_rewards = 100_000_000_000_000u64; // 100T tokens (large for precision)
        let duration = MS_PER_WEEK;

        // Calculate rate
        let rate = math::calculate_reward_rate(total_rewards, duration);

        // Calculate earned over full duration
        let earned = math::calculate_rewards_earned(duration, rate);

        // Should get approximately all rewards (minus truncation loss)
        let diff = if (total_rewards > earned) {
            total_rewards - earned
        } else {
            earned - total_rewards
        };

        // Allow 1% tolerance for truncation
        let tolerance = total_rewards / 100;
        assert!(diff <= tolerance, 0);
    }

    #[test]
    fun test_scenario_two_equal_stakers() {
        // Scenario: 2 stakers with equal stake split rewards 50/50

        let total_rewards = 1_000_000_000u64;
        let stake_per_user = 50_000_000u64;
        let total_staked = stake_per_user * 2;

        // After full distribution, acc_reward_per_share
        let acc = math::calculate_acc_reward_per_share(0, total_rewards, total_staked);

        // Each user's pending rewards
        let pending = math::calculate_pending_rewards(stake_per_user, acc, 0);

        // Each should get ~50% of rewards
        let expected = total_rewards / 2;
        let diff = if (pending > expected) { pending - expected } else { expected - pending };

        // Allow small rounding difference
        assert!(diff <= 1, 0);
    }

    #[test]
    fun test_scenario_unequal_stakers() {
        // Scenario: Alice 75%, Bob 25% of stake

        let total_rewards = 1_000_000u64;
        let alice_stake = 75_000u64;
        let bob_stake = 25_000u64;
        let total_staked = alice_stake + bob_stake;

        let acc = math::calculate_acc_reward_per_share(0, total_rewards, total_staked);

        let alice_pending = math::calculate_pending_rewards(alice_stake, acc, 0);
        let bob_pending = math::calculate_pending_rewards(bob_stake, acc, 0);

        // Alice should get 75% = 750,000
        assert!(alice_pending == 750_000, 0);
        // Bob should get 25% = 250,000
        assert!(bob_pending == 250_000, 1);
        // Total = 100% of rewards
        assert!(alice_pending + bob_pending == total_rewards, 2);
    }

    #[test]
    fun test_scenario_late_joiner() {
        // Scenario: Alice stakes at start, Bob joins halfway

        let rewards_per_period = 500_000u64;
        let alice_stake = 100_000u64;
        let bob_stake = 100_000u64;

        // Period 1: Only Alice staked
        let acc1 = math::calculate_acc_reward_per_share(0, rewards_per_period, alice_stake);
        // acc1 = 500_000 * 1e18 / 100_000 = 5e18

        // Alice's debt when Bob joins = 0 (staked from start)
        let alice_debt = 0u128;

        // Bob joins with debt at current acc
        let bob_debt = math::calculate_reward_debt(bob_stake, acc1);

        // Period 2: Both staked
        let total_staked = alice_stake + bob_stake;
        let acc2 = math::calculate_acc_reward_per_share(acc1, rewards_per_period, total_staked);
        // acc2 = 5e18 + (500_000 * 1e18 / 200_000) = 5e18 + 2.5e18 = 7.5e18

        // Calculate pending rewards
        let alice_pending = math::calculate_pending_rewards(alice_stake, acc2, alice_debt);
        let bob_pending = math::calculate_pending_rewards(bob_stake, acc2, bob_debt);

        // Alice: all of period 1 (500k) + half of period 2 (250k) = 750k
        assert!(alice_pending == 750_000, 0);

        // Bob: half of period 2 = 250k
        assert!(bob_pending == 250_000, 1);

        // Total distributed = 1M (all rewards)
        assert!(alice_pending + bob_pending == rewards_per_period * 2, 2);
    }

    #[test]
    fun test_scenario_partial_unstake() {
        // Scenario: Alice stakes 1000, earns rewards, unstakes 500

        let initial_stake = 1000u64;
        let total_staked = 1000u64;

        // Accumulate some rewards
        let rewards = 500u64;
        let acc = math::calculate_acc_reward_per_share(0, rewards, total_staked);

        // Alice's pending before unstake
        let pending = math::calculate_pending_rewards(initial_stake, acc, 0);
        assert!(pending == 500, 0); // All rewards

        // Alice claims and unstakes 500
        let remaining_stake = 500u64;
        let new_debt = math::calculate_reward_debt(remaining_stake, acc);

        // More rewards accumulate (only 500 staked now)
        let more_rewards = 500u64;
        let new_total_staked = 500u64;
        let acc2 = math::calculate_acc_reward_per_share(acc, more_rewards, new_total_staked);

        // Alice's new pending
        let new_pending = math::calculate_pending_rewards(remaining_stake, acc2, new_debt);
        assert!(new_pending == 500, 1); // Gets all rewards with remaining stake
    }

    #[test]
    fun test_scenario_add_stake() {
        // Scenario: Alice stakes 500, earns, adds 500 more

        let initial_stake = 500u64;

        // First reward period
        let rewards1 = 1000u64;
        let acc1 = math::calculate_acc_reward_per_share(0, rewards1, initial_stake);
        // acc1 = 1000 * 1e18 / 500 = 2e18

        // Alice's pending = 1000
        let pending1 = math::calculate_pending_rewards(initial_stake, acc1, 0);
        assert!(pending1 == 1000, 0);

        // Alice claims and adds 500 more stake
        // New debt = 1000 * 2e18 / 1e18 = 2000
        let new_stake = 1000u64;
        let new_debt = math::calculate_reward_debt(new_stake, acc1);

        // Second reward period (with 1000 staked)
        let rewards2 = 1000u64;
        let acc2 = math::calculate_acc_reward_per_share(acc1, rewards2, new_stake);
        // acc2 = 2e18 + (1000 * 1e18 / 1000) = 3e18

        // Alice's new pending
        let pending2 = math::calculate_pending_rewards(new_stake, acc2, new_debt);
        assert!(pending2 == 1000, 1); // Full second period rewards
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PRECISION EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_very_small_stake_large_rewards() {
        // 1 token staked, 1B rewards distributed
        let acc = math::calculate_acc_reward_per_share(0, 1_000_000_000, 1);
        // acc = 1B * 1e18 = 1e27

        let pending = math::calculate_pending_rewards(1, acc, 0);
        assert!(pending == 1_000_000_000, 0);
    }

    #[test]
    fun test_very_large_stake_small_rewards() {
        // 1B staked, 1 token reward
        let acc = math::calculate_acc_reward_per_share(0, 1, 1_000_000_000);
        // acc = 1 * 1e18 / 1e9 = 1e9

        let pending = math::calculate_pending_rewards(1_000_000_000, acc, 0);
        assert!(pending == 1, 0);
    }

    #[test]
    fun test_whale_vs_minnow() {
        // Whale: 99% of stake, Minnow: 1%
        let whale_stake = 99_000_000u64;
        let minnow_stake = 1_000_000u64;
        let total_staked = whale_stake + minnow_stake;
        let total_rewards = 10_000_000u64;

        let acc = math::calculate_acc_reward_per_share(0, total_rewards, total_staked);

        let whale_pending = math::calculate_pending_rewards(whale_stake, acc, 0);
        let minnow_pending = math::calculate_pending_rewards(minnow_stake, acc, 0);

        // Whale should get 99% = 9,900,000
        assert!(whale_pending == 9_900_000, 0);
        // Minnow should get 1% = 100,000
        assert!(minnow_pending == 100_000, 1);
        // Total = 100%
        assert!(whale_pending + minnow_pending == total_rewards, 2);
    }

    #[test]
    fun test_many_small_distributions() {
        // Simulate per-block reward distribution (fewer iterations)
        let total_rewards = 1_000_000u64;
        let num_distributions = 1000u64; // 1000 blocks instead of 86400 seconds
        let rewards_per_distribution = total_rewards / num_distributions;
        let staked = 1_000_000u64;

        let mut acc: u128 = 0;
        let mut total_distributed = 0u64;
        let mut i = 0u64;

        while (i < num_distributions) {
            acc = math::calculate_acc_reward_per_share(acc, rewards_per_distribution, staked);
            total_distributed = total_distributed + rewards_per_distribution;
            i = i + 1;
        };

        let pending = math::calculate_pending_rewards(staked, acc, 0);

        // Should equal total distributed
        assert!(pending == total_distributed, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // APY/APR CALCULATION VERIFICATION
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_apr_calculation_10_percent() {
        // 10% APR scenario
        // Need large numbers for precision
        // Stake: 1T tokens
        // Rewards: 100B tokens over 1 year (10% APR)

        let yearly_rewards = 100_000_000_000_000u64; // 100T (large for precision)
        let duration = MS_PER_YEAR;

        let rate = math::calculate_reward_rate(yearly_rewards, duration);
        let earned = math::calculate_rewards_earned(duration, rate);

        // Should earn approximately yearly_rewards
        let expected = yearly_rewards;
        let diff = if (earned > expected) { earned - expected } else { expected - earned };

        // Within 1% tolerance due to integer division
        let tolerance = expected / 100;
        assert!(diff <= tolerance, 0);
    }

    #[test]
    fun test_apr_calculation_100_percent() {
        // 100% APR scenario (aggressive)
        let staked = 1_000_000u64;
        let yearly_rewards = 1_000_000u64; // 100% of stake

        let acc = math::calculate_acc_reward_per_share(0, yearly_rewards, staked);
        let pending = math::calculate_pending_rewards(staked, acc, 0);

        // Should get exactly 100% of stake as rewards
        assert!(pending == staked, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTER FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_constant_getters() {
        assert!(math::precision() == PRECISION, 0);
        assert!(math::bps_denominator() == 10_000, 1);
        assert!(math::ms_per_second() == 1_000, 2);
        assert!(math::ms_per_day() == 86_400_000, 3);
        assert!(math::min_duration_ms() == 604_800_000, 4); // 7 days
        assert!(math::max_duration_ms() == 63_072_000_000, 5); // 2 years
        assert!(math::max_early_fee_bps() == 1_000, 6); // 10%
        assert!(math::max_platform_fee_bps() == 500, 7); // 5%
    }
}
