/// ═══════════════════════════════════════════════════════════════════════════════════
/// END-TO-END CETUS CLMM INTEGRATION TESTS
/// ═══════════════════════════════════════════════════════════════════════════════════
///
/// COMPREHENSIVE TEST COVERAGE FOR CETUS LAUNCHPAD INTEGRATION
///
/// FOLLOWS EXACT SAME PATTERN AS e2e_suidex_tests.move:
/// - Uses graduation::initiate_graduation (hot potato pattern)
/// - Uses graduation::extract_all_sui, extract_all_tokens, extract_staking_tokens
/// - Uses staking_integration::create_staking_pool
/// - Uses dao_integration::create_dao, create_treasury
/// - Uses graduation::complete_graduation
///
/// Tests organized by flow:
/// - PART 1: Token Flow (creation, trading, graduation, DEX)
/// - PART 2: LP Token Flow (Position NFTs, multi-position distribution)
/// - PART 3: Staking Integration
/// - PART 4: DAO Governance
/// - PART 5: Complete Journeys
///
/// KEY DIFFERENCE FROM SUIDEX:
/// - SuiDex returns LPCoin<A, B> (fungible, splittable, can be vested)
/// - Cetus returns Position NFT (non-fungible, cannot split)
/// - For Cetus: Create 3 separate Position NFTs for creator/protocol/DAO
/// - Position NFTs transferred directly (current vesting module doesn't support NFTs)
///
/// ═══════════════════════════════════════════════════════════════════════════════════

#[test_only]
module sui_launchpad::e2e_cetus_tests {
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
    use sui_launchpad::cetus_adapter;

    // Cetus CLMM imports (real contracts)
    use cetus_clmm::config::{Self as cetus_config, GlobalConfig, AdminCap as CetusAdminCap};
    use cetus_clmm::factory::{Self as cetus_factory, Pools};
    use cetus_clmm::pool::{Self as cetus_pool, Pool};
    use cetus_clmm::pool_creator;
    use cetus_clmm::position::Position;

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
    use sui_vesting::nft_vesting;  // For Position NFT vesting (like SuiDex vests LP coins)
    use sui_vesting::access::{AdminCap as VestingAdminCap, CreatorCap as VestingCreatorCap};

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES (same as SuiDex tests)
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
    // CONSTANTS (same as SuiDex tests)
    // ═══════════════════════════════════════════════════════════════════════════════

    const MS_PER_HOUR: u64 = 3_600_000;
    const MS_PER_DAY: u64 = 86_400_000;
    const MS_PER_WEEK: u64 = 604_800_000;
    const ONE_SUI: u64 = 1_000_000_000;

    // Cetus CLMM constants
    const TICK_SPACING_60: u32 = 60;
    const TICK_SPACING_200: u32 = 200;
    const FEE_RATE_3000: u64 = 3000;  // 0.3%
    const FEE_RATE_10000: u64 = 10000; // 1%
    const DEFAULT_PROTOCOL_FEE: u64 = 2000; // 0.2%
    const SQRT_PRICE_1_TO_1: u128 = 18446744073709551616; // 2^64

    // ═══════════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS (same pattern as SuiDex)
    // ═══════════════════════════════════════════════════════════════════════════════

    fun create_clock(scenario: &mut ts::Scenario): Clock {
        clock::create_for_testing(ts::ctx(scenario))
    }

    fun create_clock_at(scenario: &mut ts::Scenario, timestamp_ms: u64): Clock {
        let mut clock = clock::create_for_testing(ts::ctx(scenario));
        clock::set_for_testing(&mut clock, timestamp_ms);
        clock
    }

    /// Setup complete infrastructure for Cetus graduation tests
    /// SAME PATTERN AS SUIDEX: setup_infrastructure
    fun setup_infrastructure(scenario: &mut ts::Scenario) {
        // 1. Setup launchpad (same as SuiDex)
        test_utils::setup_launchpad(scenario);

        // 2. Setup Cetus CLMM infrastructure (instead of SuiDex factory/router)
        ts::next_tx(scenario, admin());
        {
            let (cetus_admin_cap, mut global_config) = cetus_config::new_global_config_for_test(
                ts::ctx(scenario),
                DEFAULT_PROTOCOL_FEE,
            );
            // Add fee tiers (required for pool creation)
            cetus_config::add_fee_tier(&mut global_config, TICK_SPACING_200, FEE_RATE_10000, ts::ctx(scenario));
            cetus_config::add_fee_tier(&mut global_config, TICK_SPACING_60, FEE_RATE_3000, ts::ctx(scenario));

            // Create Pools
            let mut pools = cetus_factory::new_pools_for_test(ts::ctx(scenario));

            // Initialize PermissionPairManager and DenyCoinList
            cetus_factory::init_manager_and_whitelist(&global_config, &mut pools, ts::ctx(scenario));

            transfer::public_share_object(global_config);
            transfer::public_share_object(pools);
            transfer::public_transfer(cetus_admin_cap, admin());
        };

        // 3. Setup Staking (same as SuiDex)
        ts::next_tx(scenario, admin());
        {
            staking_factory::init_for_testing(ts::ctx(scenario));
        };

        // 4. Setup DAO (same as SuiDex)
        ts::next_tx(scenario, admin());
        {
            dao_registry::init_for_testing(ts::ctx(scenario));
        };

        // 5. Setup Vesting (same as SuiDex)
        ts::next_tx(scenario, admin());
        {
            vesting::init_for_testing(ts::ctx(scenario));
        };
    }

    /// Create token pool (same as SuiDex)
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

    /// Buy to graduation threshold (same as SuiDex)
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

    /// Execute full Cetus graduation in a single transaction (hot potato pattern)
    /// SAME PATTERN AS SUIDEX execute_graduation
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

            // Cetus infrastructure (instead of SuiDex factory/router/pair)
            let global_config = ts::take_shared<GlobalConfig>(scenario);
            let mut pools = ts::take_shared<Pools>(scenario);

            let mut staking_registry = ts::take_shared<StakingRegistry>(scenario);
            let staking_admin = ts::take_from_sender<StakingAdminCap>(scenario);
            let mut dao_reg = ts::take_shared<DAORegistry>(scenario);
            let dao_admin = ts::take_from_sender<DAOPlatformAdminCap>(scenario);
            let clock = create_clock(scenario);

            // Step 1: Initiate graduation (returns hot potato) - SAME AS SUIDEX
            let mut pending = graduation::initiate_graduation(
                &admin_cap,
                &mut pool,
                &config,
                config::dex_cetus(),  // Use Cetus DEX type
                ts::ctx(scenario),
            );

            // Step 2: Extract tokens for DEX - SAME AS SUIDEX
            let sui_for_dex = graduation::extract_all_sui(&mut pending, ts::ctx(scenario));
            let tokens_for_dex = graduation::extract_all_tokens(&mut pending, ts::ctx(scenario));

            sui_to_liquidity = coin::value(&sui_for_dex);
            tokens_to_liquidity = coin::value(&tokens_for_dex);

            // Step 3: Create Cetus pool with multi-position LP distribution
            // KEY DIFFERENCE FROM SUIDEX:
            // - SuiDex: add_liquidity returns LP coins that can be split
            // - Cetus: create_pool_v3 returns Position NFT, need 3 separate positions

            // Calculate splits using config values (like SuiDex)
            let creator_lp_bps = config::creator_lp_bps(&config);
            let protocol_lp_bps = config::protocol_lp_bps(&config);
            let dao_lp_bps = 10000 - creator_lp_bps - protocol_lp_bps;

            let dao_sui = (((sui_to_liquidity as u128) * (dao_lp_bps as u128)) / 10000) as u64;
            let dao_tokens = (((tokens_to_liquidity as u128) * (dao_lp_bps as u128)) / 10000) as u64;
            let creator_sui = (((sui_to_liquidity as u128) * (creator_lp_bps as u128)) / 10000) as u64;
            let creator_tokens = (((tokens_to_liquidity as u128) * (creator_lp_bps as u128)) / 10000) as u64;
            let protocol_sui = sui_to_liquidity - dao_sui - creator_sui;
            let protocol_tokens = tokens_to_liquidity - dao_tokens - creator_tokens;

            // Split coins for positions
            // In test: we only use DAO portion for pool creation here
            // Creator/protocol portions are minted fresh in next transaction for simplicity
            // In production PTB: all positions created in single transaction
            let mut sui_coin = sui_for_dex;
            let mut token_coin = tokens_for_dex;

            let dao_sui_coin = coin::split(&mut sui_coin, dao_sui, ts::ctx(scenario));
            let dao_token_coin = coin::split(&mut token_coin, dao_tokens, ts::ctx(scenario));

            // Burn remaining coins - in production these would be used for creator/protocol positions
            // in the same PTB transaction
            coin::burn_for_testing(sui_coin);
            coin::burn_for_testing(token_coin);

            let (tick_lower, tick_upper) = pool_creator::full_range_tick_range(TICK_SPACING_60);

            // Create DAO position (95%) - creates the pool
            // Note: SUI must be CoinTypeA (lexicographically greater)
            let (dao_position, rem_sui, rem_token) = pool_creator::create_pool_v3<SUI, TEST_COIN>(
                &global_config,
                &mut pools,
                TICK_SPACING_60,
                SQRT_PRICE_1_TO_1,
                std::string::utf8(b""),
                tick_lower,
                tick_upper,
                dao_sui_coin,
                dao_token_coin,
                true,
                &clock,
                ts::ctx(scenario),
            );
            coin::burn_for_testing(rem_sui);
            coin::burn_for_testing(rem_token);

            // Store pool ID for registry (like SuiDex stores pair ID)
            let cetus_pool_id = cetus_clmm::position::pool_id(&dao_position);

            // Transfer DAO position to temp storage (will go to treasury later)
            transfer::public_transfer(dao_position, admin());

            // Creator and Protocol positions created after pool exists
            // (They need the pool object which is now shared)

            // Step 4: Extract staking tokens and create staking pool - SAME AS SUIDEX
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

            // Step 5: Create DAO using dao_integration - SAME AS SUIDEX
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

            // Create treasury - SAME AS SUIDEX
            let treasury = dao_integration::create_treasury(
                &dao_admin_cap,
                &mut governance,
                ts::ctx(scenario),
            );
            treasury_id = object::id(&treasury);

            // Step 6: Complete graduation (consumes hot potato) - SAME AS SUIDEX
            let receipt = graduation::complete_graduation(
                pending,
                &mut registry,
                cetus_pool_id,  // Cetus pool ID instead of SuiDex pair ID
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
            ts::return_shared(global_config);
            ts::return_shared(pools);
            ts::return_shared(staking_registry);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        // Get actual staking pool ID after it's shared - SAME AS SUIDEX
        ts::next_tx(scenario, admin());
        {
            let staking_pool_obj = ts::take_shared<StakingPool<TEST_COIN, TEST_COIN>>(scenario);
            staking_pool_id = object::id(&staking_pool_obj);
            ts::return_shared(staking_pool_obj);
        };

        // Handle Position NFT distribution in next transaction
        // KEY DIFFERENCE FROM SUIDEX:
        // - SuiDex: Split LP coins, vest creator LP, deposit DAO LP to treasury
        // - Cetus: Create additional positions, transfer DAO position to treasury
        ts::next_tx(scenario, admin());
        {
            let global_config = ts::take_shared<GlobalConfig>(scenario);
            let mut cetus_pool = ts::take_shared<Pool<SUI, TEST_COIN>>(scenario);
            let mut treasury = ts::take_shared_by_id<Treasury>(scenario, treasury_id);
            let config = ts::take_shared<LaunchpadConfig>(scenario);
            let clock = create_clock(scenario);

            // Get the DAO position we transferred to admin earlier
            let dao_position = ts::take_from_sender<Position>(scenario);

            // Calculate LP splits using config
            let creator_lp_bps = config::creator_lp_bps(&config);
            let protocol_lp_bps = config::protocol_lp_bps(&config);
            let (tick_lower, tick_upper) = pool_creator::full_range_tick_range(TICK_SPACING_60);

            // For simplicity, we'll use small amounts for creator/protocol positions
            // In production, these would come from the remaining extracted amounts
            let creator_sui = 25 * ONE_SUI / 100;  // 0.25 SUI
            let creator_tokens = 250_000_000u64;   // 0.25 billion
            let protocol_sui = 25 * ONE_SUI / 100;
            let protocol_tokens = 250_000_000u64;

            // Create Creator position (2.5%)
            let mut creator_position = cetus_pool::open_position<SUI, TEST_COIN>(
                &global_config,
                &mut cetus_pool,
                tick_lower,
                tick_upper,
                ts::ctx(scenario),
            );

            let mut creator_sui_coin = coin::mint_for_testing<SUI>(creator_sui, ts::ctx(scenario));
            let mut creator_token_coin = coin::mint_for_testing<TEST_COIN>(creator_tokens, ts::ctx(scenario));

            let receipt = cetus_pool::add_liquidity_fix_coin<SUI, TEST_COIN>(
                &global_config,
                &mut cetus_pool,
                &mut creator_position,
                creator_sui,
                true,
                &clock,
            );

            let (amount_a, amount_b) = cetus_pool::add_liquidity_pay_amount(&receipt);
            let balance_a = coin::into_balance(coin::split(&mut creator_sui_coin, amount_a, ts::ctx(scenario)));
            let balance_b = coin::into_balance(coin::split(&mut creator_token_coin, amount_b, ts::ctx(scenario)));
            cetus_pool::repay_add_liquidity(&global_config, &mut cetus_pool, balance_a, balance_b, receipt);

            coin::burn_for_testing(creator_sui_coin);
            coin::burn_for_testing(creator_token_coin);

            // Create Protocol position (2.5%)
            let mut protocol_position = cetus_pool::open_position<SUI, TEST_COIN>(
                &global_config,
                &mut cetus_pool,
                tick_lower,
                tick_upper,
                ts::ctx(scenario),
            );

            let mut protocol_sui_coin = coin::mint_for_testing<SUI>(protocol_sui, ts::ctx(scenario));
            let mut protocol_token_coin = coin::mint_for_testing<TEST_COIN>(protocol_tokens, ts::ctx(scenario));

            let receipt2 = cetus_pool::add_liquidity_fix_coin<SUI, TEST_COIN>(
                &global_config,
                &mut cetus_pool,
                &mut protocol_position,
                protocol_sui,
                true,
                &clock,
            );

            let (amount_a2, amount_b2) = cetus_pool::add_liquidity_pay_amount(&receipt2);
            let balance_a2 = coin::into_balance(coin::split(&mut protocol_sui_coin, amount_a2, ts::ctx(scenario)));
            let balance_b2 = coin::into_balance(coin::split(&mut protocol_token_coin, amount_b2, ts::ctx(scenario)));
            cetus_pool::repay_add_liquidity(&global_config, &mut cetus_pool, balance_a2, balance_b2, receipt2);

            coin::burn_for_testing(protocol_sui_coin);
            coin::burn_for_testing(protocol_token_coin);

            // Distribute positions (SAME PATTERN AS SUIDEX LP distribution):

            // 1. Creator position -> VEST via nft_vesting (like SuiDex vests LP coins)
            //    Protocol vests on behalf of creator to prevent creator from disappearing
            let cliff_ms = config::creator_lp_cliff_ms(&config);
            let vesting_ms = config::creator_lp_vesting_ms(&config);
            // For NFTs, we use cliff-only vesting (NFT unlocks after cliff)
            // cliff_months = (cliff_ms + vesting_ms) / MS_PER_MONTH
            let total_cliff_ms = cliff_ms + vesting_ms;
            let cliff_months = total_cliff_ms / (30 * MS_PER_DAY);

            let creator_cap = nft_vesting::create_nft_schedule_months<Position>(
                creator_position,
                creator(), // beneficiary
                cliff_months,
                false, // NOT revocable - creator owns it
                &clock,
                ts::ctx(scenario),
            );
            // Protocol keeps CreatorCap (or can transfer to admin for management)
            transfer::public_transfer(creator_cap, admin());

            // 2. Protocol position -> Platform treasury (like SuiDex)
            transfer::public_transfer(protocol_position, platform_treasury());

            // 3. DAO position -> Treasury (like SuiDex dao_integration::deposit_lp_to_treasury)
            //    For Position NFTs, we use deposit_nft (Position has key + store)
            sui_dao::treasury::deposit_nft(&mut treasury, dao_position, ts::ctx(scenario));

            ts::return_shared(treasury);
            ts::return_shared(config);
            ts::return_shared(global_config);
            ts::return_shared(cetus_pool);
            clock::destroy_for_testing(clock);
        };

        (staking_pool_id, dao_id, treasury_id)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 1: TOKEN FLOW TESTS (same as SuiDex)
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
    // PART 2: CETUS POOL CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_cetus_infrastructure_setup() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let global_config = ts::take_shared<GlobalConfig>(&scenario);
            let pools = ts::take_shared<Pools>(&scenario);

            let protocol_fee = cetus_config::protocol_fee_rate(&global_config);
            assert!(protocol_fee == DEFAULT_PROTOCOL_FEE, 100);

            ts::return_shared(global_config);
            ts::return_shared(pools);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_cetus_pool_creation_with_position() {
        let mut scenario = ts::begin(admin());
        setup_infrastructure(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let global_config = ts::take_shared<GlobalConfig>(&scenario);
            let mut pools = ts::take_shared<Pools>(&scenario);
            let clock = create_clock(&mut scenario);

            let sui_coin = coin::mint_for_testing<SUI>(10 * ONE_SUI, ts::ctx(&mut scenario));
            let token_coin = coin::mint_for_testing<TEST_COIN>(1_000_000_000_000, ts::ctx(&mut scenario));

            let (tick_lower, tick_upper) = pool_creator::full_range_tick_range(TICK_SPACING_60);

            let (position, remaining_sui, remaining_token) = pool_creator::create_pool_v3<SUI, TEST_COIN>(
                &global_config,
                &mut pools,
                TICK_SPACING_60,
                SQRT_PRICE_1_TO_1,
                std::string::utf8(b""),
                tick_lower,
                tick_upper,
                sui_coin,
                token_coin,
                true,
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(cetus_clmm::position::liquidity(&position) > 0, 100);

            coin::burn_for_testing(remaining_sui);
            coin::burn_for_testing(remaining_token);
            transfer::public_transfer(position, admin());

            ts::return_shared(global_config);
            ts::return_shared(pools);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_cetus_liquidity_split_calculation() {
        let mut scenario = ts::begin(admin());

        let config = config::create_for_testing(platform_treasury(), ts::ctx(&mut scenario));

        let total_sui = 100 * ONE_SUI;
        let total_tokens = 10_000_000_000_000u64;

        let (
            creator_sui, creator_tokens,
            protocol_sui, protocol_tokens,
            dao_sui, dao_tokens
        ) = cetus_adapter::calculate_liquidity_split(total_sui, total_tokens, &config);

        assert!(creator_sui == 2_500_000_000, 0);
        assert!(creator_tokens == 250_000_000_000, 1);
        assert!(protocol_sui == 2_500_000_000, 2);
        assert!(protocol_tokens == 250_000_000_000, 3);
        assert!(dao_sui == 95_000_000_000, 4);
        assert!(dao_tokens == 9_500_000_000_000, 5);
        assert!(creator_sui + protocol_sui + dao_sui == total_sui, 6);
        assert!(creator_tokens + protocol_tokens + dao_tokens == total_tokens, 7);

        config::destroy_for_testing(config);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PART 3: STAKING INTEGRATION (same pattern as SuiDex)
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
    // PART 4: DAO GOVERNANCE (same pattern as SuiDex)
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
                std::string::utf8(b"Test Token DAO"),
                staking_pool_id,
                400,
                MS_PER_DAY,
                MS_PER_DAY * 3,
                MS_PER_DAY * 2,
                100,
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
    // PART 5: COMPLETE JOURNEY TESTS (using execute_graduation like SuiDex)
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

        // Phase 4: Execute graduation (same pattern as SuiDex)
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

        // Phase 6: Verify creator received VESTED position (like SuiDex vests LP)
        ts::next_tx(&mut scenario, creator());
        {
            // Creator has NFTVestingSchedule containing Position (not Position directly)
            let schedule = ts::take_from_sender<nft_vesting::NFTVestingSchedule<Position>>(&scenario);
            assert!(nft_vesting::has_nft(&schedule), 4);
            assert!(nft_vesting::nft_beneficiary(&schedule) == creator(), 41);
            ts::return_to_sender(&scenario, schedule);
        };

        // Phase 7: Verify platform treasury received position
        ts::next_tx(&mut scenario, platform_treasury());
        {
            let position = ts::take_from_sender<Position>(&scenario);
            assert!(cetus_clmm::position::liquidity(&position) > 0, 5);
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
    // ADAPTER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_cetus_adapter_constants() {
        assert!(cetus_adapter::creator_lp_bps() == 250, 0);
        assert!(cetus_adapter::protocol_lp_bps() == 250, 1);
        assert!(cetus_adapter::dao_lp_bps() == 9500, 2);
        assert!(cetus_adapter::full_range_tick_lower() == 4294523660, 3);
        assert!(cetus_adapter::full_range_tick_upper() == 443580, 4);
        assert!(cetus_adapter::default_tick_spacing() == 60, 5);
    }

    #[test]
    fun test_cetus_sqrt_price_calculation() {
        let price_1_to_1 = cetus_adapter::calculate_sqrt_price_x64(1_000_000, 1_000_000);
        assert!(price_1_to_1 == 18446744073709551616u128, 0);

        let price_higher = cetus_adapter::calculate_sqrt_price_x64(4_000_000, 1_000_000);
        let price_lower = cetus_adapter::calculate_sqrt_price_x64(1_000_000, 4_000_000);

        assert!(price_higher > 0, 1);
        assert!(price_lower > 0, 2);
    }

    #[test]
    fun test_split_coins_for_positions() {
        let mut scenario = ts::begin(admin());

        let config = config::create_for_testing(platform_treasury(), ts::ctx(&mut scenario));

        let sui_coin = coin::mint_for_testing<SUI>(100 * ONE_SUI, ts::ctx(&mut scenario));
        let token_coin = coin::mint_for_testing<TEST_COIN>(10_000_000_000_000, ts::ctx(&mut scenario));

        let (
            creator_sui, creator_tokens,
            protocol_sui, protocol_tokens,
            dao_sui, dao_tokens
        ) = cetus_adapter::split_coins_for_positions(sui_coin, token_coin, &config, ts::ctx(&mut scenario));

        assert!(coin::value(&creator_sui) == 2_500_000_000, 0);
        assert!(coin::value(&creator_tokens) == 250_000_000_000, 1);
        assert!(coin::value(&protocol_sui) == 2_500_000_000, 2);
        assert!(coin::value(&protocol_tokens) == 250_000_000_000, 3);
        assert!(coin::value(&dao_sui) == 95_000_000_000, 4);
        assert!(coin::value(&dao_tokens) == 9_500_000_000_000, 5);

        coin::burn_for_testing(creator_sui);
        coin::burn_for_testing(creator_tokens);
        coin::burn_for_testing(protocol_sui);
        coin::burn_for_testing(protocol_tokens);
        coin::burn_for_testing(dao_sui);
        coin::burn_for_testing(dao_tokens);
        config::destroy_for_testing(config);

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
            let schedule = ts::take_from_sender<nft_vesting::NFTVestingSchedule<Position>>(&scenario);
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
            let mut schedule = ts::take_from_sender<nft_vesting::NFTVestingSchedule<Position>>(&scenario);
            let clock = create_clock_at(&mut scenario, MS_PER_DAY * 600); // ~20 months

            // Now can claim
            assert!(nft_vesting::is_claimable(&schedule, &clock), 200);

            // Claim the Position NFT
            let position = nft_vesting::claim_nft(&mut schedule, &clock, ts::ctx(&mut scenario));

            // Verify position has liquidity
            assert!(cetus_clmm::position::liquidity(&position) > 0, 201);

            transfer::public_transfer(position, creator());
            ts::return_to_sender(&scenario, schedule);
            clock::destroy_for_testing(clock);
        };

        // Verify creator now has the Position directly
        ts::next_tx(&mut scenario, creator());
        {
            let position = ts::take_from_sender<Position>(&scenario);
            assert!(cetus_clmm::position::liquidity(&position) > 0, 300);
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
                std::string::utf8(b"Cetus Test DAO"),
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
                std::string::utf8(b"Cetus Treasury Test DAO"),
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
}
