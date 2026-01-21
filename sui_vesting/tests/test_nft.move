/// Test NFT for unit tests (simulates CLMM position)
#[test_only]
module sui_vesting::test_nft {

    /// Test NFT representing a CLMM-like position
    public struct TestPosition has key, store {
        id: UID,
        /// Simulated pool ID
        pool_id: ID,
        /// Simulated liquidity amount
        liquidity: u64,
        /// Lower tick
        tick_lower: u64,
        /// Upper tick
        tick_upper: u64,
    }

    /// Create a test position NFT
    public fun create_position(
        liquidity: u64,
        ctx: &mut TxContext,
    ): TestPosition {
        TestPosition {
            id: object::new(ctx),
            pool_id: object::id_from_address(@0x123),
            liquidity,
            tick_lower: 100,
            tick_upper: 200,
        }
    }

    /// Create a position with custom ticks
    public fun create_position_with_ticks(
        liquidity: u64,
        tick_lower: u64,
        tick_upper: u64,
        ctx: &mut TxContext,
    ): TestPosition {
        TestPosition {
            id: object::new(ctx),
            pool_id: object::id_from_address(@0x123),
            liquidity,
            tick_lower,
            tick_upper,
        }
    }

    /// Get liquidity
    public fun liquidity(position: &TestPosition): u64 {
        position.liquidity
    }

    /// Get pool ID
    public fun pool_id(position: &TestPosition): ID {
        position.pool_id
    }

    /// Destroy position (for cleanup)
    public fun destroy(position: TestPosition) {
        let TestPosition { id, pool_id: _, liquidity: _, tick_lower: _, tick_upper: _ } = position;
        object::delete(id);
    }
}
