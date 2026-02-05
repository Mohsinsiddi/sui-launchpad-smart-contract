# sui_multisig

A secure multisig wallet implementation for Sui Move with M-of-N signing, proposal-based execution, and multi-asset vault support.

## Overview

sui_multisig provides a complete multisig solution for managing shared assets:

- **M-of-N Signing**: Configurable threshold (e.g., 2-of-3, 3-of-5)
- **Proposal System**: Create, approve, reject, and execute proposals
- **Multi-Asset Vault**: Store any Coin type (SUI, USDC, custom tokens) and NFTs
- **Custom Transactions**: Authorize external contract calls via hot potato pattern
- **Signer Management**: Add/remove signers and change threshold via proposals

## Architecture

```
sui_multisig/
├── sources/
│   ├── registry.move       # Platform config and wallet registry
│   ├── wallet.move         # Multisig wallet creation and management
│   ├── vault.move          # Multi-asset storage (coins + NFTs)
│   ├── proposal.move       # Proposal creation, voting, execution
│   ├── events.move         # Event definitions
│   └── core/
│       ├── access.move     # AdminCap for platform admin
│       └── errors.move     # Error constants
```

## Core Concepts

### Multisig Wallet

A shared wallet with N authorized signers requiring M approvals (threshold) for any action.

```move
public struct MultisigWallet has key, store {
    id: UID,
    name: String,
    threshold: u64,           // Required approvals
    signers: VecSet<address>, // Authorized signers
    nonce: u64,               // Replay protection
    vault_id: ID,             // Associated vault
}
```

### Vault

Stores all wallet assets uniformly - any Coin<T> (including SUI) and NFTs.

```move
public struct MultisigVault has key {
    id: UID,
    wallet_id: ID,
    balances: Bag,            // All token balances by type
    nfts: ObjectBag,          // NFTs by object ID
    nft_count: u64,
}
```

### Proposal

A proposed action requiring threshold approvals before execution.

```move
public struct MultisigProposal has key, store {
    id: UID,
    wallet_id: ID,
    wallet_nonce: u64,        // Replay protection
    approvals: VecSet<address>,
    rejections: VecSet<address>,
    status: u8,               // pending/approved/rejected/executed/cancelled
    action: ProposalAction,
    expires_at_ms: u64,
    proposer: address,
}
```

## Action Types

| Type | ID | Description |
|------|-----|-------------|
| `TRANSFER` | 0 | Transfer any Coin<T> to recipient |
| `ADD_SIGNER` | 1 | Add a new authorized signer |
| `REMOVE_SIGNER` | 2 | Remove an existing signer |
| `CHANGE_THRESHOLD` | 3 | Modify approval threshold |
| `CUSTOM_TX` | 4 | Authorize external contract call |
| `NFT_TRANSFER` | 5 | Transfer NFT to recipient |

## Proposal Status Flow

```
┌──────────┐    approve()     ┌──────────┐    execute()    ┌──────────┐
│ PENDING  │ ────────────────▶│ APPROVED │ ───────────────▶│ EXECUTED │
└──────────┘                  └──────────┘                 └──────────┘
     │
     │ reject() (threshold reached)
     ▼
┌──────────┐
│ REJECTED │
└──────────┘
     │
     │ cancel() (proposer only)
     ▼
┌───────────┐
│ CANCELLED │
└───────────┘
```

## Usage

### Creating a Wallet

```move
// Create a 2-of-3 multisig wallet
let signers = vector[@alice, @bob, @charlie];
let wallet = wallet::create_wallet(
    registry,
    b"Team Treasury".to_string(),
    signers,
    2,                    // threshold
    creation_fee,         // 5 SUI default
    clock,
    ctx,
);
transfer::public_share_object(wallet);
```

### Depositing Assets

```move
// Deposit SUI
vault::deposit<SUI>(vault, sui_coin, ctx);

// Deposit any token
vault::deposit<USDC>(vault, usdc_coin, ctx);

// Deposit NFT
vault::deposit_nft(vault, nft, ctx);
```

### Creating Proposals

```move
// Token transfer proposal
let proposal = proposal::propose_transfer<SUI>(
    wallet,
    registry,
    @recipient,
    1_000_000_000,         // 1 SUI
    b"Pay for services".to_string(),
    clock,
    ctx,
);
transfer::public_share_object(proposal);

// Add signer proposal
let proposal = proposal::propose_add_signer(
    wallet,
    registry,
    @new_signer,
    b"Add team member".to_string(),
    clock,
    ctx,
);

// Change threshold proposal
let proposal = proposal::propose_change_threshold(
    wallet,
    registry,
    3,                     // new threshold
    b"Increase security".to_string(),
    clock,
    ctx,
);

// NFT transfer proposal
let proposal = proposal::propose_nft_transfer<MyNFT>(
    wallet,
    registry,
    nft_id,
    @recipient,
    b"Transfer artwork".to_string(),
    clock,
    ctx,
);

// Custom transaction proposal
let proposal = proposal::propose_custom_tx(
    wallet,
    registry,
    target_object_id,
    b"stake".to_string(),
    b"Stake in DeFi protocol".to_string(),
    clock,
    ctx,
);
```

### Voting

```move
// Approve a proposal
proposal::approve(proposal, wallet, clock, ctx);

// Reject a proposal
proposal::reject(proposal, wallet, clock, ctx);

// Cancel (proposer only)
proposal::cancel(proposal, wallet, ctx);
```

### Executing Proposals

```move
// Execute token transfer
let coin = proposal::execute_transfer<SUI>(
    proposal,
    wallet,
    vault,
    registry,
    execution_fee,
    clock,
    ctx,
);
transfer::public_transfer(coin, recipient);

// Execute add signer
proposal::execute_add_signer(
    proposal,
    wallet,
    registry,
    execution_fee,
    clock,
    ctx,
);

// Execute NFT transfer
let nft = proposal::execute_nft_transfer<MyNFT>(
    proposal,
    wallet,
    vault,
    registry,
    execution_fee,
    clock,
    ctx,
);
transfer::public_transfer(nft, recipient);

// Execute custom transaction
let auth = proposal::execute_custom_tx(
    proposal,
    wallet,
    registry,
    execution_fee,
    clock,
    ctx,
);
// Pass auth to external contract
external_contract::do_something(auth, ...);
```

### Custom Transaction Integration

External contracts can accept multisig authorization:

```move
module my_protocol::staking {
    use sui_multisig::proposal;

    public fun stake_with_multisig(
        auth: proposal::MultisigAuth,
        pool: &mut StakingPool,
        ...
    ) {
        // Verify and consume authorization
        let (wallet_id, proposal_id, target_id, function_name) =
            proposal::consume_auth(auth);

        // Verify this auth is for this pool
        assert!(target_id == object::id(pool), ENotAuthorized);

        // Proceed with staking logic...
    }
}
```

## Platform Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `creation_fee` | 5 SUI | Fee to create a wallet |
| `execution_fee` | 0.1 SUI | Fee to execute a proposal |
| `default_proposal_expiry_ms` | 7 days | Proposal expiration time |

### Admin Functions

```move
// Update platform config
registry::update_platform_config(
    registry,
    admin_cap,
    creation_fee,
    execution_fee,
    expiry_ms,
    fee_recipient,
    ctx,
);

// Pause/unpause platform
registry::set_platform_paused(registry, admin_cap, true);

// Withdraw collected fees
let fees = registry::withdraw_fees(registry, admin_cap, ctx);
```

## Security Features

1. **Threshold Enforcement**: Actions only execute when M-of-N signers approve
2. **Nonce Protection**: Each proposal tied to wallet nonce prevents replay
3. **Expiration**: Proposals auto-expire after configurable period
4. **Signer Validation**: Only authorized signers can create/vote on proposals
5. **Type Safety**: Transfers validate token type matches proposal
6. **Auto-Threshold Adjust**: Threshold automatically reduces when signers are removed

## Events

```move
// Wallet events
WalletCreated { wallet_id, vault_id, name, threshold, signers, creator }
SignerAdded { wallet_id, signer, new_signer_count }
SignerRemoved { wallet_id, signer, new_signer_count }
ThresholdChanged { wallet_id, old_threshold, new_threshold }

// Proposal events
ProposalCreated { proposal_id, wallet_id, proposer, action_type, expires_at_ms }
ProposalApproved { proposal_id, wallet_id, approver, approval_count, threshold }
ProposalRejected { proposal_id, wallet_id, rejector, rejection_count }
ProposalExecuted { proposal_id, wallet_id, executor, action_type }
ProposalCancelled { proposal_id, wallet_id, cancelled_by }

// Vault events
TokenDeposited { vault_id, wallet_id, token_type, depositor, amount }
TokenWithdrawn { vault_id, wallet_id, token_type, recipient, amount }
NftDeposited { vault_id, wallet_id, nft_id, nft_type, depositor }
NftWithdrawn { vault_id, wallet_id, nft_id, nft_type, recipient }

// Custom TX events
CustomTxAuthCreated { proposal_id, wallet_id, target_id, function_name }
```

## Building & Testing

```bash
cd sui_multisig
sui move build
sui move test

# Run specific tests
sui move test wallet
sui move test proposal
sui move test vault
```

## Common Patterns

### Team Treasury (2-of-3)

```move
// Create wallet
let wallet = wallet::create_wallet(
    registry,
    b"Team Treasury".to_string(),
    vector[@ceo, @cfo, @cto],
    2,  // 2-of-3
    fee,
    clock,
    ctx,
);

// Any 2 can approve payments
```

### High-Security Cold Wallet (3-of-5)

```move
// Create wallet with higher threshold
let wallet = wallet::create_wallet(
    registry,
    b"Cold Storage".to_string(),
    vector[@key1, @key2, @key3, @key4, @key5],
    3,  // 3-of-5
    fee,
    clock,
    ctx,
);
```

### DAO Treasury Integration

```move
// Create wallet controlled by DAO council
let wallet = wallet::create_wallet(
    registry,
    b"DAO Treasury".to_string(),
    council_members,
    quorum_threshold,
    fee,
    clock,
    ctx,
);

// DAO proposals can add/remove council members via proposals
```

## License

Apache 2.0
