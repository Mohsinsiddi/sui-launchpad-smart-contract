/// Full integration tests for suidex_adapter module
/// Uses the actual SuiDex packages to test graduate_to_suidex_extract and complete_graduation_manual
#[test_only]
module sui_launchpad::suidex_adapter_full_tests {
    use sui::test_scenario::{Self as ts};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock;

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::AdminCap;
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::graduation;
    use sui_launchpad::registry::Registry;
    use sui_launchpad::suidex_adapter;
    use sui_launchpad::test_utils;
    use sui_launchpad::test_coin::{Self, TEST_COIN};

    // SuiDex imports
    use suitrump_dex::router::{Self as suidex_router, Router};
    use suitrump_dex::factory::{Self as suidex_factory, Factory};
    use suitrump_dex::pair::{Pair, LPCoin};

    // ═══════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════

    fun admin(): address { @0xA1 }
    fun creator(): address { @0xC1 }

    fun buyer1(): address { @0xB1 }
    fun buyer2(): address { @0xB2 }
    fun buyer3(): address { @0xB3 }
    fun buyer4(): address { @0xB4 }
    fun buyer5(): address { @0xB5 }
    fun buyer6(): address { @0xB6 }
    fun buyer7(): address { @0xB7 }
    fun buyer8(): address { @0xB8 }
    fun buyer9(): address { @0xB9 }
    fun buyer10(): address { @0xBA }

    fun get_10_buyers(): vector<address> {
        vector[buyer1(), buyer2(), buyer3(), buyer4(), buyer5(),
               buyer6(), buyer7(), buyer8(), buyer9(), buyer10()]
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    fun setup_full_infrastructure(scenario: &mut ts::Scenario) {
        // Setup launchpad
        test_utils::setup_launchpad(scenario);

        // Configure SuiDex package address in config
        ts::next_tx(scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(scenario);
            let mut launchpad_config = ts::take_shared<LaunchpadConfig>(scenario);

            // Set SuiDex package address (non-zero to pass validation)
            config::set_suidex_package(&admin_cap, &mut launchpad_config, @0x5D);

            ts::return_shared(launchpad_config);
            ts::return_to_sender(scenario, admin_cap);
        };

        // Setup SuiDex
        ts::next_tx(scenario, admin());
        {
            suidex_factory::init_for_testing(ts::ctx(scenario));
            suidex_router::init_for_testing(ts::ctx(scenario));
        };
    }

    fun create_token_pool(scenario: &mut ts::Scenario): ID {
        ts::next_tx(scenario, creator());
        let pool_id;
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(ts::ctx(scenario));
            let config = ts::take_shared<LaunchpadConfig>(scenario);
            let clk = clock::create_for_testing(ts::ctx(scenario));

            let creation_fee = config::creation_fee(&config);
            let payment = coin::mint_for_testing<SUI>(creation_fee, ts::ctx(scenario));

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clk,
                ts::ctx(scenario),
            );
            pool_id = object::id(&pool);

            transfer::public_share_object(pool);
            sui::test_utils::destroy(metadata);
            ts::return_shared(config);
            clock::destroy_for_testing(clk);
        };
        pool_id
    }

    fun buy_to_graduation(scenario: &mut ts::Scenario) {
        // Use same pattern as e2e_suidex_tests: buy threshold + 10% with admin
        ts::next_tx(scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(scenario);
            let config = ts::take_shared<LaunchpadConfig>(scenario);
            let clk = clock::create_for_testing(ts::ctx(scenario));

            let threshold = config::graduation_threshold(&config);
            let buy_amount = threshold + (threshold / 10);

            let sui_coin = coin::mint_for_testing<SUI>(buy_amount, ts::ctx(scenario));
            let tokens = bonding_curve::buy<TEST_COIN>(
                &mut pool,
                &config,
                sui_coin,
                1,
                &clk,
                ts::ctx(scenario),
            );
            transfer::public_transfer(tokens, admin());

            ts::return_shared(pool);
            ts::return_shared(config);
            clock::destroy_for_testing(clk);
        };
    }

    fun create_suidex_pair(scenario: &mut ts::Scenario) {
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

    // ═══════════════════════════════════════════════════════════════════════
    // SUIDEX ADAPTER FULL TESTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Test the full graduation flow using suidex_adapter functions
    #[test]
    fun test_suidex_adapter_full_graduation_flow() {
        let mut scenario = ts::begin(admin());

        // Setup
        setup_full_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        buy_to_graduation(&mut scenario);
        create_suidex_pair(&mut scenario);

        // Execute graduation using ADAPTER functions (not graduation module directly)
        ts::next_tx(&mut scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let mut factory = ts::take_shared<Factory>(&scenario);
            let router = ts::take_shared<Router>(&scenario);
            let mut pair = ts::take_shared<Pair<TEST_COIN, SUI>>(&scenario);
            let clk = clock::create_for_testing(ts::ctx(&mut scenario));

            // Step 1: Initiate graduation
            let pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            // Step 2: Use SUIDEX ADAPTER to extract tokens
            let (mut pending, sui_coin, token_coin) = suidex_adapter::graduate_to_suidex_extract(
                pending,
                &config,
                ts::ctx(&mut scenario),
            );

            let sui_amount = coin::value(&sui_coin);
            let token_amount = coin::value(&token_coin);

            // Verify minimum liquidity requirements
            assert!(sui_amount >= suidex_adapter::minimum_liquidity(), 0);
            assert!(token_amount >= suidex_adapter::minimum_liquidity(), 1);

            // Step 3: Add liquidity to SuiDex
            suidex_router::add_liquidity<TEST_COIN, SUI>(
                &router, &mut factory, &mut pair,
                token_coin, sui_coin,
                (token_amount as u256), (sui_amount as u256),
                0, 0,
                std::string::utf8(b"TEST"), std::string::utf8(b"SUI"),
                9999999999999, &clk,
                ts::ctx(&mut scenario),
            );

            // Step 3.5: Extract staking tokens (required before completing graduation)
            let staking_tokens = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));
            // Burn staking tokens for this test (normally would create staking pool)
            coin::burn_for_testing(staking_tokens);

            // Step 4: Use SUIDEX ADAPTER to complete graduation
            let receipt = suidex_adapter::complete_graduation_manual(
                pending,
                &mut registry,
                object::id(&pair),
                sui_amount,
                token_amount,
                0, 0, 0,
                &clk,
                ts::ctx(&mut scenario),
            );

            // Verify graduation completed
            assert!(bonding_curve::is_graduated(&pool), 2);

            graduation::destroy_receipt_for_testing(receipt);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
            ts::return_shared(registry);
            ts::return_shared(factory);
            ts::return_shared(router);
            ts::return_shared(pair);
            clock::destroy_for_testing(clk);
        };

        ts::end(scenario);
    }

    /// Test create_suidex_objects helper
    #[test]
    fun test_create_suidex_objects() {
        let factory_id = object::id_from_address(@0xF1);
        let router_id = object::id_from_address(@0xA1);
        
        // With pair
        let objects = suidex_adapter::create_suidex_objects<TEST_COIN>(
            factory_id,
            router_id,
            option::some(object::id_from_address(@0xB1)),
        );
        let _ = objects; // Has drop

        // Without pair
        let objects2 = suidex_adapter::create_suidex_objects<TEST_COIN>(
            factory_id,
            router_id,
            option::none(),
        );
        let _ = objects2;
    }

    /// Test wrong DEX type validation
    #[test]
    #[expected_failure(abort_code = 630)] // EWrongDexType
    fun test_suidex_adapter_wrong_dex_type() {
        let mut scenario = ts::begin(admin());

        setup_full_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        buy_to_graduation(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Initiate graduation for CETUS (not SuiDex)
            let pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_cetus(), // Wrong DEX!
                ts::ctx(&mut scenario),
            );

            // Try to use SuiDex adapter - should fail
            let (pending, sui_coin, token_coin) = suidex_adapter::graduate_to_suidex_extract(
                pending,
                &config,
                ts::ctx(&mut scenario),
            );

            // Cleanup (won't reach here)
            coin::burn_for_testing(sui_coin);
            coin::burn_for_testing(token_coin);
            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    /// Test minimum liquidity validation
    #[test]
    fun test_suidex_minimum_liquidity_check() {
        // The graduation flow ensures we have enough liquidity
        // by requiring 10 unique buyers and significant SUI volume
        let mut scenario = ts::begin(admin());

        setup_full_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        buy_to_graduation(&mut scenario);
        create_suidex_pair(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let mut factory = ts::take_shared<Factory>(&scenario);
            let router = ts::take_shared<Router>(&scenario);
            let mut pair = ts::take_shared<Pair<TEST_COIN, SUI>>(&scenario);
            let clk = clock::create_for_testing(ts::ctx(&mut scenario));

            let pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            let (mut pending, sui_coin, token_coin) = suidex_adapter::graduate_to_suidex_extract(
                pending,
                &config,
                ts::ctx(&mut scenario),
            );

            // Verify we have way more than minimum liquidity
            assert!(coin::value(&sui_coin) > suidex_adapter::minimum_liquidity() * 1000, 0);
            assert!(coin::value(&token_coin) > suidex_adapter::minimum_liquidity() * 1000, 1);

            let sui_amount = coin::value(&sui_coin);
            let token_amount = coin::value(&token_coin);

            suidex_router::add_liquidity<TEST_COIN, SUI>(
                &router, &mut factory, &mut pair,
                token_coin, sui_coin,
                (token_amount as u256), (sui_amount as u256),
                0, 0,
                std::string::utf8(b"TEST"), std::string::utf8(b"SUI"),
                9999999999999, &clk,
                ts::ctx(&mut scenario),
            );

            // Extract staking tokens (required before completing graduation)
            let staking_tokens = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));
            coin::burn_for_testing(staking_tokens);

            let receipt = suidex_adapter::complete_graduation_manual(
                pending,
                &mut registry,
                object::id(&pair),
                sui_amount,
                token_amount,
                0, 0, 0,
                &clk,
                ts::ctx(&mut scenario),
            );

            graduation::destroy_receipt_for_testing(receipt);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
            ts::return_shared(registry);
            ts::return_shared(factory);
            ts::return_shared(router);
            ts::return_shared(pair);
            clock::destroy_for_testing(clk);
        };

        ts::end(scenario);
    }

    /// Test LP tokens are minted after graduation
    #[test]
    fun test_suidex_lp_tokens_minted() {
        let mut scenario = ts::begin(admin());

        setup_full_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        buy_to_graduation(&mut scenario);
        create_suidex_pair(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let mut factory = ts::take_shared<Factory>(&scenario);
            let router = ts::take_shared<Router>(&scenario);
            let mut pair = ts::take_shared<Pair<TEST_COIN, SUI>>(&scenario);
            let clk = clock::create_for_testing(ts::ctx(&mut scenario));

            let pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            let (mut pending, sui_coin, token_coin) = suidex_adapter::graduate_to_suidex_extract(
                pending,
                &config,
                ts::ctx(&mut scenario),
            );

            let sui_amount = coin::value(&sui_coin);
            let token_amount = coin::value(&token_coin);

            suidex_router::add_liquidity<TEST_COIN, SUI>(
                &router, &mut factory, &mut pair,
                token_coin, sui_coin,
                (token_amount as u256), (sui_amount as u256),
                0, 0,
                std::string::utf8(b"TEST"), std::string::utf8(b"SUI"),
                9999999999999, &clk,
                ts::ctx(&mut scenario),
            );

            // Extract staking tokens (required before completing graduation)
            let staking_tokens = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));
            coin::burn_for_testing(staking_tokens);

            let receipt = suidex_adapter::complete_graduation_manual(
                pending,
                &mut registry,
                object::id(&pair),
                sui_amount,
                token_amount,
                0, 0, 0,
                &clk,
                ts::ctx(&mut scenario),
            );

            graduation::destroy_receipt_for_testing(receipt);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
            ts::return_shared(registry);
            ts::return_shared(factory);
            ts::return_shared(router);
            ts::return_shared(pair);
            clock::destroy_for_testing(clk);
        };

        // Verify LP tokens were minted to admin
        ts::next_tx(&mut scenario, admin());
        {
            let lp_tokens = ts::take_from_sender<Coin<LPCoin<TEST_COIN, SUI>>>(&scenario);
            assert!(coin::value(&lp_tokens) > 0, 0);
            ts::return_to_sender(&scenario, lp_tokens);
        };

        ts::end(scenario);
    }

    /// Test slippage calculation helper
    #[test]
    fun test_calculate_min_amount_edge_cases() {
        // Zero amount
        assert!(suidex_adapter::calculate_min_amount(0, 100) == 0, 0);

        // Large amount with small slippage
        assert!(suidex_adapter::calculate_min_amount(1_000_000_000_000, 1) == 999_900_000_000, 1);

        // Max slippage (100% = 10000 bps)
        assert!(suidex_adapter::calculate_min_amount(10000, 10000) == 0, 2);
    }

    /// Test that ESuiDexNotConfigured is thrown when suidex_package is not set
    #[test]
    #[expected_failure(abort_code = 631)] // ESuiDexNotConfigured
    fun test_suidex_adapter_not_configured_error() {
        let mut scenario = ts::begin(admin());

        // Setup launchpad WITHOUT setting suidex_package
        test_utils::setup_launchpad(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        buy_to_graduation(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Initiate graduation for SuiDex
            let pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            // This should fail because suidex_package is @0x0
            let (pending2, sui_coin, token_coin) = suidex_adapter::graduate_to_suidex_extract(
                pending,
                &config,
                ts::ctx(&mut scenario),
            );

            // Cleanup (won't reach here due to expected_failure)
            coin::burn_for_testing(sui_coin);
            coin::burn_for_testing(token_coin);
            graduation::destroy_pending_for_testing(pending2);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }
}
