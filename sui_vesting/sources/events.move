/// Events for the vesting module
module sui_vesting::events {
    use std::type_name::{Self, TypeName};
    use sui::event;

    // ═══════════════════════════════════════════════════════════════════════
    // SCHEDULE EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emitted when a new vesting schedule is created
    public struct ScheduleCreated has copy, drop {
        schedule_id: ID,
        token_type: TypeName,
        creator: address,
        beneficiary: address,
        total_amount: u64,
        start_time: u64,
        cliff_duration: u64,
        vesting_duration: u64,
        revocable: bool,
    }

    /// Emitted when tokens are claimed from a schedule
    public struct TokensClaimed has copy, drop {
        schedule_id: ID,
        token_type: TypeName,
        beneficiary: address,
        amount: u64,
        total_claimed: u64,
        remaining: u64,
        timestamp: u64,
    }

    /// Emitted when a schedule is revoked
    public struct ScheduleRevoked has copy, drop {
        schedule_id: ID,
        token_type: TypeName,
        revoker: address,
        beneficiary: address,
        amount_returned: u64,
        amount_claimed_by_beneficiary: u64,
        timestamp: u64,
    }

    /// Emitted when a schedule is fully vested
    public struct ScheduleCompleted has copy, drop {
        schedule_id: ID,
        token_type: TypeName,
        beneficiary: address,
        total_claimed: u64,
        timestamp: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emitted when platform is paused/unpaused
    public struct PlatformPauseToggled has copy, drop {
        paused: bool,
        admin: address,
        timestamp: u64,
    }

    /// Emitted when a schedule is paused/unpaused
    public struct SchedulePauseToggled has copy, drop {
        schedule_id: ID,
        paused: bool,
        admin: address,
        timestamp: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMIT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    public fun emit_schedule_created<T>(
        schedule_id: ID,
        creator: address,
        beneficiary: address,
        total_amount: u64,
        start_time: u64,
        cliff_duration: u64,
        vesting_duration: u64,
        revocable: bool,
    ) {
        event::emit(ScheduleCreated {
            schedule_id,
            token_type: type_name::with_defining_ids<T>(),
            creator,
            beneficiary,
            total_amount,
            start_time,
            cliff_duration,
            vesting_duration,
            revocable,
        });
    }

    public fun emit_tokens_claimed<T>(
        schedule_id: ID,
        beneficiary: address,
        amount: u64,
        total_claimed: u64,
        remaining: u64,
        timestamp: u64,
    ) {
        event::emit(TokensClaimed {
            schedule_id,
            token_type: type_name::with_defining_ids<T>(),
            beneficiary,
            amount,
            total_claimed,
            remaining,
            timestamp,
        });
    }

    public fun emit_schedule_revoked<T>(
        schedule_id: ID,
        revoker: address,
        beneficiary: address,
        amount_returned: u64,
        amount_claimed_by_beneficiary: u64,
        timestamp: u64,
    ) {
        event::emit(ScheduleRevoked {
            schedule_id,
            token_type: type_name::with_defining_ids<T>(),
            revoker,
            beneficiary,
            amount_returned,
            amount_claimed_by_beneficiary,
            timestamp,
        });
    }

    public fun emit_schedule_completed<T>(
        schedule_id: ID,
        beneficiary: address,
        total_claimed: u64,
        timestamp: u64,
    ) {
        event::emit(ScheduleCompleted {
            schedule_id,
            token_type: type_name::with_defining_ids<T>(),
            beneficiary,
            total_claimed,
            timestamp,
        });
    }

    public fun emit_platform_pause_toggled(
        paused: bool,
        admin: address,
        timestamp: u64,
    ) {
        event::emit(PlatformPauseToggled {
            paused,
            admin,
            timestamp,
        });
    }

    public fun emit_schedule_pause_toggled(
        schedule_id: ID,
        paused: bool,
        admin: address,
        timestamp: u64,
    ) {
        event::emit(SchedulePauseToggled {
            schedule_id,
            paused,
            admin,
            timestamp,
        });
    }
}
