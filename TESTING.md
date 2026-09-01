# Writing Foundry Tests with CoFHE

> Targets CoFHE **0.7** — `@cofhe/foundry-plugin` 0.7.1, `@cofhe/mock-contracts` 0.7.1,
> `@fhenixprotocol/cofhe-contracts` 0.2.0. See
> [Migrating to 0.7](https://cofhe-docs.fhenix.zone/client-sdk/introduction/migrating-to-0-7)
> for what changed.

## Test Setup

Test contracts inherit `CofheTest` from the Foundry plugin (which itself extends forge-std's
`Test`) and call `deployMocks()` in `setUp()`. That deploys and wires the whole mock stack:
`MockTaskManager`, `MockACL`, `ACPTimestampRevoker`, `ACPShareRegistry`, `MockZkVerifier`,
`MockZkVerifierSigner`, `MockThresholdNetwork` and `MockThresholdNetworkSigner`.

User accounts are represented by `CofheClient` instances — the in-Solidity stand-in for the
JavaScript SDK. A client encrypts inputs, builds ACPs, and decrypts outputs on behalf of one
address.

```solidity
import {CofheTest} from "@cofhe/foundry-plugin/contracts/CofheTest.sol";
import {CofheClient} from "@cofhe/foundry-plugin/contracts/CofheClient.sol";
import {FHE, euint32, externalEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

contract MyTest is CofheTest {
    CofheClient public bob;
    MyContract public target;

    uint256 constant BOB_PKEY = 0xB0B;

    function setUp() public {
        deployMocks();

        bob = createCofheClient();
        bob.connect(BOB_PKEY);   // bob.account() is now derived from the key

        vm.prank(bob.account());
        target = new MyContract();
    }
}
```

Available types:

```solidity
// Encrypted state types (each wraps a bytes32 handle)
ebool, euint8, euint16, euint32, euint64, euint128, eaddress

// Encrypted user-input handles (paired with a `bytes` proof)
externalEbool, externalEuint8, externalEuint16, externalEuint32,
externalEuint64, externalEuint128, externalEaddress

// Cross-contract transfer handles
sharedEbool, sharedEuint8, sharedEuint16, sharedEuint32,
sharedEuint64, sharedEuint128, sharedEaddress
```

> **Note:** there is no `euint256` / `InEuint256` in 0.2.0 — `euint128` is the widest integer.

### foundry.toml

The mock stack is large and compiled without the optimizer, so a test contract inheriting
`CofheTest` easily exceeds the EVM's 24 KB limit. Raise it:

```toml
[profile.default]
evm_version = "cancun"      # required: transient storage (tstore) for allowTransient
code_size_limit = 300000
```

---

## Encrypted Types

All encrypted types are `bytes32` newtypes. The value they hold is a **handle** (pointer) into
mock storage — not the plaintext.

| Type | Plaintext equivalent |
|------|---------------------|
| `ebool` | `bool` |
| `euint8` | `uint8` |
| `euint16` | `uint16` |
| `euint32` | `uint32` |
| `euint64` | `uint64` |
| `euint128` | `uint128` |
| `eaddress` | `address` |

### unwrap / wrap

```solidity
euint32 encrypted = FHE.asEuint32(42);

bytes32 handle = euint32.unwrap(encrypted);   // raw handle
euint32 restored = euint32.wrap(handle);      // back to the newtype
```

`CofheClient` helpers take `bytes32`. `MockThresholdNetwork` methods take `uint256`, so cast with
`uint256(euint32.unwrap(value))`.

---

## FHE Operations Reference

### Trivial Encryption (plaintext to encrypted)

Converts a public value into an encrypted type. The value is known, so this does not provide
confidentiality — only FHE-operation compatibility.

```solidity
ebool    a = FHE.asEbool(true);
euint8   b = FHE.asEuint8(255);
euint16  c = FHE.asEuint16(1000);
euint32  d = FHE.asEuint32(42);
euint64  e = FHE.asEuint64(1_000_000_000);
euint128 f = FHE.asEuint128(type(uint64).max);
eaddress g = FHE.asEaddress(msg.sender);
```

Use in contracts for constants (e.g. `FHE.asEuint32(1)` for a ONE value).

### Encrypted Input Verification (user-encrypted to on-chain)

**Changed in 0.7.** The `InEuintXX` input structs are gone. An encrypted user input is now an
`externalEuintXX` handle plus a `bytes` proof — the ZK-verifier signature covering the batch the
handle belongs to:

```solidity
function deposit(externalEuint32 encryptedAmount, bytes memory proof) public {
    euint32 amount = FHE.asEuint32(encryptedAmount, proof);
    // amount is now an on-chain encrypted value
}
```

The proof is bound to **both** the encrypting account and the consuming contract address, so a
signed input observed on-chain cannot be replayed into a different contract.

#### Multiple encrypted parameters

One signature covers a whole batch. Group the handles into an array and verify them together:

```solidity
function transfer(
    address to,
    externalEuint32 amount,
    externalEuint32 fee,
    bytes calldata signature
) public {
    externalEuint32[] memory packed = new externalEuint32[](2);
    packed[0] = amount;
    packed[1] = fee;
    euint32[] memory values = FHE.asEuint32s(packed, signature);
    // values[0] = amount, values[1] = fee
}
```

Order matters: the signature covers `keccak256(h_0 || … || h_n)` in the order the batch was
created. Reordering or partially submitting a batch fails verification.

See [Creating Encrypted Inputs in Tests](#createexternal---creating-encrypted-inputs).

### Cross-Contract Encrypted Values

**New in 0.7.** Passing a bare `euintXX` between contracts still compiles but the receiver has no
ACL access to it. Use the `sharedEuintXX` handoff instead — both sides must migrate together, or
the call reverts with `NotShared`.

```solidity
// Sender
token.pull(FHE.shareEuint64(amount, address(token)));

// Receiver
function pull(sharedEuint64 shared) external {
    euint64 amount = FHE.receiveEuint64Param(shared);
}
```

For a value returned *from* a call, the callee shares with `msg.sender` and the caller unwraps
with `FHE.receiveEuint64FromCall(shared, callee)` — passing the wrong callee address is
exploitable, so it must be the contract that was actually called.

### Arithmetic

Available for `euint8`, `euint16`, `euint32`, `euint64`, `euint128`:

```solidity
euint32 sum  = FHE.add(a, b);   // a + b
euint32 diff = FHE.sub(a, b);   // a - b
euint32 prod = FHE.mul(a, b);   // a * b
euint32 quot = FHE.div(a, b);   // a / b  (integer division, truncates)
euint32 rem  = FHE.rem(a, b);   // a % b
euint32 sq   = FHE.square(a);   // a * a  (more efficient than mul(a, a))
```

### Comparisons

Return `ebool`. Available for all integer types and `eaddress` (`eq` / `ne` only):

```solidity
ebool isEqual     = FHE.eq(a, b);    // a == b
ebool isNotEqual  = FHE.ne(a, b);    // a != b
ebool isLess      = FHE.lt(a, b);    // a < b
ebool isLessEq    = FHE.lte(a, b);   // a <= b
ebool isGreater   = FHE.gt(a, b);    // a > b
ebool isGreaterEq = FHE.gte(a, b);   // a >= b
```

### Min / Max

```solidity
euint32 lower  = FHE.min(a, b);
euint32 higher = FHE.max(a, b);
```

### Bitwise Operations

```solidity
euint32 result = FHE.and(a, b);   // bitwise AND
euint32 result = FHE.or(a, b);    // bitwise OR
euint32 result = FHE.xor(a, b);   // bitwise XOR
euint32 result = FHE.not(a);      // bitwise NOT

// Boolean versions
ebool result = FHE.and(boolA, boolB);
ebool result = FHE.or(boolA, boolB);
ebool result = FHE.not(boolA);
```

### Bit Shifts

```solidity
euint32 result = FHE.shl(a, shift);   // shift left
euint32 result = FHE.shr(a, shift);   // shift right
euint32 result = FHE.rol(a, shift);   // rotate left
euint32 result = FHE.ror(a, shift);   // rotate right
```

### Select (Encrypted Conditional)

The FHE equivalent of a ternary operator. Picks between two values based on an encrypted
condition **without revealing the condition**.

```solidity
euint32 result = FHE.select(condition, ifTrue, ifFalse);
```

Works with all encrypted types (`euint*`, `ebool`, `eaddress`):

```solidity
// Real-world pattern: apply fee based on encrypted threshold
ebool isLargeAmount = FHE.gt(amount, threshold);
euint32 fee = FHE.select(isLargeAmount, highFee, lowFee);
euint32 net = FHE.sub(amount, fee);
```

### Decryption

Decryption is a three-step flow: **permission** (on-chain) → **decrypt** (off-chain) →
**publish/verify** (on-chain with the Threshold Network signature).

```solidity
// In your contract:

// Step 1: Grant public decryption permission
function allowBalancePublicly() public {
    FHE.allowPublic(balance);
}

// Step 3: Publish the verified result on-chain (after off-chain decryption)
function revealBalance(uint32 plaintext, bytes memory signature) public {
    FHE.publishDecryptResult(balance, plaintext, signature);
}

// Step 4: Read the published result
function getBalance() external view returns (uint256) {
    (uint256 value, bool ready) = FHE.getDecryptResultSafe(balance);
    if (!ready) revert("Not ready");
    return value;
}
```

In production, Step 2 happens off-chain via the client SDK
(`client.decryptForTx(ctHash).withoutACP().execute()`).

In tests, `CofheClient.decryptForTx_withoutACP()` simulates that step and returns a **real
signature** the contract will verify:

```solidity
function test_DecryptFlow() public {
    myContract.allowBalancePublicly();

    // Simulate the off-chain SDK call
    bytes32 ctHash = euint32.unwrap(myContract.balance());
    (, uint256 plaintext, bytes memory sig) = bob.decryptForTx_withoutACP(ctHash);

    // Publish the result on-chain
    myContract.revealBalance(uint32(plaintext), sig);

    assertEq(myContract.getBalance(), plaintext);
}
```

#### publishDecryptResult vs verifyDecryptResult

| Aspect | `publishDecryptResult` | `verifyDecryptResult` |
|--------|------------------------|----------------------|
| **Storage** | Stores result on-chain | No storage |
| **Visibility** | Other contracts can read via `getDecryptResultSafe` | Private to current call |
| **Use case** | Public reveals (auctions, votes, counters) | One-time verification (transfers, burns) |

---

## Access Control (ACL)

Every FHE operation produces a new ciphertext handle. You must explicitly grant permissions on
each new handle, or subsequent operations will fail.

### FHE.allowThis(value)

Grants the **current contract** (`address(this)`) permission to operate on the encrypted value.
Call this after every operation producing a handle the contract needs later.

```solidity
count = FHE.add(count, ONE);
FHE.allowThis(count);
```

### FHE.allowSender(value)

Grants `msg.sender` permission to **view/unseal** the value off-chain.

```solidity
count = FHE.add(count, ONE);
FHE.allowThis(count);     // contract can operate on it
FHE.allowSender(count);   // caller can unseal it with an ACP
```

### FHE.allow(value, address)

Grants a **specific address** permission.

```solidity
FHE.allow(secret, auditorAddress);
```

### FHE.allowGlobal(value) / FHE.allowPublic(value)

`allowGlobal` grants **any account** permission to use and unseal the value. `allowPublic` marks
the handle as publicly decryptable — the prerequisite for the `decryptForTx_withoutACP` →
`publishDecryptResult` flow above. Both effectively make the value public.

```solidity
FHE.allowGlobal(publicResult);
FHE.allowPublic(finalScore);
```

### FHE.allowTransient(value, address)

Grants a permission that expires at the end of the current **transaction**, via EIP-1153
transient storage.

```solidity
FHE.allowTransient(intermediate, helperContract);
```

> **0.7 gotcha:** transient allowances no longer survive across transactions. Code that relied on
> a transient allowance still being present in a later call must switch to `allow`/`allowThis`.

### Typical Pattern

```solidity
function increment() public {
    count = FHE.add(count, ONE);
    FHE.allowThis(count);     // so the contract can use count next time
    FHE.allowSender(count);   // so the caller can unseal count
}
```

---

## CofheTest Helper Functions

Available in any test contract inheriting `CofheTest`.

### expectPlaintext -- Assert Encrypted Values

The primary assertion for FHE tests: checks the plaintext behind an encrypted handle.

```solidity
expectPlaintext(ebool encrypted,    bool expected);
expectPlaintext(euint8 encrypted,   uint8 expected);
expectPlaintext(euint16 encrypted,  uint16 expected);
expectPlaintext(euint32 encrypted,  uint32 expected);
expectPlaintext(euint64 encrypted,  uint64 expected);
expectPlaintext(euint128 encrypted, uint128 expected);
expectPlaintext(eaddress encrypted, address expected);

// Every overload also accepts a custom failure message as the last parameter
expectPlaintext(euint32 encrypted, uint32 expected, string memory message);

// Raw handle overload
expectPlaintext(bytes32 ctHash, uint256 expected);
```

```solidity
expectPlaintext(counter.count(), uint32(42));
```

### getPlaintext -- Read Plaintext from the Mock

Returns the plaintext behind a handle (reverts if the handle is unknown to the mock). Same typed
overloads as `expectPlaintext`, plus a `bytes32` version.

```solidity
assertEq(getPlaintext(product), uint32(30));
uint256 raw = getPlaintext(euint32.unwrap(counter.count()));
```

For low-level inspection, the mock's storage maps are public:

```solidity
uint256 ct = uint256(euint32.unwrap(value));
assertTrue(mockTaskManager.inMockStorage(ct));
assertEq(mockTaskManager.mockStorage(ct), 333);
```

### enableLogs / disableLogs

Toggle plaintext operation logging from `MockTaskManager` for debugging:

```solidity
enableLogs();   // prints FHE operations to console
disableLogs();
```

### Mock handles

`deployMocks()` exposes each mock as a public member: `mockTaskManager`, `mockAcl`, `acpRevoker`,
`acpShareRegistry`, `mockZkVerifier`, `mockZkVerifierSigner`, `mockThresholdNetwork` and
`mockThresholdNetworkSigner`. Use them for assertions the client helpers don't cover (e.g.
asserting a *denied* unseal, where `decryptForView` would revert).

---

## CofheClient Reference

`createCofheClient()` returns an unconnected client; `connect(pkey)` binds it to an account.

```solidity
CofheClient bob = createCofheClient();
bob.connect(0xB0B);
address bobAddr = bob.account();
```

### createExternal* -- Creating Encrypted Inputs

Each helper returns a `(handle, proof)` pair bound to the account **and** to the contract that
will consume it:

```solidity
(externalEbool    h, bytes memory p) = bob.createExternalEbool(true, address(target));
(externalEuint8   h, bytes memory p) = bob.createExternalEuint8(255, address(target));
(externalEuint16  h, bytes memory p) = bob.createExternalEuint16(1000, address(target));
(externalEuint32  h, bytes memory p) = bob.createExternalEuint32(42, address(target));
(externalEuint64  h, bytes memory p) = bob.createExternalEuint64(1e12, address(target));
(externalEuint128 h, bytes memory p) = bob.createExternalEuint128(val, address(target));
(externalEaddress h, bytes memory p) = bob.createExternalEaddress(addr, address(target));
```

**Important: both bindings must match.** `FHE.asEuint32(handle, proof)` verifies the proof against
`msg.sender` (the account) and the calling contract's own address (the consumer). So `vm.prank` as
the client's account, and pass the consuming contract to `createExternal*`:

```solidity
(externalEuint32 handle, bytes memory proof) = bob.createExternalEuint32(2000, address(counter));

vm.prank(bob.account());   // msg.sender inside counter = bob
counter.reset(handle, proof);
```

Calling `FHE.asE*()` directly in a test makes the test contract the consumer. To exercise a
different sender, route through a helper contract:

```solidity
contract EncryptedInputHelper {
    function verifyEuint32(externalEuint32 input, bytes memory proof) external returns (euint32) {
        return FHE.asEuint32(input, proof);
    }
}

// In test:
(externalEuint32 input, bytes memory proof) = alice.createExternalEuint32(42, address(helper));
vm.prank(alice.account());
euint32 result = helper.verifyEuint32(input, proof);
```

### createEuint32sBatch -- Batched Inputs

Produces many handles sharing one signature, for contract functions that take several encrypted
parameters:

```solidity
uint32[] memory values = new uint32[](3);
values[0] = 10; values[1] = 20; values[2] = 30;

(externalEuint32[] memory handles, bytes memory signature) =
    alice.createEuint32sBatch(values, address(helper));

vm.prank(alice.account());
euint32[] memory verified = helper.verifyEuint32Batch(handles, signature);
```

### ACP Helpers (formerly "permits")

**Renamed in 0.7:** `Permission` → `ACP` (Access Control Permission), and the client's
`permit_*` helpers are now `ACP_*`. An ACP is the signed proof a user presents off-chain to
unseal a value they have ACL access to.

```solidity
import {ACP} from "@cofhe/mock-contracts/contracts/Permissioned.sol";
```

| Function | Description |
|----------|-------------|
| `ACP_createSelf()` | Self-ACP for the connected account, signed with its key |
| `ACP_createShared(recipient)` | Issuer half of a shared ACP (no sealing key yet) |
| `ACP_exportShared(acp)` | Strips recipient-specific fields for transmission |
| `ACP_importShared(export)` | Recipient completes it: adds sealing key + signature |
| `createBaseACP()` | A blank ACP with default fields, for hand-rolled scopes |
| `createSealingKey(seed)` | Deterministic sealing key from a seed |

An ACP is scoped: `SCOPE_GLOBAL` (all of the issuer's values — the default), `SCOPE_CONTRACT`
(values readable by the listed `contracts`), or `SCOPE_HANDLES` (only the listed `handles`).

```solidity
ACP memory bobAcp = bob.ACP_createSelf();

// Sharing bob's access with alice (two-step signing)
ACP memory shared = bob.ACP_createShared(alice.account());
ACP memory aliceAcp = alice.ACP_importShared(bob.ACP_exportShared(shared));
```

> `ACP_exportShared` is for shared ACPs only — exporting a self-ACP throws in 0.7.

### decryptForView -- Off-chain Read

Simulates the seal/unseal round-trip a client performs to read a value. Reverts if the ACP does
not grant access.

```solidity
bytes32 ctHash = euint32.unwrap(counter.count());
uint256 value = bob.decryptForView(ctHash, bob.ACP_createSelf());
assertEq(value, 1);
```

To assert a **denial**, query the mock directly instead (`decryptForView` would revert):

```solidity
(bool allowed, string memory error, ) = mockThresholdNetwork.querySealOutput(
    uint256(ctHash), block.chainid, alice.ACP_createSelf()
);
assertFalse(allowed);
assertEq(error, "NotAllowed");
```

### decryptForTx_withoutACP / decryptForTx_withACP

Simulate the off-chain `client.decryptForTx()` call. Both return
`(ctHash, plaintext, signature)`, where `signature` is a valid Threshold Network signature that
`FHE.publishDecryptResult` / `FHE.verifyDecryptResult` will accept.

```solidity
// After FHE.allowPublic(...)
(, uint256 plaintext, bytes memory sig) = bob.decryptForTx_withoutACP(ctHash);

// After FHE.allow(value, bob) -- requires an ACP proving bob's access
(, uint256 plaintext, bytes memory sig) = bob.decryptForTx_withACP(ctHash, bob.ACP_createSelf());
```

---

## Common Test Patterns

### 1. Basic Operation Test

```solidity
function test_Addition() public {
    euint32 a = FHE.asEuint32(10);
    euint32 b = FHE.asEuint32(20);
    euint32 result = FHE.add(a, b);
    expectPlaintext(result, uint32(30));
}
```

### 2. Testing Contract Functions

```solidity
function test_Increment() public {
    expectPlaintext(counter.count(), uint32(0));

    vm.prank(bob.account());
    counter.increment();

    expectPlaintext(counter.count(), uint32(1));
}
```

### 3. Encrypted User Input

```solidity
function test_ResetWithEncryptedInput() public {
    (externalEuint32 handle, bytes memory proof) =
        bob.createExternalEuint32(2000, address(counter));

    vm.prank(bob.account());
    counter.reset(handle, proof);

    expectPlaintext(counter.count(), uint32(2000));
}
```

### 4. On-chain Decryption

```solidity
function test_DecryptFlow() public {
    // Step 1: allow public decryption
    vm.prank(bob.account());
    counter.allowCounterPublicly();

    // Before publish: not ready
    vm.expectRevert("Value is not ready");
    counter.getDecryptedValue();

    // Step 2: simulate the off-chain decryption
    bytes32 ctHash = euint32.unwrap(counter.count());
    (, uint256 plaintext, bytes memory sig) = bob.decryptForTx_withoutACP(ctHash);

    // Step 3: publish the signed result on-chain
    counter.revealCounter(uint32(plaintext), sig);

    // Step 4: read it back
    assertEq(counter.getDecryptedValue(), plaintext);
}
```

### 5. ACL / ACP Verification

Only the caller who executed an operation can unseal its result:

```solidity
function test_CallerCanUnseal() public {
    vm.prank(bob.account());
    counter.increment();

    bytes32 ctHash = euint32.unwrap(counter.count());

    uint256 decrypted = bob.decryptForView(ctHash, bob.ACP_createSelf());
    assertEq(decrypted, 1);
}

function test_NonCallerCannotUnseal() public {
    vm.prank(bob.account());
    counter.increment();

    uint256 ctHash = uint256(euint32.unwrap(counter.count()));

    (bool allowed, string memory error, ) = mockThresholdNetwork.querySealOutput(
        ctHash, block.chainid, alice.ACP_createSelf()
    );
    assertFalse(allowed);
    assertEq(error, "NotAllowed");
}
```

### 6. Batched Encrypted Inputs

```solidity
function test_BatchReorderFails() public {
    uint32[] memory values = new uint32[](2);
    values[0] = 1; values[1] = 2;

    (externalEuint32[] memory handles, bytes memory signature) =
        alice.createEuint32sBatch(values, address(helper));

    externalEuint32[] memory reordered = new externalEuint32[](2);
    reordered[0] = handles[1];
    reordered[1] = handles[0];

    vm.prank(alice.account());
    vm.expectRevert();               // signature covers the original order
    helper.verifyEuint32Batch(reordered, signature);
}
```

### 7. Fuzz Testing

```solidity
function testFuzz_Add(uint32 a, uint32 b) public {
    vm.assume(uint64(a) + uint64(b) <= type(uint32).max);
    euint32 ea = FHE.asEuint32(a);
    euint32 eb = FHE.asEuint32(b);
    euint32 result = FHE.add(ea, eb);
    expectPlaintext(result, a + b);
}
```

### 8. Low-level Mock Storage Inspection

```solidity
function test_InspectStorage() public {
    euint32 a = FHE.asEuint32(111);
    euint32 b = FHE.asEuint32(222);
    euint32 c = FHE.add(a, b);

    uint256 ct = uint256(euint32.unwrap(c));
    assertTrue(mockTaskManager.inMockStorage(ct));
    assertEq(mockTaskManager.mockStorage(ct), 333);
}
```

---

## ACL Enforcement in the Mock

The mock **does enforce ACL** on FHE operation inputs. Every FHE operation (`add`, `sub`, `mul`,
…) goes through `MockTaskManager.createTask()`, which calls `checkAllowed()` on each input handle:

```
Contract calls FHE.add(a, b)
  → Impl.mathOp() calls ITaskManager.createTask(...)
    → validateEncryptedHashes() loops over inputs
      → checkAllowed(ctHash):
          if NOT trivially encrypted AND NOT allowed → revert ACLNotAllowed
```

**Trivially encrypted values** (created via `FHE.asEuint32(plaintext)`) skip the ACL check — they
are public constants and always allowed. **Operation results** are not trivially encrypted, so
they require ACL permission. If a contract forgets `FHE.allowThis()` on a result, the next
operation using it reverts with `ACLNotAllowed(ctHash, sender)`.

### What can be tested

| Check | How to test |
|-------|------------|
| Contract has permission to operate | Skip `FHE.allowThis()` on a result, then use it — should revert with `ACLNotAllowed` |
| Caller can unseal a value | `client.decryptForView(ctHash, client.ACP_createSelf())` returns the plaintext |
| Unauthorized address cannot unseal | `mockThresholdNetwork.querySealOutput(...)` returns `allowed = false, error = "NotAllowed"` |
| Permission transfers on new operation | After a new caller executes an operation, only they can unseal the new result |
| Global permissions | Call `FHE.allowGlobal()` — any address can then unseal |
| Transient permissions | Call `FHE.allowTransient()` — permission only lasts for the current transaction |
| Input proof binding | Submit a handle to a contract other than the one it was bound to — verification reverts |

### Testing ACL reverts

```solidity
function test_RevertWithoutAllowThis() public {
    euint32 a = FHE.asEuint32(10);  // trivially encrypted, always allowed
    euint32 b = FHE.asEuint32(5);
    euint32 result = FHE.add(a, b); // result is NOT trivially encrypted
    // FHE.allowThis(result);       // <-- deliberately skipped

    vm.expectRevert();
    FHE.add(result, a);
}
```

> **Note:** this only applies to non-trivially encrypted values. `FHE.asEuint32(plaintext)` always
> passes the ACL check regardless of permissions.

---

## Mock Limitations

The mocks simulate FHE behavior deterministically. Differences from the real coprocessor:

| Operation | Mock behavior | Real coprocessor |
|-----------|--------------|-----------------|
| `FHE.not(value)` | Boolean NOT (`value == 1 ? 0 : 1`) | Bitwise NOT |
| `FHE.rol(a, b)` | Simple shift left (no wrap) | True bit rotation |
| `FHE.ror(a, b)` | Simple shift right (no wrap) | True bit rotation |
| Input proofs | ECDSA signature from a fixed mock ZK-verifier key; no actual ZK proof | Real ZK proof verification |
| Decryption signatures | Signed by a fixed mock Threshold Network key — always use the signature returned by `decryptForTx_*`, an empty `""` is rejected | Real threshold signature |
| Trivially encrypted ACL | Skipped (always allowed) | Same behavior |
