/// Access control capabilities for the staking module
module sui_staking::access {

    // ═══════════════════════════════════════════════════════════════════════
    // CAPABILITIES
    // ═══════════════════════════════════════════════════════════════════════

    /// Platform admin capability - can pause platform, update fees
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Pool admin capability - issued to pool creators for pool management
    public struct PoolAdminCap has key, store {
        id: UID,
        pool_id: ID,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create platform admin capability (called during init)
    public fun create_admin_cap(ctx: &mut TxContext): AdminCap {
        AdminCap {
            id: object::new(ctx),
        }
    }

    /// Create pool admin capability for a pool
    public fun create_pool_admin_cap(pool_id: ID, ctx: &mut TxContext): PoolAdminCap {
        PoolAdminCap {
            id: object::new(ctx),
            pool_id,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get the pool ID from pool admin cap
    public fun pool_admin_cap_pool_id(cap: &PoolAdminCap): ID {
        cap.pool_id
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DESTRUCTOR FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Destroy pool admin cap (when pool is closed)
    public fun destroy_pool_admin_cap(cap: PoolAdminCap) {
        let PoolAdminCap { id, pool_id: _ } = cap;
        object::delete(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_admin_cap() {
        let mut ctx = tx_context::dummy();
        let cap = create_admin_cap(&mut ctx);
        transfer::public_transfer(cap, @0x1);
    }

    #[test]
    fun test_create_pool_admin_cap() {
        let mut ctx = tx_context::dummy();
        let dummy_id = object::id_from_address(@0x123);
        let cap = create_pool_admin_cap(dummy_id, &mut ctx);
        assert!(pool_admin_cap_pool_id(&cap) == dummy_id, 0);
        destroy_pool_admin_cap(cap);
    }
}
