/// Platform configuration - stores all configurable parameters
/// Config values can be changed per environment (local/testnet/mainnet)
module sui_launchpad::config {

    use sui::event;
    use sui_launchpad::access::{AdminCap};

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Maximum fee in basis points (10% = 1000 bps)
    const MAX_FEE_BPS: u64 = 1000;

    /// Minimum creation fee (0.1 SUI = 100_000_000 MIST) - prevents spam attacks
    const MIN_CREATION_FEE: u64 = 100_000_000;

    /// Maximum total graduation allocation (20% = 2000 bps)
    /// creator_graduation_bps + platform_graduation_bps + staking_reward_bps <= 2000
    const MAX_TOTAL_GRADUATION_ALLOCATION_BPS: u64 = 2000;

    /// Maximum creator graduation allocation (5% = 500 bps)
    const MAX_CREATOR_GRADUATION_BPS: u64 = 500;

    /// Minimum platform graduation allocation (2.5% = 250 bps)
    const MIN_PLATFORM_GRADUATION_BPS: u64 = 250;

    /// Maximum platform graduation allocation (5% = 500 bps)
    const MAX_PLATFORM_GRADUATION_BPS: u64 = 500;

    /// DEX types
    const DEX_CETUS: u8 = 0;
    const DEX_TURBOS: u8 = 1;
    const DEX_FLOWX: u8 = 2;
    const DEX_SUIDEX: u8 = 3;

    // ═══════════════════════════════════════════════════════════════════════
    // FUND SAFETY CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Maximum creator LP percentage (30% = 3000 bps)
    const MAX_CREATOR_LP_BPS: u64 = 3000;

    /// Maximum protocol LP percentage (10% = 1000 bps)
    const MAX_PROTOCOL_LP_BPS: u64 = 1000;

    /// Minimum LP lock duration (90 days in ms)
    const MIN_LP_LOCK_DURATION: u64 = 7_776_000_000;

    // LP/Position Destination types for DAO share
    const LP_DEST_BURN: u8 = 0;        // Send to 0x0 (locked forever)
    const LP_DEST_DAO: u8 = 1;         // Direct transfer to DAO treasury
    const LP_DEST_STAKING: u8 = 2;     // Send to staking contract
    const LP_DEST_COMMUNITY_VEST: u8 = 3; // Vest to community

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING INTEGRATION CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Maximum staking reward allocation (10% = 1000 bps)
    const MAX_STAKING_REWARD_BPS: u64 = 1000;

    /// Default staking reward allocation (5% = 500 bps)
    const DEFAULT_STAKING_REWARD_BPS: u64 = 500;

    /// Default staking duration (365 days in ms)
    const DEFAULT_STAKING_DURATION_MS: u64 = 31_536_000_000;

    /// Minimum staking duration (7 days in ms)
    const MIN_STAKING_DURATION_MS: u64 = 604_800_000;

    /// Maximum staking duration (2 years in ms)
    const MAX_STAKING_DURATION_MS: u64 = 63_072_000_000;

    /// Default minimum stake duration (7 days in ms)
    const DEFAULT_MIN_STAKE_DURATION_MS: u64 = 604_800_000;

    /// Maximum minimum stake duration (30 days in ms)
    const MAX_MIN_STAKE_DURATION_MS: u64 = 2_592_000_000;

    /// Default early unstake fee (5% = 500 bps)
    const DEFAULT_EARLY_UNSTAKE_FEE_BPS: u64 = 500;

    /// Maximum stake/unstake fee (5% = 500 bps)
    const MAX_STAKE_FEE_BPS: u64 = 500;

    // Staking admin destination types
    const STAKING_ADMIN_DEST_CREATOR: u8 = 0;   // Creator manages pool
    const STAKING_ADMIN_DEST_DAO: u8 = 1;       // DAO treasury manages pool
    const STAKING_ADMIN_DEST_PLATFORM: u8 = 2; // Platform manages pool

    // Staking reward token types
    const STAKING_REWARD_SAME_TOKEN: u8 = 0;   // Reward with same graduated token
    const STAKING_REWARD_SUI: u8 = 1;          // Reward with SUI
    const STAKING_REWARD_CUSTOM: u8 = 2;       // Custom reward token (requires separate setup)

    // ═══════════════════════════════════════════════════════════════════════
    // DAO INTEGRATION CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Default DAO quorum (4% = 400 bps)
    const DEFAULT_DAO_QUORUM_BPS: u64 = 400;

    /// Default voting delay (1 day in ms)
    const DEFAULT_DAO_VOTING_DELAY_MS: u64 = 86_400_000;

    /// Default voting period (3 days in ms)
    const DEFAULT_DAO_VOTING_PERIOD_MS: u64 = 259_200_000;

    /// Default timelock delay (2 days in ms)
    const DEFAULT_DAO_TIMELOCK_DELAY_MS: u64 = 172_800_000;

    /// Default proposal threshold (1% = 100 bps)
    const DEFAULT_DAO_PROPOSAL_THRESHOLD_BPS: u64 = 100;

    /// Minimum voting delay (1 hour in ms)
    const MIN_DAO_VOTING_DELAY_MS: u64 = 3_600_000;

    /// Maximum voting delay (7 days in ms)
    const MAX_DAO_VOTING_DELAY_MS: u64 = 604_800_000;

    /// Minimum voting period (1 day in ms)
    const MIN_DAO_VOTING_PERIOD_MS: u64 = 86_400_000;

    /// Maximum voting period (14 days in ms)
    const MAX_DAO_VOTING_PERIOD_MS: u64 = 1_209_600_000;

    /// Minimum timelock delay (1 hour in ms)
    const MIN_DAO_TIMELOCK_DELAY_MS: u64 = 3_600_000;

    /// Maximum timelock delay (14 days in ms)
    const MAX_DAO_TIMELOCK_DELAY_MS: u64 = 1_209_600_000;

    /// Maximum quorum (50% = 5000 bps)
    const MAX_DAO_QUORUM_BPS: u64 = 5000;

    /// Maximum proposal threshold (10% = 1000 bps)
    const MAX_DAO_PROPOSAL_THRESHOLD_BPS: u64 = 1000;

    // DAO admin destination types (same as staking)
    const DAO_ADMIN_DEST_CREATOR: u8 = 0;     // Creator manages DAO
    const DAO_ADMIN_DEST_DAO_TREASURY: u8 = 1; // DAO treasury (community-controlled)
    const DAO_ADMIN_DEST_PLATFORM: u8 = 2;    // Platform manages DAO

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    const EFeeTooHigh: u64 = 100;
    const EInvalidDex: u64 = 101;
    const EPaused: u64 = 102;
    const EInvalidThreshold: u64 = 103;
    const EInvalidGraduationAllocation: u64 = 104;
    const ECreatorLPTooHigh: u64 = 105;
    const EInvalidLPDestination: u64 = 106;
    const EBelowHardMinimum: u64 = 107;
    const EProtocolLPTooHigh: u64 = 108;
    const ELPAllocationTooHigh: u64 = 109;
    const EStakingRewardTooHigh: u64 = 110;
    const EInvalidStakingDuration: u64 = 111;
    const EInvalidStakingMinDuration: u64 = 112;
    const EInvalidStakingAdminDest: u64 = 113;
    const EInvalidStakingRewardType: u64 = 114;
    const EStakingFeeTooHigh: u64 = 115;
    const EInvalidDAOQuorum: u64 = 116;
    const EInvalidDAOVotingDelay: u64 = 117;
    const EInvalidDAOVotingPeriod: u64 = 118;
    const EInvalidDAOTimelockDelay: u64 = 119;
    const EInvalidDAOProposalThreshold: u64 = 120;
    const EInvalidDAOAdminDest: u64 = 121;
    const ECreationFeeTooLow: u64 = 122;
    const ETotalGraduationAllocationTooHigh: u64 = 123;
    const EDAOTreasurySameAsPlatform: u64 = 124;

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIG STRUCT
    // ═══════════════════════════════════════════════════════════════════════

    /// Main configuration object - shared so anyone can read
    public struct LaunchpadConfig has key, store {
        id: UID,

        // ─── Fees ───────────────────────────────────────────────────────────
        /// Fee to create a new token (in MIST, e.g., 500_000_000 = 0.5 SUI)
        creation_fee: u64,
        /// Trading fee in basis points (e.g., 50 = 0.5%)
        trading_fee_bps: u64,
        /// Graduation fee in basis points (e.g., 500 = 5%)
        graduation_fee_bps: u64,
        /// Platform token allocation in basis points (e.g., 100 = 1%)
        platform_allocation_bps: u64,

        // ─── Graduation ────────────────────────────────────────────────────
        /// Target market cap for graduation (in MIST)
        graduation_threshold: u64,
        /// Minimum liquidity required for graduation (in MIST)
        min_graduation_liquidity: u64,
        /// Creator token allocation at graduation in bps (0-5%, e.g., 250 = 2.5%)
        creator_graduation_bps: u64,
        /// Platform token allocation at graduation in bps (2.5-5%, e.g., 250 = 2.5%)
        platform_graduation_bps: u64,

        // ─── Bonding Curve ─────────────────────────────────────────────────
        /// Default base price for new tokens
        default_base_price: u64,
        /// Default slope for bonding curve
        default_slope: u64,
        /// Total token supply for new tokens
        default_total_supply: u64,

        // ─── DEX Configuration ─────────────────────────────────────────────
        /// Default DEX for graduation (0=Cetus, 1=Turbos, 2=FlowX, 3=SuiDex)
        default_dex: u8,
        /// Cetus CLMM package address
        cetus_package: address,
        /// Turbos package address
        turbos_package: address,
        /// FlowX package address
        flowx_package: address,
        /// SuiDex package address
        suidex_package: address,

        // ─── Treasury ──────────────────────────────────────────────────────
        /// Address to receive platform fees
        treasury: address,

        // ─── State ─────────────────────────────────────────────────────────
        /// Global pause switch
        paused: bool,

        // ═══════════════════════════════════════════════════════════════════
        // LP/POSITION DISTRIBUTION SETTINGS (Fund Safety)
        // Distribution: Creator (vested) + Protocol (direct) + DAO (remainder)
        // ═══════════════════════════════════════════════════════════════════

        // ─── Creator LP Settings (VESTED) ──────────────────────────────────
        /// Creator LP/Position percentage (0-30% = 0-3000 bps, default 2.5%)
        creator_lp_bps: u64,
        /// Creator LP vesting cliff duration (in ms, default 6 months)
        creator_lp_cliff_ms: u64,
        /// Creator LP vesting duration after cliff (in ms, default 12 months)
        creator_lp_vesting_ms: u64,

        // ─── Protocol LP Settings (DIRECT TRANSFER) ────────────────────────
        /// Protocol LP/Position percentage (0-10% = 0-1000 bps, default 2.5%)
        protocol_lp_bps: u64,

        // ─── DAO LP Settings (REMAINDER = 100% - creator - protocol) ───────
        /// DAO treasury address for LP/Position transfers
        dao_treasury: address,
        /// DAO LP destination (0=burn, 1=dao_treasury, 2=staking, 3=vested)
        dao_lp_destination: u8,
        /// DAO LP vesting cliff (if destination = vested)
        dao_lp_cliff_ms: u64,
        /// DAO LP vesting duration (if destination = vested)
        dao_lp_vesting_ms: u64,

        // ═══════════════════════════════════════════════════════════════════
        // STAKING INTEGRATION SETTINGS
        // At graduation, tokens are reserved for staking pool rewards
        // ═══════════════════════════════════════════════════════════════════

        /// Whether to automatically create staking pool at graduation
        staking_enabled: bool,
        /// Percentage of token supply reserved for staking rewards (default 5%)
        staking_reward_bps: u64,
        /// Duration of the staking reward period (default 365 days)
        staking_duration_ms: u64,
        /// Minimum stake duration before withdrawal (default 7 days)
        staking_min_duration_ms: u64,
        /// Early unstake fee (default 5%)
        staking_early_fee_bps: u64,
        /// Fee on staking (default 0)
        staking_stake_fee_bps: u64,
        /// Fee on unstaking (default 0)
        staking_unstake_fee_bps: u64,
        /// Who receives the PoolAdminCap (0=creator, 1=dao, 2=platform)
        staking_admin_destination: u8,
        /// Type of reward token (0=same_token, 1=sui, 2=custom)
        staking_reward_type: u8,

        // ═══════════════════════════════════════════════════════════════════
        // DAO INTEGRATION SETTINGS
        // At graduation, a DAO is created for the token's governance
        // ═══════════════════════════════════════════════════════════════════

        /// Whether DAO creation is enabled at graduation
        dao_enabled: bool,
        /// Quorum required for proposals to pass (in bps of voting supply)
        dao_quorum_bps: u64,
        /// Delay before voting starts after proposal creation (in ms)
        dao_voting_delay_ms: u64,
        /// Duration of the voting period (in ms)
        dao_voting_period_ms: u64,
        /// Delay after voting ends before execution (in ms)
        dao_timelock_delay_ms: u64,
        /// Minimum voting power to create a proposal (in bps of total supply)
        dao_proposal_threshold_bps: u64,
        /// Whether council is enabled at DAO creation
        dao_council_enabled: bool,
        /// Who receives the DAOAdminCap (0=creator, 1=dao_treasury, 2=platform)
        dao_admin_destination: u8,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    public struct ConfigCreated has copy, drop {
        config_id: ID,
        treasury: address,
    }

    public struct ConfigUpdated has copy, drop {
        field: vector<u8>,
        old_value: u64,
        new_value: u64,
    }

    public struct TreasuryUpdated has copy, drop {
        old_treasury: address,
        new_treasury: address,
    }

    public struct DexConfigUpdated has copy, drop {
        dex_type: u8,
        package_address: address,
    }

    public struct PauseToggled has copy, drop {
        paused: bool,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create and share the config - called during package init
    public(package) fun create_config(
        treasury: address,
        ctx: &mut TxContext
    ): LaunchpadConfig {
        let config = LaunchpadConfig {
            id: object::new(ctx),

            // Default fees
            creation_fee: 500_000_000,        // 0.5 SUI
            trading_fee_bps: 50,               // 0.5%
            graduation_fee_bps: 500,           // 5%
            platform_allocation_bps: 100,      // 1%

            // Default graduation settings
            graduation_threshold: 69_000_000_000_000, // 69,000 SUI
            min_graduation_liquidity: 10_000_000_000_000, // 10,000 SUI
            creator_graduation_bps: 0,                 // 0% creator allocation at graduation (configurable 0-5%)
            platform_graduation_bps: 250,              // 2.5% platform allocation at graduation (configurable 2.5-5%)

            // Default bonding curve
            default_base_price: 1_000,         // Starting price
            default_slope: 1_000_000,          // Slope factor
            default_total_supply: 1_000_000_000_000_000_000, // 1 billion with 9 decimals

            // DEX (addresses set to 0x0, configure per environment)
            default_dex: DEX_CETUS,
            cetus_package: @0x0,
            turbos_package: @0x0,
            flowx_package: @0x0,
            suidex_package: @0x0,

            // Treasury
            treasury,

            // State
            paused: false,

            // ═══════════════════════════════════════════════════════════════
            // LP/POSITION DISTRIBUTION DEFAULTS (Fund Safety)
            // Default: Creator 2.5% (vested) + Protocol 2.5% (direct) + DAO 95% (direct)
            // ═══════════════════════════════════════════════════════════════

            // Creator LP settings (VESTED)
            creator_lp_bps: 250,                  // 2.5% of LP to creator
            creator_lp_cliff_ms: 15_552_000_000,  // 6 months cliff
            creator_lp_vesting_ms: 31_104_000_000, // 12 months linear vesting

            // Protocol LP settings (DIRECT)
            protocol_lp_bps: 250,                 // 2.5% of LP to protocol treasury

            // DAO LP settings (gets remainder = 95%)
            dao_treasury: treasury,               // Same as platform treasury by default
            dao_lp_destination: LP_DEST_DAO,      // Direct transfer to DAO treasury
            dao_lp_cliff_ms: 0,                   // No vesting for DAO
            dao_lp_vesting_ms: 0,                 // No vesting for DAO

            // ═══════════════════════════════════════════════════════════════
            // STAKING INTEGRATION DEFAULTS
            // ═══════════════════════════════════════════════════════════════

            staking_enabled: true,                              // Enabled by default
            staking_reward_bps: DEFAULT_STAKING_REWARD_BPS,     // 5% of token supply
            staking_duration_ms: DEFAULT_STAKING_DURATION_MS,   // 365 days
            staking_min_duration_ms: DEFAULT_MIN_STAKE_DURATION_MS, // 7 days
            staking_early_fee_bps: DEFAULT_EARLY_UNSTAKE_FEE_BPS,  // 5% early unstake fee
            staking_stake_fee_bps: 0,                           // No stake fee
            staking_unstake_fee_bps: 0,                         // No unstake fee
            staking_admin_destination: STAKING_ADMIN_DEST_CREATOR, // Creator manages pool
            staking_reward_type: STAKING_REWARD_SAME_TOKEN,     // Same token rewards

            // DAO INTEGRATION DEFAULTS
            // ═══════════════════════════════════════════════════════════════

            dao_enabled: true,                                      // Enabled by default
            dao_quorum_bps: DEFAULT_DAO_QUORUM_BPS,                  // 4% quorum
            dao_voting_delay_ms: DEFAULT_DAO_VOTING_DELAY_MS,        // 1 day
            dao_voting_period_ms: DEFAULT_DAO_VOTING_PERIOD_MS,      // 3 days
            dao_timelock_delay_ms: DEFAULT_DAO_TIMELOCK_DELAY_MS,    // 2 days
            dao_proposal_threshold_bps: DEFAULT_DAO_PROPOSAL_THRESHOLD_BPS, // 1%
            dao_council_enabled: false,                              // Disabled by default
            dao_admin_destination: DAO_ADMIN_DEST_DAO_TREASURY,     // DAO treasury manages DAO
        };

        event::emit(ConfigCreated {
            config_id: object::id(&config),
            treasury,
        });

        config
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN SETTERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Update creation fee (minimum 0.1 SUI to prevent spam)
    public fun set_creation_fee(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_fee: u64,
    ) {
        assert!(new_fee >= MIN_CREATION_FEE, ECreationFeeTooLow);
        let old = config.creation_fee;
        config.creation_fee = new_fee;
        event::emit(ConfigUpdated { field: b"creation_fee", old_value: old, new_value: new_fee });
    }

    /// Update trading fee
    public fun set_trading_fee(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_fee_bps: u64,
    ) {
        assert!(new_fee_bps <= MAX_FEE_BPS, EFeeTooHigh);
        let old = config.trading_fee_bps;
        config.trading_fee_bps = new_fee_bps;
        event::emit(ConfigUpdated { field: b"trading_fee_bps", old_value: old, new_value: new_fee_bps });
    }

    /// Update graduation fee
    public fun set_graduation_fee(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_fee_bps: u64,
    ) {
        assert!(new_fee_bps <= MAX_FEE_BPS, EFeeTooHigh);
        let old = config.graduation_fee_bps;
        config.graduation_fee_bps = new_fee_bps;
        event::emit(ConfigUpdated { field: b"graduation_fee_bps", old_value: old, new_value: new_fee_bps });
    }

    /// Update platform allocation
    public fun set_platform_allocation(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_allocation_bps: u64,
    ) {
        assert!(new_allocation_bps <= MAX_FEE_BPS, EFeeTooHigh);
        let old = config.platform_allocation_bps;
        config.platform_allocation_bps = new_allocation_bps;
        event::emit(ConfigUpdated { field: b"platform_allocation_bps", old_value: old, new_value: new_allocation_bps });
    }

    /// Update graduation threshold
    public fun set_graduation_threshold(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_threshold: u64,
    ) {
        assert!(new_threshold > 0, EInvalidThreshold);
        let old = config.graduation_threshold;
        config.graduation_threshold = new_threshold;
        event::emit(ConfigUpdated { field: b"graduation_threshold", old_value: old, new_value: new_threshold });
    }

    /// Update minimum graduation liquidity
    public fun set_min_graduation_liquidity(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_min: u64,
    ) {
        let old = config.min_graduation_liquidity;
        config.min_graduation_liquidity = new_min;
        event::emit(ConfigUpdated { field: b"min_graduation_liquidity", old_value: old, new_value: new_min });
    }

    /// Update creator graduation allocation (0-5%)
    /// Total graduation allocation (creator + platform + staking) must not exceed 20%
    public fun set_creator_graduation_bps(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_bps: u64,
    ) {
        assert!(new_bps <= MAX_CREATOR_GRADUATION_BPS, EInvalidGraduationAllocation);
        // Validate total graduation allocation doesn't exceed 20%
        let total_allocation = new_bps + config.platform_graduation_bps + config.staking_reward_bps;
        assert!(total_allocation <= MAX_TOTAL_GRADUATION_ALLOCATION_BPS, ETotalGraduationAllocationTooHigh);
        let old = config.creator_graduation_bps;
        config.creator_graduation_bps = new_bps;
        event::emit(ConfigUpdated { field: b"creator_graduation_bps", old_value: old, new_value: new_bps });
    }

    /// Update platform graduation allocation (2.5-5%)
    /// Total graduation allocation (creator + platform + staking) must not exceed 20%
    public fun set_platform_graduation_bps(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_bps: u64,
    ) {
        assert!(new_bps >= MIN_PLATFORM_GRADUATION_BPS && new_bps <= MAX_PLATFORM_GRADUATION_BPS, EInvalidGraduationAllocation);
        // Validate total graduation allocation doesn't exceed 20%
        let total_allocation = config.creator_graduation_bps + new_bps + config.staking_reward_bps;
        assert!(total_allocation <= MAX_TOTAL_GRADUATION_ALLOCATION_BPS, ETotalGraduationAllocationTooHigh);
        let old = config.platform_graduation_bps;
        config.platform_graduation_bps = new_bps;
        event::emit(ConfigUpdated { field: b"platform_graduation_bps", old_value: old, new_value: new_bps });
    }

    /// Update treasury address
    public fun set_treasury(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_treasury: address,
    ) {
        let old = config.treasury;
        config.treasury = new_treasury;
        event::emit(TreasuryUpdated { old_treasury: old, new_treasury });
    }

    /// Update default DEX
    public fun set_default_dex(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        dex_type: u8,
    ) {
        assert!(dex_type <= DEX_SUIDEX, EInvalidDex);
        config.default_dex = dex_type;
    }

    /// Update Cetus package address
    public fun set_cetus_package(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        package_addr: address,
    ) {
        config.cetus_package = package_addr;
        event::emit(DexConfigUpdated { dex_type: DEX_CETUS, package_address: package_addr });
    }

    /// Update Turbos package address
    public fun set_turbos_package(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        package_addr: address,
    ) {
        config.turbos_package = package_addr;
        event::emit(DexConfigUpdated { dex_type: DEX_TURBOS, package_address: package_addr });
    }

    /// Update FlowX package address
    public fun set_flowx_package(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        package_addr: address,
    ) {
        config.flowx_package = package_addr;
        event::emit(DexConfigUpdated { dex_type: DEX_FLOWX, package_address: package_addr });
    }

    /// Update SuiDex package address
    public fun set_suidex_package(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        package_addr: address,
    ) {
        config.suidex_package = package_addr;
        event::emit(DexConfigUpdated { dex_type: DEX_SUIDEX, package_address: package_addr });
    }

    /// Toggle pause state
    public fun toggle_pause(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
    ) {
        config.paused = !config.paused;
        event::emit(PauseToggled { paused: config.paused });
    }

    /// Set pause state explicitly
    public fun set_paused(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        paused: bool,
    ) {
        config.paused = paused;
        event::emit(PauseToggled { paused });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LP DISTRIBUTION ADMIN SETTERS (Fund Safety)
    // ═══════════════════════════════════════════════════════════════════════

    /// Set creator LP percentage (max 30%)
    /// Creator + Protocol must not exceed 50% (DAO gets at least 50%)
    public fun set_creator_lp_bps(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_bps: u64,
    ) {
        assert!(new_bps <= MAX_CREATOR_LP_BPS, ECreatorLPTooHigh);
        assert!(new_bps + config.protocol_lp_bps <= 5000, ELPAllocationTooHigh); // Max 50% combined
        let old = config.creator_lp_bps;
        config.creator_lp_bps = new_bps;
        event::emit(ConfigUpdated { field: b"creator_lp_bps", old_value: old, new_value: new_bps });
    }

    /// Set creator LP vesting parameters
    public fun set_creator_lp_vesting(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        cliff_ms: u64,
        vesting_ms: u64,
    ) {
        // Validate minimum lock duration
        assert!(cliff_ms + vesting_ms >= MIN_LP_LOCK_DURATION, EBelowHardMinimum);

        config.creator_lp_cliff_ms = cliff_ms;
        config.creator_lp_vesting_ms = vesting_ms;
        event::emit(ConfigUpdated { field: b"creator_lp_cliff_ms", old_value: 0, new_value: cliff_ms });
        event::emit(ConfigUpdated { field: b"creator_lp_vesting_ms", old_value: 0, new_value: vesting_ms });
    }

    /// Set protocol LP percentage (max 10%)
    /// Creator + Protocol must not exceed 50% (DAO gets at least 50%)
    public fun set_protocol_lp_bps(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_bps: u64,
    ) {
        assert!(new_bps <= MAX_PROTOCOL_LP_BPS, EProtocolLPTooHigh);
        assert!(config.creator_lp_bps + new_bps <= 5000, ELPAllocationTooHigh); // Max 50% combined
        let old = config.protocol_lp_bps;
        config.protocol_lp_bps = new_bps;
        event::emit(ConfigUpdated { field: b"protocol_lp_bps", old_value: old, new_value: new_bps });
    }

    /// Set DAO treasury address (for LP/Position transfers)
    /// DAO treasury must be different from platform treasury to ensure proper fund separation
    public fun set_dao_treasury(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_dao_treasury: address,
    ) {
        // Ensure DAO treasury is different from platform treasury
        assert!(new_dao_treasury != config.treasury, EDAOTreasurySameAsPlatform);
        config.dao_treasury = new_dao_treasury;
        event::emit(TreasuryUpdated { old_treasury: @0x0, new_treasury: new_dao_treasury });
    }

    /// Set DAO LP destination
    public fun set_dao_lp_destination(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        destination: u8,
    ) {
        assert!(destination <= LP_DEST_COMMUNITY_VEST, EInvalidLPDestination);
        config.dao_lp_destination = destination;
        event::emit(ConfigUpdated { field: b"dao_lp_destination", old_value: 0, new_value: destination as u64 });
    }

    /// Set DAO LP vesting parameters (only used if destination = vested)
    public fun set_dao_lp_vesting(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        cliff_ms: u64,
        vesting_ms: u64,
    ) {
        config.dao_lp_cliff_ms = cliff_ms;
        config.dao_lp_vesting_ms = vesting_ms;
        event::emit(ConfigUpdated { field: b"dao_lp_cliff_ms", old_value: 0, new_value: cliff_ms });
        event::emit(ConfigUpdated { field: b"dao_lp_vesting_ms", old_value: 0, new_value: vesting_ms });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING INTEGRATION ADMIN SETTERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Enable or disable staking pool creation at graduation
    public fun set_staking_enabled(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        enabled: bool,
    ) {
        config.staking_enabled = enabled;
        event::emit(ConfigUpdated {
            field: b"staking_enabled",
            old_value: if (config.staking_enabled) { 1 } else { 0 },
            new_value: if (enabled) { 1 } else { 0 }
        });
    }

    /// Set staking reward percentage (0-10% of token supply)
    /// Total graduation allocation (creator + platform + staking) must not exceed 20%
    public fun set_staking_reward_bps(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_bps: u64,
    ) {
        assert!(new_bps <= MAX_STAKING_REWARD_BPS, EStakingRewardTooHigh);
        // Validate total graduation allocation doesn't exceed 20%
        let total_allocation = config.creator_graduation_bps + config.platform_graduation_bps + new_bps;
        assert!(total_allocation <= MAX_TOTAL_GRADUATION_ALLOCATION_BPS, ETotalGraduationAllocationTooHigh);
        let old = config.staking_reward_bps;
        config.staking_reward_bps = new_bps;
        event::emit(ConfigUpdated { field: b"staking_reward_bps", old_value: old, new_value: new_bps });
    }

    /// Set staking duration (7 days - 2 years)
    public fun set_staking_duration_ms(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        duration_ms: u64,
    ) {
        assert!(duration_ms >= MIN_STAKING_DURATION_MS && duration_ms <= MAX_STAKING_DURATION_MS, EInvalidStakingDuration);
        let old = config.staking_duration_ms;
        config.staking_duration_ms = duration_ms;
        event::emit(ConfigUpdated { field: b"staking_duration_ms", old_value: old, new_value: duration_ms });
    }

    /// Set minimum stake duration (0 - 30 days)
    public fun set_staking_min_duration_ms(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        min_duration_ms: u64,
    ) {
        assert!(min_duration_ms <= MAX_MIN_STAKE_DURATION_MS, EInvalidStakingMinDuration);
        let old = config.staking_min_duration_ms;
        config.staking_min_duration_ms = min_duration_ms;
        event::emit(ConfigUpdated { field: b"staking_min_duration_ms", old_value: old, new_value: min_duration_ms });
    }

    /// Set early unstake fee (0-10%)
    public fun set_staking_early_fee_bps(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_bps: u64,
    ) {
        assert!(new_bps <= MAX_FEE_BPS, EStakingFeeTooHigh);
        let old = config.staking_early_fee_bps;
        config.staking_early_fee_bps = new_bps;
        event::emit(ConfigUpdated { field: b"staking_early_fee_bps", old_value: old, new_value: new_bps });
    }

    /// Set stake fee (0-5%)
    public fun set_staking_stake_fee_bps(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_bps: u64,
    ) {
        assert!(new_bps <= MAX_STAKE_FEE_BPS, EStakingFeeTooHigh);
        let old = config.staking_stake_fee_bps;
        config.staking_stake_fee_bps = new_bps;
        event::emit(ConfigUpdated { field: b"staking_stake_fee_bps", old_value: old, new_value: new_bps });
    }

    /// Set unstake fee (0-5%)
    public fun set_staking_unstake_fee_bps(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_bps: u64,
    ) {
        assert!(new_bps <= MAX_STAKE_FEE_BPS, EStakingFeeTooHigh);
        let old = config.staking_unstake_fee_bps;
        config.staking_unstake_fee_bps = new_bps;
        event::emit(ConfigUpdated { field: b"staking_unstake_fee_bps", old_value: old, new_value: new_bps });
    }

    /// Set staking admin destination (0=creator, 1=dao, 2=platform)
    public fun set_staking_admin_destination(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        destination: u8,
    ) {
        assert!(destination <= STAKING_ADMIN_DEST_PLATFORM, EInvalidStakingAdminDest);
        let old = config.staking_admin_destination;
        config.staking_admin_destination = destination;
        event::emit(ConfigUpdated { field: b"staking_admin_destination", old_value: old as u64, new_value: destination as u64 });
    }

    /// Set staking reward type (0=same_token, 1=sui, 2=custom)
    public fun set_staking_reward_type(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        reward_type: u8,
    ) {
        assert!(reward_type <= STAKING_REWARD_CUSTOM, EInvalidStakingRewardType);
        let old = config.staking_reward_type;
        config.staking_reward_type = reward_type;
        event::emit(ConfigUpdated { field: b"staking_reward_type", old_value: old as u64, new_value: reward_type as u64 });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DAO INTEGRATION ADMIN SETTERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Enable/disable DAO creation at graduation
    public fun set_dao_enabled(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        enabled: bool,
    ) {
        config.dao_enabled = enabled;
        event::emit(ConfigUpdated {
            field: b"dao_enabled",
            old_value: if (config.dao_enabled) { 1 } else { 0 },
            new_value: if (enabled) { 1 } else { 0 }
        });
    }

    /// Set DAO quorum (in bps, max 50%)
    public fun set_dao_quorum_bps(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        quorum_bps: u64,
    ) {
        assert!(quorum_bps > 0 && quorum_bps <= MAX_DAO_QUORUM_BPS, EInvalidDAOQuorum);
        let old = config.dao_quorum_bps;
        config.dao_quorum_bps = quorum_bps;
        event::emit(ConfigUpdated { field: b"dao_quorum_bps", old_value: old, new_value: quorum_bps });
    }

    /// Set DAO voting delay (time before voting starts after proposal creation)
    public fun set_dao_voting_delay_ms(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        delay_ms: u64,
    ) {
        assert!(delay_ms >= MIN_DAO_VOTING_DELAY_MS && delay_ms <= MAX_DAO_VOTING_DELAY_MS, EInvalidDAOVotingDelay);
        let old = config.dao_voting_delay_ms;
        config.dao_voting_delay_ms = delay_ms;
        event::emit(ConfigUpdated { field: b"dao_voting_delay_ms", old_value: old, new_value: delay_ms });
    }

    /// Set DAO voting period (how long voting is open)
    public fun set_dao_voting_period_ms(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        period_ms: u64,
    ) {
        assert!(period_ms >= MIN_DAO_VOTING_PERIOD_MS && period_ms <= MAX_DAO_VOTING_PERIOD_MS, EInvalidDAOVotingPeriod);
        let old = config.dao_voting_period_ms;
        config.dao_voting_period_ms = period_ms;
        event::emit(ConfigUpdated { field: b"dao_voting_period_ms", old_value: old, new_value: period_ms });
    }

    /// Set DAO timelock delay (time after voting before execution)
    public fun set_dao_timelock_delay_ms(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        delay_ms: u64,
    ) {
        assert!(delay_ms >= MIN_DAO_TIMELOCK_DELAY_MS && delay_ms <= MAX_DAO_TIMELOCK_DELAY_MS, EInvalidDAOTimelockDelay);
        let old = config.dao_timelock_delay_ms;
        config.dao_timelock_delay_ms = delay_ms;
        event::emit(ConfigUpdated { field: b"dao_timelock_delay_ms", old_value: old, new_value: delay_ms });
    }

    /// Set DAO proposal threshold (minimum voting power to create proposal, in bps)
    public fun set_dao_proposal_threshold_bps(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        threshold_bps: u64,
    ) {
        assert!(threshold_bps > 0 && threshold_bps <= MAX_DAO_PROPOSAL_THRESHOLD_BPS, EInvalidDAOProposalThreshold);
        let old = config.dao_proposal_threshold_bps;
        config.dao_proposal_threshold_bps = threshold_bps;
        event::emit(ConfigUpdated { field: b"dao_proposal_threshold_bps", old_value: old, new_value: threshold_bps });
    }

    /// Enable/disable council at DAO creation
    public fun set_dao_council_enabled(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        enabled: bool,
    ) {
        config.dao_council_enabled = enabled;
        event::emit(ConfigUpdated {
            field: b"dao_council_enabled",
            old_value: if (config.dao_council_enabled) { 1 } else { 0 },
            new_value: if (enabled) { 1 } else { 0 }
        });
    }

    /// Set DAO admin destination (0=creator, 1=dao_treasury, 2=platform)
    public fun set_dao_admin_destination(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        destination: u8,
    ) {
        assert!(destination <= DAO_ADMIN_DEST_PLATFORM, EInvalidDAOAdminDest);
        let old = config.dao_admin_destination;
        config.dao_admin_destination = destination;
        event::emit(ConfigUpdated { field: b"dao_admin_destination", old_value: old as u64, new_value: destination as u64 });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEPRECATED - Use dao_* instead of community_* (kept for compatibility)
    // ═══════════════════════════════════════════════════════════════════════

    /// @deprecated Use set_dao_lp_destination instead
    public fun set_community_lp_destination(
        admin: &AdminCap,
        config: &mut LaunchpadConfig,
        destination: u8,
    ) {
        set_dao_lp_destination(admin, config, destination);
    }

    /// @deprecated Use set_dao_lp_vesting instead
    public fun set_community_lp_vesting(
        admin: &AdminCap,
        config: &mut LaunchpadConfig,
        cliff_ms: u64,
        vesting_ms: u64,
    ) {
        set_dao_lp_vesting(admin, config, cliff_ms, vesting_ms);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun creation_fee(config: &LaunchpadConfig): u64 { config.creation_fee }
    public fun trading_fee_bps(config: &LaunchpadConfig): u64 { config.trading_fee_bps }
    public fun graduation_fee_bps(config: &LaunchpadConfig): u64 { config.graduation_fee_bps }
    public fun platform_allocation_bps(config: &LaunchpadConfig): u64 { config.platform_allocation_bps }
    public fun graduation_threshold(config: &LaunchpadConfig): u64 { config.graduation_threshold }
    public fun min_graduation_liquidity(config: &LaunchpadConfig): u64 { config.min_graduation_liquidity }
    public fun creator_graduation_bps(config: &LaunchpadConfig): u64 { config.creator_graduation_bps }
    public fun platform_graduation_bps(config: &LaunchpadConfig): u64 { config.platform_graduation_bps }
    public fun default_base_price(config: &LaunchpadConfig): u64 { config.default_base_price }
    public fun default_slope(config: &LaunchpadConfig): u64 { config.default_slope }
    public fun default_total_supply(config: &LaunchpadConfig): u64 { config.default_total_supply }
    public fun default_dex(config: &LaunchpadConfig): u8 { config.default_dex }
    public fun cetus_package(config: &LaunchpadConfig): address { config.cetus_package }
    public fun turbos_package(config: &LaunchpadConfig): address { config.turbos_package }
    public fun flowx_package(config: &LaunchpadConfig): address { config.flowx_package }
    public fun suidex_package(config: &LaunchpadConfig): address { config.suidex_package }
    public fun treasury(config: &LaunchpadConfig): address { config.treasury }
    public fun is_paused(config: &LaunchpadConfig): bool { config.paused }

    // ─── LP/Position Distribution Getters (Fund Safety) ────────────────────
    public fun creator_lp_bps(config: &LaunchpadConfig): u64 { config.creator_lp_bps }
    public fun creator_lp_cliff_ms(config: &LaunchpadConfig): u64 { config.creator_lp_cliff_ms }
    public fun creator_lp_vesting_ms(config: &LaunchpadConfig): u64 { config.creator_lp_vesting_ms }
    public fun protocol_lp_bps(config: &LaunchpadConfig): u64 { config.protocol_lp_bps }
    public fun dao_treasury(config: &LaunchpadConfig): address { config.dao_treasury }
    public fun dao_lp_destination(config: &LaunchpadConfig): u8 { config.dao_lp_destination }
    public fun dao_lp_cliff_ms(config: &LaunchpadConfig): u64 { config.dao_lp_cliff_ms }
    public fun dao_lp_vesting_ms(config: &LaunchpadConfig): u64 { config.dao_lp_vesting_ms }
    /// Calculate DAO LP share (remainder after creator + protocol)
    public fun dao_lp_bps(config: &LaunchpadConfig): u64 {
        10000 - config.creator_lp_bps - config.protocol_lp_bps
    }

    // ─── Deprecated getters (use dao_* instead) ───────────────────────────
    public fun community_lp_destination(config: &LaunchpadConfig): u8 { config.dao_lp_destination }
    public fun community_lp_cliff_ms(config: &LaunchpadConfig): u64 { config.dao_lp_cliff_ms }
    public fun community_lp_vesting_ms(config: &LaunchpadConfig): u64 { config.dao_lp_vesting_ms }

    // ─── Staking Integration Getters ─────────────────────────────────────────
    public fun staking_enabled(config: &LaunchpadConfig): bool { config.staking_enabled }
    public fun staking_reward_bps(config: &LaunchpadConfig): u64 { config.staking_reward_bps }
    public fun staking_duration_ms(config: &LaunchpadConfig): u64 { config.staking_duration_ms }
    public fun staking_min_duration_ms(config: &LaunchpadConfig): u64 { config.staking_min_duration_ms }
    public fun staking_early_fee_bps(config: &LaunchpadConfig): u64 { config.staking_early_fee_bps }
    public fun staking_stake_fee_bps(config: &LaunchpadConfig): u64 { config.staking_stake_fee_bps }
    public fun staking_unstake_fee_bps(config: &LaunchpadConfig): u64 { config.staking_unstake_fee_bps }
    public fun staking_admin_destination(config: &LaunchpadConfig): u8 { config.staking_admin_destination }
    public fun staking_reward_type(config: &LaunchpadConfig): u8 { config.staking_reward_type }

    // DAO Integration getters
    public fun dao_enabled(config: &LaunchpadConfig): bool { config.dao_enabled }
    public fun dao_quorum_bps(config: &LaunchpadConfig): u64 { config.dao_quorum_bps }
    public fun dao_voting_delay_ms(config: &LaunchpadConfig): u64 { config.dao_voting_delay_ms }
    public fun dao_voting_period_ms(config: &LaunchpadConfig): u64 { config.dao_voting_period_ms }
    public fun dao_timelock_delay_ms(config: &LaunchpadConfig): u64 { config.dao_timelock_delay_ms }
    public fun dao_proposal_threshold_bps(config: &LaunchpadConfig): u64 { config.dao_proposal_threshold_bps }
    public fun dao_council_enabled(config: &LaunchpadConfig): bool { config.dao_council_enabled }
    public fun dao_admin_destination(config: &LaunchpadConfig): u8 { config.dao_admin_destination }

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Assert platform is not paused
    public fun assert_not_paused(config: &LaunchpadConfig) {
        assert!(!config.paused, EPaused);
    }

    /// Get DEX package address by type
    public fun get_dex_package(config: &LaunchpadConfig, dex_type: u8): address {
        if (dex_type == DEX_CETUS) {
            config.cetus_package
        } else if (dex_type == DEX_TURBOS) {
            config.turbos_package
        } else if (dex_type == DEX_FLOWX) {
            config.flowx_package
        } else {
            config.suidex_package
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEX TYPE CONSTANTS (public getters)
    // ═══════════════════════════════════════════════════════════════════════

    public fun dex_cetus(): u8 { DEX_CETUS }
    public fun dex_turbos(): u8 { DEX_TURBOS }
    public fun dex_flowx(): u8 { DEX_FLOWX }
    public fun dex_suidex(): u8 { DEX_SUIDEX }

    // ═══════════════════════════════════════════════════════════════════════
    // LP DESTINATION CONSTANTS (public getters)
    // ═══════════════════════════════════════════════════════════════════════

    public fun lp_dest_burn(): u8 { LP_DEST_BURN }
    public fun lp_dest_dao(): u8 { LP_DEST_DAO }
    public fun lp_dest_staking(): u8 { LP_DEST_STAKING }
    public fun lp_dest_community_vest(): u8 { LP_DEST_COMMUNITY_VEST }

    // ═══════════════════════════════════════════════════════════════════════
    // FUND SAFETY CONSTANTS (public getters)
    // ═══════════════════════════════════════════════════════════════════════

    public fun max_creator_lp_bps(): u64 { MAX_CREATOR_LP_BPS }
    public fun min_lp_lock_duration(): u64 { MIN_LP_LOCK_DURATION }
    public fun min_creation_fee(): u64 { MIN_CREATION_FEE }
    public fun max_total_graduation_allocation_bps(): u64 { MAX_TOTAL_GRADUATION_ALLOCATION_BPS }

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING INTEGRATION CONSTANTS (public getters)
    // ═══════════════════════════════════════════════════════════════════════

    // Staking admin destination constants
    public fun staking_admin_dest_creator(): u8 { STAKING_ADMIN_DEST_CREATOR }
    public fun staking_admin_dest_dao(): u8 { STAKING_ADMIN_DEST_DAO }
    public fun staking_admin_dest_platform(): u8 { STAKING_ADMIN_DEST_PLATFORM }

    // Staking reward type constants
    public fun staking_reward_same_token(): u8 { STAKING_REWARD_SAME_TOKEN }
    public fun staking_reward_sui(): u8 { STAKING_REWARD_SUI }
    public fun staking_reward_custom(): u8 { STAKING_REWARD_CUSTOM }

    // Staking limits
    public fun max_staking_reward_bps(): u64 { MAX_STAKING_REWARD_BPS }
    public fun max_staking_duration_ms(): u64 { MAX_STAKING_DURATION_MS }
    public fun min_staking_duration_ms(): u64 { MIN_STAKING_DURATION_MS }
    public fun max_min_stake_duration_ms(): u64 { MAX_MIN_STAKE_DURATION_MS }
    public fun max_stake_fee_bps(): u64 { MAX_STAKE_FEE_BPS }

    // ═══════════════════════════════════════════════════════════════════════
    // DAO INTEGRATION CONSTANTS (public getters)
    // ═══════════════════════════════════════════════════════════════════════

    // DAO admin destination constants
    public fun dao_admin_dest_creator(): u8 { DAO_ADMIN_DEST_CREATOR }
    public fun dao_admin_dest_dao_treasury(): u8 { DAO_ADMIN_DEST_DAO_TREASURY }
    public fun dao_admin_dest_platform(): u8 { DAO_ADMIN_DEST_PLATFORM }

    // DAO limits
    public fun max_dao_quorum_bps(): u64 { MAX_DAO_QUORUM_BPS }
    public fun max_dao_proposal_threshold_bps(): u64 { MAX_DAO_PROPOSAL_THRESHOLD_BPS }
    public fun min_dao_voting_delay_ms(): u64 { MIN_DAO_VOTING_DELAY_MS }
    public fun max_dao_voting_delay_ms(): u64 { MAX_DAO_VOTING_DELAY_MS }
    public fun min_dao_voting_period_ms(): u64 { MIN_DAO_VOTING_PERIOD_MS }
    public fun max_dao_voting_period_ms(): u64 { MAX_DAO_VOTING_PERIOD_MS }
    public fun min_dao_timelock_delay_ms(): u64 { MIN_DAO_TIMELOCK_DELAY_MS }
    public fun max_dao_timelock_delay_ms(): u64 { MAX_DAO_TIMELOCK_DELAY_MS }

    // DAO defaults
    public fun default_dao_quorum_bps(): u64 { DEFAULT_DAO_QUORUM_BPS }
    public fun default_dao_voting_delay_ms(): u64 { DEFAULT_DAO_VOTING_DELAY_MS }
    public fun default_dao_voting_period_ms(): u64 { DEFAULT_DAO_VOTING_PERIOD_MS }
    public fun default_dao_timelock_delay_ms(): u64 { DEFAULT_DAO_TIMELOCK_DELAY_MS }
    public fun default_dao_proposal_threshold_bps(): u64 { DEFAULT_DAO_PROPOSAL_THRESHOLD_BPS }
}
