/// Creator Badges NFT System
///
/// Achievement badges awarded to tokens and creators based on their
/// configuration and behavior. These serve as trust signals for buyers.
///
/// Badge Types:
/// - LOCKED_LP: Creator LP is locked/vested (safer for buyers)
/// - NO_CREATOR_ALLOC: Creator takes 0% token allocation at graduation
/// - DAO_ENABLED: Token has DAO governance enabled
/// - STAKING_ENABLED: Token has staking pool enabled
/// - LONG_VESTING: Creator LP has long vesting (1+ year)
/// - COMMUNITY_MAJORITY: Community (DAO) gets majority of LP (>50%)
/// - LOW_FEES: Creator fee is below average (0-1%)
/// - VERIFIED_CREATOR: Creator has been verified (future: KYC)
module sui_launchpad::badges {

    use std::string::{Self, String};
    use sui::event;

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::creator_config::{Self, CreatorTokenConfig};

    // ═══════════════════════════════════════════════════════════════════════
    // BADGE TYPE CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Creator LP tokens are locked/vested
    const BADGE_LOCKED_LP: u8 = 0;
    /// Creator takes 0% token allocation at graduation
    const BADGE_NO_CREATOR_ALLOC: u8 = 1;
    /// Token has DAO governance enabled
    const BADGE_DAO_ENABLED: u8 = 2;
    /// Token has staking rewards enabled
    const BADGE_STAKING_ENABLED: u8 = 3;
    /// Creator LP has long vesting period (1+ year)
    const BADGE_LONG_VESTING: u8 = 4;
    /// Community/DAO gets majority of LP (>50%)
    const BADGE_COMMUNITY_MAJORITY: u8 = 5;
    /// Creator fee is low (0-1%)
    const BADGE_LOW_FEES: u8 = 6;
    /// Creator has been verified
    const BADGE_VERIFIED_CREATOR: u8 = 7;
    /// Community airdrop enabled
    const BADGE_AIRDROP_ENABLED: u8 = 8;

    /// Number of badge types
    const NUM_BADGE_TYPES: u8 = 9;

    /// Threshold for "long vesting" badge (1 year in ms)
    const LONG_VESTING_THRESHOLD_MS: u64 = 31_536_000_000;

    /// Threshold for "low fees" badge (1% = 100 bps)
    const LOW_FEE_THRESHOLD_BPS: u64 = 100;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Badge NFT awarded to a token/pool
    public struct TokenBadge has key, store {
        id: UID,
        /// Pool ID this badge belongs to
        pool_id: ID,
        /// Badge type (see constants)
        badge_type: u8,
        /// Human-readable badge name
        name: String,
        /// Badge description
        description: String,
        /// When badge was awarded
        awarded_at: u64,
    }

    /// Badge collection for a pool
    /// Holds all earned badges for easy querying
    public struct BadgeCollection has key, store {
        id: UID,
        /// Pool ID this collection belongs to
        pool_id: ID,
        /// Bitmask of earned badges (bit N = badge type N)
        badges_bitmask: u64,
        /// Total badges earned
        badge_count: u8,
        /// When collection was created
        created_at: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct BadgeAwarded has copy, drop {
        pool_id: ID,
        badge_type: u8,
        badge_name: vector<u8>,
        awarded_at: u64,
    }

    public struct BadgeCollectionCreated has copy, drop {
        collection_id: ID,
        pool_id: ID,
        badge_count: u8,
        badges_bitmask: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BADGE AWARDING
    // ═══════════════════════════════════════════════════════════════════════

    /// Create badge collection and award all eligible badges for a pool
    public fun create_badge_collection<T>(
        pool: &BondingPool<T>,
        config: &LaunchpadConfig,
        timestamp: u64,
        ctx: &mut TxContext,
    ): BadgeCollection {
        let pool_id = object::id(pool);
        let mut badges_bitmask: u64 = 0;
        let mut badge_count: u8 = 0;

        // Check each badge eligibility
        let creator_config_opt = bonding_curve::creator_config(pool);

        // BADGE: LOCKED_LP - if creator LP is vested
        if (config::creator_lp_cliff_ms(config) > 0 || config::creator_lp_vesting_ms(config) > 0) {
            badges_bitmask = badges_bitmask | (1 << (BADGE_LOCKED_LP as u8));
            badge_count = badge_count + 1;
        };

        // BADGE: NO_CREATOR_ALLOC - if creator gets 0% at graduation
        if (config::creator_graduation_bps(config) == 0) {
            badges_bitmask = badges_bitmask | (1 << (BADGE_NO_CREATOR_ALLOC as u8));
            badge_count = badge_count + 1;
        };

        // BADGE: DAO_ENABLED
        let dao_enabled = if (option::is_some(creator_config_opt)) {
            let cc = option::borrow(creator_config_opt);
            creator_config::get_dao_enabled(cc, config)
        } else {
            config::dao_enabled(config)
        };
        if (dao_enabled) {
            badges_bitmask = badges_bitmask | (1 << (BADGE_DAO_ENABLED as u8));
            badge_count = badge_count + 1;
        };

        // BADGE: STAKING_ENABLED
        let staking_enabled = if (option::is_some(creator_config_opt)) {
            let cc = option::borrow(creator_config_opt);
            creator_config::get_staking_enabled(cc, config)
        } else {
            config::staking_enabled(config)
        };
        if (staking_enabled) {
            badges_bitmask = badges_bitmask | (1 << (BADGE_STAKING_ENABLED as u8));
            badge_count = badge_count + 1;
        };

        // BADGE: LONG_VESTING - if total vesting > 1 year
        let total_vesting = config::creator_lp_cliff_ms(config) + config::creator_lp_vesting_ms(config);
        if (total_vesting >= LONG_VESTING_THRESHOLD_MS) {
            badges_bitmask = badges_bitmask | (1 << (BADGE_LONG_VESTING as u8));
            badge_count = badge_count + 1;
        };

        // BADGE: COMMUNITY_MAJORITY - if DAO gets >50% of LP
        if (config::dao_lp_bps(config) > 5000) {
            badges_bitmask = badges_bitmask | (1 << (BADGE_COMMUNITY_MAJORITY as u8));
            badge_count = badge_count + 1;
        };

        // BADGE: LOW_FEES - if creator fee <= 1%
        if (bonding_curve::creator_fee_bps(pool) <= LOW_FEE_THRESHOLD_BPS) {
            badges_bitmask = badges_bitmask | (1 << (BADGE_LOW_FEES as u8));
            badge_count = badge_count + 1;
        };

        // BADGE: AIRDROP_ENABLED
        let airdrop_enabled = if (option::is_some(creator_config_opt)) {
            let cc = option::borrow(creator_config_opt);
            creator_config::airdrop_enabled(cc)
        } else {
            false
        };
        if (airdrop_enabled) {
            badges_bitmask = badges_bitmask | (1 << (BADGE_AIRDROP_ENABLED as u8));
            badge_count = badge_count + 1;
        };

        let collection = BadgeCollection {
            id: object::new(ctx),
            pool_id,
            badges_bitmask,
            badge_count,
            created_at: timestamp,
        };

        event::emit(BadgeCollectionCreated {
            collection_id: object::id(&collection),
            pool_id,
            badge_count,
            badges_bitmask,
        });

        collection
    }

    /// Award individual badge NFT (for display purposes)
    public fun award_badge<T>(
        pool: &BondingPool<T>,
        badge_type: u8,
        timestamp: u64,
        ctx: &mut TxContext,
    ): TokenBadge {
        let pool_id = object::id(pool);
        let (name, description) = get_badge_info(badge_type);

        event::emit(BadgeAwarded {
            pool_id,
            badge_type,
            badge_name: *string::bytes(&name),
            awarded_at: timestamp,
        });

        TokenBadge {
            id: object::new(ctx),
            pool_id,
            badge_type,
            name,
            description,
            awarded_at: timestamp,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BADGE INFO
    // ═══════════════════════════════════════════════════════════════════════

    /// Get badge name and description
    public fun get_badge_info(badge_type: u8): (String, String) {
        if (badge_type == BADGE_LOCKED_LP) {
            (
                string::utf8(b"Locked LP"),
                string::utf8(b"Creator LP tokens are locked or vested")
            )
        } else if (badge_type == BADGE_NO_CREATOR_ALLOC) {
            (
                string::utf8(b"No Creator Allocation"),
                string::utf8(b"Creator receives 0% token allocation at graduation")
            )
        } else if (badge_type == BADGE_DAO_ENABLED) {
            (
                string::utf8(b"DAO Enabled"),
                string::utf8(b"Token has decentralized governance")
            )
        } else if (badge_type == BADGE_STAKING_ENABLED) {
            (
                string::utf8(b"Staking Rewards"),
                string::utf8(b"Token has staking pool with rewards")
            )
        } else if (badge_type == BADGE_LONG_VESTING) {
            (
                string::utf8(b"Long Vesting"),
                string::utf8(b"Creator LP vesting period is 1+ year")
            )
        } else if (badge_type == BADGE_COMMUNITY_MAJORITY) {
            (
                string::utf8(b"Community Majority"),
                string::utf8(b"Community owns majority of LP tokens")
            )
        } else if (badge_type == BADGE_LOW_FEES) {
            (
                string::utf8(b"Low Fees"),
                string::utf8(b"Creator trading fee is 1% or less")
            )
        } else if (badge_type == BADGE_VERIFIED_CREATOR) {
            (
                string::utf8(b"Verified Creator"),
                string::utf8(b"Creator identity has been verified")
            )
        } else if (badge_type == BADGE_AIRDROP_ENABLED) {
            (
                string::utf8(b"Community Airdrop"),
                string::utf8(b"Community airdrop enabled at graduation")
            )
        } else {
            (
                string::utf8(b"Unknown"),
                string::utf8(b"Unknown badge type")
            )
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Check if collection has a specific badge
    public fun has_badge(collection: &BadgeCollection, badge_type: u8): bool {
        (collection.badges_bitmask & (1 << badge_type)) != 0
    }

    /// Get all badges as a vector of badge types
    public fun get_badges(collection: &BadgeCollection): vector<u8> {
        let mut badges = vector::empty<u8>();
        let mut i: u8 = 0;
        while (i < NUM_BADGE_TYPES) {
            if (has_badge(collection, i)) {
                vector::push_back(&mut badges, i);
            };
            i = i + 1;
        };
        badges
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    // Badge getters
    public fun badge_pool_id(badge: &TokenBadge): ID { badge.pool_id }
    public fun badge_type(badge: &TokenBadge): u8 { badge.badge_type }
    public fun badge_name(badge: &TokenBadge): &String { &badge.name }
    public fun badge_description(badge: &TokenBadge): &String { &badge.description }
    public fun badge_awarded_at(badge: &TokenBadge): u64 { badge.awarded_at }

    // Collection getters
    public fun collection_pool_id(collection: &BadgeCollection): ID { collection.pool_id }
    public fun collection_badges_bitmask(collection: &BadgeCollection): u64 { collection.badges_bitmask }
    public fun collection_badge_count(collection: &BadgeCollection): u8 { collection.badge_count }
    public fun collection_created_at(collection: &BadgeCollection): u64 { collection.created_at }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANT GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun badge_locked_lp(): u8 { BADGE_LOCKED_LP }
    public fun badge_no_creator_alloc(): u8 { BADGE_NO_CREATOR_ALLOC }
    public fun badge_dao_enabled(): u8 { BADGE_DAO_ENABLED }
    public fun badge_staking_enabled(): u8 { BADGE_STAKING_ENABLED }
    public fun badge_long_vesting(): u8 { BADGE_LONG_VESTING }
    public fun badge_community_majority(): u8 { BADGE_COMMUNITY_MAJORITY }
    public fun badge_low_fees(): u8 { BADGE_LOW_FEES }
    public fun badge_verified_creator(): u8 { BADGE_VERIFIED_CREATOR }
    public fun badge_airdrop_enabled(): u8 { BADGE_AIRDROP_ENABLED }
    public fun num_badge_types(): u8 { NUM_BADGE_TYPES }
    public fun long_vesting_threshold_ms(): u64 { LONG_VESTING_THRESHOLD_MS }
    public fun low_fee_threshold_bps(): u64 { LOW_FEE_THRESHOLD_BPS }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun destroy_badge_for_testing(badge: TokenBadge) {
        let TokenBadge {
            id,
            pool_id: _,
            badge_type: _,
            name: _,
            description: _,
            awarded_at: _,
        } = badge;
        object::delete(id);
    }

    #[test_only]
    public fun destroy_collection_for_testing(collection: BadgeCollection) {
        let BadgeCollection {
            id,
            pool_id: _,
            badges_bitmask: _,
            badge_count: _,
            created_at: _,
        } = collection;
        object::delete(id);
    }
}
