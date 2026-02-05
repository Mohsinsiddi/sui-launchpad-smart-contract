#[test_only]
module sui_staking::emergency_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::balance;

    use sui_staking::pool::{Self, StakingPool};
    use sui_staking::position::{Self, StakingPosition};
    use sui_staking::access::{Self, PoolAdminCap};
    use sui_staking::emergency::{Self, PoolEmergencyState};

    // ═══════════════════════════════════════════════════════════════════════
    // TEST TOKENS
    // ═══════════════════════════════════════════════════════════════════════

    public struct STAKE has drop {}
    public struct REWARD has drop {}

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    const ADMIN: address = @0xAD;
    const GUARDIAN: address = @0x6A;
    const USER: address = @0x1;

    const MS_PER_DAY: u64 = 86_400_000;
    const MS_PER_WEEK: u64 = 604_800_000;

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    fun setup_test(): Scenario {
        ts::begin(ADMIN)
    }

    fun create_clock(scenario: &mut Scenario, timestamp_ms: u64): Clock {
        ts::next_tx(scenario, ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(scenario));
        clock::set_for_testing(&mut clock, timestamp_ms);
        clock
    }

    fun mint_stake_coins(scenario: &mut Scenario, amount: u64): Coin<STAKE> {
        coin::from_balance(
            balance::create_for_testing<STAKE>(amount),
            ts::ctx(scenario),
        )
    }

    fun mint_reward_coins(scenario: &mut Scenario, amount: u64): Coin<REWARD> {
        coin::from_balance(
            balance::create_for_testing<REWARD>(amount),
            ts::ctx(scenario),
        )
    }

    fun create_test_pool(
        scenario: &mut Scenario,
        clock: &Clock,
    ): (StakingPool<STAKE, REWARD>, PoolAdminCap) {
        let reward_coins = mint_reward_coins(scenario, 100_000_000_000);
        let start_time = clock.timestamp_ms() + 1000; // Start 1 second in the future
        pool::create<STAKE, REWARD>(
            reward_coins,
            start_time, // start time
            MS_PER_WEEK, // duration
            MS_PER_DAY, // min stake duration
            500, // 5% early unstake fee
            0, // 0% stake fee
            0, // 0% unstake fee
            sui_staking::events::origin_independent(),
            option::none(),
            clock,
            ts::ctx(scenario),
        )
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Emergency State Creation
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_emergency_state() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);

            let state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

            // Verify initial state
            assert!(!emergency::is_emergency_active(&state), 0);
            assert!(option::is_none(&emergency::get_guardian(&state)), 1);
            assert!(emergency::pool_id(&state) == object::id(&pool), 2);
            assert!(emergency::emergency_activated_at(&state) == 0, 3);
            assert!(vector::is_empty(emergency::emergency_reason(&state)), 4);
            assert!(emergency::total_emergency_unstakes(&state) == 0, 5);
            assert!(emergency::total_tokens_emergency_unstaked(&state) == 0, 6);

            // Cleanup
            emergency::destroy_for_testing(state);
            pool::destroy_for_testing(pool);
            access::destroy_pool_admin_cap(admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Guardian Management
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_set_guardian() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);
            let mut state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

            // Set guardian
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            // Verify
            assert!(option::is_some(&emergency::get_guardian(&state)), 0);
            assert!(emergency::is_guardian(&state, GUARDIAN), 1);
            assert!(!emergency::is_guardian(&state, USER), 2);

            emergency::destroy_for_testing(state);
            pool::destroy_for_testing(pool);
            access::destroy_pool_admin_cap(admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_change_guardian() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);
            let mut state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

            // Set initial guardian
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));
            assert!(emergency::is_guardian(&state, GUARDIAN), 0);

            // Change guardian
            let new_guardian: address = @0x99;
            emergency::set_guardian(&admin_cap, &mut state, new_guardian, ts::ctx(&mut scenario));

            assert!(emergency::is_guardian(&state, new_guardian), 1);
            assert!(!emergency::is_guardian(&state, GUARDIAN), 2);

            emergency::destroy_for_testing(state);
            pool::destroy_for_testing(pool);
            access::destroy_pool_admin_cap(admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = emergency::EAlreadyGuardian)]
    fun test_set_same_guardian_fails() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);
            let mut state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

            // Set guardian
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            // Try setting same guardian again
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            emergency::destroy_for_testing(state);
            pool::destroy_for_testing(pool);
            access::destroy_pool_admin_cap(admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_remove_guardian() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);
            let mut state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

            // Set then remove guardian
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));
            emergency::remove_guardian(&admin_cap, &mut state, ts::ctx(&mut scenario));

            assert!(option::is_none(&emergency::get_guardian(&state)), 0);
            assert!(!emergency::is_guardian(&state, GUARDIAN), 1);

            emergency::destroy_for_testing(state);
            pool::destroy_for_testing(pool);
            access::destroy_pool_admin_cap(admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = emergency::EGuardianNotSet)]
    fun test_remove_guardian_when_not_set() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);
            let mut state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

            // Try to remove when not set
            emergency::remove_guardian(&admin_cap, &mut state, ts::ctx(&mut scenario));

            emergency::destroy_for_testing(state);
            pool::destroy_for_testing(pool);
            access::destroy_pool_admin_cap(admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Emergency Activation
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_activate_emergency() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 1000000);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);
            let mut state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            pool::destroy_for_testing(pool);
            access::destroy_pool_admin_cap(admin_cap);

            // Activate as guardian
            ts::next_tx(&mut scenario, GUARDIAN);
            let reason = b"Security issue detected";
            emergency::activate_emergency(&mut state, reason, &clock, ts::ctx(&mut scenario));

            // Verify
            assert!(emergency::is_emergency_active(&state), 0);
            assert!(emergency::emergency_activated_at(&state) == 1000000, 1);
            assert!(*emergency::emergency_reason(&state) == reason, 2);

            emergency::destroy_for_testing(state);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = emergency::ENotGuardian)]
    fun test_activate_emergency_not_guardian() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);
            let mut state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            pool::destroy_for_testing(pool);
            access::destroy_pool_admin_cap(admin_cap);

            // Try to activate as non-guardian
            ts::next_tx(&mut scenario, USER);
            emergency::activate_emergency(&mut state, b"hack", &clock, ts::ctx(&mut scenario));

            emergency::destroy_for_testing(state);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = emergency::EGuardianNotSet)]
    fun test_activate_emergency_no_guardian() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);
            let mut state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

            // Try to activate without guardian set
            emergency::activate_emergency(&mut state, b"hack", &clock, ts::ctx(&mut scenario));

            emergency::destroy_for_testing(state);
            pool::destroy_for_testing(pool);
            access::destroy_pool_admin_cap(admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = emergency::EAlreadyInEmergency)]
    fun test_activate_emergency_twice() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);
            let mut state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            pool::destroy_for_testing(pool);
            access::destroy_pool_admin_cap(admin_cap);

            // Activate once
            ts::next_tx(&mut scenario, GUARDIAN);
            emergency::activate_emergency(&mut state, b"first", &clock, ts::ctx(&mut scenario));

            // Try again
            emergency::activate_emergency(&mut state, b"second", &clock, ts::ctx(&mut scenario));

            emergency::destroy_for_testing(state);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Emergency Deactivation
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_deactivate_emergency() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 1000000);

        ts::next_tx(&mut scenario, ADMIN);
        let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);
        let mut state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

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
        pool::destroy_for_testing(pool);
        access::destroy_pool_admin_cap(admin_cap);
        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = emergency::ENotInEmergency)]
    fun test_deactivate_emergency_not_active() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);
            let mut state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

            // Try to deactivate when not active
            emergency::deactivate_emergency(&admin_cap, &mut state, &clock, ts::ctx(&mut scenario));

            emergency::destroy_for_testing(state);
            pool::destroy_for_testing(pool);
            access::destroy_pool_admin_cap(admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Constants
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_constants() {
        // Emergency fee multiplier (2x)
        assert!(emergency::emergency_fee_multiplier() == 2, 0);

        // Max emergency fee (25%)
        assert!(emergency::max_emergency_fee_bps() == 2500, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: View Functions
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_is_guardian() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);
            let mut state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

            // No guardian
            assert!(!emergency::is_guardian(&state, GUARDIAN), 0);
            assert!(!emergency::is_guardian(&state, USER), 1);

            // Set guardian
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            assert!(emergency::is_guardian(&state, GUARDIAN), 2);
            assert!(!emergency::is_guardian(&state, USER), 3);

            emergency::destroy_for_testing(state);
            pool::destroy_for_testing(pool);
            access::destroy_pool_admin_cap(admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_get_guardian() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);
            let mut state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

            // No guardian
            assert!(option::is_none(&emergency::get_guardian(&state)), 0);

            // Set guardian
            emergency::set_guardian(&admin_cap, &mut state, GUARDIAN, ts::ctx(&mut scenario));

            let guardian_opt = emergency::get_guardian(&state);
            assert!(option::is_some(&guardian_opt), 1);
            assert!(*option::borrow(&guardian_opt) == GUARDIAN, 2);

            emergency::destroy_for_testing(state);
            pool::destroy_for_testing(pool);
            access::destroy_pool_admin_cap(admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_pool_id() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = create_test_pool(&mut scenario, &clock);
            let state = emergency::create_emergency_state(&admin_cap, &pool, ts::ctx(&mut scenario));

            assert!(emergency::pool_id(&state) == object::id(&pool), 0);

            emergency::destroy_for_testing(state);
            pool::destroy_for_testing(pool);
            access::destroy_pool_admin_cap(admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}
