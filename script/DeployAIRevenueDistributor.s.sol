// DeployAIRevenueDistributor.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {AIRevenueDistributor} from "../src/AIRevenueDistribtion.sol";

contract DeployAIRevenueDistributor is Script {
    bytes32 private jobId = "ca98366cc7314957b8c012c72f05aeeb"; 

     event ContractDeployed(address indexed distributorAddress);

    function run() external {
        address oracle = vm.envAddress("ORACLE_ADDRESS");
        uint256 fee = 0.1 ether; 
        address link = vm.envAddress("LINK_TOKEN_ADDRESS");

        vm.startBroadcast();
        AIRevenueDistributor distributor = new AIRevenueDistributor(oracle, jobId, fee, link);
        emit ContractDeployed(address(distributor));
        vm.stopBroadcast();
    }
}
