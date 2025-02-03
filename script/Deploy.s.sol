// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import { Arbitrum } from "lib/spark-address-registry/src/Arbitrum.sol";
import { Base }     from "lib/spark-address-registry/src/Base.sol";

import { PSM3Deploy } from "deploy/PSM3Deploy.sol";

contract DeployArbitrumOne is Script {

    function run() external {
        vm.createSelectFork(getChain("arbitrum_one").rpcUrl);

        console.log("Deploying PSM...");

        vm.startBroadcast();

        address psm = PSM3Deploy.deploy({
            owner        : Arbitrum.SPARK_EXECUTOR,
            usdc         : Arbitrum.USDC,
            usds         : Arbitrum.USDS,
            susds        : Arbitrum.SUSDS,
            rateProvider : Arbitrum.SSR_AUTH_ORACLE
        });

        vm.stopBroadcast();

        console.log("PSM3 deployed at:", psm);
    }

}

contract DeployBase is Script {

    function run() external {
        vm.createSelectFork(getChain("base").rpcUrl);

        console.log("Deploying PSM...");

        vm.startBroadcast();

        address psm = PSM3Deploy.deploy({
            owner        : Base.SPARK_EXECUTOR,
            usdc         : Base.USDC,
            usds         : Base.USDS,
            susds        : Base.SUSDS,
            rateProvider : Base.SSR_AUTH_ORACLE
        });

        vm.stopBroadcast();

        console.log("PSM3 deployed at:", psm);
    }

}
