/// Events emitted by the multisig module
module sui_multisig::events {
    use sui::event;

    // ═══════════════════════════════════════════════════════════════════════
    // WALLET EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emitted when a new multisig wallet is created
    public struct WalletCreated has copy, drop {
        wallet_id: ID,
        vault_id: ID,
        name: std::string::String,
        threshold: u64,
        signers: vector<address>,
        creator: address,
    }

    /// Emitted when a signer is added to a wallet
    public struct SignerAdded has copy, drop {
        wallet_id: ID,
        signer: address,
        new_signer_count: u64,
    }

    /// Emitted when a signer is removed from a wallet
    public struct SignerRemoved has copy, drop {
        wallet_id: ID,
        signer: address,
        new_signer_count: u64,
    }

    /// Emitted when threshold is changed
    public struct ThresholdChanged has copy, drop {
        wallet_id: ID,
        old_threshold: u64,
        new_threshold: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PROPOSAL EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emitted when a proposal is created
    public struct ProposalCreated has copy, drop {
        proposal_id: ID,
        wallet_id: ID,
        proposer: address,
        action_type: u8,
        expires_at_ms: u64,
    }

    /// Emitted when a proposal is approved
    public struct ProposalApproved has copy, drop {
        proposal_id: ID,
        wallet_id: ID,
        approver: address,
        approval_count: u64,
        threshold: u64,
    }

    /// Emitted when a proposal is rejected
    public struct ProposalRejected has copy, drop {
        proposal_id: ID,
        wallet_id: ID,
        rejector: address,
        rejection_count: u64,
    }

    /// Emitted when a proposal is executed
    public struct ProposalExecuted has copy, drop {
        proposal_id: ID,
        wallet_id: ID,
        executor: address,
        action_type: u8,
    }

    /// Emitted when a proposal is cancelled
    public struct ProposalCancelled has copy, drop {
        proposal_id: ID,
        wallet_id: ID,
        cancelled_by: address,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VAULT EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emitted when tokens are deposited (works for any Coin<T> including SUI)
    public struct TokenDeposited has copy, drop {
        vault_id: ID,
        wallet_id: ID,
        token_type: std::ascii::String,
        depositor: address,
        amount: u64,
    }

    /// Emitted when tokens are withdrawn (works for any Coin<T> including SUI)
    public struct TokenWithdrawn has copy, drop {
        vault_id: ID,
        wallet_id: ID,
        token_type: std::ascii::String,
        recipient: address,
        amount: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CUSTOM TX EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emitted when a custom transaction auth is created
    public struct CustomTxAuthCreated has copy, drop {
        proposal_id: ID,
        wallet_id: ID,
        target_id: ID,
        function_name: std::string::String,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PLATFORM EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emitted when platform config is updated
    public struct PlatformConfigUpdated has copy, drop {
        creation_fee: u64,
        execution_fee: u64,
        updated_by: address,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMIT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    public fun emit_wallet_created(
        wallet_id: ID,
        vault_id: ID,
        name: std::string::String,
        threshold: u64,
        signers: vector<address>,
        creator: address,
    ) {
        event::emit(WalletCreated {
            wallet_id,
            vault_id,
            name,
            threshold,
            signers,
            creator,
        });
    }

    public fun emit_signer_added(
        wallet_id: ID,
        signer: address,
        new_signer_count: u64,
    ) {
        event::emit(SignerAdded {
            wallet_id,
            signer,
            new_signer_count,
        });
    }

    public fun emit_signer_removed(
        wallet_id: ID,
        signer: address,
        new_signer_count: u64,
    ) {
        event::emit(SignerRemoved {
            wallet_id,
            signer,
            new_signer_count,
        });
    }

    public fun emit_threshold_changed(
        wallet_id: ID,
        old_threshold: u64,
        new_threshold: u64,
    ) {
        event::emit(ThresholdChanged {
            wallet_id,
            old_threshold,
            new_threshold,
        });
    }

    public fun emit_proposal_created(
        proposal_id: ID,
        wallet_id: ID,
        proposer: address,
        action_type: u8,
        expires_at_ms: u64,
    ) {
        event::emit(ProposalCreated {
            proposal_id,
            wallet_id,
            proposer,
            action_type,
            expires_at_ms,
        });
    }

    public fun emit_proposal_approved(
        proposal_id: ID,
        wallet_id: ID,
        approver: address,
        approval_count: u64,
        threshold: u64,
    ) {
        event::emit(ProposalApproved {
            proposal_id,
            wallet_id,
            approver,
            approval_count,
            threshold,
        });
    }

    public fun emit_proposal_rejected(
        proposal_id: ID,
        wallet_id: ID,
        rejector: address,
        rejection_count: u64,
    ) {
        event::emit(ProposalRejected {
            proposal_id,
            wallet_id,
            rejector,
            rejection_count,
        });
    }

    public fun emit_proposal_executed(
        proposal_id: ID,
        wallet_id: ID,
        executor: address,
        action_type: u8,
    ) {
        event::emit(ProposalExecuted {
            proposal_id,
            wallet_id,
            executor,
            action_type,
        });
    }

    public fun emit_proposal_cancelled(
        proposal_id: ID,
        wallet_id: ID,
        cancelled_by: address,
    ) {
        event::emit(ProposalCancelled {
            proposal_id,
            wallet_id,
            cancelled_by,
        });
    }

    public fun emit_token_deposited(
        vault_id: ID,
        wallet_id: ID,
        token_type: std::ascii::String,
        depositor: address,
        amount: u64,
    ) {
        event::emit(TokenDeposited {
            vault_id,
            wallet_id,
            token_type,
            depositor,
            amount,
        });
    }

    public fun emit_token_withdrawn(
        vault_id: ID,
        wallet_id: ID,
        token_type: std::ascii::String,
        recipient: address,
        amount: u64,
    ) {
        event::emit(TokenWithdrawn {
            vault_id,
            wallet_id,
            token_type,
            recipient,
            amount,
        });
    }

    public fun emit_custom_tx_auth_created(
        proposal_id: ID,
        wallet_id: ID,
        target_id: ID,
        function_name: std::string::String,
    ) {
        event::emit(CustomTxAuthCreated {
            proposal_id,
            wallet_id,
            target_id,
            function_name,
        });
    }

    public fun emit_platform_config_updated(
        creation_fee: u64,
        execution_fee: u64,
        updated_by: address,
    ) {
        event::emit(PlatformConfigUpdated {
            creation_fee,
            execution_fee,
            updated_by,
        });
    }
}
