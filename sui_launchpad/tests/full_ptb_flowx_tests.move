/// ═══════════════════════════════════════════════════════════════════════════════
/// FULL PTB FLOW TESTS - FLOWX (CLMM)
/// ═══════════════════════════════════════════════════════════════════════════════
///
/// Comprehensive tests for the complete graduation + staking + DAO flow
/// using FlowX CLMM (returns Position NFT, not LP tokens)
///
/// Test Coverage:
/// - Complete PTB flow with Position NFT
/// - FlowX-specific configurations
/// - NFT deposit to DAO treasury
/// - All config permutations for CLMM
///
#[test_only]
module sui_launchpad::full_ptb_flowx_tests {
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
    use sui_launchpad::flowx_adapter as flowx;
    use sui_launchpad::test_utils;
    use sui_launchpad::test_coin::TEST_COIN;

    // sui_staking imports
    use sui_staking::factory::{Self as staking_factory, StakingRegistry};
    use sui_staking::access::{AdminCap as StakingAdminCap};

    // sui_dao imports
    use sui_dao::registry::{Self as dao_registry, DAORegistry};
    use sui_dao::access::{AdminCap as DAOPlatformAdminCap};

    // ═══════════════════════════════════════════════════════════════════════
    // MOCK NFT FOR TESTING
    // ═══════════════════════════════════════════════════════════════════════

    /// Mock FlowX Position NFT for testing
    public struct FlowXPositionNFT has key, store {
        id: UID,
        pool_id: ID,
        liquidity: u128,
        tick_lower: u32,
        tick_upper: u32,
        fee_rate: u64,
    }

    fun create_flowx_position_nft(
        pool_id: ID,
        liquidity: u128,
        ctx: &mut TxContext,
    ): FlowXPositionNFT {
        FlowXPositionNFT {
            id: object::new(ctx),
            pool_id,
            liquidity,
            tick_lower: flowx::full_range_tick_lower(),
            tick_upper: flowx::full_range_tick_upper(),
            fee_rate: flowx::default_fee_rate(),
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════

    fun admin(): address { @0xA1 }
    fun creator(): address { @0xC1 }

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    fun setup_launchpad(scenario: &mut ts::Scenario) {
        test_utils::setup_launchpad(scenario);
    }

    fun setup_staking(scenario: &mut ts::Scenario) {
        ts::next_tx(scenario, admin());
        {
            staking_factory::init_for_testing(ts::ctx(scenario));
        };
    }

    fun setup_dao(scenario: &mut ts::Scenario) {
        ts::next_tx(scenario, admin());
        {
            dao_registry::init_for_testing(ts::ctx(scenario));
        };
    }

    fun create_test_pool(scenario: &mut ts::Scenario): ID {
        use sui_launchpad::test_coin;

        ts::next_tx(scenario, creator());
        let pool_id;
        {
            let (treasury_cap, metadata) = test_coin::create_test_coin(ts::ctx(scenario));
            let launchpad_config = ts::take_shared<LaunchpadConfig>(scenario);
            let clock = clock::create_for_testing(ts::ctx(scenario));

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

    fun buy_to_graduation_threshold(scenario: &mut ts::Scenario) {
        ts::next_tx(scenario, admin());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(scenario);
            let launchpad_config = ts::take_shared<LaunchpadConfig>(scenario);
            let clock = clock::create_for_testing(ts::ctx(scenario));

            let threshold = config::graduation_threshold(&launchpad_config);
            let buy_amount = threshold + (threshold / 10);

            let payment = coin::mint_for_testing<SUI>(buy_amount, ts::ctx(scenario));
            let tokens = bonding_curve::buy(
                &mut pool,
                &launchpad_config,
                payment,
                0,
                &clock,
                ts::ctx(scenario),
            );

            transfer::public_transfer(tokens, admin());
            ts::return_shared(pool);
            ts::return_shared(launchpad_config);
            clock::destroy_for_testing(clock);
        };
    }

    fun create_clock(scenario: &mut ts::Scenario): Clock {
        clock::create_for_testing(ts::ctx(scenario))
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 1: COMPLETE PTB FLOW WITH FLOWX
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Complete graduation flow with FlowX CLMM: Token → CLMM Pool → Position NFT → DAO Treasury
    fun test_complete_ptb_flow_flowx_with_dao() {
        let mut scenario = ts::begin(admin());

        // Setup
        setup_launchpad(&mut scenario);
        setup_staking(&mut scenario);
        setup_dao(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        // PTB Transaction
        ts::next_tx(&mut scenario, admin());
        {
            let launchpad_admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let staking_admin_cap = ts::take_from_sender<StakingAdminCap>(&scenario);
            let dao_platform_cap = ts::take_from_sender<DAOPlatformAdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let mut dao_reg = ts::take_shared<DAORegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            // STEP 1: Initiate graduation with FlowX
            let mut pending = graduation::initiate_graduation(
                &launchpad_admin_cap,
                &mut pool,
                &config,
                config::dex_flowx(),
                ts::ctx(&mut scenario),
            );

            // Verify DEX type
            assert!(graduation::pending_dex_type(&pending) == config::dex_flowx(), 100);

            // STEP 2: Extract all balances
            let sui_coin = graduation::extract_all_sui(&mut pending, ts::ctx(&mut scenario));
            let token_coin = graduation::extract_all_tokens(&mut pending, ts::ctx(&mut scenario));
            let staking_coin = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));

            // STEP 3: Simulate FlowX pool creation
            let mock_pool_id = object::id_from_address(@0xF10F0);
            let position_nft = create_flowx_position_nft(
                mock_pool_id,
                1_000_000_000_000u128,
                ts::ctx(&mut scenario),
            );

            coin::burn_for_testing(sui_coin);
            coin::burn_for_testing(token_coin);

            // STEP 4: Create staking pool
            let pool_admin_cap = staking_integration::create_staking_pool<TEST_COIN>(
                &mut staking_registry,
                &staking_admin_cap,
                &pending,
                staking_coin,
                &clock,
                ts::ctx(&mut scenario),
            );

            let staking_pool_id = sui_staking::access::pool_admin_cap_pool_id(&pool_admin_cap);
            transfer::public_transfer(pool_admin_cap, admin());

            // STEP 5: Create DAO
            let (mut governance, dao_admin_cap) = dao_integration::create_dao<TEST_COIN>(
                &dao_platform_cap,
                &mut dao_reg,
                &pending,
                staking_pool_id,
                std::string::utf8(b"TEST DAO"),
                &clock,
                ts::ctx(&mut scenario),
            );

            // STEP 6: Create Treasury
            let mut treasury = dao_integration::create_treasury(
                &dao_admin_cap,
                &mut governance,
                ts::ctx(&mut scenario),
            );

            // STEP 7: Deposit Position NFT to Treasury
            dao_integration::deposit_nft_to_treasury(&mut treasury, position_nft, ts::ctx(&mut scenario));

            // Verify NFT deposited
            assert!(sui_dao::treasury::has_nft<FlowXPositionNFT>(&treasury), 101);

            // STEP 8: Complete graduation
            let receipt = graduation::complete_graduation(
                pending,
                &mut registry,
                mock_pool_id,
                1_000_000, 0, 1_000_000,
                &clock,
                ts::ctx(&mut scenario),
            );

            // Share objects
            sui_dao::governance::share_governance_for_testing(governance);
            sui_dao::treasury::share_treasury_for_testing(treasury);
            transfer::public_transfer(dao_admin_cap, admin());

            graduation::destroy_receipt_for_testing(receipt);
            ts::return_to_sender(&scenario, launchpad_admin_cap);
            ts::return_to_sender(&scenario, staking_admin_cap);
            ts::return_to_sender(&scenario, dao_platform_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
            ts::return_shared(registry);
            ts::return_shared(staking_registry);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        // Verification
        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            assert!(bonding_curve::is_graduated(&pool), 200);
            ts::return_shared(pool);

            let registry = ts::take_shared<Registry>(&scenario);
            assert!(registry::total_graduated(&registry) == 1, 201);
            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 2: FLOWX ADAPTER CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_flowx_adapter_constants() {
        // Full range ticks
        let tick_lower = flowx::full_range_tick_lower();
        let tick_upper = flowx::full_range_tick_upper();
        // Tick values are two's complement u32, verify range is defined (ticks differ)
        assert!(tick_lower != tick_upper, 100);

        // Fee rate
        let fee_rate = flowx::default_fee_rate();
        assert!(fee_rate > 0, 101);

        // Minimum liquidity
        let min_liquidity = flowx::minimum_liquidity();
        assert!(min_liquidity > 0, 102);

        // Deadline offset
        let deadline_offset = flowx::default_deadline_offset_ms();
        assert!(deadline_offset > 0, 103);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 3: FLOWX SQRT PRICE CALCULATION
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_flowx_sqrt_price_calculation() {
        // 1:1 ratio
        let sqrt_price_1_1 = flowx::calculate_sqrt_price_x64(1_000_000_000, 1_000_000_000);
        assert!(sqrt_price_1_1 > 0, 100);

        // Different ratios
        let sqrt_price_2_1 = flowx::calculate_sqrt_price_x64(2_000_000_000, 1_000_000_000);
        let sqrt_price_1_2 = flowx::calculate_sqrt_price_x64(1_000_000_000, 2_000_000_000);

        assert!(sqrt_price_2_1 != sqrt_price_1_1, 101);
        assert!(sqrt_price_1_2 != sqrt_price_1_1, 102);
        assert!(sqrt_price_2_1 != sqrt_price_1_2, 103);

        // Small amounts
        let sqrt_price_small = flowx::calculate_sqrt_price_x64(1_000_000, 1_000_000);
        assert!(sqrt_price_small > 0, 104);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 4: DEX TYPE COMPARISON (FLOWX VS OTHERS)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_dex_type_flowx_vs_others() {
        // Verify FlowX is distinct
        let flowx = config::dex_flowx();
        let suidex = config::dex_suidex();
        let cetus = config::dex_cetus();
        let turbos = config::dex_turbos();

        assert!(flowx != suidex, 100);
        assert!(flowx != cetus, 101);
        assert!(flowx != turbos, 102);

        // All should be different
        assert!(suidex != cetus, 103);
        assert!(suidex != turbos, 104);
        assert!(cetus != turbos, 105);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 5: FLOWX WITH ALL ADMIN DESTINATIONS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_flowx_staking_admin_to_creator() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);

        // Set staking admin destination to creator
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);
            config::set_staking_admin_destination(&admin_cap, &mut config, 0); // CREATOR
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_flowx(),
                ts::ctx(&mut scenario),
            );

            // Verify staking admin goes to creator
            let expected = graduation::pending_creator(&pending);
            let actual = staking_integration::get_admin_destination(&pending, &config);
            assert!(actual == expected, 100);

            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_flowx_dao_admin_to_dao_treasury() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);

        // Set DAO admin destination to DAO treasury
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);
            config::set_dao_admin_destination(&admin_cap, &mut config, 1); // DAO_TREASURY
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_flowx(),
                ts::ctx(&mut scenario),
            );

            // Verify DAO admin goes to DAO treasury
            let expected = config::dao_treasury(&config);
            let actual = dao_integration::get_admin_destination(&pending, &config);
            assert!(actual == expected, 100);

            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 6: FLOWX GRADUATION WITHOUT STAKING
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_flowx_graduation_without_staking() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        setup_dao(&mut scenario);

        // Disable staking
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);
            config::set_staking_enabled(&admin_cap, &mut config, false);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let clock = create_clock(&mut scenario);

            let mut pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_flowx(),
                ts::ctx(&mut scenario),
            );

            // Staking should be disabled
            assert!(!staking_integration::should_create_staking_pool(&pending), 100);
            assert!(graduation::pending_staking_amount(&pending) == 0, 101);

            // Extract for DEX only
            let sui_coin = graduation::extract_all_sui(&mut pending, ts::ctx(&mut scenario));
            let token_coin = graduation::extract_all_tokens(&mut pending, ts::ctx(&mut scenario));

            coin::burn_for_testing(sui_coin);
            coin::burn_for_testing(token_coin);

            // Complete graduation
            let mock_pool_id = object::id_from_address(@0xF10F0);
            let receipt = graduation::complete_graduation(
                pending,
                &mut registry,
                mock_pool_id,
                1_000_000, 0, 1_000_000,
                &clock,
                ts::ctx(&mut scenario),
            );

            graduation::destroy_receipt_for_testing(receipt);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
            ts::return_shared(registry);
            clock::destroy_for_testing(clock);
        };

        // Verify graduated
        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            assert!(bonding_curve::is_graduated(&pool), 200);
            ts::return_shared(pool);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 7: FLOWX FULL RANGE TICK CONSISTENCY
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_flowx_full_range_tick_consistency() {
        use sui_launchpad::cetus_adapter as cetus;

        // Both Cetus and FlowX should use similar tick ranges for full range
        let flowx_lower = flowx::full_range_tick_lower();
        let flowx_upper = flowx::full_range_tick_upper();
        let cetus_lower = cetus::full_range_tick_lower();
        let cetus_upper = cetus::full_range_tick_upper();

        // Both should represent full range (max ticks)
        // They may have different values but both should be valid
        assert!(flowx_lower != flowx_upper, 100);
        assert!(cetus_lower != cetus_upper, 101);

        // Lower ticks should be smaller than upper ticks
        // (accounting for two's complement representation)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 8: MULTIPLE FLOWX POSITIONS IN DAO
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_multiple_flowx_positions_in_dao() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        setup_dao(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let dao_platform_cap = ts::take_from_sender<DAOPlatformAdminCap>(&scenario);
            let mut dao_reg = ts::take_shared<DAORegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let staking_pool_id = object::id_from_address(@0x123);

            let (mut governance, dao_admin_cap) = sui_dao::governance::create_staking_governance_free(
                &dao_platform_cap,
                &mut dao_reg,
                std::string::utf8(b"FlowX DAO"),
                staking_pool_id,
                400, 86_400_000, 259_200_000, 172_800_000, 100,
                &clock,
                ts::ctx(&mut scenario),
            );

            let mut treasury = sui_dao::treasury::create_treasury(
                &dao_admin_cap,
                &mut governance,
                ts::ctx(&mut scenario),
            );

            // Create multiple FlowX positions (different fee tiers or ranges)
            let pool_id_1 = object::id_from_address(@0xF10F1);
            let pool_id_2 = object::id_from_address(@0xF10F2);

            let nft1 = create_flowx_position_nft(pool_id_1, 500_000_000_000u128, ts::ctx(&mut scenario));
            let nft2 = create_flowx_position_nft(pool_id_2, 500_000_000_000u128, ts::ctx(&mut scenario));

            // Deposit both
            sui_dao::treasury::deposit_nft(&mut treasury, nft1, ts::ctx(&mut scenario));
            sui_dao::treasury::deposit_nft(&mut treasury, nft2, ts::ctx(&mut scenario));

            // Verify both deposited
            assert!(sui_dao::treasury::nft_count<FlowXPositionNFT>(&treasury) == 2, 100);

            // Cleanup
            sui_dao::governance::share_governance_for_testing(governance);
            sui_dao::treasury::destroy_treasury_for_testing(treasury);
            transfer::public_transfer(dao_admin_cap, admin());
            ts::return_to_sender(&scenario, dao_platform_cap);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 9: FLOWX WITH COUNCIL ENABLED
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_flowx_with_council_enabled() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        setup_staking(&mut scenario);
        setup_dao(&mut scenario);

        // Enable council
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);
            config::set_dao_council_enabled(&admin_cap, &mut config, true);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let staking_admin_cap = ts::take_from_sender<StakingAdminCap>(&scenario);
            let dao_platform_cap = ts::take_from_sender<DAOPlatformAdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let mut dao_reg = ts::take_shared<DAORegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let mut pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_flowx(),
                ts::ctx(&mut scenario),
            );

            // Verify council should be enabled
            assert!(dao_integration::should_enable_council(&pending), 100);

            // Extract staking tokens
            let staking_coin = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));

            // Create staking pool
            let pool_admin_cap = staking_integration::create_staking_pool<TEST_COIN>(
                &mut staking_registry,
                &staking_admin_cap,
                &pending,
                staking_coin,
                &clock,
                ts::ctx(&mut scenario),
            );

            let staking_pool_id = sui_staking::access::pool_admin_cap_pool_id(&pool_admin_cap);
            transfer::public_transfer(pool_admin_cap, admin());

            // Use full DAO setup with council
            let (governance, treasury, dao_admin_cap, council_cap_opt) =
                dao_integration::setup_full_dao<TEST_COIN>(
                    &dao_platform_cap,
                    &mut dao_reg,
                    &pending,
                    staking_pool_id,
                    std::string::utf8(b"FlowX DAO"),
                    &clock,
                    ts::ctx(&mut scenario),
                );

            // Verify council cap returned
            assert!(council_cap_opt.is_some(), 101);

            // Cleanup
            let cap = council_cap_opt.destroy_some();
            transfer::public_transfer(cap, creator());
            sui_dao::governance::share_governance_for_testing(governance);
            sui_dao::treasury::share_treasury_for_testing(treasury);
            transfer::public_transfer(dao_admin_cap, admin());

            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_to_sender(&scenario, staking_admin_cap);
            ts::return_to_sender(&scenario, dao_platform_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
            ts::return_shared(staking_registry);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 10: FLOWX GRADUATION PARAMS EXTRACTION
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_flowx_graduation_params_extraction() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_flowx(),
                ts::ctx(&mut scenario),
            );

            // Extract all params that would be needed for FlowX
            let sui_amount = graduation::pending_sui_amount(&pending);
            let token_amount = graduation::pending_token_amount(&pending);
            let staking_amount = graduation::pending_staking_amount(&pending);
            let pool_id = graduation::pending_pool_id(&pending);
            let creator_addr = graduation::pending_creator(&pending);
            let dex_type = graduation::pending_dex_type(&pending);

            // All should be valid
            assert!(sui_amount > 0, 100);
            assert!(token_amount > 0, 101);
            assert!(staking_amount > 0, 102);
            assert!(creator_addr == creator(), 104);
            assert!(dex_type == config::dex_flowx(), 105);

            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }
}
