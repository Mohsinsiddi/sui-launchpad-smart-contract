/// Mock Cetus CLMM structures for testing
/// These simulate Cetus Position NFTs without requiring the actual dependency
#[test_only]
module sui_launchpad::mock_cetus {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;

    // ═══════════════════════════════════════════════════════════════════════
    // MOCK POSITION NFT
    // ═══════════════════════════════════════════════════════════════════════

    /// Mock Cetus Position NFT
    /// Represents a concentrated liquidity position in a CLMM pool
    public struct MockPosition has key, store {
        id: UID,
        /// Pool this position belongs to
        pool_id: ID,
        /// Lower tick bound (price range)
        tick_lower: u32,
        /// Upper tick bound (price range)
        tick_upper: u32,
        /// Liquidity amount in this position
        liquidity: u128,
        /// Accumulated fees for token A
        fee_growth_inside_a: u128,
        /// Accumulated fees for token B
        fee_growth_inside_b: u128,
        /// Unclaimed fees token A
        tokens_owed_a: u64,
        /// Unclaimed fees token B
        tokens_owed_b: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MOCK POOL
    // ═══════════════════════════════════════════════════════════════════════

    /// Mock Cetus Pool
    public struct MockPool<phantom A, phantom B> has key, store {
        id: UID,
        /// Current sqrt price
        sqrt_price: u128,
        /// Current tick
        tick_current: u32,
        /// Total liquidity
        liquidity: u128,
        /// Fee rate in basis points
        fee_rate: u64,
        /// Balance of token A
        balance_a: Balance<A>,
        /// Balance of token B
        balance_b: Balance<B>,
    }

    /// Mock Cetus Global Config
    public struct MockGlobalConfig has key, store {
        id: UID,
        /// Protocol fee rate
        protocol_fee_rate: u64,
        /// Whether pool creation is enabled
        pool_creation_enabled: bool,
    }

    /// Mock Cetus Pools registry
    public struct MockPools has key, store {
        id: UID,
        /// Number of pools created
        pool_count: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Full range tick lower (near minimum)
    const FULL_RANGE_TICK_LOWER: u32 = 0;

    /// Full range tick upper (near maximum)
    const FULL_RANGE_TICK_UPPER: u32 = 887220;

    /// Default tick spacing (0.3% fee tier)
    const DEFAULT_TICK_SPACING: u32 = 60;

    /// sqrt(1) * 2^64 = 1 << 64
    const SQRT_PRICE_1_TO_1: u128 = 18446744073709551616;

    /// Precision for liquidity calculations
    const LIQUIDITY_PRECISION: u128 = 1_000_000_000_000;

    // ═══════════════════════════════════════════════════════════════════════
    // MOCK CONFIG CREATION
    // ═══════════════════════════════════════════════════════════════════════

    public fun create_mock_global_config(ctx: &mut TxContext): MockGlobalConfig {
        MockGlobalConfig {
            id: object::new(ctx),
            protocol_fee_rate: 2000, // 20%
            pool_creation_enabled: true,
        }
    }

    public fun create_mock_pools(ctx: &mut TxContext): MockPools {
        MockPools {
            id: object::new(ctx),
            pool_count: 0,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MOCK POOL CREATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a mock pool and initial position (simulates create_pool_v3)
    public fun create_pool_v3<A, B>(
        _config: &MockGlobalConfig,
        pools: &mut MockPools,
        _tick_spacing: u32,
        sqrt_price: u128,
        _url: vector<u8>,
        tick_lower: u32,
        tick_upper: u32,
        coin_a: Coin<A>,
        coin_b: Coin<B>,
        _fix_amount_a: bool,
        ctx: &mut TxContext,
    ): (MockPool<A, B>, MockPosition, Coin<A>, Coin<B>) {
        let amount_a = coin::value(&coin_a);
        let amount_b = coin::value(&coin_b);

        // Calculate liquidity from amounts
        let liquidity = calculate_liquidity(amount_a, amount_b);

        // Create pool
        let pool = MockPool<A, B> {
            id: object::new(ctx),
            sqrt_price,
            tick_current: (tick_lower + tick_upper) / 2,
            liquidity,
            fee_rate: 3000, // 0.3%
            balance_a: coin::into_balance(coin_a),
            balance_b: coin::into_balance(coin_b),
        };

        let pool_id = object::id(&pool);

        // Create position
        let position = MockPosition {
            id: object::new(ctx),
            pool_id,
            tick_lower,
            tick_upper,
            liquidity,
            fee_growth_inside_a: 0,
            fee_growth_inside_b: 0,
            tokens_owed_a: 0,
            tokens_owed_b: 0,
        };

        pools.pool_count = pools.pool_count + 1;

        // Return empty remaining coins (all used)
        let remaining_a = coin::zero<A>(ctx);
        let remaining_b = coin::zero<B>(ctx);

        (pool, position, remaining_a, remaining_b)
    }

    /// Open a new position in an existing pool
    public fun open_position<A, B>(
        _config: &MockGlobalConfig,
        pool: &MockPool<A, B>,
        tick_lower: u32,
        tick_upper: u32,
        ctx: &mut TxContext,
    ): MockPosition {
        MockPosition {
            id: object::new(ctx),
            pool_id: object::id(pool),
            tick_lower,
            tick_upper,
            liquidity: 0,
            fee_growth_inside_a: 0,
            fee_growth_inside_b: 0,
            tokens_owed_a: 0,
            tokens_owed_b: 0,
        }
    }

    /// Add liquidity to a position
    public fun add_liquidity<A, B>(
        _config: &MockGlobalConfig,
        pool: &mut MockPool<A, B>,
        position: &mut MockPosition,
        coin_a: Coin<A>,
        coin_b: Coin<B>,
        ctx: &mut TxContext,
    ): (Coin<A>, Coin<B>) {
        let amount_a = coin::value(&coin_a);
        let amount_b = coin::value(&coin_b);

        // Calculate liquidity from amounts
        let liquidity = calculate_liquidity(amount_a, amount_b);

        // Add to position
        position.liquidity = position.liquidity + liquidity;

        // Add to pool
        pool.liquidity = pool.liquidity + liquidity;
        balance::join(&mut pool.balance_a, coin::into_balance(coin_a));
        balance::join(&mut pool.balance_b, coin::into_balance(coin_b));

        // Return empty coins
        (coin::zero<A>(ctx), coin::zero<B>(ctx))
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Calculate liquidity from token amounts (simplified)
    fun calculate_liquidity(amount_a: u64, amount_b: u64): u128 {
        // Simplified: liquidity = sqrt(amount_a * amount_b)
        // Using geometric mean approximation
        let product = (amount_a as u128) * (amount_b as u128);
        sqrt_u128(product)
    }

    /// Integer square root for u128
    fun sqrt_u128(x: u128): u128 {
        if (x == 0) return 0;

        let mut z = (x + 1) / 2;
        let mut y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        };

        y
    }

    /// Get full range tick bounds
    public fun full_range_tick_lower(): u32 { FULL_RANGE_TICK_LOWER }
    public fun full_range_tick_upper(): u32 { FULL_RANGE_TICK_UPPER }
    public fun default_tick_spacing(): u32 { DEFAULT_TICK_SPACING }
    public fun sqrt_price_1_to_1(): u128 { SQRT_PRICE_1_TO_1 }

    // ═══════════════════════════════════════════════════════════════════════
    // POSITION GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun position_id(position: &MockPosition): ID {
        object::id(position)
    }

    public fun position_pool_id(position: &MockPosition): ID {
        position.pool_id
    }

    public fun position_liquidity(position: &MockPosition): u128 {
        position.liquidity
    }

    public fun position_tick_lower(position: &MockPosition): u32 {
        position.tick_lower
    }

    public fun position_tick_upper(position: &MockPosition): u32 {
        position.tick_upper
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POOL GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun pool_id<A, B>(pool: &MockPool<A, B>): ID {
        object::id(pool)
    }

    public fun pool_liquidity<A, B>(pool: &MockPool<A, B>): u128 {
        pool.liquidity
    }

    public fun pool_sqrt_price<A, B>(pool: &MockPool<A, B>): u128 {
        pool.sqrt_price
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLEANUP
    // ═══════════════════════════════════════════════════════════════════════

    public fun destroy_position(position: MockPosition) {
        let MockPosition {
            id,
            pool_id: _,
            tick_lower: _,
            tick_upper: _,
            liquidity: _,
            fee_growth_inside_a: _,
            fee_growth_inside_b: _,
            tokens_owed_a: _,
            tokens_owed_b: _,
        } = position;
        object::delete(id);
    }

    public fun destroy_pool<A, B>(pool: MockPool<A, B>) {
        let MockPool {
            id,
            sqrt_price: _,
            tick_current: _,
            liquidity: _,
            fee_rate: _,
            balance_a,
            balance_b,
        } = pool;
        object::delete(id);
        balance::destroy_for_testing(balance_a);
        balance::destroy_for_testing(balance_b);
    }

    public fun destroy_global_config(config: MockGlobalConfig) {
        let MockGlobalConfig { id, protocol_fee_rate: _, pool_creation_enabled: _ } = config;
        object::delete(id);
    }

    public fun destroy_pools(pools: MockPools) {
        let MockPools { id, pool_count: _ } = pools;
        object::delete(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_pool_and_position() {
        let mut ctx = tx_context::dummy();

        let config = create_mock_global_config(&mut ctx);
        let mut pools = create_mock_pools(&mut ctx);

        let coin_a = coin::mint_for_testing<SUI>(1_000_000_000, &mut ctx);
        let coin_b = coin::mint_for_testing<SUI>(1_000_000_000, &mut ctx);

        let (pool, position, remaining_a, remaining_b) = create_pool_v3<SUI, SUI>(
            &config,
            &mut pools,
            60,
            SQRT_PRICE_1_TO_1,
            b"test",
            0,
            887220,
            coin_a,
            coin_b,
            true,
            &mut ctx,
        );

        // Verify position has liquidity
        assert!(position_liquidity(&position) > 0, 0);

        // Verify pool ID matches
        assert!(position_pool_id(&position) == pool_id(&pool), 1);

        // Cleanup
        coin::destroy_zero(remaining_a);
        coin::destroy_zero(remaining_b);
        destroy_position(position);
        destroy_pool(pool);
        destroy_global_config(config);
        destroy_pools(pools);
    }

    #[test]
    fun test_open_position_and_add_liquidity() {
        let mut ctx = tx_context::dummy();

        let config = create_mock_global_config(&mut ctx);
        let mut pools = create_mock_pools(&mut ctx);

        // Create initial pool
        let coin_a = coin::mint_for_testing<SUI>(1_000_000_000, &mut ctx);
        let coin_b = coin::mint_for_testing<SUI>(1_000_000_000, &mut ctx);

        let (mut pool, initial_position, remaining_a, remaining_b) = create_pool_v3<SUI, SUI>(
            &config,
            &mut pools,
            60,
            SQRT_PRICE_1_TO_1,
            b"test",
            0,
            887220,
            coin_a,
            coin_b,
            true,
            &mut ctx,
        );

        coin::destroy_zero(remaining_a);
        coin::destroy_zero(remaining_b);

        // Open new position
        let mut new_position = open_position<SUI, SUI>(
            &config,
            &pool,
            0,
            887220,
            &mut ctx,
        );

        // Initially no liquidity
        assert!(position_liquidity(&new_position) == 0, 0);

        // Add liquidity
        let add_coin_a = coin::mint_for_testing<SUI>(500_000_000, &mut ctx);
        let add_coin_b = coin::mint_for_testing<SUI>(500_000_000, &mut ctx);

        let (rem_a, rem_b) = add_liquidity<SUI, SUI>(
            &config,
            &mut pool,
            &mut new_position,
            add_coin_a,
            add_coin_b,
            &mut ctx,
        );

        // Now has liquidity
        assert!(position_liquidity(&new_position) > 0, 1);

        // Cleanup
        coin::destroy_zero(rem_a);
        coin::destroy_zero(rem_b);
        destroy_position(initial_position);
        destroy_position(new_position);
        destroy_pool(pool);
        destroy_global_config(config);
        destroy_pools(pools);
    }

    #[test]
    fun test_multiple_positions_different_liquidity() {
        let mut ctx = tx_context::dummy();

        let config = create_mock_global_config(&mut ctx);
        let mut pools = create_mock_pools(&mut ctx);

        // Create pool with initial position (95% liquidity - DAO)
        let dao_coin_a = coin::mint_for_testing<SUI>(9_500_000_000, &mut ctx);
        let dao_coin_b = coin::mint_for_testing<SUI>(9_500_000_000, &mut ctx);

        let (mut pool, dao_position, rem_a, rem_b) = create_pool_v3<SUI, SUI>(
            &config,
            &mut pools,
            60,
            SQRT_PRICE_1_TO_1,
            b"test",
            0,
            887220,
            dao_coin_a,
            dao_coin_b,
            true,
            &mut ctx,
        );

        coin::destroy_zero(rem_a);
        coin::destroy_zero(rem_b);

        let dao_liquidity = position_liquidity(&dao_position);

        // Create creator position (2.5%)
        let mut creator_position = open_position<SUI, SUI>(&config, &pool, 0, 887220, &mut ctx);
        let creator_coin_a = coin::mint_for_testing<SUI>(250_000_000, &mut ctx);
        let creator_coin_b = coin::mint_for_testing<SUI>(250_000_000, &mut ctx);
        let (rem_a, rem_b) = add_liquidity(&config, &mut pool, &mut creator_position, creator_coin_a, creator_coin_b, &mut ctx);
        coin::destroy_zero(rem_a);
        coin::destroy_zero(rem_b);

        let creator_liquidity = position_liquidity(&creator_position);

        // Create protocol position (2.5%)
        let mut protocol_position = open_position<SUI, SUI>(&config, &pool, 0, 887220, &mut ctx);
        let protocol_coin_a = coin::mint_for_testing<SUI>(250_000_000, &mut ctx);
        let protocol_coin_b = coin::mint_for_testing<SUI>(250_000_000, &mut ctx);
        let (rem_a, rem_b) = add_liquidity(&config, &mut pool, &mut protocol_position, protocol_coin_a, protocol_coin_b, &mut ctx);
        coin::destroy_zero(rem_a);
        coin::destroy_zero(rem_b);

        let protocol_liquidity = position_liquidity(&protocol_position);

        // Verify ratios (DAO should have ~38x more liquidity than creator/protocol)
        // Due to sqrt relationship, 95% vs 2.5% = 38x in amounts means sqrt(38) ~ 6.2x in liquidity
        assert!(dao_liquidity > creator_liquidity, 0);
        assert!(dao_liquidity > protocol_liquidity, 1);
        assert!(creator_liquidity == protocol_liquidity, 2); // Same amounts

        // Cleanup
        destroy_position(dao_position);
        destroy_position(creator_position);
        destroy_position(protocol_position);
        destroy_pool(pool);
        destroy_global_config(config);
        destroy_pools(pools);
    }
}
