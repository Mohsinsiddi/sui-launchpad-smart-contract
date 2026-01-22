/// Guardian module - Emergency pause capability for DAO governance
///
/// The Guardian is a trusted address that can pause the DAO in emergencies.
/// Unlike the admin, the guardian has limited powers:
/// - Can emergency pause the governance
/// - Cannot unpause (only admin can unpause)
/// - Cannot modify configuration
///
/// This provides a safety mechanism where a security-focused entity (like a
/// multisig or security council) can halt operations if a vulnerability is found.
module sui_dao::guardian {
    use sui_dao::access::DAOAdminCap;
    use sui_dao::errors;
    use sui_dao::events;
    use sui_dao::governance::{Self, Governance};

    // ═══════════════════════════════════════════════════════════════════════
    // GUARDIAN MANAGEMENT (Admin Only)
    // ═══════════════════════════════════════════════════════════════════════

    /// Set a guardian for the governance (admin only)
    public fun set_guardian(
        admin_cap: &DAOAdminCap,
        governance: &mut Governance,
        guardian: address,
        ctx: &TxContext,
    ) {
        sui_dao::access::assert_dao_admin_cap_matches(admin_cap, object::id(governance));

        // Check if already has the same guardian
        let current_guardian = governance::guardian(governance);
        if (current_guardian.is_some()) {
            assert!(*current_guardian.borrow() != guardian, errors::already_guardian());
        };

        governance::set_guardian_internal(governance, guardian);

        events::emit_guardian_set(
            object::id(governance),
            guardian,
            ctx.sender(),
        );
    }

    /// Remove the guardian (admin only)
    public fun remove_guardian(
        admin_cap: &DAOAdminCap,
        governance: &mut Governance,
        ctx: &TxContext,
    ) {
        sui_dao::access::assert_dao_admin_cap_matches(admin_cap, object::id(governance));

        let current_guardian = governance::guardian(governance);
        assert!(current_guardian.is_some(), errors::guardian_not_set());

        let old_guardian = *current_guardian.borrow();
        governance::remove_guardian_internal(governance);

        events::emit_guardian_removed(
            object::id(governance),
            old_guardian,
            ctx.sender(),
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMERGENCY PAUSE (Guardian Only)
    // ═══════════════════════════════════════════════════════════════════════

    /// Emergency pause the governance (guardian only)
    /// Note: Only admin can unpause after guardian pauses
    public fun emergency_pause(
        governance: &mut Governance,
        ctx: &TxContext,
    ) {
        let guardian_opt = governance::guardian(governance);
        assert!(guardian_opt.is_some(), errors::guardian_not_set());

        let guardian = *guardian_opt.borrow();
        assert!(ctx.sender() == guardian, errors::not_guardian());

        // Pause the governance
        governance::pause_by_guardian(governance);

        events::emit_emergency_pause_by_guardian(
            object::id(governance),
            guardian,
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Check if governance has a guardian set
    public fun has_guardian(governance: &Governance): bool {
        governance::guardian(governance).is_some()
    }

    /// Get the guardian address if set
    public fun get_guardian(governance: &Governance): Option<address> {
        governance::guardian(governance)
    }

    /// Check if address is the guardian
    public fun is_guardian(governance: &Governance, addr: address): bool {
        let guardian_opt = governance::guardian(governance);
        guardian_opt.is_some() && *guardian_opt.borrow() == addr
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_has_guardian() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let staking_pool_id = object::id_from_address(@0x123);

        let mut governance = governance::create_governance_for_testing(
            std::string::utf8(b"Test DAO"),
            staking_pool_id,
            &clock,
            &mut ctx,
        );

        // No guardian initially
        assert!(!has_guardian(&governance), 0);

        // Set guardian
        governance::set_guardian_internal(&mut governance, @0xABC);
        assert!(has_guardian(&governance), 1);
        assert!(is_guardian(&governance, @0xABC), 2);
        assert!(!is_guardian(&governance, @0xDEF), 3);

        // Remove guardian
        governance::remove_guardian_internal(&mut governance);
        assert!(!has_guardian(&governance), 4);

        governance::destroy_governance_for_testing(governance);
        sui::clock::destroy_for_testing(clock);
    }
}
