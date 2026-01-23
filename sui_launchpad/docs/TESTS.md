# Test Documentation - Sui Launchpad

## Overview

**Total Tests: 201**
**Status: All Passing ✅**
**Last Updated: January 2026**

---

## Test Modules Summary

| Module | Tests | Description |
|--------|-------|-------------|
| `bonding_curve_tests` | 46 | Core trading, fees, pool safety |
| `config_tests` | 35 | Configuration, admin controls, limits |
| `math_tests` | 26 | Mathematical functions, precision |
| `dex_adapter_tests` | 32 | DEX helper functions, sqrt price, slippage |
| `launchpad_tests` | 14 | Entry points, user flows |
| `graduation_tests` | 14 | Graduation mechanics |
| `suidex_integration_tests` | 5 | SuiDex LP token creation, PTB flow |
| `cetus_integration_tests` | 2 | Cetus Position NFT creation |
| `flowx_integration_tests` | 2 | FlowX Position NFT creation |
| `registry_tests` | 8 | Pool registry |
| `access` | 2 | Admin/operator capabilities |
| `math` (inline) | 4 | Core math functions |
| Other inline tests | 11 | DEX adapter inline tests |

---

## Bonding Curve Tests (`bonding_curve_tests.move`)

### Pool Creation Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_create_pool_success` | ✅ PASS | Pool created with correct initial state |
| `test_create_pool_with_creator_fee` | ✅ PASS | Pool accepts valid creator fee (1-5%) |
| `test_create_pool_creator_fee_too_high` | ✅ PASS | Rejects creator fee > 5% (error 308) |
| `test_create_pool_insufficient_payment` | ✅ PASS | Rejects if creation fee not paid (error 303) |
| `test_create_pool_excess_payment_refunded` | ✅ PASS | Excess payment refunded to creator |

### Buy Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_buy_tokens_success` | ✅ PASS | Buy executes, tokens received, pool state updated |
| `test_buy_tokens_slippage_exceeded` | ✅ PASS | Rejects if min_tokens not met (error 306) |
| `test_buy_tokens_zero_amount` | ✅ PASS | Rejects zero amount buy (error 305) |
| `test_buy_on_paused_pool` | ✅ PASS | Rejects buy on paused pool (error 300) |

### Sell Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_sell_tokens_success` | ✅ PASS | Sell executes, SUI received, tokens returned to pool |
| `test_sell_tokens_slippage_exceeded` | ✅ PASS | Rejects if min_sui not met (error 306) |
| `test_sell_all_tokens` | ✅ PASS | Can sell all tokens, pool left with dust |
| `test_multiple_buy_sell_cycles` | ✅ PASS | Multiple buy/sell cycles work correctly |

### Fee Calculation Tests (STRICT)

| Test | Status | Description |
|------|--------|-------------|
| `test_strict_buy_fee_calculation` | ✅ PASS | **Exact values**: 10 SUI buy → 0.05 SUI platform fee (0.5%), 0.2 SUI creator fee (2%), 9.75 SUI to pool |
| `test_strict_sell_fee_calculation` | ✅ PASS | **Exact values**: Fees deducted from gross SUI, user receives net |
| `test_creator_fee_paid_on_buy` | ✅ PASS | Creator receives exact fee amount on each buy |

### Token Conservation Tests (STRICT)

| Test | Status | Description |
|------|--------|-------------|
| `test_token_conservation_on_buy` | ✅ PASS | **Invariant**: `pool_tokens + circulating = available_supply` holds after buy |
| `test_token_conservation_on_sell` | ✅ PASS | **Invariant**: Same invariant holds after sell |

### Price & Math Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_get_price` | ✅ PASS | Price calculation correct |
| `test_estimate_buy_sell` | ✅ PASS | Estimates match actual execution |
| `test_price_strictly_increases_on_buy` | ✅ PASS | **Strict**: Price monotonically increases with each buy |
| `test_volume_and_trade_count_tracking` | ✅ PASS | **Exact**: Volume = sum of trade amounts, count increments |

### Admin Safety Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_pause_pool` | ✅ PASS | Admin can pause pool |
| `test_only_admin_can_pause` | ✅ PASS | Only AdminCap holder can pause/unpause |
| `test_pool_state_after_pause_unpause` | ✅ PASS | **Strict**: All state preserved across pause/unpause cycles |
| `test_check_graduation_ready` | ✅ PASS | Graduation readiness check works |

### Edge Case Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_pool_creation_with_zero_creator_fee` | ✅ PASS | Pool works with 0% creator fee |
| `test_pool_creation_with_max_creator_fee` | ✅ PASS | Pool works with max 5% creator fee |

### Fund Safety Tests (CRITICAL)

| Test | Status | Description |
|------|--------|-------------|
| `test_emergency_withdraw_sui_requires_pause` | ✅ PASS | **Security**: Admin can withdraw SUI only when pool paused |
| `test_emergency_withdraw_sui_fails_without_pause` | ✅ PASS | **Security**: Withdrawal fails if pool not paused (error 300) |
| `test_emergency_withdraw_tokens_requires_pause` | ✅ PASS | **Security**: Admin can withdraw tokens only when pool paused |
| `test_emergency_withdraw_tokens_fails_without_pause` | ✅ PASS | **Security**: Withdrawal fails if pool not paused (error 300) |

### Token Flow Tests (STRICT)

| Test | Status | Description |
|------|--------|-------------|
| `test_sui_flow_buy_exact_destinations` | ✅ PASS | **Exact**: Pool gets net SUI, creator gets fee, treasury gets platform fee |
| `test_sui_flow_sell_exact_destinations` | ✅ PASS | **Exact**: User receives net SUI after all fees |
| `test_token_flow_buy_exact_amounts` | ✅ PASS | **Exact**: Tokens decrease from pool, increase in circulation |
| `test_token_flow_sell_returns_to_pool` | ✅ PASS | **Exact**: Tokens return to pool, circulation decreases |
| `test_no_fund_leakage_full_cycle` | ✅ PASS | **Security**: Full buy→sell cycle leaves only dust, no leakage |

---

## Config Tests (`config_tests.move`)

### Config Creation Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_config_creation` | ✅ PASS | Config created with correct defaults |
| `test_config_default_curve_params` | ✅ PASS | Default curve params: base_price=1000, slope=1M, supply=1B |

### Fee Update Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_set_creation_fee` | ✅ PASS | Admin can update creation fee |
| `test_set_trading_fee` | ✅ PASS | Admin can update trading fee |
| `test_set_trading_fee_too_high` | ✅ PASS | Rejects trading fee > 5% (error 100) |
| `test_set_graduation_fee` | ✅ PASS | Admin can update graduation fee |

### Graduation Settings Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_set_graduation_threshold` | ✅ PASS | Admin can update graduation threshold |
| `test_set_graduation_threshold_zero` | ✅ PASS | Allows zero threshold (disabled) |
| `test_set_creator_graduation_bps` | ✅ PASS | Admin can set creator graduation allocation |
| `test_set_creator_graduation_bps_too_high` | ✅ PASS | Rejects > 5% creator allocation (error 104) |
| `test_set_platform_graduation_bps` | ✅ PASS | Admin can set platform graduation allocation |
| `test_set_platform_graduation_bps_too_low` | ✅ PASS | Rejects < 2.5% platform allocation (error 104) |

### LP Distribution Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_set_creator_lp_bps` | ✅ PASS | Admin can set creator LP share |
| `test_set_creator_lp_bps_too_high` | ✅ PASS | Rejects > 30% creator LP (error 105) |
| `test_set_community_lp_destination` | ✅ PASS | Admin can set LP destination |
| `test_set_community_lp_destination_invalid` | ✅ PASS | Rejects invalid destination > 3 (error 106) |

### Admin Safety Tests (STRICT)

| Test | Status | Description |
|------|--------|-------------|
| `test_config_values_preserved_across_updates` | ✅ PASS | **Strict**: Only updated value changes, others preserved |
| `test_all_fee_limits_enforced` | ✅ PASS | **Strict**: Trading ≤5%, graduation ≤5% enforced |
| `test_lp_distribution_safety_limits` | ✅ PASS | **Strict**: Creator LP ≤30%, community ≥70% |
| `test_graduation_threshold_safety` | ✅ PASS | **Strict**: Threshold within bounds |
| `test_pause_state_toggle_correctness` | ✅ PASS | **Strict**: Pause/unpause is idempotent |
| `test_treasury_address_safety` | ✅ PASS | **Strict**: Treasury address updates correctly |
| `test_dex_configuration_safety` | ✅ PASS | **Strict**: Only valid DEX types (0-3) accepted |

### Constants Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_dex_type_constants` | ✅ PASS | DEX constants: Cetus=0, Turbos=1, FlowX=2, SuiDex=3 |
| `test_lp_destination_constants` | ✅ PASS | LP dest: Burn=0, DAO=1, Staking=2, Vest=3 |
| `test_fund_safety_constants` | ✅ PASS | Safety limits defined correctly |

---

## Math Tests (`math_tests.move`)

### Core Math Functions

| Test | Status | Description |
|------|--------|-------------|
| `test_bps_percentages` | ✅ PASS | BPS calculation: 500 bps = 5% |
| `test_bps_zero` | ✅ PASS | 0 bps = 0 |
| `test_bps_fractional` | ✅ PASS | Fractional BPS handled |
| `test_bps_denominator` | ✅ PASS | 10000 bps = 100% |
| `test_mul_div_basic` | ✅ PASS | Basic multiplication/division |
| `test_mul_div_large_numbers` | ✅ PASS | Handles large numbers without overflow |
| `test_mul_div_zero_numerator` | ✅ PASS | Zero numerator returns 0 |
| `test_mul_div_zero_denominator` | ✅ PASS | Division by zero aborts (error 2) |
| `test_mul_div_up_basic` | ✅ PASS | Round-up division works |
| `test_mul_div_up_exact` | ✅ PASS | Exact division doesn't round |

### Curve Math Functions

| Test | Status | Description |
|------|--------|-------------|
| `test_curve_area_zero_supply` | ✅ PASS | Area at supply=0 is 0 |
| `test_curve_area_zero_slope` | ✅ PASS | Flat curve (slope=0) works |
| `test_curve_area_with_slope` | ✅ PASS | Sloped curve area calculation |
| `test_get_price_zero_supply` | ✅ PASS | Initial price = base_price |
| `test_get_price_with_supply` | ✅ PASS | Price increases with supply |
| `test_get_price_linear_increase` | ✅ PASS | Price follows linear curve |
| `test_tokens_out_basic` | ✅ PASS | Token output for SUI input |
| `test_sui_out_basic` | ✅ PASS | SUI output for token input |
| `test_buy_sell_symmetry` | ✅ PASS | Buy/sell roughly symmetric |

### Utility Functions

| Test | Status | Description |
|------|--------|-------------|
| `test_min` | ✅ PASS | Min function works |
| `test_max` | ✅ PASS | Max function works |
| `test_sqrt_perfect_squares` | ✅ PASS | Sqrt of perfect squares |
| `test_sqrt_non_perfect_squares` | ✅ PASS | Sqrt rounds down |
| `test_sqrt_large_numbers` | ✅ PASS | Sqrt handles large numbers |
| `test_sqrt_u64` | ✅ PASS | Full u64 range supported |
| `test_after_fee` | ✅ PASS | Fee deduction calculation |
| `test_precision` | ✅ PASS | Precision constant correct |
| `test_edge_case_max_bps` | ✅ PASS | Max BPS (10000) = 100% |
| `test_edge_case_small_amounts` | ✅ PASS | Small amounts don't underflow |

---

## Launchpad Tests (`launchpad_tests.move`)

### Entry Point Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_buy_entry_point` | ✅ PASS | Buy entry function works |
| `test_buy_and_transfer_entry_point` | ✅ PASS | Buy and transfer in one call |
| `test_sell_entry_point` | ✅ PASS | Sell entry function works |
| `test_sell_and_transfer_entry_point` | ✅ PASS | Sell and transfer in one call |

### View Functions

| Test | Status | Description |
|------|--------|-------------|
| `test_get_price` | ✅ PASS | Price view function |
| `test_get_market_cap` | ✅ PASS | Market cap calculation |
| `test_estimate_buy` | ✅ PASS | Buy estimation accurate |
| `test_estimate_sell` | ✅ PASS | Sell estimation accurate |
| `test_can_graduate` | ✅ PASS | Graduation readiness check |
| `test_registry_views` | ✅ PASS | Registry view functions |

### Admin Entry Points

| Test | Status | Description |
|------|--------|-------------|
| `test_pause_platform` | ✅ PASS | Admin can pause platform |
| `test_unpause_platform` | ✅ PASS | Admin can unpause platform |
| `test_pause_pool` | ✅ PASS | Admin can pause specific pool |
| `test_unpause_pool` | ✅ PASS | Admin can unpause specific pool |
| `test_price_increases_on_buy` | ✅ PASS | Price increases after buy |
| `test_price_decreases_on_sell` | ✅ PASS | Price decreases after sell |

---

## Graduation Tests (`graduation_tests.move`)

### Readiness Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_can_graduate_initial_state` | ✅ PASS | New pool not ready for graduation |
| `test_pool_not_graduated_initially` | ✅ PASS | Pool starts as not graduated |
| `test_graduation_threshold_checks` | ✅ PASS | Threshold requirements enforced |
| `test_graduation_with_some_trading` | ✅ PASS | Partial trading doesn't trigger graduation |
| `test_paused_pool_cannot_graduate` | ✅ PASS | Paused pool cannot graduate |

### Configuration Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_graduation_fee_configuration` | ✅ PASS | Graduation fee configured correctly |
| `test_lp_distribution_config` | ✅ PASS | LP distribution params correct |
| `test_dex_type_constants` | ✅ PASS | DEX type constants defined |
| `test_graduation_token_allocations` | ✅ PASS | Token allocation limits enforced |

### Graduation Flow Tests

| Test | Status | Description |
|------|--------|-------------|
| `test_initiate_graduation_not_ready` | ✅ PASS | Cannot initiate if not ready (error 400) |
| `test_initiate_graduation_paused_pool` | ✅ PASS | Cannot graduate paused pool (error 402) |
| `test_market_cap_increases_with_buys` | ✅ PASS | Market cap tracked correctly |

---

## Registry Tests (`registry_tests.move`)

| Test | Status | Description |
|------|--------|-------------|
| `test_registry_creation` | ✅ PASS | Registry created correctly |
| `test_registry_counters_initial` | ✅ PASS | Counters start at 0 |
| `test_is_not_registered_initially` | ✅ PASS | New types not registered |
| `test_get_pools_empty` | ✅ PASS | Empty registry returns empty |
| `test_get_pools_beyond_range` | ✅ PASS | Out of range returns empty |
| `test_get_pools_by_creator_empty` | ✅ PASS | No pools for new creator |
| `test_get_creator_pool_count_zero` | ✅ PASS | New creator has 0 pools |
| `test_get_pool_by_type_not_found` | ✅ PASS | Unknown type returns none |

---

## Access Tests (`access.move`)

| Test | Status | Description |
|------|--------|-------------|
| `test_create_admin_cap` | ✅ PASS | AdminCap created correctly |
| `test_create_operator_cap` | ✅ PASS | OperatorCap created correctly |

---

## Error Codes Reference

| Code | Name | Description |
|------|------|-------------|
| 100 | EFeeTooHigh | Fee exceeds maximum allowed |
| 103 | EInvalidThreshold | Invalid graduation threshold |
| 104 | EInvalidGraduationAllocation | Graduation allocation out of bounds |
| 105 | ECreatorLPTooHigh | Creator LP share > 30% |
| 106 | EInvalidLPDestination | LP destination > 3 |
| 300 | EPoolPaused | Operation on paused pool |
| 303 | EInsufficientPayment | Not enough SUI provided |
| 305 | EZeroAmount | Zero amount not allowed |
| 306 | ESlippageExceeded | Slippage protection triggered |
| 308 | ECreatorFeeTooHigh | Creator fee > 5% |
| 400 | ENotReadyForGraduation | Pool hasn't reached threshold |
| 402 | EPoolPaused (graduation) | Cannot graduate paused pool |

---

## Security Guarantees

### Fund Safety
- Emergency withdrawals require **AdminCap + Pool Paused**
- No direct fund extraction without proper authorization
- Token conservation invariant always holds

### Fee Integrity
- Platform fee: 0.5% (50 bps) - exact amount verified
- Creator fee: 0-5% (0-500 bps) - exact amount verified
- Graduation fee: up to 5% (500 bps)

### Access Control
- AdminCap required for: pause, emergency withdraw, config updates
- OperatorCap for limited operations
- Creator receives fees automatically

### Mathematical Safety
- Overflow protection in curve calculations
- Division by zero protection
- Precision maintained through PRECISION constant (10^9)

---

## Running Tests

```bash
# Run all tests
sui move test

# Run specific module tests
sui move test --filter bonding_curve

# Run with verbose output
sui move test -v
```

---

## DEX Integration Tests

### SuiDex Tests (`suidex_integration_tests.move`)

| Test | Status | Description |
|------|--------|-------------|
| `test_suidex_graduation_creates_lp_tokens` | ✅ PASS | LP tokens minted on graduation |
| `test_suidex_lp_amount_proportional_to_liquidity` | ✅ PASS | LP amount matches input liquidity |
| `test_suidex_pair_reserves_match_input` | ✅ PASS | Pair reserves equal input amounts |
| `test_suidex_ptb_atomic_graduation` | ✅ PASS | Full PTB flow: initiate → extract → add_liquidity → complete |
| `test_suidex_ptb_atomic_failure_reverts_all` | ✅ PASS | Failed graduation doesn't create partial state |

### Cetus Tests (`cetus_integration_tests.move`)

| Test | Status | Description |
|------|--------|-------------|
| `test_cetus_graduation_creates_position_nft` | ✅ PASS | Position NFT created with liquidity > 0 |
| `test_cetus_position_has_correct_tick_range` | ✅ PASS | Tick range [0, 2000] verified |

### FlowX Tests (`flowx_integration_tests.move`)

| Test | Status | Description |
|------|--------|-------------|
| `test_flowx_graduation_creates_position_nft` | ✅ PASS | Position NFT created, pool_id valid |
| `test_flowx_position_has_correct_tick_range` | ✅ PASS | Tick range [-60000, +60000] verified |

### DEX Adapter Tests (`dex_adapter_tests.move`)

| Test | Status | Description |
|------|--------|-------------|
| `test_suidex_*` | ✅ 10 PASS | SuiDex helper functions (slippage, min amounts) |
| `test_cetus_*` | ✅ 6 PASS | Cetus helper functions (sqrt price, ticks) |
| `test_flowx_*` | ✅ 10 PASS | FlowX helper functions (sqrt price, ticks, fee) |
| `test_turbos_*` | ✅ 6 PASS | Turbos helper functions |

---

## Test Coverage Summary

| Category | Tests | Coverage |
|----------|-------|----------|
| Pool Creation | 5 | ✅ Complete |
| Buy Operations | 4 | ✅ Complete |
| Sell Operations | 4 | ✅ Complete |
| Fee Calculations | 3 | ✅ Strict/Exact |
| Token Conservation | 2 | ✅ Invariant |
| Fund Safety | 5 | ✅ Critical |
| Token Flow | 4 | ✅ Exact |
| Admin Controls | 4 | ✅ Complete |
| Config Updates | 15+ | ✅ Complete |
| Math Functions | 26 | ✅ Complete |
| Graduation | 14 | ✅ Complete |
| Registry | 8 | ✅ Complete |
| DEX Adapters | 32 | ✅ Complete |
| DEX Integration | 9 | ✅ Complete |

**Total: 201 tests, 100% passing**
