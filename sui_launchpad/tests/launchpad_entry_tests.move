#[test_only]
module sui_launchpad::launchpad_entry_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};
    use sui::coin;

    use sui_launchpad::operators::{Self, OperatorRegistry};
    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::{Self, AdminCap};
    use sui_launchpad::registry::{Self, Registry};
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::launchpad;
    use sui_launchpad::test_coin::{Self, TEST_COIN};

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    const ADMIN: address = @0xAD;
    const PAUSE_OP: address = @0x111;
    const FEE_OP: address = @0x222;
    const TREASURY_OP: address = @0x333;
    const CREATOR: address = @0xC1;
    const TREASURY: address = @0xFEE;

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    fun setup_full_launchpad(): Scenario {
        let mut scenario = ts::begin(ADMIN);

        // Create operator registry
        ts::next_tx(&mut scenario, ADMIN);
        {
            let registry = operators::create_registry_for_testing(ts::ctx(&mut scenario));
            transfer::public_share_object(registry);
        };

        // Create admin cap, config, and token registry
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = access::create_admin_cap_for_testing(ts::ctx(&mut scenario));
            transfer::public_transfer(admin_cap, ADMIN);

            let config = config::create_for_testing(TREASURY, ts::ctx(&mut scenario));
            transfer::public_share_object(config);

            let token_registry = registry::create_registry(ts::ctx(&mut scenario));
            transfer::public_share_object(token_registry);
        };

        scenario
    }

    fun setup_with_operators(): Scenario {
        let mut scenario = setup_full_launchpad();

        // Add operators
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut op_registry = ts::take_shared<OperatorRegistry>(&scenario);

            operators::add_operator(&mut op_registry, PAUSE_OP, operators::role_pause(), ts::ctx(&mut scenario));
            operators::add_operator(&mut op_registry, FEE_OP, operators::role_fee(), ts::ctx(&mut scenario));
            operators::add_operator(&mut op_registry, TREASURY_OP, operators::role_treasury(), ts::ctx(&mut scenario));

            ts::return_shared(op_registry);
        };

        scenario
    }

    fun create_clock(scenario: &mut Scenario): Clock {
        clock::create_for_testing(ts::ctx(scenario))
    }

    fun create_test_pool_internal(scenario: &mut Scenario): ID {
        let (treasury_cap, metadata) = test_coin::create_test_coin(ts::ctx(scenario));
        let config = ts::take_shared<LaunchpadConfig>(scenario);
        let mut token_registry = ts::take_shared<Registry>(scenario);
        let clock = create_clock(scenario);

        let creation_fee = config::creation_fee(&config);
        let payment = coin::mint_for_testing<sui::sui::SUI>(creation_fee, ts::ctx(scenario));

        let pool = bonding_curve::create_pool(
            &config,
            treasury_cap,
            &metadata,
            0, // no creator fee
            payment,
            &clock,
            ts::ctx(scenario),
        );

        // Register pool
        registry::register_pool(&mut token_registry, &pool, ts::ctx(scenario));

        let pool_id = object::id(&pool);

        transfer::public_share_object(pool);
        ts::return_shared(config);
        ts::return_shared(token_registry);
        transfer::public_freeze_object(metadata);
        clock::destroy_for_testing(clock);

        pool_id
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Operator Pause Platform
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_operator_pause_platform_success() {
        let mut scenario = setup_with_operators();

        ts::next_tx(&mut scenario, PAUSE_OP);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            launchpad::operator_pause_platform(
                &op_registry,
                &admin_cap,
                &mut config,
                ts::ctx(&mut scenario),
            );

            assert!(config::is_paused(&config), 0);

            ts::return_shared(op_registry);
            transfer::public_transfer(admin_cap, ADMIN);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_operator_unpause_platform_success() {
        let mut scenario = setup_with_operators();

        // First pause
        ts::next_tx(&mut scenario, PAUSE_OP);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            launchpad::operator_pause_platform(&op_registry, &admin_cap, &mut config, ts::ctx(&mut scenario));

            ts::return_shared(op_registry);
            transfer::public_transfer(admin_cap, ADMIN);
            ts::return_shared(config);
        };

        // Then unpause
        ts::next_tx(&mut scenario, PAUSE_OP);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            launchpad::operator_unpause_platform(&op_registry, &admin_cap, &mut config, ts::ctx(&mut scenario));

            assert!(!config::is_paused(&config), 0);

            ts::return_shared(op_registry);
            transfer::public_transfer(admin_cap, ADMIN);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 703)]
    fun test_operator_pause_platform_unauthorized() {
        let mut scenario = setup_with_operators();

        // Non-pause operator tries to pause
        ts::next_tx(&mut scenario, FEE_OP);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            launchpad::operator_pause_platform(&op_registry, &admin_cap, &mut config, ts::ctx(&mut scenario));

            ts::return_shared(op_registry);
            transfer::public_transfer(admin_cap, ADMIN);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Operator Pause Pool
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_operator_pause_pool_success() {
        let mut scenario = setup_with_operators();

        // Create a pool
        ts::next_tx(&mut scenario, CREATOR);
        {
            let _pool_id = create_test_pool_internal(&mut scenario);
        };

        // Pause pool
        ts::next_tx(&mut scenario, PAUSE_OP);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let clock = create_clock(&mut scenario);

            launchpad::operator_pause_pool(
                &op_registry,
                &admin_cap,
                &mut pool,
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(bonding_curve::is_paused(&pool), 0);

            ts::return_shared(op_registry);
            transfer::public_transfer(admin_cap, ADMIN);
            ts::return_shared(pool);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_operator_unpause_pool_success() {
        let mut scenario = setup_with_operators();

        // Create a pool
        ts::next_tx(&mut scenario, CREATOR);
        {
            let _pool_id = create_test_pool_internal(&mut scenario);
        };

        // Pause pool
        ts::next_tx(&mut scenario, PAUSE_OP);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let clock = create_clock(&mut scenario);

            launchpad::operator_pause_pool(&op_registry, &admin_cap, &mut pool, &clock, ts::ctx(&mut scenario));

            ts::return_shared(op_registry);
            transfer::public_transfer(admin_cap, ADMIN);
            ts::return_shared(pool);
            clock::destroy_for_testing(clock);
        };

        // Unpause pool
        ts::next_tx(&mut scenario, PAUSE_OP);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut pool = ts::take_shared<BondingPool<TEST_COIN>>(&scenario);
            let clock = create_clock(&mut scenario);

            launchpad::operator_unpause_pool(&op_registry, &admin_cap, &mut pool, &clock, ts::ctx(&mut scenario));

            assert!(!bonding_curve::is_paused(&pool), 0);

            ts::return_shared(op_registry);
            transfer::public_transfer(admin_cap, ADMIN);
            ts::return_shared(pool);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Operator Fee Functions
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_operator_set_creation_fee() {
        let mut scenario = setup_with_operators();

        ts::next_tx(&mut scenario, FEE_OP);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            let new_fee = 1_000_000_000; // 1 SUI
            launchpad::operator_set_creation_fee(
                &op_registry,
                &admin_cap,
                &mut config,
                new_fee,
                ts::ctx(&mut scenario),
            );

            assert!(config::creation_fee(&config) == new_fee, 0);

            ts::return_shared(op_registry);
            transfer::public_transfer(admin_cap, ADMIN);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_operator_set_trading_fee() {
        let mut scenario = setup_with_operators();

        ts::next_tx(&mut scenario, FEE_OP);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            let new_fee_bps = 150; // 1.5%
            launchpad::operator_set_trading_fee(
                &op_registry,
                &admin_cap,
                &mut config,
                new_fee_bps,
                ts::ctx(&mut scenario),
            );

            assert!(config::trading_fee_bps(&config) == new_fee_bps, 0);

            ts::return_shared(op_registry);
            transfer::public_transfer(admin_cap, ADMIN);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_operator_set_graduation_fee() {
        let mut scenario = setup_with_operators();

        ts::next_tx(&mut scenario, FEE_OP);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            let new_fee_bps = 200; // 2%
            launchpad::operator_set_graduation_fee(
                &op_registry,
                &admin_cap,
                &mut config,
                new_fee_bps,
                ts::ctx(&mut scenario),
            );

            assert!(config::graduation_fee_bps(&config) == new_fee_bps, 0);

            ts::return_shared(op_registry);
            transfer::public_transfer(admin_cap, ADMIN);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 702)] // ENotFeeOperator
    fun test_operator_set_fee_unauthorized() {
        let mut scenario = setup_with_operators();

        // Pause operator tries to set fees
        ts::next_tx(&mut scenario, PAUSE_OP);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            launchpad::operator_set_creation_fee(&op_registry, &admin_cap, &mut config, 1_000_000_000, ts::ctx(&mut scenario));

            ts::return_shared(op_registry);
            transfer::public_transfer(admin_cap, ADMIN);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Operator Treasury Functions
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_operator_set_treasury() {
        let mut scenario = setup_with_operators();

        ts::next_tx(&mut scenario, TREASURY_OP);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            let new_treasury: address = @0x1111;
            launchpad::operator_set_treasury(
                &op_registry,
                &admin_cap,
                &mut config,
                new_treasury,
                ts::ctx(&mut scenario),
            );

            assert!(config::treasury(&config) == new_treasury, 0);

            ts::return_shared(op_registry);
            transfer::public_transfer(admin_cap, ADMIN);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_operator_set_dao_treasury() {
        let mut scenario = setup_with_operators();

        ts::next_tx(&mut scenario, TREASURY_OP);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            let new_dao_treasury: address = @0xDA0;
            launchpad::operator_set_dao_treasury(
                &op_registry,
                &admin_cap,
                &mut config,
                new_dao_treasury,
                ts::ctx(&mut scenario),
            );

            assert!(config::dao_treasury(&config) == new_dao_treasury, 0);

            ts::return_shared(op_registry);
            transfer::public_transfer(admin_cap, ADMIN);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 704)] // ENotTreasuryOperator
    fun test_operator_set_treasury_unauthorized() {
        let mut scenario = setup_with_operators();

        // Fee operator tries to set treasury
        ts::next_tx(&mut scenario, FEE_OP);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
            let mut config = ts::take_shared<LaunchpadConfig>(&scenario);

            launchpad::operator_set_treasury(&op_registry, &admin_cap, &mut config, @0x1111, ts::ctx(&mut scenario));

            ts::return_shared(op_registry);
            transfer::public_transfer(admin_cap, ADMIN);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Operator Management Entry Points
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_add_operator_entry() {
        let mut scenario = setup_full_launchpad();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let new_op: address = @0x444;

            launchpad::add_operator(&mut op_registry, new_op, operators::role_pause(), ts::ctx(&mut scenario));

            assert!(operators::is_pause_operator(&op_registry, new_op), 0);

            ts::return_shared(op_registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_remove_operator_entry() {
        let mut scenario = setup_with_operators();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut op_registry = ts::take_shared<OperatorRegistry>(&scenario);

            launchpad::remove_operator(&mut op_registry, PAUSE_OP, operators::role_pause(), ts::ctx(&mut scenario));

            assert!(!operators::is_pause_operator(&op_registry, PAUSE_OP), 0);

            ts::return_shared(op_registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_add_super_admin_entry() {
        let mut scenario = setup_full_launchpad();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut op_registry = ts::take_shared<OperatorRegistry>(&scenario);
            let new_admin: address = @0xAD2;

            launchpad::add_super_admin(&mut op_registry, new_admin, ts::ctx(&mut scenario));

            assert!(operators::is_super_admin(&op_registry, new_admin), 0);

            ts::return_shared(op_registry);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 700)] // ENotSuperAdmin
    fun test_add_operator_not_super_admin() {
        let mut scenario = setup_with_operators();

        // Non-super admin tries to add operator
        ts::next_tx(&mut scenario, PAUSE_OP);
        {
            let mut op_registry = ts::take_shared<OperatorRegistry>(&scenario);

            launchpad::add_operator(&mut op_registry, @0x1111, operators::role_pause(), ts::ctx(&mut scenario));

            ts::return_shared(op_registry);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: View Functions
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_is_super_admin_view() {
        let mut scenario = setup_full_launchpad();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);

            assert!(launchpad::is_super_admin(&op_registry, ADMIN), 0);
            assert!(!launchpad::is_super_admin(&op_registry, CREATOR), 1);

            ts::return_shared(op_registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_has_role_view() {
        let mut scenario = setup_with_operators();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let op_registry = ts::take_shared<OperatorRegistry>(&scenario);

            assert!(launchpad::has_role(&op_registry, PAUSE_OP, operators::role_pause()), 0);
            assert!(launchpad::has_role(&op_registry, FEE_OP, operators::role_fee()), 1);
            assert!(launchpad::has_role(&op_registry, TREASURY_OP, operators::role_treasury()), 2);

            // Wrong roles
            assert!(!launchpad::has_role(&op_registry, PAUSE_OP, operators::role_fee()), 3);

            ts::return_shared(op_registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_total_tokens_view() {
        let mut scenario = setup_full_launchpad();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let token_registry = ts::take_shared<Registry>(&scenario);

            assert!(launchpad::total_tokens(&token_registry) == 0, 0);

            ts::return_shared(token_registry);
        };

        // Create a pool
        ts::next_tx(&mut scenario, CREATOR);
        {
            let _pool_id = create_test_pool_internal(&mut scenario);
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let token_registry = ts::take_shared<Registry>(&scenario);

            assert!(launchpad::total_tokens(&token_registry) == 1, 1);

            ts::return_shared(token_registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_total_graduated_view() {
        let mut scenario = setup_full_launchpad();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let token_registry = ts::take_shared<Registry>(&scenario);

            assert!(launchpad::total_graduated(&token_registry) == 0, 0);

            ts::return_shared(token_registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_is_registered_view() {
        let mut scenario = setup_full_launchpad();

        // Initially not registered
        ts::next_tx(&mut scenario, ADMIN);
        {
            let token_registry = ts::take_shared<Registry>(&scenario);

            assert!(!launchpad::is_registered<TEST_COIN>(&token_registry), 0);

            ts::return_shared(token_registry);
        };

        // Create a pool
        ts::next_tx(&mut scenario, CREATOR);
        {
            let _pool_id = create_test_pool_internal(&mut scenario);
        };

        // Now should be registered
        ts::next_tx(&mut scenario, ADMIN);
        {
            let token_registry = ts::take_shared<Registry>(&scenario);

            assert!(launchpad::is_registered<TEST_COIN>(&token_registry), 1);

            ts::return_shared(token_registry);
        };

        ts::end(scenario);
    }
}
