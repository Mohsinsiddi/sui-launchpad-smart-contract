/// Comprehensive tests for the NFT vesting module
#[test_only]
module sui_vesting::nft_vesting_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};

    use sui_vesting::nft_vesting::{Self, NFTVestingSchedule};
    use sui_vesting::access::{Self, AdminCap, CreatorCap};
    use sui_vesting::test_nft::{Self, TestPosition};

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
        let scenario = ts::begin(ADMIN);
        // Note: NFT vesting doesn't require init like coin vesting
        // It uses standalone schedules
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
    // NFT SCHEDULE CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test basic NFT schedule creation with cliff
    fun test_create_nft_schedule_basic() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(1_000_000, ts::ctx(&mut scenario));
            let nft_id = object::id(&nft);

            let creator_cap = nft_vesting::create_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                1000, // start_time
                MS_PER_MONTH * 6, // 6 month cliff
                true, // revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Verify schedule was transferred to beneficiary
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            assert!(nft_vesting::nft_beneficiary(&schedule) == BENEFICIARY, 0);
            assert!(nft_vesting::nft_creator(&schedule) == CREATOR, 1);
            assert!(nft_vesting::nft_cliff_duration(&schedule) == MS_PER_MONTH * 6, 2);
            assert!(nft_vesting::nft_is_revocable(&schedule), 3);
            assert!(!nft_vesting::nft_is_revoked(&schedule), 4);
            assert!(!nft_vesting::nft_is_claimed(&schedule), 5);
            assert!(!nft_vesting::nft_is_paused(&schedule), 6);
            assert!(nft_vesting::has_nft(&schedule), 7);

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test creating NFT schedule with months convenience function
    fun test_create_nft_schedule_months() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(500_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule_months<TestPosition>(
                nft,
                BENEFICIARY,
                3, // 3 month cliff
                false, // non-revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            assert!(nft_vesting::nft_cliff_duration(&schedule) == MS_PER_MONTH * 3, 0);
            assert!(!nft_vesting::nft_is_revocable(&schedule), 1);

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test creating instant unlock NFT schedule (no cliff)
    fun test_create_instant_nft_schedule() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(100_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_instant_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            // Instant unlock = no cliff
            assert!(nft_vesting::nft_cliff_duration(&schedule) == 0, 0);
            assert!(!nft_vesting::nft_is_revocable(&schedule), 1);

            // Should be claimable immediately
            assert!(nft_vesting::is_claimable(&schedule, &clock), 2);

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = nft_vesting::EInvalidBeneficiary)]
    /// Test that zero address beneficiary fails
    fun test_create_nft_schedule_zero_beneficiary_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(100_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule<TestPosition>(
                nft,
                @0x0, // Zero address - should fail
                1000,
                0,
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            access::destroy_creator_cap(creator_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NFT CLAIMING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test claiming NFT from instant unlock schedule
    fun test_claim_nft_instant_unlock() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(100_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_instant_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Claim immediately
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            let claimed_nft = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(test_nft::liquidity(&claimed_nft) == 100_000, 0);

            assert!(nft_vesting::nft_is_claimed(&schedule), 1);
            assert!(!nft_vesting::has_nft(&schedule), 2);

            test_nft::destroy(claimed_nft);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test NFT not claimable during cliff period
    fun test_nft_not_claimable_during_cliff() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create schedule with 6 month cliff
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(1_000_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                0, // start_time
                MS_PER_MONTH * 6, // 6 month cliff
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Check claimable during cliff
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            // At start - not claimable
            assert!(!nft_vesting::is_claimable(&schedule, &clock), 0);
            assert!(nft_vesting::time_until_claimable(&schedule, &clock) == MS_PER_MONTH * 6, 1);

            // 3 months in (still in cliff)
            advance_clock(&mut clock, MS_PER_MONTH * 3);
            assert!(!nft_vesting::is_claimable(&schedule, &clock), 2);
            assert!(nft_vesting::time_until_claimable(&schedule, &clock) == MS_PER_MONTH * 3, 3);

            // 5 months 29 days in (still in cliff)
            advance_clock(&mut clock, MS_PER_MONTH * 2 + MS_PER_DAY * 29);
            assert!(!nft_vesting::is_claimable(&schedule, &clock), 4);

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test NFT claimable after cliff ends
    fun test_nft_claimable_after_cliff() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create schedule with 6 month cliff
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(1_000_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                0,
                MS_PER_MONTH * 6,
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Claim after cliff
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            // Advance past cliff
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 6);

            assert!(nft_vesting::is_claimable(&schedule, &clock), 0);
            assert!(nft_vesting::time_until_claimable(&schedule, &clock) == 0, 1);

            // Claim
            let claimed_nft = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(test_nft::liquidity(&claimed_nft) == 1_000_000, 2);

            test_nft::destroy(claimed_nft);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = nft_vesting::ENotBeneficiary)]
    /// Test that non-beneficiary cannot claim NFT
    fun test_claim_nft_non_beneficiary_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create instant schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(100_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_instant_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Transfer schedule to attacker and try to claim
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);
            transfer::public_transfer(schedule, @0xA77AC);
        };

        ts::next_tx(&mut scenario, @0xA77AC);
        {
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);
            // This should fail - attacker is not the beneficiary
            let nft = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));
            test_nft::destroy(nft);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = nft_vesting::ECliffNotEnded)]
    /// Test claiming during cliff fails
    fun test_claim_nft_during_cliff_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create schedule with cliff
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(100_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                0,
                MS_PER_MONTH * 6, // 6 month cliff
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Try to claim during cliff - should fail
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);
            clock::set_for_testing(&mut clock, MS_PER_MONTH * 3); // Still in cliff

            let nft = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));
            test_nft::destroy(nft);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = nft_vesting::EAlreadyClaimed)]
    /// Test double claim fails
    fun test_double_claim_nft_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create instant schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(100_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_instant_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // First claim - succeeds
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            let nft = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));
            test_nft::destroy(nft);

            ts::return_to_sender(&scenario, schedule);
        };

        // Second claim - should fail
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            let nft = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));
            test_nft::destroy(nft);

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NFT REVOCATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test revoking an NFT schedule before cliff ends
    fun test_revoke_nft_before_cliff() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create revocable schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(1_000_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                0,
                MS_PER_MONTH * 6,
                true, // revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Revoke during cliff
        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            clock::set_for_testing(&mut clock, MS_PER_MONTH * 3); // 3 months in

            ts::next_tx(&mut scenario, CREATOR);
            let revoked_nft = nft_vesting::revoke_nft(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            // NFT should return to creator
            assert!(test_nft::liquidity(&revoked_nft) == 1_000_000, 0);
            assert!(nft_vesting::nft_is_revoked(&schedule), 1);
            assert!(!nft_vesting::has_nft(&schedule), 2);

            test_nft::destroy(revoked_nft);
            transfer::public_transfer(schedule, BENEFICIARY);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = nft_vesting::ENotRevocable)]
    /// Test revoking after cliff ends fails (beneficiary owns it after cliff)
    fun test_revoke_nft_after_cliff_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create revocable schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(1_000_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                0,
                MS_PER_MONTH * 6,
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Try to revoke after cliff - should fail
        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            clock::set_for_testing(&mut clock, MS_PER_MONTH * 7); // After cliff

            ts::next_tx(&mut scenario, CREATOR);
            let revoked_nft = nft_vesting::revoke_nft(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            test_nft::destroy(revoked_nft);
            transfer::public_transfer(schedule, BENEFICIARY);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = nft_vesting::ENotRevocable)]
    /// Test that non-revocable schedule cannot be revoked
    fun test_revoke_non_revocable_nft_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create non-revocable schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(1_000_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                0,
                MS_PER_MONTH * 6,
                false, // NOT revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Try to revoke - should fail
        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            ts::next_tx(&mut scenario, CREATOR);
            let revoked_nft = nft_vesting::revoke_nft(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            test_nft::destroy(revoked_nft);
            transfer::public_transfer(schedule, BENEFICIARY);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = nft_vesting::ECreatorCapMismatch)]
    /// Test that wrong creator cap cannot revoke
    fun test_revoke_nft_wrong_cap_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create first schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft1 = test_nft::create_position(1_000_000, ts::ctx(&mut scenario));

            let creator_cap1 = nft_vesting::create_nft_schedule<TestPosition>(
                nft1,
                BENEFICIARY,
                0,
                MS_PER_MONTH * 6,
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            // Create second schedule
            let nft2 = test_nft::create_position(500_000, ts::ctx(&mut scenario));
            let creator_cap2 = nft_vesting::create_nft_schedule<TestPosition>(
                nft2,
                @0xB2,
                0,
                MS_PER_MONTH * 3,
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap1, CREATOR);
            transfer::public_transfer(creator_cap2, @0xC2);
        };

        // Try to use cap2 to revoke schedule1 - should fail
        ts::next_tx(&mut scenario, @0xC2);
        {
            let creator_cap2 = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule1 = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            ts::next_tx(&mut scenario, @0xC2);
            // Using cap2 for schedule1 - should fail
            let revoked_nft = nft_vesting::revoke_nft(&creator_cap2, &mut schedule1, &clock, ts::ctx(&mut scenario));

            test_nft::destroy(revoked_nft);
            transfer::public_transfer(schedule1, BENEFICIARY);
            transfer::public_transfer(creator_cap2, @0xC2);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = nft_vesting::EAlreadyRevoked)]
    /// Test double revocation fails
    fun test_double_revoke_nft_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create revocable schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(1_000_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                0,
                MS_PER_MONTH * 6,
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // First revoke - succeeds
        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            ts::next_tx(&mut scenario, CREATOR);
            let revoked_nft = nft_vesting::revoke_nft(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            test_nft::destroy(revoked_nft);
            transfer::public_transfer(schedule, BENEFICIARY);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Second revoke - should fail
        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            ts::next_tx(&mut scenario, CREATOR);
            let revoked_nft = nft_vesting::revoke_nft(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            test_nft::destroy(revoked_nft);
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
    /// Test admin can pause NFT schedule
    fun test_admin_pause_nft_schedule() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Initialize vesting platform to get admin cap
        ts::next_tx(&mut scenario, ADMIN);
        {
            sui_vesting::vesting::init_for_testing(ts::ctx(&mut scenario));
        };

        // Create instant schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(100_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_instant_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Admin pauses schedule
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            ts::next_tx(&mut scenario, ADMIN);
            nft_vesting::set_nft_schedule_paused(&admin_cap, &mut schedule, true, &clock, ts::ctx(&mut scenario));

            assert!(nft_vesting::nft_is_paused(&schedule), 0);
            assert!(!nft_vesting::is_claimable(&schedule, &clock), 1); // Not claimable when paused

            transfer::public_transfer(schedule, BENEFICIARY);
            ts::return_to_sender(&scenario, admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = nft_vesting::ESchedulePaused)]
    /// Test that paused schedule rejects claims
    fun test_paused_nft_schedule_rejects_claims() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Initialize vesting platform to get admin cap
        ts::next_tx(&mut scenario, ADMIN);
        {
            sui_vesting::vesting::init_for_testing(ts::ctx(&mut scenario));
        };

        // Create instant schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(100_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_instant_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Admin pauses schedule
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            ts::next_tx(&mut scenario, ADMIN);
            nft_vesting::set_nft_schedule_paused(&admin_cap, &mut schedule, true, &clock, ts::ctx(&mut scenario));

            transfer::public_transfer(schedule, BENEFICIARY);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Try to claim from paused schedule - should fail
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            let nft = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));

            test_nft::destroy(nft);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test NFT schedule with custom position ticks
    fun test_nft_schedule_with_custom_ticks() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position_with_ticks(
                500_000,
                50,   // tick_lower
                150,  // tick_upper
                ts::ctx(&mut scenario),
            );

            let creator_cap = nft_vesting::create_instant_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Claim and verify NFT properties
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            let claimed_nft = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(test_nft::liquidity(&claimed_nft) == 500_000, 0);

            test_nft::destroy(claimed_nft);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test time calculations before start time
    fun test_time_until_claimable_before_start() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create schedule starting in the future
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(100_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                MS_PER_MONTH * 1, // Starts in 1 month
                MS_PER_MONTH * 6, // 6 month cliff
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            // Time until claimable = (start - now) + cliff
            let time_until = nft_vesting::time_until_claimable(&schedule, &clock);
            assert!(time_until == MS_PER_MONTH * 7, 0); // 1 month until start + 6 month cliff

            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test deleting empty NFT schedule after claim
    fun test_delete_empty_nft_schedule() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create instant schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(100_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_instant_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Claim NFT and delete schedule
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            let nft = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(!nft_vesting::has_nft(&schedule), 0);

            test_nft::destroy(nft);

            // Delete empty schedule
            nft_vesting::delete_empty_nft_schedule(schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = nft_vesting::EZeroItems)]
    /// Test deleting non-empty NFT schedule fails
    fun test_delete_non_empty_nft_schedule_fails() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create instant schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = test_nft::create_position(100_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_instant_nft_schedule<TestPosition>(
                nft,
                BENEFICIARY,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Try to delete without claiming - should fail
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);
            nft_vesting::delete_empty_nft_schedule(schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test NFT vesting time constants
    fun test_nft_time_constants() {
        assert!(nft_vesting::nft_ms_per_day() == 86_400_000, 0);
        assert!(nft_vesting::nft_ms_per_month() == 2_592_000_000, 1);
    }
}
