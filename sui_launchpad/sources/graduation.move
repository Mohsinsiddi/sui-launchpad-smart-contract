/// Graduation module - handles token migration from bonding curve to DEX
/// Tokens graduate when they reach the market cap threshold
///
/// LP Token Distribution (Fund Safety):
/// - Creator: 0-30% of LP tokens (vested over 6mo cliff + 12mo vesting)
/// - Community: 70-100% of LP tokens (burned by default = locked forever)
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

    /// Creator LP vesting schedule - holds creator's LP tokens until vesting completes
    /// Creator can claim tokens linearly after cliff period ends
    public struct CreatorLPVesting<phantom LP> has key, store {
        id: UID,
        pool_id: ID,
        creator: address,
        lp_balance: Balance<LP>,
        total_amount: u64,
        claimed_amount: u64,
        start_time: u64,
        cliff_ms: u64,
        vesting_ms: u64,
        lp_type: TypeName,
    }

    /// LP Distribution info passed to DEX adapters
    public struct LPDistributionConfig has copy, drop, store {
        creator: address,
        creator_bps: u64,
        creator_cliff_ms: u64,
        creator_vesting_ms: u64,
        community_destination: u8, // 0=burn, 1=dao, 2=staking, 3=community_vest
        dao_address: address,
        staking_address: address,
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
    /// - Creator: 0-30% (vested with cliff + linear vesting)
    /// - Community: 70-100% (burned/dao/staking/vested based on config)
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
        let _tokens_for_liquidity = total_tokens - creator_tokens - platform_tokens;

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

        // Build LP distribution config for DEX adapter
        let lp_distribution = LPDistributionConfig {
            creator,
            creator_bps: config::creator_lp_bps(config),
            creator_cliff_ms: config::creator_lp_cliff_ms(config),
            creator_vesting_ms: config::creator_lp_vesting_ms(config),
            community_destination: config::community_lp_destination(config),
            dao_address: config::treasury(config),     // DAO uses treasury for now
            staking_address: config::treasury(config), // Staking uses treasury for now
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
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GRADUATION COMPLETION (called by DEX adapters)
    // ═══════════════════════════════════════════════════════════════════════

    /// Complete graduation after DEX pool creation
    /// DEX adapter calls this after creating liquidity pool
    /// LP tokens should have already been distributed via distribute_lp_tokens
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
        } = pending;

        let sui_amount = balance::value(&sui_balance);
        let token_amount = balance::value(&token_balance);
        let timestamp = clock.timestamp_ms();

        // Balances should be zero after DEX adapter consumed them
        // If not zero, destroy remaining (edge case)
        balance::destroy_zero(sui_balance);
        balance::destroy_zero(token_balance);

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
            community_lp_destination: lp_distribution.community_destination,
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
        } = pending;

        let timestamp = clock.timestamp_ms();

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
            community_lp_destination: lp_distribution.community_destination,
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
    // LP DISTRIBUTION (called by DEX adapters after creating LP)
    // ═══════════════════════════════════════════════════════════════════════

    /// Distribute LP tokens according to config
    /// DEX adapter calls this after receiving LP tokens from pool creation
    /// Returns (creator_lp_amount, community_lp_amount)
    public fun distribute_lp_tokens<T, LP: store>(
        pending: &PendingGraduation<T>,
        mut lp_tokens: Coin<LP>,
        pool_id: ID,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (u64, u64) {
        let total_lp = coin::value(&lp_tokens);
        assert!(total_lp > 0, EInvalidLPAmount);

        let lp_config = &pending.lp_distribution;

        // Calculate split
        let creator_lp_amount = math::bps(total_lp, lp_config.creator_bps);
        let community_lp_amount = total_lp - creator_lp_amount;

        // Handle creator LP (vested)
        if (creator_lp_amount > 0) {
            let creator_lp = coin::split(&mut lp_tokens, creator_lp_amount, ctx);

            // Create vesting schedule for creator
            let vesting = CreatorLPVesting<LP> {
                id: object::new(ctx),
                pool_id,
                creator: lp_config.creator,
                lp_balance: coin::into_balance(creator_lp),
                total_amount: creator_lp_amount,
                claimed_amount: 0,
                start_time: clock.timestamp_ms(),
                cliff_ms: lp_config.creator_cliff_ms,
                vesting_ms: lp_config.creator_vesting_ms,
                lp_type: type_name::with_defining_ids<LP>(),
            };

            // Transfer vesting schedule to creator
            transfer::transfer(vesting, lp_config.creator);
        };

        // Handle community LP (burn/dao/staking/vest)
        if (community_lp_amount > 0) {
            let dest = lp_config.community_destination;

            if (dest == config::lp_dest_burn()) {
                // Burn = send to dead address (0x0)
                transfer::public_transfer(lp_tokens, BURN_ADDRESS);
            } else if (dest == config::lp_dest_dao()) {
                // Send to DAO treasury
                transfer::public_transfer(lp_tokens, lp_config.dao_address);
            } else if (dest == config::lp_dest_staking()) {
                // Send to staking contract
                transfer::public_transfer(lp_tokens, lp_config.staking_address);
            } else {
                // Community vest - send to treasury for now (future: vesting contract)
                transfer::public_transfer(lp_tokens, lp_config.dao_address);
            };
        } else {
            // No community LP, destroy empty coin
            coin::destroy_zero(lp_tokens);
        };

        (creator_lp_amount, community_lp_amount)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CREATOR LP VESTING CLAIMS
    // ═══════════════════════════════════════════════════════════════════════

    /// Calculate how much LP the creator can claim now
    public fun claimable_lp<LP: store>(
        vesting: &CreatorLPVesting<LP>,
        clock: &Clock,
    ): u64 {
        let now = clock.timestamp_ms();
        let start = vesting.start_time;
        let cliff_end = start + vesting.cliff_ms;

        // Before cliff ends, nothing is claimable
        if (now < cliff_end) {
            return 0
        };

        let vesting_end = cliff_end + vesting.vesting_ms;

        // Calculate total vested
        let vested = if (now >= vesting_end) {
            // Fully vested
            vesting.total_amount
        } else {
            // Linear vesting after cliff
            let time_since_cliff = now - cliff_end;
            let vested_ratio = (time_since_cliff as u128) * 10000 / (vesting.vesting_ms as u128);
            let vested_amount = (vesting.total_amount as u128) * vested_ratio / 10000;
            (vested_amount as u64)
        };

        // Subtract already claimed
        if (vested > vesting.claimed_amount) {
            vested - vesting.claimed_amount
        } else {
            0
        }
    }

    /// Creator claims their vested LP tokens
    public fun claim_creator_lp<LP: store>(
        vesting: &mut CreatorLPVesting<LP>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<LP> {
        // Only creator can claim
        assert!(ctx.sender() == vesting.creator, ENotReadyForGraduation);

        let claimable = claimable_lp(vesting, clock);
        assert!(claimable > 0, EInsufficientLiquidity);

        // Update claimed amount
        vesting.claimed_amount = vesting.claimed_amount + claimable;

        // Extract and return LP tokens
        coin::from_balance(balance::split(&mut vesting.lp_balance, claimable), ctx)
    }

    /// Check if all LP tokens have been claimed and destroy vesting object
    public fun destroy_empty_vesting<LP: store>(
        vesting: CreatorLPVesting<LP>,
    ) {
        let CreatorLPVesting {
            id,
            pool_id: _,
            creator: _,
            lp_balance,
            total_amount: _,
            claimed_amount: _,
            start_time: _,
            cliff_ms: _,
            vesting_ms: _,
            lp_type: _,
        } = vesting;

        balance::destroy_zero(lp_balance);
        object::delete(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VESTING GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun vesting_pool_id<LP: store>(v: &CreatorLPVesting<LP>): ID { v.pool_id }
    public fun vesting_creator<LP: store>(v: &CreatorLPVesting<LP>): address { v.creator }
    public fun vesting_total_amount<LP: store>(v: &CreatorLPVesting<LP>): u64 { v.total_amount }
    public fun vesting_claimed_amount<LP: store>(v: &CreatorLPVesting<LP>): u64 { v.claimed_amount }
    public fun vesting_start_time<LP: store>(v: &CreatorLPVesting<LP>): u64 { v.start_time }
    public fun vesting_cliff_ms<LP: store>(v: &CreatorLPVesting<LP>): u64 { v.cliff_ms }
    public fun vesting_vesting_ms<LP: store>(v: &CreatorLPVesting<LP>): u64 { v.vesting_ms }
    public fun vesting_remaining<LP: store>(v: &CreatorLPVesting<LP>): u64 { balance::value(&v.lp_balance) }

    // ═══════════════════════════════════════════════════════════════════════
    // LP DISTRIBUTION CONFIG GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun lp_config_creator(c: &LPDistributionConfig): address { c.creator }
    public fun lp_config_creator_bps(c: &LPDistributionConfig): u64 { c.creator_bps }
    public fun lp_config_creator_cliff_ms(c: &LPDistributionConfig): u64 { c.creator_cliff_ms }
    public fun lp_config_creator_vesting_ms(c: &LPDistributionConfig): u64 { c.creator_vesting_ms }
    public fun lp_config_community_destination(c: &LPDistributionConfig): u8 { c.community_destination }

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
}
