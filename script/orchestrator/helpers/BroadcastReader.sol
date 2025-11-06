// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Vm } from "forge-std/Vm.sol";

/**
 * @title BroadcastReader
 * @notice Helper library to read deployment addresses from Foundry broadcast artifacts
 * @dev Parses JSON from broadcast/<ScriptName>/<chainId>/run-latest.json
 * @dev Fails fast if both real and dry-run artifacts exist to prevent mode mismatch
 */
library BroadcastReader {
  Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

  /**
   * @notice Read main DAO factory address from latest broadcast
   * @dev Reads from either real broadcast or dry-run, but not both
   * @dev If both exist, reverts to prevent accidental mismatch
   * @return mainDaoFactory Address of deployed VETokenVotingDaoFactory
   */
  function readMainDaoFactory() internal view returns (address mainDaoFactory) {
    string memory basePath =
      string.concat(vm.projectRoot(), "/broadcast/01_DeployMainDao.s.sol/", vm.toString(block.chainid));

    string memory realPath = string.concat(basePath, "/run-latest.json");
    string memory dryRunPath = string.concat(basePath, "/dry-run/run-latest.json");

    // Check which files exist
    bool realExists = _fileExists(realPath);
    bool dryRunExists = _fileExists(dryRunPath);

    // Fail fast if both exist to prevent mode mismatch
    require(
      !(realExists && dryRunExists),
      string.concat(
        "BroadcastReader: Found both real and dry-run artifacts.\n",
        "This prevents accidental deployment mode mismatch.\n",
        "Please clean up before deploying:\n",
        "  For production: rm -rf broadcast/01_DeployMainDao.s.sol/*/dry-run/\n",
        "  For testing:    rm broadcast/01_DeployMainDao.s.sol/*/run-latest.json"
      )
    );

    // Require at least one exists
    require(
      realExists || dryRunExists,
      "BroadcastReader: No broadcast artifacts found. Deploy main DAO first with script/orchestrator/01_DeployMainDao.s.sol"
    );

    // Read whichever exists
    string memory json = realExists ? vm.readFile(realPath) : vm.readFile(dryRunPath);

    // Parse factory address from returns field
    // Foundry broadcast format: .returns.factory.value
    mainDaoFactory = abi.decode(vm.parseJson(json, ".returns.factory.value"), (address));

    require(mainDaoFactory != address(0), "BroadcastReader: Factory address is zero");
  }

  /**
   * @notice Read main DAO address from factory deployment
   * @param factoryAddress Address of the VETokenVotingDaoFactory
   * @return mainDao Address of deployed DAO
   */
  function readMainDaoFromFactory(address factoryAddress) internal view returns (address mainDao) {
    // Call getDeployment() on factory to get DAO address
    // This is a view function, so we can call it from the script
    (bool success, bytes memory data) = factoryAddress.staticcall(abi.encodeWithSignature("getDeployment()"));

    require(success, "BroadcastReader: Failed to read deployment from factory");

    // Parse DAO address from deployment struct (first field)
    mainDao = abi.decode(data, (address));

    require(mainDao != address(0), "BroadcastReader: DAO address is zero");
  }

  /**
   * @notice Check if a file exists
   * @param path Path to check
   * @return exists True if file exists and is readable
   */
  function _fileExists(string memory path) private view returns (bool exists) {
    try vm.readFile(path) returns (string memory) {
      return true;
    } catch {
      return false;
    }
  }
}
