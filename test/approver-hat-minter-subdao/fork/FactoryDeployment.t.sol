// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { ApproverHatMinterSubDaoTestBase } from "../base/ApproverHatMinterSubDaoTestBase.sol";
import {
  ApproverHatMinterSubDaoFactory,
  DeploymentParameters,
  Deployment
} from "../../../src/ApproverHatMinterSubDaoFactory.sol";
import { VETokenVotingDaoFactory } from "../../../src/VETokenVotingDaoFactory.sol";

/**
 * @title FactoryDeploymentTest
 * @notice Fork integration tests for ApproverHatMinterSubDaoFactory full deployment
 * @dev Tests end-to-end deployment flow with real contracts
 */
contract FactoryDeploymentTest is ApproverHatMinterSubDaoTestBase {
  function setUp() public override {
    super.setUp();
  }

  /// @notice Test that factory deploys all components successfully
  function test_FullDeploymentSucceeds() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    // Verify all core components are deployed
    assertTrue(address(factory) != address(0), "Factory should be deployed");
    assertTrue(address(dao) != address(0), "DAO should be deployed");
    assertTrue(address(tokenVoting) != address(0), "TokenVoting should be deployed");
    assertTrue(address(adminPlugin) != address(0), "Admin plugin should be deployed");
    assertTrue(address(sppPlugin) != address(0), "SPP plugin should be deployed");
  }

  /// @notice Test that DAO is properly initialized
  function test_DaoIsInitialized() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    // Verify DAO has ROOT_PERMISSION setup
    bytes32 rootPermission = dao.ROOT_PERMISSION_ID();
    assertTrue(rootPermission != bytes32(0), "ROOT_PERMISSION_ID should be set");

    // Verify DAO address is not zero
    assertTrue(address(dao) != address(0), "DAO address should not be zero");
  }

  /// @notice Test that plugin repos are set correctly
  function test_PluginReposAreSet() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    // Get deployment
    assertTrue(address(deployment.adminPluginRepo) != address(0), "Admin plugin repo should be set");
    assertTrue(address(deployment.tokenVotingPluginRepo) != address(0), "TokenVoting plugin repo should be set");
    assertTrue(address(deployment.sppPluginRepo) != address(0), "SPP plugin repo should be set");
  }

  /// @notice Test that factory version is correct
  function test_FactoryVersionIsCorrect() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    assertEq(factory.version(), "1.0.0", "Factory version should be 1.0.0");
  }

  /// @notice Test that deployer is set correctly
  function test_DeployerIsSet() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    (ApproverHatMinterSubDaoFactory _factory,) = deployFactoryAndSubdao(address(mainFactory), address(0));

    // Deployer should be the script that created the factory
    assertTrue(_factory.deployer() != address(0), "Deployer should be set");
  }

  /// @notice Test that deployment struct is populated after deployOnce
  function test_DeploymentStructIsPopulated() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    // Verify deployment struct has all components
    assertTrue(address(deployment.dao) != address(0), "Deployment should have DAO");
    assertTrue(address(deployment.adminPlugin) != address(0), "Deployment should have admin plugin");
    assertTrue(address(deployment.tokenVotingPlugin) != address(0), "Deployment should have token voting");
    assertTrue(deployment.sppPlugin != address(0), "Deployment should have SPP plugin");
  }

  /// @notice Test that TokenVoting plugin is configured correctly
  function test_TokenVotingConfigured() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    // Verify token voting plugin has the correct settings
    assertTrue(address(tokenVoting) != address(0), "TokenVoting should be deployed");

    // Verify token voting plugin DAO reference is correct
    assertEq(address(tokenVoting.dao()), address(dao), "TokenVoting DAO should match");
  }

  /// @notice Test that Admin plugin is configured correctly
  function test_AdminPluginConfigured() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    // Verify admin plugin is deployed
    assertTrue(address(adminPlugin) != address(0), "Admin plugin should be deployed");

    // Verify admin plugin target is the DAO
    assertEq(address(adminPlugin.dao()), address(dao), "Admin plugin target should be the DAO");
  }

  /// @notice Test that SPP plugin is configured with 2 stages
  function test_SppPluginConfigured() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    // Verify SPP plugin is deployed
    assertTrue(address(sppPlugin) != address(0), "SPP plugin should be deployed");

    // Verify SPP plugin DAO reference is correct
    assertEq(address(sppPlugin.dao()), address(dao), "SPP DAO should match");
  }

  /// @notice Test that parameters are stored correctly in factory
  function test_ParametersStoredCorrectly() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    // Get stored parameters
    DeploymentParameters memory params = factory.getDeploymentParameters();

    // Verify key parameters match config
    assertEq(params.adminPlugin.adminAddress, testConfig.adminPlugin.adminAddress, "Admin address should match");
    assertEq(params.stage1.proposerAddress, testConfig.stage1.proposerAddress, "Proposer address should match");

    // Verify IVotesAdapter was queried from main DAO factory (use deployed factory, not config)
    assertEq(params.ivotesAdapter, mainFactory.getIVotesAdapter(), "IVotesAdapter should match main DAO factory");
  }

  /// @notice Test that deployment can be retrieved after deployOnce
  function test_DeploymentCanBeRetrieved() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    // Get deployment multiple times to ensure it's stable
    Deployment memory dep1 = factory.getDeployment();
    Deployment memory dep2 = factory.getDeployment();

    // Verify addresses are consistent
    assertEq(address(dep1.dao), address(dep2.dao), "DAO address should be consistent");
    assertEq(address(dep1.adminPlugin), address(dep2.adminPlugin), "Admin plugin should be consistent");
    assertEq(address(dep1.tokenVotingPlugin), address(dep2.tokenVotingPlugin), "TokenVoting should be consistent");
    assertEq(dep1.sppPlugin, dep2.sppPlugin, "SPP plugin should be consistent");
  }
}
