/// DAO Treasury - Multi-token treasury controlled by governance
module sui_dao::treasury {
    use sui::balance::{Self, Balance};
    use sui::bag::{Self, Bag};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui_dao::access::DAOAdminCap;
    use sui_dao::errors;
    use sui_dao::events;
    use sui_dao::governance::{Self, Governance};
    use sui_dao::proposal::DAOAuth;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Multi-token treasury for a DAO
    public struct Treasury has key {
        id: UID,
        /// The governance that controls this treasury
        governance_id: ID,
        /// SUI balance (common case)
        sui_balance: Balance<SUI>,
        /// Other token balances (keyed by type name)
        token_balances: Bag,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CREATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new treasury for a governance (called by admin)
    public fun create_treasury(
        admin_cap: &DAOAdminCap,
        governance: &mut Governance,
        ctx: &mut TxContext,
    ): Treasury {
        sui_dao::access::assert_dao_admin_cap_matches(admin_cap, object::id(governance));

        let treasury = Treasury {
            id: object::new(ctx),
            governance_id: object::id(governance),
            sui_balance: balance::zero(),
            token_balances: bag::new(ctx),
        };

        let treasury_id = object::id(&treasury);
        governance::set_treasury(admin_cap, governance, treasury_id);

        events::emit_treasury_created(treasury_id, object::id(governance));

        treasury
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEPOSITS (Anyone can deposit)
    // ═══════════════════════════════════════════════════════════════════════

    /// Deposit SUI into the treasury
    public fun deposit_sui(
        treasury: &mut Treasury,
        coin: Coin<SUI>,
        ctx: &TxContext,
    ) {
        let amount = coin.value();
        treasury.sui_balance.join(coin.into_balance());

        let token_type = std::type_name::with_original_ids<SUI>().into_string();
        events::emit_treasury_deposit(
            object::id(treasury),
            token_type,
            amount,
            ctx.sender(),
        );
    }

    /// Deposit any token into the treasury
    public fun deposit<T>(
        treasury: &mut Treasury,
        coin: Coin<T>,
        ctx: &TxContext,
    ) {
        let amount = coin.value();
        let token_type = std::type_name::with_original_ids<T>().into_string();

        if (treasury.token_balances.contains(token_type)) {
            let balance: &mut Balance<T> = treasury.token_balances.borrow_mut(token_type);
            balance.join(coin.into_balance());
        } else {
            treasury.token_balances.add(token_type, coin.into_balance());
        };

        events::emit_treasury_deposit(
            object::id(treasury),
            token_type,
            amount,
            ctx.sender(),
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WITHDRAWALS (Requires DAO Auth from proposal)
    // ═══════════════════════════════════════════════════════════════════════

    /// Withdraw SUI from treasury (requires DAOAuth from executed proposal)
    public fun withdraw_sui(
        treasury: &mut Treasury,
        auth: DAOAuth,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        let proposal_id = sui_dao::proposal::auth_proposal_id(&auth);

        // Verify auth matches treasury
        sui_dao::proposal::consume_auth(auth, object::id(treasury));

        assert!(treasury.sui_balance.value() >= amount, errors::insufficient_treasury_balance());

        let coin = coin::from_balance(treasury.sui_balance.split(amount), ctx);

        let token_type = std::type_name::with_original_ids<SUI>().into_string();
        events::emit_treasury_withdrawal(
            object::id(treasury),
            token_type,
            amount,
            recipient,
            proposal_id,
        );

        transfer::public_transfer(coin, recipient);
    }

    /// Withdraw any token from treasury (requires DAOAuth)
    public fun withdraw<T>(
        treasury: &mut Treasury,
        auth: DAOAuth,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        let proposal_id = sui_dao::proposal::auth_proposal_id(&auth);

        // Verify auth matches treasury
        sui_dao::proposal::consume_auth(auth, object::id(treasury));

        let token_type = std::type_name::with_original_ids<T>().into_string();

        assert!(treasury.token_balances.contains(token_type), errors::insufficient_treasury_balance());

        let balance: &mut Balance<T> = treasury.token_balances.borrow_mut(token_type);
        assert!(balance.value() >= amount, errors::insufficient_treasury_balance());

        let coin = coin::from_balance(balance.split(amount), ctx);

        events::emit_treasury_withdrawal(
            object::id(treasury),
            token_type,
            amount,
            recipient,
            proposal_id,
        );

        transfer::public_transfer(coin, recipient);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    public fun governance_id(treasury: &Treasury): ID {
        treasury.governance_id
    }

    public fun sui_balance(treasury: &Treasury): u64 {
        treasury.sui_balance.value()
    }

    public fun token_balance<T>(treasury: &Treasury): u64 {
        let token_type = std::type_name::with_original_ids<T>().into_string();
        if (treasury.token_balances.contains(token_type)) {
            let balance: &Balance<T> = treasury.token_balances.borrow(token_type);
            balance.value()
        } else {
            0
        }
    }

    public fun has_token<T>(treasury: &Treasury): bool {
        let token_type = std::type_name::with_original_ids<T>().into_string();
        treasury.token_balances.contains(token_type)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun create_treasury_for_testing(
        governance_id: ID,
        ctx: &mut TxContext,
    ): Treasury {
        Treasury {
            id: object::new(ctx),
            governance_id,
            sui_balance: balance::zero(),
            token_balances: bag::new(ctx),
        }
    }

    #[test_only]
    public fun destroy_treasury_for_testing(treasury: Treasury) {
        let Treasury {
            id,
            governance_id: _,
            sui_balance,
            token_balances,
        } = treasury;
        object::delete(id);
        balance::destroy_for_testing(sui_balance);
        token_balances.destroy_empty();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_deposit_sui() {
        let mut ctx = tx_context::dummy();
        let governance_id = object::id_from_address(@0x123);

        let mut treasury = create_treasury_for_testing(governance_id, &mut ctx);

        assert!(treasury.sui_balance.value() == 0, 0);

        let coin = coin::mint_for_testing<SUI>(1000, &mut ctx);
        deposit_sui(&mut treasury, coin, &ctx);

        assert!(treasury.sui_balance.value() == 1000, 1);

        destroy_treasury_for_testing(treasury);
    }

    #[test]
    fun test_deposit_more_sui() {
        let mut ctx = tx_context::dummy();
        let governance_id = object::id_from_address(@0x123);

        let mut treasury = create_treasury_for_testing(governance_id, &mut ctx);

        // Deposit SUI
        let coin = coin::mint_for_testing<SUI>(500, &mut ctx);
        deposit_sui(&mut treasury, coin, &ctx);

        assert!(sui_balance(&treasury) == 500, 0);

        // Deposit more
        let coin2 = coin::mint_for_testing<SUI>(300, &mut ctx);
        deposit_sui(&mut treasury, coin2, &ctx);

        assert!(sui_balance(&treasury) == 800, 1);

        destroy_treasury_for_testing(treasury);
    }

    #[test]
    fun test_multiple_deposits() {
        let mut ctx = tx_context::dummy();
        let governance_id = object::id_from_address(@0x123);

        let mut treasury = create_treasury_for_testing(governance_id, &mut ctx);

        // Multiple SUI deposits
        let coin1 = coin::mint_for_testing<SUI>(100, &mut ctx);
        let coin2 = coin::mint_for_testing<SUI>(200, &mut ctx);
        let coin3 = coin::mint_for_testing<SUI>(300, &mut ctx);

        deposit_sui(&mut treasury, coin1, &ctx);
        deposit_sui(&mut treasury, coin2, &ctx);
        deposit_sui(&mut treasury, coin3, &ctx);

        assert!(sui_balance(&treasury) == 600, 0);

        destroy_treasury_for_testing(treasury);
    }
}
