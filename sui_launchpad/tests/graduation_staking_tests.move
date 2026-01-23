/// Tests for staking integration with graduation
/// Tests config settings, token allocation, and staking helper functions
#[test_only]
module sui_launchpad::graduation_staking_tests {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::test_scenario::{Self, Scenario};
    use sui::clock::{Self, Clock};

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::{Self, AdminCap};
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::graduation;
    use sui_launchpad::staking_integration;
    use sui_launchpad::test_utils;
    use sui_launchpad::test_coin::TEST_COIN;

    // ═══════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════

    fun admin(): address { @0xA1 }
    fun creator(): address { @0xC1 }
    fun treasury(): address { @0xE1 }

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    fun create_clock(scenario: &mut Scenario): Clock {
        clock::create_for_testing(scenario.ctx())
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIG STAKING DEFAULTS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_staking_config_defaults() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let config = scenario.take_shared<LaunchpadConfig>();

            // Verify default staking settings
            assert!(config::staking_enabled(&config) == true, 0);
            assert!(config::staking_reward_bps(&config) == 500, 1); // 5%
            assert!(config::staking_duration_ms(&config) == 31_536_000_000, 2); // 365 days
            assert!(config::staking_min_duration_ms(&config) == 604_800_000, 3); // 7 days
            assert!(config::staking_early_fee_bps(&config) == 500, 4); // 5%
            assert!(config::staking_stake_fee_bps(&config) == 0, 5);
            assert!(config::staking_unstake_fee_bps(&config) == 0, 6);
            assert!(config::staking_admin_destination(&config) == 0, 7); // Creator
            assert!(config::staking_reward_type(&config) == 0, 8); // Same token

            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_staking_config_constants() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let config = scenario.take_shared<LaunchpadConfig>();

            // Verify constant getters
            assert!(config::staking_admin_dest_creator() == 0, 0);
            assert!(config::staking_admin_dest_dao() == 1, 1);
            assert!(config::staking_admin_dest_platform() == 2, 2);

            assert!(config::staking_reward_same_token() == 0, 3);
            assert!(config::staking_reward_sui() == 1, 4);
            assert!(config::staking_reward_custom() == 2, 5);

            // Verify limits
            assert!(config::max_staking_reward_bps() == 1000, 6); // 10%
            assert!(config::max_stake_fee_bps() == 500, 7); // 5%

            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIG SETTER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_set_staking_enabled() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Initially enabled
            assert!(config::staking_enabled(&config) == true, 0);

            // Disable staking
            config::set_staking_enabled(&admin_cap, &mut config, false);
            assert!(config::staking_enabled(&config) == false, 1);

            // Re-enable staking
            config::set_staking_enabled(&admin_cap, &mut config, true);
            assert!(config::staking_enabled(&config) == true, 2);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_staking_reward_bps() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Set to 3% (300 bps)
            config::set_staking_reward_bps(&admin_cap, &mut config, 300);
            assert!(config::staking_reward_bps(&config) == 300, 0);

            // Set to maximum (10% = 1000 bps)
            config::set_staking_reward_bps(&admin_cap, &mut config, 1000);
            assert!(config::staking_reward_bps(&config) == 1000, 1);

            // Set to 0 (no staking rewards)
            config::set_staking_reward_bps(&admin_cap, &mut config, 0);
            assert!(config::staking_reward_bps(&config) == 0, 2);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 110)] // EStakingRewardTooHigh
    fun test_set_staking_reward_bps_too_high() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Try to set above maximum (>10%)
            config::set_staking_reward_bps(&admin_cap, &mut config, 1001);

            abort 999
        };

        scenario.end();
    }

    #[test]
    fun test_set_staking_duration_ms() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Set to 6 months
            let six_months = 15_768_000_000;
            config::set_staking_duration_ms(&admin_cap, &mut config, six_months);
            assert!(config::staking_duration_ms(&config) == six_months, 0);

            // Set to minimum (7 days)
            let seven_days = 604_800_000;
            config::set_staking_duration_ms(&admin_cap, &mut config, seven_days);
            assert!(config::staking_duration_ms(&config) == seven_days, 1);

            // Set to maximum (2 years)
            let two_years = 63_072_000_000;
            config::set_staking_duration_ms(&admin_cap, &mut config, two_years);
            assert!(config::staking_duration_ms(&config) == two_years, 2);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 111)] // EInvalidStakingDuration
    fun test_set_staking_duration_too_short() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Try to set below minimum (< 7 days)
            config::set_staking_duration_ms(&admin_cap, &mut config, 604_800_000 - 1);

            abort 999
        };

        scenario.end();
    }

    #[test]
    fun test_set_staking_min_duration_ms() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Set to 0 (no minimum duration)
            config::set_staking_min_duration_ms(&admin_cap, &mut config, 0);
            assert!(config::staking_min_duration_ms(&config) == 0, 0);

            // Set to 14 days
            let fourteen_days = 1_209_600_000;
            config::set_staking_min_duration_ms(&admin_cap, &mut config, fourteen_days);
            assert!(config::staking_min_duration_ms(&config) == fourteen_days, 1);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_set_staking_fees() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Set early unstake fee
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
    #[expected_failure(abort_code = 115)] // EStakingFeeTooHigh
    fun test_set_staking_stake_fee_too_high() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Try to set above 5%
            config::set_staking_stake_fee_bps(&admin_cap, &mut config, 501);

            abort 999
        };

        scenario.end();
    }

    #[test]
    fun test_set_staking_admin_destination() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Set to DAO
            config::set_staking_admin_destination(&admin_cap, &mut config, 1);
            assert!(config::staking_admin_destination(&config) == 1, 0);

            // Set to platform
            config::set_staking_admin_destination(&admin_cap, &mut config, 2);
            assert!(config::staking_admin_destination(&config) == 2, 1);

            // Set back to creator
            config::set_staking_admin_destination(&admin_cap, &mut config, 0);
            assert!(config::staking_admin_destination(&config) == 0, 2);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 113)] // EInvalidStakingAdminDest
    fun test_set_staking_admin_destination_invalid() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Try invalid destination (>2)
            config::set_staking_admin_destination(&admin_cap, &mut config, 3);

            abort 999
        };

        scenario.end();
    }

    #[test]
    fun test_set_staking_reward_type() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Set to SUI rewards
            config::set_staking_reward_type(&admin_cap, &mut config, 1);
            assert!(config::staking_reward_type(&config) == 1, 0);

            // Set to custom rewards
            config::set_staking_reward_type(&admin_cap, &mut config, 2);
            assert!(config::staking_reward_type(&config) == 2, 1);

            // Set back to same token
            config::set_staking_reward_type(&admin_cap, &mut config, 0);
            assert!(config::staking_reward_type(&config) == 0, 2);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 114)] // EInvalidStakingRewardType
    fun test_set_staking_reward_type_invalid() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Try invalid reward type (>2)
            config::set_staking_reward_type(&admin_cap, &mut config, 3);

            abort 999
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING INTEGRATION MODULE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_staking_integration_constants() {
        // Test admin destination constants
        assert!(staking_integration::admin_dest_creator() == 0, 0);
        assert!(staking_integration::admin_dest_dao() == 1, 1);
        assert!(staking_integration::admin_dest_platform() == 2, 2);

        // Test reward type constants
        assert!(staking_integration::reward_same_token() == 0, 3);
        assert!(staking_integration::reward_sui() == 1, 4);
        assert!(staking_integration::reward_custom() == 2, 5);
    }

    #[test]
    fun test_staking_integration_validation() {
        // Test admin destination validation
        assert!(staking_integration::is_valid_admin_destination(0) == true, 0);
        assert!(staking_integration::is_valid_admin_destination(1) == true, 1);
        assert!(staking_integration::is_valid_admin_destination(2) == true, 2);
        assert!(staking_integration::is_valid_admin_destination(3) == false, 3);

        // Test reward type validation
        assert!(staking_integration::is_valid_reward_type(0) == true, 4);
        assert!(staking_integration::is_valid_reward_type(1) == true, 5);
        assert!(staking_integration::is_valid_reward_type(2) == true, 6);
        assert!(staking_integration::is_valid_reward_type(3) == false, 7);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING CONFIG STRUCT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_staking_config_getters() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(creator());
        {
            let _pool_id = test_utils::create_test_pool(&mut scenario, 0);
        };

        scenario.next_tx(admin());
        {
            let config = scenario.take_shared<LaunchpadConfig>();

            // Verify staking config from launchpad config is accessible
            let enabled = config::staking_enabled(&config);
            let duration = config::staking_duration_ms(&config);
            let min_duration = config::staking_min_duration_ms(&config);
            let early_fee = config::staking_early_fee_bps(&config);
            let stake_fee = config::staking_stake_fee_bps(&config);
            let unstake_fee = config::staking_unstake_fee_bps(&config);
            let admin_dest = config::staking_admin_destination(&config);
            let reward_type = config::staking_reward_type(&config);

            assert!(enabled == true, 0);
            assert!(duration == 31_536_000_000, 1);
            assert!(min_duration == 604_800_000, 2);
            assert!(early_fee == 500, 3);
            assert!(stake_fee == 0, 4);
            assert!(unstake_fee == 0, 5);
            assert!(admin_dest == 0, 6);
            assert!(reward_type == 0, 7);

            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TOKEN ALLOCATION TESTS (with staking disabled)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_graduation_allocation_with_staking_disabled() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Disable staking
            config::set_staking_enabled(&admin_cap, &mut config, false);

            // Verify allocations without staking
            // Creator: 0% (default)
            // Platform: 2.5% (default)
            // Staking: 0% (disabled)
            // Liquidity: 97.5% (remainder)
            let creator_bps = config::creator_graduation_bps(&config);
            let platform_bps = config::platform_graduation_bps(&config);
            let staking_bps = config::staking_reward_bps(&config);
            let staking_enabled = config::staking_enabled(&config);

            assert!(creator_bps == 0, 0);
            assert!(platform_bps == 250, 1);
            assert!(staking_bps == 500, 2); // Still configured, but not used
            assert!(staking_enabled == false, 3);

            // Total non-liquidity = creator + platform = 2.5% (staking disabled)
            let total_allocation = creator_bps + platform_bps;
            assert!(total_allocation == 250, 4);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_graduation_allocation_with_staking_enabled() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let config = scenario.take_shared<LaunchpadConfig>();

            // Verify allocations with staking enabled (default)
            // Creator: 0% (default)
            // Platform: 2.5% (default)
            // Staking: 5% (default)
            // Liquidity: 92.5% (remainder)
            let creator_bps = config::creator_graduation_bps(&config);
            let platform_bps = config::platform_graduation_bps(&config);
            let staking_bps = config::staking_reward_bps(&config);
            let staking_enabled = config::staking_enabled(&config);

            assert!(creator_bps == 0, 0);
            assert!(platform_bps == 250, 1);
            assert!(staking_bps == 500, 2);
            assert!(staking_enabled == true, 3);

            // Total non-liquidity = creator + platform + staking = 7.5%
            let total_allocation = creator_bps + platform_bps + staking_bps;
            assert!(total_allocation == 750, 4);

            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_max_graduation_allocations() {
        let mut scenario = test_scenario::begin(admin());

        test_utils::setup_launchpad(&mut scenario);

        scenario.next_tx(admin());
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            let mut config = scenario.take_shared<LaunchpadConfig>();

            // Set maximum allocations
            config::set_creator_graduation_bps(&admin_cap, &mut config, 500); // 5%
            config::set_platform_graduation_bps(&admin_cap, &mut config, 500); // 5%
            config::set_staking_reward_bps(&admin_cap, &mut config, 1000); // 10%

            // Verify maximums
            // Creator: 5%
            // Platform: 5%
            // Staking: 10%
            // Liquidity: 80% (remainder)
            let creator_bps = config::creator_graduation_bps(&config);
            let platform_bps = config::platform_graduation_bps(&config);
            let staking_bps = config::staking_reward_bps(&config);

            assert!(creator_bps == 500, 0);
            assert!(platform_bps == 500, 1);
            assert!(staking_bps == 1000, 2);

            // Total non-liquidity = 20%
            let total_allocation = creator_bps + platform_bps + staking_bps;
            assert!(total_allocation == 2000, 3);

            // Liquidity still gets 80% minimum
            let liquidity_bps = 10000 - total_allocation;
            assert!(liquidity_bps == 8000, 4);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }
}
