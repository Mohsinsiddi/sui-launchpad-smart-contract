# Multisig Service - Detailed Specification

## Overview

Multisig Wallet Service - A standalone product for creating multi-signature wallets. Requires N-of-M signers to approve transactions before execution. Supports custom transaction proposals for calling any contract where the multisig is admin.

---

## Business Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      MULTISIG WALLET SERVICE                             │
└─────────────────────────────────────────────────────────────────────────┘

WHO USES IT:
════════════
• Project teams (treasury management)
• DAOs (as execution layer)
• Investment groups
• Any group needing shared control

REVENUE MODEL:
══════════════
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   1. CREATION FEE (One-time)                                            │
│      └── 5-10 SUI per wallet                                            │
│      └── Paid when creating multisig                                    │
│                                                                         │
│   2. TRANSACTION FEE (Per TX)                                           │
│      └── 0.1 SUI per executed transaction                               │
│      └── Paid by executor                                               │
│                                                                         │
│   Example (100 wallets, 10 TX/wallet/month):                            │
│   ─────────────────────────────────────────                             │
│   Creation: 100 * 10 = 1,000 SUI                                        │
│   Monthly TX: 100 * 10 * 0.1 = 100 SUI/month                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Module Structure

```
sui-multisig/
├── Move.toml
└── sources/
    │
    ├── core/                    # Self-contained utilities
    │   └── access.move         # AdminCap
    │
    ├── wallet.move             # Multisig wallet creation & management
    ├── proposal.move           # Transaction proposals
    ├── custom_tx.move          # Custom transaction execution
    └── events.move             # All events
```

---

## Core Concepts

### Multisig Wallet

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       MULTISIG WALLET                                    │
└─────────────────────────────────────────────────────────────────────────┘

MultisigWallet
══════════════

┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   Configuration:                                                        │
│   ├── threshold: u64                    (N signatures required)        │
│   ├── signers: vector<address>          (M total signers)              │
│   ├── name: String                      (wallet name)                  │
│   └── description: String               (optional description)         │
│                                                                         │
│   Example: 2-of-3 Multisig                                              │
│   ├── threshold: 2                                                     │
│   └── signers: [Alice, Bob, Charlie]                                   │
│       Any 2 of these 3 must approve                                    │
│                                                                         │
│   State:                                                                │
│   ├── proposal_count: u64               (total proposals created)      │
│   ├── executed_count: u64               (total executed)               │
│   └── nonce: u64                        (for replay protection)        │
│                                                                         │
│   Balances:                                                             │
│   ├── sui_balance: Balance<SUI>         (SUI held)                     │
│   └── other_balances: Bag               (other tokens held)            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Transaction Proposal

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    TRANSACTION PROPOSAL                                  │
└─────────────────────────────────────────────────────────────────────────┘

MultisigProposal
════════════════

┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   Basic Info:                                                           │
│   ├── id: ID                                                           │
│   ├── wallet_id: ID                     (parent wallet)                │
│   ├── proposer: address                 (who created)                  │
│   ├── title: String                     (short description)            │
│   ├── description: String               (detailed description)         │
│   └── proposal_number: u64              (sequential number)            │
│                                                                         │
│   Timing:                                                               │
│   ├── created_at: u64                   (creation timestamp)           │
│   └── expires_at: u64                   (proposal expiry)              │
│                                                                         │
│   Approvals:                                                            │
│   ├── approvals: VecSet<address>        (who approved)                 │
│   ├── rejections: VecSet<address>       (who rejected)                 │
│   └── threshold_met: bool               (ready to execute)             │
│                                                                         │
│   Status:                                                               │
│   └── status: ProposalStatus                                           │
│       ├── PENDING     (waiting for approvals)                          │
│       ├── APPROVED    (threshold met, ready to execute)                │
│       ├── EXECUTED    (successfully executed)                          │
│       ├── REJECTED    (majority rejected)                              │
│       └── EXPIRED     (expired without execution)                      │
│                                                                         │
│   Action:                                                               │
│   └── action: MultisigAction                                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Multisig Actions

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       MULTISIG ACTIONS                                   │
└─────────────────────────────────────────────────────────────────────────┘

MultisigAction (enum)
═════════════════════

1. TRANSFER_SUI
   └── Send SUI to address
   └── Fields: recipient, amount

2. TRANSFER_TOKEN
   └── Send any token to address
   └── Fields: recipient, amount, token_type

3. ADD_SIGNER
   └── Add new signer to wallet
   └── Fields: new_signer, new_threshold (optional)

4. REMOVE_SIGNER
   └── Remove signer from wallet
   └── Fields: signer_to_remove, new_threshold (optional)

5. CHANGE_THRESHOLD
   └── Change approval threshold
   └── Fields: new_threshold

6. CUSTOM_TX
   └── Call any contract where multisig is admin
   └── Fields: target, module, function, type_args, args

7. BATCH_TRANSFER
   └── Multiple transfers in one proposal
   └── Fields: vector<TransferInfo>


Example Actions:
════════════════

TRANSFER_SUI:
{
    action_type: TRANSFER_SUI,
    recipient: 0xALICE...,
    amount: 1000000000  // 1 SUI
}

ADD_SIGNER:
{
    action_type: ADD_SIGNER,
    new_signer: 0xDAVID...,
    new_threshold: 3  // Change from 2-of-3 to 3-of-4
}

CUSTOM_TX:
{
    action_type: CUSTOM_TX,
    target: 0xMY_CONTRACT...,
    module: "admin",
    function: "pause_contract",
    type_args: [],
    args: []
}
```

---

## Custom Transaction Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│              CUSTOM TX FLOW (Same as DAO, but with Signatures)           │
└─────────────────────────────────────────────────────────────────────────┘

STEP 1: SIGNER PROPOSES CUSTOM TX
═════════════════════════════════

    One signer creates proposal:

    ┌─────────────────────────────────────────────────────────────────┐
    │  Proposal: "Pause trading on our DEX"                           │
    │                                                                 │
    │  Action:                                                        │
    │  ├── target: 0xOUR_DEX...                                      │
    │  ├── module: admin                                             │
    │  ├── function: pause_trading                                   │
    │  ├── type_args: []                                             │
    │  └── args: [true]  // pause = true                             │
    └─────────────────────────────────────────────────────────────────┘


STEP 2: SIMULATE TX (Off-chain)
═══════════════════════════════

    Other signers simulate before approving:

    ┌─────────────────────────────────────────────────────────────────┐
    │  Simulation Result:                                             │
    │  ├── Status: SUCCESS                                           │
    │  ├── Gas estimate: 500,000                                     │
    │  │                                                              │
    │  │  State Changes:                                              │
    │  │  ├── dex.trading_paused: false → true                       │
    │  │  └── (no other changes)                                     │
    │  │                                                              │
    │  └── Warnings: Trading will be halted!                         │
    └─────────────────────────────────────────────────────────────────┘


STEP 3: COLLECT APPROVALS
═════════════════════════

    Each signer reviews and approves:

    Wallet: 2-of-3 multisig
    ├── Alice (proposer): ✅ Auto-approved
    ├── Bob: Reviewed simulation → ✅ Approved
    └── Charlie: Pending...

    Threshold met! (2 of 3)


STEP 4: EXECUTE
═══════════════

    Anyone can execute once threshold met:

    ┌─────────────────────────────────────────────────────────────────┐
    │  multisig::execute_proposal(proposal_id)                        │
    │                                                                 │
    │  Checks:                                                        │
    │  ├── Proposal threshold met                                    │
    │  ├── Proposal not expired                                      │
    │  └── Proposal not already executed                             │
    │                                                                 │
    │  Execution:                                                     │
    │  └── Call target.module::function(args)                        │
    │      with multisig address as sender (admin)                   │
    │                                                                 │
    │  Result:                                                        │
    │  └── Trading paused on DEX                                     │
    └─────────────────────────────────────────────────────────────────┘


NO TIMELOCK (unlike DAO):
═════════════════════════
• Multisig = trusted signers
• Signers review before approving
• Faster execution for operational needs
• Optional: Add timelock for extra security
```

---

## User Flows

### Create Multisig Wallet

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    CREATE MULTISIG WALLET                                │
└─────────────────────────────────────────────────────────────────────────┘

User calls create_wallet()
══════════════════════════

    Transaction:
    ────────────
    Package:  multisig
    Module:   wallet
    Function: create_wallet

    Arguments:
    ├── registry: &mut MultisigRegistry
    ├── name: String                          ← "Team Treasury"
    ├── signers: vector<address>              ← [Alice, Bob, Charlie]
    ├── threshold: u64                        ← 2 (2-of-3)
    ├── creation_fee: Coin<SUI>               ← 5-10 SUI
    └── ctx: &mut TxContext

    Validations:
    ├── threshold > 0
    ├── threshold <= signers.length
    ├── signers.length >= 1
    ├── No duplicate signers
    └── Creation fee sufficient

    Returns:
    ────────
    MultisigWallet (shared object)

    The wallet address (object ID) can now be used as admin
    for other contracts!
```

### Deposit Funds

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        DEPOSIT FUNDS                                     │
└─────────────────────────────────────────────────────────────────────────┘

Anyone can deposit:
═══════════════════

    SUI:
    multisig::deposit_sui(wallet, sui_coin)

    Other tokens:
    multisig::deposit_token<T>(wallet, token_coin)

    No proposal needed - anyone can fund the wallet
```

### Create Proposal

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      CREATE PROPOSAL                                     │
└─────────────────────────────────────────────────────────────────────────┘

Signer calls create_proposal()
══════════════════════════════

    Transaction:
    ────────────
    Package:  multisig
    Module:   proposal
    Function: create_proposal

    Arguments:
    ├── wallet: &mut MultisigWallet
    ├── title: String
    ├── description: String
    ├── action: MultisigAction
    ├── expiry_hours: u64                     ← e.g., 72 (3 days)
    ├── clock: &Clock
    └── ctx: &mut TxContext

    Requirements:
    └── Caller must be a signer

    Auto-approval:
    └── Proposer automatically approves

    Returns:
    ────────
    MultisigProposal (shared object)
```

### Approve Proposal

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      APPROVE PROPOSAL                                    │
└─────────────────────────────────────────────────────────────────────────┘

Signer calls approve()
══════════════════════

    Transaction:
    ────────────
    Package:  multisig
    Module:   proposal
    Function: approve

    Arguments:
    ├── wallet: &MultisigWallet
    ├── proposal: &mut MultisigProposal
    ├── clock: &Clock
    └── ctx: &mut TxContext

    Requirements:
    ├── Caller is a signer
    ├── Hasn't already voted
    ├── Proposal not expired
    └── Proposal is PENDING

    Updates:
    ├── Add caller to approvals
    └── Check if threshold met → update status to APPROVED
```

### Reject Proposal

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       REJECT PROPOSAL                                    │
└─────────────────────────────────────────────────────────────────────────┘

Signer calls reject()
═════════════════════

    Transaction:
    ────────────
    Package:  multisig
    Module:   proposal
    Function: reject

    Arguments:
    ├── wallet: &MultisigWallet
    ├── proposal: &mut MultisigProposal
    ├── clock: &Clock
    └── ctx: &mut TxContext

    Updates:
    ├── Add caller to rejections
    └── If rejections > (signers - threshold):
        └── Mark as REJECTED (can never pass)
```

### Execute Proposal

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      EXECUTE PROPOSAL                                    │
└─────────────────────────────────────────────────────────────────────────┘

Anyone calls execute()
══════════════════════

    Transaction:
    ────────────
    Package:  multisig
    Module:   proposal
    Function: execute

    Arguments:
    ├── wallet: &mut MultisigWallet
    ├── proposal: &mut MultisigProposal
    ├── execution_fee: Coin<SUI>              ← 0.1 SUI
    ├── clock: &Clock
    └── ctx: &mut TxContext

    Requirements:
    ├── Proposal status == APPROVED
    ├── Proposal not expired
    └── Not already executed

    Execution (based on action type):
    ├── TRANSFER_SUI: wallet.sui_balance → recipient
    ├── TRANSFER_TOKEN: wallet.tokens[T] → recipient
    ├── ADD_SIGNER: wallet.signers.push(new)
    ├── REMOVE_SIGNER: wallet.signers.remove(old)
    ├── CHANGE_THRESHOLD: wallet.threshold = new
    └── CUSTOM_TX: call target.function(args)

    Finally:
    ├── Mark proposal as EXECUTED
    ├── Increment wallet.nonce
    └── Emit ProposalExecuted event
```

---

## Signer Management

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      SIGNER MANAGEMENT                                   │
└─────────────────────────────────────────────────────────────────────────┘

All signer changes require proposal approval:

ADD SIGNER
══════════
    Proposal action: ADD_SIGNER
    ├── new_signer: address
    └── new_threshold: Option<u64>

    Example: Add David to 2-of-3, make it 2-of-4
    {
        action_type: ADD_SIGNER,
        new_signer: 0xDAVID,
        new_threshold: None  // Keep threshold at 2
    }

    Validation:
    ├── New signer not already in list
    ├── New threshold (if provided) <= new signer count
    └── Requires current threshold approvals


REMOVE SIGNER
═════════════
    Proposal action: REMOVE_SIGNER
    ├── signer_to_remove: address
    └── new_threshold: Option<u64>

    Example: Remove Charlie from 2-of-3, make it 2-of-2
    {
        action_type: REMOVE_SIGNER,
        signer_to_remove: 0xCHARLIE,
        new_threshold: 2
    }

    Validation:
    ├── Signer exists in list
    ├── Remaining signers >= 1
    ├── New threshold <= remaining signers
    └── Can't remove below threshold


CHANGE THRESHOLD
════════════════
    Proposal action: CHANGE_THRESHOLD
    └── new_threshold: u64

    Example: Change 2-of-3 to 3-of-3
    {
        action_type: CHANGE_THRESHOLD,
        new_threshold: 3
    }

    Validation:
    ├── New threshold > 0
    └── New threshold <= current signer count


ROTATION EXAMPLE
════════════════
    Scenario: Replace Alice with Eve in 2-of-3

    Proposal 1: Add Eve (becomes 2-of-4)
    Proposal 2: Remove Alice (becomes 2-of-3 with Bob, Charlie, Eve)

    Or in one batch if supported:
    {
        actions: [
            { ADD_SIGNER, new_signer: Eve },
            { REMOVE_SIGNER, signer_to_remove: Alice }
        ]
    }
```

---

## Events

```move
module multisig::events {

    struct WalletCreated has copy, drop {
        wallet_id: ID,
        name: String,
        signers: vector<address>,
        threshold: u64,
        creator: address,
        creation_fee: u64,
        timestamp: u64,
    }

    struct ProposalCreated has copy, drop {
        wallet_id: ID,
        proposal_id: ID,
        proposal_number: u64,
        proposer: address,
        title: String,
        action_type: String,
        expires_at: u64,
        timestamp: u64,
    }

    struct ProposalApproved has copy, drop {
        wallet_id: ID,
        proposal_id: ID,
        signer: address,
        approvals_count: u64,
        threshold: u64,
        threshold_met: bool,
        timestamp: u64,
    }

    struct ProposalRejected has copy, drop {
        wallet_id: ID,
        proposal_id: ID,
        signer: address,
        rejections_count: u64,
        timestamp: u64,
    }

    struct ProposalExecuted has copy, drop {
        wallet_id: ID,
        proposal_id: ID,
        executor: address,
        action_type: String,
        success: bool,
        timestamp: u64,
    }

    struct SignerAdded has copy, drop {
        wallet_id: ID,
        new_signer: address,
        new_threshold: u64,
        total_signers: u64,
        timestamp: u64,
    }

    struct SignerRemoved has copy, drop {
        wallet_id: ID,
        removed_signer: address,
        new_threshold: u64,
        total_signers: u64,
        timestamp: u64,
    }

    struct FundsDeposited has copy, drop {
        wallet_id: ID,
        token_type: TypeName,
        amount: u64,
        depositor: address,
        timestamp: u64,
    }

    struct FundsTransferred has copy, drop {
        wallet_id: ID,
        proposal_id: ID,
        token_type: TypeName,
        amount: u64,
        recipient: address,
        timestamp: u64,
    }

    struct CustomTxExecuted has copy, drop {
        wallet_id: ID,
        proposal_id: ID,
        target: address,
        module_name: String,
        function_name: String,
        success: bool,
        timestamp: u64,
    }
}
```

---

## Security

### Access Control

| Function | Who Can Call | Requirements |
|----------|--------------|--------------|
| `create_wallet` | Anyone | Pays creation fee |
| `deposit_sui` | Anyone | Has SUI |
| `deposit_token` | Anyone | Has tokens |
| `create_proposal` | Signers only | Is wallet signer |
| `approve` | Signers only | Is signer, hasn't voted |
| `reject` | Signers only | Is signer, hasn't voted |
| `execute` | Anyone | Threshold met, not expired |
| `cancel_proposal` | Proposer | Proposal not executed |

### Validations

```move
// On create_wallet
assert!(threshold > 0, EInvalidThreshold);
assert!(threshold <= vector::length(&signers), EThresholdTooHigh);
assert!(vector::length(&signers) >= 1, ENoSigners);
assert!(!has_duplicates(&signers), EDuplicateSigners);

// On create_proposal
assert!(is_signer(wallet, sender), ENotSigner);
assert!(!wallet.paused, EWalletPaused);

// On approve
assert!(is_signer(wallet, sender), ENotSigner);
assert!(!has_voted(proposal, sender), EAlreadyVoted);
assert!(proposal.status == PENDING, EInvalidStatus);
assert!(clock::timestamp_ms(clock) < proposal.expires_at, EProposalExpired);

// On execute
assert!(proposal.status == APPROVED, ENotApproved);
assert!(clock::timestamp_ms(clock) < proposal.expires_at, EProposalExpired);

// On signer changes
assert!(new_threshold <= new_signer_count, EInvalidThreshold);
assert!(new_signer_count >= 1, ECannotRemoveAllSigners);
```

### Replay Protection

```move
struct MultisigWallet has key {
    // ...
    nonce: u64,  // Incremented on each execution
}

struct MultisigProposal has key {
    // ...
    wallet_nonce: u64,  // Nonce when proposal created
}

// On execute
assert!(proposal.wallet_nonce == wallet.nonce, EInvalidNonce);
wallet.nonce = wallet.nonce + 1;
```

---

## Configuration

```move
struct MultisigRegistry has key {
    id: UID,

    // Platform fees
    creation_fee: u64,           // SUI for wallet creation
    execution_fee: u64,          // SUI per execution

    // Limits
    max_signers: u64,            // Max signers per wallet (e.g., 20)
    default_expiry_hours: u64,   // Default proposal expiry
    max_expiry_hours: u64,       // Max proposal expiry

    // Admin
    treasury: address,           // Where fees go
    paused: bool,                // Global pause
}
```

---

## Use Cases

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       COMMON USE CASES                                   │
└─────────────────────────────────────────────────────────────────────────┘

1. TEAM TREASURY
════════════════
   • 2-of-3 team members
   • Hold project funds
   • Approve expenditures together

2. PROTOCOL ADMIN
═════════════════
   • Multisig as admin of protocol contracts
   • Custom TX to update parameters
   • Emergency pause capability

3. INVESTMENT CLUB
══════════════════
   • 3-of-5 members
   • Pool funds for investments
   • Vote on trades

4. GRANT COMMITTEE
══════════════════
   • Committee members as signers
   • Approve grant distributions
   • Transparent on-chain record

5. ESCROW
═════════
   • Buyer + Seller + Arbitrator (2-of-3)
   • Release funds on agreement
   • Arbitrator breaks deadlocks
```

---

## Actual Lines of Code

| File | Lines | Description |
|------|-------|-------------|
| registry.move | ~310 | Platform config, AdminCap, fees |
| wallet.move | ~347 | Wallet creation, signer management |
| vault.move | ~176 | Generic multi-coin Bag storage |
| proposal.move | ~826 | Proposal lifecycle, custom TX auth |
| events.move | ~317 | All event definitions |
| **Total Sources** | **~1,976** | |
| **Tests** | **~2,586** | 33 tests |
| **Grand Total** | **~4,562** | |

---

## Status

| Component | Status | Notes |
|-----------|--------|-------|
| Registry | ✅ DONE | Platform config, AdminCap |
| Wallet | ✅ DONE | N-of-M creation, signer management |
| Vault | ✅ DONE | Generic Coin<T> with Bag |
| Proposal | ✅ DONE | Full lifecycle + custom TX |
| Events | ✅ DONE | All events defined |
| Tests | ✅ DONE | 33 tests passing |
| Audit | Not started | |

---

## Implementation Notes

### Key Differences from Spec

1. **No separate custom_tx.move** - Custom TX logic integrated into proposal.move
2. **Added vault.move** - Dedicated module for multi-coin storage
3. **Added registry.move** - Platform configuration and fees
4. **Hot potato auth** - MultisigAuth struct with no abilities for secure custom TX
5. **Generic Coin<T>** - All tokens (including SUI) handled uniformly

### Custom TX Flow (Implemented)

```
1. propose_custom_tx() → Creates proposal with target_id + function_name
2. approve() → Signers approve until threshold
3. execute_custom_tx() → Returns MultisigAuth hot potato
4. External contract consumes auth via consume_auth() or consume_auth_for_target()
5. Auth verified: wallet_id, proposal_id, target_id match
```

### Test Coverage

- Wallet creation (1-of-1, 2-of-3, validation errors)
- Multi-coin vault (SUI + 3 custom tokens)
- Proposal lifecycle (create, approve, reject, cancel, expire)
- Token transfers (all types via generic proposal)
- Custom TX with strict data verification
- Signer management (add, remove, auto-adjust threshold)
