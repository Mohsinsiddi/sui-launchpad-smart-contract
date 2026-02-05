/// Creator Token Configuration - per-token customization at creation time
/// Allows creators to customize staking, DAO, and LP settings for their token
///
/// Default behavior: If no creator config is provided, platform defaults are used
/// Override behavior: Creator can override specific settings within allowed ranges
module sui_launchpad::creator_config {

    use sui_launchpad::config::{Self, LaunchpadConfig};

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    const EInvalidStakingRewardBps: u64 = 700;
    const EInvalidStakingDuration: u64 = 701;
    const EInvalidStakingMinDuration: u64 = 702;
    const EInvalidStakingFee: u64 = 703;
    const EInvalidDAOQuorum: u64 = 704;
    const EInvalidDAOVotingDelay: u64 = 705;
    const EInvalidDAOVotingPeriod: u64 = 706;
    const EInvalidDAOTimelockDelay: u64 = 707;
    const EInvalidDAOProposalThreshold: u64 = 708;
    const EInvalidAirdropBps: u64 = 709;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Maximum airdrop allocation (5% = 500 bps)
    const MAX_AIRDROP_BPS: u64 = 500;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Per-token configuration set by creator at token creation
    /// All fields are Option - if None, platform defaults are used
    public struct CreatorTokenConfig has copy, drop, store {
        // ─── Staking Customization ──────────────────────────────────────────
        /// Whether to create staking pool at graduation (None = use platform default)
        staking_enabled: Option<bool>,
        /// Percentage of token supply for staking rewards (0-10%)
        staking_reward_bps: Option<u64>,
        /// Duration of staking reward period
        staking_duration_ms: Option<u64>,
        /// Minimum stake duration
        staking_min_duration_ms: Option<u64>,
        /// Early unstake fee
        staking_early_fee_bps: Option<u64>,
        /// Stake fee
        staking_stake_fee_bps: Option<u64>,
        /// Unstake fee
        staking_unstake_fee_bps: Option<u64>,

        // ─── DAO Customization ──────────────────────────────────────────────
        /// Whether to create DAO at graduation (None = use platform default)
        dao_enabled: Option<bool>,
        /// Quorum for proposals
        dao_quorum_bps: Option<u64>,
        /// Voting delay
        dao_voting_delay_ms: Option<u64>,
        /// Voting period
        dao_voting_period_ms: Option<u64>,
        /// Timelock delay
        dao_timelock_delay_ms: Option<u64>,
        /// Proposal threshold
        dao_proposal_threshold_bps: Option<u64>,
        /// Enable council
        dao_council_enabled: Option<bool>,

        // ─── Airdrop Customization ──────────────────────────────────────────
        /// Whether to enable community airdrop at graduation
        airdrop_enabled: bool,
        /// Percentage of token supply for airdrop (0-5%)
        airdrop_bps: u64,
        /// Merkle root for airdrop claims (if using merkle tree)
        airdrop_merkle_root: Option<vector<u8>>,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BUILDER PATTERN
    // ═══════════════════════════════════════════════════════════════════════

    /// Create empty config (all defaults from platform)
    public fun new_empty(): CreatorTokenConfig {
        CreatorTokenConfig {
            staking_enabled: option::none(),
            staking_reward_bps: option::none(),
            staking_duration_ms: option::none(),
            staking_min_duration_ms: option::none(),
            staking_early_fee_bps: option::none(),
            staking_stake_fee_bps: option::none(),
            staking_unstake_fee_bps: option::none(),
            dao_enabled: option::none(),
            dao_quorum_bps: option::none(),
            dao_voting_delay_ms: option::none(),
            dao_voting_period_ms: option::none(),
            dao_timelock_delay_ms: option::none(),
            dao_proposal_threshold_bps: option::none(),
            dao_council_enabled: option::none(),
            airdrop_enabled: false,
            airdrop_bps: 0,
            airdrop_merkle_root: option::none(),
        }
    }

    /// Create config with staking disabled
    public fun new_no_staking(): CreatorTokenConfig {
        let mut config = new_empty();
        config.staking_enabled = option::some(false);
        config
    }

    /// Create config with DAO disabled
    public fun new_no_dao(): CreatorTokenConfig {
        let mut config = new_empty();
        config.dao_enabled = option::some(false);
        config
    }

    /// Create config with both staking and DAO disabled
    public fun new_minimal(): CreatorTokenConfig {
        let mut config = new_empty();
        config.staking_enabled = option::some(false);
        config.dao_enabled = option::some(false);
        config
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SETTERS (Builder Pattern)
    // ═══════════════════════════════════════════════════════════════════════

    /// Set staking enabled
    public fun set_staking_enabled(config: &mut CreatorTokenConfig, enabled: bool) {
        config.staking_enabled = option::some(enabled);
    }

    /// Set staking reward percentage (validated against platform limits)
    public fun set_staking_reward_bps(
        config: &mut CreatorTokenConfig,
        platform_config: &LaunchpadConfig,
        bps: u64
    ) {
        assert!(bps <= config::max_staking_reward_bps(), EInvalidStakingRewardBps);
        // Also check against total graduation allocation
        let total = config::creator_graduation_bps(platform_config) +
                   config::platform_graduation_bps(platform_config) + bps;
        assert!(total <= config::max_total_graduation_allocation_bps(), EInvalidStakingRewardBps);
        config.staking_reward_bps = option::some(bps);
    }

    /// Set staking duration
    public fun set_staking_duration_ms(config: &mut CreatorTokenConfig, duration_ms: u64) {
        assert!(
            duration_ms >= config::min_staking_duration_ms() &&
            duration_ms <= config::max_staking_duration_ms(),
            EInvalidStakingDuration
        );
        config.staking_duration_ms = option::some(duration_ms);
    }

    /// Set minimum stake duration
    public fun set_staking_min_duration_ms(config: &mut CreatorTokenConfig, duration_ms: u64) {
        assert!(duration_ms <= config::max_min_stake_duration_ms(), EInvalidStakingMinDuration);
        config.staking_min_duration_ms = option::some(duration_ms);
    }

    /// Set early unstake fee
    public fun set_staking_early_fee_bps(config: &mut CreatorTokenConfig, bps: u64) {
        assert!(bps <= 1000, EInvalidStakingFee); // Max 10%
        config.staking_early_fee_bps = option::some(bps);
    }

    /// Set stake fee
    public fun set_staking_stake_fee_bps(config: &mut CreatorTokenConfig, bps: u64) {
        assert!(bps <= config::max_stake_fee_bps(), EInvalidStakingFee);
        config.staking_stake_fee_bps = option::some(bps);
    }

    /// Set unstake fee
    public fun set_staking_unstake_fee_bps(config: &mut CreatorTokenConfig, bps: u64) {
        assert!(bps <= config::max_stake_fee_bps(), EInvalidStakingFee);
        config.staking_unstake_fee_bps = option::some(bps);
    }

    /// Set DAO enabled
    public fun set_dao_enabled(config: &mut CreatorTokenConfig, enabled: bool) {
        config.dao_enabled = option::some(enabled);
    }

    /// Set DAO quorum
    public fun set_dao_quorum_bps(config: &mut CreatorTokenConfig, bps: u64) {
        assert!(bps > 0 && bps <= config::max_dao_quorum_bps(), EInvalidDAOQuorum);
        config.dao_quorum_bps = option::some(bps);
    }

    /// Set voting delay
    public fun set_dao_voting_delay_ms(config: &mut CreatorTokenConfig, delay_ms: u64) {
        assert!(
            delay_ms >= config::min_dao_voting_delay_ms() &&
            delay_ms <= config::max_dao_voting_delay_ms(),
            EInvalidDAOVotingDelay
        );
        config.dao_voting_delay_ms = option::some(delay_ms);
    }

    /// Set voting period
    public fun set_dao_voting_period_ms(config: &mut CreatorTokenConfig, period_ms: u64) {
        assert!(
            period_ms >= config::min_dao_voting_period_ms() &&
            period_ms <= config::max_dao_voting_period_ms(),
            EInvalidDAOVotingPeriod
        );
        config.dao_voting_period_ms = option::some(period_ms);
    }

    /// Set timelock delay
    public fun set_dao_timelock_delay_ms(config: &mut CreatorTokenConfig, delay_ms: u64) {
        assert!(
            delay_ms >= config::min_dao_timelock_delay_ms() &&
            delay_ms <= config::max_dao_timelock_delay_ms(),
            EInvalidDAOTimelockDelay
        );
        config.dao_timelock_delay_ms = option::some(delay_ms);
    }

    /// Set proposal threshold
    public fun set_dao_proposal_threshold_bps(config: &mut CreatorTokenConfig, bps: u64) {
        assert!(bps > 0 && bps <= config::max_dao_proposal_threshold_bps(), EInvalidDAOProposalThreshold);
        config.dao_proposal_threshold_bps = option::some(bps);
    }

    /// Set council enabled
    public fun set_dao_council_enabled(config: &mut CreatorTokenConfig, enabled: bool) {
        config.dao_council_enabled = option::some(enabled);
    }

    /// Enable airdrop with specified percentage
    public fun enable_airdrop(config: &mut CreatorTokenConfig, bps: u64) {
        assert!(bps <= MAX_AIRDROP_BPS, EInvalidAirdropBps);
        config.airdrop_enabled = true;
        config.airdrop_bps = bps;
    }

    /// Set airdrop merkle root (for merkle tree based airdrops)
    public fun set_airdrop_merkle_root(config: &mut CreatorTokenConfig, root: vector<u8>) {
        config.airdrop_merkle_root = option::some(root);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTERS - Return value or platform default
    // ═══════════════════════════════════════════════════════════════════════

    /// Get staking enabled (returns creator override or platform default)
    public fun get_staking_enabled(
        config: &CreatorTokenConfig,
        platform: &LaunchpadConfig
    ): bool {
        if (option::is_some(&config.staking_enabled)) {
            *option::borrow(&config.staking_enabled)
        } else {
            config::staking_enabled(platform)
        }
    }

    /// Get staking reward bps
    public fun get_staking_reward_bps(
        config: &CreatorTokenConfig,
        platform: &LaunchpadConfig
    ): u64 {
        if (option::is_some(&config.staking_reward_bps)) {
            *option::borrow(&config.staking_reward_bps)
        } else {
            config::staking_reward_bps(platform)
        }
    }

    /// Get staking duration
    public fun get_staking_duration_ms(
        config: &CreatorTokenConfig,
        platform: &LaunchpadConfig
    ): u64 {
        if (option::is_some(&config.staking_duration_ms)) {
            *option::borrow(&config.staking_duration_ms)
        } else {
            config::staking_duration_ms(platform)
        }
    }

    /// Get minimum stake duration
    public fun get_staking_min_duration_ms(
        config: &CreatorTokenConfig,
        platform: &LaunchpadConfig
    ): u64 {
        if (option::is_some(&config.staking_min_duration_ms)) {
            *option::borrow(&config.staking_min_duration_ms)
        } else {
            config::staking_min_duration_ms(platform)
        }
    }

    /// Get early unstake fee
    public fun get_staking_early_fee_bps(
        config: &CreatorTokenConfig,
        platform: &LaunchpadConfig
    ): u64 {
        if (option::is_some(&config.staking_early_fee_bps)) {
            *option::borrow(&config.staking_early_fee_bps)
        } else {
            config::staking_early_fee_bps(platform)
        }
    }

    /// Get stake fee
    public fun get_staking_stake_fee_bps(
        config: &CreatorTokenConfig,
        platform: &LaunchpadConfig
    ): u64 {
        if (option::is_some(&config.staking_stake_fee_bps)) {
            *option::borrow(&config.staking_stake_fee_bps)
        } else {
            config::staking_stake_fee_bps(platform)
        }
    }

    /// Get unstake fee
    public fun get_staking_unstake_fee_bps(
        config: &CreatorTokenConfig,
        platform: &LaunchpadConfig
    ): u64 {
        if (option::is_some(&config.staking_unstake_fee_bps)) {
            *option::borrow(&config.staking_unstake_fee_bps)
        } else {
            config::staking_unstake_fee_bps(platform)
        }
    }

    /// Get DAO enabled
    public fun get_dao_enabled(
        config: &CreatorTokenConfig,
        platform: &LaunchpadConfig
    ): bool {
        if (option::is_some(&config.dao_enabled)) {
            *option::borrow(&config.dao_enabled)
        } else {
            config::dao_enabled(platform)
        }
    }

    /// Get DAO quorum
    public fun get_dao_quorum_bps(
        config: &CreatorTokenConfig,
        platform: &LaunchpadConfig
    ): u64 {
        if (option::is_some(&config.dao_quorum_bps)) {
            *option::borrow(&config.dao_quorum_bps)
        } else {
            config::dao_quorum_bps(platform)
        }
    }

    /// Get voting delay
    public fun get_dao_voting_delay_ms(
        config: &CreatorTokenConfig,
        platform: &LaunchpadConfig
    ): u64 {
        if (option::is_some(&config.dao_voting_delay_ms)) {
            *option::borrow(&config.dao_voting_delay_ms)
        } else {
            config::dao_voting_delay_ms(platform)
        }
    }

    /// Get voting period
    public fun get_dao_voting_period_ms(
        config: &CreatorTokenConfig,
        platform: &LaunchpadConfig
    ): u64 {
        if (option::is_some(&config.dao_voting_period_ms)) {
            *option::borrow(&config.dao_voting_period_ms)
        } else {
            config::dao_voting_period_ms(platform)
        }
    }

    /// Get timelock delay
    public fun get_dao_timelock_delay_ms(
        config: &CreatorTokenConfig,
        platform: &LaunchpadConfig
    ): u64 {
        if (option::is_some(&config.dao_timelock_delay_ms)) {
            *option::borrow(&config.dao_timelock_delay_ms)
        } else {
            config::dao_timelock_delay_ms(platform)
        }
    }

    /// Get proposal threshold
    public fun get_dao_proposal_threshold_bps(
        config: &CreatorTokenConfig,
        platform: &LaunchpadConfig
    ): u64 {
        if (option::is_some(&config.dao_proposal_threshold_bps)) {
            *option::borrow(&config.dao_proposal_threshold_bps)
        } else {
            config::dao_proposal_threshold_bps(platform)
        }
    }

    /// Get council enabled
    public fun get_dao_council_enabled(
        config: &CreatorTokenConfig,
        platform: &LaunchpadConfig
    ): bool {
        if (option::is_some(&config.dao_council_enabled)) {
            *option::borrow(&config.dao_council_enabled)
        } else {
            config::dao_council_enabled(platform)
        }
    }

    // ─── Airdrop Getters ────────────────────────────────────────────────────

    public fun airdrop_enabled(config: &CreatorTokenConfig): bool {
        config.airdrop_enabled
    }

    public fun airdrop_bps(config: &CreatorTokenConfig): u64 {
        config.airdrop_bps
    }

    public fun airdrop_merkle_root(config: &CreatorTokenConfig): &Option<vector<u8>> {
        &config.airdrop_merkle_root
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RAW GETTERS (for checking if override exists)
    // ═══════════════════════════════════════════════════════════════════════

    public fun has_staking_enabled_override(config: &CreatorTokenConfig): bool {
        option::is_some(&config.staking_enabled)
    }

    public fun has_dao_enabled_override(config: &CreatorTokenConfig): bool {
        option::is_some(&config.dao_enabled)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun max_airdrop_bps(): u64 { MAX_AIRDROP_BPS }
}
