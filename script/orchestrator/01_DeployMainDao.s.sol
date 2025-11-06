// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { DeployDaoFromConfigScript } from "../DeployDao.s.sol";
import { VETokenVotingDaoFactory } from "../../src/VETokenVotingDaoFactory.sol";

/**
 * @title DeployMainDaoOrchestrator
 * @notice Step 1 of orchestrated deployment: Deploy main DAO
 * @dev This is a wrapper around DeployDaoFromConfigScript for clarity
 * @dev After this script, VERIFY main DAO deployment before proceeding to step 2
 */
contract DeployMainDaoOrchestrator is DeployDaoFromConfigScript {
  // Inherits run() and execute() from parent
  // No need to override - uses parent implementation directly

  }
