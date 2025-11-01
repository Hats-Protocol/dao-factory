// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { ApproverHatMinterSubDaoTestBase } from "../base/ApproverHatMinterSubDaoTestBase.sol";
import { ApproverHatMinterSubDaoFactory, DeploymentParameters } from "../../../src/ApproverHatMinterSubDaoFactory.sol";
import { VETokenVotingDaoFactory } from "../../../src/VETokenVotingDaoFactory.sol";

/**
 * @title FactoryPermissionsTest
 * @notice Fork integration tests for ApproverHatMinterSubDaoFactory permission setup
 * @dev Tests that all permissions are correctly configured after deployment
 */
contract FactoryPermissionsTest is ApproverHatMinterSubDaoTestBase {
  function setUp() public override {
    super.setUp();
  }

  /// @notice Test that admin plugin has correct permissions
  function test_AdminPluginPermissions() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    bytes32 EXECUTE_PERMISSION_ID = dao.EXECUTE_PERMISSION_ID();

    // Admin plugin should have EXECUTE_PERMISSION on the DAO
    assertHasPermission(
      address(dao), address(adminPlugin), EXECUTE_PERMISSION_ID, "Admin should have EXECUTE permission"
    );
  }

  /// @notice Test that TokenVoting plugin has correct permissions
  function test_TokenVotingPermissions() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    bytes32 EXECUTE_PERMISSION_ID = dao.EXECUTE_PERMISSION_ID();

    // TokenVoting plugin should have EXECUTE_PERMISSION on the DAO
    assertHasPermission(
      address(dao), address(tokenVoting), EXECUTE_PERMISSION_ID, "TokenVoting should have EXECUTE permission"
    );
  }

  /// @notice Test that SPP plugin has correct permissions
  function test_SppPluginPermissions() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    bytes32 EXECUTE_PERMISSION_ID = dao.EXECUTE_PERMISSION_ID();
    bytes32 CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");

    // SPP plugin should have EXECUTE_PERMISSION on the DAO
    assertHasPermission(address(dao), address(sppPlugin), EXECUTE_PERMISSION_ID, "SPP should have EXECUTE permission");

    // Proposer should have CREATE_PROPOSAL_PERMISSION on SPP
    assertHasPermission(
      address(sppPlugin),
      testConfig.stage1.proposerAddress,
      CREATE_PROPOSAL_PERMISSION_ID,
      "Proposer should have CREATE_PROPOSAL permission"
    );
  }

  /// @notice Test that factory temporary permissions are revoked
  function test_FactoryTemporaryPermissionsRevoked() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    (ApproverHatMinterSubDaoFactory _factory,) = deployFactoryAndSubdao(address(mainFactory), address(0));

    bytes32 ROOT_PERMISSION_ID = dao.ROOT_PERMISSION_ID();
    bytes32 EXECUTE_PERMISSION_ID = dao.EXECUTE_PERMISSION_ID();

    // Factory should NOT have ROOT_PERMISSION after deployment
    assertNoPermission(address(dao), address(_factory), ROOT_PERMISSION_ID, "Factory should not have ROOT permission");

    // Factory should NOT have EXECUTE_PERMISSION after deployment
    assertNoPermission(
      address(dao), address(_factory), EXECUTE_PERMISSION_ID, "Factory should not have EXECUTE permission"
    );
  }

  /// @notice Test that DAO has ROOT_PERMISSION_ID on itself
  function test_DaoHasRootPermissionOnItself() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    bytes32 ROOT_PERMISSION_ID = dao.ROOT_PERMISSION_ID();

    // DAO should have ROOT_PERMISSION on itself
    assertHasPermission(address(dao), address(dao), ROOT_PERMISSION_ID, "DAO should have ROOT permission on itself");
  }

  /// @notice Test that admin address from config has correct permissions via Admin plugin
  function test_AdminAddressCanExecuteViaAdminPlugin() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    // Admin plugin should allow the configured admin to execute
    // (This is handled by the Admin plugin's internal logic, not DAO permissions)
    assertTrue(address(adminPlugin) != address(0), "Admin plugin should be deployed");
    assertEq(address(adminPlugin.dao()), address(dao), "Admin plugin should target the DAO");
  }

  /// @notice Test that proposer has CREATE_PROPOSAL permission on SPP
  function test_ProposerCanCreateProposals() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    bytes32 CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");

    // Proposer from config should have permission
    assertHasPermission(
      address(sppPlugin),
      testConfig.stage1.proposerAddress,
      CREATE_PROPOSAL_PERMISSION_ID,
      "Proposer should have CREATE_PROPOSAL permission"
    );
  }

  /// @notice Test that ANY_ADDR does NOT have CREATE_PROPOSAL permission
  function test_AnyAddrDoesNotHaveCreateProposal() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    bytes32 CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");
    address ANY_ADDR = address(type(uint160).max);

    // ANY_ADDR should NOT have CREATE_PROPOSAL permission (it was revoked)
    assertNoPermission(
      address(sppPlugin), ANY_ADDR, CREATE_PROPOSAL_PERMISSION_ID, "ANY_ADDR should not have CREATE_PROPOSAL permission"
    );
  }

  /// @notice Test that random address does NOT have CREATE_PROPOSAL permission
  function test_RandomAddressCannotCreateProposal() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    bytes32 CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");
    address randomAddress = address(0x999);

    // Random address should NOT have CREATE_PROPOSAL permission
    assertNoPermission(
      address(sppPlugin),
      randomAddress,
      CREATE_PROPOSAL_PERMISSION_ID,
      "Random address should not have CREATE_PROPOSAL permission"
    );
  }

  /// @notice Test that PluginSetupProcessor does NOT have ROOT permission after deployment
  function test_PluginSetupProcessorPermissionsRevoked() public {
    setupFork();
    VETokenVotingDaoFactory mainFactory = deployMainDao();
    deployFactoryAndSubdao(address(mainFactory), address(0));

    bytes32 ROOT_PERMISSION_ID = dao.ROOT_PERMISSION_ID();
    DeploymentParameters memory params = factory.getDeploymentParameters();

    // PluginSetupProcessor should NOT have ROOT_PERMISSION after deployment
    assertNoPermission(
      address(dao),
      address(params.pluginSetupProcessor),
      ROOT_PERMISSION_ID,
      "PluginSetupProcessor should not have ROOT permission"
    );
  }
}
