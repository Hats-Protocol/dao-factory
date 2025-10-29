// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";

// Import the deployment script to run it
import { DeployDaoFromConfigScript } from "../../script/DeployDao.s.sol";

// Factory and deployment types
import { VETokenVotingDaoFactory, Deployment } from "../../src/VETokenVotingDaoFactory.sol";

// Deployed contract types for quick access
import { DAO, Action } from "@aragon/osx/core/dao/DAO.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { VotingEscrowV1_2_0 as VotingEscrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { LinearIncreasingCurve as Curve } from "@curve/LinearIncreasingCurve.sol";
import { DynamicExitQueue as ExitQueue } from "@queue/DynamicExitQueue.sol";
import { LockV1_2_0 as Lock } from "@lock/Lock_v1_2_0.sol";
import { EscrowIVotesAdapter } from "@delegation/EscrowIVotesAdapter.sol";
import { AddressGaugeVoter } from "@voting/AddressGaugeVoter.sol";
import { TokenVotingHats } from "@token-voting-hats/TokenVotingHats.sol";
import { IMajorityVoting } from "@token-voting-hats/base/IMajorityVoting.sol";
import { Admin } from "@admin-plugin/Admin.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Hats Protocol
import { IHats } from "hats-protocol/src/Interfaces/IHats.sol";

/**
 * @title FactoryTestBase
 * @notice Base contract for all DAO factory tests
 * @dev Runs the DeployDaoFromConfigScript and provides test helpers
 */
abstract contract FactoryTestBase is Test {
  // ============================================
  // FORK CONFIGURATION (Override in tests)
  // ============================================

  /// @notice Network to fork for tests (default: sepolia)
  /// @dev Override in test setUp() before calling super.setUp()
  string internal forkNetwork = "sepolia";

  /// @notice Block number to fork at (0 = latest)
  /// @dev Override for deterministic forks, leave 0 for latest
  uint256 internal forkBlockNumber = 9_504_000;

  // ============================================
  // NETWORK-SPECIFIC ADDRESSES
  // ============================================

  /// @notice Hats Protocol contract address (Sepolia)
  address internal constant HATS_ADDRESS = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;

  /// @notice Top hat wearer on Sepolia (can transfer top hat to DAO)
  address internal constant TOP_HAT_WEARER = 0x624123ec4A9f48Be7AA8a307a74381E4ea7530D4;

  // ============================================
  // DEPLOYMENT ARTIFACTS
  // ============================================

  /// @notice The deployment script instance
  DeployDaoFromConfigScript internal deployScript;

  /// @notice The factory contract
  VETokenVotingDaoFactory internal factory;

  /// @notice Full deployment struct
  Deployment internal deployment;

  /// @notice Hats Protocol instance
  IHats internal hats;

  /// @notice Top hat ID (determined from hat IDs in config)
  uint256 internal topHatId;

  /// @notice Quick access references to commonly used components
  DAO internal dao;
  VotingEscrow internal escrow;
  Curve internal curve;
  ExitQueue internal exitQueue;
  Lock internal nftLock;
  EscrowIVotesAdapter internal ivotesAdapter;
  AddressGaugeVoter internal gaugeVoter;
  TokenVotingHats internal tokenVoting;
  Admin internal adminPlugin;

  /// @notice Parsed hat IDs from config (for convenience)
  uint256 internal proposerHatId;
  uint256 internal voterHatId;
  uint256 internal executorHatId;

  /// @notice Config loaded directly by test (to verify script loads it correctly)
  DeployDaoFromConfigScript.Config internal testConfig;

  // ============================================
  // SETUP
  // ============================================

  function setUp() public virtual {
    // Load config directly in test (before script runs)
    _loadTestConfig();

    // Parse hat IDs from config
    _parseHatIds();

    // Create deployment script instance
    deployScript = new DeployDaoFromConfigScript();
  }

  /// @notice Load config directly for test verification
  function _loadTestConfig() internal {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/config/deployment-config.json");
    string memory json = vm.readFile(path);

    // Parse config (basic fields for verification)
    testConfig.version = vm.parseJsonString(json, ".version");
    testConfig.network = vm.parseJsonString(json, ".network");

    // Parse DAO config
    testConfig.dao.metadataUri = vm.parseJsonString(json, ".dao.metadataUri");
    testConfig.dao.subdomain = vm.parseJsonString(json, ".dao.subdomain");

    // Parse VE system config
    testConfig.veSystem.underlyingToken = vm.parseJsonAddress(json, ".veSystem.underlyingToken");
    testConfig.veSystem.minDeposit = vm.parseJsonUint(json, ".veSystem.minDeposit");
    testConfig.veSystem.veTokenName = vm.parseJsonString(json, ".veSystem.veTokenName");
    testConfig.veSystem.veTokenSymbol = vm.parseJsonString(json, ".veSystem.veTokenSymbol");
    testConfig.veSystem.minLockDuration = uint48(vm.parseJsonUint(json, ".veSystem.minLockDuration"));
    testConfig.veSystem.feePercent = uint16(vm.parseJsonUint(json, ".veSystem.feePercent"));
    testConfig.veSystem.cooldownPeriod = uint48(vm.parseJsonUint(json, ".veSystem.cooldownPeriod"));

    // Parse voting power curve
    testConfig.votingPowerCurve.constantCoefficient = vm.parseJsonInt(json, ".votingPowerCurve.constantCoefficient");
    testConfig.votingPowerCurve.linearCoefficient = vm.parseJsonInt(json, ".votingPowerCurve.linearCoefficient");
    testConfig.votingPowerCurve.quadraticCoefficient = vm.parseJsonInt(json, ".votingPowerCurve.quadraticCoefficient");
    testConfig.votingPowerCurve.maxEpochs = uint48(vm.parseJsonUint(json, ".votingPowerCurve.maxEpochs"));

    // Parse token voting hats plugin config
    testConfig.tokenVotingHats.votingMode = vm.parseJsonString(json, ".tokenVotingHats.votingMode");
    testConfig.tokenVotingHats.supportThreshold = uint32(vm.parseJsonUint(json, ".tokenVotingHats.supportThreshold"));
    testConfig.tokenVotingHats.minParticipation = uint32(vm.parseJsonUint(json, ".tokenVotingHats.minParticipation"));
    testConfig.tokenVotingHats.minDuration = uint64(vm.parseJsonUint(json, ".tokenVotingHats.minDuration"));
    testConfig.tokenVotingHats.minProposerVotingPower =
      vm.parseJsonUint(json, ".tokenVotingHats.minProposerVotingPower");
    testConfig.tokenVotingHats.proposerHatId = vm.parseJsonUint(json, ".tokenVotingHats.proposerHatId");
    testConfig.tokenVotingHats.voterHatId = vm.parseJsonUint(json, ".tokenVotingHats.voterHatId");
    testConfig.tokenVotingHats.executorHatId = vm.parseJsonUint(json, ".tokenVotingHats.executorHatId");

    // Parse admin plugin config
    testConfig.adminPlugin.adminAddress = vm.parseJsonAddress(json, ".adminPlugin.adminAddress");
  }

  // ============================================
  // HELPERS: Hat Management
  // ============================================

  /// @notice Parse Hat IDs from test config
  function _parseHatIds() internal {
    proposerHatId = testConfig.tokenVotingHats.proposerHatId;
    voterHatId = testConfig.tokenVotingHats.voterHatId;
    executorHatId = testConfig.tokenVotingHats.executorHatId;

    // Extract top hat ID from any hat ID (top 32 bits)
    topHatId = uint256(uint32(proposerHatId >> 224)) << 224;
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
  // HELPERS: Deployment (Using Script)
  // ============================================

  /// @notice Deploy factory and DAO using the deployment script
  /// @dev This runs the actual DeployDaoFromConfigScript.execute() function
  /// @dev NOTE: This creates a NEW script instance to ensure it's on the current fork
  /// @return Deployed factory instance
  function deployFactoryAndDao() internal returns (VETokenVotingDaoFactory) {
    // Create a NEW script instance on the current fork
    // (the one created in setUp() might be on a different fork)
    DeployDaoFromConfigScript script = new DeployDaoFromConfigScript();

    // Execute the script (without broadcasting)
    factory = script.execute();

    // Get deployment and store in state
    deployment = factory.getDeployment();

    // Store quick access references
    dao = deployment.dao;
    escrow = deployment.veSystem.votingEscrow;
    curve = deployment.veSystem.curve;
    exitQueue = deployment.veSystem.exitQueue;
    nftLock = deployment.veSystem.nftLock;
    ivotesAdapter = deployment.veSystem.ivotesAdapter;
    gaugeVoter = deployment.veSystem.voter;
    tokenVoting = deployment.tokenVotingPlugin;
    adminPlugin = deployment.adminPlugin;

    // Set up Hats Protocol infrastructure
    _setupHats();

    return factory;
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

  /// @notice Convenience alias for deployFactoryAndDao()
  function deployFactory() internal returns (VETokenVotingDaoFactory) {
    return deployFactoryAndDao();
  }

  // ============================================
  // HELPERS: Token Funding
  // ============================================

  /// @notice Fund an address with underlying tokens for testing
  /// @param recipient Address to receive tokens
  /// @param amount Amount of tokens to mint
  function fundWithUnderlyingToken(address recipient, uint256 amount) internal {
    // Use deal for ERC20
    deal(testConfig.veSystem.underlyingToken, recipient, amount);
  }

  // ============================================
  // HELPERS: VE System Operations
  // ============================================

  /// @notice Create a VE lock for a user
  /// @param user The address creating the lock
  /// @param amount The amount of tokens to lock
  /// @return lockId The ID of the created lock NFT
  function createLock(address user, uint256 amount) internal returns (uint256 lockId) {
    // Fund user with tokens
    fundWithUnderlyingToken(user, amount);

    // Approve escrow to spend tokens
    vm.prank(user);
    IERC20(testConfig.veSystem.underlyingToken).approve(address(escrow), amount);

    // Create lock via VotingEscrow
    vm.prank(user);
    lockId = escrow.createLock(amount);
  }

  /// @notice Create a proposal via TokenVotingHats plugin
  /// @param proposer The address creating the proposal (must have proposer hat)
  /// @param metadata Proposal metadata
  /// @param actions Array of actions to execute
  /// @param allowFailureMap Bitmap for actions that can fail
  /// @return proposalId The ID of the created proposal
  function createProposal(
    address proposer,
    bytes memory metadata,
    Action[] memory actions,
    uint256 allowFailureMap
  ) internal returns (uint256 proposalId) {
    vm.prank(proposer);
    proposalId = tokenVoting.createProposal(
      metadata,
      actions,
      allowFailureMap,
      0, // _startDate (0 = now)
      0, // _endDate (0 = use default duration)
      IMajorityVoting.VoteOption.None, // _voteOption
      false // _tryEarlyExecution
    );
  }

  /// @notice Vote on a proposal
  /// @param voter The address voting (must have voter hat)
  /// @param proposalId The proposal ID
  /// @param voteOption 2 = Yes, 3 = No, 1 = Abstain
  function vote(address voter, uint256 proposalId, IMajorityVoting.VoteOption voteOption) internal {
    vm.prank(voter);
    tokenVoting.vote(proposalId, voteOption, false);
  }

  /// @notice Execute a proposal
  /// @param executor The address executing (must have executor hat)
  /// @param proposalId The proposal ID
  function executeProposal(address executor, uint256 proposalId) internal {
    vm.prank(executor);
    tokenVoting.execute(proposalId);
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

  // ============================================
  // HELPERS: Config Access (Convenience)
  // ============================================

  /// @notice Get the test config (loaded directly by test base)
  function getTestConfig() internal view returns (DeployDaoFromConfigScript.Config memory) {
    return testConfig;
  }
}
