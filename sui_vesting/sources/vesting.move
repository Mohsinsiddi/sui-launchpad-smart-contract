/// Core vesting module - Claim-based token vesting
///
/// Supports:
/// - Cliff + Linear vesting (e.g., 6 month cliff, 12 month linear)
/// - Instant unlock (cliff = 0, duration = 0)
/// - Revocable/non-revocable schedules
///
/// Formula for claimable tokens:
/// - If current_time < start_time: 0
/// - If current_time < start_time + cliff: 0
/// - If current_time >= start_time + cliff + vesting_duration: total_amount - claimed
/// - Otherwise: (total_amount * elapsed_after_cliff / vesting_duration) - claimed
module sui_vesting::vesting {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::Clock;

    use sui_vesting::events;
    use sui_vesting::access::{Self, AdminCap, CreatorCap};

    // ═══════════════════════════════════════════════════════════════════════
    // ERROR CODES
    // ═══════════════════════════════════════════════════════════════════════

    const ENotClaimable: u64 = 100;
    const EScheduleEmpty: u64 = 101;
    const EZeroAmount: u64 = 105;
    const EInvalidBeneficiary: u64 = 107;
    const EAlreadyRevoked: u64 = 108;
    const ENotRevocable: u64 = 109;
    const ENotBeneficiary: u64 = 200;
    const ESchedulePaused: u64 = 300;
    const ECreatorCapMismatch: u64 = 400;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Milliseconds in a day
    const MS_PER_DAY: u64 = 86_400_000;
    /// Milliseconds in a month (30 days)
    const MS_PER_MONTH: u64 = 2_592_000_000;
    /// Milliseconds in a year (365 days)
    const MS_PER_YEAR: u64 = 31_536_000_000;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Global configuration for the vesting platform
    public struct VestingConfig has key {
        id: UID,
        /// Platform paused state
        paused: bool,
        /// Platform admin address
        admin: address,
        /// Total schedules created
        total_schedules: u64,
        /// Total tokens vested (across all token types, in units)
        total_vested_count: u64,
    }

    /// A vesting schedule for a specific token type
    /// Owned by the beneficiary (transferred on creation)
    public struct VestingSchedule<phantom T> has key, store {
        id: UID,
        /// Address that created this schedule
        creator: address,
        /// Address that can claim tokens
        beneficiary: address,
        /// Remaining tokens in the schedule
        balance: Balance<T>,
        /// Original total amount
        total_amount: u64,
        /// Amount already claimed
        claimed: u64,
        /// Timestamp when vesting starts (ms)
        start_time: u64,
        /// Cliff duration in ms (tokens locked until cliff ends)
        cliff_duration: u64,
        /// Linear vesting duration in ms (after cliff)
        vesting_duration: u64,
        /// Whether the schedule can be revoked by creator
        revocable: bool,
        /// Whether the schedule has been revoked
        revoked: bool,
        /// Whether the schedule is paused
        paused: bool,
        /// Creation timestamp
        created_at: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Initialize the vesting platform
    fun init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);

        // Create and transfer admin cap
        let admin_cap = access::create_admin_cap(ctx);
        transfer::public_transfer(admin_cap, admin);

        // Create and share config
        let config = VestingConfig {
            id: object::new(ctx),
            paused: false,
            admin,
            total_schedules: 0,
            total_vested_count: 0,
        };
        transfer::share_object(config);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SCHEDULE CREATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new vesting schedule
    ///
    /// # Arguments
    /// * `config` - Platform config
    /// * `tokens` - Tokens to vest
    /// * `beneficiary` - Address that can claim tokens
    /// * `start_time` - When vesting starts (ms timestamp)
    /// * `cliff_duration` - Cliff period in ms (0 for no cliff)
    /// * `vesting_duration` - Linear vesting period in ms (0 for instant unlock after cliff)
    /// * `revocable` - Whether creator can revoke unvested tokens
    /// * `clock` - Clock for timestamp
    ///
    /// # Returns
    /// * `CreatorCap` - Capability for creator to manage the schedule
    public fun create_schedule<T>(
        config: &mut VestingConfig,
        tokens: Coin<T>,
        beneficiary: address,
        start_time: u64,
        cliff_duration: u64,
        vesting_duration: u64,
        revocable: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ): CreatorCap {
        // Validations
        assert!(!config.paused, ESchedulePaused);
        assert!(beneficiary != @0x0, EInvalidBeneficiary);

        let amount = coin::value(&tokens);
        assert!(amount > 0, EZeroAmount);

        // If there's a vesting duration, it must be > 0 when cliff is 0
        // (instant unlock is cliff=0, vesting=0)
        // Linear vesting requires vesting_duration > 0

        let creator = tx_context::sender(ctx);
        let now = sui::clock::timestamp_ms(clock);

        let schedule = VestingSchedule<T> {
            id: object::new(ctx),
            creator,
            beneficiary,
            balance: coin::into_balance(tokens),
            total_amount: amount,
            claimed: 0,
            start_time,
            cliff_duration,
            vesting_duration,
            revocable,
            revoked: false,
            paused: false,
            created_at: now,
        };

        let schedule_id = object::id(&schedule);

        // Update config stats
        config.total_schedules = config.total_schedules + 1;
        config.total_vested_count = config.total_vested_count + 1;

        // Emit event
        events::emit_schedule_created<T>(
            schedule_id,
            creator,
            beneficiary,
            amount,
            start_time,
            cliff_duration,
            vesting_duration,
            revocable,
        );

        // Transfer schedule to beneficiary
        transfer::transfer(schedule, beneficiary);

        // Return creator cap
        access::create_creator_cap(schedule_id, ctx)
    }

    /// Create a schedule with cliff + linear vesting using months
    /// Convenience function for common use cases
    public fun create_schedule_months<T>(
        config: &mut VestingConfig,
        tokens: Coin<T>,
        beneficiary: address,
        cliff_months: u64,
        vesting_months: u64,
        revocable: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ): CreatorCap {
        let start_time = sui::clock::timestamp_ms(clock);
        let cliff_duration = cliff_months * MS_PER_MONTH;
        let vesting_duration = vesting_months * MS_PER_MONTH;

        create_schedule<T>(
            config,
            tokens,
            beneficiary,
            start_time,
            cliff_duration,
            vesting_duration,
            revocable,
            clock,
            ctx,
        )
    }

    /// Create an instant unlock schedule (no cliff, no vesting)
    /// Tokens can be claimed immediately
    public fun create_instant_schedule<T>(
        config: &mut VestingConfig,
        tokens: Coin<T>,
        beneficiary: address,
        clock: &Clock,
        ctx: &mut TxContext,
    ): CreatorCap {
        let start_time = sui::clock::timestamp_ms(clock);

        create_schedule<T>(
            config,
            tokens,
            beneficiary,
            start_time,
            0, // No cliff
            0, // No vesting (instant)
            false, // Not revocable (already fully vested)
            clock,
            ctx,
        )
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLAIMING
    // ═══════════════════════════════════════════════════════════════════════

    /// Claim all available tokens from a vesting schedule
    /// Only the beneficiary can call this
    public fun claim<T>(
        schedule: &mut VestingSchedule<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        let sender = tx_context::sender(ctx);
        assert!(sender == schedule.beneficiary, ENotBeneficiary);
        assert!(!schedule.paused, ESchedulePaused);
        assert!(!schedule.revoked, EAlreadyRevoked);

        let now = sui::clock::timestamp_ms(clock);
        let claimable = calculate_claimable(schedule, now);

        assert!(claimable > 0, ENotClaimable);

        // Update claimed amount
        schedule.claimed = schedule.claimed + claimable;

        // Extract tokens
        let tokens = coin::from_balance(
            balance::split(&mut schedule.balance, claimable),
            ctx
        );

        let remaining = balance::value(&schedule.balance);
        let schedule_id = object::id(schedule);

        // Emit claim event
        events::emit_tokens_claimed<T>(
            schedule_id,
            schedule.beneficiary,
            claimable,
            schedule.claimed,
            remaining,
            now,
        );

        // Emit completion event if fully claimed
        if (remaining == 0) {
            events::emit_schedule_completed<T>(
                schedule_id,
                schedule.beneficiary,
                schedule.claimed,
                now,
            );
        };

        tokens
    }

    /// Claim and transfer directly to beneficiary
    public entry fun claim_and_transfer<T>(
        schedule: &mut VestingSchedule<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let tokens = claim(schedule, clock, ctx);
        let beneficiary = schedule.beneficiary;
        transfer::public_transfer(tokens, beneficiary);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REVOCATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Revoke a vesting schedule (creator only)
    /// Returns unvested tokens to creator, beneficiary keeps already vested tokens
    public fun revoke<T>(
        creator_cap: &CreatorCap,
        schedule: &mut VestingSchedule<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        // Verify creator cap matches schedule
        assert!(access::creator_cap_schedule_id(creator_cap) == object::id(schedule), ECreatorCapMismatch);
        assert!(schedule.revocable, ENotRevocable);
        assert!(!schedule.revoked, EAlreadyRevoked);

        let now = sui::clock::timestamp_ms(clock);

        // Calculate what beneficiary has vested (can still claim)
        let vested = calculate_vested(schedule, now);
        let already_claimed = schedule.claimed;
        let beneficiary_entitled = if (vested > already_claimed) { vested - already_claimed } else { 0 };

        // Creator gets back unvested tokens
        let remaining_balance = balance::value(&schedule.balance);
        let creator_amount = if (remaining_balance > beneficiary_entitled) {
            remaining_balance - beneficiary_entitled
        } else {
            0
        };

        // Mark as revoked
        schedule.revoked = true;

        // Extract creator's portion
        let creator_tokens = if (creator_amount > 0) {
            coin::from_balance(
                balance::split(&mut schedule.balance, creator_amount),
                ctx
            )
        } else {
            coin::zero<T>(ctx)
        };

        let schedule_id = object::id(schedule);

        // Emit revoke event
        events::emit_schedule_revoked<T>(
            schedule_id,
            tx_context::sender(ctx),
            schedule.beneficiary,
            creator_amount,
            already_claimed,
            now,
        );

        creator_tokens
    }

    /// Revoke and transfer unvested tokens back to creator
    public entry fun revoke_and_transfer<T>(
        creator_cap: &CreatorCap,
        schedule: &mut VestingSchedule<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let tokens = revoke(creator_cap, schedule, clock, ctx);
        let creator = schedule.creator;
        transfer::public_transfer(tokens, creator);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Pause/unpause the platform (admin only)
    public fun set_platform_paused(
        _admin: &AdminCap,
        config: &mut VestingConfig,
        paused: bool,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        config.paused = paused;
        events::emit_platform_pause_toggled(
            paused,
            tx_context::sender(ctx),
            sui::clock::timestamp_ms(clock),
        );
    }

    /// Pause/unpause a specific schedule (admin only - emergency)
    public fun set_schedule_paused<T>(
        _admin: &AdminCap,
        schedule: &mut VestingSchedule<T>,
        paused: bool,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        schedule.paused = paused;
        events::emit_schedule_pause_toggled(
            object::id(schedule),
            paused,
            tx_context::sender(ctx),
            sui::clock::timestamp_ms(clock),
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Calculate claimable amount at current time
    public fun claimable<T>(schedule: &VestingSchedule<T>, clock: &Clock): u64 {
        if (schedule.paused || schedule.revoked) {
            return 0
        };
        let now = sui::clock::timestamp_ms(clock);
        calculate_claimable(schedule, now)
    }

    /// Calculate total vested amount (claimed + claimable)
    public fun vested<T>(schedule: &VestingSchedule<T>, clock: &Clock): u64 {
        let now = sui::clock::timestamp_ms(clock);
        calculate_vested(schedule, now)
    }

    /// Get remaining balance in schedule
    public fun remaining<T>(schedule: &VestingSchedule<T>): u64 {
        balance::value(&schedule.balance)
    }

    /// Get schedule details
    public fun beneficiary<T>(schedule: &VestingSchedule<T>): address { schedule.beneficiary }
    public fun creator<T>(schedule: &VestingSchedule<T>): address { schedule.creator }
    public fun total_amount<T>(schedule: &VestingSchedule<T>): u64 { schedule.total_amount }
    public fun claimed<T>(schedule: &VestingSchedule<T>): u64 { schedule.claimed }
    public fun start_time<T>(schedule: &VestingSchedule<T>): u64 { schedule.start_time }
    public fun cliff_duration<T>(schedule: &VestingSchedule<T>): u64 { schedule.cliff_duration }
    public fun vesting_duration<T>(schedule: &VestingSchedule<T>): u64 { schedule.vesting_duration }
    public fun is_revocable<T>(schedule: &VestingSchedule<T>): bool { schedule.revocable }
    public fun is_revoked<T>(schedule: &VestingSchedule<T>): bool { schedule.revoked }
    public fun is_paused<T>(schedule: &VestingSchedule<T>): bool { schedule.paused }
    public fun created_at<T>(schedule: &VestingSchedule<T>): u64 { schedule.created_at }

    /// Config getters
    public fun config_paused(config: &VestingConfig): bool { config.paused }
    public fun config_admin(config: &VestingConfig): address { config.admin }
    public fun config_total_schedules(config: &VestingConfig): u64 { config.total_schedules }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Calculate claimable amount (vested - claimed)
    fun calculate_claimable<T>(schedule: &VestingSchedule<T>, now: u64): u64 {
        let vested_amount = calculate_vested(schedule, now);
        if (vested_amount > schedule.claimed) {
            vested_amount - schedule.claimed
        } else {
            0
        }
    }

    /// Calculate total vested amount at a given time
    fun calculate_vested<T>(schedule: &VestingSchedule<T>, now: u64): u64 {
        // Not started yet
        if (now < schedule.start_time) {
            return 0
        };

        let elapsed = now - schedule.start_time;

        // Still in cliff period
        if (elapsed < schedule.cliff_duration) {
            return 0
        };

        // Instant unlock (no vesting duration)
        if (schedule.vesting_duration == 0) {
            return schedule.total_amount
        };

        let elapsed_after_cliff = elapsed - schedule.cliff_duration;

        // Fully vested
        if (elapsed_after_cliff >= schedule.vesting_duration) {
            return schedule.total_amount
        };

        // Linear vesting: (total * elapsed_after_cliff) / vesting_duration
        // Use u128 to prevent overflow
        let total = schedule.total_amount as u128;
        let elapsed_128 = elapsed_after_cliff as u128;
        let duration_128 = schedule.vesting_duration as u128;

        ((total * elapsed_128) / duration_128) as u64
    }

    /// Delete an empty schedule (after fully claimed)
    public fun delete_empty_schedule<T>(schedule: VestingSchedule<T>) {
        assert!(balance::value(&schedule.balance) == 0, EScheduleEmpty);

        let VestingSchedule {
            id,
            creator: _,
            beneficiary: _,
            balance,
            total_amount: _,
            claimed: _,
            start_time: _,
            cliff_duration: _,
            vesting_duration: _,
            revocable: _,
            revoked: _,
            paused: _,
            created_at: _,
        } = schedule;

        balance::destroy_zero(balance);
        object::delete(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun ms_per_day(): u64 { MS_PER_DAY }
    public fun ms_per_month(): u64 { MS_PER_MONTH }
    public fun ms_per_year(): u64 { MS_PER_YEAR }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun create_config_for_testing(ctx: &mut TxContext): VestingConfig {
        VestingConfig {
            id: object::new(ctx),
            paused: false,
            admin: tx_context::sender(ctx),
            total_schedules: 0,
            total_vested_count: 0,
        }
    }
}
