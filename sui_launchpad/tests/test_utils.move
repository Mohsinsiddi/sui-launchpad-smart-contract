/// Test utilities for testing the launchpad
#[test_only]
module sui_launchpad::test_utils {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::test_scenario::Scenario;
    use sui::clock::{Self, Clock};

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access;
    use sui_launchpad::registry;
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::test_coin::{Self, TEST_COIN};

    // ═══════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════

    public fun admin(): address { @0xA1 }
    public fun creator(): address { @0xC1 }
    public fun buyer(): address { @0xB1 }
    public fun seller(): address { @0xD1 }
    public fun treasury(): address { @0xE1 }
    public fun operator(): address { @0xF1 }

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Setup basic launchpad infrastructure: AdminCap, Config, Registry
    public fun setup_launchpad(scenario: &mut Scenario) {
        scenario.next_tx(admin());
        {
            let ctx = scenario.ctx();

            // Create admin cap
            let admin_cap = access::create_admin_cap(ctx);
            transfer::public_transfer(admin_cap, admin());

            // Create config
            let config = config::create_config(treasury(), ctx);
            transfer::public_share_object(config);

            // Create registry
            let registry = registry::create_registry(ctx);
            transfer::public_share_object(registry);
        };
    }

    /// Create a clock for testing
    public fun create_clock(scenario: &mut Scenario): Clock {
        let ctx = scenario.ctx();
        clock::create_for_testing(ctx)
    }

    /// Create SUI coins for testing
    public fun mint_sui(amount: u64, scenario: &mut Scenario): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, scenario.ctx())
    }

    /// Create a test pool with the test coin
    /// Returns the pool ID for reference
    public fun create_test_pool(
        scenario: &mut Scenario,
        creator_fee_bps: u64,
    ): ID {
        let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());

        // Get config
        let config = scenario.take_shared<LaunchpadConfig>();

        // Create clock
        let clock = create_clock(scenario);

        // Get creation fee from config
        let creation_fee = config::creation_fee(&config);
        let payment = mint_sui(creation_fee, scenario);

        // Create pool
        let pool = bonding_curve::create_pool(
            &config,
            treasury_cap,
            &metadata,
            creator_fee_bps,
            payment,
            &clock,
            scenario.ctx(),
        );

        let pool_id = object::id(&pool);

        // Share the pool
        transfer::public_share_object(pool);

        // Cleanup
        sui::test_scenario::return_shared(config);
        transfer::public_freeze_object(metadata);
        clock::destroy_for_testing(clock);

        pool_id
    }

    /// Setup launchpad and create a pool in one call
    /// Useful for tests that need a pool registered in the registry
    public fun setup_launchpad_with_pool(
        scenario: &mut Scenario,
        pool_creator: address,
    ): ID {
        use sui_launchpad::registry::Registry;

        // First setup launchpad
        setup_launchpad(scenario);

        // Create pool as the specified creator
        scenario.next_tx(pool_creator);

        let (treasury_cap, metadata) = test_coin::create_test_coin(scenario.ctx());
        let config = scenario.take_shared<LaunchpadConfig>();
        let mut token_registry = scenario.take_shared<Registry>();
        let clock = create_clock(scenario);

        let creation_fee = config::creation_fee(&config);
        let payment = mint_sui(creation_fee, scenario);

        let pool = bonding_curve::create_pool(
            &config,
            treasury_cap,
            &metadata,
            0, // no creator fee
            payment,
            &clock,
            scenario.ctx(),
        );

        // Register in registry
        registry::register_pool(&mut token_registry, &pool, scenario.ctx());

        let pool_id = object::id(&pool);
        transfer::public_share_object(pool);

        sui::test_scenario::return_shared(config);
        sui::test_scenario::return_shared(token_registry);
        transfer::public_freeze_object(metadata);
        clock::destroy_for_testing(clock);

        pool_id
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ASSERTION HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Assert two u64 values are equal
    public fun assert_eq(actual: u64, expected: u64, error_code: u64) {
        assert!(actual == expected, error_code);
    }

    /// Assert actual is greater than expected
    public fun assert_gt(actual: u64, expected: u64, error_code: u64) {
        assert!(actual > expected, error_code);
    }

    /// Assert actual is greater than or equal to expected
    public fun assert_gte(actual: u64, expected: u64, error_code: u64) {
        assert!(actual >= expected, error_code);
    }

    /// Assert actual is less than expected
    public fun assert_lt(actual: u64, expected: u64, error_code: u64) {
        assert!(actual < expected, error_code);
    }

    /// Assert a boolean is true
    public fun assert_true(condition: bool, error_code: u64) {
        assert!(condition, error_code);
    }

    /// Assert a boolean is false
    public fun assert_false(condition: bool, error_code: u64) {
        assert!(!condition, error_code);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Default creation fee (0.5 SUI)
    public fun default_creation_fee(): u64 { 500_000_000 }

    /// Large SUI amount for testing (1000 SUI)
    public fun large_sui_amount(): u64 { 1_000_000_000_000 }

    /// Small SUI amount for testing (1 SUI)
    public fun small_sui_amount(): u64 { 1_000_000_000 }

    /// Minimum SUI amount (0.001 SUI)
    public fun min_sui_amount(): u64 { 1_000_000 }
}
