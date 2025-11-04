// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { IHats } from "@hats-protocol/Interfaces/IHats.sol";

/**
 * @title BaseFactoryTest
 * @notice Base contract with common functionality for all factory tests
 * @dev Provides fork management, Hats Protocol setup, and permission helpers
 */
abstract contract BaseFactoryTest is Test {
  // ============================================
  // FORK CONFIGURATION (Override in tests)
  // ============================================

  /// @notice Network to fork for tests (default: sepolia)
  /// @dev Override in test setUp() before calling super.setUp()
  string internal forkNetwork = "sepolia";

  /// @notice Block number to fork at (0 = latest)
  /// @dev Override for deterministic forks, leave 0 for latest
  uint256 internal forkBlockNumber = 9_556_500;

  // ============================================
  // NETWORK-SPECIFIC ADDRESSES
  // ============================================

  /// @notice Hats Protocol contract address (Sepolia)
  address internal constant HATS_ADDRESS = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;

  /// @notice Top hat wearer on Sepolia (can transfer top hat to DAO)
  address internal constant TOP_HAT_WEARER = 0x624123ec4A9f48Be7AA8a307a74381E4ea7530D4;

  // ============================================
  // COMMON STATE
  // ============================================

  /// @notice The DAO instance
  DAO internal dao;

  /// @notice Hats Protocol instance
  IHats internal hats;

  /// @notice Top hat ID (determined from hat IDs in config)
  uint256 internal topHatId;

  /// @notice Parsed hat IDs from config (for convenience)
  uint256 internal proposerHatId;
  uint256 internal voterHatId;
  uint256 internal executorHatId;

  // ============================================
  // HELPERS: Fork Management
  // ============================================

  /// @notice Set up fork for configured network
  /// @return forkId The fork identifier
  function setupFork() internal returns (uint256 forkId) {
    if (forkBlockNumber == 0) {
      // Fork at latest block
      forkId = vm.createFork(vm.rpcUrl(forkNetwork));
    } else {
      // Fork at specific block
      forkId = vm.createFork(vm.rpcUrl(forkNetwork), forkBlockNumber);
    }
    vm.selectFork(forkId);
  }

  // ============================================
  // HELPERS: Hat Management
  // ============================================

  /// @notice Parse Hat IDs and extract top hat
  /// @param _proposerHatId The proposer hat ID from config
  /// @param _voterHatId The voter hat ID from config
  /// @param _executorHatId The executor hat ID from config
  function _parseHatIds(uint256 _proposerHatId, uint256 _voterHatId, uint256 _executorHatId) internal {
    proposerHatId = _proposerHatId;
    voterHatId = _voterHatId;
    executorHatId = _executorHatId;

    // Extract top hat ID from any hat ID (top 32 bits)
    topHatId = uint256(uint32(proposerHatId >> 224)) << 224;
  }

  /// @notice Set up Hats Protocol after deployment
  /// @dev Transfers top hat to DAO for test control
  function _setupHats() internal {
    // Get Hats Protocol instance
    hats = IHats(HATS_ADDRESS);

    // Transfer top hat from current wearer to DAO
    // This gives the DAO (and tests pranking as DAO) the ability to mint hats
    vm.prank(TOP_HAT_WEARER);
    hats.transferHat(topHatId, TOP_HAT_WEARER, address(dao));
  }

  /// @notice Check if address wears the proposer hat
  /// @dev Requires fork with Hats Protocol deployed
  function wearerCanCreateProposal(address wearer) internal view returns (bool) {
    return hats.isWearerOfHat(wearer, proposerHatId);
  }

  /// @notice Check if address wears the voter hat
  function wearerCanVote(address wearer) internal view returns (bool) {
    return hats.isWearerOfHat(wearer, voterHatId);
  }

  /// @notice Check if address wears the executor hat
  function wearerCanExecute(address wearer) internal view returns (bool) {
    return hats.isWearerOfHat(wearer, executorHatId);
  }

  /// @notice Mint a hat to an address (requires DAO to control the hat's admin)
  /// @param hatId The hat ID to mint
  /// @param wearer The address to mint the hat to
  function mintHatToAddress(uint256 hatId, address wearer) internal {
    vm.prank(address(dao));
    hats.mintHat(hatId, wearer);
  }

  // ============================================
  // HELPERS: Common Assertions
  // ============================================

  /// @notice Assert that an address has a specific permission
  function assertHasPermission(address where, address who, bytes32 permissionId, string memory errorMsg) internal {
    assertTrue(dao.hasPermission(where, who, permissionId, bytes("")), errorMsg);
  }

  /// @notice Assert that an address does NOT have a specific permission
  function assertNoPermission(address where, address who, bytes32 permissionId, string memory errorMsg) internal {
    assertFalse(dao.hasPermission(where, who, permissionId, bytes("")), errorMsg);
  }
}
