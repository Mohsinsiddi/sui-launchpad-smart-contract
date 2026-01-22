/// Test coins for staking unit tests
/// Provides STAKE and REWARD token types with minting utilities
#[test_only]
module sui_staking::test_coins {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::balance;

    // ═══════════════════════════════════════════════════════════════════════
    // STAKE TOKEN
    // ═══════════════════════════════════════════════════════════════════════

    /// Stake token type (the token users stake)
    public struct STAKE has drop {}

    /// Mint STAKE tokens for testing
    public fun mint_stake(amount: u64, ctx: &mut TxContext): Coin<STAKE> {
        let (mut treasury, metadata) = coin::create_currency(
            STAKE {},
            9, // 9 decimals like SUI
            b"STAKE",
            b"Stake Token",
            b"Token to stake for rewards",
            option::none(),
            ctx,
        );

        let coins = coin::mint(&mut treasury, amount, ctx);

        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, tx_context::sender(ctx));

        coins
    }

    /// Get STAKE treasury cap for complex tests
    public fun create_stake_treasury(ctx: &mut TxContext): TreasuryCap<STAKE> {
        let (treasury, metadata) = coin::create_currency(
            STAKE {},
            9,
            b"STAKE",
            b"Stake Token",
            b"Token to stake for rewards",
            option::none(),
            ctx,
        );

        transfer::public_freeze_object(metadata);
        treasury
    }

    /// Mint STAKE from balance (no treasury needed)
    public fun mint_stake_balance(amount: u64, ctx: &mut TxContext): Coin<STAKE> {
        coin::from_balance(
            balance::create_for_testing<STAKE>(amount),
            ctx,
        )
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REWARD TOKEN
    // ═══════════════════════════════════════════════════════════════════════

    /// Reward token type (the token users earn)
    public struct REWARD has drop {}

    /// Mint REWARD tokens for testing
    public fun mint_reward(amount: u64, ctx: &mut TxContext): Coin<REWARD> {
        let (mut treasury, metadata) = coin::create_currency(
            REWARD {},
            9, // 9 decimals like SUI
            b"REWARD",
            b"Reward Token",
            b"Token earned from staking",
            option::none(),
            ctx,
        );

        let coins = coin::mint(&mut treasury, amount, ctx);

        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, tx_context::sender(ctx));

        coins
    }

    /// Get REWARD treasury cap for complex tests
    public fun create_reward_treasury(ctx: &mut TxContext): TreasuryCap<REWARD> {
        let (treasury, metadata) = coin::create_currency(
            REWARD {},
            9,
            b"REWARD",
            b"Reward Token",
            b"Token earned from staking",
            option::none(),
            ctx,
        );

        transfer::public_freeze_object(metadata);
        treasury
    }

    /// Mint REWARD from balance (no treasury needed)
    public fun mint_reward_balance(amount: u64, ctx: &mut TxContext): Coin<REWARD> {
        coin::from_balance(
            balance::create_for_testing<REWARD>(amount),
            ctx,
        )
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ALTERNATIVE TOKEN (for multi-pool tests)
    // ═══════════════════════════════════════════════════════════════════════

    /// Alternative stake token
    public struct ALT_STAKE has drop {}

    /// Alternative reward token
    public struct ALT_REWARD has drop {}

    /// Mint ALT_STAKE tokens
    public fun mint_alt_stake(amount: u64, ctx: &mut TxContext): Coin<ALT_STAKE> {
        coin::from_balance(
            balance::create_for_testing<ALT_STAKE>(amount),
            ctx,
        )
    }

    /// Mint ALT_REWARD tokens
    public fun mint_alt_reward(amount: u64, ctx: &mut TxContext): Coin<ALT_REWARD> {
        coin::from_balance(
            balance::create_for_testing<ALT_REWARD>(amount),
            ctx,
        )
    }

    // ═══════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Burn coins (cleanup)
    public fun burn_stake(coin: Coin<STAKE>) {
        coin::burn_for_testing(coin);
    }

    /// Burn reward coins (cleanup)
    public fun burn_reward(coin: Coin<REWARD>) {
        coin::burn_for_testing(coin);
    }

    /// Get coin value
    public fun stake_value(coin: &Coin<STAKE>): u64 {
        coin::value(coin)
    }

    /// Get reward coin value
    public fun reward_value(coin: &Coin<REWARD>): u64 {
        coin::value(coin)
    }
}
