// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { ApproverHatMinterSubDaoTestBase } from "../base/ApproverHatMinterSubDaoTestBase.sol";
import {
  ApproverHatMinterSubDaoFactory,
  DeploymentParameters,
  Deployment
} from "../../../src/ApproverHatMinterSubDaoFactory.sol";
import { VETokenVotingDaoFactory } from "../../../src/VETokenVotingDaoFactory.sol";
import { DeployApproverHatMinterSubDaoScript } from "../../../script/DeployApproverHatMinterSubDao.s.sol";

/**
 * @title FactoryErrorsTest
 * @notice Fork integration tests for ApproverHatMinterSubDaoFactory error conditions
 * @dev Tests error handling with real contract interactions
 */
contract FactoryErrorsTest is ApproverHatMinterSubDaoTestBase {
  function setUp() public override {
    super.setUp();
  }

  /// @notice Test that deployOnce reverts when called by unauthorized address
  function test_DeployOnce_RevertsForUnauthorized() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    address unauthorized = address(0x999);

    // Try to call deployOnce again as unauthorized user
    vm.prank(unauthorized);
    vm.expectRevert(ApproverHatMinterSubDaoFactory.Unauthorized.selector);
    factory.deployOnce();
  }

  /// @notice Test that deployOnce reverts when called twice
  function test_DeployOnce_RevertsWhenCalledTwice() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    (ApproverHatMinterSubDaoFactory _factory, DeployApproverHatMinterSubDaoScript script) = deployFactoryAndSubdao(address(mainFactory), address(0));

    // Try to call deployOnce again (should revert with AlreadyDeployed)
    vm.prank(address(script));
    vm.expectRevert(ApproverHatMinterSubDaoFactory.AlreadyDeployed.selector);
    _factory.deployOnce();
  }

  /// @notice Test that factory with zero IVotesAdapter reverts on deployment
  function test_DeployOnce_RevertsForZeroIVotesAdapter() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();

    // Create params with zero IVotesAdapter
    DeploymentParameters memory params = _createParamsWithZeroAdapter(mainFactory);

    // Deploy factory with zero adapter
    address deployer = address(this);
    ApproverHatMinterSubDaoFactory badFactory = new ApproverHatMinterSubDaoFactory(params);

    // Try to deploy (should revert with InvalidIVotesAdapterAddress)
    vm.expectRevert(ApproverHatMinterSubDaoFactory.InvalidIVotesAdapterAddress.selector);
    badFactory.deployOnce();
  }

  /// @notice Test that factory version is accessible before deployment
  function test_VersionAccessibleBeforeDeployment() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();

    // Create a new factory without deploying
    DeploymentParameters memory params = _createValidParams(mainFactory);
    ApproverHatMinterSubDaoFactory newFactory = new ApproverHatMinterSubDaoFactory(params);

    // Version should be accessible
    assertEq(newFactory.version(), "1.0.0", "Version should be accessible before deployment");
  }

  /// @notice Test that getDeploymentParameters is accessible before deployment
  function test_GetParametersAccessibleBeforeDeployment() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();

    // Create a new factory without deploying
    DeploymentParameters memory params = _createValidParams(mainFactory);
    ApproverHatMinterSubDaoFactory newFactory = new ApproverHatMinterSubDaoFactory(params);

    // Parameters should be accessible
    DeploymentParameters memory retrieved = newFactory.getDeploymentParameters();
    assertEq(retrieved.ivotesAdapter, mainFactory.getIVotesAdapter(), "Parameters should be accessible");
  }

  /// @notice Test that getDeployment returns empty struct before deployment
  function test_GetDeploymentEmptyBeforeDeployment() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();

    // Create a new factory without deploying
    DeploymentParameters memory params = _createValidParams(mainFactory);
    ApproverHatMinterSubDaoFactory newFactory = new ApproverHatMinterSubDaoFactory(params);

    // Deployment should be empty
    Deployment memory retrieved = newFactory.getDeployment();
    assertEq(address(retrieved.dao), address(0), "Deployment should be empty before deployOnce");
  }

  /// @notice Helper to create valid deployment parameters from config
  function _createValidParams(VETokenVotingDaoFactory mainFactory) internal returns (DeploymentParameters memory) {
    DeploymentParameters memory params;

    // Use config values
    params.dao = testConfig.dao;
    params.adminPlugin = testConfig.adminPlugin;
    params.stage1 = testConfig.stage1;
    params.stage2 = testConfig.stage2;
    params.sppPlugin = testConfig.sppPlugin;

    // Query main DAO factory for ivotesAdapter (use deployed factory, not config)
    params.ivotesAdapter = mainFactory.getIVotesAdapter();

    // Get real setup contracts from deployment script (pass main factory address)
    DeployApproverHatMinterSubDaoScript script = new DeployApproverHatMinterSubDaoScript();
    ApproverHatMinterSubDaoFactory tempFactory = script.execute(address(mainFactory), address(0));
    DeploymentParameters memory scriptParams = tempFactory.getDeploymentParameters();

    // Use the setup contracts from the script
    params.tokenVotingSetup = scriptParams.tokenVotingSetup;
    params.tokenVotingPluginRepo = scriptParams.tokenVotingPluginRepo;
    params.adminSetup = scriptParams.adminSetup;
    params.adminPluginRepo = scriptParams.adminPluginRepo;
    params.sppPluginSetup = scriptParams.sppPluginSetup;
    params.sppPluginRepo = scriptParams.sppPluginRepo;
    params.tokenVotingPluginRepoRelease = scriptParams.tokenVotingPluginRepoRelease;
    params.tokenVotingPluginRepoBuild = scriptParams.tokenVotingPluginRepoBuild;
    params.osxDaoFactory = scriptParams.osxDaoFactory;
    params.pluginSetupProcessor = scriptParams.pluginSetupProcessor;
    params.pluginRepoFactory = scriptParams.pluginRepoFactory;

    return params;
  }

  /// @notice Helper to create params with zero IVotesAdapter
  function _createParamsWithZeroAdapter(VETokenVotingDaoFactory mainFactory) internal returns (DeploymentParameters memory) {
    DeploymentParameters memory params = _createValidParams(mainFactory);
    params.ivotesAdapter = address(0); // Set to zero
    return params;
  }
}
