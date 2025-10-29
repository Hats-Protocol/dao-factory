// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { FactoryTestBase } from "../base/FactoryTestBase.sol";
import { IMajorityVoting } from "@token-voting-hats/base/IMajorityVoting.sol";
import { Action } from "@aragon/osx/core/dao/DAO.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ITicketV2 } from "@queue/IDynamicExitQueue.sol";

/**
 * @title VeSystemCriticalPathTest
 * @notice Tests critical paths for VE system integration
 * @dev Validates lock creation, exit queue, voting power, and end-to-end flows
 */
contract VeSystemCriticalPathTest is FactoryTestBase {
  // Test users (EOAs)
  address alice = vm.addr(1);
  address bob = vm.addr(2);
  address charlie = vm.addr(3);

  // Standard test amounts
  uint256 constant STANDARD_LOCK = 1000 ether;
  uint256 constant SMALL_LOCK = 500 ether;
  uint256 constant BELOW_MIN = 0.5 ether; // Below minDeposit (1e18)

  function setUp() public override {
    super.setUp();
    setupFork();
    deployFactoryAndDao();

    // Ensure proper EOAs
    vm.etch(alice, "");
    vm.etch(bob, "");
    vm.etch(charlie, "");

    vm.label(alice, "alice");
    vm.label(bob, "bob");
    vm.label(charlie, "charlie");
  }

  // ============================================
  // Helper Functions
  // ============================================

  function _createLockAndDelegate(address user, uint256 amount) internal returns (uint256 lockId) {
    lockId = createLock(user, amount);
    vm.prank(user);
    ivotesAdapter.delegate(user);
  }

  function _waitForCheckpoint() internal {
    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 12);
  }

  function _setupDaoMemberForVoting(address user, uint256 lockAmount) internal {
    if (lockAmount > 0) {
      _createLockAndDelegate(user, lockAmount);
    }
    if (!hats.isWearerOfHat(user, proposerHatId)) {
      mintHatToAddress(proposerHatId, user);
    }
  }

  // ============================================
  // 1.1 Lock Creation Tests
  // ============================================

  function test_CreateLockSuccessfully() public {
    // Get initial escrow balance
    uint256 initialEscrowBalance = IERC20(testConfig.veSystem.underlyingToken).balanceOf(address(escrow));

    // Create lock (createLock helper funds user and creates lock)
    uint256 lockId = createLock(alice, STANDARD_LOCK);

    // Verify lock was created
    assertTrue(lockId > 0, "Lock ID should be greater than 0");

    // Verify NFT ownership
    assertEq(nftLock.ownerOf(lockId), alice, "Alice should own the lock NFT");

    // Verify tokens transferred to escrow
    assertEq(
      IERC20(testConfig.veSystem.underlyingToken).balanceOf(address(escrow)),
      initialEscrowBalance + STANDARD_LOCK,
      "Escrow balance should increase by lock amount"
    );

    // Verify user balance is now 0 (all tokens locked)
    assertEq(
      IERC20(testConfig.veSystem.underlyingToken).balanceOf(alice),
      0,
      "User balance should be 0 after locking all tokens"
    );

    // Verify lock amount is recorded
    assertEq(escrow.locked(lockId).amount, STANDARD_LOCK, "Lock amount should match");
  }

  function test_CannotCreateLockBelowMinimum() public {
    // Fund Alice with tokens below minimum
    fundWithUnderlyingToken(alice, BELOW_MIN);

    vm.prank(alice);
    IERC20(testConfig.veSystem.underlyingToken).approve(address(escrow), BELOW_MIN);

    // Attempt to create lock below minimum should fail
    vm.expectRevert();
    vm.prank(alice);
    escrow.createLock(BELOW_MIN);

    // Verify no NFT was minted (next token ID should still be 1)
    vm.expectRevert();
    nftLock.ownerOf(1);
  }

  function test_LockCreatesVotingPowerAfterDelegation() public {
    // Create lock
    uint256 lockId = createLock(alice, STANDARD_LOCK);

    // Voting power should be 0 before delegation
    assertEq(ivotesAdapter.getVotes(alice), 0, "Voting power should be 0 before delegation");

    // Delegate to self
    vm.prank(alice);
    ivotesAdapter.delegate(alice);

    // Wait for checkpoint
    _waitForCheckpoint();

    // Voting power should equal lock amount (flat curve: constant=1e18)
    assertEq(ivotesAdapter.getVotes(alice), STANDARD_LOCK, "Voting power should equal lock amount after delegation");

    // Can use voting power in governance
    _setupDaoMemberForVoting(bob, SMALL_LOCK);
    _waitForCheckpoint();

    // Create proposal
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://test") });

    // Alice needs daoMember hat to propose
    mintHatToAddress(proposerHatId, alice);

    vm.prank(alice);
    uint256 proposalId =
      tokenVoting.createProposal("Test Proposal", actions, 0, 0, 0, IMajorityVoting.VoteOption.None, false);

    // Verify proposal was created (voting power is working)
    assertTrue(proposalId > 0, "Proposal should be created with voting power");
  }

  // ============================================
  // 1.2 Exit Queue Tests
  // ============================================

  function test_EnterExitQueueSuccessfully() public {
    // Create lock
    uint256 lockId = createLock(alice, STANDARD_LOCK);

    // Wait for minLockDuration
    vm.warp(block.timestamp + testConfig.veSystem.minLockDuration + 1);

    // Approve escrow to transfer NFT
    vm.prank(alice);
    nftLock.approve(address(escrow), lockId);

    // Enter exit queue
    vm.prank(alice);
    escrow.beginWithdrawal(lockId);

    // Verify queue entry exists
    ITicketV2.TicketV2 memory ticket = exitQueue.queue(lockId);
    assertGt(ticket.queuedAt, 0, "Queue entry should exist");
    assertEq(ticket.queuedAt, block.timestamp, "Queue timestamp should match current time");
  }

  function test_CannotEnterQueueBeforeMinLock() public {
    // Create lock
    uint256 lockId = createLock(alice, STANDARD_LOCK);

    // Try to enter queue immediately (before minLockDuration)
    vm.expectRevert();
    vm.prank(alice);
    escrow.beginWithdrawal(lockId);
  }

  function test_ExitAfterCooldownCompletes() public {
    // Create lock
    uint256 lockId = createLock(alice, STANDARD_LOCK);

    // Wait for minLockDuration
    vm.warp(block.timestamp + testConfig.veSystem.minLockDuration + 1);

    // Approve escrow to transfer NFT
    vm.prank(alice);
    nftLock.approve(address(escrow), lockId);

    // Enter exit queue
    vm.prank(alice);
    escrow.beginWithdrawal(lockId);

    // Wait for cooldown period (0 from config, so can exit immediately)
    vm.warp(block.timestamp + testConfig.veSystem.cooldownPeriod + 1);

    // Get Alice's balance before exit
    uint256 balanceBeforeExit = IERC20(testConfig.veSystem.underlyingToken).balanceOf(alice);

    // Exit queue
    vm.prank(alice);
    escrow.withdraw(lockId);

    // Verify tokens returned to Alice
    assertEq(
      IERC20(testConfig.veSystem.underlyingToken).balanceOf(alice),
      balanceBeforeExit + STANDARD_LOCK,
      "Tokens should be returned to user"
    );

    // Verify NFT was burned
    vm.expectRevert();
    nftLock.ownerOf(lockId);
  }

  // ============================================
  // 1.3 Voting Power Tests
  // ============================================

  function test_VotingPowerEqualsLockAmount() public {
    // Create lock and delegate
    uint256 lockId = _createLockAndDelegate(alice, STANDARD_LOCK);

    // Wait for checkpoint
    _waitForCheckpoint();

    // Voting power should equal lock amount for flat curve
    uint256 votingPower = ivotesAdapter.getVotes(alice);
    assertEq(votingPower, STANDARD_LOCK, "Voting power should equal lock amount with flat curve");
  }

  function test_SelfDelegationRequired() public {
    // Create lock WITHOUT delegation
    uint256 lockId = createLock(alice, STANDARD_LOCK);

    // Voting power should be 0 before delegation
    assertEq(ivotesAdapter.getVotes(alice), 0, "Voting power should be 0 before delegation");

    // Delegate to self
    vm.prank(alice);
    ivotesAdapter.delegate(alice);

    // Wait for checkpoint
    _waitForCheckpoint();

    // Now voting power should be active
    assertEq(ivotesAdapter.getVotes(alice), STANDARD_LOCK, "Voting power should be active after delegation");
  }

  function test_VotingPowerInGovernance() public {
    // Setup two users with different lock amounts
    _setupDaoMemberForVoting(alice, STANDARD_LOCK); // 1000 ether
    _setupDaoMemberForVoting(bob, SMALL_LOCK); // 500 ether

    // Wait for checkpoints
    _waitForCheckpoint();

    // Create proposal
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://test") });

    vm.prank(alice);
    uint256 proposalId =
      tokenVoting.createProposal("Test Proposal", actions, 0, 0, 0, IMajorityVoting.VoteOption.None, false);

    // Both vote
    vm.prank(alice);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    vm.prank(bob);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    // Verify both votes were cast
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

    // Verify voting power is correct
    assertEq(ivotesAdapter.getVotes(alice), STANDARD_LOCK, "Alice voting power should equal her lock");
    assertEq(ivotesAdapter.getVotes(bob), SMALL_LOCK, "Bob voting power should equal his lock");
    assertGt(ivotesAdapter.getVotes(alice), ivotesAdapter.getVotes(bob), "Alice should have more voting power");
  }

  // ============================================
  // 1.4 End-to-End Integration Tests
  // ============================================

  function test_CompleteUserJourney() public {
    // Step 1: User creates lock
    uint256 lockId = createLock(alice, STANDARD_LOCK);
    assertEq(nftLock.ownerOf(lockId), alice, "Alice should own lock NFT");

    // Step 2: User delegates to self
    vm.prank(alice);
    ivotesAdapter.delegate(alice);

    // Step 3: User gets daoMember hat
    mintHatToAddress(proposerHatId, alice);

    // Step 4: Wait for checkpoints
    _waitForCheckpoint();

    // Step 5: User participates in governance
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://test") });

    vm.prank(alice);
    uint256 proposalId =
      tokenVoting.createProposal("Test Proposal", actions, 0, 0, 0, IMajorityVoting.VoteOption.None, false);

    vm.prank(alice);
    tokenVoting.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

    assertEq(
      uint256(tokenVoting.getVoteOption(proposalId, alice)),
      uint256(IMajorityVoting.VoteOption.Yes),
      "Alice should have voted"
    );

    // Step 6: User enters exit queue after minLock
    vm.warp(block.timestamp + testConfig.veSystem.minLockDuration + 1);

    // Approve escrow to transfer NFT
    vm.prank(alice);
    nftLock.approve(address(escrow), lockId);

    vm.prank(alice);
    escrow.beginWithdrawal(lockId);

    ITicketV2.TicketV2 memory ticket = exitQueue.queue(lockId);
    assertGt(ticket.queuedAt, 0, "Should be in exit queue");

    // Step 7: User exits after cooldown
    vm.warp(block.timestamp + testConfig.veSystem.cooldownPeriod + 1);

    uint256 balanceBeforeExit = IERC20(testConfig.veSystem.underlyingToken).balanceOf(alice);

    vm.prank(alice);
    escrow.withdraw(lockId);

    // Step 8: Verify tokens returned and NFT burned
    assertEq(
      IERC20(testConfig.veSystem.underlyingToken).balanceOf(alice),
      balanceBeforeExit + STANDARD_LOCK,
      "Tokens should be returned"
    );

    vm.expectRevert();
    nftLock.ownerOf(lockId);
  }

  function test_MultiUserConcurrentFlow() public {
    // Alice locks 1000 ether
    uint256 aliceLockId = _createLockAndDelegate(alice, STANDARD_LOCK);

    // Bob locks 500 ether
    uint256 bobLockId = _createLockAndDelegate(bob, SMALL_LOCK);

    // Both get daoMember hats
    mintHatToAddress(proposerHatId, alice);
    mintHatToAddress(proposerHatId, bob);

    // Wait for checkpoints
    _waitForCheckpoint();

    // Verify correct voting power for each
    assertEq(ivotesAdapter.getVotes(alice), STANDARD_LOCK, "Alice should have 1000 ether voting power");
    assertEq(ivotesAdapter.getVotes(bob), SMALL_LOCK, "Bob should have 500 ether voting power");

    // Both participate in governance
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

    // Verify both voted
    assertEq(
      uint256(tokenVoting.getVoteOption(proposalId, alice)),
      uint256(IMajorityVoting.VoteOption.Yes),
      "Alice voted"
    );
    assertEq(uint256(tokenVoting.getVoteOption(proposalId, bob)), uint256(IMajorityVoting.VoteOption.Yes), "Bob voted");

    // Both can exit independently
    vm.warp(block.timestamp + testConfig.veSystem.minLockDuration + 1);

    // Alice exits
    vm.prank(alice);
    nftLock.approve(address(escrow), aliceLockId);

    vm.prank(alice);
    escrow.beginWithdrawal(aliceLockId);

    vm.warp(block.timestamp + testConfig.veSystem.cooldownPeriod + 1);

    uint256 aliceBalanceBefore = IERC20(testConfig.veSystem.underlyingToken).balanceOf(alice);
    vm.prank(alice);
    escrow.withdraw(aliceLockId);

    assertEq(
      IERC20(testConfig.veSystem.underlyingToken).balanceOf(alice),
      aliceBalanceBefore + STANDARD_LOCK,
      "Alice should receive her tokens"
    );

    // Bob exits (independently)
    vm.prank(bob);
    nftLock.approve(address(escrow), bobLockId);

    vm.prank(bob);
    escrow.beginWithdrawal(bobLockId);

    vm.warp(block.timestamp + testConfig.veSystem.cooldownPeriod + 1);

    uint256 bobBalanceBefore = IERC20(testConfig.veSystem.underlyingToken).balanceOf(bob);
    vm.prank(bob);
    escrow.withdraw(bobLockId);

    assertEq(
      IERC20(testConfig.veSystem.underlyingToken).balanceOf(bob),
      bobBalanceBefore + SMALL_LOCK,
      "Bob should receive his tokens"
    );

    // Verify both NFTs burned
    vm.expectRevert();
    nftLock.ownerOf(aliceLockId);

    vm.expectRevert();
    nftLock.ownerOf(bobLockId);
  }
}
