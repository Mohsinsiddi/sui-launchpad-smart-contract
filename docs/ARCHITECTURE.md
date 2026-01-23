# DeFi Product Suite - Master Architecture

## Overview

A modular DeFi ecosystem on Sui blockchain consisting of 4 independent products that work together to provide a complete token lifecycle management system.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PRODUCT ECOSYSTEM                                │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐ │
│  │  LAUNCHPAD  │   │   STAKING   │   │     DAO     │   │   MULTISIG  │ │
│  │             │   │             │   │             │   │             │ │
│  │  Token      │   │  Staking    │   │  Governance │   │  Multi-sig  │ │
│  │  Creation   │   │  as a       │   │  as a       │   │  Wallet     │ │
│  │  & Trading  │   │  Service    │   │  Service    │   │  Service    │ │
│  └──────┬──────┘   └─────────────┘   └─────────────┘   └─────────────┘ │
│         │                 ▲                 ▲                           │
│         │                 │                 │                           │
│         └─────────────────┴─────────────────┘                           │
│                   POST-GRADUATION SERVICES                              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Token Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         TOKEN LIFECYCLE                                  │
└─────────────────────────────────────────────────────────────────────────┘

PHASE 1: TOKEN CREATION (PBT - Publish By Template)
══════════════════════════════════════════════════

    User wants to create meme token
                │
                ▼
    ┌───────────────────────┐
    │  1. User publishes    │
    │     coin module from  │
    │     template          │
    │                       │
    │  Template includes:   │
    │  • Coin struct        │
    │  • TreasuryCap        │
    │  • Metadata           │
    └───────────┬───────────┘
                │
                ▼
    ┌───────────────────────┐
    │  2. User calls        │
    │     register_token()  │
    │     on Launchpad      │
    │                       │
    │  Transfers:           │
    │  • TreasuryCap        │
    │  • Creation fee       │
    └───────────┬───────────┘
                │
                ▼
    ┌───────────────────────┐
    │  3. Launchpad creates │
    │     BondingPool       │
    │                       │
    │  • Mints initial      │
    │    supply             │
    │  • Sets curve params  │
    │  • Opens trading      │
    └───────────────────────┘


PHASE 2: BONDING CURVE TRADING
══════════════════════════════

    ┌─────────────────────────────────────────────────────────────┐
    │                                                             │
    │   BONDING CURVE POOL                                        │
    │   ══════════════════                                        │
    │                                                             │
    │   ┌─────────┐         ┌─────────┐         ┌─────────┐      │
    │   │   SUI   │ ◄─────► │  POOL   │ ◄─────► │  TOKEN  │      │
    │   │ Reserve │         │         │         │ Reserve │      │
    │   └─────────┘         └─────────┘         └─────────┘      │
    │                                                             │
    │   Price = f(supply) → Increases as more tokens bought       │
    │                                                             │
    │   BUY:  User sends SUI  → Receives tokens                   │
    │   SELL: User sends tokens → Receives SUI                    │
    │                                                             │
    │   Fees collected on each trade:                             │
    │   • Platform fee: 0.5%                                      │
    │   • Creator fee: configurable                               │
    │                                                             │
    └─────────────────────────────────────────────────────────────┘


PHASE 3: GRADUATION (When target market cap reached)
════════════════════════════════════════════════════

    Market Cap reaches threshold (e.g., $69K)
                │
                ▼
    ┌───────────────────────┐
    │  1. Trading halted    │
    │     on bonding curve  │
    └───────────┬───────────┘
                │
                ▼
    ┌───────────────────────┐
    │  2. Collect:          │
    │     • SUI from pool   │
    │     • Remaining tokens│
    │     • Graduation fee  │
    └───────────┬───────────┘
                │
                ▼
    ┌───────────────────────┐
    │  3. Create LP on DEX  │
    │     (Cetus/Turbos)    │
    │                       │
    │     • Add liquidity   │
    │     • Get LP tokens   │
    └───────────┬───────────┘
                │
                ▼
    ┌───────────────────────┐
    │  4. LP Token Handling │
    │                       │
    │  Options:             │
    │  • Lock forever       │
    │  • Vest to creator    │
    │  • Partial burn       │
    └───────────────────────┘


PHASE 4: POST-GRADUATION (Token is live on DEX)
═══════════════════════════════════════════════

    Token now tradeable on real DEX
                │
                ▼
    ┌─────────────────────────────────────────────────────────────┐
    │                                                             │
    │   TOKEN CAN NOW USE ANY SERVICE:                            │
    │                                                             │
    │   ┌───────────┐   ┌───────────┐   ┌───────────┐            │
    │   │  STAKING  │   │    DAO    │   │  MULTISIG │            │
    │   │           │   │           │   │           │            │
    │   │ Stake     │   │ Create    │   │ Team      │            │
    │   │ tokens    │   │ governance│   │ wallet    │            │
    │   │ for       │   │ for       │   │ for       │            │
    │   │ rewards   │   │ community │   │ treasury  │            │
    │   │           │   │ voting    │   │ mgmt      │            │
    │   └───────────┘   └───────────┘   └───────────┘            │
    │                                                             │
    └─────────────────────────────────────────────────────────────┘
```

---

## Package Structure

```
your-org/
│
├── sui-launchpad/               # PRODUCT 1: Token Launchpad (219 tests)
│   ├── Move.toml
│   └── sources/
│       ├── core/                # Self-contained utilities
│       │   ├── math.move
│       │   ├── access.move
│       │   └── errors.move
│       ├── registry.move        # Token registry
│       ├── config.move          # Platform config + LP distribution
│       ├── bonding_curve.move   # Trading pool
│       ├── graduation.move      # DEX migration + LP splits
│       ├── vesting.move         # PTB flow docs + sui_vesting integration
│       ├── dex_adapters/        # DEX integrations
│       │   ├── cetus.move       # CLMM + LP distribution
│       │   ├── turbos.move      # CLMM + LP distribution
│       │   ├── flowx.move       # CLMM + LP distribution
│       │   └── suidex.move      # AMM + LP distribution
│       └── events.move
│
├── sui-vesting/                 # STANDALONE: Vesting Service (65 tests)
│   ├── Move.toml
│   └── sources/
│       ├── core/
│       │   ├── access.move      # AdminCap, CreatorCap
│       │   └── errors.move      # Error codes
│       ├── vesting.move         # Coin<T> vesting (cliff + linear)
│       ├── nft_vesting.move     # NFT/Position vesting (CLMM)
│       └── events.move          # Event definitions
│
├── sui-staking/                 # PRODUCT 2: Staking Service
│   ├── Move.toml
│   └── sources/
│       ├── core/
│       │   ├── math.move
│       │   └── access.move
│       ├── factory.move
│       ├── pool.move
│       ├── position.move
│       ├── emissions.move
│       └── events.move
│
├── sui-dao/                     # PRODUCT 3: DAO Service
│   ├── Move.toml
│   └── sources/
│       ├── core/
│       │   ├── math.move
│       │   └── access.move
│       ├── factory.move
│       ├── governance.move
│       ├── proposal.move
│       ├── custom_tx.move
│       ├── timelock.move
│       ├── treasury.move
│       └── events.move
│
├── sui-multisig/                # PRODUCT 4: Multisig Wallet
│   ├── Move.toml
│   └── sources/
│       ├── core/
│       │   └── access.move
│       ├── wallet.move
│       ├── proposal.move
│       ├── custom_tx.move
│       └── events.move
│
└── token-template/              # Template for PBT
    ├── Move.toml
    └── sources/
        └── coin_template.move   # Users copy & modify this
```

---

## Inter-Product Relationships

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    HOW PRODUCTS CONNECT                                  │
└─────────────────────────────────────────────────────────────────────────┘

                         TOKEN TEMPLATE
                              │
                              │ User publishes
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         LAUNCHPAD                                        │
│                                                                         │
│  register_token() ◄── User transfers TreasuryCap                        │
│       │                                                                 │
│       ▼                                                                 │
│  BondingPool created ──► Trading enabled                                │
│       │                                                                 │
│       ▼                                                                 │
│  graduation() ──► Liquidity added to DEX                                │
│       │                                                                 │
└───────┼─────────────────────────────────────────────────────────────────┘
        │
        │ Token now on DEX
        │
        ├──────────────────────┬──────────────────────┐
        │                      │                      │
        ▼                      ▼                      ▼
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│    STAKING    │      │      DAO      │      │   MULTISIG    │
│               │      │               │      │               │
│ Project can   │      │ Project can   │      │ Team can      │
│ create        │      │ create        │      │ create        │
│ staking pool  │      │ governance    │      │ multisig      │
│ for their     │      │ for their     │      │ for treasury  │
│ token         │      │ token         │      │ management    │
│               │      │               │      │               │
│ B2B Service:  │      │ B2B Service:  │      │ Service:      │
│ • Setup fee   │      │ • Setup fee   │      │ • Setup fee   │
│ • % rewards   │      │ • Proposal $  │      │ • Per-TX fee  │
└───────────────┘      └───────────────┘      └───────────────┘

OPTIONAL INTEGRATION:
─────────────────────
DAO can use staking positions for voting power
(voter_power = staked_tokens instead of just held tokens)
```

---

## Revenue Model

| Product | Fee Type | Amount | When |
|---------|----------|--------|------|
| **Launchpad** | Token Creation | 0.5 SUI | Token registered |
| | Trading Fee | 0.5% | Every trade |
| | Graduation Fee | 5% of SUI | At graduation |
| | Token Allocation | 1% supply | At graduation |
| **Staking** | Setup Fee | 10-50 SUI | Pool created |
| | Platform Fee | 2% rewards | On distribution |
| **DAO** | Setup Fee | 20-100 SUI | DAO created |
| | Proposal Fee | 1 SUI | Per proposal |
| | Execution Fee | 0.1 SUI | Per execution |
| **Multisig** | Creation Fee | 5-10 SUI | Wallet created |
| | Transaction Fee | 0.1 SUI | Per TX |

---

## Security Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         SECURITY LAYERS                                  │
└─────────────────────────────────────────────────────────────────────────┘

LAYER 1: CAPABILITY-BASED ACCESS
════════════════════════════════
• AdminCap - Platform admin operations
• PoolAdminCap - Individual pool management
• TreasuryCap - Token minting (transferred to launchpad)

LAYER 2: FUNCTION VISIBILITY
════════════════════════════
• public - External callable (with proper checks)
• public(package) - Internal only (graduation, etc.)
• friend - Specific module access

LAYER 3: STATE VALIDATION
═════════════════════════
• Reentrancy guards on all state changes
• State machine for token lifecycle (trading → graduated)
• Timelock for critical config changes

LAYER 4: INPUT VALIDATION
═════════════════════════
• All numeric inputs bounded
• Fee caps (max 10%)
• Dust protection (min amounts)

LAYER 5: CUSTOM TX SECURITY (DAO/Multisig)
══════════════════════════════════════════
• Proposal must pass voting/threshold
• Timelock before execution
• Optional target allowlist
• TX simulation before voting
```

---

## Development Order

| Order | Product | Actual LOC | Tests | Status |
|-------|---------|------------|-------|--------|
| 1 | sui-launchpad | ~2,500 | 219 | ✅ DONE |
| 2 | sui-vesting | ~1,350 | 65 | ✅ DONE |
| 3 | sui-staking | ~2,170 | 97 | ✅ DONE |
| 4 | sui-dao | ~5,200 | 58 | ✅ DONE |
| 5 | sui-multisig | ~1,976 | 33 | ✅ DONE |
| **Total** | | **~13,200** | **472** | ✅ |

> **Note:** All packages are complete with comprehensive test coverage.
> sui-vesting is fully integrated with sui-launchpad graduation flow.
> See [VESTING.md](./VESTING.md) and [STATUS.md](./STATUS.md) for details.

---

## Deployment Flow

```
STEP 1: Deploy sui-launchpad
        │
        └──► Package ID: 0xLAUNCHPAD...
             └──► Initialize config
             └──► Set fees
             └──► Ready for token creation

STEP 2: Deploy sui-vesting (standalone)
        │
        └──► Package ID: 0xVESTING...
             └──► Initialize config
             └──► Ready for vesting schedules
             └──► Integrate with launchpad graduation

STEP 3: Deploy sui-staking
        │
        └──► Package ID: 0xSTAKING...
             └──► Initialize registry
             └──► Optional: integrate sui-vesting
             └──► Ready for pool creation

STEP 4: Deploy sui-dao
        │
        └──► Package ID: 0xDAO...
             └──► Initialize registry
             └──► Optional: integrate sui-vesting
             └──► Ready for DAO creation

STEP 5: Deploy sui-multisig
        │
        └──► Package ID: 0xMULTISIG...
             └──► Initialize
             └──► Ready for wallet creation

ALL PRODUCTS LAUNCH SIMULTANEOUSLY
```

---

## Documentation Index

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | This file - master architecture |
| [REPOSITORY.md](./REPOSITORY.md) | Complete repository structure |
| [SUI_CLI.md](./SUI_CLI.md) | Sui CLI commands reference |
| [LAUNCHPAD.md](./LAUNCHPAD.md) | Launchpad detailed spec |
| [VESTING.md](./VESTING.md) | **Vesting service spec (standalone)** |
| [STAKING.md](./STAKING.md) | Staking service spec |
| [DAO.md](./DAO.md) | DAO service spec |
| [MULTISIG.md](./MULTISIG.md) | Multisig wallet spec |
| [STATUS.md](./STATUS.md) | Development progress tracking |
