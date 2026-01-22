/// Comprehensive tests for the staking module
#[test_only]
module sui_staking::staking_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::balance;

    use sui_staking::pool::{Self, StakingPool};
    use sui_staking::position::{Self, StakingPosition};
    use sui_staking::access::PoolAdminCap;
    use sui_staking::factory::{Self, StakingRegistry};

    // Test tokens
    public struct STAKE has drop {}
    public struct REWARD has drop {}

    // Test addresses
    const ADMIN: address = @0xAD;
    const ALICE: address = @0xA;
    const BOB: address = @0xB;

    // Time constants
    const MS_PER_DAY: u64 = 86_400_000;
    const MS_PER_WEEK: u64 = 604_800_000;

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    fun setup_test(): Scenario {
        ts::begin(ADMIN)
    }

    fun create_clock(scenario: &mut Scenario, timestamp_ms: u64): Clock {
        ts::next_tx(scenario, ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(scenario));
        clock::set_for_testing(&mut clock, timestamp_ms);
        clock
    }

    fun mint_stake_coins(scenario: &mut Scenario, amount: u64): Coin<STAKE> {
        coin::from_balance(
            balance::create_for_testing<STAKE>(amount),
            ts::ctx(scenario),
        )
    }

    fun mint_reward_coins(scenario: &mut Scenario, amount: u64): Coin<REWARD> {
        coin::from_balance(
            balance::create_for_testing<REWARD>(amount),
            ts::ctx(scenario),
        )
    }

    fun mint_sui_coins(scenario: &mut Scenario, amount: u64): Coin<sui::sui::SUI> {
        coin::from_balance(
            balance::create_for_testing<sui::sui::SUI>(amount),
            ts::ctx(scenario),
        )
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POOL CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_pool_direct() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000); // 100B rewards
            let start_time = 1000;
            let duration = MS_PER_WEEK; // 7 days

            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                start_time,
                duration,
                MS_PER_DAY, // 1 day min stake
                500, // 5% early fee
                0, // 0% stake fee
                0, // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );

            // Verify pool state
            assert!(pool::total_staked(&pool) == 0, 0);
            assert!(pool::reward_balance(&pool) == 100_000_000_000, 1);
            assert!(pool::is_paused(&pool) == false, 2);

            // Clean up
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_create_pool_via_factory() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        // Initialize factory
        ts::next_tx(&mut scenario, ADMIN);
        {
            factory::init_for_testing(ts::ctx(&mut scenario));
        };

        // Create pool via factory
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<StakingRegistry>(&scenario);

            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let setup_fee = mint_sui_coins(&mut scenario, 1_000_000_000); // 1 SUI

            let admin_cap = factory::create_pool<STAKE, REWARD>(
                &mut registry,
                reward_coins,
                setup_fee,
                1000, // start time
                MS_PER_WEEK, // duration
                MS_PER_DAY, // min stake
                500, // 5% early fee
                0, // 0% stake fee
                0, // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(factory::total_pools(&registry) == 1, 0);
            assert!(factory::collected_fees(&registry) == 1_000_000_000, 1);

            ts::return_shared(registry);
            transfer::public_transfer(admin_cap, ALICE);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_stake_and_receive_position() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000, // start time
                MS_PER_WEEK,
                MS_PER_DAY,
                500,
                0, // 0% stake fee
                0, // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Alice stakes
        clock::set_for_testing(&mut clock, 1000); // Move to start time
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000);

            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));

            assert!(position::staked_amount(&position) == 10_000_000, 0);
            assert!(pool::total_staked(&pool) == 10_000_000, 1);

            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_claim_rewards() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create pool with 100B rewards over 7 days
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                MS_PER_DAY,
                500,
                0, // 0% stake fee
                0, // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Alice stakes at start
        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        // Wait 1 day and claim
        clock::set_for_testing(&mut clock, 1000 + MS_PER_DAY);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let mut position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);

            // Check pending rewards before claim
            let pending = pool::pending_rewards(&pool, &position, 1000 + MS_PER_DAY);
            assert!(pending > 0, 0);

            let reward_coin = pool::claim_rewards(
                &mut pool,
                &mut position,
                &clock,
                ts::ctx(&mut scenario),
            );

            // Should have received rewards
            assert!(coin::value(&reward_coin) > 0, 1);

            ts::return_shared(pool);
            ts::return_to_sender(&scenario, position);
            coin::burn_for_testing(reward_coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_unstake_full() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                MS_PER_DAY,
                500, // 5% early fee
                0, // 0% stake fee
                0, // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Alice stakes
        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        // Wait past min stake duration (1 day) and unstake
        clock::set_for_testing(&mut clock, 1000 + MS_PER_DAY);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);

            let (stake_coin, reward_coin) = pool::unstake(
                &mut pool,
                position,
                &clock,
                ts::ctx(&mut scenario),
            );

            // Should get full stake back (no early fee after min duration)
            assert!(coin::value(&stake_coin) == 10_000_000, 0);
            // Should have some rewards
            assert!(coin::value(&reward_coin) > 0, 1);
            // Pool should be empty
            assert!(pool::total_staked(&pool) == 0, 2);

            ts::return_shared(pool);
            coin::burn_for_testing(stake_coin);
            coin::burn_for_testing(reward_coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_early_unstake_fee() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create pool with 5% early fee and 1 day min stake
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                MS_PER_DAY, // 1 day min
                500, // 5% early fee
                0, // 0% stake fee
                0, // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Alice stakes
        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        // Unstake after 1 hour (before min stake duration)
        clock::set_for_testing(&mut clock, 1000 + 3_600_000); // 1 hour
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);

            let (stake_coin, reward_coin) = pool::unstake(
                &mut pool,
                position,
                &clock,
                ts::ctx(&mut scenario),
            );

            // Should get 95% of stake (5% fee taken)
            assert!(coin::value(&stake_coin) == 9_500_000, 0);
            // Pool should have collected fees
            assert!(pool::collected_fees(&pool) == 500_000, 1);

            ts::return_shared(pool);
            coin::burn_for_testing(stake_coin);
            coin::burn_for_testing(reward_coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MULTI-USER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_multiple_stakers_proportional_rewards() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                0, // no min stake
                0, // no early fee
                0, // 0% stake fee
                0, // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Alice stakes 10M at start
        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        // Bob stakes 10M at start (same amount = 50/50 split)
        ts::next_tx(&mut scenario, BOB);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));

            assert!(pool::total_staked(&pool) == 20_000_000, 0);

            ts::return_shared(pool);
            transfer::public_transfer(position, BOB);
        };

        // Wait 1 day
        clock::set_for_testing(&mut clock, 1000 + MS_PER_DAY);

        // Alice claims
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let mut position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);

            let alice_pending = pool::pending_rewards(&pool, &position, 1000 + MS_PER_DAY);

            let reward_coin = pool::claim_rewards(
                &mut pool,
                &mut position,
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(pool);
            ts::return_to_sender(&scenario, position);
            coin::burn_for_testing(reward_coin);

            // Bob should have similar pending rewards
            ts::next_tx(&mut scenario, BOB);
            let pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let bob_position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);

            let bob_pending = pool::pending_rewards(&pool, &bob_position, 1000 + MS_PER_DAY);

            // Alice and Bob should have approximately equal rewards (both staked same amount from start)
            // Allow 1% difference due to rounding
            let diff = if (alice_pending > bob_pending) {
                alice_pending - bob_pending
            } else {
                bob_pending - alice_pending
            };
            assert!(diff * 100 < alice_pending, 1); // diff < 1%

            ts::return_shared(pool);
            ts::return_to_sender(&scenario, bob_position);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_pool_admin_functions() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                MS_PER_DAY,
                500,
                0, // 0% stake fee
                0, // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Test pause
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let admin_cap = ts::take_from_sender<PoolAdminCap>(&scenario);

            pool::set_paused(&mut pool, &admin_cap, true, ts::ctx(&mut scenario));
            assert!(pool::is_paused(&pool), 0);

            pool::set_paused(&mut pool, &admin_cap, false, ts::ctx(&mut scenario));
            assert!(!pool::is_paused(&pool), 1);

            ts::return_shared(pool);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Test update config
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let admin_cap = ts::take_from_sender<PoolAdminCap>(&scenario);

            pool::update_config(
                &mut pool,
                &admin_cap,
                MS_PER_DAY * 2, // 2 day min stake
                300, // 3% early fee
                100, // 1% stake fee
                200, // 2% unstake fee
                ts::ctx(&mut scenario),
            );

            let config = pool::config(&pool);
            assert!(pool::config_min_stake_duration_ms(config) == MS_PER_DAY * 2, 0);
            assert!(pool::config_early_unstake_fee_bps(config) == 300, 1);
            assert!(pool::config_stake_fee_bps(config) == 100, 2);
            assert!(pool::config_unstake_fee_bps(config) == 200, 3);

            ts::return_shared(pool);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Test add rewards
        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let admin_cap = ts::take_from_sender<PoolAdminCap>(&scenario);
            let more_rewards = mint_reward_coins(&mut scenario, 50_000_000_000);

            let initial_balance = pool::reward_balance(&pool);
            pool::add_rewards(&mut pool, &admin_cap, more_rewards, &clock, ts::ctx(&mut scenario));

            assert!(pool::reward_balance(&pool) == initial_balance + 50_000_000_000, 0);

            ts::return_shared(pool);
            ts::return_to_sender(&scenario, admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_withdraw_collected_fees() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create pool with early fee
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                MS_PER_DAY,
                500, // 5% early fee
                0, // 0% stake fee
                0, // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Alice stakes and early unstakes
        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        clock::set_for_testing(&mut clock, 1000 + 3_600_000); // 1 hour later
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);
            let (stake_coin, reward_coin) = pool::unstake(&mut pool, position, &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
            coin::burn_for_testing(stake_coin);
            coin::burn_for_testing(reward_coin);
        };

        // Admin withdraws fees
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let admin_cap = ts::take_from_sender<PoolAdminCap>(&scenario);

            assert!(pool::collected_fees(&pool) == 500_000, 0);

            let fee_coin = pool::withdraw_fees(&mut pool, &admin_cap, ts::ctx(&mut scenario));
            assert!(coin::value(&fee_coin) == 500_000, 1);
            assert!(pool::collected_fees(&pool) == 0, 2);

            ts::return_shared(pool);
            ts::return_to_sender(&scenario, admin_cap);
            coin::burn_for_testing(fee_coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure(abort_code = 100)] // EPoolPaused
    fun test_cannot_stake_when_paused() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create and pause pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                MS_PER_DAY,
                500,
                0, // 0% stake fee
                0, // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let admin_cap = ts::take_from_sender<PoolAdminCap>(&scenario);
            pool::set_paused(&mut pool, &admin_cap, true, ts::ctx(&mut scenario));
            ts::return_shared(pool);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Try to stake - should fail
        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));

            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 102)] // EPoolNotStarted
    fun test_cannot_stake_before_start() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        // Create pool starting at t=1000
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000, // starts at t=1000
                MS_PER_WEEK,
                MS_PER_DAY,
                500,
                0, // 0% stake fee
                0, // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Try to stake at t=500 (before start) - should fail
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));

            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 201)] // EAmountTooSmall
    fun test_cannot_stake_dust() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                MS_PER_DAY,
                500,
                0, // 0% stake fee
                0, // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 100); // Too small
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));

            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PARTIAL UNSTAKE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_partial_unstake() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                MS_PER_DAY,
                500,
                0, // 0% stake fee
                0, // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Alice stakes 10M
        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        // Wait past min stake and partial unstake
        clock::set_for_testing(&mut clock, 1000 + MS_PER_DAY);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let mut position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);

            let (stake_coin, reward_coin) = pool::unstake_partial(
                &mut pool,
                &mut position,
                5_000_000, // unstake half
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(coin::value(&stake_coin) == 5_000_000, 0);
            assert!(position::staked_amount(&position) == 5_000_000, 1);
            assert!(pool::total_staked(&pool) == 5_000_000, 2);

            ts::return_shared(pool);
            ts::return_to_sender(&scenario, position);
            coin::burn_for_testing(stake_coin);
            coin::burn_for_testing(reward_coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADD STAKE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_add_stake_to_existing_position() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                MS_PER_DAY,
                500,
                0, // 0% stake fee
                0, // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Alice stakes 5M
        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 5_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        // Alice adds 5M more
        clock::set_for_testing(&mut clock, 1000 + 3_600_000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let mut position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);
            let more_stake = mint_stake_coins(&mut scenario, 5_000_000);

            let reward_coin = pool::add_stake(
                &mut pool,
                &mut position,
                more_stake,
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(position::staked_amount(&position) == 10_000_000, 0);
            assert!(pool::total_staked(&pool) == 10_000_000, 1);

            ts::return_shared(pool);
            ts::return_to_sender(&scenario, position);
            coin::burn_for_testing(reward_coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STAKE/UNSTAKE FEE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_stake_fee_collected_on_deposit() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create pool with 2% stake fee
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                0, // no min stake
                0, // no early fee
                200, // 2% stake fee
                0, // no unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Alice stakes 10M, should get 9.8M staked (2% fee = 200k)
        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));

            // Position should have 9.8M (10M - 2% fee)
            assert!(position::staked_amount(&position) == 9_800_000, 0);
            // Pool should have 9.8M staked
            assert!(pool::total_staked(&pool) == 9_800_000, 1);
            // Pool should have collected 200k fees
            assert!(pool::collected_fees(&pool) == 200_000, 2);

            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_unstake_fee_collected_on_withdrawal() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create pool with 3% unstake fee, no stake fee
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                0, // no min stake
                0, // no early fee
                0, // no stake fee
                300, // 3% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Alice stakes 10M
        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        // Alice unstakes, should pay 3% unstake fee
        clock::set_for_testing(&mut clock, 1000 + MS_PER_DAY);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);

            let (stake_coin, reward_coin) = pool::unstake(
                &mut pool,
                position,
                &clock,
                ts::ctx(&mut scenario),
            );

            // Should get 97% back (10M - 3% = 9.7M)
            assert!(coin::value(&stake_coin) == 9_700_000, 0);
            // Pool should have collected 300k fees
            assert!(pool::collected_fees(&pool) == 300_000, 1);

            ts::return_shared(pool);
            coin::burn_for_testing(stake_coin);
            coin::burn_for_testing(reward_coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_combined_early_and_unstake_fee() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create pool with 5% early fee AND 2% unstake fee
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                MS_PER_DAY, // 1 day min stake
                500, // 5% early fee
                0, // no stake fee
                200, // 2% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Alice stakes 10M
        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        // Alice unstakes early (before 1 day), pays both fees
        clock::set_for_testing(&mut clock, 1000 + 3_600_000); // 1 hour later
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);

            let (stake_coin, reward_coin) = pool::unstake(
                &mut pool,
                position,
                &clock,
                ts::ctx(&mut scenario),
            );

            // Total fee = 5% early + 2% unstake = 7%
            // 10M - 7% = 9.3M
            assert!(coin::value(&stake_coin) == 9_300_000, 0);
            // Pool should have collected 700k total fees
            assert!(pool::collected_fees(&pool) == 700_000, 1);

            ts::return_shared(pool);
            coin::burn_for_testing(stake_coin);
            coin::burn_for_testing(reward_coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_stake_fee_on_add_stake() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create pool with 2% stake fee
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                0, // no min stake
                0, // no early fee
                200, // 2% stake fee
                0, // no unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Alice stakes 5M first
        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 5_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));

            // Position should have 4.9M (5M - 2%)
            assert!(position::staked_amount(&position) == 4_900_000, 0);
            // Fees collected = 100k
            assert!(pool::collected_fees(&pool) == 100_000, 1);

            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        // Alice adds 5M more
        clock::set_for_testing(&mut clock, 1000 + 3_600_000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let mut position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);
            let more_stake = mint_stake_coins(&mut scenario, 5_000_000);

            let reward_coin = pool::add_stake(
                &mut pool,
                &mut position,
                more_stake,
                &clock,
                ts::ctx(&mut scenario),
            );

            // Position should have 4.9M + 4.9M = 9.8M
            assert!(position::staked_amount(&position) == 9_800_000, 2);
            // Total fees = 100k + 100k = 200k
            assert!(pool::collected_fees(&pool) == 200_000, 3);

            ts::return_shared(pool);
            ts::return_to_sender(&scenario, position);
            coin::burn_for_testing(reward_coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_max_fees_validation() {
        let mut scenario = setup_test();
        let clock = create_clock(&mut scenario, 0);

        // Create pool with max fees (5% stake, 5% unstake)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                0,
                0,
                500, // 5% max stake fee
                500, // 5% max unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );

            let config = pool::config(&pool);
            assert!(pool::config_stake_fee_bps(config) == 500, 0);
            assert!(pool::config_unstake_fee_bps(config) == 500, 1);

            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_partial_unstake_with_fees() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 0);

        // Create pool with 2% unstake fee
        ts::next_tx(&mut scenario, ADMIN);
        {
            let reward_coins = mint_reward_coins(&mut scenario, 100_000_000_000);
            let (pool, admin_cap) = pool::create<STAKE, REWARD>(
                reward_coins,
                1000,
                MS_PER_WEEK,
                0,
                0, // no early fee
                0, // no stake fee
                200, // 2% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Alice stakes 10M
        clock::set_for_testing(&mut clock, 1000);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        // Partial unstake 5M, pays 2% on 5M = 100k
        clock::set_for_testing(&mut clock, 1000 + MS_PER_DAY);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
            let mut position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);

            let (stake_coin, reward_coin) = pool::unstake_partial(
                &mut pool,
                &mut position,
                5_000_000,
                &clock,
                ts::ctx(&mut scenario),
            );

            // Should get 4.9M (5M - 2%)
            assert!(coin::value(&stake_coin) == 4_900_000, 0);
            // Remaining in position
            assert!(position::staked_amount(&position) == 5_000_000, 1);
            // Fees collected
            assert!(pool::collected_fees(&pool) == 100_000, 2);

            ts::return_shared(pool);
            ts::return_to_sender(&scenario, position);
            coin::burn_for_testing(stake_coin);
            coin::burn_for_testing(reward_coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GOVERNANCE-ONLY POOL TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_governance_pool() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        // Create governance-only pool (no rewards)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = pool::create_governance_pool<STAKE>(
                MS_PER_DAY,  // min stake duration
                500,         // 5% early unstake fee
                0,           // 0% stake fee
                0,           // 0% unstake fee
                &clock,
                ts::ctx(&mut scenario),
            );

            // Verify it's a governance-only pool
            assert!(pool::is_governance_only(&pool), 0);
            assert!(pool::reward_rate(&pool) == 0, 1);
            assert!(pool::reward_balance(&pool) == 0, 2);
            assert!(pool::config_governance_only(pool::config(&pool)), 3);

            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_governance_pool_stake_and_unstake() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        // Create governance-only pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = pool::create_governance_pool<STAKE>(
                MS_PER_DAY,
                500,
                0,
                0,
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Stake tokens
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, STAKE>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000_000);

            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));

            // Verify position
            assert!(position::staked_amount(&position) == 10_000_000_000, 0);
            assert!(pool::total_staked(&pool) == 10_000_000_000, 1);

            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        // Advance time past min stake duration
        clock::set_for_testing(&mut clock, 1000 + MS_PER_DAY + 1);

        // Unstake
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, STAKE>>(&scenario);
            let position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);

            let (stake_coin, reward_coin) = pool::unstake(&mut pool, position, &clock, ts::ctx(&mut scenario));

            // Full stake returned (no early fee since min duration passed)
            assert!(coin::value(&stake_coin) == 10_000_000_000, 0);
            // No rewards for governance-only pool
            assert!(coin::value(&reward_coin) == 0, 1);
            assert!(pool::total_staked(&pool) == 0, 2);

            ts::return_shared(pool);
            coin::burn_for_testing(stake_coin);
            coin::burn_for_testing(reward_coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_governance_pool_no_end_time() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        // Create governance-only pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = pool::create_governance_pool<STAKE>(
                0, // No min stake duration
                0, // No early unstake fee
                0,
                0,
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Advance time far into the future (1 year)
        clock::set_for_testing(&mut clock, 1000 + (MS_PER_DAY * 365));

        // Should still be able to stake (governance pools have no end time)
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, STAKE>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 5_000_000_000);

            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));

            // Stake succeeded even after "1 year"
            assert!(position::staked_amount(&position) == 5_000_000_000, 0);

            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_governance_pool_early_unstake_fee() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        // Create governance pool with early unstake fee
        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = pool::create_governance_pool<STAKE>(
                MS_PER_WEEK,  // 7 day min stake
                1000,         // 10% early unstake fee
                0,
                0,
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Stake tokens
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, STAKE>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        // Unstake early (only 1 day passed)
        clock::set_for_testing(&mut clock, 1000 + MS_PER_DAY);
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, STAKE>>(&scenario);
            let position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);

            let (stake_coin, reward_coin) = pool::unstake(&mut pool, position, &clock, ts::ctx(&mut scenario));

            // 10% early fee applied: 10B - 1B = 9B
            assert!(coin::value(&stake_coin) == 9_000_000_000, 0);
            // 1B collected as fees
            assert!(pool::collected_fees(&pool) == 1_000_000_000, 1);
            // No rewards
            assert!(coin::value(&reward_coin) == 0, 2);

            ts::return_shared(pool);
            coin::burn_for_testing(stake_coin);
            coin::burn_for_testing(reward_coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_governance_pool_voting_power() {
        let mut scenario = setup_test();
        let mut clock = create_clock(&mut scenario, 1000);

        // Create governance pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let (pool, admin_cap) = pool::create_governance_pool<STAKE>(
                0, 0, 0, 0,
                &clock,
                ts::ctx(&mut scenario),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Alice stakes 10B
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, STAKE>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 10_000_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));

            // Voting power = staked amount
            assert!(position::staked_amount(&position) == 10_000_000_000, 0);

            ts::return_shared(pool);
            transfer::public_transfer(position, ALICE);
        };

        // Bob stakes 5B
        ts::next_tx(&mut scenario, BOB);
        {
            let mut pool = ts::take_shared<StakingPool<STAKE, STAKE>>(&scenario);
            let stake_coins = mint_stake_coins(&mut scenario, 5_000_000_000);
            let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));

            // Bob's voting power
            assert!(position::staked_amount(&position) == 5_000_000_000, 0);
            // Total staked (can be used for quorum calculations)
            assert!(pool::total_staked(&pool) == 15_000_000_000, 1);

            ts::return_shared(pool);
            transfer::public_transfer(position, BOB);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}
