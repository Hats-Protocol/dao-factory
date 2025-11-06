// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { BaseFactoryTest } from "./BaseFactoryTest.sol";

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

/**
 * @title FactoryTestBase
 * @notice Base contract for VETokenVotingDaoFactory tests
 * @dev Runs the DeployDaoFromConfigScript and provides VE-specific test helpers
 */
abstract contract FactoryTestBase is BaseFactoryTest {
  // ============================================
  // DEPLOYMENT ARTIFACTS
  // ============================================

  /// @notice The deployment script instance
  DeployDaoFromConfigScript internal deployScript;

  /// @notice The factory contract
  VETokenVotingDaoFactory internal factory;

  /// @notice Full deployment struct
  Deployment internal deployment;

  /// @notice Quick access references to VE system components
  VotingEscrow internal escrow;
  Curve internal curve;
  ExitQueue internal exitQueue;
  Lock internal nftLock;
  EscrowIVotesAdapter internal ivotesAdapter;
  AddressGaugeVoter internal gaugeVoter;
  TokenVotingHats internal tokenVoting;
  Admin internal adminPlugin;

  /// @notice Config loaded directly by test (to verify script loads it correctly)
  DeployDaoFromConfigScript.Config internal testConfig;

  // ============================================
  // SETUP
  // ============================================

  function setUp() public virtual {
    // Reset CONFIG_PATH to default to prevent pollution from previous tests
    vm.setEnv("CONFIG_PATH", "config/deployment-config.json");

    // Set fork block number for VE tests (matches BaseFactoryTest default)
    forkBlockNumber = 9_561_700;

    // Load config directly in test (before script runs)
    _loadTestConfig();

    // Parse hat IDs from config
    _parseHatIdsFromConfig();

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
  function _parseHatIdsFromConfig() internal {
    _parseHatIds(
      testConfig.tokenVotingHats.proposerHatId,
      testConfig.tokenVotingHats.voterHatId,
      testConfig.tokenVotingHats.executorHatId
    );
  }

  // ============================================
  // HELPERS: Deployment (Using Script)
  // ============================================

  /// @notice Deploy factory and DAO using the deployment script
  /// @dev This runs the actual DeployDaoFromConfigScript.execute() function
  /// @dev NOTE: This creates a NEW script instance to ensure it's on the current fork
  /// @return Deployed factory instance
  /// @return Deployed script instance
  function deployFactoryAndDao() internal returns (VETokenVotingDaoFactory, DeployDaoFromConfigScript) {
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

    return (factory, script);
  }

  /// @notice Convenience alias for deployFactoryAndDao()
  function deployDao() internal returns (VETokenVotingDaoFactory, DeployDaoFromConfigScript) {
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
  function createProposal(address proposer, bytes memory metadata, Action[] memory actions, uint256 allowFailureMap)
    internal
    returns (uint256 proposalId)
  {
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
  // HELPERS: Config Access (Convenience)
  // ============================================

  /// @notice Get the test config (loaded directly by test base)
  function getTestConfig() internal view returns (DeployDaoFromConfigScript.Config memory) {
    return testConfig;
  }
}
