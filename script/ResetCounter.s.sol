// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Counter} from "../src/Counter.sol";
import {externalEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

// Reset the Counter to a new encrypted value.
//
// Since CoFHE 0.7 an encrypted user input is an `externalEuint32` handle plus a `bytes` proof
// (the signature covering the batch the handle belongs to). The proof is bound to both the
// encrypting account and the consuming contract, so it must be generated off-chain against the
// deployed Counter address:
//
//   const [handle, signature] = await client
//     .encryptInputs([value])
//     .setConsumingContract(counterAddress)
//     .execute();
//
// For local testing, use the test suite instead (test/Counter.t.sol) which uses mock helpers.
//
// Usage on testnet:
//   1. Use @cofhe/sdk to generate the handle and signature off-chain (snippet above)
//   2. Pass them as env vars: CT_HASH, PROOF
//   3. Run: forge script script/ResetCounter.s.sol --rpc-url <network> --broadcast
contract ResetCounter is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address counterAddress = vm.envAddress("COUNTER_ADDRESS");

        // Read the pre-computed encrypted input handle and its proof
        externalEuint32 handle = externalEuint32.wrap(vm.envBytes32("CT_HASH"));
        bytes memory proof = vm.envBytes("PROOF");

        Counter counter = Counter(counterAddress);

        vm.startBroadcast(deployerPrivateKey);
        counter.reset(handle, proof);
        vm.stopBroadcast();

        console.log("Counter reset successfully");
    }
}
