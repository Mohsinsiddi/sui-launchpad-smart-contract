#[test_only]
module sui_launchpad::badges_tests {
    use std::string;

    use sui_launchpad::badges;
    use sui_launchpad::config;
    use sui_launchpad::bonding_curve;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    const ADMIN: address = @0xAD;
    const CREATOR: address = @0xC1;

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Badge Constants
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_badge_type_constants() {
        // Verify all badge type constants
        assert!(badges::badge_locked_lp() == 0, 0);
        assert!(badges::badge_no_creator_alloc() == 1, 1);
        assert!(badges::badge_dao_enabled() == 2, 2);
        assert!(badges::badge_staking_enabled() == 3, 3);
        assert!(badges::badge_long_vesting() == 4, 4);
        assert!(badges::badge_community_majority() == 5, 5);
        assert!(badges::badge_low_fees() == 6, 6);
        assert!(badges::badge_verified_creator() == 7, 7);
        assert!(badges::badge_airdrop_enabled() == 8, 8);
    }

    #[test]
    fun test_num_badge_types() {
        assert!(badges::num_badge_types() == 9, 0);
    }

    #[test]
    fun test_threshold_constants() {
        // 1 year in milliseconds
        assert!(badges::long_vesting_threshold_ms() == 31_536_000_000, 0);

        // 1% = 100 bps
        assert!(badges::low_fee_threshold_bps() == 100, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Badge Info
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_get_badge_info_locked_lp() {
        let (name, desc) = badges::get_badge_info(badges::badge_locked_lp());
        assert!(name == string::utf8(b"Locked LP"), 0);
        assert!(desc == string::utf8(b"Creator LP tokens are locked or vested"), 1);
    }

    #[test]
    fun test_get_badge_info_no_creator_alloc() {
        let (name, desc) = badges::get_badge_info(badges::badge_no_creator_alloc());
        assert!(name == string::utf8(b"No Creator Allocation"), 0);
        assert!(desc == string::utf8(b"Creator receives 0% token allocation at graduation"), 1);
    }

    #[test]
    fun test_get_badge_info_dao_enabled() {
        let (name, desc) = badges::get_badge_info(badges::badge_dao_enabled());
        assert!(name == string::utf8(b"DAO Enabled"), 0);
        assert!(desc == string::utf8(b"Token has decentralized governance"), 1);
    }

    #[test]
    fun test_get_badge_info_staking_enabled() {
        let (name, desc) = badges::get_badge_info(badges::badge_staking_enabled());
        assert!(name == string::utf8(b"Staking Rewards"), 0);
        assert!(desc == string::utf8(b"Token has staking pool with rewards"), 1);
    }

    #[test]
    fun test_get_badge_info_long_vesting() {
        let (name, desc) = badges::get_badge_info(badges::badge_long_vesting());
        assert!(name == string::utf8(b"Long Vesting"), 0);
        assert!(desc == string::utf8(b"Creator LP vesting period is 1+ year"), 1);
    }

    #[test]
    fun test_get_badge_info_community_majority() {
        let (name, desc) = badges::get_badge_info(badges::badge_community_majority());
        assert!(name == string::utf8(b"Community Majority"), 0);
        assert!(desc == string::utf8(b"Community owns majority of LP tokens"), 1);
    }

    #[test]
    fun test_get_badge_info_low_fees() {
        let (name, desc) = badges::get_badge_info(badges::badge_low_fees());
        assert!(name == string::utf8(b"Low Fees"), 0);
        assert!(desc == string::utf8(b"Creator trading fee is 1% or less"), 1);
    }

    #[test]
    fun test_get_badge_info_verified_creator() {
        let (name, desc) = badges::get_badge_info(badges::badge_verified_creator());
        assert!(name == string::utf8(b"Verified Creator"), 0);
        assert!(desc == string::utf8(b"Creator identity has been verified"), 1);
    }

    #[test]
    fun test_get_badge_info_airdrop_enabled() {
        let (name, desc) = badges::get_badge_info(badges::badge_airdrop_enabled());
        assert!(name == string::utf8(b"Community Airdrop"), 0);
        assert!(desc == string::utf8(b"Community airdrop enabled at graduation"), 1);
    }

    #[test]
    fun test_get_badge_info_unknown() {
        let (name, desc) = badges::get_badge_info(99);
        assert!(name == string::utf8(b"Unknown"), 0);
        assert!(desc == string::utf8(b"Unknown badge type"), 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Award Badge
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_award_badge() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        // Create a pool for testing
        let pool = bonding_curve::create_pool_for_testing<FakeToken>(
            1_000_000_000_000, // total supply
            100,               // creator fee bps (1%)
            CREATOR,
            &mut ctx
        );

        let timestamp = 1000000;
        let badge = badges::award_badge(&pool, badges::badge_low_fees(), timestamp, &mut ctx);

        // Verify badge properties
        assert!(badges::badge_pool_id(&badge) == object::id(&pool), 0);
        assert!(badges::badge_type(&badge) == badges::badge_low_fees(), 1);
        assert!(*badges::badge_name(&badge) == string::utf8(b"Low Fees"), 2);
        assert!(badges::badge_awarded_at(&badge) == timestamp, 3);

        // Cleanup
        badges::destroy_badge_for_testing(badge);
        bonding_curve::destroy_pool_for_testing(pool);
        config::destroy_for_testing(platform);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Badge Collection - has_badge and get_badges
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_badge_collection_with_defaults() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        // Create pool with low creator fee (1%)
        let pool = bonding_curve::create_pool_for_testing<FakeToken>(
            1_000_000_000_000,
            100, // 1% fee - qualifies for LOW_FEES badge
            CREATOR,
            &mut ctx
        );

        let timestamp = 1000000;
        let collection = badges::create_badge_collection(&pool, &platform, timestamp, &mut ctx);

        // With default config, should have:
        // - DAO_ENABLED (if platform default is enabled)
        // - STAKING_ENABLED (if platform default is enabled)
        // - LOW_FEES (because creator_fee_bps = 100 <= 100)
        // - LOCKED_LP (if cliff or vesting > 0)

        // Verify LOW_FEES badge is present
        assert!(badges::has_badge(&collection, badges::badge_low_fees()), 0);

        // Check collection getters
        assert!(badges::collection_pool_id(&collection) == object::id(&pool), 1);
        assert!(badges::collection_created_at(&collection) == timestamp, 2);
        assert!(badges::collection_badge_count(&collection) > 0, 3);

        badges::destroy_collection_for_testing(collection);
        bonding_curve::destroy_pool_for_testing(pool);
        config::destroy_for_testing(platform);
    }

    #[test]
    fun test_has_badge_false_for_unearned() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        // Create pool with HIGH creator fee (5%)
        let pool = bonding_curve::create_pool_for_testing<FakeToken>(
            1_000_000_000_000,
            500, // 5% fee - does NOT qualify for LOW_FEES badge
            CREATOR,
            &mut ctx
        );

        let collection = badges::create_badge_collection(&pool, &platform, 1000000, &mut ctx);

        // Should NOT have LOW_FEES badge
        assert!(!badges::has_badge(&collection, badges::badge_low_fees()), 0);

        badges::destroy_collection_for_testing(collection);
        bonding_curve::destroy_pool_for_testing(pool);
        config::destroy_for_testing(platform);
    }

    #[test]
    fun test_get_badges_returns_vector() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        let pool = bonding_curve::create_pool_for_testing<FakeToken>(
            1_000_000_000_000,
            50, // 0.5% fee
            CREATOR,
            &mut ctx
        );

        let collection = badges::create_badge_collection(&pool, &platform, 1000000, &mut ctx);

        let badge_types = badges::get_badges(&collection);

        // Should have at least LOW_FEES badge
        assert!(vector::length(&badge_types) > 0, 0);

        // Check LOW_FEES is in the list
        let mut found_low_fees = false;
        let mut i = 0;
        while (i < vector::length(&badge_types)) {
            if (*vector::borrow(&badge_types, i) == badges::badge_low_fees()) {
                found_low_fees = true;
            };
            i = i + 1;
        };
        assert!(found_low_fees, 1);

        badges::destroy_collection_for_testing(collection);
        bonding_curve::destroy_pool_for_testing(pool);
        config::destroy_for_testing(platform);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Badge Bitmask
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_badges_bitmask() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        let pool = bonding_curve::create_pool_for_testing<FakeToken>(
            1_000_000_000_000,
            0, // 0% fee - definitely qualifies for LOW_FEES
            CREATOR,
            &mut ctx
        );

        let collection = badges::create_badge_collection(&pool, &platform, 1000000, &mut ctx);

        let bitmask = badges::collection_badges_bitmask(&collection);

        // LOW_FEES is badge type 6, so bit 6 should be set
        // Check: bitmask & (1 << 6) != 0
        assert!((bitmask & (1 << 6)) != 0, 0);

        badges::destroy_collection_for_testing(collection);
        bonding_curve::destroy_pool_for_testing(pool);
        config::destroy_for_testing(platform);
    }

    #[test]
    fun test_badge_count_matches_bitmask() {
        let mut ctx = tx_context::dummy();
        let platform = config::create_for_testing(@0x1, &mut ctx);

        let pool = bonding_curve::create_pool_for_testing<FakeToken>(
            1_000_000_000_000,
            100,
            CREATOR,
            &mut ctx
        );

        let collection = badges::create_badge_collection(&pool, &platform, 1000000, &mut ctx);

        let bitmask = badges::collection_badges_bitmask(&collection);
        let count = badges::collection_badge_count(&collection);

        // Count should equal number of set bits in bitmask
        let mut bit_count: u8 = 0;
        let mut mask = bitmask;
        while (mask > 0) {
            if ((mask & 1) == 1) {
                bit_count = bit_count + 1;
            };
            mask = mask >> 1;
        };

        assert!(count == bit_count, 0);

        badges::destroy_collection_for_testing(collection);
        bonding_curve::destroy_pool_for_testing(pool);
        config::destroy_for_testing(platform);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FAKE TOKEN FOR TESTING
    // ═══════════════════════════════════════════════════════════════════════

    public struct FakeToken has drop {}
}
