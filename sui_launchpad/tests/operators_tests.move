/// Tests for the operators module
#[test_only]
module sui_launchpad::operators_tests {
    use sui::test_scenario::{Self as ts};
    use sui_launchpad::operators::{Self, OperatorRegistry};

    const ADMIN: address = @0xAD;
    const OP1: address = @0x111;
    const OP2: address = @0x222;
    const OP3: address = @0x333;

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
    // REGISTRY CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_registry() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            // Creator becomes super admin
            assert!(operators::is_super_admin(&registry, ADMIN), 0);
            assert!(!operators::is_super_admin(&registry, OP1), 1);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OPERATOR MANAGEMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_add_graduation_operator() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            operators::add_operator(&mut registry, OP1, operators::role_graduation(), ts::ctx(&mut scenario));

            assert!(operators::is_graduation_operator(&registry, OP1), 0);
            assert!(!operators::is_graduation_operator(&registry, OP2), 1);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_add_fee_operator() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            operators::add_operator(&mut registry, OP1, operators::role_fee(), ts::ctx(&mut scenario));

            assert!(operators::is_fee_operator(&registry, OP1), 0);
            assert!(!operators::is_fee_operator(&registry, OP2), 1);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_add_treasury_operator() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            operators::add_operator(&mut registry, OP1, operators::role_treasury(), ts::ctx(&mut scenario));

            assert!(operators::is_treasury_operator(&registry, OP1), 0);
            assert!(!operators::is_treasury_operator(&registry, OP2), 1);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_remove_operator() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            // Add operator
            operators::add_operator(&mut registry, OP1, operators::role_pause(), ts::ctx(&mut scenario));
            assert!(operators::is_pause_operator(&registry, OP1), 0);

            // Remove operator
            operators::remove_operator(&mut registry, OP1, operators::role_pause(), ts::ctx(&mut scenario));
            assert!(!operators::is_pause_operator(&registry, OP1), 1);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_add_super_admin() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            operators::add_super_admin(&mut registry, OP1, ts::ctx(&mut scenario));

            assert!(operators::is_super_admin(&registry, ADMIN), 0);
            assert!(operators::is_super_admin(&registry, OP1), 1);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_remove_super_admin() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            // Add second super admin
            operators::add_super_admin(&mut registry, OP1, ts::ctx(&mut scenario));
            assert!(operators::is_super_admin(&registry, OP1), 0);

            // Remove second super admin
            operators::remove_super_admin(&mut registry, OP1, ts::ctx(&mut scenario));
            assert!(!operators::is_super_admin(&registry, OP1), 1);

            // First admin still there
            assert!(operators::is_super_admin(&registry, ADMIN), 2);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 708)] // ECannotRemoveLastSuperAdmin
    fun test_cannot_remove_last_super_admin() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            // Try to remove the only super admin
            operators::remove_super_admin(&mut registry, ADMIN, ts::ctx(&mut scenario));

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 700)] // ENotSuperAdmin
    fun test_non_admin_cannot_add_operator() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));
            transfer::public_share_object(registry);
        };

        // Non-admin tries to add operator
        ts::next_tx(&mut scenario, OP1);
        {
            let mut registry = ts::take_shared<OperatorRegistry>(&scenario);

            operators::add_operator(&mut registry, OP2, operators::role_pause(), ts::ctx(&mut scenario));

            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 706)] // EOperatorAlreadyExists
    fun test_cannot_add_duplicate_operator() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            operators::add_operator(&mut registry, OP1, operators::role_pause(), ts::ctx(&mut scenario));
            // Try to add same operator again
            operators::add_operator(&mut registry, OP1, operators::role_pause(), ts::ctx(&mut scenario));

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 707)] // EOperatorNotFound
    fun test_cannot_remove_nonexistent_operator() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            // Try to remove operator that doesn't exist
            operators::remove_operator(&mut registry, OP1, operators::role_pause(), ts::ctx(&mut scenario));

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 705)] // EInvalidRole
    fun test_invalid_role() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            // Try to add with invalid role (> 4)
            operators::add_operator(&mut registry, OP1, 5, ts::ctx(&mut scenario));

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HAS_ROLE AND ASSERTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_has_role() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            operators::add_operator(&mut registry, OP1, operators::role_graduation(), ts::ctx(&mut scenario));
            operators::add_operator(&mut registry, OP2, operators::role_fee(), ts::ctx(&mut scenario));
            operators::add_operator(&mut registry, OP3, operators::role_treasury(), ts::ctx(&mut scenario));

            // Super admin has all roles
            assert!(operators::has_role(&registry, ADMIN, operators::role_super_admin()), 0);
            assert!(operators::has_role(&registry, ADMIN, operators::role_graduation()), 1);
            assert!(operators::has_role(&registry, ADMIN, operators::role_fee()), 2);
            assert!(operators::has_role(&registry, ADMIN, operators::role_pause()), 3);
            assert!(operators::has_role(&registry, ADMIN, operators::role_treasury()), 4);

            // Specific operators have their roles
            assert!(operators::has_role(&registry, OP1, operators::role_graduation()), 5);
            assert!(!operators::has_role(&registry, OP1, operators::role_fee()), 6);

            // Invalid role returns false
            assert!(!operators::has_role(&registry, OP1, 99), 7);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_assert_functions() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            operators::add_operator(&mut registry, OP1, operators::role_graduation(), ts::ctx(&mut scenario));
            operators::add_operator(&mut registry, OP2, operators::role_fee(), ts::ctx(&mut scenario));
            operators::add_operator(&mut registry, OP3, operators::role_treasury(), ts::ctx(&mut scenario));

            // These should not abort
            operators::assert_super_admin(&registry, ADMIN);
            operators::assert_graduation_operator(&registry, OP1);
            operators::assert_graduation_operator(&registry, ADMIN); // Super admin has all roles
            operators::assert_fee_operator(&registry, OP2);
            operators::assert_fee_operator(&registry, ADMIN);
            operators::assert_treasury_operator(&registry, OP3);
            operators::assert_treasury_operator(&registry, ADMIN);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 701)] // ENotGraduationOperator
    fun test_assert_graduation_operator_fails() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            // OP1 is not a graduation operator
            operators::assert_graduation_operator(&registry, OP1);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 702)] // ENotFeeOperator
    fun test_assert_fee_operator_fails() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            operators::assert_fee_operator(&registry, OP1);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 703)] // ENotPauseOperator
    fun test_assert_pause_operator_fails() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            operators::assert_pause_operator(&registry, OP1);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 704)] // ENotTreasuryOperator
    fun test_assert_treasury_operator_fails() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            operators::assert_treasury_operator(&registry, OP1);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_get_operators_lists() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            operators::add_operator(&mut registry, OP1, operators::role_graduation(), ts::ctx(&mut scenario));
            operators::add_operator(&mut registry, OP2, operators::role_fee(), ts::ctx(&mut scenario));
            operators::add_operator(&mut registry, OP3, operators::role_pause(), ts::ctx(&mut scenario));

            let super_admins = operators::get_super_admins(&registry);
            assert!(vector::length(&super_admins) == 1, 0);
            assert!(*vector::borrow(&super_admins, 0) == ADMIN, 1);

            let graduation_ops = operators::get_graduation_operators(&registry);
            assert!(vector::length(&graduation_ops) == 1, 2);

            let fee_ops = operators::get_fee_operators(&registry);
            assert!(vector::length(&fee_ops) == 1, 3);

            let pause_ops = operators::get_pause_operators(&registry);
            assert!(vector::length(&pause_ops) == 1, 4);

            let treasury_ops = operators::get_treasury_operators(&registry);
            assert!(vector::length(&treasury_ops) == 0, 5);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_get_operator_count() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            assert!(operators::get_operator_count(&registry, operators::role_super_admin()) == 1, 0);
            assert!(operators::get_operator_count(&registry, operators::role_graduation()) == 0, 1);
            assert!(operators::get_operator_count(&registry, operators::role_fee()) == 0, 2);
            assert!(operators::get_operator_count(&registry, operators::role_pause()) == 0, 3);
            assert!(operators::get_operator_count(&registry, operators::role_treasury()) == 0, 4);
            assert!(operators::get_operator_count(&registry, 99) == 0, 5); // Invalid role

            // Add operators
            operators::add_operator(&mut registry, OP1, operators::role_graduation(), ts::ctx(&mut scenario));
            operators::add_operator(&mut registry, OP2, operators::role_graduation(), ts::ctx(&mut scenario));

            assert!(operators::get_operator_count(&registry, operators::role_graduation()) == 2, 6);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OPERATOR SAME ROLE AS SUPER ADMIN TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_super_admin_has_all_operator_privileges() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));

            // Super admin should pass all operator checks
            assert!(operators::is_graduation_operator(&registry, ADMIN), 0);
            assert!(operators::is_fee_operator(&registry, ADMIN), 1);
            assert!(operators::is_pause_operator(&registry, ADMIN), 2);
            assert!(operators::is_treasury_operator(&registry, ADMIN), 3);

            operators::destroy_registry_for_testing(registry);
        };

        ts::end(scenario);
    }
}
