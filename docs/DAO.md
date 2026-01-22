# sui_dao - DAO Governance System

A comprehensive, production-ready DAO governance system for the Sui blockchain with dual voting modes, council powers, delegation, and multi-token treasury.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Governance Modes](#governance-modes)
4. [Complete Lifecycle Flow](#complete-lifecycle-flow)
5. [Council System](#council-system)
6. [Guardian System](#guardian-system)
7. [Delegation](#delegation)
8. [Treasury](#treasury)
9. [Proposal Actions](#proposal-actions)
10. [Configuration](#configuration)
11. [Error Codes](#error-codes)
12. [Integration Guide](#integration-guide)

---

## Overview

sui_dao provides a flexible, secure governance system that supports:

- **Dual Voting Modes**: Token staking OR NFT-based voting
- **Council Powers**: Fast-track (majority), veto, emergency proposals
- **Guardian System**: Emergency pause capability for security
- **Delegation**: Delegate voting power to trusted addresses
- **Multi-Token Treasury**: Hold any Coin<T> including SUI
- **Hot Potato Auth**: Secure custom transaction execution

### Key Statistics

| Metric | Value |
|--------|-------|
| Total Lines | ~5,200 |
| Test Count | 58 |
| Module Count | 11 |
| Event Types | 45+ |

### Business Model

```
WHO USES IT:
- Graduated launchpad tokens
- External token projects
- Any Sui token wanting governance

REVENUE MODEL:
- Setup Fee: 50 SUI per DAO (one-time)
- Proposal Fee: 1 SUI per proposal
- Execution Fee: 0.1 SUI per execution
- Treasury Setup: +10 SUI (optional)
```

---

## Architecture

```
                              sui_dao Package

┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   registry  │    │  governance │    │   proposal  │    │   treasury  │
│             │    │             │    │             │    │             │
│ - Platform  │───>│ - Config    │───>│ - Lifecycle │<───│ - SUI       │
│   Config    │    │ - Council   │    │ - Voting    │    │ - Tokens    │
│ - Fees      │    │ - Guardian  │    │ - Actions   │    │ - Bag       │
│ - Registry  │    │ - Modes     │    │ - DAOAuth   │    │             │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                          │                  │
                          │                  │
            ┌─────────────┴─────────────┐    │
            │                           │    │
            v                           v    v
    ┌─────────────┐            ┌─────────────┐    ┌─────────────┐
    │   voting    │            │   council   │    │  delegation │
    │             │            │             │    │             │
    │ - Stake     │            │ - Fast-Track│    │ - Delegate  │
    │ - NFT Vault │            │ - Veto      │    │ - Transfer  │
    │             │            │ - Emergency │    │ - Revoke    │
    └─────────────┘            └─────────────┘    └─────────────┘
            │
            v
    ┌─────────────┐            ┌─────────────┐
    │  nft_vault  │            │   guardian  │
    │             │            │             │
    │ - Lock NFTs │            │ - Emergency │
    │ - Voting    │            │   Pause     │
    │ - Unlock    │            │             │
    └─────────────┘            └─────────────┘

External Dependency:
┌─────────────┐
│ sui_staking │
│             │
│ - Positions │<── Staking mode uses positions for voting power
│ - Pools     │
└─────────────┘
```

### Module Responsibilities

| Module | Responsibility |
|--------|----------------|
| `registry.move` | Platform admin, fees, DAO registration |
| `governance.move` | Governance config, council, guardian, modes |
| `proposal.move` | Proposal lifecycle, voting, actions, DAOAuth |
| `voting.move` | Vote with staking positions or NFT vaults |
| `nft_vault.move` | Lock NFTs for voting power |
| `council.move` | Fast-track, veto, emergency proposals |
| `guardian.move` | Emergency pause capability |
| `delegation.move` | Delegate voting power |
| `treasury.move` | Multi-token DAO treasury |
| `events.move` | Event definitions |
| `core/*.move` | Errors, math, access control |

---

## Governance Modes

### Mode 1: Staking-Based Governance

Uses `sui_staking` positions for voting power. Voting power = staked token amount.

```
                    STAKING MODE FLOW

User Stakes Tokens                     User Votes on Proposal
        │                                      │
        v                                      v
┌───────────────┐                     ┌───────────────┐
│ sui_staking   │                     │ sui_dao       │
│ Pool          │                     │ Governance    │
└───────────────┘                     └───────────────┘
        │                                      │
        v                                      v
┌───────────────┐                     ┌───────────────┐
│ Staking       │─────────────────────│ voting::      │
│ Position NFT  │   Position passed   │ vote_with_    │
│               │   as reference      │ stake()       │
│ staked: 1000  │                     │               │
└───────────────┘                     └───────────────┘
                                              │
                                              v
                                      Voting Power = 1000
```

**Creation:**
```move
public fun create_staking_governance(
    registry: &mut DAORegistry,
    name: String,
    description_hash: String,
    staking_pool_id: ID,         // Link to sui_staking pool
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): (Governance, DAOAdminCap)
```

### Mode 2: NFT-Based Governance

Lock NFTs in a vault for voting power. 1 NFT = 1 vote.

```
                          NFT MODE FLOW

User Creates Vault              User Locks NFTs              User Votes
        │                              │                         │
        v                              v                         v
┌───────────────┐             ┌───────────────┐        ┌───────────────┐
│ nft_vault::   │────────────>│ nft_vault::   │───────>│ nft_vault::   │
│ create_vault  │             │ lock_nft      │        │ vote          │
│ <MyNFT>()     │             │               │        │               │
└───────────────┘             └───────────────┘        └───────────────┘
        │                              │                         │
        v                              v                         v
┌───────────────┐             ┌───────────────┐        ┌───────────────┐
│ NFTVault<     │             │ NFT stored in │        │ Voting Power  │
│   MyNFT>      │             │ vault via DOF │        │ = nft_count   │
│               │             │               │        │ = 5 votes     │
│ nft_count: 0  │             │ nft_count: 5  │        │               │
└───────────────┘             └───────────────┘        └───────────────┘
```

**Creation:**
```move
public fun create_nft_governance<NFT: key + store>(
    registry: &mut DAORegistry,
    name: String,
    description_hash: String,
    quorum_votes: u64,           // e.g., 100 NFTs needed for quorum
    proposal_threshold_nfts: u64, // e.g., 5 NFTs to create proposal
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): (Governance, DAOAdminCap)
```

---

## Complete Lifecycle Flow

### Full Proposal Lifecycle

```
                     PROPOSAL LIFECYCLE

                              Time ───────────────────────────────────────>

┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│   PENDING    │──>│    ACTIVE    │──>│  SUCCEEDED   │──>│   QUEUED     │
│              │   │              │   │      or      │   │  (Timelock)  │
│ Voting Delay │   │ Voting Open  │   │  DEFEATED    │   │              │
│   (1 day)    │   │  (3 days)    │   │              │   │   (2 days)   │
└──────────────┘   └──────────────┘   └──────────────┘   └──────────────┘
                                              │                  │
                                              │                  │
                         ┌────────────────────┘                  │
                         │                                       │
                         v                                       v
                 ┌──────────────┐                        ┌──────────────┐
                 │   DEFEATED   │                        │   EXECUTED   │
                 │              │                        │      or      │
                 │ Quorum not   │                        │   VETOED     │
                 │ met or votes │                        │      or      │
                 │ against      │                        │   EXPIRED    │
                 └──────────────┘                        └──────────────┘

                    ┌──────────────┐
                    │  CANCELLED   │<── Proposer can cancel before voting ends
                    └──────────────┘
```

### Status Constants

| Status | Value | Description |
|--------|-------|-------------|
| PENDING | 0 | Waiting for voting delay |
| ACTIVE | 1 | Voting in progress |
| SUCCEEDED | 2 | Passed, waiting for timelock |
| DEFEATED | 3 | Failed (quorum or votes) |
| QUEUED | 4 | In timelock queue |
| EXECUTED | 5 | Successfully executed |
| CANCELLED | 6 | Cancelled by proposer |
| VETOED | 7 | Vetoed by council |
| EXPIRED | 8 | Execution window passed |

### Step-by-Step Flow

#### 1. Create Proposal

```move
// Build actions
let actions = vector[
    proposal::create_treasury_transfer_action<SUI>(
        treasury_id,
        1_000_000_000, // 1 SUI
        @recipient,
    ),
];

// Create proposal (requires voting power >= threshold)
let proposal = proposal::create_proposal(
    registry,
    governance,
    string::utf8(b"Fund Development"),
    string::utf8(b"ipfs://QmDescription"),
    actions,
    voting_power,  // Must meet proposal_threshold
    payment,       // Proposal fee
    clock,
    ctx,
);
```

#### 2. Vote on Proposal

```move
// Staking mode - vote with position
voting::vote_with_stake<MYTOKEN>(
    governance,
    proposal,
    staking_position,
    proposal::vote_for(),  // 1 = For, 0 = Against, 2 = Abstain
    clock,
    ctx,
);

// NFT mode - vote with vault
nft_vault::vote<MyNFT>(
    governance,
    proposal,
    vault,
    proposal::vote_for(),
    clock,
    ctx,
);
```

#### 3. Finalize Voting

```move
// After voting period ends, finalize to determine outcome
proposal::finalize_voting(
    proposal,
    governance,
    total_voting_power,  // Total supply or total staked
    clock,
);
// Status becomes SUCCEEDED or DEFEATED
```

#### 4. Queue Proposal

```move
// If succeeded, queue for timelock
proposal::queue_proposal(proposal, governance, clock);
// Status becomes QUEUED
```

#### 5. Execute Proposal

```move
// After timelock expires, execute
let auths = proposal::begin_execution(
    registry,
    proposal,
    payment,  // Execution fee
    clock,
    ctx,
);

// Use DAOAuth for treasury transfers
let auth = auths.pop_back();
treasury::withdraw_sui(
    treasury,
    auth,
    amount,
    recipient,
    ctx,
);
```

---

## Council System

The council is a group of trusted addresses with special powers for emergency governance.

### Council Thresholds

| Action | Threshold | Example (5 members) |
|--------|-----------|---------------------|
| Fast-Track | >50% (majority) | 3 votes needed |
| Veto | 1/3 + 1 | 2 votes needed |
| Emergency Proposal | 1 member | Any council member |

### Fast-Track (Majority Voting)

Council members vote to fast-track proposals. When majority is reached, the proposal is automatically fast-tracked with reduced timelock.

```
                     FAST-TRACK FLOW

Council of 5 Members (Threshold = 3)

Member A votes    Member B votes    Member C votes
     │                  │                  │
     v                  v                  v
┌──────────┐      ┌──────────┐      ┌──────────┐
│ Vote 1/3 │─────>│ Vote 2/3 │─────>│ Vote 3/3 │─────> AUTO-EXECUTE
│          │      │          │      │ MAJORITY │      FAST-TRACK
│ Continue │      │ Continue │      │ REACHED  │
└──────────┘      └──────────┘      └──────────┘
                                          │
                                          v
                               ┌─────────────────────┐
                               │ Proposal Fast-      │
                               │ Tracked:            │
                               │ - Skip voting delay │
                               │ - Reduced timelock  │
                               │   (12h vs 2 days)   │
                               └─────────────────────┘
```

```move
// Council member votes to fast-track
council::vote_to_fast_track(
    council_cap,
    governance,
    proposal,
    clock,
);
// Auto-executes when majority reached
```

### Veto Power

Council can veto proposals during the timelock period. Requires 1/3+1 council members.

```move
// Council member votes to veto
council::vote_to_veto(
    council_cap,
    governance,
    proposal,
    clock,
);
// Auto-executes veto when threshold reached
```

### Emergency Proposals

Council can create urgent proposals with reduced timelines:
- **1 hour** voting delay (vs 1 day)
- **1 day** voting period (vs 3 days)
- Auto-fast-tracked with reduced timelock

```move
let proposal = council::create_emergency_proposal(
    council_cap,
    governance,
    string::utf8(b"Emergency: Pause Protocol"),
    string::utf8(b"ipfs://QmEmergency"),
    actions,
    clock,
    ctx,
);
```

---

## Guardian System

The guardian is a trusted address (e.g., security multisig) that can emergency pause the DAO if a vulnerability is discovered.

```
                     GUARDIAN SYSTEM

                    ┌─────────────────┐
                    │   DAO Admin     │
                    │                 │
                    │ - Set guardian  │
                    │ - Remove guard  │
                    │ - Unpause       │
                    └────────┬────────┘
                             │
                             v
                    ┌─────────────────┐
                    │   Guardian      │
                    │  (e.g., 3-of-5  │
                    │   multisig)     │
                    │                 │
                    │ - Emergency     │<── Limited powers
                    │   pause ONLY    │
                    │ - Cannot unpause│
                    │ - Cannot config │
                    └────────┬────────┘
                             │
                             v Vulnerability Found!
                    ┌─────────────────┐
                    │ emergency_pause │
                    │                 │
                    │ DAO is PAUSED   │
                    │ - No proposals  │
                    │ - No voting     │
                    │ - No execution  │
                    └─────────────────┘
                             │
                             v After fix deployed
                    ┌─────────────────┐
                    │ Admin unpause() │
                    │                 │
                    │ DAO resumes     │
                    └─────────────────┘
```

### Guardian Functions

```move
// Admin sets guardian
guardian::set_guardian(admin_cap, governance, @guardian_address, ctx);

// Guardian emergency pauses (only power guardian has)
guardian::emergency_pause(governance, ctx);

// Admin unpauses (guardian cannot unpause)
governance::unpause(admin_cap, governance);

// Admin removes guardian
guardian::remove_guardian(admin_cap, governance, ctx);
```

---

## Delegation

Token holders can delegate their voting power to trusted addresses.

```
                     DELEGATION FLOW

Alice (Delegator)                         Bob (Delegate)
Has 1000 staked tokens                    Active voter

        │
        │ delegate()
        v
┌───────────────────┐
│ DelegationRecord  │
│                   │
│ delegator: Alice  │
│ delegate: Bob     │
│ position_id: 0x.. │
│ voting_power:1000 │
│ lock_until: ...   │
└───────────────────┘
        │
        │ Bob can now vote with Alice's power
        v
┌───────────────────┐
│ delegation::      │
│ vote_as_delegate  │
│                   │
│ Casts 1000 votes  │
│ for Alice         │
└───────────────────┘

Alice can:
- revoke() after lock expires
- transfer_delegation() to another delegate
```

```move
// Create delegation
let record = delegation::delegate<MYTOKEN>(
    governance,
    staking_position,
    @delegate_address,
    lock_until_ms,  // Optional lock period
    clock,
    ctx,
);

// Delegate votes on behalf of delegator
delegation::vote_as_delegate(
    governance,
    proposal,
    delegation_record,
    proposal::vote_for(),
    clock,
    ctx,
);

// Revoke delegation
delegation::revoke(record, clock, ctx);
```

---

## Treasury

Multi-token treasury controlled by governance proposals.

```
                     TREASURY

┌─────────────────────────────────────────┐
│              Treasury                    │
│                                         │
│  sui_balance: 100 SUI                   │<── Direct SUI storage
│                                         │
│  token_balances: Bag {                  │<── Bag for other tokens
│    "0x...::token::USDC": 10,000 USDC    │
│    "0x...::token::DEEP": 50,000 DEEP    │
│    "0x...::mytoken::MY": 1M MY          │
│  }                                      │
│                                         │
└─────────────────────────────────────────┘
         ^                    │
         │                    │
    Anyone can               Only via
    deposit                  DAOAuth
         │                    │
         v                    v
┌──────────────┐      ┌──────────────┐
│ deposit_sui  │      │ withdraw_sui │<── Requires executed
│ deposit<T>   │      │ withdraw<T>  │    proposal with DAOAuth
└──────────────┘      └──────────────┘
```

### Treasury Functions

```move
// Anyone can deposit
treasury::deposit_sui(treasury, coin, ctx);
treasury::deposit<USDC>(treasury, coin, ctx);

// Withdrawal requires DAOAuth from executed proposal
treasury::withdraw_sui(treasury, auth, amount, recipient, ctx);
treasury::withdraw<USDC>(treasury, auth, amount, recipient, ctx);

// View balances
let sui_balance = treasury::sui_balance(treasury);
let usdc_balance = treasury::token_balance<USDC>(treasury);
```

---

## Proposal Actions

### Action Types

| Type | Constant | Description |
|------|----------|-------------|
| Treasury Transfer | 0 | Transfer tokens from treasury |
| Config Update | 1 | Update governance config |
| Custom TX | 2 | Execute custom transaction |
| Text | 3 | Signal/text-only proposal |

### Building Actions

```move
// Treasury transfer
let action1 = proposal::create_treasury_transfer_action<SUI>(
    treasury_id,
    1_000_000_000,  // 1 SUI
    @recipient,
);

// Config update (encoded parameters)
let action2 = proposal::create_config_update_action(
    bcs::to_bytes(&new_quorum_bps),
);

// Custom TX (hot potato auth)
let action3 = proposal::create_custom_tx_action(
    target_contract_id,
    bcs::to_bytes(&custom_params),
);

// Text/signal proposal
let action4 = proposal::create_text_action(
    b"We support proposal XYZ",
);

let actions = vector[action1, action2, action3, action4];
```

### Custom TX with Hot Potato DAOAuth

```move
// Execute proposal returns DAOAuth for each custom TX action
let auths = proposal::begin_execution(registry, proposal, payment, clock, ctx);

// Use auth in target contract
let auth = auths.pop_back();

// Target contract consumes auth
my_contract::do_something(target, auth, params, ctx);

// In target contract:
public fun do_something(target: &mut MyTarget, auth: DAOAuth, ...) {
    // Verify auth is for this target
    proposal::consume_auth(auth, object::id(target));

    // Do the action...
}
```

---

## Configuration

### Default Parameters

| Parameter | Default | Min | Max | Description |
|-----------|---------|-----|-----|-------------|
| Quorum (BPS) | 400 (4%) | - | - | % of total supply needed |
| Voting Delay | 1 day | 1 hour | 7 days | Time before voting starts |
| Voting Period | 3 days | 1 day | 14 days | Duration of voting |
| Timelock | 2 days | 12 hours | 7 days | Delay after passing |
| Fast-Track Timelock | 12 hours | 12 hours | timelock | Reduced timelock |
| Proposal Threshold | 100 tokens | - | - | Tokens to create proposal |
| Approval Threshold | 5000 (50%) | - | 10000 | % of FOR votes needed |

### Updating Config

```move
governance::update_config(
    admin_cap,
    governance,
    quorum_bps,
    quorum_votes,
    voting_delay_ms,
    voting_period_ms,
    timelock_delay_ms,
    proposal_threshold,
    approval_threshold_bps,
);
```

---

## Error Codes

### Platform Errors (100-199)

| Code | Name | Description |
|------|------|-------------|
| 100 | EPlatformPaused | Platform is paused |
| 101 | EInsufficientFee | Fee payment too low |
| 102 | ENotAdmin | Not platform admin |
| 103 | EZeroAmount | Amount is zero |

### Governance Errors (200-299)

| Code | Name | Description |
|------|------|-------------|
| 200 | EGovernancePaused | Governance is paused |
| 201 | EWrongVotingMode | Wrong voting mode for action |
| 202 | EWrongStakingPool | Position from wrong pool |
| 203 | EWrongNFTCollection | Wrong NFT type |
| 204 | ENotDAOAdmin | Not DAO admin |
| 205 | EInvalidConfig | Invalid config parameter |

### Proposal Errors (300-399)

| Code | Name | Description |
|------|------|-------------|
| 300 | EInsufficientVotingPower | Not enough power to propose |
| 301 | EProposalNotActive | Proposal not in active state |
| 307 | EAlreadyVoted | Already voted on proposal |
| 311 | ENotProposer | Not the proposal creator |
| 312 | EVotingNotStarted | Voting hasn't started |
| 313 | EVotingEnded | Voting has ended |

### Council Errors (500-549)

| Code | Name | Description |
|------|------|-------------|
| 500 | ECouncilNotEnabled | Council not enabled |
| 501 | ENotCouncilMember | Not a council member |
| 504 | EInsufficientCouncilVotes | Not enough votes |
| 506 | EAlreadyFastTracked | Already fast-tracked |
| 508 | EAlreadyVotedFastTrack | Already voted fast-track |

### Guardian Errors (510-549)

| Code | Name | Description |
|------|------|-------------|
| 510 | EGuardianNotSet | No guardian set |
| 511 | ENotGuardian | Caller is not guardian |
| 512 | EAlreadyGuardian | Already set as guardian |

### Delegation Errors (600-699)

| Code | Name | Description |
|------|------|-------------|
| 600 | EDelegationNotEnabled | Delegation not enabled |
| 601 | ECannotDelegateToSelf | Cannot delegate to self |
| 603 | EDelegationLocked | Delegation is locked |
| 604 | ENotDelegator | Not the delegator |

### Treasury Errors (700-799)

| Code | Name | Description |
|------|------|-------------|
| 701 | EInsufficientTreasuryBalance | Not enough balance |
| 702 | EWrongTreasury | Wrong treasury ID |

### NFT Vault Errors (800-899)

| Code | Name | Description |
|------|------|-------------|
| 800 | ENFTsStillLocked | NFTs locked during voting |
| 801 | ENoNFTsLocked | Vault is empty |

---

## Integration Guide

### 1. Deploy and Initialize

```move
// 1. Create registry (platform admin)
let (registry, admin_cap) = registry::create_registry(ctx);

// 2. Create governance
let (governance, dao_admin_cap) = governance::create_staking_governance(
    registry,
    string::utf8(b"My DAO"),
    string::utf8(b"ipfs://QmDescription"),
    staking_pool_id,
    payment,
    clock,
    ctx,
);

// 3. Create treasury
let treasury = treasury::create_treasury(
    dao_admin_cap,
    governance,
    ctx,
);

// 4. Enable council (optional)
let council_caps = governance::enable_council(
    dao_admin_cap,
    governance,
    vector[@member1, @member2, @member3],
    ctx,
);

// 5. Set guardian (optional)
guardian::set_guardian(dao_admin_cap, governance, @security_multisig, ctx);

// 6. Enable delegation (optional)
governance::enable_delegation(dao_admin_cap, governance);
```

### 2. Frontend Integration

```typescript
// Create proposal
const actions = [
  createTreasuryTransferAction(treasuryId, amount, recipient),
];

const tx = new TransactionBlock();
tx.moveCall({
  target: `${PACKAGE}::proposal::create_proposal`,
  arguments: [
    tx.object(registryId),
    tx.object(governanceId),
    tx.pure(title),
    tx.pure(description),
    tx.pure(actions),
    tx.pure(votingPower),
    tx.object(paymentCoin),
    tx.object(clockId),
  ],
});

// Vote on proposal
tx.moveCall({
  target: `${PACKAGE}::voting::vote_with_stake`,
  typeArguments: [tokenType],
  arguments: [
    tx.object(governanceId),
    tx.object(proposalId),
    tx.object(positionId),
    tx.pure(1), // VOTE_FOR
    tx.object(clockId),
  ],
});
```

### 3. Governance Pool Setup (sui_staking)

For token-based governance, create a governance-only pool in sui_staking:

```move
// Create governance pool (0 rewards, indefinite)
let (pool, pool_admin_cap) = factory::create_governance_pool<MYTOKEN>(
    registry,
    payment,
    clock,
    ctx,
);

// Users stake for voting power only
let position = pool::stake(pool, tokens, clock, ctx);

// Use position for DAO voting
voting::vote_with_stake<MYTOKEN>(governance, proposal, position, ...);
```

---

## Security Considerations

1. **Hot Potato Pattern**: DAOAuth cannot be stored, must be consumed in same transaction
2. **Position Tracking**: Each position/vault can only vote once per proposal
3. **Timelock**: All passed proposals have mandatory delay before execution
4. **Guardian Limits**: Guardian can only pause, not unpause or configure
5. **Council Thresholds**: Fast-track requires majority, veto requires 1/3+1
6. **Lock Periods**: NFT vaults locked during voting to prevent double-voting

---

## Testing

```bash
cd sui_dao
sui move test
```

58 tests covering:
- Governance creation (staking + NFT modes)
- Proposal lifecycle (create, vote, finalize, execute)
- Council fast-track with majority voting
- Council veto with threshold
- Emergency proposal creation
- Guardian set/remove/pause
- Delegation create/transfer/revoke
- Treasury deposits and withdrawals
- NFT vault lock/unlock
- Error conditions and edge cases
