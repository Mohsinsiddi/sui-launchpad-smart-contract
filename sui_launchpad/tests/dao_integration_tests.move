/// Tests for dao_integration module
#[test_only]
module sui_launchpad::dao_integration_tests {
    use sui_launchpad::dao_integration;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANT GETTER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_admin_destination_constants() {
        assert!(dao_integration::admin_dest_creator() == 0, 0);
        assert!(dao_integration::admin_dest_dao_treasury() == 1, 1);
        assert!(dao_integration::admin_dest_platform() == 2, 2);
    }

    #[test]
    fun test_admin_destination_values() {
        // Creator gets cap to manage their own DAO
        assert!(dao_integration::admin_dest_creator() == 0, 0);

        // DAO treasury receives cap - community-controlled (default)
        assert!(dao_integration::admin_dest_dao_treasury() == 1, 1);

        // Platform receives cap - platform operates for creator
        assert!(dao_integration::admin_dest_platform() == 2, 2);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION HELPER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_is_valid_admin_destination() {
        // Valid destinations (0, 1, 2)
        assert!(dao_integration::is_valid_admin_destination(0), 0);
        assert!(dao_integration::is_valid_admin_destination(1), 1);
        assert!(dao_integration::is_valid_admin_destination(2), 2);

        // Invalid destinations (> 2)
        assert!(!dao_integration::is_valid_admin_destination(3), 3);
        assert!(!dao_integration::is_valid_admin_destination(4), 4);
        assert!(!dao_integration::is_valid_admin_destination(100), 5);
        assert!(!dao_integration::is_valid_admin_destination(255), 6);
    }

    #[test]
    fun test_admin_destination_boundary() {
        // Test boundary: 2 is valid (ADMIN_DEST_PLATFORM), 3 is invalid
        assert!(dao_integration::is_valid_admin_destination(2), 0);
        assert!(!dao_integration::is_valid_admin_destination(3), 1);
    }
}
