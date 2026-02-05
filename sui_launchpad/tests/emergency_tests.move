#[test_only]
module sui_launchpad::emergency_tests {
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::test_scenario::{Self as ts, Scenario};

    use sui_launchpad::emergency::{Self, EmergencyState};
    use sui_launchpad::access::{Self, AdminCap};
    use sui_launchpad::config::{Self, LaunchpadConfig};

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    const ADMIN: address = @0xAD;
    const GUARDIAN: address = @0x6A;
    const USER: address = @0x1;
    const TREASURY: address = @0xFEE;

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    fun setup_test(): Scenario {
        let mut scenario = ts::begin(ADMIN);
        scenario
    }

    fun create_clock(scenario: &mut Scenario): Clock {
        ts::next_tx(scenario, ADMIN);
        clock::create_for_testing(ts::ctx(scenario))
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Emergency State Creation
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_emergency_state() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // Verify initial state
            assert!(!emergency::is_emergency_active(&state), 0);
            assert!(option::is_none(&emergency::get_guardian(&state)), 1);
            assert!(emergency::emergency_activated_at(&state) == 0, 2);
            assert!(vector::is_empty(emergency::emergency_reason(&state)), 3);
            assert!(emergency::total_rage_quits(&state) == 0, 4);
            assert!(emergency::total_sui_recovered(&state) == 0, 5);

            emergency::destroy_for_testing(state);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Guardian Management
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_set_guardian() {
        let mut scenario = setup_test();
        let mut ctx = tx_context::dummy();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // Set guardian
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            // Verify guardian is set
            assert!(option::is_some(&emergency::get_guardian(&state)), 0);
            assert!(emergency::is_guardian(&state, GUARDIAN), 1);
            assert!(!emergency::is_guardian(&state, USER), 2);

            // Cleanup
            emergency::destroy_for_testing(state);
            access::destroy_admin_cap_for_testing(admin_cap);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_change_guardian() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // Set initial guardian
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));
            assert!(emergency::is_guardian(&state, GUARDIAN), 0);

            // Change to new guardian
            let new_guardian: address = @0x99;
            emergency::set_guardian(&admin_cap, &mut state, new_guardian, ts::ctx(&mut scenario));

            assert!(emergency::is_guardian(&state, new_guardian), 1);
            assert!(!emergency::is_guardian(&state, GUARDIAN), 2);

            emergency::destroy_for_testing(state);
            access::destroy_admin_cap_for_testing(admin_cap);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = emergency::EAlreadyGuardian)]
    fun test_set_same_guardian_fails() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // Set guardian
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            // Try to set same guardian again - should fail
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            emergency::destroy_for_testing(state);
            access::destroy_admin_cap_for_testing(admin_cap);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_remove_guardian() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // Set then remove guardian
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));
            assert!(emergency::is_guardian(&state, GUARDIAN), 0);

            emergency::remove_guardian(&admin_cap, &mut state, ts::ctx(&mut scenario));

            assert!(option::is_none(&emergency::get_guardian(&state)), 1);
            assert!(!emergency::is_guardian(&state, GUARDIAN), 2);

            emergency::destroy_for_testing(state);
            access::destroy_admin_cap_for_testing(admin_cap);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = emergency::EGuardianNotSet)]
    fun test_remove_guardian_when_not_set() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // Try to remove when no guardian set
            emergency::remove_guardian(&admin_cap, &mut state, ts::ctx(&mut scenario));

            emergency::destroy_for_testing(state);
            access::destroy_admin_cap_for_testing(admin_cap);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Emergency Activation
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_activate_emergency() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            // Set guardian
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            access::destroy_admin_cap_for_testing(admin_cap);

            // Activate emergency as guardian
            ts::next_tx(&mut scenario, GUARDIAN);
            let reason = b"Security vulnerability detected";
            emergency::activate_emergency(&mut state, reason, &clock, ts::ctx(&mut scenario));

            // Verify emergency is active
            assert!(emergency::is_emergency_active(&state), 0);
            assert!(emergency::emergency_activated_at(&state) == 0, 1); // clock starts at 0
            assert!(*emergency::emergency_reason(&state) == reason, 2);

            emergency::destroy_for_testing(state);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = emergency::ENotGuardian)]
    fun test_activate_emergency_not_guardian() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            // Set guardian
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            access::destroy_admin_cap_for_testing(admin_cap);

            // Try to activate as non-guardian (USER)
            ts::next_tx(&mut scenario, USER);
            emergency::activate_emergency(&mut state, b"hack", &clock, ts::ctx(&mut scenario));

            emergency::destroy_for_testing(state);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = emergency::EGuardianNotSet)]
    fun test_activate_emergency_no_guardian() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            // Try to activate without guardian set
            emergency::activate_emergency(&mut state, b"hack", &clock, ts::ctx(&mut scenario));

            emergency::destroy_for_testing(state);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = emergency::EAlreadyInEmergency)]
    fun test_activate_emergency_twice() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));
            access::destroy_admin_cap_for_testing(admin_cap);

            // Activate once
            ts::next_tx(&mut scenario, GUARDIAN);
            emergency::activate_emergency(&mut state, b"first", &clock, ts::ctx(&mut scenario));

            // Try to activate again
            emergency::activate_emergency(&mut state, b"second", &clock, ts::ctx(&mut scenario));

            emergency::destroy_for_testing(state);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Emergency Deactivation
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_deactivate_emergency() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            // Activate as guardian
            ts::next_tx(&mut scenario, GUARDIAN);
            emergency::activate_emergency(&mut state, b"test", &clock, ts::ctx(&mut scenario));
            assert!(emergency::is_emergency_active(&state), 0);

            // Deactivate as admin
            ts::next_tx(&mut scenario, ADMIN);
            emergency::deactivate_emergency(&admin_cap, &mut state, &clock, ts::ctx(&mut scenario));

            assert!(!emergency::is_emergency_active(&state), 1);
            assert!(vector::is_empty(emergency::emergency_reason(&state)), 2);

            emergency::destroy_for_testing(state);
            access::destroy_admin_cap_for_testing(admin_cap);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = emergency::ENotInEmergency)]
    fun test_deactivate_emergency_not_active() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            // Try to deactivate when not in emergency
            emergency::deactivate_emergency(&admin_cap, &mut state, &clock, ts::ctx(&mut scenario));

            emergency::destroy_for_testing(state);
            access::destroy_admin_cap_for_testing(admin_cap);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Constants
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_constants() {
        // Verify rage quit fee multiplier
        assert!(emergency::rage_quit_fee_multiplier() == 2, 0);

        // Verify max rage quit fee (20%)
        assert!(emergency::max_rage_quit_fee_bps() == 2000, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: View Functions
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_is_guardian() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // No guardian set
            assert!(!emergency::is_guardian(&state, GUARDIAN), 0);
            assert!(!emergency::is_guardian(&state, USER), 1);

            // Set guardian
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            assert!(emergency::is_guardian(&state, GUARDIAN), 2);
            assert!(!emergency::is_guardian(&state, USER), 3);

            emergency::destroy_for_testing(state);
            access::destroy_admin_cap_for_testing(admin_cap);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_get_guardian() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            let mut state = emergency::create_emergency_state(ts::ctx(&mut scenario));

            // No guardian
            assert!(option::is_none(&emergency::get_guardian(&state)), 0);

            // Set guardian
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            let guardian_opt = emergency::get_guardian(&state);
            assert!(option::is_some(&guardian_opt), 1);
            assert!(*option::borrow(&guardian_opt) == GUARDIAN, 2);

            emergency::destroy_for_testing(state);
            access::destroy_admin_cap_for_testing(admin_cap);
        };

        ts::end(scenario);
    }
}
