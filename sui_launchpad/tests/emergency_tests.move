/// Tests for emergency module
#[test_only]
module sui_launchpad::emergency_tests {
    use sui::test_scenario::{Self as ts};

    use sui_launchpad::emergency;
    use sui_launchpad::access;

    // ═══════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════

    fun admin(): address { @0xA1 }
    fun guardian(): address { @0xB2 }
    fun user(): address { @0xC3 }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANT GETTER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_rage_quit_fee_multiplier() {
        // Fee multiplier constant
        let multiplier = emergency::rage_quit_fee_multiplier();
        assert!(multiplier == 2, 0);
    }

    #[test]
    fun test_max_rage_quit_fee_bps() {
        // Max fee should be 20% = 2000 bps
        let max_fee = emergency::max_rage_quit_fee_bps();
        assert!(max_fee == 2000, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMERGENCY STATE CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_emergency_state() {
        let mut scenario = ts::begin(admin());
        {
            let state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // New state should not be active
            assert!(!emergency::is_emergency_active(&state), 0);

            // No guardian set initially
            assert!(option::is_none(&emergency::get_guardian(&state)), 1);

            // No emergency activated time
            assert!(emergency::emergency_activated_at(&state) == 0, 2);

            // Clean up
            emergency::destroy_for_testing(state);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_emergency_state_initial_counters() {
        let mut scenario = ts::begin(admin());
        {
            let state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // Initial counters should be zero
            assert!(emergency::total_rage_quits(&state) == 0, 0);
            assert!(emergency::total_sui_recovered(&state) == 0, 1);

            emergency::destroy_for_testing(state);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_emergency_reason_empty_initially() {
        let mut scenario = ts::begin(admin());
        {
            let state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // Reason should be empty initially
            let reason = emergency::emergency_reason(&state);
            assert!(vector::length(reason) == 0, 0);

            emergency::destroy_for_testing(state);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GUARDIAN MANAGEMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_set_guardian() {
        let mut scenario = ts::begin(admin());
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // Set guardian
            emergency::set_guardian(&admin_cap, &mut state, guardian(), ts::ctx(&mut scenario));

            // Verify guardian is set
            assert!(emergency::is_guardian(&state, guardian()), 0);
            assert!(!emergency::is_guardian(&state, user()), 1);

            let opt_guardian = emergency::get_guardian(&state);
            assert!(option::is_some(&opt_guardian), 2);
            assert!(*option::borrow(&opt_guardian) == guardian(), 3);

            // Clean up
            access::destroy_admin_cap_for_testing(admin_cap);
            emergency::destroy_for_testing(state);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_remove_guardian() {
        let mut scenario = ts::begin(admin());
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // Set guardian first
            emergency::set_guardian(&admin_cap, &mut state, guardian(), ts::ctx(&mut scenario));
            assert!(emergency::is_guardian(&state, guardian()), 0);

            // Remove guardian
            emergency::remove_guardian(&admin_cap, &mut state, ts::ctx(&mut scenario));
            assert!(!emergency::is_guardian(&state, guardian()), 1);
            assert!(option::is_none(&emergency::get_guardian(&state)), 2);

            // Clean up
            access::destroy_admin_cap_for_testing(admin_cap);
            emergency::destroy_for_testing(state);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_update_guardian() {
        let mut scenario = ts::begin(admin());
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // Set guardian to one address
            emergency::set_guardian(&admin_cap, &mut state, guardian(), ts::ctx(&mut scenario));
            assert!(emergency::is_guardian(&state, guardian()), 0);

            // Update guardian to another address
            emergency::set_guardian(&admin_cap, &mut state, user(), ts::ctx(&mut scenario));
            assert!(!emergency::is_guardian(&state, guardian()), 1);
            assert!(emergency::is_guardian(&state, user()), 2);

            // Clean up
            access::destroy_admin_cap_for_testing(admin_cap);
            emergency::destroy_for_testing(state);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMERGENCY ACTIVATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_activate_emergency_by_guardian() {
        let mut scenario = ts::begin(admin());
        // Setup: set guardian
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let state = emergency::create_emergency_state(ts::ctx(&mut scenario));
            transfer::public_share_object(state);
            access::destroy_admin_cap_for_testing(admin_cap);
        };

        // Set guardian
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = ts::take_shared<emergency::EmergencyState>(&scenario);
            emergency::set_guardian(&admin_cap, &mut state, guardian(), ts::ctx(&mut scenario));
            ts::return_shared(state);
            access::destroy_admin_cap_for_testing(admin_cap);
        };

        // Guardian activates emergency
        ts::next_tx(&mut scenario, guardian());
        {
            let mut state = ts::take_shared<emergency::EmergencyState>(&scenario);
            let clock = sui::clock::create_for_testing(ts::ctx(&mut scenario));

            emergency::activate_emergency(
                &mut state,
                b"Security vulnerability detected",
                &clock,
                ts::ctx(&mut scenario)
            );

            // Verify emergency is active
            assert!(emergency::is_emergency_active(&state), 0);

            sui::clock::destroy_for_testing(clock);
            ts::return_shared(state);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_deactivate_emergency() {
        let mut scenario = ts::begin(admin());
        // Setup
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let state = emergency::create_emergency_state(ts::ctx(&mut scenario));
            transfer::public_share_object(state);
            access::destroy_admin_cap_for_testing(admin_cap);
        };

        // Set guardian
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = ts::take_shared<emergency::EmergencyState>(&scenario);
            emergency::set_guardian(&admin_cap, &mut state, guardian(), ts::ctx(&mut scenario));
            ts::return_shared(state);
            access::destroy_admin_cap_for_testing(admin_cap);
        };

        // Guardian activates emergency
        ts::next_tx(&mut scenario, guardian());
        {
            let mut state = ts::take_shared<emergency::EmergencyState>(&scenario);
            let clock = sui::clock::create_for_testing(ts::ctx(&mut scenario));
            emergency::activate_emergency(&mut state, b"Test", &clock, ts::ctx(&mut scenario));
            assert!(emergency::is_emergency_active(&state), 0);
            sui::clock::destroy_for_testing(clock);
            ts::return_shared(state);
        };

        // Admin deactivates emergency
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = ts::take_shared<emergency::EmergencyState>(&scenario);
            let clock = sui::clock::create_for_testing(ts::ctx(&mut scenario));
            emergency::deactivate_emergency(&admin_cap, &mut state, &clock, ts::ctx(&mut scenario));
            assert!(!emergency::is_emergency_active(&state), 1);
            sui::clock::destroy_for_testing(clock);
            ts::return_shared(state);
            access::destroy_admin_cap_for_testing(admin_cap);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_is_guardian_with_no_guardian_set() {
        let mut scenario = ts::begin(admin());
        {
            let state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // Any address should return false when no guardian is set
            assert!(!emergency::is_guardian(&state, guardian()), 0);
            assert!(!emergency::is_guardian(&state, user()), 1);
            assert!(!emergency::is_guardian(&state, admin()), 2);

            emergency::destroy_for_testing(state);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 801)] // EGuardianNotSet
    fun test_remove_guardian_when_none_set_fails() {
        let mut scenario = ts::begin(admin());
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // Should fail when removing non-existent guardian
            emergency::remove_guardian(&admin_cap, &mut state, ts::ctx(&mut scenario));

            access::destroy_admin_cap_for_testing(admin_cap);
            emergency::destroy_for_testing(state);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 802)] // EAlreadyGuardian
    fun test_set_same_guardian_fails() {
        let mut scenario = ts::begin(admin());
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // Set guardian
            emergency::set_guardian(&admin_cap, &mut state, guardian(), ts::ctx(&mut scenario));

            // Try to set same guardian again - should fail
            emergency::set_guardian(&admin_cap, &mut state, guardian(), ts::ctx(&mut scenario));

            access::destroy_admin_cap_for_testing(admin_cap);
            emergency::destroy_for_testing(state);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 800)] // ENotGuardian
    fun test_activate_emergency_not_guardian_fails() {
        let mut scenario = ts::begin(admin());
        // Setup
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let state = emergency::create_emergency_state(ts::ctx(&mut scenario));
            transfer::public_share_object(state);
            access::destroy_admin_cap_for_testing(admin_cap);
        };

        // Set guardian
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = ts::take_shared<emergency::EmergencyState>(&scenario);
            emergency::set_guardian(&admin_cap, &mut state, guardian(), ts::ctx(&mut scenario));
            ts::return_shared(state);
            access::destroy_admin_cap_for_testing(admin_cap);
        };

        // Non-guardian tries to activate emergency - should fail
        ts::next_tx(&mut scenario, user());
        {
            let mut state = ts::take_shared<emergency::EmergencyState>(&scenario);
            let clock = sui::clock::create_for_testing(ts::ctx(&mut scenario));

            emergency::activate_emergency(&mut state, b"Hack", &clock, ts::ctx(&mut scenario));

            sui::clock::destroy_for_testing(clock);
            ts::return_shared(state);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 801)] // EGuardianNotSet
    fun test_activate_emergency_no_guardian_fails() {
        let mut scenario = ts::begin(guardian());
        {
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));
            let clock = sui::clock::create_for_testing(ts::ctx(&mut scenario));

            // No guardian set - should fail
            emergency::activate_emergency(&mut state, b"Test", &clock, ts::ctx(&mut scenario));

            sui::clock::destroy_for_testing(clock);
            emergency::destroy_for_testing(state);
        };
        ts::end(scenario);
    }
}
