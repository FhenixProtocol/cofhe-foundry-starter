# Writing Foundry Tests with CoFHE

## Test Setup

Inherit `CofheTest` from `@cofhe/foundry-plugin` and call `deployMocks()` in `setUp`. Create one `CofheClient` per simulated user, then `connect` each client with a private key.

```solidity
import {CofheTest} from "@cofhe/foundry-plugin/contracts/CofheTest.sol";
import {CofheClient} from "@cofhe/foundry-plugin/contracts/CofheClient.sol";
import {euint32, InEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

contract MyTest is CofheTest {
    CofheClient public bob;
    uint256 constant BOB_PKEY = 0xB0B;

    function setUp() public {
        deployMocks();

        bob = createCofheClient();
        bob.connect(BOB_PKEY);
        // Deploy your contracts here.
    }
}
```

`CofheTest` already inherits forge-std `Test`, so you do not need a second `Test` base.

Only import the types you actually use. Available encrypted types:

```solidity
// Encrypted types (each wraps a bytes32 handle)
ebool, euint8, euint16, euint32, euint64, euint128, eaddress
```

## Encrypted Types

Encrypted values are `bytes32` newtypes. The value they hold is a **handle** (pointer) into mock storage, not the plaintext.

```solidity
euint32 count = counter.count();
bytes32 ctHash = euint32.unwrap(count);
```

Use `unwrap` when a helper expects a raw handle (`decryptForTx_*`, `querySealOutput`, etc.).

## Creating Encrypted Inputs

Encrypted inputs come from a connected `CofheClient`. The client signs the input as that user; match `vm.prank(client.account())` to the same client.

```solidity
InEuint32 memory encrypted = bob.createInEuint32(2000);

vm.prank(bob.account());
counter.reset(encrypted);
```

Available creators on `CofheClient`:

| Function | Returns |
| --- | --- |
| `createInEbool(bool)` | `InEbool` |
| `createInEuint8(uint8)` | `InEuint8` |
| `createInEuint16(uint16)` | `InEuint16` |
| `createInEuint32(uint32)` | `InEuint32` |
| `createInEuint64(uint64)` | `InEuint64` |
| `createInEuint128(uint128)` | `InEuint128` |
| `createInEaddress(address)` | `InEaddress` |

## Asserting Encrypted Values

Use `expectPlaintext` from `CofheTest` (typed overloads for every encrypted type):

```solidity
expectPlaintext(counter.count(), uint32(42));
expectPlaintext(counter.count(), uint32(42), "count should be 42");
```

For low-level reads without an assertion:

```solidity
uint256 plaintext = getPlaintext(euint32.unwrap(counter.count()));
```

## FHE Operations Reference

### Trivial Encryption (plaintext to encrypted)

```solidity
euint32 x = FHE.asEuint32(42);
```

### Encrypted Input Verification (user-encrypted to on-chain)

```solidity
function deposit(InEuint32 memory encryptedAmount) public {
    euint32 amount = FHE.asEuint32(encryptedAmount);
    // ...
}
```

### Arithmetic / comparisons / bitwise

Use the usual `FHE.add`, `FHE.sub`, `FHE.mul`, `FHE.div`, `FHE.rem`, `FHE.lt` / `lte` / `gt` / `gte` / `eq` / `ne`, `FHE.min` / `max`, `FHE.and` / `or` / `xor` / `not`, shifts, and `FHE.select`. See the [FHE.sol reference](https://docs.fhenix.io/fhe-library/reference/fhe-sol).

## Decryption (on-chain publish flow)

Production flow: **allow** on-chain → **decrypt off-chain** → **publish/verify** on-chain.

```solidity
// Step 1: grant public decryption permission
function allowBalancePublicly() public {
    FHE.allowPublic(balance);
}

// Step 3: publish verified result on-chain (after off-chain decryption)
function revealBalance(uint32 plaintext, bytes memory signature) public {
    FHE.publishDecryptResult(euint32.unwrap(balance), plaintext, signature);
}
```

In tests, simulate the off-chain SDK step with `CofheClient.decryptForTx_withoutPermit` (for `FHE.allowPublic`) or `decryptForTx_withPermit` (for ACL-gated decrypt):

```solidity
bytes32 ctHash = euint32.unwrap(counter.count());
(, uint256 plaintext, bytes memory sig) = bob.decryptForTx_withoutPermit(ctHash);
assertEq(plaintext, 42);

counter.revealCounter(uint32(plaintext), sig);
```

## Access Control (ACL)

| Call | Effect |
| --- | --- |
| `FHE.allowThis(value)` | Contract can use the value in later FHE ops |
| `FHE.allowSender(value)` | `msg.sender` can unseal off-chain |
| `FHE.allow(value, address)` | Named account can unseal |
| `FHE.allowGlobal(value)` / `FHE.allowPublic(value)` | Anyone can decrypt (tx / public path) |
| `FHE.allowTransient(value, address)` | Transient allowance for the current tx |

Typical pattern after a write:

```solidity
function increment() public {
    count = FHE.add(count, FHE.asEuint32(1));
    FHE.allowThis(count);
    FHE.allowSender(count);
}
```

## CofheTest Helpers

| Function | Description |
| --- | --- |
| `deployMocks()` | Deploys mock TaskManager, ACL, ZkVerifier, ThresholdNetwork |
| `createCofheClient()` | Returns a new unconnected `CofheClient` |
| `enableLogs()` / `disableLogs()` | Toggle mock plaintext logging |
| `getPlaintext(...)` | Read plaintext behind a handle / encrypted type |
| `expectPlaintext(...)` | Assert plaintext equals expected value |

`mockThresholdNetwork` is available on the test contract for deny-path checks without going through `decryptForView` (which reverts on deny).

## CofheClient Helpers

| Function | Description |
| --- | --- |
| `connect(pkey)` | Bind the client to `vm.addr(pkey)` |
| `account()` | Connected address |
| `createInEuintN(...)` | Signed encrypted inputs (see table above) |
| `decryptForTx_withoutPermit(ctHash)` | Public decrypt; returns `(ctHash, plaintext, signature)` |
| `decryptForTx_withPermit(ctHash, permit)` | ACL-gated decrypt for tx |
| `decryptForView(ctHash, permit)` | Off-chain seal/unseal; **reverts on deny** |
| `permit_createSelf()` | Self-permit for the connected account |
| `permit_createShared(recipient)` | Issuer half of a shared permit |
| `permit_exportShared(permit)` | Strip sensitive fields for transfer |
| `permit_importShared(export)` | Recipient completes the shared permit |

### View decrypt (permit)

```solidity
import {Permission} from "@cofhe/mock-contracts/contracts/Permissioned.sol";

Permission memory bobPermit = bob.permit_createSelf();
uint256 decrypted = bob.decryptForView(ctHash, bobPermit);
assertEq(decrypted, 1);
```

### Assert deny without reverting

```solidity
Permission memory alicePermit = alice.permit_createSelf();
(bool allowed, string memory error, ) = mockThresholdNetwork.querySealOutput(
    uint256(ctHash),
    block.chainid,
    alicePermit
);
assertFalse(allowed);
assertEq(error, "NotAllowed");
```

## Common Patterns

### Increment and assert

```solidity
function test_ShouldIncrementTheCounter() public {
    expectPlaintext(counter.count(), uint32(0));

    vm.prank(bob.account());
    counter.increment();

    expectPlaintext(counter.count(), uint32(1));
}
```

### Encrypt input then reset

```solidity
function test_ShouldEncryptInputAndResetCounter() public {
    InEuint32 memory encrypted = bob.createInEuint32(2000);

    vm.prank(bob.account());
    counter.reset(encrypted);

    expectPlaintext(counter.count(), uint32(2000));
}
```

### Public decrypt → publish

```solidity
vm.prank(bob.account());
counter.allowCounterPublicly();

bytes32 ctHash = euint32.unwrap(counter.count());
(, uint256 plaintext, bytes memory sig) = bob.decryptForTx_withoutPermit(ctHash);

counter.revealCounter(uint32(plaintext), sig);
assertEq(counter.getDecryptedValue(), 42);
```

## Pitfalls

- **Prank must match the client** that created the encrypted input. `vm.prank(bob.account())` with an input from `alice.createInEuint32(...)` fails ZK verification.
- **`decryptForView` reverts on deny.** Use `mockThresholdNetwork.querySealOutput` when you want to assert `"NotAllowed"`.
- **Handles are `bytes32`.** Cast with `uint256(ctHash)` only when a mock helper still takes `uint256`.

See `test/Counter.t.sol` in this repo for a full working suite.
