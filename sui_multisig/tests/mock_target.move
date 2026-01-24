/// Mock target contract for testing custom transactions
/// Demonstrates how external contracts integrate with multisig authorization
#[test_only]
module sui_multisig::mock_target {
    use sui_multisig::proposal::{Self, MultisigAuth};

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// A mock treasury that can only be controlled via multisig
    public struct MockTreasury has key, store {
        id: UID,
        /// Counter to track operations
        operation_count: u64,
        /// Last authorized wallet
        last_wallet_id: Option<ID>,
        /// Value that can be set via multisig
        value: u64,
        /// Paused state
        paused: bool,
    }

    /// A mock NFT for testing NFT vault operations
    public struct MockNFT has key, store {
        id: UID,
        /// NFT name
        name: std::string::String,
        /// NFT value/rarity
        value: u64,
    }

    /// Another mock NFT type for testing multiple NFT types
    public struct MockNFT2 has key, store {
        id: UID,
        /// NFT description
        description: std::string::String,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new mock treasury
    public fun create_treasury(ctx: &mut TxContext): MockTreasury {
        MockTreasury {
            id: object::new(ctx),
            operation_count: 0,
            last_wallet_id: option::none(),
            value: 0,
            paused: false,
        }
    }

    /// Create a new mock NFT
    public fun create_nft(
        name: std::string::String,
        value: u64,
        ctx: &mut TxContext,
    ): MockNFT {
        MockNFT {
            id: object::new(ctx),
            name,
            value,
        }
    }

    /// Create a new mock NFT2
    public fun create_nft2(
        description: std::string::String,
        ctx: &mut TxContext,
    ): MockNFT2 {
        MockNFT2 {
            id: object::new(ctx),
            description,
        }
    }

    /// Create and share a new mock treasury
    public fun create_and_share(ctx: &mut TxContext) {
        transfer::public_share_object(create_treasury(ctx));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MULTISIG-AUTHORIZED FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Set the treasury value - requires multisig authorization
    public fun set_value_with_auth(
        treasury: &mut MockTreasury,
        auth: MultisigAuth,
        new_value: u64,
    ) {
        // Verify the auth is for this treasury
        let (wallet_id, _proposal_id) = proposal::consume_auth_for_target(
            auth,
            object::id(treasury),
        );

        treasury.value = new_value;
        treasury.operation_count = treasury.operation_count + 1;
        treasury.last_wallet_id = option::some(wallet_id);
    }

    /// Pause the treasury - requires multisig authorization
    public fun pause_with_auth(
        treasury: &mut MockTreasury,
        auth: MultisigAuth,
    ) {
        let (wallet_id, _proposal_id) = proposal::consume_auth_for_target(
            auth,
            object::id(treasury),
        );

        treasury.paused = true;
        treasury.operation_count = treasury.operation_count + 1;
        treasury.last_wallet_id = option::some(wallet_id);
    }

    /// Unpause the treasury - requires multisig authorization
    public fun unpause_with_auth(
        treasury: &mut MockTreasury,
        auth: MultisigAuth,
    ) {
        let (wallet_id, _proposal_id) = proposal::consume_auth_for_target(
            auth,
            object::id(treasury),
        );

        treasury.paused = false;
        treasury.operation_count = treasury.operation_count + 1;
        treasury.last_wallet_id = option::some(wallet_id);
    }

    /// Execute arbitrary logic with auth - demonstrates consuming raw auth
    public fun execute_with_raw_auth(
        treasury: &mut MockTreasury,
        auth: MultisigAuth,
        increment: u64,
    ) {
        let (wallet_id, _proposal_id, target_id, _function_name) = proposal::consume_auth(auth);

        // Verify target matches
        assert!(target_id == object::id(treasury), 0);

        treasury.value = treasury.value + increment;
        treasury.operation_count = treasury.operation_count + 1;
        treasury.last_wallet_id = option::some(wallet_id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun treasury_id(treasury: &MockTreasury): ID {
        object::id(treasury)
    }

    public fun value(treasury: &MockTreasury): u64 {
        treasury.value
    }

    public fun operation_count(treasury: &MockTreasury): u64 {
        treasury.operation_count
    }

    public fun last_wallet_id(treasury: &MockTreasury): Option<ID> {
        treasury.last_wallet_id
    }

    public fun is_paused(treasury: &MockTreasury): bool {
        treasury.paused
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLEANUP
    // ═══════════════════════════════════════════════════════════════════════

    public fun destroy_treasury(treasury: MockTreasury) {
        let MockTreasury {
            id,
            operation_count: _,
            last_wallet_id: _,
            value: _,
            paused: _,
        } = treasury;
        object::delete(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NFT GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun nft_id(nft: &MockNFT): ID {
        object::id(nft)
    }

    public fun nft_name(nft: &MockNFT): std::string::String {
        nft.name
    }

    public fun nft_value(nft: &MockNFT): u64 {
        nft.value
    }

    public fun nft2_id(nft: &MockNFT2): ID {
        object::id(nft)
    }

    public fun nft2_description(nft: &MockNFT2): std::string::String {
        nft.description
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NFT CLEANUP
    // ═══════════════════════════════════════════════════════════════════════

    public fun destroy_nft(nft: MockNFT) {
        let MockNFT { id, name: _, value: _ } = nft;
        object::delete(id);
    }

    public fun destroy_nft2(nft: MockNFT2) {
        let MockNFT2 { id, description: _ } = nft;
        object::delete(id);
    }
}
