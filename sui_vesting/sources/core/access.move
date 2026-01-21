/// Access control capabilities for the vesting module
module sui_vesting::access {

    // ═══════════════════════════════════════════════════════════════════════
    // CAPABILITIES
    // ═══════════════════════════════════════════════════════════════════════

    /// Admin capability - can pause platform, revoke schedules
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Creator capability - issued to schedule creators for management
    public struct CreatorCap has key, store {
        id: UID,
        schedule_id: ID,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create admin capability (called during init)
    public fun create_admin_cap(ctx: &mut TxContext): AdminCap {
        AdminCap {
            id: object::new(ctx),
        }
    }

    /// Create creator capability for a schedule
    public fun create_creator_cap(schedule_id: ID, ctx: &mut TxContext): CreatorCap {
        CreatorCap {
            id: object::new(ctx),
            schedule_id,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get the schedule ID from creator cap
    public fun creator_cap_schedule_id(cap: &CreatorCap): ID {
        cap.schedule_id
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DESTRUCTOR FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Destroy creator cap (when schedule is fully claimed or revoked)
    public fun destroy_creator_cap(cap: CreatorCap) {
        let CreatorCap { id, schedule_id: _ } = cap;
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
    fun test_create_creator_cap() {
        let mut ctx = tx_context::dummy();
        let dummy_id = object::id_from_address(@0x123);
        let cap = create_creator_cap(dummy_id, &mut ctx);
        assert!(creator_cap_schedule_id(&cap) == dummy_id, 0);
        destroy_creator_cap(cap);
    }
}
