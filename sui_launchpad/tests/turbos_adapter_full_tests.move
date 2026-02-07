/// Full integration tests for turbos_adapter module
/// Tests graduate_to_turbos_extract and complete_graduation_manual functions
#[test_only]
module sui_launchpad::turbos_adapter_full_tests {
    use sui::test_scenario::{Self as ts};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock;

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::AdminCap;
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::graduation;
    use sui_launchpad::registry::Registry;
    use sui_launchpad::turbos_adapter;
    use sui_launchpad::test_utils;
    use sui_launchpad::test_coin::{Self, TEST_COIN};

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

        // Configure Turbos package address in config
        ts::next_tx(scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(scenario);
            let mut launchpad_config = ts::take_shared<LaunchpadConfig>(scenario);

            // Set Turbos package address (non-zero to pass validation)
            config::set_turbos_package(&admin_cap, &mut launchpad_config, @0xD1);

            ts::return_shared(launchpad_config);
            ts::return_to_sender(scenario, admin_cap);
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
    // TURBOS ADAPTER FULL TESTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Test the full graduation flow using turbos_adapter functions
    #[test]
    fun test_turbos_adapter_full_graduation_flow() {
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

            // Step 1: Initiate graduation for Turbos
            let pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_turbos(),
                ts::ctx(&mut scenario),
            );

            // Step 2: Use TURBOS ADAPTER to extract tokens
            let (mut pending, sui_coin, token_coin) = turbos_adapter::graduate_to_turbos_extract(
                pending,
                &config,
                ts::ctx(&mut scenario),
            );

            let sui_amount = coin::value(&sui_coin);
            let token_amount = coin::value(&token_coin);

            // Verify minimum liquidity requirements
            assert!(sui_amount >= turbos_adapter::minimum_liquidity(), 0);
            assert!(token_amount >= turbos_adapter::minimum_liquidity(), 1);

            // Step 3: Simulate Turbos pool creation (in real scenario would call Turbos on testnet/mainnet)
            // For test, just burn the coins and use mock pool ID
            coin::burn_for_testing(sui_coin);
            coin::burn_for_testing(token_coin);
            let mock_pool_id = object::id_from_address(@0xD10);

            // Step 3.5: Extract staking tokens (required before completing graduation)
            let staking_tokens = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));
            coin::burn_for_testing(staking_tokens);

            // Step 4: Use TURBOS ADAPTER to complete graduation
            let receipt = turbos_adapter::complete_graduation_manual(
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
    #[expected_failure(abort_code = 610)] // EWrongDexType
    fun test_turbos_adapter_wrong_dex_type() {
        let mut scenario = ts::begin(admin());

        setup_full_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        buy_to_graduation(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Initiate graduation for SUIDEX (not Turbos)
            let pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_suidex(), // Wrong DEX!
                ts::ctx(&mut scenario),
            );

            // Try to use Turbos adapter - should fail
            let (pending, sui_coin, token_coin) = turbos_adapter::graduate_to_turbos_extract(
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

    /// Test ETurbosNotConfigured error when turbos_package is not set
    #[test]
    #[expected_failure(abort_code = 611)] // ETurbosNotConfigured
    fun test_turbos_adapter_not_configured_error() {
        let mut scenario = ts::begin(admin());

        // Setup launchpad WITHOUT setting turbos_package
        test_utils::setup_launchpad(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        buy_to_graduation(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Initiate graduation for Turbos
            let pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_turbos(),
                ts::ctx(&mut scenario),
            );

            // This should fail because turbos_package is @0x0
            let (pending2, sui_coin, token_coin) = turbos_adapter::graduate_to_turbos_extract(
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
    fun test_turbos_minimum_liquidity_check() {
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
                config::dex_turbos(),
                ts::ctx(&mut scenario),
            );

            let (mut pending, sui_coin, token_coin) = turbos_adapter::graduate_to_turbos_extract(
                pending,
                &config,
                ts::ctx(&mut scenario),
            );

            // Verify we have way more than minimum liquidity
            assert!(coin::value(&sui_coin) > turbos_adapter::minimum_liquidity() * 1000, 0);
            assert!(coin::value(&token_coin) > turbos_adapter::minimum_liquidity() * 1000, 1);

            let sui_amount = coin::value(&sui_coin);
            let token_amount = coin::value(&token_coin);

            // Burn coins
            coin::burn_for_testing(sui_coin);
            coin::burn_for_testing(token_coin);

            // Extract staking tokens
            let staking_tokens = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));
            coin::burn_for_testing(staking_tokens);

            let mock_pool_id = object::id_from_address(@0xD10);
            let receipt = turbos_adapter::complete_graduation_manual(
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

    /// Test calculate_sqrt_price_x64 function
    #[test]
    fun test_turbos_calculate_sqrt_price() {
        // 1:1 ratio returns the constant
        let sqrt_price = turbos_adapter::calculate_sqrt_price_x64(1_000_000, 1_000_000);
        assert!(sqrt_price == 18446744073709551616, 0); // 1 << 64

        // Different ratios return non-zero values
        let sqrt_price_2 = turbos_adapter::calculate_sqrt_price_x64(2_000_000, 1_000_000);
        assert!(sqrt_price_2 > 0, 1);

        // Token < sui case
        let sqrt_price_3 = turbos_adapter::calculate_sqrt_price_x64(1_000_000, 2_000_000);
        assert!(sqrt_price_3 > 0, 2);
    }
}
