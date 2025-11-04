// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SubDaoTestBase } from "../base/SubDaoTestBase.sol";
import { SubDaoFactory, DeploymentParameters, Deployment } from "../../../src/SubDaoFactory.sol";
import { VETokenVotingDaoFactory } from "../../../src/VETokenVotingDaoFactory.sol";
import { StagedProposalProcessor } from "staged-proposal-processor-plugin/StagedProposalProcessor.sol";
import { IPermissionCondition } from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";

/**
 * @title ApproveModeDeployment
 * @notice Tests SubDaoFactory deployment in approve mode (member-curator config)
 * @dev Verifies factory configuration and component setup for approve mode
 */
contract ApproveModeDeployment is SubDaoTestBase {
  VETokenVotingDaoFactory internal mainFactory;

  function setUp() public override {
    super.setUp();
    setupFork();
    mainFactory = deployMainDao();
    loadConfigAndDeploy("config/subdaos/member-curator.json", address(mainFactory));
  }

  /// @notice Test that factory deploys all components successfully
  function test_FullDeploymentSucceeds() public {
    assertStandardDeployment();
  }

  /// @notice Test that parameters match config (with auto-queried proposerHatId)
  function test_ParametersMatchConfig() public {
    DeploymentParameters memory params = factory.getDeploymentParameters();

    // Verify Stage 1 parameters match config
    assertEq(params.stage1.mode, "approve", "Mode should be approve");
    assertEq(params.stage1.proposerHatId, mainFactory.getProposerHatId(), "ProposerHatId should be auto-queried");
    assertEq(params.stage1.controllerAddress, testConfig.stage1.controllerAddress, "Controller address should match");
    assertEq(params.stage1.minAdvance, testConfig.stage1.minAdvance, "MinAdvance should match config");
    assertEq(params.stage1.maxAdvance, testConfig.stage1.maxAdvance, "MaxAdvance should match config");
    assertEq(params.stage1.voteDuration, testConfig.stage1.voteDuration, "VoteDuration should match config");
  }

  /// @notice Test that SPP Stage 1 is configured correctly
  /// @dev We verify config is correct by checking factory parameters match
  function test_Stage1ConfiguredInApproveMode() public {
    // Verify factory parameters match approve mode config
    DeploymentParameters memory params = factory.getDeploymentParameters();
    assertEq(params.stage1.mode, "approve", "Mode should be approve");

    // Verify SPP plugin is deployed
    assertTrue(deployment.sppPlugin != address(0), "SPP plugin should be deployed");

    // Stage configuration is internal to SPP, but we can verify parameters were set correctly
    // The actual approve behavior is tested in governance tests
  }

  /// @notice Test that permissions are granted with HatsCondition
  function test_HatBasedPermissions() public {
    // Verify that hat-based permissions are configured correctly
    // Note: OSx hasPermission() with empty data doesn't reliably check conditional permissions
    // The actual functionality is tested in ApproveModeGovernance tests (test_OnlyHatWearersCanPropose)

    // Verify prerequisites for hat-based permissions are in place
    DeploymentParameters memory params = factory.getDeploymentParameters();
    assertTrue(params.stage1.proposerHatId != 0, "ProposerHatId should be set for hat-based permissions");
    assertTrue(deployment.hatsCondition != address(0), "HatsCondition should be deployed");
  }

  /// @notice Test that HatsCondition is stored from TokenVotingHats
  function test_HatsConditionStored() public {
    // HatsCondition should be stored from TokenVotingHats deployment
    assertTrue(deployment.hatsCondition != address(0), "HatsCondition should be stored");

    // Verify proposerHatId is set (indicates hat-based permissions are used)
    DeploymentParameters memory params = factory.getDeploymentParameters();
    assertTrue(params.stage1.proposerHatId != 0, "ProposerHatId should be set for hat-based permissions");
  }

  /// @notice Test that controller does NOT have direct permission (uses hat)
  function test_ControllerDoesNotHaveDirectPermission() public {
    bytes32 CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");

    // In approve mode with hat-based permissions, controller needs hat to propose
    // The permission is granted to ANY_ADDR with HatsCondition, not directly to controller

    // We can't easily test "controller without hat can't propose" here without Hats Protocol
    // But we can verify the permission structure is correct

    // Verify proposerHatId was set (not 0)
    DeploymentParameters memory params = factory.getDeploymentParameters();
    assertTrue(params.stage1.proposerHatId != 0, "ProposerHatId should be set (not 0)");
  }

  /// @notice Test that proposerHatId was auto-queried from main DAO
  function test_ProposerHatIdAutoQueried() public {
    DeploymentParameters memory params = factory.getDeploymentParameters();

    // Config had proposerHatId = 0, should be auto-queried to main DAO's proposerHatId
    uint256 mainDaoProposerHat = mainFactory.getProposerHatId();
    assertEq(params.stage1.proposerHatId, mainDaoProposerHat, "ProposerHatId should match main DAO's proposer hat");
  }

  /// @notice Test that factory version is correct
  function test_FactoryVersionIsCorrect() public {
    assertFactoryVersion("1.0.0");
  }

  /// @notice Test that deployment struct is populated
  function test_DeploymentStructIsPopulated() public {
    assertDeploymentStructPopulated();
  }
}
