# Vesting Package Test Documentation

**Total Tests: 51**
**Status: All Passing**

---

## Test Structure

```
sui_vesting/tests/
├── test_coin.move         # Test coin helper for fungible tests
├── test_nft.move          # Test NFT helper for position tests
├── vesting_tests.move     # Coin vesting tests (32 tests)
└── nft_vesting_tests.move # NFT vesting tests (19 tests)
```

---

## Coin Vesting Tests (32 tests)

### Schedule Creation Tests (5 tests)

| Test | Description | Expected Behavior |
|------|-------------|-------------------|
| `test_create_schedule_basic` | Create schedule with custom parameters | Schedule created with correct cliff, vesting, revocable flag |
| `test_create_schedule_months` | Create schedule using months helper | Cliff/vesting converted to milliseconds correctly |
| `test_create_instant_schedule` | Create instant unlock schedule | No cliff, no vesting, immediately claimable |
| `test_create_schedule_zero_beneficiary_fails` | Attempt with zero address | Fails with `EInvalidBeneficiary` |
| `test_create_schedule_zero_amount_fails` | Attempt with zero tokens | Fails with `EZeroAmount` |

### Claiming Tests (6 tests)

| Test | Description | Expected Behavior |
|------|-------------|-------------------|
| `test_claim_instant_unlock` | Claim from instant schedule | Full amount claimed immediately |
| `test_claimable_during_cliff` | Check claimable during cliff | Returns 0 at all points during cliff |
| `test_linear_vesting_calculations` | Verify vesting math | Correct amounts at 0%, 50%, 100% vesting |
| `test_multiple_claims` | Claim at multiple time points | Each claim receives correct incremental amount |
| `test_claim_non_beneficiary_fails` | Non-beneficiary attempts claim | Fails with `ENotBeneficiary` |
| `test_claim_nothing_claimable_fails` | Claim when nothing vested | Fails with `ENotClaimable` |

### Revocation Tests (6 tests)

| Test | Description | Expected Behavior |
|------|-------------|-------------------|
| `test_revoke_before_vesting` | Revoke during cliff period | All tokens returned to creator |
| `test_revoke_after_partial_vesting` | Revoke after 50% vested | Creator gets 50%, beneficiary keeps 50% |
| `test_claim_after_revoke` | Beneficiary situation after revoke | Vested portion remains for beneficiary |
| `test_revoke_non_revocable_fails` | Revoke non-revocable schedule | Fails with `ENotRevocable` |
| `test_revoke_wrong_cap_fails` | Use wrong CreatorCap | Fails with `ECreatorCapMismatch` |
| `test_double_revoke_fails` | Attempt second revocation | Fails with `EAlreadyRevoked` |

### Admin Tests (4 tests)

| Test | Description | Expected Behavior |
|------|-------------|-------------------|
| `test_platform_pause` | Admin pauses platform | Config paused flag set to true |
| `test_paused_platform_rejects_schedules` | Create schedule on paused platform | Fails with `ESchedulePaused` |
| `test_schedule_pause` | Admin pauses specific schedule | Schedule paused, claimable returns 0 |
| `test_paused_schedule_rejects_claims` | Claim from paused schedule | Fails with `ESchedulePaused` |

### Edge Case Tests (11 tests)

| Test | Description | Expected Behavior |
|------|-------------|-------------------|
| `test_cliff_only_schedule` | Schedule with cliff but no linear vesting | Instant unlock after cliff ends |
| `test_before_start_time` | Query before vesting starts | Nothing claimable |
| `test_large_amounts_no_overflow` | 1 trillion tokens vested | u128 intermediate prevents overflow |
| `test_delete_empty_schedule` | Delete after full claim | Schedule object deleted successfully |
| `test_delete_non_empty_schedule_fails` | Delete with remaining balance | Fails with `EScheduleEmpty` |
| `test_time_constants` | Verify time constants | MS_PER_DAY, MS_PER_MONTH, MS_PER_YEAR correct |

---

## NFT Vesting Tests (19 tests)

### Schedule Creation Tests (4 tests)

| Test | Description | Expected Behavior |
|------|-------------|-------------------|
| `test_create_nft_schedule_basic` | Create NFT schedule with cliff | Schedule created, NFT locked |
| `test_create_nft_schedule_months` | Create using months helper | Cliff converted to milliseconds |
| `test_create_instant_nft_schedule` | Create instant unlock schedule | No cliff, immediately claimable |
| `test_create_nft_schedule_zero_beneficiary_fails` | Attempt with zero address | Fails with `EInvalidBeneficiary` |

### Claiming Tests (6 tests)

| Test | Description | Expected Behavior |
|------|-------------|-------------------|
| `test_claim_nft_instant_unlock` | Claim from instant schedule | NFT returned immediately |
| `test_nft_not_claimable_during_cliff` | Check claimable during cliff | `is_claimable` returns false |
| `test_nft_claimable_after_cliff` | Check and claim after cliff | NFT claimable, claim succeeds |
| `test_claim_nft_non_beneficiary_fails` | Non-beneficiary attempts claim | Fails with `ENotBeneficiary` |
| `test_claim_nft_during_cliff_fails` | Claim attempt during cliff | Fails with `ECliffNotEnded` |
| `test_double_claim_nft_fails` | Attempt second claim | Fails with `EAlreadyClaimed` |

### Revocation Tests (5 tests)

| Test | Description | Expected Behavior |
|------|-------------|-------------------|
| `test_revoke_nft_before_cliff` | Revoke during cliff period | NFT returned to creator |
| `test_revoke_nft_after_cliff_fails` | Revoke after cliff ends | Fails with `ENotRevocable` (beneficiary owns it) |
| `test_revoke_non_revocable_nft_fails` | Revoke non-revocable schedule | Fails with `ENotRevocable` |
| `test_revoke_nft_wrong_cap_fails` | Use wrong CreatorCap | Fails with `ECreatorCapMismatch` |
| `test_double_revoke_nft_fails` | Attempt second revocation | Fails with `EAlreadyRevoked` |

### Admin Tests (2 tests)

| Test | Description | Expected Behavior |
|------|-------------|-------------------|
| `test_admin_pause_nft_schedule` | Admin pauses NFT schedule | Schedule paused, `is_claimable` returns false |
| `test_paused_nft_schedule_rejects_claims` | Claim from paused schedule | Fails with `ESchedulePaused` |

### Edge Case Tests (4 tests)

| Test | Description | Expected Behavior |
|------|-------------|-------------------|
| `test_nft_schedule_with_custom_ticks` | Create with custom CLMM ticks | NFT properties preserved |
| `test_time_until_claimable_before_start` | Query before start time | Returns start delay + cliff |
| `test_delete_empty_nft_schedule` | Delete after claim | Schedule object deleted |
| `test_delete_non_empty_nft_schedule_fails` | Delete with NFT still inside | Fails with `EZeroItems` |
| `test_nft_time_constants` | Verify time constants | MS_PER_DAY, MS_PER_MONTH correct |

---

## Test Helpers

### test_coin.move

```move
/// Test coin for fungible token vesting tests
module sui_vesting::test_coin {
    public struct TEST_COIN has drop {}

    /// Mint test tokens
    public fun mint(amount: u64, ctx: &mut TxContext): Coin<TEST_COIN>

    /// Get treasury for more complex tests
    public fun create_treasury(ctx: &mut TxContext): TreasuryCap<TEST_COIN>
}
```

### test_nft.move

```move
/// Test NFT simulating CLMM position
module sui_vesting::test_nft {
    public struct TestPosition has key, store {
        id: UID,
        pool_id: ID,
        liquidity: u64,
        tick_lower: u64,
        tick_upper: u64,
    }

    /// Create position with default ticks
    public fun create_position(liquidity: u64, ctx: &mut TxContext): TestPosition

    /// Create position with custom ticks
    public fun create_position_with_ticks(
        liquidity: u64,
        tick_lower: u64,
        tick_upper: u64,
        ctx: &mut TxContext
    ): TestPosition

    /// Get liquidity
    public fun liquidity(position: &TestPosition): u64

    /// Destroy position (cleanup)
    public fun destroy(position: TestPosition)
}
```

---

## Test Constants

```move
const ADMIN: address = @0xAD;
const CREATOR: address = @0xC1;
const BENEFICIARY: address = @0xB1;

const MS_PER_DAY: u64 = 86_400_000;
const MS_PER_MONTH: u64 = 2_592_000_000;
```

---

## Running Tests

```bash
# Run all tests
sui move test

# Run specific test
sui move test test_create_schedule_basic

# Run tests matching pattern
sui move test vesting

# Run with single thread (debugging)
sui move test -t 1

# List all tests
sui move test --list
```

---

## Test Coverage Summary

| Module | Tests | Coverage |
|--------|-------|----------|
| vesting.move | 32 | Schedule creation, claiming, revocation, admin, edge cases |
| nft_vesting.move | 19 | Schedule creation, claiming, revocation, admin, edge cases |
| access.move | 2 | Capability creation |
| **Total** | **51** | **All passing** |

---

## Error Codes Tested

### Coin Vesting

| Error | Tests Verifying |
|-------|-----------------|
| `ENotClaimable` (100) | `test_claim_nothing_claimable_fails` |
| `EScheduleEmpty` (101) | `test_delete_non_empty_schedule_fails` |
| `EZeroAmount` (105) | `test_create_schedule_zero_amount_fails` |
| `EInvalidBeneficiary` (107) | `test_create_schedule_zero_beneficiary_fails` |
| `EAlreadyRevoked` (108) | `test_double_revoke_fails` |
| `ENotRevocable` (109) | `test_revoke_non_revocable_fails` |
| `ENotBeneficiary` (200) | `test_claim_non_beneficiary_fails` |
| `ESchedulePaused` (300) | `test_paused_platform_rejects_schedules`, `test_paused_schedule_rejects_claims` |
| `ECreatorCapMismatch` (400) | `test_revoke_wrong_cap_fails` |

### NFT Vesting

| Error | Tests Verifying |
|-------|-----------------|
| `EAlreadyClaimed` (501) | `test_double_claim_nft_fails` |
| `EZeroItems` (502) | `test_delete_non_empty_nft_schedule_fails` |
| `EInvalidBeneficiary` (503) | `test_create_nft_schedule_zero_beneficiary_fails` |
| `EAlreadyRevoked` (504) | `test_double_revoke_nft_fails` |
| `ENotRevocable` (505) | `test_revoke_non_revocable_nft_fails`, `test_revoke_nft_after_cliff_fails` |
| `ENotBeneficiary` (506) | `test_claim_nft_non_beneficiary_fails` |
| `ESchedulePaused` (507) | `test_paused_nft_schedule_rejects_claims` |
| `ECreatorCapMismatch` (508) | `test_revoke_nft_wrong_cap_fails` |
| `ECliffNotEnded` (509) | `test_claim_nft_during_cliff_fails` |
