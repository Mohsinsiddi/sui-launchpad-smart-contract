/// Error codes for the DAO module
module sui_dao::errors {
    // ═══════════════════════════════════════════════════════════════════════
    // PLATFORM ERRORS (100-199)
    // ═══════════════════════════════════════════════════════════════════════

    const EPlatformPaused: u64 = 100;
    const EInsufficientFee: u64 = 101;
    const ENotAdmin: u64 = 102;
    const EZeroAmount: u64 = 103;

    // ═══════════════════════════════════════════════════════════════════════
    // GOVERNANCE ERRORS (200-299)
    // ═══════════════════════════════════════════════════════════════════════

    const EGovernancePaused: u64 = 200;
    const EWrongVotingMode: u64 = 201;
    const EWrongStakingPool: u64 = 202;
    const EWrongNFTCollection: u64 = 203;
    const ENotDAOAdmin: u64 = 204;
    const EInvalidConfig: u64 = 205;
    const EGovernanceNotFound: u64 = 206;

    // ═══════════════════════════════════════════════════════════════════════
    // PROPOSAL ERRORS (300-399)
    // ═══════════════════════════════════════════════════════════════════════

    const EInsufficientVotingPower: u64 = 300;
    const EProposalNotActive: u64 = 301;
    const EProposalNotSucceeded: u64 = 302;
    const EProposalExpired: u64 = 303;
    const EProposalAlreadyExecuted: u64 = 304;
    const EProposalNotInTimelock: u64 = 305;
    const ETimelockNotExpired: u64 = 306;
    const EAlreadyVoted: u64 = 307;
    const EInvalidVoteOption: u64 = 308;
    const EProposalCancelled: u64 = 309;
    const EProposalVetoed: u64 = 310;
    const ENotProposer: u64 = 311;
    const EVotingNotStarted: u64 = 312;
    const EVotingEnded: u64 = 313;
    const ENoActions: u64 = 314;
    const ETooManyActions: u64 = 315;

    // ═══════════════════════════════════════════════════════════════════════
    // VOTING ERRORS (400-499)
    // ═══════════════════════════════════════════════════════════════════════

    const ENoVotingPower: u64 = 400;
    const ENotPositionOwner: u64 = 401;
    const EWrongGovernance: u64 = 402;
    const EVotingPeriodEnded: u64 = 403;

    // ═══════════════════════════════════════════════════════════════════════
    // COUNCIL ERRORS (500-599)
    // ═══════════════════════════════════════════════════════════════════════

    const ECouncilNotEnabled: u64 = 500;
    const ENotCouncilMember: u64 = 501;
    const EAlreadyCouncilMember: u64 = 502;
    const ECannotRemoveLastCouncilMember: u64 = 503;
    const EInsufficientCouncilVotes: u64 = 504;
    const EVetoWindowClosed: u64 = 505;
    const EAlreadyFastTracked: u64 = 506;
    const EAlreadyVetoed: u64 = 507;
    const EAlreadyVotedFastTrack: u64 = 508;
    const ENotEmergencyProposal: u64 = 509;

    // ═══════════════════════════════════════════════════════════════════════
    // GUARDIAN ERRORS (510-549)
    // ═══════════════════════════════════════════════════════════════════════

    const EGuardianNotSet: u64 = 510;
    const ENotGuardian: u64 = 511;
    const EAlreadyGuardian: u64 = 512;

    // ═══════════════════════════════════════════════════════════════════════
    // DELEGATION ERRORS (600-699)
    // ═══════════════════════════════════════════════════════════════════════

    const EDelegationNotEnabled: u64 = 600;
    const ECannotDelegateToSelf: u64 = 601;
    const ECircularDelegation: u64 = 602;
    const EDelegationLocked: u64 = 603;
    const ENotDelegator: u64 = 604;
    const EAlreadyDelegated: u64 = 605;
    const ENoDelegation: u64 = 606;

    // ═══════════════════════════════════════════════════════════════════════
    // TREASURY ERRORS (700-799)
    // ═══════════════════════════════════════════════════════════════════════

    const ETreasuryNotFound: u64 = 700;
    const EInsufficientTreasuryBalance: u64 = 701;
    const EWrongTreasury: u64 = 702;

    // ═══════════════════════════════════════════════════════════════════════
    // NFT VAULT ERRORS (800-899)
    // ═══════════════════════════════════════════════════════════════════════

    const ENFTsStillLocked: u64 = 800;
    const ENoNFTsLocked: u64 = 801;
    const EWrongVault: u64 = 802;

    // ═══════════════════════════════════════════════════════════════════════
    // CUSTOM TX ERRORS (900-999)
    // ═══════════════════════════════════════════════════════════════════════

    const ETargetNotAllowed: u64 = 900;
    const EWrongTarget: u64 = 901;
    const EAuthAlreadyConsumed: u64 = 902;

    // ═══════════════════════════════════════════════════════════════════════
    // GETTER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    // Platform
    public fun platform_paused(): u64 { EPlatformPaused }
    public fun insufficient_fee(): u64 { EInsufficientFee }
    public fun not_admin(): u64 { ENotAdmin }
    public fun zero_amount(): u64 { EZeroAmount }

    // Governance
    public fun governance_paused(): u64 { EGovernancePaused }
    public fun wrong_voting_mode(): u64 { EWrongVotingMode }
    public fun wrong_staking_pool(): u64 { EWrongStakingPool }
    public fun wrong_nft_collection(): u64 { EWrongNFTCollection }
    public fun not_dao_admin(): u64 { ENotDAOAdmin }
    public fun invalid_config(): u64 { EInvalidConfig }
    public fun governance_not_found(): u64 { EGovernanceNotFound }

    // Proposal
    public fun insufficient_voting_power(): u64 { EInsufficientVotingPower }
    public fun proposal_not_active(): u64 { EProposalNotActive }
    public fun proposal_not_succeeded(): u64 { EProposalNotSucceeded }
    public fun proposal_expired(): u64 { EProposalExpired }
    public fun proposal_already_executed(): u64 { EProposalAlreadyExecuted }
    public fun proposal_not_in_timelock(): u64 { EProposalNotInTimelock }
    public fun timelock_not_expired(): u64 { ETimelockNotExpired }
    public fun already_voted(): u64 { EAlreadyVoted }
    public fun invalid_vote_option(): u64 { EInvalidVoteOption }
    public fun proposal_cancelled(): u64 { EProposalCancelled }
    public fun proposal_vetoed(): u64 { EProposalVetoed }
    public fun not_proposer(): u64 { ENotProposer }
    public fun voting_not_started(): u64 { EVotingNotStarted }
    public fun voting_ended(): u64 { EVotingEnded }
    public fun no_actions(): u64 { ENoActions }
    public fun too_many_actions(): u64 { ETooManyActions }

    // Voting
    public fun no_voting_power(): u64 { ENoVotingPower }
    public fun not_position_owner(): u64 { ENotPositionOwner }
    public fun wrong_governance(): u64 { EWrongGovernance }
    public fun voting_period_ended(): u64 { EVotingPeriodEnded }

    // Council
    public fun council_not_enabled(): u64 { ECouncilNotEnabled }
    public fun not_council_member(): u64 { ENotCouncilMember }
    public fun already_council_member(): u64 { EAlreadyCouncilMember }
    public fun cannot_remove_last_council_member(): u64 { ECannotRemoveLastCouncilMember }
    public fun insufficient_council_votes(): u64 { EInsufficientCouncilVotes }
    public fun veto_window_closed(): u64 { EVetoWindowClosed }
    public fun already_fast_tracked(): u64 { EAlreadyFastTracked }
    public fun already_vetoed(): u64 { EAlreadyVetoed }
    public fun already_voted_fast_track(): u64 { EAlreadyVotedFastTrack }
    public fun not_emergency_proposal(): u64 { ENotEmergencyProposal }

    // Guardian
    public fun guardian_not_set(): u64 { EGuardianNotSet }
    public fun not_guardian(): u64 { ENotGuardian }
    public fun already_guardian(): u64 { EAlreadyGuardian }

    // Delegation
    public fun delegation_not_enabled(): u64 { EDelegationNotEnabled }
    public fun cannot_delegate_to_self(): u64 { ECannotDelegateToSelf }
    public fun circular_delegation(): u64 { ECircularDelegation }
    public fun delegation_locked(): u64 { EDelegationLocked }
    public fun not_delegator(): u64 { ENotDelegator }
    public fun already_delegated(): u64 { EAlreadyDelegated }
    public fun no_delegation(): u64 { ENoDelegation }

    // Treasury
    public fun treasury_not_found(): u64 { ETreasuryNotFound }
    public fun insufficient_treasury_balance(): u64 { EInsufficientTreasuryBalance }
    public fun wrong_treasury(): u64 { EWrongTreasury }

    // NFT Vault
    public fun nfts_still_locked(): u64 { ENFTsStillLocked }
    public fun no_nfts_locked(): u64 { ENoNFTsLocked }
    public fun wrong_vault(): u64 { EWrongVault }

    // Custom TX
    public fun target_not_allowed(): u64 { ETargetNotAllowed }
    public fun wrong_target(): u64 { EWrongTarget }
    public fun auth_already_consumed(): u64 { EAuthAlreadyConsumed }
}
