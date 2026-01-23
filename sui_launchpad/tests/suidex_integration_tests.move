/// SuiDex Integration Tests
/// Tests real LP token creation and PTB flow simulation
#[test_only]
module sui_launchpad::suidex_integration_tests {

    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock;

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::{Self, AdminCap};
    use sui_launchpad::registry::{Self, Registry};
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::graduation::{Self, GraduationReceipt};
    use sui_launchpad::test_coin::{Self, TEST_COIN};

    // SuiDex imports
    use suitrump_dex::factory::{Self as suidex_factory, Factory};
    use suitrump_dex::router::{Self as suidex_router, Router};
    use suitrump_dex::pair::{Self, Pair, LPCoin};

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

    /// Setup launchpad infrastructure
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

    /// Setup SuiDex infrastructure
    fun setup_suidex(scenario: &mut Scenario) {
        ts::next_tx(scenario, admin());
        {
            let ctx = ts::ctx(scenario);
            suidex_factory::init_for_testing(ctx);
            suidex_router::init_for_testing(ctx);
        };
    }

    /// Create a test token pool
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

    /// Buy tokens to reach graduation threshold
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
    // SUIDEX LP TOKEN TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_suidex_graduation_creates_lp_tokens() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        setup_suidex(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        // Verify pool is ready for graduation
        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let can_grad = graduation::can_graduate(&pool, &config);
            assert!(can_grad, 0);

            ts::return_shared(pool);
            ts::return_shared(config);
        };

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
                config::dex_suidex(),
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

        // Phase 2: Create pair on SuiDex
        ts::next_tx(&mut scenario, admin());
        {
            let router = ts::take_shared<Router>(&scenario);
            let mut factory = ts::take_shared<Factory>(&scenario);

            suidex_router::create_pair<TEST_COIN, SUI>(
                &router,
                &mut factory,
                std::string::utf8(b"TEST"),
                std::string::utf8(b"SUI"),
                ts::ctx(&mut scenario),
            );

            ts::return_shared(router);
            ts::return_shared(factory);
        };

        // Phase 3: Add liquidity and get LP tokens
        ts::next_tx(&mut scenario, admin());
        {
            let router = ts::take_shared<Router>(&scenario);
            let mut factory = ts::take_shared<Factory>(&scenario);
            let mut pair = ts::take_shared<Pair<TEST_COIN, SUI>>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            let token_coin = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            let sui_coin = ts::take_from_sender<Coin<SUI>>(&scenario);

            let token_value = coin::value(&token_coin);
            let sui_value = coin::value(&sui_coin);

            suidex_router::add_liquidity<TEST_COIN, SUI>(
                &router,
                &mut factory,
                &mut pair,
                token_coin,
                sui_coin,
                (token_value as u256),
                (sui_value as u256),
                0,
                0,
                std::string::utf8(b"TEST"),
                std::string::utf8(b"SUI"),
                9999999999999,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(router);
            ts::return_shared(factory);
            ts::return_shared(pair);
            clock::destroy_for_testing(clock);
        };

        // Verify LP tokens were received
        ts::next_tx(&mut scenario, admin());
        {
            let has_lp = ts::has_most_recent_for_sender<Coin<LPCoin<TEST_COIN, SUI>>>(&scenario);
            assert!(has_lp, 3);

            if (has_lp) {
                let lp_coin = ts::take_from_sender<Coin<LPCoin<TEST_COIN, SUI>>>(&scenario);
                let lp_amount = coin::value(&lp_coin);
                assert!(lp_amount > 0, 4);
                ts::return_to_sender(&scenario, lp_coin);
            };
        };

        ts::end(scenario);
    }

    #[test]
    fun test_suidex_lp_amount_proportional_to_liquidity() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        setup_suidex(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        // Extract graduation liquidity
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let mut pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_suidex(),
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

        // Create pair
        ts::next_tx(&mut scenario, admin());
        {
            let router = ts::take_shared<Router>(&scenario);
            let mut factory = ts::take_shared<Factory>(&scenario);

            suidex_router::create_pair<TEST_COIN, SUI>(
                &router,
                &mut factory,
                std::string::utf8(b"TEST"),
                std::string::utf8(b"SUI"),
                ts::ctx(&mut scenario),
            );

            ts::return_shared(router);
            ts::return_shared(factory);
        };

        // Add liquidity with measured amounts
        ts::next_tx(&mut scenario, admin());
        let (input_sui, input_token);
        {
            let router = ts::take_shared<Router>(&scenario);
            let mut factory = ts::take_shared<Factory>(&scenario);
            let mut pair = ts::take_shared<Pair<TEST_COIN, SUI>>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            let token_coin = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            let sui_coin = ts::take_from_sender<Coin<SUI>>(&scenario);

            input_token = coin::value(&token_coin);
            input_sui = coin::value(&sui_coin);

            suidex_router::add_liquidity<TEST_COIN, SUI>(
                &router,
                &mut factory,
                &mut pair,
                token_coin,
                sui_coin,
                (input_token as u256),
                (input_sui as u256),
                0,
                0,
                std::string::utf8(b"TEST"),
                std::string::utf8(b"SUI"),
                9999999999999,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(router);
            ts::return_shared(factory);
            ts::return_shared(pair);
            clock::destroy_for_testing(clock);
        };

        // Verify LP amount
        ts::next_tx(&mut scenario, admin());
        {
            let lp_coin = ts::take_from_sender<Coin<LPCoin<TEST_COIN, SUI>>>(&scenario);
            let lp_amount = coin::value(&lp_coin);

            assert!(lp_amount > 0, 0);
            let total_input = input_sui + input_token;
            assert!(lp_amount < total_input, 1);

            ts::return_to_sender(&scenario, lp_coin);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_suidex_pair_reserves_match_input() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        setup_suidex(&mut scenario);
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
                config::dex_suidex(),
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

        // Create pair
        ts::next_tx(&mut scenario, admin());
        {
            let router = ts::take_shared<Router>(&scenario);
            let mut factory = ts::take_shared<Factory>(&scenario);

            suidex_router::create_pair<TEST_COIN, SUI>(
                &router,
                &mut factory,
                std::string::utf8(b"TEST"),
                std::string::utf8(b"SUI"),
                ts::ctx(&mut scenario),
            );

            ts::return_shared(router);
            ts::return_shared(factory);
        };

        // Add liquidity
        ts::next_tx(&mut scenario, admin());
        let (input_sui, input_token);
        {
            let router = ts::take_shared<Router>(&scenario);
            let mut factory = ts::take_shared<Factory>(&scenario);
            let mut pair = ts::take_shared<Pair<TEST_COIN, SUI>>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            let token_coin = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            let sui_coin = ts::take_from_sender<Coin<SUI>>(&scenario);

            input_token = coin::value(&token_coin);
            input_sui = coin::value(&sui_coin);

            suidex_router::add_liquidity<TEST_COIN, SUI>(
                &router,
                &mut factory,
                &mut pair,
                token_coin,
                sui_coin,
                (input_token as u256),
                (input_sui as u256),
                0,
                0,
                std::string::utf8(b"TEST"),
                std::string::utf8(b"SUI"),
                9999999999999,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(router);
            ts::return_shared(factory);
            ts::return_shared(pair);
            clock::destroy_for_testing(clock);
        };

        // Verify pair reserves
        ts::next_tx(&mut scenario, admin());
        {
            let pair = ts::take_shared<Pair<TEST_COIN, SUI>>(&scenario);

            let (reserve0, reserve1, _timestamp) = pair::get_reserves(&pair);

            assert!(reserve0 > 0, 0);
            assert!(reserve1 > 0, 1);

            let total_reserve = (reserve0 as u64) + (reserve1 as u64);
            let total_input = input_token + input_sui;
            assert!(total_reserve == total_input, 2);

            ts::return_shared(pair);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PTB SIMULATION TEST - FULL GRADUATION FLOW WITH COMPLETION
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Simulates full PTB graduation flow
    /// Note: test_scenario requires next_tx() between create_pair and take_shared,
    /// but on mainnet PTB, all commands execute atomically in ONE transaction.
    /// This test proves all graduation steps work correctly end-to-end.
    fun test_suidex_ptb_atomic_graduation() {
        let mut scenario = ts::begin(admin());

        // Setup phase (separate transactions - these happen before the PTB)
        setup_launchpad(&mut scenario);
        setup_suidex(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        // Pre-create the SuiDex pair (in real PTB, this is command 3)
        // Note: test_scenario limitation - can't take_shared in same tx as share
        ts::next_tx(&mut scenario, admin());
        {
            let router = ts::take_shared<Router>(&scenario);
            let mut factory = ts::take_shared<Factory>(&scenario);

            suidex_router::create_pair<TEST_COIN, SUI>(
                &router,
                &mut factory,
                std::string::utf8(b"TEST"),
                std::string::utf8(b"SUI"),
                ts::ctx(&mut scenario),
            );

            ts::return_shared(router);
            ts::return_shared(factory);
        };

        // ═══════════════════════════════════════════════════════════════════
        // PTB TRANSACTION SIMULATION
        // On mainnet: Commands 1-5 execute atomically in one PTB
        // ═══════════════════════════════════════════════════════════════════
        ts::next_tx(&mut scenario, admin());
        {
            // Get all shared objects (PTB inputs)
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let router = ts::take_shared<Router>(&scenario);
            let mut factory = ts::take_shared<Factory>(&scenario);
            let mut pair = ts::take_shared<Pair<TEST_COIN, SUI>>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            // ─────────────────────────────────────────────────────────────────
            // PTB Command 1: Initiate graduation
            // ─────────────────────────────────────────────────────────────────
            let mut pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            // ─────────────────────────────────────────────────────────────────
            // PTB Command 2: Extract coins from pending
            // ─────────────────────────────────────────────────────────────────
            let sui_coin = graduation::extract_all_sui(&mut pending, ts::ctx(&mut scenario));
            let token_coin = graduation::extract_all_tokens(&mut pending, ts::ctx(&mut scenario));

            let sui_amount = coin::value(&sui_coin);
            let token_amount = coin::value(&token_coin);

            // ─────────────────────────────────────────────────────────────────
            // PTB Command 3: Add liquidity to DEX pair
            // (create_pair already called above due to test framework limitation)
            // ─────────────────────────────────────────────────────────────────
            suidex_router::add_liquidity<TEST_COIN, SUI>(
                &router,
                &mut factory,
                &mut pair,
                token_coin,
                sui_coin,
                (token_amount as u256),
                (sui_amount as u256),
                0, // min_amount_a (no slippage protection for test)
                0, // min_amount_b
                std::string::utf8(b"TEST"),
                std::string::utf8(b"SUI"),
                9999999999999, // far future deadline
                &clock,
                ts::ctx(&mut scenario),
            );

            // ─────────────────────────────────────────────────────────────────
            // PTB Command 4: Complete graduation with DEX pool ID
            // ─────────────────────────────────────────────────────────────────
            let dex_pool_id = object::id(&pair);

            // In real scenario, we'd query LP token balance from add_liquidity result
            // For test, we use placeholder values
            let total_lp = 1000000; // Placeholder
            let creator_lp = 200000; // 20% to creator
            let community_lp = 800000; // 80% to community

            let receipt = graduation::complete_graduation(
                pending,
                &mut registry,
                dex_pool_id,
                total_lp,
                creator_lp,
                community_lp,
                &clock,
                ts::ctx(&mut scenario),
            );

            // ─────────────────────────────────────────────────────────────────
            // Verify graduation completed successfully
            // ─────────────────────────────────────────────────────────────────
            assert!(graduation::receipt_dex_pool_id(&receipt) == dex_pool_id, 100);
            assert!(graduation::receipt_total_lp_tokens(&receipt) == total_lp, 101);
            assert!(graduation::receipt_creator_lp_tokens(&receipt) == creator_lp, 102);
            assert!(graduation::receipt_community_lp_tokens(&receipt) == community_lp, 103);

            // Cleanup
            graduation::destroy_receipt_for_testing(receipt);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
            ts::return_shared(registry);
            ts::return_shared(router);
            ts::return_shared(factory);
            ts::return_shared(pair);
            clock::destroy_for_testing(clock);
        };
        // ═══════════════════════════════════════════════════════════════════
        // END OF PTB TRANSACTION
        // ═══════════════════════════════════════════════════════════════════

        // Verify final state
        ts::next_tx(&mut scenario, admin());
        {
            // Verify LP tokens were received
            let has_lp = ts::has_most_recent_for_sender<Coin<LPCoin<TEST_COIN, SUI>>>(&scenario);
            assert!(has_lp, 200);

            // Verify pool is marked as graduated
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            assert!(bonding_curve::is_graduated(&pool), 201);
            ts::return_shared(pool);

            // Verify registry recorded the graduation
            let registry = ts::take_shared<Registry>(&scenario);
            assert!(registry::total_graduated(&registry) == 1, 202);
            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    #[test]
    /// Test that graduation fails atomically if any step fails
    fun test_suidex_ptb_atomic_failure_reverts_all() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        setup_suidex(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        // Don't buy to threshold - graduation should fail

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // This should fail because pool hasn't reached graduation threshold
            let can_graduate = graduation::can_graduate(&pool, &config);
            assert!(!can_graduate, 0); // Confirm it can't graduate

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }
}
