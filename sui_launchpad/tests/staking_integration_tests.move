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
        // Valid destinations (0, 1, 2)
        assert!(staking_integration::is_valid_admin_destination(0), 0);
        assert!(staking_integration::is_valid_admin_destination(1), 1);
        assert!(staking_integration::is_valid_admin_destination(2), 2);

        // Invalid destinations (> 2)
        assert!(!staking_integration::is_valid_admin_destination(3), 3);
        assert!(!staking_integration::is_valid_admin_destination(4), 4);
        assert!(!staking_integration::is_valid_admin_destination(100), 5);
        assert!(!staking_integration::is_valid_admin_destination(255), 6);
    }

    #[test]
    fun test_is_valid_reward_type() {
        // Valid reward types (0, 1, 2)
        assert!(staking_integration::is_valid_reward_type(0), 0);
        assert!(staking_integration::is_valid_reward_type(1), 1);
        assert!(staking_integration::is_valid_reward_type(2), 2);

        // Invalid reward types (> 2)
        assert!(!staking_integration::is_valid_reward_type(3), 3);
        assert!(!staking_integration::is_valid_reward_type(4), 4);
        assert!(!staking_integration::is_valid_reward_type(100), 5);
        assert!(!staking_integration::is_valid_reward_type(255), 6);
    }

    #[test]
    fun test_admin_destination_boundary() {
        // Test boundary: 2 is valid (ADMIN_DEST_PLATFORM), 3 is invalid
        assert!(staking_integration::is_valid_admin_destination(2), 0);
        assert!(!staking_integration::is_valid_admin_destination(3), 1);
    }

    #[test]
    fun test_reward_type_boundary() {
        // Test boundary: 2 is valid (REWARD_CUSTOM), 3 is invalid
        assert!(staking_integration::is_valid_reward_type(2), 0);
        assert!(!staking_integration::is_valid_reward_type(3), 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANT VALUE VERIFICATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_admin_destination_values_are_sequential() {
        // Admin destinations should be 0, 1, 2 (sequential)
        let creator = staking_integration::admin_dest_creator();
        let dao = staking_integration::admin_dest_dao();
        let platform = staking_integration::admin_dest_platform();

        assert!(creator == 0, 0);
        assert!(dao == creator + 1, 1);
        assert!(platform == dao + 1, 2);
    }

    #[test]
    fun test_reward_type_values_are_sequential() {
        // Reward types should be 0, 1, 2 (sequential)
        let same_token = staking_integration::reward_same_token();
        let sui = staking_integration::reward_sui();
        let custom = staking_integration::reward_custom();

        assert!(same_token == 0, 0);
        assert!(sui == same_token + 1, 1);
        assert!(custom == sui + 1, 2);
    }

    #[test]
    fun test_admin_destination_uniqueness() {
        // All admin destinations must be unique
        let creator = staking_integration::admin_dest_creator();
        let dao = staking_integration::admin_dest_dao();
        let platform = staking_integration::admin_dest_platform();

        assert!(creator != dao, 0);
        assert!(creator != platform, 1);
        assert!(dao != platform, 2);
    }

    #[test]
    fun test_reward_type_uniqueness() {
        // All reward types must be unique
        let same_token = staking_integration::reward_same_token();
        let sui = staking_integration::reward_sui();
        let custom = staking_integration::reward_custom();

        assert!(same_token != sui, 0);
        assert!(same_token != custom, 1);
        assert!(sui != custom, 2);
    }
}
