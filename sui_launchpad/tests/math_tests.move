/// Comprehensive tests for the math module
#[test_only]
module sui_launchpad::math_tests {
    use sui_launchpad::math;

    // ═══════════════════════════════════════════════════════════════════════
    // MUL_DIV TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_mul_div_basic() {
        // Basic multiplication and division
        assert!(math::mul_div(100, 50, 100) == 50, 0);
        assert!(math::mul_div(1000, 500, 10000) == 50, 1);
        assert!(math::mul_div(100, 100, 100) == 100, 2);
    }

    #[test]
    fun test_mul_div_large_numbers() {
        // Test with large numbers that would overflow u64 in intermediate step
        let large = 1_000_000_000_000; // 1 trillion
        let result = math::mul_div(large, large, large);
        assert!(result == large, 0);

        // Test another large calculation
        let a = 10_000_000_000_000_000; // 10 quadrillion
        let b = 1000;
        let c = 10000;
        let result2 = math::mul_div(a, b, c);
        assert!(result2 == 1_000_000_000_000_000, 1);
    }

    #[test]
    fun test_mul_div_zero_numerator() {
        // Zero in numerator should return zero
        assert!(math::mul_div(0, 100, 50) == 0, 0);
        assert!(math::mul_div(100, 0, 50) == 0, 1);
    }

    #[test]
    #[expected_failure(abort_code = 2)] // EDivisionByZero
    fun test_mul_div_zero_denominator() {
        math::mul_div(100, 50, 0);
    }

    #[test]
    fun test_mul_div_up_basic() {
        // Should round up
        assert!(math::mul_div_up(100, 50, 100) == 50, 0);
        assert!(math::mul_div_up(101, 1, 100) == 2, 1); // 1.01 rounds up to 2
        assert!(math::mul_div_up(99, 1, 100) == 1, 2);  // 0.99 rounds up to 1
    }

    #[test]
    fun test_mul_div_up_exact() {
        // Exact divisions should not add extra
        assert!(math::mul_div_up(100, 100, 100) == 100, 0);
        assert!(math::mul_div_up(1000, 10, 100) == 100, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BASIS POINTS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_bps_percentages() {
        // 1% = 100 bps
        assert!(math::bps(10000, 100) == 100, 0);

        // 5% = 500 bps
        assert!(math::bps(10000, 500) == 500, 1);

        // 10% = 1000 bps
        assert!(math::bps(10000, 1000) == 1000, 2);

        // 50% = 5000 bps
        assert!(math::bps(10000, 5000) == 5000, 3);

        // 100% = 10000 bps
        assert!(math::bps(10000, 10000) == 10000, 4);
    }

    #[test]
    fun test_bps_fractional() {
        // 0.5% = 50 bps
        assert!(math::bps(10000, 50) == 50, 0);

        // 0.1% = 10 bps
        assert!(math::bps(10000, 10) == 10, 1);

        // 2.5% = 250 bps
        assert!(math::bps(10000, 250) == 250, 2);
    }

    #[test]
    fun test_bps_zero() {
        // 0% should return 0
        assert!(math::bps(10000, 0) == 0, 0);
        assert!(math::bps(0, 500) == 0, 1);
    }

    #[test]
    fun test_after_fee() {
        // 5% fee on 1000 = 50, so after fee = 950
        assert!(math::after_fee(1000, 500) == 950, 0);

        // 1% fee on 10000 = 100, so after fee = 9900
        assert!(math::after_fee(10000, 100) == 9900, 1);

        // 0% fee
        assert!(math::after_fee(1000, 0) == 1000, 2);
    }

    #[test]
    fun test_bps_denominator() {
        assert!(math::bps_denominator() == 10000, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MIN/MAX TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_min() {
        assert!(math::min(5, 10) == 5, 0);
        assert!(math::min(10, 5) == 5, 1);
        assert!(math::min(5, 5) == 5, 2);
        assert!(math::min(0, 100) == 0, 3);
    }

    #[test]
    fun test_max() {
        assert!(math::max(5, 10) == 10, 0);
        assert!(math::max(10, 5) == 10, 1);
        assert!(math::max(5, 5) == 5, 2);
        assert!(math::max(0, 100) == 100, 3);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SQRT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_sqrt_perfect_squares() {
        assert!(math::sqrt(0) == 0, 0);
        assert!(math::sqrt(1) == 1, 1);
        assert!(math::sqrt(4) == 2, 2);
        assert!(math::sqrt(9) == 3, 3);
        assert!(math::sqrt(16) == 4, 4);
        assert!(math::sqrt(25) == 5, 5);
        assert!(math::sqrt(100) == 10, 6);
        assert!(math::sqrt(10000) == 100, 7);
        assert!(math::sqrt(1000000) == 1000, 8);
    }

    #[test]
    fun test_sqrt_non_perfect_squares() {
        // sqrt(2) ~= 1.41, floor = 1
        assert!(math::sqrt(2) == 1, 0);

        // sqrt(3) ~= 1.73, floor = 1
        assert!(math::sqrt(3) == 1, 1);

        // sqrt(5) ~= 2.24, floor = 2
        assert!(math::sqrt(5) == 2, 2);

        // sqrt(10) ~= 3.16, floor = 3
        assert!(math::sqrt(10) == 3, 3);

        // sqrt(50) ~= 7.07, floor = 7
        assert!(math::sqrt(50) == 7, 4);
    }

    #[test]
    fun test_sqrt_u64() {
        assert!(math::sqrt_u64(0) == 0, 0);
        assert!(math::sqrt_u64(100) == 10, 1);
        assert!(math::sqrt_u64(10000) == 100, 2);
    }

    #[test]
    fun test_sqrt_large_numbers() {
        // sqrt(1e18) = 1e9
        let large = 1_000_000_000_000_000_000u256;
        assert!(math::sqrt(large) == 1_000_000_000, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BONDING CURVE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_get_price_zero_supply() {
        // At zero supply, price = base_price
        let base_price = 1000;
        let slope = 1_000_000;
        let supply = 0;

        let price = math::get_price(base_price, slope, supply);
        assert!(price == base_price, 0);
    }

    #[test]
    fun test_get_price_with_supply() {
        // price = base_price + slope * supply / PRECISION
        let base_price = 1000;
        let slope = 1_000_000_000; // 1 per unit
        let supply = 100;

        let price = math::get_price(base_price, slope, supply);
        // 1000 + (1e9 * 100) / 1e9 = 1000 + 100 = 1100
        assert!(price == 1100, 0);
    }

    #[test]
    fun test_get_price_linear_increase() {
        let base_price = 1000;
        let slope = 1_000_000_000;

        // Price should increase linearly with supply
        let price_0 = math::get_price(base_price, slope, 0);
        let price_100 = math::get_price(base_price, slope, 100);
        let price_200 = math::get_price(base_price, slope, 200);

        assert!(price_0 == 1000, 0);
        assert!(price_100 == 1100, 1);
        assert!(price_200 == 1200, 2);

        // Verify linearity: price_200 - price_100 == price_100 - price_0
        assert!(price_200 - price_100 == price_100 - price_0, 3);
    }

    #[test]
    fun test_curve_area_zero_slope() {
        // With zero slope, area = base_price * supply
        let base_price = 1000;
        let slope = 0;
        let supply = 100;

        let area = math::curve_area(base_price, slope, supply);
        assert!(area == 100000, 0);
    }

    #[test]
    fun test_curve_area_zero_supply() {
        // With zero supply, area should be 0
        let area = math::curve_area(1000, 1_000_000, 0);
        assert!(area == 0, 0);
    }

    #[test]
    fun test_curve_area_with_slope() {
        // Area = base_price * supply + (slope * supply^2) / (2 * PRECISION)
        let base_price = 1000;
        let slope = 1_000_000_000;
        let supply = 100;

        let area = math::curve_area(base_price, slope, supply);
        // base_area = 1000 * 100 = 100000
        // slope_area = (1e9 * 100 * 100) / (2 * 1e9) = 10000 / 2 = 5000
        // total = 100000 + 5000 = 105000
        assert!(area == 105000, 0);
    }

    #[test]
    fun test_tokens_out_basic() {
        let base_price = 1000;
        let slope = 0; // Constant price
        let current_supply = 0;
        let sui_in = 10000;

        let tokens = math::tokens_out(sui_in, current_supply, base_price, slope);
        // With constant price of 1000, 10000 SUI gets 10 tokens
        assert!(tokens == 10, 0);
    }

    #[test]
    fun test_sui_out_basic() {
        let base_price = 1000;
        let slope = 0; // Constant price
        let current_supply = 100; // 100 tokens in circulation
        let tokens_in = 10;

        let sui = math::sui_out(tokens_in, current_supply, base_price, slope);
        // With constant price of 1000, 10 tokens gets 10000 SUI
        assert!(sui == 10000, 0);
    }

    #[test]
    fun test_buy_sell_symmetry() {
        // Buy then sell same amount should give back approximately same SUI
        // (exact symmetry depends on curve parameters)
        let base_price = 1000;
        let slope = 0;
        let initial_supply = 0;

        // Buy tokens
        let sui_in = 10000;
        let tokens_bought = math::tokens_out(sui_in, initial_supply, base_price, slope);

        // Sell tokens
        let new_supply = initial_supply + tokens_bought;
        let sui_back = math::sui_out(tokens_bought, new_supply, base_price, slope);

        // Should get back same amount (with zero slope/constant price)
        assert!(sui_back == sui_in, 0);
    }

    #[test]
    fun test_precision() {
        assert!(math::precision() == 1_000_000_000, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDGE CASES
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_edge_case_small_amounts() {
        // Very small amounts should still work
        assert!(math::bps(1, 5000) == 0, 0); // 50% of 1 = 0 (floor)
        assert!(math::bps(2, 5000) == 1, 1); // 50% of 2 = 1

        assert!(math::mul_div(1, 1, 2) == 0, 2); // 0.5 floors to 0
        assert!(math::mul_div(3, 1, 2) == 1, 3); // 1.5 floors to 1
    }

    #[test]
    fun test_edge_case_max_bps() {
        // 100% = 10000 bps
        assert!(math::bps(1000, 10000) == 1000, 0);

        // More than 100% should work (for other use cases)
        assert!(math::bps(1000, 20000) == 2000, 1);
    }
}
