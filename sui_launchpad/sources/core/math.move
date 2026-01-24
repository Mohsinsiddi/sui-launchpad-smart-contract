/// Math utilities for bonding curve calculations
/// Note: Sui Move has native overflow protection, so basic arithmetic is safe
module sui_launchpad::math {

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Precision for fixed-point calculations (1e9)
    const PRECISION: u256 = 1_000_000_000;

    /// Basis points denominator (10000 = 100%)
    const BPS_DENOMINATOR: u64 = 10_000;

    /// Max u64 for conversion checks
    const MAX_U64: u256 = 18_446_744_073_709_551_615;

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    const EOverflow: u64 = 1;
    const EDivisionByZero: u64 = 2;
    const EFeeTooHigh: u64 = 3;
    const EInvalidInput: u64 = 4;

    /// Maximum safe supply to prevent overflow in curve calculations
    /// sqrt(MAX_U256 / slope_max) roughly
    const MAX_SAFE_SUPPLY: u64 = 1_000_000_000_000_000_000; // 1e18

    // ═══════════════════════════════════════════════════════════════════════
    // CORE MATH (using u256 for intermediate calculations)
    // ═══════════════════════════════════════════════════════════════════════

    /// Multiply then divide - uses u256 to prevent intermediate overflow
    /// Returns (a * b) / c
    public fun mul_div(a: u64, b: u64, c: u64): u64 {
        assert!(c > 0, EDivisionByZero);
        let result = ((a as u256) * (b as u256)) / (c as u256);
        assert!(result <= MAX_U64, EOverflow);
        (result as u64)
    }

    /// Multiply then divide with rounding up
    /// Returns ceil((a * b) / c)
    public fun mul_div_up(a: u64, b: u64, c: u64): u64 {
        assert!(c > 0, EDivisionByZero);
        let numerator = (a as u256) * (b as u256);
        let result = (numerator + (c as u256) - 1) / (c as u256);
        assert!(result <= MAX_U64, EOverflow);
        (result as u64)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BASIS POINTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Calculate percentage using basis points
    /// bps_amount(1000, 500) = 50 (5% of 1000)
    public fun bps(amount: u64, bps: u64): u64 {
        mul_div(amount, bps, BPS_DENOMINATOR)
    }

    /// Calculate amount after deducting fee
    /// after_fee(1000, 500) = 950 (1000 - 5%)
    /// Validates fee_bps < 10000 to prevent underflow
    public fun after_fee(amount: u64, fee_bps: u64): u64 {
        assert!(fee_bps < BPS_DENOMINATOR, EFeeTooHigh);
        amount - bps(amount, fee_bps)
    }

    /// BPS denominator getter
    public fun bps_denominator(): u64 { BPS_DENOMINATOR }

    // ═══════════════════════════════════════════════════════════════════════
    // UTILITIES
    // ═══════════════════════════════════════════════════════════════════════

    /// Minimum of two values
    public fun min(a: u64, b: u64): u64 {
        if (a < b) a else b
    }

    /// Maximum of two values
    public fun max(a: u64, b: u64): u64 {
        if (a > b) a else b
    }

    /// Integer square root (Newton's method)
    public fun sqrt(x: u256): u256 {
        if (x == 0) return 0;
        if (x == 1) return 1;

        let mut z = x;
        let mut y = (x + 1) / 2;

        while (y < z) {
            z = y;
            y = (x / y + y) / 2;
        };

        z
    }

    /// Square root for u64
    public fun sqrt_u64(x: u64): u64 {
        (sqrt((x as u256)) as u64)
    }

    /// Precision getter
    public fun precision(): u256 { PRECISION }

    // ═══════════════════════════════════════════════════════════════════════
    // BONDING CURVE - LINEAR: price = base_price + slope * supply
    // ═══════════════════════════════════════════════════════════════════════

    /// Get current price on linear curve
    public fun get_price(base_price: u64, slope: u64, supply: u64): u64 {
        let slope_component = ((slope as u256) * (supply as u256)) / PRECISION;
        assert!(slope_component <= MAX_U64, EOverflow);
        base_price + (slope_component as u64)
    }

    /// Area under curve from 0 to supply
    /// Area = base_price * supply + (slope * supply^2) / (2 * PRECISION)
    /// Validates inputs to prevent overflow in intermediate calculations
    public fun curve_area(base_price: u64, slope: u64, supply: u64): u64 {
        // Validate supply is within safe bounds to prevent overflow
        assert!(supply <= MAX_SAFE_SUPPLY, EOverflow);

        let s = (supply as u256);
        let base_area = (base_price as u256) * s;

        // Calculate slope_area with overflow check
        // slope * s * s can overflow u256 if values are extreme
        let slope_256 = (slope as u256);
        let s_squared = s * s; // Safe because s <= MAX_SAFE_SUPPLY
        let slope_area = (slope_256 * s_squared) / (2 * PRECISION);

        let total = base_area + slope_area;
        assert!(total <= MAX_U64, EOverflow);
        (total as u64)
    }

    /// Calculate tokens received for SUI input
    public fun tokens_out(
        sui_in: u64,
        current_supply: u64,
        base_price: u64,
        slope: u64
    ): u64 {
        let current_area = curve_area(base_price, slope, current_supply);
        let new_area = current_area + sui_in;
        let new_supply = supply_from_area(base_price, slope, new_area);
        new_supply - current_supply
    }

    /// Calculate SUI received for tokens input
    public fun sui_out(
        tokens_in: u64,
        current_supply: u64,
        base_price: u64,
        slope: u64
    ): u64 {
        let current_area = curve_area(base_price, slope, current_supply);
        let new_supply = current_supply - tokens_in;
        let new_area = curve_area(base_price, slope, new_supply);
        current_area - new_area
    }

    /// Inverse: get supply from area (quadratic formula)
    /// Validates inputs to prevent division by zero and overflow
    fun supply_from_area(base_price: u64, slope: u64, area: u64): u64 {
        // Handle zero slope case (linear pricing)
        if (slope == 0) {
            assert!(base_price > 0, EDivisionByZero);
            return area / base_price
        };

        // Quadratic: slope*s^2/(2*PRECISION) + base*s - area = 0
        // s = (-base + sqrt(base^2 + 2*slope*area/PRECISION)) * PRECISION / slope
        let b = (base_price as u256);
        let k = (slope as u256);
        let a = (area as u256);

        // Calculate discriminant with overflow protection
        let b_squared = b * b;
        let two_k_a = 2 * k * a;
        let discriminant = b_squared + two_k_a; // Simplified: PRECISION cancels out
        let sqrt_disc = sqrt(discriminant);

        // Ensure sqrt_disc >= b to prevent underflow
        assert!(sqrt_disc >= b, EInvalidInput);

        let numerator = (sqrt_disc - b) * PRECISION;
        let result = numerator / k;

        assert!(result <= MAX_U64, EOverflow);
        (result as u64)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_mul_div() {
        assert!(mul_div(100, 50, 100) == 50, 0);
        assert!(mul_div(1000, 500, 10000) == 50, 1);
    }

    #[test]
    fun test_bps() {
        assert!(bps(1000, 500) == 50, 0);   // 5%
        assert!(bps(1000, 100) == 10, 1);   // 1%
        assert!(bps(10000, 250) == 250, 2); // 2.5%
    }

    #[test]
    fun test_sqrt() {
        assert!(sqrt(0) == 0, 0);
        assert!(sqrt(1) == 1, 1);
        assert!(sqrt(4) == 2, 2);
        assert!(sqrt(9) == 3, 3);
        assert!(sqrt(100) == 10, 4);
    }

    #[test]
    fun test_curve_area() {
        // With zero slope, area = base_price * supply
        assert!(curve_area(1000, 0, 100) == 100000, 0);
    }
}
