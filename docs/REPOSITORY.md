# Repository Structure

## Complete Project Layout

```
launchpad/
│
├── sui-launchpad/                       # PRODUCT 1: Token Launchpad
│   ├── Move.toml
│   ├── Move.lock
│   └── sources/
│       ├── core/
│       │   ├── math.move
│       │   ├── access.move
│       │   └── errors.move
│       ├── config.move
│       ├── registry.move
│       ├── bonding_curve.move
│       ├── graduation.move
│       ├── vesting.move               # PLACEHOLDER → see sui-vesting
│       ├── launchpad.move
│       ├── dex_adapters/
│       │   ├── cetus.move
│       │   ├── turbos.move
│       │   ├── flowx.move
│       │   └── suidex.move
│       └── events.move
│
├── sui-vesting/                         # STANDALONE: Vesting Service
│   ├── Move.toml
│   ├── Move.lock
│   └── sources/
│       ├── vesting.move               # Core vesting logic
│       ├── linear.move                # Linear vesting
│       ├── milestone.move             # Milestone-based (future)
│       ├── batch.move                 # Batch operations
│       ├── admin.move                 # Admin functions
│       └── events.move                # Event definitions
│
├── sui-staking/                         # PRODUCT 2: Staking Service
│   ├── Move.toml
│   ├── Move.lock
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
├── sui-dao/                             # PRODUCT 3: DAO Service
│   ├── Move.toml
│   ├── Move.lock
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
├── sui-multisig/                        # PRODUCT 4: Multisig Wallet
│   ├── Move.toml
│   ├── Move.lock
│   └── sources/
│       ├── core/
│       │   └── access.move
│       ├── wallet.move
│       ├── proposal.move
│       ├── custom_tx.move
│       └── events.move
│
├── token-template/                      # PBT Template for Users
│   ├── Move.toml
│   └── sources/
│       └── coin_template.move
│
├── scripts/                             # Deployment & Utility Scripts
│   ├── deploy_launchpad.sh
│   ├── deploy_staking.sh
│   ├── deploy_dao.sh
│   ├── deploy_multisig.sh
│   ├── deploy_all.sh
│   └── initialize_all.sh
│
├── docs/                                # Documentation
│   ├── ARCHITECTURE.md                  # Master architecture
│   ├── LAUNCHPAD.md                     # Launchpad specification
│   ├── VESTING.md                       # Vesting specification (standalone)
│   ├── STAKING.md                       # Staking specification
│   ├── DAO.md                           # DAO specification
│   ├── MULTISIG.md                      # Multisig specification
│   ├── REPOSITORY.md                    # This file
│   ├── SUI_CLI.md                       # Sui CLI reference
│   └── STATUS.md                        # Development progress
│
├── .env.example                         # Environment template
├── .gitignore                           # Git ignore rules
└── README.md                            # Project overview
```

---

## Product Independence

Each product is a standalone Sui Move package:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    INDEPENDENT DEPLOYMENTS                               │
└─────────────────────────────────────────────────────────────────────────┘

sui-launchpad/          sui-staking/           sui-dao/              sui-multisig/
     │                       │                      │                      │
     ▼                       ▼                      ▼                      ▼
┌─────────┐            ┌─────────┐            ┌─────────┐            ┌─────────┐
│ Own     │            │ Own     │            │ Own     │            │ Own     │
│ Move.   │            │ Move.   │            │ Move.   │            │ Move.   │
│ toml    │            │ toml    │            │ toml    │            │ toml    │
├─────────┤            ├─────────┤            ├─────────┤            ├─────────┤
│ Own     │            │ Own     │            │ Own     │            │ Own     │
│ core/   │            │ core/   │            │ core/   │            │ core/   │
├─────────┤            ├─────────┤            ├─────────┤            ├─────────┤
│ No ext  │            │ No ext  │            │ No ext  │            │ No ext  │
│ deps    │            │ deps    │            │ deps    │            │ deps    │
└─────────┘            └─────────┘            └─────────┘            └─────────┘
     │                       │                      │                      │
     ▼                       ▼                      ▼                      ▼
sui publish            sui publish            sui publish            sui publish
     │                       │                      │                      │
     ▼                       ▼                      ▼                      ▼
0xLAUNCH...            0xSTAKE...             0xDAO...              0xMULTI...
```

**Benefits:**
- Independent audits (smaller scope)
- Independent deployments
- Independent upgrades
- No version conflicts
- Cleaner codebase

---

## Move.toml Templates

### sui-launchpad/Move.toml
```toml
[package]
name = "sui_launchpad"
version = "1.0.0"
edition = "2024"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "mainnet-v1.x.x" }

[addresses]
sui_launchpad = "0x0"
sui = "0x2"
```

### sui-staking/Move.toml
```toml
[package]
name = "sui_staking"
version = "1.0.0"
edition = "2024"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "mainnet-v1.x.x" }

[addresses]
sui_staking = "0x0"
sui = "0x2"
```

### sui-dao/Move.toml
```toml
[package]
name = "sui_dao"
version = "1.0.0"
edition = "2024"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "mainnet-v1.x.x" }

[addresses]
sui_dao = "0x0"
sui = "0x2"
```

### sui-multisig/Move.toml
```toml
[package]
name = "sui_multisig"
version = "1.0.0"
edition = "2024"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "mainnet-v1.x.x" }

[addresses]
sui_multisig = "0x0"
sui = "0x2"
```

---

## .gitignore

```gitignore
# Build artifacts
build/
.move/

# Lock files (optional - some prefer to commit)
# Move.lock

# Environment
.env
.env.local
.env.*.local

# IDE
.idea/
.vscode/
*.swp
*.swo
.DS_Store

# Deployment artifacts
deployment_*.json
*_package_id.txt

# Test artifacts
.coverage/
test-results/
```

---

## .env.example

```env
# Network Configuration
SUI_NETWORK=testnet
SUI_RPC_URL=https://fullnode.testnet.sui.io:443

# Deployer (DO NOT COMMIT ACTUAL VALUES)
DEPLOYER_ADDRESS=0x...
DEPLOYER_PRIVATE_KEY=

# Package IDs (filled after deployment)
LAUNCHPAD_PACKAGE_ID=
STAKING_PACKAGE_ID=
DAO_PACKAGE_ID=
MULTISIG_PACKAGE_ID=

# Shared Object IDs (filled after initialization)
LAUNCHPAD_CONFIG=
LAUNCHPAD_REGISTRY=
STAKING_REGISTRY=
DAO_REGISTRY=
MULTISIG_REGISTRY=

# Admin Caps (KEEP SECURE)
LAUNCHPAD_ADMIN_CAP=
STAKING_ADMIN_CAP=
DAO_ADMIN_CAP=
MULTISIG_ADMIN_CAP=

# Platform Treasury
TREASURY_ADDRESS=
```

---

## File Counts

| Product | Directories | Files | Est. Lines |
|---------|-------------|-------|------------|
| sui-launchpad | 3 | 14 | ~3,313 |
| sui-vesting | 1 | 6 | ~760 |
| sui-staking | 2 | 7 | ~940 |
| sui-dao | 2 | 9 | ~1,510 |
| sui-multisig | 2 | 5 | ~820 |
| token-template | 1 | 1 | ~50 |
| scripts | 1 | 6 | ~300 |
| docs | 1 | 9 | ~3,000 |
| **Total** | **13** | **57** | **~10,693** |

> **Note:** sui-vesting is a standalone package for reusability across products.
> Launchpad contains a placeholder (`vesting.move`) that will integrate with sui-vesting.
