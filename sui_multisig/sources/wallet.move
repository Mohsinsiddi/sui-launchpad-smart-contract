/// Wallet module for creating and managing multisig wallets
module sui_multisig::wallet {
    use sui::coin::Coin;
    use sui::sui::SUI;
    use sui::clock::Clock;
    use sui::vec_set::{Self, VecSet};

    use sui_multisig::registry::{Self, MultisigRegistry};
    use sui_multisig::vault;
    use sui_multisig::errors;
    use sui_multisig::events;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Maximum wallet name length
    const MAX_NAME_LENGTH: u64 = 64;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Multisig wallet
    public struct MultisigWallet has key, store {
        id: UID,
        /// Wallet name
        name: std::string::String,
        /// Required signatures threshold
        threshold: u64,
        /// Set of authorized signers
        signers: VecSet<address>,
        /// Nonce for replay protection
        nonce: u64,
        /// Associated vault ID
        vault_id: ID,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WALLET CREATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new multisig wallet
    public fun create_wallet(
        registry: &mut MultisigRegistry,
        name: std::string::String,
        signers: vector<address>,
        threshold: u64,
        creation_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): MultisigWallet {
        // Validate platform not paused
        assert!(!registry.is_paused(), errors::platform_paused());

        // Validate name length
        assert!(name.length() <= MAX_NAME_LENGTH, errors::name_too_long());

        // Validate signers
        let signer_count = signers.length();
        assert!(signer_count > 0, errors::no_signers());

        // Validate threshold
        assert!(threshold > 0, errors::zero_threshold());
        assert!(threshold <= signer_count, errors::threshold_exceeds_signers());

        // Collect creation fee
        registry.collect_creation_fee(creation_fee);

        // Create signer set and check for duplicates
        let mut signer_set = vec_set::empty<address>();
        let mut i = 0;
        while (i < signer_count) {
            let signer = signers[i];
            assert!(!signer_set.contains(&signer), errors::duplicate_signer());
            signer_set.insert(signer);
            i = i + 1;
        };

        // Create wallet ID first, then create and share vault
        let wallet_uid = object::new(ctx);
        let wallet_id = object::uid_to_inner(&wallet_uid);
        let vault_id = vault::create_and_share(wallet_id, ctx);

        // Register wallet in registry
        let current_time = clock.timestamp_ms();
        registry.register_wallet(
            wallet_id,
            name,
            signer_count,
            threshold,
            current_time,
            ctx,
        );

        // Emit event
        events::emit_wallet_created(
            wallet_id,
            vault_id,
            name,
            threshold,
            signers,
            ctx.sender(),
        );

        MultisigWallet {
            id: wallet_uid,
            name,
            threshold,
            signers: signer_set,
            nonce: 0,
            vault_id,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SIGNER MANAGEMENT (called by proposal execution)
    // ═══════════════════════════════════════════════════════════════════════

    /// Add a new signer (called by proposal execution)
    public(package) fun add_signer(
        wallet: &mut MultisigWallet,
        registry: &mut MultisigRegistry,
        new_signer: address,
    ) {
        assert!(!wallet.signers.contains(&new_signer), errors::signer_exists());

        wallet.signers.insert(new_signer);
        let new_count = wallet.signers.size();

        // Update registry metadata
        registry.update_wallet_metadata(
            object::id(wallet),
            new_count,
            wallet.threshold,
        );

        events::emit_signer_added(
            object::id(wallet),
            new_signer,
            new_count,
        );
    }

    /// Remove a signer (called by proposal execution)
    public(package) fun remove_signer(
        wallet: &mut MultisigWallet,
        registry: &mut MultisigRegistry,
        signer_to_remove: address,
    ) {
        assert!(wallet.signers.contains(&signer_to_remove), errors::signer_not_found());

        let current_count = wallet.signers.size();
        assert!(current_count > 1, errors::cannot_remove_last_signer());

        wallet.signers.remove(&signer_to_remove);
        let new_count = wallet.signers.size();

        // Auto-adjust threshold if necessary
        if (wallet.threshold > new_count) {
            let old_threshold = wallet.threshold;
            wallet.threshold = new_count;
            events::emit_threshold_changed(
                object::id(wallet),
                old_threshold,
                new_count,
            );
        };

        // Update registry metadata
        registry.update_wallet_metadata(
            object::id(wallet),
            new_count,
            wallet.threshold,
        );

        events::emit_signer_removed(
            object::id(wallet),
            signer_to_remove,
            new_count,
        );
    }

    /// Change threshold (called by proposal execution)
    public(package) fun change_threshold(
        wallet: &mut MultisigWallet,
        registry: &mut MultisigRegistry,
        new_threshold: u64,
    ) {
        assert!(new_threshold > 0, errors::zero_threshold());
        assert!(new_threshold <= wallet.signers.size(), errors::threshold_exceeds_signers());

        let old_threshold = wallet.threshold;
        wallet.threshold = new_threshold;

        // Update registry metadata
        registry.update_wallet_metadata(
            object::id(wallet),
            wallet.signers.size(),
            new_threshold,
        );

        events::emit_threshold_changed(
            object::id(wallet),
            old_threshold,
            new_threshold,
        );
    }

    /// Increment nonce (called after proposal execution)
    public(package) fun increment_nonce(wallet: &mut MultisigWallet) {
        wallet.nonce = wallet.nonce + 1;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Check if an address is a signer
    public fun is_signer(wallet: &MultisigWallet, addr: address): bool {
        wallet.signers.contains(&addr)
    }

    /// Validate that caller is a signer
    public fun assert_is_signer(wallet: &MultisigWallet, addr: address) {
        assert!(wallet.signers.contains(&addr), errors::not_signer());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun wallet_id(wallet: &MultisigWallet): ID {
        object::id(wallet)
    }

    public fun name(wallet: &MultisigWallet): std::string::String {
        wallet.name
    }

    public fun threshold(wallet: &MultisigWallet): u64 {
        wallet.threshold
    }

    public fun signer_count(wallet: &MultisigWallet): u64 {
        wallet.signers.size()
    }

    public fun signers(wallet: &MultisigWallet): vector<address> {
        wallet.signers.into_keys()
    }

    public fun nonce(wallet: &MultisigWallet): u64 {
        wallet.nonce
    }

    public fun vault_id(wallet: &MultisigWallet): ID {
        wallet.vault_id
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun create_wallet_for_testing(
        name: std::string::String,
        signers: vector<address>,
        threshold: u64,
        vault_id: ID,
        ctx: &mut TxContext,
    ): MultisigWallet {
        let signer_count = signers.length();
        assert!(signer_count > 0, errors::no_signers());
        assert!(threshold > 0, errors::zero_threshold());
        assert!(threshold <= signer_count, errors::threshold_exceeds_signers());

        let mut signer_set = vec_set::empty<address>();
        let mut i = 0;
        while (i < signer_count) {
            let signer = signers[i];
            assert!(!signer_set.contains(&signer), errors::duplicate_signer());
            signer_set.insert(signer);
            i = i + 1;
        };

        MultisigWallet {
            id: object::new(ctx),
            name,
            threshold,
            signers: signer_set,
            nonce: 0,
            vault_id,
        }
    }

    #[test_only]
    public fun destroy_wallet_for_testing(wallet: MultisigWallet) {
        let MultisigWallet {
            id,
            name: _,
            threshold: _,
            signers: _,
            nonce: _,
            vault_id: _,
        } = wallet;

        object::delete(id);
    }

    #[test_only]
    public fun add_signer_for_testing(
        wallet: &mut MultisigWallet,
        new_signer: address,
    ) {
        assert!(!wallet.signers.contains(&new_signer), errors::signer_exists());
        wallet.signers.insert(new_signer);
    }

    #[test_only]
    public fun remove_signer_for_testing(
        wallet: &mut MultisigWallet,
        signer_to_remove: address,
    ) {
        assert!(wallet.signers.contains(&signer_to_remove), errors::signer_not_found());
        assert!(wallet.signers.size() > 1, errors::cannot_remove_last_signer());
        wallet.signers.remove(&signer_to_remove);
        if (wallet.threshold > wallet.signers.size()) {
            wallet.threshold = wallet.signers.size();
        };
    }

    #[test_only]
    public fun change_threshold_for_testing(
        wallet: &mut MultisigWallet,
        new_threshold: u64,
    ) {
        assert!(new_threshold > 0, errors::zero_threshold());
        assert!(new_threshold <= wallet.signers.size(), errors::threshold_exceeds_signers());
        wallet.threshold = new_threshold;
    }

    #[test_only]
    public fun increment_nonce_for_testing(wallet: &mut MultisigWallet) {
        wallet.nonce = wallet.nonce + 1;
    }
}
