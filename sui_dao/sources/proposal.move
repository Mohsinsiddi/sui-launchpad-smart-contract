/// Proposal lifecycle management
module sui_dao::proposal {
    use std::string::String;
    use sui::clock::Clock;
    use sui::coin::Coin;
    use sui::sui::SUI;
    use sui::vec_set::{Self, VecSet};
    use sui_dao::errors;
    use sui_dao::events;
    use sui_dao::governance::{Self, Governance};
    use sui_dao::math;
    use sui_dao::registry::{Self, DAORegistry};

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Proposal statuses
    const STATUS_PENDING: u8 = 0;       // Waiting for voting to start
    const STATUS_ACTIVE: u8 = 1;        // Voting in progress
    const STATUS_SUCCEEDED: u8 = 2;     // Passed, waiting for timelock
    const STATUS_DEFEATED: u8 = 3;      // Failed (quorum not met or more against)
    const STATUS_QUEUED: u8 = 4;        // In timelock queue
    const STATUS_EXECUTED: u8 = 5;      // Successfully executed
    const STATUS_CANCELLED: u8 = 6;     // Cancelled by proposer
    const STATUS_VETOED: u8 = 7;        // Vetoed by council
    const STATUS_EXPIRED: u8 = 8;       // Execution window passed

    /// Vote options
    const VOTE_AGAINST: u8 = 0;
    const VOTE_FOR: u8 = 1;
    const VOTE_ABSTAIN: u8 = 2;

    /// Proposal action types
    const ACTION_TREASURY_TRANSFER: u8 = 0;
    const ACTION_CONFIG_UPDATE: u8 = 1;
    const ACTION_CUSTOM_TX: u8 = 2;
    const ACTION_TEXT: u8 = 3;          // Signal/text-only proposal

    /// Limits
    const MAX_ACTIONS: u64 = 10;
    const EXECUTION_WINDOW_MS: u64 = 604_800_000; // 7 days to execute after timelock

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// A proposal action to be executed
    public struct ProposalAction has store, copy, drop {
        /// Action type
        action_type: u8,
        /// Target object ID (treasury, config, etc.)
        target_id: Option<ID>,
        /// Token type for transfers (as type name)
        token_type: Option<std::ascii::String>,
        /// Amount for transfers
        amount: u64,
        /// Recipient for transfers
        recipient: Option<address>,
        /// Arbitrary data for custom actions
        data: vector<u8>,
    }

    /// A governance proposal
    public struct Proposal has key {
        id: UID,
        /// Associated governance
        governance_id: ID,
        /// Proposal number (sequential)
        proposal_number: u64,
        /// Proposer address
        proposer: address,
        /// Title
        title: String,
        /// Description hash (IPFS CID or URL)
        description_hash: String,
        /// Current status
        status: u8,
        /// Voting starts timestamp (ms)
        voting_starts_ms: u64,
        /// Voting ends timestamp (ms)
        voting_ends_ms: u64,
        /// Timelock expires timestamp (set when queued)
        execute_after_ms: u64,
        /// Execution window expires (set when queued)
        execution_deadline_ms: u64,
        /// Votes for
        for_votes: u64,
        /// Votes against
        against_votes: u64,
        /// Abstain votes
        abstain_votes: u64,
        /// Voters who have voted (to prevent double voting)
        voters: VecSet<address>,
        /// Staking positions that have voted (to prevent double voting)
        voted_positions: VecSet<ID>,
        /// NFT vaults that have voted (for NFT governance)
        voted_vaults: VecSet<ID>,
        /// Actions to execute
        actions: vector<ProposalAction>,
        /// Council members who voted to veto
        veto_votes: VecSet<address>,
        /// Council members who voted to fast-track
        fast_track_votes: VecSet<address>,
        /// Whether fast-tracked by council (majority approved)
        is_fast_tracked: bool,
        /// Custom timelock (for fast-tracked proposals)
        custom_timelock_ms: Option<u64>,
        /// Whether this is an emergency proposal (created by council)
        is_emergency: bool,
        /// Creation timestamp
        created_at_ms: u64,
    }

    /// Hot potato for custom TX authorization
    public struct DAOAuth {
        /// The proposal authorizing this TX
        proposal_id: ID,
        /// The governance authorizing this TX
        governance_id: ID,
        /// Target object this auth is for
        target_id: ID,
        /// Whether this auth has been consumed
        consumed: bool,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CREATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new proposal
    public fun create_proposal(
        registry: &mut DAORegistry,
        governance: &mut Governance,
        title: String,
        description_hash: String,
        actions: vector<ProposalAction>,
        voting_power: u64,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Proposal {
        registry::assert_not_paused(registry);
        governance::assert_not_paused(governance);
        governance::assert_meets_proposal_threshold(governance, voting_power);

        assert!(actions.length() > 0, errors::no_actions());
        assert!(actions.length() <= MAX_ACTIONS, errors::too_many_actions());

        registry::collect_proposal_fee(registry, payment);
        registry::increment_proposals(registry);
        governance::increment_proposal_count(governance);

        let now = clock.timestamp_ms();
        let voting_starts_ms = now + governance::voting_delay_ms(governance);
        let voting_ends_ms = voting_starts_ms + governance::voting_period_ms(governance);

        let proposal = Proposal {
            id: object::new(ctx),
            governance_id: object::id(governance),
            proposal_number: governance::proposal_count(governance),
            proposer: ctx.sender(),
            title,
            description_hash,
            status: STATUS_PENDING,
            voting_starts_ms,
            voting_ends_ms,
            execute_after_ms: 0,
            execution_deadline_ms: 0,
            for_votes: 0,
            against_votes: 0,
            abstain_votes: 0,
            voters: vec_set::empty(),
            voted_positions: vec_set::empty(),
            voted_vaults: vec_set::empty(),
            actions,
            veto_votes: vec_set::empty(),
            fast_track_votes: vec_set::empty(),
            is_fast_tracked: false,
            custom_timelock_ms: option::none(),
            is_emergency: false,
            created_at_ms: now,
        };

        events::emit_proposal_created(
            object::id(&proposal),
            object::id(governance),
            ctx.sender(),
            proposal.title,
            proposal.description_hash,
            proposal.actions.length(),
            voting_starts_ms,
            voting_ends_ms,
        );

        proposal
    }

    /// Create an emergency proposal (council only) - reduced voting delay
    /// Emergency proposals have 1 hour voting delay and 1 day voting period
    public(package) fun create_emergency_proposal(
        governance: &mut Governance,
        title: String,
        description_hash: String,
        actions: vector<ProposalAction>,
        council_member: address,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Proposal {
        governance::assert_not_paused(governance);

        assert!(actions.length() > 0, errors::no_actions());
        assert!(actions.length() <= MAX_ACTIONS, errors::too_many_actions());

        governance::increment_proposal_count(governance);

        let now = clock.timestamp_ms();
        // Emergency: 1 hour delay, 1 day voting period
        let voting_starts_ms = now + 3_600_000; // 1 hour
        let voting_ends_ms = voting_starts_ms + 86_400_000; // 1 day

        let proposal = Proposal {
            id: object::new(ctx),
            governance_id: object::id(governance),
            proposal_number: governance::proposal_count(governance),
            proposer: council_member,
            title,
            description_hash,
            status: STATUS_PENDING,
            voting_starts_ms,
            voting_ends_ms,
            execute_after_ms: 0,
            execution_deadline_ms: 0,
            for_votes: 0,
            against_votes: 0,
            abstain_votes: 0,
            voters: vec_set::empty(),
            voted_positions: vec_set::empty(),
            voted_vaults: vec_set::empty(),
            actions,
            veto_votes: vec_set::empty(),
            fast_track_votes: vec_set::empty(),
            is_fast_tracked: true, // Emergency proposals are auto-fast-tracked
            custom_timelock_ms: option::some(governance::fast_track_timelock_ms(governance)),
            is_emergency: true,
            created_at_ms: now,
        };

        events::emit_emergency_proposal_created(
            object::id(&proposal),
            object::id(governance),
            council_member,
            proposal.title,
            voting_starts_ms,
            voting_ends_ms,
        );

        proposal
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ACTION BUILDERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a treasury transfer action
    public fun create_treasury_transfer_action<T>(
        treasury_id: ID,
        amount: u64,
        recipient: address,
    ): ProposalAction {
        let token_type = std::type_name::with_original_ids<T>().into_string();
        ProposalAction {
            action_type: ACTION_TREASURY_TRANSFER,
            target_id: option::some(treasury_id),
            token_type: option::some(token_type),
            amount,
            recipient: option::some(recipient),
            data: vector::empty(),
        }
    }

    /// Create a config update action
    public fun create_config_update_action(data: vector<u8>): ProposalAction {
        ProposalAction {
            action_type: ACTION_CONFIG_UPDATE,
            target_id: option::none(),
            token_type: option::none(),
            amount: 0,
            recipient: option::none(),
            data,
        }
    }

    /// Create a custom TX action
    public fun create_custom_tx_action(target_id: ID, data: vector<u8>): ProposalAction {
        ProposalAction {
            action_type: ACTION_CUSTOM_TX,
            target_id: option::some(target_id),
            token_type: option::none(),
            amount: 0,
            recipient: option::none(),
            data,
        }
    }

    /// Create a text/signal proposal action (no execution)
    public fun create_text_action(data: vector<u8>): ProposalAction {
        ProposalAction {
            action_type: ACTION_TEXT,
            target_id: option::none(),
            token_type: option::none(),
            amount: 0,
            recipient: option::none(),
            data,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VOTING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Cast a vote using staking position
    public(package) fun cast_vote_with_position(
        proposal: &mut Proposal,
        voter: address,
        position_id: ID,
        support: u8,
        voting_power: u64,
        clock: &Clock,
    ) {
        assert_voting_active(proposal, clock);
        assert!(!proposal.voted_positions.contains(&position_id), errors::already_voted());
        assert!(support <= VOTE_ABSTAIN, errors::invalid_vote_option());

        proposal.voted_positions.insert(position_id);

        apply_vote(proposal, support, voting_power);

        events::emit_vote_cast_with_stake(
            object::id(proposal),
            voter,
            position_id,
            support,
            voting_power,
        );
    }

    /// Cast a vote using NFT vault
    public(package) fun cast_vote_with_vault(
        proposal: &mut Proposal,
        voter: address,
        vault_id: ID,
        support: u8,
        voting_power: u64,
        clock: &Clock,
    ) {
        assert_voting_active(proposal, clock);
        assert!(!proposal.voted_vaults.contains(&vault_id), errors::already_voted());
        assert!(support <= VOTE_ABSTAIN, errors::invalid_vote_option());

        proposal.voted_vaults.insert(vault_id);

        apply_vote(proposal, support, voting_power);

        events::emit_vote_cast_with_nft(
            object::id(proposal),
            voter,
            vault_id,
            support,
            voting_power,
        );
    }

    /// Cast a vote with delegated power
    public(package) fun cast_vote_with_delegation(
        proposal: &mut Proposal,
        voter: address,
        delegator: address,
        support: u8,
        voting_power: u64,
        clock: &Clock,
    ) {
        assert_voting_active(proposal, clock);
        assert!(!proposal.voters.contains(&delegator), errors::already_voted());
        assert!(support <= VOTE_ABSTAIN, errors::invalid_vote_option());

        proposal.voters.insert(delegator);

        apply_vote(proposal, support, voting_power);

        events::emit_vote_cast_with_delegation(
            object::id(proposal),
            voter,
            delegator,
            support,
            voting_power,
        );
    }

    fun apply_vote(proposal: &mut Proposal, support: u8, voting_power: u64) {
        if (support == VOTE_FOR) {
            proposal.for_votes = proposal.for_votes + voting_power;
        } else if (support == VOTE_AGAINST) {
            proposal.against_votes = proposal.against_votes + voting_power;
        } else {
            proposal.abstain_votes = proposal.abstain_votes + voting_power;
        };
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Update proposal status based on current state (called after voting ends)
    public fun finalize_voting(
        proposal: &mut Proposal,
        governance: &Governance,
        total_voting_power: u64,
        clock: &Clock,
    ) {
        let now = clock.timestamp_ms();
        assert!(proposal.status == STATUS_PENDING || proposal.status == STATUS_ACTIVE, errors::proposal_not_active());
        assert!(now >= proposal.voting_ends_ms, errors::voting_not_started());

        let total_votes = proposal.for_votes + proposal.against_votes + proposal.abstain_votes;

        // Check quorum
        let quorum_met = if (governance::is_staking_mode(governance)) {
            math::is_quorum_met(total_votes, total_voting_power, governance::quorum_bps(governance))
        } else {
            total_votes >= governance::quorum_votes(governance)
        };

        // Check if proposal passes
        let passes = math::proposal_passes_with_threshold(
            proposal.for_votes,
            proposal.against_votes,
            governance::approval_threshold_bps(governance),
        );

        if (quorum_met && passes) {
            proposal.status = STATUS_SUCCEEDED;

            // Set timelock
            let timelock = if (proposal.is_fast_tracked && proposal.custom_timelock_ms.is_some()) {
                *proposal.custom_timelock_ms.borrow()
            } else {
                governance::timelock_delay_ms(governance)
            };

            proposal.execute_after_ms = now + timelock;
            proposal.execution_deadline_ms = proposal.execute_after_ms + EXECUTION_WINDOW_MS;

            events::emit_proposal_queued(
                object::id(proposal),
                object::id(governance),
                proposal.execute_after_ms,
            );
        } else {
            proposal.status = STATUS_DEFEATED;
            events::emit_proposal_defeated(
                object::id(proposal),
                object::id(governance),
                proposal.for_votes,
                proposal.against_votes,
                proposal.abstain_votes,
            );
        }
    }

    /// Queue a successful proposal for execution
    public fun queue_proposal(
        proposal: &mut Proposal,
        governance: &Governance,
        clock: &Clock,
    ) {
        assert!(proposal.status == STATUS_SUCCEEDED, errors::proposal_not_succeeded());

        let now = clock.timestamp_ms();
        proposal.status = STATUS_QUEUED;

        // Timelock was already set in finalize_voting
        if (proposal.execute_after_ms == 0) {
            let timelock = if (proposal.is_fast_tracked && proposal.custom_timelock_ms.is_some()) {
                *proposal.custom_timelock_ms.borrow()
            } else {
                governance::timelock_delay_ms(governance)
            };
            proposal.execute_after_ms = now + timelock;
            proposal.execution_deadline_ms = proposal.execute_after_ms + EXECUTION_WINDOW_MS;
        };

        events::emit_proposal_queued(
            object::id(proposal),
            object::id(governance),
            proposal.execute_after_ms,
        );
    }

    /// Begin proposal execution (returns DAOAuth for each custom TX action)
    public fun begin_execution(
        registry: &mut DAORegistry,
        proposal: &mut Proposal,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &TxContext,
    ): vector<DAOAuth> {
        registry::assert_not_paused(registry);
        let now = clock.timestamp_ms();

        assert!(
            proposal.status == STATUS_QUEUED || proposal.status == STATUS_SUCCEEDED,
            errors::proposal_not_in_timelock()
        );
        assert!(now >= proposal.execute_after_ms, errors::timelock_not_expired());
        assert!(now <= proposal.execution_deadline_ms, errors::proposal_expired());

        registry::collect_execution_fee(registry, payment);

        // Generate auth for each custom TX action
        let mut auths = vector::empty<DAOAuth>();

        let mut i = 0;
        while (i < proposal.actions.length()) {
            let action = proposal.actions.borrow(i);
            if (action.action_type == ACTION_CUSTOM_TX && action.target_id.is_some()) {
                let auth = DAOAuth {
                    proposal_id: object::id(proposal),
                    governance_id: proposal.governance_id,
                    target_id: *action.target_id.borrow(),
                    consumed: false,
                };
                auths.push_back(auth);

                events::emit_custom_tx_authorized(
                    object::id(proposal),
                    proposal.governance_id,
                    *action.target_id.borrow(),
                );
            };
            i = i + 1;
        };

        proposal.status = STATUS_EXECUTED;

        events::emit_proposal_executed(
            object::id(proposal),
            proposal.governance_id,
            ctx.sender(),
        );

        auths
    }

    /// Consume a DAO auth (must be called by target contract)
    public fun consume_auth(auth: DAOAuth, target_id: ID) {
        assert!(!auth.consumed, errors::auth_already_consumed());
        assert!(auth.target_id == target_id, errors::wrong_target());

        let DAOAuth { proposal_id: _, governance_id: _, target_id: _, consumed: _ } = auth;
    }

    /// Cancel a proposal (only by proposer, only before voting ends)
    public fun cancel_proposal(
        proposal: &mut Proposal,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let now = clock.timestamp_ms();
        assert!(ctx.sender() == proposal.proposer, errors::not_proposer());
        assert!(
            proposal.status == STATUS_PENDING ||
            (proposal.status == STATUS_ACTIVE && now < proposal.voting_ends_ms),
            errors::proposal_not_active()
        );

        proposal.status = STATUS_CANCELLED;

        events::emit_proposal_cancelled(
            object::id(proposal),
            proposal.governance_id,
            ctx.sender(),
        );
    }

    /// Mark proposal as expired (after execution window passes)
    public fun mark_expired(proposal: &mut Proposal, clock: &Clock) {
        let now = clock.timestamp_ms();
        assert!(
            (proposal.status == STATUS_SUCCEEDED || proposal.status == STATUS_QUEUED) &&
            now > proposal.execution_deadline_ms,
            errors::proposal_not_in_timelock()
        );

        proposal.status = STATUS_EXPIRED;

        events::emit_proposal_expired(object::id(proposal), proposal.governance_id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COUNCIL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Cast a fast-track vote (council member)
    public(package) fun cast_fast_track_vote(
        proposal: &mut Proposal,
        council_member: address,
    ) {
        assert!(!proposal.is_fast_tracked, errors::already_fast_tracked());
        assert!(
            proposal.status == STATUS_PENDING || proposal.status == STATUS_ACTIVE,
            errors::proposal_not_active()
        );
        assert!(!proposal.fast_track_votes.contains(&council_member), errors::already_voted_fast_track());

        proposal.fast_track_votes.insert(council_member);
    }

    /// Execute fast-track after council majority is reached
    public(package) fun execute_fast_track(
        proposal: &mut Proposal,
        reduced_timelock_ms: u64,
        clock: &Clock,
    ) {
        assert!(!proposal.is_fast_tracked, errors::already_fast_tracked());
        assert!(
            proposal.status == STATUS_PENDING || proposal.status == STATUS_ACTIVE,
            errors::proposal_not_active()
        );

        proposal.is_fast_tracked = true;
        proposal.custom_timelock_ms = option::some(reduced_timelock_ms);

        // Reduce voting period for fast-tracked proposals
        let now = clock.timestamp_ms();
        if (now < proposal.voting_starts_ms) {
            // If voting hasn't started, skip the delay
            proposal.voting_starts_ms = now;
            proposal.voting_ends_ms = now + 86_400_000; // 1 day minimum voting
        };
    }

    /// Cast a veto vote (council member)
    public(package) fun cast_veto_vote(
        proposal: &mut Proposal,
        council_member: address,
        clock: &Clock,
    ) {
        let now = clock.timestamp_ms();

        // Can only veto during timelock period
        assert!(
            proposal.status == STATUS_SUCCEEDED || proposal.status == STATUS_QUEUED,
            errors::proposal_not_in_timelock()
        );
        assert!(now < proposal.execute_after_ms, errors::veto_window_closed());
        assert!(!proposal.veto_votes.contains(&council_member), errors::already_vetoed());

        proposal.veto_votes.insert(council_member);

        events::emit_council_veto_vote_cast(object::id(proposal), council_member);
    }

    /// Execute veto if threshold is met
    public(package) fun execute_veto(
        proposal: &mut Proposal,
        governance: &Governance,
    ) {
        let veto_count = proposal.veto_votes.length();
        let council_size = governance::council_size(governance);
        let threshold = math::council_veto_threshold(council_size);

        assert!(veto_count >= threshold, errors::insufficient_council_votes());

        proposal.status = STATUS_VETOED;

        events::emit_proposal_vetoed(
            object::id(proposal),
            object::id(governance),
            @0x0, // No specific member
            veto_count,
            threshold,
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    fun assert_voting_active(proposal: &Proposal, clock: &Clock) {
        let now = clock.timestamp_ms();

        // Auto-transition from PENDING to ACTIVE if voting period has started
        assert!(now >= proposal.voting_starts_ms, errors::voting_not_started());
        assert!(now < proposal.voting_ends_ms, errors::voting_ended());
        assert!(
            proposal.status == STATUS_PENDING || proposal.status == STATUS_ACTIVE,
            errors::proposal_not_active()
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    // Proposal getters
    public fun governance_id(proposal: &Proposal): ID { proposal.governance_id }
    public fun proposal_number(proposal: &Proposal): u64 { proposal.proposal_number }
    public fun proposer(proposal: &Proposal): address { proposal.proposer }
    public fun title(proposal: &Proposal): String { proposal.title }
    public fun description_hash(proposal: &Proposal): String { proposal.description_hash }
    public fun status(proposal: &Proposal): u8 { proposal.status }
    public fun voting_starts_ms(proposal: &Proposal): u64 { proposal.voting_starts_ms }
    public fun voting_ends_ms(proposal: &Proposal): u64 { proposal.voting_ends_ms }
    public fun execute_after_ms(proposal: &Proposal): u64 { proposal.execute_after_ms }
    public fun execution_deadline_ms(proposal: &Proposal): u64 { proposal.execution_deadline_ms }
    public fun for_votes(proposal: &Proposal): u64 { proposal.for_votes }
    public fun against_votes(proposal: &Proposal): u64 { proposal.against_votes }
    public fun abstain_votes(proposal: &Proposal): u64 { proposal.abstain_votes }
    public fun total_votes(proposal: &Proposal): u64 {
        proposal.for_votes + proposal.against_votes + proposal.abstain_votes
    }
    public fun action_count(proposal: &Proposal): u64 { proposal.actions.length() }
    public fun veto_vote_count(proposal: &Proposal): u64 { proposal.veto_votes.length() }
    public fun fast_track_vote_count(proposal: &Proposal): u64 { proposal.fast_track_votes.length() }
    public fun is_fast_tracked(proposal: &Proposal): bool { proposal.is_fast_tracked }
    public fun is_emergency(proposal: &Proposal): bool { proposal.is_emergency }
    public fun created_at_ms(proposal: &Proposal): u64 { proposal.created_at_ms }
    public fun has_voted_fast_track(proposal: &Proposal, member: address): bool {
        proposal.fast_track_votes.contains(&member)
    }

    // Status helpers
    public fun is_pending(proposal: &Proposal): bool { proposal.status == STATUS_PENDING }
    public fun is_active(proposal: &Proposal): bool { proposal.status == STATUS_ACTIVE }
    public fun is_succeeded(proposal: &Proposal): bool { proposal.status == STATUS_SUCCEEDED }
    public fun is_defeated(proposal: &Proposal): bool { proposal.status == STATUS_DEFEATED }
    public fun is_queued(proposal: &Proposal): bool { proposal.status == STATUS_QUEUED }
    public fun is_executed(proposal: &Proposal): bool { proposal.status == STATUS_EXECUTED }
    public fun is_cancelled(proposal: &Proposal): bool { proposal.status == STATUS_CANCELLED }
    public fun is_vetoed(proposal: &Proposal): bool { proposal.status == STATUS_VETOED }
    public fun is_expired(proposal: &Proposal): bool { proposal.status == STATUS_EXPIRED }

    // Check if address/position has voted
    public fun has_address_voted(proposal: &Proposal, voter: address): bool {
        proposal.voters.contains(&voter)
    }
    public fun has_position_voted(proposal: &Proposal, position_id: ID): bool {
        proposal.voted_positions.contains(&position_id)
    }
    public fun has_vault_voted(proposal: &Proposal, vault_id: ID): bool {
        proposal.voted_vaults.contains(&vault_id)
    }

    // Action getters
    public fun get_action(proposal: &Proposal, index: u64): &ProposalAction {
        proposal.actions.borrow(index)
    }
    public fun action_type(action: &ProposalAction): u8 { action.action_type }
    public fun action_target_id(action: &ProposalAction): Option<ID> { action.target_id }
    public fun action_token_type(action: &ProposalAction): Option<std::ascii::String> { action.token_type }
    public fun action_amount(action: &ProposalAction): u64 { action.amount }
    public fun action_recipient(action: &ProposalAction): Option<address> { action.recipient }
    public fun action_data(action: &ProposalAction): vector<u8> { action.data }

    // DAOAuth getters
    public fun auth_proposal_id(auth: &DAOAuth): ID { auth.proposal_id }
    public fun auth_governance_id(auth: &DAOAuth): ID { auth.governance_id }
    public fun auth_target_id(auth: &DAOAuth): ID { auth.target_id }
    public fun auth_is_consumed(auth: &DAOAuth): bool { auth.consumed }

    // Constants getters
    public fun status_pending(): u8 { STATUS_PENDING }
    public fun status_active(): u8 { STATUS_ACTIVE }
    public fun status_succeeded(): u8 { STATUS_SUCCEEDED }
    public fun status_defeated(): u8 { STATUS_DEFEATED }
    public fun status_queued(): u8 { STATUS_QUEUED }
    public fun status_executed(): u8 { STATUS_EXECUTED }
    public fun status_cancelled(): u8 { STATUS_CANCELLED }
    public fun status_vetoed(): u8 { STATUS_VETOED }
    public fun status_expired(): u8 { STATUS_EXPIRED }

    public fun vote_against(): u8 { VOTE_AGAINST }
    public fun vote_for(): u8 { VOTE_FOR }
    public fun vote_abstain(): u8 { VOTE_ABSTAIN }

    public fun action_treasury_transfer(): u8 { ACTION_TREASURY_TRANSFER }
    public fun action_config_update(): u8 { ACTION_CONFIG_UPDATE }
    public fun action_custom_tx(): u8 { ACTION_CUSTOM_TX }
    public fun action_text(): u8 { ACTION_TEXT }

    public fun max_actions(): u64 { MAX_ACTIONS }
    public fun execution_window_ms(): u64 { EXECUTION_WINDOW_MS }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun create_proposal_for_testing(
        governance_id: ID,
        proposer: address,
        actions: vector<ProposalAction>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Proposal {
        let now = clock.timestamp_ms();
        Proposal {
            id: object::new(ctx),
            governance_id,
            proposal_number: 1,
            proposer,
            title: std::string::utf8(b"Test Proposal"),
            description_hash: std::string::utf8(b"QmTest"),
            status: STATUS_PENDING,
            voting_starts_ms: now,  // Immediate start for testing
            voting_ends_ms: now + 86_400_000,  // 1 day
            execute_after_ms: 0,
            execution_deadline_ms: 0,
            for_votes: 0,
            against_votes: 0,
            abstain_votes: 0,
            voters: vec_set::empty(),
            voted_positions: vec_set::empty(),
            voted_vaults: vec_set::empty(),
            actions,
            veto_votes: vec_set::empty(),
            fast_track_votes: vec_set::empty(),
            is_fast_tracked: false,
            custom_timelock_ms: option::none(),
            is_emergency: false,
            created_at_ms: now,
        }
    }

    #[test_only]
    public fun destroy_proposal_for_testing(proposal: Proposal) {
        let Proposal {
            id,
            governance_id: _,
            proposal_number: _,
            proposer: _,
            title: _,
            description_hash: _,
            status: _,
            voting_starts_ms: _,
            voting_ends_ms: _,
            execute_after_ms: _,
            execution_deadline_ms: _,
            for_votes: _,
            against_votes: _,
            abstain_votes: _,
            voters: _,
            voted_positions: _,
            voted_vaults: _,
            actions: _,
            veto_votes: _,
            fast_track_votes: _,
            is_fast_tracked: _,
            custom_timelock_ms: _,
            is_emergency: _,
            created_at_ms: _,
        } = proposal;
        object::delete(id);
    }

    #[test_only]
    public fun set_status_for_testing(proposal: &mut Proposal, new_status: u8) {
        proposal.status = new_status;
    }

    #[test_only]
    public fun set_votes_for_testing(
        proposal: &mut Proposal,
        for_votes: u64,
        against_votes: u64,
        abstain_votes: u64,
    ) {
        proposal.for_votes = for_votes;
        proposal.against_votes = against_votes;
        proposal.abstain_votes = abstain_votes;
    }

    #[test_only]
    public fun set_execute_after_for_testing(proposal: &mut Proposal, execute_after_ms: u64) {
        proposal.execute_after_ms = execute_after_ms;
        proposal.execution_deadline_ms = execute_after_ms + EXECUTION_WINDOW_MS;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_text_proposal() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let governance_id = object::id_from_address(@0x123);

        let actions = vector[create_text_action(b"Vote on this!")];

        let proposal = create_proposal_for_testing(
            governance_id,
            @0xABC,
            actions,
            &clock,
            &mut ctx,
        );

        assert!(proposal.status == STATUS_PENDING, 0);
        assert!(proposal.for_votes == 0, 1);
        assert!(proposal.actions.length() == 1, 2);

        destroy_proposal_for_testing(proposal);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    fun test_create_treasury_transfer_action() {
        use sui::sui::SUI;

        let treasury_id = object::id_from_address(@0x456);
        let action = create_treasury_transfer_action<SUI>(treasury_id, 1000, @0xABC);

        assert!(action.action_type == ACTION_TREASURY_TRANSFER, 0);
        assert!(action.target_id == option::some(treasury_id), 1);
        assert!(action.amount == 1000, 2);
        assert!(action.recipient == option::some(@0xABC), 3);
    }

    #[test]
    fun test_cast_vote() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let governance_id = object::id_from_address(@0x123);

        let actions = vector[create_text_action(b"Test")];
        let mut proposal = create_proposal_for_testing(
            governance_id,
            @0xABC,
            actions,
            &clock,
            &mut ctx,
        );

        let position_id = object::id_from_address(@0x789);
        cast_vote_with_position(&mut proposal, @0xDEF, position_id, VOTE_FOR, 1000, &clock);

        assert!(proposal.for_votes == 1000, 0);
        assert!(proposal.voted_positions.contains(&position_id), 1);

        destroy_proposal_for_testing(proposal);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    fun test_vote_against_and_abstain() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let governance_id = object::id_from_address(@0x123);

        let actions = vector[create_text_action(b"Test")];
        let mut proposal = create_proposal_for_testing(
            governance_id,
            @0xABC,
            actions,
            &clock,
            &mut ctx,
        );

        let pos1 = object::id_from_address(@0x1);
        let pos2 = object::id_from_address(@0x2);
        let pos3 = object::id_from_address(@0x3);

        cast_vote_with_position(&mut proposal, @0x1, pos1, VOTE_FOR, 1000, &clock);
        cast_vote_with_position(&mut proposal, @0x2, pos2, VOTE_AGAINST, 500, &clock);
        cast_vote_with_position(&mut proposal, @0x3, pos3, VOTE_ABSTAIN, 200, &clock);

        assert!(proposal.for_votes == 1000, 0);
        assert!(proposal.against_votes == 500, 1);
        assert!(proposal.abstain_votes == 200, 2);
        assert!(total_votes(&proposal) == 1700, 3);

        destroy_proposal_for_testing(proposal);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    #[expected_failure(abort_code = 307)] // EAlreadyVoted
    fun test_double_vote_fails() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let governance_id = object::id_from_address(@0x123);

        let actions = vector[create_text_action(b"Test")];
        let mut proposal = create_proposal_for_testing(
            governance_id,
            @0xABC,
            actions,
            &clock,
            &mut ctx,
        );

        let position_id = object::id_from_address(@0x789);
        cast_vote_with_position(&mut proposal, @0xDEF, position_id, VOTE_FOR, 1000, &clock);
        cast_vote_with_position(&mut proposal, @0xDEF, position_id, VOTE_AGAINST, 500, &clock);

        destroy_proposal_for_testing(proposal);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    fun test_cancel_proposal() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let governance_id = object::id_from_address(@0x123);

        let actions = vector[create_text_action(b"Test")];
        let mut proposal = create_proposal_for_testing(
            governance_id,
            ctx.sender(), // proposer is sender
            actions,
            &clock,
            &mut ctx,
        );

        cancel_proposal(&mut proposal, &clock, &ctx);

        assert!(proposal.status == STATUS_CANCELLED, 0);

        destroy_proposal_for_testing(proposal);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    #[expected_failure(abort_code = 311)] // ENotProposer
    fun test_cancel_by_non_proposer_fails() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let governance_id = object::id_from_address(@0x123);

        let actions = vector[create_text_action(b"Test")];
        let mut proposal = create_proposal_for_testing(
            governance_id,
            @0xFED,  // Different proposer
            actions,
            &clock,
            &mut ctx,
        );

        // ctx.sender() is not the proposer
        cancel_proposal(&mut proposal, &clock, &ctx);

        destroy_proposal_for_testing(proposal);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    fun test_fast_track() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let governance_id = object::id_from_address(@0x123);

        let actions = vector[create_text_action(b"Test")];
        let mut proposal = create_proposal_for_testing(
            governance_id,
            @0xABC,
            actions,
            &clock,
            &mut ctx,
        );

        execute_fast_track(&mut proposal, 43_200_000, &clock); // 12 hour timelock

        assert!(proposal.is_fast_tracked == true, 0);
        assert!(proposal.custom_timelock_ms == option::some(43_200_000), 1);

        destroy_proposal_for_testing(proposal);
        sui::clock::destroy_for_testing(clock);
    }
}
