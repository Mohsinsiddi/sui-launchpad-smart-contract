/// Graduation module - handles token migration from bonding curve to DEX
/// Tokens graduate when they reach the market cap threshold
///
/// LP/Position Distribution at Graduation:
/// ────────────────────────────────────────
/// - Creator: 2.5% (VESTED via sui_vesting package)
/// - Protocol: 2.5% (DIRECT transfer to treasury)
/// - DAO: 95% (DIRECT transfer to DAO treasury)
///
/// PTB Flow for Graduation:
/// ────────────────────────
/// 1. Call initiate_graduation() → PendingGraduation
/// 2. Extract SUI/tokens from PendingGraduation
/// 3. Call DEX to create pool/position
/// 4. Call split_lp_tokens() → (creator_coin, protocol_coin, dao_coin)
/// 5. For creator_coin: Call sui_vesting::vesting::create_schedule()
/// 6. Transfer protocol_coin to treasury
/// 7. Transfer/burn dao_coin based on config
/// 8. Call complete_graduation()
module sui_launchpad::graduation {

    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::Clock;
    use std::type_name::{Self, TypeName};

    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::AdminCap;
    use sui_launchpad::bonding_curve::{Self, BondingPool};
    use sui_launchpad::registry::{Self, Registry};
    use sui_launchpad::math;
    use sui_launchpad::events;

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    const ENotReadyForGraduation: u64 = 400;
    const EAlreadyGraduated: u64 = 401;
    const EPoolPaused: u64 = 402;
    const EInsufficientLiquidity: u64 = 403;
    const EInvalidDexType: u64 = 404;
    const EInvalidLPAmount: u64 = 405;
    const EStakingTokensAlreadyExtracted: u64 = 406;
    const EStakingNotEnabled: u64 = 407;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Dead address for burning LP tokens (provably unspendable)
    const BURN_ADDRESS: address = @0x0;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Graduation receipt - proof of successful DEX migration
    public struct GraduationReceipt has key, store {
        id: UID,
        pool_id: ID,
        dex_type: u8,
        dex_pool_id: ID,
        sui_to_liquidity: u64,
        tokens_to_liquidity: u64,
        graduation_fee: u64,
        graduated_at: u64,
        // LP distribution tracking
        total_lp_tokens: u64,
        creator_lp_tokens: u64,
        community_lp_tokens: u64,
        community_lp_destination: u8,
    }

    /// LP/Position Distribution info passed to DEX adapters
    /// Distribution: Creator (vested) + Protocol (direct) + DAO (remainder)
    public struct LPDistributionConfig has copy, drop, store {
        // Creator settings (VESTED via sui_vesting)
        creator: address,
        creator_bps: u64,              // Creator's share (default 2.5%)
        creator_cliff_ms: u64,         // Cliff before vesting starts
        creator_vesting_ms: u64,       // Linear vesting duration

        // Protocol settings (DIRECT TRANSFER)
        protocol_bps: u64,             // Protocol's share (default 2.5%)
        protocol_treasury: address,    // Where protocol LP goes

        // DAO settings (REMAINDER = 100% - creator - protocol)
        dao_bps: u64,                  // DAO's share (calculated, default 95%)
        dao_treasury: address,         // Where DAO LP goes
        dao_destination: u8,           // 0=burn, 1=dao_treasury, 2=staking, 3=vest
        dao_cliff_ms: u64,             // If destination = vest
        dao_vesting_ms: u64,           // If destination = vest
    }

    /// Configuration for staking pool creation at graduation
    /// Passed via PendingGraduation to PTB for staking pool setup
    public struct StakingConfig has copy, drop, store {
        /// Whether staking is enabled for this graduation
        enabled: bool,
        /// Duration of the staking reward period (in ms)
        duration_ms: u64,
        /// Minimum stake duration before withdrawal (in ms)
        min_stake_duration_ms: u64,
        /// Early unstake fee in basis points
        early_unstake_fee_bps: u64,
        /// Fee on staking in basis points
        stake_fee_bps: u64,
        /// Fee on unstaking in basis points
        unstake_fee_bps: u64,
        /// Who receives the PoolAdminCap (0=creator, 1=dao, 2=platform)
        admin_destination: u8,
        /// Type of reward token (0=same_token, 1=sui, 2=custom)
        reward_type: u8,
    }

    /// Pending graduation - hot potato that must be consumed
    /// DEX adapter takes this and creates liquidity pool
    public struct PendingGraduation<phantom T> {
        pool_id: ID,
        sui_balance: Balance<SUI>,
        token_balance: Balance<T>,
        graduation_fee: u64,
        dex_type: u8,
        // LP distribution info
        creator: address,
        lp_distribution: LPDistributionConfig,
        // Staking integration
        staking_balance: Balance<T>,
        staking_config: StakingConfig,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GRADUATION INITIATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Check if pool is ready for graduation
    public fun can_graduate<T>(
        pool: &BondingPool<T>,
        config: &LaunchpadConfig,
    ): bool {
        bonding_curve::check_graduation_ready(pool, config)
    }

    /// Initiate graduation - admin only
    /// Returns PendingGraduation which must be consumed by a DEX adapter
    ///
    /// Token Distribution at Graduation:
    /// - Creator: 0-5% (admin configurable via creator_graduation_bps)
    /// - Platform: 2.5-5% (admin configurable via platform_graduation_bps)
    /// - Remaining: Goes to DEX liquidity pool
    ///
    /// LP Token Distribution (after DEX creates pool):
    /// - Creator: 2.5% (vested via sui_vesting package)
    /// - Protocol: 2.5% (direct transfer to treasury)
    /// - DAO: 95% (direct transfer/burn based on config)
    public fun initiate_graduation<T>(
        _admin: &AdminCap,
        pool: &mut BondingPool<T>,
        config: &LaunchpadConfig,
        dex_type: u8,
        ctx: &mut TxContext,
    ): PendingGraduation<T> {
        // Validations
        assert!(!bonding_curve::is_paused(pool), EPoolPaused);
        assert!(!bonding_curve::is_graduated(pool), EAlreadyGraduated);
        assert!(bonding_curve::check_graduation_ready(pool, config), ENotReadyForGraduation);
        assert!(dex_type <= config::dex_suidex(), EInvalidDexType);

        // Calculate amounts for liquidity
        let total_sui = bonding_curve::sui_balance(pool);
        let total_tokens = bonding_curve::token_balance(pool);

        // Calculate graduation fee (SUI)
        let graduation_fee = math::bps(total_sui, config::graduation_fee_bps(config));
        let sui_for_liquidity = total_sui - graduation_fee;

        // Validate minimum liquidity
        assert!(sui_for_liquidity >= config::min_graduation_liquidity(config), EInsufficientLiquidity);

        // Calculate token allocations at graduation
        let creator_tokens = math::bps(total_tokens, config::creator_graduation_bps(config));
        let platform_tokens = math::bps(total_tokens, config::platform_graduation_bps(config));

        // Calculate staking allocation (if enabled)
        let staking_enabled = config::staking_enabled(config);
        let staking_tokens = if (staking_enabled) {
            math::bps(total_tokens, config::staking_reward_bps(config))
        } else {
            0
        };

        let _tokens_for_liquidity = total_tokens - creator_tokens - platform_tokens - staking_tokens;

        // Mark pool as graduated
        bonding_curve::set_graduated(pool);

        // Extract funds from pool
        let sui_coin = bonding_curve::extract_sui_for_graduation(pool, total_sui, ctx);
        let token_coin = bonding_curve::extract_tokens_for_graduation(pool, total_tokens, ctx);

        // Convert to balances
        let mut sui_balance = coin::into_balance(sui_coin);
        let mut token_balance = coin::into_balance(token_coin);

        // Split and send graduation fee (SUI) to treasury
        let fee_balance = balance::split(&mut sui_balance, graduation_fee);
        transfer::public_transfer(
            coin::from_balance(fee_balance, ctx),
            config::treasury(config)
        );

        // Split and send creator tokens (if any)
        let creator = bonding_curve::creator(pool);
        if (creator_tokens > 0) {
            let creator_balance = balance::split(&mut token_balance, creator_tokens);
            transfer::public_transfer(
                coin::from_balance(creator_balance, ctx),
                creator
            );
        };

        // Split and send platform tokens
        if (platform_tokens > 0) {
            let platform_balance = balance::split(&mut token_balance, platform_tokens);
            transfer::public_transfer(
                coin::from_balance(platform_balance, ctx),
                config::treasury(config)
            );
        };

        // Split staking tokens (kept in PendingGraduation for later extraction)
        let staking_balance = if (staking_tokens > 0) {
            balance::split(&mut token_balance, staking_tokens)
        } else {
            balance::zero<T>()
        };

        // Build staking config from LaunchpadConfig
        let staking_config = StakingConfig {
            enabled: staking_enabled,
            duration_ms: config::staking_duration_ms(config),
            min_stake_duration_ms: config::staking_min_duration_ms(config),
            early_unstake_fee_bps: config::staking_early_fee_bps(config),
            stake_fee_bps: config::staking_stake_fee_bps(config),
            unstake_fee_bps: config::staking_unstake_fee_bps(config),
            admin_destination: config::staking_admin_destination(config),
            reward_type: config::staking_reward_type(config),
        };

        // Build LP distribution config for DEX adapter
        // Distribution: Creator (vested) + Protocol (direct) + DAO (remainder)
        let lp_distribution = LPDistributionConfig {
            // Creator (VESTED via sui_vesting)
            creator,
            creator_bps: config::creator_lp_bps(config),
            creator_cliff_ms: config::creator_lp_cliff_ms(config),
            creator_vesting_ms: config::creator_lp_vesting_ms(config),

            // Protocol (DIRECT)
            protocol_bps: config::protocol_lp_bps(config),
            protocol_treasury: config::treasury(config),

            // DAO (REMAINDER)
            dao_bps: config::dao_lp_bps(config),
            dao_treasury: config::dao_treasury(config),
            dao_destination: config::dao_lp_destination(config),
            dao_cliff_ms: config::dao_lp_cliff_ms(config),
            dao_vesting_ms: config::dao_lp_vesting_ms(config),
        };

        // Return pending graduation with remaining tokens for DEX liquidity
        PendingGraduation {
            pool_id: object::id(pool),
            sui_balance,
            token_balance, // Now contains only tokens_for_liquidity
            graduation_fee,
            dex_type,
            creator,
            lp_distribution,
            staking_balance,
            staking_config,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GRADUATION COMPLETION (called by DEX adapters)
    // ═══════════════════════════════════════════════════════════════════════

    /// Complete graduation after DEX pool creation
    /// DEX adapter calls this after creating liquidity pool
    /// LP tokens should have already been distributed via split_lp_tokens
    public fun complete_graduation<T>(
        pending: PendingGraduation<T>,
        registry: &mut Registry,
        dex_pool_id: ID,
        total_lp_tokens: u64,
        creator_lp_tokens: u64,
        community_lp_tokens: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): GraduationReceipt {
        let PendingGraduation {
            pool_id,
            sui_balance,
            token_balance,
            graduation_fee,
            dex_type,
            creator: _,
            lp_distribution,
            staking_balance,
            staking_config: _,
        } = pending;

        let sui_amount = balance::value(&sui_balance);
        let token_amount = balance::value(&token_balance);
        let timestamp = clock.timestamp_ms();

        // Balances should be zero after DEX adapter consumed them
        // If not zero, destroy remaining (edge case)
        balance::destroy_zero(sui_balance);
        balance::destroy_zero(token_balance);
        // Staking balance should have been extracted if enabled
        balance::destroy_zero(staking_balance);

        // Record graduation in registry
        registry::record_graduation(registry, pool_id, dex_type, dex_pool_id);

        // Emit graduation event
        events::emit_token_graduated(
            pool_id,
            type_name::with_original_ids<T>(),
            dex_type,
            dex_pool_id,
            0, // final_price
            sui_amount + graduation_fee,
            sui_amount,
            token_amount,
            graduation_fee,
            0, // platform_tokens already distributed
            timestamp,
        );

        // Create receipt with LP distribution info
        GraduationReceipt {
            id: object::new(ctx),
            pool_id,
            dex_type,
            dex_pool_id,
            sui_to_liquidity: sui_amount,
            tokens_to_liquidity: token_amount,
            graduation_fee,
            graduated_at: timestamp,
            total_lp_tokens,
            creator_lp_tokens,
            community_lp_tokens,
            community_lp_destination: lp_distribution.dao_destination,
        }
    }

    /// Complete graduation with leftover handling
    /// Use this if DEX has slippage and doesn't use all liquidity
    #[allow(lint(self_transfer))]
    public fun complete_graduation_with_remainder<T>(
        pending: PendingGraduation<T>,
        registry: &mut Registry,
        dex_pool_id: ID,
        sui_used: u64,
        tokens_used: u64,
        total_lp_tokens: u64,
        creator_lp_tokens: u64,
        community_lp_tokens: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): GraduationReceipt {
        let PendingGraduation {
            pool_id,
            sui_balance,
            token_balance,
            graduation_fee,
            dex_type,
            creator: _,
            lp_distribution,
            staking_balance,
            staking_config: _,
        } = pending;

        let timestamp = clock.timestamp_ms();

        // Staking balance should have been extracted if enabled
        balance::destroy_zero(staking_balance);

        // Handle remaining SUI (send to sender)
        let sui_remaining = balance::value(&sui_balance);
        if (sui_remaining > 0) {
            transfer::public_transfer(
                coin::from_balance(sui_balance, ctx),
                ctx.sender()
            );
        } else {
            balance::destroy_zero(sui_balance);
        };

        // Handle remaining tokens (burn or send back)
        let tokens_remaining = balance::value(&token_balance);
        if (tokens_remaining > 0) {
            transfer::public_transfer(
                coin::from_balance(token_balance, ctx),
                ctx.sender()
            );
        } else {
            balance::destroy_zero(token_balance);
        };

        // Record graduation
        registry::record_graduation(registry, pool_id, dex_type, dex_pool_id);

        // Emit event
        events::emit_token_graduated(
            pool_id,
            type_name::with_original_ids<T>(),
            dex_type,
            dex_pool_id,
            0,
            sui_used + graduation_fee,
            sui_used,
            tokens_used,
            graduation_fee,
            0,
            timestamp,
        );

        GraduationReceipt {
            id: object::new(ctx),
            pool_id,
            dex_type,
            dex_pool_id,
            sui_to_liquidity: sui_used,
            tokens_to_liquidity: tokens_used,
            graduation_fee,
            graduated_at: timestamp,
            total_lp_tokens,
            creator_lp_tokens,
            community_lp_tokens,
            community_lp_destination: lp_distribution.dao_destination,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PENDING GRADUATION ACCESSORS (for DEX adapters)
    // ═══════════════════════════════════════════════════════════════════════

    /// Get pool ID from pending graduation
    public fun pending_pool_id<T>(pending: &PendingGraduation<T>): ID {
        pending.pool_id
    }

    /// Get SUI amount available for liquidity
    public fun pending_sui_amount<T>(pending: &PendingGraduation<T>): u64 {
        balance::value(&pending.sui_balance)
    }

    /// Get token amount available for liquidity
    public fun pending_token_amount<T>(pending: &PendingGraduation<T>): u64 {
        balance::value(&pending.token_balance)
    }

    /// Get DEX type for this graduation
    public fun pending_dex_type<T>(pending: &PendingGraduation<T>): u8 {
        pending.dex_type
    }

    /// Extract SUI for DEX adapter to use
    public fun extract_sui<T>(
        pending: &mut PendingGraduation<T>,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<SUI> {
        coin::from_balance(balance::split(&mut pending.sui_balance, amount), ctx)
    }

    /// Extract all SUI for DEX adapter
    public fun extract_all_sui<T>(
        pending: &mut PendingGraduation<T>,
        ctx: &mut TxContext
    ): Coin<SUI> {
        let amount = balance::value(&pending.sui_balance);
        coin::from_balance(balance::split(&mut pending.sui_balance, amount), ctx)
    }

    /// Extract tokens for DEX adapter to use
    public fun extract_tokens<T>(
        pending: &mut PendingGraduation<T>,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<T> {
        coin::from_balance(balance::split(&mut pending.token_balance, amount), ctx)
    }

    /// Extract all tokens for DEX adapter
    public fun extract_all_tokens<T>(
        pending: &mut PendingGraduation<T>,
        ctx: &mut TxContext
    ): Coin<T> {
        let amount = balance::value(&pending.token_balance);
        coin::from_balance(balance::split(&mut pending.token_balance, amount), ctx)
    }

    /// Get LP distribution config from pending graduation
    public fun pending_lp_distribution<T>(pending: &PendingGraduation<T>): &LPDistributionConfig {
        &pending.lp_distribution
    }

    /// Get creator address from pending graduation
    public fun pending_creator<T>(pending: &PendingGraduation<T>): address {
        pending.creator
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING INTEGRATION ACCESSORS (for PTB staking pool creation)
    // ═══════════════════════════════════════════════════════════════════════

    /// Get staking config from pending graduation
    public fun pending_staking_config<T>(pending: &PendingGraduation<T>): &StakingConfig {
        &pending.staking_config
    }

    /// Get staking token amount available
    public fun pending_staking_amount<T>(pending: &PendingGraduation<T>): u64 {
        balance::value(&pending.staking_balance)
    }

    /// Check if staking is enabled for this graduation
    public fun pending_staking_enabled<T>(pending: &PendingGraduation<T>): bool {
        pending.staking_config.enabled
    }

    /// Extract staking tokens for staking pool creation
    /// Called by PTB to get tokens to fund the staking pool
    public fun extract_staking_tokens<T>(
        pending: &mut PendingGraduation<T>,
        ctx: &mut TxContext
    ): Coin<T> {
        assert!(pending.staking_config.enabled, EStakingNotEnabled);
        let amount = balance::value(&pending.staking_balance);
        assert!(amount > 0, EStakingTokensAlreadyExtracted);
        coin::from_balance(balance::split(&mut pending.staking_balance, amount), ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING CONFIG GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun staking_config_enabled(c: &StakingConfig): bool { c.enabled }
    public fun staking_config_duration_ms(c: &StakingConfig): u64 { c.duration_ms }
    public fun staking_config_min_stake_duration_ms(c: &StakingConfig): u64 { c.min_stake_duration_ms }
    public fun staking_config_early_unstake_fee_bps(c: &StakingConfig): u64 { c.early_unstake_fee_bps }
    public fun staking_config_stake_fee_bps(c: &StakingConfig): u64 { c.stake_fee_bps }
    public fun staking_config_unstake_fee_bps(c: &StakingConfig): u64 { c.unstake_fee_bps }
    public fun staking_config_admin_destination(c: &StakingConfig): u8 { c.admin_destination }
    public fun staking_config_reward_type(c: &StakingConfig): u8 { c.reward_type }

    // ═══════════════════════════════════════════════════════════════════════
    // LP/POSITION SPLITTING (PTB calls this, then handles vesting separately)
    // Distribution: Creator (vested) + Protocol (direct) + DAO (remainder)
    // ═══════════════════════════════════════════════════════════════════════

    /// Split LP tokens into 3 parts according to config
    /// Returns (creator_coin, protocol_coin, dao_coin)
    ///
    /// PTB should then:
    /// - creator_coin: Call sui_vesting::vesting::create_schedule() for vesting
    /// - protocol_coin: Transfer directly to protocol treasury
    /// - dao_coin: Transfer/burn based on dao_destination config
    public fun split_lp_tokens<T, LP>(
        pending: &PendingGraduation<T>,
        mut lp_tokens: Coin<LP>,
        ctx: &mut TxContext,
    ): (Coin<LP>, Coin<LP>, Coin<LP>) {
        let total_lp = coin::value(&lp_tokens);
        assert!(total_lp > 0, EInvalidLPAmount);

        let lp_config = &pending.lp_distribution;

        // Calculate split (Creator + Protocol + DAO = 100%)
        let creator_lp_amount = math::bps(total_lp, lp_config.creator_bps);
        let protocol_lp_amount = math::bps(total_lp, lp_config.protocol_bps);
        // DAO gets the remainder
        let dao_lp_amount = total_lp - creator_lp_amount - protocol_lp_amount;

        // Split coins
        let creator_coin = coin::split(&mut lp_tokens, creator_lp_amount, ctx);
        let protocol_coin = coin::split(&mut lp_tokens, protocol_lp_amount, ctx);
        // Remaining is DAO coin
        let dao_coin = lp_tokens;

        // Verify DAO amount
        assert!(coin::value(&dao_coin) == dao_lp_amount, EInvalidLPAmount);

        (creator_coin, protocol_coin, dao_coin)
    }

    /// Convenience function: split and handle protocol + DAO transfers
    /// Returns creator_coin for PTB to vest via sui_vesting
    ///
    /// This handles:
    /// - Protocol LP: Direct transfer to protocol treasury
    /// - DAO LP: Transfer/burn based on config
    /// - Creator LP: Returned for PTB to vest
    #[allow(lint(self_transfer))]
    public fun split_and_distribute_lp_tokens<T, LP>(
        pending: &PendingGraduation<T>,
        lp_tokens: Coin<LP>,
        ctx: &mut TxContext,
    ): (Coin<LP>, u64, u64, u64) {
        let (creator_coin, protocol_coin, dao_coin) = split_lp_tokens(pending, lp_tokens, ctx);

        let creator_amount = coin::value(&creator_coin);
        let protocol_amount = coin::value(&protocol_coin);
        let dao_amount = coin::value(&dao_coin);

        let lp_config = &pending.lp_distribution;

        // Transfer protocol LP to treasury
        if (protocol_amount > 0) {
            transfer::public_transfer(protocol_coin, lp_config.protocol_treasury);
        } else {
            coin::destroy_zero(protocol_coin);
        };

        // Handle DAO LP based on destination
        if (dao_amount > 0) {
            let dest = lp_config.dao_destination;

            if (dest == config::lp_dest_burn()) {
                // Burn = send to dead address (0x0) - locked forever
                transfer::public_transfer(dao_coin, BURN_ADDRESS);
            } else if (dest == config::lp_dest_dao()) {
                // Direct transfer to DAO treasury
                transfer::public_transfer(dao_coin, lp_config.dao_treasury);
            } else if (dest == config::lp_dest_staking()) {
                // Send to staking contract (use dao_treasury for now)
                transfer::public_transfer(dao_coin, lp_config.dao_treasury);
            } else {
                // Vested to DAO - send to dao_treasury (future: vesting)
                transfer::public_transfer(dao_coin, lp_config.dao_treasury);
            };
        } else {
            coin::destroy_zero(dao_coin);
        };

        // Return creator coin for PTB to vest via sui_vesting
        (creator_coin, creator_amount, protocol_amount, dao_amount)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LP DISTRIBUTION CONFIG GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    // Creator getters
    public fun lp_config_creator(c: &LPDistributionConfig): address { c.creator }
    public fun lp_config_creator_bps(c: &LPDistributionConfig): u64 { c.creator_bps }
    public fun lp_config_creator_cliff_ms(c: &LPDistributionConfig): u64 { c.creator_cliff_ms }
    public fun lp_config_creator_vesting_ms(c: &LPDistributionConfig): u64 { c.creator_vesting_ms }

    // Protocol getters
    public fun lp_config_protocol_bps(c: &LPDistributionConfig): u64 { c.protocol_bps }
    public fun lp_config_protocol_treasury(c: &LPDistributionConfig): address { c.protocol_treasury }

    // DAO getters
    public fun lp_config_dao_bps(c: &LPDistributionConfig): u64 { c.dao_bps }
    public fun lp_config_dao_treasury(c: &LPDistributionConfig): address { c.dao_treasury }
    public fun lp_config_dao_destination(c: &LPDistributionConfig): u8 { c.dao_destination }
    public fun lp_config_dao_cliff_ms(c: &LPDistributionConfig): u64 { c.dao_cliff_ms }
    public fun lp_config_dao_vesting_ms(c: &LPDistributionConfig): u64 { c.dao_vesting_ms }

    // Deprecated (use dao_* instead)
    public fun lp_config_community_destination(c: &LPDistributionConfig): u8 { c.dao_destination }

    // ═══════════════════════════════════════════════════════════════════════
    // RECEIPT GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun receipt_pool_id(receipt: &GraduationReceipt): ID { receipt.pool_id }
    public fun receipt_dex_type(receipt: &GraduationReceipt): u8 { receipt.dex_type }
    public fun receipt_dex_pool_id(receipt: &GraduationReceipt): ID { receipt.dex_pool_id }
    public fun receipt_sui_to_liquidity(receipt: &GraduationReceipt): u64 { receipt.sui_to_liquidity }
    public fun receipt_tokens_to_liquidity(receipt: &GraduationReceipt): u64 { receipt.tokens_to_liquidity }
    public fun receipt_graduation_fee(receipt: &GraduationReceipt): u64 { receipt.graduation_fee }
    public fun receipt_graduated_at(receipt: &GraduationReceipt): u64 { receipt.graduated_at }
    public fun receipt_total_lp_tokens(receipt: &GraduationReceipt): u64 { receipt.total_lp_tokens }
    public fun receipt_creator_lp_tokens(receipt: &GraduationReceipt): u64 { receipt.creator_lp_tokens }
    public fun receipt_community_lp_tokens(receipt: &GraduationReceipt): u64 { receipt.community_lp_tokens }
    public fun receipt_community_lp_destination(receipt: &GraduationReceipt): u8 { receipt.community_lp_destination }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    #[test_only]
    /// Destroy PendingGraduation for testing (consumes the hot potato)
    public fun destroy_pending_for_testing<T>(pending: PendingGraduation<T>) {
        let PendingGraduation {
            pool_id: _,
            sui_balance,
            token_balance,
            graduation_fee: _,
            dex_type: _,
            creator: _,
            lp_distribution: _,
            staking_balance,
            staking_config: _,
        } = pending;

        balance::destroy_for_testing(sui_balance);
        balance::destroy_for_testing(token_balance);
        balance::destroy_for_testing(staking_balance);
    }

    #[test_only]
    /// Destroy GraduationReceipt for testing
    public fun destroy_receipt_for_testing(receipt: GraduationReceipt) {
        let GraduationReceipt {
            id,
            pool_id: _,
            dex_type: _,
            dex_pool_id: _,
            sui_to_liquidity: _,
            tokens_to_liquidity: _,
            graduation_fee: _,
            graduated_at: _,
            total_lp_tokens: _,
            creator_lp_tokens: _,
            community_lp_tokens: _,
            community_lp_destination: _,
        } = receipt;

        object::delete(id);
    }
}
