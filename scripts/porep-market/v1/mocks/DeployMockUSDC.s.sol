// SPDX-License-Identifier: MIT
pragma solidity =0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDC} from "./MockUSDC.sol";

contract DeployMockUSDC is Script {
    function run() external {
        vm.startBroadcast();
        MockUSDC usdc = new MockUSDC("Mock USDC", "USDC");
        vm.stopBroadcast();
        console.log("USDC_DEPLOYED_TO=%s", address(usdc));
    }
}
