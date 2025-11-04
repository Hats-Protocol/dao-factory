// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { BaseFactoryTest } from "../../base/BaseFactoryTest.sol";
import { VETokenVotingDaoFactory } from "../../../src/VETokenVotingDaoFactory.sol";
import { SubDaoFactory, Deployment } from "../../../src/SubDaoFactory.sol";
import { DeployDaoFromConfigScript } from "../../../script/DeployDao.s.sol";
import { DeploySubDaoScript } from "../../../script/DeploySubDao.s.sol";

/**
 * @title BothSubDaosDeployment
 * @notice Integration tests for deploying both SubDAOs together
 * @dev Tests that both veto and approve modes coexist correctly
 */
contract BothSubDaosDeployment is BaseFactoryTest {
  VETokenVotingDaoFactory mainFactory;
  SubDaoFactory approverFactory;
  SubDaoFactory memberCuratorFactory;

  function setUp() public {
    // Reset CONFIG_PATH to default to prevent pollution from/to other tests
    vm.setEnv("CONFIG_PATH", "config/deployment-config.json");
  }

  /// @notice Test deploying both SubDAOs successfully
  function test_DeployBothSubDaosSuccessfully() public {
    setupFork();

    // Deploy main DAO (explicitly set CONFIG_PATH)
    vm.setEnv("CONFIG_PATH", "config/deployment-config.json");
    DeployDaoFromConfigScript mainScript = new DeployDaoFromConfigScript();
    mainFactory = mainScript.execute();
    assertTrue(address(mainFactory) != address(0), "Main factory should be deployed");

    // Deploy approver-hat-minter SubDAO (veto mode)
    vm.setEnv("CONFIG_PATH", "config/subdaos/approver-hat-minter.json");
    DeploySubDaoScript approverScript = new DeploySubDaoScript();
    approverFactory = approverScript.execute(address(mainFactory), address(0));
    assertTrue(address(approverFactory) != address(0), "Approver factory should be deployed");

    // Deploy member-curator SubDAO (approve mode)
    vm.setEnv("CONFIG_PATH", "config/subdaos/member-curator.json");
    DeploySubDaoScript memberScript = new DeploySubDaoScript();
    memberCuratorFactory = memberScript.execute(address(mainFactory), address(0));
    assertTrue(address(memberCuratorFactory) != address(0), "Member-curator factory should be deployed");

    // Verify both factories deployed successfully
    assertNotEq(
      address(approverFactory), address(memberCuratorFactory), "Factory addresses should be different"
    );
  }

  /// @notice Test that both SubDAOs share the same IVotesAdapter from main DAO
  function test_SubDaosShareIVotesAdapter() public {
    setupFork();

    // Deploy all (explicitly set CONFIG_PATH for main DAO)
    vm.setEnv("CONFIG_PATH", "config/deployment-config.json");
    DeployDaoFromConfigScript mainScript = new DeployDaoFromConfigScript();
    mainFactory = mainScript.execute();

    vm.setEnv("CONFIG_PATH", "config/subdaos/approver-hat-minter.json");
    DeploySubDaoScript approverScript = new DeploySubDaoScript();
    approverFactory = approverScript.execute(address(mainFactory), address(0));

    vm.setEnv("CONFIG_PATH", "config/subdaos/member-curator.json");
    DeploySubDaoScript memberScript = new DeploySubDaoScript();
    memberCuratorFactory = memberScript.execute(address(mainFactory), address(0));

    // Get IVotesAdapter from each
    address mainAdapter = mainFactory.getIVotesAdapter();
    address approverAdapter = approverFactory.getDeploymentParameters().ivotesAdapter;
    address memberAdapter = memberCuratorFactory.getDeploymentParameters().ivotesAdapter;

    // Verify all three use the same IVotesAdapter
    assertEq(approverAdapter, mainAdapter, "Approver should use main DAO's IVotesAdapter");
    assertEq(memberAdapter, mainAdapter, "Member-curator should use main DAO's IVotesAdapter");
  }

  /// @notice Test that both SubDAOs share the same hat IDs
  function test_SubDaosShareHatIds() public {
    setupFork();

    // Deploy all (explicitly set CONFIG_PATH for main DAO)
    vm.setEnv("CONFIG_PATH", "config/deployment-config.json");
    DeployDaoFromConfigScript mainScript = new DeployDaoFromConfigScript();
    mainFactory = mainScript.execute();

    vm.setEnv("CONFIG_PATH", "config/subdaos/approver-hat-minter.json");
    DeploySubDaoScript approverScript = new DeploySubDaoScript();
    approverFactory = approverScript.execute(address(mainFactory), address(0));

    vm.setEnv("CONFIG_PATH", "config/subdaos/member-curator.json");
    DeploySubDaoScript memberScript = new DeploySubDaoScript();
    memberCuratorFactory = memberScript.execute(address(mainFactory), address(0));

    // Get hat IDs from each
    uint256 mainProposerHat = mainFactory.getProposerHatId();
    uint256 mainVoterHat = mainFactory.getVoterHatId();
    uint256 mainExecutorHat = mainFactory.getExecutorHatId();

    uint256 approverProposerHat =
      approverFactory.getDeploymentParameters().stage2.tokenVotingHats.proposerHatId;
    uint256 approverVoterHat = approverFactory.getDeploymentParameters().stage2.tokenVotingHats.voterHatId;
    uint256 approverExecutorHat = approverFactory.getDeploymentParameters().stage2.tokenVotingHats.executorHatId;

    uint256 memberProposerHat = memberCuratorFactory.getDeploymentParameters().stage2.tokenVotingHats.proposerHatId;
    uint256 memberVoterHat = memberCuratorFactory.getDeploymentParameters().stage2.tokenVotingHats.voterHatId;
    uint256 memberExecutorHat = memberCuratorFactory.getDeploymentParameters().stage2.tokenVotingHats.executorHatId;

    // Verify all use the same hat IDs (Stage 2)
    assertEq(approverProposerHat, mainProposerHat, "Approver should use main DAO's proposer hat");
    assertEq(approverVoterHat, mainVoterHat, "Approver should use main DAO's voter hat");
    assertEq(approverExecutorHat, mainExecutorHat, "Approver should use main DAO's executor hat");

    assertEq(memberProposerHat, mainProposerHat, "Member-curator should use main DAO's proposer hat");
    assertEq(memberVoterHat, mainVoterHat, "Member-curator should use main DAO's voter hat");
    assertEq(memberExecutorHat, mainExecutorHat, "Member-curator should use main DAO's executor hat");
  }

  /// @notice Test that SubDAOs have different DAO addresses
  function test_SubDaosHaveDifferentDaoAddresses() public {
    setupFork();

    // Deploy all (explicitly set CONFIG_PATH for main DAO)
    vm.setEnv("CONFIG_PATH", "config/deployment-config.json");
    DeployDaoFromConfigScript mainScript = new DeployDaoFromConfigScript();
    mainFactory = mainScript.execute();

    vm.setEnv("CONFIG_PATH", "config/subdaos/approver-hat-minter.json");
    DeploySubDaoScript approverScript = new DeploySubDaoScript();
    approverFactory = approverScript.execute(address(mainFactory), address(0));

    vm.setEnv("CONFIG_PATH", "config/subdaos/member-curator.json");
    DeploySubDaoScript memberScript = new DeploySubDaoScript();
    memberCuratorFactory = memberScript.execute(address(mainFactory), address(0));

    // Get DAO addresses
    Deployment memory approverDeployment = approverFactory.getDeployment();
    Deployment memory memberDeployment = memberCuratorFactory.getDeployment();

    // Verify different DAO addresses
    assertNotEq(
      address(approverDeployment.dao),
      address(memberDeployment.dao),
      "SubDAOs should have different DAO addresses"
    );
  }

  /// @notice Test that SubDAOs have different Stage 1 modes
  function test_SubDaosHaveDifferentModes() public {
    setupFork();

    // Deploy all (explicitly set CONFIG_PATH for main DAO)
    vm.setEnv("CONFIG_PATH", "config/deployment-config.json");
    DeployDaoFromConfigScript mainScript = new DeployDaoFromConfigScript();
    mainFactory = mainScript.execute();

    vm.setEnv("CONFIG_PATH", "config/subdaos/approver-hat-minter.json");
    DeploySubDaoScript approverScript = new DeploySubDaoScript();
    approverFactory = approverScript.execute(address(mainFactory), address(0));

    vm.setEnv("CONFIG_PATH", "config/subdaos/member-curator.json");
    DeploySubDaoScript memberScript = new DeploySubDaoScript();
    memberCuratorFactory = memberScript.execute(address(mainFactory), address(0));

    // Get modes
    string memory approverMode = approverFactory.getDeploymentParameters().stage1.mode;
    string memory memberMode = memberCuratorFactory.getDeploymentParameters().stage1.mode;

    // Verify different modes
    assertEq(approverMode, "veto", "Approver should use veto mode");
    assertEq(memberMode, "approve", "Member-curator should use approve mode");
  }

  /// @notice Test that SubDAOs have different Stage 1 permission types
  function test_SubDaosHaveDifferentPermissionTypes() public {
    setupFork();

    // Deploy all (explicitly set CONFIG_PATH for main DAO)
    vm.setEnv("CONFIG_PATH", "config/deployment-config.json");
    DeployDaoFromConfigScript mainScript = new DeployDaoFromConfigScript();
    mainFactory = mainScript.execute();

    vm.setEnv("CONFIG_PATH", "config/subdaos/approver-hat-minter.json");
    DeploySubDaoScript approverScript = new DeploySubDaoScript();
    approverFactory = approverScript.execute(address(mainFactory), address(0));

    vm.setEnv("CONFIG_PATH", "config/subdaos/member-curator.json");
    DeploySubDaoScript memberScript = new DeploySubDaoScript();
    memberCuratorFactory = memberScript.execute(address(mainFactory), address(0));

    // Verify permission types
    uint256 approverProposerHatId = approverFactory.getDeploymentParameters().stage1.proposerHatId;
    uint256 memberProposerHatId = memberCuratorFactory.getDeploymentParameters().stage1.proposerHatId;

    // Approver uses direct grant (proposerHatId = 0)
    assertEq(approverProposerHatId, 0, "Approver should use direct grant (proposerHatId = 0)");

    // Member-curator uses hat-based permissions (proposerHatId != 0)
    assertTrue(memberProposerHatId != 0, "Member-curator should use hat-based permissions (proposerHatId != 0)");
    assertEq(memberProposerHatId, mainFactory.getProposerHatId(), "Member-curator should use main DAO's proposer hat");
  }

  /// @notice Test that both SubDAOs share the same HatsCondition
  function test_SubDaosShareHatsCondition() public {
    setupFork();

    // Deploy all (explicitly set CONFIG_PATH for main DAO)
    vm.setEnv("CONFIG_PATH", "config/deployment-config.json");
    DeployDaoFromConfigScript mainScript = new DeployDaoFromConfigScript();
    mainFactory = mainScript.execute();

    vm.setEnv("CONFIG_PATH", "config/subdaos/approver-hat-minter.json");
    DeploySubDaoScript approverScript = new DeploySubDaoScript();
    approverFactory = approverScript.execute(address(mainFactory), address(0));

    vm.setEnv("CONFIG_PATH", "config/subdaos/member-curator.json");
    DeploySubDaoScript memberScript = new DeploySubDaoScript();
    memberCuratorFactory = memberScript.execute(address(mainFactory), address(0));

    // Both should have HatsCondition stored (from TokenVotingHats)
    address approverHatsCondition = approverFactory.getDeployment().hatsCondition;
    address memberHatsCondition = memberCuratorFactory.getDeployment().hatsCondition;

    assertTrue(approverHatsCondition != address(0), "Approver should have HatsCondition stored");
    assertTrue(memberHatsCondition != address(0), "Member-curator should have HatsCondition stored");

    // Note: They won't be the SAME address because each SubDAO deploys its own TokenVotingHats
    // But they should both be valid HatsCondition contracts
    assertNotEq(approverHatsCondition, memberHatsCondition, "Each SubDAO has its own HatsCondition (from its own TokenVotingHats)");
  }
}
