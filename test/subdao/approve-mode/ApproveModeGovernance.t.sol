// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SubDaoTestBase } from "../base/SubDaoTestBase.sol";
import { IMajorityVoting } from "@token-voting-hats/base/IMajorityVoting.sol";
import { StagedProposalProcessor } from "staged-proposal-processor-plugin/StagedProposalProcessor.sol";
import { Action } from "@aragon/osx/core/dao/DAO.sol";
import { VETokenVotingDaoFactory } from "../../../src/VETokenVotingDaoFactory.sol";

/**
 * @title ApproveModeGovernance
 * @notice Tests governance workflows for SubDAO in approve mode (member-curator config)
 * @dev Tests the 2-stage approval process: Stage 0 (manual approval) → Stage 1 (hat voting veto)
 */
contract ApproveModeGovernance is SubDaoTestBase {
  function setUp() public override {
    super.setUp();
    setupFork();

    VETokenVotingDaoFactory mainFactory = deployMainDaoWithEscrow();
    loadConfigAndDeploy("config/subdaos/member-curator.json", address(mainFactory));

    setupTestUsers();

    // Give Alice proposer hat (she can create proposals in approve mode)
    mintHatToAddress(proposerHatId, alice);
  }

  // ============================================
  // Test: Proposal Blocked Without Approval
  // ============================================

  /// @notice Test that proposals are blocked by default and require explicit approval
  function test_ProposalBlockedWithoutApproval() public {
    // Alice creates proposal (she has proposer hat)
    uint256 proposalId = createMetadataProposal(alice);

    // Verify proposal is in Stage 0
    StagedProposalProcessor.Proposal memory proposal = sppPlugin.getProposal(proposalId);
    assertEq(proposal.currentStage, 0, "Proposal should start in Stage 0");

    // Wait for full 7-day approval window
    vm.warp(block.timestamp + testConfig.stage1.voteDuration + 1);

    // Try to advance without approval - should FAIL
    vm.expectRevert();
    vm.prank(alice);
    sppPlugin.advanceProposal(proposalId);
  }

  // ============================================
  // Test: Controller Can Approve
  // ============================================

  /// @notice Test that controller can approve and proposal advances
  function test_ControllerCanApprove() public {
    address controller = testConfig.stage1.controllerAddress;

    // Alice creates proposal
    uint256 proposalId = createMetadataProposal(alice);

    // Wait for minAdvance (0 in approve mode - can approve immediately)
    vm.warp(block.timestamp + testConfig.stage1.minAdvance + 1);

    // Controller approves
    reportProposalResult(controller, proposalId, 0, StagedProposalProcessor.ResultType.Approval, true);

    // Verify proposal advanced to Stage 1 immediately (tryAdvance = true)
    StagedProposalProcessor.Proposal memory proposal = sppPlugin.getProposal(proposalId);
    assertEq(proposal.currentStage, 1, "Proposal should advance to Stage 1 after approval");
  }

  // ============================================
  // Test: Immediate Advance on Approval
  // ============================================

  /// @notice Test that proposal advances immediately upon approval (tryAdvance = true)
  function test_ImmediateAdvanceOnApproval() public {
    address controller = testConfig.stage1.controllerAddress;

    // Alice creates proposal
    uint256 proposalId = createMetadataProposal(alice);

    // Controller approves immediately (no wait needed, minAdvance = 0)
    reportProposalResult(controller, proposalId, 0, StagedProposalProcessor.ResultType.Approval, true);

    // Verify proposal advanced immediately (same block)
    StagedProposalProcessor.Proposal memory proposal = sppPlugin.getProposal(proposalId);
    assertEq(proposal.currentStage, 1, "Proposal should advance immediately on approval");
  }

  // ============================================
  // Test: Controller Can Reject
  // ============================================

  /// @notice Test that controller can reject (report veto in approve mode)
  function test_ControllerCanReject() public {
    address controller = testConfig.stage1.controllerAddress;

    // Alice creates proposal
    uint256 proposalId = createMetadataProposal(alice);

    // Controller rejects (reports Veto in approve mode means rejection)
    reportProposalResult(controller, proposalId, 0, StagedProposalProcessor.ResultType.Veto, false);

    // Verify proposal was rejected (can't advance or execute)
    vm.expectRevert();
    vm.prank(alice);
    sppPlugin.advanceProposal(proposalId);

    vm.expectRevert();
    vm.prank(controller);
    sppPlugin.execute(proposalId);
  }

  // ============================================
  // Test: Only Hat Wearers Can Propose
  // ============================================

  /// @notice Test that only addresses wearing proposer hat can create proposals
  function test_OnlyHatWearersCanPropose() public {
    // Alice has proposer hat - CAN create proposal
    uint256 proposalId = createMetadataProposal(alice);
    assertTrue(proposalId > 0, "Alice with proposer hat should be able to create proposals");

    // Bob does NOT have proposer hat - CANNOT create proposal
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://hacked") });

    vm.expectRevert();
    createSppProposal(bob, "Unauthorized proposal", actions);
  }

  // ============================================
  // Test: Controller Cannot Propose Without Hat
  // ============================================

  /// @notice Test that controller role doesn't grant proposal creation (need hat)
  function test_ControllerCannotProposeWithoutHat() public {
    address controller = testConfig.stage1.controllerAddress;

    // Controller does NOT have proposer hat by default
    // Controller should NOT be able to create proposals (even though they can approve)
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://test") });

    vm.expectRevert();
    createSppProposal(controller, "Controller proposal", actions);
  }

  // ============================================
  // Test: Full Approve Mode Workflow
  // ============================================

  /// @notice Test full approve mode workflow: Propose → Approve → DAO Veto → Execute
  function test_FullApproveModeWorkflow() public {
    address controller = testConfig.stage1.controllerAddress;

    // Setup voting power for Stage 1 (DAO veto stage)
    mintHatToAddress(voterHatId, bob);
    mintHatToAddress(voterHatId, charlie);

    createLock(bob, STANDARD_LOCK_AMOUNT);
    createLock(charlie, STANDARD_LOCK_AMOUNT);

    vm.prank(bob);
    ivotesAdapter.delegate(bob);
    vm.prank(charlie);
    ivotesAdapter.delegate(charlie);

    // Wait for checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Step 1: Alice (hat wearer) creates proposal
    uint256 proposalId = createMetadataProposal(alice);

    // Step 2: Controller approves (advances to Stage 1 immediately)
    reportProposalResult(controller, proposalId, 0, StagedProposalProcessor.ResultType.Approval, true);

    // Verify in Stage 1
    StagedProposalProcessor.Proposal memory proposal = sppPlugin.getProposal(proposalId);
    assertEq(proposal.currentStage, 1, "Proposal should be in Stage 1");

    // Step 3: DAO members don't veto (vote NO)
    uint256 stage1VotingProposalId = sppPlugin.getBodyProposalId(proposalId, 1, address(tokenVoting));

    voteOnTokenVoting(bob, stage1VotingProposalId, IMajorityVoting.VoteOption.No);
    voteOnTokenVoting(charlie, stage1VotingProposalId, IMajorityVoting.VoteOption.No);

    // Wait for Stage 1 voting to complete
    vm.warp(block.timestamp + testConfig.stage2.minAdvance + 1);

    // Step 4: Execute
    vm.prank(controller);
    sppPlugin.execute(proposalId);

    // Verify execution succeeded (can't execute again)
    vm.expectRevert();
    vm.prank(controller);
    sppPlugin.execute(proposalId);
  }

  // ============================================
  // Test: DAO Can Veto After Approval
  // ============================================

  /// @notice Test that DAO can veto even after controller approval
  function test_DaoCanVetoAfterApproval() public {
    address controller = testConfig.stage1.controllerAddress;

    // Setup voting power
    mintHatToAddress(voterHatId, bob);
    createLock(bob, STANDARD_LOCK_AMOUNT);

    vm.prank(bob);
    ivotesAdapter.delegate(bob);

    // Wait for checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Alice creates proposal, controller approves
    uint256 proposalId = createMetadataProposal(alice);
    reportProposalResult(controller, proposalId, 0, StagedProposalProcessor.ResultType.Approval, true);

    // DAO votes to veto (YES = veto)
    uint256 stage1VotingProposalId = sppPlugin.getBodyProposalId(proposalId, 1, address(tokenVoting));
    voteOnTokenVoting(bob, stage1VotingProposalId, IMajorityVoting.VoteOption.Yes);

    // Wait for voting to complete
    vm.warp(block.timestamp + testConfig.stage2.minAdvance + 1);

    // Try to execute - should FAIL (DAO vetoed)
    vm.expectRevert();
    vm.prank(controller);
    sppPlugin.execute(proposalId);
  }
}
