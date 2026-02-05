#[test_only]
module sui_launchpad::creator_config_tests {
    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::creator_config::{Self, CreatorTokenConfig};
    use sui_launchpad::access;

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Basic Config Creation
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_new_empty_config() {
        let config = creator_config::new_empty();
        // All options should be None, meaning platform defaults will be used
        assert!(!creator_config::has_staking_enabled_override(&config), 0);
        assert!(!creator_config::has_dao_enabled_override(&config), 1);
        assert!(!creator_config::airdrop_enabled(&config), 2);
        assert!(creator_config::airdrop_bps(&config) == 0, 3);
    }

    #[test]
    fun test_new_no_staking_config() {
        let config = creator_config::new_no_staking();
        assert!(creator_config::has_staking_enabled_override(&config), 0);
        // DAO should still be default
        assert!(!creator_config::has_dao_enabled_override(&config), 1);
    }

    #[test]
    fun test_new_no_dao_config() {
        let config = creator_config::new_no_dao();
        assert!(!creator_config::has_staking_enabled_override(&config), 0);
        assert!(creator_config::has_dao_enabled_override(&config), 1);
    }

    #[test]
    fun test_new_minimal_config() {
        let config = creator_config::new_minimal();
        assert!(creator_config::has_staking_enabled_override(&config), 0);
        assert!(creator_config::has_dao_enabled_override(&config), 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Staking Configuration
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_set_staking_enabled() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        let mut config = creator_config::new_empty();
        creator_config::set_staking_enabled(&mut config, false);

        // With override set to false, staking should be disabled
        assert!(!creator_config::get_staking_enabled(&config, &platform), 0);

        creator_config::set_staking_enabled(&mut config, true);
        assert!(creator_config::get_staking_enabled(&config, &platform), 1);

        config::destroy_for_testing(platform);
    }

    #[test]
    fun test_set_staking_reward_bps() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        let mut config = creator_config::new_empty();
        creator_config::set_staking_reward_bps(&mut config, &platform, 300); // 3%

        assert!(creator_config::get_staking_reward_bps(&config, &platform) == 300, 0);

        config::destroy_for_testing(platform);
    }

    #[test]
    #[expected_failure(abort_code = creator_config::EInvalidStakingRewardBps)]
    fun test_set_staking_reward_bps_too_high() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        let mut config = creator_config::new_empty();
        // Try to set > 10% which is max
        creator_config::set_staking_reward_bps(&mut config, &platform, 1500);

        config::destroy_for_testing(platform);
    }

    #[test]
    fun test_set_staking_duration() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        let mut config = creator_config::new_empty();
        let duration = 15_552_000_000; // 180 days
        creator_config::set_staking_duration_ms(&mut config, duration);

        assert!(creator_config::get_staking_duration_ms(&config, &platform) == duration, 0);

        config::destroy_for_testing(platform);
    }

    #[test]
    #[expected_failure(abort_code = creator_config::EInvalidStakingDuration)]
    fun test_set_staking_duration_too_short() {
        let mut config = creator_config::new_empty();
        // Less than 7 days
        creator_config::set_staking_duration_ms(&mut config, 100_000);
    }

    #[test]
    fun test_set_staking_fees() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        let mut config = creator_config::new_empty();

        creator_config::set_staking_early_fee_bps(&mut config, 800); // 8%
        creator_config::set_staking_stake_fee_bps(&mut config, 100); // 1%
        creator_config::set_staking_unstake_fee_bps(&mut config, 50); // 0.5%

        assert!(creator_config::get_staking_early_fee_bps(&config, &platform) == 800, 0);
        assert!(creator_config::get_staking_stake_fee_bps(&config, &platform) == 100, 1);
        assert!(creator_config::get_staking_unstake_fee_bps(&config, &platform) == 50, 2);

        config::destroy_for_testing(platform);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: DAO Configuration
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_set_dao_enabled() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        let mut config = creator_config::new_empty();
        creator_config::set_dao_enabled(&mut config, false);

        assert!(!creator_config::get_dao_enabled(&config, &platform), 0);

        creator_config::set_dao_enabled(&mut config, true);
        assert!(creator_config::get_dao_enabled(&config, &platform), 1);

        config::destroy_for_testing(platform);
    }

    #[test]
    fun test_set_dao_quorum() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        let mut config = creator_config::new_empty();
        creator_config::set_dao_quorum_bps(&mut config, 1000); // 10%

        assert!(creator_config::get_dao_quorum_bps(&config, &platform) == 1000, 0);

        config::destroy_for_testing(platform);
    }

    #[test]
    #[expected_failure(abort_code = creator_config::EInvalidDAOQuorum)]
    fun test_set_dao_quorum_too_high() {
        let mut config = creator_config::new_empty();
        // Max is 50%
        creator_config::set_dao_quorum_bps(&mut config, 6000);
    }

    #[test]
    fun test_set_dao_voting_periods() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        let mut config = creator_config::new_empty();

        creator_config::set_dao_voting_delay_ms(&mut config, 43_200_000); // 12 hours
        creator_config::set_dao_voting_period_ms(&mut config, 172_800_000); // 2 days
        creator_config::set_dao_timelock_delay_ms(&mut config, 86_400_000); // 1 day

        assert!(creator_config::get_dao_voting_delay_ms(&config, &platform) == 43_200_000, 0);
        assert!(creator_config::get_dao_voting_period_ms(&config, &platform) == 172_800_000, 1);
        assert!(creator_config::get_dao_timelock_delay_ms(&config, &platform) == 86_400_000, 2);

        config::destroy_for_testing(platform);
    }

    #[test]
    fun test_set_dao_proposal_threshold() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        let mut config = creator_config::new_empty();
        creator_config::set_dao_proposal_threshold_bps(&mut config, 200); // 2%

        assert!(creator_config::get_dao_proposal_threshold_bps(&config, &platform) == 200, 0);

        config::destroy_for_testing(platform);
    }

    #[test]
    fun test_set_dao_council_enabled() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        let mut config = creator_config::new_empty();
        creator_config::set_dao_council_enabled(&mut config, true);

        assert!(creator_config::get_dao_council_enabled(&config, &platform), 0);

        config::destroy_for_testing(platform);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Airdrop Configuration
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_enable_airdrop() {
        let mut config = creator_config::new_empty();
        creator_config::enable_airdrop(&mut config, 300); // 3%

        assert!(creator_config::airdrop_enabled(&config), 0);
        assert!(creator_config::airdrop_bps(&config) == 300, 1);
    }

    #[test]
    #[expected_failure(abort_code = creator_config::EInvalidAirdropBps)]
    fun test_enable_airdrop_too_high() {
        let mut config = creator_config::new_empty();
        // Max is 5%
        creator_config::enable_airdrop(&mut config, 600);
    }

    #[test]
    fun test_set_airdrop_merkle_root() {
        let mut config = creator_config::new_empty();
        creator_config::enable_airdrop(&mut config, 200);

        let merkle_root = x"deadbeef";
        creator_config::set_airdrop_merkle_root(&mut config, merkle_root);

        let stored_root = creator_config::airdrop_merkle_root(&config);
        assert!(option::is_some(stored_root), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Default Fallback
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_defaults_fallback_to_platform() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        // Empty config should fall back to platform defaults
        let config = creator_config::new_empty();

        // Check values match platform defaults
        assert!(
            creator_config::get_staking_enabled(&config, &platform) == config::staking_enabled(&platform),
            0
        );
        assert!(
            creator_config::get_staking_reward_bps(&config, &platform) == config::staking_reward_bps(&platform),
            1
        );
        assert!(
            creator_config::get_dao_enabled(&config, &platform) == config::dao_enabled(&platform),
            2
        );
        assert!(
            creator_config::get_dao_quorum_bps(&config, &platform) == config::dao_quorum_bps(&platform),
            3
        );

        config::destroy_for_testing(platform);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Max Airdrop BPS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_max_airdrop_bps() {
        assert!(creator_config::max_airdrop_bps() == 500, 0);
    }
}
