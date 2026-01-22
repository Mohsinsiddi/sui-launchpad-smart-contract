# Test Patterns Guide

This document describes the testing patterns and conventions used across all packages in the DeFi suite.

## Table of Contents

1. [Test File Structure](#test-file-structure)
2. [Test Token Helpers](#test-token-helpers)
3. [Test Categories](#test-categories)
4. [Naming Conventions](#naming-conventions)
5. [Test Scenario Patterns](#test-scenario-patterns)
6. [Fairness & Invariant Tests](#fairness--invariant-tests)
7. [Running Tests](#running-tests)

---

## Test File Structure

Each package follows this test directory structure:

```
package_name/
├── sources/
│   └── ... (production code)
└── tests/
    ├── test_coins.move      # Test token types (STAKE, REWARD, etc.)
    ├── test_nft.move        # Test NFT types (if needed)
    ├── module_tests.move    # Unit tests per module
    ├── math_tests.move      # Mathematical precision tests
    ├── fairness_tests.move  # Invariant/fairness verification
    └── integration_tests.move # Full flow tests
```

### Example: sui_staking

```
sui_staking/tests/
├── test_coins.move      # STAKE, REWARD, ALT_STAKE, ALT_REWARD
├── staking_tests.move   # Integration tests (14 tests)
├── math_tests.move      # Precision tests (39 tests)
└── fairness_tests.move  # Invariant tests (20 tests)
```

### Example: sui_vesting

```
sui_vesting/tests/
├── test_coin.move         # TEST_COIN
├── test_nft.move          # TestPosition (CLMM-like)
├── vesting_tests.move     # Coin vesting tests (32 tests)
└── nft_vesting_tests.move # NFT vesting tests (19 tests)
```

---

## Test Token Helpers

### Pattern: Dedicated Test Token Module

Each package has a `test_coins.move` (or `test_coin.move`) file that provides:

```move
#[test_only]
module package_name::test_coins {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::balance;

    /// Token type definition
    public struct TOKEN_NAME has drop {}

    /// Mint tokens (creates treasury, freezes metadata)
    public fun mint_token_name(amount: u64, ctx: &mut TxContext): Coin<TOKEN_NAME> {
        let (mut treasury, metadata) = coin::create_currency(
            TOKEN_NAME {},
            9, // decimals
            b"SYMBOL",
            b"Name",
            b"Description",
            option::none(),
            ctx,
        );
        let coins = coin::mint(&mut treasury, amount, ctx);
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, tx_context::sender(ctx));
        coins
    }

    /// Quick mint from balance (no treasury overhead)
    public fun mint_token_balance(amount: u64, ctx: &mut TxContext): Coin<TOKEN_NAME> {
        coin::from_balance(balance::create_for_testing<TOKEN_NAME>(amount), ctx)
    }

    /// Burn for cleanup
    public fun burn_token(coin: Coin<TOKEN_NAME>) {
        coin::burn_for_testing(coin);
    }
}
```

### Best Practices

1. **Use `balance::create_for_testing`** for simple tests (faster, no treasury)
2. **Use `coin::create_currency`** when testing treasury-dependent logic
3. **Always clean up** - burn coins or transfer to test addresses
4. **Define multiple token types** for multi-token scenarios (STAKE, REWARD, ALT_STAKE)

---

## Test Categories

### 1. Unit Tests

Test individual functions in isolation.

```move
#[test]
fun test_calculate_fee_bps() {
    let fee = math::calculate_fee_bps(1000, 500); // 5%
    assert!(fee == 50, 0);
}
```

### 2. Integration Tests

Test complete user flows with multiple modules.

```move
#[test]
fun test_stake_and_claim_rewards() {
    let mut scenario = ts::begin(ADMIN);
    // Create pool
    // User stakes
    // Time passes
    // User claims
    // Verify balances
    ts::end(scenario);
}
```

### 3. Math Precision Tests

Verify mathematical calculations maintain precision.

```move
#[test]
fun test_reward_rate_high_precision() {
    let total_rewards = 1_000_000_000_000u64;
    let duration = MS_PER_DAY;
    let rate = math::calculate_reward_rate(total_rewards, duration);
    let distributed = rate * duration;
    // Verify within tolerance
    let diff = if (distributed > total_rewards) {...} else {...};
    assert!(diff <= total_rewards / 1000, 0); // 0.1% tolerance
}
```

### 4. Fairness/Invariant Tests

Verify mathematical invariants hold under all conditions.

```move
#[test]
fun test_invariant_reward_conservation() {
    // Sum of user rewards must equal total rewards
    let alice_rewards = ...;
    let bob_rewards = ...;
    assert!(alice_rewards + bob_rewards == total_rewards, 0);
}
```

### 5. Edge Case Tests

Test boundary conditions and error handling.

```move
#[test]
#[expected_failure(abort_code = 100)]
fun test_cannot_stake_when_paused() {
    // Setup paused pool
    // Attempt stake - should fail
}
```

---

## Naming Conventions

### Test Functions

```
test_<action>_<condition>_<expected_result>
```

Examples:
- `test_stake_and_receive_position`
- `test_cannot_stake_when_paused`
- `test_claim_rewards_after_full_duration`
- `test_invariant_reward_conservation`

### Test Categories by Prefix

| Prefix | Category | Purpose |
|--------|----------|---------|
| `test_` | Standard | Basic functionality |
| `test_cannot_` | Negative | Should fail/abort |
| `test_invariant_` | Invariant | Mathematical properties |
| `test_scenario_` | Scenario | Complex multi-step |
| `test_edge_` | Edge case | Boundary conditions |

### Constants

```move
// Addresses
const ADMIN: address = @0xAD;
const ALICE: address = @0xA;
const BOB: address = @0xB;
const CHARLIE: address = @0xC;

// Time
const MS_PER_DAY: u64 = 86_400_000;
const MS_PER_WEEK: u64 = 604_800_000;

// Precision
const PRECISION: u128 = 1_000_000_000_000_000_000; // 1e18
```

---

## Test Scenario Patterns

### Pattern: Test Scenario Setup

```move
#[test]
fun test_complete_staking_flow() {
    // 1. SETUP
    let mut scenario = ts::begin(ADMIN);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // 2. CREATE POOL
    ts::next_tx(&mut scenario, ADMIN);
    {
        let reward_coins = mint_reward(100_000_000_000, ts::ctx(&mut scenario));
        let (pool, admin_cap) = pool::create<STAKE, REWARD>(...);
        transfer::public_share_object(pool);
        transfer::public_transfer(admin_cap, ADMIN);
    };

    // 3. USER ACTION
    clock::set_for_testing(&mut clock, 1000);
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut pool = ts::take_shared<StakingPool<STAKE, REWARD>>(&scenario);
        let stake_coins = mint_stake(10_000_000, ts::ctx(&mut scenario));
        let position = pool::stake(&mut pool, stake_coins, &clock, ts::ctx(&mut scenario));
        ts::return_shared(pool);
        transfer::public_transfer(position, ALICE);
    };

    // 4. VERIFY
    ts::next_tx(&mut scenario, ALICE);
    {
        let position = ts::take_from_sender<StakingPosition<STAKE>>(&scenario);
        assert!(position::staked_amount(&position) == 10_000_000, 0);
        ts::return_to_sender(&scenario, position);
    };

    // 5. CLEANUP
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
```

### Pattern: Multi-User Scenario

```move
#[test]
fun test_multiple_stakers() {
    // Setup...

    // Alice stakes 60%
    ts::next_tx(&mut scenario, ALICE);
    { /* stake 600,000 */ };

    // Bob stakes 40%
    ts::next_tx(&mut scenario, BOB);
    { /* stake 400,000 */ };

    // Time passes, rewards accumulate

    // Verify proportional rewards
    // Alice should get 60% of rewards
    // Bob should get 40% of rewards
}
```

### Pattern: Time-Based Testing

```move
#[test]
fun test_rewards_over_time() {
    // Setup pool starting at t=1000

    // Stake at t=1000
    clock::set_for_testing(&mut clock, 1000);
    // ... stake

    // Check at t=1000 + 1 day
    clock::set_for_testing(&mut clock, 1000 + MS_PER_DAY);
    // ... verify 1 day of rewards

    // Check at t=1000 + 7 days
    clock::set_for_testing(&mut clock, 1000 + MS_PER_WEEK);
    // ... verify 7 days of rewards
}
```

---

## Fairness & Invariant Tests

### Core Invariants to Test

#### 1. Reward Conservation
```move
#[test]
fun test_invariant_reward_conservation() {
    // Setup rewards distribution
    // Calculate each user's rewards
    // ASSERT: sum(user_rewards) == total_rewards
}
```

#### 2. Proportionality
```move
#[test]
fun test_invariant_proportional_rewards() {
    // Alice stakes 75%, Bob stakes 25%
    // ASSERT: alice_rewards == 3 * bob_rewards
}
```

#### 3. No Retroactive Rewards
```move
#[test]
fun test_invariant_no_retroactive_rewards() {
    // Period 1: Only Alice staked
    // Period 2: Bob joins
    // ASSERT: Bob only gets Period 2 rewards (reward_debt works)
}
```

#### 4. Debt Updates Correctly
```move
#[test]
fun test_invariant_debt_prevents_double_claim() {
    // User claims
    // ASSERT: Claiming again immediately gives 0
}
```

#### 5. Fee Bounds
```move
#[test]
fun test_invariant_fee_never_exceeds_amount() {
    // For any valid bps
    // ASSERT: fee <= amount
}
```

### Invariant Test Template

```move
#[test]
fun test_invariant_<property_name>() {
    // SETUP: Create conditions

    // ACTION: Perform operations

    // INVARIANT: Assert mathematical property
    assert!(<invariant_expression>, <error_code>);
}
```

---

## Running Tests

### Run All Tests

```bash
sui move test
```

### Run Specific Package

```bash
cd sui_staking && sui move test
```

### Run with Filter

```bash
sui move test fairness
```

### Run with Coverage

```bash
sui move test --coverage
```

### Expected Output

```
Running Move unit tests
[ PASS    ] package::module::test_name
...
Test result: OK. Total tests: 86; passed: 86; failed: 0
```

---

## Summary: Test Counts by Package

| Package | Unit | Integration | Math | Fairness | Total |
|---------|------|-------------|------|----------|-------|
| Launchpad | 138 | - | - | - | 138 |
| Vesting | 51 | - | - | - | 51 |
| Staking | 13 | 20 | 39 | 20 | 92 |
| **Total** | 202 | 20 | 39 | 20 | **281** |

---

## Best Practices Checklist

- [ ] Create dedicated test token modules
- [ ] Use `#[test_only]` for all test modules
- [ ] Follow naming conventions
- [ ] Test all error conditions with `#[expected_failure]`
- [ ] Verify mathematical invariants
- [ ] Test with realistic token amounts (9 decimals)
- [ ] Clean up all objects in tests
- [ ] Use `clock` for time-dependent tests
- [ ] Document complex test scenarios
