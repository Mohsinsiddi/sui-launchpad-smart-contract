/// Events for the DAO module
module sui_dao::events {
    use sui::event;

    // ═══════════════════════════════════════════════════════════════════════
    // ORIGIN CONSTANTS - Track how DAO was created
    // ═══════════════════════════════════════════════════════════════════════

    /// DAO created directly by user (independent)
    const ORIGIN_INDEPENDENT: u8 = 0;
    /// DAO created via launchpad graduation
    const ORIGIN_LAUNCHPAD: u8 = 1;
    /// DAO created via partner platform
    const ORIGIN_PARTNER: u8 = 2;

    /// Get origin constant for independent creation
    public fun origin_independent(): u8 { ORIGIN_INDEPENDENT }
    /// Get origin constant for launchpad creation
    public fun origin_launchpad(): u8 { ORIGIN_LAUNCHPAD }
    /// Get origin constant for partner creation
    public fun origin_partner(): u8 { ORIGIN_PARTNER }

    // ═══════════════════════════════════════════════════════════════════════
    // PLATFORM EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct PlatformInitialized has copy, drop {
        registry_id: ID,
        admin: address,
    }

    public struct PlatformConfigUpdated has copy, drop {
        registry_id: ID,
        dao_creation_fee: u64,
        proposal_fee: u64,
        execution_fee: u64,
    }

    public struct PlatformPaused has copy, drop {
        registry_id: ID,
    }

    public struct PlatformUnpaused has copy, drop {
        registry_id: ID,
    }

    public struct FeesCollected has copy, drop {
        registry_id: ID,
        amount: u64,
        recipient: address,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GOVERNANCE EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct GovernanceCreated has copy, drop {
        governance_id: ID,
        creator: address,
        name: std::string::String,
        voting_mode: u8,
        staking_pool_id: Option<ID>,
        quorum_bps: u64,
        voting_delay_ms: u64,
        voting_period_ms: u64,
        timelock_delay_ms: u64,
        proposal_threshold: u64,
        // Origin tracking
        origin: u8,              // 0=independent, 1=launchpad, 2=partner
        origin_id: Option<ID>,   // Optional: launchpad pool ID or partner ID
        created_at: u64,         // Timestamp of creation
    }

    public struct NFTGovernanceCreated has copy, drop {
        governance_id: ID,
        creator: address,
        name: std::string::String,
        nft_collection_type: std::ascii::String,
        quorum_votes: u64,
        voting_delay_ms: u64,
        voting_period_ms: u64,
        timelock_delay_ms: u64,
        proposal_threshold: u64,
        // Origin tracking
        origin: u8,              // 0=independent, 1=launchpad, 2=partner
        origin_id: Option<ID>,   // Optional: launchpad pool ID or partner ID
        created_at: u64,         // Timestamp of creation
    }

    public struct GovernanceConfigUpdated has copy, drop {
        governance_id: ID,
        quorum_bps: u64,
        voting_delay_ms: u64,
        voting_period_ms: u64,
        timelock_delay_ms: u64,
        proposal_threshold: u64,
    }

    public struct GovernancePaused has copy, drop {
        governance_id: ID,
    }

    public struct GovernanceUnpaused has copy, drop {
        governance_id: ID,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PROPOSAL EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct ProposalCreated has copy, drop {
        proposal_id: ID,
        governance_id: ID,
        proposer: address,
        title: std::string::String,
        description_hash: std::string::String,
        action_count: u64,
        voting_starts_ms: u64,
        voting_ends_ms: u64,
    }

    public struct ProposalCancelled has copy, drop {
        proposal_id: ID,
        governance_id: ID,
        cancelled_by: address,
    }

    public struct ProposalQueued has copy, drop {
        proposal_id: ID,
        governance_id: ID,
        execute_after_ms: u64,
    }

    public struct ProposalExecuted has copy, drop {
        proposal_id: ID,
        governance_id: ID,
        executor: address,
    }

    public struct ProposalDefeated has copy, drop {
        proposal_id: ID,
        governance_id: ID,
        for_votes: u64,
        against_votes: u64,
        abstain_votes: u64,
    }

    public struct ProposalExpired has copy, drop {
        proposal_id: ID,
        governance_id: ID,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VOTING EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct VoteCast has copy, drop {
        proposal_id: ID,
        voter: address,
        support: u8,  // 0 = Against, 1 = For, 2 = Abstain
        voting_power: u64,
        reason: std::string::String,
    }

    public struct VoteCastWithStake has copy, drop {
        proposal_id: ID,
        voter: address,
        position_id: ID,
        support: u8,
        voting_power: u64,
    }

    public struct VoteCastWithNFT has copy, drop {
        proposal_id: ID,
        voter: address,
        vault_id: ID,
        support: u8,
        voting_power: u64,  // Number of NFTs
    }

    public struct VoteCastWithDelegation has copy, drop {
        proposal_id: ID,
        voter: address,
        delegator: address,
        support: u8,
        voting_power: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COUNCIL EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct CouncilEnabled has copy, drop {
        governance_id: ID,
        initial_members: vector<address>,
    }

    public struct CouncilMemberAdded has copy, drop {
        governance_id: ID,
        member: address,
        added_by: address,
    }

    public struct CouncilMemberRemoved has copy, drop {
        governance_id: ID,
        member: address,
        removed_by: address,
    }

    public struct ProposalFastTracked has copy, drop {
        proposal_id: ID,
        governance_id: ID,
        council_member: address,
        new_voting_ends_ms: u64,
        new_timelock_ms: u64,
    }

    public struct ProposalVetoed has copy, drop {
        proposal_id: ID,
        governance_id: ID,
        council_member: address,
        veto_count: u64,
        threshold: u64,
    }

    public struct CouncilVetoVoteCast has copy, drop {
        proposal_id: ID,
        council_member: address,
    }

    public struct CouncilFastTrackVoteCast has copy, drop {
        proposal_id: ID,
        governance_id: ID,
        council_member: address,
        current_votes: u64,
        threshold: u64,
    }

    public struct EmergencyProposalCreated has copy, drop {
        proposal_id: ID,
        governance_id: ID,
        proposer: address,
        title: std::string::String,
        voting_starts_ms: u64,
        voting_ends_ms: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GUARDIAN EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct GuardianSet has copy, drop {
        governance_id: ID,
        guardian: address,
        set_by: address,
    }

    public struct GuardianRemoved has copy, drop {
        governance_id: ID,
        old_guardian: address,
        removed_by: address,
    }

    public struct EmergencyPauseByGuardian has copy, drop {
        governance_id: ID,
        guardian: address,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DELEGATION EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct DelegationCreated has copy, drop {
        delegation_id: ID,
        governance_id: ID,
        delegator: address,
        delegate: address,
        voting_power: u64,
        lock_until_ms: Option<u64>,
    }

    public struct DelegationRevoked has copy, drop {
        delegation_id: ID,
        governance_id: ID,
        delegator: address,
        delegate: address,
    }

    public struct DelegationTransferred has copy, drop {
        delegation_id: ID,
        governance_id: ID,
        delegator: address,
        old_delegate: address,
        new_delegate: address,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TREASURY EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct TreasuryCreated has copy, drop {
        treasury_id: ID,
        governance_id: ID,
        creator: address,        // Who created the treasury
        created_at: u64,         // Timestamp of creation
    }

    public struct TreasuryDeposit has copy, drop {
        treasury_id: ID,
        token_type: std::ascii::String,
        amount: u64,
        depositor: address,
    }

    public struct TreasuryWithdrawal has copy, drop {
        treasury_id: ID,
        token_type: std::ascii::String,
        amount: u64,
        recipient: address,
        proposal_id: ID,
    }

    public struct TreasuryNFTDeposit has copy, drop {
        treasury_id: ID,
        nft_type: std::ascii::String,
        nft_id: ID,
        depositor: address,
    }

    public struct TreasuryNFTWithdrawal has copy, drop {
        treasury_id: ID,
        nft_type: std::ascii::String,
        nft_id: ID,
        recipient: address,
        proposal_id: ID,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NFT VAULT EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct NFTVaultCreated has copy, drop {
        vault_id: ID,
        governance_id: ID,
        owner: address,
    }

    public struct NFTLocked has copy, drop {
        vault_id: ID,
        nft_id: ID,
        owner: address,
    }

    public struct NFTUnlocked has copy, drop {
        vault_id: ID,
        nft_id: ID,
        owner: address,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CUSTOM TX EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct CustomTXAuthorized has copy, drop {
        proposal_id: ID,
        governance_id: ID,
        target_id: ID,
    }

    public struct CustomTXExecuted has copy, drop {
        proposal_id: ID,
        governance_id: ID,
        target_id: ID,
        executor: address,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMIT FUNCTIONS - Platform
    // ═══════════════════════════════════════════════════════════════════════

    public(package) fun emit_platform_initialized(registry_id: ID, admin: address) {
        event::emit(PlatformInitialized { registry_id, admin });
    }

    public(package) fun emit_platform_config_updated(
        registry_id: ID,
        dao_creation_fee: u64,
        proposal_fee: u64,
        execution_fee: u64,
    ) {
        event::emit(PlatformConfigUpdated {
            registry_id,
            dao_creation_fee,
            proposal_fee,
            execution_fee,
        });
    }

    public(package) fun emit_platform_paused(registry_id: ID) {
        event::emit(PlatformPaused { registry_id });
    }

    public(package) fun emit_platform_unpaused(registry_id: ID) {
        event::emit(PlatformUnpaused { registry_id });
    }

    public(package) fun emit_fees_collected(registry_id: ID, amount: u64, recipient: address) {
        event::emit(FeesCollected { registry_id, amount, recipient });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMIT FUNCTIONS - Governance
    // ═══════════════════════════════════════════════════════════════════════

    public(package) fun emit_governance_created(
        governance_id: ID,
        creator: address,
        name: std::string::String,
        voting_mode: u8,
        staking_pool_id: Option<ID>,
        quorum_bps: u64,
        voting_delay_ms: u64,
        voting_period_ms: u64,
        timelock_delay_ms: u64,
        proposal_threshold: u64,
        origin: u8,
        origin_id: Option<ID>,
        created_at: u64,
    ) {
        event::emit(GovernanceCreated {
            governance_id,
            creator,
            name,
            voting_mode,
            staking_pool_id,
            quorum_bps,
            voting_delay_ms,
            voting_period_ms,
            timelock_delay_ms,
            proposal_threshold,
            origin,
            origin_id,
            created_at,
        });
    }

    public(package) fun emit_nft_governance_created(
        governance_id: ID,
        creator: address,
        name: std::string::String,
        nft_collection_type: std::ascii::String,
        quorum_votes: u64,
        voting_delay_ms: u64,
        voting_period_ms: u64,
        timelock_delay_ms: u64,
        proposal_threshold: u64,
        origin: u8,
        origin_id: Option<ID>,
        created_at: u64,
    ) {
        event::emit(NFTGovernanceCreated {
            governance_id,
            creator,
            name,
            nft_collection_type,
            quorum_votes,
            voting_delay_ms,
            voting_period_ms,
            timelock_delay_ms,
            proposal_threshold,
            origin,
            origin_id,
            created_at,
        });
    }

    public(package) fun emit_governance_config_updated(
        governance_id: ID,
        quorum_bps: u64,
        voting_delay_ms: u64,
        voting_period_ms: u64,
        timelock_delay_ms: u64,
        proposal_threshold: u64,
    ) {
        event::emit(GovernanceConfigUpdated {
            governance_id,
            quorum_bps,
            voting_delay_ms,
            voting_period_ms,
            timelock_delay_ms,
            proposal_threshold,
        });
    }

    public(package) fun emit_governance_paused(governance_id: ID) {
        event::emit(GovernancePaused { governance_id });
    }

    public(package) fun emit_governance_unpaused(governance_id: ID) {
        event::emit(GovernanceUnpaused { governance_id });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMIT FUNCTIONS - Proposal
    // ═══════════════════════════════════════════════════════════════════════

    public(package) fun emit_proposal_created(
        proposal_id: ID,
        governance_id: ID,
        proposer: address,
        title: std::string::String,
        description_hash: std::string::String,
        action_count: u64,
        voting_starts_ms: u64,
        voting_ends_ms: u64,
    ) {
        event::emit(ProposalCreated {
            proposal_id,
            governance_id,
            proposer,
            title,
            description_hash,
            action_count,
            voting_starts_ms,
            voting_ends_ms,
        });
    }

    public(package) fun emit_proposal_cancelled(
        proposal_id: ID,
        governance_id: ID,
        cancelled_by: address,
    ) {
        event::emit(ProposalCancelled {
            proposal_id,
            governance_id,
            cancelled_by,
        });
    }

    public(package) fun emit_proposal_queued(
        proposal_id: ID,
        governance_id: ID,
        execute_after_ms: u64,
    ) {
        event::emit(ProposalQueued {
            proposal_id,
            governance_id,
            execute_after_ms,
        });
    }

    public(package) fun emit_proposal_executed(
        proposal_id: ID,
        governance_id: ID,
        executor: address,
    ) {
        event::emit(ProposalExecuted {
            proposal_id,
            governance_id,
            executor,
        });
    }

    public(package) fun emit_proposal_defeated(
        proposal_id: ID,
        governance_id: ID,
        for_votes: u64,
        against_votes: u64,
        abstain_votes: u64,
    ) {
        event::emit(ProposalDefeated {
            proposal_id,
            governance_id,
            for_votes,
            against_votes,
            abstain_votes,
        });
    }

    public(package) fun emit_proposal_expired(proposal_id: ID, governance_id: ID) {
        event::emit(ProposalExpired { proposal_id, governance_id });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMIT FUNCTIONS - Voting
    // ═══════════════════════════════════════════════════════════════════════

    public(package) fun emit_vote_cast(
        proposal_id: ID,
        voter: address,
        support: u8,
        voting_power: u64,
        reason: std::string::String,
    ) {
        event::emit(VoteCast {
            proposal_id,
            voter,
            support,
            voting_power,
            reason,
        });
    }

    public(package) fun emit_vote_cast_with_stake(
        proposal_id: ID,
        voter: address,
        position_id: ID,
        support: u8,
        voting_power: u64,
    ) {
        event::emit(VoteCastWithStake {
            proposal_id,
            voter,
            position_id,
            support,
            voting_power,
        });
    }

    public(package) fun emit_vote_cast_with_nft(
        proposal_id: ID,
        voter: address,
        vault_id: ID,
        support: u8,
        voting_power: u64,
    ) {
        event::emit(VoteCastWithNFT {
            proposal_id,
            voter,
            vault_id,
            support,
            voting_power,
        });
    }

    public(package) fun emit_vote_cast_with_delegation(
        proposal_id: ID,
        voter: address,
        delegator: address,
        support: u8,
        voting_power: u64,
    ) {
        event::emit(VoteCastWithDelegation {
            proposal_id,
            voter,
            delegator,
            support,
            voting_power,
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMIT FUNCTIONS - Council
    // ═══════════════════════════════════════════════════════════════════════

    public(package) fun emit_council_enabled(
        governance_id: ID,
        initial_members: vector<address>,
    ) {
        event::emit(CouncilEnabled {
            governance_id,
            initial_members,
        });
    }

    public(package) fun emit_council_member_added(
        governance_id: ID,
        member: address,
        added_by: address,
    ) {
        event::emit(CouncilMemberAdded {
            governance_id,
            member,
            added_by,
        });
    }

    public(package) fun emit_council_member_removed(
        governance_id: ID,
        member: address,
        removed_by: address,
    ) {
        event::emit(CouncilMemberRemoved {
            governance_id,
            member,
            removed_by,
        });
    }

    public(package) fun emit_proposal_fast_tracked(
        proposal_id: ID,
        governance_id: ID,
        council_member: address,
        new_voting_ends_ms: u64,
        new_timelock_ms: u64,
    ) {
        event::emit(ProposalFastTracked {
            proposal_id,
            governance_id,
            council_member,
            new_voting_ends_ms,
            new_timelock_ms,
        });
    }

    public(package) fun emit_proposal_vetoed(
        proposal_id: ID,
        governance_id: ID,
        council_member: address,
        veto_count: u64,
        threshold: u64,
    ) {
        event::emit(ProposalVetoed {
            proposal_id,
            governance_id,
            council_member,
            veto_count,
            threshold,
        });
    }

    public(package) fun emit_council_veto_vote_cast(
        proposal_id: ID,
        council_member: address,
    ) {
        event::emit(CouncilVetoVoteCast {
            proposal_id,
            council_member,
        });
    }

    public(package) fun emit_council_fast_track_vote_cast(
        proposal_id: ID,
        governance_id: ID,
        council_member: address,
        current_votes: u64,
        threshold: u64,
    ) {
        event::emit(CouncilFastTrackVoteCast {
            proposal_id,
            governance_id,
            council_member,
            current_votes,
            threshold,
        });
    }

    public(package) fun emit_emergency_proposal_created(
        proposal_id: ID,
        governance_id: ID,
        proposer: address,
        title: std::string::String,
        voting_starts_ms: u64,
        voting_ends_ms: u64,
    ) {
        event::emit(EmergencyProposalCreated {
            proposal_id,
            governance_id,
            proposer,
            title,
            voting_starts_ms,
            voting_ends_ms,
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMIT FUNCTIONS - Guardian
    // ═══════════════════════════════════════════════════════════════════════

    public(package) fun emit_guardian_set(
        governance_id: ID,
        guardian: address,
        set_by: address,
    ) {
        event::emit(GuardianSet {
            governance_id,
            guardian,
            set_by,
        });
    }

    public(package) fun emit_guardian_removed(
        governance_id: ID,
        old_guardian: address,
        removed_by: address,
    ) {
        event::emit(GuardianRemoved {
            governance_id,
            old_guardian,
            removed_by,
        });
    }

    public(package) fun emit_emergency_pause_by_guardian(
        governance_id: ID,
        guardian: address,
    ) {
        event::emit(EmergencyPauseByGuardian {
            governance_id,
            guardian,
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMIT FUNCTIONS - Delegation
    // ═══════════════════════════════════════════════════════════════════════

    public(package) fun emit_delegation_created(
        delegation_id: ID,
        governance_id: ID,
        delegator: address,
        delegate: address,
        voting_power: u64,
        lock_until_ms: Option<u64>,
    ) {
        event::emit(DelegationCreated {
            delegation_id,
            governance_id,
            delegator,
            delegate,
            voting_power,
            lock_until_ms,
        });
    }

    public(package) fun emit_delegation_revoked(
        delegation_id: ID,
        governance_id: ID,
        delegator: address,
        delegate: address,
    ) {
        event::emit(DelegationRevoked {
            delegation_id,
            governance_id,
            delegator,
            delegate,
        });
    }

    public(package) fun emit_delegation_transferred(
        delegation_id: ID,
        governance_id: ID,
        delegator: address,
        old_delegate: address,
        new_delegate: address,
    ) {
        event::emit(DelegationTransferred {
            delegation_id,
            governance_id,
            delegator,
            old_delegate,
            new_delegate,
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMIT FUNCTIONS - Treasury
    // ═══════════════════════════════════════════════════════════════════════

    public(package) fun emit_treasury_created(
        treasury_id: ID,
        governance_id: ID,
        creator: address,
        created_at: u64,
    ) {
        event::emit(TreasuryCreated { treasury_id, governance_id, creator, created_at });
    }

    public(package) fun emit_treasury_deposit(
        treasury_id: ID,
        token_type: std::ascii::String,
        amount: u64,
        depositor: address,
    ) {
        event::emit(TreasuryDeposit {
            treasury_id,
            token_type,
            amount,
            depositor,
        });
    }

    public(package) fun emit_treasury_withdrawal(
        treasury_id: ID,
        token_type: std::ascii::String,
        amount: u64,
        recipient: address,
        proposal_id: ID,
    ) {
        event::emit(TreasuryWithdrawal {
            treasury_id,
            token_type,
            amount,
            recipient,
            proposal_id,
        });
    }

    public(package) fun emit_treasury_nft_deposit(
        treasury_id: ID,
        nft_type: std::ascii::String,
        nft_id: ID,
        depositor: address,
    ) {
        event::emit(TreasuryNFTDeposit {
            treasury_id,
            nft_type,
            nft_id,
            depositor,
        });
    }

    public(package) fun emit_treasury_nft_withdrawal(
        treasury_id: ID,
        nft_type: std::ascii::String,
        nft_id: ID,
        recipient: address,
        proposal_id: ID,
    ) {
        event::emit(TreasuryNFTWithdrawal {
            treasury_id,
            nft_type,
            nft_id,
            recipient,
            proposal_id,
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMIT FUNCTIONS - NFT Vault
    // ═══════════════════════════════════════════════════════════════════════

    public(package) fun emit_nft_vault_created(
        vault_id: ID,
        governance_id: ID,
        owner: address,
    ) {
        event::emit(NFTVaultCreated {
            vault_id,
            governance_id,
            owner,
        });
    }

    public(package) fun emit_nft_locked(vault_id: ID, nft_id: ID, owner: address) {
        event::emit(NFTLocked { vault_id, nft_id, owner });
    }

    public(package) fun emit_nft_unlocked(vault_id: ID, nft_id: ID, owner: address) {
        event::emit(NFTUnlocked { vault_id, nft_id, owner });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMIT FUNCTIONS - Custom TX
    // ═══════════════════════════════════════════════════════════════════════

    public(package) fun emit_custom_tx_authorized(
        proposal_id: ID,
        governance_id: ID,
        target_id: ID,
    ) {
        event::emit(CustomTXAuthorized {
            proposal_id,
            governance_id,
            target_id,
        });
    }

    public(package) fun emit_custom_tx_executed(
        proposal_id: ID,
        governance_id: ID,
        target_id: ID,
        executor: address,
    ) {
        event::emit(CustomTXExecuted {
            proposal_id,
            governance_id,
            target_id,
            executor,
        });
    }
}
