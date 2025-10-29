// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { FactoryTestBase } from "../base/FactoryTestBase.sol";
import { IMajorityVoting } from "@token-voting-hats/base/IMajorityVoting.sol";
import { Action } from "@aragon/osx/core/dao/DAO.sol";

/**
 * @title GovernanceFlowTest
 * @notice Tests complete end-to-end governance flows with Hats + VE system
 * @dev Tests the full lifecycle: lock → hat → propose → vote → execute
 */
contract GovernanceFlowTest is FactoryTestBase {
  // Test users (EOAs)
  address alice = vm.addr(1);
  address bob = vm.addr(2);
  address charlie = vm.addr(3);

  // Standard lock amounts
  uint256 constant STANDARD_LOCK_AMOUNT = 1000 ether;
  uint256 constant LARGE_LOCK_AMOUNT = 5000 ether;

  function setUp() public override {
    super.setUp();

    // Set up fork and deploy DAO
    setupFork();
    deployFactoryAndDao();

    // Ensure test users are proper EOAs (not contracts) by setting code to empty
    // This is needed because vm.addr() addresses might collide with existing contracts on fork
    vm.etch(alice, "");
    vm.etch(bob, "");
    vm.etch(charlie, "");

    // Label test users for better trace readability
    vm.label(alice, "alice");
    vm.label(bob, "bob");
    vm.label(charlie, "charlie");
  }

  // ============================================
  // Helper: Setup DAO Member
  // ============================================

  /// @notice Setup a DAO member with voting power and member hat
  /// @dev The proposer and voter hats are the same (daoMember hat)
  /// @dev Executor hat is public (uint256(1)), so anyone can execute
  /// @param user The user address
  /// @param lockAmount Amount to lock for voting power
  function _setupDaoMember(address user, uint256 lockAmount) internal {
    // Create lock for voting power
    if (lockAmount > 0) {
      createLock(user, lockAmount);

      // Delegate to self to activate voting power (required for SelfDelegationEscrowIVotesAdapter)
      vm.prank(user);
      ivotesAdapter.delegate(user);
    }

    // Mint DAO member hat (proposer/voter are same hat)
    if (!hats.isWearerOfHat(user, proposerHatId)) {
      mintHatToAddress(proposerHatId, user);
    }
  }

  /// @notice Create a simple metadata update proposal
  function createSimpleProposal(address proposer) internal returns (uint256 proposalId) {
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://updated") });

    vm.prank(proposer);
    proposalId = tokenVoting.createProposal(
      "Update DAO Metadata",
      actions,
      0, // allowFailureMap
      0, // startDate
      0, // endDate
      IMajorityVoting.VoteOption.None,
      false // tryEarlyExecution
    );
  }

  // ============================================
  // Test 1: Complete Happy Path
  // ============================================

  function test_CompleteGovernanceHappyPath() public {
    // Setup: Alice and Bob are DAO members with voting power
    // Anyone can execute (public executor hat)
    _setupDaoMember(alice, STANDARD_LOCK_AMOUNT);
    _setupDaoMember(bob, STANDARD_LOCK_AMOUNT);

    // Wait for voting power checkpoints to be recorded
    // This ensures voting power is available at the proposal snapshot time
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12); // ~1 block

    // Step 1: Alice creates proposal
    uint256 proposalId = createSimpleProposal(alice);
    assertTrue(proposalId > 0, "Proposal should be created");

    // Step 2: Alice and Bob vote YES
    vm.prank(alice);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    vm.prank(bob);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    // Verify votes were cast
    assertEq(
      uint256(tokenVoting.getVoteOption(proposalId, alice)),
      uint256(IMajorityVoting.VoteOption.Yes),
      "Alice should have voted Yes"
    );
    assertEq(
      uint256(tokenVoting.getVoteOption(proposalId, bob)),
      uint256(IMajorityVoting.VoteOption.Yes),
      "Bob should have voted Yes"
    );

    // Step 3: Wait for minDuration (3600 seconds = 1 hour)
    vm.warp(block.timestamp + testConfig.tokenVotingHats.minDuration + 1);

    // Step 4: Verify proposal can be executed
    assertTrue(tokenVoting.canExecute(proposalId), "Proposal should be executable");

    // Step 5: Charlie executes the proposal
    vm.prank(charlie);
    tokenVoting.execute(proposalId);

    // Step 6: Verify proposal was executed
    assertFalse(tokenVoting.canExecute(proposalId), "Proposal should no longer be executable after execution");
  }

  // ============================================
  // Test 2: Insufficient Support
  // ============================================

  function test_ProposalInsufficientSupport() public {
    // Setup participants
    _setupDaoMember(alice, STANDARD_LOCK_AMOUNT);
    _setupDaoMember(bob, LARGE_LOCK_AMOUNT); // Bob has more voting power

    // Wait for voting power checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Create proposal
    uint256 proposalId = createSimpleProposal(alice);

    // Alice votes YES (small amount)
    vm.prank(alice);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    // Bob votes NO (large amount - this will fail support threshold)
    vm.prank(bob);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.No, false);

    // Wait for voting period
    vm.warp(block.timestamp + testConfig.tokenVotingHats.minDuration + 1);

    // Proposal should NOT be executable (support threshold not met)
    assertFalse(tokenVoting.canExecute(proposalId), "Proposal should not be executable with insufficient support");

    // Execution should revert
    vm.expectRevert();
    vm.prank(charlie);
    tokenVoting.execute(proposalId);
  }

  // ============================================
  // Test 3: Insufficient Participation
  // ============================================

  function test_ProposalInsufficientParticipation() public {
    // Setup: Alice can propose/vote with small amount
    // Bob has large lock but doesn't vote (low participation)
    _setupDaoMember(alice, STANDARD_LOCK_AMOUNT);
    _setupDaoMember(bob, LARGE_LOCK_AMOUNT * 10); // Bob has 10x more power but won't vote

    // Wait for voting power checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Create proposal
    uint256 proposalId = createSimpleProposal(alice);

    // Only Alice votes (very small % of total voting power)
    vm.prank(alice);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    // Wait for voting period
    vm.warp(block.timestamp + testConfig.tokenVotingHats.minDuration + 1);

    // Proposal should NOT be executable (participation threshold not met)
    // Config has 15% min participation, Alice has < 10% of total power
    assertFalse(
      tokenVoting.canExecute(proposalId), "Proposal should not be executable with insufficient participation"
    );

    // Execution should revert
    vm.expectRevert();
    vm.prank(charlie);
    tokenVoting.execute(proposalId);
  }

  // ============================================
  // Test 4: Cannot Execute Before MinDuration
  // ============================================

  function test_CannotExecuteBeforeMinDuration() public {
    // Setup participants
    _setupDaoMember(alice, STANDARD_LOCK_AMOUNT);
    _setupDaoMember(bob, STANDARD_LOCK_AMOUNT);

    // Wait for voting power checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Create and vote on proposal
    uint256 proposalId = createSimpleProposal(alice);

    vm.prank(alice);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    vm.prank(bob);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    // Try to execute immediately (should fail - minDuration not passed)
    assertFalse(tokenVoting.canExecute(proposalId), "Proposal should not be executable before minDuration");

    vm.expectRevert();
    vm.prank(charlie);
    tokenVoting.execute(proposalId);

    // Wait half the duration (still not enough)
    vm.warp(block.timestamp + testConfig.tokenVotingHats.minDuration / 2);

    assertFalse(tokenVoting.canExecute(proposalId), "Proposal should not be executable at half minDuration");

    vm.expectRevert();
    vm.prank(charlie);
    tokenVoting.execute(proposalId);

    // Wait full duration + 1 second (now it should work)
    vm.warp(block.timestamp + testConfig.tokenVotingHats.minDuration / 2 + 1);

    assertTrue(tokenVoting.canExecute(proposalId), "Proposal should be executable after minDuration");

    vm.prank(charlie);
    tokenVoting.execute(proposalId);
  }

  // ============================================
  // Test 5: DAO State Modification via Proposal
  // ============================================

  function test_DaoStateModification() public {
    // Setup participants
    _setupDaoMember(alice, STANDARD_LOCK_AMOUNT);
    _setupDaoMember(bob, STANDARD_LOCK_AMOUNT);

    // Wait for voting power checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Create proposal to grant a new permission
    address newRecipient = makeAddr("newRecipient");
    bytes32 EXECUTE_PERMISSION_ID = dao.EXECUTE_PERMISSION_ID();

    Action[] memory actions = new Action[](1);
    actions[0] = Action({
      to: address(dao),
      value: 0,
      data: abi.encodeWithSignature(
        "grant(address,address,bytes32)", address(dao), newRecipient, EXECUTE_PERMISSION_ID
      )
    });

    vm.prank(alice);
    uint256 proposalId = tokenVoting.createProposal(
      "Grant EXECUTE_PERMISSION to new recipient",
      actions,
      0,
      0,
      0,
      IMajorityVoting.VoteOption.None,
      false
    );

    // Vote
    vm.prank(alice);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    vm.prank(bob);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    // Verify permission does NOT exist yet
    assertFalse(
      dao.hasPermission(address(dao), newRecipient, EXECUTE_PERMISSION_ID, bytes("")),
      "Permission should not exist before execution"
    );

    // Execute
    vm.warp(block.timestamp + testConfig.tokenVotingHats.minDuration + 1);

    vm.prank(charlie);
    tokenVoting.execute(proposalId);

    // Verify permission WAS granted
    assertTrue(
      dao.hasPermission(address(dao), newRecipient, EXECUTE_PERMISSION_ID, bytes("")),
      "Permission should exist after execution"
    );
  }

  // ============================================
  // Test 6: VE System Parameter Update via Governance
  // ============================================

  function test_VeSystemParameterUpdate() public {

    // Setup participants
    _setupDaoMember(alice, STANDARD_LOCK_AMOUNT);
    _setupDaoMember(bob, STANDARD_LOCK_AMOUNT);

    // Wait for voting power checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Get current fee (should be 0% from config)
    uint256 currentFee = exitQueue.feePercent();
    assertEq(currentFee, 0, "Initial fee should be 0%");

    // Create proposal to update exit queue fee to 1% (100 basis points)
    // Using setFixedExitFeePercent which takes (feePercent, minCooldown)
    uint256 newFee = 100; // 1% = 100 basis points
    uint48 minCooldown = 0; // Keep current minCooldown

    Action[] memory actions = new Action[](1);
    actions[0] = Action({
      to: address(exitQueue),
      value: 0,
      data: abi.encodeWithSignature("setFixedExitFeePercent(uint256,uint48)", newFee, minCooldown)
    });

    vm.prank(alice);
    uint256 proposalId = tokenVoting.createProposal(
      "Update exit queue fee to 1%",
      actions,
      0,
      0,
      0,
      IMajorityVoting.VoteOption.None,
      false
    );

    // Vote
    vm.prank(alice);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    vm.prank(bob);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    // Execute
    vm.warp(block.timestamp + testConfig.tokenVotingHats.minDuration + 1);

    vm.prank(charlie);
    tokenVoting.execute(proposalId);

    // Verify fee was updated
    assertEq(exitQueue.feePercent(), newFee, "Fee should be updated to 1%");
  }
}
