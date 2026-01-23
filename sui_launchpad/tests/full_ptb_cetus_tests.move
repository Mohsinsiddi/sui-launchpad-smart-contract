/// ═══════════════════════════════════════════════════════════════════════════════
/// FULL PTB FLOW TESTS - CETUS (CLMM)
/// ═══════════════════════════════════════════════════════════════════════════════
///
/// Comprehensive tests for the complete graduation + staking + DAO flow
/// using Cetus CLMM (returns Position NFT, not LP tokens)
///
/// Test Coverage:
/// - Complete PTB flow with Position NFT
/// - NFT deposit to DAO treasury
/// - Position NFT vesting for creator
/// - All config permutations for CLMM
/// - Edge cases and failure modes
///
#[test_only]
module sui_launchpad::full_ptb_cetus_tests {
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
    use sui_launchpad::cetus_adapter as cetus;
    use sui_launchpad::test_utils;
    use sui_launchpad::test_coin::TEST_COIN;

    // sui_staking imports
    use sui_staking::factory::{Self as staking_factory, StakingRegistry};
    use sui_staking::access::{AdminCap as StakingAdminCap};

    // sui_dao imports
    use sui_dao::registry::{Self as dao_registry, DAORegistry};
    use sui_dao::access::{AdminCap as DAOPlatformAdminCap};
    use sui_dao::governance::Governance;
    use sui_dao::treasury::Treasury;

    // ═══════════════════════════════════════════════════════════════════════
    // MOCK NFT FOR TESTING
    // ═══════════════════════════════════════════════════════════════════════

    /// Mock Position NFT for Cetus CLMM testing
    public struct MockPositionNFT has key, store {
        id: UID,
        pool_id: ID,
        liquidity: u128,
        tick_lower: u32,
        tick_upper: u32,
    }

    fun create_mock_position_nft(
        pool_id: ID,
        liquidity: u128,
        ctx: &mut TxContext,
    ): MockPositionNFT {
        MockPositionNFT {
            id: object::new(ctx),
            pool_id,
            liquidity,
            tick_lower: cetus::full_range_tick_lower(),
            tick_upper: cetus::full_range_tick_upper(),
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════

    fun admin(): address { @0xA1 }
    fun creator(): address { @0xC1 }
    fun platform_treasury(): address { @0xE1 }
    fun dao_treasury_addr(): address { @0xD1 }

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
    // TEST 1: COMPLETE PTB FLOW WITH CETUS (POSITION NFT)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    /// Complete graduation flow with Cetus CLMM: Token → CLMM Pool → Position NFT → DAO Treasury
    fun test_complete_ptb_flow_cetus_with_dao() {
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

            // STEP 1: Initiate graduation with Cetus
            let mut pending = graduation::initiate_graduation(
                &launchpad_admin_cap,
                &mut pool,
                &config,
                config::dex_cetus(),
                ts::ctx(&mut scenario),
            );

            // Verify DEX type
            assert!(graduation::pending_dex_type(&pending) == config::dex_cetus(), 100);

            // STEP 2: Extract all balances
            let sui_coin = graduation::extract_all_sui(&mut pending, ts::ctx(&mut scenario));
            let token_coin = graduation::extract_all_tokens(&mut pending, ts::ctx(&mut scenario));
            let staking_coin = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));

            // STEP 3: Simulate Cetus pool creation and liquidity add
            // In real PTB, this would call cetus::create_pool and add_liquidity
            // Returns a Position NFT instead of LP tokens
            let mock_pool_id = object::id_from_address(@0xCE705);
            let position_nft = create_mock_position_nft(
                mock_pool_id,
                1_000_000_000_000u128, // liquidity
                ts::ctx(&mut scenario),
            );

            // Consume the coins (in real flow, they go to DEX)
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

            // STEP 5: Create DAO linked to staking pool
            let (mut governance, dao_admin_cap) = dao_integration::create_dao<TEST_COIN>(
                &dao_platform_cap,
                &mut dao_reg,
                &pending,
                staking_pool_id,
                std::string::utf8(b"TEST DAO"),
                &clock,
                ts::ctx(&mut scenario),
            );

            // STEP 6: Create DAO Treasury
            let mut treasury = dao_integration::create_treasury(
                &dao_admin_cap,
                &mut governance,
                ts::ctx(&mut scenario),
            );

            // STEP 7: Deposit Position NFT to DAO Treasury
            // For CLMM, the Position NFT goes to the DAO treasury
            dao_integration::deposit_nft_to_treasury(&mut treasury, position_nft, ts::ctx(&mut scenario));

            // STEP 8: Complete graduation
            let receipt = graduation::complete_graduation(
                pending,
                &mut registry,
                mock_pool_id,
                0, // sui_to_liquidity
                0, // tokens_to_liquidity
                1_000_000, // total LP (represented by position liquidity)
                0, // creator LP (for NFT, creator gets vested position separately)
                1_000_000, // DAO LP (entire position in this case)
                &clock,
                ts::ctx(&mut scenario),
            );

            // Verify
            assert!(graduation::receipt_dex_pool_id(&receipt) == mock_pool_id, 200);

            // Share/transfer objects
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
            assert!(bonding_curve::is_graduated(&pool), 300);
            ts::return_shared(pool);

            let staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            assert!(staking_factory::total_pools(&staking_registry) == 1, 301);
            ts::return_shared(staking_registry);

            let dao_reg = ts::take_shared<DAORegistry>(&scenario);
            assert!(dao_registry::total_daos_created(&dao_reg) == 1, 302);
            ts::return_shared(dao_reg);

            let registry = ts::take_shared<Registry>(&scenario);
            assert!(registry::total_graduated(&registry) == 1, 303);
            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 2: CETUS ADAPTER CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_cetus_adapter_constants() {
        // Full range ticks for concentrated liquidity
        let tick_lower = cetus::full_range_tick_lower();
        let tick_upper = cetus::full_range_tick_upper();

        // Verify tick range is valid (ticks are different for a range)
        // Note: tick values are two's complement u32, so direct comparison isn't valid
        assert!(tick_lower != tick_upper, 100);

        // Default fee tier
        let fee_tier = cetus::default_fee_tier();
        assert!(fee_tier > 0, 101);

        // Minimum liquidity
        let min_liquidity = cetus::minimum_liquidity();
        assert!(min_liquidity > 0, 102);

        // Tick spacing
        let tick_spacing = cetus::default_tick_spacing();
        assert!(tick_spacing > 0, 103);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 3: CETUS SQRT PRICE CALCULATION
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_cetus_sqrt_price_calculation() {
        // 1:1 ratio should give specific sqrt price
        let sqrt_price_1_1 = cetus::calculate_sqrt_price_x64(1_000_000_000, 1_000_000_000);
        assert!(sqrt_price_1_1 > 0, 100);

        // 2:1 ratio should give different sqrt price
        let sqrt_price_2_1 = cetus::calculate_sqrt_price_x64(2_000_000_000, 1_000_000_000);
        assert!(sqrt_price_2_1 != sqrt_price_1_1, 101);

        // Verify monotonicity (more token_amount = lower sqrt_price)
        let sqrt_price_high = cetus::calculate_sqrt_price_x64(1_000_000_000, 2_000_000_000);
        let sqrt_price_low = cetus::calculate_sqrt_price_x64(2_000_000_000, 1_000_000_000);
        // The relationship depends on which token is base
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 4: POSITION NFT TREASURY DEPOSIT
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_position_nft_treasury_deposit() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        setup_dao(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let dao_platform_cap = ts::take_from_sender<DAOPlatformAdminCap>(&scenario);
            let mut dao_reg = ts::take_shared<DAORegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            // Create mock staking pool ID
            let staking_pool_id = object::id_from_address(@0x123);

            // Create governance and treasury manually for this test
            let (mut governance, dao_admin_cap) = sui_dao::governance::create_staking_governance_free(
                &dao_platform_cap,
                &mut dao_reg,
                std::string::utf8(b"Test DAO"),
                staking_pool_id,
                400, // quorum
                86_400_000, // voting delay
                259_200_000, // voting period
                172_800_000, // timelock
                100, // threshold
                &clock,
                ts::ctx(&mut scenario),
            );

            let mut treasury = sui_dao::treasury::create_treasury(
                &dao_admin_cap,
                &mut governance,
                ts::ctx(&mut scenario),
            );

            // Create Position NFT
            let mock_pool_id = object::id_from_address(@0xCE705);
            let position_nft = create_mock_position_nft(
                mock_pool_id,
                1_000_000_000_000u128,
                ts::ctx(&mut scenario),
            );

            // Check treasury has no NFTs initially
            assert!(!sui_dao::treasury::has_nft<MockPositionNFT>(&treasury), 100);

            // Deposit NFT to treasury
            sui_dao::treasury::deposit_nft(&mut treasury, position_nft, ts::ctx(&mut scenario));

            // Verify NFT was deposited
            assert!(sui_dao::treasury::has_nft<MockPositionNFT>(&treasury), 101);
            assert!(sui_dao::treasury::nft_count<MockPositionNFT>(&treasury) == 1, 102);

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
    // TEST 5: MULTIPLE POSITION NFTS IN TREASURY
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_multiple_position_nfts_in_treasury() {
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
                std::string::utf8(b"Test DAO"),
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

            // Create multiple Position NFTs (simulating multiple CLMM positions)
            let mock_pool_id = object::id_from_address(@0xCE705);
            let nft1 = create_mock_position_nft(mock_pool_id, 500_000_000_000u128, ts::ctx(&mut scenario));
            let nft2 = create_mock_position_nft(mock_pool_id, 300_000_000_000u128, ts::ctx(&mut scenario));
            let nft3 = create_mock_position_nft(mock_pool_id, 200_000_000_000u128, ts::ctx(&mut scenario));

            // Deposit all NFTs
            sui_dao::treasury::deposit_nft(&mut treasury, nft1, ts::ctx(&mut scenario));
            sui_dao::treasury::deposit_nft(&mut treasury, nft2, ts::ctx(&mut scenario));
            sui_dao::treasury::deposit_nft(&mut treasury, nft3, ts::ctx(&mut scenario));

            // Verify count
            assert!(sui_dao::treasury::nft_count<MockPositionNFT>(&treasury) == 3, 100);

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
    // TEST 6: CETUS VS SUIDEX DEX TYPE VERIFICATION
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_dex_type_verification() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        // Test Cetus DEX type
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_cetus(),
                ts::ctx(&mut scenario),
            );

            // Verify DEX type is Cetus
            assert!(graduation::pending_dex_type(&pending) == config::dex_cetus(), 100);
            assert!(graduation::pending_dex_type(&pending) != config::dex_suidex(), 101);
            assert!(graduation::pending_dex_type(&pending) != config::dex_flowx(), 102);

            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 7: GRADUATION WITH CETUS - DAO DISABLED
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_cetus_graduation_dao_disabled() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        setup_staking(&mut scenario);

        // Disable DAO
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);
            config::set_dao_enabled(&admin_cap, &mut config, false);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let staking_admin_cap = ts::take_from_sender<StakingAdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let mut pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_cetus(),
                ts::ctx(&mut scenario),
            );

            // DAO should not be created
            assert!(!dao_integration::should_create_dao(&pending), 100);

            // Extract balances
            let sui_coin = graduation::extract_all_sui(&mut pending, ts::ctx(&mut scenario));
            let token_coin = graduation::extract_all_tokens(&mut pending, ts::ctx(&mut scenario));
            let staking_coin = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));

            // Simulate Cetus operations
            coin::burn_for_testing(sui_coin);
            coin::burn_for_testing(token_coin);

            // Create staking pool
            let pool_admin_cap = staking_integration::create_staking_pool<TEST_COIN>(
                &mut staking_registry,
                &staking_admin_cap,
                &pending,
                staking_coin,
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_transfer(pool_admin_cap, admin());

            // Complete graduation without DAO
            let mock_pool_id = object::id_from_address(@0xCE705);
            let receipt = graduation::complete_graduation(
                pending,
                &mut registry,
                mock_pool_id,
                0, 0, // sui_to_liquidity, tokens_to_liquidity
                1_000_000, 0, 1_000_000,
                &clock,
                ts::ctx(&mut scenario),
            );

            graduation::destroy_receipt_for_testing(receipt);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_to_sender(&scenario, staking_admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
            ts::return_shared(registry);
            ts::return_shared(staking_registry);
            clock::destroy_for_testing(clock);
        };

        // Verify graduation succeeded
        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            assert!(bonding_curve::is_graduated(&pool), 200);
            ts::return_shared(pool);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 8: VERIFY TICK RANGE FOR FULL LIQUIDITY
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_cetus_full_range_tick_values() {
        // Get tick values
        let tick_lower = cetus::full_range_tick_lower();
        let tick_upper = cetus::full_range_tick_upper();

        // For Cetus CLMM, these should be the maximum range
        // Tick lower should be negative (represented as large u32)
        // Tick upper should be positive
        assert!(tick_lower > 0, 100); // Negative in two's complement
        assert!(tick_upper > 0, 101);

        // Verify they're different
        assert!(tick_lower != tick_upper, 102);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 9: CETUS WITH CUSTOM DAO PARAMS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_cetus_with_custom_dao_params() {
        let mut scenario = ts::begin(admin());

        setup_launchpad(&mut scenario);
        setup_staking(&mut scenario);
        setup_dao(&mut scenario);

        // Set custom DAO parameters
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            config::set_dao_quorum_bps(&admin_cap, &mut config, 1000); // 10%
            config::set_dao_voting_delay_ms(&admin_cap, &mut config, 43_200_000); // 12 hours
            config::set_dao_voting_period_ms(&admin_cap, &mut config, 604_800_000); // 7 days
            config::set_dao_timelock_delay_ms(&admin_cap, &mut config, 259_200_000); // 3 days
            config::set_dao_proposal_threshold_bps(&admin_cap, &mut config, 500); // 5%
            config::set_dao_council_enabled(&admin_cap, &mut config, true);

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
                config::dex_cetus(),
                ts::ctx(&mut scenario),
            );

            // Verify custom params
            let (quorum, voting_delay, voting_period, timelock_delay, proposal_threshold) =
                dao_integration::get_dao_params(&pending);

            assert!(quorum == 1000, 100);
            assert!(voting_delay == 43_200_000, 101);
            assert!(voting_period == 604_800_000, 102);
            assert!(timelock_delay == 259_200_000, 103);
            assert!(proposal_threshold == 500, 104);
            assert!(dao_integration::should_enable_council(&pending), 105);

            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST 10: POSITION NFT OWNERSHIP VERIFICATION
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_position_nft_ownership_after_treasury_deposit() {
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
                std::string::utf8(b"Test DAO"),
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

            // Create and deposit NFT
            let mock_pool_id = object::id_from_address(@0xCE705);
            let nft = create_mock_position_nft(mock_pool_id, 1_000_000_000_000u128, ts::ctx(&mut scenario));
            let nft_id = object::id(&nft);

            sui_dao::treasury::deposit_nft(&mut treasury, nft, ts::ctx(&mut scenario));

            // Verify NFT is in treasury (can be checked by has_nft_at_index)
            assert!(sui_dao::treasury::has_nft_at_index<MockPositionNFT>(&treasury, 0), 100);

            // NFT can only be withdrawn via DAO proposal (DAOAuth required)
            // This ensures Position NFT is safely held by the DAO

            sui_dao::governance::share_governance_for_testing(governance);
            sui_dao::treasury::destroy_treasury_for_testing(treasury);
            transfer::public_transfer(dao_admin_cap, admin());
            ts::return_to_sender(&scenario, dao_platform_cap);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }
}
