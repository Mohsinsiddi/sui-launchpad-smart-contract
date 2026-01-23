/// Comprehensive tests for graduation vesting integration
/// Tests LP token distribution: Creator (vested), Protocol (direct), DAO (direct)
/// Tests Position NFT vesting for CLMM DEXes
#[test_only]
module sui_launchpad::graduation_vesting_tests {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::{Self, AdminCap};
    use sui_launchpad::graduation;
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::registry::{Self, Registry};
    use sui_launchpad::math;
    use sui_launchpad::test_utils;
    use sui_launchpad::test_coin::{Self, TEST_COIN};

    // Import vesting modules
    use sui_vesting::vesting::{Self, VestingConfig, VestingSchedule};
    use sui_vesting::nft_vesting::{Self, NFTVestingSchedule};
    use sui_vesting::access::CreatorCap;

    // ═══════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════

    const ADMIN: address = @0xA1;
    const CREATOR: address = @0xC1;
    const BUYER: address = @0xB1;
    const TREASURY: address = @0xE1;
    const DAO_TREASURY: address = @0xDA0;
    const BURN_ADDRESS: address = @0x0;

    // ═══════════════════════════════════════════════════════════════════════
    // TIME CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    const MS_PER_DAY: u64 = 86_400_000;
    const MS_PER_MONTH: u64 = 2_592_000_000; // 30 days
    const MS_PER_YEAR: u64 = 31_536_000_000;

    // ═══════════════════════════════════════════════════════════════════════
    // LP TOKEN SIMULATION - For testing split and vesting
    // ═══════════════════════════════════════════════════════════════════════

    /// Simulated LP token (like SuiDex LP)
    public struct LP_TOKEN has drop {}

    /// Simulated Position NFT (like Cetus/FlowX Position)
    public struct PositionNFT has key, store {
        id: UID,
        liquidity: u128,
        tick_lower: u32,
        tick_upper: u32,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    fun setup_test(): Scenario {
        let mut scenario = ts::begin(ADMIN);
        {
            // Setup launchpad
            test_utils::setup_launchpad(&mut scenario);
        };
        scenario
    }

    fun setup_vesting_config(scenario: &mut Scenario) {
        ts::next_tx(scenario, ADMIN);
        {
            vesting::init_for_testing(ts::ctx(scenario));
        };
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

    fun mint_sui(amount: u64, scenario: &mut Scenario): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ts::ctx(scenario))
    }

    /// Mint LP tokens for testing (simulates DEX LP token minting)
    fun mint_lp_tokens(amount: u64, scenario: &mut Scenario): Coin<TEST_COIN> {
        // Using TEST_COIN as LP token for testing
        // In real scenario, this would be the actual LP token type from the DEX
        sui_launchpad::test_coin::mint(amount, ts::ctx(scenario))
    }

    /// Create a simulated Position NFT (like Cetus/FlowX position)
    fun create_position_nft(
        liquidity: u128,
        tick_lower: u32,
        tick_upper: u32,
        ctx: &mut TxContext
    ): PositionNFT {
        PositionNFT {
            id: object::new(ctx),
            liquidity,
            tick_lower,
            tick_upper,
        }
    }

    fun destroy_position_nft(nft: PositionNFT) {
        let PositionNFT { id, liquidity: _, tick_lower: _, tick_upper: _ } = nft;
        object::delete(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LP DISTRIBUTION SPLIT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test LP token split calculation: Creator 2.5% + Protocol 2.5% + DAO 95%
    fun test_lp_split_percentages() {
        let mut scenario = setup_test();

        // Create a pool that reaches graduation threshold
        ts::next_tx(&mut scenario, CREATOR);
        {
            let _pool_id = test_utils::create_test_pool(&mut scenario, 0);
        };

        // Simulate graduation with LP tokens
        ts::next_tx(&mut scenario, ADMIN);
        {
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Verify default LP distribution percentages
            let creator_bps = config::creator_lp_bps(&config);
            let protocol_bps = config::protocol_lp_bps(&config);
            let dao_bps = config::dao_lp_bps(&config);

            // Default: Creator 2.5% (250 bps) + Protocol 2.5% (250 bps) + DAO 95% (9500 bps)
            assert!(creator_bps == 250, 100);
            assert!(protocol_bps == 250, 101);
            assert!(dao_bps == 9500, 102);
            assert!(creator_bps + protocol_bps + dao_bps == 10000, 103);

            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    /// Test LP token split with actual coin amounts
    fun test_lp_split_amounts() {
        let mut scenario = setup_test();

        // Create pool and simulate graduation
        ts::next_tx(&mut scenario, CREATOR);
        {
            let _pool_id = test_utils::create_test_pool(&mut scenario, 0);
        };

        // Test LP split calculation
        ts::next_tx(&mut scenario, ADMIN);
        {
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Simulate 1,000,000 LP tokens
            let total_lp = 1_000_000_000_000u64; // 1M with 6 decimals

            let creator_bps = config::creator_lp_bps(&config);
            let protocol_bps = config::protocol_lp_bps(&config);

            // Calculate expected amounts
            let creator_amount = math::bps(total_lp, creator_bps);
            let protocol_amount = math::bps(total_lp, protocol_bps);
            let dao_amount = total_lp - creator_amount - protocol_amount;

            // Verify amounts
            // Creator: 2.5% of 1M = 25,000
            assert!(creator_amount == 25_000_000_000, 200);
            // Protocol: 2.5% of 1M = 25,000
            assert!(protocol_amount == 25_000_000_000, 201);
            // DAO: 95% of 1M = 950,000
            assert!(dao_amount == 950_000_000_000, 202);
            // Total check
            assert!(creator_amount + protocol_amount + dao_amount == total_lp, 203);

            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CREATOR LP VESTING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test creator LP vesting configuration
    fun test_creator_lp_vesting_config() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Verify default vesting params
            let cliff_ms = config::creator_lp_cliff_ms(&config);
            let vesting_ms = config::creator_lp_vesting_ms(&config);

            // Default: 6 month cliff + 12 month linear vesting
            let expected_cliff = 6 * MS_PER_MONTH;
            let expected_vesting = 12 * MS_PER_MONTH;

            // Allow for slight differences in month calculation
            assert!(cliff_ms >= expected_cliff - MS_PER_DAY, 300);
            assert!(cliff_ms <= expected_cliff + MS_PER_DAY, 301);
            assert!(vesting_ms >= expected_vesting - MS_PER_DAY, 302);
            assert!(vesting_ms <= expected_vesting + MS_PER_DAY, 303);

            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    /// Test full creator LP vesting flow at graduation
    fun test_creator_lp_vesting_full_flow() {
        let mut scenario = setup_test();
        setup_vesting_config(&mut scenario);
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        let lp_amount = 25_000_000_000u64; // 2.5% of 1M LP tokens
        let cliff_ms = MS_PER_MONTH * 6;
        let vesting_ms = MS_PER_MONTH * 12;

        // Creator creates vesting schedule for their LP tokens (simulating graduation)
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut vesting_config = ts::take_shared<VestingConfig>(&scenario);
            let lp_tokens = mint_lp_tokens(lp_amount, &mut scenario);

            // Create vesting schedule (this is what happens at graduation)
            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut vesting_config,
                lp_tokens,
                CREATOR, // Creator is the beneficiary
                start_time,
                cliff_ms,
                vesting_ms,
                false, // Non-revocable (creator's LP should not be revocable)
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(vesting_config);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Verify schedule properties
        ts::next_tx(&mut scenario, CREATOR);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            assert!(vesting::beneficiary(&schedule) == CREATOR, 400);
            assert!(vesting::total_amount(&schedule) == lp_amount, 401);
            assert!(vesting::cliff_duration(&schedule) == cliff_ms, 402);
            assert!(vesting::vesting_duration(&schedule) == vesting_ms, 403);
            assert!(!vesting::is_revocable(&schedule), 404);

            ts::return_to_sender(&scenario, schedule);
        };

        // TEST 1: Cannot claim during cliff
        advance_clock(&mut clock, MS_PER_MONTH * 3); // 3 months into cliff

        ts::next_tx(&mut scenario, CREATOR);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            let claimable = vesting::claimable(&schedule, &clock);
            assert!(claimable == 0, 500); // Nothing claimable during cliff

            ts::return_to_sender(&scenario, schedule);
        };

        // TEST 2: Claim after cliff + partial vesting (7 months = 6 cliff + 1 vesting)
        advance_clock(&mut clock, MS_PER_MONTH * 4); // Now at 7 months

        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // 1/12 of vesting should be available
            let claimable = vesting::claimable(&schedule, &clock);
            let expected = lp_amount / 12;

            // Allow 1% tolerance for rounding
            assert!(claimable >= expected - expected / 100, 600);
            assert!(claimable <= expected + expected / 100, 601);

            // Claim
            let claimed = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(coin::value(&claimed) == claimable, 602);

            transfer::public_transfer(claimed, CREATOR);
            ts::return_to_sender(&scenario, schedule);
        };

        // TEST 3: Full claim after vesting complete (18 months)
        advance_clock(&mut clock, MS_PER_MONTH * 11); // Now at 18 months

        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            // Remaining should be fully claimable
            let claimable = vesting::claimable(&schedule, &clock);
            let remaining = vesting::remaining(&schedule);

            assert!(claimable == remaining, 700);

            let claimed = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(vesting::remaining(&schedule) == 0, 701);

            transfer::public_transfer(claimed, CREATOR);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PROTOCOL DIRECT DISTRIBUTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test protocol receives LP directly (no vesting)
    fun test_protocol_direct_lp_distribution() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Verify protocol treasury is set
            let protocol_treasury = config::treasury(&config);
            assert!(protocol_treasury == TREASURY, 800);

            // Verify protocol LP percentage
            let protocol_bps = config::protocol_lp_bps(&config);
            assert!(protocol_bps == 250, 801); // 2.5%

            ts::return_shared(config);
        };

        // Simulate protocol LP distribution (direct transfer)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let protocol_lp = mint_lp_tokens(25_000_000_000, &mut scenario); // 2.5% of 1M

            // Direct transfer to treasury (no vesting)
            transfer::public_transfer(protocol_lp, TREASURY);
        };

        // Verify treasury received LP
        ts::next_tx(&mut scenario, TREASURY);
        {
            let lp_tokens = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            assert!(coin::value(&lp_tokens) == 25_000_000_000, 802);
            ts::return_to_sender(&scenario, lp_tokens);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DAO DISTRIBUTION TESTS (Multiple destinations)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test DAO LP destination configurations
    fun test_dao_lp_destinations() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Verify DAO destination constants
            assert!(config::lp_dest_burn() == 0, 900);
            assert!(config::lp_dest_dao() == 1, 901);
            assert!(config::lp_dest_staking() == 2, 902);
            assert!(config::lp_dest_community_vest() == 3, 903);

            // Verify DAO LP percentage (remainder after creator + protocol)
            let dao_bps = config::dao_lp_bps(&config);
            assert!(dao_bps == 9500, 904); // 95%

            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    /// Test DAO LP burn destination
    fun test_dao_lp_burn_distribution() {
        let mut scenario = setup_test();

        // Simulate DAO LP burn
        ts::next_tx(&mut scenario, ADMIN);
        {
            let dao_lp = mint_lp_tokens(950_000_000_000, &mut scenario); // 95% of 1M

            // Burn = transfer to dead address (0x0)
            transfer::public_transfer(dao_lp, BURN_ADDRESS);
        };

        // Verify burn address received tokens (locked forever)
        ts::next_tx(&mut scenario, BURN_ADDRESS);
        {
            assert!(ts::has_most_recent_for_sender<Coin<TEST_COIN>>(&scenario), 1000);
        };

        ts::end(scenario);
    }

    #[test]
    /// Test DAO LP direct transfer to DAO treasury
    fun test_dao_lp_treasury_distribution() {
        let mut scenario = setup_test();

        // Simulate DAO LP direct transfer
        ts::next_tx(&mut scenario, ADMIN);
        {
            let dao_lp = mint_lp_tokens(950_000_000_000, &mut scenario);

            // Direct transfer to DAO treasury
            transfer::public_transfer(dao_lp, DAO_TREASURY);
        };

        // Verify DAO treasury received tokens
        ts::next_tx(&mut scenario, DAO_TREASURY);
        {
            let lp_tokens = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            assert!(coin::value(&lp_tokens) == 950_000_000_000, 1100);
            ts::return_to_sender(&scenario, lp_tokens);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POSITION NFT VESTING TESTS (for CLMM DEXes)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test Position NFT vesting for CLMM DEX graduation
    fun test_position_nft_vesting_lifecycle() {
        let mut scenario = setup_test();
        setup_vesting_config(&mut scenario);
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        let cliff_ms = MS_PER_MONTH * 6;

        // Creator vests their Position NFT at graduation
        ts::next_tx(&mut scenario, CREATOR);
        {
            let position = create_position_nft(
                1_000_000_000_000u128, // liquidity
                0, // tick_lower (min tick for full range)
                1000000,  // tick_upper (max tick for full range)
                ts::ctx(&mut scenario),
            );

            // Create NFT vesting schedule
            let creator_cap = nft_vesting::create_nft_schedule<PositionNFT>(
                position,
                CREATOR,
                start_time,
                cliff_ms,
                false, // Non-revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Verify NFT is locked
        ts::next_tx(&mut scenario, CREATOR);
        {
            let schedule = ts::take_from_sender<NFTVestingSchedule<PositionNFT>>(&scenario);

            assert!(nft_vesting::nft_beneficiary(&schedule) == CREATOR, 1200);
            assert!(nft_vesting::has_nft(&schedule), 1201);
            assert!(!nft_vesting::is_claimable(&schedule, &clock), 1202);

            ts::return_to_sender(&scenario, schedule);
        };

        // TEST 1: Cannot claim during cliff
        advance_clock(&mut clock, MS_PER_MONTH * 3);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let schedule = ts::take_from_sender<NFTVestingSchedule<PositionNFT>>(&scenario);
            assert!(!nft_vesting::is_claimable(&schedule, &clock), 1300);
            ts::return_to_sender(&scenario, schedule);
        };

        // TEST 2: Can claim after cliff
        advance_clock(&mut clock, MS_PER_MONTH * 4); // Now at 7 months

        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<PositionNFT>>(&scenario);

            assert!(nft_vesting::is_claimable(&schedule, &clock), 1400);

            // Claim the position
            let position = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));

            // Verify position properties
            assert!(position.liquidity == 1_000_000_000_000u128, 1401);

            destroy_position_nft(position);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test revocable Position NFT (edge case - unusual but supported)
    fun test_revocable_position_nft() {
        let mut scenario = setup_test();
        setup_vesting_config(&mut scenario);
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        // Create revocable position vesting
        ts::next_tx(&mut scenario, CREATOR);
        {
            let position = create_position_nft(
                500_000_000_000u128,
                0,
                1000000,
                ts::ctx(&mut scenario),
            );

            let creator_cap = nft_vesting::create_nft_schedule<PositionNFT>(
                position,
                CREATOR,
                start_time,
                MS_PER_MONTH * 6,
                true, // Revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Revoke during cliff
        advance_clock(&mut clock, MS_PER_MONTH * 2);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let creator_cap = ts::take_from_sender<CreatorCap>(&scenario);
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<PositionNFT>>(&scenario);

            // Revoke
            let position = nft_vesting::revoke_nft(
                &creator_cap,
                &mut schedule,
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(nft_vesting::nft_is_revoked(&schedule), 1500);

            destroy_position_nft(position);
            ts::return_to_sender(&scenario, schedule);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FULL GRADUATION FLOW WITH VESTING (SIMULATED)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Simulate complete graduation flow with vesting integration
    /// This tests the conceptual flow that would happen in a real PTB
    fun test_full_graduation_vesting_flow_simulated() {
        let mut scenario = setup_test();
        setup_vesting_config(&mut scenario);
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        let total_lp = 1_000_000_000_000u64; // Total LP from DEX

        // Simulate graduation LP distribution
        ts::next_tx(&mut scenario, ADMIN);
        {
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Calculate splits
            let creator_bps = config::creator_lp_bps(&config);
            let protocol_bps = config::protocol_lp_bps(&config);

            let creator_lp = math::bps(total_lp, creator_bps);
            let protocol_lp = math::bps(total_lp, protocol_bps);
            let dao_lp = total_lp - creator_lp - protocol_lp;

            // Verify split
            assert!(creator_lp == 25_000_000_000, 1600); // 2.5%
            assert!(protocol_lp == 25_000_000_000, 1601); // 2.5%
            assert!(dao_lp == 950_000_000_000, 1602); // 95%

            ts::return_shared(config);
        };

        // Step 1: Create vested LP for creator
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut vesting_config = ts::take_shared<VestingConfig>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let creator_lp_tokens = mint_lp_tokens(25_000_000_000, &mut scenario);

            let cliff_ms = config::creator_lp_cliff_ms(&config);
            let vesting_ms = config::creator_lp_vesting_ms(&config);

            let creator_cap = vesting::create_schedule<TEST_COIN>(
                &mut vesting_config,
                creator_lp_tokens,
                CREATOR,
                start_time,
                cliff_ms,
                vesting_ms,
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(vesting_config);
            ts::return_shared(config);
            // Transfer cap to admin (or burn)
            transfer::public_transfer(creator_cap, ADMIN);
        };

        // Step 2: Direct transfer protocol LP
        ts::next_tx(&mut scenario, ADMIN);
        {
            let protocol_lp_tokens = mint_lp_tokens(25_000_000_000, &mut scenario);
            transfer::public_transfer(protocol_lp_tokens, TREASURY);
        };

        // Step 3: Direct transfer DAO LP (or burn)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let dao_lp_tokens = mint_lp_tokens(950_000_000_000, &mut scenario);
            transfer::public_transfer(dao_lp_tokens, DAO_TREASURY);
        };

        // Verify final state

        // Creator has vesting schedule
        ts::next_tx(&mut scenario, CREATOR);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            assert!(vesting::total_amount(&schedule) == 25_000_000_000, 1700);
            ts::return_to_sender(&scenario, schedule);
        };

        // Protocol treasury has LP directly
        ts::next_tx(&mut scenario, TREASURY);
        {
            let lp = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            assert!(coin::value(&lp) == 25_000_000_000, 1701);
            ts::return_to_sender(&scenario, lp);
        };

        // DAO treasury has LP directly
        ts::next_tx(&mut scenario, DAO_TREASURY);
        {
            let lp = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            assert!(coin::value(&lp) == 950_000_000_000, 1702);
            ts::return_to_sender(&scenario, lp);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIG UPDATE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test admin can update LP distribution percentages
    fun test_admin_update_lp_bps() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Update creator LP to 5%
            config::set_creator_lp_bps(&admin_cap, &mut config, 500);
            assert!(config::creator_lp_bps(&config) == 500, 1800);

            // DAO should now be 92.5% (10000 - 500 - 250)
            assert!(config::dao_lp_bps(&config) == 9250, 1801);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    /// Test admin can update creator vesting params
    fun test_admin_update_creator_vesting() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Update to 3 month cliff + 6 month vesting
            let new_cliff = MS_PER_MONTH * 3;
            let new_vesting = MS_PER_MONTH * 6;

            config::set_creator_lp_vesting(&admin_cap, &mut config, new_cliff, new_vesting);

            assert!(config::creator_lp_cliff_ms(&config) == new_cliff, 1900);
            assert!(config::creator_lp_vesting_ms(&config) == new_vesting, 1901);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    /// Test admin can update DAO LP destination
    fun test_admin_update_dao_destination() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Change from burn (0) to DAO treasury (1)
            config::set_dao_lp_destination(&admin_cap, &mut config, 1);
            assert!(config::dao_lp_destination(&config) == 1, 2000);

            // Change to staking (2)
            config::set_dao_lp_destination(&admin_cap, &mut config, 2);
            assert!(config::dao_lp_destination(&config) == 2, 2001);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test multiple creators with parallel vesting schedules
    fun test_multiple_creators_parallel_vesting() {
        let mut scenario = setup_test();
        setup_vesting_config(&mut scenario);
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        let creator2: address = @0xC2;
        let creator3: address = @0xC3;

        // Create 3 vesting schedules for 3 different creators
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut vesting_config = ts::take_shared<VestingConfig>(&scenario);

            // Creator 1: 6 month cliff + 12 month vesting
            let lp1 = mint_lp_tokens(10_000_000_000, &mut scenario);
            let cap1 = vesting::create_schedule<TEST_COIN>(
                &mut vesting_config,
                lp1,
                CREATOR,
                start_time,
                MS_PER_MONTH * 6,
                MS_PER_MONTH * 12,
                false,
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_transfer(cap1, ADMIN);

            // Creator 2: 3 month cliff + 6 month vesting
            let lp2 = mint_lp_tokens(15_000_000_000, &mut scenario);
            let cap2 = vesting::create_schedule<TEST_COIN>(
                &mut vesting_config,
                lp2,
                creator2,
                start_time,
                MS_PER_MONTH * 3,
                MS_PER_MONTH * 6,
                false,
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_transfer(cap2, ADMIN);

            // Creator 3: 1 month cliff + 3 month vesting
            let lp3 = mint_lp_tokens(20_000_000_000, &mut scenario);
            let cap3 = vesting::create_schedule<TEST_COIN>(
                &mut vesting_config,
                lp3,
                creator3,
                start_time,
                MS_PER_MONTH * 1,
                MS_PER_MONTH * 3,
                false,
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_transfer(cap3, ADMIN);

            assert!(vesting::config_total_schedules(&vesting_config) == 3, 2100);

            ts::return_shared(vesting_config);
        };

        // After 4 months: Creator 3 should be fully vested, Creator 2 partially, Creator 1 in cliff
        advance_clock(&mut clock, MS_PER_MONTH * 4);

        // Creator 3: Fully vested (1 month cliff + 3 months vesting = 4 months total)
        ts::next_tx(&mut scenario, creator3);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            let claimable = vesting::claimable(&schedule, &clock);
            assert!(claimable == 20_000_000_000, 2200); // All tokens claimable

            let claimed = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            transfer::public_transfer(claimed, creator3);
            ts::return_to_sender(&scenario, schedule);
        };

        // Creator 2: Partially vested (3 month cliff + 1 month into vesting = ~16.6%)
        ts::next_tx(&mut scenario, creator2);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            let claimable = vesting::claimable(&schedule, &clock);
            // 1/6 of vesting complete
            let expected = 15_000_000_000 / 6;
            assert!(claimable >= expected - expected / 10, 2300);

            let claimed = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            transfer::public_transfer(claimed, creator2);
            ts::return_to_sender(&scenario, schedule);
        };

        // Creator 1: Still in cliff (4 months < 6 month cliff)
        ts::next_tx(&mut scenario, CREATOR);
        {
            let schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            let claimable = vesting::claimable(&schedule, &clock);
            assert!(claimable == 0, 2400); // Nothing claimable
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test instant vesting (no cliff, no vesting period) for special cases
    fun test_instant_lp_vesting() {
        let mut scenario = setup_test();
        setup_vesting_config(&mut scenario);
        let mut clock = create_clock(&mut scenario, MS_PER_DAY);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut vesting_config = ts::take_shared<VestingConfig>(&scenario);
            let lp_tokens = mint_lp_tokens(100_000_000_000, &mut scenario);

            // Instant schedule (no cliff, no vesting)
            let creator_cap = vesting::create_instant_schedule<TEST_COIN>(
                &mut vesting_config,
                lp_tokens,
                CREATOR,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(vesting_config);
            transfer::public_transfer(creator_cap, ADMIN);
        };

        // Should be immediately claimable
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);

            let claimable = vesting::claimable(&schedule, &clock);
            assert!(claimable == 100_000_000_000, 2500);

            let claimed = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(coin::value(&claimed) == 100_000_000_000, 2501);

            transfer::public_transfer(claimed, CREATOR);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLMM POSITION NFT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Test CLMM position NFT cannot be claimed during cliff
    #[expected_failure(abort_code = nft_vesting::ECliffNotEnded)]
    fun test_position_nft_cannot_claim_during_cliff() {
        let mut scenario = setup_test();
        setup_vesting_config(&mut scenario);
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        // Create vested position
        ts::next_tx(&mut scenario, CREATOR);
        {
            let position = create_position_nft(
                1_000_000_000_000u128,
                0,
                1000000,
                ts::ctx(&mut scenario),
            );

            let creator_cap = nft_vesting::create_nft_schedule<PositionNFT>(
                position,
                CREATOR,
                start_time,
                MS_PER_MONTH * 6,
                false,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, CREATOR);
        };

        // Try to claim during cliff (3 months)
        advance_clock(&mut clock, MS_PER_MONTH * 3);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<PositionNFT>>(&scenario);

            // This should fail
            let position = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));

            destroy_position_nft(position);
            ts::return_to_sender(&scenario, schedule);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    /// Test CLMM position NFT revoke fails after cliff
    #[expected_failure(abort_code = nft_vesting::ENotRevocable)]
    fun test_position_nft_revoke_after_cliff_fails() {
        let mut scenario = setup_test();
        setup_vesting_config(&mut scenario);
        let start_time = MS_PER_DAY;
        let mut clock = create_clock(&mut scenario, start_time);

        // Create revocable position vesting
        ts::next_tx(&mut scenario, CREATOR);
        {
            let position = create_position_nft(
                500_000_000_000u128,
                0,
                1000000,
                ts::ctx(&mut scenario),
            );

            let creator_cap = nft_vesting::create_nft_schedule<PositionNFT>(
                position,
                CREATOR,
                start_time,
                MS_PER_MONTH * 6,
                true, // Revocable
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
            let mut schedule = ts::take_from_sender<NFTVestingSchedule<PositionNFT>>(&scenario);

            // This should fail - NFT is claimable after cliff
            let position = nft_vesting::revoke_nft(
                &creator_cap,
                &mut schedule,
                &clock,
                ts::ctx(&mut scenario),
            );

            destroy_position_nft(position);
            ts::return_to_sender(&scenario, schedule);
            transfer::public_transfer(creator_cap, CREATOR);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}
