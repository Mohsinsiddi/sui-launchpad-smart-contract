/// All launchpad events in one place for easy indexing
module sui_launchpad::events {

    use std::string::String;
    use std::ascii;
    use std::type_name::TypeName;

    // ═══════════════════════════════════════════════════════════════════════
    // TOKEN LIFECYCLE EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emitted when a new token is created and registered
    public struct TokenCreated has copy, drop {
        pool_id: ID,
        token_type: TypeName,
        creator: address,
        name: String,
        symbol: ascii::String,
        total_supply: u64,
        creation_fee_paid: u64,
        timestamp: u64,
    }

    /// Emitted on every buy/sell trade
    public struct Trade has copy, drop {
        pool_id: ID,
        token_type: TypeName,
        trader: address,
        is_buy: bool,
        sui_amount: u64,
        token_amount: u64,
        price_after: u64,
        platform_fee: u64,
        creator_fee: u64,
        new_supply: u64,
        timestamp: u64,
    }

    /// Emitted when token graduates to DEX
    public struct TokenGraduated has copy, drop {
        pool_id: ID,
        token_type: TypeName,
        dex_type: u8,
        dex_pool_id: ID,
        final_price: u64,
        total_sui_raised: u64,
        sui_to_liquidity: u64,
        tokens_to_liquidity: u64,
        graduation_fee: u64,
        platform_tokens: u64,
        timestamp: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POOL EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emitted when a pool is paused/unpaused
    public struct PoolPaused has copy, drop {
        pool_id: ID,
        paused: bool,
        timestamp: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VESTING EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emitted when LP vesting schedule is created
    public struct VestingCreated has copy, drop {
        vesting_id: ID,
        pool_id: ID,
        beneficiary: address,
        total_amount: u64,
        start_time: u64,
        cliff_duration: u64,
        vesting_duration: u64,
        timestamp: u64,
    }

    /// Emitted when vested tokens are claimed
    public struct VestingClaimed has copy, drop {
        vesting_id: ID,
        beneficiary: address,
        amount_claimed: u64,
        total_claimed: u64,
        remaining: u64,
        timestamp: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FEE EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Emitted when fees are withdrawn to treasury
    public struct FeesWithdrawn has copy, drop {
        amount: u64,
        treasury: address,
        timestamp: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMIT HELPERS (called by other modules)
    // ═══════════════════════════════════════════════════════════════════════

    public fun emit_token_created(
        pool_id: ID,
        token_type: TypeName,
        creator: address,
        name: String,
        symbol: ascii::String,
        total_supply: u64,
        creation_fee_paid: u64,
        timestamp: u64,
    ) {
        sui::event::emit(TokenCreated {
            pool_id,
            token_type,
            creator,
            name,
            symbol,
            total_supply,
            creation_fee_paid,
            timestamp,
        });
    }

    public fun emit_trade(
        pool_id: ID,
        token_type: TypeName,
        trader: address,
        is_buy: bool,
        sui_amount: u64,
        token_amount: u64,
        price_after: u64,
        platform_fee: u64,
        creator_fee: u64,
        new_supply: u64,
        timestamp: u64,
    ) {
        sui::event::emit(Trade {
            pool_id,
            token_type,
            trader,
            is_buy,
            sui_amount,
            token_amount,
            price_after,
            platform_fee,
            creator_fee,
            new_supply,
            timestamp,
        });
    }

    public fun emit_token_graduated(
        pool_id: ID,
        token_type: TypeName,
        dex_type: u8,
        dex_pool_id: ID,
        final_price: u64,
        total_sui_raised: u64,
        sui_to_liquidity: u64,
        tokens_to_liquidity: u64,
        graduation_fee: u64,
        platform_tokens: u64,
        timestamp: u64,
    ) {
        sui::event::emit(TokenGraduated {
            pool_id,
            token_type,
            dex_type,
            dex_pool_id,
            final_price,
            total_sui_raised,
            sui_to_liquidity,
            tokens_to_liquidity,
            graduation_fee,
            platform_tokens,
            timestamp,
        });
    }

    public fun emit_pool_paused(
        pool_id: ID,
        paused: bool,
        timestamp: u64,
    ) {
        sui::event::emit(PoolPaused {
            pool_id,
            paused,
            timestamp,
        });
    }

    public fun emit_vesting_created(
        vesting_id: ID,
        pool_id: ID,
        beneficiary: address,
        total_amount: u64,
        start_time: u64,
        cliff_duration: u64,
        vesting_duration: u64,
        timestamp: u64,
    ) {
        sui::event::emit(VestingCreated {
            vesting_id,
            pool_id,
            beneficiary,
            total_amount,
            start_time,
            cliff_duration,
            vesting_duration,
            timestamp,
        });
    }

    public fun emit_vesting_claimed(
        vesting_id: ID,
        beneficiary: address,
        amount_claimed: u64,
        total_claimed: u64,
        remaining: u64,
        timestamp: u64,
    ) {
        sui::event::emit(VestingClaimed {
            vesting_id,
            beneficiary,
            amount_claimed,
            total_claimed,
            remaining,
            timestamp,
        });
    }

    public fun emit_fees_withdrawn(
        amount: u64,
        treasury: address,
        timestamp: u64,
    ) {
        sui::event::emit(FeesWithdrawn {
            amount,
            treasury,
            timestamp,
        });
    }
}
