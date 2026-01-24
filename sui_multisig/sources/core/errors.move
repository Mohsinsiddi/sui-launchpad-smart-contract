/// Error codes for the multisig module
module sui_multisig::errors {

    // ═══════════════════════════════════════════════════════════════════════
    // WALLET ERRORS (100-199)
    // ═══════════════════════════════════════════════════════════════════════

    /// Threshold is zero
    const EZeroThreshold: u64 = 100;
    /// Threshold exceeds number of signers
    const EThresholdExceedsSigners: u64 = 101;
    /// No signers provided
    const ENoSigners: u64 = 102;
    /// Duplicate signer in list
    const EDuplicateSigner: u64 = 103;
    /// Signer already exists
    const ESignerExists: u64 = 104;
    /// Signer not found
    const ESignerNotFound: u64 = 105;
    /// Cannot remove last signer
    const ECannotRemoveLastSigner: u64 = 106;
    /// Wallet name too long
    const ENameTooLong: u64 = 107;

    // ═══════════════════════════════════════════════════════════════════════
    // PROPOSAL ERRORS (200-299)
    // ═══════════════════════════════════════════════════════════════════════

    /// Proposal already exists
    const EProposalExists: u64 = 200;
    /// Proposal not found
    const EProposalNotFound: u64 = 201;
    /// Proposal already executed
    const EProposalExecuted: u64 = 202;
    /// Proposal expired
    const EProposalExpired: u64 = 203;
    /// Proposal not ready for execution
    const EProposalNotReady: u64 = 204;
    /// Already approved
    const EAlreadyApproved: u64 = 205;
    /// Already rejected
    const EAlreadyRejected: u64 = 206;
    /// Not a signer
    const ENotSigner: u64 = 207;
    /// Proposal rejected
    const EProposalRejected: u64 = 208;
    /// Invalid nonce
    const EInvalidNonce: u64 = 209;
    /// Wrong wallet
    const EWrongWallet: u64 = 210;
    /// Proposal is cancelled
    const EProposalCancelled: u64 = 211;

    // ═══════════════════════════════════════════════════════════════════════
    // VAULT ERRORS (300-399)
    // ═══════════════════════════════════════════════════════════════════════

    /// Insufficient balance
    const EInsufficientBalance: u64 = 300;
    /// Zero amount
    const EZeroAmount: u64 = 301;
    /// Token type not found
    const ETokenNotFound: u64 = 302;
    /// NFT not found in vault
    const ENftNotFound: u64 = 303;
    /// NFT type mismatch
    const ENftTypeMismatch: u64 = 304;

    // ═══════════════════════════════════════════════════════════════════════
    // ACCESS ERRORS (400-499)
    // ═══════════════════════════════════════════════════════════════════════

    /// Not authorized
    const ENotAuthorized: u64 = 400;
    /// Not platform admin
    const ENotAdmin: u64 = 401;

    // ═══════════════════════════════════════════════════════════════════════
    // FEE ERRORS (500-599)
    // ═══════════════════════════════════════════════════════════════════════

    /// Insufficient fee
    const EInsufficientFee: u64 = 500;

    // ═══════════════════════════════════════════════════════════════════════
    // PLATFORM ERRORS (600-699)
    // ═══════════════════════════════════════════════════════════════════════

    /// Platform is paused
    const EPlatformPaused: u64 = 600;

    // ═══════════════════════════════════════════════════════════════════════
    // GETTER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    // Wallet errors
    public fun zero_threshold(): u64 { EZeroThreshold }
    public fun threshold_exceeds_signers(): u64 { EThresholdExceedsSigners }
    public fun no_signers(): u64 { ENoSigners }
    public fun duplicate_signer(): u64 { EDuplicateSigner }
    public fun signer_exists(): u64 { ESignerExists }
    public fun signer_not_found(): u64 { ESignerNotFound }
    public fun cannot_remove_last_signer(): u64 { ECannotRemoveLastSigner }
    public fun name_too_long(): u64 { ENameTooLong }

    // Proposal errors
    public fun proposal_exists(): u64 { EProposalExists }
    public fun proposal_not_found(): u64 { EProposalNotFound }
    public fun proposal_executed(): u64 { EProposalExecuted }
    public fun proposal_expired(): u64 { EProposalExpired }
    public fun proposal_not_ready(): u64 { EProposalNotReady }
    public fun already_approved(): u64 { EAlreadyApproved }
    public fun already_rejected(): u64 { EAlreadyRejected }
    public fun not_signer(): u64 { ENotSigner }
    public fun proposal_rejected(): u64 { EProposalRejected }
    public fun invalid_nonce(): u64 { EInvalidNonce }
    public fun wrong_wallet(): u64 { EWrongWallet }
    public fun proposal_cancelled(): u64 { EProposalCancelled }

    // Vault errors
    public fun insufficient_balance(): u64 { EInsufficientBalance }
    public fun zero_amount(): u64 { EZeroAmount }
    public fun token_not_found(): u64 { ETokenNotFound }
    public fun nft_not_found(): u64 { ENftNotFound }
    public fun nft_type_mismatch(): u64 { ENftTypeMismatch }

    // Access errors
    public fun not_authorized(): u64 { ENotAuthorized }
    public fun not_admin(): u64 { ENotAdmin }

    // Fee errors
    public fun insufficient_fee(): u64 { EInsufficientFee }

    // Platform errors
    public fun platform_paused(): u64 { EPlatformPaused }
}
