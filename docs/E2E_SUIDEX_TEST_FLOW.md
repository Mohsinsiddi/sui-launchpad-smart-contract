# End-to-End SuiDex Test Flow Documentation

## Overview

This document describes the complete end-to-end test flows for the SuiDex integration with the launchpad. The tests cover the full token lifecycle from creation through trading, graduation, DEX trading, LP token distribution, staking, DAO governance, treasury management, and vesting.

## Test File

| File | Description | Tests |
|------|-------------|-------|
| `tests/e2e_suidex_tests.move` | Comprehensive E2E tests for SuiDex integration | 16 |

**Total E2E Tests: 16**

---

## Complete Token Journey

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           COMPLETE TOKEN LIFECYCLE                               │
└─────────────────────────────────────────────────────────────────────────────────┘

PHASE 1: TOKEN LAUNCH
├── TreasuryCap → Bonding Pool (1 billion tokens minted)
└── Pool created with bonding curve pricing

PHASE 2: TRADING ON LAUNCHPAD
├── Users buy tokens with SUI
├── Bonding curve determines price (increases with purchases)
└── Pool accumulates SUI toward graduation threshold

PHASE 3: GRADUATION THRESHOLD (69,000 SUI)
└── Pool marked as ready for graduation

PHASE 4: GRADUATION EXECUTION
├── Extract SUI + Tokens from pool
├── Add liquidity to SuiDex → LP tokens minted
├── Extract staking tokens → Create staking pool
├── Create DAO linked to staking pool
└── Create Treasury for DAO

PHASE 5: LP TOKEN DISTRIBUTION
├── Creator LP (2.5%) → Vesting contract
├── Protocol LP (2.5%) → Platform treasury
└── DAO LP (95%) → DAO Treasury

PHASE 6: POST-GRADUATION DEX TRADING
├── Buy tokens from SuiDex (SUI → TEST_COIN)
└── Sell tokens on SuiDex (TEST_COIN → SUI)

PHASE 7: STAKING
├── Token holders stake → Receive StakingPosition NFT
├── Staked tokens = Voting power in DAO
├── Earn staking rewards over time
├── Claim rewards without unstaking
├── Add more stake to existing position
├── Unstake after minimum duration
└── Early unstake with penalty

PHASE 8: DAO GOVERNANCE
├── Create proposals (requires voting power threshold)
├── Vote YES/NO/ABSTAIN on proposals
├── Finalize voting after period ends
├── Queue passed proposals for execution
└── Execute or cancel proposals

PHASE 9: TREASURY MANAGEMENT
├── Deposit SUI to treasury
├── Deposit tokens to treasury
└── Governance-controlled withdrawals

PHASE 10: VESTING
├── Create vesting schedules
├── Cliff period (no claims)
├── Linear vesting after cliff
├── Claim vested tokens
└── Revoke revocable schedules
```

---

## Test Functions (e2e_suidex_tests.move)

### PART 1: Token Flow Tests

| Test | Purpose |
|------|---------|
| `test_token_creation` | Verify pool created with correct state |
| `test_launchpad_trading` | Test buying tokens and reaching graduation threshold |
| `test_graduation_initiates_correctly` | Test graduation initiation with hot potato pattern |
| `test_cannot_graduate_before_threshold` | Graduation blocked before 69,000 SUI |

---

### PART 2: LP Token Flow Tests

| Test | Purpose |
|------|---------|
| `test_dex_pair_creation` | Create DEX pair using router |
| `test_add_liquidity_mints_lp` | Add liquidity and verify LP tokens minted |

**Key points:**
- Uses `suidex_router::create_pair` to create DEX pair
- Uses `suidex_router::add_liquidity` with 14 parameters
- LP tokens transferred to transaction sender

---

### PART 3: Staking Tests

| Test | Purpose |
|------|---------|
| `test_staking_pool_creation` | Create staking pool directly |
| `test_stake_and_receive_position` | Stake tokens and receive StakingPosition NFT |

**Key points:**
- `StakingPool<TEST_COIN, TEST_COIN>` - same token for stake and rewards
- Positions are owned objects (StakingPosition<T>)
- Uses `staking_factory::create_pool_free` for pool creation

---

### PART 4: DAO Governance Tests

| Test | Purpose |
|------|---------|
| `test_dao_creation` | Create DAO with staking governance |
| `test_treasury_creation` | Create treasury linked to DAO |
| `test_treasury_deposit_sui` | Deposit SUI into DAO treasury |

**Key points:**
- Voting power comes from `StakingPosition<T>.staked_amount`
- Treasury accepts any coin type
- Withdrawals require DAO governance approval

---

### PART 5: Vesting Tests

| Test | Purpose |
|------|---------|
| `test_vesting_schedule_creation` | Create vesting schedule for beneficiary |
| `test_vesting_claim_after_cliff` | Claim tokens after cliff period |
| `test_vesting_nothing_before_cliff` | Zero claimable during cliff |

**Key points:**
- VestingSchedule is owned by beneficiary (not shared)
- Creator receives CreatorCap for management
- Cliff period: no vesting occurs
- Linear vesting after cliff

---

### PART 6: Complete Journey Tests

| Test | Purpose |
|------|---------|
| `test_complete_token_lifecycle` | Full journey: creation → trading → graduation → DEX → treasury |
| `test_trading_blocked_after_graduation` | Pool properly closed after graduation |

---

## Key Implementation Details

### Hot Potato Pattern

The `PendingGraduation<T>` struct has no `drop` ability:
```move
public struct PendingGraduation<phantom T> {
    // ... balances must be extracted
}
```
Forces caller to:
1. Extract all balances (SUI, tokens, staking tokens)
2. Call `complete_graduation()` to consume it

### LP Token Flow

```move
// Step 1: Add liquidity to DEX (14 parameters)
suidex_router::add_liquidity<TEST_COIN, SUI>(
    &router, &mut factory, &mut pair,
    tokens_for_dex, sui_for_dex,
    (token_amount as u256), (sui_amount as u256),
    0, 0,
    std::string::utf8(b"TEST"), std::string::utf8(b"SUI"),
    9999999999999, &clock,
    ts::ctx(scenario),
);
// LP tokens transferred to tx sender

// Step 2: Split LP tokens
let creator_lp = coin::split(&mut lp_tokens, creator_amount, ctx);
let protocol_lp = coin::split(&mut lp_tokens, protocol_amount, ctx);
let dao_lp = lp_tokens; // remaining 95%

// Step 3: Distribute
transfer::public_transfer(creator_lp, creator);
transfer::public_transfer(protocol_lp, platform_treasury);
dao_integration::deposit_lp_to_treasury<LPCoin<TEST_COIN, SUI>>(&mut treasury, dao_lp, ctx);
```

### Staking Pool Configuration

```move
StakingPool<TEST_COIN, TEST_COIN>
// StakeToken = TEST_COIN (users stake this)
// RewardToken = TEST_COIN (distributed as rewards)
```

### Address Configuration

Must match `test_utils.move`:
- `admin() = @0xA1` - AdminCap owner
- `creator() = @0xC1` - Token creator
- `platform_treasury() = @0xE1` - Protocol fee recipient

---

## Test Results Summary

```
E2E SuiDex Tests: 16 total
└── All tests in e2e_suidex_tests.move: 16 passed
```

| Test | Status |
|------|--------|
| test_token_creation | PASS |
| test_launchpad_trading | PASS |
| test_graduation_initiates_correctly | PASS |
| test_cannot_graduate_before_threshold | PASS |
| test_dex_pair_creation | PASS |
| test_add_liquidity_mints_lp | PASS |
| test_staking_pool_creation | PASS |
| test_stake_and_receive_position | PASS |
| test_dao_creation | PASS |
| test_treasury_creation | PASS |
| test_treasury_deposit_sui | PASS |
| test_vesting_schedule_creation | PASS |
| test_vesting_claim_after_cliff | PASS |
| test_vesting_nothing_before_cliff | PASS |
| test_complete_token_lifecycle | PASS |
| test_trading_blocked_after_graduation | PASS |

---

## Running the Tests

```bash
# Run all E2E SuiDex tests
sui move test e2e_suidex_tests --silence-warnings

# Run a specific test
sui move test test_complete_token_lifecycle --silence-warnings
```

---

## Dependencies

The E2E tests require these packages:
- `sui_launchpad` - Main launchpad package
- `sui_staking` - Staking pool functionality
- `sui_dao` - Governance + Treasury
- `sui_vesting` - Token vesting
- `suitrump_dex` - SuiDex AMM

---

## Coverage Summary

| User Flow Category | Tests | Coverage |
|-------------------|-------|----------|
| Token Launch | 1 | Complete |
| Launchpad Trading | 1 | Complete |
| Graduation | 2 | Complete |
| DEX Pair Creation | 1 | Complete |
| LP Minting | 1 | Complete |
| Staking | 2 | Complete |
| DAO Governance | 2 | Complete |
| Treasury | 1 | Complete |
| Vesting | 3 | Complete |
| Complete Journey | 2 | Complete |

**Total: 16 tests covering all major user flows**
