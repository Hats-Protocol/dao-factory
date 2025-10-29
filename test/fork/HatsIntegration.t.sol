// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { FactoryTestBase } from "../base/FactoryTestBase.sol";
import { IMajorityVoting } from "@token-voting-hats/base/IMajorityVoting.sol";
import { Action } from "@aragon/osx/core/dao/DAO.sol";

/**
 * @title HatsIntegrationTest
 * @notice Tests Hats Protocol integration with real Hats contract on Sepolia fork
 * @dev Validates hat-gated proposal creation, voting, and execution
 */
contract HatsIntegrationTest is FactoryTestBase {
  // Test users (EOAs)
  address alice = vm.addr(1);
  address bob = vm.addr(2);
  address charlie = vm.addr(3);

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

  // ============================================
  // Test 1: Proposer Hat Required
  // ============================================

  function test_ProposerHatRequired() public {
    // Setup: Alice needs voting power to create proposal
    uint256 lockAmount = 1000 ether;
    createLock(alice, lockAmount);
    vm.prank(alice);
    ivotesAdapter.delegate(alice);

    // Wait for voting power checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Create a simple proposal action
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://test") });

    // Alice WITHOUT proposer hat should NOT be able to create proposal (even with voting power)
    vm.expectRevert();
    vm.prank(alice);
    tokenVoting.createProposal(
      "Test Proposal",
      actions,
      0, // allowFailureMap
      0, // startDate
      0, // endDate
      IMajorityVoting.VoteOption.None,
      false // tryEarlyExecution
    );

    // Mint proposer hat to Alice (proposerHatId = daoMember hat)
    mintHatToAddress(proposerHatId, alice);

    // Alice WITH proposer hat AND voting power SHOULD be able to create proposal
    vm.prank(alice);
    uint256 proposalId = tokenVoting.createProposal(
      "Test Proposal",
      actions,
      0, // allowFailureMap
      0, // startDate
      0, // endDate
      IMajorityVoting.VoteOption.None,
      false // tryEarlyExecution
    );

    // Verify proposal was created
    assertTrue(proposalId > 0, "Proposal should be created");
  }

  function test_WrongHatCannotCreateProposal() public {
    // Setup: Bob has voting power but no daoMember hat
    uint256 lockAmount = 1000 ether;
    createLock(bob, lockAmount);
    vm.prank(bob);
    ivotesAdapter.delegate(bob);

    // Wait for voting power checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Create a simple proposal action
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://test") });

    // Bob with voting power but WITHOUT daoMember hat should NOT be able to create proposal
    vm.expectRevert();
    vm.prank(bob);
    tokenVoting.createProposal(
      "Test Proposal",
      actions,
      0, // allowFailureMap
      0, // startDate
      0, // endDate
      IMajorityVoting.VoteOption.None,
      false // tryEarlyExecution
    );
  }

  // ============================================
  // Test 2: Voter Hat Required
  // ============================================

  function test_VoterHatRequired() public {
    // Setup: Create a lock for Alice to have voting power and activate it
    uint256 lockAmount = 1000 ether;
    createLock(alice, lockAmount);
    vm.prank(alice);
    ivotesAdapter.delegate(alice);

    // Setup: Charlie as DAO member with voting power to create proposal
    _setupDaoMember(charlie, 100 ether);

    // Wait for voting power checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Create proposal
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://test") });

    vm.prank(charlie);
    uint256 proposalId =
      tokenVoting.createProposal("Test Proposal", actions, 0, 0, 0, IMajorityVoting.VoteOption.None, false);

    // Alice WITHOUT daoMember hat should NOT be able to vote (even with voting power)
    vm.expectRevert();
    vm.prank(alice);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    // Mint daoMember hat to Alice (proposerHatId = voterHatId = daoMember hat)
    mintHatToAddress(proposerHatId, alice);

    // Alice WITH daoMember hat AND voting power SHOULD be able to vote
    vm.prank(alice);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    // Verify vote was cast
    IMajorityVoting.VoteOption voteOption = tokenVoting.getVoteOption(proposalId, alice);
    assertEq(uint256(voteOption), uint256(IMajorityVoting.VoteOption.Yes), "Vote should be Yes");
  }

  function test_WrongHatCannotVote() public {
    // Setup: Bob has voting power and activates it
    uint256 lockAmount = 1000 ether;
    createLock(bob, lockAmount);
    vm.prank(bob);
    ivotesAdapter.delegate(bob);

    // Setup: Alice as DAO member to create proposal
    _setupDaoMember(alice, 100 ether);

    // Wait for voting power checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Create proposal
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://test") });

    vm.prank(alice);
    uint256 proposalId =
      tokenVoting.createProposal("Test Proposal", actions, 0, 0, 0, IMajorityVoting.VoteOption.None, false);

    // Bob with voting power but WITHOUT daoMember hat should NOT be able to vote
    vm.expectRevert();
    vm.prank(bob);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
  }

  // ============================================
  // Test 3: Executor Hat Required
  // ============================================

  function test_ExecutorHatRequired() public {
    // Note: Executor hat is public (uint256(1) sentinel), meaning ANYONE can execute passing proposals
    // This test validates that execution works without needing a specific hat

    // Setup: Alice as DAO member with voting power
    _setupDaoMember(alice, 1000 ether);
    _setupDaoMember(bob, 1000 ether);

    // Wait for voting power checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Create and vote on proposal
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://test") });

    vm.prank(alice);
    uint256 proposalId =
      tokenVoting.createProposal("Test Proposal", actions, 0, 0, 0, IMajorityVoting.VoteOption.None, false);

    vm.prank(alice);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    vm.prank(bob);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    // Wait for voting period to end
    vm.warp(block.timestamp + testConfig.tokenVotingHats.minDuration + 1);

    // Charlie (who has NO hats and NO voting power) CAN execute because executor is public
    vm.prank(charlie);
    tokenVoting.execute(proposalId);

    // Verify proposal was executed
    assertFalse(tokenVoting.canExecute(proposalId), "Proposal should be executed");
  }

  // ============================================
  // Test 4: Hat Revocation Blocks Access
  // ============================================

  function test_HatRevocationBlocksAccess() public {
    // Setup: Alice has voting power and daoMember hat
    uint256 lockAmount = 1000 ether;
    createLock(alice, lockAmount);
    vm.prank(alice);
    ivotesAdapter.delegate(alice);

    mintHatToAddress(proposerHatId, alice);

    // Setup: Charlie as DAO member to create proposals
    _setupDaoMember(charlie, 100 ether);

    // Wait for voting power checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Create proposal
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://test") });

    vm.prank(charlie);
    uint256 proposalId =
      tokenVoting.createProposal("Test Proposal", actions, 0, 0, 0, IMajorityVoting.VoteOption.None, false);

    // Alice votes successfully
    vm.prank(alice);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    // Verify Alice voted
    IMajorityVoting.VoteOption aliceVote = tokenVoting.getVoteOption(proposalId, alice);
    assertEq(uint256(aliceVote), uint256(IMajorityVoting.VoteOption.Yes), "Alice should have voted Yes");

    // Now create a second proposal
    vm.prank(charlie);
    uint256 proposalId2 =
      tokenVoting.createProposal("Test Proposal 2", actions, 0, 0, 0, IMajorityVoting.VoteOption.None, false);

    // Revoke Alice's daoMember hat (burn it)
    vm.prank(address(dao));
    hats.transferHat(proposerHatId, alice, address(0));

    // Alice should NOT be able to vote on the new proposal without the hat
    vm.expectRevert();
    vm.prank(alice);
    tokenVoting.vote(proposalId2, IMajorityVoting.VoteOption.Yes, false);
  }

  // ============================================
  // Test 5: Voting Power Calculation with Hats
  // ============================================

  function test_VotingPowerCalculationWithHats() public {
    // Setup: Create locks for Alice and Bob with different amounts
    uint256 aliceLockAmount = 1000 ether;
    uint256 bobLockAmount = 500 ether;

    // Use helper to setup Alice and Bob as DAO members with voting power
    _setupDaoMember(alice, aliceLockAmount);
    _setupDaoMember(bob, bobLockAmount);
    _setupDaoMember(charlie, 100 ether);

    // Wait for voting power checkpoints
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);

    // Create proposal
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://test") });

    vm.prank(charlie);
    uint256 proposalId =
      tokenVoting.createProposal("Test Proposal", actions, 0, 0, 0, IMajorityVoting.VoteOption.None, false);

    // Both vote
    vm.prank(alice);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    vm.prank(bob);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    // Verify both votes were cast
    IMajorityVoting.VoteOption aliceVote = tokenVoting.getVoteOption(proposalId, alice);
    IMajorityVoting.VoteOption bobVote = tokenVoting.getVoteOption(proposalId, bob);

    assertEq(uint256(aliceVote), uint256(IMajorityVoting.VoteOption.Yes), "Alice should have voted Yes");
    assertEq(uint256(bobVote), uint256(IMajorityVoting.VoteOption.Yes), "Bob should have voted Yes");

    // Check voting power via the VE adapter (voting power = lock amount for flat curve)
    uint256 aliceVotingPower = ivotesAdapter.getVotes(alice);
    uint256 bobVotingPower = ivotesAdapter.getVotes(bob);

    assertEq(aliceVotingPower, aliceLockAmount, "Alice's voting power should equal her lock amount");
    assertEq(bobVotingPower, bobLockAmount, "Bob's voting power should equal his lock amount");
    assertGt(aliceVotingPower, bobVotingPower, "Alice should have more voting power than Bob");
  }
}
