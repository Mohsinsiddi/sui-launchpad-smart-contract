# sui_dao

A comprehensive DAO governance system for Sui Move with staking-based and NFT-based voting.

## Overview

sui_dao provides a full-featured governance framework supporting:

- **Staking-based voting**: Voting power from staking positions
- **NFT-based voting**: Voting power from NFT holdings
- **Multi-token treasury**: Holds tokens and NFTs controlled by governance
- **Council system**: Fast-track, veto, and emergency powers
- **Delegation**: Delegate voting power to other addresses
- **Guardian**: Emergency pause capabilities
- **Origin tracking**: Track if DAO was created via launchpad

## Architecture

```
sui_dao/
├── sources/
│   ├── governance.move       # Core governance configuration
│   ├── proposal.move         # Proposal lifecycle
│   ├── voting.move           # Vote casting logic
│   ├── treasury.move         # Multi-token treasury
│   ├── council.move          # Council powers
│   ├── delegation.move       # Vote delegation
│   ├── guardian.move         # Emergency controls
│   ├── nft_vault.move        # NFT voting vault
│   ├── registry.move         # DAO registry
│   ├── events.move           # Event definitions
│   ├── sui_dao.move          # Entry points
│   └── core/
│       ├── access.move       # Capabilities
│       ├── math.move         # Math utilities
│       └── errors.move       # Error codes
```

## Key Concepts

### Governance

The core governance object that defines DAO parameters and voting rules.

```move
public struct Governance has key {
    id: UID,
    name: String,
    config: GovernanceConfig,           // Voting parameters
    voting_mode: u8,                    // STAKING (0) or NFT (1)
    staking_pool_id: Option<ID>,        // For staking mode
    nft_collection_type: Option<...>,   // For NFT mode
    council_enabled: bool,
    council_members: VecSet<address>,
    delegation_enabled: bool,
    treasury_id: Option<ID>,
    guardian: Option<address>,
    proposal_count: u64,
    // ...
}
```

### GovernanceConfig

Voting parameters that define how proposals work.

```move
public struct GovernanceConfig has store {
    quorum_bps: u64,              // Min votes needed (basis points)
    quorum_votes: u64,            // Min votes needed (absolute, for NFT)
    voting_delay_ms: u64,         // Delay before voting starts
    voting_period_ms: u64,        // Duration of voting
    timelock_delay_ms: u64,       // Delay after proposal passes
    fast_track_timelock_ms: u64,  // Reduced timelock for fast-track
    proposal_threshold: u64,      // Min voting power to propose
    approval_threshold_bps: u64,  // % needed to pass (default 50%)
}
```

### Proposal

Represents a governance proposal with actions to execute.

```move
public struct Proposal has key {
    id: UID,
    governance_id: ID,
    proposal_number: u64,
    proposer: address,
    title: String,
    status: u8,                   // Pending, Active, Succeeded, etc.
    for_votes: u64,
    against_votes: u64,
    abstain_votes: u64,
    actions: vector<ProposalAction>,
    // Council voting
    veto_votes: VecSet<address>,
    fast_track_votes: VecSet<address>,
    is_fast_tracked: bool,
    is_emergency: bool,
    // ...
}
```

### Treasury

Multi-token treasury controlled by the DAO.

```move
public struct Treasury has key {
    id: UID,
    governance_id: ID,
    sui_balance: Balance<SUI>,
    token_balances: Bag,          // Other tokens by type
    nft_counters: Bag,            // NFT tracking
}
```

## Creating a DAO

### Staking-Based DAO

```move
let (governance, dao_admin_cap) = governance::create_staking_governance(
    &mut registry,
    string::utf8(b"My DAO"),
    string::utf8(b"ipfs://..."),  // Description hash
    staking_pool_id,              // Link to staking pool
    payment,                       // SUI for creation fee
    clock,
    ctx,
);
```

### Staking-Based DAO (Admin, with Origin)

```move
let (governance, dao_admin_cap) = governance::create_staking_governance_admin(
    &admin_cap,                    // Platform AdminCap
    &mut registry,
    string::utf8(b"My DAO"),
    staking_pool_id,
    quorum_bps,                    // Custom quorum
    voting_delay_ms,
    voting_period_ms,
    timelock_delay_ms,
    proposal_threshold_bps,
    origin,                        // 0=independent, 1=launchpad, 2=partner
    origin_id,                     // Optional source ID
    clock,
    ctx,
);
```

### NFT-Based DAO

```move
let (governance, dao_admin_cap) = governance::create_nft_governance<MyNFT>(
    &mut registry,
    string::utf8(b"NFT DAO"),
    string::utf8(b"ipfs://..."),
    quorum_votes,                  // Absolute vote threshold
    voting_delay_ms,
    voting_period_ms,
    timelock_delay_ms,
    payment,
    clock,
    ctx,
);
```

## Proposal Lifecycle

```
1. PENDING   → Proposal created, waiting for voting delay
2. ACTIVE    → Voting in progress
3. SUCCEEDED → Passed, enters timelock
4. QUEUED    → In timelock, waiting for execution
5. EXECUTED  → Successfully executed

Alternative endings:
- DEFEATED  → Quorum not met or more against votes
- CANCELLED → Cancelled by proposer
- VETOED    → Vetoed by council
- EXPIRED   → Execution window passed
```

### Creating a Proposal

```move
let proposal = proposal::create_proposal(
    &mut governance,
    &registry,
    title,
    description_hash,
    actions,              // vector<ProposalAction>
    voting_power,         // Proposer's voting power
    payment,              // Proposal fee
    clock,
    ctx,
);
```

### Voting

```move
// With staking position
voting::vote_with_position<StakeToken>(
    &governance,
    &mut proposal,
    &position,            // StakingPosition NFT
    vote,                 // 0=against, 1=for, 2=abstain
    clock,
    ctx,
);

// With NFT vault
voting::vote_with_vault<MyNFT>(
    &governance,
    &mut proposal,
    &vault,               // NFTVault
    vote,
    clock,
    ctx,
);
```

### Executing a Proposal

```move
let dao_auth = proposal::begin_execution(
    &mut governance,
    &mut proposal,
    &registry,
    payment,              // Execution fee
    clock,
    ctx,
);

// Execute actions using dao_auth...

proposal::complete_execution(
    &mut proposal,
    dao_auth,
    clock,
);
```

## Treasury Operations

### Creating Treasury

```move
let treasury = treasury::create_treasury(
    &dao_admin_cap,
    &mut governance,
    clock,
    ctx,
);
```

### Deposits (Anyone)

```move
treasury::deposit_sui(&mut treasury, sui_coin, ctx);
treasury::deposit<TOKEN>(&mut treasury, token_coin, ctx);
treasury::deposit_nft<MyNFT>(&mut treasury, nft, ctx);
```

### Withdrawals (Governance Only)

```move
// Via proposal execution with DAOAuth
let coin = treasury::withdraw<TOKEN>(
    &mut treasury,
    &dao_auth,
    amount,
    ctx,
);
```

## Council System

Council members have special powers: fast-track, veto, and emergency proposals.

### Enabling Council

```move
let caps = governance::enable_council(
    &dao_admin_cap,
    &mut governance,
    initial_members,      // vector<address>
    ctx,
);
```

### Council Powers

```move
// Fast-track (reduce timelock) - requires majority
council::vote_to_fast_track(&council_cap, &governance, &mut proposal, clock);

// Veto - requires majority
council::vote_to_veto(&council_cap, &governance, &mut proposal, clock);

// Emergency proposal (bypass voting)
council::create_emergency_proposal(
    &council_cap,
    &mut governance,
    &registry,
    title,
    description_hash,
    actions,
    payment,
    clock,
    ctx,
);
```

## Delegation

Users can delegate their voting power to another address.

```move
// Create delegation
let delegation = delegation::create_delegation<StakeToken>(
    &governance,
    &position,            // StakingPosition to delegate
    delegate,             // Address to receive voting power
    clock,
    ctx,
);

// Revoke delegation
delegation::revoke_delegation(
    &mut governance,
    delegation,
    ctx,
);
```

## Origin Tracking

DAOs can be tagged with their creation origin:

```move
const ORIGIN_INDEPENDENT: u8 = 0;  // Direct creation
const ORIGIN_LAUNCHPAD: u8 = 1;    // Via launchpad graduation
const ORIGIN_PARTNER: u8 = 2;      // Via partner integration

sui_dao::events::origin_independent()
sui_dao::events::origin_launchpad()
sui_dao::events::origin_partner()
```

## Capabilities

### AdminCap

Platform admin capability for:
- Updating platform fees
- Pausing/unpausing the registry
- Fee-free DAO creation

### DAOAdminCap

DAO-specific admin capability for:
- Updating governance configuration
- Creating treasury
- Enabling/managing council
- Setting guardian

### CouncilCap

Council member capability for:
- Voting to fast-track proposals
- Voting to veto proposals
- Creating emergency proposals

## Default Parameters

| Parameter | Default | Range |
|-----------|---------|-------|
| Quorum | 4% (400 bps) | - |
| Voting Delay | 1 day | 1 hour - 7 days |
| Voting Period | 3 days | 1 day - 14 days |
| Timelock Delay | 2 days | 12 hours - 7 days |
| Fast-Track Timelock | 12 hours | - |
| Approval Threshold | 50% (5000 bps) | - |
| Max Council Members | 11 | - |
| Execution Window | 7 days | - |

## Proposal Action Types

| Type | Description |
|------|-------------|
| `ACTION_TREASURY_TRANSFER` | Transfer tokens from treasury |
| `ACTION_CONFIG_UPDATE` | Update governance configuration |
| `ACTION_CUSTOM_TX` | Execute custom transaction |
| `ACTION_TEXT` | Signal/text-only proposal |

## Events

Key events emitted by the system:

```move
// Governance events
GovernanceCreated { governance_id, creator, name, voting_mode, ... }
GovernanceConfigUpdated { governance_id, ... }

// Proposal events
ProposalCreated { proposal_id, governance_id, proposer, title, ... }
ProposalStatusChanged { proposal_id, old_status, new_status, ... }
VoteCast { proposal_id, voter, vote, voting_power, ... }
ProposalExecuted { proposal_id, executor, ... }

// Council events
CouncilEnabled { governance_id, members, ... }
CouncilFastTrackVoteCast { proposal_id, member, ... }
ProposalFastTracked { proposal_id, ... }
ProposalVetoed { proposal_id, ... }

// Treasury events
TreasuryCreated { treasury_id, governance_id, creator, ... }
TreasuryDeposit { treasury_id, token_type, amount, ... }
TreasuryWithdrawal { treasury_id, token_type, amount, ... }
```

## Integration with Launchpad

At graduation, a DAO can be created for the token:

```move
let (governance, treasury, dao_admin_cap, council_cap) = dao_integration::setup_full_dao<T>(
    &dao_platform_admin,
    &mut dao_registry,
    &pending,              // PendingGraduation
    staking_pool_id,
    token_name,
    clock,
    ctx,
);

// Deposit LP tokens to treasury
dao_integration::deposit_lp_to_treasury(&mut treasury, dao_lp_tokens, ctx);
```

## Building & Testing

```bash
cd sui_dao
sui move build
sui move test
```

## License

Apache 2.0
