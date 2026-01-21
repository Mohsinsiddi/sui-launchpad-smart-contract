# DAO Service - Detailed Specification

## Overview

DAO as a Service (DaaS) - A standalone product that allows any token project to create decentralized governance for their community. Token holders can create proposals, vote, and execute on-chain actions including custom contract calls.

---

## Business Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      DAO AS A SERVICE (B2B)                              │
└─────────────────────────────────────────────────────────────────────────┘

WHO USES IT:
════════════
• Graduated launchpad tokens
• External token projects
• Any Sui token wanting governance

REVENUE MODEL:
══════════════
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   1. SETUP FEE (One-time)                                               │
│      └── 20-100 SUI per DAO                                             │
│      └── Paid when creating governance                                  │
│                                                                         │
│   2. PROPOSAL FEE (Per proposal)                                        │
│      └── 1 SUI per proposal                                             │
│      └── Prevents spam, generates revenue                               │
│                                                                         │
│   3. EXECUTION FEE (Per execution)                                      │
│      └── 0.1 SUI per executed proposal                                  │
│      └── Paid by executor                                               │
│                                                                         │
│   4. TREASURY SETUP (Optional)                                          │
│      └── +10 SUI for treasury integration                               │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Module Structure

```
sui-dao/
├── Move.toml
└── sources/
    │
    ├── core/                    # Self-contained utilities
    │   ├── math.move           # Voting math, quorum calculations
    │   └── access.move         # AdminCap, DAOAdminCap
    │
    ├── factory.move            # DAO creation & registry
    ├── governance.move         # Main governance logic
    ├── proposal.move           # Proposal management
    ├── custom_tx.move          # Custom transaction execution
    ├── timelock.move           # Execution delay
    ├── treasury.move           # DAO treasury management
    └── events.move             # All events
```

---

## Core Concepts

### Governance Instance

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       GOVERNANCE INSTANCE                                │
└─────────────────────────────────────────────────────────────────────────┘

Governance<T>
═════════════

┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   Configuration:                                                        │
│   ├── token_type: TypeName              (governance token)             │
│   ├── min_proposal_threshold: u64       (tokens to create proposal)    │
│   ├── quorum_votes: u64                 (min votes to pass)            │
│   ├── voting_period: u64                (how long voting lasts)        │
│   ├── timelock_delay: u64               (delay before execution)       │
│   └── dao_admin: address                (can update config)            │
│                                                                         │
│   State:                                                                │
│   ├── proposal_count: u64               (total proposals created)      │
│   ├── active_proposals: VecSet<ID>      (currently voting)             │
│   └── executed_proposals: u64           (total executed)               │
│                                                                         │
│   Voting Power Source (choose one):                                     │
│   ├── TOKEN_BALANCE: Snapshot of token balance                         │
│   ├── STAKING_POSITION: Use staked amount from staking service         │
│   └── CUSTOM: Custom voting power calculation                          │
│                                                                         │
│   Optional Features:                                                    │
│   ├── treasury: Option<ID>              (linked treasury)              │
│   ├── allowed_targets: VecSet<address>  (whitelist for custom TX)      │
│   └── blocked_functions: VecSet<vector<u8>>  (blacklist functions)     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Proposal

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           PROPOSAL                                       │
└─────────────────────────────────────────────────────────────────────────┘

Proposal
════════

┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   Basic Info:                                                           │
│   ├── id: ID                                                           │
│   ├── governance_id: ID                 (parent governance)            │
│   ├── proposer: address                 (who created)                  │
│   ├── title: String                     (short title)                  │
│   ├── description: String               (detailed description)         │
│   ├── discussion_url: Option<String>    (forum link)                   │
│   └── proposal_number: u64              (sequential number)            │
│                                                                         │
│   Timing:                                                               │
│   ├── created_at: u64                   (creation timestamp)           │
│   ├── voting_starts: u64                (when voting begins)           │
│   ├── voting_ends: u64                  (when voting ends)             │
│   └── execute_after: u64                (timelock expiry)              │
│                                                                         │
│   Votes:                                                                │
│   ├── for_votes: u64                    (votes in favor)               │
│   ├── against_votes: u64                (votes against)                │
│   ├── abstain_votes: u64                (abstentions)                  │
│   └── voters: Table<address, VoteRecord> (who voted what)              │
│                                                                         │
│   Status:                                                               │
│   └── status: ProposalStatus                                           │
│       ├── PENDING      (created, waiting for voting to start)          │
│       ├── ACTIVE       (voting in progress)                            │
│       ├── SUCCEEDED    (passed, in timelock)                           │
│       ├── DEFEATED     (failed to reach quorum or majority)            │
│       ├── EXECUTED     (successfully executed)                         │
│       ├── CANCELLED    (cancelled by proposer or admin)                │
│       └── EXPIRED      (passed timelock but not executed)              │
│                                                                         │
│   Actions (what to execute):                                            │
│   └── actions: vector<ProposalAction>                                  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Proposal Actions

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       PROPOSAL ACTIONS                                   │
└─────────────────────────────────────────────────────────────────────────┘

ProposalAction (enum)
═════════════════════

1. TREASURY_TRANSFER
   └── Send tokens from DAO treasury to address
   └── Fields: recipient, amount, token_type

2. CONFIG_UPDATE
   └── Update governance parameters
   └── Fields: parameter_name, new_value

3. CUSTOM_TX
   └── Call any contract function where DAO is admin
   └── Fields: target, module, function, type_args, args

4. TEXT_PROPOSAL
   └── Signal vote, no on-chain action
   └── Fields: none (just description)

5. ADD_TO_ALLOWLIST
   └── Add contract to allowed targets
   └── Fields: contract_address

6. REMOVE_FROM_ALLOWLIST
   └── Remove contract from allowed targets
   └── Fields: contract_address


Example Actions:
════════════════

TREASURY_TRANSFER:
{
    action_type: TREASURY_TRANSFER,
    recipient: 0xALICE...,
    amount: 10000,
    token_type: "0xPEPE::pepe::PEPE"
}

CUSTOM_TX:
{
    action_type: CUSTOM_TX,
    target: 0xMY_CONTRACT...,
    module: "config",
    function: "update_fee",
    type_args: [],
    args: [bcs::to_bytes(&500u64)]  // new fee = 5%
}
```

---

## Custom Transaction Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    CUSTOM TX FLOW (Key Feature!)                         │
└─────────────────────────────────────────────────────────────────────────┘

This allows the DAO to control any contract where DAO address is admin.

STEP 1: PROPOSE CUSTOM TX
═════════════════════════

    Proposer creates proposal with CUSTOM_TX action:

    ┌─────────────────────────────────────────────────────────────────┐
    │  Proposal: "Reduce platform fee from 5% to 3%"                  │
    │                                                                 │
    │  Action:                                                        │
    │  ├── target: 0xMY_PROTOCOL...                                  │
    │  ├── module: config                                            │
    │  ├── function: update_platform_fee                             │
    │  ├── type_args: []                                             │
    │  └── args: [300]  // 3% in basis points                        │
    └─────────────────────────────────────────────────────────────────┘


STEP 2: SIMULATE TX (Off-chain)
═══════════════════════════════

    Before voting, anyone can simulate the TX:

    ┌─────────────────────────────────────────────────────────────────┐
    │  Simulation Result:                                             │
    │  ├── Status: SUCCESS                                           │
    │  ├── Gas estimate: 1,234,567                                   │
    │  │                                                              │
    │  │  State Changes:                                              │
    │  │  ├── config.platform_fee_bps: 500 → 300                     │
    │  │  └── (no other changes)                                     │
    │  │                                                              │
    │  └── Warnings: None                                            │
    └─────────────────────────────────────────────────────────────────┘

    Simulation uses Sui's devInspectTransactionBlock


STEP 3: VOTING
══════════════

    Token holders vote based on simulation results:

    ├── See exactly what will change
    ├── No surprises
    └── Informed decision


STEP 4: TIMELOCK
════════════════

    If proposal passes:
    └── Wait for timelock period (e.g., 24-48 hours)
    └── Allows users to exit if they disagree


STEP 5: EXECUTE
═══════════════

    After timelock expires, anyone can execute:

    ┌─────────────────────────────────────────────────────────────────┐
    │  dao::execute_proposal(proposal_id)                             │
    │                                                                 │
    │  Internally calls:                                              │
    │  ────────────────                                               │
    │  1. Verify proposal passed and timelock expired                 │
    │  2. For each action in proposal.actions:                        │
    │     └── If CUSTOM_TX:                                          │
    │         └── Call target.module::function(args)                 │
    │         └── DAO address is tx sender (has admin rights)        │
    │  3. Mark proposal as EXECUTED                                   │
    │  4. Emit ProposalExecuted event                                 │
    └─────────────────────────────────────────────────────────────────┘


SECURITY CHECKS:
════════════════

    Before executing custom TX:
    ├── Proposal must be SUCCEEDED status
    ├── Timelock must be expired
    ├── Target must be in allowed_targets (if allowlist enabled)
    ├── Function must not be in blocked_functions
    └── Execution must succeed (reverts entire proposal if any action fails)
```

---

## Voting Power

### Option 1: Token Balance Snapshot

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    TOKEN BALANCE VOTING                                  │
└─────────────────────────────────────────────────────────────────────────┘

Voting power = Token balance at snapshot time

Snapshot taken when:
• Proposal created (snapshot block recorded)
• Prevents flash-loan attacks

Implementation:
═══════════════
    On proposal creation:
        proposal.snapshot_timestamp = clock::timestamp_ms(clock)

    On vote:
        // User must prove they had tokens at snapshot
        // Using Sui's object versioning or checkpoint data
        voting_power = get_balance_at_checkpoint(
            voter,
            token_type,
            proposal.snapshot_timestamp
        )

Pros:
├── Simple to understand
├── Fair (snapshot prevents manipulation)
└── Standard approach

Cons:
├── Tokens held = votes (no commitment)
└── Whales dominate
```

### Option 2: Staking Position Integration

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    STAKING-BASED VOTING                                  │
└─────────────────────────────────────────────────────────────────────────┘

Voting power = Staked amount in staking service

Benefits:
═════════
• Rewards long-term holders
• Stakers are committed (can't quickly exit)
• Aligns governance with protocol success

Implementation:
═══════════════
    Governance stores reference to staking pool:
        governance.staking_pool_id = Option<ID>

    On vote:
        if governance.staking_pool_id.is_some():
            voting_power = staking::get_staked_amount(
                voter_position_id,
                governance.staking_pool_id
            )
        else:
            voting_power = token_balance

    // User passes their StakingPosition as proof
    dao::vote_with_stake(
        proposal_id,
        staking_position: &StakingPosition,
        vote: bool
    )
```

### Option 3: Hybrid (Token + Staking Multiplier)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    HYBRID VOTING                                         │
└─────────────────────────────────────────────────────────────────────────┘

voting_power = token_balance + (staked_amount * multiplier)

Example with 2x multiplier:
═══════════════════════════
User has:
├── 10,000 tokens in wallet
└── 5,000 tokens staked

voting_power = 10,000 + (5,000 * 2) = 20,000 votes

Benefits:
├── Rewards stakers but includes all holders
├── Configurable multiplier
└── More inclusive
```

---

## Treasury

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         DAO TREASURY                                     │
└─────────────────────────────────────────────────────────────────────────┘

Optional treasury controlled by governance:

DAOTreasury<T>
══════════════

┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   Treasury holds:                                                       │
│   ├── governance_token: Balance<T>        (native token)               │
│   ├── sui: Balance<SUI>                   (SUI reserves)               │
│   └── other_tokens: Bag                   (any other tokens)           │
│                                                                         │
│   Who can access:                                                       │
│   └── ONLY through passed governance proposals                         │
│                                                                         │
│   Operations (via proposal):                                            │
│   ├── transfer(): Send tokens to address                               │
│   ├── add_liquidity(): Add to DEX pool                                │
│   ├── stake(): Stake tokens in staking pool                           │
│   └── custom_call(): Any contract call                                 │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

Fund Treasury:
══════════════
Anyone can deposit tokens:
    dao::deposit_to_treasury<T>(treasury, tokens)

This is how projects fund grants, development, etc.
```

---

## User Flows

### Create DAO

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CREATE DAO                                       │
└─────────────────────────────────────────────────────────────────────────┘

Project calls create_governance()
═════════════════════════════════

    Transaction:
    ────────────
    Package:  dao
    Module:   factory
    Function: create_governance<T>

    Arguments:
    ├── registry: &mut DAORegistry
    ├── setup_fee: Coin<SUI>                  ← 20-100 SUI
    ├── min_proposal_threshold: u64           ← tokens to propose
    ├── quorum_votes: u64                     ← min votes to pass
    ├── voting_period_ms: u64                 ← e.g., 3 days
    ├── timelock_delay_ms: u64                ← e.g., 24 hours
    ├── voting_power_source: u8               ← 0=balance, 1=staking
    ├── staking_pool_id: Option<ID>           ← if using staking
    ├── create_treasury: bool                 ← whether to create treasury
    └── ctx: &mut TxContext

    Returns:
    ────────
    ├── Governance<T> object (shared)
    ├── DAOAdminCap (to creator)
    └── DAOTreasury<T> (if requested)
```

### Create Proposal

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      CREATE PROPOSAL                                     │
└─────────────────────────────────────────────────────────────────────────┘

Token holder calls create_proposal()
════════════════════════════════════

    Requirements:
    ├── Must hold >= min_proposal_threshold tokens
    └── Must pay proposal fee (1 SUI)

    Transaction:
    ────────────
    Package:  dao
    Module:   governance
    Function: create_proposal<T>

    Arguments:
    ├── governance: &mut Governance<T>
    ├── title: String
    ├── description: String
    ├── discussion_url: Option<String>
    ├── actions: vector<ProposalAction>
    ├── proposal_fee: Coin<SUI>
    ├── voting_power_proof: ...              ← Proof of token ownership
    └── ctx: &mut TxContext

    Returns:
    ────────
    Proposal object (shared)

    Timeline started:
    ├── Now: PENDING (optional delay before voting)
    ├── +0-N hours: ACTIVE (voting open)
    ├── +voting_period: Voting ends
    └── Result: SUCCEEDED or DEFEATED
```

### Vote

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            VOTE                                          │
└─────────────────────────────────────────────────────────────────────────┘

Token holder calls vote()
═════════════════════════

    Transaction:
    ────────────
    Package:  dao
    Module:   governance
    Function: vote<T>

    Arguments:
    ├── governance: &Governance<T>
    ├── proposal: &mut Proposal
    ├── support: u8                           ← 0=against, 1=for, 2=abstain
    ├── voting_power_proof: ...               ← Proof of voting power
    ├── clock: &Clock
    └── ctx: &mut TxContext

    Checks:
    ├── Proposal is ACTIVE
    ├── User hasn't voted already
    ├── User has voting power > 0
    └── Voting period not ended

    Updates:
    ├── proposal.for_votes or against_votes or abstain_votes
    └── proposal.voters[sender] = VoteRecord

    Emit: Voted event
```

### Execute Proposal

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       EXECUTE PROPOSAL                                   │
└─────────────────────────────────────────────────────────────────────────┘

Anyone calls execute_proposal() after timelock
══════════════════════════════════════════════

    Transaction:
    ────────────
    Package:  dao
    Module:   governance
    Function: execute_proposal

    Arguments:
    ├── governance: &mut Governance<T>
    ├── proposal: &mut Proposal
    ├── treasury: Option<&mut DAOTreasury<T>>  ← If treasury action
    ├── execution_fee: Coin<SUI>               ← 0.1 SUI
    ├── clock: &Clock
    ├── ... (additional args based on actions)
    └── ctx: &mut TxContext

    Checks:
    ├── Proposal status == SUCCEEDED
    ├── Timelock expired (clock >= execute_after)
    └── Not already executed

    For each action:
    ├── TREASURY_TRANSFER: Transfer from treasury
    ├── CONFIG_UPDATE: Update governance config
    ├── CUSTOM_TX: Execute contract call
    └── ... (other action types)

    Finally:
    ├── Mark proposal as EXECUTED
    └── Emit ProposalExecuted event
```

---

## Events

```move
module dao::events {

    struct GovernanceCreated has copy, drop {
        governance_id: ID,
        token_type: TypeName,
        min_proposal_threshold: u64,
        quorum_votes: u64,
        voting_period: u64,
        timelock_delay: u64,
        creator: address,
        has_treasury: bool,
        timestamp: u64,
    }

    struct ProposalCreated has copy, drop {
        governance_id: ID,
        proposal_id: ID,
        proposal_number: u64,
        proposer: address,
        title: String,
        actions_count: u64,
        voting_starts: u64,
        voting_ends: u64,
        timestamp: u64,
    }

    struct Voted has copy, drop {
        governance_id: ID,
        proposal_id: ID,
        voter: address,
        support: u8,
        voting_power: u64,
        for_votes: u64,
        against_votes: u64,
        timestamp: u64,
    }

    struct ProposalFinalized has copy, drop {
        governance_id: ID,
        proposal_id: ID,
        status: u8,
        for_votes: u64,
        against_votes: u64,
        quorum_reached: bool,
        timestamp: u64,
    }

    struct ProposalExecuted has copy, drop {
        governance_id: ID,
        proposal_id: ID,
        executor: address,
        actions_executed: u64,
        timestamp: u64,
    }

    struct TreasuryAction has copy, drop {
        governance_id: ID,
        treasury_id: ID,
        action_type: String,
        amount: u64,
        recipient: Option<address>,
        timestamp: u64,
    }

    struct CustomTxExecuted has copy, drop {
        governance_id: ID,
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
| `create_governance` | Anyone | Pays setup fee |
| `create_proposal` | Token holders | Min threshold + proposal fee |
| `vote` | Token holders | Has voting power, proposal active |
| `finalize_proposal` | Anyone | Voting period ended |
| `execute_proposal` | Anyone | Passed + timelock expired |
| `cancel_proposal` | Proposer or Admin | Proposal not executed |
| `update_config` | DAO Admin | DAOAdminCap |
| `emergency_cancel` | Platform Admin | AdminCap (extreme cases) |

### Custom TX Security

```move
module dao::custom_tx {

    /// Validate custom TX before execution
    public(package) fun validate_custom_tx(
        gov: &Governance,
        action: &CustomTxAction,
    ) {
        // 1. Check target is allowed (if allowlist enabled)
        if (!vec_set::is_empty(&gov.allowed_targets)) {
            assert!(
                vec_set::contains(&gov.allowed_targets, &action.target),
                ETargetNotAllowed
            );
        };

        // 2. Check function not blocked
        assert!(
            !vec_set::contains(&gov.blocked_functions, &action.function_name),
            EFunctionBlocked
        );

        // 3. Validate args are properly encoded
        // (BCS validation)
    }

    /// Execute custom TX
    /// ONLY callable internally after proposal passed
    public(package) fun execute_custom_tx(
        gov: &Governance,
        action: &CustomTxAction,
        ctx: &mut TxContext
    ) {
        validate_custom_tx(gov, action);

        // Build and execute dynamic call
        // The DAO's address is the sender, so it has admin rights
        // on contracts where DAO is set as admin

        // NOTE: In Move, we can't do fully dynamic calls
        // Instead, we need adapters for each supported protocol
        // OR use PTBs (Programmable Transaction Blocks) with
        // pre-approved function signatures
    }
}
```

### Timelock Protection

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       TIMELOCK PROTECTION                                │
└─────────────────────────────────────────────────────────────────────────┘

Why timelock?
═════════════
• Gives users time to react to controversial proposals
• Can exit positions before harmful changes
• Prevents flash-governance attacks

Timeline:
═════════
    Proposal Created
          │
          ▼
    ┌─────────────┐
    │   VOTING    │ ← 3-7 days typically
    │   PERIOD    │
    └─────────────┘
          │
          ▼ (if passed)
    ┌─────────────┐
    │  TIMELOCK   │ ← 24-48 hours typically
    │   PERIOD    │
    │             │   Users can:
    │             │   • Unstake tokens
    │             │   • Sell tokens
    │             │   • Exit positions
    └─────────────┘
          │
          ▼
    ┌─────────────┐
    │  EXECUTION  │ ← Anyone can trigger
    │   WINDOW    │
    └─────────────┘

Configurable delays:
════════════════════
• Minimum timelock: 12 hours
• Maximum timelock: 7 days
• Default: 24 hours
```

---

## Configuration

```move
struct DAORegistry has key {
    id: UID,

    // Platform fees
    setup_fee: u64,              // SUI for DAO creation
    treasury_setup_fee: u64,     // Additional for treasury
    proposal_fee: u64,           // SUI per proposal
    execution_fee: u64,          // SUI per execution

    // Limits
    min_voting_period: u64,      // Min voting duration
    max_voting_period: u64,      // Max voting duration
    min_timelock: u64,           // Min delay before execution
    max_timelock: u64,           // Max delay

    // Admin
    treasury: address,           // Platform treasury
    paused: bool,                // Global pause
}

struct Governance<phantom T> has key {
    id: UID,

    // Voting parameters
    min_proposal_threshold: u64, // Tokens to propose
    quorum_votes: u64,           // Min votes to pass
    voting_period: u64,          // Voting duration (ms)
    timelock_delay: u64,         // Execution delay (ms)

    // Voting power
    voting_power_source: u8,     // 0=balance, 1=staking, 2=hybrid
    staking_pool_id: Option<ID>, // If using staking

    // Custom TX security
    allowed_targets: VecSet<address>,
    blocked_functions: VecSet<vector<u8>>,

    // Treasury
    treasury_id: Option<ID>,

    // State
    proposal_count: u64,
    active_proposals: VecSet<ID>,

    // Admin
    dao_admin: address,
    paused: bool,
}
```

---

## Estimated Lines of Code

| File | Lines | Description |
|------|-------|-------------|
| core/math.move | ~60 | Voting math, quorum |
| core/access.move | ~70 | AdminCap, DAOAdminCap |
| factory.move | ~150 | DAO creation, registry |
| governance.move | ~400 | Main governance logic |
| proposal.move | ~250 | Proposal management |
| custom_tx.move | ~200 | Custom TX execution |
| timelock.move | ~100 | Timelock logic |
| treasury.move | ~180 | Treasury management |
| events.move | ~100 | Event definitions |
| **Total** | **~1,510** | |

---

## Status

| Component | Status | Notes |
|-----------|--------|-------|
| Core utilities | Not started | |
| Factory | Not started | |
| Governance | Not started | |
| Proposal | Not started | |
| Custom TX | Not started | |
| Timelock | Not started | |
| Treasury | Not started | |
| Events | Not started | |
| Tests | Not started | |
| Audit | Not started | |
