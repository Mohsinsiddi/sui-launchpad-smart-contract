/// Tests for the Operator Registry system
#[test_only]
module sui_launchpad::operator_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};

    use sui_launchpad::operators::{Self, OperatorRegistry};
    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::{Self, AdminCap};

    // Test addresses
    fun admin(): address { @0xAD }
    fun operator1(): address { @0xE1 }
    fun operator2(): address { @0xE2 }
    fun operator3(): address { @0xE3 }
    fun random_user(): address { @0x999 }

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    fun setup_test(): Scenario {
        let mut scenario = ts::begin(admin());

        // Create operator registry
        ts::next_tx(&mut scenario, admin());
        {
            let registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));
            transfer::public_share_object(registry);
        };

        // Create admin cap and config
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = access::create_admin_cap(ts::ctx(&mut scenario));
            transfer::public_transfer(admin_cap, admin());

            let config = config::create_for_testing(admin(), ts::ctx(&mut scenario));
            transfer::public_share_object(config);
        };

        scenario
    }

    fun create_clock(scenario: &mut Scenario): Clock {
        clock::create_for_testing(ts::ctx(scenario))
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ROLE CONSTANT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_role_constants() {
        assert!(operators::role_super_admin() == 0, 0);
        assert!(operators::role_graduation() == 1, 1);
        assert!(operators::role_fee() == 2, 2);
        assert!(operators::role_pause() == 3, 3);
        assert!(operators::role_treasury() == 4, 4);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SUPER ADMIN TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_deployer_is_super_admin() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, admin());
        {
            let registry = ts::take_shared<OperatorRegistry>(&scenario);

            // Deployer should be super admin
            assert!(operators::is_super_admin(&registry, admin()), 0);

            // Random user should not be super admin
            assert!(!operators::is_super_admin(&registry, random_user()), 1);

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_add_super_admin() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, admin());
        {
            let mut registry = ts::take_shared<OperatorRegistry>(&scenario);

            // Add new super admin
            operators::add_super_admin(&mut registry, operator1(), ts::ctx(&mut scenario));

            // Verify both are super admins
            assert!(operators::is_super_admin(&registry, admin()), 0);
            assert!(operators::is_super_admin(&registry, operator1()), 1);

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 700)] // ENotSuperAdmin
    fun test_non_admin_cannot_add_operator() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, random_user());
        {
            let mut registry = ts::take_shared<OperatorRegistry>(&scenario);

            // Non-admin trying to add operator should fail
            operators::add_operator(&mut registry, operator1(), operators::role_pause(), ts::ctx(&mut scenario));

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OPERATOR MANAGEMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_add_and_remove_operators() {
        let mut scenario = setup_test();

        // Add operators for different roles
        ts::next_tx(&mut scenario, admin());
        {
            let mut registry = ts::take_shared<OperatorRegistry>(&scenario);

            operators::add_operator(&mut registry, operator1(), operators::role_pause(), ts::ctx(&mut scenario));
            operators::add_operator(&mut registry, operator2(), operators::role_fee(), ts::ctx(&mut scenario));
            operators::add_operator(&mut registry, operator3(), operators::role_treasury(), ts::ctx(&mut scenario));

            ts::return_shared(registry);
        };

        // Verify operators have correct roles
        ts::next_tx(&mut scenario, admin());
        {
            let registry = ts::take_shared<OperatorRegistry>(&scenario);

            assert!(operators::is_pause_operator(&registry, operator1()), 0);
            assert!(!operators::is_fee_operator(&registry, operator1()), 1);

            assert!(operators::is_fee_operator(&registry, operator2()), 2);
            assert!(!operators::is_pause_operator(&registry, operator2()), 3);

            assert!(operators::is_treasury_operator(&registry, operator3()), 4);

            ts::return_shared(registry);
        };

        // Remove an operator
        ts::next_tx(&mut scenario, admin());
        {
            let mut registry = ts::take_shared<OperatorRegistry>(&scenario);

            operators::remove_operator(&mut registry, operator1(), operators::role_pause(), ts::ctx(&mut scenario));

            // Verify operator no longer has role
            assert!(!operators::is_pause_operator(&registry, operator1()), 5);

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_super_admin_has_all_roles() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, admin());
        {
            let registry = ts::take_shared<OperatorRegistry>(&scenario);

            // Super admin should have all operator roles
            assert!(operators::is_graduation_operator(&registry, admin()), 0);
            assert!(operators::is_fee_operator(&registry, admin()), 1);
            assert!(operators::is_pause_operator(&registry, admin()), 2);
            assert!(operators::is_treasury_operator(&registry, admin()), 3);

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 708)] // ECannotRemoveLastSuperAdmin
    fun test_cannot_remove_last_super_admin() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, admin());
        {
            let mut registry = ts::take_shared<OperatorRegistry>(&scenario);

            // Try to remove the only super admin - should fail
            operators::remove_operator(&mut registry, admin(), operators::role_super_admin(), ts::ctx(&mut scenario));

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_can_remove_super_admin_if_others_exist() {
        let mut scenario = setup_test();

        // Add another super admin
        ts::next_tx(&mut scenario, admin());
        {
            let mut registry = ts::take_shared<OperatorRegistry>(&scenario);
            operators::add_super_admin(&mut registry, operator1(), ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };

        // Now admin can remove themselves (operator1 will still be super admin)
        ts::next_tx(&mut scenario, admin());
        {
            let mut registry = ts::take_shared<OperatorRegistry>(&scenario);
            operators::remove_operator(&mut registry, admin(), operators::role_super_admin(), ts::ctx(&mut scenario));

            assert!(!operators::is_super_admin(&registry, admin()), 0);
            assert!(operators::is_super_admin(&registry, operator1()), 1);

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OPERATOR COUNT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_operator_counts() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, admin());
        {
            let mut registry = ts::take_shared<OperatorRegistry>(&scenario);

            // Initial state: 1 super admin
            assert!(operators::get_operator_count(&registry, operators::role_super_admin()) == 1, 0);
            assert!(operators::get_operator_count(&registry, operators::role_pause()) == 0, 1);

            // Add operators
            operators::add_operator(&mut registry, operator1(), operators::role_pause(), ts::ctx(&mut scenario));
            operators::add_operator(&mut registry, operator2(), operators::role_pause(), ts::ctx(&mut scenario));

            assert!(operators::get_operator_count(&registry, operators::role_pause()) == 2, 2);

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HAS_ROLE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_has_role() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, admin());
        {
            let mut registry = ts::take_shared<OperatorRegistry>(&scenario);

            operators::add_operator(&mut registry, operator1(), operators::role_fee(), ts::ctx(&mut scenario));

            // Test has_role function
            assert!(operators::has_role(&registry, admin(), operators::role_super_admin()), 0);
            assert!(operators::has_role(&registry, admin(), operators::role_fee()), 1); // super admin has all roles
            assert!(operators::has_role(&registry, operator1(), operators::role_fee()), 2);
            assert!(!operators::has_role(&registry, operator1(), operators::role_pause()), 3);

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DUPLICATE OPERATOR TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure(abort_code = 706)] // EOperatorAlreadyExists
    fun test_cannot_add_duplicate_operator() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, admin());
        {
            let mut registry = ts::take_shared<OperatorRegistry>(&scenario);

            operators::add_operator(&mut registry, operator1(), operators::role_pause(), ts::ctx(&mut scenario));
            // Try to add same operator for same role again
            operators::add_operator(&mut registry, operator1(), operators::role_pause(), ts::ctx(&mut scenario));

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_same_operator_can_have_multiple_roles() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, admin());
        {
            let mut registry = ts::take_shared<OperatorRegistry>(&scenario);

            // Add operator for multiple roles
            operators::add_operator(&mut registry, operator1(), operators::role_pause(), ts::ctx(&mut scenario));
            operators::add_operator(&mut registry, operator1(), operators::role_fee(), ts::ctx(&mut scenario));

            assert!(operators::is_pause_operator(&registry, operator1()), 0);
            assert!(operators::is_fee_operator(&registry, operator1()), 1);

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ASSERTION FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure(abort_code = 701)] // ENotGraduationOperator
    fun test_assert_graduation_operator_fails() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, admin());
        {
            let registry = ts::take_shared<OperatorRegistry>(&scenario);

            // random_user is not a graduation operator
            operators::assert_graduation_operator(&registry, random_user());

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 702)] // ENotFeeOperator
    fun test_assert_fee_operator_fails() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, admin());
        {
            let registry = ts::take_shared<OperatorRegistry>(&scenario);

            operators::assert_fee_operator(&registry, random_user());

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 703)] // ENotPauseOperator
    fun test_assert_pause_operator_fails() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, admin());
        {
            let registry = ts::take_shared<OperatorRegistry>(&scenario);

            operators::assert_pause_operator(&registry, random_user());

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 704)] // ENotTreasuryOperator
    fun test_assert_treasury_operator_fails() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, admin());
        {
            let registry = ts::take_shared<OperatorRegistry>(&scenario);

            operators::assert_treasury_operator(&registry, random_user());

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTER FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_get_operators() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, admin());
        {
            let mut registry = ts::take_shared<OperatorRegistry>(&scenario);

            operators::add_operator(&mut registry, operator1(), operators::role_pause(), ts::ctx(&mut scenario));
            operators::add_operator(&mut registry, operator2(), operators::role_pause(), ts::ctx(&mut scenario));

            let pause_ops = operators::get_pause_operators(&registry);
            assert!(vector::length(&pause_ops) == 2, 0);

            let super_admins = operators::get_super_admins(&registry);
            assert!(vector::length(&super_admins) == 1, 1);

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }
}
