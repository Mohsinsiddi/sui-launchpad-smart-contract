/// Token registry for pool discovery and tracking
/// Provides lookup by token type, creator, and global listing
module sui_launchpad::registry {

    use std::type_name::{Self, TypeName};
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use sui::event;

    use sui_launchpad::access::AdminCap;
    use sui_launchpad::bonding_curve::BondingPool;

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    const EPoolAlreadyRegistered: u64 = 200;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Global registry - shared object for pool discovery
    public struct Registry has key, store {
        id: UID,

        /// All pool IDs (for iteration)
        all_pools: vector<ID>,

        /// Lookup: token type -> pool ID
        pools_by_type: Table<TypeName, ID>,

        /// Lookup: creator address -> pool IDs
        pools_by_creator: Table<address, VecSet<ID>>,

        /// Total tokens launched
        total_tokens: u64,

        /// Total graduated tokens
        total_graduated: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct PoolRegistered has copy, drop {
        pool_id: ID,
        token_type: TypeName,
        creator: address,
        total_tokens: u64,
    }

    public struct PoolGraduationRecorded has copy, drop {
        pool_id: ID,
        dex_type: u8,
        dex_pool_id: ID,
        total_graduated: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create and share the registry - called during package init
    public(package) fun create_registry(ctx: &mut TxContext): Registry {
        Registry {
            id: object::new(ctx),
            all_pools: vector::empty(),
            pools_by_type: table::new(ctx),
            pools_by_creator: table::new(ctx),
            total_tokens: 0,
            total_graduated: 0,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REGISTRATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Register a new pool in the registry
    /// Called by bonding_curve module after pool creation
    public(package) fun register_pool<T>(
        registry: &mut Registry,
        pool: &BondingPool<T>,
        ctx: &TxContext,
    ) {
        let token_type = type_name::with_original_ids<T>();
        let pool_id = object::id(pool);
        let creator = ctx.sender();

        // Ensure not already registered
        assert!(!table::contains(&registry.pools_by_type, token_type), EPoolAlreadyRegistered);

        // Add to all pools list
        vector::push_back(&mut registry.all_pools, pool_id);

        // Add to type lookup
        table::add(&mut registry.pools_by_type, token_type, pool_id);

        // Add to creator lookup
        if (!table::contains(&registry.pools_by_creator, creator)) {
            table::add(&mut registry.pools_by_creator, creator, vec_set::empty());
        };
        let creator_pools = table::borrow_mut(&mut registry.pools_by_creator, creator);
        vec_set::insert(creator_pools, pool_id);

        // Increment counter
        registry.total_tokens = registry.total_tokens + 1;

        // Emit event
        event::emit(PoolRegistered {
            pool_id,
            token_type,
            creator,
            total_tokens: registry.total_tokens,
        });
    }

    /// Record graduation of a pool
    /// Called by graduation module after successful DEX migration
    public(package) fun record_graduation(
        registry: &mut Registry,
        pool_id: ID,
        dex_type: u8,
        dex_pool_id: ID,
    ) {
        registry.total_graduated = registry.total_graduated + 1;

        event::emit(PoolGraduationRecorded {
            pool_id,
            dex_type,
            dex_pool_id,
            total_graduated: registry.total_graduated,
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LOOKUP FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get pool ID by token type
    public fun get_pool_by_type<T>(registry: &Registry): Option<ID> {
        let token_type = type_name::with_original_ids<T>();
        if (table::contains(&registry.pools_by_type, token_type)) {
            option::some(*table::borrow(&registry.pools_by_type, token_type))
        } else {
            option::none()
        }
    }

    /// Check if a token type is registered
    public fun is_registered<T>(registry: &Registry): bool {
        let token_type = type_name::with_original_ids<T>();
        table::contains(&registry.pools_by_type, token_type)
    }

    /// Get pools created by an address
    public fun get_pools_by_creator(registry: &Registry, creator: address): vector<ID> {
        if (table::contains(&registry.pools_by_creator, creator)) {
            vec_set::into_keys(*table::borrow(&registry.pools_by_creator, creator))
        } else {
            vector::empty()
        }
    }

    /// Get pool count for a creator
    public fun get_creator_pool_count(registry: &Registry, creator: address): u64 {
        if (table::contains(&registry.pools_by_creator, creator)) {
            vec_set::length(table::borrow(&registry.pools_by_creator, creator))
        } else {
            0
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get total number of tokens launched
    public fun total_tokens(registry: &Registry): u64 {
        registry.total_tokens
    }

    /// Get total number of graduated tokens
    public fun total_graduated(registry: &Registry): u64 {
        registry.total_graduated
    }

    /// Get all pool IDs (paginated view)
    public fun get_pools(registry: &Registry, start: u64, limit: u64): vector<ID> {
        let len = vector::length(&registry.all_pools);
        let end = if (start + limit > len) { len } else { start + limit };

        let mut result = vector::empty();
        let mut i = start;
        while (i < end) {
            vector::push_back(&mut result, *vector::borrow(&registry.all_pools, i));
            i = i + 1;
        };
        result
    }

    /// Get total pool count
    public fun pool_count(registry: &Registry): u64 {
        vector::length(&registry.all_pools)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Remove a pool from registry (admin only, for cleanup)
    public fun remove_pool<T>(
        _admin: &AdminCap,
        registry: &mut Registry,
        pool_id: ID,
        creator: address,
    ) {
        let token_type = type_name::with_original_ids<T>();

        // Remove from type lookup
        if (table::contains(&registry.pools_by_type, token_type)) {
            table::remove(&mut registry.pools_by_type, token_type);
        };

        // Remove from creator lookup
        if (table::contains(&registry.pools_by_creator, creator)) {
            let creator_pools = table::borrow_mut(&mut registry.pools_by_creator, creator);
            if (vec_set::contains(creator_pools, &pool_id)) {
                vec_set::remove(creator_pools, &pool_id);
            };
        };

        // Remove from all pools list (linear search, but rare operation)
        let len = vector::length(&registry.all_pools);
        let mut i = 0;
        while (i < len) {
            if (*vector::borrow(&registry.all_pools, i) == pool_id) {
                vector::remove(&mut registry.all_pools, i);
                break
            };
            i = i + 1;
        };

        // Decrement counter
        if (registry.total_tokens > 0) {
            registry.total_tokens = registry.total_tokens - 1;
        };
    }
}
