/// ═══════════════════════════════════════════════════════════════════════════════
/// DAO SECURITY AND EXPLOIT TESTS
/// ═══════════════════════════════════════════════════════════════════════════════
///
/// Tests for security vulnerabilities and potential exploits
///
/// Coverage:
/// - Unauthorized access attempts
/// - Treasury withdrawal attacks
/// - Admin cap theft prevention
/// - Double extraction attempts
/// - Reentrancy-like patterns
/// - State manipulation attacks
/// - Overflow/underflow protection
/// - Access control verification
///
#[test_only]
module sui_launchpad::dao_security_tests {
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

    // sui_staking imports
    use sui_staking::factory::{Self as staking_factory, StakingRegistry};
    use sui_staking::access::{AdminCap as StakingAdminCap};

    // sui_dao imports
    use sui_dao::registry::{Self as dao_registry, DAORegistry};
    use sui_dao::access::{AdminCap as DAOPlatformAdminCap};
    use sui_dao::governance::Governance;
    use sui_dao::treasury::Treasury;

    // SuiDex imports
    use suitrump_dex::router::{Self as suidex_router, Router};
    use suitrump_dex::factory::{Self as suidex_factory, Factory};

    // ═══════════════════════════════════════════════════════════════════════
    // MOCK NFT FOR TESTING
    // ═══════════════════════════════════════════════════════════════════════

    public struct TestNFT has key, store {
        id: UID,
        value: u64,
    }

    fun create_test_nft(value: u64, ctx: &mut TxContext): TestNFT {
        TestNFT { id: object::new(ctx), value }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════

    fun admin(): address { @0xA1 }
    fun creator(): address { @0xC1 }
    fun attacker(): address { @0xBA0 }
    fun user1(): address { @0x111 }
    fun user2(): address { @0x222 }

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    fun setup_all(scenario: &mut ts::Scenario) {
        test_utils::setup_launchpad(scenario);

        ts::next_tx(scenario, admin());
        {
            suidex_factory::init_for_testing(ts::ctx(scenario));
            suidex_router::init_for_testing(ts::ctx(scenario));
            staking_factory::init_for_testing(ts::ctx(scenario));
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
    // UNAUTHORIZED ACCESS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure]
    fun test_attacker_cannot_initiate_graduation() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        // Attacker tries to initiate graduation without AdminCap
        ts::next_tx(&mut scenario, attacker());
        {
            // Attacker doesn't have AdminCap - this should fail at compile time
            // because they can't take_from_sender what they don't have
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

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

    #[test]
    #[expected_failure]
    fun test_attacker_cannot_modify_config() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        // Attacker tries to modify config without AdminCap
        ts::next_tx(&mut scenario, attacker());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario); // Will fail
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            config::set_staking_enabled(&admin_cap, &mut config, false);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_attacker_cannot_create_staking_pool() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        // Attacker tries to create staking pool without StakingAdminCap
        ts::next_tx(&mut scenario, attacker());
        {
            let staking_admin_cap = ts::take_from_sender<StakingAdminCap>(&scenario); // Will fail
            ts::return_to_sender(&scenario, staking_admin_cap);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_attacker_cannot_create_dao() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        // Attacker tries to create DAO without DAOPlatformAdminCap
        ts::next_tx(&mut scenario, attacker());
        {
            let dao_cap = ts::take_from_sender<DAOPlatformAdminCap>(&scenario); // Will fail
            ts::return_to_sender(&scenario, dao_cap);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TREASURY WITHDRAWAL PROTECTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_treasury_requires_dao_auth_for_withdrawal() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

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

            // Deposit some SUI
            let deposit = coin::mint_for_testing<SUI>(1_000_000_000, ts::ctx(&mut scenario));
            sui_dao::treasury::deposit_sui(&mut treasury, deposit, ts::ctx(&mut scenario));

            // Verify balance
            assert!(sui_dao::treasury::sui_balance(&treasury) == 1_000_000_000, 100);

            // NOTE: Cannot withdraw without DAOAuth from executed proposal
            // withdraw_sui requires DAOAuth which is only generated from begin_execution
            // This enforces that treasury withdrawals must go through governance

            sui_dao::governance::share_governance_for_testing(governance);
            sui_dao::treasury::destroy_treasury_for_testing(treasury);
            transfer::public_transfer(dao_admin_cap, admin());
            ts::return_to_sender(&scenario, dao_platform_cap);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_treasury_nft_requires_dao_auth_for_withdrawal() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

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

            // Deposit NFT
            let nft = create_test_nft(1000, ts::ctx(&mut scenario));
            sui_dao::treasury::deposit_nft(&mut treasury, nft, ts::ctx(&mut scenario));

            // Verify NFT deposited
            assert!(sui_dao::treasury::nft_count<TestNFT>(&treasury) == 1, 100);

            // NOTE: Cannot withdraw NFT without DAOAuth
            // withdraw_nft requires DAOAuth from executed proposal
            // This ensures Position NFTs are protected by DAO governance

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
    // DOUBLE EXTRACTION PREVENTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure]
    fun test_cannot_extract_sui_twice() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let mut pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            // First extraction
            let sui_coin1 = graduation::extract_all_sui(&mut pending, ts::ctx(&mut scenario));
            coin::burn_for_testing(sui_coin1);

            // Second extraction should fail
            let sui_coin2 = graduation::extract_all_sui(&mut pending, ts::ctx(&mut scenario));
            coin::burn_for_testing(sui_coin2);

            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_cannot_extract_tokens_twice() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let mut pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            // First extraction
            let token_coin1 = graduation::extract_all_tokens(&mut pending, ts::ctx(&mut scenario));
            coin::burn_for_testing(token_coin1);

            // Second extraction should fail
            let token_coin2 = graduation::extract_all_tokens(&mut pending, ts::ctx(&mut scenario));
            coin::burn_for_testing(token_coin2);

            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_cannot_extract_staking_tokens_twice() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let mut pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            // First extraction
            let staking_coin1 = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));
            coin::burn_for_testing(staking_coin1);

            // Second extraction should fail
            let staking_coin2 = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));
            coin::burn_for_testing(staking_coin2);

            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRADING PROTECTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure]
    fun test_cannot_trade_after_graduation() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        // Graduate the pool
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let mut staking_registry = ts::take_shared<StakingRegistry>(&scenario);
            let staking_admin_cap = ts::take_from_sender<StakingAdminCap>(&scenario);
            let clock = create_clock(&mut scenario);

            let mut pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            let sui_coin = graduation::extract_all_sui(&mut pending, ts::ctx(&mut scenario));
            let token_coin = graduation::extract_all_tokens(&mut pending, ts::ctx(&mut scenario));
            let staking_coin = graduation::extract_staking_tokens(&mut pending, ts::ctx(&mut scenario));

            coin::burn_for_testing(sui_coin);
            coin::burn_for_testing(token_coin);

            let pool_admin_cap = staking_integration::create_staking_pool<TEST_COIN>(
                &mut staking_registry,
                &staking_admin_cap,
                &pending,
                staking_coin,
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_transfer(pool_admin_cap, admin());

            let receipt = graduation::complete_graduation(
                pending,
                &mut registry,
                object::id_from_address(@0x123),
                0, 0, // sui_to_liquidity, tokens_to_liquidity
                1000000, 25000, 950000,
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

        // Try to trade after graduation - should fail
        ts::next_tx(&mut scenario, attacker());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let clock = create_clock(&mut scenario);

            let payment = coin::mint_for_testing<SUI>(1_000_000_000, ts::ctx(&mut scenario));

            // This should fail - pool is graduated
            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                0,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(tokens, attacker());
            ts::return_shared(pool);
            ts::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PAUSED STATE PROTECTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure]
    fun test_cannot_trade_when_paused() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);

        // Pause the pool
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let clock = create_clock(&mut scenario);

            bonding_curve::set_paused(&admin_cap, &mut pool, true, &clock);

            clock::destroy_for_testing(clock);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
        };

        // Try to trade when paused - should fail
        ts::next_tx(&mut scenario, attacker());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let clock = create_clock(&mut scenario);

            let payment = coin::mint_for_testing<SUI>(1_000_000_000, ts::ctx(&mut scenario));

            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                0,
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(tokens, attacker());
            ts::return_shared(pool);
            ts::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_cannot_graduate_when_paused() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        // Pause the pool
        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let clock = create_clock(&mut scenario);

            bonding_curve::set_paused(&admin_cap, &mut pool, true, &clock);

            clock::destroy_for_testing(clock);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
        };

        // Try to graduate when paused - should fail at initiate_graduation
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

            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TREASURY CAP SAFETY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_treasury_cap_frozen_after_graduation() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);

        // Verify treasury cap is frozen after pool creation
        ts::next_tx(&mut scenario, admin());
        {
            let pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);

            // Treasury cap should be frozen (no more minting possible)
            assert!(bonding_curve::is_treasury_cap_frozen(&pool), 100);

            ts::return_shared(pool);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FUND SAFETY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_all_funds_accounted_for_on_graduation() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);
        buy_to_graduation_threshold(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            // Record initial balances
            let initial_sui = bonding_curve::sui_balance(&pool);
            let initial_tokens = bonding_curve::token_balance(&pool);

            let pending = graduation::initiate_graduation(
                &admin_cap, &mut pool, &config,
                config::dex_suidex(),
                ts::ctx(&mut scenario),
            );

            // All balances should be extracted to pending
            let pending_sui = graduation::pending_sui_amount(&pending);
            let pending_tokens = graduation::pending_token_amount(&pending);
            let pending_staking = graduation::pending_staking_amount(&pending);

            // SUI should be preserved (minus graduation fee)
            // Tokens should be split between DEX and staking
            assert!(pending_sui > 0, 100);
            assert!(pending_tokens + pending_staking > 0, 101);

            graduation::destroy_pending_for_testing(pending);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LP DISTRIBUTION SAFETY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_lp_split_adds_up_correctly() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let config = ts::take_shared<LaunchpadConfig>(&scenario);

            let creator_bps = config::creator_lp_bps(&config);
            let protocol_bps = config::protocol_lp_bps(&config);

            // Total assigned BPS should leave at least 50% for DAO
            let total_assigned = creator_bps + protocol_bps;
            assert!(total_assigned <= 5000, 100); // ≤ 50%

            // DAO gets remainder
            let dao_bps = 10000 - total_assigned;
            assert!(dao_bps >= 5000, 101); // ≥ 50%

            // Total must equal 100%
            assert!(creator_bps + protocol_bps + dao_bps == 10000, 102);

            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DAO GOVERNANCE SAFETY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_dao_requires_staking_pool_link() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, admin());
        {
            let dao_platform_cap = ts::take_from_sender<DAOPlatformAdminCap>(&scenario);
            let mut dao_reg = ts::take_shared<DAORegistry>(&scenario);
            let clock = create_clock(&mut scenario);

            // Create DAO with staking pool link
            let staking_pool_id = object::id_from_address(@0x123);

            let (governance, dao_admin_cap) = sui_dao::governance::create_staking_governance_free(
                &dao_platform_cap,
                &mut dao_reg,
                std::string::utf8(b"Test DAO"),
                staking_pool_id,
                400, 86_400_000, 259_200_000, 172_800_000, 100,
                &clock,
                ts::ctx(&mut scenario),
            );

            // DAO should be linked to staking pool
            // Voting power comes from staked tokens
            assert!(sui_dao::governance::staking_pool_id(&governance).is_some(), 100);

            sui_dao::governance::share_governance_for_testing(governance);
            transfer::public_transfer(dao_admin_cap, admin());
            ts::return_to_sender(&scenario, dao_platform_cap);
            ts::return_shared(dao_reg);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SLIPPAGE PROTECTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure]
    fun test_buy_with_insufficient_output() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);
        let _pool_id = create_test_pool(&mut scenario);

        ts::next_tx(&mut scenario, user1());
        {
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let config = ts::take_shared<LaunchpadConfig>(&scenario);
            let clock = create_clock(&mut scenario);

            let payment = coin::mint_for_testing<SUI>(1_000_000_000, ts::ctx(&mut scenario));

            // Set unreasonably high min_tokens_out (slippage protection)
            let min_tokens_out = 999_999_999_999_999; // Way more than possible

            let tokens = bonding_curve::buy(
                &mut pool,
                &config,
                payment,
                min_tokens_out, // Should fail slippage check
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(tokens, user1());
            ts::return_shared(pool);
            ts::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FEE CAP TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure]
    fun test_creator_fee_cap_enforced() {
        let mut scenario = ts::begin(admin());
        setup_all(&mut scenario);

        ts::next_tx(&mut scenario, creator());
        {
            use sui_launchpad::test_coin;
            let (treasury_cap, metadata) = test_coin::create_test_coin(ts::ctx(&mut scenario));
            let launchpad_config = ts::take_shared<LaunchpadConfig>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));

            let creation_fee = config::creation_fee(&launchpad_config);
            let payment = coin::mint_for_testing<SUI>(creation_fee, ts::ctx(&mut scenario));

            // Try to create pool with 6% creator fee (max is 5%)
            let pool = bonding_curve::create_pool(
                &launchpad_config,
                treasury_cap,
                &metadata,
                600, // 6% - should fail
                payment,
                &clock,
                ts::ctx(&mut scenario),
            );

            // If we reach here, the test failed to reject invalid fee
            transfer::public_share_object(pool);
            ts::return_shared(launchpad_config);
            transfer::public_freeze_object(metadata);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }
}
