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

    /// Minimum LP lock duration (90 days in ms)
    const MIN_LP_LOCK_DURATION: u64 = 7_776_000_000;

    // LP Destination types
    const LP_DEST_BURN: u8 = 0;
    const LP_DEST_DAO: u8 = 1;
    const LP_DEST_STAKING: u8 = 2;
    const LP_DEST_COMMUNITY_VEST: u8 = 3;

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
        // LP TOKEN DISTRIBUTION SETTINGS (Fund Safety)
        // ═══════════════════════════════════════════════════════════════════

        // ─── Creator LP Settings ───────────────────────────────────────────
        /// Creator LP percentage (0-30% = 0-3000 bps)
        creator_lp_bps: u64,
        /// Creator LP vesting cliff duration (in ms)
        creator_lp_cliff_ms: u64,
        /// Creator LP vesting duration after cliff (in ms)
        creator_lp_vesting_ms: u64,

        // ─── Community LP Settings ─────────────────────────────────────────
        /// Community LP destination (0=burn, 1=dao, 2=staking, 3=community_vest)
        community_lp_destination: u8,
        /// Community LP vesting cliff (if destination = community_vest)
        community_lp_cliff_ms: u64,
        /// Community LP vesting duration (if destination = community_vest)
        community_lp_vesting_ms: u64,
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
            // LP TOKEN DISTRIBUTION DEFAULTS (Fund Safety)
            // ═══════════════════════════════════════════════════════════════

            // Creator LP settings
            creator_lp_bps: 2000,                 // 20% of LP to creator
            creator_lp_cliff_ms: 15_552_000_000,  // 6 months cliff
            creator_lp_vesting_ms: 31_104_000_000, // 12 months vesting

            // Community LP settings
            community_lp_destination: LP_DEST_BURN, // Burn = liquidity locked forever
            community_lp_cliff_ms: 0,              // No cliff if burn
            community_lp_vesting_ms: 0,            // No vesting if burn
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

    /// Update creation fee
    public fun set_creation_fee(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_fee: u64,
    ) {
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
    public fun set_creator_graduation_bps(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_bps: u64,
    ) {
        assert!(new_bps <= MAX_CREATOR_GRADUATION_BPS, EInvalidGraduationAllocation);
        let old = config.creator_graduation_bps;
        config.creator_graduation_bps = new_bps;
        event::emit(ConfigUpdated { field: b"creator_graduation_bps", old_value: old, new_value: new_bps });
    }

    /// Update platform graduation allocation (2.5-5%)
    public fun set_platform_graduation_bps(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_bps: u64,
    ) {
        assert!(new_bps >= MIN_PLATFORM_GRADUATION_BPS && new_bps <= MAX_PLATFORM_GRADUATION_BPS, EInvalidGraduationAllocation);
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
    public fun set_creator_lp_bps(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        new_bps: u64,
    ) {
        assert!(new_bps <= MAX_CREATOR_LP_BPS, ECreatorLPTooHigh);
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

    /// Set community LP destination
    public fun set_community_lp_destination(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        destination: u8,
    ) {
        assert!(destination <= LP_DEST_COMMUNITY_VEST, EInvalidLPDestination);
        config.community_lp_destination = destination;
        event::emit(ConfigUpdated { field: b"community_lp_destination", old_value: 0, new_value: destination as u64 });
    }

    /// Set community LP vesting parameters (only used if destination = community_vest)
    public fun set_community_lp_vesting(
        _admin: &AdminCap,
        config: &mut LaunchpadConfig,
        cliff_ms: u64,
        vesting_ms: u64,
    ) {
        config.community_lp_cliff_ms = cliff_ms;
        config.community_lp_vesting_ms = vesting_ms;
        event::emit(ConfigUpdated { field: b"community_lp_cliff_ms", old_value: 0, new_value: cliff_ms });
        event::emit(ConfigUpdated { field: b"community_lp_vesting_ms", old_value: 0, new_value: vesting_ms });
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

    // ─── LP Distribution Getters (Fund Safety) ─────────────────────────────
    public fun creator_lp_bps(config: &LaunchpadConfig): u64 { config.creator_lp_bps }
    public fun creator_lp_cliff_ms(config: &LaunchpadConfig): u64 { config.creator_lp_cliff_ms }
    public fun creator_lp_vesting_ms(config: &LaunchpadConfig): u64 { config.creator_lp_vesting_ms }
    public fun community_lp_destination(config: &LaunchpadConfig): u8 { config.community_lp_destination }
    public fun community_lp_cliff_ms(config: &LaunchpadConfig): u64 { config.community_lp_cliff_ms }
    public fun community_lp_vesting_ms(config: &LaunchpadConfig): u64 { config.community_lp_vesting_ms }

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
}
