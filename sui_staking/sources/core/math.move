/// Math utilities for staking reward calculations
/// Uses MasterChef-style accumulated reward per share model
module sui_staking::math {

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Precision for fixed-point math (1e18)
    const PRECISION: u128 = 1_000_000_000_000_000_000;

    /// Basis points denominator (10000 = 100%)
    const BPS_DENOMINATOR: u64 = 10_000;

    /// Milliseconds per second
    const MS_PER_SECOND: u64 = 1_000;

    /// Milliseconds per day
    const MS_PER_DAY: u64 = 86_400_000;

    /// Minimum pool duration (7 days in ms)
    const MIN_DURATION_MS: u64 = 604_800_000;

    /// Maximum pool duration (2 years in ms)
    const MAX_DURATION_MS: u64 = 63_072_000_000;

    /// Maximum early unstake fee (10% = 1000 bps)
    const MAX_EARLY_FEE_BPS: u64 = 1_000;

    /// Maximum platform fee (5% = 500 bps)
    const MAX_PLATFORM_FEE_BPS: u64 = 500;

    /// Maximum stake fee (5% = 500 bps)
    const MAX_STAKE_FEE_BPS: u64 = 500;

    /// Maximum unstake fee (5% = 500 bps)
    const MAX_UNSTAKE_FEE_BPS: u64 = 500;

    // ═══════════════════════════════════════════════════════════════════════
    // REWARD CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Calculate reward rate (tokens per millisecond)
    /// reward_rate = total_rewards / duration_ms
    public fun calculate_reward_rate(total_rewards: u64, duration_ms: u64): u64 {
        if (duration_ms == 0) {
            return 0
        };
        total_rewards / duration_ms
    }

    /// Calculate new accumulated reward per share
    /// acc_reward_per_share += (rewards * PRECISION) / total_staked
    /// With overflow protection
    public fun calculate_acc_reward_per_share(
        current_acc: u128,
        new_rewards: u64,
        total_staked: u64,
    ): u128 {
        if (total_staked == 0) {
            return current_acc
        };

        let rewards_128 = (new_rewards as u128);
        let total_staked_128 = (total_staked as u128);
        let increment = (rewards_128 * PRECISION) / total_staked_128;

        // Check for overflow before addition
        let max_u128: u128 = 340_282_366_920_938_463_463_374_607_431_768_211_455;
        if (current_acc > max_u128 - increment) {
            // Cap at max instead of overflowing
            max_u128
        } else {
            current_acc + increment
        }
    }

    /// Calculate rewards earned since last update
    /// rewards = time_elapsed_ms * reward_rate
    /// With overflow protection - caps at MAX_U64 instead of wrapping
    public fun calculate_rewards_earned(
        time_elapsed_ms: u64,
        reward_rate: u64,
    ): u64 {
        // Use u128 to prevent overflow in multiplication
        let time_128 = (time_elapsed_ms as u128);
        let rate_128 = (reward_rate as u128);
        let result = time_128 * rate_128;

        // Check if result overflows u64, cap at MAX_U64 if so
        let max_u64: u128 = 18_446_744_073_709_551_615;
        if (result > max_u64) {
            (max_u64 as u64)
        } else {
            (result as u64)
        }
    }

    /// Calculate pending rewards for a position
    /// pending = (staked_amount * acc_reward_per_share / PRECISION) - reward_debt
    public fun calculate_pending_rewards(
        staked_amount: u64,
        acc_reward_per_share: u128,
        reward_debt: u128,
    ): u64 {
        let staked_128 = (staked_amount as u128);
        let accumulated = (staked_128 * acc_reward_per_share) / PRECISION;

        if (accumulated > reward_debt) {
            ((accumulated - reward_debt) as u64)
        } else {
            0
        }
    }

    /// Calculate reward debt for a new position
    /// reward_debt = staked_amount * acc_reward_per_share / PRECISION
    public fun calculate_reward_debt(
        staked_amount: u64,
        acc_reward_per_share: u128,
    ): u128 {
        let staked_128 = (staked_amount as u128);
        (staked_128 * acc_reward_per_share) / PRECISION
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FEE CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Calculate fee amount from basis points
    /// fee = amount * bps / 10000
    public fun calculate_fee_bps(amount: u64, bps: u64): u64 {
        let amount_128 = (amount as u128);
        let bps_128 = (bps as u128);
        let denominator_128 = (BPS_DENOMINATOR as u128);

        ((amount_128 * bps_128) / denominator_128) as u64
    }

    /// Calculate amount after fee
    /// net = amount - fee
    public fun calculate_amount_after_fee(amount: u64, fee_bps: u64): u64 {
        let fee = calculate_fee_bps(amount, fee_bps);
        amount - fee
    }

    /// Calculate early unstake fee based on time staked
    /// Returns 0 if min_stake_duration has passed
    public fun calculate_early_unstake_fee(
        staked_amount: u64,
        stake_time_ms: u64,
        current_time_ms: u64,
        min_stake_duration_ms: u64,
        early_fee_bps: u64,
    ): u64 {
        if (current_time_ms >= stake_time_ms + min_stake_duration_ms) {
            return 0
        };
        calculate_fee_bps(staked_amount, early_fee_bps)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Check if duration is within valid range
    public fun is_valid_duration(duration_ms: u64): bool {
        duration_ms >= MIN_DURATION_MS && duration_ms <= MAX_DURATION_MS
    }

    /// Check if early fee is within valid range
    public fun is_valid_early_fee(fee_bps: u64): bool {
        fee_bps <= MAX_EARLY_FEE_BPS
    }

    /// Check if platform fee is within valid range
    public fun is_valid_platform_fee(fee_bps: u64): bool {
        fee_bps <= MAX_PLATFORM_FEE_BPS
    }

    /// Check if stake fee is within valid range (0-5%)
    public fun is_valid_stake_fee(fee_bps: u64): bool {
        fee_bps <= MAX_STAKE_FEE_BPS
    }

    /// Check if unstake fee is within valid range (0-5%)
    public fun is_valid_unstake_fee(fee_bps: u64): bool {
        fee_bps <= MAX_UNSTAKE_FEE_BPS
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANT GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun precision(): u128 { PRECISION }
    public fun bps_denominator(): u64 { BPS_DENOMINATOR }
    public fun ms_per_second(): u64 { MS_PER_SECOND }
    public fun ms_per_day(): u64 { MS_PER_DAY }
    public fun min_duration_ms(): u64 { MIN_DURATION_MS }
    public fun max_duration_ms(): u64 { MAX_DURATION_MS }
    public fun max_early_fee_bps(): u64 { MAX_EARLY_FEE_BPS }
    public fun max_platform_fee_bps(): u64 { MAX_PLATFORM_FEE_BPS }
    public fun max_stake_fee_bps(): u64 { MAX_STAKE_FEE_BPS }
    public fun max_unstake_fee_bps(): u64 { MAX_UNSTAKE_FEE_BPS }

    // ═══════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Calculate basis points (shorthand for calculate_fee_bps)
    public fun bps(amount: u64, bps: u64): u64 {
        calculate_fee_bps(amount, bps)
    }

    /// Return the minimum of two u64 values
    public fun min_u64(a: u64, b: u64): u64 {
        if (a < b) { a } else { b }
    }

    /// Return the maximum of two u64 values
    public fun max_u64(a: u64, b: u64): u64 {
        if (a > b) { a } else { b }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_calculate_reward_rate() {
        // 100 billion tokens (100e9) over 1 day = ~1.157 tokens per ms
        let rate = calculate_reward_rate(100_000_000_000, MS_PER_DAY);
        assert!(rate > 0, 0);
        // Expected: 100_000_000_000 / 86_400_000 = 1157
        assert!(rate == 1157, 1);

        // Edge case: zero duration returns 0
        let rate_zero = calculate_reward_rate(1000, 0);
        assert!(rate_zero == 0, 2);
    }

    #[test]
    fun test_calculate_pending_rewards() {
        // Alice stakes 1000, acc_reward_per_share = 1e18, no previous debt
        let pending = calculate_pending_rewards(
            1000,
            PRECISION, // 1e18
            0,
        );
        assert!(pending == 1000, 0);
    }

    #[test]
    fun test_calculate_fee_bps() {
        // 2% of 1000 = 20
        let fee = calculate_fee_bps(1000, 200);
        assert!(fee == 20, 0);

        // 5% of 10000 = 500
        let fee2 = calculate_fee_bps(10000, 500);
        assert!(fee2 == 500, 1);
    }

    #[test]
    fun test_early_unstake_fee() {
        // Staked 1 day ago, min duration is 7 days, should pay fee
        let fee = calculate_early_unstake_fee(
            1000,
            0, // stake time
            MS_PER_DAY, // current time (1 day later)
            MS_PER_DAY * 7, // min 7 days
            500, // 5% fee
        );
        assert!(fee == 50, 0); // 5% of 1000

        // Staked 7 days ago, no fee
        let fee2 = calculate_early_unstake_fee(
            1000,
            0,
            MS_PER_DAY * 7, // 7 days later
            MS_PER_DAY * 7, // min 7 days
            500,
        );
        assert!(fee2 == 0, 1);
    }

    #[test]
    fun test_valid_duration() {
        assert!(is_valid_duration(MS_PER_DAY * 7), 0); // 7 days - valid
        assert!(is_valid_duration(MS_PER_DAY * 365), 1); // 1 year - valid
        assert!(!is_valid_duration(MS_PER_DAY), 2); // 1 day - too short
        assert!(!is_valid_duration(MS_PER_DAY * 365 * 3), 3); // 3 years - too long
    }
}
