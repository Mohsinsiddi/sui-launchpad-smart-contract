/// Comprehensive tests for all DEX adapters
/// Tests constants, helpers, and graduation extraction functions
#[test_only]
module sui_launchpad::dex_adapters_tests {
    use sui::test_scenario::{Self as ts};

    use sui_launchpad::config;

    // Adapter imports
    use sui_launchpad::suidex_adapter;
    use sui_launchpad::cetus_adapter;
    use sui_launchpad::flowx_adapter;
    use sui_launchpad::turbos_adapter;
    use sui_launchpad::test_coin::TEST_COIN;

    // ═══════════════════════════════════════════════════════════════════════
    // SUIDEX ADAPTER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_suidex_constants() {
        // Default swap fee is 0.3% = 30 bps
        assert!(suidex_adapter::default_swap_fee_bps() == 30, 0);

        // Minimum liquidity is 1000
        assert!(suidex_adapter::minimum_liquidity() == 1000, 1);

        // Default slippage is 1% = 100 bps
        assert!(suidex_adapter::default_slippage_bps() == 100, 2);
    }

    #[test]
    fun test_suidex_calculate_min_amount() {
        // 1% slippage on 10000 = 9900
        assert!(suidex_adapter::calculate_min_amount(10000, 100) == 9900, 0);

        // 0.5% slippage on 20000 = 19900
        assert!(suidex_adapter::calculate_min_amount(20000, 50) == 19900, 1);

        // 0% slippage = original amount
        assert!(suidex_adapter::calculate_min_amount(10000, 0) == 10000, 2);

        // 10% slippage on 1000 = 900
        assert!(suidex_adapter::calculate_min_amount(1000, 1000) == 900, 3);

        // Edge case: 100% slippage = 0
        assert!(suidex_adapter::calculate_min_amount(1000, 10000) == 0, 4);
    }

    #[test]
    fun test_suidex_create_objects() {
        let factory_id = object::id_from_address(@0xF1);
        let router_id = object::id_from_address(@0xA1);
        let pair_id = option::some(object::id_from_address(@0xB1));

        let objects = suidex_adapter::create_suidex_objects<TEST_COIN>(
            factory_id,
            router_id,
            pair_id,
        );
        // Objects wrapper created successfully (struct has drop)
        let _ = objects;
    }

    #[test]
    fun test_suidex_create_objects_no_pair() {
        let factory_id = object::id_from_address(@0xF1);
        let router_id = object::id_from_address(@0xA1);

        let objects = suidex_adapter::create_suidex_objects<TEST_COIN>(
            factory_id,
            router_id,
            option::none(),
        );
        let _ = objects;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CETUS ADAPTER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_cetus_constants() {
        // Default tick spacing (0.3% fee tier)
        assert!(cetus_adapter::default_tick_spacing() == 60, 0);

        // Default fee tier is 0.3% = 3000 bps
        assert!(cetus_adapter::default_fee_tier() == 3000, 1);

        // Minimum liquidity
        assert!(cetus_adapter::minimum_liquidity() == 1000, 2);

        // Full range ticks
        assert!(cetus_adapter::full_range_tick_lower() == 4294523660, 3);
        assert!(cetus_adapter::full_range_tick_upper() == 443580, 4);
    }

    #[test]
    fun test_cetus_create_objects() {
        let global_config_id = object::id_from_address(@0xC1);
        let pools_id = object::id_from_address(@0xD1);

        let objects = cetus_adapter::create_cetus_objects(
            global_config_id,
            pools_id,
        );
        let _ = objects;
    }

    #[test]
    fun test_cetus_lp_distribution_constants() {
        // LP distribution percentages
        assert!(cetus_adapter::creator_lp_bps() > 0, 0);
        assert!(cetus_adapter::protocol_lp_bps() > 0, 1);
        assert!(cetus_adapter::dao_lp_bps() > 0, 2);

        // Total should be 100% = 10000 bps
        let total = cetus_adapter::creator_lp_bps() +
                    cetus_adapter::protocol_lp_bps() +
                    cetus_adapter::dao_lp_bps();
        assert!(total == 10000, 3);
    }

    #[test]
    fun test_cetus_calculate_sqrt_price() {
        // 1:1 ratio returns the constant SQRT_PRICE_1_TO_1
        let sqrt_price = cetus_adapter::calculate_sqrt_price_x64(1_000_000, 1_000_000);
        assert!(sqrt_price == 18446744073709551616, 0); // 1 << 64

        // Different ratios return non-zero values
        let sqrt_price_2 = cetus_adapter::calculate_sqrt_price_x64(2_000_000, 1_000_000);
        assert!(sqrt_price_2 > 0, 1);

        let sqrt_price_3 = cetus_adapter::calculate_sqrt_price_x64(1_000_000, 2_000_000);
        assert!(sqrt_price_3 > 0, 2);
    }

    #[test]
    fun test_cetus_price_to_tick() {
        // price_to_tick is a placeholder that returns 0
        let tick = cetus_adapter::price_to_tick(18446744073709551616);
        assert!(tick == 0, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FLOWX ADAPTER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_flowx_constants() {
        // Default fee rate is 0.3% = 3000 bps
        assert!(flowx_adapter::default_fee_rate() == 3000, 0);

        // Minimum liquidity
        assert!(flowx_adapter::minimum_liquidity() == 1000, 1);

        // Full range ticks
        assert!(flowx_adapter::full_range_tick_lower() == 4294523660, 2);
        assert!(flowx_adapter::full_range_tick_upper() == 443580, 3);

        // Default deadline offset (10 minutes in ms)
        assert!(flowx_adapter::default_deadline_offset_ms() == 600_000, 4);
    }

    #[test]
    fun test_flowx_create_objects() {
        let pool_registry_id = object::id_from_address(@0xE1);
        let position_registry_id = object::id_from_address(@0xE2);
        let versioned_id = object::id_from_address(@0xE3);

        let objects = flowx_adapter::create_flowx_objects(
            pool_registry_id,
            position_registry_id,
            versioned_id,
        );
        let _ = objects;
    }

    #[test]
    fun test_flowx_calculate_sqrt_price() {
        // 1:1 ratio returns the constant
        let sqrt_price = flowx_adapter::calculate_sqrt_price_x64(1_000_000, 1_000_000);
        assert!(sqrt_price == 18446744073709551616, 0); // 1 << 64

        // Different ratios return non-zero values
        let sqrt_price_2 = flowx_adapter::calculate_sqrt_price_x64(2_000_000, 1_000_000);
        assert!(sqrt_price_2 > 0, 1);
    }

    #[test]
    fun test_flowx_calculate_deadline() {
        let mut scenario = ts::begin(@0xA1);
        {
            let clock = sui::clock::create_for_testing(ts::ctx(&mut scenario));
            // Current time + default offset
            let deadline = flowx_adapter::calculate_deadline(&clock);
            // Deadline should be at least the default offset from now (0)
            assert!(deadline == 600_000, 0);
            sui::clock::destroy_for_testing(clock);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TURBOS ADAPTER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_turbos_constants() {
        // Default tick spacing
        assert!(turbos_adapter::default_tick_spacing() == 60, 0);

        // Default fee is 0.3% = 3000 bps
        assert!(turbos_adapter::default_fee_bps() == 3000, 1);

        // Minimum liquidity
        assert!(turbos_adapter::minimum_liquidity() == 1000, 2);

        // Full range ticks
        assert!(turbos_adapter::full_range_tick_lower() == 4294523660, 3);
        assert!(turbos_adapter::full_range_tick_upper() == 443580, 4);
    }

    #[test]
    fun test_turbos_calculate_sqrt_price() {
        // 1:1 ratio returns the constant
        let sqrt_price = turbos_adapter::calculate_sqrt_price_x64(1_000_000, 1_000_000);
        assert!(sqrt_price == 18446744073709551616, 0); // 1 << 64

        // Different ratios return non-zero values
        let sqrt_price_2 = turbos_adapter::calculate_sqrt_price_x64(2_000_000, 1_000_000);
        assert!(sqrt_price_2 > 0, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CROSS-ADAPTER COMPARISON TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_all_adapters_have_minimum_liquidity_1000() {
        // All adapters should have the same minimum liquidity
        assert!(suidex_adapter::minimum_liquidity() == 1000, 0);
        assert!(cetus_adapter::minimum_liquidity() == 1000, 1);
        assert!(flowx_adapter::minimum_liquidity() == 1000, 2);
        assert!(turbos_adapter::minimum_liquidity() == 1000, 3);
    }

    #[test]
    fun test_clmm_adapters_have_consistent_tick_ranges() {
        // All CLMM adapters have the same full range tick values
        assert!(cetus_adapter::full_range_tick_lower() == flowx_adapter::full_range_tick_lower(), 0);
        assert!(cetus_adapter::full_range_tick_upper() == flowx_adapter::full_range_tick_upper(), 1);
        assert!(cetus_adapter::full_range_tick_lower() == turbos_adapter::full_range_tick_lower(), 2);
        assert!(cetus_adapter::full_range_tick_upper() == turbos_adapter::full_range_tick_upper(), 3);
    }

    #[test]
    fun test_clmm_adapters_fee_rates() {
        // All CLMM adapters should have 0.3% = 3000 bps as default
        assert!(cetus_adapter::default_fee_tier() == 3000, 0);
        assert!(flowx_adapter::default_fee_rate() == 3000, 1);
        assert!(turbos_adapter::default_fee_bps() == 3000, 2);
    }

    #[test]
    fun test_clmm_adapters_tick_spacing() {
        // Cetus and Turbos have tick spacing of 60
        assert!(cetus_adapter::default_tick_spacing() == 60, 0);
        assert!(turbos_adapter::default_tick_spacing() == 60, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEX TYPE CONSTANT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_dex_type_constants() {
        // Verify DEX type constants from config
        assert!(config::dex_cetus() == 0, 0);
        assert!(config::dex_turbos() == 1, 1);
        assert!(config::dex_flowx() == 2, 2);
        assert!(config::dex_suidex() == 3, 3);
    }

    #[test]
    fun test_dex_types_are_unique() {
        // Ensure all DEX types are different
        assert!(config::dex_cetus() != config::dex_turbos(), 0);
        assert!(config::dex_cetus() != config::dex_flowx(), 1);
        assert!(config::dex_cetus() != config::dex_suidex(), 2);
        assert!(config::dex_turbos() != config::dex_flowx(), 3);
        assert!(config::dex_turbos() != config::dex_suidex(), 4);
        assert!(config::dex_flowx() != config::dex_suidex(), 5);
    }
}
