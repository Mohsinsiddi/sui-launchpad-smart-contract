/// Comprehensive tests for the config module
#[test_only]
module sui_launchpad::config_tests {
    use sui::test_scenario::{Self, Scenario};

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::{Self, AdminCap};

    // ═══════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════

    fun admin(): address { @0xA1 }
    fun treasury(): address { @0xE1 }
    fun new_treasury(): address { @0xE2 }

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    fun setup_config(scenario: &mut Scenario) {
        scenario.next_tx(admin());
        {
            let ctx = scenario.ctx();

            let admin_cap = access::create_admin_cap(ctx);
            transfer::public_transfer(admin_cap, admin());

            let config = config::create_config(treasury(), ctx);
            transfer::public_share_object(config);
        };
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIG CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_config_creation() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let config = scenario.take_shared<LaunchpadConfig>();

            // Verify default values
            assert!(config::creation_fee(&config) == 500_000_000, 0); // 0.5 SUI
            assert!(config::trading_fee_bps(&config) == 50, 1); // 0.5%
            assert!(config::graduation_fee_bps(&config) == 500, 2); // 5%
            assert!(config::platform_allocation_bps(&config) == 100, 3); // 1%
            assert!(config::treasury(&config) == treasury(), 4);
            assert!(!config::is_paused(&config), 5);

            // Verify graduation defaults
            assert!(config::creator_graduation_bps(&config) == 0, 6); // 0% default
            assert!(config::platform_graduation_bps(&config) == 250, 7); // 2.5%

            // Verify LP distribution defaults
            assert!(config::creator_lp_bps(&config) == 2000, 8); // 20%
            assert!(config::community_lp_destination(&config) == 0, 9); // burn

            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_config_default_curve_params() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let config = scenario.take_shared<LaunchpadConfig>();

            // Verify curve defaults
            assert!(config::default_base_price(&config) == 1_000, 0);
            assert!(config::default_slope(&config) == 1_000_000, 1);
            assert!(config::default_total_supply(&config) == 1_000_000_000_000_000_000, 2); // 1 billion with 9 decimals

            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FEE UPDATE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_set_creation_fee() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            let new_fee = 1_000_000_000; // 1 SUI

            config::set_creation_fee(&admin_cap, &mut config, new_fee);

            assert!(config::creation_fee(&config) == new_fee, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_trading_fee() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            let new_fee = 100; // 1%

            config::set_trading_fee(&admin_cap, &mut config, new_fee);

            assert!(config::trading_fee_bps(&config) == new_fee, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 100)] // EFeeTooHigh
    fun test_set_trading_fee_too_high() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Try to set fee above 10% (1000 bps)
            config::set_trading_fee(&admin_cap, &mut config, 1001);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_graduation_fee() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            let new_fee = 300; // 3%

            config::set_graduation_fee(&admin_cap, &mut config, new_fee);

            assert!(config::graduation_fee_bps(&config) == new_fee, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GRADUATION ALLOCATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_set_creator_graduation_bps() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Set to 5% (max allowed)
            config::set_creator_graduation_bps(&admin_cap, &mut config, 500);

            assert!(config::creator_graduation_bps(&config) == 500, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 104)] // EInvalidGraduationAllocation
    fun test_set_creator_graduation_bps_too_high() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Try to set above 5% (500 bps)
            config::set_creator_graduation_bps(&admin_cap, &mut config, 501);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_platform_graduation_bps() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Set to 5% (max allowed)
            config::set_platform_graduation_bps(&admin_cap, &mut config, 500);

            assert!(config::platform_graduation_bps(&config) == 500, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 104)] // EInvalidGraduationAllocation
    fun test_set_platform_graduation_bps_too_low() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Try to set below 2.5% (250 bps)
            config::set_platform_graduation_bps(&admin_cap, &mut config, 249);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LP DISTRIBUTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_set_creator_lp_bps() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Set to 30% (max allowed)
            config::set_creator_lp_bps(&admin_cap, &mut config, 3000);

            assert!(config::creator_lp_bps(&config) == 3000, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 105)] // ECreatorLPTooHigh
    fun test_set_creator_lp_bps_too_high() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Try to set above 30% (3000 bps)
            config::set_creator_lp_bps(&admin_cap, &mut config, 3001);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_community_lp_destination() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Test all valid destinations
            config::set_community_lp_destination(&admin_cap, &mut config, 0); // burn
            assert!(config::community_lp_destination(&config) == 0, 0);

            config::set_community_lp_destination(&admin_cap, &mut config, 1); // dao
            assert!(config::community_lp_destination(&config) == 1, 1);

            config::set_community_lp_destination(&admin_cap, &mut config, 2); // staking
            assert!(config::community_lp_destination(&config) == 2, 2);

            config::set_community_lp_destination(&admin_cap, &mut config, 3); // community vest
            assert!(config::community_lp_destination(&config) == 3, 3);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 106)] // EInvalidLPDestination
    fun test_set_community_lp_destination_invalid() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Try invalid destination (> 3)
            config::set_community_lp_destination(&admin_cap, &mut config, 4);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TREASURY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_set_treasury() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            config::set_treasury(&admin_cap, &mut config, new_treasury());

            assert!(config::treasury(&config) == new_treasury(), 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PAUSE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_toggle_pause() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            assert!(!config::is_paused(&config), 0);

            config::toggle_pause(&admin_cap, &mut config);
            assert!(config::is_paused(&config), 1);

            config::toggle_pause(&admin_cap, &mut config);
            assert!(!config::is_paused(&config), 2);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_paused() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            config::set_paused(&admin_cap, &mut config, true);
            assert!(config::is_paused(&config), 0);

            config::set_paused(&admin_cap, &mut config, false);
            assert!(!config::is_paused(&config), 1);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEX CONFIG TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_dex_type_constants() {
        assert!(config::dex_cetus() == 0, 0);
        assert!(config::dex_turbos() == 1, 1);
        assert!(config::dex_flowx() == 2, 2);
        assert!(config::dex_suidex() == 3, 3);
    }

    #[test]
    fun test_lp_destination_constants() {
        assert!(config::lp_dest_burn() == 0, 0);
        assert!(config::lp_dest_dao() == 1, 1);
        assert!(config::lp_dest_staking() == 2, 2);
        assert!(config::lp_dest_community_vest() == 3, 3);
    }

    #[test]
    fun test_set_default_dex() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            config::set_default_dex(&admin_cap, &mut config, config::dex_turbos());
            assert!(config::default_dex(&config) == config::dex_turbos(), 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GRADUATION THRESHOLD TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_set_graduation_threshold() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            let new_threshold = 100_000_000_000_000; // 100,000 SUI

            config::set_graduation_threshold(&admin_cap, &mut config, new_threshold);

            assert!(config::graduation_threshold(&config) == new_threshold, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 103)] // EInvalidThreshold
    fun test_set_graduation_threshold_zero() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Try to set threshold to 0
            config::set_graduation_threshold(&admin_cap, &mut config, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FUND SAFETY CONSTANT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_fund_safety_constants() {
        assert!(config::max_creator_lp_bps() == 3000, 0); // 30%
        assert!(config::min_lp_lock_duration() == 7_776_000_000, 1); // 90 days in ms
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STRICT ADMIN SAFETY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_config_values_preserved_across_updates() {
        let mut scenario = test_scenario::begin(admin());

        scenario.next_tx(admin());
        {
            let ctx = scenario.ctx();
            let admin_cap = access::create_admin_cap(ctx);
            transfer::public_transfer(admin_cap, admin());

            let config = config::create_config(treasury(), ctx);
            transfer::public_share_object(config);
        };

        // Record all initial values
        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            let initial_creation_fee = config::creation_fee(&config);
            let initial_trading_fee = config::trading_fee_bps(&config);
            let initial_treasury = config::treasury(&config);
            let initial_threshold = config::graduation_threshold(&config);

            // Update ONE value
            config::set_creation_fee(&admin_cap, &mut config, 1_000_000_000);

            // STRICT: Only that value changed, others preserved
            assert!(config::creation_fee(&config) == 1_000_000_000, 10000);
            assert!(config::trading_fee_bps(&config) == initial_trading_fee, 10001);
            assert!(config::treasury(&config) == initial_treasury, 10002);
            assert!(config::graduation_threshold(&config) == initial_threshold, 10003);

            // Update another value
            config::set_trading_fee(&admin_cap, &mut config, 75);

            // STRICT: Only that value changed
            assert!(config::creation_fee(&config) == 1_000_000_000, 10004);
            assert!(config::trading_fee_bps(&config) == 75, 10005);
            assert!(config::treasury(&config) == initial_treasury, 10006);
            assert!(config::graduation_threshold(&config) == initial_threshold, 10007);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_all_fee_limits_enforced() {
        let mut scenario = test_scenario::begin(admin());

        scenario.next_tx(admin());
        {
            let ctx = scenario.ctx();
            let admin_cap = access::create_admin_cap(ctx);
            transfer::public_transfer(admin_cap, admin());

            let config = config::create_config(treasury(), ctx);
            transfer::public_share_object(config);
        };

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let config = scenario.take_shared<LaunchpadConfig>();

            // STRICT: Verify fee limits from constants
            assert!(config::trading_fee_bps(&config) <= 500, 11000); // Max 5%
            assert!(config::graduation_fee_bps(&config) <= 500, 11001); // Max 5%
            assert!(config::creator_graduation_bps(&config) <= 500, 11002); // Max 5%
            assert!(config::platform_graduation_bps(&config) >= 250, 11003); // Min 2.5%
            assert!(config::platform_graduation_bps(&config) <= 500, 11004); // Max 5%

            // Combined allocation must leave majority for liquidity
            let creator_bps = config::creator_graduation_bps(&config);
            let platform_bps = config::platform_graduation_bps(&config);
            assert!(creator_bps + platform_bps <= 1000, 11005); // Max 10% combined

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_lp_distribution_safety_limits() {
        let mut scenario = test_scenario::begin(admin());

        scenario.next_tx(admin());
        {
            let ctx = scenario.ctx();
            let admin_cap = access::create_admin_cap(ctx);
            transfer::public_transfer(admin_cap, admin());

            let config = config::create_config(treasury(), ctx);
            transfer::public_share_object(config);
        };

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let config = scenario.take_shared<LaunchpadConfig>();

            // STRICT: Creator LP is within safe limits
            let creator_lp = config::creator_lp_bps(&config);
            assert!(creator_lp <= config::max_creator_lp_bps(), 12000);
            assert!(creator_lp <= 3000, 12001); // Hard cap 30%

            // STRICT: Community gets the rest
            let community_lp = 10000 - creator_lp;
            assert!(community_lp >= 7000, 12002); // At least 70% to community

            // STRICT: Vesting parameters are reasonable
            let cliff = config::creator_lp_cliff_ms(&config);
            let vesting = config::creator_lp_vesting_ms(&config);
            assert!(cliff + vesting >= config::min_lp_lock_duration(), 12003);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_graduation_threshold_safety() {
        let mut scenario = test_scenario::begin(admin());

        scenario.next_tx(admin());
        {
            let ctx = scenario.ctx();
            let admin_cap = access::create_admin_cap(ctx);
            transfer::public_transfer(admin_cap, admin());

            let config = config::create_config(treasury(), ctx);
            transfer::public_share_object(config);
        };

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let config = scenario.take_shared<LaunchpadConfig>();

            // STRICT: Graduation threshold is reasonable
            let threshold = config::graduation_threshold(&config);
            assert!(threshold > 0, 13000); // Must be positive

            // STRICT: Min liquidity is reasonable
            let min_liq = config::min_graduation_liquidity(&config);
            assert!(min_liq > 0, 13001);

            // STRICT: Threshold should be achievable but meaningful
            // Default is 69,000 SUI (pump.fun style graduation)
            assert!(threshold >= 1_000_000_000, 13002); // At least 1 SUI
            assert!(threshold <= 100_000_000_000_000, 13003); // At most 100,000 SUI

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_pause_state_toggle_correctness() {
        let mut scenario = test_scenario::begin(admin());

        scenario.next_tx(admin());
        {
            let ctx = scenario.ctx();
            let admin_cap = access::create_admin_cap(ctx);
            transfer::public_transfer(admin_cap, admin());

            let config = config::create_config(treasury(), ctx);
            transfer::public_share_object(config);
        };

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Initial state: not paused
            assert!(!config::is_paused(&config), 14000);

            // Pause
            config::set_paused(&admin_cap, &mut config, true);
            assert!(config::is_paused(&config), 14001);

            // Pause again (idempotent)
            config::set_paused(&admin_cap, &mut config, true);
            assert!(config::is_paused(&config), 14002);

            // Unpause
            config::set_paused(&admin_cap, &mut config, false);
            assert!(!config::is_paused(&config), 14003);

            // Unpause again (idempotent)
            config::set_paused(&admin_cap, &mut config, false);
            assert!(!config::is_paused(&config), 14004);

            // Toggle via toggle_pause
            config::toggle_pause(&admin_cap, &mut config);
            assert!(config::is_paused(&config), 14005);

            config::toggle_pause(&admin_cap, &mut config);
            assert!(!config::is_paused(&config), 14006);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_treasury_address_safety() {
        let mut scenario = test_scenario::begin(admin());

        scenario.next_tx(admin());
        {
            let ctx = scenario.ctx();
            let admin_cap = access::create_admin_cap(ctx);
            transfer::public_transfer(admin_cap, admin());

            let config = config::create_config(treasury(), ctx);
            transfer::public_share_object(config);
        };

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Initial treasury
            assert!(config::treasury(&config) == treasury(), 15000);

            // Update treasury
            let new_treasury = @0xF2;
            config::set_treasury(&admin_cap, &mut config, new_treasury);

            // STRICT: Treasury updated exactly
            assert!(config::treasury(&config) == new_treasury, 15001);
            assert!(config::treasury(&config) != treasury(), 15002);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_dex_configuration_safety() {
        let mut scenario = test_scenario::begin(admin());

        scenario.next_tx(admin());
        {
            let ctx = scenario.ctx();
            let admin_cap = access::create_admin_cap(ctx);
            transfer::public_transfer(admin_cap, admin());

            let config = config::create_config(treasury(), ctx);
            transfer::public_share_object(config);
        };

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // STRICT: DEX type must be valid (0-3)
            let default_dex = config::default_dex(&config);
            assert!(default_dex <= 3, 16000);

            // Can set to any valid DEX
            config::set_default_dex(&admin_cap, &mut config, config::dex_cetus());
            assert!(config::default_dex(&config) == 0, 16001);

            config::set_default_dex(&admin_cap, &mut config, config::dex_turbos());
            assert!(config::default_dex(&config) == 1, 16002);

            config::set_default_dex(&admin_cap, &mut config, config::dex_flowx());
            assert!(config::default_dex(&config) == 2, 16003);

            config::set_default_dex(&admin_cap, &mut config, config::dex_suidex());
            assert!(config::default_dex(&config) == 3, 16004);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }
}
