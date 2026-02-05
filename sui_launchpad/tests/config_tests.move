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
            assert!(config::creator_lp_bps(&config) == 250, 8); // 2.5% (creator vested)
            assert!(config::protocol_lp_bps(&config) == 250, 81); // 2.5% (protocol direct)
            assert!(config::dao_lp_destination(&config) == 1, 9); // DAO treasury (not burn)

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

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING INTEGRATION CONFIG TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_staking_config_defaults() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let config = scenario.take_shared<LaunchpadConfig>();

            // Verify staking defaults
            assert!(config::staking_enabled(&config), 0);
            assert!(config::staking_reward_bps(&config) == 500, 1); // 5%
            assert!(config::staking_duration_ms(&config) == 31_536_000_000, 2); // 365 days
            assert!(config::staking_min_duration_ms(&config) == 604_800_000, 3); // 7 days
            assert!(config::staking_early_fee_bps(&config) == 500, 4); // 5%
            assert!(config::staking_stake_fee_bps(&config) == 0, 5);
            assert!(config::staking_unstake_fee_bps(&config) == 0, 6);
            assert!(config::staking_admin_destination(&config) == 0, 7); // creator
            assert!(config::staking_reward_type(&config) == 0, 8); // same token

            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_staking_enabled() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Disable staking
            config::set_staking_enabled(&admin_cap, &mut config, false);
            assert!(!config::staking_enabled(&config), 0);

            // Enable staking
            config::set_staking_enabled(&admin_cap, &mut config, true);
            assert!(config::staking_enabled(&config), 1);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_staking_reward_bps() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Set to 10% (max allowed)
            config::set_staking_reward_bps(&admin_cap, &mut config, 1000);
            assert!(config::staking_reward_bps(&config) == 1000, 0);

            // Set to 0%
            config::set_staking_reward_bps(&admin_cap, &mut config, 0);
            assert!(config::staking_reward_bps(&config) == 0, 1);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_staking_duration() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Set to 30 days
            let thirty_days = 2_592_000_000;
            config::set_staking_duration_ms(&admin_cap, &mut config, thirty_days);
            assert!(config::staking_duration_ms(&config) == thirty_days, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_staking_fees() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Set early fee
            config::set_staking_early_fee_bps(&admin_cap, &mut config, 300);
            assert!(config::staking_early_fee_bps(&config) == 300, 0);

            // Set stake fee
            config::set_staking_stake_fee_bps(&admin_cap, &mut config, 100);
            assert!(config::staking_stake_fee_bps(&config) == 100, 1);

            // Set unstake fee
            config::set_staking_unstake_fee_bps(&admin_cap, &mut config, 50);
            assert!(config::staking_unstake_fee_bps(&config) == 50, 2);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_staking_admin_destination() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Test all destinations
            config::set_staking_admin_destination(&admin_cap, &mut config, 0); // creator
            assert!(config::staking_admin_destination(&config) == 0, 0);

            config::set_staking_admin_destination(&admin_cap, &mut config, 1); // dao
            assert!(config::staking_admin_destination(&config) == 1, 1);

            config::set_staking_admin_destination(&admin_cap, &mut config, 2); // platform
            assert!(config::staking_admin_destination(&config) == 2, 2);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_staking_reward_type() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Test all reward types
            config::set_staking_reward_type(&admin_cap, &mut config, 0); // same token
            assert!(config::staking_reward_type(&config) == 0, 0);

            config::set_staking_reward_type(&admin_cap, &mut config, 1); // sui
            assert!(config::staking_reward_type(&config) == 1, 1);

            config::set_staking_reward_type(&admin_cap, &mut config, 2); // custom
            assert!(config::staking_reward_type(&config) == 2, 2);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DAO INTEGRATION CONFIG TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_dao_config_defaults() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let config = scenario.take_shared<LaunchpadConfig>();

            // Verify DAO defaults
            assert!(config::dao_enabled(&config), 0);
            assert!(config::dao_quorum_bps(&config) == 400, 1); // 4%
            assert!(config::dao_voting_delay_ms(&config) == 86_400_000, 2); // 1 day
            assert!(config::dao_voting_period_ms(&config) == 259_200_000, 3); // 3 days
            assert!(config::dao_timelock_delay_ms(&config) == 172_800_000, 4); // 2 days
            assert!(config::dao_proposal_threshold_bps(&config) == 100, 5); // 1%
            assert!(!config::dao_council_enabled(&config), 6);
            assert!(config::dao_admin_destination(&config) == 1, 7); // dao_treasury

            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_dao_enabled() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            config::set_dao_enabled(&admin_cap, &mut config, false);
            assert!(!config::dao_enabled(&config), 0);

            config::set_dao_enabled(&admin_cap, &mut config, true);
            assert!(config::dao_enabled(&config), 1);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_dao_quorum() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            config::set_dao_quorum_bps(&admin_cap, &mut config, 1000); // 10%
            assert!(config::dao_quorum_bps(&config) == 1000, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_dao_voting_params() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Set voting delay (2 days)
            config::set_dao_voting_delay_ms(&admin_cap, &mut config, 172_800_000);
            assert!(config::dao_voting_delay_ms(&config) == 172_800_000, 0);

            // Set voting period (5 days)
            config::set_dao_voting_period_ms(&admin_cap, &mut config, 432_000_000);
            assert!(config::dao_voting_period_ms(&config) == 432_000_000, 1);

            // Set timelock delay (3 days)
            config::set_dao_timelock_delay_ms(&admin_cap, &mut config, 259_200_000);
            assert!(config::dao_timelock_delay_ms(&config) == 259_200_000, 2);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_dao_proposal_threshold() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            config::set_dao_proposal_threshold_bps(&admin_cap, &mut config, 500); // 5%
            assert!(config::dao_proposal_threshold_bps(&config) == 500, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_dao_council_enabled() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            config::set_dao_council_enabled(&admin_cap, &mut config, true);
            assert!(config::dao_council_enabled(&config), 0);

            config::set_dao_council_enabled(&admin_cap, &mut config, false);
            assert!(!config::dao_council_enabled(&config), 1);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_dao_admin_destination() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Test all destinations
            config::set_dao_admin_destination(&admin_cap, &mut config, 0); // creator
            assert!(config::dao_admin_destination(&config) == 0, 0);

            config::set_dao_admin_destination(&admin_cap, &mut config, 1); // dao_treasury
            assert!(config::dao_admin_destination(&config) == 1, 1);

            config::set_dao_admin_destination(&admin_cap, &mut config, 2); // platform
            assert!(config::dao_admin_destination(&config) == 2, 2);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LP DISTRIBUTION CONFIG TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_set_protocol_lp_bps() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            config::set_protocol_lp_bps(&admin_cap, &mut config, 500); // 5%
            assert!(config::protocol_lp_bps(&config) == 500, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_dao_lp_bps_calculation() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Default: creator=2.5%, protocol=2.5%, DAO=95%
            assert!(config::dao_lp_bps(&config) == 9500, 0);

            // Change creator to 10%
            config::set_creator_lp_bps(&admin_cap, &mut config, 1000);
            // DAO should now be 87.5%
            assert!(config::dao_lp_bps(&config) == 8750, 1);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_min_graduation_liquidity() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            let new_min = 5_000_000_000_000; // 5000 SUI
            config::set_min_graduation_liquidity(&admin_cap, &mut config, new_min);
            assert!(config::min_graduation_liquidity(&config) == new_min, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_platform_allocation() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            config::set_platform_allocation(&admin_cap, &mut config, 200); // 2%
            assert!(config::platform_allocation_bps(&config) == 200, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION HELPER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_assert_not_paused() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let config = scenario.take_shared<LaunchpadConfig>();

            // Should not abort when not paused
            config::assert_not_paused(&config);

            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 102)] // EPaused
    fun test_assert_not_paused_when_paused() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            config::set_paused(&admin_cap, &mut config, true);

            // Should abort when paused
            config::assert_not_paused(&config);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_get_dex_package() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Set package addresses (using valid hex addresses)
            let cetus_pkg = @0xCE1;
            let turbos_pkg = @0x7B2;
            let flowx_pkg = @0xF13;
            let suidex_pkg = @0x5D4;

            config::set_cetus_package(&admin_cap, &mut config, cetus_pkg);
            config::set_turbos_package(&admin_cap, &mut config, turbos_pkg);
            config::set_flowx_package(&admin_cap, &mut config, flowx_pkg);
            config::set_suidex_package(&admin_cap, &mut config, suidex_pkg);

            // Verify get_dex_package returns correct addresses
            assert!(config::get_dex_package(&config, config::dex_cetus()) == cetus_pkg, 0);
            assert!(config::get_dex_package(&config, config::dex_turbos()) == turbos_pkg, 1);
            assert!(config::get_dex_package(&config, config::dex_flowx()) == flowx_pkg, 2);
            assert!(config::get_dex_package(&config, config::dex_suidex()) == suidex_pkg, 3);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING CONSTANT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_staking_constant_getters() {
        // Admin destination constants
        assert!(config::staking_admin_dest_creator() == 0, 0);
        assert!(config::staking_admin_dest_dao() == 1, 1);
        assert!(config::staking_admin_dest_platform() == 2, 2);

        // Reward type constants
        assert!(config::staking_reward_same_token() == 0, 3);
        assert!(config::staking_reward_sui() == 1, 4);
        assert!(config::staking_reward_custom() == 2, 5);

        // Limits
        assert!(config::max_staking_reward_bps() == 1000, 6); // 10%
        assert!(config::min_staking_duration_ms() == 604_800_000, 7); // 7 days
        assert!(config::max_staking_duration_ms() == 63_072_000_000, 8); // 2 years
        assert!(config::max_min_stake_duration_ms() == 2_592_000_000, 9); // 30 days
        assert!(config::max_stake_fee_bps() == 500, 10); // 5%
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DAO CONSTANT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_dao_constant_getters() {
        // Admin destination constants
        assert!(config::dao_admin_dest_creator() == 0, 0);
        assert!(config::dao_admin_dest_dao_treasury() == 1, 1);
        assert!(config::dao_admin_dest_platform() == 2, 2);

        // Limits
        assert!(config::max_dao_quorum_bps() == 5000, 3); // 50%
        assert!(config::max_dao_proposal_threshold_bps() == 1000, 4); // 10%
        assert!(config::min_dao_voting_delay_ms() == 3_600_000, 5); // 1 hour
        assert!(config::max_dao_voting_delay_ms() == 604_800_000, 6); // 7 days
        assert!(config::min_dao_voting_period_ms() == 86_400_000, 7); // 1 day
        assert!(config::max_dao_voting_period_ms() == 1_209_600_000, 8); // 14 days
        assert!(config::min_dao_timelock_delay_ms() == 3_600_000, 9); // 1 hour
        assert!(config::max_dao_timelock_delay_ms() == 1_209_600_000, 10); // 14 days

        // Defaults
        assert!(config::default_dao_quorum_bps() == 400, 11); // 4%
        assert!(config::default_dao_voting_delay_ms() == 86_400_000, 12); // 1 day
        assert!(config::default_dao_voting_period_ms() == 259_200_000, 13); // 3 days
        assert!(config::default_dao_timelock_delay_ms() == 172_800_000, 14); // 2 days
        assert!(config::default_dao_proposal_threshold_bps() == 100, 15); // 1%
    }

    #[test]
    fun test_fund_safety_limits() {
        assert!(config::min_creation_fee() == 100_000_000, 0); // 0.1 SUI
        assert!(config::max_total_graduation_allocation_bps() == 2000, 1); // 20%
    }

    #[test]
    #[expected_failure(abort_code = 122)] // ECreationFeeTooLow
    fun test_creation_fee_below_minimum() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Try to set below minimum (0.1 SUI)
            config::set_creation_fee(&admin_cap, &mut config, 50_000_000);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_staking_min_duration() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            // Set to 14 days
            let fourteen_days = 1_209_600_000;
            config::set_staking_min_duration_ms(&admin_cap, &mut config, fourteen_days);
            assert!(config::staking_min_duration_ms(&config) == fourteen_days, 0);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_creator_lp_vesting() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            let new_cliff = 30_000_000_000; // 30 days
            let new_vesting = 60_000_000_000; // 60 days
            config::set_creator_lp_vesting(&admin_cap, &mut config, new_cliff, new_vesting);

            assert!(config::creator_lp_cliff_ms(&config) == new_cliff, 0);
            assert!(config::creator_lp_vesting_ms(&config) == new_vesting, 1);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_dao_lp_vesting() {
        let mut scenario = test_scenario::begin(admin());

        setup_config(&mut scenario);

        scenario.next_tx(admin());
        {
            let mut config = scenario.take_shared<LaunchpadConfig>();
            let admin_cap = scenario.take_from_sender<AdminCap>();

            let new_cliff = 10_000_000_000;
            let new_vesting = 20_000_000_000;
            config::set_dao_lp_vesting(&admin_cap, &mut config, new_cliff, new_vesting);

            assert!(config::dao_lp_cliff_ms(&config) == new_cliff, 0);
            assert!(config::dao_lp_vesting_ms(&config) == new_vesting, 1);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }
}
