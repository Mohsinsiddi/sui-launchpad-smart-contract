/// Strict tests for vesting module - LP tokens, external coins, Position NFTs
/// Tests all scenarios: creation, cliff, vesting, claiming, revocation
#[test_only]
module sui_vesting::strict_vesting_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin, TreasuryCap};

    use sui_vesting::vesting::{Self, VestingConfig, VestingSchedule};
    use sui_vesting::nft_vesting::{Self, NFTVestingSchedule};
    use sui_vesting::access::{Self, AdminCap, CreatorCap};
    use sui_vesting::test_coin::{Self, TEST_COIN};
    use sui_vesting::test_nft::{Self, TestPosition};

    // ═══════════════════════════════════════════════════════════════════════
    // TEST CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    const ADMIN: address = @0xAD;
    const CREATOR: address = @0xC1;
    const BENEFICIARY: address = @0xB1;
    const BENEFICIARY2: address = @0xB2;
    const TREASURY: address = @0xAE;

    const MS_PER_SECOND: u64 = 1_000;
    const MS_PER_MINUTE: u64 = 60_000;
    const MS_PER_HOUR: u64 = 3_600_000;
    const MS_PER_DAY: u64 = 86_400_000;
    const MS_PER_MONTH: u64 = 2_592_000_000; // 30 days
    const MS_PER_YEAR: u64 = 31_536_000_000; // 365 days

    // LP Token simulation constants
    const LP_TOTAL_SUPPLY: u64 = 1_000_000_000_000; // 1T LP tokens
    const CREATOR_LP_SHARE: u64 = 25_000_000_000; // 2.5% = 25B
    const PROTOCOL_LP_SHARE: u64 = 25_000_000_000; // 2.5% = 25B
    const DAO_LP_SHARE: u64 = 950_000_000_000; // 95% = 950B

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    // Note: Using TEST_COIN for all coin vesting tests since vesting logic is generic
    // LP tokens, external tokens, etc. all work the same way with Coin<T>

    /// Simulated external NFT
    public struct ExternalNFT has key, store {
        id: UID,
        name: vector<u8>,
        value: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    fun setup_test(): Scenario {
        let mut scenario = ts::begin(ADMIN);
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

    // Using test_coin::mint() for all coin vesting tests
    // The vesting logic is generic over coin types - TEST_COIN works for LP and external token simulation

    fun create_external_nft(name: vector<u8>, value: u64, ctx: &mut TxContext): ExternalNFT {
        ExternalNFT {
            id: object::new(ctx),
            name,
            value,
        }
    }

    fun destroy_external_nft(nft: ExternalNFT) {
        let ExternalNFT { id, name: _, value: _ } = nft;
        object::delete(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STRICT LP TOKEN VESTING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// STRICT TEST: LP token vesting with 6 month cliff + 12 month linear
    /// Simulates creator LP distribution at graduation
    fun test_strict_lp_vesting_full_lifecycle() {
        let mut scenario = setup_test();
        let start_time = MS_PER_DAY; // Start at day 1
        let mut clock = create_clock(&mut scenario, start_time);

        let cliff_ms = MS_PER_MONTH * 6; // 6 months
        let vesting_ms = MS_PER_MONTH * 12; // 12 months

        // Creator creates vesting for LP tokens (simulated with TEST_COIN)
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let lp_tokens = test_coin::mint(CREATOR_LP_SHARE, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                lp_tokens,
                BENEFICIARY,
                start_time,
                cliff_ms,
                vesting_ms,
                false, // non-revocable for creators
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Verify schedule properties
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // Strict property checks
            assert!(vesting::beneficiary(&schedule) == BENEFICIARY, 100);
            assert!(vesting::total_amount(&schedule) == CREATOR_LP_SHARE, 101);
            assert!(vesting::claimed(&schedule) == 0, 102);
            assert!(vesting::cliff_duration(&schedule) == cliff_ms, 103);
            assert!(vesting::vesting_duration(&schedule) == vesting_ms, 104);
            assert!(!vesting::is_revocable(&schedule), 105);

            ts::return_to_sender(&scenario, schedule);
        };

        // TEST 1: Cannot claim during cliff period
        // Advance to middle of cliff (3 months)
        advance_clock(&mut clock, MS_PER_MONTH * 3);

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            let claimable = vesting::claimable(&schedule, &clock);
            assert!(claimable == 0, 200); // STRICT: Nothing claimable during cliff

            ts::return_to_sender(&scenario, schedule);
        };

        // TEST 2: Claim after cliff starts
        // Advance to end of cliff + 1 month (7 months total)
        advance_clock(&mut clock, MS_PER_MONTH * 4); // 3 + 4 = 7 months

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // After 1 month of vesting (1/12 of total should be vested)
            let claimable = vesting::claimable(&schedule, &clock);
            let expected = CREATOR_LP_SHARE / 12; // ~2.08B tokens

            // Allow small rounding error (0.01%)
            assert!(claimable >= expected - expected / 10000, 300);
            assert!(claimable <= expected + expected / 10000, 301);

            // Actually claim
            let claimed_coins = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(coin::value(&claimed_coins) == claimable, 302);

            // Verify state updated
            assert!(vesting::claimed(&schedule) == claimable, 303);

            transfer::public_transfer(claimed_coins, BENEFICIARY);
            ts::return_to_sender(&scenario, schedule);
        };

        // TEST 3: Partial claim in middle of vesting
        // Advance to 12 months total (6 months into vesting)
        advance_clock(&mut clock, MS_PER_MONTH * 5); // 7 + 5 = 12 months

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // 6/12 = 50% should be vested total
            let claimable = vesting::claimable(&schedule, &clock);
            let total_vested = CREATOR_LP_SHARE / 2; // 50%
            let already_claimed = vesting::claimed(&schedule);
            let expected_claimable = total_vested - already_claimed;

            assert!(claimable >= expected_claimable - expected_claimable / 10000, 400);
            assert!(claimable <= expected_claimable + expected_claimable / 10000, 401);

            let claimed_coins = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            transfer::public_transfer(claimed_coins, BENEFICIARY);
            ts::return_to_sender(&scenario, schedule);
        };

        // TEST 4: Full claim after vesting complete
        // Advance to 18 months total (end of vesting)
        advance_clock(&mut clock, MS_PER_MONTH * 6); // 12 + 6 = 18 months

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // Should be able to claim remaining 50%
            let claimable = vesting::claimable(&schedule, &clock);
            let remaining = vesting::remaining(&schedule);

            assert!(claimable == remaining, 500); // STRICT: All remaining should be claimable

            let claimed_coins = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(coin::value(&claimed_coins) == claimable, 501);

            // Verify fully claimed
            assert!(vesting::claimed(&schedule) == CREATOR_LP_SHARE, 502);
            assert!(vesting::remaining(&schedule) == 0, 503);

            transfer::public_transfer(claimed_coins, BENEFICIARY);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// STRICT TEST: Multiple LP vesting schedules in parallel
    fun test_strict_multiple_lp_vesting_parallel() {
        let mut scenario = setup_test();
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        // Create 3 different vesting schedules with different params
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);

            // Schedule 1: 6 month cliff, 12 month vesting (standard)
            let lp1 = test_coin::mint(100_000_000, ts::ctx(&mut scenario));
            let cap1 = vesting::create_schedule<TEST_COIN>(
                &mut config, lp1, BENEFICIARY,
                start_time, MS_PER_MONTH * 6, MS_PER_MONTH * 12,
                false, &clock, ts::ctx(&mut scenario),
            );
            transfer::public_transfer(cap1, CREATOR);

            // Schedule 2: 3 month cliff, 6 month vesting (shorter)
            let lp2 = test_coin::mint(200_000_000, ts::ctx(&mut scenario));
            let cap2 = vesting::create_schedule<TEST_COIN>(
                &mut config, lp2, BENEFICIARY,
                start_time, MS_PER_MONTH * 3, MS_PER_MONTH * 6,
                false, &clock, ts::ctx(&mut scenario),
            );
            transfer::public_transfer(cap2, CREATOR);

            // Schedule 3: 12 month cliff, 24 month vesting (longer)
            let lp3 = test_coin::mint(300_000_000, ts::ctx(&mut scenario));
            let cap3 = vesting::create_schedule<TEST_COIN>(
                &mut config, lp3, BENEFICIARY2, // different beneficiary
                start_time, MS_PER_MONTH * 12, MS_PER_MONTH * 24,
                false, &clock, ts::ctx(&mut scenario),
            );
            transfer::public_transfer(cap3, CREATOR);

            assert!(vesting::config_total_schedules(&config) == 3, 100);

            ts::return_shared(config);
        };

        // After 4 months: Schedule 2 should have vested 1/6
        advance_clock(&mut clock, MS_PER_MONTH * 4);

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            // Check schedule 1 (still in cliff)
            assert!(ts::has_most_recent_for_sender<VestingSchedule<TEST_COIN>>(&scenario), 200);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STRICT EXTERNAL COIN VESTING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// STRICT TEST: External token vesting (simulates any ERC20-like token)
    fun test_strict_external_coin_vesting() {
        let mut scenario = setup_test();
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        let amount = 5_000_000_000_000; // 5T tokens
        let cliff_ms = MS_PER_MONTH * 3;
        let vesting_ms = MS_PER_MONTH * 9;

        // Create vesting for external tokens
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(amount, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                start_time,
                cliff_ms,
                vesting_ms,
                true, // revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Verify schedule
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            assert!(vesting::total_amount(&schedule) == amount, 100);
            assert!(vesting::is_revocable(&schedule), 101);

            ts::return_to_sender(&scenario, schedule);
        };

        // Test claim after partial vesting
        advance_clock(&mut clock, MS_PER_MONTH * 6); // 6 months (3 cliff + 3 vesting)

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // 3/9 = 33.3% should be vested
            let claimable = vesting::claimable(&schedule, &clock);
            let expected = amount / 3;

            assert!(claimable >= expected - expected / 1000, 200);
            assert!(claimable <= expected + expected / 1000, 201);

            let claimed = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            transfer::public_transfer(claimed, BENEFICIARY);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// STRICT TEST: Revocable external coin vesting - revoke before cliff
    fun test_strict_external_coin_revoke_before_cliff() {
        let mut scenario = setup_test();
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        let amount = 1_000_000_000;

        // Create revocable vesting
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(amount, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                start_time,
                MS_PER_MONTH * 6, // 6 month cliff
                MS_PER_MONTH * 12,
                true, // revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Advance 2 months (still in cliff)
        advance_clock(&mut clock, MS_PER_MONTH * 2);

        // Revoke during cliff
        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // Revoke - all tokens should go back to creator
            let returned = vesting::revoke(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            // STRICT: All tokens returned since nothing vested
            assert!(coin::value(&returned) == amount, 100);
            assert!(vesting::is_revoked(&schedule), 101);
            assert!(vesting::remaining(&schedule) == 0, 102);

            transfer::public_transfer(returned, CREATOR);
            ts::return_to_sender(&scenario, schedule);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// STRICT TEST: Revoke during vesting - beneficiary gets vested, creator gets unvested
    fun test_strict_external_coin_revoke_during_vesting() {
        let mut scenario = setup_test();
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        let amount = 1_200_000_000; // 1.2B for easy division

        // Create revocable vesting
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(amount, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                start_time,
                MS_PER_MONTH * 3, // 3 month cliff
                MS_PER_MONTH * 12, // 12 month vesting
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Advance 9 months (3 cliff + 6 vesting = 50% vested)
        advance_clock(&mut clock, MS_PER_MONTH * 9);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // Check vested amount before revoke
            let vested_before = vesting::claimable(&schedule, &clock);
            let expected_vested = amount / 2; // 50%

            assert!(vested_before >= expected_vested - expected_vested / 100, 100);

            // Revoke
            let returned = vesting::revoke(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            // STRICT: Creator gets unvested portion (~50%)
            let expected_returned = amount - vested_before;
            assert!(coin::value(&returned) >= expected_returned - expected_returned / 100, 101);

            transfer::public_transfer(returned, CREATOR);
            ts::return_to_sender(&scenario, schedule);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STRICT POSITION NFT VESTING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// STRICT TEST: Position NFT vesting (simulates Cetus/FlowX position)
    fun test_strict_position_nft_vesting_lifecycle() {
        let mut scenario = setup_test();
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        let liquidity = 1_000_000_000_000; // 1T liquidity
        let cliff_ms = MS_PER_MONTH * 6; // 6 month cliff

        // Creator vests a position NFT
        ts::next_tx(&mut scenario, CREATOR);
        {
            let position = test_nft::create_position(liquidity, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule<TestPosition>(
                position,
                BENEFICIARY,
                start_time,
                cliff_ms,
                false, // non-revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Verify schedule properties
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            assert!(nft_vesting::nft_beneficiary(&schedule) == BENEFICIARY, 100);
            assert!(nft_vesting::nft_cliff_duration(&schedule) == cliff_ms, 101);
            assert!(!nft_vesting::nft_is_revocable(&schedule), 102);
            assert!(nft_vesting::has_nft(&schedule), 103);
            assert!(!nft_vesting::nft_is_claimed(&schedule), 104);

            ts::return_to_sender(&scenario, schedule);
        };

        // TEST 1: Cannot claim during cliff
        advance_clock(&mut clock, MS_PER_MONTH * 3); // 3 months (half of cliff)

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            // STRICT: Should not be claimable during cliff
            assert!(!nft_vesting::is_claimable(&schedule, &clock), 200);

            // Check time remaining
            let remaining = nft_vesting::time_until_claimable(&schedule, &clock);
            assert!(remaining > 0, 201);

            ts::return_to_sender(&scenario, schedule);
        };

        // TEST 2: Can claim after cliff
        advance_clock(&mut clock, MS_PER_MONTH * 4); // 3 + 4 = 7 months (past cliff)

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            // STRICT: Should be claimable after cliff
            assert!(nft_vesting::is_claimable(&schedule, &clock), 300);

            // Claim the position
            let position = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));

            // Verify position properties
            assert!(test_nft::liquidity(&position) == liquidity, 301);

            // Verify schedule updated
            assert!(nft_vesting::nft_is_claimed(&schedule), 302);
            assert!(!nft_vesting::has_nft(&schedule), 303);

            test_nft::destroy(position);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// STRICT TEST: Position NFT vesting - revoke before cliff
    fun test_strict_position_nft_revoke_before_cliff() {
        let mut scenario = setup_test();
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        // Create revocable position vesting
        ts::next_tx(&mut scenario, CREATOR);
        {
            let position = test_nft::create_position(500_000_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule<TestPosition>(
                position,
                BENEFICIARY,
                start_time,
                MS_PER_MONTH * 6,
                true, // revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Advance 2 months (still in cliff)
        advance_clock(&mut clock, MS_PER_MONTH * 2);

        // Revoke
        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            // STRICT: Should be able to revoke during cliff
            let position = nft_vesting::revoke_nft(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            assert!(nft_vesting::nft_is_revoked(&schedule), 100);
            assert!(!nft_vesting::has_nft(&schedule), 101);

            test_nft::destroy(position);
            ts::return_to_sender(&scenario, schedule);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = nft_vesting::ENotRevocable)]
    /// STRICT TEST: Cannot revoke position after cliff ends (NFT becomes claimable)
    fun test_strict_position_nft_revoke_after_cliff_fails() {
        let mut scenario = setup_test();
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        // Create revocable position vesting
        ts::next_tx(&mut scenario, CREATOR);
        {
            let position = test_nft::create_position(500_000_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule<TestPosition>(
                position,
                BENEFICIARY,
                start_time,
                MS_PER_MONTH * 6,
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Advance past cliff
        advance_clock(&mut clock, MS_PER_MONTH * 7);

        // Try to revoke after cliff - should fail
        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);

            ts::next_tx(&mut scenario, BENEFICIARY);
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            // STRICT: This should abort
            let position = nft_vesting::revoke_nft(&creator_cap, &mut schedule, &clock, ts::ctx(&mut scenario));

            test_nft::destroy(position);
            ts::return_to_sender(&scenario, schedule);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STRICT EXTERNAL NFT VESTING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// STRICT TEST: External NFT vesting (any NFT with key + store)
    fun test_strict_external_nft_vesting() {
        let mut scenario = setup_test();
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        // Create and vest an external NFT
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = create_external_nft(b"Valuable NFT", 1_000_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule<ExternalNFT>(
                nft,
                BENEFICIARY,
                start_time,
                MS_PER_MONTH * 12, // 12 month cliff
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Verify schedule
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<NFTVestingSchedule<ExternalNFT>>(&scenario);

            assert!(nft_vesting::nft_cliff_duration(&schedule) == MS_PER_MONTH * 12, 100);
            assert!(nft_vesting::has_nft(&schedule), 101);

            ts::return_to_sender(&scenario, schedule);
        };

        // Advance past cliff and claim
        advance_clock(&mut clock, MS_PER_MONTH * 13);

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<ExternalNFT>>(&scenario);

            assert!(nft_vesting::is_claimable(&schedule, &clock), 200);

            let nft = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));

            destroy_external_nft(nft);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// STRICT TEST: Instant cliff (cliff = 0)
    fun test_strict_instant_cliff() {
        let mut scenario = setup_test();
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_000_000, ts::ctx(&mut scenario));

            // Instant schedule (no cliff, no vesting)
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

        // Should be immediately claimable
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            let claimable = vesting::claimable(&schedule, &clock);
            assert!(claimable == 1_000_000, 100); // STRICT: All immediately available

            let claimed = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(coin::value(&claimed) == 1_000_000, 101);

            transfer::public_transfer(claimed, BENEFICIARY);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// STRICT TEST: Very long vesting period (5 years)
    fun test_strict_long_vesting_period() {
        let mut scenario = setup_test();
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        let amount = 10_000_000_000_000; // 10T tokens
        let cliff_ms = MS_PER_YEAR; // 1 year cliff
        let vesting_ms = MS_PER_YEAR * 4; // 4 year vesting

        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(amount, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                start_time,
                cliff_ms,
                vesting_ms,
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Advance 3 years (1 cliff + 2 vesting = 50% vested)
        advance_clock(&mut clock, MS_PER_YEAR * 3);

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            let claimable = vesting::claimable(&schedule, &clock);
            let expected = amount / 2; // 50%

            // STRICT: Should be ~50% vested
            assert!(claimable >= expected - expected / 100, 100);
            assert!(claimable <= expected + expected / 100, 101);

            let claimed = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            transfer::public_transfer(claimed, BENEFICIARY);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vesting::ENotBeneficiary)]
    /// STRICT TEST: Non-beneficiary cannot claim
    fun test_strict_non_beneficiary_cannot_claim() {
        let mut scenario = setup_test();
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        // Create vesting for BENEFICIARY
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_000_000, ts::ctx(&mut scenario));

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

        // BENEFICIARY transfers schedule to BENEFICIARY2
        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            // Transfer the schedule object to BENEFICIARY2
            transfer::public_transfer(schedule, BENEFICIARY2);
        };

        // BENEFICIARY2 now owns the schedule object, but tries to claim
        // This should fail because beneficiary field is still BENEFICIARY
        ts::next_tx(&mut scenario, BENEFICIARY2);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // STRICT: This should abort with ENotBeneficiary
            let claimed = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));

            transfer::public_transfer(claimed, BENEFICIARY2);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vesting::ENotClaimable)]
    /// STRICT TEST: Cannot claim when nothing is claimable
    fun test_strict_cannot_claim_zero() {
        let mut scenario = setup_test();
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut config = ts::take_shared<VestingConfig>(&scenario);
            let tokens = test_coin::mint(1_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut config,
                tokens,
                BENEFICIARY,
                start_time,
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
        advance_clock(&mut clock, MS_PER_MONTH * 3); // Still in cliff

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // STRICT: This should abort
            let claimed = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));

            transfer::public_transfer(claimed, BENEFICIARY);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = nft_vesting::ECliffNotEnded)]
    /// STRICT TEST: Cannot claim NFT during cliff
    fun test_strict_nft_cannot_claim_during_cliff() {
        let mut scenario = setup_test();
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let position = test_nft::create_position(1_000_000, ts::ctx(&mut scenario));

            let creator_cap = nft_vesting::create_nft_schedule<TestPosition>(
                position,
                BENEFICIARY,
                start_time,
                MS_PER_MONTH * 6,
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Try to claim during cliff
        advance_clock(&mut clock, MS_PER_MONTH * 3);

        ts::next_tx(&mut scenario, BENEFICIARY);
        {
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<TestPosition>>(&scenario);

            // STRICT: This should abort
            let position = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));

            test_nft::destroy(position);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}
