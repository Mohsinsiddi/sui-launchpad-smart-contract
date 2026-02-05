/// DAO Treasury - Multi-token treasury controlled by governance
/// Supports both fungible tokens (Coin<T>) and NFTs (key + store objects)
module sui_dao::treasury {
    use sui::balance::{Self, Balance};
    use sui::bag::{Self, Bag};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::dynamic_object_field as dof;
    use sui_dao::access::DAOAdminCap;
    use sui_dao::errors;
    use sui_dao::events;
    use sui_dao::governance::{Self, Governance};
    use sui_dao::proposal::DAOAuth;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Multi-token treasury for a DAO
    /// Supports fungible tokens via token_balances and NFTs via dynamic_object_field
    public struct Treasury has key {
        id: UID,
        /// The governance that controls this treasury
        governance_id: ID,
        /// SUI balance (common case)
        sui_balance: Balance<SUI>,
        /// Other token balances (keyed by type name)
        token_balances: Bag,
        /// Counter for NFTs of each type (for generating unique keys)
        nft_counters: Bag,
    }

    /// Key for storing NFTs in dynamic object field
    public struct NFTKey has copy, drop, store {
        nft_type: std::ascii::String,
        index: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CREATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new treasury for a governance (called by admin)
    public fun create_treasury(
        admin_cap: &DAOAdminCap,
        governance: &mut Governance,
        clock: &sui::clock::Clock,
        ctx: &mut TxContext,
    ): Treasury {
        sui_dao::access::assert_dao_admin_cap_matches(admin_cap, object::id(governance));

        let treasury = Treasury {
            id: object::new(ctx),
            governance_id: object::id(governance),
            sui_balance: balance::zero(),
            token_balances: bag::new(ctx),
            nft_counters: bag::new(ctx),
        };

        let treasury_id = object::id(&treasury);
        governance::set_treasury(admin_cap, governance, treasury_id);

        events::emit_treasury_created(
            treasury_id,
            object::id(governance),
            ctx.sender(),
            clock.timestamp_ms(),
        );

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
    // NFT DEPOSITS (Anyone can deposit)
    // ═══════════════════════════════════════════════════════════════════════

    /// Deposit an NFT into the treasury (e.g., Cetus/Turbos Position NFT)
    /// NFTs are stored using dynamic_object_field with a unique key
    public fun deposit_nft<NFT: key + store>(
        treasury: &mut Treasury,
        nft: NFT,
        ctx: &TxContext,
    ) {
        let nft_type = std::type_name::with_original_ids<NFT>().into_string();
        let nft_id = object::id(&nft);

        // Get or initialize the counter for this NFT type
        let index = if (treasury.nft_counters.contains(nft_type)) {
            let counter: &mut u64 = treasury.nft_counters.borrow_mut(nft_type);
            let current = *counter;
            *counter = current + 1;
            current
        } else {
            treasury.nft_counters.add(nft_type, 1u64);
            0
        };

        // Create unique key and store NFT
        let key = NFTKey { nft_type, index };
        dof::add(&mut treasury.id, key, nft);

        events::emit_treasury_nft_deposit(
            object::id(treasury),
            nft_type,
            nft_id,
            ctx.sender(),
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NFT WITHDRAWALS (Requires DAO Auth from proposal)
    // ═══════════════════════════════════════════════════════════════════════

    /// Withdraw an NFT from treasury (requires DAOAuth from executed proposal)
    /// The index identifies which NFT of this type to withdraw (LIFO order typically)
    public fun withdraw_nft<NFT: key + store>(
        treasury: &mut Treasury,
        auth: DAOAuth,
        index: u64,
        recipient: address,
    ) {
        let proposal_id = sui_dao::proposal::auth_proposal_id(&auth);

        // Verify auth matches treasury
        sui_dao::proposal::consume_auth(auth, object::id(treasury));

        let nft_type = std::type_name::with_original_ids<NFT>().into_string();
        let key = NFTKey { nft_type, index };

        // Verify NFT exists
        assert!(dof::exists_with_type<NFTKey, NFT>(&treasury.id, key), errors::insufficient_treasury_balance());

        // Remove and transfer NFT
        let nft: NFT = dof::remove(&mut treasury.id, key);
        let nft_id = object::id(&nft);

        events::emit_treasury_nft_withdrawal(
            object::id(treasury),
            nft_type,
            nft_id,
            recipient,
            proposal_id,
        );

        transfer::public_transfer(nft, recipient);
    }

    /// Get the latest NFT of a type and withdraw it (convenience function)
    /// Withdraws the most recently deposited NFT of the given type
    public fun withdraw_latest_nft<NFT: key + store>(
        treasury: &mut Treasury,
        auth: DAOAuth,
        recipient: address,
    ) {
        let nft_type = std::type_name::with_original_ids<NFT>().into_string();

        // Get current count
        assert!(treasury.nft_counters.contains(nft_type), errors::insufficient_treasury_balance());
        let counter: &u64 = treasury.nft_counters.borrow(nft_type);
        assert!(*counter > 0, errors::insufficient_treasury_balance());

        // Withdraw the latest (index = counter - 1)
        let latest_index = *counter - 1;
        withdraw_nft<NFT>(treasury, auth, latest_index, recipient);
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

    /// Get the count of NFTs of a specific type in the treasury
    public fun nft_count<NFT: key + store>(treasury: &Treasury): u64 {
        let nft_type = std::type_name::with_original_ids<NFT>().into_string();
        if (treasury.nft_counters.contains(nft_type)) {
            *treasury.nft_counters.borrow(nft_type)
        } else {
            0
        }
    }

    /// Check if treasury has any NFTs of a specific type
    public fun has_nft<NFT: key + store>(treasury: &Treasury): bool {
        nft_count<NFT>(treasury) > 0
    }

    /// Check if a specific NFT exists at the given index
    public fun has_nft_at_index<NFT: key + store>(treasury: &Treasury, index: u64): bool {
        let nft_type = std::type_name::with_original_ids<NFT>().into_string();
        let key = NFTKey { nft_type, index };
        dof::exists_with_type<NFTKey, NFT>(&treasury.id, key)
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
            nft_counters: bag::new(ctx),
        }
    }

    #[test_only]
    public fun destroy_treasury_for_testing(mut treasury: Treasury) {
        // Clean up NFT counters if any
        let nft_type = std::type_name::with_original_ids<TestNFT>().into_string();
        if (treasury.nft_counters.contains(nft_type)) {
            let _: u64 = treasury.nft_counters.remove(nft_type);
        };

        let Treasury {
            id,
            governance_id: _,
            sui_balance,
            token_balances,
            nft_counters,
        } = treasury;
        object::delete(id);
        balance::destroy_for_testing(sui_balance);
        token_balances.destroy_empty();
        nft_counters.destroy_empty();
    }

    #[test_only]
    public fun share_treasury_for_testing(treasury: Treasury) {
        transfer::share_object(treasury);
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

    // ═══════════════════════════════════════════════════════════════════════
    // NFT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public struct TestNFT has key, store {
        id: UID,
        value: u64,
    }

    #[test_only]
    public fun create_test_nft(value: u64, ctx: &mut TxContext): TestNFT {
        TestNFT {
            id: object::new(ctx),
            value,
        }
    }

    #[test_only]
    public fun destroy_test_nft(nft: TestNFT) {
        let TestNFT { id, value: _ } = nft;
        object::delete(id);
    }

    #[test_only]
    /// Remove an NFT from treasury without DAOAuth (for testing only)
    public fun remove_nft_for_testing<NFT: key + store>(
        treasury: &mut Treasury,
        index: u64,
    ): NFT {
        let nft_type = std::type_name::with_original_ids<NFT>().into_string();
        let key = NFTKey { nft_type, index };
        dof::remove(&mut treasury.id, key)
    }

    #[test]
    fun test_deposit_nft() {
        let mut ctx = tx_context::dummy();
        let governance_id = object::id_from_address(@0x123);

        let mut treasury = create_treasury_for_testing(governance_id, &mut ctx);

        assert!(nft_count<TestNFT>(&treasury) == 0, 0);
        assert!(!has_nft<TestNFT>(&treasury), 1);

        // Deposit NFT
        let nft = create_test_nft(100, &mut ctx);
        deposit_nft(&mut treasury, nft, &ctx);

        assert!(nft_count<TestNFT>(&treasury) == 1, 2);
        assert!(has_nft<TestNFT>(&treasury), 3);
        assert!(has_nft_at_index<TestNFT>(&treasury, 0), 4);

        // Cleanup - remove NFT for testing
        let nft = remove_nft_for_testing<TestNFT>(&mut treasury, 0);
        destroy_test_nft(nft);

        destroy_treasury_for_testing(treasury);
    }

    #[test]
    fun test_deposit_multiple_nfts() {
        let mut ctx = tx_context::dummy();
        let governance_id = object::id_from_address(@0x123);

        let mut treasury = create_treasury_for_testing(governance_id, &mut ctx);

        // Deposit multiple NFTs
        let nft1 = create_test_nft(1, &mut ctx);
        let nft2 = create_test_nft(2, &mut ctx);
        let nft3 = create_test_nft(3, &mut ctx);

        deposit_nft(&mut treasury, nft1, &ctx);
        deposit_nft(&mut treasury, nft2, &ctx);
        deposit_nft(&mut treasury, nft3, &ctx);

        assert!(nft_count<TestNFT>(&treasury) == 3, 0);
        assert!(has_nft_at_index<TestNFT>(&treasury, 0), 1);
        assert!(has_nft_at_index<TestNFT>(&treasury, 1), 2);
        assert!(has_nft_at_index<TestNFT>(&treasury, 2), 3);
        assert!(!has_nft_at_index<TestNFT>(&treasury, 3), 4);

        // Cleanup - remove NFTs for testing (LIFO order)
        let nft3 = remove_nft_for_testing<TestNFT>(&mut treasury, 2);
        let nft2 = remove_nft_for_testing<TestNFT>(&mut treasury, 1);
        let nft1 = remove_nft_for_testing<TestNFT>(&mut treasury, 0);

        destroy_test_nft(nft1);
        destroy_test_nft(nft2);
        destroy_test_nft(nft3);

        destroy_treasury_for_testing(treasury);
    }
}
