// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

/// @notice Shared utilities for deployment scripts
abstract contract DeploymentScriptHelpers is Script {
  /// @notice Gets OSx framework addresses for the current chain
  function _getOSxAddresses()
    internal
    view
    returns (address daoFactory, address pluginSetupProcessor, address pluginRepoFactory)
  {
    // Read addresses from OSx deployment artifacts
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/lib/osx/packages/artifacts/src/addresses.json");
    string memory json = vm.readFile(path);

    // Map chain ID to network name
    string memory network = _getNetworkName(block.chainid);

    // Parse addresses for current network
    daoFactory = vm.parseJsonAddress(json, string.concat(".daoFactory.", network));
    pluginSetupProcessor = vm.parseJsonAddress(json, string.concat(".pluginSetupProcessor.", network));
    pluginRepoFactory = vm.parseJsonAddress(json, string.concat(".pluginRepoFactory.", network));

    console.log("Using OSx contracts for", network);
    console.log("Chain ID:", block.chainid);
    console.log("  DAOFactory:", daoFactory);
    console.log("  PluginSetupProcessor:", pluginSetupProcessor);
    console.log("  PluginRepoFactory:", pluginRepoFactory);
    console.log("");
  }

  /// @notice Maps chain ID to network name used in addresses.json
  function _getNetworkName(uint256 chainId) internal pure returns (string memory) {
    if (chainId == 1) return "mainnet";
    if (chainId == 11_155_111) return "sepolia";
    if (chainId == 137) return "polygon";
    if (chainId == 42_161) return "arbitrum";
    if (chainId == 421_614) return "arbitrumSepolia";
    if (chainId == 8453) return "base";
    if (chainId == 17_000) return "holesky";
    if (chainId == 56) return "bsc";
    if (chainId == 97) return "bscTestnet";
    if (chainId == 59_144) return "linea";
    if (chainId == 34_443) return "mode";
    if (chainId == 324) return "zksync";
    if (chainId == 300) return "zksyncSepolia";

    revert(
      string.concat(
        "Unsupported chain ID: ",
        vm.toString(chainId),
        ". Check lib/osx/packages/artifacts/src/addresses.json for supported chains"
      )
    );
  }

  /// @notice Gets Admin Plugin repo address for the current chain
  function _getAdminPluginRepo() internal view returns (address pluginRepo) {
    // Read addresses from Admin Plugin deployment artifacts
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/lib/admin-plugin/packages/artifacts/src/addresses.json");
    string memory json = vm.readFile(path);

    // Map chain ID to network name
    string memory network = _getNetworkName(block.chainid);

    // Parse plugin repo address for current network
    pluginRepo = vm.parseJsonAddress(json, string.concat(".pluginRepo.", network));

    console.log("Using Admin Plugin repo for", network);
    console.log("  AdminPlugin Repo:", pluginRepo);
  }

  /// @notice Set up the deployer via their private key from the environment
  function _deployer() internal returns (address) {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    return vm.rememberKey(privKey);
  }
}
