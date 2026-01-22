/// Access control capabilities for the DAO module
module sui_dao::access {
    // ═══════════════════════════════════════════════════════════════════════
    // PLATFORM ADMIN CAP
    // ═══════════════════════════════════════════════════════════════════════

    /// Platform admin capability - controls platform-wide settings
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Create a new admin cap (called during init)
    public(package) fun create_admin_cap(ctx: &mut TxContext): AdminCap {
        AdminCap {
            id: object::new(ctx),
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DAO ADMIN CAP
    // ═══════════════════════════════════════════════════════════════════════

    /// DAO admin capability - controls a specific governance instance
    public struct DAOAdminCap has key, store {
        id: UID,
        /// The governance this cap controls
        governance_id: ID,
    }

    /// Create a new DAO admin cap
    public(package) fun create_dao_admin_cap(
        governance_id: ID,
        ctx: &mut TxContext,
    ): DAOAdminCap {
        DAOAdminCap {
            id: object::new(ctx),
            governance_id,
        }
    }

    /// Get the governance ID this cap controls
    public fun dao_admin_cap_governance_id(cap: &DAOAdminCap): ID {
        cap.governance_id
    }

    /// Verify cap matches governance
    public fun assert_dao_admin_cap_matches(cap: &DAOAdminCap, governance_id: ID) {
        assert!(cap.governance_id == governance_id, sui_dao::errors::not_dao_admin());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COUNCIL CAP
    // ═══════════════════════════════════════════════════════════════════════

    /// Council member capability - grants council powers for a specific governance
    public struct CouncilCap has key, store {
        id: UID,
        /// The governance this cap belongs to
        governance_id: ID,
        /// The council member address
        member: address,
    }

    /// Create a new council cap
    public(package) fun create_council_cap(
        governance_id: ID,
        member: address,
        ctx: &mut TxContext,
    ): CouncilCap {
        CouncilCap {
            id: object::new(ctx),
            governance_id,
            member,
        }
    }

    /// Get the governance ID
    public fun council_cap_governance_id(cap: &CouncilCap): ID {
        cap.governance_id
    }

    /// Get the council member address
    public fun council_cap_member(cap: &CouncilCap): address {
        cap.member
    }

    /// Verify cap matches governance
    public fun assert_council_cap_matches(cap: &CouncilCap, governance_id: ID) {
        assert!(cap.governance_id == governance_id, sui_dao::errors::wrong_governance());
    }

    /// Destroy a council cap (when member is removed)
    public(package) fun destroy_council_cap(cap: CouncilCap) {
        let CouncilCap { id, governance_id: _, member: _ } = cap;
        object::delete(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun destroy_admin_cap_for_testing(cap: AdminCap) {
        let AdminCap { id } = cap;
        object::delete(id);
    }

    #[test_only]
    public fun destroy_dao_admin_cap_for_testing(cap: DAOAdminCap) {
        let DAOAdminCap { id, governance_id: _ } = cap;
        object::delete(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_admin_cap() {
        let mut ctx = tx_context::dummy();
        let admin_cap = create_admin_cap(&mut ctx);

        let AdminCap { id } = admin_cap;
        object::delete(id);
    }

    #[test]
    fun test_create_dao_admin_cap() {
        let mut ctx = tx_context::dummy();
        let governance_id = object::id_from_address(@0x123);

        let dao_admin_cap = create_dao_admin_cap(governance_id, &mut ctx);

        assert!(dao_admin_cap_governance_id(&dao_admin_cap) == governance_id, 0);

        let DAOAdminCap { id, governance_id: _ } = dao_admin_cap;
        object::delete(id);
    }

    #[test]
    fun test_create_council_cap() {
        let mut ctx = tx_context::dummy();
        let governance_id = object::id_from_address(@0x123);
        let member = @0xABC;

        let council_cap = create_council_cap(governance_id, member, &mut ctx);

        assert!(council_cap_governance_id(&council_cap) == governance_id, 0);
        assert!(council_cap_member(&council_cap) == member, 1);

        destroy_council_cap(council_cap);
    }
}
