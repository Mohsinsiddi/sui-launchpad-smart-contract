/// Tests for the registry module
/// Pool registration tests are covered in bonding_curve_tests
#[test_only]
module sui_launchpad::registry_tests {
    use sui::test_scenario;

    use sui_launchpad::registry::{Self, Registry};
    use sui_launchpad::test_utils;
    use sui_launchpad::test_coin::TEST_COIN;

    fun admin(): address { @0xA1 }
    fun creator(): address { @0xC1 }

    // ═══════════════════════════════════════════════════════════════════════
    // REGISTRY INITIAL STATE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_registry_creation() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let registry = scenario.take_shared<Registry>();

            // Verify initial state
            assert!(registry::total_tokens(&registry) == 0, 0);
            assert!(registry::total_graduated(&registry) == 0, 1);
            assert!(registry::pool_count(&registry) == 0, 2);

            test_scenario::return_shared(registry);
        };

        scenario.end();
    }

    #[test]
    fun test_registry_counters_initial() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let registry = scenario.take_shared<Registry>();

            assert!(registry::total_tokens(&registry) == 0, 0);
            assert!(registry::total_graduated(&registry) == 0, 1);
            assert!(registry::pool_count(&registry) == 0, 2);

            test_scenario::return_shared(registry);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LOOKUP TESTS (empty state)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_is_not_registered_initially() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let registry = scenario.take_shared<Registry>();

            assert!(!registry::is_registered<TEST_COIN>(&registry), 0);

            test_scenario::return_shared(registry);
        };

        scenario.end();
    }

    #[test]
    fun test_get_pools_by_creator_empty() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let registry = scenario.take_shared<Registry>();

            let pools = registry::get_pools_by_creator(&registry, creator());
            assert!(vector::length(&pools) == 0, 0);

            test_scenario::return_shared(registry);
        };

        scenario.end();
    }

    #[test]
    fun test_get_creator_pool_count_zero() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let registry = scenario.take_shared<Registry>();

            assert!(registry::get_creator_pool_count(&registry, creator()) == 0, 0);

            test_scenario::return_shared(registry);
        };

        scenario.end();
    }

    #[test]
    fun test_get_pool_by_type_not_found() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let registry = scenario.take_shared<Registry>();

            let pool_opt = registry::get_pool_by_type<TEST_COIN>(&registry);
            assert!(option::is_none(&pool_opt), 0);

            test_scenario::return_shared(registry);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PAGINATION TESTS (empty state)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_get_pools_empty() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let registry = scenario.take_shared<Registry>();

            let pools = registry::get_pools(&registry, 0, 10);
            assert!(vector::length(&pools) == 0, 0);

            test_scenario::return_shared(registry);
        };

        scenario.end();
    }

    #[test]
    fun test_get_pools_beyond_range() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let registry = scenario.take_shared<Registry>();

            let pools = registry::get_pools(&registry, 100, 10);
            assert!(vector::length(&pools) == 0, 0);

            test_scenario::return_shared(registry);
        };

        scenario.end();
    }
}
