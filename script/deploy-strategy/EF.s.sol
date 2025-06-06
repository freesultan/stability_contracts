// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {EqualizerFarmStrategy} from "../../src/strategies/EqualizerFarmStrategy.sol";

contract DeployEF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new EqualizerFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
