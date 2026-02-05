/// Governance configuration and management
module sui_dao::governance {
    use std::string::String;
    use sui::clock::Clock;
    use sui::coin::Coin;
    use sui::sui::SUI;
    use sui::vec_set::{Self, VecSet};
    use sui_dao::access::{Self, DAOAdminCap, CouncilCap};
    use sui_dao::errors;
    use sui_dao::events;
    use sui_dao::registry::{Self, DAORegistry};

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Voting modes
    const VOTING_MODE_STAKING: u8 = 0;
    const VOTING_MODE_NFT: u8 = 1;

    /// Default voting parameters
    const DEFAULT_QUORUM_BPS: u64 = 400;           // 4%
    const DEFAULT_VOTING_DELAY_MS: u64 = 86_400_000;    // 1 day
    const DEFAULT_VOTING_PERIOD_MS: u64 = 259_200_000;  // 3 days
    const DEFAULT_TIMELOCK_DELAY_MS: u64 = 172_800_000; // 2 days
    const DEFAULT_PROPOSAL_THRESHOLD: u64 = 100_000_000_000; // 100 tokens

    /// Limits
    const MIN_VOTING_DELAY_MS: u64 = 3_600_000;     // 1 hour
    const MAX_VOTING_DELAY_MS: u64 = 604_800_000;   // 7 days
    const MIN_VOTING_PERIOD_MS: u64 = 86_400_000;   // 1 day
    const MAX_VOTING_PERIOD_MS: u64 = 1_209_600_000; // 14 days
    const MIN_TIMELOCK_MS: u64 = 43_200_000;        // 12 hours
    const MAX_TIMELOCK_MS: u64 = 604_800_000;       // 7 days
    const MAX_COUNCIL_MEMBERS: u64 = 11;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Governance configuration parameters
    public struct GovernanceConfig has store, copy, drop {
        /// Quorum in basis points (for staking mode)
        quorum_bps: u64,
        /// Quorum in absolute votes (for NFT mode)
        quorum_votes: u64,
        /// Delay before voting starts (ms)
        voting_delay_ms: u64,
        /// Duration of voting period (ms)
        voting_period_ms: u64,
        /// Timelock delay after proposal passes (ms)
        timelock_delay_ms: u64,
        /// Reduced timelock for fast-tracked proposals (ms)
        fast_track_timelock_ms: u64,
        /// Minimum voting power to create proposal
        proposal_threshold: u64,
        /// Approval threshold in basis points (default 5000 = 50%)
        approval_threshold_bps: u64,
    }

    /// Token-based governance (uses staking positions for voting)
    public struct Governance has key {
        id: UID,
        /// Name of the DAO
        name: String,
        /// Description hash (IPFS or URL)
        description_hash: String,
        /// Governance configuration
        config: GovernanceConfig,
        /// Voting mode (STAKING or NFT)
        voting_mode: u8,
        /// Associated staking pool ID (for STAKING mode)
        staking_pool_id: Option<ID>,
        /// NFT collection type name (for NFT mode)
        nft_collection_type: Option<std::ascii::String>,
        /// Is governance paused
        paused: bool,
        /// Council enabled flag
        council_enabled: bool,
        /// Council member addresses
        council_members: VecSet<address>,
        /// Delegation enabled flag
        delegation_enabled: bool,
        /// Treasury ID (optional)
        treasury_id: Option<ID>,
        /// Guardian address (can emergency pause)
        guardian: Option<address>,
        /// Total proposals created
        proposal_count: u64,
        /// Creation timestamp
        created_at_ms: u64,
        /// Creator address
        creator: address,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CREATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create staking-based governance
    public fun create_staking_governance(
        registry: &mut DAORegistry,
        name: String,
        description_hash: String,
        staking_pool_id: ID,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Governance, DAOAdminCap) {
        registry::assert_not_paused(registry);
        registry::collect_dao_creation_fee(registry, payment, false);

        let config = GovernanceConfig {
            quorum_bps: DEFAULT_QUORUM_BPS,
            quorum_votes: 0,
            voting_delay_ms: DEFAULT_VOTING_DELAY_MS,
            voting_period_ms: DEFAULT_VOTING_PERIOD_MS,
            timelock_delay_ms: DEFAULT_TIMELOCK_DELAY_MS,
            fast_track_timelock_ms: MIN_TIMELOCK_MS,
            proposal_threshold: DEFAULT_PROPOSAL_THRESHOLD,
            approval_threshold_bps: 5000, // 50%
        };

        let governance = Governance {
            id: object::new(ctx),
            name,
            description_hash,
            config,
            voting_mode: VOTING_MODE_STAKING,
            staking_pool_id: option::some(staking_pool_id),
            nft_collection_type: option::none(),
            paused: false,
            council_enabled: false,
            council_members: vec_set::empty(),
            delegation_enabled: false,
            treasury_id: option::none(),
            guardian: option::none(),
            proposal_count: 0,
            created_at_ms: clock.timestamp_ms(),
            creator: ctx.sender(),
        };

        let governance_id = object::id(&governance);
        registry::register_governance(registry, governance_id);

        let admin_cap = access::create_dao_admin_cap(governance_id, ctx);

        events::emit_governance_created(
            governance_id,
            ctx.sender(),
            governance.name,
            VOTING_MODE_STAKING,
            governance.staking_pool_id,
            config.quorum_bps,
            config.voting_delay_ms,
            config.voting_period_ms,
            config.timelock_delay_ms,
            config.proposal_threshold,
            events::origin_independent(),
            option::none(),
            clock.timestamp_ms(),
        );

        (governance, admin_cap)
    }

    /// Create staking-based governance with custom parameters (admin only, no fee)
    /// Used by launchpad during graduation for automatic DAO creation
    /// origin: 0=independent, 1=launchpad, 2=partner (use events::origin_* constants)
    /// origin_id: Optional ID linking to source (e.g., launchpad pool ID)
    public fun create_staking_governance_admin(
        _admin_cap: &access::AdminCap,
        registry: &mut DAORegistry,
        name: String,
        staking_pool_id: ID,
        quorum_bps: u64,
        voting_delay_ms: u64,
        voting_period_ms: u64,
        timelock_delay_ms: u64,
        proposal_threshold_bps: u64,
        origin: u8,
        origin_id: Option<ID>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Governance, DAOAdminCap) {
        registry::assert_not_paused(registry);
        // No fee collection - admin privilege

        let config = GovernanceConfig {
            quorum_bps,
            quorum_votes: 0,
            voting_delay_ms,
            voting_period_ms,
            timelock_delay_ms,
            fast_track_timelock_ms: MIN_TIMELOCK_MS,
            proposal_threshold: proposal_threshold_bps,
            approval_threshold_bps: 5000, // 50%
        };

        let governance = Governance {
            id: object::new(ctx),
            name,
            description_hash: std::string::utf8(b""), // Empty for auto-created DAOs
            config,
            voting_mode: VOTING_MODE_STAKING,
            staking_pool_id: option::some(staking_pool_id),
            nft_collection_type: option::none(),
            paused: false,
            council_enabled: false,
            council_members: vec_set::empty(),
            delegation_enabled: false,
            treasury_id: option::none(),
            guardian: option::none(),
            proposal_count: 0,
            created_at_ms: clock.timestamp_ms(),
            creator: ctx.sender(),
        };

        let governance_id = object::id(&governance);
        registry::register_governance(registry, governance_id);

        let admin_cap = access::create_dao_admin_cap(governance_id, ctx);

        events::emit_governance_created(
            governance_id,
            ctx.sender(),
            governance.name,
            VOTING_MODE_STAKING,
            governance.staking_pool_id,
            config.quorum_bps,
            config.voting_delay_ms,
            config.voting_period_ms,
            config.timelock_delay_ms,
            config.proposal_threshold,
            origin,
            origin_id,
            clock.timestamp_ms(),
        );

        (governance, admin_cap)
    }

    /// Create NFT-based governance
    public fun create_nft_governance<NFT: key + store>(
        registry: &mut DAORegistry,
        name: String,
        description_hash: String,
        quorum_votes: u64,
        proposal_threshold_nfts: u64,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Governance, DAOAdminCap) {
        registry::assert_not_paused(registry);
        registry::collect_dao_creation_fee(registry, payment, false);

        let nft_type_string = std::type_name::with_original_ids<NFT>().into_string();

        let config = GovernanceConfig {
            quorum_bps: 0, // Not used for NFT voting
            quorum_votes,
            voting_delay_ms: DEFAULT_VOTING_DELAY_MS,
            voting_period_ms: DEFAULT_VOTING_PERIOD_MS,
            timelock_delay_ms: DEFAULT_TIMELOCK_DELAY_MS,
            fast_track_timelock_ms: MIN_TIMELOCK_MS,
            proposal_threshold: proposal_threshold_nfts,
            approval_threshold_bps: 5000, // 50%
        };

        let governance = Governance {
            id: object::new(ctx),
            name,
            description_hash,
            config,
            voting_mode: VOTING_MODE_NFT,
            staking_pool_id: option::none(),
            nft_collection_type: option::some(nft_type_string),
            paused: false,
            council_enabled: false,
            council_members: vec_set::empty(),
            delegation_enabled: false,
            treasury_id: option::none(),
            guardian: option::none(),
            proposal_count: 0,
            created_at_ms: clock.timestamp_ms(),
            creator: ctx.sender(),
        };

        let governance_id = object::id(&governance);
        registry::register_governance(registry, governance_id);

        let admin_cap = access::create_dao_admin_cap(governance_id, ctx);

        events::emit_nft_governance_created(
            governance_id,
            ctx.sender(),
            governance.name,
            *governance.nft_collection_type.borrow(),
            quorum_votes,
            config.voting_delay_ms,
            config.voting_period_ms,
            config.timelock_delay_ms,
            config.proposal_threshold,
            events::origin_independent(),
            option::none(),
            clock.timestamp_ms(),
        );

        (governance, admin_cap)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Update governance configuration
    public fun update_config(
        admin_cap: &DAOAdminCap,
        governance: &mut Governance,
        quorum_bps: u64,
        quorum_votes: u64,
        voting_delay_ms: u64,
        voting_period_ms: u64,
        timelock_delay_ms: u64,
        proposal_threshold: u64,
        approval_threshold_bps: u64,
    ) {
        access::assert_dao_admin_cap_matches(admin_cap, object::id(governance));
        validate_config_params(voting_delay_ms, voting_period_ms, timelock_delay_ms, approval_threshold_bps);

        governance.config.quorum_bps = quorum_bps;
        governance.config.quorum_votes = quorum_votes;
        governance.config.voting_delay_ms = voting_delay_ms;
        governance.config.voting_period_ms = voting_period_ms;
        governance.config.timelock_delay_ms = timelock_delay_ms;
        governance.config.proposal_threshold = proposal_threshold;
        governance.config.approval_threshold_bps = approval_threshold_bps;

        events::emit_governance_config_updated(
            object::id(governance),
            quorum_bps,
            voting_delay_ms,
            voting_period_ms,
            timelock_delay_ms,
            proposal_threshold,
        );
    }

    /// Set fast-track timelock duration
    public fun set_fast_track_timelock(
        admin_cap: &DAOAdminCap,
        governance: &mut Governance,
        fast_track_timelock_ms: u64,
    ) {
        access::assert_dao_admin_cap_matches(admin_cap, object::id(governance));
        assert!(
            fast_track_timelock_ms >= MIN_TIMELOCK_MS && fast_track_timelock_ms <= governance.config.timelock_delay_ms,
            errors::invalid_config()
        );
        governance.config.fast_track_timelock_ms = fast_track_timelock_ms;
    }

    /// Pause governance
    public fun pause(admin_cap: &DAOAdminCap, governance: &mut Governance) {
        access::assert_dao_admin_cap_matches(admin_cap, object::id(governance));
        governance.paused = true;
        events::emit_governance_paused(object::id(governance));
    }

    /// Unpause governance
    public fun unpause(admin_cap: &DAOAdminCap, governance: &mut Governance) {
        access::assert_dao_admin_cap_matches(admin_cap, object::id(governance));
        governance.paused = false;
        events::emit_governance_unpaused(object::id(governance));
    }

    /// Enable delegation
    public fun enable_delegation(admin_cap: &DAOAdminCap, governance: &mut Governance) {
        access::assert_dao_admin_cap_matches(admin_cap, object::id(governance));
        governance.delegation_enabled = true;
    }

    /// Disable delegation
    public fun disable_delegation(admin_cap: &DAOAdminCap, governance: &mut Governance) {
        access::assert_dao_admin_cap_matches(admin_cap, object::id(governance));
        governance.delegation_enabled = false;
    }

    /// Set treasury ID
    public fun set_treasury(
        admin_cap: &DAOAdminCap,
        governance: &mut Governance,
        treasury_id: ID,
    ) {
        access::assert_dao_admin_cap_matches(admin_cap, object::id(governance));
        governance.treasury_id = option::some(treasury_id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COUNCIL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Enable council with initial members
    public fun enable_council(
        admin_cap: &DAOAdminCap,
        governance: &mut Governance,
        initial_members: vector<address>,
        ctx: &mut TxContext,
    ): vector<CouncilCap> {
        access::assert_dao_admin_cap_matches(admin_cap, object::id(governance));
        assert!(!governance.council_enabled, errors::already_council_member());
        assert!(initial_members.length() > 0 && initial_members.length() <= MAX_COUNCIL_MEMBERS, errors::invalid_config());

        governance.council_enabled = true;

        let mut caps = vector::empty<CouncilCap>();
        let governance_id = object::id(governance);

        let mut i = 0;
        while (i < initial_members.length()) {
            let member = *initial_members.borrow(i);
            governance.council_members.insert(member);
            caps.push_back(access::create_council_cap(governance_id, member, ctx));
            i = i + 1;
        };

        events::emit_council_enabled(governance_id, initial_members);

        caps
    }

    /// Add council member (requires DAO admin cap)
    public fun add_council_member(
        admin_cap: &DAOAdminCap,
        governance: &mut Governance,
        member: address,
        ctx: &mut TxContext,
    ): CouncilCap {
        access::assert_dao_admin_cap_matches(admin_cap, object::id(governance));
        assert!(governance.council_enabled, errors::council_not_enabled());
        assert!(!governance.council_members.contains(&member), errors::already_council_member());
        assert!(governance.council_members.length() < MAX_COUNCIL_MEMBERS, errors::invalid_config());

        governance.council_members.insert(member);
        let cap = access::create_council_cap(object::id(governance), member, ctx);

        events::emit_council_member_added(object::id(governance), member, ctx.sender());

        cap
    }

    /// Remove council member (requires DAO admin cap)
    public fun remove_council_member(
        admin_cap: &DAOAdminCap,
        governance: &mut Governance,
        member: address,
        council_cap: CouncilCap,
        ctx: &TxContext,
    ) {
        access::assert_dao_admin_cap_matches(admin_cap, object::id(governance));
        assert!(governance.council_enabled, errors::council_not_enabled());
        assert!(governance.council_members.contains(&member), errors::not_council_member());
        assert!(governance.council_members.length() > 1, errors::cannot_remove_last_council_member());

        governance.council_members.remove(&member);
        access::destroy_council_cap(council_cap);

        events::emit_council_member_removed(object::id(governance), member, ctx.sender());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PACKAGE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Check governance is not paused
    public(package) fun assert_not_paused(governance: &Governance) {
        assert!(!governance.paused, errors::governance_paused());
    }

    /// Check sender meets proposal threshold
    public(package) fun assert_meets_proposal_threshold(
        governance: &Governance,
        voting_power: u64,
    ) {
        assert!(voting_power >= governance.config.proposal_threshold, errors::insufficient_voting_power());
    }

    /// Increment proposal count
    public(package) fun increment_proposal_count(governance: &mut Governance) {
        governance.proposal_count = governance.proposal_count + 1;
    }

    /// Check if council member
    public(package) fun is_council_member(governance: &Governance, member: address): bool {
        governance.council_members.contains(&member)
    }

    /// Get council size
    public(package) fun council_size(governance: &Governance): u64 {
        governance.council_members.length()
    }

    /// Set guardian (called from guardian module)
    public(package) fun set_guardian_internal(governance: &mut Governance, guardian: address) {
        governance.guardian = option::some(guardian);
    }

    /// Remove guardian (called from guardian module)
    public(package) fun remove_guardian_internal(governance: &mut Governance) {
        governance.guardian = option::none();
    }

    /// Pause by guardian (called from guardian module)
    public(package) fun pause_by_guardian(governance: &mut Governance) {
        governance.paused = true;
        events::emit_governance_paused(object::id(governance));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    public fun name(governance: &Governance): String { governance.name }
    public fun description_hash(governance: &Governance): String { governance.description_hash }
    public fun voting_mode(governance: &Governance): u8 { governance.voting_mode }
    public fun is_staking_mode(governance: &Governance): bool { governance.voting_mode == VOTING_MODE_STAKING }
    public fun is_nft_mode(governance: &Governance): bool { governance.voting_mode == VOTING_MODE_NFT }
    public fun staking_pool_id(governance: &Governance): Option<ID> { governance.staking_pool_id }
    public fun nft_collection_type(governance: &Governance): Option<std::ascii::String> { governance.nft_collection_type }
    public fun is_paused(governance: &Governance): bool { governance.paused }
    public fun is_council_enabled(governance: &Governance): bool { governance.council_enabled }
    public fun is_delegation_enabled(governance: &Governance): bool { governance.delegation_enabled }
    public fun treasury_id(governance: &Governance): Option<ID> { governance.treasury_id }
    public fun guardian(governance: &Governance): Option<address> { governance.guardian }
    public fun proposal_count(governance: &Governance): u64 { governance.proposal_count }
    public fun created_at_ms(governance: &Governance): u64 { governance.created_at_ms }
    public fun creator(governance: &Governance): address { governance.creator }

    // Config getters
    public fun quorum_bps(governance: &Governance): u64 { governance.config.quorum_bps }
    public fun quorum_votes(governance: &Governance): u64 { governance.config.quorum_votes }
    public fun voting_delay_ms(governance: &Governance): u64 { governance.config.voting_delay_ms }
    public fun voting_period_ms(governance: &Governance): u64 { governance.config.voting_period_ms }
    public fun timelock_delay_ms(governance: &Governance): u64 { governance.config.timelock_delay_ms }
    public fun fast_track_timelock_ms(governance: &Governance): u64 { governance.config.fast_track_timelock_ms }
    public fun proposal_threshold(governance: &Governance): u64 { governance.config.proposal_threshold }
    public fun approval_threshold_bps(governance: &Governance): u64 { governance.config.approval_threshold_bps }
    public fun config(governance: &Governance): GovernanceConfig { governance.config }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    fun validate_config_params(
        voting_delay_ms: u64,
        voting_period_ms: u64,
        timelock_delay_ms: u64,
        approval_threshold_bps: u64,
    ) {
        assert!(
            voting_delay_ms >= MIN_VOTING_DELAY_MS && voting_delay_ms <= MAX_VOTING_DELAY_MS,
            errors::invalid_config()
        );
        assert!(
            voting_period_ms >= MIN_VOTING_PERIOD_MS && voting_period_ms <= MAX_VOTING_PERIOD_MS,
            errors::invalid_config()
        );
        assert!(
            timelock_delay_ms >= MIN_TIMELOCK_MS && timelock_delay_ms <= MAX_TIMELOCK_MS,
            errors::invalid_config()
        );
        assert!(
            approval_threshold_bps > 0 && approval_threshold_bps <= 10000,
            errors::invalid_config()
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun voting_mode_staking(): u8 { VOTING_MODE_STAKING }
    public fun voting_mode_nft(): u8 { VOTING_MODE_NFT }
    public fun default_quorum_bps(): u64 { DEFAULT_QUORUM_BPS }
    public fun default_voting_delay_ms(): u64 { DEFAULT_VOTING_DELAY_MS }
    public fun default_voting_period_ms(): u64 { DEFAULT_VOTING_PERIOD_MS }
    public fun default_timelock_delay_ms(): u64 { DEFAULT_TIMELOCK_DELAY_MS }
    public fun default_proposal_threshold(): u64 { DEFAULT_PROPOSAL_THRESHOLD }
    public fun min_timelock_ms(): u64 { MIN_TIMELOCK_MS }
    public fun max_timelock_ms(): u64 { MAX_TIMELOCK_MS }
    public fun max_council_members(): u64 { MAX_COUNCIL_MEMBERS }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun create_governance_for_testing(
        name: String,
        staking_pool_id: ID,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Governance {
        let config = GovernanceConfig {
            quorum_bps: DEFAULT_QUORUM_BPS,
            quorum_votes: 0,
            voting_delay_ms: DEFAULT_VOTING_DELAY_MS,
            voting_period_ms: DEFAULT_VOTING_PERIOD_MS,
            timelock_delay_ms: DEFAULT_TIMELOCK_DELAY_MS,
            fast_track_timelock_ms: MIN_TIMELOCK_MS,
            proposal_threshold: DEFAULT_PROPOSAL_THRESHOLD,
            approval_threshold_bps: 5000,
        };

        Governance {
            id: object::new(ctx),
            name,
            description_hash: std::string::utf8(b"test"),
            config,
            voting_mode: VOTING_MODE_STAKING,
            staking_pool_id: option::some(staking_pool_id),
            nft_collection_type: option::none(),
            paused: false,
            council_enabled: false,
            council_members: vec_set::empty(),
            delegation_enabled: false,
            treasury_id: option::none(),
            guardian: option::none(),
            proposal_count: 0,
            created_at_ms: clock.timestamp_ms(),
            creator: ctx.sender(),
        }
    }

    #[test_only]
    public fun create_nft_governance_for_testing<NFT: key + store>(
        name: String,
        quorum_votes: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Governance {
        let nft_type_string = std::type_name::with_original_ids<NFT>().into_string();

        let config = GovernanceConfig {
            quorum_bps: 0,
            quorum_votes,
            voting_delay_ms: DEFAULT_VOTING_DELAY_MS,
            voting_period_ms: DEFAULT_VOTING_PERIOD_MS,
            timelock_delay_ms: DEFAULT_TIMELOCK_DELAY_MS,
            fast_track_timelock_ms: MIN_TIMELOCK_MS,
            proposal_threshold: 1, // 1 NFT to propose
            approval_threshold_bps: 5000,
        };

        Governance {
            id: object::new(ctx),
            name,
            description_hash: std::string::utf8(b"test"),
            config,
            voting_mode: VOTING_MODE_NFT,
            staking_pool_id: option::none(),
            nft_collection_type: option::some(nft_type_string),
            paused: false,
            council_enabled: false,
            council_members: vec_set::empty(),
            delegation_enabled: false,
            treasury_id: option::none(),
            guardian: option::none(),
            proposal_count: 0,
            created_at_ms: clock.timestamp_ms(),
            creator: ctx.sender(),
        }
    }

    #[test_only]
    public fun destroy_governance_for_testing(governance: Governance) {
        let Governance {
            id,
            name: _,
            description_hash: _,
            config: _,
            voting_mode: _,
            staking_pool_id: _,
            nft_collection_type: _,
            paused: _,
            council_enabled: _,
            council_members: _,
            delegation_enabled: _,
            treasury_id: _,
            guardian: _,
            proposal_count: _,
            created_at_ms: _,
            creator: _,
        } = governance;
        object::delete(id);
    }

    #[test_only]
    public fun share_governance_for_testing(governance: Governance) {
        transfer::share_object(governance);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_staking_governance() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let staking_pool_id = object::id_from_address(@0x123);

        let governance = create_governance_for_testing(
            std::string::utf8(b"Test DAO"),
            staking_pool_id,
            &clock,
            &mut ctx,
        );

        assert!(governance.voting_mode == VOTING_MODE_STAKING, 0);
        assert!(governance.staking_pool_id == option::some(staking_pool_id), 1);
        assert!(governance.council_enabled == false, 2);
        assert!(governance.delegation_enabled == false, 3);
        assert!(governance.config.quorum_bps == DEFAULT_QUORUM_BPS, 4);

        destroy_governance_for_testing(governance);
        sui::clock::destroy_for_testing(clock);
    }

    #[test_only]
    public struct TestNFT has key, store {
        id: UID,
    }

    #[test]
    fun test_create_nft_governance() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);

        let governance = create_nft_governance_for_testing<TestNFT>(
            std::string::utf8(b"Test NFT DAO"),
            10, // quorum of 10 NFTs
            &clock,
            &mut ctx,
        );

        assert!(governance.voting_mode == VOTING_MODE_NFT, 0);
        assert!(governance.staking_pool_id == option::none(), 1);
        assert!(governance.nft_collection_type.is_some(), 2);
        assert!(governance.config.quorum_votes == 10, 3);

        destroy_governance_for_testing(governance);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    fun test_pause_unpause() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let staking_pool_id = object::id_from_address(@0x123);

        let mut governance = create_governance_for_testing(
            std::string::utf8(b"Test DAO"),
            staking_pool_id,
            &clock,
            &mut ctx,
        );

        let admin_cap = access::create_dao_admin_cap(object::id(&governance), &mut ctx);

        assert!(governance.paused == false, 0);

        pause(&admin_cap, &mut governance);
        assert!(governance.paused == true, 1);

        unpause(&admin_cap, &mut governance);
        assert!(governance.paused == false, 2);

        destroy_governance_for_testing(governance);
        access::destroy_dao_admin_cap_for_testing(admin_cap);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    fun test_enable_delegation() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let staking_pool_id = object::id_from_address(@0x123);

        let mut governance = create_governance_for_testing(
            std::string::utf8(b"Test DAO"),
            staking_pool_id,
            &clock,
            &mut ctx,
        );

        let admin_cap = access::create_dao_admin_cap(object::id(&governance), &mut ctx);

        assert!(governance.delegation_enabled == false, 0);

        enable_delegation(&admin_cap, &mut governance);
        assert!(governance.delegation_enabled == true, 1);

        disable_delegation(&admin_cap, &mut governance);
        assert!(governance.delegation_enabled == false, 2);

        destroy_governance_for_testing(governance);
        access::destroy_dao_admin_cap_for_testing(admin_cap);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    fun test_enable_council() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let staking_pool_id = object::id_from_address(@0x123);

        let mut governance = create_governance_for_testing(
            std::string::utf8(b"Test DAO"),
            staking_pool_id,
            &clock,
            &mut ctx,
        );

        let admin_cap = access::create_dao_admin_cap(object::id(&governance), &mut ctx);

        let members = vector[@0xA, @0xB, @0xC];
        let mut caps = enable_council(&admin_cap, &mut governance, members, &mut ctx);

        assert!(governance.council_enabled == true, 0);
        assert!(governance.council_members.length() == 3, 1);
        assert!(is_council_member(&governance, @0xA), 2);
        assert!(is_council_member(&governance, @0xB), 3);
        assert!(is_council_member(&governance, @0xC), 4);

        // Cleanup
        while (!caps.is_empty()) {
            let cap = caps.pop_back();
            access::destroy_council_cap(cap);
        };
        caps.destroy_empty();

        destroy_governance_for_testing(governance);
        access::destroy_dao_admin_cap_for_testing(admin_cap);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    fun test_update_config() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let staking_pool_id = object::id_from_address(@0x123);

        let mut governance = create_governance_for_testing(
            std::string::utf8(b"Test DAO"),
            staking_pool_id,
            &clock,
            &mut ctx,
        );

        let admin_cap = access::create_dao_admin_cap(object::id(&governance), &mut ctx);

        update_config(
            &admin_cap,
            &mut governance,
            500,           // 5% quorum
            0,
            MIN_VOTING_DELAY_MS,
            MIN_VOTING_PERIOD_MS,
            MIN_TIMELOCK_MS,
            200_000_000_000, // 200 tokens threshold
            6000,          // 60% approval
        );

        assert!(governance.config.quorum_bps == 500, 0);
        assert!(governance.config.proposal_threshold == 200_000_000_000, 1);
        assert!(governance.config.approval_threshold_bps == 6000, 2);

        destroy_governance_for_testing(governance);
        access::destroy_dao_admin_cap_for_testing(admin_cap);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    #[expected_failure(abort_code = 200)] // EGovernancePaused
    fun test_assert_not_paused_fails() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let staking_pool_id = object::id_from_address(@0x123);

        let mut governance = create_governance_for_testing(
            std::string::utf8(b"Test DAO"),
            staking_pool_id,
            &clock,
            &mut ctx,
        );

        let admin_cap = access::create_dao_admin_cap(object::id(&governance), &mut ctx);
        pause(&admin_cap, &mut governance);

        assert_not_paused(&governance);

        destroy_governance_for_testing(governance);
        access::destroy_dao_admin_cap_for_testing(admin_cap);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    #[expected_failure(abort_code = 300)] // EInsufficientVotingPower
    fun test_assert_meets_proposal_threshold_fails() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let staking_pool_id = object::id_from_address(@0x123);

        let governance = create_governance_for_testing(
            std::string::utf8(b"Test DAO"),
            staking_pool_id,
            &clock,
            &mut ctx,
        );

        // Try with 0 voting power (threshold is 100 tokens by default)
        assert_meets_proposal_threshold(&governance, 0);

        destroy_governance_for_testing(governance);
        sui::clock::destroy_for_testing(clock);
    }
}
