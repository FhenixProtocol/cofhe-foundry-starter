// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@fhenixprotocol/cofhe-contracts/FHE.sol";

contract Counter {
    euint32 public count;
    euint32 public ONE;
    ebool public isInitialized;

    constructor() {
        ONE = FHE.asEuint32(1);
        count = FHE.asEuint32(0);

        isInitialized = FHE.asEbool(false);
        isInitialized = FHE.asEbool(true);

        FHE.allowThis(count);
        FHE.allowThis(ONE);

        FHE.gte(count, ONE);

        FHE.allowSender(count);
    }

    function increment() public {
        count = FHE.add(count, ONE);
        FHE.allowThis(count);
        FHE.allowSender(count);
    }

    function decrement() public {
        count = FHE.sub(count, ONE);
        FHE.allowThis(count);
        FHE.allowSender(count);
    }

    /// @notice Reset the counter to an encrypted user input.
    /// @dev In cofhe-contracts 0.2.0 the `InEuintXX` input structs are gone. Encrypted user
    ///      inputs arrive as an `externalEuintXX` handle plus a `bytes` proof (the signature
    ///      covering the batch the handle was encrypted in).
    function reset(externalEuint32 value, bytes memory proof) public {
        count = FHE.asEuint32(value, proof);
        FHE.allowThis(count);
        FHE.allowSender(count);
    }

    function allowCounterPublicly() public {
        FHE.allowPublic(count);
    }

    function revealCounter(uint32 plaintext, bytes memory signature) public {
        FHE.publishDecryptResult(count, plaintext, signature);
    }

    function getDecryptedValue() external view returns(uint256) {
        (uint256 value, bool decrypted) = FHE.getDecryptResultSafe(count);
        if (!decrypted)
            revert("Value is not ready");

        return value;
    }
}
