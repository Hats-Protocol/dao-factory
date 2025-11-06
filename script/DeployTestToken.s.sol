// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import { TestToken } from "../src/TestToken.sol";

/**
 * @title DeployTestTokenScript
 * @notice Deploys the TestToken contract
 * @dev Run with: forge script script/DeployTestToken.s.sol --rpc-url <RPC_URL> --broadcast --verify
 * @dev Requires PRIVATE_KEY environment variable to be set
 */
contract DeployTestTokenScript is Script {
  /**
   * @notice Main deployment function
   * @return testToken The deployed TestToken contract
   */
  function run() external returns (TestToken testToken) {
    // Get deployer address from private key
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    console.log("Deploying TestToken...");
    console.log("Deployer address:", deployer);

    vm.startBroadcast(deployerPrivateKey);

    // Deploy TestToken
    testToken = new TestToken();

    vm.stopBroadcast();

    console.log("TestToken deployed at:", address(testToken));
    console.log("Token Name:", testToken.name());
    console.log("Token Symbol:", testToken.symbol());

    return testToken;
  }
}

/*
forge script script/DeployTestToken.s.sol:DeployTestTokenScript --rpc-url sepolia

forge script script/DeployTestToken.s.sol:DeployTestTokenScript --rpc-url sepolia --broadcast --verify

forge verify-contract --chain-id 115511 --num-of-optimizations 10000 --watch --constructor-args $(cast abi-encode "constructor()" "") --compiler-version v0.8.29 <CONTRACT_ADDRESS> src/TestToken.sol:TestToken $ETHERSCAN_API_KEY
*/
