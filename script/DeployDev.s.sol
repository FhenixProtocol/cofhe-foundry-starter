// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Counter} from "../src/Counter.sol";
import {MockTaskManager} from "@cofhe/mock-contracts/MockTaskManager.sol";
import {MockThresholdNetwork} from "@cofhe/mock-contracts/MockThresholdNetwork.sol";
import {TASK_MANAGER_ADDRESS} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/// @notice CoFHE mock bytecodes MUST be etched at hardcoded addresses BEFORE running this script.
///         Use script/dev.sh which handles etching and then calls this script.
contract DeployDev is Script {
    address constant ACL_ADDR = 0xa6Ea4b5291d044D93b73b3CFf3109A1128663E8B;
    address constant THRESHOLD_NETWORK_ADDR = 0x0000000000000000000000000000000000005002;

    function run() external {
        require(block.chainid == 31337, "DeployDev: localhost only");

        vm.startBroadcast();

        // Initialize CoFHE mocks (bytecodes MUST have etched)
        console.log("Initializing CoFHE mocks...");
        MockTaskManager tm = MockTaskManager(TASK_MANAGER_ADDRESS);
        tm.initialize(msg.sender);
        tm.setSecurityZoneMin(0);
        tm.setSecurityZoneMax(1);
        tm.setACLContract(ACL_ADDR);

        MockThresholdNetwork tn = MockThresholdNetwork(THRESHOLD_NETWORK_ADDR);
        tn.initialize(TASK_MANAGER_ADDRESS, ACL_ADDR);

        console.log("MockTaskManager:", TASK_MANAGER_ADDRESS);
        console.log("MockACL:", ACL_ADDR);
        console.log("MockThresholdNetwork:", THRESHOLD_NETWORK_ADDR);

        Counter counter = new Counter();
        console.log("Counter deployed to:", address(counter));

        vm.stopBroadcast();
    }
}
