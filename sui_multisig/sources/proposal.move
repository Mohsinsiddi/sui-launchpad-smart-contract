/// Proposal module for multisig transaction proposals
/// Supports: token transfers (any Coin<T>), signer management, custom transactions
module sui_multisig::proposal {
    use sui::coin::Coin;
    use sui::sui::SUI;
    use sui::clock::Clock;
    use sui::vec_set::{Self, VecSet};

    use sui_multisig::registry::{Self, MultisigRegistry};
    use sui_multisig::wallet::{Self, MultisigWallet};
    use sui_multisig::vault::{Self, MultisigVault};
    use sui_multisig::errors;
    use sui_multisig::events;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS - Proposal Status
    // ═══════════════════════════════════════════════════════════════════════

    const STATUS_PENDING: u8 = 0;
    const STATUS_APPROVED: u8 = 1;
    const STATUS_REJECTED: u8 = 2;
    const STATUS_EXECUTED: u8 = 3;
    const STATUS_CANCELLED: u8 = 4;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS - Action Types
    // ═══════════════════════════════════════════════════════════════════════

    const ACTION_TRANSFER: u8 = 0;        // Generic transfer (any Coin<T>)
    const ACTION_ADD_SIGNER: u8 = 1;
    const ACTION_REMOVE_SIGNER: u8 = 2;
    const ACTION_CHANGE_THRESHOLD: u8 = 3;
    const ACTION_CUSTOM_TX: u8 = 4;       // Custom transaction authorization
    const ACTION_NFT_TRANSFER: u8 = 5;    // NFT transfer

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Multisig proposal
    public struct MultisigProposal has key, store {
        id: UID,
        /// Associated wallet ID
        wallet_id: ID,
        /// Wallet nonce at creation time (for replay protection)
        wallet_nonce: u64,
        /// Addresses that approved
        approvals: VecSet<address>,
        /// Addresses that rejected
        rejections: VecSet<address>,
        /// Current status
        status: u8,
        /// Action to execute
        action: ProposalAction,
        /// Expiration timestamp
        expires_at_ms: u64,
        /// Proposal description
        description: std::string::String,
        /// Proposer address
        proposer: address,
        /// Creation timestamp
        created_at_ms: u64,
    }

    /// Action to be executed
    public struct ProposalAction has store, copy, drop {
        /// Action type
        action_type: u8,
        /// Recipient address (for transfers, add signer)
        recipient: address,
        /// Amount (for transfers)
        amount: u64,
        /// Token type name (for transfers)
        token_type: std::ascii::String,
        /// New threshold value (for threshold change)
        new_threshold: u64,
        /// Target object ID (for custom tx or NFT transfer)
        target_id: ID,
        /// Function name (for custom tx - informational)
        function_name: std::string::String,
        /// NFT type name (for NFT transfers)
        nft_type: std::ascii::String,
    }

    /// Authorization "hot potato" for custom transactions
    /// External contracts consume this to verify multisig approval
    /// Has no abilities except being droppable via consume function
    public struct MultisigAuth {
        /// The wallet that authorized this action
        wallet_id: ID,
        /// The proposal that was executed
        proposal_id: ID,
        /// Target object this auth is for
        target_id: ID,
        /// Additional context
        function_name: std::string::String,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PROPOSAL CREATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a proposal to transfer any token type (including SUI)
    public fun propose_transfer<T>(
        wallet: &MultisigWallet,
        registry: &MultisigRegistry,
        recipient: address,
        amount: u64,
        description: std::string::String,
        clock: &Clock,
        ctx: &mut TxContext,
    ): MultisigProposal {
        assert!(amount > 0, errors::zero_amount());

        let type_name = std::type_name::get<T>();
        let type_string = std::type_name::into_string(type_name);

        let action = ProposalAction {
            action_type: ACTION_TRANSFER,
            recipient,
            amount,
            token_type: type_string,
            new_threshold: 0,
            target_id: object::id_from_address(@0x0),
            function_name: std::string::utf8(b""),
            nft_type: std::ascii::string(b""),
        };

        create_proposal_internal(wallet, registry, action, description, clock, ctx)
    }

    /// Create a proposal to add a signer
    public fun propose_add_signer(
        wallet: &MultisigWallet,
        registry: &MultisigRegistry,
        new_signer: address,
        description: std::string::String,
        clock: &Clock,
        ctx: &mut TxContext,
    ): MultisigProposal {
        let action = ProposalAction {
            action_type: ACTION_ADD_SIGNER,
            recipient: new_signer,
            amount: 0,
            token_type: std::ascii::string(b""),
            new_threshold: 0,
            target_id: object::id_from_address(@0x0),
            function_name: std::string::utf8(b""),
            nft_type: std::ascii::string(b""),
        };

        create_proposal_internal(wallet, registry, action, description, clock, ctx)
    }

    /// Create a proposal to remove a signer
    public fun propose_remove_signer(
        wallet: &MultisigWallet,
        registry: &MultisigRegistry,
        signer_to_remove: address,
        description: std::string::String,
        clock: &Clock,
        ctx: &mut TxContext,
    ): MultisigProposal {
        let action = ProposalAction {
            action_type: ACTION_REMOVE_SIGNER,
            recipient: signer_to_remove,
            amount: 0,
            token_type: std::ascii::string(b""),
            new_threshold: 0,
            target_id: object::id_from_address(@0x0),
            function_name: std::string::utf8(b""),
            nft_type: std::ascii::string(b""),
        };

        create_proposal_internal(wallet, registry, action, description, clock, ctx)
    }

    /// Create a proposal to change threshold
    public fun propose_change_threshold(
        wallet: &MultisigWallet,
        registry: &MultisigRegistry,
        new_threshold: u64,
        description: std::string::String,
        clock: &Clock,
        ctx: &mut TxContext,
    ): MultisigProposal {
        let action = ProposalAction {
            action_type: ACTION_CHANGE_THRESHOLD,
            recipient: @0x0,
            amount: 0,
            token_type: std::ascii::string(b""),
            new_threshold,
            target_id: object::id_from_address(@0x0),
            function_name: std::string::utf8(b""),
            nft_type: std::ascii::string(b""),
        };

        create_proposal_internal(wallet, registry, action, description, clock, ctx)
    }

    /// Create a proposal for custom transaction
    /// The target_id and function_name are informational -
    /// the actual execution happens when the auth is consumed by the target contract
    public fun propose_custom_tx(
        wallet: &MultisigWallet,
        registry: &MultisigRegistry,
        target_id: ID,
        function_name: std::string::String,
        description: std::string::String,
        clock: &Clock,
        ctx: &mut TxContext,
    ): MultisigProposal {
        let action = ProposalAction {
            action_type: ACTION_CUSTOM_TX,
            recipient: @0x0,
            amount: 0,
            token_type: std::ascii::string(b""),
            new_threshold: 0,
            target_id,
            function_name,
            nft_type: std::ascii::string(b""),
        };

        create_proposal_internal(wallet, registry, action, description, clock, ctx)
    }

    /// Create a proposal to transfer an NFT
    public fun propose_nft_transfer<T: key + store>(
        wallet: &MultisigWallet,
        registry: &MultisigRegistry,
        nft_id: ID,
        recipient: address,
        description: std::string::String,
        clock: &Clock,
        ctx: &mut TxContext,
    ): MultisigProposal {
        let type_name = std::type_name::get<T>();
        let type_string = std::type_name::into_string(type_name);

        let action = ProposalAction {
            action_type: ACTION_NFT_TRANSFER,
            recipient,
            amount: 0,
            token_type: std::ascii::string(b""),
            new_threshold: 0,
            target_id: nft_id,
            function_name: std::string::utf8(b""),
            nft_type: type_string,
        };

        create_proposal_internal(wallet, registry, action, description, clock, ctx)
    }

    /// Internal function to create a proposal
    fun create_proposal_internal(
        wallet: &MultisigWallet,
        registry: &MultisigRegistry,
        action: ProposalAction,
        description: std::string::String,
        clock: &Clock,
        ctx: &mut TxContext,
    ): MultisigProposal {
        let sender = ctx.sender();

        // Validate sender is a signer
        wallet.assert_is_signer(sender);

        let current_time = clock.timestamp_ms();
        let config = registry.config();
        let expires_at = current_time + registry::config_default_proposal_expiry_ms(config);

        let mut approvals = vec_set::empty();
        // Proposer automatically approves
        approvals.insert(sender);

        // Check if threshold is already reached (e.g., 1-of-1 wallet)
        let status = if (approvals.length() >= wallet.threshold()) {
            STATUS_APPROVED
        } else {
            STATUS_PENDING
        };

        let proposal_uid = object::new(ctx);
        let proposal_id = object::uid_to_inner(&proposal_uid);

        events::emit_proposal_created(
            proposal_id,
            wallet.wallet_id(),
            sender,
            action.action_type,
            expires_at,
        );

        MultisigProposal {
            id: proposal_uid,
            wallet_id: wallet.wallet_id(),
            wallet_nonce: wallet.nonce(),
            approvals,
            rejections: vec_set::empty(),
            status,
            action,
            expires_at_ms: expires_at,
            description,
            proposer: sender,
            created_at_ms: current_time,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VOTING
    // ═══════════════════════════════════════════════════════════════════════

    /// Approve a proposal
    public fun approve(
        proposal: &mut MultisigProposal,
        wallet: &MultisigWallet,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = ctx.sender();

        // Validations
        wallet.assert_is_signer(sender);
        assert!(proposal.wallet_id == wallet.wallet_id(), errors::wrong_wallet());
        assert!(proposal.status == STATUS_PENDING, errors::proposal_executed());
        assert!(clock.timestamp_ms() < proposal.expires_at_ms, errors::proposal_expired());
        assert!(!proposal.approvals.contains(&sender), errors::already_approved());

        // Remove from rejections if previously rejected
        if (proposal.rejections.contains(&sender)) {
            proposal.rejections.remove(&sender);
        };

        proposal.approvals.insert(sender);

        let approval_count = proposal.approvals.size();
        let threshold = wallet.threshold();

        // Check if threshold reached
        if (approval_count >= threshold) {
            proposal.status = STATUS_APPROVED;
        };

        events::emit_proposal_approved(
            object::id(proposal),
            wallet.wallet_id(),
            sender,
            approval_count,
            threshold,
        );
    }

    /// Reject a proposal
    public fun reject(
        proposal: &mut MultisigProposal,
        wallet: &MultisigWallet,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = ctx.sender();

        // Validations
        wallet.assert_is_signer(sender);
        assert!(proposal.wallet_id == wallet.wallet_id(), errors::wrong_wallet());
        assert!(proposal.status == STATUS_PENDING, errors::proposal_executed());
        assert!(clock.timestamp_ms() < proposal.expires_at_ms, errors::proposal_expired());
        assert!(!proposal.rejections.contains(&sender), errors::already_rejected());

        // Remove from approvals if previously approved
        if (proposal.approvals.contains(&sender)) {
            proposal.approvals.remove(&sender);
        };

        proposal.rejections.insert(sender);

        let rejection_count = proposal.rejections.size();
        let signer_count = wallet.signer_count();
        let threshold = wallet.threshold();

        // Check if rejection threshold reached (can't possibly reach approval threshold)
        if (rejection_count > signer_count - threshold) {
            proposal.status = STATUS_REJECTED;
        };

        events::emit_proposal_rejected(
            object::id(proposal),
            wallet.wallet_id(),
            sender,
            rejection_count,
        );
    }

    /// Cancel a proposal (proposer only)
    public fun cancel(
        proposal: &mut MultisigProposal,
        wallet: &MultisigWallet,
        ctx: &TxContext,
    ) {
        let sender = ctx.sender();

        // Only proposer can cancel
        assert!(sender == proposal.proposer, errors::not_authorized());
        assert!(proposal.wallet_id == wallet.wallet_id(), errors::wrong_wallet());
        assert!(proposal.status == STATUS_PENDING, errors::proposal_executed());

        proposal.status = STATUS_CANCELLED;

        events::emit_proposal_cancelled(
            object::id(proposal),
            wallet.wallet_id(),
            sender,
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXECUTION
    // ═══════════════════════════════════════════════════════════════════════

    /// Execute a token transfer proposal (works for any Coin<T> including SUI)
    public fun execute_transfer<T>(
        proposal: &mut MultisigProposal,
        wallet: &mut MultisigWallet,
        vault: &mut MultisigVault,
        registry: &mut MultisigRegistry,
        execution_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        // Validate execution conditions
        validate_execution(proposal, wallet, vault, clock, ctx);
        assert!(proposal.action.action_type == ACTION_TRANSFER, errors::proposal_not_ready());

        // Validate token type matches
        let type_name = std::type_name::get<T>();
        let type_string = std::type_name::into_string(type_name);
        assert!(proposal.action.token_type == type_string, errors::token_not_found());

        // Collect execution fee
        registry.collect_execution_fee(execution_fee);

        // Mark as executed
        proposal.status = STATUS_EXECUTED;
        wallet.increment_nonce();

        // Perform transfer
        let amount = proposal.action.amount;
        let recipient = proposal.action.recipient;

        events::emit_proposal_executed(
            object::id(proposal),
            wallet.wallet_id(),
            ctx.sender(),
            ACTION_TRANSFER,
        );

        vault::withdraw<T>(vault, amount, recipient, ctx)
    }

    /// Execute an add signer proposal
    public fun execute_add_signer(
        proposal: &mut MultisigProposal,
        wallet: &mut MultisigWallet,
        registry: &mut MultisigRegistry,
        execution_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        // Validate execution conditions
        validate_execution_no_vault(proposal, wallet, clock, ctx);
        assert!(proposal.action.action_type == ACTION_ADD_SIGNER, errors::proposal_not_ready());

        // Collect execution fee
        registry.collect_execution_fee(execution_fee);

        // Mark as executed
        proposal.status = STATUS_EXECUTED;
        wallet.increment_nonce();

        // Add signer
        let new_signer = proposal.action.recipient;
        wallet::add_signer(wallet, registry, new_signer);

        events::emit_proposal_executed(
            object::id(proposal),
            wallet.wallet_id(),
            ctx.sender(),
            ACTION_ADD_SIGNER,
        );
    }

    /// Execute a remove signer proposal
    public fun execute_remove_signer(
        proposal: &mut MultisigProposal,
        wallet: &mut MultisigWallet,
        registry: &mut MultisigRegistry,
        execution_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        // Validate execution conditions
        validate_execution_no_vault(proposal, wallet, clock, ctx);
        assert!(proposal.action.action_type == ACTION_REMOVE_SIGNER, errors::proposal_not_ready());

        // Collect execution fee
        registry.collect_execution_fee(execution_fee);

        // Mark as executed
        proposal.status = STATUS_EXECUTED;
        wallet.increment_nonce();

        // Remove signer
        let signer_to_remove = proposal.action.recipient;
        wallet::remove_signer(wallet, registry, signer_to_remove);

        events::emit_proposal_executed(
            object::id(proposal),
            wallet.wallet_id(),
            ctx.sender(),
            ACTION_REMOVE_SIGNER,
        );
    }

    /// Execute a change threshold proposal
    public fun execute_change_threshold(
        proposal: &mut MultisigProposal,
        wallet: &mut MultisigWallet,
        registry: &mut MultisigRegistry,
        execution_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        // Validate execution conditions
        validate_execution_no_vault(proposal, wallet, clock, ctx);
        assert!(proposal.action.action_type == ACTION_CHANGE_THRESHOLD, errors::proposal_not_ready());

        // Collect execution fee
        registry.collect_execution_fee(execution_fee);

        // Mark as executed
        proposal.status = STATUS_EXECUTED;
        wallet.increment_nonce();

        // Change threshold
        let new_threshold = proposal.action.new_threshold;
        wallet::change_threshold(wallet, registry, new_threshold);

        events::emit_proposal_executed(
            object::id(proposal),
            wallet.wallet_id(),
            ctx.sender(),
            ACTION_CHANGE_THRESHOLD,
        );
    }

    /// Execute a custom transaction proposal
    /// Returns a MultisigAuth that must be consumed by the target contract
    public fun execute_custom_tx(
        proposal: &mut MultisigProposal,
        wallet: &mut MultisigWallet,
        registry: &mut MultisigRegistry,
        execution_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &TxContext,
    ): MultisigAuth {
        // Validate execution conditions
        validate_execution_no_vault(proposal, wallet, clock, ctx);
        assert!(proposal.action.action_type == ACTION_CUSTOM_TX, errors::proposal_not_ready());

        // Collect execution fee
        registry.collect_execution_fee(execution_fee);

        // Mark as executed
        proposal.status = STATUS_EXECUTED;
        wallet.increment_nonce();

        let proposal_id = object::id(proposal);
        let wallet_id = wallet.wallet_id();

        events::emit_proposal_executed(
            proposal_id,
            wallet_id,
            ctx.sender(),
            ACTION_CUSTOM_TX,
        );

        events::emit_custom_tx_auth_created(
            proposal_id,
            wallet_id,
            proposal.action.target_id,
            proposal.action.function_name,
        );

        // Return authorization hot potato
        MultisigAuth {
            wallet_id,
            proposal_id,
            target_id: proposal.action.target_id,
            function_name: proposal.action.function_name,
        }
    }

    /// Execute an NFT transfer proposal
    public fun execute_nft_transfer<T: key + store>(
        proposal: &mut MultisigProposal,
        wallet: &mut MultisigWallet,
        vault: &mut MultisigVault,
        registry: &mut MultisigRegistry,
        execution_fee: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): T {
        // Validate execution conditions
        validate_execution(proposal, wallet, vault, clock, ctx);
        assert!(proposal.action.action_type == ACTION_NFT_TRANSFER, errors::proposal_not_ready());

        // Validate NFT type matches
        let type_name = std::type_name::get<T>();
        let type_string = std::type_name::into_string(type_name);
        assert!(proposal.action.nft_type == type_string, errors::nft_type_mismatch());

        // Collect execution fee
        registry.collect_execution_fee(execution_fee);

        // Mark as executed
        proposal.status = STATUS_EXECUTED;
        wallet.increment_nonce();

        // Get NFT details
        let nft_id = proposal.action.target_id;
        let recipient = proposal.action.recipient;

        events::emit_proposal_executed(
            object::id(proposal),
            wallet.wallet_id(),
            ctx.sender(),
            ACTION_NFT_TRANSFER,
        );

        // Withdraw NFT and return it (caller transfers to recipient)
        vault::withdraw_nft<T>(vault, nft_id, recipient)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // AUTHORIZATION CONSUMPTION
    // ═══════════════════════════════════════════════════════════════════════

    /// Consume the MultisigAuth - call this from external contracts to verify authorization
    /// Returns the authorization details for the consuming contract to verify
    public fun consume_auth(auth: MultisigAuth): (ID, ID, ID, std::string::String) {
        let MultisigAuth { wallet_id, proposal_id, target_id, function_name } = auth;
        (wallet_id, proposal_id, target_id, function_name)
    }

    /// Verify and consume auth for a specific target
    /// Aborts if the auth is not for the expected target
    public fun consume_auth_for_target(auth: MultisigAuth, expected_target_id: ID): (ID, ID) {
        let MultisigAuth { wallet_id, proposal_id, target_id, function_name: _ } = auth;
        assert!(target_id == expected_target_id, errors::not_authorized());
        (wallet_id, proposal_id)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Validate execution conditions
    fun validate_execution(
        proposal: &MultisigProposal,
        wallet: &MultisigWallet,
        vault: &MultisigVault,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = ctx.sender();

        // Must be a signer
        wallet.assert_is_signer(sender);

        // Proposal must belong to this wallet
        assert!(proposal.wallet_id == wallet.wallet_id(), errors::wrong_wallet());

        // Vault must belong to this wallet
        assert!(vault::wallet_id(vault) == wallet.wallet_id(), errors::wrong_wallet());

        // Proposal must be approved
        assert!(proposal.status == STATUS_APPROVED, errors::proposal_not_ready());

        // Must not be expired
        assert!(clock.timestamp_ms() < proposal.expires_at_ms, errors::proposal_expired());

        // Nonce must match
        assert!(proposal.wallet_nonce == wallet.nonce(), errors::invalid_nonce());
    }

    /// Validate execution conditions (no vault needed)
    fun validate_execution_no_vault(
        proposal: &MultisigProposal,
        wallet: &MultisigWallet,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = ctx.sender();

        // Must be a signer
        wallet.assert_is_signer(sender);

        // Proposal must belong to this wallet
        assert!(proposal.wallet_id == wallet.wallet_id(), errors::wrong_wallet());

        // Proposal must be approved
        assert!(proposal.status == STATUS_APPROVED, errors::proposal_not_ready());

        // Must not be expired
        assert!(clock.timestamp_ms() < proposal.expires_at_ms, errors::proposal_expired());

        // Nonce must match
        assert!(proposal.wallet_nonce == wallet.nonce(), errors::invalid_nonce());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun proposal_id(proposal: &MultisigProposal): ID {
        object::id(proposal)
    }

    public fun wallet_id(proposal: &MultisigProposal): ID {
        proposal.wallet_id
    }

    public fun wallet_nonce(proposal: &MultisigProposal): u64 {
        proposal.wallet_nonce
    }

    public fun approval_count(proposal: &MultisigProposal): u64 {
        proposal.approvals.size()
    }

    public fun rejection_count(proposal: &MultisigProposal): u64 {
        proposal.rejections.size()
    }

    public fun status(proposal: &MultisigProposal): u8 {
        proposal.status
    }

    public fun action_type(proposal: &MultisigProposal): u8 {
        proposal.action.action_type
    }

    public fun expires_at_ms(proposal: &MultisigProposal): u64 {
        proposal.expires_at_ms
    }

    public fun description(proposal: &MultisigProposal): std::string::String {
        proposal.description
    }

    public fun proposer(proposal: &MultisigProposal): address {
        proposal.proposer
    }

    public fun created_at_ms(proposal: &MultisigProposal): u64 {
        proposal.created_at_ms
    }

    public fun has_approved(proposal: &MultisigProposal, addr: address): bool {
        proposal.approvals.contains(&addr)
    }

    public fun has_rejected(proposal: &MultisigProposal, addr: address): bool {
        proposal.rejections.contains(&addr)
    }

    // Status constants
    public fun status_pending(): u8 { STATUS_PENDING }
    public fun status_approved(): u8 { STATUS_APPROVED }
    public fun status_rejected(): u8 { STATUS_REJECTED }
    public fun status_executed(): u8 { STATUS_EXECUTED }
    public fun status_cancelled(): u8 { STATUS_CANCELLED }

    // Action type constants
    public fun action_type_transfer(): u8 { ACTION_TRANSFER }
    public fun action_type_add_signer(): u8 { ACTION_ADD_SIGNER }
    public fun action_type_remove_signer(): u8 { ACTION_REMOVE_SIGNER }
    public fun action_type_change_threshold(): u8 { ACTION_CHANGE_THRESHOLD }
    public fun action_type_custom_tx(): u8 { ACTION_CUSTOM_TX }
    public fun action_type_nft_transfer(): u8 { ACTION_NFT_TRANSFER }

    // Action getters
    public fun action_recipient(proposal: &MultisigProposal): address {
        proposal.action.recipient
    }

    public fun action_amount(proposal: &MultisigProposal): u64 {
        proposal.action.amount
    }

    public fun action_token_type(proposal: &MultisigProposal): std::ascii::String {
        proposal.action.token_type
    }

    public fun action_new_threshold(proposal: &MultisigProposal): u64 {
        proposal.action.new_threshold
    }

    public fun action_target_id(proposal: &MultisigProposal): ID {
        proposal.action.target_id
    }

    public fun action_function_name(proposal: &MultisigProposal): std::string::String {
        proposal.action.function_name
    }

    public fun action_nft_type(proposal: &MultisigProposal): std::ascii::String {
        proposal.action.nft_type
    }

    /// Get NFT ID for NFT transfer proposals (alias for target_id)
    public fun action_nft_id(proposal: &MultisigProposal): ID {
        proposal.action.target_id
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun create_proposal_for_testing(
        wallet_id: ID,
        wallet_nonce: u64,
        action_type: u8,
        recipient: address,
        amount: u64,
        new_threshold: u64,
        expires_at_ms: u64,
        proposer: address,
        ctx: &mut TxContext,
    ): MultisigProposal {
        let mut approvals = vec_set::empty();
        approvals.insert(proposer);

        MultisigProposal {
            id: object::new(ctx),
            wallet_id,
            wallet_nonce,
            approvals,
            rejections: vec_set::empty(),
            status: STATUS_PENDING,
            action: ProposalAction {
                action_type,
                recipient,
                amount,
                token_type: std::ascii::string(b""),
                new_threshold,
                target_id: object::id_from_address(@0x0),
                function_name: std::string::utf8(b""),
                nft_type: std::ascii::string(b""),
            },
            expires_at_ms,
            description: std::string::utf8(b"Test proposal"),
            proposer,
            created_at_ms: 0,
        }
    }

    #[test_only]
    public fun destroy_proposal_for_testing(proposal: MultisigProposal) {
        let MultisigProposal {
            id,
            wallet_id: _,
            wallet_nonce: _,
            approvals: _,
            rejections: _,
            status: _,
            action: _,
            expires_at_ms: _,
            description: _,
            proposer: _,
            created_at_ms: _,
        } = proposal;

        object::delete(id);
    }

    #[test_only]
    public fun set_status_for_testing(proposal: &mut MultisigProposal, status: u8) {
        proposal.status = status;
    }

    #[test_only]
    public fun add_approval_for_testing(proposal: &mut MultisigProposal, approver: address) {
        if (!proposal.approvals.contains(&approver)) {
            proposal.approvals.insert(approver);
        }
    }

    #[test_only]
    public fun create_auth_for_testing(
        wallet_id: ID,
        proposal_id: ID,
        target_id: ID,
        function_name: std::string::String,
    ): MultisigAuth {
        MultisigAuth {
            wallet_id,
            proposal_id,
            target_id,
            function_name,
        }
    }
}
