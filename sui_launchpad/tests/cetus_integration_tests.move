/// Cetus CLMM Integration Tests
/// Tests real Position NFT creation
#[test_only]
module sui_launchpad::cetus_integration_tests {

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

    // Cetus CLMM imports
    use cetus_clmm::config::{Self as cetus_config, GlobalConfig as CetusConfig};
    use cetus_clmm::factory::{Self as cetus_factory, Pools as CetusPools};
    use cetus_clmm::pool_creator;
    use cetus_clmm::position::Position as CetusPosition;
    use cetus_clmm::tick_math::get_sqrt_price_at_tick;
    use integer_mate::i32;

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

    fun setup_cetus(scenario: &mut Scenario) {
        ts::next_tx(scenario, admin());
        {
            let ctx = ts::ctx(scenario);
            let (admin_cap, mut config) = cetus_config::new_global_config_for_test(ctx, 1000);
            config.add_fee_tier(200, 1000, ctx);

            let mut pools = cetus_factory::new_pools_for_test(ctx);
            cetus_factory::init_manager_and_whitelist(&config, &mut pools, ctx);

            transfer::public_transfer(admin_cap, admin());
            transfer::public_share_object(config);
            transfer::public_share_object(pools);
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
    // CETUS POSITION NFT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_cetus_graduation_creates_position_nft() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        setup_cetus(&mut scenario);
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
                config::dex_cetus(),
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

        // Phase 2: Create pool on Cetus and get Position NFT
        ts::next_tx(&mut scenario, admin());
        {
            let cetus_config = ts::take_shared<CetusConfig>(&scenario);
            let mut cetus_pools = ts::take_shared<CetusPools>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            let token_coin = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            let sui_coin = ts::take_from_sender<Coin<SUI>>(&scenario);

            let init_sqrt_price = get_sqrt_price_at_tick(i32::from(1000));

            let (position, remaining_sui, remaining_token) = pool_creator::create_pool_v3<SUI, TEST_COIN>(
                &cetus_config,
                &mut cetus_pools,
                200,
                init_sqrt_price,
                std::string::utf8(b"https://test.pool"),
                0,
                2000,
                sui_coin,
                token_coin,
                true, // fix_amount_a - fix SUI amount
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(position, admin());
            remaining_sui.into_balance().destroy_for_testing();
            remaining_token.into_balance().destroy_for_testing();

            ts::return_shared(cetus_config);
            ts::return_shared(cetus_pools);
            clock::destroy_for_testing(clock);
        };

        // Verify Position NFT was received
        ts::next_tx(&mut scenario, admin());
        {
            let has_position = ts::has_most_recent_for_sender<CetusPosition>(&scenario);
            assert!(has_position, 3);

            if (has_position) {
                let position = ts::take_from_sender<CetusPosition>(&scenario);
                let liquidity = cetus_clmm::position::liquidity(&position);
                assert!(liquidity > 0, 4);
                ts::return_to_sender(&scenario, position);
            };
        };

        ts::end(scenario);
    }

    #[test]
    fun test_cetus_position_has_correct_tick_range() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        setup_cetus(&mut scenario);
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
                config::dex_cetus(),
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

        // Create Cetus pool
        ts::next_tx(&mut scenario, admin());
        {
            let cetus_config = ts::take_shared<CetusConfig>(&scenario);
            let mut cetus_pools = ts::take_shared<CetusPools>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            let token_coin = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            let sui_coin = ts::take_from_sender<Coin<SUI>>(&scenario);

            let init_sqrt_price = get_sqrt_price_at_tick(i32::from(1000));

            let (position, remaining_sui, remaining_token) = pool_creator::create_pool_v3<SUI, TEST_COIN>(
                &cetus_config,
                &mut cetus_pools,
                200,
                init_sqrt_price,
                std::string::utf8(b"https://test.pool"),
                0,
                2000,
                sui_coin,
                token_coin,
                true, // fix_amount_a - fix SUI amount
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(position, admin());
            remaining_sui.into_balance().destroy_for_testing();
            remaining_token.into_balance().destroy_for_testing();

            ts::return_shared(cetus_config);
            ts::return_shared(cetus_pools);
            clock::destroy_for_testing(clock);
        };

        // Verify tick range
        ts::next_tx(&mut scenario, admin());
        {
            let position = ts::take_from_sender<CetusPosition>(&scenario);

            let (tick_lower, tick_upper) = cetus_clmm::position::tick_range(&position);

            assert!(i32::as_u32(tick_lower) == 0, 0);
            assert!(i32::as_u32(tick_upper) == 2000, 1);

            ts::return_to_sender(&scenario, position);
        };

        ts::end(scenario);
    }
}
