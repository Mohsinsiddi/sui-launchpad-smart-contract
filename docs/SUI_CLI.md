# Sui CLI Reference Guide

Complete reference for Sui Move development, deployment, and testing.

**Sources:**
- [Sui CLI Documentation](https://docs.sui.io/references/cli)
- [Sui Client CLI](https://docs.sui.io/references/cli/client)
- [Sui Move CLI](https://docs.sui.io/references/cli/move)
- [Sui PTB CLI](https://docs.sui.io/references/cli/ptb)
- [Building PTBs](https://docs.sui.io/guides/developer/sui-101/building-ptb)
- [Create Coins and Tokens](https://docs.sui.io/guides/developer/coin)

---

## Installation

### Using suiup (Recommended)

```bash
# Install suiup
curl -fsSL https://sui.io/install.sh | sh

# Install latest stable
suiup

# Install specific version
suiup --version 1.63.0

# Switch to testnet version
suiup --network testnet

# Switch to mainnet version
suiup --network mainnet
```

### Verify Installation

```bash
sui --version
sui client --version
```

---

## Project Setup

### Create New Project

```bash
# Create new Move package
sui move new <package_name>

# Example
sui move new sui_launchpad
```

### Move.toml Configuration

```toml
[package]
name = "sui_launchpad"
version = "1.0.0"
edition = "2024"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "mainnet-v1.40.0" }

[addresses]
sui_launchpad = "0x0"
sui = "0x2"
std = "0x1"

[dev-dependencies]

[dev-addresses]
```

### Environment-Based Dependencies

```toml
[package]
name = "sui_launchpad"
version = "1.0.0"
edition = "2024"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "mainnet" }

[addresses]
sui_launchpad = "0x0"

# Override for testnet
[dep-replacements.testnet]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "testnet" }
```

---

## Network Configuration

### Switch Networks

```bash
# List available environments
sui client envs

# Add new environment
sui client new-env --alias mainnet --rpc https://fullnode.mainnet.sui.io:443
sui client new-env --alias testnet --rpc https://fullnode.testnet.sui.io:443
sui client new-env --alias devnet --rpc https://fullnode.devnet.sui.io:443
sui client new-env --alias localnet --rpc http://127.0.0.1:9000

# Switch environment
sui client switch --env testnet
sui client switch --env mainnet
```

### Check Active Environment

```bash
sui client active-env
sui client active-address
```

---

## Wallet Management

### Create/Import Addresses

```bash
# List all addresses
sui client addresses

# Create new address
sui client new-address ed25519
sui client new-address secp256k1

# Switch active address
sui client switch --address <ADDRESS>

# Get gas coins
sui client gas
```

### Faucet (Testnet/Devnet)

```bash
# Request test tokens
sui client faucet

# Request to specific address
sui client faucet --address <ADDRESS>
```

---

## Build Commands

### Build Package

```bash
# Basic build
sui move build

# Build with path
sui move build --path ./sui-launchpad

# Build for specific environment
sui move build --default-move-edition 2024

# Build with additional checks
sui move build --lint
```

### Build Output

```
Build successful
Package digest: <DIGEST>
```

---

## Test Commands

### Run Tests

```bash
# Run all tests
sui move test

# Run specific test
sui move test <test_name>

# Run with filter
sui move test --filter "test_buy"

# Run with coverage
sui move test --coverage

# Run with gas profiling
sui move test --gas-profiler
```

### Test Example

```move
#[test]
fun test_create_pool() {
    // Test code
}

#[test]
#[expected_failure(abort_code = EInsufficientFunds)]
fun test_buy_insufficient_funds() {
    // Should abort
}

#[test_only]
fun setup_test_scenario(): Scenario {
    // Test helper
}
```

---

## Publish Commands

### Publish Package

```bash
# Basic publish
sui client publish --gas-budget 100000000

# Publish with path
sui client publish ./sui-launchpad --gas-budget 100000000

# Publish and get JSON output
sui client publish --gas-budget 100000000 --json

# Publish with specific gas coin
sui client publish --gas-budget 100000000 --gas-coin <COIN_ID>

# Skip dependency verification (not recommended)
sui client publish --gas-budget 100000000 --skip-dependency-verification
```

### Publish Output (JSON)

```json
{
  "digest": "TRANSACTION_DIGEST",
  "objectChanges": [
    {
      "type": "published",
      "packageId": "0xPACKAGE_ID...",
      "modules": ["module1", "module2"]
    },
    {
      "type": "created",
      "objectType": "0x2::package::UpgradeCap",
      "objectId": "0xUPGRADE_CAP..."
    }
  ]
}
```

### Extract Package ID (Bash)

```bash
RESULT=$(sui client publish --gas-budget 100000000 --json)
PACKAGE_ID=$(echo $RESULT | jq -r '.objectChanges[] | select(.type == "published") | .packageId')
echo "Package ID: $PACKAGE_ID"
```

---

## Call Functions

### sui client call

```bash
# Basic call
sui client call \
  --package <PACKAGE_ID> \
  --module <MODULE_NAME> \
  --function <FUNCTION_NAME> \
  --gas-budget 10000000

# With arguments
sui client call \
  --package 0xPACKAGE \
  --module bonding_curve \
  --function buy \
  --args 0xPOOL_ID 1000000000 \
  --gas-budget 50000000

# With type arguments
sui client call \
  --package 0xPACKAGE \
  --module pool \
  --function stake \
  --type-args "0xTOKEN::token::TOKEN" \
  --args 0xPOOL_ID 0xCOIN_ID \
  --gas-budget 50000000

# With object arguments
sui client call \
  --package 0xPACKAGE \
  --module config \
  --function update_fee \
  --args 0xADMIN_CAP 0xCONFIG 500 \
  --gas-budget 10000000
```

### Argument Types

```bash
# Object ID (pass by reference)
--args 0xOBJECT_ID

# Pure value (u64)
--args 1000000000

# Pure value (bool)
--args true

# Pure value (vector<u8> as hex string)
--args "0x68656c6c6f"

# Address
--args @0xADDRESS

# Vector of objects
--args "[0xOBJ1, 0xOBJ2]"

# String (encoded)
--args '"Hello, World!"'
```

---

## Programmable Transaction Blocks (PTB)

### Basic PTB

```bash
# Simple transfer
sui client ptb \
  --transfer-objects "[0xOBJECT_ID]" @0xRECIPIENT \
  --gas-budget 10000000

# Split and transfer coins
sui client ptb \
  --split-coins gas "[1000000000]" \
  --assign coin \
  --transfer-objects "[coin]" @0xRECIPIENT \
  --gas-budget 10000000
```

### Move Call in PTB

```bash
# Single move call
sui client ptb \
  --move-call "0xPACKAGE::module::function" \
  --gas-budget 10000000

# With arguments
sui client ptb \
  --move-call "0xPACKAGE::bonding_curve::buy" 0xPOOL_ID 1000 \
  --gas-budget 50000000

# With type arguments
sui client ptb \
  --move-call "0xPACKAGE::pool::stake<0xTOKEN::t::T>" 0xPOOL 0xCOIN \
  --gas-budget 50000000
```

### Complex PTB (Multiple Operations)

```bash
# Multiple operations in one transaction
sui client ptb \
  --split-coins gas "[1000000000, 2000000000]" \
  --assign coins \
  --move-call "0xPKG::module::func1" "coins.0" \
  --move-call "0xPKG::module::func2" "coins.1" \
  --gas-budget 100000000
```

### PTB with Preview (Dry Run)

```bash
# Preview without executing
sui client ptb \
  --move-call "0xPACKAGE::module::function" \
  --gas-budget 10000000 \
  --preview
```

---

## Object Queries

### Get Objects

```bash
# Get owned objects
sui client objects

# Get specific object
sui client object <OBJECT_ID>

# Get object with JSON output
sui client object <OBJECT_ID> --json

# Get object with BCS
sui client object <OBJECT_ID> --bcs
```

### Get Dynamic Fields

```bash
# List dynamic fields
sui client dynamic-field <PARENT_OBJECT_ID>
```

---

## Transaction Queries

```bash
# Get transaction details
sui client tx-block <TX_DIGEST>

# Get transaction with JSON
sui client tx-block <TX_DIGEST> --json
```

---

## Coin Operations

### Create Currency (TreasuryCap)

```move
module example::my_coin {
    use sui::coin::{Self, TreasuryCap, CoinMetadata};
    use sui::url;

    /// One-Time Witness
    struct MY_COIN has drop {}

    fun init(witness: MY_COIN, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness,
            9,                                    // decimals
            b"MYC",                               // symbol
            b"My Coin",                           // name
            b"Description",                       // description
            option::some(url::new_unsafe_from_bytes(
                b"https://example.com/icon.png"
            )),
            ctx
        );

        // Transfer TreasuryCap to sender
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));

        // Freeze metadata
        transfer::public_freeze_object(metadata);
    }

    /// Mint new coins (requires TreasuryCap)
    public fun mint(
        treasury_cap: &mut TreasuryCap<MY_COIN>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let coin = coin::mint(treasury_cap, amount, ctx);
        transfer::public_transfer(coin, recipient);
    }

    /// Burn coins
    public fun burn(
        treasury_cap: &mut TreasuryCap<MY_COIN>,
        coin: Coin<MY_COIN>
    ) {
        coin::burn(treasury_cap, coin);
    }
}
```

### Mint Coins (CLI)

```bash
sui client call \
  --package 0xPACKAGE \
  --module my_coin \
  --function mint \
  --args 0xTREASURY_CAP 1000000000 @0xRECIPIENT \
  --gas-budget 10000000
```

---

## Shared Objects

### Creating Shared Objects

```move
/// Create a shared object
public fun create_pool(ctx: &mut TxContext) {
    let pool = Pool {
        id: object::new(ctx),
        balance: balance::zero(),
    };
    // Make it shared - accessible by anyone
    transfer::share_object(pool);
}
```

### Using Shared Objects in CLI

```bash
# Shared objects are passed by ID
sui client call \
  --package 0xPKG \
  --module pool \
  --function deposit \
  --args 0xSHARED_POOL_ID 0xCOIN_ID \
  --gas-budget 10000000
```

---

## Upgrade Packages

### Upgrade with UpgradeCap

```bash
sui client upgrade \
  --upgrade-capability <UPGRADE_CAP_ID> \
  --gas-budget 100000000
```

### Make Package Immutable

```bash
# Destroy UpgradeCap to make package immutable
sui client call \
  --package 0x2 \
  --module package \
  --function make_immutable \
  --args <UPGRADE_CAP_ID> \
  --gas-budget 10000000
```

---

## Gas Estimation

### Dry Run

```bash
# Dry run to estimate gas
sui client call \
  --package 0xPKG \
  --module module \
  --function func \
  --dry-run
```

### Dev Inspect

```bash
# Inspect transaction without executing
sui client call \
  --package 0xPKG \
  --module module \
  --function func \
  --dev-inspect
```

---

## Common Patterns

### Deploy & Initialize Script

```bash
#!/bin/bash
set -e

echo "Building package..."
sui move build

echo "Publishing package..."
RESULT=$(sui client publish --gas-budget 500000000 --json)

PACKAGE_ID=$(echo $RESULT | jq -r '.objectChanges[] | select(.type == "published") | .packageId')
UPGRADE_CAP=$(echo $RESULT | jq -r '.objectChanges[] | select(.objectType | contains("UpgradeCap")) | .objectId')

echo "Package ID: $PACKAGE_ID"
echo "UpgradeCap: $UPGRADE_CAP"

echo "Initializing..."
sui client call \
  --package $PACKAGE_ID \
  --module config \
  --function initialize \
  --gas-budget 50000000

echo "Done!"
```

### Full Deployment Example

```bash
#!/bin/bash
# deploy_launchpad.sh

set -e

NETWORK=${1:-testnet}
GAS_BUDGET=500000000

echo "==================================="
echo "Deploying Launchpad to $NETWORK"
echo "==================================="

# Switch network
sui client switch --env $NETWORK

# Build
echo "Building..."
cd sui-launchpad
sui move build

# Publish
echo "Publishing..."
RESULT=$(sui client publish --gas-budget $GAS_BUDGET --json)

# Extract IDs
PACKAGE_ID=$(echo $RESULT | jq -r '.objectChanges[] | select(.type == "published") | .packageId')
ADMIN_CAP=$(echo $RESULT | jq -r '.objectChanges[] | select(.objectType | contains("AdminCap")) | .objectId')
CONFIG=$(echo $RESULT | jq -r '.objectChanges[] | select(.objectType | contains("LaunchpadConfig")) | .objectId')
REGISTRY=$(echo $RESULT | jq -r '.objectChanges[] | select(.objectType | contains("LaunchpadRegistry")) | .objectId')

echo ""
echo "==================================="
echo "Deployment Complete!"
echo "==================================="
echo "Package ID:    $PACKAGE_ID"
echo "AdminCap:      $ADMIN_CAP"
echo "Config:        $CONFIG"
echo "Registry:      $REGISTRY"
echo ""

# Save to env file
cat > .env.$NETWORK << EOF
LAUNCHPAD_PACKAGE_ID=$PACKAGE_ID
LAUNCHPAD_ADMIN_CAP=$ADMIN_CAP
LAUNCHPAD_CONFIG=$CONFIG
LAUNCHPAD_REGISTRY=$REGISTRY
EOF

echo "Saved to .env.$NETWORK"
```

---

## Troubleshooting

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `InsufficientGas` | Gas budget too low | Increase `--gas-budget` |
| `ObjectNotFound` | Invalid object ID | Check object exists with `sui client object` |
| `MoveAbort` | Smart contract error | Check abort code in Move code |
| `InvalidTransactionDigest` | Bad TX reference | Verify transaction digest |
| `DependencyVerificationFailure` | Wrong framework version | Match `rev` to network version |

### Debug Commands

```bash
# Check object exists
sui client object <ID> --json

# Check transaction
sui client tx-block <DIGEST> --json

# Check gas coins
sui client gas

# Verify package
sui client object <PACKAGE_ID>
```

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `sui move new <name>` | Create new project |
| `sui move build` | Build package |
| `sui move test` | Run tests |
| `sui client publish` | Deploy package |
| `sui client call` | Call function |
| `sui client ptb` | Execute PTB |
| `sui client objects` | List owned objects |
| `sui client gas` | Show gas coins |
| `sui client switch --env` | Switch network |
| `sui client faucet` | Request test tokens |
