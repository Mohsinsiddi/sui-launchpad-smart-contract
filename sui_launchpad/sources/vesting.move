/// ═══════════════════════════════════════════════════════════════════════════
/// VESTING MODULE - Re-exports from sui_vesting package
/// ═══════════════════════════════════════════════════════════════════════════
///
/// This module provides convenient access to vesting functionality from the
/// standalone sui_vesting package. The launchpad uses:
///
/// - sui_vesting::vesting::VestingSchedule<T> - For LP token vesting (AMM DEXes)
/// - sui_vesting::nft_vesting::NFTVestingSchedule<T> - For Position NFT vesting (CLMM DEXes)
///
/// ═══════════════════════════════════════════════════════════════════════════
/// PTB FLOW FOR GRADUATION WITH VESTING
/// ═══════════════════════════════════════════════════════════════════════════
///
/// STEP 1: Initiate Graduation
/// ────────────────────────────
/// ```
/// let pending = graduation::initiate_graduation<T>(
///     &admin_cap,
///     &mut pool,
///     &config,
///     dex_type,        // 0=Cetus, 1=Turbos, 2=FlowX, 3=SuiDex
///     ctx,
/// );
/// ```
///
/// STEP 2: Extract Funds for DEX
/// ─────────────────────────────
/// ```
/// let sui_coin = graduation::extract_all_sui(&mut pending, ctx);
/// let token_coin = graduation::extract_all_tokens(&mut pending, ctx);
/// ```
///
/// STEP 3A: Create DEX Pool (AMM - SuiDex)
/// ───────────────────────────────────────
/// ```
/// // Returns LP tokens
/// let lp_tokens = suidex::create_pair_and_add_liquidity(
///     sui_coin,
///     token_coin,
///     &clock,
///     ctx,
/// );
/// ```
///
/// STEP 3B: Create DEX Pool (CLMM - Cetus/FlowX)
/// ─────────────────────────────────────────────
/// ```
/// // Returns Position NFT instead of LP tokens
/// let position_nft = cetus::create_pool_and_position(
///     sui_coin,
///     token_coin,
///     tick_lower,
///     tick_upper,
///     &clock,
///     ctx,
/// );
/// ```
///
/// STEP 4A: Split LP Tokens (AMM Flow)
/// ───────────────────────────────────
/// ```
/// let (creator_lp, protocol_lp, dao_lp) = graduation::split_lp_tokens(
///     &pending,
///     lp_tokens,
///     ctx,
/// );
/// ```
///
/// STEP 4B: Handle Position NFT (CLMM Flow)
/// ────────────────────────────────────────
/// For CLMM, the position NFT cannot be split. Options:
/// - Vest entire position to creator (most common)
/// - Create separate positions for each party
///
/// STEP 5A: Vest Creator LP (AMM)
/// ──────────────────────────────
/// ```
/// let creator_cap = sui_vesting::vesting::create_schedule<LP>(
///     &mut vesting_config,
///     creator_lp,
///     creator_address,         // beneficiary
///     clock.timestamp_ms(),    // start_time
///     cliff_ms,                // from config (default: 6 months)
///     vesting_ms,              // from config (default: 12 months)
///     false,                   // non-revocable
///     &clock,
///     ctx,
/// );
/// ```
///
/// STEP 5B: Vest Creator Position NFT (CLMM)
/// ─────────────────────────────────────────
/// ```
/// let creator_cap = sui_vesting::nft_vesting::create_nft_schedule<Position>(
///     position_nft,
///     creator_address,
///     clock.timestamp_ms(),
///     cliff_ms,                // from config (default: 6 months)
///     false,                   // non-revocable
///     &clock,
///     ctx,
/// );
/// ```
///
/// STEP 6: Transfer Protocol LP (Direct)
/// ─────────────────────────────────────
/// ```
/// transfer::public_transfer(protocol_lp, protocol_treasury);
/// ```
///
/// STEP 7: Handle DAO LP (Based on Destination)
/// ────────────────────────────────────────────
/// ```
/// // destination = 0: BURN
/// transfer::public_transfer(dao_lp, @0x0);
///
/// // destination = 1: DAO TREASURY
/// transfer::public_transfer(dao_lp, dao_treasury);
///
/// // destination = 2: STAKING CONTRACT
/// staking::deposit(dao_lp, staking_pool);
///
/// // destination = 3: VESTED TO DAO
/// sui_vesting::vesting::create_schedule(dao_lp, dao_treasury, ...);
/// ```
///
/// STEP 8: Complete Graduation
/// ───────────────────────────
/// ```
/// let receipt = graduation::complete_graduation(
///     pending,
///     &mut registry,
///     dex_pool_id,
///     total_lp_tokens,
///     creator_lp_tokens,
///     dao_lp_tokens,
///     &clock,
///     ctx,
/// );
/// ```
///
/// ═══════════════════════════════════════════════════════════════════════════
/// ADMIN CONFIGURABLE PARAMETERS
/// ═══════════════════════════════════════════════════════════════════════════
///
/// ┌─────────────────────────────────────────────────────────────────────────┐
/// │ LP DISTRIBUTION PERCENTAGES                                              │
/// ├─────────────────────┬─────────────┬─────────────┬───────────────────────┤
/// │ Parameter           │ Default     │ Range       │ Admin Function        │
/// ├─────────────────────┼─────────────┼─────────────┼───────────────────────┤
/// │ creator_lp_bps      │ 250 (2.5%)  │ 0-3000 (30%)│ set_creator_lp_bps()  │
/// │ protocol_lp_bps     │ 250 (2.5%)  │ 0-3000 (30%)│ set_protocol_lp_bps() │
/// │ dao_lp_bps          │ 9500 (95%)  │ AUTO        │ (calculated)          │
/// └─────────────────────┴─────────────┴─────────────┴───────────────────────┘
/// NOTE: creator_bps + protocol_bps cannot exceed 5000 (50%)
///       dao_bps = 10000 - creator_bps - protocol_bps
///
/// ┌─────────────────────────────────────────────────────────────────────────┐
/// │ CREATOR VESTING PARAMETERS                                               │
/// ├─────────────────────┬─────────────┬─────────────┬───────────────────────┤
/// │ Parameter           │ Default     │ Range       │ Admin Function        │
/// ├─────────────────────┼─────────────┼─────────────┼───────────────────────┤
/// │ creator_lp_cliff_ms │ 6 months    │ >= min_lock │ set_creator_lp_       │
/// │ creator_lp_vesting  │ 12 months   │ >= 0        │   vesting()           │
/// └─────────────────────┴─────────────┴─────────────┴───────────────────────┘
/// NOTE: cliff + vesting must meet minimum lock duration (e.g., 30 days)
///
/// ┌─────────────────────────────────────────────────────────────────────────┐
/// │ DAO LP DESTINATION                                                       │
/// ├─────────────────────┬─────────────┬─────────────────────────────────────┤
/// │ Value               │ Constant    │ Description                         │
/// ├─────────────────────┼─────────────┼─────────────────────────────────────┤
/// │ 0                   │ LP_DEST_BURN│ Burn (transfer to 0x0)              │
/// │ 1                   │ LP_DEST_DAO │ Direct to DAO treasury              │
/// │ 2                   │ LP_DEST_STAKE│ Send to staking contract           │
/// │ 3                   │ LP_DEST_VEST│ Vest to DAO treasury                │
/// └─────────────────────┴─────────────┴─────────────────────────────────────┘
/// Admin Function: set_dao_lp_destination()
///
/// ┌─────────────────────────────────────────────────────────────────────────┐
/// │ DAO VESTING PARAMETERS (only if destination = 3)                         │
/// ├─────────────────────┬─────────────┬─────────────┬───────────────────────┤
/// │ Parameter           │ Default     │ Range       │ Admin Function        │
/// ├─────────────────────┼─────────────┼─────────────┼───────────────────────┤
/// │ dao_lp_cliff_ms     │ 0           │ >= 0        │ set_dao_lp_vesting()  │
/// │ dao_lp_vesting_ms   │ 0           │ >= 0        │                       │
/// └─────────────────────┴─────────────┴─────────────┴───────────────────────┘
///
/// ┌─────────────────────────────────────────────────────────────────────────┐
/// │ TREASURY ADDRESSES                                                       │
/// ├─────────────────────┬─────────────────────────────┬─────────────────────┤
/// │ Parameter           │ Description                  │ Admin Function      │
/// ├─────────────────────┼─────────────────────────────┼─────────────────────┤
/// │ treasury            │ Protocol fee treasury        │ set_treasury()      │
/// │ dao_treasury        │ DAO/community treasury       │ set_dao_treasury()  │
/// └─────────────────────┴─────────────────────────────┴─────────────────────┘
///
/// ═══════════════════════════════════════════════════════════════════════════
/// EXAMPLE: Admin Updates LP Distribution
/// ═══════════════════════════════════════════════════════════════════════════
///
/// ```move
/// // Increase creator share to 5%, protocol to 5%, DAO becomes 90%
/// config::set_creator_lp_bps(&admin_cap, &mut config, 500);
/// config::set_protocol_lp_bps(&admin_cap, &mut config, 500);
///
/// // Change creator vesting: 3 month cliff + 9 month linear
/// config::set_creator_lp_vesting(
///     &admin_cap,
///     &mut config,
///     3 * 2_592_000_000,  // 3 months cliff
///     9 * 2_592_000_000,  // 9 months vesting
/// );
///
/// // Change DAO destination from burn to DAO treasury
/// config::set_dao_lp_destination(&admin_cap, &mut config, 1);
///
/// // Update DAO treasury address
/// config::set_dao_treasury(&admin_cap, &mut config, @0xDAO_MULTISIG);
/// ```
///
/// ═══════════════════════════════════════════════════════════════════════════
/// VISUAL FLOW DIAGRAM
/// ═══════════════════════════════════════════════════════════════════════════
///
/// ```
///                         ┌─────────────────────┐
///                         │   GRADUATION        │
///                         │   TRIGGERED         │
///                         └──────────┬──────────┘
///                                    │
///                         ┌──────────▼──────────┐
///                         │  initiate_graduation│
///                         │  (extract SUI+Token)│
///                         └──────────┬──────────┘
///                                    │
///              ┌─────────────────────┴─────────────────────┐
///              │                                           │
///    ┌─────────▼─────────┐                     ┌──────────▼──────────┐
///    │   AMM (SuiDex)    │                     │  CLMM (Cetus/FlowX) │
///    │   Returns LP      │                     │  Returns Position   │
///    └─────────┬─────────┘                     └──────────┬──────────┘
///              │                                          │
///    ┌─────────▼─────────┐                     ┌──────────▼──────────┐
///    │  split_lp_tokens  │                     │   Position NFT      │
///    │  ┌──────────────┐ │                     │   (single owner)    │
///    │  │Creator: 2.5% │ │                     └──────────┬──────────┘
///    │  │Protocol:2.5% │ │                                │
///    │  │DAO: 95%      │ │                     ┌──────────▼──────────┐
///    │  └──────────────┘ │                     │   Vest to Creator   │
///    └─────────┬─────────┘                     │   (6mo cliff)       │
///              │                               └──────────┬──────────┘
///    ┌─────────┴─────────────────┐                        │
///    │         │                 │                        │
/// ┌──▼───┐ ┌───▼────┐ ┌─────────▼─────────┐              │
/// │VESTED│ │DIRECT  │ │DAO Destination    │              │
/// │Creator│ │Protocol│ │ ┌───┬───┬───┬───┐│              │
/// │6mo+12m│ │Treasury│ │ │BRN│DAO│STK│VST││              │
/// └───────┘ └────────┘ │ └───┴───┴───┴───┘│              │
///                      └──────────────────┘              │
///                                                        │
///                         ┌──────────────────────────────┘
///                         │
///              ┌──────────▼──────────┐
///              │ complete_graduation │
///              │ (emit receipt)      │
///              └─────────────────────┘
/// ```
///
/// ═══════════════════════════════════════════════════════════════════════════
module sui_launchpad::vesting {

    // Re-export key types and functions from sui_vesting for convenience
    // The actual vesting logic lives in the sui_vesting package

    /// Returns true - vesting is integrated via sui_vesting package
    public fun is_integrated(): bool {
        true
    }

    /// Time constants (re-exported for convenience)
    public fun ms_per_day(): u64 { 86_400_000 }
    public fun ms_per_month(): u64 { 2_592_000_000 }
    public fun ms_per_year(): u64 { 31_536_000_000 }

    /// Default vesting parameters for creator LP at graduation
    /// 6 month cliff + 12 month linear vesting
    public fun default_creator_cliff_ms(): u64 { 6 * ms_per_month() }
    public fun default_creator_vesting_ms(): u64 { 12 * ms_per_month() }

    /// Default vesting parameters for creator Position NFT at graduation
    /// 6 month cliff (no linear - NFTs unlock all at once after cliff)
    public fun default_creator_position_cliff_ms(): u64 { 6 * ms_per_month() }
}
