/// Operator Registry - Role-based access control for launchpad operations
///
/// Provides a flexible operator system for dashboard/multi-admin UX:
/// - Super admins can do everything + manage operators
/// - Graduation operators can graduate pools
/// - Fee operators can update platform fees
/// - Pause operators can pause/unpause platform or pools
/// - Treasury operators can withdraw collected fees
///
/// Usage from dashboard:
/// 1. Super admin adds operators for specific roles
/// 2. Operators sign transactions directly from dashboard
/// 3. No capability transfer needed - just address-based checks
module sui_launchpad::operators {
    use sui::vec_set::{Self, VecSet};
    use sui::event;

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    const ENotSuperAdmin: u64 = 700;
    const ENotGraduationOperator: u64 = 701;
    const ENotFeeOperator: u64 = 702;
    const ENotPauseOperator: u64 = 703;
    const ENotTreasuryOperator: u64 = 704;
    const EInvalidRole: u64 = 705;
    const EOperatorAlreadyExists: u64 = 706;
    const EOperatorNotFound: u64 = 707;
    const ECannotRemoveLastSuperAdmin: u64 = 708;

    // ═══════════════════════════════════════════════════════════════════════
    // ROLE CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Super admin - can do everything + manage operators
    const ROLE_SUPER_ADMIN: u8 = 0;
    /// Graduation operator - can graduate pools, create staking/DAO
    const ROLE_GRADUATION: u8 = 1;
    /// Fee operator - can update platform fees
    const ROLE_FEE: u8 = 2;
    /// Pause operator - can pause/unpause platform or pools
    const ROLE_PAUSE: u8 = 3;
    /// Treasury operator - can withdraw collected fees
    const ROLE_TREASURY: u8 = 4;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Global operator registry - shared object
    /// Manages role-based access for all launchpad operations
    public struct OperatorRegistry has key, store {
        id: UID,
        /// Super admins - full access + can manage operators
        super_admins: VecSet<address>,
        /// Graduation operators - can graduate pools
        graduation_operators: VecSet<address>,
        /// Fee operators - can update fees
        fee_operators: VecSet<address>,
        /// Pause operators - can pause/unpause
        pause_operators: VecSet<address>,
        /// Treasury operators - can withdraw fees
        treasury_operators: VecSet<address>,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct OperatorAdded has copy, drop {
        operator: address,
        role: u8,
        added_by: address,
    }

    public struct OperatorRemoved has copy, drop {
        operator: address,
        role: u8,
        removed_by: address,
    }


    // ═══════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create operator registry - called during package init
    /// Deployer becomes the first super admin
    public(package) fun create_registry(ctx: &mut TxContext): OperatorRegistry {
        let sender = ctx.sender();

        OperatorRegistry {
            id: object::new(ctx),
            super_admins: vec_set::singleton(sender),
            graduation_operators: vec_set::empty(),
            fee_operators: vec_set::empty(),
            pause_operators: vec_set::empty(),
            treasury_operators: vec_set::empty(),
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OPERATOR MANAGEMENT (Super Admin Only)
    // ═══════════════════════════════════════════════════════════════════════

    /// Add an operator for a specific role
    /// Only super admins can add operators
    public fun add_operator(
        registry: &mut OperatorRegistry,
        operator: address,
        role: u8,
        ctx: &TxContext,
    ) {
        let sender = ctx.sender();
        assert_super_admin(registry, sender);
        assert!(role <= ROLE_TREASURY, EInvalidRole);

        let set = get_role_set_mut(registry, role);
        assert!(!vec_set::contains(set, &operator), EOperatorAlreadyExists);
        vec_set::insert(set, operator);

        event::emit(OperatorAdded {
            operator,
            role,
            added_by: sender,
        });
    }

    /// Remove an operator from a specific role
    /// Only super admins can remove operators
    public fun remove_operator(
        registry: &mut OperatorRegistry,
        operator: address,
        role: u8,
        ctx: &TxContext,
    ) {
        let sender = ctx.sender();
        assert_super_admin(registry, sender);
        assert!(role <= ROLE_TREASURY, EInvalidRole);

        // Prevent removing the last super admin
        if (role == ROLE_SUPER_ADMIN) {
            assert!(vec_set::length(&registry.super_admins) > 1, ECannotRemoveLastSuperAdmin);
        };

        let set = get_role_set_mut(registry, role);
        assert!(vec_set::contains(set, &operator), EOperatorNotFound);
        vec_set::remove(set, &operator);

        event::emit(OperatorRemoved {
            operator,
            role,
            removed_by: sender,
        });
    }

    /// Add a new super admin
    /// Only existing super admins can add new super admins
    public fun add_super_admin(
        registry: &mut OperatorRegistry,
        new_admin: address,
        ctx: &TxContext,
    ) {
        add_operator(registry, new_admin, ROLE_SUPER_ADMIN, ctx);
    }

    /// Remove a super admin
    /// Cannot remove the last super admin
    public fun remove_super_admin(
        registry: &mut OperatorRegistry,
        admin: address,
        ctx: &TxContext,
    ) {
        remove_operator(registry, admin, ROLE_SUPER_ADMIN, ctx);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ROLE CHECK FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Check if address is a super admin
    public fun is_super_admin(registry: &OperatorRegistry, addr: address): bool {
        vec_set::contains(&registry.super_admins, &addr)
    }

    /// Check if address is a graduation operator (or super admin)
    public fun is_graduation_operator(registry: &OperatorRegistry, addr: address): bool {
        is_super_admin(registry, addr) ||
        vec_set::contains(&registry.graduation_operators, &addr)
    }

    /// Check if address is a fee operator (or super admin)
    public fun is_fee_operator(registry: &OperatorRegistry, addr: address): bool {
        is_super_admin(registry, addr) ||
        vec_set::contains(&registry.fee_operators, &addr)
    }

    /// Check if address is a pause operator (or super admin)
    public fun is_pause_operator(registry: &OperatorRegistry, addr: address): bool {
        is_super_admin(registry, addr) ||
        vec_set::contains(&registry.pause_operators, &addr)
    }

    /// Check if address is a treasury operator (or super admin)
    public fun is_treasury_operator(registry: &OperatorRegistry, addr: address): bool {
        is_super_admin(registry, addr) ||
        vec_set::contains(&registry.treasury_operators, &addr)
    }

    /// Check if address has a specific role (or is super admin)
    public fun has_role(registry: &OperatorRegistry, addr: address, role: u8): bool {
        if (role == ROLE_SUPER_ADMIN) {
            is_super_admin(registry, addr)
        } else if (role == ROLE_GRADUATION) {
            is_graduation_operator(registry, addr)
        } else if (role == ROLE_FEE) {
            is_fee_operator(registry, addr)
        } else if (role == ROLE_PAUSE) {
            is_pause_operator(registry, addr)
        } else if (role == ROLE_TREASURY) {
            is_treasury_operator(registry, addr)
        } else {
            false
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ASSERTION FUNCTIONS (for use in other modules)
    // ═══════════════════════════════════════════════════════════════════════

    /// Assert caller is a super admin
    public fun assert_super_admin(registry: &OperatorRegistry, addr: address) {
        assert!(is_super_admin(registry, addr), ENotSuperAdmin);
    }

    /// Assert caller is a graduation operator
    public fun assert_graduation_operator(registry: &OperatorRegistry, addr: address) {
        assert!(is_graduation_operator(registry, addr), ENotGraduationOperator);
    }

    /// Assert caller is a fee operator
    public fun assert_fee_operator(registry: &OperatorRegistry, addr: address) {
        assert!(is_fee_operator(registry, addr), ENotFeeOperator);
    }

    /// Assert caller is a pause operator
    public fun assert_pause_operator(registry: &OperatorRegistry, addr: address) {
        assert!(is_pause_operator(registry, addr), ENotPauseOperator);
    }

    /// Assert caller is a treasury operator
    public fun assert_treasury_operator(registry: &OperatorRegistry, addr: address) {
        assert!(is_treasury_operator(registry, addr), ENotTreasuryOperator);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get all super admins
    public fun get_super_admins(registry: &OperatorRegistry): vector<address> {
        vec_set::into_keys(registry.super_admins)
    }

    /// Get all graduation operators
    public fun get_graduation_operators(registry: &OperatorRegistry): vector<address> {
        vec_set::into_keys(registry.graduation_operators)
    }

    /// Get all fee operators
    public fun get_fee_operators(registry: &OperatorRegistry): vector<address> {
        vec_set::into_keys(registry.fee_operators)
    }

    /// Get all pause operators
    public fun get_pause_operators(registry: &OperatorRegistry): vector<address> {
        vec_set::into_keys(registry.pause_operators)
    }

    /// Get all treasury operators
    public fun get_treasury_operators(registry: &OperatorRegistry): vector<address> {
        vec_set::into_keys(registry.treasury_operators)
    }

    /// Get count of operators for a role
    public fun get_operator_count(registry: &OperatorRegistry, role: u8): u64 {
        if (role == ROLE_SUPER_ADMIN) {
            vec_set::length(&registry.super_admins)
        } else if (role == ROLE_GRADUATION) {
            vec_set::length(&registry.graduation_operators)
        } else if (role == ROLE_FEE) {
            vec_set::length(&registry.fee_operators)
        } else if (role == ROLE_PAUSE) {
            vec_set::length(&registry.pause_operators)
        } else if (role == ROLE_TREASURY) {
            vec_set::length(&registry.treasury_operators)
        } else {
            0
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ROLE CONSTANT GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun role_super_admin(): u8 { ROLE_SUPER_ADMIN }
    public fun role_graduation(): u8 { ROLE_GRADUATION }
    public fun role_fee(): u8 { ROLE_FEE }
    public fun role_pause(): u8 { ROLE_PAUSE }
    public fun role_treasury(): u8 { ROLE_TREASURY }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get mutable reference to the VecSet for a role
    fun get_role_set_mut(registry: &mut OperatorRegistry, role: u8): &mut VecSet<address> {
        if (role == ROLE_SUPER_ADMIN) {
            &mut registry.super_admins
        } else if (role == ROLE_GRADUATION) {
            &mut registry.graduation_operators
        } else if (role == ROLE_FEE) {
            &mut registry.fee_operators
        } else if (role == ROLE_PAUSE) {
            &mut registry.pause_operators
        } else {
            &mut registry.treasury_operators
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun create_registry_for_testing(ctx: &mut TxContext): OperatorRegistry {
        create_registry(ctx)
    }

    #[test_only]
    public fun destroy_registry_for_testing(registry: OperatorRegistry) {
        let OperatorRegistry {
            id,
            super_admins: _,
            graduation_operators: _,
            fee_operators: _,
            pause_operators: _,
            treasury_operators: _,
        } = registry;
        object::delete(id);
    }
}
