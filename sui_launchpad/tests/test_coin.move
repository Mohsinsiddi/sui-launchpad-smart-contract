/// Test coin module with proper OTW (one-time witness) for testing
/// The module name 'test_coin' matches the struct name 'TEST_COIN' (lowercase)
#[test_only]
#[allow(deprecated_usage)]
module sui_launchpad::test_coin {
    use sui::coin::{Self, TreasuryCap, CoinMetadata};

    /// One-time witness for test coin
    /// OTW requirements: uppercase name, drop ability, no fields, module name matches
    public struct TEST_COIN has drop {}

    /// Create test coin - can be called from any test
    /// Note: Using deprecated create_currency for test compatibility
    public fun create_test_coin(ctx: &mut TxContext): (TreasuryCap<TEST_COIN>, CoinMetadata<TEST_COIN>) {
        let (treasury_cap, metadata) = coin::create_currency(
            TEST_COIN {},
            9, // decimals
            b"TEST",
            b"Test Coin",
            b"A test coin for unit tests",
            option::none(),
            ctx,
        );
        (treasury_cap, metadata)
    }

    /// Get a fresh witness - for cases where you need the witness directly
    public fun get_witness(): TEST_COIN {
        TEST_COIN {}
    }

    /// Mint test coins directly for testing (simulates LP tokens, etc.)
    public fun mint(amount: u64, ctx: &mut TxContext): coin::Coin<TEST_COIN> {
        let (mut treasury_cap, metadata) = create_test_coin(ctx);
        let coins = coin::mint(&mut treasury_cap, amount, ctx);
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury_cap, ctx.sender());
        coins
    }
}
