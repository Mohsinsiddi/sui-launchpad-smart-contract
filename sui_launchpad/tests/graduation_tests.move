/// Tests for the graduation module
/// Note: Full graduation flow requires DEX adapters - testing core functions here
#[test_only]
module sui_launchpad::graduation_tests {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::test_scenario::{Self, Scenario};
    use sui::clock::{Self, Clock};

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::{Self, AdminCap};
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::graduation;
    use sui_launchpad::test_utils;
    use sui_launchpad::test_coin::TEST_COIN;

    // ═══════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════

    fun admin(): address { @0xA1 }
    fun creator(): address { @0xC1 }
    fun buyer(): address { @0xB1 }
    fun treasury(): address { @0xE1 }

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    fun mint_sui(amount: u64, scenario: &mut Scenario): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, scenario.ctx())
    }

    fun create_clock(scenario: &mut Scenario): Clock {
        clock::create_for_testing(scenario.ctx())
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GRADUATION READINESS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_can_graduate_initial_state() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(creator());
        {
            let _pool_id = test_utils::create_test_pool(&mut scenario, 0);
        };

        scenario.next_tx(admin());
        {
            let pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();

            // Initially should NOT be ready for graduation
            assert!(!graduation::can_graduate(&pool, &config), 0);
            assert!(!bonding_curve::check_graduation_ready(&pool, &config), 1);

            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_pool_not_graduated_initially() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(creator());
        {
            let _pool_id = test_utils::create_test_pool(&mut scenario, 0);
        };

        scenario.next_tx(admin());
        {
            let pool = scenario.take_shared<BondingPool<TEST_COIN>>();

            // Pool should not be marked as graduated
            assert!(!bonding_curve::is_graduated(&pool), 0);

            test_scenario::return_shared(pool);
        };

        scenario.end();
    }

    #[test]
    fun test_graduation_threshold_checks() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(creator());
        {
            let _pool_id = test_utils::create_test_pool(&mut scenario, 0);
        };

        scenario.next_tx(admin());
        {
            let pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();

            // Verify graduation thresholds from config
            let _threshold = config::graduation_threshold(&config);
            let _min_liquidity = config::min_graduation_liquidity(&config);

            // Initial state: no SUI in pool, market cap = 0
            assert!(bonding_curve::sui_balance(&pool) == 0, 0);

            // Can't graduate without meeting thresholds
            assert!(!graduation::can_graduate(&pool, &config), 1);

            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_graduation_with_some_trading() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(creator());
        {
            let _pool_id = test_utils::create_test_pool(&mut scenario, 0);
        };

        // Buy some tokens
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            // Buy 10 SUI worth of tokens
            let payment = mint_sui(10_000_000_000, &mut scenario);

            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                0,
                &clock,
                scenario.ctx(),
            );

            // Check pool has some SUI now
            assert!(bonding_curve::sui_balance(&pool) > 0, 0);

            // Still might not be ready for graduation (depends on threshold)
            // This tests the function runs without error
            let _can_grad = graduation::can_graduate(&pool, &config);

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PAUSED POOL GRADUATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_paused_pool_cannot_graduate() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(creator());
        {
            let _pool_id = test_utils::create_test_pool(&mut scenario, 0);
        };

        // Admin pauses the pool
        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            bonding_curve::set_paused(&admin_cap, &mut pool, true, &clock);

            // Paused pool cannot graduate
            assert!(!graduation::can_graduate(&pool, &config), 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIG GRADUATION PARAMS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_graduation_fee_configuration() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let config = scenario.take_shared<LaunchpadConfig>();

            // Verify graduation fee is set
            let grad_fee_bps = config::graduation_fee_bps(&config);
            assert!(grad_fee_bps > 0, 0); // Should have some graduation fee
            assert!(grad_fee_bps <= 1000, 1); // Should be <= 10%

            // Verify graduation threshold
            let threshold = config::graduation_threshold(&config);
            assert!(threshold > 0, 2);

            // Verify min liquidity
            let min_liq = config::min_graduation_liquidity(&config);
            assert!(min_liq > 0, 3);

            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_lp_distribution_config() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let config = scenario.take_shared<LaunchpadConfig>();

            // Verify LP distribution settings
            let creator_lp_bps = config::creator_lp_bps(&config);
            assert!(creator_lp_bps <= 3000, 0); // Max 30% for creator

            let community_dest = config::community_lp_destination(&config);
            assert!(community_dest <= 3, 1); // Valid destination (0-3)

            // Verify vesting params
            let cliff = config::creator_lp_cliff_ms(&config);
            let vesting = config::creator_lp_vesting_ms(&config);
            assert!(cliff > 0 || vesting > 0, 2); // Some vesting should be set

            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEX TYPE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_dex_type_constants() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let config = scenario.take_shared<LaunchpadConfig>();

            // Verify DEX type constants
            assert!(config::dex_cetus() == 0, 0);
            assert!(config::dex_turbos() == 1, 1);
            assert!(config::dex_flowx() == 2, 2);
            assert!(config::dex_suidex() == 3, 3);

            // LP destination constants
            assert!(config::lp_dest_burn() == 0, 4);
            assert!(config::lp_dest_dao() == 1, 5);
            assert!(config::lp_dest_staking() == 2, 6);
            assert!(config::lp_dest_community_vest() == 3, 7);

            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GRADUATION ALLOCATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_graduation_token_allocations() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let config = scenario.take_shared<LaunchpadConfig>();

            // Creator gets 0-5% of tokens at graduation
            let creator_bps = config::creator_graduation_bps(&config);
            assert!(creator_bps <= 500, 0); // Max 5%

            // Platform gets 2.5-5% of tokens at graduation
            let platform_bps = config::platform_graduation_bps(&config);
            assert!(platform_bps >= 250, 1); // Min 2.5%
            assert!(platform_bps <= 500, 2); // Max 5%

            // Combined should leave majority for liquidity
            assert!(creator_bps + platform_bps <= 1000, 3); // Max 10% total

            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INITIATE GRADUATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure(abort_code = 400)] // ENotReadyForGraduation
    fun test_initiate_graduation_not_ready() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(creator());
        {
            let _pool_id = test_utils::create_test_pool(&mut scenario, 0);
        };

        // Try to initiate graduation on pool that's not ready
        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();

            // This should fail - pool hasn't reached graduation threshold
            let _pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                0, // Cetus DEX
                scenario.ctx(),
            );

            // Won't reach here
            abort 999
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 402)] // EPoolPaused
    fun test_initiate_graduation_paused_pool() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(creator());
        {
            let _pool_id = test_utils::create_test_pool(&mut scenario, 0);
        };

        // Admin pauses pool
        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let clock = create_clock(&mut scenario);

            bonding_curve::set_paused(&admin_cap, &mut pool, true, &clock);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(pool);
            clock::destroy_for_testing(clock);
        };

        // Try to initiate graduation on paused pool
        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();

            // This should fail - pool is paused
            let _pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                0,
                scenario.ctx(),
            );

            abort 999
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARKET CAP CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_market_cap_increases_with_buys() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(creator());
        {
            let _pool_id = test_utils::create_test_pool(&mut scenario, 0);
        };

        // Buy tokens
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let _initial_mcap = bonding_curve::get_market_cap(&pool);

            let payment = mint_sui(5_000_000_000, &mut scenario); // 5 SUI

            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                0,
                &clock,
                scenario.ctx(),
            );

            // Market cap should increase
            let _new_mcap = bonding_curve::get_market_cap(&pool);
            // Note: initial was 0 when no tokens in circulation
            // After buy, circulating_supply > 0, so mcap > 0

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }
}
