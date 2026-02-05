/// Tests for errors module - ensures all error code getters work correctly
#[test_only]
module sui_launchpad::errors_tests {
    use sui_launchpad::errors;

    // ═══════════════════════════════════════════════════════════════════════
    // GENERAL ERRORS (0-99)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_general_error_codes() {
        assert!(errors::not_authorized() == 0, 0);
        assert!(errors::invalid_input() == 1, 1);
        assert!(errors::paused() == 2, 2);
        assert!(errors::zero_amount() == 3, 3);
        assert!(errors::insufficient_balance() == 4, 4);
        assert!(errors::overflow() == 5, 5);
        assert!(errors::division_by_zero() == 6, 6);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIG ERRORS (100-199)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_config_error_codes() {
        assert!(errors::fee_too_high() == 100, 0);
        assert!(errors::invalid_fee() == 101, 1);
        assert!(errors::invalid_threshold() == 102, 2);
        assert!(errors::already_initialized() == 103, 3);
        assert!(errors::not_initialized() == 104, 4);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REGISTRY ERRORS (200-299)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_registry_error_codes() {
        assert!(errors::token_already_registered() == 200, 0);
        assert!(errors::token_not_found() == 201, 1);
        assert!(errors::invalid_token_type() == 202, 2);
        assert!(errors::tokens_already_minted() == 203, 3);
        assert!(errors::insufficient_creation_fee() == 204, 4);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BONDING CURVE ERRORS (300-399)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_bonding_curve_error_codes() {
        assert!(errors::pool_not_found() == 300, 0);
        assert!(errors::pool_already_exists() == 301, 1);
        assert!(errors::pool_graduated() == 302, 2);
        assert!(errors::pool_paused() == 303, 3);
        assert!(errors::pool_locked() == 304, 4);
        assert!(errors::insufficient_liquidity() == 305, 5);
        assert!(errors::amount_too_small() == 306, 6);
        assert!(errors::amount_too_large() == 307, 7);
        assert!(errors::slippage_exceeded() == 308, 8);
        assert!(errors::invalid_price() == 309, 9);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GRADUATION ERRORS (400-499)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_graduation_error_codes() {
        assert!(errors::not_ready_for_graduation() == 400, 0);
        assert!(errors::already_graduated() == 401, 1);
        assert!(errors::graduation_threshold_not_met() == 402, 2);
        assert!(errors::invalid_dex_config() == 403, 3);
        assert!(errors::dex_operation_failed() == 404, 4);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VESTING ERRORS (500-599)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_vesting_error_codes() {
        assert!(errors::vesting_not_found() == 500, 0);
        assert!(errors::nothing_to_claim() == 501, 1);
        assert!(errors::vesting_not_started() == 502, 2);
        assert!(errors::cliff_not_ended() == 503, 3);
        assert!(errors::invalid_vesting_schedule() == 504, 4);
        assert!(errors::not_beneficiary() == 505, 5);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ANTI-RUG ERRORS (600-699)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_antirug_error_codes() {
        assert!(errors::pool_too_young() == 600, 0);
        assert!(errors::insufficient_buyers() == 601, 1);
        assert!(errors::insufficient_tokens_sold() == 602, 2);
        assert!(errors::graduation_cooling_period() == 603, 3);
        assert!(errors::trading_cooldown() == 604, 4);
        assert!(errors::honeypot_detected() == 605, 5);
        assert!(errors::buy_amount_too_large() == 606, 6);
        assert!(errors::timelock_not_expired() == 607, 7);
        assert!(errors::change_pending() == 608, 8);
        assert!(errors::no_pending_change() == 609, 9);
        assert!(errors::invalid_lp_distribution() == 610, 10);
        assert!(errors::creator_lp_too_high() == 611, 11);
        assert!(errors::treasury_cap_destroyed() == 612, 12);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LP DISTRIBUTION ERRORS (700-799)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_lp_distribution_error_codes() {
        assert!(errors::invalid_lp_destination() == 700, 0);
        assert!(errors::lp_vesting_too_short() == 701, 1);
        assert!(errors::lp_cliff_too_long() == 702, 2);
    }
}
