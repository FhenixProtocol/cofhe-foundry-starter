# CoFHE Foundry Starter

A starter template for developing Fully Homomorphic Encryption (FHE) smart contracts using [Fhenix CoFHE](https://www.fhenix.io/) and [Foundry](https://getfoundry.sh/).

## Prerequisites

- [Foundry](https://getfoundry.sh/) (`forge`, `cast`, `anvil`)
- [Node.js](https://nodejs.org/) (v18+) and npm

## Quick Start

```bash
# Clone the repository
git clone <repo-url>
cd cofhe-foundry-starter

# Install Solidity dependencies
npm install

# Compile contracts
forge build

# Run tests
forge test -vvv
```

## Project Structure

```
├── src/
│   └── Counter.sol           # Example FHE counter contract
├── test/
│   └── Counter.t.sol         # Comprehensive Solidity tests
├── script/
│   ├── DeployCounter.s.sol   # Deployment script
│   ├── IncrementCounter.s.sol # Increment interaction
│   └── ResetCounter.s.sol    # Reset with encrypted input
├── foundry.toml              # Foundry configuration
├── package.json              # npm dependencies
└── remappings.txt            # Solidity import remappings
```

## How FHE Testing Works

Tests inherit `CofheTest` from `@cofhe/foundry-plugin`. Call `deployMocks()` in `setUp`, create per-user `CofheClient` instances for encrypted inputs / permits, and assert with `expectPlaintext` -- all in Solidity with no JS SDK needed.

For the full testing guide covering helpers, FHE operations, ACL, permits, and patterns, see **[TESTING.md](TESTING.md)**.

## Deployment

### Setup

```bash
cp .env.example .env
# Edit .env with your private key and RPC URLs
```

### Deploy to Testnet

```bash
# Ethereum Sepolia
npm run deploy:eth-sepolia

# Arbitrum Sepolia
npm run deploy:arb-sepolia

# Base Sepolia
npm run deploy:base-sepolia
```

### Interact with Deployed Contract

```bash
# Set the deployed contract address
export COUNTER_ADDRESS=0x...

# Increment the counter
source .env && forge script script/IncrementCounter.s.sol --rpc-url eth-sepolia --broadcast
```

## Gas Report

```bash
npm run test:gas
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `@fhenixprotocol/cofhe-contracts` | FHE type definitions and operations (FHE.sol) |
| `@cofhe/foundry-plugin` | `CofheTest` / `CofheClient` Foundry test helpers |
| `@cofhe/mock-contracts` | Mock CoFHE contracts used by the Foundry plugin |
| `@openzeppelin/contracts` | Standard contract utilities |
| `forge-std` | Foundry standard library (Test, Script, cheatcodes) |

## Configuration Notes

- **EVM Version**: `cancun` — required for MockACL's transient storage (`tstore`/`tload`)
- **Code Size Limit**: `100000` — mock contracts exceed the default 24KB limit
- **Solidity Version**: `0.8.25` — compatible with CoFHE contracts

## Resources

- [Fhenix Documentation](https://docs.fhenix.zone/)
- [Foundry Book](https://book.getfoundry.sh/)
- [CoFHE Contracts](https://github.com/FhenixProtocol/cofhe-contracts)
