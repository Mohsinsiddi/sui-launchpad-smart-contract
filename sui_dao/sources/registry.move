/// Registry and platform configuration for DAO
module sui_dao::registry {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::vec_set::{Self, VecSet};
    use sui_dao::access::{Self, AdminCap};
    use sui_dao::events;
    use sui_dao::errors;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Default DAO creation fee: 50 SUI
    const DEFAULT_DAO_CREATION_FEE: u64 = 50_000_000_000;

    /// Default proposal fee: 1 SUI
    const DEFAULT_PROPOSAL_FEE: u64 = 1_000_000_000;

    /// Default execution fee: 0.1 SUI
    const DEFAULT_EXECUTION_FEE: u64 = 100_000_000;

    /// Default treasury addon fee: 10 SUI
    const DEFAULT_TREASURY_FEE: u64 = 10_000_000_000;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// One-time witness for module initialization
    public struct REGISTRY has drop {}

    /// Platform configuration and fee collection
    public struct DAORegistry has key {
        id: UID,
        /// Platform paused state
        paused: bool,
        /// Fee for creating a new DAO
        dao_creation_fee: u64,
        /// Additional fee for treasury addon
        treasury_fee: u64,
        /// Fee for creating proposals (anti-spam)
        proposal_fee: u64,
        /// Fee for executing proposals
        execution_fee: u64,
        /// Collected fees balance
        collected_fees: Balance<SUI>,
        /// All registered governance IDs
        governance_ids: VecSet<ID>,
        /// Total DAOs created
        total_daos_created: u64,
        /// Total proposals created across all DAOs
        total_proposals_created: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INIT
    // ═══════════════════════════════════════════════════════════════════════

    fun init(_witness: REGISTRY, ctx: &mut TxContext) {
        let admin_cap = access::create_admin_cap(ctx);
        let admin = ctx.sender();

        let registry = DAORegistry {
            id: object::new(ctx),
            paused: false,
            dao_creation_fee: DEFAULT_DAO_CREATION_FEE,
            treasury_fee: DEFAULT_TREASURY_FEE,
            proposal_fee: DEFAULT_PROPOSAL_FEE,
            execution_fee: DEFAULT_EXECUTION_FEE,
            collected_fees: balance::zero(),
            governance_ids: vec_set::empty(),
            total_daos_created: 0,
            total_proposals_created: 0,
        };

        events::emit_platform_initialized(object::id(&registry), admin);

        transfer::share_object(registry);
        transfer::public_transfer(admin_cap, admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Update platform configuration
    public fun update_config(
        _admin_cap: &AdminCap,
        registry: &mut DAORegistry,
        dao_creation_fee: u64,
        treasury_fee: u64,
        proposal_fee: u64,
        execution_fee: u64,
    ) {
        registry.dao_creation_fee = dao_creation_fee;
        registry.treasury_fee = treasury_fee;
        registry.proposal_fee = proposal_fee;
        registry.execution_fee = execution_fee;

        events::emit_platform_config_updated(
            object::id(registry),
            dao_creation_fee,
            proposal_fee,
            execution_fee,
        );
    }

    /// Pause the platform
    public fun pause(_admin_cap: &AdminCap, registry: &mut DAORegistry) {
        registry.paused = true;
        events::emit_platform_paused(object::id(registry));
    }

    /// Unpause the platform
    public fun unpause(_admin_cap: &AdminCap, registry: &mut DAORegistry) {
        registry.paused = false;
        events::emit_platform_unpaused(object::id(registry));
    }

    /// Withdraw collected fees
    public fun withdraw_fees(
        _admin_cap: &AdminCap,
        registry: &mut DAORegistry,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        assert!(amount > 0, errors::zero_amount());
        let fee_balance = registry.collected_fees.split(amount);
        let fee_coin = coin::from_balance(fee_balance, ctx);

        events::emit_fees_collected(object::id(registry), amount, recipient);

        transfer::public_transfer(fee_coin, recipient);
    }

    /// Withdraw all collected fees
    public fun withdraw_all_fees(
        _admin_cap: &AdminCap,
        registry: &mut DAORegistry,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        let amount = registry.collected_fees.value();
        if (amount > 0) {
            withdraw_fees(_admin_cap, registry, amount, recipient, ctx);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PACKAGE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Check platform is not paused
    public(package) fun assert_not_paused(registry: &DAORegistry) {
        assert!(!registry.paused, errors::platform_paused());
    }

    /// Collect DAO creation fee
    public(package) fun collect_dao_creation_fee(
        registry: &mut DAORegistry,
        payment: Coin<SUI>,
        with_treasury: bool,
    ) {
        let required = if (with_treasury) {
            registry.dao_creation_fee + registry.treasury_fee
        } else {
            registry.dao_creation_fee
        };

        assert!(payment.value() >= required, errors::insufficient_fee());

        registry.collected_fees.join(payment.into_balance());
    }

    /// Collect proposal fee
    public(package) fun collect_proposal_fee(
        registry: &mut DAORegistry,
        payment: Coin<SUI>,
    ) {
        assert!(payment.value() >= registry.proposal_fee, errors::insufficient_fee());
        registry.collected_fees.join(payment.into_balance());
    }

    /// Collect execution fee
    public(package) fun collect_execution_fee(
        registry: &mut DAORegistry,
        payment: Coin<SUI>,
    ) {
        assert!(payment.value() >= registry.execution_fee, errors::insufficient_fee());
        registry.collected_fees.join(payment.into_balance());
    }

    /// Register a new governance
    public(package) fun register_governance(
        registry: &mut DAORegistry,
        governance_id: ID,
    ) {
        registry.governance_ids.insert(governance_id);
        registry.total_daos_created = registry.total_daos_created + 1;
    }

    /// Increment total proposals counter
    public(package) fun increment_proposals(registry: &mut DAORegistry) {
        registry.total_proposals_created = registry.total_proposals_created + 1;
    }

    /// Check if governance is registered
    public(package) fun is_governance_registered(registry: &DAORegistry, governance_id: ID): bool {
        registry.governance_ids.contains(&governance_id)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    public fun is_paused(registry: &DAORegistry): bool {
        registry.paused
    }

    public fun dao_creation_fee(registry: &DAORegistry): u64 {
        registry.dao_creation_fee
    }

    public fun treasury_fee(registry: &DAORegistry): u64 {
        registry.treasury_fee
    }

    public fun proposal_fee(registry: &DAORegistry): u64 {
        registry.proposal_fee
    }

    public fun execution_fee(registry: &DAORegistry): u64 {
        registry.execution_fee
    }

    public fun collected_fees_balance(registry: &DAORegistry): u64 {
        registry.collected_fees.value()
    }

    public fun total_daos_created(registry: &DAORegistry): u64 {
        registry.total_daos_created
    }

    public fun total_proposals_created(registry: &DAORegistry): u64 {
        registry.total_proposals_created
    }

    public fun governance_count(registry: &DAORegistry): u64 {
        registry.governance_ids.length()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(REGISTRY {}, ctx);
    }

    #[test_only]
    public fun create_registry_for_testing(ctx: &mut TxContext): DAORegistry {
        DAORegistry {
            id: object::new(ctx),
            paused: false,
            dao_creation_fee: DEFAULT_DAO_CREATION_FEE,
            treasury_fee: DEFAULT_TREASURY_FEE,
            proposal_fee: DEFAULT_PROPOSAL_FEE,
            execution_fee: DEFAULT_EXECUTION_FEE,
            collected_fees: balance::zero(),
            governance_ids: vec_set::empty(),
            total_daos_created: 0,
            total_proposals_created: 0,
        }
    }

    #[test_only]
    public fun destroy_registry_for_testing(registry: DAORegistry) {
        let DAORegistry {
            id,
            paused: _,
            dao_creation_fee: _,
            treasury_fee: _,
            proposal_fee: _,
            execution_fee: _,
            collected_fees,
            governance_ids: _,
            total_daos_created: _,
            total_proposals_created: _,
        } = registry;
        object::delete(id);
        balance::destroy_for_testing(collected_fees);
    }

    #[test]
    fun test_registry_creation() {
        let mut ctx = tx_context::dummy();
        let registry = create_registry_for_testing(&mut ctx);

        assert!(registry.paused == false, 0);
        assert!(registry.dao_creation_fee == DEFAULT_DAO_CREATION_FEE, 1);
        assert!(registry.proposal_fee == DEFAULT_PROPOSAL_FEE, 2);
        assert!(registry.execution_fee == DEFAULT_EXECUTION_FEE, 3);
        assert!(registry.total_daos_created == 0, 4);

        destroy_registry_for_testing(registry);
    }

    #[test]
    fun test_update_config() {
        let mut ctx = tx_context::dummy();
        let admin_cap = access::create_admin_cap(&mut ctx);
        let mut registry = create_registry_for_testing(&mut ctx);

        update_config(
            &admin_cap,
            &mut registry,
            100_000_000_000, // 100 SUI
            20_000_000_000,  // 20 SUI
            2_000_000_000,   // 2 SUI
            200_000_000,     // 0.2 SUI
        );

        assert!(registry.dao_creation_fee == 100_000_000_000, 0);
        assert!(registry.treasury_fee == 20_000_000_000, 1);
        assert!(registry.proposal_fee == 2_000_000_000, 2);
        assert!(registry.execution_fee == 200_000_000, 3);

        destroy_registry_for_testing(registry);
        access::destroy_admin_cap_for_testing(admin_cap);
    }

    #[test]
    fun test_pause_unpause() {
        let mut ctx = tx_context::dummy();
        let admin_cap = access::create_admin_cap(&mut ctx);
        let mut registry = create_registry_for_testing(&mut ctx);

        assert!(registry.paused == false, 0);

        pause(&admin_cap, &mut registry);
        assert!(registry.paused == true, 1);

        unpause(&admin_cap, &mut registry);
        assert!(registry.paused == false, 2);

        destroy_registry_for_testing(registry);
        access::destroy_admin_cap_for_testing(admin_cap);
    }

    #[test]
    fun test_register_governance() {
        let mut ctx = tx_context::dummy();
        let mut registry = create_registry_for_testing(&mut ctx);

        let governance_id = object::id_from_address(@0x123);
        register_governance(&mut registry, governance_id);

        assert!(registry.total_daos_created == 1, 0);
        assert!(is_governance_registered(&registry, governance_id) == true, 1);

        destroy_registry_for_testing(registry);
    }

    #[test]
    fun test_collect_fees() {
        let mut ctx = tx_context::dummy();
        let mut registry = create_registry_for_testing(&mut ctx);

        // Create payment coin
        let payment = coin::mint_for_testing<SUI>(DEFAULT_DAO_CREATION_FEE, &mut ctx);

        collect_dao_creation_fee(&mut registry, payment, false);

        assert!(registry.collected_fees.value() == DEFAULT_DAO_CREATION_FEE, 0);

        destroy_registry_for_testing(registry);
    }

    #[test]
    fun test_collect_fee_with_treasury() {
        let mut ctx = tx_context::dummy();
        let mut registry = create_registry_for_testing(&mut ctx);

        let total = DEFAULT_DAO_CREATION_FEE + DEFAULT_TREASURY_FEE;
        let payment = coin::mint_for_testing<SUI>(total, &mut ctx);

        collect_dao_creation_fee(&mut registry, payment, true);

        assert!(registry.collected_fees.value() == total, 0);

        destroy_registry_for_testing(registry);
    }

    #[test]
    #[expected_failure(abort_code = 101)] // EInsufficientFee
    fun test_collect_insufficient_fee() {
        let mut ctx = tx_context::dummy();
        let mut registry = create_registry_for_testing(&mut ctx);

        let payment = coin::mint_for_testing<SUI>(1_000_000_000, &mut ctx); // 1 SUI (not enough)

        collect_dao_creation_fee(&mut registry, payment, false);

        destroy_registry_for_testing(registry);
    }

    #[test]
    fun test_withdraw_fees() {
        let mut ctx = tx_context::dummy();
        let admin_cap = access::create_admin_cap(&mut ctx);
        let mut registry = create_registry_for_testing(&mut ctx);

        // Add some fees
        let payment = coin::mint_for_testing<SUI>(DEFAULT_DAO_CREATION_FEE, &mut ctx);
        collect_dao_creation_fee(&mut registry, payment, false);

        // Withdraw half
        let half = DEFAULT_DAO_CREATION_FEE / 2;
        withdraw_fees(&admin_cap, &mut registry, half, @0xABC, &mut ctx);

        assert!(registry.collected_fees.value() == half, 0);

        destroy_registry_for_testing(registry);
        access::destroy_admin_cap_for_testing(admin_cap);
    }

    #[test]
    #[expected_failure(abort_code = 100)] // EPlatformPaused
    fun test_assert_not_paused_fails() {
        let mut ctx = tx_context::dummy();
        let admin_cap = access::create_admin_cap(&mut ctx);
        let mut registry = create_registry_for_testing(&mut ctx);

        pause(&admin_cap, &mut registry);
        assert_not_paused(&registry);

        destroy_registry_for_testing(registry);
        access::destroy_admin_cap_for_testing(admin_cap);
    }
}
