// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { ApproverHatMinterSubDaoTestBase } from "../base/ApproverHatMinterSubDaoTestBase.sol";
import { VETokenVotingDaoFactory } from "../../../src/VETokenVotingDaoFactory.sol";

/**
 * @title SmokeTest
 * @notice Smoke test to verify ApproverHatMinterSubDaoTestBase infrastructure works
 * @dev This test validates that the base contract can load config and deploy the factory
 */
contract SmokeTest is ApproverHatMinterSubDaoTestBase {
  function setUp() public override {
    super.setUp();
  }

  /// @notice Test that config loads correctly
  function test_ConfigLoads() public {
    assertEq(testConfig.version, "1.0.0", "Version should match");
    assertEq(testConfig.network, "sepolia", "Network should be sepolia");
    assertTrue(testConfig.mainDaoAddress != address(0), "Main DAO address should not be zero");
    assertTrue(testConfig.stage1.proposerAddress != address(0), "Proposer address should not be zero");
    assertTrue(testConfig.adminPlugin.adminAddress != address(0), "Admin address should not be zero");
  }

  /// @notice Test that hat IDs are parsed correctly
  function test_HatIdsParsed() public {
    // Setup fork first (required to query factory)
    setupFork();

    // Deploy main DAO and get factory address
    deployMainDao();

    assertTrue(proposerHatId != 0, "Proposer hat ID should not be zero");
    assertTrue(voterHatId != 0, "Voter hat ID should not be zero");
    assertTrue(executorHatId != 0, "Executor hat ID should not be zero");
    assertTrue(topHatId != 0, "Top hat ID should not be zero");
  }

  /// @notice Test that factory deploys on fork
  function test_FactoryDeploys() public {
    // Setup fork
    setupFork();

    // Deploy main DAO and get factory address
    VETokenVotingDaoFactory mainFactory = deployMainDao();

    // Deploy factory and subDAO
    deployFactoryAndSubdao(address(mainFactory), address(0));

    // Verify factory deployed (factory is a state variable in base)
    assertTrue(address(factory) != address(0), "Factory should be deployed");

    // Verify factory has a deployer set
    assertTrue(factory.deployer() != address(0), "Factory should have a deployer");

    // Verify factory version
    assertEq(factory.version(), "1.0.0", "Factory version should match");
  }

  /// @notice Test that subDAO deploys correctly
  function test_SubdaoDeployed() public {
    // Setup fork
    setupFork();

    // Deploy main DAO and get factory address
    VETokenVotingDaoFactory mainFactory = deployMainDao();

    // Deploy factory and subDAO
    deployFactoryAndSubdao(address(mainFactory), address(0));

    // Verify subDAO deployed
    assertTrue(address(dao) != address(0), "SubDAO should be deployed");
    assertTrue(address(tokenVoting) != address(0), "TokenVoting should be deployed");
    assertTrue(address(adminPlugin) != address(0), "Admin plugin should be deployed");
    assertTrue(address(sppPlugin) != address(0), "SPP plugin should be deployed");
  }

  /// @notice Test that Hats Protocol is set up correctly
  function test_HatsSetup() public {
    // Setup fork
    setupFork();

    // Deploy main DAO and get factory address
    VETokenVotingDaoFactory mainFactory = deployMainDao();

    // Deploy factory and subDAO
    deployFactoryAndSubdao(address(mainFactory), address(0));

    // Verify Hats instance is set
    assertTrue(address(hats) != address(0), "Hats instance should be set");

    // Verify subDAO is the top hat wearer
    assertTrue(hats.isWearerOfHat(address(dao), topHatId), "SubDAO should wear top hat");
  }
}
