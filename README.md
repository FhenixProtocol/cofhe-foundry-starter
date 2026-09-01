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
│   ├── Counter.t.sol         # Comprehensive Solidity tests
│   └── FHEOperations.t.sol   # FHE operation / input / ACL coverage
├── script/
│   ├── DeployCounter.s.sol   # Deployment script
│   ├── IncrementCounter.s.sol # Increment interaction
│   └── ResetCounter.s.sol    # Reset with encrypted input
├── foundry.toml              # Foundry configuration
├── package.json              # npm dependencies
└── remappings.txt            # Solidity import remappings
```

## How FHE Testing Works

Tests inherit `CofheTest` from `@cofhe/foundry-plugin` and call `deployMocks()` in `setUp()`, which deploys and wires the whole mock stack. Each user account is a `CofheClient` — the in-Solidity stand-in for the JS SDK — which encrypts inputs, builds ACPs, and decrypts outputs. No JS SDK needed.

```solidity
(externalEuint32 handle, bytes memory proof) = bob.createExternalEuint32(2000, address(counter));

vm.prank(bob.account());
counter.reset(handle, proof);

expectPlaintext(counter.count(), uint32(2000));
```

For the full testing guide covering all helper functions, FHE operations, ACL, ACPs, and patterns, see **[TESTING.md](TESTING.md)**.

## CoFHE 0.7

This starter targets CoFHE 0.7. The headline changes from earlier versions:

| Before | Now |
|--------|-----|
| `function reset(InEuint32 memory value)` | `function reset(externalEuint32 value, bytes memory proof)` |
| `FHE.asEuint32(inValue)` | `FHE.asEuint32(handle, proof)` |
| one signature per encrypted input | one signature per **batch** — `FHE.asEuint32s(handles, signature)` |
| bare `euintXX` passed between contracts | `sharedEuintXX` + `FHE.shareEuintXX` / `FHE.receiveEuintXXParam` |
| `Permission` / `permit_createSelf()` | `ACP` / `ACP_createSelf()` |
| `decryptForTx_withoutPermit()` | `decryptForTx_withoutACP()` |

Encrypted input proofs are now bound to the **consuming contract**, so the contract address must be passed when creating one. See the [0.7 migration guide](https://cofhe-docs.fhenix.zone/client-sdk/introduction/migrating-to-0-7).

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

Resetting the counter takes an encrypted input, so the handle and proof have to be produced
off-chain with `@cofhe/sdk` (0.7.1) and bound to the deployed Counter address:

```ts
const [handle, signature] = await client
  .encryptInputs([2000])
  .setConsumingContract(counterAddress)
  .execute();
```

```bash
export CT_HASH=<handle> PROOF=<signature>
source .env && forge script script/ResetCounter.s.sol --rpc-url eth-sepolia --broadcast
```

## Gas Report

```bash
npm run test:gas
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `@fhenixprotocol/cofhe-contracts` | FHE type definitions and operations (FHE.sol) — `0.2.0` |
| `@cofhe/foundry-plugin` | `CofheTest` / `CofheClient` Foundry test helpers — `0.7.1` |
| `@cofhe/mock-contracts` | Mock CoFHE contracts for local testing — `0.7.1` |
| `@openzeppelin/contracts` | Standard contract utilities |
| `forge-std` | Foundry standard library (Test, Script, cheatcodes) |

## Configuration Notes

- **EVM Version**: `cancun` — required for MockACL's transient storage (`tstore`/`tload`); note that as of 0.7 `FHE.allowTransient` allowances expire with the transaction (EIP-1153)
- **Code Size Limit**: `300000` — the mock stack puts test contracts far past the default 24KB limit
- **Solidity Version**: `0.8.25` — compatible with CoFHE contracts

## Resources

- [Fhenix Documentation](https://docs.fhenix.zone/)
- [Foundry Book](https://book.getfoundry.sh/)
- [CoFHE Contracts](https://github.com/FhenixProtocol/cofhe-contracts)
