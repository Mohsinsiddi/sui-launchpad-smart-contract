/// Test token types for multisig tests
#[test_only]
module sui_multisig::test_coins {
    use sui::coin::{Self, Coin};
    use sui::balance;

    /// Test token A (e.g., USDC-like stablecoin)
    public struct TEST_TOKEN_A has drop {}

    /// Test token B (e.g., wrapped ETH)
    public struct TEST_TOKEN_B has drop {}

    /// Test token C (e.g., governance token)
    public struct TEST_TOKEN_C has drop {}

    /// Mint test token A using balance (fast, no treasury)
    public fun mint_token_a(amount: u64, ctx: &mut TxContext): Coin<TEST_TOKEN_A> {
        coin::from_balance(balance::create_for_testing<TEST_TOKEN_A>(amount), ctx)
    }

    /// Mint test token B using balance (fast, no treasury)
    public fun mint_token_b(amount: u64, ctx: &mut TxContext): Coin<TEST_TOKEN_B> {
        coin::from_balance(balance::create_for_testing<TEST_TOKEN_B>(amount), ctx)
    }

    /// Mint test token C using balance (fast, no treasury)
    public fun mint_token_c(amount: u64, ctx: &mut TxContext): Coin<TEST_TOKEN_C> {
        coin::from_balance(balance::create_for_testing<TEST_TOKEN_C>(amount), ctx)
    }

    /// Burn test token A
    public fun burn_token_a(coin: Coin<TEST_TOKEN_A>) {
        coin::burn_for_testing(coin);
    }

    /// Burn test token B
    public fun burn_token_b(coin: Coin<TEST_TOKEN_B>) {
        coin::burn_for_testing(coin);
    }

    /// Burn test token C
    public fun burn_token_c(coin: Coin<TEST_TOKEN_C>) {
        coin::burn_for_testing(coin);
    }
}
