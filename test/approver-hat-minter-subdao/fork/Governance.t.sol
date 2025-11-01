// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { ApproverHatMinterSubDaoTestBase } from "../base/ApproverHatMinterSubDaoTestBase.sol";
import { IMajorityVoting } from "@token-voting-hats/base/IMajorityVoting.sol";
import { StagedProposalProcessor } from "staged-proposal-processor-plugin/StagedProposalProcessor.sol";
import { Action } from "@aragon/osx/core/dao/DAO.sol";
import { VETokenVotingDaoFactory, Deployment as MainDaoDeployment } from "../../../src/VETokenVotingDaoFactory.sol";
import { DeployDaoFromConfigScript } from "../../../script/DeployDao.s.sol";
import { VotingEscrowV1_2_0 as VotingEscrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { EscrowIVotesAdapter } from "@delegation/EscrowIVotesAdapter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GovernanceTest
 * @notice Tests end-to-end governance workflows for ApproverHatMinterSubDao
 * @dev Tests the 2-stage approval process: Stage 0 (manual approve/veto) → Stage 1 (hat voting)
 * @dev NOTE: Stages are 0-indexed in SPP
 */
contract GovernanceTest is ApproverHatMinterSubDaoTestBase {
  // Test users (EOAs)
  address alice = vm.addr(1);
  address bob = vm.addr(2);
  address charlie = vm.addr(3);

  // Main DAO components (needed for voting power)
  VotingEscrow internal escrow;
  EscrowIVotesAdapter internal ivotesAdapter;

  // Standard lock amounts
  uint256 constant STANDARD_LOCK_AMOUNT = 1000 ether;

  function setUp() public override {
    // Note: We need to set up fork BEFORE calling super.setUp()
    // because super.setUp() will try to parse hat IDs from the factory
    forkBlockNumber = 0; // Use latest block
    setupFork();

    // Deploy Main DAO FIRST (before calling super.setUp())
    // This ensures the factory exists when super.setUp() tries to query it
    DeployDaoFromConfigScript script = new DeployDaoFromConfigScript();
    VETokenVotingDaoFactory mainFactory = script.execute();
    MainDaoDeployment memory mainDeployment = mainFactory.getDeployment();

    // Store escrow and ivotesAdapter for test use
    escrow = mainDeployment.veSystem.votingEscrow;
    ivotesAdapter = mainDeployment.veSystem.ivotesAdapter;

    // Now call super.setUp() to load config and create script instance
    super.setUp();

    // Update testConfig to use the freshly deployed main DAO factory
    testConfig.mainDaoFactoryAddress = address(mainFactory);

    // Parse hat IDs from the freshly deployed factory
    _parseHatIdsFromConfig();

    // Deploy SubDAO - it will automatically query main DAO factory for adapter!
    deployFactoryAndSubdao(address(mainFactory), address(0));

    // Ensure test users are proper EOAs (not contracts)
    vm.etch(alice, "");
    vm.etch(bob, "");
    vm.etch(charlie, "");

    // Label test users for better trace readability
    vm.label(alice, "alice");
    vm.label(bob, "bob");
    vm.label(charlie, "charlie");
  }

  /// @notice Create a lock for a user to give them voting power
  function createLock(address user, uint256 amount) internal returns (uint256 lockId) {
    // Get the token address
    address tokenAddress = escrow.token();
    IERC20 token = IERC20(tokenAddress);

    // Deal tokens to user
    vm.deal(user, amount * 2); // Give ETH for gas
    deal(tokenAddress, user, amount);

    // User approves escrow and creates lock
    vm.startPrank(user);
    token.approve(address(escrow), amount);
    lockId = escrow.createLock(amount);
    vm.stopPrank();
  }

  // ============================================
  // Helper: Create Simple Metadata Proposal
  // ============================================

  /// @notice Create a simple DAO metadata update proposal
  function createMetadataProposal(address proposer) internal returns (uint256 proposalId) {
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://updated") });

    proposalId = createSppProposal(proposer, "Update SubDAO Metadata", actions);
  }

  // ============================================
  // Test 1: Full Flow Without Veto (Happy Path)
  // ============================================

  /// @notice Test full workflow without veto: Stage 0 (manual veto) → Stage 1 (voting veto) → Execution
  /// @dev Both stages are veto stages with approvalThreshold=0, so proposals advance if NOT vetoed
  function test_FullApprovalFlow() public {
    // Verify the SubDAO is using the correct IVotesAdapter
    address subdaoIVotesAdapter = address(tokenVoting.getVotingToken());
    assertEq(subdaoIVotesAdapter, address(ivotesAdapter), "SubDAO should use Main DAO's IVotesAdapter");

    // Get proposer address from config (Stage 0 approver)
    address proposer = testConfig.stage1.proposerAddress;

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

    // Step 1: Proposer creates proposal (starts in Stage 0)
    uint256 proposalId = createMetadataProposal(proposer);
    assertTrue(proposalId > 0, "Proposal should be created");

    // Verify proposal is in Stage 0 (first stage, 0-indexed)
    StagedProposalProcessor.Proposal memory proposal = sppPlugin.getProposal(proposalId);
    assertEq(proposal.currentStage, 0, "Proposal should start in Stage 0");

    // Wait for Stage 0 minAdvance duration (3600 seconds)
    vm.warp(block.timestamp + testConfig.stage1.minAdvance + 1);

    // Step 2: Advance to Stage 1 without veto
    // Stage 0 is a veto stage (approvalThreshold=0, vetoThreshold=1)
    // In veto stages, proposals advance if NOT vetoed (no reportProposalResult needed)
    // Anyone can call advanceProposal since ADVANCE_PERMISSION is granted to ANY_ADDR
    vm.prank(alice);
    sppPlugin.advanceProposal(proposalId);

    // Verify proposal advanced to Stage 1
    proposal = sppPlugin.getProposal(proposalId);
    assertEq(proposal.currentStage, 1, "Proposal should be in Stage 1 after advancing");

    // Step 3: Hat wearers can vote in Stage 1 (via TokenVotingHats)
    // Stage 1 is an automatic veto stage - SPP created a sub-proposal in TokenVotingHats
    // In veto voting: YES = veto the proposal, NO = don't veto
    // The proposal is blocked only if the veto vote PASSES (reaches support threshold)

    // Get the Stage 1 voting proposal ID from SPP
    // Stage 1 is at index 1 (0-indexed), and the body is the TokenVotingHats plugin
    uint256 stage1VotingProposalId = sppPlugin.getBodyProposalId(proposalId, 1, address(tokenVoting));

    // Voters can participate but neither vetoes (both vote NO to veto)
    // This ensures the veto proposal FAILS, allowing the main proposal to advance
    voteOnTokenVoting(alice, stage1VotingProposalId, IMajorityVoting.VoteOption.No);
    voteOnTokenVoting(bob, stage1VotingProposalId, IMajorityVoting.VoteOption.No);

    // Step 4: Wait for Stage 1 voting period to end
    // Stage 1 has minAdvance duration (259200 seconds = 3 days)
    vm.warp(block.timestamp + testConfig.stage2.minAdvance + 1);

    // Step 5: Execute the proposal
    // Since Stage 1 is the last stage, advance = execute
    // SPP will automatically check hasSucceeded() on the TokenVotingHats sub-proposal
    // The veto proposal FAILED (not enough YES votes), so the main proposal can execute
    vm.prank(proposer);
    sppPlugin.execute(proposalId);

    // Verify proposal was executed
    // Check that we can't execute again
    vm.expectRevert();
    vm.prank(proposer);
    sppPlugin.execute(proposalId);
  }

  // ============================================
  // Test 2: Stage 0 Veto (First Stage)
  // ============================================

  function test_Stage1Veto() public {
    // Get proposer address from config
    address proposer = testConfig.stage1.proposerAddress;

    // Step 1: Proposer creates proposal
    uint256 proposalId = createMetadataProposal(proposer);

    // Verify proposal is in Stage 0
    StagedProposalProcessor.Proposal memory proposal = sppPlugin.getProposal(proposalId);
    assertEq(proposal.currentStage, 0, "Proposal should start in Stage 0");

    // Wait for Stage 1 minAdvance duration (3600 seconds)
    vm.warp(block.timestamp + testConfig.stage1.minAdvance + 1);

    // Step 2: Proposer vetos in Stage 0
    reportProposalResult(proposer, proposalId, 0, StagedProposalProcessor.ResultType.Veto, false);

    // Verify proposal was rejected (not advanced to Stage 1)
    proposal = sppPlugin.getProposal(proposalId);
    // After veto, the proposal should still be in Stage 0 but rejected
    // SPP marks it as rejected, not executable

    // Step 3: Try to execute (should fail)
    vm.expectRevert();
    vm.prank(proposer);
    sppPlugin.execute(proposalId);

    // Verify we can't advance the proposal
    vm.expectRevert();
    advanceProposal(proposer, proposalId);
  }

  // ============================================
  // Test 3: Stage 1 Veto (Second Stage - Voting)
  // ============================================

  function test_Stage2Veto() public {
    // Get proposer address from config
    address proposer = testConfig.stage1.proposerAddress;

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

    // Step 1: Proposer creates proposal
    uint256 proposalId = createMetadataProposal(proposer);

    // Wait for Stage 0 minAdvance duration (3600 seconds)
    vm.warp(block.timestamp + testConfig.stage1.minAdvance + 1);

    // Step 2: Advance to Stage 1 without veto in Stage 0
    vm.prank(alice);
    sppPlugin.advanceProposal(proposalId);

    // Verify we're in Stage 1
    StagedProposalProcessor.Proposal memory proposal = sppPlugin.getProposal(proposalId);
    assertEq(proposal.currentStage, 1, "Proposal should be in Stage 1");

    // Step 3: Hat wearers veto in Stage 1
    // In veto voting: YES = veto the proposal, NO = don't veto
    // Both Alice and Bob vote YES to veto the proposal
    // Get the Stage 1 voting proposal ID from SPP
    uint256 stage1VotingProposalId = sppPlugin.getBodyProposalId(proposalId, 1, address(tokenVoting));

    voteOnTokenVoting(alice, stage1VotingProposalId, IMajorityVoting.VoteOption.Yes);
    voteOnTokenVoting(bob, stage1VotingProposalId, IMajorityVoting.VoteOption.Yes);

    // Wait for Stage 1 voting period to end
    vm.warp(block.timestamp + testConfig.stage2.minAdvance + 1);

    // Step 4: Try to execute (should fail - proposal was vetoed)
    // The veto proposal PASSED (enough YES votes), blocking the main proposal
    vm.expectRevert();
    vm.prank(proposer);
    sppPlugin.execute(proposalId);
  }

  // ============================================
  // Test 4: Verify Voting Power Scales with Locked Tokens
  // ============================================

  /// @notice Verify that voting power scales linearly with locked token amount
  /// @dev Expected: 1 locked token = 1 voting power (not one-person-one-vote)
  function test_VotingPowerScalesWithLockedTokens() public {
    // Setup: Give Alice, Bob, and Charlie voter hats
    mintHatToAddress(voterHatId, alice);
    mintHatToAddress(voterHatId, bob);
    mintHatToAddress(voterHatId, charlie);

    // Lock different amounts:
    // Alice: 1 ether
    // Bob: 10 ether (10x Alice)
    // Charlie: 100 ether (100x Alice)
    createLock(alice, 1 ether);
    createLock(bob, 10 ether);
    createLock(charlie, 100 ether);

    // Delegate to self to activate voting power
    vm.prank(alice);
    ivotesAdapter.delegate(alice);
    vm.prank(bob);
    ivotesAdapter.delegate(bob);
    vm.prank(charlie);
    ivotesAdapter.delegate(charlie);

    // Wait for checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Measure voting power
    uint256 aliceVP = ivotesAdapter.getVotes(alice);
    uint256 bobVP = ivotesAdapter.getVotes(bob);
    uint256 charlieVP = ivotesAdapter.getVotes(charlie);

    // Log the actual values for debugging
    emit log_named_uint("Alice VP (1 ether locked)", aliceVP);
    emit log_named_uint("Bob VP (10 ether locked)", bobVP);
    emit log_named_uint("Charlie VP (100 ether locked)", charlieVP);

    // Verify linear scaling: voting power should be proportional to locked amount
    // Bob should have ~10x Alice's voting power
    // Charlie should have ~100x Alice's voting power
    // Allow for small rounding errors (1% tolerance)
    assertApproxEqRel(bobVP, aliceVP * 10, 0.01e18, "Bob should have ~10x Alice's voting power");
    assertApproxEqRel(charlieVP, aliceVP * 100, 0.01e18, "Charlie should have ~100x Alice's voting power");
  }

  // ============================================
  // Test 5: Single Voter with Minimal Voting Power Can Veto
  // ============================================

  /// @notice Verify that even minimal voting power can veto when outnumbered
  /// @dev With supportThreshold=0 and vetoThreshold=1, any YES vote should veto regardless of voting power
  function test_SingleVoterCanVeto() public {
    // Get proposer address
    address proposer = testConfig.stage1.proposerAddress;

    // Setup: Give all voters hats
    mintHatToAddress(voterHatId, alice);
    mintHatToAddress(voterHatId, bob);
    mintHatToAddress(voterHatId, charlie);

    // Give Alice MINIMAL voting power (1 ether lock - the minimum allowed)
    // Give Bob and Charlie MASSIVE voting power (1000 ether locks each - 1000x more)
    createLock(alice, 1 ether); // Minimum allowed
    createLock(bob, STANDARD_LOCK_AMOUNT); // 1000 ether
    createLock(charlie, STANDARD_LOCK_AMOUNT); // 1000 ether

    // Delegate to self to activate voting power
    vm.prank(alice);
    ivotesAdapter.delegate(alice);
    vm.prank(bob);
    ivotesAdapter.delegate(bob);
    vm.prank(charlie);
    ivotesAdapter.delegate(charlie);

    // Wait for checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Verify voting power distribution: Alice has only 0.05% of total voting power
    uint256 aliceVP = ivotesAdapter.getVotes(alice);
    uint256 bobVP = ivotesAdapter.getVotes(bob);
    uint256 charlieVP = ivotesAdapter.getVotes(charlie);

    assertEq(aliceVP, 1 ether, "Alice should have 1 ether VP");
    assertEq(bobVP, 1000 ether, "Bob should have 1000 ether VP");
    assertEq(charlieVP, 1000 ether, "Charlie should have 1000 ether VP");

    // Alice has only 1 out of 2001 total voting power (0.05%)
    uint256 totalVP = aliceVP + bobVP + charlieVP;
    assertTrue(aliceVP * 100 < totalVP, "Alice should have < 1% of total voting power");

    // Step 1: Create proposal
    uint256 proposalId = createMetadataProposal(proposer);

    // Wait for Stage 0 minAdvance
    vm.warp(block.timestamp + testConfig.stage1.minAdvance + 1);

    // Step 2: Advance to Stage 1 without veto
    vm.prank(alice);
    sppPlugin.advanceProposal(proposalId);

    // Step 3: Vote in Stage 1
    // Alice (1 ether VP) votes YES to veto
    // Bob (1000 ether VP) and Charlie (1000 ether VP) vote NO (don't veto)
    // Despite having only 0.05% of the voting power (1 out of 2001 total), Alice's veto should succeed
    uint256 stage1VotingProposalId = sppPlugin.getBodyProposalId(proposalId, 1, address(tokenVoting));

    voteOnTokenVoting(alice, stage1VotingProposalId, IMajorityVoting.VoteOption.Yes); // Veto with minimal VP
    voteOnTokenVoting(bob, stage1VotingProposalId, IMajorityVoting.VoteOption.No); // Don't veto with 1000x VP
    voteOnTokenVoting(charlie, stage1VotingProposalId, IMajorityVoting.VoteOption.No); // Don't veto with 1000x VP

    // Wait for voting period to end
    vm.warp(block.timestamp + testConfig.stage2.minAdvance + 1);

    // Step 4: Try to execute - should FAIL because Alice vetoed
    // With supportThreshold=0, even minimal voting power can pass the veto sub-proposal
    // This proves ANY voter with ANY amount of voting power can veto, regardless of being outnumbered
    vm.expectRevert();
    vm.prank(proposer);
    sppPlugin.execute(proposalId);
  }

  // ============================================
  // Test 5: Only Proposer Can Create Proposals
  // ============================================

  function test_OnlyProposerCanCreateProposals() public {
    // Try to create proposal as unauthorized user (alice)
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://hacked") });

    // Should revert because alice doesn't have CREATE_PROPOSAL permission
    vm.expectRevert();
    createSppProposal(alice, "Unauthorized proposal", actions);

    // Verify proposer CAN create proposals
    address proposer = testConfig.stage1.proposerAddress;
    uint256 proposalId = createMetadataProposal(proposer);
    assertTrue(proposalId > 0, "Proposer should be able to create proposals");
  }

  // ============================================
  // Test 5: Only Hat Wearers Can Vote in Stage 1 (Voting Stage)
  // ============================================

  function test_OnlyHatWearersCanVoteStage2() public {
    // Get proposer address
    address proposer = testConfig.stage1.proposerAddress;

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
    uint256 proposalId = createMetadataProposal(proposer);

    // Wait for Stage 1 minAdvance duration (3600 seconds)
    vm.warp(block.timestamp + testConfig.stage1.minAdvance + 1);

    reportProposalResult(proposer, proposalId, 0, StagedProposalProcessor.ResultType.Approval, true);

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

  // ============================================
  // Test 6: Only SPP Can Execute on DAO
  // ============================================

  function test_OnlySppCanExecuteOnDao() public {
    // Try to execute an action directly on the DAO (should fail)
    bytes32 EXECUTE_PERMISSION_ID = dao.EXECUTE_PERMISSION_ID();

    // Random address tries to execute on DAO
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://hacked") });

    // Should fail - alice doesn't have EXECUTE permission
    vm.expectRevert();
    vm.prank(alice);
    dao.execute(bytes32(0), actions, 0);

    // Verify SPP does have EXECUTE permission
    assertTrue(
      dao.hasPermission(address(dao), address(sppPlugin), EXECUTE_PERMISSION_ID, bytes("")),
      "SPP should have EXECUTE permission"
    );

    // Verify random address does NOT have EXECUTE permission
    assertFalse(
      dao.hasPermission(address(dao), alice, EXECUTE_PERMISSION_ID, bytes("")),
      "Alice should not have EXECUTE permission"
    );
  }
}
