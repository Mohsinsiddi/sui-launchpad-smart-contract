/// FlowX CLMM Integration Tests
/// Tests real Position NFT creation
#[test_only]
module sui_launchpad::flowx_integration_tests {

    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock;

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::{Self, AdminCap};
    use sui_launchpad::registry::{Self};
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::graduation;
    use sui_launchpad::test_coin::{Self, TEST_COIN};

    // FlowX CLMM imports
    use flowx_clmm::versioned::{Self as flowx_versioned, Versioned as FlowXVersioned};
    use flowx_clmm::pool_manager::{Self as flowx_pool_manager, PoolRegistry as FlowXPoolRegistry};
    use flowx_clmm::position_manager::{Self as flowx_position_manager, PositionRegistry as FlowXPositionRegistry};
    use flowx_clmm::position::Position as FlowXPosition;
    use flowx_clmm::i32 as flowx_i32;

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

    fun setup_launchpad(scenario: &mut Scenario) {
        ts::next_tx(scenario, admin());
        {
            let ctx = ts::ctx(scenario);
            let admin_cap = access::create_admin_cap(ctx);
            transfer::public_transfer(admin_cap, admin());

            let config = config::create_config(treasury(), ctx);
            transfer::public_share_object(config);

            let registry = registry::create_registry(ctx);
            transfer::public_share_object(registry);
        };
    }

    fun setup_flowx(scenario: &mut Scenario) {
        ts::next_tx(scenario, admin());
        {
            let ctx = ts::ctx(scenario);
            let versioned = flowx_versioned::create_for_testing(ctx);
            let mut pool_registry = flowx_pool_manager::create_for_testing(ctx);
            let position_registry = flowx_position_manager::create_for_testing(ctx);

            // Enable fee rate (fee_rate=3000 = 0.3%, tick_spacing=60)
            flowx_pool_manager::enable_fee_rate_for_testing(&mut pool_registry, 3000, 60);

            transfer::public_share_object(versioned);
            transfer::public_share_object(pool_registry);
            transfer::public_share_object(position_registry);
        };
    }

    fun create_test_pool(scenario: &mut Scenario): ID {
        ts::next_tx(scenario, creator());
        let pool_id;
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(ts::ctx(scenario));
            let config = ts::take_shared<LaunchpadConfig>(scenario);
            let clock = clock::create_for_testing(ts::ctx(scenario));

            let creation_fee = config::creation_fee(&config);
            let payment = coin::mint_for_testing<SUI>(creation_fee, ts::ctx(scenario));

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                ts::ctx(scenario),
            );

            pool_id = object::id(&pool);
            transfer::public_share_object(pool);
            ts::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };
        pool_id
    }

    fun buy_to_graduation_threshold(scenario: &mut Scenario) {
        ts::next_tx(scenario, buyer());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(scenario);
            let config = ts::take_shared<LaunchpadConfig>(scenario);
            let clock = clock::create_for_testing(ts::ctx(scenario));

            let threshold = config::graduation_threshold(&config);
            let buy_amount = threshold + (threshold / 10);

            let payment = coin::mint_for_testing<SUI>(buy_amount, ts::ctx(scenario));
            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                0,
                &clock,
                ts::ctx(scenario),
            );

            transfer::public_transfer(tokens, buyer());

            ts::return_shared(pool);
            ts::return_shared(config);
            clock::destroy_for_testing(clock);
        };
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FLOWX POSITION NFT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_flowx_graduation_creates_position_nft() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        setup_flowx(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        // Phase 1: Initiate graduation and extract coins
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let mut pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_flowx(),
                ts::ctx(&mut scenario),
            );

            let sui_coin = graduation::extract_all_sui(&mut pending, ts::ctx(&mut scenario));
            let token_coin = graduation::extract_all_tokens(&mut pending, ts::ctx(&mut scenario));

            let sui_amount = coin::value(&sui_coin);
            let token_amount = coin::value(&token_coin);

            assert!(sui_amount > 0, 1);
            assert!(token_amount > 0, 2);

            transfer::public_transfer(sui_coin, admin());
            transfer::public_transfer(token_coin, admin());
            graduation::destroy_pending_for_testing(pending);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        // Phase 2: Create pool on FlowX
        ts::next_tx(&mut scenario, admin());
        {
            let versioned = ts::take_shared<FlowXVersioned>(&scenario);
            let mut pool_registry = ts::take_shared<FlowXPoolRegistry>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            // Create and initialize pool with sqrt_price (1:1 ratio = sqrt(1) * 2^64)
            let sqrt_price: u128 = 18446744073709551616; // 1 << 64

            // FlowX requires X < Y in type order (alphabetically)
            flowx_pool_manager::create_and_initialize_pool<TEST_COIN, SUI>(
                &mut pool_registry,
                3000, // fee_rate (0.3%)
                sqrt_price,
                &versioned,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(versioned);
            ts::return_shared(pool_registry);
            clock::destroy_for_testing(clock);
        };

        // Phase 3: Open position
        ts::next_tx(&mut scenario, admin());
        {
            let versioned = ts::take_shared<FlowXVersioned>(&scenario);
            let pool_registry = ts::take_shared<FlowXPoolRegistry>(&scenario);
            let mut position_registry = ts::take_shared<FlowXPositionRegistry>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            let token_coin = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            let sui_coin = ts::take_from_sender<Coin<SUI>>(&scenario);

            // TICK_BOUND is 443636, so valid range is [-443636, +443636]
            // Use ticks divisible by 60
            let tick_lower = flowx_i32::neg_from(443580);
            let tick_upper = flowx_i32::from(443580);

            // Open position (must match pool type order)
            let position = flowx_position_manager::open_position<TEST_COIN, SUI>(
                &mut position_registry,
                &pool_registry,
                3000, // fee_rate
                tick_lower,
                tick_upper,
                &versioned,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(position, admin());
            transfer::public_transfer(token_coin, admin());
            transfer::public_transfer(sui_coin, admin());

            ts::return_shared(versioned);
            ts::return_shared(pool_registry);
            ts::return_shared(position_registry);
            clock::destroy_for_testing(clock);
        };

        // Verify Position NFT was received
        ts::next_tx(&mut scenario, admin());
        {
            let has_position = ts::has_most_recent_for_sender<FlowXPosition>(&scenario);
            assert!(has_position, 3);

            if (has_position) {
                let position = ts::take_from_sender<FlowXPosition>(&scenario);
                let pool_id = flowx_clmm::position::pool_id(&position);
                assert!(object::id_to_address(&pool_id) != @0x0, 4);
                ts::return_to_sender(&scenario, position);
            };
        };

        ts::end(scenario);
    }

    #[test]
    fun test_flowx_position_has_correct_tick_range() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        setup_flowx(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        // Extract liquidity
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let mut pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_flowx(),
                ts::ctx(&mut scenario),
            );

            let sui_coin = graduation::extract_all_sui(&mut pending, ts::ctx(&mut scenario));
            let token_coin = graduation::extract_all_tokens(&mut pending, ts::ctx(&mut scenario));

            transfer::public_transfer(sui_coin, admin());
            transfer::public_transfer(token_coin, admin());
            graduation::destroy_pending_for_testing(pending);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        // Create FlowX pool
        ts::next_tx(&mut scenario, admin());
        {
            let versioned = ts::take_shared<FlowXVersioned>(&scenario);
            let mut pool_registry = ts::take_shared<FlowXPoolRegistry>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            let sqrt_price: u128 = 18446744073709551616;

            flowx_pool_manager::create_and_initialize_pool<TEST_COIN, SUI>(
                &mut pool_registry,
                3000,
                sqrt_price,
                &versioned,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(versioned);
            ts::return_shared(pool_registry);
            clock::destroy_for_testing(clock);
        };

        // Open position with specific tick range
        ts::next_tx(&mut scenario, admin());
        {
            let versioned = ts::take_shared<FlowXVersioned>(&scenario);
            let pool_registry = ts::take_shared<FlowXPoolRegistry>(&scenario);
            let mut position_registry = ts::take_shared<FlowXPositionRegistry>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            let token_coin = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            let sui_coin = ts::take_from_sender<Coin<SUI>>(&scenario);

            // Use specific tick range for testing
            let tick_lower = flowx_i32::neg_from(60000); // divisible by 60
            let tick_upper = flowx_i32::from(60000);

            let position = flowx_position_manager::open_position<TEST_COIN, SUI>(
                &mut position_registry,
                &pool_registry,
                3000,
                tick_lower,
                tick_upper,
                &versioned,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(position, admin());
            transfer::public_transfer(token_coin, admin());
            transfer::public_transfer(sui_coin, admin());

            ts::return_shared(versioned);
            ts::return_shared(pool_registry);
            ts::return_shared(position_registry);
            clock::destroy_for_testing(clock);
        };

        // Verify tick range
        ts::next_tx(&mut scenario, admin());
        {
            let position = ts::take_from_sender<FlowXPosition>(&scenario);

            let lower = flowx_clmm::position::tick_lower_index(&position);
            let upper = flowx_clmm::position::tick_upper_index(&position);

            // Verify ticks are as expected
            assert!(flowx_i32::is_neg(lower), 0);
            assert!(!flowx_i32::is_neg(upper), 1);

            ts::return_to_sender(&scenario, position);
        };

        ts::end(scenario);
    }
}
