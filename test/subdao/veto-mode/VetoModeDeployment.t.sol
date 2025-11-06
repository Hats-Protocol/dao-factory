// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SubDaoTestBase } from "../base/SubDaoTestBase.sol";
import { SubDaoFactory, DeploymentParameters, Deployment } from "../../../src/SubDaoFactory.sol";
import { VETokenVotingDaoFactory } from "../../../src/VETokenVotingDaoFactory.sol";
import { StagedProposalProcessor } from "staged-proposal-processor-plugin/StagedProposalProcessor.sol";

/**
 * @title VetoModeDeployment
 * @notice Tests SubDaoFactory deployment in veto mode (approver-hat-minter config)
 * @dev Verifies factory configuration and component setup for veto mode
 */
contract VetoModeDeployment is SubDaoTestBase {
  VETokenVotingDaoFactory internal mainFactory;

  function setUp() public override {
    super.setUp();
    setupFork();
    mainFactory = deployMainDao();
    loadConfigAndDeploy("config/subdaos/approver-hat-minter.json", address(mainFactory));
  }

  /// @notice Test that factory deploys all components successfully
  function test_FullDeploymentSucceeds() public {
    assertStandardDeployment();
  }

  /// @notice Test that parameters are stored correctly in factory
  function test_ParametersMatchConfig() public {
    DeploymentParameters memory params = factory.getDeploymentParameters();

    // Verify Stage 1 parameters match config
    assertEq(params.stage1.mode, "veto", "Mode should be veto");
    assertEq(params.stage1.proposerHatId, 0, "ProposerHatId should be 0 (direct grant)");
    assertEq(params.stage1.controllerAddress, testConfig.stage1.controllerAddress, "Controller address should match");
    assertEq(params.stage1.minAdvance, testConfig.stage1.minAdvance, "MinAdvance should match");
    assertEq(params.stage1.maxAdvance, testConfig.stage1.maxAdvance, "MaxAdvance should match");
    assertEq(params.stage1.voteDuration, testConfig.stage1.voteDuration, "VoteDuration should match");
  }

  /// @notice Test that SPP Stage 1 is configured correctly
  /// @dev We verify config is correct by checking factory parameters match
  function test_Stage1ConfiguredInVetoMode() public {
    // Verify factory parameters match veto mode config
    DeploymentParameters memory params = factory.getDeploymentParameters();
    assertEq(params.stage1.mode, "veto", "Mode should be veto");

    // Verify SPP plugin is deployed
    assertTrue(deployment.sppPlugin != address(0), "SPP plugin should be deployed");

    // Stage configuration is internal to SPP, but we can verify parameters were set correctly
    // The actual veto behavior is tested in governance tests
  }

  /// @notice Test that permissions are granted correctly (direct grant, not hat-based)
  function test_DirectGrantPermissions() public {
    bytes32 CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");

    // Verify controller has CREATE_PROPOSAL permission
    assertTrue(
      dao.hasPermission(
        address(sppPlugin), testConfig.stage1.controllerAddress, CREATE_PROPOSAL_PERMISSION_ID, bytes("")
      ),
      "Controller should have CREATE_PROPOSAL permission"
    );

    // Verify random address does NOT have permission
    address randomAddr = vm.addr(999);
    assertFalse(
      dao.hasPermission(address(sppPlugin), randomAddr, CREATE_PROPOSAL_PERMISSION_ID, bytes("")),
      "Random address should not have CREATE_PROPOSAL permission"
    );
  }

  /// @notice Test that HatsCondition was stored but not used for permissions
  function test_HatsConditionStoredButNotUsed() public {
    // HatsCondition should be stored from TokenVotingHats
    assertTrue(deployment.hatsCondition != address(0), "HatsCondition should be stored");

    // But it should NOT be used for SPP permissions (proposerHatId == 0)
    DeploymentParameters memory params = factory.getDeploymentParameters();
    assertEq(params.stage1.proposerHatId, 0, "ProposerHatId should be 0 (not using hat-based permissions)");
  }

  /// @notice Test that factory version is correct
  function test_FactoryVersionIsCorrect() public {
    assertFactoryVersion("1.0.0");
  }

  /// @notice Test that deployment struct is populated
  function test_DeploymentStructIsPopulated() public {
    assertDeploymentStructPopulated();
  }

  /// @notice Test that main DAO has ROOT_PERMISSION on SubDAO
  function test_MainDaoHasRootPermission() public {
    // Get the main DAO address from the factory
    address mainDaoAddress = mainFactory.getDao();

    // Verify main DAO has ROOT_PERMISSION on SubDAO
    bytes32 ROOT_PERMISSION_ID = dao.ROOT_PERMISSION_ID();
    assertTrue(
      dao.hasPermission(address(dao), mainDaoAddress, ROOT_PERMISSION_ID, bytes("")),
      "Main DAO should have ROOT_PERMISSION on SubDAO"
    );
  }
}
