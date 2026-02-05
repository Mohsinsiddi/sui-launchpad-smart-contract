/// Tests for vesting module - ensures all constant getters work correctly
#[test_only]
module sui_launchpad::vesting_tests {
    use sui_launchpad::vesting;

    // ═══════════════════════════════════════════════════════════════════════
    // INTEGRATION CHECK
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_is_integrated() {
        assert!(vesting::is_integrated() == true, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TIME CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_time_constants() {
        // 1 day = 24 * 60 * 60 * 1000 ms = 86,400,000 ms
        assert!(vesting::ms_per_day() == 86_400_000, 0);

        // 1 month = 30 days = 30 * 86,400,000 = 2,592,000,000 ms
        assert!(vesting::ms_per_month() == 2_592_000_000, 1);

        // 1 year = 365 days = 365 * 86,400,000 = 31,536,000,000 ms
        assert!(vesting::ms_per_year() == 31_536_000_000, 2);
    }

    #[test]
    fun test_time_constant_relationships() {
        // Verify relationships between time units
        // 30 days = 1 month
        assert!(vesting::ms_per_month() == 30 * vesting::ms_per_day(), 0);

        // 365 days = 1 year
        assert!(vesting::ms_per_year() == 365 * vesting::ms_per_day(), 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEFAULT VESTING PARAMETERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_default_creator_vesting_params() {
        // Default cliff is 6 months
        let expected_cliff = 6 * vesting::ms_per_month();
        assert!(vesting::default_creator_cliff_ms() == expected_cliff, 0);

        // Default vesting is 12 months
        let expected_vesting = 12 * vesting::ms_per_month();
        assert!(vesting::default_creator_vesting_ms() == expected_vesting, 1);
    }

    #[test]
    fun test_default_position_nft_params() {
        // Position NFT cliff is 6 months (same as LP)
        let expected_cliff = 6 * vesting::ms_per_month();
        assert!(vesting::default_creator_position_cliff_ms() == expected_cliff, 0);
    }

    #[test]
    fun test_default_vesting_durations_are_reasonable() {
        // Cliff should be less than 1 year
        assert!(vesting::default_creator_cliff_ms() < vesting::ms_per_year(), 0);

        // Total vesting (cliff + linear) should be reasonable (< 3 years)
        let total = vesting::default_creator_cliff_ms() + vesting::default_creator_vesting_ms();
        assert!(total < 3 * vesting::ms_per_year(), 1);

        // Cliff should be positive
        assert!(vesting::default_creator_cliff_ms() > 0, 2);

        // Vesting duration should be positive
        assert!(vesting::default_creator_vesting_ms() > 0, 3);
    }
}
