/// Registry module for managing multisig platform configuration
module sui_multisig::registry {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};

    use sui_multisig::access::{Self, AdminCap};
    use sui_multisig::errors;
    use sui_multisig::events;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Default creation fee: 5 SUI
    const DEFAULT_CREATION_FEE: u64 = 5_000_000_000;

    /// Default execution fee: 0.1 SUI
    const DEFAULT_EXECUTION_FEE: u64 = 100_000_000;

    /// Default proposal expiry: 7 days
    const DEFAULT_PROPOSAL_EXPIRY_MS: u64 = 604_800_000;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Global registry for all multisig wallets
    public struct MultisigRegistry has key {
        id: UID,
        /// Platform configuration
        config: PlatformConfig,
        /// All wallet IDs (for enumeration)
        wallet_ids: vector<ID>,
        /// Wallet metadata by ID
        wallet_metadata: Table<ID, WalletMetadata>,
        /// Collected fees
        collected_fees: Balance<SUI>,
        /// Total wallets created
        total_wallets: u64,
        /// Whether platform is paused
        paused: bool,
    }

    /// Platform configuration
    public struct PlatformConfig has store, copy, drop {
        /// Fee required to create a wallet (in SUI)
        creation_fee: u64,
        /// Fee for executing proposals
        execution_fee: u64,
        /// Default proposal expiry time
        default_proposal_expiry_ms: u64,
        /// Fee recipient address
        fee_recipient: address,
    }

    /// Metadata about a wallet (for indexing)
    public struct WalletMetadata has store, copy, drop {
        /// Wallet creator
        creator: address,
        /// When wallet was created
        created_at_ms: u64,
        /// Wallet name
        name: std::string::String,
        /// Number of signers
        signer_count: u64,
        /// Current threshold
        threshold: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Initialize the multisig platform
    fun init(ctx: &mut TxContext) {
        let admin_cap = access::create_admin_cap(ctx);
        let sender = ctx.sender();

        let registry = MultisigRegistry {
            id: object::new(ctx),
            config: PlatformConfig {
                creation_fee: DEFAULT_CREATION_FEE,
                execution_fee: DEFAULT_EXECUTION_FEE,
                default_proposal_expiry_ms: DEFAULT_PROPOSAL_EXPIRY_MS,
                fee_recipient: sender,
            },
            wallet_ids: vector::empty(),
            wallet_metadata: table::new(ctx),
            collected_fees: balance::zero(),
            total_wallets: 0,
            paused: false,
        };

        transfer::share_object(registry);
        transfer::public_transfer(admin_cap, sender);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REGISTRATION FUNCTIONS (called by wallet module)
    // ═══════════════════════════════════════════════════════════════════════

    /// Register a new wallet (called internally by wallet module)
    public(package) fun register_wallet(
        registry: &mut MultisigRegistry,
        wallet_id: ID,
        name: std::string::String,
        signer_count: u64,
        threshold: u64,
        created_at_ms: u64,
        ctx: &TxContext,
    ) {
        let metadata = WalletMetadata {
            creator: ctx.sender(),
            created_at_ms,
            name,
            signer_count,
            threshold,
        };

        registry.wallet_ids.push_back(wallet_id);
        registry.wallet_metadata.add(wallet_id, metadata);
        registry.total_wallets = registry.total_wallets + 1;
    }

    /// Update wallet metadata
    public(package) fun update_wallet_metadata(
        registry: &mut MultisigRegistry,
        wallet_id: ID,
        signer_count: u64,
        threshold: u64,
    ) {
        let metadata = registry.wallet_metadata.borrow_mut(wallet_id);
        metadata.signer_count = signer_count;
        metadata.threshold = threshold;
    }

    /// Collect creation fee
    public(package) fun collect_creation_fee(
        registry: &mut MultisigRegistry,
        fee: Coin<SUI>,
    ) {
        let fee_amount = fee.value();
        assert!(fee_amount >= registry.config.creation_fee, errors::insufficient_fee());
        registry.collected_fees.join(fee.into_balance());
    }

    /// Collect execution fee
    public(package) fun collect_execution_fee(
        registry: &mut MultisigRegistry,
        fee: Coin<SUI>,
    ) {
        let fee_amount = fee.value();
        assert!(fee_amount >= registry.config.execution_fee, errors::insufficient_fee());
        registry.collected_fees.join(fee.into_balance());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Update platform configuration
    public fun update_platform_config(
        registry: &mut MultisigRegistry,
        _admin_cap: &AdminCap,
        creation_fee: u64,
        execution_fee: u64,
        default_proposal_expiry_ms: u64,
        fee_recipient: address,
        ctx: &TxContext,
    ) {
        registry.config.creation_fee = creation_fee;
        registry.config.execution_fee = execution_fee;
        registry.config.default_proposal_expiry_ms = default_proposal_expiry_ms;
        registry.config.fee_recipient = fee_recipient;

        events::emit_platform_config_updated(
            creation_fee,
            execution_fee,
            ctx.sender(),
        );
    }

    /// Pause/unpause the platform
    public fun set_platform_paused(
        registry: &mut MultisigRegistry,
        _admin_cap: &AdminCap,
        paused: bool,
    ) {
        registry.paused = paused;
    }

    /// Withdraw collected fees
    public fun withdraw_fees(
        registry: &mut MultisigRegistry,
        _admin_cap: &AdminCap,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        let amount = registry.collected_fees.value();
        assert!(amount > 0, errors::zero_amount());

        let fee_balance = registry.collected_fees.split(amount);
        coin::from_balance(fee_balance, ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun config(registry: &MultisigRegistry): &PlatformConfig {
        &registry.config
    }

    public fun total_wallets(registry: &MultisigRegistry): u64 {
        registry.total_wallets
    }

    public fun is_paused(registry: &MultisigRegistry): bool {
        registry.paused
    }

    public fun collected_fees(registry: &MultisigRegistry): u64 {
        registry.collected_fees.value()
    }

    public fun wallet_ids(registry: &MultisigRegistry): &vector<ID> {
        &registry.wallet_ids
    }

    public fun wallet_metadata(registry: &MultisigRegistry, wallet_id: ID): &WalletMetadata {
        registry.wallet_metadata.borrow(wallet_id)
    }

    public fun has_wallet(registry: &MultisigRegistry, wallet_id: ID): bool {
        registry.wallet_metadata.contains(wallet_id)
    }

    // Config getters
    public fun config_creation_fee(config: &PlatformConfig): u64 { config.creation_fee }
    public fun config_execution_fee(config: &PlatformConfig): u64 { config.execution_fee }
    public fun config_default_proposal_expiry_ms(config: &PlatformConfig): u64 { config.default_proposal_expiry_ms }
    public fun config_fee_recipient(config: &PlatformConfig): address { config.fee_recipient }

    // Metadata getters
    public fun metadata_creator(metadata: &WalletMetadata): address { metadata.creator }
    public fun metadata_created_at_ms(metadata: &WalletMetadata): u64 { metadata.created_at_ms }
    public fun metadata_name(metadata: &WalletMetadata): std::string::String { metadata.name }
    public fun metadata_signer_count(metadata: &WalletMetadata): u64 { metadata.signer_count }
    public fun metadata_threshold(metadata: &WalletMetadata): u64 { metadata.threshold }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun create_registry_for_testing(ctx: &mut TxContext): (MultisigRegistry, AdminCap) {
        let admin_cap = access::create_admin_cap_for_testing(ctx);
        let sender = ctx.sender();

        let registry = MultisigRegistry {
            id: object::new(ctx),
            config: PlatformConfig {
                creation_fee: DEFAULT_CREATION_FEE,
                execution_fee: DEFAULT_EXECUTION_FEE,
                default_proposal_expiry_ms: DEFAULT_PROPOSAL_EXPIRY_MS,
                fee_recipient: sender,
            },
            wallet_ids: vector::empty(),
            wallet_metadata: table::new(ctx),
            collected_fees: balance::zero(),
            total_wallets: 0,
            paused: false,
        };

        (registry, admin_cap)
    }

    #[test_only]
    public fun destroy_registry_for_testing(registry: MultisigRegistry) {
        let MultisigRegistry {
            id,
            config: _,
            wallet_ids: _,
            wallet_metadata,
            collected_fees,
            total_wallets: _,
            paused: _,
        } = registry;

        object::delete(id);
        wallet_metadata.drop();
        collected_fees.destroy_for_testing();
    }

    #[test_only]
    public fun get_creation_fee(registry: &MultisigRegistry): u64 {
        registry.config.creation_fee
    }

    #[test_only]
    public fun get_execution_fee(registry: &MultisigRegistry): u64 {
        registry.config.execution_fee
    }
}
