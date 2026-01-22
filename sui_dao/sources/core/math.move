/// Math utilities for DAO voting calculations
module sui_dao::math {
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Basis points denominator (100%)
    const BPS_DENOMINATOR: u64 = 10_000;

    /// Percentage denominator (100%)
    const PERCENTAGE_DENOMINATOR: u64 = 100;

    // ═══════════════════════════════════════════════════════════════════════
    // QUORUM CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Calculate quorum threshold based on total supply and quorum percentage
    /// quorum_bps is in basis points (e.g., 400 = 4%)
    public fun calculate_quorum(total_supply: u64, quorum_bps: u64): u64 {
        mul_div(total_supply, quorum_bps, BPS_DENOMINATOR)
    }

    /// Check if quorum is met
    public fun is_quorum_met(
        total_votes: u64,
        total_supply: u64,
        quorum_bps: u64,
    ): bool {
        let quorum_threshold = calculate_quorum(total_supply, quorum_bps);
        total_votes >= quorum_threshold
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VOTING CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Check if proposal passes (for votes > against votes)
    public fun proposal_passes(for_votes: u64, against_votes: u64): bool {
        for_votes > against_votes
    }

    /// Check if proposal passes with a required approval percentage
    /// approval_bps is in basis points (e.g., 5000 = 50% simple majority)
    public fun proposal_passes_with_threshold(
        for_votes: u64,
        against_votes: u64,
        approval_bps: u64,
    ): bool {
        let total_votes = for_votes + against_votes;
        if (total_votes == 0) {
            return false
        };
        let required_for = mul_div(total_votes, approval_bps, BPS_DENOMINATOR);
        for_votes >= required_for
    }

    /// Calculate vote percentage in basis points
    public fun calculate_vote_percentage_bps(votes: u64, total_votes: u64): u64 {
        if (total_votes == 0) {
            return 0
        };
        mul_div(votes, BPS_DENOMINATOR, total_votes)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COUNCIL CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Calculate majority threshold for council (more than 50%)
    public fun council_majority_threshold(total_members: u64): u64 {
        (total_members / 2) + 1
    }

    /// Calculate veto threshold (1/3 + 1 of council)
    public fun council_veto_threshold(total_members: u64): u64 {
        (total_members / 3) + 1
    }

    /// Check if council has majority
    public fun has_council_majority(approvals: u64, total_members: u64): bool {
        approvals >= council_majority_threshold(total_members)
    }

    /// Check if council can veto (needs 1/3 + 1)
    public fun has_veto_power(veto_votes: u64, total_members: u64): bool {
        veto_votes >= council_veto_threshold(total_members)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FEE CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Calculate fee amount from basis points
    public fun calculate_fee_bps(amount: u64, fee_bps: u64): u64 {
        mul_div(amount, fee_bps, BPS_DENOMINATOR)
    }

    /// Calculate amount after fee deduction
    public fun amount_after_fee_bps(amount: u64, fee_bps: u64): u64 {
        let fee = calculate_fee_bps(amount, fee_bps);
        amount - fee
    }

    // ═══════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Safe multiplication and division to avoid overflow
    /// Returns (a * b) / c
    public fun mul_div(a: u64, b: u64, c: u64): u64 {
        let result = ((a as u128) * (b as u128)) / (c as u128);
        (result as u64)
    }

    /// Safe multiplication and division with rounding up
    /// Returns ceil((a * b) / c)
    public fun mul_div_up(a: u64, b: u64, c: u64): u64 {
        let numerator = (a as u128) * (b as u128);
        let result = (numerator + (c as u128) - 1) / (c as u128);
        (result as u64)
    }

    /// Calculate percentage (0-100)
    public fun percentage(value: u64, total: u64): u64 {
        if (total == 0) {
            return 0
        };
        mul_div(value, PERCENTAGE_DENOMINATOR, total)
    }

    /// Minimum of two values
    public fun min(a: u64, b: u64): u64 {
        if (a < b) { a } else { b }
    }

    /// Maximum of two values
    public fun max(a: u64, b: u64): u64 {
        if (a > b) { a } else { b }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun bps_denominator(): u64 { BPS_DENOMINATOR }
    public fun percentage_denominator(): u64 { PERCENTAGE_DENOMINATOR }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_calculate_quorum() {
        // 4% of 1,000,000 = 40,000
        assert!(calculate_quorum(1_000_000, 400) == 40_000, 0);

        // 10% of 500,000 = 50,000
        assert!(calculate_quorum(500_000, 1000) == 50_000, 1);

        // 50% of 100 = 50
        assert!(calculate_quorum(100, 5000) == 50, 2);
    }

    #[test]
    fun test_is_quorum_met() {
        // 4% quorum of 1,000,000 = 40,000
        assert!(is_quorum_met(40_000, 1_000_000, 400) == true, 0);
        assert!(is_quorum_met(39_999, 1_000_000, 400) == false, 1);
        assert!(is_quorum_met(50_000, 1_000_000, 400) == true, 2);
    }

    #[test]
    fun test_proposal_passes() {
        assert!(proposal_passes(100, 50) == true, 0);
        assert!(proposal_passes(50, 100) == false, 1);
        assert!(proposal_passes(100, 100) == false, 2); // Tie = fails
        assert!(proposal_passes(0, 0) == false, 3);
    }

    #[test]
    fun test_proposal_passes_with_threshold() {
        // 50% threshold (simple majority)
        assert!(proposal_passes_with_threshold(51, 49, 5000) == true, 0);
        assert!(proposal_passes_with_threshold(50, 50, 5000) == true, 1);
        assert!(proposal_passes_with_threshold(49, 51, 5000) == false, 2);

        // 66% threshold (supermajority)
        assert!(proposal_passes_with_threshold(66, 34, 6600) == true, 3);
        assert!(proposal_passes_with_threshold(65, 35, 6600) == false, 4);

        // Zero total votes
        assert!(proposal_passes_with_threshold(0, 0, 5000) == false, 5);
    }

    #[test]
    fun test_calculate_vote_percentage_bps() {
        // 50 out of 100 = 5000 bps (50%)
        assert!(calculate_vote_percentage_bps(50, 100) == 5000, 0);

        // 33 out of 100 = 3300 bps (33%)
        assert!(calculate_vote_percentage_bps(33, 100) == 3300, 1);

        // 0 out of 0 = 0 (avoid division by zero)
        assert!(calculate_vote_percentage_bps(0, 0) == 0, 2);

        // 100 out of 100 = 10000 bps (100%)
        assert!(calculate_vote_percentage_bps(100, 100) == 10_000, 3);
    }

    #[test]
    fun test_council_majority_threshold() {
        assert!(council_majority_threshold(3) == 2, 0);  // 2 of 3
        assert!(council_majority_threshold(5) == 3, 1);  // 3 of 5
        assert!(council_majority_threshold(7) == 4, 2);  // 4 of 7
        assert!(council_majority_threshold(10) == 6, 3); // 6 of 10
    }

    #[test]
    fun test_council_veto_threshold() {
        assert!(council_veto_threshold(3) == 2, 0);   // 2 of 3 (1/3 + 1)
        assert!(council_veto_threshold(6) == 3, 1);   // 3 of 6
        assert!(council_veto_threshold(9) == 4, 2);   // 4 of 9
        assert!(council_veto_threshold(10) == 4, 3);  // 4 of 10
    }

    #[test]
    fun test_has_council_majority() {
        assert!(has_council_majority(2, 3) == true, 0);
        assert!(has_council_majority(1, 3) == false, 1);
        assert!(has_council_majority(3, 5) == true, 2);
        assert!(has_council_majority(2, 5) == false, 3);
    }

    #[test]
    fun test_has_veto_power() {
        assert!(has_veto_power(2, 3) == true, 0);
        assert!(has_veto_power(1, 3) == false, 1);
        assert!(has_veto_power(3, 6) == true, 2);
        assert!(has_veto_power(2, 6) == false, 3);
    }

    #[test]
    fun test_calculate_fee_bps() {
        // 1% fee on 10,000 = 100
        assert!(calculate_fee_bps(10_000, 100) == 100, 0);

        // 2.5% fee on 1000 = 25
        assert!(calculate_fee_bps(1000, 250) == 25, 1);

        // 0% fee = 0
        assert!(calculate_fee_bps(1000, 0) == 0, 2);
    }

    #[test]
    fun test_amount_after_fee_bps() {
        // 1% fee on 10,000 = 9,900
        assert!(amount_after_fee_bps(10_000, 100) == 9_900, 0);

        // 2.5% fee on 1000 = 975
        assert!(amount_after_fee_bps(1000, 250) == 975, 1);
    }

    #[test]
    fun test_mul_div() {
        assert!(mul_div(100, 50, 100) == 50, 0);
        assert!(mul_div(1_000_000, 1_000_000, 1_000_000) == 1_000_000, 1);

        // Test large numbers that would overflow u64 without casting
        assert!(mul_div(10_000_000_000, 10_000_000_000, 10_000_000_000) == 10_000_000_000, 2);
    }

    #[test]
    fun test_mul_div_up() {
        // Exact division
        assert!(mul_div_up(100, 50, 100) == 50, 0);

        // Rounds up
        assert!(mul_div_up(100, 33, 100) == 33, 1);
        assert!(mul_div_up(10, 3, 10) == 3, 2);

        // 7 * 3 / 10 = 2.1 -> rounds to 3
        assert!(mul_div_up(7, 3, 10) == 3, 3);
    }

    #[test]
    fun test_percentage() {
        assert!(percentage(50, 100) == 50, 0);
        assert!(percentage(25, 100) == 25, 1);
        assert!(percentage(0, 100) == 0, 2);
        assert!(percentage(100, 0) == 0, 3); // Avoid division by zero
    }

    #[test]
    fun test_min_max() {
        assert!(min(5, 10) == 5, 0);
        assert!(min(10, 5) == 5, 1);
        assert!(min(5, 5) == 5, 2);

        assert!(max(5, 10) == 10, 3);
        assert!(max(10, 5) == 10, 4);
        assert!(max(5, 5) == 5, 5);
    }
}
