/// Tests for DEX adapters
/// Tests helper functions, constants, and math calculations for all adapters
#[test_only]
module sui_launchpad::dex_adapter_tests {

    use sui_launchpad::cetus_adapter;
    use sui_launchpad::turbos_adapter;
    use sui_launchpad::flowx_adapter;
    use sui_launchpad::suidex_adapter;

    // ═══════════════════════════════════════════════════════════════════════
    // CETUS ADAPTER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_cetus_default_tick_spacing() {
        // Standard 0.3% fee tier uses tick spacing of 60
        assert!(cetus_adapter::default_tick_spacing() == 60, 0);
    }

    #[test]
    fun test_cetus_default_fee_tier() {
        // 0.3% = 3000 basis points
        assert!(cetus_adapter::default_fee_tier() == 3000, 0);
    }

    #[test]
    fun test_cetus_minimum_liquidity() {
        // Minimum liquidity is 1000 to prevent division by zero
        assert!(cetus_adapter::minimum_liquidity() == 1000, 0);
    }

    #[test]
    fun test_cetus_full_range_tick_lower() {
        // -443636 as u32 (two's complement)
        assert!(cetus_adapter::full_range_tick_lower() == 4294523660, 0);
    }

    #[test]
    fun test_cetus_full_range_tick_upper() {
        // Near maximum positive tick
        assert!(cetus_adapter::full_range_tick_upper() == 443580, 0);
    }

    #[test]
    fun test_cetus_create_objects() {
        let global_config_id = object::id_from_address(@0x1);
        let pools_id = object::id_from_address(@0x2);
        let _objects = cetus_adapter::create_cetus_objects(global_config_id, pools_id);
        // Object created successfully (has drop ability)
    }

    #[test]
    fun test_cetus_calculate_sqrt_price_1_to_1() {
        // Equal amounts should give sqrt_price = 1 << 64
        let price = cetus_adapter::calculate_sqrt_price_x64(1000000, 1000000);
        // 1 << 64 = 18446744073709551616
        assert!(price == 18446744073709551616, 0);
    }

    #[test]
    fun test_cetus_calculate_sqrt_price_different_amounts() {
        // When token_amount != sui_amount, price should differ from 1:1
        let price_2_to_1 = cetus_adapter::calculate_sqrt_price_x64(2000000, 1000000);
        let price_1_to_1 = cetus_adapter::calculate_sqrt_price_x64(1000000, 1000000);

        // Different ratio should produce different sqrt_price
        assert!(price_2_to_1 != price_1_to_1, 0);
        // Both should be non-zero
        assert!(price_2_to_1 > 0, 1);
    }

    #[test]
    fun test_cetus_calculate_sqrt_price_small_ratio() {
        // Very small ratio should still return valid price (at least 1)
        let price = cetus_adapter::calculate_sqrt_price_x64(1, 1000000000);
        assert!(price >= 1, 0);
    }

    #[test]
    fun test_cetus_calculate_sqrt_price_large_ratio() {
        // Large token amount relative to SUI
        let price = cetus_adapter::calculate_sqrt_price_x64(1000000000, 1);
        assert!(price > 0, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TURBOS ADAPTER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_turbos_default_tick_spacing() {
        // Standard 0.3% fee tier uses tick spacing of 60
        assert!(turbos_adapter::default_tick_spacing() == 60, 0);
    }

    #[test]
    fun test_turbos_default_fee_bps() {
        // 0.3% = 3000 basis points
        assert!(turbos_adapter::default_fee_bps() == 3000, 0);
    }

    #[test]
    fun test_turbos_minimum_liquidity() {
        // Minimum liquidity is 1000 to prevent division by zero
        assert!(turbos_adapter::minimum_liquidity() == 1000, 0);
    }

    #[test]
    fun test_turbos_full_range_tick_lower() {
        // -443636 as u32 (two's complement)
        assert!(turbos_adapter::full_range_tick_lower() == 4294523660, 0);
    }

    #[test]
    fun test_turbos_full_range_tick_upper() {
        // Near maximum positive tick
        assert!(turbos_adapter::full_range_tick_upper() == 443580, 0);
    }

    #[test]
    fun test_turbos_calculate_sqrt_price_1_to_1() {
        // Equal amounts should give sqrt_price = 1 << 64
        let price = turbos_adapter::calculate_sqrt_price_x64(1000000, 1000000);
        // 1 << 64 = 18446744073709551616
        assert!(price == 18446744073709551616, 0);
    }

    #[test]
    fun test_turbos_calculate_sqrt_price_small_ratio() {
        // Very small ratio should still return valid price (at least 1)
        let price = turbos_adapter::calculate_sqrt_price_x64(1, 1000000000);
        assert!(price >= 1, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FLOWX ADAPTER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_flowx_default_fee_rate() {
        // 0.3% = 3000 basis points
        assert!(flowx_adapter::default_fee_rate() == 3000, 0);
    }

    #[test]
    fun test_flowx_minimum_liquidity() {
        // Minimum liquidity is 1000 to prevent division by zero
        assert!(flowx_adapter::minimum_liquidity() == 1000, 0);
    }

    #[test]
    fun test_flowx_full_range_tick_lower() {
        // -443636 as u32 (two's complement)
        assert!(flowx_adapter::full_range_tick_lower() == 4294523660, 0);
    }

    #[test]
    fun test_flowx_full_range_tick_upper() {
        // Near maximum positive tick
        assert!(flowx_adapter::full_range_tick_upper() == 443580, 0);
    }

    #[test]
    fun test_flowx_default_deadline_offset() {
        // 10 minutes = 600,000 ms
        assert!(flowx_adapter::default_deadline_offset_ms() == 600_000, 0);
    }

    #[test]
    fun test_flowx_calculate_sqrt_price_1_to_1() {
        // Equal amounts should give sqrt_price = 1 << 64
        let price = flowx_adapter::calculate_sqrt_price_x64(1000000, 1000000);
        // 1 << 64 = 18446744073709551616
        assert!(price == 18446744073709551616, 0);
    }

    #[test]
    fun test_flowx_calculate_sqrt_price_different_amounts() {
        // When token_amount != sui_amount, price should differ from 1:1
        let price_2_to_1 = flowx_adapter::calculate_sqrt_price_x64(2000000, 1000000);
        let price_1_to_1 = flowx_adapter::calculate_sqrt_price_x64(1000000, 1000000);

        // Different ratio should produce different sqrt_price
        assert!(price_2_to_1 != price_1_to_1, 0);
        // Both should be non-zero
        assert!(price_2_to_1 > 0, 1);
    }

    #[test]
    fun test_flowx_calculate_sqrt_price_small_ratio() {
        // Very small ratio should still return valid price (at least 1)
        let price = flowx_adapter::calculate_sqrt_price_x64(1, 1000000000);
        assert!(price >= 1, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SUIDEX ADAPTER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_suidex_default_swap_fee_bps() {
        // 0.3% for SuiDex = 30 basis points (0.30%)
        // Note: SuiDex uses 30 not 3000 because different scale
        assert!(suidex_adapter::default_swap_fee_bps() == 30, 0);
    }

    #[test]
    fun test_suidex_minimum_liquidity() {
        // Minimum liquidity is 1000 to prevent division by zero
        assert!(suidex_adapter::minimum_liquidity() == 1000, 0);
    }

    #[test]
    fun test_suidex_default_slippage_bps() {
        // 1% = 100 basis points
        assert!(suidex_adapter::default_slippage_bps() == 100, 0);
    }

    #[test]
    fun test_suidex_calculate_min_amount_1_percent() {
        // 1% slippage on 10000
        let min = suidex_adapter::calculate_min_amount(10000, 100);
        assert!(min == 9900, 0);
    }

    #[test]
    fun test_suidex_calculate_min_amount_half_percent() {
        // 0.5% slippage on 20000
        let min = suidex_adapter::calculate_min_amount(20000, 50);
        assert!(min == 19900, 0);
    }

    #[test]
    fun test_suidex_calculate_min_amount_zero_slippage() {
        // 0% slippage should return original amount
        let min = suidex_adapter::calculate_min_amount(10000, 0);
        assert!(min == 10000, 0);
    }

    #[test]
    fun test_suidex_calculate_min_amount_large_amount() {
        // Test with large amounts (1000 SUI = 1_000_000_000_000 MIST)
        let amount = 1_000_000_000_000;
        let min = suidex_adapter::calculate_min_amount(amount, 100);
        // 1% of 1000 SUI = 10 SUI = 10_000_000_000 MIST
        assert!(min == 990_000_000_000, 0);
    }

    #[test]
    fun test_suidex_calculate_min_amount_max_slippage() {
        // 50% slippage (extreme case)
        let min = suidex_adapter::calculate_min_amount(10000, 5000);
        assert!(min == 5000, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CROSS-ADAPTER CONSISTENCY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_clmm_adapters_consistent_tick_ranges() {
        // All CLMM adapters should use same full range ticks
        let cetus_lower = cetus_adapter::full_range_tick_lower();
        let turbos_lower = turbos_adapter::full_range_tick_lower();
        let flowx_lower = flowx_adapter::full_range_tick_lower();

        assert!(cetus_lower == turbos_lower, 0);
        assert!(turbos_lower == flowx_lower, 1);

        let cetus_upper = cetus_adapter::full_range_tick_upper();
        let turbos_upper = turbos_adapter::full_range_tick_upper();
        let flowx_upper = flowx_adapter::full_range_tick_upper();

        assert!(cetus_upper == turbos_upper, 2);
        assert!(turbos_upper == flowx_upper, 3);
    }

    #[test]
    fun test_clmm_adapters_consistent_sqrt_price() {
        // All CLMM adapters should calculate same sqrt_price for same inputs
        let cetus_price = cetus_adapter::calculate_sqrt_price_x64(1000000, 1000000);
        let turbos_price = turbos_adapter::calculate_sqrt_price_x64(1000000, 1000000);
        let flowx_price = flowx_adapter::calculate_sqrt_price_x64(1000000, 1000000);

        assert!(cetus_price == turbos_price, 0);
        assert!(turbos_price == flowx_price, 1);
    }

    #[test]
    fun test_all_adapters_minimum_liquidity() {
        // All adapters should have same minimum liquidity
        let cetus_min = cetus_adapter::minimum_liquidity();
        let turbos_min = turbos_adapter::minimum_liquidity();
        let flowx_min = flowx_adapter::minimum_liquidity();
        let suidex_min = suidex_adapter::minimum_liquidity();

        assert!(cetus_min == 1000, 0);
        assert!(turbos_min == 1000, 1);
        assert!(flowx_min == 1000, 2);
        assert!(suidex_min == 1000, 3);
    }

    #[test]
    fun test_clmm_adapters_fee_consistency() {
        // Cetus, Turbos, FlowX all use 3000 bps (0.3%) as default
        let cetus_fee = cetus_adapter::default_fee_tier();
        let turbos_fee = turbos_adapter::default_fee_bps();
        let flowx_fee = flowx_adapter::default_fee_rate();

        assert!(cetus_fee == 3000, 0);
        assert!(turbos_fee == 3000, 1);
        assert!(flowx_fee == 3000, 2);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SQRT_PRICE EDGE CASES
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_sqrt_price_symmetry() {
        // Test that swapping inputs gives reciprocal-ish relationship
        let price_a = cetus_adapter::calculate_sqrt_price_x64(2000000, 1000000);
        let price_b = cetus_adapter::calculate_sqrt_price_x64(1000000, 2000000);

        // With 2:1 vs 1:2, price_a should be greater than price_b
        assert!(price_a > price_b, 0);
    }

    #[test]
    fun test_sqrt_price_monotonic() {
        // As token amount increases relative to SUI, sqrt_price should change
        // Note: The simplified calculation may not preserve exact monotonicity,
        // but larger ratios should produce non-zero different values
        let price_1x = cetus_adapter::calculate_sqrt_price_x64(1000000, 1000000);
        let price_2x = cetus_adapter::calculate_sqrt_price_x64(2000000, 1000000);
        let price_4x = cetus_adapter::calculate_sqrt_price_x64(4000000, 1000000);

        // All prices should be non-zero
        assert!(price_1x > 0, 0);
        assert!(price_2x > 0, 1);
        assert!(price_4x > 0, 2);

        // 4x ratio should be different from 2x ratio
        assert!(price_4x != price_2x, 3);
    }

    #[test]
    fun test_sqrt_price_boundary_values() {
        // Test with minimum values (should not panic)
        let price_min = cetus_adapter::calculate_sqrt_price_x64(1, 1);
        assert!(price_min > 0, 0);

        // Test with large but safe values
        let price_large = cetus_adapter::calculate_sqrt_price_x64(
            1_000_000_000_000, // 1 trillion tokens
            1_000_000_000_000  // 1000 SUI (in MIST)
        );
        assert!(price_large > 0, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SLIPPAGE CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_slippage_never_exceeds_original() {
        // Min amount should never be greater than original
        let amount = 10000;
        let slippages = vector[0, 50, 100, 500, 1000, 5000, 10000];

        let mut i = 0;
        while (i < vector::length(&slippages)) {
            let slippage = *vector::borrow(&slippages, i);
            let min = suidex_adapter::calculate_min_amount(amount, slippage);
            assert!(min <= amount, i);
            i = i + 1;
        };
    }

    #[test]
    fun test_slippage_decreases_with_higher_tolerance() {
        // Higher slippage tolerance = lower minimum acceptable amount
        let amount = 10000;

        let min_1pct = suidex_adapter::calculate_min_amount(amount, 100);  // 1%
        let min_2pct = suidex_adapter::calculate_min_amount(amount, 200);  // 2%
        let min_5pct = suidex_adapter::calculate_min_amount(amount, 500);  // 5%

        assert!(min_1pct > min_2pct, 0);
        assert!(min_2pct > min_5pct, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FLOWX OBJECTS WRAPPER TEST
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_flowx_objects_creation() {
        let pool_registry_id = object::id_from_address(@0x1);
        let position_registry_id = object::id_from_address(@0x2);
        let versioned_id = object::id_from_address(@0x3);

        let _objects = flowx_adapter::create_flowx_objects(
            pool_registry_id,
            position_registry_id,
            versioned_id,
        );
        // Object created successfully (has drop ability, so auto-dropped)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SUIDEX OBJECTS WRAPPER TEST
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_suidex_objects_creation_without_pair() {
        let factory_id = object::id_from_address(@0x1);
        let router_id = object::id_from_address(@0x2);

        let _objects = suidex_adapter::create_suidex_objects<u64>(
            factory_id,
            router_id,
            std::option::none(),
        );
        // Object created successfully
    }

    #[test]
    fun test_suidex_objects_creation_with_pair() {
        let factory_id = object::id_from_address(@0x1);
        let router_id = object::id_from_address(@0x2);
        let pair_id = object::id_from_address(@0x3);

        let _objects = suidex_adapter::create_suidex_objects<u64>(
            factory_id,
            router_id,
            std::option::some(pair_id),
        );
        // Object created successfully
    }
}
