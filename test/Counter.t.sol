// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {CofheTest} from "@cofhe/foundry-plugin/contracts/CofheTest.sol";
import {CofheClient} from "@cofhe/foundry-plugin/contracts/CofheClient.sol";
import {euint32, externalEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {ACP} from "@cofhe/mock-contracts/contracts/Permissioned.sol";
import {Counter} from "../src/Counter.sol";

contract CounterTest is CofheTest {
    Counter public counter;
    CofheClient public bob;
    CofheClient public alice;

    uint256 constant BOB_PKEY = 0xB0B;
    uint256 constant ALICE_PKEY = 0xA11CE;

    function setUp() public {
        deployMocks();

        bob = createCofheClient();
        bob.connect(BOB_PKEY);

        alice = createCofheClient();
        alice.connect(ALICE_PKEY);

        vm.prank(bob.account());
        counter = new Counter();
    }

    // --- Functionality ---

    function test_ShouldIncrementTheCounter() public {
        expectPlaintext(counter.count(), uint32(0));

        vm.prank(bob.account());
        counter.increment();

        expectPlaintext(counter.count(), uint32(1));
    }

    function test_ShouldDecrementTheCounter() public {
        vm.prank(bob.account());
        counter.increment();
        expectPlaintext(counter.count(), uint32(1));

        vm.prank(bob.account());
        counter.decrement();
        expectPlaintext(counter.count(), uint32(0));
    }

    function test_ShouldEncryptInputAndResetCounter() public {
        // 0.7: encrypted inputs are a handle + proof pair, bound to the consuming contract.
        (externalEuint32 handle, bytes memory proof) = bob.createExternalEuint32(2000, address(counter));

        vm.prank(bob.account());
        counter.reset(handle, proof);

        expectPlaintext(counter.count(), uint32(2000));
    }

    function test_ShouldHandleMultipleOperationsInSequence() public {
        (externalEuint32 handle, bytes memory proof) = bob.createExternalEuint32(10, address(counter));
        vm.prank(bob.account());
        counter.reset(handle, proof);

        // 10 -> 11 -> 12 -> 13 -> 12
        vm.startPrank(bob.account());
        counter.increment();
        counter.increment();
        counter.increment();
        counter.decrement();
        vm.stopPrank();

        expectPlaintext(counter.count(), uint32(12));
    }

    // --- On-chain Decryption (allowPublic → decryptForTx → publishDecryptResult) ---

    function test_ShouldRevertBeforeDecryptionPublished() public {
        (externalEuint32 handle, bytes memory proof) = bob.createExternalEuint32(42, address(counter));
        vm.prank(bob.account());
        counter.reset(handle, proof);

        vm.prank(bob.account());
        counter.allowCounterPublicly();

        vm.expectRevert("Value is not ready");
        counter.getDecryptedValue();
    }

    function test_ShouldReturnDecryptedValueAfterPublish() public {
        (externalEuint32 handle, bytes memory proof) = bob.createExternalEuint32(42, address(counter));
        vm.prank(bob.account());
        counter.reset(handle, proof);

        // Step 1: contract grants public decrypt permission
        vm.prank(bob.account());
        counter.allowCounterPublicly();

        // Step 2: SDK fetches plaintext + threshold-network signature
        bytes32 ctHash = euint32.unwrap(counter.count());
        (, uint256 plaintext, bytes memory sig) = bob.decryptForTx_withoutACP(ctHash);
        assertEq(plaintext, 42);

        // Step 3: contract verifies signature and stores plaintext
        counter.revealCounter(uint32(plaintext), sig);

        // Step 4: read the result
        assertEq(counter.getDecryptedValue(), 42);
    }

    function test_ShouldCheckPlaintextViaExpectPlaintext() public {
        vm.startPrank(bob.account());
        counter.increment();
        counter.increment();
        vm.stopPrank();

        expectPlaintext(counter.count(), uint32(2));
    }

    // --- ACL & ACP Unsealing ---

    function test_CallerCanUnsealAfterIncrement() public {
        vm.prank(bob.account());
        counter.increment();

        bytes32 ctHash = euint32.unwrap(counter.count());

        ACP memory bobAcp = bob.ACP_createSelf();
        uint256 decrypted = bob.decryptForView(ctHash, bobAcp);
        assertEq(decrypted, 1, "Decrypted value should be 1");
    }

    function test_NonCallerCannotUnsealAfterIncrement() public {
        vm.prank(bob.account());
        counter.increment();

        uint256 ctHash = uint256(euint32.unwrap(counter.count()));

        // Alice has no ACL permission on this count -- assert deny via mock directly
        // (decryptForView would revert on deny).
        ACP memory aliceAcp = alice.ACP_createSelf();

        (bool allowed, string memory error, ) = mockThresholdNetwork.querySealOutput(ctHash, block.chainid, aliceAcp);
        assertFalse(allowed, "Alice should NOT be allowed to unseal bob's count");
        assertEq(error, "NotAllowed");
    }

    function test_SealOutputPermissionFlow() public {
        vm.prank(bob.account());
        counter.increment();

        bytes32 ctHash = euint32.unwrap(counter.count());

        ACP memory bobAcp = bob.ACP_createSelf();
        uint256 unsealed = bob.decryptForView(ctHash, bobAcp);
        assertEq(unsealed, 1, "Unsealed value should be 1");
    }

    function test_PermissionTransfersToNewCaller() public {
        vm.prank(bob.account());
        counter.increment();

        // Alice increments -- she gets allowSender on the new count
        vm.prank(alice.account());
        counter.increment();

        bytes32 ctHash = euint32.unwrap(counter.count());

        // Alice can unseal the current count
        ACP memory aliceAcp = alice.ACP_createSelf();
        uint256 aliceDecrypted = alice.decryptForView(ctHash, aliceAcp);
        assertEq(aliceDecrypted, 2);

        // Bob cannot unseal the current count (alice was the last caller)
        ACP memory bobAcp = bob.ACP_createSelf();
        (bool bobAllowed, string memory error, ) = mockThresholdNetwork.querySealOutput(
            uint256(ctHash),
            block.chainid,
            bobAcp
        );
        assertFalse(bobAllowed, "Bob should NOT unseal alice's count");
        assertEq(error, "NotAllowed");
    }

    // --- Fuzz Tests ---

    function testFuzz_ResetCounter(uint32 value) public {
        (externalEuint32 handle, bytes memory proof) = bob.createExternalEuint32(value, address(counter));

        vm.prank(bob.account());
        counter.reset(handle, proof);

        expectPlaintext(counter.count(), value);
    }
}
