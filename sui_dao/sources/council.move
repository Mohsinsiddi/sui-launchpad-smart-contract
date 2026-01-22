/// Council module - Fast-track, veto, and emergency powers for council members
module sui_dao::council {
    use std::string::String;
    use sui::clock::Clock;
    use sui_dao::access::CouncilCap;
    use sui_dao::errors;
    use sui_dao::events;
    use sui_dao::governance::{Self, Governance};
    use sui_dao::math;
    use sui_dao::proposal::{Self, Proposal, ProposalAction};

    // ═══════════════════════════════════════════════════════════════════════
    // FAST-TRACK (Requires Council Majority)
    // ═══════════════════════════════════════════════════════════════════════

    /// Vote to fast-track a proposal (requires council majority > 50%)
    /// Once majority is reached, the proposal is automatically fast-tracked
    public fun vote_to_fast_track(
        council_cap: &CouncilCap,
        governance: &Governance,
        proposal: &mut Proposal,
        clock: &Clock,
    ) {
        // Verify council is enabled
        assert!(governance::is_council_enabled(governance), errors::council_not_enabled());

        // Verify cap matches governance
        sui_dao::access::assert_council_cap_matches(council_cap, object::id(governance));

        // Verify caller is a council member
        let member = sui_dao::access::council_cap_member(council_cap);
        assert!(governance::is_council_member(governance, member), errors::not_council_member());

        // Cast fast-track vote
        proposal::cast_fast_track_vote(proposal, member);

        // Check if majority is reached
        let vote_count = proposal::fast_track_vote_count(proposal);
        let council_size = governance::council_size(governance);
        let threshold = math::council_majority_threshold(council_size);

        events::emit_council_fast_track_vote_cast(
            object::id(proposal),
            object::id(governance),
            member,
            vote_count,
            threshold,
        );

        // Auto-execute fast-track when majority is reached
        if (vote_count >= threshold) {
            let reduced_timelock = governance::fast_track_timelock_ms(governance);
            proposal::execute_fast_track(proposal, reduced_timelock, clock);

            events::emit_proposal_fast_tracked(
                object::id(proposal),
                object::id(governance),
                member,
                proposal::voting_ends_ms(proposal),
                reduced_timelock,
            );
        };
    }

    /// Check how many more fast-track votes are needed
    public fun fast_track_votes_needed(
        governance: &Governance,
        proposal: &Proposal,
    ): u64 {
        let council_size = governance::council_size(governance);
        let threshold = math::council_majority_threshold(council_size);
        let current = proposal::fast_track_vote_count(proposal);

        if (current >= threshold) {
            0
        } else {
            threshold - current
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMERGENCY PROPOSALS (Council Only)
    // ═══════════════════════════════════════════════════════════════════════

    /// Create an emergency proposal (council member only)
    /// Emergency proposals have reduced voting delay (1 hour) and period (1 day)
    public fun create_emergency_proposal(
        council_cap: &CouncilCap,
        governance: &mut Governance,
        title: String,
        description_hash: String,
        actions: vector<ProposalAction>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Proposal {
        // Verify council is enabled
        assert!(governance::is_council_enabled(governance), errors::council_not_enabled());

        // Verify cap matches governance
        sui_dao::access::assert_council_cap_matches(council_cap, object::id(governance));

        // Verify caller is a council member
        let member = sui_dao::access::council_cap_member(council_cap);
        assert!(governance::is_council_member(governance, member), errors::not_council_member());

        // Create the emergency proposal
        proposal::create_emergency_proposal(
            governance,
            title,
            description_hash,
            actions,
            member,
            clock,
            ctx,
        )
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VETO
    // ═══════════════════════════════════════════════════════════════════════

    /// Cast a veto vote on a proposal
    public fun vote_to_veto(
        council_cap: &CouncilCap,
        governance: &Governance,
        proposal: &mut Proposal,
        clock: &Clock,
    ) {
        // Verify council is enabled
        assert!(governance::is_council_enabled(governance), errors::council_not_enabled());

        // Verify cap matches governance
        sui_dao::access::assert_council_cap_matches(council_cap, object::id(governance));

        // Verify caller is a council member
        let member = sui_dao::access::council_cap_member(council_cap);
        assert!(governance::is_council_member(governance, member), errors::not_council_member());

        // Cast veto vote
        proposal::cast_veto_vote(proposal, member, clock);

        // Check if veto threshold is met
        let veto_count = proposal::veto_vote_count(proposal);
        let council_size = governance::council_size(governance);
        let threshold = math::council_veto_threshold(council_size);

        if (veto_count >= threshold) {
            // Execute the veto
            proposal::execute_veto(proposal, governance);
        };
    }

    /// Check if proposal can be vetoed (during timelock period)
    public fun can_veto(
        governance: &Governance,
        proposal: &Proposal,
        clock: &Clock,
    ): bool {
        if (!governance::is_council_enabled(governance)) {
            return false
        };

        let status = proposal::status(proposal);
        if (status != proposal::status_succeeded() && status != proposal::status_queued()) {
            return false
        };

        let now = clock.timestamp_ms();
        now < proposal::execute_after_ms(proposal)
    }

    /// Check how many more veto votes are needed
    public fun veto_votes_needed(
        governance: &Governance,
        proposal: &Proposal,
    ): u64 {
        let council_size = governance::council_size(governance);
        let threshold = math::council_veto_threshold(council_size);
        let current = proposal::veto_vote_count(proposal);

        if (current >= threshold) {
            0
        } else {
            threshold - current
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get the fast-track threshold for a governance
    public fun get_fast_track_threshold(governance: &Governance): u64 {
        let council_size = governance::council_size(governance);
        math::council_majority_threshold(council_size)
    }

    /// Get the veto threshold for a governance
    public fun get_veto_threshold(governance: &Governance): u64 {
        let council_size = governance::council_size(governance);
        math::council_veto_threshold(council_size)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_fast_track_threshold() {
        // 3 member council needs 2 votes for majority (3/2 + 1 = 2)
        assert!(math::council_majority_threshold(3) == 2, 0);
        // 5 member council needs 3 votes for majority
        assert!(math::council_majority_threshold(5) == 3, 1);
        // 7 member council needs 4 votes for majority
        assert!(math::council_majority_threshold(7) == 4, 2);
    }

    #[test]
    fun test_veto_threshold() {
        // 3 member council needs 2 veto votes (1/3 + 1 = 2)
        assert!(math::council_veto_threshold(3) == 2, 0);
        // 6 member council needs 3 veto votes
        assert!(math::council_veto_threshold(6) == 3, 1);
        // 9 member council needs 4 veto votes
        assert!(math::council_veto_threshold(9) == 4, 2);
    }
}
