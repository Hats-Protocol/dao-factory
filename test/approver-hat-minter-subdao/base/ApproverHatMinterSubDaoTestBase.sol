// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { BaseFactoryTest } from "../../base/BaseFactoryTest.sol";

// Import the deployment script to run it
import { DeploySubDaoScript } from "../../../script/DeploySubDao.s.sol";

// Factory and deployment types
import {
  SubDaoFactory,
  Deployment,
  DeploymentParameters,
  DaoConfig,
  AdminPluginConfig,
  Stage1Config,
  Stage2Config,
  TokenVotingHatsPluginConfig,
  SppPluginConfig
} from "../../../src/SubDaoFactory.sol";

// Main DAO factory for querying deployment data
import { VETokenVotingDaoFactory } from "../../../src/VETokenVotingDaoFactory.sol";
import { DeployDaoFromConfigScript } from "../../../script/DeployDao.s.sol";

// Deployed contract types for quick access
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { TokenVotingHats } from "@token-voting-hats/TokenVotingHats.sol";
import { IMajorityVoting } from "@token-voting-hats/base/IMajorityVoting.sol";
import { MajorityVotingBase } from "@token-voting-hats/base/MajorityVotingBase.sol";
import { Admin } from "@admin-plugin/Admin.sol";
import { StagedProposalProcessor } from "staged-proposal-processor-plugin/StagedProposalProcessor.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

/**
 * @title ApproverHatMinterSubDaoTestBase
 * @notice Base contract for ApproverHatMinterSubDaoFactory tests
 * @dev Runs the DeploySubDaoScript and provides subDAO-specific test helpers
 */
abstract contract ApproverHatMinterSubDaoTestBase is BaseFactoryTest {
  // ============================================
  // DEPLOYMENT ARTIFACTS
  // ============================================

  /// @notice The deployment script instance
  DeploySubDaoScript internal deployScript;

  /// @notice The factory contract
  SubDaoFactory internal factory;

  /// @notice Full deployment struct
  Deployment internal deployment;

  /// @notice Quick access references to subDAO components
  TokenVotingHats internal tokenVoting;
  Admin internal adminPlugin;
  StagedProposalProcessor internal sppPlugin;

  /// @notice Config loaded directly by test (to verify script loads it correctly)
  DeploySubDaoScript.Config internal testConfig;

  // ============================================
  // SETUP
  // ============================================

  function setUp() public virtual {
    // Use latest block for ApproverHatMinter tests (overrides BaseFactoryTest default)
    forkBlockNumber = 0;

    // Load config directly in test (before script runs)
    _loadTestConfig();

    // NOTE: _parseHatIdsFromConfig() is NOT called here because it requires a fork to be set up
    // Tests must call setupFork() and then _parseHatIdsFromConfig() explicitly

    // Create deployment script instance
    deployScript = new DeploySubDaoScript();
  }

  /// @notice Load config directly for test verification
  function _loadTestConfig() internal {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/config/subdaos/approver-hat-minter.json");
    string memory json = vm.readFile(path);

    // Parse root level fields
    testConfig.version = vm.parseJsonString(json, ".version");
    testConfig.network = vm.parseJsonString(json, ".network");

    // Parse DAO config
    testConfig.dao.metadataUri = vm.parseJsonString(json, ".dao.metadataUri");
    testConfig.dao.subdomain = vm.parseJsonString(json, ".dao.subdomain");

    // Parse main DAO addresses
    testConfig.mainDaoAddress = vm.parseJsonAddress(json, ".mainDaoAddress");
    testConfig.mainDaoFactoryAddress = vm.parseJsonAddress(json, ".mainDaoFactoryAddress");

    // Note: mainDaoDeploymentData is NO LONGER loaded from config!
    // It will be queried from the main DAO factory via getter functions by the deployment script

    // Parse admin plugin config
    testConfig.adminPlugin.adminAddress = vm.parseJsonAddress(json, ".adminPlugin.adminAddress");

    // Parse Stage 1 config
    testConfig.stage1.proposerAddress = vm.parseJsonAddress(json, ".stage1.proposerAddress");
    testConfig.stage1.minAdvance = uint48(vm.parseJsonUint(json, ".stage1.minAdvance"));
    testConfig.stage1.maxAdvance = uint48(vm.parseJsonUint(json, ".stage1.maxAdvance"));
    testConfig.stage1.voteDuration = uint48(vm.parseJsonUint(json, ".stage1.voteDuration"));

    // Parse Stage 2 config
    testConfig.stage2.tokenVotingHats.votingMode =
      _parseVotingMode(vm.parseJsonString(json, ".stage2.tokenVotingHats.votingMode"));
    testConfig.stage2.tokenVotingHats.supportThreshold =
      uint32(vm.parseJsonUint(json, ".stage2.tokenVotingHats.supportThreshold"));
    testConfig.stage2.tokenVotingHats.minParticipation =
      uint32(vm.parseJsonUint(json, ".stage2.tokenVotingHats.minParticipation"));
    testConfig.stage2.tokenVotingHats.minDuration =
      uint64(vm.parseJsonUint(json, ".stage2.tokenVotingHats.minDuration"));
    testConfig.stage2.tokenVotingHats.minProposerVotingPower =
      vm.parseJsonUint(json, ".stage2.tokenVotingHats.minProposerVotingPower");
    testConfig.stage2.minAdvance = uint48(vm.parseJsonUint(json, ".stage2.minAdvance"));
    testConfig.stage2.maxAdvance = uint48(vm.parseJsonUint(json, ".stage2.maxAdvance"));
    testConfig.stage2.voteDuration = uint48(vm.parseJsonUint(json, ".stage2.voteDuration"));

    // Parse SPP plugin config
    testConfig.sppPlugin.release = uint8(vm.parseJsonUint(json, ".sppPlugin.release"));
    testConfig.sppPlugin.build = uint16(vm.parseJsonUint(json, ".sppPlugin.build"));
    testConfig.sppPlugin.useExisting = vm.parseJsonBool(json, ".sppPlugin.useExisting");
    testConfig.sppPlugin.metadata = vm.parseJsonString(json, ".sppPlugin.metadata");
  }

  /// @notice Converts string voting mode to enum
  function _parseVotingMode(string memory mode) internal pure returns (MajorityVotingBase.VotingMode) {
    bytes32 modeHash = keccak256(bytes(mode));
    if (modeHash == keccak256(bytes("Standard"))) return MajorityVotingBase.VotingMode.Standard;
    if (modeHash == keccak256(bytes("EarlyExecution"))) return MajorityVotingBase.VotingMode.EarlyExecution;
    if (modeHash == keccak256(bytes("VoteReplacement"))) return MajorityVotingBase.VotingMode.VoteReplacement;
    revert(string.concat("Invalid voting mode: ", mode));
  }

  // ============================================
  // HELPERS: Hat Management
  // ============================================

  /// @notice Parse Hat IDs from main DAO factory (NOT from config!)
  function _parseHatIdsFromConfig() internal {
    // Query main DAO factory for hat IDs
    VETokenVotingDaoFactory mainFactory = VETokenVotingDaoFactory(testConfig.mainDaoFactoryAddress);
    uint256 proposerHat = mainFactory.getProposerHatId();
    uint256 voterHat = mainFactory.getVoterHatId();
    uint256 executorHat = mainFactory.getExecutorHatId();

    _parseHatIds(proposerHat, voterHat, executorHat);
  }

  /// @notice Deploy fresh main DAO for tests
  /// @dev This ensures tests always use a main DAO factory with getter functions
  /// @dev Call this after setupFork() and before deployFactoryAndSubdao()
  /// @return mainFactory The deployed main DAO factory
  function deployMainDao() internal returns (VETokenVotingDaoFactory mainFactory) {
    // Deploy fresh main DAO
    DeployDaoFromConfigScript script = new DeployDaoFromConfigScript();
    mainFactory = script.execute();

    // Parse hat IDs from the fresh factory
    VETokenVotingDaoFactory mainFactoryInstance = VETokenVotingDaoFactory(address(mainFactory));
    uint256 proposerHat = mainFactoryInstance.getProposerHatId();
    uint256 voterHat = mainFactoryInstance.getVoterHatId();
    uint256 executorHat = mainFactoryInstance.getExecutorHatId();
    _parseHatIds(proposerHat, voterHat, executorHat);
  }

  // ============================================
  // HELPERS: Deployment (Using Script)
  // ============================================

  /// @notice Deploy factory and subDAO using the deployment script
  /// @dev This runs the actual DeploySubDaoScript.execute() function
  /// @dev NOTE: This creates a NEW script instance to ensure it's on the current fork
  /// @param mainDaoFactoryOverride Optional main DAO factory address (if address(0), uses config)
  /// @param mainDaoAddressOverride Optional main DAO address (if address(0), uses config)
  /// @return Deployed factory instance
  /// @return Deployed script instance
  function deployFactoryAndSubdao(address mainDaoFactoryOverride, address mainDaoAddressOverride)
    internal
    returns (SubDaoFactory, DeploySubDaoScript)
  {
    // Create a NEW script instance on the current fork
    // (the one created in setUp() might be on a different fork)
    DeploySubDaoScript script = new DeploySubDaoScript();

    // Execute the script with optional overrides (address(0) = use config)
    factory = script.execute(mainDaoFactoryOverride, mainDaoAddressOverride);

    // Get deployment and store in state
    deployment = factory.getDeployment();

    // Store quick access references
    dao = deployment.dao;
    tokenVoting = deployment.tokenVotingPlugin;
    adminPlugin = deployment.adminPlugin;
    sppPlugin = StagedProposalProcessor(deployment.sppPlugin);

    // Set up Hats Protocol infrastructure
    _setupHats();

    return (factory, script);
  }

  // ============================================
  // HELPERS: SPP Proposal Operations
  // ============================================

  /// @notice Create a proposal via SPP plugin
  /// @param proposer The address creating the proposal (must have CREATE_PROPOSAL permission)
  /// @param metadata Proposal metadata
  /// @param actions Array of actions to execute
  /// @return proposalId The ID of the created proposal
  function createSppProposal(address proposer, bytes memory metadata, Action[] memory actions)
    internal
    returns (uint256 proposalId)
  {
    // Create empty proposal params for each stage's bodies
    bytes[][] memory proposalParams = new bytes[][](2); // 2 stages
    proposalParams[0] = new bytes[](1); // Stage 1 has 1 body
    proposalParams[1] = new bytes[](1); // Stage 2 has 1 body

    vm.prank(proposer);
    proposalId = sppPlugin.createProposal(
      metadata,
      actions,
      0, // allowFailureMap (0 = atomic execution)
      0, // startDate (0 = now)
      proposalParams
    );
  }

  /// @notice Advance a proposal to the next stage (manual advance)
  /// @param advancer The address advancing the proposal
  /// @param proposalId The proposal ID
  function advanceProposal(address advancer, uint256 proposalId) internal {
    vm.prank(advancer);
    sppPlugin.advanceProposal(proposalId);
  }

  /// @notice Report a result for a proposal (approve or veto)
  /// @param reporter The address reporting (must be a body in the stage)
  /// @param proposalId The proposal ID
  /// @param stageId The stage ID
  /// @param resultType The result type (Approval or Veto)
  /// @param tryAdvance Whether to try to advance after reporting
  function reportProposalResult(
    address reporter,
    uint256 proposalId,
    uint16 stageId,
    StagedProposalProcessor.ResultType resultType,
    bool tryAdvance
  ) internal {
    vm.prank(reporter);
    sppPlugin.reportProposalResult(proposalId, stageId, resultType, tryAdvance);
  }

  // ============================================
  // HELPERS: TokenVoting Operations
  // ============================================

  /// @notice Vote on a proposal in TokenVotingHats plugin (for Stage 2)
  /// @param voter The address voting (must have voter hat)
  /// @param proposalId The proposal ID
  /// @param voteOption 2 = Yes, 3 = No, 1 = Abstain
  function voteOnTokenVoting(address voter, uint256 proposalId, IMajorityVoting.VoteOption voteOption) internal {
    vm.prank(voter);
    tokenVoting.vote(proposalId, voteOption, false);
  }

  // ============================================
  // HELPERS: Config Access (Convenience)
  // ============================================

  /// @notice Get the test config (loaded directly by test base)
  function getTestConfig() internal view returns (DeploySubDaoScript.Config memory) {
    return testConfig;
  }
}
