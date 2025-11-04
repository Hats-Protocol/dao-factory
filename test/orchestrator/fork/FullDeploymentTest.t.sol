// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {BaseFactoryTest} from "../../base/BaseFactoryTest.sol";
import {VETokenVotingDaoFactory} from "../../../src/VETokenVotingDaoFactory.sol";
import {SubDaoFactory, Deployment} from "../../../src/SubDaoFactory.sol";
import {DeployDaoFromConfigScript} from "../../../script/DeployDao.s.sol";
import {DeploySubDaoScript} from "../../../script/DeploySubDao.s.sol";

/**
 * @title FullDeploymentTest
 * @notice Integration tests for deploying main DAO + both SubDAOs
 * @dev Tests the full orchestration flow: main DAO → approver SubDAO → member-curator SubDAO
 */
contract FullDeploymentTest is BaseFactoryTest {
    VETokenVotingDaoFactory mainFactory;
    SubDaoFactory approverFactory;
    SubDaoFactory memberCuratorFactory;

    /// @notice Test deploying main DAO and both SubDAOs successfully
    function test_DeployMainDaoAndBothSubDaos() public {
        setupFork();

        // Deploy main DAO (explicitly set CONFIG_PATH)
        vm.setEnv("CONFIG_PATH", "config/deployment-config.json");
        DeployDaoFromConfigScript mainScript = new DeployDaoFromConfigScript();
        mainFactory = mainScript.execute();
        assertTrue(address(mainFactory) != address(0), "Main factory should be deployed");

        // Deploy approver-hat-minter SubDAO
        vm.setEnv("CONFIG_PATH", "config/subdaos/approver-hat-minter.json");
        DeploySubDaoScript approverScript = new DeploySubDaoScript();
        approverFactory = approverScript.execute(address(mainFactory), address(0));
        assertTrue(address(approverFactory) != address(0), "Approver factory should be deployed");

        // Deploy member-curator SubDAO
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

        // Verify all use the same hat IDs
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

    /// @notice Test that SubDAOs have different stage2 vote durations
    function test_SubDaosHaveDifferentVoteDurations() public {
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

        // Get vote durations
        uint48 approverDuration = approverFactory.getDeploymentParameters().stage2.voteDuration;
        uint48 memberDuration = memberCuratorFactory.getDeploymentParameters().stage2.voteDuration;

        // Verify different durations
        assertEq(approverDuration, 259200, "Approver should have 3 day voting (259200 sec)");
        assertEq(memberDuration, 86400, "Member-curator should have 1 day voting (86400 sec)");
        assertTrue(
            memberDuration < approverDuration, "Member-curator duration should be shorter than approver duration"
        );
    }
}
