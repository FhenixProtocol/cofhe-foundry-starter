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

# runs the local Forge node
yarn dev
```

## Project Structure

```
├── src/
│   └── mocks/
│   │   └── ForgeMockACL.sol    # The MockACL that works with Forge
│   └── Counter.sol             # Example FHE counter contract
├── test/
│   └── Counter.t.sol           # Comprehensive Solidity tests
├── script/
│   ├── DeployCounter.s.sol     # Deployment script
│   ├── IncrementCounter.s.sol  # Increment interaction
│   └── ResetCounter.s.sol      # Reset with encrypted input
│   └── dev.sh                  # Shell script to etch FHE, deploy and init contracts and run forge
│   └── DeployDEv.s.sol         # Initializes etched addresses for MockAcl
├── foundry.toml                # Foundry configuration
├── package.json                # npm dependencies
└── remappings.txt              # Solidity import remappings
```

## How FHE Testing Works

Tests use `CoFheTest` from `@cofhe/mock-contracts`, which provides mock contract deployment, encrypted input creation, plaintext assertions, and permission testing -- all in Solidity with no JS SDK needed.

For the full testing guide covering all helper functions, FHE operations, ACL, permits, and patterns, see **[TESTING.md](TESTING.md)**.

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
| `@cofhe/mock-contracts` | Mock contracts for local testing + Foundry helpers |
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
