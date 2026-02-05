/// Emergency Actions module for Launchpad
///
/// Provides emergency functionality for the platform:
/// 1. Guardian System - Trusted address that can emergency pause
/// 2. Rage Quit - Users can exit even when paused (with penalty)
/// 3. Emergency State - Separate state from normal pause
///
/// Safety guarantees:
/// - Guardian can only pause, not unpause (admin only)
/// - Rage quit has higher fees to discourage abuse
/// - Emergency state is clearly tracked
module sui_launchpad::emergency {

    use sui::clock::Clock;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::event;

    use sui_launchpad::config::LaunchpadConfig;
    use sui_launchpad::access::AdminCap;
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::math;

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    const ENotGuardian: u64 = 800;
    const EGuardianNotSet: u64 = 801;
    const EAlreadyGuardian: u64 = 802;
    const ENotInEmergency: u64 = 803;
    const EAlreadyInEmergency: u64 = 804;
    const EPoolGraduated: u64 = 805;
    const EInsufficientTokens: u64 = 806;
    const EZeroAmount: u64 = 807;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Rage quit fee multiplier (2x normal fee)
    const RAGE_QUIT_FEE_MULTIPLIER: u64 = 2;

    /// Maximum rage quit fee (20% = 2000 bps)
    const MAX_RAGE_QUIT_FEE_BPS: u64 = 2000;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emergency state for the platform
    /// Shared object that tracks emergency status
    public struct EmergencyState has key, store {
        id: UID,
        /// Guardian address (can emergency pause)
        guardian: Option<address>,
        /// Whether platform is in emergency mode
        emergency_active: bool,
        /// Timestamp when emergency was activated
        emergency_activated_at: u64,
        /// Reason for emergency (if any)
        emergency_reason: vector<u8>,
        /// Total rage quits executed
        total_rage_quits: u64,
        /// Total SUI recovered via rage quit
        total_sui_recovered: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct GuardianSet has copy, drop {
        guardian: address,
        set_by: address,
    }

    public struct GuardianRemoved has copy, drop {
        old_guardian: address,
        removed_by: address,
    }

    public struct EmergencyActivated has copy, drop {
        activated_by: address,
        reason: vector<u8>,
        timestamp: u64,
    }

    public struct EmergencyDeactivated has copy, drop {
        deactivated_by: address,
        timestamp: u64,
    }

    public struct RageQuitExecuted has copy, drop {
        pool_id: ID,
        user: address,
        tokens_sold: u64,
        sui_received: u64,
        fee_paid: u64,
        timestamp: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create emergency state (called by launchpad init or admin)
    public fun create_emergency_state(ctx: &mut TxContext): EmergencyState {
        EmergencyState {
            id: object::new(ctx),
            guardian: option::none(),
            emergency_active: false,
            emergency_activated_at: 0,
            emergency_reason: vector::empty(),
            total_rage_quits: 0,
            total_sui_recovered: 0,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GUARDIAN MANAGEMENT (Admin Only)
    // ═══════════════════════════════════════════════════════════════════════

    /// Set a guardian for the platform
    public fun set_guardian(
        _admin: &AdminCap,
        state: &mut EmergencyState,
        guardian: address,
        ctx: &TxContext,
    ) {
        // Check not setting same guardian
        if (option::is_some(&state.guardian)) {
            assert!(*option::borrow(&state.guardian) != guardian, EAlreadyGuardian);
        };

        state.guardian = option::some(guardian);

        event::emit(GuardianSet {
            guardian,
            set_by: ctx.sender(),
        });
    }

    /// Remove the guardian
    public fun remove_guardian(
        _admin: &AdminCap,
        state: &mut EmergencyState,
        ctx: &TxContext,
    ) {
        assert!(option::is_some(&state.guardian), EGuardianNotSet);

        let old_guardian = option::extract(&mut state.guardian);

        event::emit(GuardianRemoved {
            old_guardian,
            removed_by: ctx.sender(),
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMERGENCY ACTIVATION (Guardian Only)
    // ═══════════════════════════════════════════════════════════════════════

    /// Activate emergency mode (guardian only)
    /// This pauses all trading and enables rage quit
    public fun activate_emergency(
        state: &mut EmergencyState,
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
            activated_by: ctx.sender(),
            reason,
            timestamp,
        });
    }

    /// Deactivate emergency mode (admin only)
    /// Guardian can pause but only admin can unpause
    public fun deactivate_emergency(
        _admin: &AdminCap,
        state: &mut EmergencyState,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(state.emergency_active, ENotInEmergency);

        state.emergency_active = false;
        state.emergency_reason = vector::empty();

        event::emit(EmergencyDeactivated {
            deactivated_by: ctx.sender(),
            timestamp: clock.timestamp_ms(),
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RAGE QUIT (Available when emergency is active)
    // ═══════════════════════════════════════════════════════════════════════

    /// Rage quit - sell tokens even when paused
    /// Higher fees apply as a disincentive for non-emergency use
    /// Only available when emergency mode is active
    #[allow(lint(self_transfer))]
    public fun rage_quit<T>(
        state: &mut EmergencyState,
        pool: &mut BondingPool<T>,
        config: &LaunchpadConfig,
        tokens: Coin<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        // Must be in emergency mode
        assert!(state.emergency_active, ENotInEmergency);

        // Pool must not be graduated
        assert!(!bonding_curve::is_graduated(pool), EPoolGraduated);

        let tokens_in = coin::value(&tokens);
        assert!(tokens_in > 0, EZeroAmount);
        assert!(tokens_in <= bonding_curve::circulating_supply(pool), EInsufficientTokens);

        // Calculate SUI out using bonding curve math
        let base_price = bonding_curve::base_price(pool);
        let slope = bonding_curve::slope(pool);
        let circulating = bonding_curve::circulating_supply(pool);

        let ideal_sui_out = math::sui_out(tokens_in, circulating, base_price, slope);

        // Cap to available pool balance
        let pool_balance = bonding_curve::sui_balance(pool);
        let gross_sui_out = math::min(ideal_sui_out, pool_balance);

        assert!(pool_balance >= gross_sui_out, EInsufficientTokens);

        // Calculate rage quit fee (2x normal trading fee, capped at 20%)
        let normal_fee = sui_launchpad::config::trading_fee_bps(config);
        let rage_fee_bps = math::min(
            normal_fee * RAGE_QUIT_FEE_MULTIPLIER,
            MAX_RAGE_QUIT_FEE_BPS
        );
        let fee = math::bps(gross_sui_out, rage_fee_bps);
        let net_sui_out = gross_sui_out - fee;

        // Update emergency state stats
        state.total_rage_quits = state.total_rage_quits + 1;
        state.total_sui_recovered = state.total_sui_recovered + net_sui_out;

        // Execute the trade using internal pool functions
        // Note: This requires package-level access to bonding_curve internals
        // For now, we'll emit event and let frontend handle via PTB
        event::emit(RageQuitExecuted {
            pool_id: object::id(pool),
            user: ctx.sender(),
            tokens_sold: tokens_in,
            sui_received: net_sui_out,
            fee_paid: fee,
            timestamp: clock.timestamp_ms(),
        });

        // Transfer tokens to the pool balance and extract SUI
        // This is a simplified version - full implementation would need
        // package-level access to bonding_curve internals
        let mut sui_out = bonding_curve::rage_quit_sell(pool, tokens, net_sui_out, fee, ctx);

        // Send fee to treasury
        if (fee > 0) {
            let fee_coin = coin::split(&mut sui_out, 0, ctx); // Fee already deducted
            if (coin::value(&fee_coin) > 0) {
                transfer::public_transfer(fee_coin, sui_launchpad::config::treasury(config));
            } else {
                coin::destroy_zero(fee_coin);
            }
        };

        sui_out
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Check if emergency mode is active
    public fun is_emergency_active(state: &EmergencyState): bool {
        state.emergency_active
    }

    /// Check if address is the guardian
    public fun is_guardian(state: &EmergencyState, addr: address): bool {
        option::is_some(&state.guardian) && *option::borrow(&state.guardian) == addr
    }

    /// Get guardian address
    public fun get_guardian(state: &EmergencyState): Option<address> {
        state.guardian
    }

    /// Get emergency activation timestamp
    public fun emergency_activated_at(state: &EmergencyState): u64 {
        state.emergency_activated_at
    }

    /// Get emergency reason
    public fun emergency_reason(state: &EmergencyState): &vector<u8> {
        &state.emergency_reason
    }

    /// Get total rage quits
    public fun total_rage_quits(state: &EmergencyState): u64 {
        state.total_rage_quits
    }

    /// Get total SUI recovered
    public fun total_sui_recovered(state: &EmergencyState): u64 {
        state.total_sui_recovered
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun rage_quit_fee_multiplier(): u64 { RAGE_QUIT_FEE_MULTIPLIER }
    public fun max_rage_quit_fee_bps(): u64 { MAX_RAGE_QUIT_FEE_BPS }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun destroy_for_testing(state: EmergencyState) {
        let EmergencyState {
            id,
            guardian: _,
            emergency_active: _,
            emergency_activated_at: _,
            emergency_reason: _,
            total_rage_quits: _,
            total_sui_recovered: _,
        } = state;
        object::delete(id);
    }
}
