/// Bonding curve pool for token trading
/// Linear curve: price = base_price + slope * circulating_supply
///
/// FUND SAFETY:
/// - Treasury cap is frozen after minting (no infinite mint possible)
/// - Hard fee caps prevent honeypot (max 5% creator fee)
/// - LP tokens distributed with community majority at graduation
module sui_launchpad::bonding_curve {

    use std::string::String;
    use std::ascii;
    use std::type_name::{Self, TypeName};
    use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::Clock;

    use sui_launchpad::math;
    use sui_launchpad::config::{Self, LaunchpadConfig};
    use sui_launchpad::access::AdminCap;
    use sui_launchpad::events;

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    const EPoolPaused: u64 = 300;
    const EPoolGraduated: u64 = 301;
    const EPoolLocked: u64 = 302;
    const EInsufficientPayment: u64 = 303;
    const EInsufficientTokens: u64 = 304;
    const EZeroAmount: u64 = 305;
    const ESlippageExceeded: u64 = 306;
    const ETokensAlreadyMinted: u64 = 307;
    const ECreatorFeeTooHigh: u64 = 308;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Maximum creator fee: 5% (500 basis points) - fee on each trade
    const MAX_CREATOR_FEE_BPS: u64 = 500;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// The bonding curve pool for a specific token type
    public struct BondingPool<phantom T> has key, store {
        id: UID,

        // ─── Token Info ────────────────────────────────────────────────────
        /// The token type name for identification
        token_type: TypeName,
        /// Token name (from metadata)
        name: String,
        /// Token symbol (from metadata)
        symbol: ascii::String,
        /// Total supply of tokens
        total_supply: u64,

        // ─── Pool Balances ─────────────────────────────────────────────────
        /// SUI collected from buys
        sui_balance: Balance<SUI>,
        /// Tokens available for sale
        token_balance: Balance<T>,

        // ─── Curve Parameters ──────────────────────────────────────────────
        /// Base price (y-intercept)
        base_price: u64,
        /// Slope of the curve
        slope: u64,
        /// Current circulating supply (tokens sold)
        circulating_supply: u64,

        // ─── Creator Info ──────────────────────────────────────────────────
        /// Token creator address
        creator: address,
        /// Creator fee in basis points (optional, on top of platform fee)
        creator_fee_bps: u64,

        // ─── State ─────────────────────────────────────────────────────────
        /// Whether trading is paused
        paused: bool,
        /// Whether token has graduated to DEX
        graduated: bool,
        /// Reentrancy lock
        locked: bool,

        // ─── Fund Safety ───────────────────────────────────────────────────
        /// Whether treasury cap has been frozen (true = no more minting ever)
        treasury_cap_frozen: bool,

        // ─── Stats ─────────────────────────────────────────────────────────
        /// Total SUI volume traded
        total_volume: u64,
        /// Total trades count
        trade_count: u64,
        /// Creation timestamp
        created_at: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POOL CREATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new bonding pool by registering a token
    /// The creator must provide a fresh TreasuryCap (no tokens minted yet)
    ///
    /// FUND SAFETY: Treasury cap is FROZEN after minting
    /// This ensures NO MORE TOKENS can ever be minted - fixed supply forever
    ///
    /// Token Distribution (admin-configurable via config):
    /// - platform_allocation_bps (e.g., 1%) → Platform treasury (protocol holds)
    /// - Remaining (e.g., 99%) → Pool for bonding curve trading
    /// - Creator gets 0 tokens (earns from creator_fee_bps on trades instead)
    #[allow(lint(self_transfer))]
    public fun create_pool<T>(
        config: &LaunchpadConfig,
        treasury_cap: TreasuryCap<T>,
        metadata: &CoinMetadata<T>,
        creator_fee_bps: u64,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): BondingPool<T> {
        // Validate platform not paused
        config::assert_not_paused(config);

        // Validate no tokens have been minted yet
        assert!(coin::total_supply(&treasury_cap) == 0, ETokensAlreadyMinted);

        // Validate creator fee is within acceptable range (max 5%)
        assert!(creator_fee_bps <= MAX_CREATOR_FEE_BPS, ECreatorFeeTooHigh);

        // Validate creation fee
        let creation_fee = config::creation_fee(config);
        assert!(coin::value(&payment) >= creation_fee, EInsufficientPayment);

        // Get token info from metadata
        let name = coin::get_name(metadata);
        let symbol = coin::get_symbol(metadata);

        // Get curve parameters from config
        let total_supply = config::default_total_supply(config);
        let base_price = config::default_base_price(config);
        let slope = config::default_slope(config);

        // Mint total supply
        let mut treasury = treasury_cap;
        let tokens = coin::mint(&mut treasury, total_supply, ctx);

        // Calculate platform allocation (admin-configurable, e.g., 1%)
        let platform_allocation = math::bps(total_supply, config::platform_allocation_bps(config));

        // Split tokens
        let mut token_balance = coin::into_balance(tokens);

        // Platform tokens → treasury (protocol holds these)
        let platform_tokens = balance::split(&mut token_balance, platform_allocation);
        transfer::public_transfer(
            coin::from_balance(platform_tokens, ctx),
            config::treasury(config)
        );

        // Handle creation fee payment
        let payment_value = coin::value(&payment);
        let mut payment_balance = coin::into_balance(payment);

        // Send creation fee to treasury
        let fee_balance = balance::split(&mut payment_balance, creation_fee);
        transfer::public_transfer(
            coin::from_balance(fee_balance, ctx),
            config::treasury(config)
        );

        // Return excess payment to creator (if any)
        let excess = payment_value - creation_fee;
        if (excess > 0) {
            transfer::public_transfer(
                coin::from_balance(payment_balance, ctx),
                ctx.sender()
            );
        } else {
            balance::destroy_zero(payment_balance);
        };

        let creator = ctx.sender();
        let timestamp = clock.timestamp_ms();

        // ═══════════════════════════════════════════════════════════════════
        // FUND SAFETY: Treasury Cap Freeze
        // ═══════════════════════════════════════════════════════════════════
        // Freeze the treasury cap so no more tokens can ever be minted.
        // This is ALWAYS done for maximum security - fixed supply forever.
        transfer::public_freeze_object(treasury);
        let treasury_cap_frozen = true;

        // Create the pool (remaining tokens go into pool for trading)
        let pool = BondingPool<T> {
            id: object::new(ctx),
            token_type: type_name::with_original_ids<T>(),
            name,
            symbol,
            total_supply,
            sui_balance: balance::zero(),
            token_balance,
            base_price,
            slope,
            circulating_supply: 0, // No tokens in circulation yet
            creator,
            creator_fee_bps,
            paused: false,
            graduated: false,
            locked: false,
            treasury_cap_frozen,
            total_volume: 0,
            trade_count: 0,
            created_at: timestamp,
        };

        // Emit event
        events::emit_token_created(
            object::id(&pool),
            type_name::with_original_ids<T>(),
            creator,
            name,
            symbol,
            total_supply,
            creation_fee,
            timestamp,
        );

        pool
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRADING - BUY
    // ═══════════════════════════════════════════════════════════════════════

    /// Buy tokens with SUI
    public fun buy<T>(
        pool: &mut BondingPool<T>,
        config: &LaunchpadConfig,
        payment: Coin<SUI>,
        min_tokens_out: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        // Validations
        assert!(!pool.paused, EPoolPaused);
        assert!(!pool.graduated, EPoolGraduated);
        assert!(!pool.locked, EPoolLocked);

        let sui_in = coin::value(&payment);
        assert!(sui_in > 0, EZeroAmount);

        // Lock pool (reentrancy guard)
        pool.locked = true;

        // Calculate fees (hard-capped at 5% each for safety)
        let platform_fee = math::bps(sui_in, config::trading_fee_bps(config));
        let creator_fee = math::bps(sui_in, pool.creator_fee_bps);
        let net_sui = sui_in - platform_fee - creator_fee;

        // Calculate tokens out using bonding curve
        let tokens_out = math::tokens_out(
            net_sui,
            pool.circulating_supply,
            pool.base_price,
            pool.slope
        );

        // Slippage check
        assert!(tokens_out >= min_tokens_out, ESlippageExceeded);

        // Check pool has enough tokens
        assert!(balance::value(&pool.token_balance) >= tokens_out, EInsufficientTokens);

        // Update pool state
        pool.circulating_supply = pool.circulating_supply + tokens_out;
        pool.total_volume = pool.total_volume + sui_in;
        pool.trade_count = pool.trade_count + 1;

        // Handle payment
        let mut payment_balance = coin::into_balance(payment);

        // Extract and send platform fee (if any)
        if (platform_fee > 0) {
            let platform_fee_balance = balance::split(&mut payment_balance, platform_fee);
            transfer::public_transfer(
                coin::from_balance(platform_fee_balance, ctx),
                config::treasury(config)
            );
        };

        // Extract and send creator fee (if any)
        if (creator_fee > 0) {
            let creator_fee_balance = balance::split(&mut payment_balance, creator_fee);
            transfer::public_transfer(
                coin::from_balance(creator_fee_balance, ctx),
                pool.creator
            );
        };

        // Add net SUI to pool
        balance::join(&mut pool.sui_balance, payment_balance);

        // Extract tokens for buyer
        let tokens = coin::from_balance(
            balance::split(&mut pool.token_balance, tokens_out),
            ctx
        );

        // Emit trade event
        let price_after = math::get_price(pool.base_price, pool.slope, pool.circulating_supply);
        events::emit_trade(
            object::id(pool),
            pool.token_type,
            ctx.sender(),
            true, // is_buy
            sui_in,
            tokens_out,
            price_after,
            platform_fee,
            creator_fee,
            pool.circulating_supply,
            clock.timestamp_ms(),
        );

        // Unlock pool
        pool.locked = false;

        tokens
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRADING - SELL
    // ═══════════════════════════════════════════════════════════════════════

    /// Sell tokens for SUI
    public fun sell<T>(
        pool: &mut BondingPool<T>,
        config: &LaunchpadConfig,
        tokens: Coin<T>,
        min_sui_out: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        // Validations
        assert!(!pool.paused, EPoolPaused);
        assert!(!pool.graduated, EPoolGraduated);
        assert!(!pool.locked, EPoolLocked);

        let tokens_in = coin::value(&tokens);
        assert!(tokens_in > 0, EZeroAmount);
        assert!(tokens_in <= pool.circulating_supply, EInsufficientTokens);

        // Lock pool (reentrancy guard)
        pool.locked = true;

        // Calculate SUI out using bonding curve
        let gross_sui_out = math::sui_out(
            tokens_in,
            pool.circulating_supply,
            pool.base_price,
            pool.slope
        );

        // Calculate fees (hard-capped at 5% each for safety)
        let platform_fee = math::bps(gross_sui_out, config::trading_fee_bps(config));
        let creator_fee = math::bps(gross_sui_out, pool.creator_fee_bps);
        let net_sui_out = gross_sui_out - platform_fee - creator_fee;

        // Slippage check
        assert!(net_sui_out >= min_sui_out, ESlippageExceeded);

        // Check pool has enough SUI
        assert!(balance::value(&pool.sui_balance) >= gross_sui_out, EInsufficientPayment);

        // Update pool state
        pool.circulating_supply = pool.circulating_supply - tokens_in;
        pool.total_volume = pool.total_volume + gross_sui_out;
        pool.trade_count = pool.trade_count + 1;

        // Return tokens to pool
        balance::join(&mut pool.token_balance, coin::into_balance(tokens));

        // Extract SUI
        let mut sui_out_balance = balance::split(&mut pool.sui_balance, gross_sui_out);

        // Extract and send platform fee (if any)
        if (platform_fee > 0) {
            let platform_fee_balance = balance::split(&mut sui_out_balance, platform_fee);
            transfer::public_transfer(
                coin::from_balance(platform_fee_balance, ctx),
                config::treasury(config)
            );
        };

        // Extract and send creator fee (if any)
        if (creator_fee > 0) {
            let creator_fee_balance = balance::split(&mut sui_out_balance, creator_fee);
            transfer::public_transfer(
                coin::from_balance(creator_fee_balance, ctx),
                pool.creator
            );
        };

        // Create SUI coin for seller (net amount after fees)
        let sui_coin = coin::from_balance(sui_out_balance, ctx);

        // Emit trade event
        let price_after = math::get_price(pool.base_price, pool.slope, pool.circulating_supply);
        events::emit_trade(
            object::id(pool),
            pool.token_type,
            ctx.sender(),
            false, // is_buy
            gross_sui_out,
            tokens_in,
            price_after,
            platform_fee,
            creator_fee,
            pool.circulating_supply,
            clock.timestamp_ms(),
        );

        // Unlock pool
        pool.locked = false;

        sui_coin
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get current token price
    public fun get_price<T>(pool: &BondingPool<T>): u64 {
        math::get_price(pool.base_price, pool.slope, pool.circulating_supply)
    }

    /// Get market cap (price * circulating supply)
    public fun get_market_cap<T>(pool: &BondingPool<T>): u64 {
        let price = get_price(pool);
        math::mul_div(price, pool.circulating_supply, math::precision() as u64)
    }

    /// Estimate tokens out for given SUI input
    public fun estimate_buy<T>(pool: &BondingPool<T>, config: &LaunchpadConfig, sui_in: u64): u64 {
        let platform_fee = math::bps(sui_in, config::trading_fee_bps(config));
        let creator_fee = math::bps(sui_in, pool.creator_fee_bps);
        let net_sui = sui_in - platform_fee - creator_fee;

        math::tokens_out(net_sui, pool.circulating_supply, pool.base_price, pool.slope)
    }

    /// Estimate SUI out for given token input
    public fun estimate_sell<T>(pool: &BondingPool<T>, config: &LaunchpadConfig, tokens_in: u64): u64 {
        let gross_sui = math::sui_out(tokens_in, pool.circulating_supply, pool.base_price, pool.slope);
        let platform_fee = math::bps(gross_sui, config::trading_fee_bps(config));
        let creator_fee = math::bps(gross_sui, pool.creator_fee_bps);
        gross_sui - platform_fee - creator_fee
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun token_type<T>(pool: &BondingPool<T>): TypeName { pool.token_type }
    public fun name<T>(pool: &BondingPool<T>): String { pool.name }
    public fun symbol<T>(pool: &BondingPool<T>): ascii::String { pool.symbol }
    public fun total_supply<T>(pool: &BondingPool<T>): u64 { pool.total_supply }
    public fun sui_balance<T>(pool: &BondingPool<T>): u64 { balance::value(&pool.sui_balance) }
    public fun token_balance<T>(pool: &BondingPool<T>): u64 { balance::value(&pool.token_balance) }
    public fun base_price<T>(pool: &BondingPool<T>): u64 { pool.base_price }
    public fun slope<T>(pool: &BondingPool<T>): u64 { pool.slope }
    public fun circulating_supply<T>(pool: &BondingPool<T>): u64 { pool.circulating_supply }
    public fun creator<T>(pool: &BondingPool<T>): address { pool.creator }
    public fun creator_fee_bps<T>(pool: &BondingPool<T>): u64 { pool.creator_fee_bps }
    public fun is_paused<T>(pool: &BondingPool<T>): bool { pool.paused }
    public fun is_graduated<T>(pool: &BondingPool<T>): bool { pool.graduated }
    public fun is_treasury_cap_frozen<T>(pool: &BondingPool<T>): bool { pool.treasury_cap_frozen }
    public fun total_volume<T>(pool: &BondingPool<T>): u64 { pool.total_volume }
    public fun trade_count<T>(pool: &BondingPool<T>): u64 { pool.trade_count }
    public fun created_at<T>(pool: &BondingPool<T>): u64 { pool.created_at }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Pause/unpause the pool (admin only)
    public fun set_paused<T>(
        _admin: &AdminCap,
        pool: &mut BondingPool<T>,
        paused: bool,
        clock: &Clock,
    ) {
        pool.paused = paused;
        events::emit_pool_paused(object::id(pool), paused, clock.timestamp_ms());
    }

    /// Emergency withdrawal of SUI from pool (admin only)
    /// Use only in emergency situations (e.g., critical bug, hack recovery)
    /// Pool must be paused first
    public fun emergency_withdraw_sui<T>(
        _admin: &AdminCap,
        pool: &mut BondingPool<T>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        assert!(pool.paused, EPoolPaused);
        assert!(balance::value(&pool.sui_balance) >= amount, EInsufficientPayment);

        let sui_coin = coin::from_balance(
            balance::split(&mut pool.sui_balance, amount),
            ctx
        );

        // Optionally transfer directly to recipient
        if (recipient != @0x0) {
            transfer::public_transfer(sui_coin, recipient);
            coin::zero(ctx)
        } else {
            sui_coin
        }
    }

    /// Emergency withdrawal of tokens from pool (admin only)
    /// Use only in emergency situations
    /// Pool must be paused first
    public fun emergency_withdraw_tokens<T>(
        _admin: &AdminCap,
        pool: &mut BondingPool<T>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(pool.paused, EPoolPaused);
        assert!(balance::value(&pool.token_balance) >= amount, EInsufficientTokens);

        let token_coin = coin::from_balance(
            balance::split(&mut pool.token_balance, amount),
            ctx
        );

        if (recipient != @0x0) {
            transfer::public_transfer(token_coin, recipient);
            coin::zero(ctx)
        } else {
            token_coin
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PACKAGE-LEVEL FUNCTIONS (for graduation module)
    // ═══════════════════════════════════════════════════════════════════════

    /// Mark pool as graduated (only callable by graduation module)
    public(package) fun set_graduated<T>(pool: &mut BondingPool<T>) {
        pool.graduated = true;
    }

    /// Extract SUI balance for graduation (only callable by graduation module)
    public(package) fun extract_sui_for_graduation<T>(
        pool: &mut BondingPool<T>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        coin::from_balance(balance::split(&mut pool.sui_balance, amount), ctx)
    }

    /// Extract tokens for graduation (only callable by graduation module)
    public(package) fun extract_tokens_for_graduation<T>(
        pool: &mut BondingPool<T>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        coin::from_balance(balance::split(&mut pool.token_balance, amount), ctx)
    }

    /// Check if pool is ready for graduation
    public fun check_graduation_ready<T>(pool: &BondingPool<T>, config: &LaunchpadConfig): bool {
        if (pool.graduated || pool.paused) {
            return false
        };

        let market_cap = get_market_cap(pool);
        let sui_raised = balance::value(&pool.sui_balance);

        market_cap >= config::graduation_threshold(config) &&
        sui_raised >= config::min_graduation_liquidity(config)
    }
}
