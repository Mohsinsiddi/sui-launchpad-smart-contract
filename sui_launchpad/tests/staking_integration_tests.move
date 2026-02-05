/// Tests for staking_integration module
#[test_only]
module sui_launchpad::staking_integration_tests {
    use sui_launchpad::staking_integration;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANT GETTER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_admin_destination_constants() {
        assert!(staking_integration::admin_dest_creator() == 0, 0);
        assert!(staking_integration::admin_dest_dao() == 1, 1);
        assert!(staking_integration::admin_dest_platform() == 2, 2);
    }

    #[test]
    fun test_reward_type_constants() {
        assert!(staking_integration::reward_same_token() == 0, 0);
        assert!(staking_integration::reward_sui() == 1, 1);
        assert!(staking_integration::reward_custom() == 2, 2);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION HELPER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_is_valid_admin_destination() {
        // Valid destinations
        assert!(staking_integration::is_valid_admin_destination(0), 0);
        assert!(staking_integration::is_valid_admin_destination(1), 1);
        assert!(staking_integration::is_valid_admin_destination(2), 2);

        // Invalid destinations
        assert!(!staking_integration::is_valid_admin_destination(3), 3);
        assert!(!staking_integration::is_valid_admin_destination(100), 4);
    }

    #[test]
    fun test_is_valid_reward_type() {
        // Valid reward types
        assert!(staking_integration::is_valid_reward_type(0), 0);
        assert!(staking_integration::is_valid_reward_type(1), 1);
        assert!(staking_integration::is_valid_reward_type(2), 2);

        // Invalid reward types
        assert!(!staking_integration::is_valid_reward_type(3), 3);
        assert!(!staking_integration::is_valid_reward_type(255), 4);
    }
}
