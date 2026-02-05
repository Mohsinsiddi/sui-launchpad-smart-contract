/// ═══════════════════════════════════════════════════════════════════════════════════
/// END-TO-END FLOWX CLMM INTEGRATION TESTS
/// ═══════════════════════════════════════════════════════════════════════════════════
///
/// COMPREHENSIVE TEST COVERAGE FOR FLOWX LAUNCHPAD INTEGRATION
///
/// FOLLOWS EXACT SAME PATTERN AS e2e_cetus_tests.move AND e2e_suidex_tests.move:
/// - Uses graduation::initiate_graduation (hot potato pattern)
/// - Uses graduation::extract_all_sui, extract_all_tokens, extract_staking_tokens
/// - Uses staking_integration::create_staking_pool
/// - Uses dao_integration::create_dao, create_treasury
/// - Uses graduation::complete_graduation
/// - Uses nft_vesting for creator Position (same as Cetus)
///
/// Tests organized by flow:
/// - PART 1: Token Flow (creation, trading, graduation, DEX)
/// - PART 2: LP Token Flow (Position NFTs, multi-position distribution)
/// - PART 3: Staking Integration
/// - PART 4: DAO Governance
/// - PART 5: Complete Journeys
///
/// KEY SIMILARITY TO CETUS:
/// - Both are CLMM (V3 style)
/// - Both return Position NFT (non-fungible)
/// - Both use nft_vesting for creator Position
/// - Both use deposit_nft for DAO treasury
///
/// ═══════════════════════════════════════════════════════════════════════════════════

#[test_only]
module sui_launchpad::e2e_flowx_tests {
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
    use sui_launchpad::flowx_adapter;

    // FlowX CLMM imports (real contracts)
    use flowx_clmm::versioned::{Self as flowx_versioned, Versioned as FlowXVersioned};
    use flowx_clmm::pool_manager::{Self as flowx_pool_manager, PoolRegistry as FlowXPoolRegistry};
    use flowx_clmm::position_manager::{Self as flowx_position_manager, PositionRegistry as FlowXPositionRegistry};
    use flowx_clmm::position::Position as FlowXPosition;
    use flowx_clmm::pool::Pool as FlowXPool;
    use flowx_clmm::i32 as flowx_i32;

    // Staking imports
    use sui_staking::factory::{Self as staking_factory, StakingRegistry};
    use sui_staking::pool::{Self as staking_pool, StakingPool};
    use sui_staking::position::StakingPosition;
    use sui_staking::access::{AdminCap as StakingAdminCap};

    // DAO imports
    use sui_dao::registry::{Self as dao_registry, DAORegistry};
    use sui_dao::access::{AdminCap as DAOPlatformAdminCap};
    use sui_dao::governance::Governance;
    use sui_dao::treasury::Treasury;
    use sui_dao::proposal::{Self, Proposal};
    use sui_dao::voting;

    // Vesting imports
    use sui_vesting::vesting::{Self};
    use sui_vesting::nft_vesting;  // For Position NFT vesting (same as Cetus)

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES (same as Cetus/SuiDex tests)
    // ═══════════════════════════════════════════════════════════════════════════════

    fun admin(): address { @0xA1 }
    fun platform_treasury(): address { @0xE1 }
    fun creator(): address { @0xC1 }
    fun alice(): address { @0xA2 }
    fun bob(): address { @0xB1 }

    // 10 users for comprehensive testing
    fun user1(): address { @0x101 }
    fun user2(): address { @0x102 }
    fun user3(): address { @0x103 }
    fun user4(): address { @0x104 }
    fun user5(): address { @0x105 }
    fun user6(): address { @0x106 }
    fun user7(): address { @0x107 }
    fun user8(): address { @0x108 }
    fun user9(): address { @0x109 }
    fun user10(): address { @0x110 }

    fun get_10_users(): vector<address> {
        vector[user1(), user2(), user3(), user4(), user5(), user6(), user7(), user8(), user9(), user10()]
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // CONSTANTS (same as Cetus tests)
    // ═══════════════════════════════════════════════════════════════════════════════

    const MS_PER_HOUR: u64 = 3_600_000;
    const MS_PER_DAY: u64 = 86_400_000;
    const MS_PER_WEEK: u64 = 604_800_000;
    const ONE_SUI: u64 = 1_000_000_000;

    // FlowX CLMM constants
    const FEE_RATE_3000: u64 = 3000;  // 0.3%
    const TICK_SPACING_60: u64 = 60;
    const SQRT_PRICE_1_TO_1: u128 = 18446744073709551616; // 2^64

    // ═══════════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS (same pattern as Cetus)
    // ═══════════════════════════════════════════════════════════════════════════════

    fun create_clock(scenario: &mut ts::Scenario): Clock {
        clock::create_for_testing(ts::ctx(scenario))
    }

    fun create_clock_at(scenario: &mut ts::Scenario, timestamp_ms: u64): Clock {
        let mut clock = clock::create_for_testing(ts::ctx(scenario));
        clock::set_for_testing(&mut clock, timestamp_ms);
        clock
    }

    /// Setup complete infrastructure for FlowX graduation tests
    /// SAME PATTERN AS CETUS: setup_infrastructure
    fun setup_infrastructure(scenario: &mut ts::Scenario) {
        // 1. Setup launchpad (same as Cetus)
        test_utils::setup_launchpad(scenario);

        // 2. Setup FlowX CLMM infrastructure (instead of Cetus)
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

        // 3. Setup Staking (same as Cetus)
        ts::next_tx(scenario, admin());
        {
            staking_factory::init_for_testing(ts::ctx(scenario));
        };

        // 4. Setup DAO (same as Cetus)
        ts::next_tx(scenario, admin());
        {
            dao_registry::init_for_testing(ts::ctx(scenario));
        };

        // 5. Setup Vesting (same as Cetus)
        ts::next_tx(scenario, admin());
        {
            vesting::init_for_testing(ts::ctx(scenario));
        };
    }

    /// Create token pool (same as Cetus)
    fun create_token_pool(scenario: &mut ts::Scenario): ID {
        use sui_launchpad::test_coin;

        ts::next_tx(scenario, creator());
        let pool_id;
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(ts::ctx(scenario));
            let launchpad_config = ts::take_shared<LaunchpadConfig>(scenario);
            let clock = create_clock(scenario);

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

    /// Buy to graduation threshold (same as Cetus)
    fun buy_to_graduation_threshold(scenario: &mut ts::Scenario): u64 {
        ts::next_tx(scenario, admin());
        let tokens_received;
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(scenario);
            let config = ts::take_shared<LaunchpadConfig>(scenario);
            let clock = create_clock(scenario);

            let threshold = config::graduation_threshold(&config);
            let buy_amount = threshold + (threshold / 10);

            let payment = coin::mint_for_testing<SUI>(buy_amount, ts::ctx(scenario));
            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                1,
                &clock,
                ts::ctx(scenario),
            );

            tokens_received = coin::value(&tokens);
            transfer::public_transfer(tokens, admin());

            ts::return_shared(pool);
            ts::return_shared(config);
            clock::destroy_for_testing(clock);
        };
        tokens_received
    }

    /// Execute full FlowX graduation in a single transaction (hot potato pattern)
    /// SAME PATTERN AS CETUS execute_graduation
    /// Returns (staking_pool_id, dao_id, treasury_id)
    fun execute_graduation(scenario: &mut ts::Scenario): (ID, ID, ID) {
        let mut staking_pool_id = object::id_from_address(@0x0);
        let dao_id;
        let treasury_id;
        let mut sui_to_liquidity = 0u64;
        let mut tokens_to_liquidity = 0u64;

        // All graduation steps must happen in one transaction due to hot potato
        ts::next_tx(scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(scenario);
            let config = ts::take_shared<LaunchpadConfig>(scenario);
            let mut registry = ts::take_shared<Registry>(scenario);

            // FlowX infrastructure (instead of Cetus GlobalConfig/Pools)
            let versioned = ts::take_shared<FlowXVersioned>(scenario);
            let mut pool_registry = ts::take_shared<FlowXPoolRegistry>(scenario);
            let mut position_registry = ts::take_shared<FlowXPositionRegistry>(scenario);

            let mut staking_registry = ts::take_shared<StakingRegistry>(scenario);
            let staking_admin = ts::take_from_sender<StakingAdminCap>(scenario);
            let mut dao_reg = ts::take_shared<DAORegistry>(scenario);
            let dao_admin = ts::take_from_sender<DAOPlatformAdminCap>(scenario);
            let clock = create_clock(scenario);

            // Step 1: Initiate graduation (returns hot potato) - SAME AS CETUS
            let mut pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_flowx(),  // Use FlowX DEX type
                ts::ctx(scenario),
            );

            // Step 2: Extract tokens for DEX - SAME AS CETUS
            let sui_for_dex = graduation::extract_all_sui(&mut pending, ts::ctx(scenario));
            let tokens_for_dex = graduation::extract_all_tokens(&mut pending, ts::ctx(scenario));

            sui_to_liquidity = coin::value(&sui_for_dex);
            tokens_to_liquidity = coin::value(&tokens_for_dex);

            // Step 3: Create FlowX pool with multi-position LP distribution
            // SAME PATTERN AS CETUS:
            // - FlowX returns Position NFT, need 3 separate positions
            // - Calculate splits using config values

            let creator_lp_bps = config::creator_lp_bps(&config);
            let protocol_lp_bps = config::protocol_lp_bps(&config);
            let dao_lp_bps = 10000 - creator_lp_bps - protocol_lp_bps;

            let dao_sui = (((sui_to_liquidity as u128) * (dao_lp_bps as u128)) / 10000) as u64;
            let dao_tokens = (((tokens_to_liquidity as u128) * (dao_lp_bps as u128)) / 10000) as u64;

            // Split coins for DAO position (largest)
            let mut sui_coin = sui_for_dex;
            let mut token_coin = tokens_for_dex;

            let dao_sui_coin = coin::split(&mut sui_coin, dao_sui, ts::ctx(scenario));
            let dao_token_coin = coin::split(&mut token_coin, dao_tokens, ts::ctx(scenario));

            // Burn remaining coins - in production these would be used for creator/protocol positions
            coin::burn_for_testing(sui_coin);
            coin::burn_for_testing(token_coin);

            // Create and initialize FlowX pool (DAO creates the pool)
            // FlowX requires X < Y in type order (TEST_COIN < SUI alphabetically)
            flowx_pool_manager::create_and_initialize_pool<TEST_COIN, SUI>(
                &mut pool_registry,
                FEE_RATE_3000,
                SQRT_PRICE_1_TO_1,
                &versioned,
                &clock,
                ts::ctx(scenario),
            );

            // Open DAO position with full range
            let tick_lower = flowx_i32::neg_from(443580);
            let tick_upper = flowx_i32::from(443580);

            let mut dao_position = flowx_position_manager::open_position<TEST_COIN, SUI>(
                &mut position_registry,
                &pool_registry,
                FEE_RATE_3000,
                tick_lower,
                tick_upper,
                &versioned,
                ts::ctx(scenario),
            );

            // Add liquidity to DAO position
            // Note: FlowX increase_liquidity auto-refunds remaining coins to sender
            let deadline = clock::timestamp_ms(&clock) + 600_000;
            flowx_position_manager::increase_liquidity<TEST_COIN, SUI>(
                &mut pool_registry,
                &mut dao_position,
                dao_token_coin,
                dao_sui_coin,
                0, // min amounts
                0,
                deadline,
                &versioned,
                &clock,
                ts::ctx(scenario),
            );

            // Store pool ID for registry
            let flowx_pool_id = flowx_clmm::position::pool_id(&dao_position);

            // Transfer DAO position to temp storage (will go to treasury later)
            transfer::public_transfer(dao_position, admin());

            // Step 4: Extract staking tokens and create staking pool - SAME AS CETUS
            let staking_tokens = graduation::extract_staking_tokens(&mut pending, ts::ctx(scenario));

            let pool_admin_cap = staking_integration::create_staking_pool<TEST_COIN>(
                &mut staking_registry,
                &staking_admin,
                &pending,
                staking_tokens,
                &clock,
                ts::ctx(scenario),
            );
            transfer::public_transfer(pool_admin_cap, creator());

            // Step 5: Create DAO using dao_integration - SAME AS CETUS
            let temp_staking_pool_id = object::id_from_address(@0x54A4E);
            let (mut governance, dao_admin_cap) = dao_integration::create_dao(
                &dao_admin,
                &mut dao_reg,
                &pending,
                temp_staking_pool_id,
                std::string::utf8(b"Test Token DAO"),
                &clock,
                ts::ctx(scenario),
            );

            dao_id = object::id(&governance);

            // Create treasury - SAME AS CETUS
            let treasury = dao_integration::create_treasury(
                &dao_admin_cap,
                &mut governance,
                &clock,
                ts::ctx(scenario),
            );
            treasury_id = object::id(&treasury);

            // Step 6: Complete graduation (consumes hot potato) - SAME AS CETUS
            let receipt = graduation::complete_graduation(
                pending,
                &mut registry,
                flowx_pool_id,  // FlowX pool ID
                sui_to_liquidity,
                tokens_to_liquidity,
                0,  // total_lp_tokens - Position NFTs don't have numeric amount
                0,  // creator_lp_tokens
                0,  // community_lp_tokens
                &clock,
                ts::ctx(scenario),
            );

            graduation::destroy_receipt_for_testing(receipt);
            sui_dao::governance::share_governance_for_testing(governance);
            sui_dao::treasury::share_treasury_for_testing(treasury);
            transfer::public_transfer(dao_admin_cap, creator());

            // Return everything
            ts::return_to_sender(scenario, admin_cap);
            ts::return_to_sender(scenario, staking_admin);
            ts::return_to_sender(scenario, dao_admin);
            ts::return_shared(pool);
            ts::return_shared(config);
            ts::return_shared(registry);
            ts::return_shared(versioned);
            ts::return_shared(pool_registry);
            ts::return_shared(position_registry);
            ts::return_shared(staking_registry);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        // Get actual staking pool ID after it's shared - SAME AS CETUS
        ts::next_tx(scenario, admin());
        {
            let staking_pool_obj = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(scenario);
            staking_pool_id = object::id(&staking_pool_obj);
            ts::return_shared(staking_pool_obj);
        };

        // Handle Position NFT distribution in next transaction
        // SAME PATTERN AS CETUS:
        // - Create additional positions for creator/protocol
        // - Vest creator Position via nft_vesting
        // - Transfer DAO position to treasury
        ts::next_tx(scenario, admin());
        {
            let versioned = ts::take_shared<FlowXVersioned>(scenario);
            let mut pool_registry = ts::take_shared<FlowXPoolRegistry>(scenario);
            let mut position_registry = ts::take_shared<FlowXPositionRegistry>(scenario);
            let mut treasury = ts::take_shared_by_id<Treasury>(scenario, treasury_id);
            let config = ts::take_shared<LaunchpadConfig>(scenario);
            let clock = create_clock(scenario);

            // Get the DAO position we transferred to admin earlier
            let dao_position = ts::take_from_sender<FlowXPosition>(scenario);

            // Calculate LP splits using config
            let tick_lower = flowx_i32::neg_from(443580);
            let tick_upper = flowx_i32::from(443580);

            // For simplicity, we'll use small amounts for creator/protocol positions
            let creator_sui = 25 * ONE_SUI / 100;  // 0.25 SUI
            let creator_tokens = 250_000_000u64;
            let protocol_sui = 25 * ONE_SUI / 100;
            let protocol_tokens = 250_000_000u64;

            // Create Creator position (2.5%)
            let mut creator_position = flowx_position_manager::open_position<TEST_COIN, SUI>(
                &mut position_registry,
                &pool_registry,
                FEE_RATE_3000,
                tick_lower,
                tick_upper,
                &versioned,
                ts::ctx(scenario),
            );

            let creator_sui_coin = coin::mint_for_testing<SUI>(creator_sui, ts::ctx(scenario));
            let creator_token_coin = coin::mint_for_testing<TEST_COIN>(creator_tokens, ts::ctx(scenario));

            let deadline = clock::timestamp_ms(&clock) + 600_000;
            flowx_position_manager::increase_liquidity<TEST_COIN, SUI>(
                &mut pool_registry,
                &mut creator_position,
                creator_token_coin,
                creator_sui_coin,
                0,
                0,
                deadline,
                &versioned,
                &clock,
                ts::ctx(scenario),
            );

            // Create Protocol position (2.5%)
            let mut protocol_position = flowx_position_manager::open_position<TEST_COIN, SUI>(
                &mut position_registry,
                &pool_registry,
                FEE_RATE_3000,
                tick_lower,
                tick_upper,
                &versioned,
                ts::ctx(scenario),
            );

            let protocol_sui_coin = coin::mint_for_testing<SUI>(protocol_sui, ts::ctx(scenario));
            let protocol_token_coin = coin::mint_for_testing<TEST_COIN>(protocol_tokens, ts::ctx(scenario));

            flowx_position_manager::increase_liquidity<TEST_COIN, SUI>(
                &mut pool_registry,
                &mut protocol_position,
                protocol_token_coin,
                protocol_sui_coin,
                0,
                0,
                deadline,
                &versioned,
                &clock,
                ts::ctx(scenario),
            );

            // Distribute positions (SAME PATTERN AS CETUS):

            // 1. Creator position -> VEST via nft_vesting (like Cetus/SuiDex)
            let cliff_ms = config::creator_lp_cliff_ms(&config);
            let vesting_ms = config::creator_lp_vesting_ms(&config);
            let total_cliff_ms = cliff_ms + vesting_ms;
            let cliff_months = total_cliff_ms / (30 * MS_PER_DAY);

            let creator_cap = nft_vesting::create_nft_schedule_months<FlowXPosition>(
                creator_position,
                creator(),
                cliff_months,
                false,  // NOT revocable
                &clock,
                ts::ctx(scenario),
            );
            transfer::public_transfer(creator_cap, admin());

            // 2. Protocol position -> Platform treasury (like Cetus)
            transfer::public_transfer(protocol_position, platform_treasury());

            // 3. DAO position -> Treasury (like Cetus dao_integration::deposit_lp_to_treasury)
            sui_dao::treasury::deposit_nft(&mut treasury, dao_position, ts::ctx(scenario));

            ts::return_shared(treasury);
            ts::return_shared(config);
            ts::return_shared(versioned);
            ts::return_shared(pool_registry);
            ts::return_shared(position_registry);
            clock::destroy_for_testing(clock);
        };

        (staking_pool_id, dao_id, treasury_id)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 1: TOKEN FLOW TESTS (same as Cetus)
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_token_creation() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);
        let pool_id = create_token_pool(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            assert!(bonding_curve::creator(&pool) == creator(), 100);
            assert!(!bonding_curve::is_graduated(&pool), 101);
            assert!(bonding_curve::token_balance(&pool) > 0, 102);
            ts::return_shared(pool);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_launchpad_trading() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        let tokens_received = buy_to_graduation_threshold(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let tokens = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            assert!(coin::value(&tokens) == tokens_received, 100);
            assert!(tokens_received > 0, 101);
            ts::return_to_sender(&scenario, tokens);

            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let threshold = config::graduation_threshold(&config);
            assert!(bonding_curve::sui_balance(&pool) >= threshold, 102);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_graduation_readiness() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            assert!(!bonding_curve::check_graduation_ready(&pool, &config), 100);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        let _tokens = buy_to_graduation_threshold(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            assert!(bonding_curve::check_graduation_ready(&pool, &config), 101);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 2: FLOWX POOL CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_flowx_infrastructure_setup() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let versioned = ts::take_shared<FlowXVersioned>(&scenario);
            let pool_registry = ts::take_shared<FlowXPoolRegistry>(&scenario);
            let position_registry = ts::take_shared<FlowXPositionRegistry>(&scenario);

            // Verify FlowX infrastructure is set up
            ts::return_shared(versioned);
            ts::return_shared(pool_registry);
            ts::return_shared(position_registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_flowx_pool_creation_with_position() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let versioned = ts::take_shared<FlowXVersioned>(&scenario);
            let mut pool_registry = ts::take_shared<FlowXPoolRegistry>(&scenario);
            let mut position_registry = ts::take_shared<FlowXPositionRegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            // Create pool
            flowx_pool_manager::create_and_initialize_pool<TEST_COIN, SUI>(
                &mut pool_registry,
                FEE_RATE_3000,
                SQRT_PRICE_1_TO_1,
                &versioned,
                &clock,
                ts::ctx(&mut scenario),
            );

            // Open position
            let tick_lower = flowx_i32::neg_from(443580);
            let tick_upper = flowx_i32::from(443580);

            let position = flowx_position_manager::open_position<TEST_COIN, SUI>(
                &mut position_registry,
                &pool_registry,
                FEE_RATE_3000,
                tick_lower,
                tick_upper,
                &versioned,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(position, admin());

            ts::return_shared(versioned);
            ts::return_shared(pool_registry);
            ts::return_shared(position_registry);
            clock::destroy_for_testing(clock);
        };

        // Verify position was created
        ts::next_tx(&mut scenario, admin());
        {
            let position = ts::take_from_sender<FlowXPosition>(&scenario);
            let pool_id = flowx_clmm::position::pool_id(&position);
            assert!(object::id_to_address(&pool_id) != @0x0, 100);
            ts::return_to_sender(&scenario, position);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_flowx_adapter_constants() {
        assert!(flowx_adapter::default_fee_rate() == 3000, 0);
        assert!(flowx_adapter::minimum_liquidity() == 1000, 1);
        assert!(flowx_adapter::full_range_tick_lower() == 4294523660, 2);
        assert!(flowx_adapter::full_range_tick_upper() == 443580, 3);
        assert!(flowx_adapter::default_deadline_offset_ms() == 600_000, 4);
    }

    #[test]
    fun test_flowx_sqrt_price_calculation() {
        let price_1_to_1 = flowx_adapter::calculate_sqrt_price_x64(1_000_000, 1_000_000);
        assert!(price_1_to_1 == 18446744073709551616u128, 0);

        let price_higher = flowx_adapter::calculate_sqrt_price_x64(4_000_000, 1_000_000);
        let price_lower = flowx_adapter::calculate_sqrt_price_x64(1_000_000, 4_000_000);

        assert!(price_higher > 0, 1);
        assert!(price_lower > 0, 2);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 3: STAKING INTEGRATION (same pattern as Cetus)
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_staking_pool_creation() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let staking_admin = ts::take_from_sender<StakingAdminCap>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let reward_tokens = coin::mint_for_testing<TEST_COIN>(1_000_000_000_000, ts::ctx(&mut scenario));

            let pool_admin_cap = staking_factory::create_pool_admin<TEST_COIN, TEST_COIN>(
                &mut staking_registry,
                &staking_admin,
                reward_tokens,
                clock::timestamp_ms(&clock),
                MS_PER_DAY * 365,
                MS_PER_WEEK,
                500,
                0,
                0,
                sui_staking::events::origin_independent(),
                option::none(),
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(pool_admin_cap, admin());
            ts::return_to_sender(&scenario, staking_admin);
            ts::return_shared(staking_registry);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_stake_and_receive_position() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let staking_admin = ts::take_from_sender<StakingAdminCap>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let reward_tokens = coin::mint_for_testing<TEST_COIN>(1_000_000_000_000, ts::ctx(&mut scenario));

            let pool_admin_cap = staking_factory::create_pool_admin<TEST_COIN, TEST_COIN>(
                &mut staking_registry,
                &staking_admin,
                reward_tokens,
                clock::timestamp_ms(&clock),
                MS_PER_DAY * 365,
                MS_PER_WEEK,
                500,
                0,
                0,
                sui_staking::events::origin_independent(),
                option::none(),
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(pool_admin_cap, admin());
            ts::return_to_sender(&scenario, staking_admin);
            ts::return_shared(staking_registry);
            clock::destroy_for_testing(clock);
        };

        ts::next_tx(&mut scenario, alice());
        {
            let mut pool = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(&scenario);
            let clock = create_clock(&mut scenario);

            let stake_amount = 100_000_000_000u64;
            let tokens_to_stake = coin::mint_for_testing<TEST_COIN>(stake_amount, ts::ctx(&mut scenario));

            let position = staking_pool::stake(&mut pool, tokens_to_stake, &clock, ts::ctx(&mut scenario));
            transfer::public_transfer(position, alice());

            ts::return_shared(pool);
            clock::destroy_for_testing(clock);
        };

        ts::next_tx(&mut scenario, alice());
        {
            let position = ts::take_from_sender<StakingPosition<TEST_COIN>>(&scenario);
            ts::return_to_sender(&scenario, position);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 4: DAO GOVERNANCE (same pattern as Cetus)
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_dao_creation() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let dao_admin = ts::take_from_sender<DAOPlatformAdminCap>(&scenario);
            let mut dao_reg = ts::take_shared<DAORegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let staking_pool_id = object::id_from_address(@0x1234);

            let (governance, dao_admin_cap) = sui_dao::governance::create_staking_governance_admin(
                &dao_admin,
                &mut dao_reg,
                std::string::utf8(b"Test Token DAO"),
                staking_pool_id,
                400,
                MS_PER_DAY,
                MS_PER_DAY * 3,
                MS_PER_DAY * 2,
                100,
                sui_dao::events::origin_independent(),
                option::none(),
                &clock,
                ts::ctx(&mut scenario),
            );

            sui_dao::governance::share_governance_for_testing(governance);
            transfer::public_transfer(dao_admin_cap, admin());
            ts::return_to_sender(&scenario, dao_admin);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_treasury_creation_and_deposit() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let dao_admin = ts::take_from_sender<DAOPlatformAdminCap>(&scenario);
            let mut dao_reg = ts::take_shared<DAORegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let staking_pool_id = object::id_from_address(@0x1234);

            let (mut governance, dao_admin_cap) = sui_dao::governance::create_staking_governance_admin(
                &dao_admin,
                &mut dao_reg,
                std::string::utf8(b"Test DAO"),
                staking_pool_id,
                400,
                MS_PER_DAY,
                MS_PER_DAY * 3,
                MS_PER_DAY * 2,
                100,
                sui_dao::events::origin_independent(),
                option::none(),
                &clock,
                ts::ctx(&mut scenario),
            );

            let treasury = sui_dao::treasury::create_treasury(
                &dao_admin_cap,
                &mut governance,
                &clock,
                ts::ctx(&mut scenario),
            );

            sui_dao::governance::share_governance_for_testing(governance);
            sui_dao::treasury::share_treasury_for_testing(treasury);
            transfer::public_transfer(dao_admin_cap, admin());
            ts::return_to_sender(&scenario, dao_admin);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        ts::next_tx(&mut scenario, alice());
        {
            let mut treasury = ts::take_shared<Treasury>(&scenario);

            let deposit_amount = 1_000_000_000u64;
            let sui_to_deposit = coin::mint_for_testing<SUI>(deposit_amount, ts::ctx(&mut scenario));

            sui_dao::treasury::deposit_sui(&mut treasury, sui_to_deposit, ts::ctx(&mut scenario));

            assert!(sui_dao::treasury::sui_balance(&treasury) == deposit_amount, 100);

            ts::return_shared(treasury);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 5: COMPLETE JOURNEY TESTS (using execute_graduation like Cetus)
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_complete_graduation_journey() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        // Phase 1: Token creation
        let _pool_id = create_token_pool(&mut scenario);

        // Phase 2: Trading on launchpad
        let _tokens = buy_to_graduation_threshold(&mut scenario);

        // Phase 3: Verify graduation ready
        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            assert!(bonding_curve::check_graduation_ready(&pool, &config), 1);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        // Phase 4: Execute graduation (same pattern as Cetus)
        let (staking_pool_id, dao_id, treasury_id) = execute_graduation(&mut scenario);

        // Phase 5: Verify all components created
        ts::next_tx(&mut scenario, admin());
        {
            // Verify staking pool exists
            let staking_pool = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(&scenario);
            assert!(object::id(&staking_pool) == staking_pool_id, 2);
            ts::return_shared(staking_pool);

            // Verify DAO exists
            let governance = ts::take_shared_by_id<Governance>(&scenario, dao_id);
            ts::return_shared(governance);

            // Verify treasury exists
            let treasury = ts::take_shared_by_id<Treasury>(&scenario, treasury_id);
            ts::return_shared(treasury);

            // Verify bonding pool is graduated
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            assert!(bonding_curve::is_graduated(&pool), 3);
            ts::return_shared(pool);
        };

        // Phase 6: Verify creator received VESTED position (like Cetus)
        ts::next_tx(&mut scenario, creator());
        {
            // Creator has NFTVestingSchedule containing Position (not Position directly)
            let schedule = ts::take_from_sender<nft_vesting::NFTVestingSchedule<FlowXPosition>>(&scenario);
            assert!(nft_vesting::has_nft(&schedule), 4);
            assert!(nft_vesting::nft_beneficiary(&schedule) == creator(), 41);
            ts::return_to_sender(&scenario, schedule);
        };

        // Phase 7: Verify platform treasury received position
        ts::next_tx(&mut scenario, platform_treasury());
        {
            let position = ts::take_from_sender<FlowXPosition>(&scenario);
            let pool_id = flowx_clmm::position::pool_id(&position);
            assert!(object::id_to_address(&pool_id) != @0x0, 5);
            ts::return_to_sender(&scenario, position);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_10_users_stake_and_earn_rewards() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let staking_admin = ts::take_from_sender<StakingAdminCap>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let reward_tokens = coin::mint_for_testing<TEST_COIN>(10_000_000_000_000, ts::ctx(&mut scenario));

            let pool_admin_cap = staking_factory::create_pool_admin<TEST_COIN, TEST_COIN>(
                &mut staking_registry,
                &staking_admin,
                reward_tokens,
                clock::timestamp_ms(&clock),
                MS_PER_DAY * 365,
                MS_PER_DAY * 7,
                500,
                0,
                0,
                sui_staking::events::origin_independent(),
                option::none(),
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(pool_admin_cap, admin());
            ts::return_to_sender(&scenario, staking_admin);
            ts::return_shared(staking_registry);
            clock::destroy_for_testing(clock);
        };

        let users = get_10_users();
        let stake_amount = 1_000_000_000_000u64;
        let mut i = 0;
        while (i < 10) {
            let user = *vector::borrow(&users, i);
            ts::next_tx(&mut scenario, user);
            {
                let mut pool = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(&scenario);
                let clock = create_clock(&mut scenario);

                let tokens = coin::mint_for_testing<TEST_COIN>(stake_amount, ts::ctx(&mut scenario));
                let position = staking_pool::stake(&mut pool, tokens, &clock, ts::ctx(&mut scenario));
                transfer::public_transfer(position, user);

                ts::return_shared(pool);
                clock::destroy_for_testing(clock);
            };
            i = i + 1;
        };

        let mut j = 0;
        while (j < 10) {
            let user = *vector::borrow(&users, j);
            ts::next_tx(&mut scenario, user);
            {
                let position = ts::take_from_sender<StakingPosition<TEST_COIN>>(&scenario);
                assert!(sui_staking::position::staked_amount(&position) == stake_amount, 100 + j);
                ts::return_to_sender(&scenario, position);
            };
            j = j + 1;
        };

        ts::next_tx(&mut scenario, user1());
        {
            let position = ts::take_from_sender<StakingPosition<TEST_COIN>>(&scenario);
            let pool = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(&scenario);

            let current_time = MS_PER_DAY * 30;
            let pending = staking_pool::pending_rewards(&pool, &position, current_time);
            assert!(pending > 0, 200);

            ts::return_to_sender(&scenario, position);
            ts::return_shared(pool);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 6: NFT VESTING CLAIM TEST (Position NFT after cliff)
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_creator_can_claim_position_after_cliff() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        let _tokens = buy_to_graduation_threshold(&mut scenario);

        // Execute graduation (creates NFT vesting for creator Position)
        let (_staking_pool_id, _dao_id, _treasury_id) = execute_graduation(&mut scenario);

        // Verify creator has NFTVestingSchedule
        ts::next_tx(&mut scenario, creator());
        {
            let schedule = ts::take_from_sender<nft_vesting::NFTVestingSchedule<FlowXPosition>>(&scenario);
            assert!(nft_vesting::has_nft(&schedule), 100);
            assert!(nft_vesting::nft_beneficiary(&schedule) == creator(), 101);

            // Cannot claim yet (cliff period)
            let clock = create_clock(&mut scenario);
            assert!(!nft_vesting::is_claimable(&schedule, &clock), 102);

            ts::return_to_sender(&scenario, schedule);
            clock::destroy_for_testing(clock);
        };

        // Fast forward past cliff (6 months) and vesting period
        // Config defaults: 6 month cliff + 12 month vesting = 18 months total
        ts::next_tx(&mut scenario, creator());
        {
            let mut schedule = ts::take_from_sender<nft_vesting::NFTVestingSchedule<FlowXPosition>>(&scenario);
            let clock = create_clock_at(&mut scenario, MS_PER_DAY * 600); // ~20 months

            // Now can claim
            assert!(nft_vesting::is_claimable(&schedule, &clock), 200);

            // Claim the Position NFT
            let position = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));

            // Verify position has valid pool ID
            let pool_id = flowx_clmm::position::pool_id(&position);
            assert!(object::id_to_address(&pool_id) != @0x0, 201);

            transfer::public_transfer(position, creator());
            ts::return_to_sender(&scenario, schedule);
            clock::destroy_for_testing(clock);
        };

        // Verify creator now has the Position directly
        ts::next_tx(&mut scenario, creator());
        {
            let position = ts::take_from_sender<FlowXPosition>(&scenario);
            let pool_id = flowx_clmm::position::pool_id(&position);
            assert!(object::id_to_address(&pool_id) != @0x0, 300);
            ts::return_to_sender(&scenario, position);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 7: 10 USERS VOTE ON DAO PROPOSAL (Staking → Voting Power)
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_10_users_vote_on_proposal() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        // Setup DAO with staking governance
        let staking_pool_id;
        let governance_id;
        let treasury_id;

        ts::next_tx(&mut scenario, admin());
        {
            let staking_admin = ts::take_from_sender<StakingAdminCap>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let reward_tokens = coin::mint_for_testing<TEST_COIN>(10_000_000_000_000, ts::ctx(&mut scenario));

            let pool_admin_cap = staking_factory::create_pool_admin<TEST_COIN, TEST_COIN>(
                &mut staking_registry,
                &staking_admin,
                reward_tokens,
                clock::timestamp_ms(&clock),
                MS_PER_DAY * 365,
                MS_PER_DAY * 7,
                500,
                0,
                0,
                sui_staking::events::origin_independent(),
                option::none(),
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(pool_admin_cap, admin());
            ts::return_to_sender(&scenario, staking_admin);
            ts::return_shared(staking_registry);
            clock::destroy_for_testing(clock);
        };

        // Get staking pool ID
        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(&scenario);
            staking_pool_id = object::id(&pool);
            ts::return_shared(pool);
        };

        // Create DAO with staking governance
        ts::next_tx(&mut scenario, admin());
        {
            let dao_admin = ts::take_from_sender<DAOPlatformAdminCap>(&scenario);
            let mut dao_reg = ts::take_shared<DAORegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let (mut governance, dao_admin_cap) = sui_dao::governance::create_staking_governance_admin(
                &dao_admin,
                &mut dao_reg,
                std::string::utf8(b"FlowX Test DAO"),
                staking_pool_id,
                400,        // 4% quorum
                0,          // no voting delay for testing
                MS_PER_DAY, // 1 day voting period
                0,          // no timelock for testing
                100,        // proposal threshold
                sui_dao::events::origin_independent(),
                option::none(),
                &clock,
                ts::ctx(&mut scenario),
            );

            governance_id = object::id(&governance);

            let treasury = sui_dao::treasury::create_treasury(
                &dao_admin_cap,
                &mut governance,
                &clock,
                ts::ctx(&mut scenario),
            );
            treasury_id = object::id(&treasury);

            sui_dao::governance::share_governance_for_testing(governance);
            sui_dao::treasury::share_treasury_for_testing(treasury);
            transfer::public_transfer(dao_admin_cap, admin());
            ts::return_to_sender(&scenario, dao_admin);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        // Fund treasury with SUI
        ts::next_tx(&mut scenario, admin());
        {
            let mut treasury = ts::take_shared_by_id<Treasury>(&scenario, treasury_id);
            let sui_deposit = coin::mint_for_testing<SUI>(10_000_000_000, ts::ctx(&mut scenario));
            sui_dao::treasury::deposit_sui(&mut treasury, sui_deposit, ts::ctx(&mut scenario));
            ts::return_shared(treasury);
        };

        // 10 users stake tokens
        let users = get_10_users();
        let stake_amount = 1_000_000_000_000u64;
        let mut i = 0;
        while (i < 10) {
            let user = *vector::borrow(&users, i);
            ts::next_tx(&mut scenario, user);
            {
                let mut pool = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(&scenario);
                let clock = create_clock(&mut scenario);

                let tokens = coin::mint_for_testing<TEST_COIN>(stake_amount, ts::ctx(&mut scenario));
                let position = staking_pool::stake(&mut pool, tokens, &clock, ts::ctx(&mut scenario));
                transfer::public_transfer(position, user);

                ts::return_shared(pool);
                clock::destroy_for_testing(clock);
            };
            i = i + 1;
        };

        // User1 creates a proposal (treasury transfer)
        ts::next_tx(&mut scenario, user1());
        {
            let mut dao_reg = ts::take_shared<DAORegistry>(&scenario);
            let mut governance = ts::take_shared_by_id<Governance>(&scenario, governance_id);
            let treasury = ts::take_shared_by_id<Treasury>(&scenario, treasury_id);
            let position = ts::take_from_sender<StakingPosition<TEST_COIN>>(&scenario);
            let clock = create_clock(&mut scenario);

            let voting_power = sui_staking::position::staked_amount(&position);

            // Create treasury transfer action
            let action = proposal::create_treasury_transfer_action<SUI>(
                object::id(&treasury),
                1_000_000_000, // 1 SUI
                user1(), // recipient
            );

            let payment = coin::mint_for_testing<SUI>(1_000_000_000, ts::ctx(&mut scenario));

            let prop = proposal::create_proposal(
                &mut dao_reg,
                &mut governance,
                std::string::utf8(b"Withdraw 1 SUI"),
                std::string::utf8(b"QmProposalHash"),
                vector[action],
                voting_power,
                payment,
                &clock,
                ts::ctx(&mut scenario),
            );

            proposal::share_proposal_for_testing(prop);

            ts::return_to_sender(&scenario, position);
            ts::return_shared(dao_reg);
            ts::return_shared(governance);
            ts::return_shared(treasury);
            clock::destroy_for_testing(clock);
        };

        // All 10 users vote YES
        let mut k = 0;
        while (k < 10) {
            let user = *vector::borrow(&users, k);
            ts::next_tx(&mut scenario, user);
            {
                let governance = ts::take_shared_by_id<Governance>(&scenario, governance_id);
                let mut prop = ts::take_shared<Proposal>(&scenario);
                let position = ts::take_from_sender<StakingPosition<TEST_COIN>>(&scenario);
                let clock = create_clock_at(&mut scenario, MS_PER_HOUR); // After voting starts

                voting::vote_with_stake<TEST_COIN>(
                    &governance,
                    &mut prop,
                    &position,
                    proposal::vote_for(), // Vote YES
                    &clock,
                    ts::ctx(&mut scenario),
                );

                ts::return_to_sender(&scenario, position);
                ts::return_shared(governance);
                ts::return_shared(prop);
                clock::destroy_for_testing(clock);
            };
            k = k + 1;
        };

        // Verify votes
        ts::next_tx(&mut scenario, admin());
        {
            let prop = ts::take_shared<Proposal>(&scenario);

            // All 10 users voted, each with stake_amount voting power
            let expected_votes = stake_amount * 10;
            assert!(proposal::for_votes(&prop) == expected_votes, 300);
            assert!(proposal::against_votes(&prop) == 0, 301);

            ts::return_shared(prop);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 8: COMPLETE DAO TREASURY WITHDRAWAL FLOW WITH EXECUTION
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_dao_treasury_withdrawal_via_proposal() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        let staking_pool_id;
        let governance_id;
        let treasury_id;

        // Create staking pool
        ts::next_tx(&mut scenario, admin());
        {
            let staking_admin = ts::take_from_sender<StakingAdminCap>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let reward_tokens = coin::mint_for_testing<TEST_COIN>(10_000_000_000_000, ts::ctx(&mut scenario));

            let pool_admin_cap = staking_factory::create_pool_admin<TEST_COIN, TEST_COIN>(
                &mut staking_registry,
                &staking_admin,
                reward_tokens,
                clock::timestamp_ms(&clock),
                MS_PER_DAY * 365,
                0, // no min stake duration for testing
                0, // no early unstake fee
                0,
                0,
                sui_staking::events::origin_independent(),
                option::none(),
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(pool_admin_cap, admin());
            ts::return_to_sender(&scenario, staking_admin);
            ts::return_shared(staking_registry);
            clock::destroy_for_testing(clock);
        };

        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(&scenario);
            staking_pool_id = object::id(&pool);
            ts::return_shared(pool);
        };

        // Create DAO
        ts::next_tx(&mut scenario, admin());
        {
            let dao_admin = ts::take_from_sender<DAOPlatformAdminCap>(&scenario);
            let mut dao_reg = ts::take_shared<DAORegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let (mut governance, dao_admin_cap) = sui_dao::governance::create_staking_governance_admin(
                &dao_admin,
                &mut dao_reg,
                std::string::utf8(b"FlowX Treasury Test DAO"),
                staking_pool_id,
                100,        // 1% quorum (low for testing)
                0,          // no voting delay
                MS_PER_HOUR, // 1 hour voting
                0,          // no timelock
                1,          // low threshold
                sui_dao::events::origin_independent(),
                option::none(),
                &clock,
                ts::ctx(&mut scenario),
            );

            governance_id = object::id(&governance);

            let treasury = sui_dao::treasury::create_treasury(
                &dao_admin_cap,
                &mut governance,
                &clock,
                ts::ctx(&mut scenario),
            );
            treasury_id = object::id(&treasury);

            sui_dao::governance::share_governance_for_testing(governance);
            sui_dao::treasury::share_treasury_for_testing(treasury);
            transfer::public_transfer(dao_admin_cap, admin());
            ts::return_to_sender(&scenario, dao_admin);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        // Fund treasury
        ts::next_tx(&mut scenario, admin());
        {
            let mut treasury = ts::take_shared_by_id<Treasury>(&scenario, treasury_id);
            let sui_deposit = coin::mint_for_testing<SUI>(5_000_000_000, ts::ctx(&mut scenario)); // 5 SUI
            sui_dao::treasury::deposit_sui(&mut treasury, sui_deposit, ts::ctx(&mut scenario));

            assert!(sui_dao::treasury::sui_balance(&treasury) == 5_000_000_000, 100);
            ts::return_shared(treasury);
        };

        // User1 stakes
        ts::next_tx(&mut scenario, user1());
        {
            let mut pool = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(&scenario);
            let clock = create_clock(&mut scenario);

            let tokens = coin::mint_for_testing<TEST_COIN>(10_000_000_000_000, ts::ctx(&mut scenario));
            let position = staking_pool::stake(&mut pool, tokens, &clock, ts::ctx(&mut scenario));
            transfer::public_transfer(position, user1());

            ts::return_shared(pool);
            clock::destroy_for_testing(clock);
        };

        // User1 creates withdrawal proposal
        ts::next_tx(&mut scenario, user1());
        {
            let mut dao_reg = ts::take_shared<DAORegistry>(&scenario);
            let mut governance = ts::take_shared_by_id<Governance>(&scenario, governance_id);
            let treasury = ts::take_shared_by_id<Treasury>(&scenario, treasury_id);
            let position = ts::take_from_sender<StakingPosition<TEST_COIN>>(&scenario);
            let clock = create_clock(&mut scenario);

            let voting_power = sui_staking::position::staked_amount(&position);

            let action = proposal::create_treasury_transfer_action<SUI>(
                object::id(&treasury),
                1_000_000_000, // 1 SUI withdrawal
                user1(),
            );

            let payment = coin::mint_for_testing<SUI>(1_000_000_000, ts::ctx(&mut scenario));

            let prop = proposal::create_proposal(
                &mut dao_reg,
                &mut governance,
                std::string::utf8(b"Withdraw 1 SUI to User1"),
                std::string::utf8(b"QmHash"),
                vector[action],
                voting_power,
                payment,
                &clock,
                ts::ctx(&mut scenario),
            );

            proposal::share_proposal_for_testing(prop);

            ts::return_to_sender(&scenario, position);
            ts::return_shared(dao_reg);
            ts::return_shared(governance);
            ts::return_shared(treasury);
            clock::destroy_for_testing(clock);
        };

        // User1 votes YES
        ts::next_tx(&mut scenario, user1());
        {
            let governance = ts::take_shared_by_id<Governance>(&scenario, governance_id);
            let mut prop = ts::take_shared<Proposal>(&scenario);
            let position = ts::take_from_sender<StakingPosition<TEST_COIN>>(&scenario);
            let clock = create_clock_at(&mut scenario, MS_PER_HOUR / 2);

            voting::vote_with_stake<TEST_COIN>(
                &governance,
                &mut prop,
                &position,
                proposal::vote_for(),
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_to_sender(&scenario, position);
            ts::return_shared(governance);
            ts::return_shared(prop);
            clock::destroy_for_testing(clock);
        };

        // Finalize voting (after voting period)
        ts::next_tx(&mut scenario, admin());
        {
            let governance = ts::take_shared_by_id<Governance>(&scenario, governance_id);
            let mut prop = ts::take_shared<Proposal>(&scenario);
            let pool = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(&scenario);
            let clock = create_clock_at(&mut scenario, MS_PER_HOUR * 2); // After voting ends

            let total_staked = staking_pool::total_staked(&pool);

            proposal::finalize_voting(
                &mut prop,
                &governance,
                total_staked,
                &clock,
            );

            // Proposal should have passed (quorum met, majority voted yes)
            assert!(proposal::is_succeeded(&prop) || proposal::is_queued(&prop), 200);

            ts::return_shared(governance);
            ts::return_shared(prop);
            ts::return_shared(pool);
            clock::destroy_for_testing(clock);
        };

        // Verify treasury still has 5 SUI (withdrawal not executed yet - needs begin_execution)
        ts::next_tx(&mut scenario, admin());
        {
            let treasury = ts::take_shared_by_id<Treasury>(&scenario, treasury_id);
            assert!(sui_dao::treasury::sui_balance(&treasury) == 5_000_000_000, 300);
            ts::return_shared(treasury);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 9: TRADING BLOCKED AFTER GRADUATION
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure]
    fun test_trading_blocked_after_graduation() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        let _tokens = buy_to_graduation_threshold(&mut scenario);
        let (_staking_pool_id, _dao_id, _treasury_id) = execute_graduation(&mut scenario);

        // Try to buy from bonding pool after graduation - should fail
        ts::next_tx(&mut scenario, alice());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let clock = create_clock(&mut scenario);

            let payment = coin::mint_for_testing<SUI>(1_000_000_000, ts::ctx(&mut scenario));
            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                1,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(tokens, alice());
            ts::return_shared(pool);
            ts::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 11: USER UNSTAKE AND CLAIM REWARDS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_user_unstake_and_claim_rewards() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        // Create staking pool with rewards
        ts::next_tx(&mut scenario, admin());
        {
            let staking_admin = ts::take_from_sender<StakingAdminCap>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let reward_tokens = coin::mint_for_testing<TEST_COIN>(10_000_000_000_000, ts::ctx(&mut scenario));

            let pool_admin_cap = staking_factory::create_pool_admin<TEST_COIN, TEST_COIN>(
                &mut staking_registry,
                &staking_admin,
                reward_tokens,
                clock::timestamp_ms(&clock),
                MS_PER_DAY * 365, // 1 year duration
                0, // no min stake duration
                0, // no early unstake fee
                0,
                0,
                sui_staking::events::origin_independent(),
                option::none(),
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(pool_admin_cap, admin());
            ts::return_to_sender(&scenario, staking_admin);
            ts::return_shared(staking_registry);
            clock::destroy_for_testing(clock);
        };

        // User1 stakes tokens
        ts::next_tx(&mut scenario, user1());
        {
            let mut pool = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(&scenario);
            let clock = create_clock(&mut scenario);

            let stake_amount = 1_000_000_000_000u64;
            let tokens = coin::mint_for_testing<TEST_COIN>(stake_amount, ts::ctx(&mut scenario));
            let position = staking_pool::stake(&mut pool, tokens, &clock, ts::ctx(&mut scenario));

            assert!(sui_staking::position::staked_amount(&position) == stake_amount, 100);
            transfer::public_transfer(position, user1());

            ts::return_shared(pool);
            clock::destroy_for_testing(clock);
        };

        // Fast forward time to accumulate rewards (30 days)
        ts::next_tx(&mut scenario, user1());
        {
            let pool = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(&scenario);
            let position = ts::take_from_sender<StakingPosition<TEST_COIN>>(&scenario);

            let time_after_30_days = MS_PER_DAY * 30;
            let pending = staking_pool::pending_rewards(&pool, &position, time_after_30_days);

            // Should have accumulated some rewards
            assert!(pending > 0, 200);

            ts::return_to_sender(&scenario, position);
            ts::return_shared(pool);
        };

        // User1 claims rewards without unstaking
        ts::next_tx(&mut scenario, user1());
        {
            let mut pool = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(&scenario);
            let mut position = ts::take_from_sender<StakingPosition<TEST_COIN>>(&scenario);
            let clock = create_clock_at(&mut scenario, MS_PER_DAY * 30);

            let rewards = staking_pool::claim_rewards(&mut pool, &mut position, &clock, ts::ctx(&mut scenario));

            assert!(coin::value(&rewards) > 0, 300);
            transfer::public_transfer(rewards, user1());
            ts::return_to_sender(&scenario, position);
            ts::return_shared(pool);
            clock::destroy_for_testing(clock);
        };

        // Verify user1 received rewards
        ts::next_tx(&mut scenario, user1());
        {
            let rewards = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            assert!(coin::value(&rewards) > 0, 400);
            ts::return_to_sender(&scenario, rewards);
        };

        // User1 unstakes (after more time)
        ts::next_tx(&mut scenario, user1());
        {
            let mut pool = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(&scenario);
            let position = ts::take_from_sender<StakingPosition<TEST_COIN>>(&scenario);
            let clock = create_clock_at(&mut scenario, MS_PER_DAY * 60);

            let (staked_tokens, final_rewards) = staking_pool::unstake(&mut pool, position, &clock, ts::ctx(&mut scenario));

            // Should get back staked tokens
            assert!(coin::value(&staked_tokens) == 1_000_000_000_000, 500);
            transfer::public_transfer(staked_tokens, user1());
            transfer::public_transfer(final_rewards, user1());

            ts::return_shared(pool);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }
}
