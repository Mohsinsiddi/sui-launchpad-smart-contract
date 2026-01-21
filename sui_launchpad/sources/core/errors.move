/// Error codes for the launchpad platform
module sui_launchpad::errors {

    // ═══════════════════════════════════════════════════════════════════════
    // GENERAL ERRORS (0-99)
    // ═══════════════════════════════════════════════════════════════════════

    /// Caller is not authorized to perform this action
    const ENotAuthorized: u64 = 0;

    /// Invalid input parameter
    const EInvalidInput: u64 = 1;

    /// Operation is paused
    const EPaused: u64 = 2;

    /// Zero amount not allowed
    const EZeroAmount: u64 = 3;

    /// Insufficient balance
    const EInsufficientBalance: u64 = 4;

    /// Overflow detected
    const EOverflow: u64 = 5;

    /// Division by zero
    const EDivisionByZero: u64 = 6;

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIG ERRORS (100-199)
    // ═══════════════════════════════════════════════════════════════════════

    /// Fee exceeds maximum allowed
    const EFeeTooHigh: u64 = 100;

    /// Invalid fee configuration
    const EInvalidFee: u64 = 101;

    /// Invalid threshold configuration
    const EInvalidThreshold: u64 = 102;

    /// Already initialized
    const EAlreadyInitialized: u64 = 103;

    /// Not initialized
    const ENotInitialized: u64 = 104;

    // ═══════════════════════════════════════════════════════════════════════
    // REGISTRY ERRORS (200-299)
    // ═══════════════════════════════════════════════════════════════════════

    /// Token already registered
    const ETokenAlreadyRegistered: u64 = 200;

    /// Token not found
    const ETokenNotFound: u64 = 201;

    /// Invalid token type
    const EInvalidTokenType: u64 = 202;

    /// Tokens already minted (TreasuryCap not fresh)
    const ETokensAlreadyMinted: u64 = 203;

    /// Insufficient creation fee
    const EInsufficientCreationFee: u64 = 204;

    // ═══════════════════════════════════════════════════════════════════════
    // BONDING CURVE ERRORS (300-399)
    // ═══════════════════════════════════════════════════════════════════════

    /// Pool not found
    const EPoolNotFound: u64 = 300;

    /// Pool already exists
    const EPoolAlreadyExists: u64 = 301;

    /// Pool is graduated (no more trading)
    const EPoolGraduated: u64 = 302;

    /// Pool is paused
    const EPoolPaused: u64 = 303;

    /// Pool is locked (reentrancy)
    const EPoolLocked: u64 = 304;

    /// Insufficient liquidity in pool
    const EInsufficientLiquidity: u64 = 305;

    /// Trade amount too small
    const EAmountTooSmall: u64 = 306;

    /// Trade amount too large
    const EAmountTooLarge: u64 = 307;

    /// Slippage tolerance exceeded
    const ESlippageExceeded: u64 = 308;

    /// Invalid price
    const EInvalidPrice: u64 = 309;

    // ═══════════════════════════════════════════════════════════════════════
    // GRADUATION ERRORS (400-499)
    // ═══════════════════════════════════════════════════════════════════════

    /// Not ready for graduation
    const ENotReadyForGraduation: u64 = 400;

    /// Already graduated
    const EAlreadyGraduated: u64 = 401;

    /// Graduation threshold not met
    const EGraduationThresholdNotMet: u64 = 402;

    /// Invalid DEX configuration
    const EInvalidDexConfig: u64 = 403;

    /// DEX operation failed
    const EDexOperationFailed: u64 = 404;

    // ═══════════════════════════════════════════════════════════════════════
    // VESTING ERRORS (500-599)
    // ═══════════════════════════════════════════════════════════════════════

    /// Vesting schedule not found
    const EVestingNotFound: u64 = 500;

    /// Nothing to claim yet
    const ENothingToClaim: u64 = 501;

    /// Vesting not started
    const EVestingNotStarted: u64 = 502;

    /// Cliff period not ended
    const ECliffNotEnded: u64 = 503;

    /// Invalid vesting schedule
    const EInvalidVestingSchedule: u64 = 504;

    /// Not beneficiary
    const ENotBeneficiary: u64 = 505;

    // ═══════════════════════════════════════════════════════════════════════
    // ANTI-RUG ERRORS (600-699)
    // ═══════════════════════════════════════════════════════════════════════

    /// Pool is too young for graduation
    const EPoolTooYoung: u64 = 600;

    /// Not enough unique buyers
    const EInsufficientBuyers: u64 = 601;

    /// Not enough tokens sold
    const EInsufficientTokensSold: u64 = 602;

    /// Graduation cooling period not met
    const EGraduationCoolingPeriod: u64 = 603;

    /// Trading cooldown not expired
    const ETradingCooldown: u64 = 604;

    /// Honeypot detected (sell validation failed)
    const EHoneypotDetected: u64 = 605;

    /// Buy amount exceeds maximum per transaction
    const EBuyAmountTooLarge: u64 = 606;

    /// Timelock not expired
    const ETimelockNotExpired: u64 = 607;

    /// Change already pending
    const EChangePending: u64 = 608;

    /// No pending change found
    const ENoPendingChange: u64 = 609;

    /// Invalid LP distribution
    const EInvalidLPDistribution: u64 = 610;

    /// Creator LP percentage too high
    const ECreatorLPTooHigh: u64 = 611;

    /// Treasury cap already destroyed
    const ETreasuryCapDestroyed: u64 = 612;

    // ═══════════════════════════════════════════════════════════════════════
    // LP DISTRIBUTION ERRORS (700-799)
    // ═══════════════════════════════════════════════════════════════════════

    /// Invalid LP destination
    const EInvalidLPDestination: u64 = 700;

    /// LP vesting duration too short
    const ELPVestingTooShort: u64 = 701;

    /// LP cliff duration too long
    const ELPCliffTooLong: u64 = 702;

    // ═══════════════════════════════════════════════════════════════════════
    // PUBLIC GETTERS (for use in other modules)
    // ═══════════════════════════════════════════════════════════════════════

    // General
    public fun not_authorized(): u64 { ENotAuthorized }
    public fun invalid_input(): u64 { EInvalidInput }
    public fun paused(): u64 { EPaused }
    public fun zero_amount(): u64 { EZeroAmount }
    public fun insufficient_balance(): u64 { EInsufficientBalance }
    public fun overflow(): u64 { EOverflow }
    public fun division_by_zero(): u64 { EDivisionByZero }

    // Config
    public fun fee_too_high(): u64 { EFeeTooHigh }
    public fun invalid_fee(): u64 { EInvalidFee }
    public fun invalid_threshold(): u64 { EInvalidThreshold }
    public fun already_initialized(): u64 { EAlreadyInitialized }
    public fun not_initialized(): u64 { ENotInitialized }

    // Registry
    public fun token_already_registered(): u64 { ETokenAlreadyRegistered }
    public fun token_not_found(): u64 { ETokenNotFound }
    public fun invalid_token_type(): u64 { EInvalidTokenType }
    public fun tokens_already_minted(): u64 { ETokensAlreadyMinted }
    public fun insufficient_creation_fee(): u64 { EInsufficientCreationFee }

    // Bonding Curve
    public fun pool_not_found(): u64 { EPoolNotFound }
    public fun pool_already_exists(): u64 { EPoolAlreadyExists }
    public fun pool_graduated(): u64 { EPoolGraduated }
    public fun pool_paused(): u64 { EPoolPaused }
    public fun pool_locked(): u64 { EPoolLocked }
    public fun insufficient_liquidity(): u64 { EInsufficientLiquidity }
    public fun amount_too_small(): u64 { EAmountTooSmall }
    public fun amount_too_large(): u64 { EAmountTooLarge }
    public fun slippage_exceeded(): u64 { ESlippageExceeded }
    public fun invalid_price(): u64 { EInvalidPrice }

    // Graduation
    public fun not_ready_for_graduation(): u64 { ENotReadyForGraduation }
    public fun already_graduated(): u64 { EAlreadyGraduated }
    public fun graduation_threshold_not_met(): u64 { EGraduationThresholdNotMet }
    public fun invalid_dex_config(): u64 { EInvalidDexConfig }
    public fun dex_operation_failed(): u64 { EDexOperationFailed }

    // Vesting
    public fun vesting_not_found(): u64 { EVestingNotFound }
    public fun nothing_to_claim(): u64 { ENothingToClaim }
    public fun vesting_not_started(): u64 { EVestingNotStarted }
    public fun cliff_not_ended(): u64 { ECliffNotEnded }
    public fun invalid_vesting_schedule(): u64 { EInvalidVestingSchedule }
    public fun not_beneficiary(): u64 { ENotBeneficiary }

    // Anti-Rug
    public fun pool_too_young(): u64 { EPoolTooYoung }
    public fun insufficient_buyers(): u64 { EInsufficientBuyers }
    public fun insufficient_tokens_sold(): u64 { EInsufficientTokensSold }
    public fun graduation_cooling_period(): u64 { EGraduationCoolingPeriod }
    public fun trading_cooldown(): u64 { ETradingCooldown }
    public fun honeypot_detected(): u64 { EHoneypotDetected }
    public fun buy_amount_too_large(): u64 { EBuyAmountTooLarge }
    public fun timelock_not_expired(): u64 { ETimelockNotExpired }
    public fun change_pending(): u64 { EChangePending }
    public fun no_pending_change(): u64 { ENoPendingChange }
    public fun invalid_lp_distribution(): u64 { EInvalidLPDistribution }
    public fun creator_lp_too_high(): u64 { ECreatorLPTooHigh }
    public fun treasury_cap_destroyed(): u64 { ETreasuryCapDestroyed }

    // LP Distribution
    public fun invalid_lp_destination(): u64 { EInvalidLPDestination }
    public fun lp_vesting_too_short(): u64 { ELPVestingTooShort }
    public fun lp_cliff_too_long(): u64 { ELPCliffTooLong }
}
