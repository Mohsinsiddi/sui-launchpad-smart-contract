/// Test coin for unit tests
#[test_only]
module sui_vesting::test_coin {
    use sui::coin::{Self, Coin, TreasuryCap};

    /// Test coin type
    public struct TEST_COIN has drop {}

    /// Mint test tokens for testing
    public fun mint(amount: u64, ctx: &mut TxContext): Coin<TEST_COIN> {
        let (mut treasury, metadata) = coin::create_currency(
            TEST_COIN {},
            9,
            b"TEST",
            b"Test Coin",
            b"Test coin for vesting tests",
            option::none(),
            ctx,
        );

        let coins = coin::mint(&mut treasury, amount, ctx);

        // Clean up
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, tx_context::sender(ctx));

        coins
    }

    /// Get treasury cap for more complex tests
    public fun create_treasury(ctx: &mut TxContext): TreasuryCap<TEST_COIN> {
        let (treasury, metadata) = coin::create_currency(
            TEST_COIN {},
            9,
            b"TEST",
            b"Test Coin",
            b"Test coin for vesting tests",
            option::none(),
            ctx,
        );

        transfer::public_freeze_object(metadata);
        treasury
    }
}
