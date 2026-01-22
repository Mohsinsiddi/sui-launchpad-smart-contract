/// Access control capabilities for the multisig module
module sui_multisig::access {

    // ═══════════════════════════════════════════════════════════════════════
    // CAPABILITIES
    // ═══════════════════════════════════════════════════════════════════════

    /// Platform admin capability - can pause platform, update fees
    public struct AdminCap has key, store {
        id: UID,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create platform admin capability (called during init)
    public(package) fun create_admin_cap(ctx: &mut TxContext): AdminCap {
        AdminCap {
            id: object::new(ctx),
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun create_admin_cap_for_testing(ctx: &mut TxContext): AdminCap {
        create_admin_cap(ctx)
    }

    #[test_only]
    public fun destroy_admin_cap_for_testing(cap: AdminCap) {
        let AdminCap { id } = cap;
        object::delete(id);
    }
}
