/// Delegation module - Delegate voting power to another address
module sui_dao::delegation {
    use sui::clock::Clock;
    use sui_dao::errors;
    use sui_dao::events;
    use sui_dao::governance::{Self, Governance};
    use sui_dao::proposal::{Self, Proposal};
    use sui_staking::position::StakingPosition;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// A delegation record - transferable NFT representing delegated voting power
    public struct DelegationRecord has key, store {
        id: UID,
        /// The governance this delegation belongs to
        governance_id: ID,
        /// The address that delegated their power
        delegator: address,
        /// The address receiving the delegated power
        delegate: address,
        /// The staking position ID being delegated
        position_id: ID,
        /// Amount of voting power delegated
        voting_power: u64,
        /// Lock until timestamp (prevents revocation before this time)
        lock_until_ms: u64,
        /// Creation timestamp
        created_at_ms: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DELEGATION MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a delegation from a staking position
    public fun delegate<StakeToken>(
        governance: &Governance,
        position: &StakingPosition<StakeToken>,
        delegate_to: address,
        lock_until_ms: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): DelegationRecord {
        // Verify delegation is enabled
        assert!(governance::is_delegation_enabled(governance), errors::delegation_not_enabled());

        // Verify governance mode (only staking mode supports delegation)
        assert!(governance::is_staking_mode(governance), errors::wrong_voting_mode());

        // Verify position belongs to correct staking pool
        let expected_pool_id = governance::staking_pool_id(governance);
        assert!(expected_pool_id.is_some(), errors::wrong_staking_pool());
        assert!(
            sui_staking::position::pool_id(position) == *expected_pool_id.borrow(),
            errors::wrong_staking_pool()
        );

        // Note: In Sui, only the owner can pass the position object,
        // so ownership is implicitly verified
        let delegator = ctx.sender();

        // Cannot delegate to self
        assert!(delegate_to != delegator, errors::cannot_delegate_to_self());

        let voting_power = sui_staking::position::staked_amount(position);
        assert!(voting_power > 0, errors::no_voting_power());

        let now = clock.timestamp_ms();

        let record = DelegationRecord {
            id: object::new(ctx),
            governance_id: object::id(governance),
            delegator,
            delegate: delegate_to,
            position_id: object::id(position),
            voting_power,
            lock_until_ms,
            created_at_ms: now,
        };

        events::emit_delegation_created(
            object::id(&record),
            object::id(governance),
            delegator,
            delegate_to,
            voting_power,
            if (lock_until_ms > 0) { option::some(lock_until_ms) } else { option::none() },
        );

        record
    }

    /// Revoke a delegation
    public fun revoke(
        record: DelegationRecord,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let DelegationRecord {
            id,
            governance_id,
            delegator,
            delegate,
            position_id: _,
            voting_power: _,
            lock_until_ms,
            created_at_ms: _,
        } = record;

        // Only delegator can revoke
        assert!(ctx.sender() == delegator, errors::not_delegator());

        // Check lock period
        let now = clock.timestamp_ms();
        assert!(lock_until_ms == 0 || now >= lock_until_ms, errors::delegation_locked());

        events::emit_delegation_revoked(
            object::uid_to_inner(&id),
            governance_id,
            delegator,
            delegate,
        );

        object::delete(id);
    }

    /// Transfer delegation to a new delegate
    public fun transfer_delegation(
        record: &mut DelegationRecord,
        new_delegate: address,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        // Only delegator can transfer
        assert!(ctx.sender() == record.delegator, errors::not_delegator());

        // Check lock period
        let now = clock.timestamp_ms();
        assert!(record.lock_until_ms == 0 || now >= record.lock_until_ms, errors::delegation_locked());

        // Cannot delegate to self
        assert!(new_delegate != record.delegator, errors::cannot_delegate_to_self());

        let old_delegate = record.delegate;
        record.delegate = new_delegate;

        events::emit_delegation_transferred(
            object::id(record),
            record.governance_id,
            record.delegator,
            old_delegate,
            new_delegate,
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VOTING WITH DELEGATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Vote on proposal using delegated power
    public fun vote_as_delegate(
        governance: &Governance,
        proposal: &mut Proposal,
        delegation: &DelegationRecord,
        support: u8,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        // Verify caller is the delegate
        assert!(ctx.sender() == delegation.delegate, errors::not_delegator());

        // Verify delegation matches governance
        assert!(delegation.governance_id == object::id(governance), errors::wrong_governance());

        // Cast vote using the delegation
        // Pass position_id to prevent double voting (direct + delegation)
        proposal::cast_vote_with_delegation(
            proposal,
            ctx.sender(),
            delegation.delegator,
            delegation.position_id,
            support,
            delegation.voting_power,
            clock,
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    public fun governance_id(record: &DelegationRecord): ID {
        record.governance_id
    }

    public fun delegator(record: &DelegationRecord): address {
        record.delegator
    }

    public fun delegate_address(record: &DelegationRecord): address {
        record.delegate
    }

    public fun position_id(record: &DelegationRecord): ID {
        record.position_id
    }

    public fun voting_power(record: &DelegationRecord): u64 {
        record.voting_power
    }

    public fun lock_until_ms(record: &DelegationRecord): u64 {
        record.lock_until_ms
    }

    public fun created_at_ms(record: &DelegationRecord): u64 {
        record.created_at_ms
    }

    public fun is_locked(record: &DelegationRecord, clock: &Clock): bool {
        let now = clock.timestamp_ms();
        record.lock_until_ms > 0 && now < record.lock_until_ms
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun create_delegation_for_testing(
        governance_id: ID,
        delegator: address,
        delegate: address,
        position_id: ID,
        voting_power: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): DelegationRecord {
        DelegationRecord {
            id: object::new(ctx),
            governance_id,
            delegator,
            delegate,
            position_id,
            voting_power,
            lock_until_ms: 0,
            created_at_ms: clock.timestamp_ms(),
        }
    }

    #[test_only]
    public fun destroy_delegation_for_testing(record: DelegationRecord) {
        let DelegationRecord {
            id,
            governance_id: _,
            delegator: _,
            delegate: _,
            position_id: _,
            voting_power: _,
            lock_until_ms: _,
            created_at_ms: _,
        } = record;
        object::delete(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_delegation() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let governance_id = object::id_from_address(@0x123);
        let position_id = object::id_from_address(@0x456);

        let record = create_delegation_for_testing(
            governance_id,
            @0xAAA,
            @0xBBB,
            position_id,
            1000,
            &clock,
            &mut ctx,
        );

        assert!(record.governance_id == governance_id, 0);
        assert!(record.delegator == @0xAAA, 1);
        assert!(record.delegate == @0xBBB, 2);
        assert!(record.voting_power == 1000, 3);
        assert!(record.lock_until_ms == 0, 4);

        destroy_delegation_for_testing(record);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    fun test_transfer_delegation() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let governance_id = object::id_from_address(@0x123);
        let position_id = object::id_from_address(@0x456);

        // Create delegation where sender is delegator
        let mut record = DelegationRecord {
            id: object::new(&mut ctx),
            governance_id,
            delegator: ctx.sender(), // sender is delegator
            delegate: @0xBBB,
            position_id,
            voting_power: 1000,
            lock_until_ms: 0,
            created_at_ms: clock.timestamp_ms(),
        };

        assert!(record.delegate == @0xBBB, 0);

        transfer_delegation(&mut record, @0xCCC, &clock, &ctx);

        assert!(record.delegate == @0xCCC, 1);

        destroy_delegation_for_testing(record);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    fun test_is_locked() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let governance_id = object::id_from_address(@0x123);
        let position_id = object::id_from_address(@0x456);

        // Not locked
        let record1 = DelegationRecord {
            id: object::new(&mut ctx),
            governance_id,
            delegator: @0xAAA,
            delegate: @0xBBB,
            position_id,
            voting_power: 1000,
            lock_until_ms: 0,
            created_at_ms: clock.timestamp_ms(),
        };
        assert!(!is_locked(&record1, &clock), 0);

        // Locked (far future)
        let record2 = DelegationRecord {
            id: object::new(&mut ctx),
            governance_id,
            delegator: @0xAAA,
            delegate: @0xBBB,
            position_id,
            voting_power: 1000,
            lock_until_ms: 999_999_999_999,
            created_at_ms: clock.timestamp_ms(),
        };
        assert!(is_locked(&record2, &clock), 1);

        destroy_delegation_for_testing(record1);
        destroy_delegation_for_testing(record2);
        sui::clock::destroy_for_testing(clock);
    }

    #[test]
    #[expected_failure(abort_code = 601)] // ECannotDelegateToSelf
    fun test_transfer_to_self_fails() {
        let mut ctx = tx_context::dummy();
        let clock = sui::clock::create_for_testing(&mut ctx);
        let governance_id = object::id_from_address(@0x123);
        let position_id = object::id_from_address(@0x456);

        let mut record = DelegationRecord {
            id: object::new(&mut ctx),
            governance_id,
            delegator: ctx.sender(),
            delegate: @0xBBB,
            position_id,
            voting_power: 1000,
            lock_until_ms: 0,
            created_at_ms: clock.timestamp_ms(),
        };

        // Try to transfer to self (delegator)
        transfer_delegation(&mut record, ctx.sender(), &clock, &ctx);

        destroy_delegation_for_testing(record);
        sui::clock::destroy_for_testing(clock);
    }
}
