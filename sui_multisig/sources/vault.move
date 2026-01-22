/// Vault module for storing multisig wallet assets
/// Treats all coins uniformly - SUI is just Coin<SUI>
module sui_multisig::vault {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::bag::{Self, Bag};

    use sui_multisig::errors;
    use sui_multisig::events;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Vault for storing wallet assets
    /// All token balances are stored uniformly in a Bag keyed by type name
    public struct MultisigVault has key {
        id: UID,
        /// Associated wallet ID
        wallet_id: ID,
        /// All token balances keyed by type name (including SUI)
        balances: Bag,
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

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun create_for_testing(wallet_id: ID, ctx: &mut TxContext): MultisigVault {
        MultisigVault {
            id: object::new(ctx),
            wallet_id,
            balances: bag::new(ctx),
        }
    }

    #[test_only]
    public fun destroy_for_testing(vault: MultisigVault) {
        let MultisigVault {
            id,
            wallet_id: _,
            balances,
        } = vault;

        object::delete(id);
        balances.destroy_empty();
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
