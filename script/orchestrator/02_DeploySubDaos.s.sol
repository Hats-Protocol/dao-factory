// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { DeploymentScriptHelpers } from "../DeploymentHelpers.sol";
import { DeploySubDaoScript } from "../DeploySubDao.s.sol";
import { SubDaoFactory } from "../../src/SubDaoFactory.sol";
import { BroadcastReader } from "./helpers/BroadcastReader.sol";

/**
 * @title DeploySubDaosOrchestrator
 * @notice Step 2 of orchestrated deployment: Deploy all SubDAOs
 * @dev Reads main DAO factory from Step 1's broadcast artifacts
 * @dev Deploys multiple SubDAOs using different config files
 */
contract DeploySubDaosOrchestrator is DeploymentScriptHelpers {
  using BroadcastReader for *;

  /// @notice Contains deployed SubDAO factories and addresses
  struct DeployedSubDaos {
    address mainDaoFactory;
    address mainDao;
    SubDaoFactory approverFactory;
    SubDaoFactory memberCuratorFactory;
  }

  /**
   * @notice Run script - orchestrates SubDAO deployments
   * @dev NO vm.startBroadcast() in orchestrator - child scripts handle their own broadcasts
   * @dev This pattern avoids Foundry's limitation: cannot call script methods from within broadcast
   * @dev Addresses passed via env vars, child scripts read them in their run() methods
   * @return result Deployed SubDAO factories and addresses
   */
  function run() external returns (DeployedSubDaos memory result) {
    verbose = true;

    // Read addresses from Step 1's broadcast artifacts
    _log("Reading main DAO factory from broadcast artifacts...");
    result.mainDaoFactory = BroadcastReader.readMainDaoFactory();
    _log("Main DAO Factory:", result.mainDaoFactory);

    result.mainDao = BroadcastReader.readMainDaoFromFactory(result.mainDaoFactory);
    _log("Main DAO:", result.mainDao);
    _log("");

    // Set env vars for child scripts to read
    vm.setEnv("MAIN_DAO_FACTORY", vm.toString(result.mainDaoFactory));
    vm.setEnv("MAIN_DAO", vm.toString(result.mainDao));

    // Deploy approver-hat-minter SubDAO
    _log("=== Deploying approver-hat-minter SubDAO ===");
    _log("  Using config: config/subdaos/approver-hat-minter.json");
    _log("");

    vm.setEnv("CONFIG_PATH", "config/subdaos/approver-hat-minter.json");
    DeploySubDaoScript approverScript = new DeploySubDaoScript();
    approverScript.setVerbose(verbose);

    // Call run() - child has its own broadcast block
    approverScript.run();
    result.approverFactory = approverScript.lastDeployedFactory();

    // Deploy member-curator SubDAO
    _log("");
    _log("=== Deploying member-curator SubDAO ===");
    _log("  Using config: config/subdaos/member-curator.json");
    _log("");

    vm.setEnv("CONFIG_PATH", "config/subdaos/member-curator.json");
    DeploySubDaoScript curatorScript = new DeploySubDaoScript();
    curatorScript.setVerbose(verbose);

    // Call run() - child has its own broadcast block
    curatorScript.run();
    result.memberCuratorFactory = curatorScript.lastDeployedFactory();

    // Log summary
    _logDeploymentSummary(result);

    return result;
  }

  /**
   * @notice Log deployment summary
   * @param result Deployed SubDAO factories and addresses
   */
  function _logDeploymentSummary(DeployedSubDaos memory result) internal view {
    _log("");
    _log("=== Deployment Summary ===");
    _log("Main DAO Factory:", result.mainDaoFactory);
    _log("Main DAO:", result.mainDao);
    _log("Approver-Hat-Minter SubDAO:", address(result.approverFactory.getDeployment().dao));
    _log("Member-Curator SubDAO:", address(result.memberCuratorFactory.getDeployment().dao));
  }
}
