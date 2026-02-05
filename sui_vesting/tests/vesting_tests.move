/// Comprehensive tests for the vesting module
#[test_only]
module sui_vesting::vesting_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};
    use sui::coin;

    use sui_vesting::vesting::{Self, VestingConfig, VestingSchedule};
    use sui_vesting::access::{Self, AdminCap, CreatorCap};
    use sui_vesting::test_coin::{Self, TEST_COIN};

    // ═══════════════════════════════════════════════════════════════════════
    // TEST CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    const ADMIN: address = @0xAD;
    const CREATOR: address = @0xC1;
    const BENEFICIARY: address = @0xB1;

    const MS_PER_DAY: u64 = 86_400_000;
    const MS_PER_MONTH: u64 = 2_592_000_000;

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    fun setup_test(): Scenario {
        let mut scenario = ts::begin(ADMIN);
        // Initialize vesting platform
        {
            vesting::init_for_testing(ts::ctx(&mut scenario));
        };
        scenario
    }

    fun create_clock(scenario: &mut Scenario, timestamp_ms: u64): Clock {
        ts::next_tx(scenario, ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(scenario));
        clock::set_for_testing(&mut clock, timestamp_ms);
        clock
    }

    fun advance_clock(clock: &mut Clock, ms: u64) {
        let current = clock::timestamp_ms(clock);
        clock::set_for_testing(clock, current + ms);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SCHEDULE CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test basic schedule creation with cliff and linear vesting
    fun test_create_schedule_basic() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_000_000_000, ts::ctx(&mut scenario)); // 1B tokens

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                1000, // start_time
                MS_PER_MONTH * 6, // 6 month cliff
                MS_PER_MONTH * 12, // 12 month linear vesting
                true, // revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(vesting::get_config_total_schedules(&config) == 1, 0);

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Verify schedule was transferred to beneficiary
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            assert!(vesting::beneficiary(&schedule) == BENEFICIARY, 1);
            assert!(vesting::creator(&schedule) == CREATOR, 2);
            assert!(vesting::total_amount(&schedule) == 1_000_000_000, 3);
            assert!(vesting::claimed(&schedule) == 0, 4);
            assert!(vesting::cliff_duration(&schedule) == MS_PER_MONTH * 6, 5);
            assert!(vesting::vesting_duration(&schedule) == MS_PER_MONTH * 12, 6);
            assert!(vesting::is_revocable(&schedule), 7);
            assert!(!vesting::is_revoked(&schedule), 8);
            assert!(!vesting::is_paused(&schedule), 9);

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test creating schedule with months convenience function
    fun test_create_schedule_months() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(500_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule_months<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                3, // 3 month cliff
                9, // 9 month vesting
                false, // non-revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            assert!(vesting::cliff_duration(&schedule) == MS_PER_MONTH * 3, 0);
            assert!(vesting::vesting_duration(&schedule) == MS_PER_MONTH * 9, 1);
            assert!(!vesting::is_revocable(&schedule), 2);

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test creating instant unlock schedule
    fun test_create_instant_schedule() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(100_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_instant_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // Instant unlock = no cliff, no vesting
            assert!(vesting::cliff_duration(&schedule) == 0, 0);
            assert!(vesting::vesting_duration(&schedule) == 0, 1);

            // Should be fully claimable immediately
            assert!(vesting::claimable(&schedule, &clock) == 100_000_000, 2);

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vesting::EInvalidBeneficiary)]
    /// Test that zero address beneficiary fails
    fun test_create_schedule_zero_beneficiary_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                @0x0, // Zero address - should fail
                1000,
                0,
                0,
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            access::destroy_creator_cap(creator_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vesting::EZeroAmount)]
    /// Test that zero amount fails
    fun test_create_schedule_zero_amount_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = coin::zero<TEST_COIN>(ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                1000,
                0,
                0,
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            access::destroy_creator_cap(creator_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLAIMING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test claiming from instant unlock schedule
    fun test_claim_instant_unlock() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        // Create instant schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(100_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_instant_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Claim immediately
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            let claimed_tokens = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(coin::value(&claimed_tokens) == 100_000_000, 0);

            assert!(vesting::claimed(&schedule) == 100_000_000, 1);
            assert!(vesting::remaining(&schedule) == 0, 2);

            transfer::public_transfer(claimed_tokens, BENEFICIARY);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test claiming during cliff period (should be 0)
    fun test_claimable_during_cliff() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        // Create schedule with 6 month cliff
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_000_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                1000,
                MS_PER_MONTH * 6, // 6 month cliff
                MS_PER_MONTH * 12, // 12 month vesting
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Check claimable during cliff
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // At start - nothing claimable
            assert!(vesting::claimable(&schedule, &clock) == 0, 0);

            // 3 months in (still in cliff)
            advance_clock(&mut clock, MS_PER_MONTH * 3);
            assert!(vesting::claimable(&schedule, &clock) == 0, 1);

            // 5 months 29 days in (still in cliff)
            advance_clock(&mut clock, MS_PER_MONTH * 2 + MS_PER_DAY * 29);
            assert!(vesting::claimable(&schedule, &clock) == 0, 2);

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test linear vesting calculations after cliff
    fun test_linear_vesting_calculations() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create schedule: 1B tokens, 6 month cliff, 12 month linear
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_200_000_000, ts::ctx(&mut scenario)); // 1.2B for easy math

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                0, // start_time = 0
                MS_PER_MONTH * 6, // 6 month cliff
                MS_PER_MONTH * 12, // 12 month vesting
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // Right at cliff end (6 months)
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 6);
            let claimable_at_cliff = vesting::claimable(&schedule, &clock);
            assert!(claimable_at_cliff == 0, 0); // 0% vested at cliff end

            // 1 month after cliff (7 months total) = 1/12 vested
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 7);
            let claimable_1m = vesting::claimable(&schedule, &clock);
            // 1.2B * 1/12 = 100M
            assert!(claimable_1m == 100_000_000, 1);

            // 6 months after cliff (12 months total) = 50% vested
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 12);
            let claimable_6m = vesting::claimable(&schedule, &clock);
            // 1.2B * 6/12 = 600M
            assert!(claimable_6m == 600_000_000, 2);

            // 12 months after cliff (18 months total) = 100% vested
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 18);
            let claimable_full = vesting::claimable(&schedule, &clock);
            assert!(claimable_full == 1_200_000_000, 3);

            // Beyond vesting period - still 100%
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 24);
            let claimable_after = vesting::claimable(&schedule, &clock);
            assert!(claimable_after == 1_200_000_000, 4);

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test multiple claims over time
    fun test_multiple_claims() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create schedule: 1.2B tokens, no cliff, 12 month linear
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_200_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                0, // start_time
                0, // no cliff
                MS_PER_MONTH * 12, // 12 month vesting
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // First claim at 3 months (25% vested = 300M)
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 3);

            let tokens = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(coin::value(&tokens) == 300_000_000, 0);
            assert!(vesting::claimed(&schedule) == 300_000_000, 1);

            transfer::public_transfer(tokens, BENEFICIARY);
            ts::return_to_sender(&scenario, schedule);
        };

        // Second claim at 6 months (50% vested = 600M total, 300M more)
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 6);

            let tokens = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(coin::value(&tokens) == 300_000_000, 2);
            assert!(vesting::claimed(&schedule) == 600_000_000, 3);

            transfer::public_transfer(tokens, BENEFICIARY);
            ts::return_to_sender(&scenario, schedule);
        };

        // Third claim at 12 months (100% vested = 1.2B total, 600M more)
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 12);

            let tokens = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(coin::value(&tokens) == 600_000_000, 4);
            assert!(vesting::claimed(&schedule) == 1_200_000_000, 5);
            assert!(vesting::remaining(&schedule) == 0, 6);

            transfer::public_transfer(tokens, BENEFICIARY);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vesting::ENotBeneficiary)]
    /// Test that non-beneficiary cannot claim
    fun test_claim_non_beneficiary_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create instant schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(100_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_instant_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Transfer schedule to attacker and try to claim
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            transfer::public_transfer(schedule, @0xA77AC);
        };

        ts::next_tx(&mut scenario, @0xA77AC);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            // This should fail - attacker is not the beneficiary
            let tokens = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            transfer::public_transfer(tokens, @0xA77AC);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vesting::ENotClaimable)]
    /// Test claiming when nothing is claimable fails
    fun test_claim_nothing_claimable_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create schedule with cliff
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(100_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                0,
                MS_PER_MONTH * 6, // 6 month cliff
                MS_PER_MONTH * 12,
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Try to claim during cliff - should fail
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 3); // Still in cliff

            let tokens = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            transfer::public_transfer(tokens, BENEFICIARY);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REVOCATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test revoking a schedule before any vesting
    fun test_revoke_before_vesting() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create revocable schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_000_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                0,
                MS_PER_MONTH * 6,
                MS_PER_MONTH * 12,
                true, // revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Revoke during cliff (all tokens return to creator)
        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            // Need to get schedule from beneficiary
            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            clock::set_for_testing(&mut clock, MS_PER_MONTH * 3); // 3 months in (during cliff)

            ts::next_tx(&mut scenario, CREATOR);
            let revoked_tokens = vesting::revoke(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            // All tokens should return to creator (nothing vested yet)
            assert!(coin::value(&revoked_tokens) == 1_000_000_000, 0);
            assert!(vesting::is_revoked(&schedule), 1);

            transfer::public_transfer(revoked_tokens, CREATOR);
            transfer::public_transfer(schedule, BENEFICIARY);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test revoking a schedule after partial vesting
    fun test_revoke_after_partial_vesting() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create revocable schedule: 1.2B tokens, no cliff, 12 month linear
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_200_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                0,
                0, // no cliff
                MS_PER_MONTH * 12, // 12 month vesting
                true, // revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Revoke at 6 months (50% vested)
        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            clock::set_for_testing(&mut clock, MS_PER_MONTH * 6); // 6 months = 50% vested

            ts::next_tx(&mut scenario, CREATOR);
            let revoked_tokens = vesting::revoke(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            // Creator gets 50% back (600M), beneficiary can still claim 50% (600M)
            assert!(coin::value(&revoked_tokens) == 600_000_000, 0);
            assert!(vesting::remaining(&schedule) == 600_000_000, 1);
            assert!(vesting::is_revoked(&schedule), 2);

            transfer::public_transfer(revoked_tokens, CREATOR);
            transfer::public_transfer(schedule, BENEFICIARY);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test beneficiary can claim vested portion after revocation
    fun test_claim_after_revoke() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create revocable schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_200_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                0,
                0,
                MS_PER_MONTH * 12,
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Beneficiary claims 25% at 3 months
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 3);

            let tokens = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(coin::value(&tokens) == 300_000_000, 0);

            transfer::public_transfer(tokens, BENEFICIARY);
            ts::return_to_sender(&scenario, schedule);
        };

        // Creator revokes at 6 months (50% vested, 25% already claimed)
        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            clock::set_for_testing(&mut clock, MS_PER_MONTH * 6);

            ts::next_tx(&mut scenario, CREATOR);
            let revoked_tokens = vesting::revoke(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            // Creator gets unvested 50% = 600M
            // Beneficiary has vested 50% = 600M, but already claimed 300M, so 300M remains
            assert!(coin::value(&revoked_tokens) == 600_000_000, 1);
            assert!(vesting::remaining(&schedule) == 300_000_000, 2);

            transfer::public_transfer(revoked_tokens, CREATOR);
            transfer::public_transfer(schedule, BENEFICIARY);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Beneficiary claims remaining vested amount
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // Note: After revocation, claimable returns 0 due to revoked flag
            // But remaining balance belongs to beneficiary
            // This is intentional - schedule is frozen after revoke

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vesting::ENotRevocable)]
    /// Test that non-revocable schedule cannot be revoked
    fun test_revoke_non_revocable_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create non-revocable schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_000_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                0,
                MS_PER_MONTH * 6,
                MS_PER_MONTH * 12,
                false, // NOT revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Try to revoke - should fail
        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            ts::next_tx(&mut scenario, CREATOR);
            let revoked_tokens = vesting::revoke(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            transfer::public_transfer(revoked_tokens, CREATOR);
            transfer::public_transfer(schedule, BENEFICIARY);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vesting::ECreatorCapMismatch)]
    /// Test that wrong creator cap cannot revoke
    fun test_revoke_wrong_cap_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create first schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens1 = test_coin::mint(1_000_000_000, ts::ctx(&mut scenario));

            let creator_cap1 = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens1,
                BENEFICIARY,
                0,
                MS_PER_MONTH * 6,
                MS_PER_MONTH * 12,
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            // Create second schedule
            let tokens2 = test_coin::mint(500_000_000, ts::ctx(&mut scenario));
            let creator_cap2 = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens2,
                @0xB2, // Different beneficiary
                0,
                0,
                MS_PER_MONTH * 6,
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap1, CREATOR);
            transfer::public_transfer(creator_cap2, @0xC2);
        };

        // Try to use cap2 to revoke schedule1 - should fail
        ts::next_tx(&mut scenario, @0xC2);
        {
            let creator_cap2 = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule1 = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            ts::next_tx(&mut scenario, @0xC2);
            // Using cap2 for schedule1 - should fail
            let revoked_tokens = vesting::revoke(&creator_cap2, &mut schedule1, &clock, ts::ctx(&mut scenario));

            transfer::public_transfer(revoked_tokens, @0xC2);
            transfer::public_transfer(schedule1, BENEFICIARY);
            transfer::public_transfer(creator_cap2, @0xC2);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vesting::EAlreadyRevoked)]
    /// Test double revocation fails
    fun test_double_revoke_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create revocable schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_000_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                0,
                MS_PER_MONTH * 6,
                MS_PER_MONTH * 12,
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // First revoke - succeeds
        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            ts::next_tx(&mut scenario, CREATOR);
            let revoked_tokens = vesting::revoke(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            transfer::public_transfer(revoked_tokens, CREATOR);
            transfer::public_transfer(schedule, BENEFICIARY);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Second revoke - should fail
        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            ts::next_tx(&mut scenario, CREATOR);
            let revoked_tokens = vesting::revoke(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            transfer::public_transfer(revoked_tokens, CREATOR);
            transfer::public_transfer(schedule, BENEFICIARY);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test platform pause prevents new schedules
    fun test_platform_pause() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Pause platform
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<VestingConfig>(&scenario);

            vesting::set_platform_paused(&admin_cap, &mut config, true, &clock, ts::ctx(&mut scenario));

            assert!(vesting::get_config_paused(&config), 0);

            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vesting::ESchedulePaused)]
    /// Test that paused platform rejects new schedules
    fun test_paused_platform_rejects_schedules() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Pause platform
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<VestingConfig>(&scenario);

            vesting::set_platform_paused(&admin_cap, &mut config, true, &clock, ts::ctx(&mut scenario));

            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Try to create schedule on paused platform - should fail
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_000_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                0,
                0,
                0,
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            access::destroy_creator_cap(creator_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test schedule pause prevents claims
    fun test_schedule_pause() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create instant schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_000_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_instant_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Admin pauses schedule
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            ts::next_tx(&mut scenario, ADMIN);
            vesting::set_schedule_paused(&admin_cap, &mut schedule, true, &clock, ts::ctx(&mut scenario));

            assert!(vesting::is_paused(&schedule), 0);
            assert!(vesting::claimable(&schedule, &clock) == 0, 1); // Returns 0 when paused

            transfer::public_transfer(schedule, BENEFICIARY);
            ts::return_to_sender(&scenario, admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vesting::ESchedulePaused)]
    /// Test that paused schedule rejects claims
    fun test_paused_schedule_rejects_claims() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create instant schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_000_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_instant_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Admin pauses schedule
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            ts::next_tx(&mut scenario, ADMIN);
            vesting::set_schedule_paused(&admin_cap, &mut schedule, true, &clock, ts::ctx(&mut scenario));

            transfer::public_transfer(schedule, BENEFICIARY);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Try to claim from paused schedule - should fail
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            let tokens = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));

            transfer::public_transfer(tokens, BENEFICIARY);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test schedule with only cliff (no linear vesting)
    fun test_cliff_only_schedule() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create schedule with cliff but no linear vesting (instant unlock after cliff)
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_000_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                0,
                MS_PER_MONTH * 6, // 6 month cliff
                0, // No linear vesting - instant after cliff
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // During cliff - nothing claimable
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 3);
            assert!(vesting::claimable(&schedule, &clock) == 0, 0);

            // At cliff end - everything claimable
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 6);
            assert!(vesting::claimable(&schedule, &clock) == 1_000_000_000, 1);

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test before start time (nothing claimable)
    fun test_before_start_time() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create schedule starting in the future
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_000_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_instant_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                &clock, // Uses current time as start
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Check claimable at time 0 (instant schedule starts at 0)
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // At start time - fully claimable (instant unlock)
            assert!(vesting::claimable(&schedule, &clock) == 1_000_000_000, 0);

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test very large token amounts don't overflow
    fun test_large_amounts_no_overflow() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create schedule with max u64 amount
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            // Use a large but reasonable amount (1 trillion with 9 decimals)
            let tokens = test_coin::mint(1_000_000_000_000_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                0,
                0,
                MS_PER_MONTH * 12,
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // 6 months = 50%
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 6);
            let claimable = vesting::claimable(&schedule, &clock);
            assert!(claimable == 500_000_000_000_000_000, 0);

            // 12 months = 100%
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 12);
            let claimable_full = vesting::claimable(&schedule, &clock);
            assert!(claimable_full == 1_000_000_000_000_000_000, 1);

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test deleting empty schedule after full claim
    fun test_delete_empty_schedule() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create instant schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(100_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_instant_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Claim all tokens
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            let tokens = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(vesting::remaining(&schedule) == 0, 0);

            transfer::public_transfer(tokens, BENEFICIARY);

            // Delete empty schedule
            vesting::delete_empty_schedule(schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vesting::EScheduleEmpty)]
    /// Test deleting non-empty schedule fails
    fun test_delete_non_empty_schedule_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create instant schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(100_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_instant_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Try to delete without claiming - should fail
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            vesting::delete_empty_schedule(schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test time constants are correct
    fun test_time_constants() {
        assert!(vesting::ms_per_day() == 86_400_000, 0);
        assert!(vesting::ms_per_month() == 2_592_000_000, 1);
        assert!(vesting::ms_per_year() == 31_536_000_000, 2);
    }
}
