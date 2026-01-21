/// Error codes for the vesting module
module sui_vesting::errors {

    // ═══════════════════════════════════════════════════════════════════════
    // VESTING ERRORS (100-199)
    // ═══════════════════════════════════════════════════════════════════════

    /// Nothing available to claim yet
    const ENotClaimable: u64 = 100;

    /// Vesting schedule is empty (fully claimed)
    const EScheduleEmpty: u64 = 101;

    /// Invalid vesting parameters
    const EInvalidParameters: u64 = 102;

    /// Cliff period not ended
    const ECliffNotEnded: u64 = 103;

    /// Vesting not started yet
    const EVestingNotStarted: u64 = 104;

    /// Zero amount not allowed
    const EZeroAmount: u64 = 105;

    /// Invalid duration (must be > 0)
    const EInvalidDuration: u64 = 106;

    /// Invalid beneficiary address
    const EInvalidBeneficiary: u64 = 107;

    /// Schedule already revoked
    const EAlreadyRevoked: u64 = 108;

    /// Schedule is not revocable
    const ENotRevocable: u64 = 109;

    // ═══════════════════════════════════════════════════════════════════════
    // ACCESS ERRORS (200-299)
    // ═══════════════════════════════════════════════════════════════════════

    /// Caller is not the beneficiary
    const ENotBeneficiary: u64 = 200;

    /// Caller is not the admin
    const ENotAdmin: u64 = 201;

    /// Caller is not the creator
    const ENotCreator: u64 = 202;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE ERRORS (300-399)
    // ═══════════════════════════════════════════════════════════════════════

    /// Schedule is paused
    const ESchedulePaused: u64 = 300;

    /// Schedule is not paused
    const EScheduleNotPaused: u64 = 301;

    /// Platform is paused
    const EPlatformPaused: u64 = 302;

    // ═══════════════════════════════════════════════════════════════════════
    // GETTER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    public fun not_claimable(): u64 { ENotClaimable }
    public fun schedule_empty(): u64 { EScheduleEmpty }
    public fun invalid_parameters(): u64 { EInvalidParameters }
    public fun cliff_not_ended(): u64 { ECliffNotEnded }
    public fun vesting_not_started(): u64 { EVestingNotStarted }
    public fun zero_amount(): u64 { EZeroAmount }
    public fun invalid_duration(): u64 { EInvalidDuration }
    public fun invalid_beneficiary(): u64 { EInvalidBeneficiary }
    public fun already_revoked(): u64 { EAlreadyRevoked }
    public fun not_revocable(): u64 { ENotRevocable }

    public fun not_beneficiary(): u64 { ENotBeneficiary }
    public fun not_admin(): u64 { ENotAdmin }
    public fun not_creator(): u64 { ENotCreator }

    public fun schedule_paused(): u64 { ESchedulePaused }
    public fun schedule_not_paused(): u64 { EScheduleNotPaused }
    public fun platform_paused(): u64 { EPlatformPaused }
}
