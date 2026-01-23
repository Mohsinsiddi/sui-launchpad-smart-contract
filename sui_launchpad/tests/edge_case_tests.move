/// ═══════════════════════════════════════════════════════════════════════════════
/// EDGE CASE TESTS
/// ═══════════════════════════════════════════════════════════════════════════════
///
/// Tests for boundary conditions, all else-if branches, and edge cases
///
/// Coverage:
/// - Config parameter boundaries (min/max values)
/// - All conditional branches (admin destinations, LP destinations)
/// - Zero value handling
/// - Maximum value handling
/// - State transitions
/// - Hot potato pattern enforcement
///
#[test_only]
module sui_launchpad::edge_case_tests {
    use sui::test_scenario::{Self as ts};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::AdminCap;
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::graduation;
    use sui_launchpad::registry::{Self, Registry};
    use sui_launchpad::staking_integration;
    use sui_launchpad::dao_integration;
    use sui_launchpad::test_utils;
    use sui_launchpad::test_coin::TEST_COIN;

    // sui_staking imports
    use sui_staking::factory::{Self as staking_factory, StakingRegistry};
    use sui_staking::access::{AdminCap as StakingAdminCap};

    // sui_dao imports
    use sui_dao::registry::{Self as dao_registry, DAORegistry};
    use sui_dao::access::{AdminCap as DAOPlatformAdminCap};

    // SuiDex imports
    use suitrump_dex::pair::Pair;
    use suitrump_dex::router::{Self as suidex_router, Router};
    use suitrump_dex::factory::{Self as suidex_factory, Factory};

    // ═══════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════

    fun admin(): address { @0xA1 }
    fun creator(): address { @0xC1 }

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    fun setup_all(scenario: &mut ts::Scenario) {
        test_utils::setup_launchpad(scenario);

        ts::next_tx(scenario, admin());
        {
            suidex_factory::init_for_testing(ts::ctx(scenario));
            suidex_router::init_for_testing(ts::ctx(scenario));
            staking_factory::init_for_testing(ts::ctx(scenario));
            dao_registry::init_for_testing(ts::ctx(scenario));
        };
    }

    fun create_test_pool(scenario: &mut ts::Scenario): ID {
        use sui_launchpad::test_coin;

        ts::next_tx(scenario, creator());
        let pool_id;
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(ts::ctx(scenario));
            let launchpad_config = ts::take_shared<LaunchpadConfig>(scenario);
            let clock = clock::create_for_testing(ts::ctx(scenario));

            let creation_fee = config::creation_fee(&launchpad_config);
            let payment = coin::mint_for_testing<SUI>(creation_fee, ts::ctx(scenario));

            let pool = bonding_curve::create_pool(
                &launchpad_config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                ts::ctx(scenario),
            );

            pool_id = object::id(&pool);
            transfer::public_share_object(pool);
            ts::return_shared(launchpad_config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };
        pool_id
    }

    fun buy_to_graduation_threshold(scenario: &mut ts::Scenario) {
        ts::next_tx(scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(scenario);
            let launchpad_config = ts::take_shared<LaunchpadConfig>(scenario);
            let clock = clock::create_for_testing(ts::ctx(scenario));

            let threshold = config::graduation_threshold(&launchpad_config);
            let buy_amount = threshold + (threshold / 10);

            let payment = coin::mint_for_testing<SUI>(buy_amount, ts::ctx(scenario));
            let tokens = bonding_curve::buy(
                &mut pool,
                &launchpad_config,
                payment,
                0,
                &clock,
                ts::ctx(scenario),
            );

            transfer::public_transfer(tokens, admin());
            ts::return_shared(pool);
            ts::return_shared(launchpad_config);
            clock::destroy_for_testing(clock);
        };
    }

    fun create_dex_pair(scenario: &mut ts::Scenario) {
        ts::next_tx(scenario, admin());
        {
            let router = ts::take_shared<Router>(scenario);
            let mut factory = ts::take_shared<Factory>(scenario);
            suidex_router::create_pair<TEST_COIN, SUI>(
                &router, &mut factory,
                std::string::utf8(b"TEST"), std::string::utf8(b"SUI"),
                ts::ctx(scenario),
            );
            ts::return_shared(router);
            ts::return_shared(factory);
        };
    }

    fun create_clock(scenario: &mut ts::Scenario): Clock {
        clock::create_for_testing(ts::ctx(scenario))
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIG PARAMETER BOUNDARY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_min_staking_reward_bps() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Set to minimum (0%)
            config::set_staking_reward_bps(&admin_cap, &mut config, 0);
            assert!(config::staking_reward_bps(&config) == 0, 100);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_max_staking_reward_bps() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Set to maximum (10%)
            config::set_staking_reward_bps(&admin_cap, &mut config, 1000);
            assert!(config::staking_reward_bps(&config) == 1000, 100);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_staking_reward_bps_exceeds_max() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Try to set above maximum (should fail)
            config::set_staking_reward_bps(&admin_cap, &mut config, 1001);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_min_dao_quorum_bps() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Set to minimum (0.01% - minimum valid quorum)
            config::set_dao_quorum_bps(&admin_cap, &mut config, 1);
            assert!(config::dao_quorum_bps(&config) == 1, 100);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_max_dao_quorum_bps() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Set to maximum (50%)
            config::set_dao_quorum_bps(&admin_cap, &mut config, 5000);
            assert!(config::dao_quorum_bps(&config) == 5000, 100);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_dao_quorum_exceeds_max() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Try to set above 50% (should fail)
            config::set_dao_quorum_bps(&admin_cap, &mut config, 5001);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VOTING PERIOD BOUNDARY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_min_voting_delay() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Set to minimum (1 hour)
            config::set_dao_voting_delay_ms(&admin_cap, &mut config, 3_600_000);
            assert!(config::dao_voting_delay_ms(&config) == 3_600_000, 100);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_max_voting_delay() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Set to maximum (7 days)
            config::set_dao_voting_delay_ms(&admin_cap, &mut config, 604_800_000);
            assert!(config::dao_voting_delay_ms(&config) == 604_800_000, 100);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_voting_delay_below_min() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Try below minimum
            config::set_dao_voting_delay_ms(&admin_cap, &mut config, 3_599_999);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LP DISTRIBUTION BOUNDARY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_max_creator_lp_bps() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Set creator LP to max (30%)
            config::set_creator_lp_bps(&admin_cap, &mut config, 3000);
            assert!(config::creator_lp_bps(&config) == 3000, 100);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_creator_lp_exceeds_max() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Try above 30%
            config::set_creator_lp_bps(&admin_cap, &mut config, 3001);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_creator_plus_protocol_exceeds_50_percent() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Set creator to 30%, then try to set protocol to 21% (total 51%)
            config::set_creator_lp_bps(&admin_cap, &mut config, 3000);
            config::set_protocol_lp_bps(&admin_cap, &mut config, 2100);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ALL ADMIN DESTINATION BRANCHES
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_all_staking_admin_destinations() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        // Test all three destinations
        let destinations = vector[0u8, 1u8, 2u8]; // CREATOR, DAO, PLATFORM

        let mut i = 0;
        while (i < destinations.length()) {
            let dest = *destinations.borrow(i);

            ts::next_tx(&mut scenario, admin());
            {
                let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
                let mut config = ts::take_shared<LaunchpadConfig>(&scenario);
                let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);

                config::set_staking_admin_destination(&admin_cap, &mut config, dest);

                // Pool already graduated from previous iteration, skip if so
                if (!bonding_curve::is_graduated(&pool)) {
                    let pending = graduation::initiate_graduation(
                        &admin_cap, &mut pool, &config,
                        config::dex_suidex(),
                        ts::ctx(&mut scenario),
                    );

                    let actual_dest = staking_integration::get_admin_destination(&pending, &config);

                    if (dest == 0) {
                        assert!(actual_dest == graduation::pending_creator(&pending), 100 + (i as u64));
                    } else if (dest == 1) {
                        assert!(actual_dest == config::dao_treasury(&config), 100 + (i as u64));
                    } else {
                        assert!(actual_dest == config::treasury(&config), 100 + (i as u64));
                    };

                    graduation::destroy_pending_for_testing(pending);
                };

                ts::return_to_sender(&scenario, admin_cap);
                ts::return_shared(config);
                ts::return_shared(pool);
            };

            i = i + 1;
        };

        ts::end(scenario);
    }

    #[test]
    fun test_all_dao_admin_destinations() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        // Test all three destinations
        let destinations = vector[0u8, 1u8, 2u8]; // CREATOR, DAO_TREASURY, PLATFORM

        let mut i = 0;
        while (i < destinations.length()) {
            let dest = *destinations.borrow(i);

            ts::next_tx(&mut scenario, admin());
            {
                let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
                let mut config = ts::take_shared<LaunchpadConfig>(&scenario);
                let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);

                config::set_dao_admin_destination(&admin_cap, &mut config, dest);

                if (!bonding_curve::is_graduated(&pool)) {
                    let pending = graduation::initiate_graduation(
                        &admin_cap, &mut pool, &config,
                        config::dex_suidex(),
                        ts::ctx(&mut scenario),
                    );

                    let actual_dest = dao_integration::get_admin_destination(&pending, &config);

                    if (dest == 0) {
                        assert!(actual_dest == graduation::pending_creator(&pending), 200 + (i as u64));
                    } else if (dest == 1) {
                        assert!(actual_dest == config::dao_treasury(&config), 200 + (i as u64));
                    } else {
                        assert!(actual_dest == config::treasury(&config), 200 + (i as u64));
                    };

                    graduation::destroy_pending_for_testing(pending);
                };

                ts::return_to_sender(&scenario, admin_cap);
                ts::return_shared(config);
                ts::return_shared(pool);
            };

            i = i + 1;
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HOT POTATO PATTERN TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure(abort_code = 409)] // ESuiNotExtracted
    fun test_graduation_fails_without_sui_extraction() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let clock = create_clock(&mut scenario);

            let pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            // DON'T extract SUI - should fail
            let receipt = graduation::complete_graduation(
                pending,
                &mut registry,
                object::id_from_address(@0x123),
                0, 0, // sui_to_liquidity, tokens_to_liquidity (test values)
                1000000, 25000, 950000,
                &clock,
                ts::ctx(&mut scenario),
            );

            graduation::destroy_receipt_for_testing(receipt);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
            ts::return_shared(registry);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 410)] // ETokensNotExtracted
    fun test_graduation_fails_without_token_extraction() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let clock = create_clock(&mut scenario);

            let mut pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            // Extract SUI but NOT tokens
            let sui_coin = graduation::extract_all_sui(&mut pending, ts::ctx(&mut scenario));
            coin::burn_for_testing(sui_coin);

            // Should fail - tokens not extracted
            let receipt = graduation::complete_graduation(
                pending,
                &mut registry,
                object::id_from_address(@0x123),
                0, 0, // sui_to_liquidity, tokens_to_liquidity (test values)
                1000000, 25000, 950000,
                &clock,
                ts::ctx(&mut scenario),
            );

            graduation::destroy_receipt_for_testing(receipt);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
            ts::return_shared(registry);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE TRANSITION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_pool_state_before_and_after_graduation() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);

        // Before graduation - not graduated
        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            assert!(!bonding_curve::is_graduated(&pool), 100);
            ts::return_shared(pool);
        };

        buy_to_graduation_threshold(&mut scenario);
        create_dex_pair(&mut scenario);

        // Perform graduation
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let staking_admin_cap = ts::take_from_sender<StakingAdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let router = ts::take_shared<Router>(&scenario);
            let mut factory = ts::take_shared<Factory>(&scenario);
            let mut pair = ts::take_shared<Pair<TEST_COIN, SUI>>(&scenario);
            let clock = create_clock(&mut scenario);

            let mut pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            let sui_coin = graduation::extract_all_sui(&mut pending, ts::ctx(&mut scenario));
            let token_coin = graduation::extract_all_tokens(&mut pending, ts::ctx(&mut scenario));
            let staking_coin = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));

            let sui_amount = coin::value(&sui_coin);
            let token_amount = coin::value(&token_coin);

            suidex_router::add_liquidity<TEST_COIN, SUI>(
                &router, &mut factory, &mut pair,
                token_coin, sui_coin,
                (token_amount as u256), (sui_amount as u256),
                0, 0,
                std::string::utf8(b"TEST"), std::string::utf8(b"SUI"),
                9999999999999, &clock,
                ts::ctx(&mut scenario),
            );

            let pool_admin_cap = staking_integration::create_staking_pool<TEST_COIN>(
                &mut staking_registry,
                &staking_admin_cap,
                &pending,
                staking_coin,
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_transfer(pool_admin_cap, admin());

            let receipt = graduation::complete_graduation(
                pending,
                &mut registry,
                object::id(&pair),
                0, 0, // sui_to_liquidity, tokens_to_liquidity (test values)
                1000000, 25000, 950000,
                &clock,
                ts::ctx(&mut scenario),
            );

            graduation::destroy_receipt_for_testing(receipt);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_to_sender(&scenario, staking_admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
            ts::return_shared(registry);
            ts::return_shared(staking_registry);
            ts::return_shared(router);
            ts::return_shared(factory);
            ts::return_shared(pair);
            clock::destroy_for_testing(clock);
        };

        // After graduation - is graduated
        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            assert!(bonding_curve::is_graduated(&pool), 200);
            ts::return_shared(pool);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DOUBLE ACTION PREVENTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure]
    fun test_cannot_graduate_twice() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);
        create_dex_pair(&mut scenario);

        // First graduation
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let staking_admin_cap = ts::take_from_sender<StakingAdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let router = ts::take_shared<Router>(&scenario);
            let mut factory = ts::take_shared<Factory>(&scenario);
            let mut pair = ts::take_shared<Pair<TEST_COIN, SUI>>(&scenario);
            let clock = create_clock(&mut scenario);

            let mut pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            let sui_coin = graduation::extract_all_sui(&mut pending, ts::ctx(&mut scenario));
            let token_coin = graduation::extract_all_tokens(&mut pending, ts::ctx(&mut scenario));
            let staking_coin = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));

            let sui_amount = coin::value(&sui_coin);
            let token_amount = coin::value(&token_coin);

            suidex_router::add_liquidity<TEST_COIN, SUI>(
                &router, &mut factory, &mut pair,
                token_coin, sui_coin,
                (token_amount as u256), (sui_amount as u256),
                0, 0,
                std::string::utf8(b"TEST"), std::string::utf8(b"SUI"),
                9999999999999, &clock,
                ts::ctx(&mut scenario),
            );

            let pool_admin_cap = staking_integration::create_staking_pool<TEST_COIN>(
                &mut staking_registry,
                &staking_admin_cap,
                &pending,
                staking_coin,
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_transfer(pool_admin_cap, admin());

            let receipt = graduation::complete_graduation(
                pending,
                &mut registry,
                object::id(&pair),
                0, 0, // sui_to_liquidity, tokens_to_liquidity (test values)
                1000000, 25000, 950000,
                &clock,
                ts::ctx(&mut scenario),
            );

            graduation::destroy_receipt_for_testing(receipt);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_to_sender(&scenario, staking_admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
            ts::return_shared(registry);
            ts::return_shared(staking_registry);
            ts::return_shared(router);
            ts::return_shared(factory);
            ts::return_shared(pair);
            clock::destroy_for_testing(clock);
        };

        // Try to graduate again - should fail
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // This should fail - pool already graduated
            let pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            // If we reach here, the test failed - should have aborted above
            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ZERO VALUE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_zero_creator_fee() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        // Create pool with 0% creator fee
        ts::next_tx(&mut scenario, creator());
        {
            use sui_launchpad::test_coin;
            let (treasury_cap, metadata) = test_coin::create_test_coin(ts::ctx(&mut scenario));
            let launchpad_config = ts::take_shared<LaunchpadConfig>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            let creation_fee = config::creation_fee(&launchpad_config);
            let payment = coin::mint_for_testing<SUI>(creation_fee, ts::ctx(&mut scenario));

            let pool = bonding_curve::create_pool(
                &launchpad_config,
                treasury_cap,
                &metadata,
                0, // 0% creator fee
                payment,
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(bonding_curve::creator_fee_bps(&pool) == 0, 100);

            transfer::public_share_object(pool);
            ts::return_shared(launchpad_config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_zero_lp_to_creator() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        // Set creator LP to 0%
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);
            config::set_creator_lp_bps(&admin_cap, &mut config, 0);
            assert!(config::creator_lp_bps(&config) == 0, 100);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INVALID DESTINATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure]
    fun test_invalid_staking_admin_destination() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Try invalid destination (3 is invalid)
            config::set_staking_admin_destination(&admin_cap, &mut config, 3);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_invalid_dao_admin_destination() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Try invalid destination (3 is invalid)
            config::set_dao_admin_destination(&admin_cap, &mut config, 3);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION HELPER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_dao_admin_destination_validation() {
        assert!(dao_integration::is_valid_admin_destination(0), 100);
        assert!(dao_integration::is_valid_admin_destination(1), 101);
        assert!(dao_integration::is_valid_admin_destination(2), 102);
        assert!(!dao_integration::is_valid_admin_destination(3), 103);
        assert!(!dao_integration::is_valid_admin_destination(255), 104);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIG TOGGLE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_staking_enabled_toggle() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Default enabled
            assert!(config::staking_enabled(&config), 100);

            // Disable
            config::set_staking_enabled(&admin_cap, &mut config, false);
            assert!(!config::staking_enabled(&config), 101);

            // Re-enable
            config::set_staking_enabled(&admin_cap, &mut config, true);
            assert!(config::staking_enabled(&config), 102);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_dao_enabled_toggle() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Default enabled
            assert!(config::dao_enabled(&config), 100);

            // Disable
            config::set_dao_enabled(&admin_cap, &mut config, false);
            assert!(!config::dao_enabled(&config), 101);

            // Re-enable
            config::set_dao_enabled(&admin_cap, &mut config, true);
            assert!(config::dao_enabled(&config), 102);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_council_enabled_toggle() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Default disabled
            assert!(!config::dao_council_enabled(&config), 100);

            // Enable
            config::set_dao_council_enabled(&admin_cap, &mut config, true);
            assert!(config::dao_council_enabled(&config), 101);

            // Disable
            config::set_dao_council_enabled(&admin_cap, &mut config, false);
            assert!(!config::dao_council_enabled(&config), 102);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }
}
