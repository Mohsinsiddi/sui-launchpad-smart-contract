/// DAO Integration Module
/// Provides helper functions for PTB-based DAO creation at graduation
///
/// This module facilitates the integration between sui_launchpad and sui_dao.
/// At graduation, a DAO is created for the token where stakers can vote on proposals.
/// LP tokens (or Position NFTs) are deposited to the DAO treasury.
///
/// ═══════════════════════════════════════════════════════════════════════════════
/// COMPLETE PTB FLOW FOR GRADUATION + STAKING + DAO
/// ═══════════════════════════════════════════════════════════════════════════════
///
/// Required Capabilities:
/// - Launchpad AdminCap (for graduation)
/// - Staking AdminCap (for create_pool_free)
/// - DAO PlatformAdminCap (for create_staking_governance_free)
///
/// ```
/// // STEPS 1-6: Same as staking_integration (graduation, DEX, staking pool)
///
/// // STEP 7: Create DAO (linked to staking pool for voting power)
/// let (governance, dao_admin_cap) = dao_integration::create_dao<T>(
///     dao_registry,
///     dao_admin_cap,
///     &pending,
///     staking_pool_id,
///     token_name,
///     clock,
///     ctx,
/// );
///
/// // STEP 8: Create DAO Treasury
/// let treasury = dao_integration::create_treasury(
///     &dao_admin_cap,
///     &mut governance,
///     ctx,
/// );
///
/// // STEP 9: Split LP tokens
/// let (creator_lp, protocol_lp, dao_lp) = graduation::split_lp_tokens(&pending, lp_coin, ctx);
///
/// // STEP 10: Deposit DAO LP to treasury
/// dao_integration::deposit_lp_to_treasury(&mut treasury, dao_lp, ctx);
/// // OR for Position NFT:
/// dao_integration::deposit_nft_to_treasury(&mut treasury, position_nft, ctx);
///
/// // STEP 11: (Optional) Enable council with creator
/// if (dao_integration::should_enable_council(&pending)) {
///     dao_integration::enable_council(&dao_admin_cap, &mut governance, creator, ctx);
/// }
///
/// // STEP 12: Share governance, treasury, transfer DAOAdminCap
/// transfer::public_share_object(governance);
/// transfer::public_share_object(treasury);
/// let admin_dest = dao_integration::get_admin_destination(&pending, &config);
/// transfer::public_transfer(dao_admin_cap, admin_dest);
///
/// // STEP 13: Handle creator LP (vest), protocol LP (transfer)
/// // ... vest creator_lp, transfer protocol_lp
///
/// // STEP 14: Complete graduation
/// let receipt = graduation::complete_graduation(pending, registry, ...);
/// ```
///
/// ═══════════════════════════════════════════════════════════════════════════════
module sui_launchpad::dao_integration {

    use std::string::String;
    use sui::clock::Clock;
    use sui::coin::Coin;

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::graduation::{Self, PendingGraduation};

    // Re-export sui_dao types for convenience
    use sui_dao::governance::{Self, Governance};
    use sui_dao::access::{AdminCap as DAOPlatformAdminCap, DAOAdminCap, CouncilCap};
    use sui_dao::treasury::{Self, Treasury};
    use sui_dao::registry::DAORegistry;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS - Admin Destinations
    // ═══════════════════════════════════════════════════════════════════════

    /// Creator receives DAOAdminCap - manages their own DAO
    const ADMIN_DEST_CREATOR: u8 = 0;

    /// DAO treasury receives DAOAdminCap - community-controlled (default)
    const ADMIN_DEST_DAO_TREASURY: u8 = 1;

    /// Platform receives DAOAdminCap - platform operates for creator
    const ADMIN_DEST_PLATFORM: u8 = 2;

    // ═══════════════════════════════════════════════════════════════════════
    // DAO CREATION (for PTB)
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a staking-based DAO for the graduated token
    /// The DAO is linked to the staking pool for voting power
    ///
    /// T = The graduated token type
    /// Requires DAOPlatformAdminCap to bypass creation fee
    /// Origin is set to LAUNCHPAD with the pool_id for tracking
    public fun create_dao<T>(
        dao_platform_admin: &DAOPlatformAdminCap,
        dao_registry: &mut DAORegistry,
        pending: &PendingGraduation<T>,
        staking_pool_id: ID,
        name: String,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Governance, DAOAdminCap) {
        let dao_config = graduation::pending_dao_config(pending);
        let launchpad_pool_id = graduation::pending_pool_id(pending);

        // Create staking-based governance with custom parameters (no fee)
        // Voting power comes from staked tokens in the linked staking pool
        // Origin is set to LAUNCHPAD for tracking
        governance::create_staking_governance_admin(
            dao_platform_admin,
            dao_registry,
            name,
            staking_pool_id,
            graduation::dao_config_quorum_bps(dao_config),
            graduation::dao_config_voting_delay_ms(dao_config),
            graduation::dao_config_voting_period_ms(dao_config),
            graduation::dao_config_timelock_delay_ms(dao_config),
            graduation::dao_config_proposal_threshold_bps(dao_config),
            sui_dao::events::origin_launchpad(),  // Origin: launchpad
            option::some(launchpad_pool_id),      // Link to launchpad pool
            clock,
            ctx,
        )
    }

    /// Create a treasury for the DAO
    /// The treasury holds LP tokens / Position NFTs from graduation
    public fun create_treasury(
        dao_admin_cap: &DAOAdminCap,
        governance: &mut Governance,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Treasury {
        treasury::create_treasury(dao_admin_cap, governance, clock, ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LP/NFT DEPOSIT TO TREASURY
    // ═══════════════════════════════════════════════════════════════════════

    /// Deposit LP tokens to DAO treasury (for AMM DEXes like SuiDex, FlowX)
    public fun deposit_lp_to_treasury<LP>(
        treasury: &mut Treasury,
        lp_coins: Coin<LP>,
        ctx: &TxContext,
    ) {
        treasury::deposit(treasury, lp_coins, ctx);
    }

    /// Deposit Position NFT to DAO treasury (for CLMM DEXes like Cetus, Turbos)
    public fun deposit_nft_to_treasury<NFT: key + store>(
        treasury: &mut Treasury,
        nft: NFT,
        ctx: &TxContext,
    ) {
        treasury::deposit_nft(treasury, nft, ctx);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COUNCIL SETUP
    // ═══════════════════════════════════════════════════════════════════════

    /// Enable council and add creator as initial member
    /// Council members can fast-track, veto, and create emergency proposals
    /// Returns the CouncilCap for the creator
    public fun enable_council_with_creator(
        dao_admin_cap: &DAOAdminCap,
        governance: &mut Governance,
        creator: address,
        ctx: &mut TxContext,
    ): CouncilCap {
        // Enable council with creator as initial member
        let initial_members = vector[creator];
        let mut caps = governance::enable_council(dao_admin_cap, governance, initial_members, ctx);
        // Return the creator's cap (only one member)
        let cap = caps.pop_back();
        caps.destroy_empty();
        cap
    }

    /// Check if council should be enabled for this graduation
    public fun should_enable_council<T>(pending: &PendingGraduation<T>): bool {
        let dao_config = graduation::pending_dao_config(pending);
        graduation::dao_config_council_enabled(dao_config)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS FOR PTB
    // ═══════════════════════════════════════════════════════════════════════

    /// Determine the destination address for the DAOAdminCap
    /// Uses the dao_admin_destination config to decide who receives control
    public fun get_admin_destination<T>(
        pending: &PendingGraduation<T>,
        config: &LaunchpadConfig,
    ): address {
        let dao_config = graduation::pending_dao_config(pending);
        let destination = graduation::dao_config_admin_destination(dao_config);

        if (destination == ADMIN_DEST_CREATOR) {
            graduation::pending_creator(pending)
        } else if (destination == ADMIN_DEST_DAO_TREASURY) {
            // For DAO treasury destination, we transfer to the DAO treasury address
            // This makes the DAO self-governing - DAOAdminCap is held by treasury
            // and can only be used via proposals
            config::dao_treasury(config)
        } else {
            // ADMIN_DEST_PLATFORM
            config::treasury(config)
        }
    }

    /// Check if DAO should be created for this graduation
    public fun should_create_dao<T>(pending: &PendingGraduation<T>): bool {
        graduation::pending_dao_enabled(pending)
    }

    /// Get all DAO parameters needed for governance creation
    /// Returns: (quorum_bps, voting_delay_ms, voting_period_ms, timelock_delay_ms, proposal_threshold_bps)
    public fun get_dao_params<T>(
        pending: &PendingGraduation<T>,
    ): (u64, u64, u64, u64, u64) {
        let config = graduation::pending_dao_config(pending);

        (
            graduation::dao_config_quorum_bps(config),
            graduation::dao_config_voting_delay_ms(config),
            graduation::dao_config_voting_period_ms(config),
            graduation::dao_config_timelock_delay_ms(config),
            graduation::dao_config_proposal_threshold_bps(config),
        )
    }

    /// Get creator address from pending graduation
    public fun get_creator<T>(pending: &PendingGraduation<T>): address {
        graduation::pending_creator(pending)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANT GETTERS (for external use)
    // ═══════════════════════════════════════════════════════════════════════

    // Admin destination constants
    public fun admin_dest_creator(): u8 { ADMIN_DEST_CREATOR }
    public fun admin_dest_dao_treasury(): u8 { ADMIN_DEST_DAO_TREASURY }
    public fun admin_dest_platform(): u8 { ADMIN_DEST_PLATFORM }

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Validate admin destination value
    public fun is_valid_admin_destination(dest: u8): bool {
        dest <= ADMIN_DEST_PLATFORM
    }

    /// Validate that DAO can be created for this graduation
    public fun validate_dao_setup<T>(pending: &PendingGraduation<T>): bool {
        graduation::pending_dao_enabled(pending)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COMBINED HELPER - Full DAO Setup
    // ═══════════════════════════════════════════════════════════════════════

    /// Complete DAO setup in one call - creates DAO, treasury, and optionally council
    /// Returns: (Governance, Treasury, DAOAdminCap, Option<CouncilCap>)
    ///
    /// This is a convenience function for PTB that combines all DAO creation steps
    public fun setup_full_dao<T>(
        dao_platform_admin: &DAOPlatformAdminCap,
        dao_registry: &mut DAORegistry,
        pending: &PendingGraduation<T>,
        staking_pool_id: ID,
        name: String,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Governance, Treasury, DAOAdminCap, Option<CouncilCap>) {
        // Create governance
        let (mut governance, dao_admin_cap) = create_dao(
            dao_platform_admin,
            dao_registry,
            pending,
            staking_pool_id,
            name,
            clock,
            ctx,
        );

        // Create treasury
        let treasury = create_treasury(&dao_admin_cap, &mut governance, clock, ctx);

        // Optionally enable council
        let council_cap = if (should_enable_council(pending)) {
            let creator = graduation::pending_creator(pending);
            let cap = enable_council_with_creator(&dao_admin_cap, &mut governance, creator, ctx);
            option::some(cap)
        } else {
            option::none()
        };

        (governance, treasury, dao_admin_cap, council_cap)
    }
}
