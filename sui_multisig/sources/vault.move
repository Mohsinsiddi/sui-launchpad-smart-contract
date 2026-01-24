/// Vault module for storing multisig wallet assets
/// Treats all coins uniformly - SUI is just Coin<SUI>
/// Also supports NFT storage via ObjectBag
module sui_multisig::vault {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::bag::{Self, Bag};
    use sui::object_bag::{Self, ObjectBag};

    use sui_multisig::errors;
    use sui_multisig::events;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Vault for storing wallet assets
    /// All token balances are stored uniformly in a Bag keyed by type name
    /// NFTs are stored in an ObjectBag keyed by object ID
    public struct MultisigVault has key {
        id: UID,
        /// Associated wallet ID
        wallet_id: ID,
        /// All token balances keyed by type name (including SUI)
        balances: Bag,
        /// NFT storage keyed by object ID
        nfts: ObjectBag,
        /// Count of NFTs stored
        nft_count: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new vault for a wallet and share it
    public(package) fun create_and_share(
        wallet_id: ID,
        ctx: &mut TxContext,
    ): ID {
        let vault = MultisigVault {
            id: object::new(ctx),
            wallet_id,
            balances: bag::new(ctx),
            nfts: object_bag::new(ctx),
            nft_count: 0,
        };
        let vault_id = object::id(&vault);
        transfer::share_object(vault);
        vault_id
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEPOSIT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Deposit any coin type into the vault (including SUI)
    public fun deposit<T>(
        vault: &mut MultisigVault,
        coin: Coin<T>,
        ctx: &TxContext,
    ) {
        let amount = coin.value();
        assert!(amount > 0, errors::zero_amount());

        let type_name = std::type_name::get<T>();
        let type_string = std::type_name::into_string(type_name);

        if (vault.balances.contains(type_string)) {
            let balance: &mut Balance<T> = vault.balances.borrow_mut(type_string);
            balance.join(coin.into_balance());
        } else {
            vault.balances.add(type_string, coin.into_balance<T>());
        };

        events::emit_token_deposited(
            object::id(vault),
            vault.wallet_id,
            type_string,
            ctx.sender(),
            amount,
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WITHDRAWAL FUNCTIONS (package-level for proposal execution)
    // ═══════════════════════════════════════════════════════════════════════

    /// Withdraw any coin type from the vault (called by proposal execution)
    public(package) fun withdraw<T>(
        vault: &mut MultisigVault,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(amount > 0, errors::zero_amount());

        let type_name = std::type_name::get<T>();
        let type_string = std::type_name::into_string(type_name);

        assert!(vault.balances.contains(type_string), errors::token_not_found());

        let balance: &mut Balance<T> = vault.balances.borrow_mut(type_string);
        assert!(balance.value() >= amount, errors::insufficient_balance());

        let withdrawn = balance.split(amount);

        events::emit_token_withdrawn(
            object::id(vault),
            vault.wallet_id,
            type_string,
            recipient,
            amount,
        );

        coin::from_balance(withdrawn, ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NFT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Deposit any NFT into the vault
    /// NFT must have key + store abilities
    public fun deposit_nft<T: key + store>(
        vault: &mut MultisigVault,
        nft: T,
        ctx: &TxContext,
    ) {
        let nft_id = object::id(&nft);
        let type_name = std::type_name::get<T>();
        let type_string = std::type_name::into_string(type_name);

        vault.nfts.add(nft_id, nft);
        vault.nft_count = vault.nft_count + 1;

        events::emit_nft_deposited(
            object::id(vault),
            vault.wallet_id,
            nft_id,
            type_string,
            ctx.sender(),
        );
    }

    /// Withdraw an NFT from the vault (called by proposal execution)
    public(package) fun withdraw_nft<T: key + store>(
        vault: &mut MultisigVault,
        nft_id: ID,
        recipient: address,
    ): T {
        assert!(vault.nfts.contains(nft_id), errors::nft_not_found());

        let nft: T = vault.nfts.remove(nft_id);
        vault.nft_count = vault.nft_count - 1;

        let type_name = std::type_name::get<T>();
        let type_string = std::type_name::into_string(type_name);

        events::emit_nft_withdrawn(
            object::id(vault),
            vault.wallet_id,
            nft_id,
            type_string,
            recipient,
        );

        nft
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun vault_id(vault: &MultisigVault): ID {
        object::id(vault)
    }

    public fun wallet_id(vault: &MultisigVault): ID {
        vault.wallet_id
    }

    /// Get balance of any token type
    public fun balance<T>(vault: &MultisigVault): u64 {
        let type_name = std::type_name::get<T>();
        let type_string = std::type_name::into_string(type_name);

        if (vault.balances.contains(type_string)) {
            let balance: &Balance<T> = vault.balances.borrow(type_string);
            balance.value()
        } else {
            0
        }
    }

    /// Check if vault has a specific token type
    public fun has_token<T>(vault: &MultisigVault): bool {
        let type_name = std::type_name::get<T>();
        let type_string = std::type_name::into_string(type_name);
        vault.balances.contains(type_string)
    }

    /// Check if vault has a specific NFT by ID
    public fun has_nft(vault: &MultisigVault, nft_id: ID): bool {
        vault.nfts.contains(nft_id)
    }

    /// Get count of NFTs in vault
    public fun nft_count(vault: &MultisigVault): u64 {
        vault.nft_count
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun create_for_testing(wallet_id: ID, ctx: &mut TxContext): MultisigVault {
        MultisigVault {
            id: object::new(ctx),
            wallet_id,
            balances: bag::new(ctx),
            nfts: object_bag::new(ctx),
            nft_count: 0,
        }
    }

    #[test_only]
    public fun destroy_for_testing(vault: MultisigVault) {
        let MultisigVault {
            id,
            wallet_id: _,
            balances,
            nfts,
            nft_count: _,
        } = vault;

        object::delete(id);
        balances.destroy_empty();
        nfts.destroy_empty();
    }

    #[test_only]
    public fun withdraw_nft_for_testing<T: key + store>(
        vault: &mut MultisigVault,
        nft_id: ID,
        recipient: address,
    ): T {
        withdraw_nft<T>(vault, nft_id, recipient)
    }

    #[test_only]
    public fun withdraw_for_testing<T>(
        vault: &mut MultisigVault,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ): Coin<T> {
        withdraw<T>(vault, amount, recipient, ctx)
    }
}
