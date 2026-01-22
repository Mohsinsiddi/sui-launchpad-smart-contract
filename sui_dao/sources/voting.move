/// Voting module - orchestrates voting with staking positions and NFT vaults
module sui_dao::voting {
    use sui::clock::Clock;
    use sui_dao::errors;
    use sui_dao::governance::{Self, Governance};
    use sui_dao::proposal::{Self, Proposal};
    use sui_staking::position::StakingPosition;

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING-BASED VOTING
    // ═══════════════════════════════════════════════════════════════════════

    /// Vote on a proposal using a staking position
    public fun vote_with_stake<StakeToken>(
        governance: &Governance,
        proposal: &mut Proposal,
        position: &StakingPosition<StakeToken>,
        support: u8,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        // Verify governance mode
        assert!(governance::is_staking_mode(governance), errors::wrong_voting_mode());

        // Verify position belongs to the correct staking pool
        let expected_pool_id = governance::staking_pool_id(governance);
        assert!(expected_pool_id.is_some(), errors::wrong_staking_pool());
        assert!(
            sui_staking::position::pool_id(position) == *expected_pool_id.borrow(),
            errors::wrong_staking_pool()
        );

        // Note: In Sui, only the owner can pass the position object,
        // so ownership is implicitly verified

        // Get voting power (staked amount)
        let voting_power = sui_staking::position::staked_amount(position);
        assert!(voting_power > 0, errors::no_voting_power());

        // Cast the vote
        proposal::cast_vote_with_position(
            proposal,
            ctx.sender(),
            object::id(position),
            support,
            voting_power,
            clock,
        );
    }

    /// Get voting power from a staking position
    public fun get_staking_voting_power<StakeToken>(
        position: &StakingPosition<StakeToken>,
    ): u64 {
        sui_staking::position::staked_amount(position)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NFT-BASED VOTING (via NFT Vault)
    // ═══════════════════════════════════════════════════════════════════════

    /// Vote on a proposal using locked NFTs (must be called from nft_vault module)
    public(package) fun vote_with_locked_nfts(
        governance: &Governance,
        proposal: &mut Proposal,
        voter: address,
        vault_id: ID,
        nft_count: u64,
        support: u8,
        clock: &Clock,
    ) {
        // Verify governance mode
        assert!(governance::is_nft_mode(governance), errors::wrong_voting_mode());

        // Get voting power (1 NFT = 1 vote)
        let voting_power = nft_count;
        assert!(voting_power > 0, errors::no_voting_power());

        // Cast the vote
        proposal::cast_vote_with_vault(
            proposal,
            voter,
            vault_id,
            support,
            voting_power,
            clock,
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_get_staking_voting_power() {
        // This is a unit test placeholder - full integration tests
        // would require setting up staking pools which is complex
        // The actual voting tests are in the integration tests
    }
}
