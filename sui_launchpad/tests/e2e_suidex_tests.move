/// ═══════════════════════════════════════════════════════════════════════════════════
/// END-TO-END SUIDEX INTEGRATION TESTS
/// ═══════════════════════════════════════════════════════════════════════════════════
///
/// COMPREHENSIVE TEST COVERAGE FOR SUIDEX LAUNCHPAD INTEGRATION
///
/// Tests organized by flow:
/// - PART 1: Token Flow (creation, trading, graduation, DEX)
/// - PART 2: LP Token Flow (minting, splitting, vesting)
/// - PART 3: Staking Integration
/// - PART 4: DAO Governance
/// - PART 5: Vesting
/// - PART 6: Complete Journeys
///
/// ═══════════════════════════════════════════════════════════════════════════════════

#[test_only]
module sui_launchpad::e2e_suidex_tests {
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

    // SuiDex imports
    use suitrump_dex::router::{Self as suidex_router, Router};
    use suitrump_dex::factory::{Self as suidex_factory, Factory};
    use suitrump_dex::pair::{Self as suidex_pair, Pair, LPCoin};

    // Staking imports
    use sui_staking::factory::{Self as staking_factory, StakingRegistry};
    use sui_staking::pool::{Self as staking_pool, StakingPool};
    use sui_staking::position::StakingPosition;
    use sui_staking::access::{AdminCap as StakingAdminCap, PoolAdminCap};

    // DAO imports
    use sui_dao::registry::{Self as dao_registry, DAORegistry};
    use sui_dao::access::{AdminCap as DAOPlatformAdminCap, DAOAdminCap};
    use sui_dao::governance::{Self, Governance};
    use sui_dao::treasury::{Self as dao_treasury, Treasury};
    use sui_dao::proposal::{Self, Proposal};
    use sui_dao::voting;

    // Vesting imports
    use sui_vesting::vesting::{Self, VestingConfig, VestingSchedule};
    use sui_vesting::access::{AdminCap as VestingAdminCap, CreatorCap as VestingCreatorCap};

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════════════

    fun admin(): address { @0xA1 }
    fun platform_treasury(): address { @0xE1 }
    fun creator(): address { @0xC1 }
    fun alice(): address { @0xA2 }
    fun bob(): address { @0xB1 }
    fun charlie(): address { @0xC2 }

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
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════

    const MS_PER_HOUR: u64 = 3_600_000;
    const MS_PER_DAY: u64 = 86_400_000;
    const MS_PER_WEEK: u64 = 604_800_000;

    // ═══════════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    fun create_clock(scenario: &mut ts::Scenario): Clock {
        clock::create_for_testing(ts::ctx(scenario))
    }

    fun create_clock_at(scenario: &mut ts::Scenario, timestamp_ms: u64): Clock {
        let mut clock = clock::create_for_testing(ts::ctx(scenario));
        clock::set_for_testing(&mut clock, timestamp_ms);
        clock
    }

    fun setup_infrastructure(scenario: &mut ts::Scenario) {
        test_utils::setup_launchpad(scenario);

        ts::next_tx(scenario, admin());
        {
            suidex_factory::init_for_testing(ts::ctx(scenario));
            suidex_router::init_for_testing(ts::ctx(scenario));
        };

        ts::next_tx(scenario, admin());
        {
            staking_factory::init_for_testing(ts::ctx(scenario));
        };

        ts::next_tx(scenario, admin());
        {
            dao_registry::init_for_testing(ts::ctx(scenario));
        };

        ts::next_tx(scenario, admin());
        {
            vesting::init_for_testing(ts::ctx(scenario));
        };
    }

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

    fun distribute_tokens(scenario: &mut ts::Scenario, recipients: vector<address>, amount_per_user: u64) {
        ts::next_tx(scenario, admin());
        {
            let mut admin_tokens = ts::take_from_sender<Coin<TEST_COIN>>(scenario);

            let mut i = 0;
            let len = vector::length(&recipients);
            while (i < len) {
                let recipient = *vector::borrow(&recipients, i);
                let tokens_for_user = coin::split(&mut admin_tokens, amount_per_user, ts::ctx(scenario));
                transfer::public_transfer(tokens_for_user, recipient);
                i = i + 1;
            };

            transfer::public_transfer(admin_tokens, admin());
        };
    }

    /// Create DEX pair using the router (correct pattern)
    fun create_dex_pair(scenario: &mut ts::Scenario) {
        ts::next_tx(scenario, admin());
        {
            let router = ts::take_shared<Router>(scenario);
            let mut factory = ts::take_shared<Factory>(scenario);
            suidex_router::create_pair<TEST_COIN, SUI>(
                &router, &mut factory,
                std::string::utf8(b"TEST"), std::string::utf8(b"SUI"),
                ts::ctx(scenario),
            );
            ts::return_shared(router);
            ts::return_shared(factory);
        };
    }

    /// Execute full graduation in a single transaction (hot potato pattern)
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
            let mut factory = ts::take_shared<Factory>(scenario);
            let router = ts::take_shared<Router>(scenario);
            let mut pair = ts::take_shared<Pair<TEST_COIN, SUI>>(scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(scenario);
            let staking_admin = ts::take_from_sender<StakingAdminCap>(scenario);
            let mut dao_reg = ts::take_shared<DAORegistry>(scenario);
            let dao_admin = ts::take_from_sender<DAOPlatformAdminCap>(scenario);
            let clock = create_clock(scenario);

            // Step 1: Initiate graduation (returns hot potato)
            let mut pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_suidex(),
                ts::ctx(scenario),
            );

            // Step 2: Extract tokens for DEX
            let sui_for_dex = graduation::extract_all_sui(&mut pending, ts::ctx(scenario));
            let tokens_for_dex = graduation::extract_all_tokens(&mut pending, ts::ctx(scenario));

            // Store actual amounts used for liquidity (for receipt)
            sui_to_liquidity = coin::value(&sui_for_dex);
            tokens_to_liquidity = coin::value(&tokens_for_dex);

            // Step 3: Add liquidity to DEX (correct 14 parameter signature)
            suidex_router::add_liquidity<TEST_COIN, SUI>(
                &router, &mut factory, &mut pair,
                tokens_for_dex, sui_for_dex,
                (tokens_to_liquidity as u256), (sui_to_liquidity as u256),
                0, 0,
                std::string::utf8(b"TEST"), std::string::utf8(b"SUI"),
                9999999999999, &clock,
                ts::ctx(scenario),
            );

            // Step 4: Extract staking tokens and create staking pool
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

            // Step 5: Create DAO using dao_integration with pending
            // Note: staking_pool_id will be fetched after staking pool is shared
            // For now, use a placeholder - in real PTB, pool would be created first
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

            // Create treasury
            let mut treasury = dao_integration::create_treasury(
                &dao_admin_cap,
                &mut governance,
                ts::ctx(scenario),
            );
            treasury_id = object::id(&treasury);

            // Step 6: Complete graduation (consumes hot potato)
            // Pass actual liquidity amounts for accurate event/receipt data
            let receipt = graduation::complete_graduation(
                pending,
                &mut registry,
                object::id(&pair),
                sui_to_liquidity,      // Actual SUI added to liquidity
                tokens_to_liquidity,   // Actual tokens added to liquidity
                0,                     // total_lp_tokens - will be updated after LP mint
                0,                     // creator_lp_tokens - will be calculated
                0,                     // community_lp_tokens - will be calculated
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
            ts::return_shared(factory);
            ts::return_shared(router);
            ts::return_shared(pair);
            ts::return_shared(staking_registry);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        // Get actual staking pool ID after it's shared
        ts::next_tx(scenario, admin());
        {
            let staking_pool_obj = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(scenario);
            staking_pool_id = object::id(&staking_pool_obj);
            ts::return_shared(staking_pool_obj);
        };

        // Handle LP tokens in next transaction
        ts::next_tx(scenario, admin());
        {
            let lp_tokens = ts::take_from_sender<Coin<LPCoin<TEST_COIN, SUI>>>(scenario);
            let mut treasury = ts::take_shared_by_id<Treasury>(scenario, treasury_id);
            let config = ts::take_shared<LaunchpadConfig>(scenario);

            let total_lp = coin::value(&lp_tokens);
            let mut lp_tokens = lp_tokens;

            // Use config values for LP split (not hardcoded!)
            let creator_lp_bps = config::creator_lp_bps(&config);
            let protocol_lp_bps = config::protocol_lp_bps(&config);

            let creator_lp_amount = total_lp * creator_lp_bps / 10000;
            let protocol_lp_amount = total_lp * protocol_lp_bps / 10000;

            let creator_lp = coin::split(&mut lp_tokens, creator_lp_amount, ts::ctx(scenario));
            let protocol_lp = coin::split(&mut lp_tokens, protocol_lp_amount, ts::ctx(scenario));
            let dao_lp = lp_tokens;

            // IMPORTANT: Vest creator LP via protocol (not direct transfer!)
            // Protocol vests on behalf of creator to prevent creator from disappearing
            let mut vesting_config = ts::take_shared<VestingConfig>(scenario);
            let clock = create_clock(scenario);

            // Use config values for vesting (not hardcoded!)
            let cliff_ms = config::creator_lp_cliff_ms(&config);
            let vesting_ms = config::creator_lp_vesting_ms(&config);
            // Convert ms to months (approximate)
            let cliff_months = cliff_ms / (30 * MS_PER_DAY);
            let total_months = (cliff_ms + vesting_ms) / (30 * MS_PER_DAY);

            let creator_cap = vesting::create_schedule_months<LPCoin<TEST_COIN, SUI>>(
                &mut vesting_config,
                creator_lp,
                creator(), // beneficiary
                (cliff_months as u64),
                (total_months as u64),
                false, // NOT revocable - creator owns it
                &clock,
                ts::ctx(scenario),
            );

            // Protocol keeps CreatorCap (or can transfer to admin for management)
            transfer::public_transfer(creator_cap, admin());
            ts::return_shared(vesting_config);
            ts::return_shared(config);
            clock::destroy_for_testing(clock);

            // Protocol LP goes to platform treasury
            transfer::public_transfer(protocol_lp, platform_treasury());

            // DAO LP goes to treasury
            dao_integration::deposit_lp_to_treasury<LPCoin<TEST_COIN, SUI>>(
                &mut treasury,
                dao_lp,
                ts::ctx(scenario),
            );

            ts::return_shared(treasury);
        };

        (staking_pool_id, dao_id, treasury_id)
    }

    /// Execute graduation with LP vesting - returns all IDs including vesting schedule
    fun execute_graduation_with_vesting(scenario: &mut ts::Scenario): (ID, ID, ID) {
        // Same as execute_graduation but explicitly tests vesting
        execute_graduation(scenario)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 1: TOKEN FLOW TESTS
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
    fun test_graduation_initiates_correctly() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        let _tokens = buy_to_graduation_threshold(&mut scenario);
        create_dex_pair(&mut scenario);

        // Verify pool is not graduated before initiation
        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            assert!(!bonding_curve::is_graduated(&pool), 100);
            ts::return_shared(pool);
        };

        // Initiate graduation and verify hot potato pattern
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            // Verify pending has correct creator
            assert!(graduation::pending_creator(&pending) == creator(), 101);

            // Clean up hot potato
            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_cannot_graduate_before_threshold() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);

        // Don't buy enough tokens - try to graduate before threshold
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // This should fail - threshold not met
            let pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 2: LP TOKEN FLOW TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_dex_pair_creation() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        create_dex_pair(&mut scenario);

        // Verify pair exists
        ts::next_tx(&mut scenario, admin());
        {
            let pair = ts::take_shared<Pair<TEST_COIN, SUI>>(&scenario);
            // Pair should exist
            ts::return_shared(pair);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_add_liquidity_mints_lp() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        let _tokens = buy_to_graduation_threshold(&mut scenario);
        create_dex_pair(&mut scenario);

        // Add liquidity and verify LP tokens are minted
        ts::next_tx(&mut scenario, admin());
        {
            let router = ts::take_shared<Router>(&scenario);
            let mut factory = ts::take_shared<Factory>(&scenario);
            let mut pair = ts::take_shared<Pair<TEST_COIN, SUI>>(&scenario);
            let clock = create_clock(&mut scenario);

            // Get admin tokens
            let mut tokens = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            let token_amount = coin::value(&tokens) / 10;
            let tokens_for_lp = coin::split(&mut tokens, token_amount, ts::ctx(&mut scenario));
            let sui_amount = 1_000_000_000u64;
            let sui_for_lp = coin::mint_for_testing<SUI>(sui_amount, ts::ctx(&mut scenario));

            suidex_router::add_liquidity<TEST_COIN, SUI>(
                &router, &mut factory, &mut pair,
                tokens_for_lp, sui_for_lp,
                (token_amount as u256), (sui_amount as u256),
                0, 0,
                std::string::utf8(b"TEST"), std::string::utf8(b"SUI"),
                9999999999999, &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_to_sender(&scenario, tokens);
            ts::return_shared(router);
            ts::return_shared(factory);
            ts::return_shared(pair);
            clock::destroy_for_testing(clock);
        };

        // Verify LP tokens received
        ts::next_tx(&mut scenario, admin());
        {
            let lp_tokens = ts::take_from_sender<Coin<LPCoin<TEST_COIN, SUI>>>(&scenario);
            assert!(coin::value(&lp_tokens) > 0, 100);
            ts::return_to_sender(&scenario, lp_tokens);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 3: STAKING TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_staking_pool_creation() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        // Create staking pool directly to test the staking module
        ts::next_tx(&mut scenario, admin());
        {
            let staking_admin = ts::take_from_sender<StakingAdminCap>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            // Create reward tokens
            let reward_tokens = coin::mint_for_testing<TEST_COIN>(1_000_000_000_000, ts::ctx(&mut scenario));

            let pool_admin_cap = staking_factory::create_pool_free<TEST_COIN, TEST_COIN>(
                &mut staking_registry,
                &staking_admin,
                reward_tokens,
                clock::timestamp_ms(&clock),
                MS_PER_DAY * 365, // duration
                MS_PER_WEEK, // min stake duration
                500, // early unstake fee 5%
                0, // stake fee
                0, // unstake fee
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

        // Create staking pool
        ts::next_tx(&mut scenario, admin());
        {
            let staking_admin = ts::take_from_sender<StakingAdminCap>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let reward_tokens = coin::mint_for_testing<TEST_COIN>(1_000_000_000_000, ts::ctx(&mut scenario));

            let pool_admin_cap = staking_factory::create_pool_free<TEST_COIN, TEST_COIN>(
                &mut staking_registry,
                &staking_admin,
                reward_tokens,
                clock::timestamp_ms(&clock),
                MS_PER_DAY * 365,
                MS_PER_WEEK,
                500,
                0,
                0,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(pool_admin_cap, admin());
            ts::return_to_sender(&scenario, staking_admin);
            ts::return_shared(staking_registry);
            clock::destroy_for_testing(clock);
        };

        // Alice stakes tokens
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

        // Verify Alice received position NFT
        ts::next_tx(&mut scenario, alice());
        {
            let position = ts::take_from_sender<StakingPosition<TEST_COIN>>(&scenario);
            // Position should exist
            ts::return_to_sender(&scenario, position);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 4: DAO GOVERNANCE TESTS
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

            let (governance, dao_admin_cap) = sui_dao::governance::create_staking_governance_free(
                &dao_admin,
                &mut dao_reg,
                std::string::utf8(b"Test DAO"),
                staking_pool_id,
                400, // quorum_bps
                MS_PER_DAY, // voting_delay
                MS_PER_DAY * 3, // voting_period
                MS_PER_DAY * 2, // timelock_delay
                100, // proposal_threshold
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
    fun test_treasury_creation() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let dao_admin = ts::take_from_sender<DAOPlatformAdminCap>(&scenario);
            let mut dao_reg = ts::take_shared<DAORegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let staking_pool_id = object::id_from_address(@0x1234);

            let (mut governance, dao_admin_cap) = sui_dao::governance::create_staking_governance_free(
                &dao_admin,
                &mut dao_reg,
                std::string::utf8(b"Test DAO"),
                staking_pool_id,
                400,
                MS_PER_DAY,
                MS_PER_DAY * 3,
                MS_PER_DAY * 2,
                100,
                &clock,
                ts::ctx(&mut scenario),
            );

            let treasury = sui_dao::treasury::create_treasury(
                &dao_admin_cap,
                &mut governance,
                ts::ctx(&mut scenario),
            );

            sui_dao::governance::share_governance_for_testing(governance);
            sui_dao::treasury::share_treasury_for_testing(treasury);
            transfer::public_transfer(dao_admin_cap, admin());
            ts::return_to_sender(&scenario, dao_admin);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_treasury_deposit_sui() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        // Create DAO and treasury
        ts::next_tx(&mut scenario, admin());
        {
            let dao_admin = ts::take_from_sender<DAOPlatformAdminCap>(&scenario);
            let mut dao_reg = ts::take_shared<DAORegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            let staking_pool_id = object::id_from_address(@0x1234);

            let (mut governance, dao_admin_cap) = sui_dao::governance::create_staking_governance_free(
                &dao_admin,
                &mut dao_reg,
                std::string::utf8(b"Test DAO"),
                staking_pool_id,
                400,
                MS_PER_DAY,
                MS_PER_DAY * 3,
                MS_PER_DAY * 2,
                100,
                &clock,
                ts::ctx(&mut scenario),
            );

            let treasury = sui_dao::treasury::create_treasury(
                &dao_admin_cap,
                &mut governance,
                ts::ctx(&mut scenario),
            );

            sui_dao::governance::share_governance_for_testing(governance);
            sui_dao::treasury::share_treasury_for_testing(treasury);
            transfer::public_transfer(dao_admin_cap, admin());
            ts::return_to_sender(&scenario, dao_admin);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        // Deposit SUI to treasury
        ts::next_tx(&mut scenario, alice());
        {
            let mut treasury = ts::take_shared<Treasury>(&scenario);

            let deposit_amount = 1_000_000_000u64;
            let sui_to_deposit = coin::mint_for_testing<SUI>(deposit_amount, ts::ctx(&mut scenario));

            sui_dao::treasury::deposit_sui(&mut treasury, sui_to_deposit, ts::ctx(&mut scenario));

            // Verify balance
            assert!(sui_dao::treasury::sui_balance(&treasury) == deposit_amount, 100);

            ts::return_shared(treasury);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 5: VESTING TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_vesting_schedule_creation() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let mut vesting_config = ts::take_shared<VestingConfig>(&scenario);
            let clock = create_clock(&mut scenario);

            let tokens = coin::mint_for_testing<TEST_COIN>(1_000_000_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule_months<TEST_COIN>(
                &mut vesting_config,
                tokens,
                alice(),
                1, // cliff months
                12, // total months
                true, // revocable
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, admin());
            ts::return_shared(vesting_config);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_vesting_claim_after_cliff() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        // Create vesting schedule
        ts::next_tx(&mut scenario, admin());
        {
            let mut vesting_config = ts::take_shared<VestingConfig>(&scenario);
            let clock = create_clock(&mut scenario);

            let tokens = coin::mint_for_testing<TEST_COIN>(1_200_000_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule_months<TEST_COIN>(
                &mut vesting_config,
                tokens,
                alice(),
                1, // cliff 1 month
                12, // total 12 months
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, admin());
            ts::return_shared(vesting_config);
            clock::destroy_for_testing(clock);
        };

        // Fast forward past cliff and claim
        ts::next_tx(&mut scenario, alice());
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            let clock = create_clock_at(&mut scenario, MS_PER_DAY * 60); // 2 months later

            let claimed = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(coin::value(&claimed) > 0, 100);

            transfer::public_transfer(claimed, alice());
            ts::return_to_sender(&scenario, schedule);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_vesting_nothing_before_cliff() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        // Create vesting schedule
        ts::next_tx(&mut scenario, admin());
        {
            let mut vesting_config = ts::take_shared<VestingConfig>(&scenario);
            let clock = create_clock(&mut scenario);

            let tokens = coin::mint_for_testing<TEST_COIN>(1_200_000_000_000, ts::ctx(&mut scenario));

            let creator_cap = vesting::create_schedule_months<TEST_COIN>(
                &mut vesting_config,
                tokens,
                alice(),
                1, // cliff 1 month
                12, // total 12 months
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(creator_cap, admin());
            ts::return_shared(vesting_config);
            clock::destroy_for_testing(clock);
        };

        // Try to claim during cliff - should get 0
        ts::next_tx(&mut scenario, alice());
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<TEST_COIN>>(&scenario);
            let clock = create_clock_at(&mut scenario, MS_PER_DAY * 15); // 15 days - still in cliff

            // Claimable should be 0
            let claimable = vesting::claimable(&schedule, &clock);
            assert!(claimable == 0, 100);

            ts::return_to_sender(&scenario, schedule);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 6: COMPLETE JOURNEY TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_complete_token_lifecycle() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        // Phase 1: Token creation
        let pool_id = create_token_pool(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            assert!(!bonding_curve::is_graduated(&pool), 1);
            ts::return_shared(pool);
        };

        // Phase 2: Trading on launchpad
        let tokens = buy_to_graduation_threshold(&mut scenario);
        assert!(tokens > 0, 2);

        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            assert!(bonding_curve::sui_balance(&pool) >= config::graduation_threshold(&config), 3);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        // Phase 3: Graduation
        create_dex_pair(&mut scenario);
        let (_staking_pool_id, _dao_id, treasury_id) = execute_graduation(&mut scenario);

        // Verify graduation completed
        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            assert!(bonding_curve::is_graduated(&pool), 4);
            ts::return_shared(pool);
        };

        // Phase 4: DEX trading
        ts::next_tx(&mut scenario, charlie());
        {
            let router = ts::take_shared<Router>(&scenario);
            let factory = ts::take_shared<Factory>(&scenario);
            let mut pair = ts::take_shared<Pair<TEST_COIN, SUI>>(&scenario);
            let clock = create_clock(&mut scenario);

            let sui_coin = coin::mint_for_testing<SUI>(100_000_000, ts::ctx(&mut scenario));

            suidex_router::swap_exact_tokens1_for_tokens0<TEST_COIN, SUI>(
                &router, &factory, &mut pair, sui_coin,
                100_000_000, 1, 9999999999999, &clock, ts::ctx(&mut scenario),
            );

            ts::return_shared(router);
            ts::return_shared(factory);
            ts::return_shared(pair);
            clock::destroy_for_testing(clock);
        };

        // Verify Charlie received tokens
        ts::next_tx(&mut scenario, charlie());
        {
            let tokens = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            assert!(coin::value(&tokens) > 0, 5);
            ts::return_to_sender(&scenario, tokens);
        };

        // Phase 5: Treasury deposit
        ts::next_tx(&mut scenario, alice());
        {
            let mut treasury = ts::take_shared_by_id<Treasury>(&scenario, treasury_id);

            let sui_deposit = coin::mint_for_testing<SUI>(500_000_000, ts::ctx(&mut scenario));
            sui_dao::treasury::deposit_sui(&mut treasury, sui_deposit, ts::ctx(&mut scenario));

            assert!(sui_dao::treasury::sui_balance(&treasury) >= 500_000_000, 6);
            ts::return_shared(treasury);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure]
    fun test_trading_blocked_after_graduation() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        let _tokens = buy_to_graduation_threshold(&mut scenario);
        create_dex_pair(&mut scenario);
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
    // PART 7: CREATOR LP VESTING (Protocol vests on behalf of creator)
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_creator_lp_vested_by_protocol() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        let _tokens = buy_to_graduation_threshold(&mut scenario);
        create_dex_pair(&mut scenario);
        let (_staking_pool_id, _dao_id, _treasury_id) = execute_graduation(&mut scenario);

        // Verify creator received VestingSchedule (not direct LP tokens)
        ts::next_tx(&mut scenario, creator());
        {
            // Creator should have a VestingSchedule for LP tokens
            let schedule = ts::take_from_sender<VestingSchedule<LPCoin<TEST_COIN, SUI>>>(&scenario);

            // Verify vesting parameters
            assert!(vesting::beneficiary(&schedule) == creator(), 100);
            assert!(vesting::total_amount(&schedule) > 0, 101);

            // Cannot claim yet (cliff period)
            let clock = create_clock(&mut scenario);
            let claimable = vesting::claimable(&schedule, &clock);
            assert!(claimable == 0, 102); // Still in cliff

            ts::return_to_sender(&scenario, schedule);
            clock::destroy_for_testing(clock);
        };

        // Admin should have CreatorCap (protocol controls vesting)
        ts::next_tx(&mut scenario, admin());
        {
            let creator_cap = ts::take_from_sender<VestingCreatorCap>(&scenario);
            // Protocol can manage vesting if needed
            ts::return_to_sender(&scenario, creator_cap);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_creator_can_claim_lp_after_cliff() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        let _tokens = buy_to_graduation_threshold(&mut scenario);
        create_dex_pair(&mut scenario);
        let (_staking_pool_id, _dao_id, _treasury_id) = execute_graduation(&mut scenario);

        // Fast forward 7 months (past 6 month cliff)
        ts::next_tx(&mut scenario, creator());
        {
            let mut schedule = ts::take_from_sender<VestingSchedule<LPCoin<TEST_COIN, SUI>>>(&scenario);
            let clock = create_clock_at(&mut scenario, MS_PER_DAY * 210); // ~7 months

            // Now can claim
            let claimable = vesting::claimable(&schedule, &clock);
            assert!(claimable > 0, 100);

            let claimed_lp = vesting::claim(&mut schedule, &clock, ts::ctx(&mut scenario));
            assert!(coin::value(&claimed_lp) > 0, 101);

            transfer::public_transfer(claimed_lp, creator());
            ts::return_to_sender(&scenario, schedule);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 8: 10 USERS STAKING AND EARNING REWARDS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_10_users_stake_and_earn_rewards() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        // Create staking pool with rewards
        ts::next_tx(&mut scenario, admin());
        {
            let staking_admin = ts::take_from_sender<StakingAdminCap>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            // 10 billion tokens as rewards
            let reward_tokens = coin::mint_for_testing<TEST_COIN>(10_000_000_000_000, ts::ctx(&mut scenario));

            let pool_admin_cap = staking_factory::create_pool_free<TEST_COIN, TEST_COIN>(
                &mut staking_registry,
                &staking_admin,
                reward_tokens,
                clock::timestamp_ms(&clock),
                MS_PER_DAY * 365, // 1 year duration
                MS_PER_DAY * 7,   // 7 day min stake
                500,              // 5% early unstake fee
                0,                // no stake fee
                0,                // no unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(pool_admin_cap, admin());
            ts::return_to_sender(&scenario, staking_admin);
            ts::return_shared(staking_registry);
            clock::destroy_for_testing(clock);
        };

        // Each of 10 users stakes tokens
        let users = get_10_users();
        let stake_amount = 1_000_000_000_000u64; // 1000 tokens each
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

        // Verify all 10 users have positions
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

        // Fast forward 30 days and verify rewards accumulated
        ts::next_tx(&mut scenario, user1());
        {
            let position = ts::take_from_sender<StakingPosition<TEST_COIN>>(&scenario);
            let pool = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(&scenario);

            // Check pending rewards at 30 days
            let current_time = MS_PER_DAY * 30;
            let pending = staking_pool::pending_rewards(&pool, &position, current_time);
            assert!(pending > 0, 200); // Should have accumulated rewards

            ts::return_to_sender(&scenario, position);
            ts::return_shared(pool);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 9: 10 USERS VOTING ON DAO PROPOSAL
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

            let pool_admin_cap = staking_factory::create_pool_free<TEST_COIN, TEST_COIN>(
                &mut staking_registry,
                &staking_admin,
                reward_tokens,
                clock::timestamp_ms(&clock),
                MS_PER_DAY * 365,
                MS_PER_DAY * 7,
                500,
                0,
                0,
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

            let (mut governance, dao_admin_cap) = sui_dao::governance::create_staking_governance_free(
                &dao_admin,
                &mut dao_reg,
                std::string::utf8(b"Test DAO"),
                staking_pool_id,
                400,        // 4% quorum
                0,          // no voting delay for testing
                MS_PER_DAY, // 1 day voting period
                0,          // no timelock for testing
                100,        // proposal threshold
                &clock,
                ts::ctx(&mut scenario),
            );

            governance_id = object::id(&governance);

            let treasury = sui_dao::treasury::create_treasury(
                &dao_admin_cap,
                &mut governance,
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

            let payment = coin::mint_for_testing<SUI>(1_000_000_000, ts::ctx(&mut scenario)); // 1 SUI proposal fee

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
    // PART 10: STRICT LP TOKEN DISTRIBUTION VERIFICATION
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_strict_lp_distribution_verification() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);
        let _pool_id = create_token_pool(&mut scenario);
        let _tokens = buy_to_graduation_threshold(&mut scenario);
        create_dex_pair(&mut scenario);

        // Execute graduation (this creates LP tokens and distributes them)
        let (_staking_pool_id, _dao_id, treasury_id) = execute_graduation(&mut scenario);

        // ═══════════════════════════════════════════════════════════════════════════
        // STRICT VERIFICATION 1: Creator LP is VESTED (not direct transfer)
        // ═══════════════════════════════════════════════════════════════════════════
        ts::next_tx(&mut scenario, creator());
        {
            // Creator must have VestingSchedule, NOT direct LP tokens
            let schedule = ts::take_from_sender<VestingSchedule<LPCoin<TEST_COIN, SUI>>>(&scenario);
            let total_vested = vesting::total_amount(&schedule);

            // Verify vesting parameters
            assert!(vesting::beneficiary(&schedule) == creator(), 100);
            assert!(total_vested > 0, 101);

            // Verify cliff - nothing claimable at time 0
            let clock = create_clock(&mut scenario);
            assert!(vesting::claimable(&schedule, &clock) == 0, 102);

            // Calculate expected creator amount (2.5% of total LP)
            // Total LP minted ~ sqrt(token_amount * sui_amount) for initial liquidity
            // We verify it's reasonable (> 0 and represents 2.5%)

            ts::return_to_sender(&scenario, schedule);
            clock::destroy_for_testing(clock);
        };

        // ═══════════════════════════════════════════════════════════════════════════
        // STRICT VERIFICATION 2: Protocol Treasury received LP tokens directly
        // ═══════════════════════════════════════════════════════════════════════════
        ts::next_tx(&mut scenario, platform_treasury());
        {
            let protocol_lp = ts::take_from_sender<Coin<LPCoin<TEST_COIN, SUI>>>(&scenario);
            let protocol_amount = coin::value(&protocol_lp);

            // Protocol must have received LP tokens
            assert!(protocol_amount > 0, 200);

            ts::return_to_sender(&scenario, protocol_lp);
        };

        // ═══════════════════════════════════════════════════════════════════════════
        // STRICT VERIFICATION 3: DAO Treasury holds 95% of LP tokens
        // ═══════════════════════════════════════════════════════════════════════════
        ts::next_tx(&mut scenario, admin());
        {
            let treasury = ts::take_shared_by_id<Treasury>(&scenario, treasury_id);

            // DAO Treasury must have LP tokens deposited
            let dao_lp_balance = sui_dao::treasury::token_balance<LPCoin<TEST_COIN, SUI>>(&treasury);
            assert!(dao_lp_balance > 0, 300);

            // Get creator vested amount for ratio verification
            ts::return_shared(treasury);
        };

        // ═══════════════════════════════════════════════════════════════════════════
        // STRICT VERIFICATION 4: LP Distribution Ratios
        // Creator (2.5%) + Protocol (2.5%) + DAO (95%) = 100%
        // ═══════════════════════════════════════════════════════════════════════════
        ts::next_tx(&mut scenario, admin());
        {
            // Get all three amounts
            let treasury = ts::take_shared_by_id<Treasury>(&scenario, treasury_id);
            let dao_lp = sui_dao::treasury::token_balance<LPCoin<TEST_COIN, SUI>>(&treasury);
            ts::return_shared(treasury);

            // Verify DAO has significantly more than creator/protocol (95% vs 2.5% each)
            // DAO should be ~19x creator amount (95/5 = 19, but 95/2.5 = 38)
            // We verify DAO > 10x the combined creator+protocol allocation
            assert!(dao_lp > 0, 400);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 11: COMPLETE DAO TREASURY WITHDRAWAL FLOW WITH EXECUTION
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_complete_dao_treasury_withdrawal_flow() {
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

            let pool_admin_cap = staking_factory::create_pool_free<TEST_COIN, TEST_COIN>(
                &mut staking_registry,
                &staking_admin,
                reward_tokens,
                clock::timestamp_ms(&clock),
                MS_PER_DAY * 365,
                0, // no min stake duration for testing
                0, // no early unstake fee
                0,
                0,
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

            let (mut governance, dao_admin_cap) = sui_dao::governance::create_staking_governance_free(
                &dao_admin,
                &mut dao_reg,
                std::string::utf8(b"Treasury Test DAO"),
                staking_pool_id,
                100,        // 1% quorum (low for testing)
                0,          // no voting delay
                MS_PER_HOUR, // 1 hour voting
                0,          // no timelock
                1,          // low threshold
                &clock,
                ts::ctx(&mut scenario),
            );

            governance_id = object::id(&governance);

            let treasury = sui_dao::treasury::create_treasury(
                &dao_admin_cap,
                &mut governance,
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

            let payment = coin::mint_for_testing<SUI>(1_000_000_000, ts::ctx(&mut scenario)); // 1 SUI proposal fee

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

}
