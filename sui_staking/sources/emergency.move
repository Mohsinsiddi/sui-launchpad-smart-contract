/// Emergency Actions module for Staking
///
/// Provides emergency functionality:
/// 1. Guardian System - Trusted address that can emergency pause
/// 2. Emergency Unstake - Bypass lock period (with penalty)
/// 3. Emergency State tracking
module sui_staking::emergency {

    use sui::clock::Clock;
    use sui::coin::{Self, Coin};
    use sui::event;

    use sui_staking::access::PoolAdminCap;
    use sui_staking::pool::{Self, StakingPool};
    use sui_staking::position::{Self, StakingPosition};
    use sui_staking::errors;
    use sui_staking::math;

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    const ENotGuardian: u64 = 600;
    const EGuardianNotSet: u64 = 601;
    const EAlreadyGuardian: u64 = 602;
    const ENotInEmergency: u64 = 603;
    const EAlreadyInEmergency: u64 = 604;
    const EWrongPool: u64 = 605;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emergency unstake penalty multiplier (2x normal early fee)
    const EMERGENCY_FEE_MULTIPLIER: u64 = 2;

    /// Maximum emergency fee (25% = 2500 bps)
    const MAX_EMERGENCY_FEE_BPS: u64 = 2500;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emergency state for a staking pool
    public struct PoolEmergencyState has key, store {
        id: UID,
        /// Pool this state belongs to
        pool_id: ID,
        /// Guardian address
        guardian: Option<address>,
        /// Whether emergency mode is active
        emergency_active: bool,
        /// Timestamp when emergency was activated
        emergency_activated_at: u64,
        /// Reason for emergency
        emergency_reason: vector<u8>,
        /// Total emergency unstakes
        total_emergency_unstakes: u64,
        /// Total tokens unstaked via emergency
        total_tokens_emergency_unstaked: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct EmergencyStateCreated has copy, drop {
        state_id: ID,
        pool_id: ID,
    }

    public struct GuardianSet has copy, drop {
        pool_id: ID,
        guardian: address,
        set_by: address,
    }

    public struct GuardianRemoved has copy, drop {
        pool_id: ID,
        old_guardian: address,
        removed_by: address,
    }

    public struct EmergencyActivated has copy, drop {
        pool_id: ID,
        activated_by: address,
        reason: vector<u8>,
        timestamp: u64,
    }

    public struct EmergencyDeactivated has copy, drop {
        pool_id: ID,
        deactivated_by: address,
        timestamp: u64,
    }

    public struct EmergencyUnstake has copy, drop {
        pool_id: ID,
        position_id: ID,
        user: address,
        amount: u64,
        fee_paid: u64,
        timestamp: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create emergency state for a pool
    public fun create_emergency_state<ST, RT>(
        _admin_cap: &PoolAdminCap,
        pool: &StakingPool<ST, RT>,
        ctx: &mut TxContext,
    ): PoolEmergencyState {
        let pool_id = object::id(pool);

        let state = PoolEmergencyState {
            id: object::new(ctx),
            pool_id,
            guardian: option::none(),
            emergency_active: false,
            emergency_activated_at: 0,
            emergency_reason: vector::empty(),
            total_emergency_unstakes: 0,
            total_tokens_emergency_unstaked: 0,
        };

        event::emit(EmergencyStateCreated {
            state_id: object::id(&state),
            pool_id,
        });

        state
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GUARDIAN MANAGEMENT (Pool Admin Only)
    // ═══════════════════════════════════════════════════════════════════════

    /// Set guardian for pool
    public fun set_guardian(
        admin_cap: &PoolAdminCap,
        state: &mut PoolEmergencyState,
        guardian: address,
        ctx: &TxContext,
    ) {
        sui_staking::access::assert_pool_admin_cap_matches(admin_cap, state.pool_id);

        if (option::is_some(&state.guardian)) {
            assert!(*option::borrow(&state.guardian) != guardian, EAlreadyGuardian);
        };

        state.guardian = option::some(guardian);

        event::emit(GuardianSet {
            pool_id: state.pool_id,
            guardian,
            set_by: ctx.sender(),
        });
    }

    /// Remove guardian
    public fun remove_guardian(
        admin_cap: &PoolAdminCap,
        state: &mut PoolEmergencyState,
        ctx: &TxContext,
    ) {
        sui_staking::access::assert_pool_admin_cap_matches(admin_cap, state.pool_id);
        assert!(option::is_some(&state.guardian), EGuardianNotSet);

        let old_guardian = option::extract(&mut state.guardian);

        event::emit(GuardianRemoved {
            pool_id: state.pool_id,
            old_guardian,
            removed_by: ctx.sender(),
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMERGENCY ACTIVATION (Guardian Only)
    // ═══════════════════════════════════════════════════════════════════════

    /// Activate emergency mode (guardian only)
    public fun activate_emergency(
        state: &mut PoolEmergencyState,
        reason: vector<u8>,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(option::is_some(&state.guardian), EGuardianNotSet);
        assert!(*option::borrow(&state.guardian) == ctx.sender(), ENotGuardian);
        assert!(!state.emergency_active, EAlreadyInEmergency);

        let timestamp = clock.timestamp_ms();

        state.emergency_active = true;
        state.emergency_activated_at = timestamp;
        state.emergency_reason = reason;

        event::emit(EmergencyActivated {
            pool_id: state.pool_id,
            activated_by: ctx.sender(),
            reason,
            timestamp,
        });
    }

    /// Deactivate emergency (admin only)
    public fun deactivate_emergency(
        admin_cap: &PoolAdminCap,
        state: &mut PoolEmergencyState,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        sui_staking::access::assert_pool_admin_cap_matches(admin_cap, state.pool_id);
        assert!(state.emergency_active, ENotInEmergency);

        state.emergency_active = false;
        state.emergency_reason = vector::empty();

        event::emit(EmergencyDeactivated {
            pool_id: state.pool_id,
            deactivated_by: ctx.sender(),
            timestamp: clock.timestamp_ms(),
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMERGENCY UNSTAKE
    // ═══════════════════════════════════════════════════════════════════════

    /// Emergency unstake - bypass lock period with penalty
    /// Available when emergency mode is active
    /// Higher fees apply (2x normal early fee, max 25%)
    #[allow(lint(self_transfer))]
    public fun emergency_unstake<ST, RT>(
        state: &mut PoolEmergencyState,
        pool: &mut StakingPool<ST, RT>,
        mut position: StakingPosition<ST>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Coin<ST>, Coin<RT>) {
        // Validate emergency state
        assert!(state.emergency_active, ENotInEmergency);
        assert!(state.pool_id == object::id(pool), EWrongPool);

        // Validate position belongs to this pool
        // Note: Ownership is validated by Sui runtime - if caller has the position, they own it
        assert!(position::pool_id(&position) == object::id(pool), errors::wrong_pool());

        let staked_amount = position::staked_amount(&position);
        let position_id = object::id(&position);

        // Calculate emergency fee (2x early fee, max 25%)
        let early_fee_bps = pool::early_unstake_fee_bps(pool);
        let emergency_fee_bps = math::min_u64(
            early_fee_bps * EMERGENCY_FEE_MULTIPLIER,
            MAX_EMERGENCY_FEE_BPS
        );
        let fee_amount = math::bps(staked_amount, emergency_fee_bps);
        let net_amount = staked_amount - fee_amount;

        // Update emergency state stats
        state.total_emergency_unstakes = state.total_emergency_unstakes + 1;
        state.total_tokens_emergency_unstaked = state.total_tokens_emergency_unstaked + staked_amount;

        // Perform emergency unstake using pool's internal function
        let (stake_coin, reward_coin) = pool::emergency_unstake_internal(
            pool,
            &mut position,
            net_amount,
            fee_amount,
            clock,
            ctx,
        );

        event::emit(EmergencyUnstake {
            pool_id: state.pool_id,
            position_id,
            user: ctx.sender(),
            amount: staked_amount,
            fee_paid: fee_amount,
            timestamp: clock.timestamp_ms(),
        });

        // Destroy the position
        position::destroy_position(position);

        (stake_coin, reward_coin)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    public fun is_emergency_active(state: &PoolEmergencyState): bool {
        state.emergency_active
    }

    public fun is_guardian(state: &PoolEmergencyState, addr: address): bool {
        option::is_some(&state.guardian) && *option::borrow(&state.guardian) == addr
    }

    public fun get_guardian(state: &PoolEmergencyState): Option<address> {
        state.guardian
    }

    public fun pool_id(state: &PoolEmergencyState): ID {
        state.pool_id
    }

    public fun emergency_activated_at(state: &PoolEmergencyState): u64 {
        state.emergency_activated_at
    }

    public fun emergency_reason(state: &PoolEmergencyState): &vector<u8> {
        &state.emergency_reason
    }

    public fun total_emergency_unstakes(state: &PoolEmergencyState): u64 {
        state.total_emergency_unstakes
    }

    public fun total_tokens_emergency_unstaked(state: &PoolEmergencyState): u64 {
        state.total_tokens_emergency_unstaked
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun emergency_fee_multiplier(): u64 { EMERGENCY_FEE_MULTIPLIER }
    public fun max_emergency_fee_bps(): u64 { MAX_EMERGENCY_FEE_BPS }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun destroy_for_testing(state: PoolEmergencyState) {
        let PoolEmergencyState {
            id,
            pool_id: _,
            guardian: _,
            emergency_active: _,
            emergency_activated_at: _,
            emergency_reason: _,
            total_emergency_unstakes: _,
            total_tokens_emergency_unstaked: _,
        } = state;
        object::delete(id);
    }
}
