/// Full integration tests for cetus_adapter module
/// Tests graduate_to_cetus_extract and complete_graduation_manual functions
#[test_only]
module sui_launchpad::cetus_adapter_full_tests {
    use sui::test_scenario::{Self as ts};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock;

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::AdminCap;
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::graduation;
    use sui_launchpad::registry::Registry;
    use sui_launchpad::cetus_adapter;
    use sui_launchpad::test_utils;
    use sui_launchpad::test_coin::{Self, TEST_COIN};

    // Cetus imports
    use cetus_clmm::config::{Self as cetus_config};

    const DEFAULT_PROTOCOL_FEE: u64 = 2000;
    const TICK_SPACING_60: u32 = 60;
    const FEE_RATE_3000: u64 = 3000;

    // ═══════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════

    fun admin(): address { @0xA1 }
    fun creator(): address { @0xC1 }

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    fun setup_full_infrastructure(scenario: &mut ts::Scenario) {
        // Setup launchpad
        test_utils::setup_launchpad(scenario);

        // Configure Cetus package address in config
        ts::next_tx(scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(scenario);
            let mut launchpad_config = ts::take_shared<LaunchpadConfig>(scenario);

            // Set Cetus package address (non-zero to pass validation)
            config::set_cetus_package(&admin_cap, &mut launchpad_config, @0xC5);

            ts::return_shared(launchpad_config);
            ts::return_to_sender(scenario, admin_cap);
        };

        // Setup Cetus infrastructure
        ts::next_tx(scenario, admin());
        {
            let (cetus_admin_cap, mut global_config) = cetus_config::new_global_config_for_test(
                ts::ctx(scenario),
                DEFAULT_PROTOCOL_FEE,
            );
            // Add fee tier
            cetus_config::add_fee_tier(&mut global_config, TICK_SPACING_60, FEE_RATE_3000, ts::ctx(scenario));
            transfer::public_share_object(global_config);
            transfer::public_transfer(cetus_admin_cap, admin());
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
        // Use same pattern as e2e tests: buy threshold + 10% with admin
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

    // ═══════════════════════════════════════════════════════════════════════
    // CETUS ADAPTER FULL TESTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Test the full graduation flow using cetus_adapter functions
    #[test]
    fun test_cetus_adapter_full_graduation_flow() {
        let mut scenario = ts::begin(admin());

        // Setup
        setup_full_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        buy_to_graduation(&mut scenario);

        // Execute graduation using ADAPTER functions
        ts::next_tx(&mut scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let clk = clock::create_for_testing(ts::ctx(&mut scenario));

            // Step 1: Initiate graduation for Cetus
            let pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_cetus(),
                ts::ctx(&mut scenario),
            );

            // Step 2: Use CETUS ADAPTER to extract tokens
            let (mut pending, sui_coin, token_coin) = cetus_adapter::graduate_to_cetus_extract(
                pending,
                &config,
                ts::ctx(&mut scenario),
            );

            let sui_amount = coin::value(&sui_coin);
            let token_amount = coin::value(&token_coin);

            // Verify minimum liquidity requirements
            assert!(sui_amount >= cetus_adapter::minimum_liquidity(), 0);
            assert!(token_amount >= cetus_adapter::minimum_liquidity(), 1);

            // Step 3: Simulate Cetus pool creation (in real scenario would call Cetus)
            // For test, just burn the coins and use mock pool ID
            coin::burn_for_testing(sui_coin);
            coin::burn_for_testing(token_coin);
            let mock_pool_id = object::id_from_address(@0xCE5);

            // Step 3.5: Extract staking tokens (required before completing graduation)
            let staking_tokens = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));
            coin::burn_for_testing(staking_tokens);

            // Step 4: Use CETUS ADAPTER to complete graduation
            let receipt = cetus_adapter::complete_graduation_manual(
                pending,
                &mut registry,
                mock_pool_id,
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
            clock::destroy_for_testing(clk);
        };

        ts::end(scenario);
    }

    /// Test wrong DEX type validation
    #[test]
    #[expected_failure(abort_code = 600)] // EWrongDexType
    fun test_cetus_adapter_wrong_dex_type() {
        let mut scenario = ts::begin(admin());

        setup_full_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        buy_to_graduation(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Initiate graduation for SUIDEX (not Cetus)
            let pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_suidex(), // Wrong DEX!
                ts::ctx(&mut scenario),
            );

            // Try to use Cetus adapter - should fail
            let (pending, sui_coin, token_coin) = cetus_adapter::graduate_to_cetus_extract(
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

    /// Test ECetusNotConfigured error when cetus_package is not set
    #[test]
    #[expected_failure(abort_code = 601)] // ECetusNotConfigured
    fun test_cetus_adapter_not_configured_error() {
        let mut scenario = ts::begin(admin());

        // Setup launchpad WITHOUT setting cetus_package
        test_utils::setup_launchpad(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        buy_to_graduation(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Initiate graduation for Cetus
            let pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_cetus(),
                ts::ctx(&mut scenario),
            );

            // This should fail because cetus_package is @0x0
            let (pending2, sui_coin, token_coin) = cetus_adapter::graduate_to_cetus_extract(
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

    /// Test minimum liquidity check in extract
    #[test]
    fun test_cetus_minimum_liquidity_check() {
        let mut scenario = ts::begin(admin());

        setup_full_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        buy_to_graduation(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let clk = clock::create_for_testing(ts::ctx(&mut scenario));

            let pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_cetus(),
                ts::ctx(&mut scenario),
            );

            let (mut pending, sui_coin, token_coin) = cetus_adapter::graduate_to_cetus_extract(
                pending,
                &config,
                ts::ctx(&mut scenario),
            );

            // Verify we have way more than minimum liquidity
            assert!(coin::value(&sui_coin) > cetus_adapter::minimum_liquidity() * 1000, 0);
            assert!(coin::value(&token_coin) > cetus_adapter::minimum_liquidity() * 1000, 1);

            let sui_amount = coin::value(&sui_coin);
            let token_amount = coin::value(&token_coin);

            // Burn coins
            coin::burn_for_testing(sui_coin);
            coin::burn_for_testing(token_coin);

            // Extract staking tokens
            let staking_tokens = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));
            coin::burn_for_testing(staking_tokens);

            let mock_pool_id = object::id_from_address(@0xCE5);
            let receipt = cetus_adapter::complete_graduation_manual(
                pending,
                &mut registry,
                mock_pool_id,
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
            clock::destroy_for_testing(clk);
        };

        ts::end(scenario);
    }

    /// Test split_coins_for_positions helper
    #[test]
    fun test_cetus_split_coins_for_positions() {
        let mut scenario = ts::begin(admin());
        test_utils::setup_launchpad(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let total_sui = 10_000_000_000; // 10 SUI
            let total_tokens = 1_000_000_000_000; // 1000 tokens

            let sui_coin = coin::mint_for_testing<SUI>(total_sui, ts::ctx(&mut scenario));
            let token_coin = coin::mint_for_testing<TEST_COIN>(total_tokens, ts::ctx(&mut scenario));

            let (
                creator_sui, creator_tokens,
                protocol_sui, protocol_tokens,
                dao_sui, dao_tokens
            ) = cetus_adapter::split_coins_for_positions(sui_coin, token_coin, &config, ts::ctx(&mut scenario));

            // Verify amounts based on default LP allocation (2.5% creator, 2.5% protocol, 95% DAO)
            assert!(coin::value(&creator_sui) == 250_000_000, 0);   // 2.5% of 10 SUI
            assert!(coin::value(&protocol_sui) == 250_000_000, 1);
            assert!(coin::value(&dao_sui) == 9_500_000_000, 2);     // 95%

            assert!(coin::value(&creator_tokens) == 25_000_000_000, 3);
            assert!(coin::value(&protocol_tokens) == 25_000_000_000, 4);
            assert!(coin::value(&dao_tokens) == 950_000_000_000, 5);

            // Total should equal original
            assert!(
                coin::value(&creator_sui) + coin::value(&protocol_sui) + coin::value(&dao_sui) == total_sui,
                6
            );
            assert!(
                coin::value(&creator_tokens) + coin::value(&protocol_tokens) + coin::value(&dao_tokens) == total_tokens,
                7
            );

            // Cleanup
            coin::burn_for_testing(creator_sui);
            coin::burn_for_testing(creator_tokens);
            coin::burn_for_testing(protocol_sui);
            coin::burn_for_testing(protocol_tokens);
            coin::burn_for_testing(dao_sui);
            coin::burn_for_testing(dao_tokens);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    /// Test calculate_liquidity_split helper
    #[test]
    fun test_cetus_calculate_liquidity_split() {
        let mut scenario = ts::begin(admin());
        test_utils::setup_launchpad(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let total_sui = 100_000_000_000; // 100 SUI
            let total_tokens = 10_000_000_000_000; // 10000 tokens

            let (
                creator_sui, creator_tokens,
                protocol_sui, protocol_tokens,
                dao_sui, dao_tokens
            ) = cetus_adapter::calculate_liquidity_split(total_sui, total_tokens, &config);

            // 2.5% each for creator and protocol
            assert!(creator_sui == 2_500_000_000, 0);     // 2.5 SUI
            assert!(creator_tokens == 250_000_000_000, 1); // 250 tokens
            assert!(protocol_sui == 2_500_000_000, 2);
            assert!(protocol_tokens == 250_000_000_000, 3);

            // 95% for DAO
            assert!(dao_sui == 95_000_000_000, 4);        // 95 SUI
            assert!(dao_tokens == 9_500_000_000_000, 5);  // 9500 tokens

            // Total should equal original
            assert!(creator_sui + protocol_sui + dao_sui == total_sui, 6);
            assert!(creator_tokens + protocol_tokens + dao_tokens == total_tokens, 7);

            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    /// Test CetusObjects creation
    #[test]
    fun test_create_cetus_objects() {
        let global_config_id = object::id_from_address(@0xC1);
        let pools_id = object::id_from_address(@0xD1);

        let objects = cetus_adapter::create_cetus_objects(
            global_config_id,
            pools_id,
        );
        let _ = objects; // Has drop
    }
}
