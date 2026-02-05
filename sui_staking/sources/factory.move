/// Factory module for creating and managing staking pools
/// Handles platform configuration, fees, and pool registry
module sui_staking::factory {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::Clock;
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};

    use sui_staking::access::{Self, AdminCap, PoolAdminCap};
    use sui_staking::pool;
    use sui_staking::events;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Default setup fee: 1 SUI
    const DEFAULT_SETUP_FEE: u64 = 1_000_000_000;

    /// Default platform fee: 1% (100 bps)
    const DEFAULT_PLATFORM_FEE_BPS: u64 = 100;

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING REGISTRY
    // ═══════════════════════════════════════════════════════════════════════

    /// Global registry for all staking pools
    public struct StakingRegistry has key {
        id: UID,
        /// Platform configuration
        config: PlatformConfig,
        /// All pool IDs (for enumeration)
        pool_ids: vector<ID>,
        /// Pool metadata by ID
        pool_metadata: Table<ID, PoolMetadata>,
        /// Collected setup fees
        collected_fees: Balance<SUI>,
        /// Total pools created
        total_pools: u64,
        /// Whether platform is paused
        paused: bool,
    }

    /// Platform configuration
    public struct PlatformConfig has store, copy, drop {
        /// Fee required to create a pool (in SUI)
        setup_fee: u64,
        /// Platform fee on rewards (in basis points)
        platform_fee_bps: u64,
        /// Fee recipient address
        fee_recipient: address,
    }

    /// Metadata about a pool (for indexing)
    public struct PoolMetadata has store, copy, drop {
        /// Pool creator
        creator: address,
        /// When pool was created
        created_at_ms: u64,
        /// Stake token type name
        stake_token_type: std::ascii::String,
        /// Reward token type name
        reward_token_type: std::ascii::String,
        /// Whether this is a governance-only pool
        governance_only: bool,
        /// Origin: 0=independent, 1=launchpad, 2=partner
        origin: u8,
        /// Optional origin ID (launchpad pool ID or partner ID)
        origin_id: Option<ID>,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Initialize the staking platform
    fun init(ctx: &mut TxContext) {
        let admin_cap = access::create_admin_cap(ctx);
        let sender = tx_context::sender(ctx);

        let registry = StakingRegistry {
            id: object::new(ctx),
            config: PlatformConfig {
                setup_fee: DEFAULT_SETUP_FEE,
                platform_fee_bps: DEFAULT_PLATFORM_FEE_BPS,
                fee_recipient: sender,
            },
            pool_ids: vector::empty(),
            pool_metadata: table::new(ctx),
            collected_fees: balance::zero(),
            total_pools: 0,
            paused: false,
        };

        transfer::share_object(registry);
        transfer::public_transfer(admin_cap, sender);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POOL CREATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new staking pool
    public fun create_pool<StakeToken, RewardToken>(
        registry: &mut StakingRegistry,
        reward_coins: Coin<RewardToken>,
        setup_fee: Coin<SUI>,
        start_time_ms: u64,
        duration_ms: u64,
        min_stake_duration_ms: u64,
        early_unstake_fee_bps: u64,
        stake_fee_bps: u64,
        unstake_fee_bps: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): PoolAdminCap {
        // Check platform not paused
        assert!(!registry.paused, sui_staking::errors::platform_paused());

        // Collect setup fee
        let fee_amount = coin::value(&setup_fee);
        assert!(fee_amount >= registry.config.setup_fee, sui_staking::errors::insufficient_fee());
        balance::join(&mut registry.collected_fees, coin::into_balance(setup_fee));

        // Create pool (independent origin for public creation)
        let (pool, admin_cap) = pool::create<StakeToken, RewardToken>(
            reward_coins,
            start_time_ms,
            duration_ms,
            min_stake_duration_ms,
            early_unstake_fee_bps,
            stake_fee_bps,
            unstake_fee_bps,
            events::origin_independent(),
            option::none(),
            clock,
            ctx,
        );

        let pool_id = pool::pool_id(&pool);
        let current_time = sui::clock::timestamp_ms(clock);

        // Get type names for metadata
        let stake_type = std::type_name::with_original_ids<StakeToken>();
        let reward_type = std::type_name::with_original_ids<RewardToken>();

        // Store metadata
        let metadata = PoolMetadata {
            creator: tx_context::sender(ctx),
            created_at_ms: current_time,
            stake_token_type: std::type_name::into_string(stake_type),
            reward_token_type: std::type_name::into_string(reward_type),
            governance_only: false,
            origin: events::origin_independent(),
            origin_id: option::none(),
        };

        vector::push_back(&mut registry.pool_ids, pool_id);
        table::add(&mut registry.pool_metadata, pool_id, metadata);
        registry.total_pools = registry.total_pools + 1;

        // Share the pool
        transfer::public_share_object(pool);

        admin_cap
    }

    /// Create a pool without setup fee (admin only)
    /// origin: 0=independent, 1=launchpad, 2=partner (use events::origin_* constants)
    /// origin_id: Optional ID linking to source (e.g., launchpad pool ID)
    public fun create_pool_admin<StakeToken, RewardToken>(
        registry: &mut StakingRegistry,
        _admin_cap: &AdminCap,
        reward_coins: Coin<RewardToken>,
        start_time_ms: u64,
        duration_ms: u64,
        min_stake_duration_ms: u64,
        early_unstake_fee_bps: u64,
        stake_fee_bps: u64,
        unstake_fee_bps: u64,
        origin: u8,
        origin_id: Option<ID>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): PoolAdminCap {
        // Check platform not paused
        assert!(!registry.paused, sui_staking::errors::platform_paused());

        // Create pool with specified origin
        let (pool, admin_cap) = pool::create<StakeToken, RewardToken>(
            reward_coins,
            start_time_ms,
            duration_ms,
            min_stake_duration_ms,
            early_unstake_fee_bps,
            stake_fee_bps,
            unstake_fee_bps,
            origin,
            origin_id,
            clock,
            ctx,
        );

        let pool_id = pool::pool_id(&pool);
        let current_time = sui::clock::timestamp_ms(clock);

        // Get type names for metadata
        let stake_type = std::type_name::with_original_ids<StakeToken>();
        let reward_type = std::type_name::with_original_ids<RewardToken>();

        // Store metadata
        let metadata = PoolMetadata {
            creator: tx_context::sender(ctx),
            created_at_ms: current_time,
            stake_token_type: std::type_name::into_string(stake_type),
            reward_token_type: std::type_name::into_string(reward_type),
            governance_only: false,
            origin,
            origin_id,
        };

        vector::push_back(&mut registry.pool_ids, pool_id);
        table::add(&mut registry.pool_metadata, pool_id, metadata);
        registry.total_pools = registry.total_pools + 1;

        // Share the pool
        transfer::public_share_object(pool);

        admin_cap
    }

    /// Create a governance-only staking pool (no rewards, just voting power for DAO)
    /// Useful for B2B DAOs that want staking for governance without reward distribution
    public fun create_governance_pool<StakeToken>(
        registry: &mut StakingRegistry,
        setup_fee: Coin<SUI>,
        min_stake_duration_ms: u64,
        early_unstake_fee_bps: u64,
        stake_fee_bps: u64,
        unstake_fee_bps: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): PoolAdminCap {
        // Check platform not paused
        assert!(!registry.paused, sui_staking::errors::platform_paused());

        // Collect setup fee
        let fee_amount = coin::value(&setup_fee);
        assert!(fee_amount >= registry.config.setup_fee, sui_staking::errors::insufficient_fee());
        balance::join(&mut registry.collected_fees, coin::into_balance(setup_fee));

        // Create governance pool (independent origin for public creation)
        let (pool, admin_cap) = pool::create_governance_pool<StakeToken>(
            min_stake_duration_ms,
            early_unstake_fee_bps,
            stake_fee_bps,
            unstake_fee_bps,
            events::origin_independent(),
            option::none(),
            clock,
            ctx,
        );

        let pool_id = pool::pool_id(&pool);
        let current_time = sui::clock::timestamp_ms(clock);

        // Get type name for metadata
        let stake_type = std::type_name::with_original_ids<StakeToken>();

        // Store metadata
        let metadata = PoolMetadata {
            creator: tx_context::sender(ctx),
            created_at_ms: current_time,
            stake_token_type: std::type_name::into_string(stake_type),
            reward_token_type: std::type_name::into_string(stake_type), // Same as stake for governance
            governance_only: true,
            origin: events::origin_independent(),
            origin_id: option::none(),
        };

        vector::push_back(&mut registry.pool_ids, pool_id);
        table::add(&mut registry.pool_metadata, pool_id, metadata);
        registry.total_pools = registry.total_pools + 1;

        // Share the pool
        transfer::public_share_object(pool);

        admin_cap
    }

    /// Create a governance pool without setup fee (admin only)
    /// origin: 0=independent, 1=launchpad, 2=partner (use events::origin_* constants)
    /// origin_id: Optional ID linking to source (e.g., launchpad pool ID)
    public fun create_governance_pool_admin<StakeToken>(
        registry: &mut StakingRegistry,
        _admin_cap: &AdminCap,
        min_stake_duration_ms: u64,
        early_unstake_fee_bps: u64,
        stake_fee_bps: u64,
        unstake_fee_bps: u64,
        origin: u8,
        origin_id: Option<ID>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): PoolAdminCap {
        // Check platform not paused
        assert!(!registry.paused, sui_staking::errors::platform_paused());

        // Create governance pool with specified origin
        let (pool, admin_cap) = pool::create_governance_pool<StakeToken>(
            min_stake_duration_ms,
            early_unstake_fee_bps,
            stake_fee_bps,
            unstake_fee_bps,
            origin,
            origin_id,
            clock,
            ctx,
        );

        let pool_id = pool::pool_id(&pool);
        let current_time = sui::clock::timestamp_ms(clock);

        // Get type name for metadata
        let stake_type = std::type_name::with_original_ids<StakeToken>();

        // Store metadata
        let metadata = PoolMetadata {
            creator: tx_context::sender(ctx),
            created_at_ms: current_time,
            stake_token_type: std::type_name::into_string(stake_type),
            reward_token_type: std::type_name::into_string(stake_type),
            governance_only: true,
            origin,
            origin_id,
        };

        vector::push_back(&mut registry.pool_ids, pool_id);
        table::add(&mut registry.pool_metadata, pool_id, metadata);
        registry.total_pools = registry.total_pools + 1;

        // Share the pool
        transfer::public_share_object(pool);

        admin_cap
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Update platform configuration
    public fun update_platform_config(
        registry: &mut StakingRegistry,
        _admin_cap: &AdminCap,
        setup_fee: u64,
        platform_fee_bps: u64,
        fee_recipient: address,
        ctx: &TxContext,
    ) {
        assert!(
            sui_staking::math::is_valid_platform_fee(platform_fee_bps),
            sui_staking::errors::fee_too_high(),
        );

        registry.config.setup_fee = setup_fee;
        registry.config.platform_fee_bps = platform_fee_bps;
        registry.config.fee_recipient = fee_recipient;

        events::emit_platform_config_updated(
            setup_fee,
            platform_fee_bps,
            tx_context::sender(ctx),
        );
    }

    /// Pause/unpause the platform
    public fun set_platform_paused(
        registry: &mut StakingRegistry,
        _admin_cap: &AdminCap,
        paused: bool,
    ) {
        registry.paused = paused;
    }

    /// Withdraw collected setup fees
    public fun withdraw_setup_fees(
        registry: &mut StakingRegistry,
        _admin_cap: &AdminCap,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        let amount = balance::value(&registry.collected_fees);
        assert!(amount > 0, sui_staking::errors::zero_amount());

        let fee_balance = balance::split(&mut registry.collected_fees, amount);
        coin::from_balance(fee_balance, ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun config(registry: &StakingRegistry): &PlatformConfig {
        &registry.config
    }

    public fun total_pools(registry: &StakingRegistry): u64 {
        registry.total_pools
    }

    public fun is_paused(registry: &StakingRegistry): bool {
        registry.paused
    }

    public fun collected_fees(registry: &StakingRegistry): u64 {
        balance::value(&registry.collected_fees)
    }

    public fun pool_ids(registry: &StakingRegistry): &vector<ID> {
        &registry.pool_ids
    }

    public fun pool_metadata(registry: &StakingRegistry, pool_id: ID): &PoolMetadata {
        table::borrow(&registry.pool_metadata, pool_id)
    }

    public fun has_pool(registry: &StakingRegistry, pool_id: ID): bool {
        table::contains(&registry.pool_metadata, pool_id)
    }

    // Config getters
    public fun get_setup_fee(config: &PlatformConfig): u64 { config.setup_fee }
    public fun get_platform_fee_bps(config: &PlatformConfig): u64 { config.platform_fee_bps }
    public fun get_fee_recipient(config: &PlatformConfig): address { config.fee_recipient }

    // Metadata getters
    public fun get_metadata_creator(metadata: &PoolMetadata): address { metadata.creator }
    public fun get_metadata_created_at_ms(metadata: &PoolMetadata): u64 { metadata.created_at_ms }
    public fun get_metadata_stake_token_type(metadata: &PoolMetadata): std::ascii::String { metadata.stake_token_type }
    public fun get_metadata_reward_token_type(metadata: &PoolMetadata): std::ascii::String { metadata.reward_token_type }
    public fun get_metadata_governance_only(metadata: &PoolMetadata): bool { metadata.governance_only }
    public fun get_metadata_origin(metadata: &PoolMetadata): u8 { metadata.origin }
    public fun get_metadata_origin_id(metadata: &PoolMetadata): Option<ID> { metadata.origin_id }

    /// Check if pool was created by launchpad
    public fun is_launchpad_pool(metadata: &PoolMetadata): bool {
        metadata.origin == events::origin_launchpad()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun create_registry_for_testing(ctx: &mut TxContext): (StakingRegistry, AdminCap) {
        let admin_cap = access::create_admin_cap(ctx);
        let sender = tx_context::sender(ctx);

        let registry = StakingRegistry {
            id: object::new(ctx),
            config: PlatformConfig {
                setup_fee: DEFAULT_SETUP_FEE,
                platform_fee_bps: DEFAULT_PLATFORM_FEE_BPS,
                fee_recipient: sender,
            },
            pool_ids: vector::empty(),
            pool_metadata: table::new(ctx),
            collected_fees: balance::zero(),
            total_pools: 0,
            paused: false,
        };

        (registry, admin_cap)
    }

    #[test_only]
    public fun destroy_registry_for_testing(registry: StakingRegistry) {
        let StakingRegistry {
            id,
            config: _,
            pool_ids: _,
            pool_metadata,
            collected_fees,
            total_pools: _,
            paused: _,
        } = registry;

        object::delete(id);
        table::drop(pool_metadata);
        balance::destroy_for_testing(collected_fees);
    }
}
