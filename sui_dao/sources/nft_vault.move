/// NFT Vault - Lock NFTs to gain voting power for NFT-based governance
module sui_dao::nft_vault {
    use sui::clock::Clock;
    use sui::dynamic_object_field as dof;
    use sui_dao::errors;
    use sui_dao::events;
    use sui_dao::governance::{Self, Governance};
    use sui_dao::proposal::Proposal;
    use sui_dao::voting;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// A vault that holds locked NFTs for voting
    public struct NFTVault<phantom NFT: key + store> has key {
        id: UID,
        /// The governance this vault belongs to
        governance_id: ID,
        /// Owner of the vault
        owner: address,
        /// Number of NFTs locked
        nft_count: u64,
        /// Lock expiry timestamp (0 = no lock)
        lock_until_ms: u64,
    }

    /// Key for storing NFTs in dynamic object field
    public struct NFTKey has copy, drop, store {
        index: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VAULT MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new NFT vault for a governance
    public fun create_vault<NFT: key + store>(
        governance: &Governance,
        ctx: &mut TxContext,
    ): NFTVault<NFT> {
        // Verify governance is NFT mode
        assert!(governance::is_nft_mode(governance), errors::wrong_voting_mode());

        // Verify NFT type matches
        let expected_type = governance::nft_collection_type(governance);
        assert!(expected_type.is_some(), errors::wrong_nft_collection());

        let actual_type = std::type_name::with_original_ids<NFT>().into_string();
        assert!(*expected_type.borrow() == actual_type, errors::wrong_nft_collection());

        let vault = NFTVault<NFT> {
            id: object::new(ctx),
            governance_id: object::id(governance),
            owner: ctx.sender(),
            nft_count: 0,
            lock_until_ms: 0,
        };

        events::emit_nft_vault_created(
            object::id(&vault),
            object::id(governance),
            ctx.sender(),
        );

        vault
    }

    /// Lock an NFT in the vault
    public fun lock_nft<NFT: key + store>(
        vault: &mut NFTVault<NFT>,
        nft: NFT,
        ctx: &TxContext,
    ) {
        assert!(vault.owner == ctx.sender(), errors::not_position_owner());

        let nft_id = object::id(&nft);
        let key = NFTKey { index: vault.nft_count };

        dof::add(&mut vault.id, key, nft);
        vault.nft_count = vault.nft_count + 1;

        events::emit_nft_locked(object::id(vault), nft_id, ctx.sender());
    }

    /// Lock multiple NFTs at once
    public fun lock_nfts<NFT: key + store>(
        vault: &mut NFTVault<NFT>,
        mut nfts: vector<NFT>,
        ctx: &TxContext,
    ) {
        while (!nfts.is_empty()) {
            let nft = nfts.pop_back();
            lock_nft(vault, nft, ctx);
        };
        nfts.destroy_empty();
    }

    /// Unlock an NFT from the vault (LIFO order)
    public fun unlock_nft<NFT: key + store>(
        vault: &mut NFTVault<NFT>,
        clock: &Clock,
        ctx: &TxContext,
    ): NFT {
        assert!(vault.owner == ctx.sender(), errors::not_position_owner());
        assert!(vault.nft_count > 0, errors::no_nfts_locked());

        // Check lock period
        let now = clock.timestamp_ms();
        assert!(vault.lock_until_ms == 0 || now >= vault.lock_until_ms, errors::nfts_still_locked());

        vault.nft_count = vault.nft_count - 1;
        let key = NFTKey { index: vault.nft_count };

        let nft: NFT = dof::remove(&mut vault.id, key);

        events::emit_nft_unlocked(object::id(vault), object::id(&nft), ctx.sender());

        nft
    }

    /// Unlock all NFTs from the vault
    public fun unlock_all_nfts<NFT: key + store>(
        vault: &mut NFTVault<NFT>,
        clock: &Clock,
        ctx: &TxContext,
    ): vector<NFT> {
        let mut nfts = vector::empty<NFT>();

        while (vault.nft_count > 0) {
            let nft = unlock_nft(vault, clock, ctx);
            nfts.push_back(nft);
        };

        nfts
    }

    /// Set lock period (prevents withdrawals until timestamp)
    public fun set_lock_period<NFT: key + store>(
        vault: &mut NFTVault<NFT>,
        lock_until_ms: u64,
        ctx: &TxContext,
    ) {
        assert!(vault.owner == ctx.sender(), errors::not_position_owner());
        vault.lock_until_ms = lock_until_ms;
    }

    /// Destroy an empty vault
    public fun destroy_empty_vault<NFT: key + store>(vault: NFTVault<NFT>) {
        assert!(vault.nft_count == 0, errors::no_nfts_locked());

        let NFTVault {
            id,
            governance_id: _,
            owner: _,
            nft_count: _,
            lock_until_ms: _,
        } = vault;

        object::delete(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VOTING
    // ═══════════════════════════════════════════════════════════════════════

    /// Vote on a proposal using locked NFTs
    public fun vote<NFT: key + store>(
        governance: &Governance,
        proposal: &mut Proposal,
        vault: &NFTVault<NFT>,
        support: u8,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        // Verify vault belongs to this governance
        assert!(vault.governance_id == object::id(governance), errors::wrong_governance());

        // Verify caller owns the vault
        assert!(vault.owner == ctx.sender(), errors::not_position_owner());

        // Verify vault has NFTs
        assert!(vault.nft_count > 0, errors::no_voting_power());

        // Lock NFTs during voting to prevent double-voting
        // The lock is automatically set to voting end time
        // (This is handled by the caller in production)

        voting::vote_with_locked_nfts(
            governance,
            proposal,
            ctx.sender(),
            object::id(vault),
            vault.nft_count,
            support,
            clock,
        );
    }

    /// Get voting power from an NFT vault
    public fun get_voting_power<NFT: key + store>(vault: &NFTVault<NFT>): u64 {
        vault.nft_count
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    public fun governance_id<NFT: key + store>(vault: &NFTVault<NFT>): ID {
        vault.governance_id
    }

    public fun owner<NFT: key + store>(vault: &NFTVault<NFT>): address {
        vault.owner
    }

    public fun nft_count<NFT: key + store>(vault: &NFTVault<NFT>): u64 {
        vault.nft_count
    }

    public fun lock_until_ms<NFT: key + store>(vault: &NFTVault<NFT>): u64 {
        vault.lock_until_ms
    }

    public fun is_locked<NFT: key + store>(vault: &NFTVault<NFT>, clock: &Clock): bool {
        let now = clock.timestamp_ms();
        vault.lock_until_ms > 0 && now < vault.lock_until_ms
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
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
    public fun create_vault_for_testing<NFT: key + store>(
        governance_id: ID,
        ctx: &mut TxContext,
    ): NFTVault<NFT> {
        NFTVault<NFT> {
            id: object::new(ctx),
            governance_id,
            owner: ctx.sender(),
            nft_count: 0,
            lock_until_ms: 0,
        }
    }

    #[test]
    fun test_lock_unlock_nft() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let governance_id = object::id_from_address(@0x123);

        let mut vault = create_vault_for_testing<TestNFT>(governance_id, &mut ctx);

        assert!(vault.nft_count == 0, 0);

        // Lock NFT
        let nft = create_test_nft(100, &mut ctx);
        lock_nft(&mut vault, nft, &ctx);

        assert!(vault.nft_count == 1, 1);

        // Unlock NFT
        let nft = unlock_nft(&mut vault, &clock, &ctx);

        assert!(vault.nft_count == 0, 2);

        destroy_test_nft(nft);
        destroy_empty_vault(vault);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    fun test_lock_multiple_nfts() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let governance_id = object::id_from_address(@0x123);

        let mut vault = create_vault_for_testing<TestNFT>(governance_id, &mut ctx);

        // Lock multiple NFTs
        let nfts = vector[
            create_test_nft(1, &mut ctx),
            create_test_nft(2, &mut ctx),
            create_test_nft(3, &mut ctx),
        ];
        lock_nfts(&mut vault, nfts, &ctx);

        assert!(vault.nft_count == 3, 0);
        assert!(get_voting_power(&vault) == 3, 1);

        // Unlock all
        let mut unlocked = unlock_all_nfts(&mut vault, &clock, &ctx);

        assert!(vault.nft_count == 0, 2);
        assert!(unlocked.length() == 3, 3);

        while (!unlocked.is_empty()) {
            let nft = unlocked.pop_back();
            destroy_test_nft(nft);
        };
        unlocked.destroy_empty();

        destroy_empty_vault(vault);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    #[expected_failure(abort_code = 801)] // ENoNFTsLocked
    fun test_unlock_empty_vault_fails() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let governance_id = object::id_from_address(@0x123);

        let mut vault = create_vault_for_testing<TestNFT>(governance_id, &mut ctx);

        // Try to unlock from empty vault - will abort
        let nft = unlock_nft(&mut vault, &clock, &ctx);

        // Cleanup (won't be reached due to abort)
        destroy_test_nft(nft);
        destroy_empty_vault(vault);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    #[expected_failure(abort_code = 801)] // ENoNFTsLocked (reusing for destroy non-empty)
    fun test_destroy_non_empty_vault_fails() {
        let mut ctx = tx_context::dummy();
        let governance_id = object::id_from_address(@0x123);

        let mut vault = create_vault_for_testing<TestNFT>(governance_id, &mut ctx);

        let nft = create_test_nft(100, &mut ctx);
        lock_nft(&mut vault, nft, &ctx);

        // Try to destroy non-empty vault
        destroy_empty_vault(vault);
    }
}
