/// Error codes for the staking module
module sui_staking::errors {

    // ═══════════════════════════════════════════════════════════════════════
    // POOL ERRORS (100-199)
    // ═══════════════════════════════════════════════════════════════════════

    /// Pool is paused
    const EPoolPaused: u64 = 100;
    /// Pool has ended
    const EPoolEnded: u64 = 101;
    /// Pool not started yet
    const EPoolNotStarted: u64 = 102;
    /// Invalid pool duration
    const EInvalidDuration: u64 = 103;
    /// Duration too short
    const EDurationTooShort: u64 = 104;
    /// Duration too long
    const EDurationTooLong: u64 = 105;
    /// Zero rewards provided
    const EZeroRewards: u64 = 106;
    /// Insufficient rewards in pool
    const EInsufficientRewards: u64 = 107;

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING ERRORS (200-299)
    // ═══════════════════════════════════════════════════════════════════════

    /// Amount is zero
    const EZeroAmount: u64 = 200;
    /// Amount too small (dust protection)
    const EAmountTooSmall: u64 = 201;
    /// Nothing to claim
    const ENothingToClaim: u64 = 202;
    /// Position belongs to different pool
    const EWrongPool: u64 = 203;
    /// Position is still locked
    const EPositionLocked: u64 = 204;
    /// Invalid lock tier
    const EInvalidLockTier: u64 = 205;
    /// Cannot extend lock to shorter duration
    const ECannotReduceLock: u64 = 206;

    // ═══════════════════════════════════════════════════════════════════════
    // ACCESS ERRORS (300-399)
    // ═══════════════════════════════════════════════════════════════════════

    /// Caller is not position owner
    const ENotOwner: u64 = 300;
    /// Caller is not pool admin
    const ENotPoolAdmin: u64 = 301;
    /// Caller is not platform admin
    const ENotAdmin: u64 = 302;
    /// Wrong admin cap for this pool
    const EPoolAdminMismatch: u64 = 303;

    // ═══════════════════════════════════════════════════════════════════════
    // FEE ERRORS (400-499)
    // ═══════════════════════════════════════════════════════════════════════

    /// Setup fee insufficient
    const EInsufficientFee: u64 = 400;
    /// Early unstake fee too high
    const EFeeTooHigh: u64 = 401;
    /// Invalid fee value
    const EInvalidFee: u64 = 402;

    // ═══════════════════════════════════════════════════════════════════════
    // PLATFORM ERRORS (500-599)
    // ═══════════════════════════════════════════════════════════════════════

    /// Platform is paused
    const EPlatformPaused: u64 = 500;
    /// Invalid configuration
    const EInvalidConfig: u64 = 501;

    // ═══════════════════════════════════════════════════════════════════════
    // GETTER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    public fun pool_paused(): u64 { EPoolPaused }
    public fun pool_ended(): u64 { EPoolEnded }
    public fun pool_not_started(): u64 { EPoolNotStarted }
    public fun invalid_duration(): u64 { EInvalidDuration }
    public fun duration_too_short(): u64 { EDurationTooShort }
    public fun duration_too_long(): u64 { EDurationTooLong }
    public fun zero_rewards(): u64 { EZeroRewards }
    public fun insufficient_rewards(): u64 { EInsufficientRewards }

    public fun zero_amount(): u64 { EZeroAmount }
    public fun amount_too_small(): u64 { EAmountTooSmall }
    public fun nothing_to_claim(): u64 { ENothingToClaim }
    public fun wrong_pool(): u64 { EWrongPool }
    public fun position_locked(): u64 { EPositionLocked }
    public fun invalid_lock_tier(): u64 { EInvalidLockTier }
    public fun cannot_reduce_lock(): u64 { ECannotReduceLock }

    public fun not_owner(): u64 { ENotOwner }
    public fun not_pool_admin(): u64 { ENotPoolAdmin }
    public fun not_admin(): u64 { ENotAdmin }
    public fun pool_admin_mismatch(): u64 { EPoolAdminMismatch }

    public fun insufficient_fee(): u64 { EInsufficientFee }
    public fun fee_too_high(): u64 { EFeeTooHigh }
    public fun invalid_fee(): u64 { EInvalidFee }

    public fun platform_paused(): u64 { EPlatformPaused }
    public fun invalid_config(): u64 { EInvalidConfig }
}
