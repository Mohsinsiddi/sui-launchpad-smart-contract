/// Comprehensive integration tests for the multisig module
#[test_only]
module sui_multisig::multisig_tests {
    use sui::test_scenario::{Self as ts};
    use sui::clock;
    use sui::coin;
    use sui::balance;
    use sui::sui::SUI;

    use sui_multisig::registry::{Self, MultisigRegistry};
    use sui_multisig::wallet::{Self, MultisigWallet};
    use sui_multisig::vault::{Self, MultisigVault};
    use sui_multisig::proposal::{Self, MultisigProposal};
    use sui_multisig::access::AdminCap;
    use sui_multisig::test_coins::{Self, TEST_TOKEN_A, TEST_TOKEN_B, TEST_TOKEN_C};
    use sui_multisig::mock_target::{Self, MockTreasury};

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    const ADMIN: address = @0xAD;
    const ALICE: address = @0xA;
    const BOB: address = @0xB;
    const CHARLIE: address = @0xC;
    const DAVE: address = @0xD;
    const RECIPIENT: address = @0xE;

    const MS_PER_DAY: u64 = 86_400_000;

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    fun mint_sui(amount: u64, ctx: &mut TxContext): coin::Coin<SUI> {
        coin::from_balance(balance::create_for_testing<SUI>(amount), ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WALLET CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_wallet_2_of_3() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let signers = vector[ALICE, BOB, CHARLIE];
            let creation_fee = mint_sui(5_000_000_000, ts::ctx(&mut scenario));

            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team Wallet"),
                signers,
                2,
                creation_fee,
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(wallet.threshold() == 2, 0);
            assert!(wallet.signer_count() == 3, 1);
            assert!(wallet.is_signer(ALICE), 2);
            assert!(wallet.is_signer(BOB), 3);
            assert!(wallet.is_signer(CHARLIE), 4);

            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            assert!(registry.total_wallets() == 1, 5);
            assert!(registry.collected_fees() == 5_000_000_000, 6);
            ts::return_shared(registry);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_create_wallet_1_of_1() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Solo"),
                vector[ALICE],
                1,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            assert!(wallet.threshold() == 1, 0);
            assert!(wallet.signer_count() == 1, 1);
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 102)] // ENoSigners
    fun test_cannot_create_wallet_with_no_signers() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Empty"),
                vector[],
                1,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 100)] // EZeroThreshold
    fun test_cannot_create_wallet_with_zero_threshold() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Bad"),
                vector[ALICE, BOB],
                0,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 101)] // EThresholdExceedsSigners
    fun test_cannot_create_wallet_with_threshold_exceeding_signers() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Bad"),
                vector[ALICE, BOB],
                3,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 103)] // EDuplicateSigner
    fun test_cannot_create_wallet_with_duplicate_signers() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Dup"),
                vector[ALICE, BOB, ALICE],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VAULT DEPOSIT TESTS - Generic handling (SUI is just Coin<SUI>)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_deposit_sui_generic() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Deposit SUI using generic deposit function
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut vault = ts::take_shared<MultisigVault>(&scenario);
            let deposit = mint_sui(100_000_000_000, ts::ctx(&mut scenario));

            // Use generic deposit - SUI is just Coin<SUI>
            vault::deposit(&mut vault, deposit, ts::ctx(&mut scenario));

            assert!(vault::balance<SUI>(&vault) == 100_000_000_000, 0);
            ts::return_shared(vault);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_deposit_multiple_token_types() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Deposit SUI, TOKEN_A, TOKEN_B
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut vault = ts::take_shared<MultisigVault>(&scenario);

            // SUI
            vault::deposit(&mut vault, mint_sui(100_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));

            // Token A
            vault::deposit(&mut vault, test_coins::mint_token_a(50_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));

            // Token B
            vault::deposit(&mut vault, test_coins::mint_token_b(25_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));

            assert!(vault::balance<SUI>(&vault) == 100_000_000_000, 0);
            assert!(vault::balance<TEST_TOKEN_A>(&vault) == 50_000_000_000, 1);
            assert!(vault::balance<TEST_TOKEN_B>(&vault) == 25_000_000_000, 2);

            ts::return_shared(vault);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GENERIC TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_transfer_sui_via_generic_proposal() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Deposit SUI
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut vault = ts::take_shared<MultisigVault>(&scenario);
            vault::deposit(&mut vault, mint_sui(100_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
            ts::return_shared(vault);
        };

        // Create SUI transfer proposal using generic propose_transfer
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);

            let proposal = proposal::propose_transfer<SUI>(
                &wallet,
                &registry,
                RECIPIENT,
                10_000_000_000,
                std::string::utf8(b"Pay contractor"),
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(proposal::action_type(&proposal) == proposal::action_type_transfer(), 0);
            assert!(proposal::action_amount(&proposal) == 10_000_000_000, 1);

            ts::return_shared(wallet);
            ts::return_shared(registry);
            transfer::public_share_object(proposal);
        };

        // Bob approves
        ts::next_tx(&mut scenario, BOB);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);

            proposal::approve(&mut proposal, &wallet, &clock, ts::ctx(&mut scenario));
            assert!(proposal::status(&proposal) == proposal::status_approved(), 0);

            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        // Execute
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut vault = ts::take_shared<MultisigVault>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);

            let withdrawn = proposal::execute_transfer<SUI>(
                &mut proposal,
                &mut wallet,
                &mut vault,
                &mut registry,
                mint_sui(100_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(coin::value(&withdrawn) == 10_000_000_000, 0);
            assert!(vault::balance<SUI>(&vault) == 90_000_000_000, 1);

            transfer::public_transfer(withdrawn, RECIPIENT);
            ts::return_shared(wallet);
            ts::return_shared(vault);
            ts::return_shared(registry);
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_transfer_token_a_via_generic_proposal() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Deposit TOKEN_A
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut vault = ts::take_shared<MultisigVault>(&scenario);
            vault::deposit(&mut vault, test_coins::mint_token_a(50_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
            ts::return_shared(vault);
        };

        // Create TOKEN_A transfer proposal
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);

            let proposal = proposal::propose_transfer<TEST_TOKEN_A>(
                &wallet,
                &registry,
                RECIPIENT,
                5_000_000_000,
                std::string::utf8(b"Token payment"),
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(wallet);
            ts::return_shared(registry);
            transfer::public_share_object(proposal);
        };

        // Bob approves
        ts::next_tx(&mut scenario, BOB);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            proposal::approve(&mut proposal, &wallet, &clock, ts::ctx(&mut scenario));
            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        // Execute
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut vault = ts::take_shared<MultisigVault>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);

            let withdrawn = proposal::execute_transfer<TEST_TOKEN_A>(
                &mut proposal,
                &mut wallet,
                &mut vault,
                &mut registry,
                mint_sui(100_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(coin::value(&withdrawn) == 5_000_000_000, 0);
            assert!(vault::balance<TEST_TOKEN_A>(&vault) == 45_000_000_000, 1);

            test_coins::burn_token_a(withdrawn);
            ts::return_shared(wallet);
            ts::return_shared(vault);
            ts::return_shared(registry);
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CUSTOM TRANSACTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_custom_tx_set_value() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        // Create wallet
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Create mock target treasury
        ts::next_tx(&mut scenario, ALICE);
        {
            mock_target::create_and_share(ts::ctx(&mut scenario));
        };

        // Create custom tx proposal
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let treasury = ts::take_shared<MockTreasury>(&scenario);

            let proposal = proposal::propose_custom_tx(
                &wallet,
                &registry,
                mock_target::treasury_id(&treasury),
                std::string::utf8(b"set_value"),
                std::string::utf8(b"Set treasury value to 42"),
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(proposal::action_type(&proposal) == proposal::action_type_custom_tx(), 0);
            assert!(proposal::action_target_id(&proposal) == mock_target::treasury_id(&treasury), 1);

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(treasury);
            transfer::public_share_object(proposal);
        };

        // Bob approves
        ts::next_tx(&mut scenario, BOB);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            proposal::approve(&mut proposal, &wallet, &clock, ts::ctx(&mut scenario));
            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        // Execute custom tx and use auth
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            let mut treasury = ts::take_shared<MockTreasury>(&scenario);

            // Get authorization
            let auth = proposal::execute_custom_tx(
                &mut proposal,
                &mut wallet,
                &mut registry,
                mint_sui(100_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );

            // Use auth on target contract
            mock_target::set_value_with_auth(&mut treasury, auth, 42);

            assert!(mock_target::value(&treasury) == 42, 0);
            assert!(mock_target::operation_count(&treasury) == 1, 1);
            assert!(proposal::status(&proposal) == proposal::status_executed(), 2);

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_custom_tx_pause_unpause() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Create mock target treasury
        ts::next_tx(&mut scenario, ALICE);
        {
            mock_target::create_and_share(ts::ctx(&mut scenario));
        };

        // Create pause proposal
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let treasury = ts::take_shared<MockTreasury>(&scenario);

            let proposal = proposal::propose_custom_tx(
                &wallet,
                &registry,
                mock_target::treasury_id(&treasury),
                std::string::utf8(b"pause"),
                std::string::utf8(b"Emergency pause"),
                &clock,
                ts::ctx(&mut scenario),
            );

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(treasury);
            transfer::public_share_object(proposal);
        };

        // Bob approves
        ts::next_tx(&mut scenario, BOB);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            proposal::approve(&mut proposal, &wallet, &clock, ts::ctx(&mut scenario));
            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        // Execute pause
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            let mut treasury = ts::take_shared<MockTreasury>(&scenario);

            let auth = proposal::execute_custom_tx(
                &mut proposal,
                &mut wallet,
                &mut registry,
                mint_sui(100_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );

            mock_target::pause_with_auth(&mut treasury, auth);
            assert!(mock_target::is_paused(&treasury), 0);

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // APPROVAL/REJECTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_proposal_approval_reaches_threshold() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB, CHARLIE],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut vault = ts::take_shared<MultisigVault>(&scenario);
            vault::deposit(&mut vault, mint_sui(100_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
            ts::return_shared(vault);
        };

        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let proposal = proposal::propose_transfer<SUI>(
                &wallet,
                &registry,
                RECIPIENT,
                10_000_000_000,
                std::string::utf8(b"Test"),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(wallet);
            ts::return_shared(registry);
            transfer::public_share_object(proposal);
        };

        // Bob approves - should reach threshold (Alice auto-approved)
        ts::next_tx(&mut scenario, BOB);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);

            assert!(proposal::approval_count(&proposal) == 1, 0);
            proposal::approve(&mut proposal, &wallet, &clock, ts::ctx(&mut scenario));
            assert!(proposal::approval_count(&proposal) == 2, 1);
            assert!(proposal::status(&proposal) == proposal::status_approved(), 2);

            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_proposal_rejection() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB, CHARLIE],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let proposal = proposal::propose_add_signer(
                &wallet,
                &registry,
                DAVE,
                std::string::utf8(b"Add Dave"),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(wallet);
            ts::return_shared(registry);
            transfer::public_share_object(proposal);
        };

        // Bob and Charlie reject
        ts::next_tx(&mut scenario, BOB);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            proposal::reject(&mut proposal, &wallet, &clock, ts::ctx(&mut scenario));
            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        ts::next_tx(&mut scenario, CHARLIE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            proposal::reject(&mut proposal, &wallet, &clock, ts::ctx(&mut scenario));
            assert!(proposal::status(&proposal) == proposal::status_rejected(), 0);
            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 205)] // EAlreadyApproved
    fun test_cannot_approve_twice() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB, CHARLIE],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let proposal = proposal::propose_add_signer(
                &wallet,
                &registry,
                DAVE,
                std::string::utf8(b"Add"),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(wallet);
            ts::return_shared(registry);
            transfer::public_share_object(proposal);
        };

        // Alice already approved, try again
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            proposal::approve(&mut proposal, &wallet, &clock, ts::ctx(&mut scenario));
            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 207)] // ENotSigner
    fun test_non_signer_cannot_create_proposal() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // DAVE (not a signer) tries to create proposal
        ts::next_tx(&mut scenario, DAVE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let proposal = proposal::propose_add_signer(
                &wallet,
                &registry,
                CHARLIE,
                std::string::utf8(b"Add"),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(wallet);
            ts::return_shared(registry);
            transfer::public_share_object(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SIGNER MANAGEMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_add_signer() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let proposal = proposal::propose_add_signer(
                &wallet,
                &registry,
                DAVE,
                std::string::utf8(b"Add Dave"),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(wallet);
            ts::return_shared(registry);
            transfer::public_share_object(proposal);
        };

        ts::next_tx(&mut scenario, BOB);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            proposal::approve(&mut proposal, &wallet, &clock, ts::ctx(&mut scenario));
            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);

            proposal::execute_add_signer(
                &mut proposal,
                &mut wallet,
                &mut registry,
                mint_sui(100_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(wallet.signer_count() == 3, 0);
            assert!(wallet.is_signer(DAVE), 1);

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_remove_signer_auto_adjusts_threshold() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        // Create 2-of-2 wallet
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB, CHARLIE],
                3, // 3-of-3
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Propose remove Charlie
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let proposal = proposal::propose_remove_signer(
                &wallet,
                &registry,
                CHARLIE,
                std::string::utf8(b"Remove"),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(wallet);
            ts::return_shared(registry);
            transfer::public_share_object(proposal);
        };

        // Bob approves
        ts::next_tx(&mut scenario, BOB);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            proposal::approve(&mut proposal, &wallet, &clock, ts::ctx(&mut scenario));
            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        // Charlie approves (3-of-3)
        ts::next_tx(&mut scenario, CHARLIE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            proposal::approve(&mut proposal, &wallet, &clock, ts::ctx(&mut scenario));
            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        // Execute removal
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);

            assert!(wallet.threshold() == 3, 0);

            proposal::execute_remove_signer(
                &mut proposal,
                &mut wallet,
                &mut registry,
                mint_sui(100_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );

            assert!(wallet.signer_count() == 2, 1);
            assert!(!wallet.is_signer(CHARLIE), 2);
            // Threshold auto-adjusted from 3 to 2
            assert!(wallet.threshold() == 2, 3);

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXPIRY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure(abort_code = 203)] // EProposalExpired
    fun test_cannot_approve_expired_proposal() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let proposal = proposal::propose_add_signer(
                &wallet,
                &registry,
                DAVE,
                std::string::utf8(b"Add"),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(wallet);
            ts::return_shared(registry);
            transfer::public_share_object(proposal);
        };

        // Fast forward past expiry (8 days)
        clock::set_for_testing(&mut clock, MS_PER_DAY * 8);

        // Try to approve expired proposal
        ts::next_tx(&mut scenario, BOB);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            proposal::approve(&mut proposal, &wallet, &clock, ts::ctx(&mut scenario));
            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CANCEL TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_proposer_can_cancel() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let proposal = proposal::propose_add_signer(
                &wallet,
                &registry,
                DAVE,
                std::string::utf8(b"Add"),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(wallet);
            ts::return_shared(registry);
            transfer::public_share_object(proposal);
        };

        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            proposal::cancel(&mut proposal, &wallet, ts::ctx(&mut scenario));
            assert!(proposal::status(&proposal) == proposal::status_cancelled(), 0);
            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 400)] // ENotAuthorized
    fun test_non_proposer_cannot_cancel() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let proposal = proposal::propose_add_signer(
                &wallet,
                &registry,
                DAVE,
                std::string::utf8(b"Add"),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(wallet);
            ts::return_shared(registry);
            transfer::public_share_object(proposal);
        };

        // Bob (not proposer) tries to cancel
        ts::next_tx(&mut scenario, BOB);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            proposal::cancel(&mut proposal, &wallet, ts::ctx(&mut scenario));
            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fun test_admin_withdraw_fees() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);

            let fees = registry::withdraw_fees(&mut registry, &admin_cap, ts::ctx(&mut scenario));
            assert!(coin::value(&fees) == 5_000_000_000, 0);

            transfer::public_transfer(fees, ADMIN);
            ts::return_shared(registry);
            ts::return_to_sender(&scenario, admin_cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_admin_update_config() {
        let mut scenario = ts::begin(ADMIN);

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);

            registry::update_platform_config(
                &mut registry,
                &admin_cap,
                10_000_000_000,
                200_000_000,
                MS_PER_DAY * 14,
                ADMIN,
                ts::ctx(&mut scenario),
            );

            let config = registry.config();
            assert!(registry::config_creation_fee(config) == 10_000_000_000, 0);
            assert!(registry::config_execution_fee(config) == 200_000_000, 1);

            ts::return_shared(registry);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXECUTION FAILURE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure(abort_code = 204)] // EProposalNotReady
    fun test_cannot_execute_pending_proposal() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Team"),
                vector[ALICE, BOB, CHARLIE],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut vault = ts::take_shared<MultisigVault>(&scenario);
            vault::deposit(&mut vault, mint_sui(100_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
            ts::return_shared(vault);
        };

        // Create proposal (only Alice approved, needs 2)
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let proposal = proposal::propose_transfer<SUI>(
                &wallet,
                &registry,
                RECIPIENT,
                10_000_000_000,
                std::string::utf8(b"Test"),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(wallet);
            ts::return_shared(registry);
            transfer::public_share_object(proposal);
        };

        // Try to execute without enough approvals
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut vault = ts::take_shared<MultisigVault>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);

            let withdrawn = proposal::execute_transfer<SUI>(
                &mut proposal,
                &mut wallet,
                &mut vault,
                &mut registry,
                mint_sui(100_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );

            transfer::public_transfer(withdrawn, RECIPIENT);
            ts::return_shared(wallet);
            ts::return_shared(vault);
            ts::return_shared(registry);
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STRICT MULTI-COIN VAULT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Test vault with 4 different coin types (SUI + TOKEN_A + TOKEN_B + TOKEN_C)
    /// Verifies: deposits, balances, multiple deposits of same type, has_token checks
    #[test]
    fun test_strict_multi_coin_vault() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        // Create wallet
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Multi-Asset Treasury"),
                vector[ALICE, BOB, CHARLIE],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Verify initial vault is empty for all token types
        ts::next_tx(&mut scenario, ALICE);
        {
            let vault = ts::take_shared<MultisigVault>(&scenario);

            // All balances should be 0 initially
            assert!(vault::balance<SUI>(&vault) == 0, 0);
            assert!(vault::balance<TEST_TOKEN_A>(&vault) == 0, 1);
            assert!(vault::balance<TEST_TOKEN_B>(&vault) == 0, 2);
            assert!(vault::balance<TEST_TOKEN_C>(&vault) == 0, 3);

            // has_token should be false for all
            assert!(!vault::has_token<SUI>(&vault), 4);
            assert!(!vault::has_token<TEST_TOKEN_A>(&vault), 5);
            assert!(!vault::has_token<TEST_TOKEN_B>(&vault), 6);
            assert!(!vault::has_token<TEST_TOKEN_C>(&vault), 7);

            ts::return_shared(vault);
        };

        // Deposit first batch: SUI and TOKEN_A
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut vault = ts::take_shared<MultisigVault>(&scenario);

            vault::deposit(&mut vault, mint_sui(100_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
            vault::deposit(&mut vault, test_coins::mint_token_a(50_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));

            // Verify after first batch
            assert!(vault::balance<SUI>(&vault) == 100_000_000_000, 10);
            assert!(vault::balance<TEST_TOKEN_A>(&vault) == 50_000_000_000, 11);
            assert!(vault::balance<TEST_TOKEN_B>(&vault) == 0, 12);
            assert!(vault::balance<TEST_TOKEN_C>(&vault) == 0, 13);

            assert!(vault::has_token<SUI>(&vault), 14);
            assert!(vault::has_token<TEST_TOKEN_A>(&vault), 15);
            assert!(!vault::has_token<TEST_TOKEN_B>(&vault), 16);
            assert!(!vault::has_token<TEST_TOKEN_C>(&vault), 17);

            ts::return_shared(vault);
        };

        // Deposit second batch: TOKEN_B and TOKEN_C (from different user BOB)
        ts::next_tx(&mut scenario, BOB);
        {
            let mut vault = ts::take_shared<MultisigVault>(&scenario);

            vault::deposit(&mut vault, test_coins::mint_token_b(25_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
            vault::deposit(&mut vault, test_coins::mint_token_c(75_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));

            // Verify all four tokens now present
            assert!(vault::balance<SUI>(&vault) == 100_000_000_000, 20);
            assert!(vault::balance<TEST_TOKEN_A>(&vault) == 50_000_000_000, 21);
            assert!(vault::balance<TEST_TOKEN_B>(&vault) == 25_000_000_000, 22);
            assert!(vault::balance<TEST_TOKEN_C>(&vault) == 75_000_000_000, 23);

            assert!(vault::has_token<SUI>(&vault), 24);
            assert!(vault::has_token<TEST_TOKEN_A>(&vault), 25);
            assert!(vault::has_token<TEST_TOKEN_B>(&vault), 26);
            assert!(vault::has_token<TEST_TOKEN_C>(&vault), 27);

            ts::return_shared(vault);
        };

        // Additional deposits to existing tokens (should add to existing balances)
        ts::next_tx(&mut scenario, CHARLIE);
        {
            let mut vault = ts::take_shared<MultisigVault>(&scenario);

            // Add more of each token
            vault::deposit(&mut vault, mint_sui(50_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
            vault::deposit(&mut vault, test_coins::mint_token_a(25_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
            vault::deposit(&mut vault, test_coins::mint_token_b(12_500_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
            vault::deposit(&mut vault, test_coins::mint_token_c(37_500_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));

            // Final strict verification
            assert!(vault::balance<SUI>(&vault) == 150_000_000_000, 30); // 100 + 50
            assert!(vault::balance<TEST_TOKEN_A>(&vault) == 75_000_000_000, 31); // 50 + 25
            assert!(vault::balance<TEST_TOKEN_B>(&vault) == 37_500_000_000, 32); // 25 + 12.5
            assert!(vault::balance<TEST_TOKEN_C>(&vault) == 112_500_000_000, 33); // 75 + 37.5

            ts::return_shared(vault);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    /// Test transfer of TOKEN_C specifically
    #[test]
    fun test_transfer_token_c_via_generic_proposal() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        // Create 1-of-1 wallet
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Treasury"),
                vector[ALICE],
                1,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Deposit TOKEN_C
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut vault = ts::take_shared<MultisigVault>(&scenario);
            vault::deposit(&mut vault, test_coins::mint_token_c(100_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
            assert!(vault::balance<TEST_TOKEN_C>(&vault) == 100_000_000_000, 100);
            ts::return_shared(vault);
        };

        // Create TOKEN_C transfer proposal
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);

            let proposal = proposal::propose_transfer<TEST_TOKEN_C>(
                &wallet, &registry, DAVE, 25_000_000_000,
                std::string::utf8(b"TOKEN_C payment"),
                &clock, ts::ctx(&mut scenario),
            );

            ts::return_shared(wallet);
            ts::return_shared(registry);
            transfer::public_share_object(proposal);
        };

        // Execute transfer
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut vault = ts::take_shared<MultisigVault>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);

            let withdrawn = proposal::execute_transfer<TEST_TOKEN_C>(
                &mut proposal, &mut wallet, &mut vault, &mut registry,
                mint_sui(100_000_000, ts::ctx(&mut scenario)),
                &clock, ts::ctx(&mut scenario),
            );

            // Verify balance decreased
            assert!(vault::balance<TEST_TOKEN_C>(&vault) == 75_000_000_000, 110); // 100 - 25
            assert!(withdrawn.value() == 25_000_000_000, 111);

            test_coins::burn_token_c(withdrawn);
            ts::return_shared(wallet);
            ts::return_shared(vault);
            ts::return_shared(registry);
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    /// Test transfer of TOKEN_B specifically
    #[test]
    fun test_transfer_token_b_via_generic_proposal() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        // Create 1-of-1 wallet
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Treasury"),
                vector[ALICE],
                1,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Deposit TOKEN_B
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut vault = ts::take_shared<MultisigVault>(&scenario);
            vault::deposit(&mut vault, test_coins::mint_token_b(80_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
            assert!(vault::balance<TEST_TOKEN_B>(&vault) == 80_000_000_000, 100);
            ts::return_shared(vault);
        };

        // Create TOKEN_B transfer proposal
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);

            let proposal = proposal::propose_transfer<TEST_TOKEN_B>(
                &wallet, &registry, CHARLIE, 30_000_000_000,
                std::string::utf8(b"TOKEN_B payment"),
                &clock, ts::ctx(&mut scenario),
            );

            ts::return_shared(wallet);
            ts::return_shared(registry);
            transfer::public_share_object(proposal);
        };

        // Execute transfer
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut vault = ts::take_shared<MultisigVault>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);

            let withdrawn = proposal::execute_transfer<TEST_TOKEN_B>(
                &mut proposal, &mut wallet, &mut vault, &mut registry,
                mint_sui(100_000_000, ts::ctx(&mut scenario)),
                &clock, ts::ctx(&mut scenario),
            );

            // Verify balance decreased
            assert!(vault::balance<TEST_TOKEN_B>(&vault) == 50_000_000_000, 110); // 80 - 30
            assert!(withdrawn.value() == 30_000_000_000, 111);

            test_coins::burn_token_b(withdrawn);
            ts::return_shared(wallet);
            ts::return_shared(vault);
            ts::return_shared(registry);
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STRICT CUSTOM TX TESTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Strict test: Custom TX set_value with full state verification
    #[test]
    fun test_strict_custom_tx_set_value() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        // Create 2-of-3 wallet
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"DAO Council"),
                vector[ALICE, BOB, CHARLIE],
                2,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Create mock target treasury
        ts::next_tx(&mut scenario, ALICE);
        {
            mock_target::create_and_share(ts::ctx(&mut scenario));
        };

        // === STRICT VERIFICATION: Initial State ===
        ts::next_tx(&mut scenario, ALICE);
        {
            let treasury = ts::take_shared<MockTreasury>(&scenario);

            // Verify treasury is in initial state
            assert!(mock_target::value(&treasury) == 0, 200);
            assert!(mock_target::operation_count(&treasury) == 0, 201);
            assert!(mock_target::is_paused(&treasury) == false, 202);
            assert!(mock_target::last_wallet_id(&treasury).is_none(), 203);

            ts::return_shared(treasury);
        };

        // Create custom tx proposal to set value to 12345
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let treasury = ts::take_shared<MockTreasury>(&scenario);
            let treasury_id = mock_target::treasury_id(&treasury);

            let proposal = proposal::propose_custom_tx(
                &wallet,
                &registry,
                treasury_id,
                std::string::utf8(b"set_value"),
                std::string::utf8(b"Set treasury value to 12345"),
                &clock,
                ts::ctx(&mut scenario),
            );

            // Verify proposal created correctly
            assert!(proposal::action_type(&proposal) == proposal::action_type_custom_tx(), 210);
            assert!(proposal::action_target_id(&proposal) == treasury_id, 211);
            assert!(proposal::status(&proposal) == proposal::status_pending(), 212);
            assert!(proposal::approval_count(&proposal) == 1, 213); // Alice auto-approved

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(treasury);
            transfer::public_share_object(proposal);
        };

        // === STRICT VERIFICATION: State unchanged after proposal creation ===
        ts::next_tx(&mut scenario, BOB);
        {
            let treasury = ts::take_shared<MockTreasury>(&scenario);

            // Treasury should still be unchanged
            assert!(mock_target::value(&treasury) == 0, 220);
            assert!(mock_target::operation_count(&treasury) == 0, 221);

            ts::return_shared(treasury);
        };

        // Bob approves (reaches threshold)
        ts::next_tx(&mut scenario, BOB);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);

            proposal::approve(&mut proposal, &wallet, &clock, ts::ctx(&mut scenario));

            // Now has 2 approvals, should be ready
            assert!(proposal::approval_count(&proposal) == 2, 230);
            assert!(proposal::status(&proposal) == proposal::status_approved(), 231);

            ts::return_shared(wallet);
            ts::return_shared(proposal);
        };

        // Execute custom tx
        ts::next_tx(&mut scenario, CHARLIE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            let mut treasury = ts::take_shared<MockTreasury>(&scenario);
            let wallet_id = wallet::wallet_id(&wallet);

            // === STRICT VERIFICATION: State BEFORE execution ===
            assert!(mock_target::value(&treasury) == 0, 240);
            assert!(mock_target::operation_count(&treasury) == 0, 241);
            assert!(mock_target::last_wallet_id(&treasury).is_none(), 242);

            // Get authorization
            let auth = proposal::execute_custom_tx(
                &mut proposal,
                &mut wallet,
                &mut registry,
                mint_sui(100_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );

            // Use auth on target contract with value 12345
            mock_target::set_value_with_auth(&mut treasury, auth, 12345);

            // === STRICT VERIFICATION: State AFTER execution ===
            assert!(mock_target::value(&treasury) == 12345, 250);
            assert!(mock_target::operation_count(&treasury) == 1, 251);
            assert!(mock_target::is_paused(&treasury) == false, 252); // Unchanged

            // Verify wallet_id was recorded
            let last_wallet = mock_target::last_wallet_id(&treasury);
            assert!(last_wallet.is_some(), 253);
            assert!(*last_wallet.borrow() == wallet_id, 254);

            // Proposal should be executed
            assert!(proposal::status(&proposal) == proposal::status_executed(), 255);

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    /// Strict test: Custom TX pause operation
    #[test]
    fun test_strict_custom_tx_pause() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        // Create 1-of-1 wallet
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Controller"),
                vector[ALICE],
                1,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Create mock target treasury
        ts::next_tx(&mut scenario, ALICE);
        {
            mock_target::create_and_share(ts::ctx(&mut scenario));
        };

        // Create pause proposal
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let treasury = ts::take_shared<MockTreasury>(&scenario);

            // Verify initial state
            assert!(mock_target::is_paused(&treasury) == false, 300);
            assert!(mock_target::operation_count(&treasury) == 0, 301);

            let proposal = proposal::propose_custom_tx(
                &wallet, &registry,
                mock_target::treasury_id(&treasury),
                std::string::utf8(b"pause"),
                std::string::utf8(b"Emergency pause"),
                &clock, ts::ctx(&mut scenario),
            );

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(treasury);
            transfer::public_share_object(proposal);
        };

        // Execute pause
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            let mut treasury = ts::take_shared<MockTreasury>(&scenario);
            let wallet_id = wallet::wallet_id(&wallet);

            let auth = proposal::execute_custom_tx(
                &mut proposal, &mut wallet, &mut registry,
                mint_sui(100_000_000, ts::ctx(&mut scenario)),
                &clock, ts::ctx(&mut scenario),
            );

            mock_target::pause_with_auth(&mut treasury, auth);

            // Verify state AFTER pause
            assert!(mock_target::is_paused(&treasury) == true, 310);
            assert!(mock_target::operation_count(&treasury) == 1, 311);
            assert!(*mock_target::last_wallet_id(&treasury).borrow() == wallet_id, 312);

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    /// Strict test: Custom TX unpause operation
    #[test]
    fun test_strict_custom_tx_unpause() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        // Create 1-of-1 wallet
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Controller"),
                vector[ALICE],
                1,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Create mock target treasury
        ts::next_tx(&mut scenario, ALICE);
        {
            mock_target::create_and_share(ts::ctx(&mut scenario));
        };

        // First pause it
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let treasury = ts::take_shared<MockTreasury>(&scenario);

            let proposal = proposal::propose_custom_tx(
                &wallet, &registry,
                mock_target::treasury_id(&treasury),
                std::string::utf8(b"pause"),
                std::string::utf8(b"Pause first"),
                &clock, ts::ctx(&mut scenario),
            );

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(treasury);
            transfer::public_share_object(proposal);
        };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            let mut treasury = ts::take_shared<MockTreasury>(&scenario);

            let auth = proposal::execute_custom_tx(
                &mut proposal, &mut wallet, &mut registry,
                mint_sui(100_000_000, ts::ctx(&mut scenario)),
                &clock, ts::ctx(&mut scenario),
            );

            mock_target::pause_with_auth(&mut treasury, auth);
            assert!(mock_target::is_paused(&treasury) == true, 320);

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        // Now unpause - note: we DON'T return the pause proposal, so take_shared will get a fresh one
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let treasury = ts::take_shared<MockTreasury>(&scenario);

            let proposal = proposal::propose_custom_tx(
                &wallet, &registry,
                mock_target::treasury_id(&treasury),
                std::string::utf8(b"unpause"),
                std::string::utf8(b"Resume operations"),
                &clock, ts::ctx(&mut scenario),
            );

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(treasury);
            transfer::public_share_object(proposal);
        };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut treasury = ts::take_shared<MockTreasury>(&scenario);

            // Take the SECOND (most recent) proposal
            // We need to skip the first executed proposal
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);

            // Check if we got the right proposal (should be APPROVED status)
            // If it's EXECUTED, we got the wrong one
            if (proposal::status(&proposal) != proposal::status_approved()) {
                ts::return_shared(proposal);
                let mut proposal2 = ts::take_shared<MultisigProposal>(&scenario);

                let auth = proposal::execute_custom_tx(
                    &mut proposal2, &mut wallet, &mut registry,
                    mint_sui(100_000_000, ts::ctx(&mut scenario)),
                    &clock, ts::ctx(&mut scenario),
                );

                mock_target::unpause_with_auth(&mut treasury, auth);

                ts::return_shared(proposal2);
            } else {
                let auth = proposal::execute_custom_tx(
                    &mut proposal, &mut wallet, &mut registry,
                    mint_sui(100_000_000, ts::ctx(&mut scenario)),
                    &clock, ts::ctx(&mut scenario),
                );

                mock_target::unpause_with_auth(&mut treasury, auth);

                ts::return_shared(proposal);
            };

            // Verify state AFTER unpause
            assert!(mock_target::is_paused(&treasury) == false, 330);
            assert!(mock_target::operation_count(&treasury) == 2, 331);

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(treasury);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    /// Strict test: Custom TX with execute_with_raw_auth (single increment)
    #[test]
    fun test_strict_custom_tx_raw_auth_increment() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        // Create wallet
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Incrementer"),
                vector[ALICE],
                1,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Create mock target treasury
        ts::next_tx(&mut scenario, ALICE);
        {
            mock_target::create_and_share(ts::ctx(&mut scenario));
        };

        // Use execute_with_raw_auth to increment by 100
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let treasury = ts::take_shared<MockTreasury>(&scenario);

            let proposal = proposal::propose_custom_tx(
                &wallet, &registry,
                mock_target::treasury_id(&treasury),
                std::string::utf8(b"execute_with_raw_auth"),
                std::string::utf8(b"Increment by 100"),
                &clock, ts::ctx(&mut scenario),
            );

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(treasury);
            transfer::public_share_object(proposal);
        };

        ts::next_tx(&mut scenario, ALICE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            let mut treasury = ts::take_shared<MockTreasury>(&scenario);

            // Value BEFORE: 0
            assert!(mock_target::value(&treasury) == 0, 400);
            assert!(mock_target::operation_count(&treasury) == 0, 401);

            let auth = proposal::execute_custom_tx(
                &mut proposal, &mut wallet, &mut registry,
                mint_sui(100_000_000, ts::ctx(&mut scenario)),
                &clock, ts::ctx(&mut scenario),
            );

            // Use raw auth and increment by 100
            mock_target::execute_with_raw_auth(&mut treasury, auth, 100);

            // Value AFTER: 100 (0 + 100)
            assert!(mock_target::value(&treasury) == 100, 410);
            assert!(mock_target::operation_count(&treasury) == 1, 411);
            assert!(mock_target::last_wallet_id(&treasury).is_some(), 412);

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    /// Test: Verify custom TX auth contains correct wallet ID
    #[test]
    fun test_custom_tx_auth_wallet_id_verification() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        // Create wallet
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Auth Test"),
                vector[ALICE],
                1,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Create mock treasury
        ts::next_tx(&mut scenario, ALICE);
        {
            mock_target::create_and_share(ts::ctx(&mut scenario));
        };

        // Create custom tx proposal
        ts::next_tx(&mut scenario, ALICE);
        {
            let wallet = ts::take_shared<MultisigWallet>(&scenario);
            let registry = ts::take_shared<MultisigRegistry>(&scenario);
            let treasury = ts::take_shared<MockTreasury>(&scenario);

            let proposal = proposal::propose_custom_tx(
                &wallet, &registry,
                mock_target::treasury_id(&treasury),
                std::string::utf8(b"set_value"),
                std::string::utf8(b"Set value"),
                &clock, ts::ctx(&mut scenario),
            );

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(treasury);
            transfer::public_share_object(proposal);
        };

        // Execute custom tx
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let mut proposal = ts::take_shared<MultisigProposal>(&scenario);
            let mut treasury = ts::take_shared<MockTreasury>(&scenario);
            let expected_wallet_id = wallet::wallet_id(&wallet);

            let auth = proposal::execute_custom_tx(
                &mut proposal, &mut wallet, &mut registry,
                mint_sui(100_000_000, ts::ctx(&mut scenario)),
                &clock, ts::ctx(&mut scenario),
            );

            mock_target::set_value_with_auth(&mut treasury, auth, 999);

            // Verify the wallet ID was correctly recorded in the external contract
            let recorded_wallet_id = mock_target::last_wallet_id(&treasury);
            assert!(recorded_wallet_id.is_some(), 500);
            assert!(*recorded_wallet_id.borrow() == expected_wallet_id, 501);

            ts::return_shared(wallet);
            ts::return_shared(registry);
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    /// Test: Verify vault can hold all four token types simultaneously
    #[test]
    fun test_vault_holds_all_four_token_types() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        { registry::init_for_testing(ts::ctx(&mut scenario)); };

        // Create wallet
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut registry = ts::take_shared<MultisigRegistry>(&scenario);
            let wallet = wallet::create_wallet(
                &mut registry,
                std::string::utf8(b"Multi-Token Vault"),
                vector[ALICE],
                1,
                mint_sui(5_000_000_000, ts::ctx(&mut scenario)),
                &clock,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            transfer::public_share_object(wallet);
        };

        // Deposit all token types and verify
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut vault = ts::take_shared<MultisigVault>(&scenario);

            // Initial balances should all be 0
            assert!(vault::balance<SUI>(&vault) == 0, 600);
            assert!(vault::balance<TEST_TOKEN_A>(&vault) == 0, 601);
            assert!(vault::balance<TEST_TOKEN_B>(&vault) == 0, 602);
            assert!(vault::balance<TEST_TOKEN_C>(&vault) == 0, 603);

            // Deposit different amounts of each
            vault::deposit(&mut vault, mint_sui(100_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
            vault::deposit(&mut vault, test_coins::mint_token_a(200_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
            vault::deposit(&mut vault, test_coins::mint_token_b(300_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));
            vault::deposit(&mut vault, test_coins::mint_token_c(400_000_000_000, ts::ctx(&mut scenario)), ts::ctx(&mut scenario));

            // Verify each balance independently
            assert!(vault::balance<SUI>(&vault) == 100_000_000_000, 610);
            assert!(vault::balance<TEST_TOKEN_A>(&vault) == 200_000_000_000, 611);
            assert!(vault::balance<TEST_TOKEN_B>(&vault) == 300_000_000_000, 612);
            assert!(vault::balance<TEST_TOKEN_C>(&vault) == 400_000_000_000, 613);

            // Verify has_token returns true for all
            assert!(vault::has_token<SUI>(&vault), 620);
            assert!(vault::has_token<TEST_TOKEN_A>(&vault), 621);
            assert!(vault::has_token<TEST_TOKEN_B>(&vault), 622);
            assert!(vault::has_token<TEST_TOKEN_C>(&vault), 623);

            ts::return_shared(vault);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}
