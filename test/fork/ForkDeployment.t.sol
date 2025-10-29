// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { FactoryTestBase } from "../base/FactoryTestBase.sol";
import { DeploymentParameters, VETokenVotingDaoFactory } from "../../src/VETokenVotingDaoFactory.sol";

/**
 * @title ForkDeploymentTest
 * @notice Tests that run on a Sepolia fork to test against real network state
 * @dev Fork is set up once in setUp() and used by all tests in this contract
 */
contract ForkDeploymentTest is FactoryTestBase {
  function setUp() public override {
    super.setUp();

    // Set up Sepolia fork for ALL tests in this contract
    setupFork();
  }

  // ============================================
  // FORK VERIFICATION TESTS
  // ============================================

  function test_DeployOnSepoliaFork() public {
    // Deploy factory and DAO using the script (fork already set up in setUp)
    factory = deployFactory();

    // Verify deployment succeeded
    assertNotEq(address(factory), address(0), "Factory not deployed on fork");
    assertNotEq(address(deployment.dao), address(0), "DAO not deployed on fork");

    // Verify we're still on Sepolia
    assertEq(block.chainid, 11_155_111, "Should be on Sepolia fork");
  }

  function test_RealOSxContractsUsed() public {
    // Deploy factory (fork already set up in setUp)
    factory = deployFactory();

    // Get deployment parameters to check OSx addresses
    DeploymentParameters memory params = factory.getDeploymentParameters();

    // Verify we're using real Sepolia OSx contracts (not zero addresses)
    assertNotEq(params.osxDaoFactory, address(0), "OSx DAO Factory should be real address");
    assertNotEq(address(params.pluginSetupProcessor), address(0), "PluginSetupProcessor should be real address");
    assertNotEq(address(params.pluginRepoFactory), address(0), "PluginRepoFactory should be real address");

    // Verify these are the actual Sepolia addresses (they should have code)
    assertGt(params.osxDaoFactory.code.length, 0, "OSx DAO Factory should have code");
    assertGt(address(params.pluginSetupProcessor).code.length, 0, "PluginSetupProcessor should have code");
  }

  // ============================================
  // FULL DEPLOYMENT TESTS
  // ============================================

  function test_FullDaoDeployment() public {
    // Deploy factory and DAO (fork already set up)
    factory = deployFactory();

    // Verify DAO deployed
    assertNotEq(address(deployment.dao), address(0), "DAO not deployed");

    // Verify VE system components
    assertNotEq(address(deployment.veSystem.votingEscrow), address(0), "VotingEscrow not deployed");
    assertNotEq(address(deployment.veSystem.clock), address(0), "Clock not deployed");
    assertNotEq(address(deployment.veSystem.curve), address(0), "Curve not deployed");
    assertNotEq(address(deployment.veSystem.exitQueue), address(0), "ExitQueue not deployed");
    assertNotEq(address(deployment.veSystem.nftLock), address(0), "Lock not deployed");
    assertNotEq(address(deployment.veSystem.ivotesAdapter), address(0), "IVotesAdapter not deployed");
    assertNotEq(address(deployment.veSystem.voter), address(0), "AddressGaugeVoter not deployed");

    // Verify plugins
    assertNotEq(address(deployment.tokenVotingPlugin), address(0), "TokenVotingHats not deployed");
    assertNotEq(address(deployment.adminPlugin), address(0), "Admin plugin not deployed");

    // Verify plugin repos
    assertNotEq(address(deployment.tokenVotingPluginRepo), address(0), "TokenVoting repo not deployed");
    assertNotEq(address(deployment.adminPluginRepo), address(0), "Admin repo not deployed");

    // Verify quick access references are set
    assertEq(address(dao), address(deployment.dao), "DAO quick ref not set");
    assertEq(address(escrow), address(deployment.veSystem.votingEscrow), "Escrow quick ref not set");
    assertEq(address(tokenVoting), address(deployment.tokenVotingPlugin), "TokenVoting quick ref not set");
    assertEq(address(adminPlugin), address(deployment.adminPlugin), "Admin quick ref not set");
  }

  function test_DoubleDeploymentReverts() public {
    // Deploy factory and DAO
    factory = deployFactory();

    // Second deployment should revert
    vm.expectRevert(VETokenVotingDaoFactory.AlreadyDeployed.selector);
    factory.deployOnce();
  }

  function test_PermissionAssertionHelpers() public {
    // Deploy factory and DAO
    factory = deployFactory();

    // Test assertHasPermission - DAO should have ROOT on itself
    assertHasPermission(address(dao), address(dao), dao.ROOT_PERMISSION_ID(), "DAO should have ROOT on itself");

    // Test assertNoPermission - random address should not have ROOT
    address random = address(0x9999);
    assertNoPermission(address(dao), random, dao.ROOT_PERMISSION_ID(), "Random should not have ROOT");
  }
}
