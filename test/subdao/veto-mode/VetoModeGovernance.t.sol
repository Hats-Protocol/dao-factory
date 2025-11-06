// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SubDaoTestBase } from "../base/SubDaoTestBase.sol";
import { IMajorityVoting } from "@token-voting-hats/base/IMajorityVoting.sol";
import { StagedProposalProcessor } from "staged-proposal-processor-plugin/StagedProposalProcessor.sol";
import { Action } from "@aragon/osx/core/dao/DAO.sol";
import { VETokenVotingDaoFactory } from "../../../src/VETokenVotingDaoFactory.sol";

/**
 * @title VetoModeGovernance
 * @notice Tests governance workflows for SubDAO in veto mode (approver-hat-minter config)
 * @dev Tests the 2-stage veto process: Stage 0 (manual veto) → Stage 1 (hat voting veto)
 */
contract VetoModeGovernance is SubDaoTestBase {
  function setUp() public override {
    super.setUp();
    setupFork();

    VETokenVotingDaoFactory mainFactory = deployMainDaoWithEscrow();
    loadConfigAndDeploy("config/subdaos/approver-hat-minter.json", address(mainFactory));

    setupTestUsers();
  }

  // ============================================
  // Test: Full Flow Without Veto (Happy Path)
  // ============================================

  /// @notice Test full workflow without veto: Stage 0 (manual veto) → Stage 1 (voting veto) → Execution
  /// @dev Both stages are veto stages with approvalThreshold=0, so proposals advance if NOT vetoed
  function test_ProposalAdvancesWithoutVeto() public {
    // Verify the SubDAO is using the correct IVotesAdapter
    address subdaoIVotesAdapter = address(tokenVoting.getVotingToken());
    assertEq(subdaoIVotesAdapter, address(ivotesAdapter), "SubDAO should use Main DAO's IVotesAdapter");

    // Get controller address from config (Stage 0 controller in veto mode)
    address controller = testConfig.stage1.controllerAddress;

    // Setup: Alice and Bob get voter hats and voting power
    mintHatToAddress(voterHatId, alice);
    mintHatToAddress(voterHatId, bob);

    // Give them voting power via locks in main DAO
    createLock(alice, STANDARD_LOCK_AMOUNT);
    createLock(bob, STANDARD_LOCK_AMOUNT);

    // Delegate to self to activate voting power
    vm.prank(alice);
    ivotesAdapter.delegate(alice);
    vm.prank(bob);
    ivotesAdapter.delegate(bob);

    // Wait for checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Verify Alice has voting power
    uint256 aliceVotingPower = ivotesAdapter.getVotes(alice);
    assertTrue(aliceVotingPower > 0, "Alice should have voting power");

    // Step 1: Controller creates proposal (starts in Stage 0)
    uint256 proposalId = createMetadataProposal(controller);
    assertTrue(proposalId > 0, "Proposal should be created");

    // Verify proposal is in Stage 0 (first stage, 0-indexed)
    StagedProposalProcessor.Proposal memory proposal = sppPlugin.getProposal(proposalId);
    assertEq(proposal.currentStage, 0, "Proposal should start in Stage 0");

    // Wait for Stage 0 minAdvance duration
    vm.warp(block.timestamp + testConfig.stage1.minAdvance + 1);

    // Step 2: Advance to Stage 1 without veto
    // Stage 0 is a veto stage (approvalThreshold=0, vetoThreshold=1)
    // In veto stages, proposals advance if NOT vetoed (no reportProposalResult needed)
    vm.prank(alice);
    sppPlugin.advanceProposal(proposalId);

    // Verify proposal advanced to Stage 1
    proposal = sppPlugin.getProposal(proposalId);
    assertEq(proposal.currentStage, 1, "Proposal should be in Stage 1 after advancing");

    // Step 3: Hat wearers can vote in Stage 1 (via TokenVotingHats)
    // Get the Stage 1 voting proposal ID from SPP
    uint256 stage1VotingProposalId = sppPlugin.getBodyProposalId(proposalId, 1, address(tokenVoting));

    // Voters don't veto (both vote NO to veto)
    voteOnTokenVoting(alice, stage1VotingProposalId, IMajorityVoting.VoteOption.No);
    voteOnTokenVoting(bob, stage1VotingProposalId, IMajorityVoting.VoteOption.No);

    // Step 4: Wait for Stage 1 voting period to end
    vm.warp(block.timestamp + testConfig.stage2.minAdvance + 1);

    // Step 5: Execute the proposal
    vm.prank(controller);
    sppPlugin.execute(proposalId);

    // Verify proposal was executed (can't execute again)
    vm.expectRevert();
    vm.prank(controller);
    sppPlugin.execute(proposalId);
  }

  // ============================================
  // Test: Stage 0 Veto (First Stage)
  // ============================================

  function test_ControllerCanVeto() public {
    // Get controller address from config
    address controller = testConfig.stage1.controllerAddress;

    // Step 1: Controller creates proposal
    uint256 proposalId = createMetadataProposal(controller);

    // Verify proposal is in Stage 0
    StagedProposalProcessor.Proposal memory proposal = sppPlugin.getProposal(proposalId);
    assertEq(proposal.currentStage, 0, "Proposal should start in Stage 0");

    // Wait for Stage 0 minAdvance duration
    vm.warp(block.timestamp + testConfig.stage1.minAdvance + 1);

    // Step 2: Controller vetos in Stage 0
    reportProposalResult(controller, proposalId, 0, StagedProposalProcessor.ResultType.Veto, false);

    // Verify proposal was rejected (can't execute)
    vm.expectRevert();
    vm.prank(controller);
    sppPlugin.execute(proposalId);

    // Verify we can't advance the proposal
    vm.expectRevert();
    vm.prank(controller);
    sppPlugin.advanceProposal(proposalId);
  }

  // ============================================
  // Test: Stage 1 Veto (Second Stage - Voting)
  // ============================================

  function test_HatWearersCanVetoInStage1() public {
    // Get controller address from config
    address controller = testConfig.stage1.controllerAddress;

    // Setup: Alice and Bob get voter hats and voting power
    mintHatToAddress(voterHatId, alice);
    mintHatToAddress(voterHatId, bob);

    // Give them voting power via locks
    createLock(alice, STANDARD_LOCK_AMOUNT);
    createLock(bob, STANDARD_LOCK_AMOUNT);

    // Delegate to self
    vm.prank(alice);
    ivotesAdapter.delegate(alice);
    vm.prank(bob);
    ivotesAdapter.delegate(bob);

    // Wait for checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Step 1: Controller creates proposal
    uint256 proposalId = createMetadataProposal(controller);

    // Wait for Stage 0 minAdvance duration
    vm.warp(block.timestamp + testConfig.stage1.minAdvance + 1);

    // Step 2: Advance to Stage 1 without veto in Stage 0
    vm.prank(alice);
    sppPlugin.advanceProposal(proposalId);

    // Verify we're in Stage 1
    StagedProposalProcessor.Proposal memory proposal = sppPlugin.getProposal(proposalId);
    assertEq(proposal.currentStage, 1, "Proposal should be in Stage 1");

    // Step 3: Hat wearers veto in Stage 1
    // Both Alice and Bob vote YES to veto the proposal
    uint256 stage1VotingProposalId = sppPlugin.getBodyProposalId(proposalId, 1, address(tokenVoting));

    voteOnTokenVoting(alice, stage1VotingProposalId, IMajorityVoting.VoteOption.Yes);
    voteOnTokenVoting(bob, stage1VotingProposalId, IMajorityVoting.VoteOption.Yes);

    // Wait for Stage 1 voting period to end
    vm.warp(block.timestamp + testConfig.stage2.minAdvance + 1);

    // Step 4: Try to execute (should fail - proposal was vetoed)
    vm.expectRevert();
    vm.prank(controller);
    sppPlugin.execute(proposalId);
  }

  // ============================================
  // Test: Only Controller Can Create Proposals
  // ============================================

  function test_OnlyControllerCanPropose() public {
    // Try to create proposal as unauthorized user (alice)
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://hacked") });

    // Should revert because alice doesn't have CREATE_PROPOSAL permission
    vm.expectRevert();
    createSppProposal(alice, "Unauthorized proposal", actions);

    // Verify controller CAN create proposals
    address controller = testConfig.stage1.controllerAddress;
    uint256 proposalId = createMetadataProposal(controller);
    assertTrue(proposalId > 0, "Controller should be able to create proposals");
  }

  // ============================================
  // Test: Only Hat Wearers Can Vote in Stage 1
  // ============================================

  function test_OnlyHatWearersCanVoteInStage1() public {
    // Get controller address
    address controller = testConfig.stage1.controllerAddress;

    // Setup: Only Alice gets voter hat (Bob does NOT)
    mintHatToAddress(voterHatId, alice);

    // Give both voting power, but only Alice has the hat
    createLock(alice, STANDARD_LOCK_AMOUNT);
    createLock(bob, STANDARD_LOCK_AMOUNT);

    vm.prank(alice);
    ivotesAdapter.delegate(alice);
    vm.prank(bob);
    ivotesAdapter.delegate(bob);

    // Wait for checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Create and advance proposal to Stage 1 (voting stage)
    uint256 proposalId = createMetadataProposal(controller);

    // Wait for Stage 0 minAdvance duration
    vm.warp(block.timestamp + testConfig.stage1.minAdvance + 1);

    // Advance to stage 1
    vm.prank(alice);
    sppPlugin.advanceProposal(proposalId);

    // Get the Stage 1 voting proposal ID from SPP
    uint256 stage1VotingProposalId = sppPlugin.getBodyProposalId(proposalId, 1, address(tokenVoting));

    // Alice CAN vote (has hat)
    voteOnTokenVoting(alice, stage1VotingProposalId, IMajorityVoting.VoteOption.Yes);

    // Verify Alice's vote was counted
    assertEq(
      uint256(tokenVoting.getVoteOption(stage1VotingProposalId, alice)),
      uint256(IMajorityVoting.VoteOption.Yes),
      "Alice should have voted Yes"
    );

    // Bob CANNOT vote (no hat) - should revert
    vm.expectRevert();
    voteOnTokenVoting(bob, stage1VotingProposalId, IMajorityVoting.VoteOption.Yes);
  }
}
