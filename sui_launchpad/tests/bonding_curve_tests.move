/// Comprehensive tests for the bonding curve module
#[test_only]
module sui_launchpad::bonding_curve_tests {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::test_scenario::{Self, Scenario};
    use sui::clock::{Self, Clock};

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::{Self, AdminCap};
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::test_coin::{Self, TEST_COIN};

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

    fun setup_config(scenario: &mut Scenario) {
        scenario.next_tx(admin());
        {
            let ctx = scenario.ctx();
            let admin_cap = access::create_admin_cap(ctx);
            transfer::public_transfer(admin_cap, admin());

            let config = config::create_config(treasury(), ctx);
            transfer::public_share_object(config);
        };
    }

    fun mint_sui(amount: u64, scenario: &mut Scenario): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, scenario.ctx())
    }

    fun create_clock(scenario: &mut Scenario): Clock {
        clock::create_for_testing(scenario.ctx())
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POOL CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_pool_success() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        // Creator creates a pool
        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0, // no creator fee
                payment,
                &clock,
                scenario.ctx(),
            );

            // Verify pool state
            assert!(bonding_curve::creator(&pool) == creator(), 0);
            assert!(bonding_curve::creator_fee_bps(&pool) == 0, 1);
            assert!(!bonding_curve::is_paused(&pool), 2);
            assert!(!bonding_curve::is_graduated(&pool), 3);
            assert!(bonding_curve::is_treasury_cap_frozen(&pool), 4);
            assert!(bonding_curve::circulating_supply(&pool) == 0, 5);
            assert!(bonding_curve::total_volume(&pool) == 0, 6);
            assert!(bonding_curve::trade_count(&pool) == 0, 7);

            // Cleanup
            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    #[test]
    fun test_create_pool_with_creator_fee() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                500, // 5% creator fee (max allowed)
                payment,
                &clock,
                scenario.ctx(),
            );

            assert!(bonding_curve::creator_fee_bps(&pool) == 500, 0);

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 308)] // ECreatorFeeTooHigh
    fun test_create_pool_creator_fee_too_high() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            // Try to create pool with 6% creator fee (max is 5%)
            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                600, // 6% - should fail
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 303)] // EInsufficientPayment
    fun test_create_pool_insufficient_payment() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            // Pay less than required
            let payment = mint_sui(100_000_000, &mut scenario); // 0.1 SUI (need 0.5)

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    #[test]
    fun test_create_pool_excess_payment_refunded() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let excess = 100_000_000; // 0.1 SUI extra
            let payment = mint_sui(creation_fee + excess, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Verify creator received refund
        scenario.next_tx(creator());
        {
            let refund = scenario.take_from_sender<Coin<SUI>>();
            assert!(coin::value(&refund) == 100_000_000, 0);
            transfer::public_transfer(refund, creator());
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BUY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_buy_tokens_success() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        // Create pool
        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Buyer buys tokens
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let sui_in = 1_000_000_000; // 1 SUI
            let payment = mint_sui(sui_in, &mut scenario);

            let initial_supply = bonding_curve::circulating_supply(&pool);
            let initial_volume = bonding_curve::total_volume(&pool);
            let initial_trade_count = bonding_curve::trade_count(&pool);

            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                0, // no min tokens (accept any)
                &clock,
                scenario.ctx(),
            );

            // Verify tokens received
            assert!(coin::value(&tokens) > 0, 0);

            // Verify pool state updated
            assert!(bonding_curve::circulating_supply(&pool) > initial_supply, 1);
            assert!(bonding_curve::total_volume(&pool) > initial_volume, 2);
            assert!(bonding_curve::trade_count(&pool) == initial_trade_count + 1, 3);

            // Verify SUI added to pool
            assert!(bonding_curve::sui_balance(&pool) > 0, 4);

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 306)] // ESlippageExceeded
    fun test_buy_tokens_slippage_exceeded() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        // Create pool
        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Buyer tries to buy with unrealistic min_tokens_out
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let sui_in = 1_000_000_000;
            let payment = mint_sui(sui_in, &mut scenario);

            // Set min_tokens_out way too high
            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                1_000_000_000_000_000_000, // impossibly high
                &clock,
                scenario.ctx(),
            );

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 305)] // EZeroAmount
    fun test_buy_tokens_zero_amount() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        // Create pool
        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Buyer tries to buy with zero SUI
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let payment = mint_sui(0, &mut scenario);

            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                0,
                &clock,
                scenario.ctx(),
            );

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SELL TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_sell_tokens_success() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        // Create pool
        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Buyer buys tokens first
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let sui_in = 10_000_000_000; // 10 SUI
            let payment = mint_sui(sui_in, &mut scenario);

            let initial_supply = bonding_curve::circulating_supply(&pool);
            let initial_sui = bonding_curve::sui_balance(&pool);

            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                0,
                &clock,
                scenario.ctx(),
            );

            // Strict assertions for buy
            let tokens_received = coin::value(&tokens);
            assert!(tokens_received > 0, 100);
            assert!(bonding_curve::circulating_supply(&pool) == initial_supply + tokens_received, 101);
            assert!(bonding_curve::sui_balance(&pool) > initial_sui, 102);
            assert!(bonding_curve::trade_count(&pool) == 1, 103);

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Buyer sells half of tokens
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let mut tokens = scenario.take_from_sender<Coin<TEST_COIN>>();
            let tokens_to_sell = coin::value(&tokens) / 2;
            let tokens_to_sell_coin = coin::split(&mut tokens, tokens_to_sell, scenario.ctx());

            let supply_before = bonding_curve::circulating_supply(&pool);
            let sui_before = bonding_curve::sui_balance(&pool);
            let trade_count_before = bonding_curve::trade_count(&pool);

            let sui_received = bonding_curve::sell(
                &mut pool,
                &config,
                tokens_to_sell_coin,
                0,
                &clock,
                scenario.ctx(),
            );

            // Strict assertions for sell
            let sui_received_amount = coin::value(&sui_received);
            assert!(sui_received_amount > 0, 200);
            assert!(bonding_curve::circulating_supply(&pool) == supply_before - tokens_to_sell, 201);
            assert!(bonding_curve::sui_balance(&pool) < sui_before, 202);
            assert!(bonding_curve::trade_count(&pool) == trade_count_before + 1, 203);

            // Verify pool token balance increased (tokens returned to pool)
            assert!(bonding_curve::token_balance(&pool) > 0, 204);

            transfer::public_transfer(sui_received, buyer());
            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    #[test]
    fun test_sell_all_tokens() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Buy tokens
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let payment = mint_sui(5_000_000_000, &mut scenario); // 5 SUI
            let tokens = bonding_curve::buy(&mut pool, &config, payment, 0, &clock, scenario.ctx());

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Sell ALL tokens - this should work now with the fix
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let tokens = scenario.take_from_sender<Coin<TEST_COIN>>();
            let _tokens_amount = coin::value(&tokens);

            let sui_received = bonding_curve::sell(
                &mut pool,
                &config,
                tokens,
                0, // Accept any amount
                &clock,
                scenario.ctx(),
            );

            // Strict assertions
            assert!(coin::value(&sui_received) > 0, 300);
            assert!(bonding_curve::circulating_supply(&pool) == 0, 301);
            // Pool should be nearly empty (may have dust due to rounding)
            assert!(bonding_curve::sui_balance(&pool) < 1_000_000, 302); // Less than 0.001 SUI dust

            transfer::public_transfer(sui_received, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    #[test]
    fun test_multiple_buy_sell_cycles() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Buy #1
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let payment = mint_sui(2_000_000_000, &mut scenario);
            let tokens = bonding_curve::buy(&mut pool, &config, payment, 0, &clock, scenario.ctx());

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Sell half
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let mut tokens = scenario.take_from_sender<Coin<TEST_COIN>>();
            let half = coin::value(&tokens) / 2;
            let to_sell = coin::split(&mut tokens, half, scenario.ctx());

            let sui = bonding_curve::sell(&mut pool, &config, to_sell, 0, &clock, scenario.ctx());
            assert!(coin::value(&sui) > 0, 400);

            transfer::public_transfer(sui, buyer());
            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Buy #2
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let payment = mint_sui(3_000_000_000, &mut scenario);
            let tokens = bonding_curve::buy(&mut pool, &config, payment, 0, &clock, scenario.ctx());

            assert!(bonding_curve::trade_count(&pool) == 3, 401);

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 306)] // ESlippageExceeded
    fun test_sell_tokens_slippage_exceeded() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        // Create pool
        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Buy tokens first
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let payment = mint_sui(1_000_000_000, &mut scenario);
            let tokens = bonding_curve::buy(&mut pool, &config, payment, 0, &clock, scenario.ctx());

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Try to sell with unrealistic min_sui_out
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let tokens = scenario.take_from_sender<Coin<TEST_COIN>>();

            let sui_received = bonding_curve::sell(
                &mut pool,
                &config,
                tokens,
                1_000_000_000_000_000_000, // impossibly high min
                &clock,
                scenario.ctx(),
            );

            transfer::public_transfer(sui_received, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_pause_pool() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        // Create pool
        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Admin pauses pool
        scenario.next_tx(admin());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let clock = create_clock(&mut scenario);

            assert!(!bonding_curve::is_paused(&pool), 0);

            bonding_curve::set_paused(&admin_cap, &mut pool, true, &clock);

            assert!(bonding_curve::is_paused(&pool), 1);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(pool);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 300)] // EPoolPaused
    fun test_buy_on_paused_pool() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        // Create pool
        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Admin pauses pool
        scenario.next_tx(admin());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let clock = create_clock(&mut scenario);

            bonding_curve::set_paused(&admin_cap, &mut pool, true, &clock);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(pool);
            clock::destroy_for_testing(clock);
        };

        // Try to buy on paused pool
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let payment = mint_sui(1_000_000_000, &mut scenario);

            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                0,
                &clock,
                scenario.ctx(),
            );

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_get_price() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        // Create pool
        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            // At zero supply, price should be base price
            let price = bonding_curve::get_price(&pool);
            assert!(price == config::default_base_price(&config), 0);

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    #[test]
    fun test_estimate_buy_sell() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        // Create pool
        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            // Test estimate_buy
            let sui_in = 1_000_000_000;
            let estimated_tokens = bonding_curve::estimate_buy(&pool, &config, sui_in);
            assert!(estimated_tokens > 0, 0);

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FEE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_creator_fee_paid_on_buy() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        // Create pool with 5% creator fee
        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                500, // 5% creator fee
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Buyer buys tokens - creator should receive fee
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let sui_in = 10_000_000_000; // 10 SUI
            let payment = mint_sui(sui_in, &mut scenario);

            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                0,
                &clock,
                scenario.ctx(),
            );

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Check creator received fee (5% of 10 SUI = 0.5 SUI)
        scenario.next_tx(creator());
        {
            let fee = scenario.take_from_sender<Coin<SUI>>();
            // Creator gets 5% of 10 SUI = 0.5 SUI = 500_000_000 MIST
            assert!(coin::value(&fee) == 500_000_000, 0);
            transfer::public_transfer(fee, creator());
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GRADUATION READINESS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_check_graduation_ready() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        // Create pool
        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            // Pool should not be ready for graduation initially
            assert!(!bonding_curve::check_graduation_ready(&pool, &config), 0);

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STRICT FEE CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_strict_buy_fee_calculation() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        // Create pool with 2% creator fee
        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                200, // 2% creator fee
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Buy and verify exact fee deductions
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let sui_in = 10_000_000_000; // 10 SUI
            let payment = mint_sui(sui_in, &mut scenario);

            // Calculate expected fees
            let platform_fee_bps = config::trading_fee_bps(&config); // 0.5% = 50 bps
            let creator_fee_bps = bonding_curve::creator_fee_bps(&pool); // 2% = 200 bps

            let expected_platform_fee = (sui_in * platform_fee_bps) / 10000;
            let expected_creator_fee = (sui_in * creator_fee_bps) / 10000;
            let expected_net_sui = sui_in - expected_platform_fee - expected_creator_fee;

            let pool_sui_before = bonding_curve::sui_balance(&pool);

            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                0,
                &clock,
                scenario.ctx(),
            );

            let pool_sui_after = bonding_curve::sui_balance(&pool);
            let sui_added_to_pool = pool_sui_after - pool_sui_before;

            // STRICT ASSERTIONS: Pool receives exactly net SUI after fees
            assert!(sui_added_to_pool == expected_net_sui, 1000);
            assert!(expected_platform_fee == 50_000_000, 1001); // 0.5% of 10 SUI = 0.05 SUI
            assert!(expected_creator_fee == 200_000_000, 1002); // 2% of 10 SUI = 0.2 SUI
            assert!(expected_net_sui == 9_750_000_000, 1003); // 10 - 0.05 - 0.2 = 9.75 SUI

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Verify creator received fee
        scenario.next_tx(creator());
        {
            let sui = scenario.take_from_sender<Coin<SUI>>();
            assert!(coin::value(&sui) == 200_000_000, 1004); // Creator gets exactly 2%
            transfer::public_transfer(sui, creator());
        };

        // Verify treasury received platform fee
        scenario.next_tx(treasury());
        {
            let sui = scenario.take_from_sender<Coin<SUI>>();
            assert!(coin::value(&sui) == 50_000_000, 1005); // Treasury gets exactly 0.5%
            transfer::public_transfer(sui, treasury());
        };

        scenario.end();
    }

    #[test]
    fun test_strict_sell_fee_calculation() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        // Create pool with 1% creator fee
        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                100, // 1% creator fee
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Buy tokens first
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let payment = mint_sui(10_000_000_000, &mut scenario);
            let tokens = bonding_curve::buy(&mut pool, &config, payment, 0, &clock, scenario.ctx());

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Sell and verify exact fee deductions
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let mut tokens = scenario.take_from_sender<Coin<TEST_COIN>>();
            let tokens_to_sell = coin::value(&tokens) / 2;
            let sell_tokens = coin::split(&mut tokens, tokens_to_sell, scenario.ctx());

            let platform_fee_bps = config::trading_fee_bps(&config);
            let creator_fee_bps = bonding_curve::creator_fee_bps(&pool);

            let pool_sui_before = bonding_curve::sui_balance(&pool);
            let supply_before = bonding_curve::circulating_supply(&pool);

            let sui_received = bonding_curve::sell(
                &mut pool,
                &config,
                sell_tokens,
                0,
                &clock,
                scenario.ctx(),
            );

            let pool_sui_after = bonding_curve::sui_balance(&pool);
            let supply_after = bonding_curve::circulating_supply(&pool);

            // STRICT: Supply decreased by exact amount sold
            assert!(supply_after == supply_before - tokens_to_sell, 2000);

            // STRICT: Pool SUI decreased
            let gross_sui_out = pool_sui_before - pool_sui_after;
            assert!(gross_sui_out > 0, 2001);

            // STRICT: Fees were taken from gross amount
            let expected_platform_fee = (gross_sui_out * platform_fee_bps) / 10000;
            let expected_creator_fee = (gross_sui_out * creator_fee_bps) / 10000;
            let expected_net = gross_sui_out - expected_platform_fee - expected_creator_fee;

            // User receives net amount after fees
            assert!(coin::value(&sui_received) == expected_net, 2002);

            transfer::public_transfer(sui_received, buyer());
            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TOKEN FLOW INVARIANT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_token_conservation_on_buy() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Test token conservation
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let total_supply = bonding_curve::total_supply(&pool);
            let pool_tokens_before = bonding_curve::token_balance(&pool);
            let circulating_before = bonding_curve::circulating_supply(&pool);

            // Platform allocation is 1% (100 bps) taken at creation
            let platform_allocation = total_supply / 100;
            let available_supply = total_supply - platform_allocation;

            // INVARIANT: pool_tokens + circulating = total_supply - platform_allocation
            assert!(pool_tokens_before + circulating_before == available_supply, 3000);

            let payment = mint_sui(5_000_000_000, &mut scenario);
            let tokens = bonding_curve::buy(&mut pool, &config, payment, 0, &clock, scenario.ctx());

            let tokens_bought = coin::value(&tokens);
            let pool_tokens_after = bonding_curve::token_balance(&pool);
            let circulating_after = bonding_curve::circulating_supply(&pool);

            // INVARIANT: pool_tokens + circulating = available_supply (still holds)
            assert!(pool_tokens_after + circulating_after == available_supply, 3001);

            // STRICT: Pool tokens decreased by exact amount bought
            assert!(pool_tokens_before - pool_tokens_after == tokens_bought, 3002);

            // STRICT: Circulating increased by exact amount bought
            assert!(circulating_after - circulating_before == tokens_bought, 3003);

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    #[test]
    fun test_token_conservation_on_sell() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Buy first
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let payment = mint_sui(10_000_000_000, &mut scenario);
            let tokens = bonding_curve::buy(&mut pool, &config, payment, 0, &clock, scenario.ctx());

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Sell and verify conservation
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let total_supply = bonding_curve::total_supply(&pool);
            let pool_tokens_before = bonding_curve::token_balance(&pool);
            let circulating_before = bonding_curve::circulating_supply(&pool);

            // Platform allocation is 1% (100 bps) taken at creation
            let platform_allocation = total_supply / 100;
            let available_supply = total_supply - platform_allocation;

            // INVARIANT before sell
            assert!(pool_tokens_before + circulating_before == available_supply, 4000);

            let mut tokens = scenario.take_from_sender<Coin<TEST_COIN>>();
            let tokens_to_sell = coin::value(&tokens) / 2;
            let sell_tokens = coin::split(&mut tokens, tokens_to_sell, scenario.ctx());

            let sui_received = bonding_curve::sell(&mut pool, &config, sell_tokens, 0, &clock, scenario.ctx());

            let pool_tokens_after = bonding_curve::token_balance(&pool);
            let circulating_after = bonding_curve::circulating_supply(&pool);

            // INVARIANT after sell: pool_tokens + circulating = available_supply
            assert!(pool_tokens_after + circulating_after == available_supply, 4001);

            // STRICT: Pool tokens increased by exact amount sold (returned to pool)
            assert!(pool_tokens_after - pool_tokens_before == tokens_to_sell, 4002);

            // STRICT: Circulating decreased by exact amount sold
            assert!(circulating_before - circulating_after == tokens_to_sell, 4003);

            transfer::public_transfer(sui_received, buyer());
            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MATH VERIFICATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_price_strictly_increases_on_buy() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Multiple buys - price must strictly increase each time
        let mut prices: vector<u64> = vector[];

        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let price0 = bonding_curve::get_price(&pool);
            vector::push_back(&mut prices, price0);

            // Buy 1 (1 SUI)
            let payment1 = mint_sui(1_000_000_000, &mut scenario);
            let tokens1 = bonding_curve::buy(&mut pool, &config, payment1, 0, &clock, scenario.ctx());
            let price1 = bonding_curve::get_price(&pool);
            vector::push_back(&mut prices, price1);

            // STRICT: Price must increase after buy
            assert!(price1 > price0, 5000);

            // Buy 2 (1 SUI)
            let payment2 = mint_sui(1_000_000_000, &mut scenario);
            let tokens2 = bonding_curve::buy(&mut pool, &config, payment2, 0, &clock, scenario.ctx());
            let price2 = bonding_curve::get_price(&pool);
            vector::push_back(&mut prices, price2);

            // STRICT: Price must increase after second buy
            assert!(price2 > price1, 5001);

            // STRICT: Verify monotonically increasing (all prices)
            let len = vector::length(&prices);
            let mut i = 1;
            while (i < len) {
                assert!(*vector::borrow(&prices, i) > *vector::borrow(&prices, i - 1), 5003);
                i = i + 1;
            };

            transfer::public_transfer(tokens1, buyer());
            transfer::public_transfer(tokens2, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    #[test]
    fun test_volume_and_trade_count_tracking() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            // Initial state
            assert!(bonding_curve::total_volume(&pool) == 0, 6000);
            assert!(bonding_curve::trade_count(&pool) == 0, 6001);

            // Trade 1: Buy 1 SUI
            let payment1 = mint_sui(1_000_000_000, &mut scenario);
            let tokens1 = bonding_curve::buy(&mut pool, &config, payment1, 0, &clock, scenario.ctx());

            // STRICT: Volume equals exact SUI spent
            assert!(bonding_curve::total_volume(&pool) == 1_000_000_000, 6002);
            assert!(bonding_curve::trade_count(&pool) == 1, 6003);

            // Trade 2: Buy 0.5 SUI
            let payment2 = mint_sui(500_000_000, &mut scenario);
            let tokens2 = bonding_curve::buy(&mut pool, &config, payment2, 0, &clock, scenario.ctx());

            // STRICT: Volume is cumulative
            assert!(bonding_curve::total_volume(&pool) == 1_500_000_000, 6004);
            assert!(bonding_curve::trade_count(&pool) == 2, 6005);

            transfer::public_transfer(tokens1, buyer());
            transfer::public_transfer(tokens2, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN HANDLER SAFETY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_only_admin_can_pause() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Admin CAN pause
        scenario.next_tx(admin());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let clock = create_clock(&mut scenario);

            assert!(!bonding_curve::is_paused(&pool), 7000);

            bonding_curve::set_paused(&admin_cap, &mut pool, true, &clock);

            assert!(bonding_curve::is_paused(&pool), 7001);

            // Unpause
            bonding_curve::set_paused(&admin_cap, &mut pool, false, &clock);
            assert!(!bonding_curve::is_paused(&pool), 7002);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(pool);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    #[test]
    fun test_pool_state_after_pause_unpause() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0,
                payment,
                &clock,
                scenario.ctx(),
            );

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Buy some tokens first
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let payment = mint_sui(5_000_000_000, &mut scenario);
            let tokens = bonding_curve::buy(&mut pool, &config, payment, 0, &clock, scenario.ctx());

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Record state before pause
        scenario.next_tx(admin());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let clock = create_clock(&mut scenario);

            let sui_before = bonding_curve::sui_balance(&pool);
            let tokens_before = bonding_curve::token_balance(&pool);
            let supply_before = bonding_curve::circulating_supply(&pool);
            let volume_before = bonding_curve::total_volume(&pool);

            // Pause
            bonding_curve::set_paused(&admin_cap, &mut pool, true, &clock);

            // STRICT: All values preserved after pause
            assert!(bonding_curve::sui_balance(&pool) == sui_before, 8000);
            assert!(bonding_curve::token_balance(&pool) == tokens_before, 8001);
            assert!(bonding_curve::circulating_supply(&pool) == supply_before, 8002);
            assert!(bonding_curve::total_volume(&pool) == volume_before, 8003);

            // Unpause
            bonding_curve::set_paused(&admin_cap, &mut pool, false, &clock);

            // STRICT: All values still preserved
            assert!(bonding_curve::sui_balance(&pool) == sui_before, 8004);
            assert!(bonding_curve::token_balance(&pool) == tokens_before, 8005);
            assert!(bonding_curve::circulating_supply(&pool) == supply_before, 8006);
            assert!(bonding_curve::total_volume(&pool) == volume_before, 8007);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(pool);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ZERO AND EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_pool_creation_with_zero_creator_fee() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                0, // Zero creator fee
                payment,
                &clock,
                scenario.ctx(),
            );

            // STRICT: Creator fee is exactly zero
            assert!(bonding_curve::creator_fee_bps(&pool) == 0, 9000);

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        // Buy with zero creator fee - creator should receive nothing
        scenario.next_tx(buyer());
        {
            let mut pool = scenario.take_shared<BondingPool<TEST_COIN>>();
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let payment = mint_sui(10_000_000_000, &mut scenario);
            let tokens = bonding_curve::buy(&mut pool, &config, payment, 0, &clock, scenario.ctx());

            transfer::public_transfer(tokens, buyer());
            test_scenario::return_shared(pool);
            test_scenario::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Creator should NOT have received any SUI (no creator fee)
        scenario.next_tx(creator());
        {
            // This should NOT find any SUI for creator
            assert!(!test_scenario::has_most_recent_for_sender<Coin<SUI>>(&scenario), 9001);
        };

        scenario.end();
    }

    #[test]
    fun test_pool_creation_with_max_creator_fee() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(creator());
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
            let config = scenario.take_shared<LaunchpadConfig>();
            let clock = create_clock(&mut scenario);

            let creation_fee = config::creation_fee(&config);
            let payment = mint_sui(creation_fee, &mut scenario);

            let pool = bonding_curve::create_pool(
                &config,
                treasury_cap,
                &metadata,
                500, // Max 5% creator fee
                payment,
                &clock,
                scenario.ctx(),
            );

            // STRICT: Creator fee is exactly 5%
            assert!(bonding_curve::creator_fee_bps(&pool) == 500, 9100);

            transfer::public_share_object(pool);
            test_scenario::return_shared(config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }
}
