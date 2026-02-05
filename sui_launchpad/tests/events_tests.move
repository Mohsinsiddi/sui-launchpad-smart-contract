/// Tests for events module - ensures all emit functions work correctly
#[test_only]
module sui_launchpad::events_tests {
    use std::type_name;
    use sui::test_scenario::{Self as ts};
    use sui_launchpad::events;

    const ADMIN: address = @0xAD;

    // Dummy coin for type_name
    public struct DUMMY_COIN has drop {}

    #[test]
    fun test_emit_token_created() {
        let mut scenario = ts::begin(ADMIN);
        ts::next_tx(&mut scenario, ADMIN);
        {
            let pool_id = object::id_from_address(@0x1);
            let token_type = type_name::get<DUMMY_COIN>();

            events::emit_token_created(
                pool_id,
                token_type,
                @0xC1,
                std::string::utf8(b"Test Token"),
                std::ascii::string(b"TEST"),
                1_000_000_000,
                500_000_000,
                1000,
            );
        };
        ts::end(scenario);
    }

    #[test]
    fun test_emit_trade() {
        let mut scenario = ts::begin(ADMIN);
        ts::next_tx(&mut scenario, ADMIN);
        {
            let pool_id = object::id_from_address(@0x1);
            let token_type = type_name::get<DUMMY_COIN>();

            events::emit_trade(
                pool_id,
                token_type,
                @0xB1,
                true, // is_buy
                1_000_000_000,
                1_000_000,
                1000,
                5_000_000,
                2_500_000,
                1_000_000,
                1000,
            );
        };
        ts::end(scenario);
    }

    #[test]
    fun test_emit_token_graduated() {
        let mut scenario = ts::begin(ADMIN);
        ts::next_tx(&mut scenario, ADMIN);
        {
            let pool_id = object::id_from_address(@0x1);
            let dex_pool_id = object::id_from_address(@0x2);
            let token_type = type_name::get<DUMMY_COIN>();

            events::emit_token_graduated(
                pool_id,
                token_type,
                0, // DEX_CETUS
                dex_pool_id,
                100_000,
                69_000_000_000_000,
                60_000_000_000_000,
                500_000_000_000_000,
                3_450_000_000_000,
                25_000_000_000_000,
                1000,
            );
        };
        ts::end(scenario);
    }

    #[test]
    fun test_emit_pool_paused() {
        let mut scenario = ts::begin(ADMIN);
        ts::next_tx(&mut scenario, ADMIN);
        {
            let pool_id = object::id_from_address(@0x1);

            // Test pause
            events::emit_pool_paused(pool_id, true, 1000);

            // Test unpause
            events::emit_pool_paused(pool_id, false, 2000);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_emit_vesting_created() {
        let mut scenario = ts::begin(ADMIN);
        ts::next_tx(&mut scenario, ADMIN);
        {
            let vesting_id = object::id_from_address(@0x1);
            let pool_id = object::id_from_address(@0x2);

            events::emit_vesting_created(
                vesting_id,
                pool_id,
                @0xC1,
                1_000_000_000,
                1000, // start_time
                86_400_000, // cliff_duration (1 day)
                259_200_000, // vesting_duration (3 days)
                1000,
            );
        };
        ts::end(scenario);
    }

    #[test]
    fun test_emit_vesting_claimed() {
        let mut scenario = ts::begin(ADMIN);
        ts::next_tx(&mut scenario, ADMIN);
        {
            let vesting_id = object::id_from_address(@0x1);

            events::emit_vesting_claimed(
                vesting_id,
                @0xC1,
                250_000_000, // amount_claimed
                500_000_000, // total_claimed
                500_000_000, // remaining
                100_000,
            );
        };
        ts::end(scenario);
    }

    #[test]
    fun test_emit_fees_withdrawn() {
        let mut scenario = ts::begin(ADMIN);
        ts::next_tx(&mut scenario, ADMIN);
        {
            events::emit_fees_withdrawn(
                1_000_000_000,
                @0xFEE,
                100_000,
            );
        };
        ts::end(scenario);
    }
}
