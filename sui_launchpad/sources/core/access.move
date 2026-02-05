/// Access control capabilities for the launchpad
module sui_launchpad::access {

    use sui::event;

    // ═══════════════════════════════════════════════════════════════════════
    // CAPABILITIES
    // ═══════════════════════════════════════════════════════════════════════

    /// Admin capability - grants full control over the launchpad
    /// Created once during init and should be kept secure
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Operator capability - grants limited operational control
    /// Can be created by admin for day-to-day operations
    public struct OperatorCap has key, store {
        id: UID,
    }

    /// Treasury capability - grants access to withdraw fees
    public struct TreasuryCap has key, store {
        id: UID,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct AdminCapCreated has copy, drop {
        admin_cap_id: ID,
        created_for: address,
    }

    public struct OperatorCapCreated has copy, drop {
        operator_cap_id: ID,
        created_by: address,
        created_for: address,
    }

    public struct OperatorCapRevoked has copy, drop {
        operator_cap_id: ID,
        revoked_by: address,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN CAP FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create AdminCap - should only be called in init
    /// This is a package-level function, not public entry
    public(package) fun create_admin_cap(ctx: &mut TxContext): AdminCap {
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };

        event::emit(AdminCapCreated {
            admin_cap_id: object::id(&admin_cap),
            created_for: ctx.sender(),
        });

        admin_cap
    }

    /// Get AdminCap ID
    public fun admin_cap_id(cap: &AdminCap): ID {
        object::id(cap)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OPERATOR CAP FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create OperatorCap - requires AdminCap
    public fun create_operator_cap(
        _admin: &AdminCap,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let operator_cap = OperatorCap {
            id: object::new(ctx),
        };

        event::emit(OperatorCapCreated {
            operator_cap_id: object::id(&operator_cap),
            created_by: ctx.sender(),
            created_for: recipient,
        });

        transfer::transfer(operator_cap, recipient);
    }

    /// Revoke OperatorCap - requires AdminCap
    public fun revoke_operator_cap(
        _admin: &AdminCap,
        operator_cap: OperatorCap,
        ctx: &TxContext
    ) {
        let OperatorCap { id } = operator_cap;

        event::emit(OperatorCapRevoked {
            operator_cap_id: id.to_inner(),
            revoked_by: ctx.sender(),
        });

        object::delete(id);
    }

    /// Get OperatorCap ID
    public fun operator_cap_id(cap: &OperatorCap): ID {
        object::id(cap)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TREASURY CAP FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create TreasuryCap - should only be called in init
    public(package) fun create_treasury_cap(ctx: &mut TxContext): TreasuryCap {
        TreasuryCap {
            id: object::new(ctx),
        }
    }

    /// Get TreasuryCap ID
    public fun treasury_cap_id(cap: &TreasuryCap): ID {
        object::id(cap)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Assert caller has admin capability (used for compile-time check)
    /// The AdminCap reference itself proves authorization
    public fun assert_admin(_admin: &AdminCap) {
        // Presence of AdminCap reference is sufficient proof
        // This function exists for explicit documentation
    }

    /// Assert caller has operator capability
    public fun assert_operator(_operator: &OperatorCap) {
        // Presence of OperatorCap reference is sufficient proof
    }

    /// Assert caller has treasury capability
    public fun assert_treasury(_treasury: &TreasuryCap) {
        // Presence of TreasuryCap reference is sufficient proof
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun create_admin_cap_for_testing(ctx: &mut TxContext): AdminCap {
        AdminCap {
            id: object::new(ctx),
        }
    }

    #[test_only]
    public fun destroy_admin_cap_for_testing(cap: AdminCap) {
        let AdminCap { id } = cap;
        object::delete(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_admin_cap() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        // Create admin cap
        {
            let ctx = scenario.ctx();
            let admin_cap = create_admin_cap(ctx);
            transfer::public_transfer(admin_cap, admin);
        };

        // Verify admin cap exists
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            assert!(object::id(&admin_cap) != object::id_from_address(@0x0), 0);
            scenario.return_to_sender(admin_cap);
        };

        scenario.end();
    }

    #[test]
    fun test_create_operator_cap() {
        use sui::test_scenario;

        let admin = @0xAD;
        let operator = @0x0B;
        let mut scenario = test_scenario::begin(admin);

        // Create admin cap
        {
            let ctx = scenario.ctx();
            let admin_cap = create_admin_cap(ctx);
            transfer::public_transfer(admin_cap, admin);
        };

        // Admin creates operator cap
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<AdminCap>();
            create_operator_cap(&admin_cap, operator, scenario.ctx());
            scenario.return_to_sender(admin_cap);
        };

        // Verify operator cap exists
        scenario.next_tx(operator);
        {
            let operator_cap = scenario.take_from_sender<OperatorCap>();
            assert!(object::id(&operator_cap) != object::id_from_address(@0x0), 0);
            scenario.return_to_sender(operator_cap);
        };

        scenario.end();
    }
}
