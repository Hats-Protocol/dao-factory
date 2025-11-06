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
import { VETokenVotingDaoFactory, Deployment as MainDaoDeployment } from "../../../src/VETokenVotingDaoFactory.sol";
import { DeployDaoFromConfigScript } from "../../../script/DeployDao.s.sol";

// Deployed contract types for quick access
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { TokenVotingHats } from "@token-voting-hats/TokenVotingHats.sol";
import { IMajorityVoting } from "@token-voting-hats/base/IMajorityVoting.sol";
import { MajorityVotingBase } from "@token-voting-hats/base/MajorityVotingBase.sol";
import { Admin } from "@admin-plugin/Admin.sol";
import { StagedProposalProcessor } from "staged-proposal-processor-plugin/StagedProposalProcessor.sol";
import { Action } from "@aragon/osx/core/dao/DAO.sol";

// VE Token System for governance tests
import { VotingEscrowV1_2_0 as VotingEscrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { EscrowIVotesAdapter } from "@delegation/EscrowIVotesAdapter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SubDaoTestBase
 * @notice Base contract for SubDAO tests (both veto and approve modes)
 * @dev Provides shared helpers and config loading utilities
 */
abstract contract SubDaoTestBase is BaseFactoryTest {
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
  // GOVERNANCE TEST SUPPORT
  // ============================================

  /// @notice Test user addresses (EOAs)
  address internal alice = vm.addr(1);
  address internal bob = vm.addr(2);
  address internal charlie = vm.addr(3);

  /// @notice Main DAO components (needed for voting power)
  VotingEscrow internal escrow;
  EscrowIVotesAdapter internal ivotesAdapter;

  /// @notice Standard lock amount for tests
  uint256 internal constant STANDARD_LOCK_AMOUNT = 1000 ether;

  // ============================================
  // SETUP
  // ============================================

  function setUp() public virtual {
    // Reset CONFIG_PATH to default to prevent pollution from previous tests
    // SubDAO tests will override this in loadConfigAndDeploy()
    vm.setEnv("CONFIG_PATH", "config/deployment-config.json");

    // Reset state variables to ensure clean slate
    delete factory;
    delete deployment;
    delete dao;
    delete tokenVoting;
    delete adminPlugin;
    delete sppPlugin;
    delete escrow;
    delete ivotesAdapter;

    // Create deployment script instance
    deployScript = new DeploySubDaoScript();
  }

  // ============================================
  // HELPERS: Config Loading
  // ============================================

  /// @notice Load config from specified path
  /// @param configPath Relative path to config file (e.g., "config/subdaos/approver-hat-minter.json")
  function _loadTestConfig(string memory configPath) internal {
    string memory root = vm.projectRoot();
    string memory fullPath = string.concat(root, "/", configPath);
    string memory json = vm.readFile(fullPath);

    // Parse root level fields
    testConfig.version = vm.parseJsonString(json, ".version");
    testConfig.network = vm.parseJsonString(json, ".network");

    // Parse DAO config
    testConfig.dao.metadataUri = vm.parseJsonString(json, ".dao.metadataUri");
    testConfig.dao.subdomain = vm.parseJsonString(json, ".dao.subdomain");

    // Parse main DAO addresses
    testConfig.mainDaoAddress = vm.parseJsonAddress(json, ".mainDaoAddress");
    testConfig.mainDaoFactoryAddress = vm.parseJsonAddress(json, ".mainDaoFactoryAddress");

    // Parse admin plugin config
    testConfig.adminPlugin.adminAddress = vm.parseJsonAddress(json, ".adminPlugin.adminAddress");

    // Parse Stage 1 config
    testConfig.stage1.mode = vm.parseJsonString(json, ".stage1.mode");
    testConfig.stage1.proposerHatId = vm.parseJsonUint(json, ".stage1.proposerHatId");
    testConfig.stage1.controllerAddress = vm.parseJsonAddress(json, ".stage1.controllerAddress");
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
  // HELPERS: Deployment
  // ============================================

  /// @notice Load config and deploy SubDAO using the deployment script
  /// @param configPath Relative path to config file (e.g., "config/subdaos/approver-hat-minter.json")
  /// @param mainFactory Address of deployed main DAO factory
  function loadConfigAndDeploy(string memory configPath, address mainFactory) internal {
    // Load config for test verification
    _loadTestConfig(configPath);

    // Parse hat IDs from main DAO factory
    VETokenVotingDaoFactory mainFactoryInstance = VETokenVotingDaoFactory(mainFactory);
    uint256 proposerHat = mainFactoryInstance.getProposerHatId();
    uint256 voterHat = mainFactoryInstance.getVoterHatId();
    uint256 executorHat = mainFactoryInstance.getExecutorHatId();
    _parseHatIds(proposerHat, voterHat, executorHat);

    // Set config path for deployment script
    vm.setEnv("CONFIG_PATH", configPath);

    // Create a NEW script instance on the current fork
    DeploySubDaoScript script = new DeploySubDaoScript();

    // Execute the script
    factory = script.execute(mainFactory, address(0));

    // Get deployment and store in state
    deployment = factory.getDeployment();

    // Store quick access references
    dao = deployment.dao;
    tokenVoting = deployment.tokenVotingPlugin;
    adminPlugin = deployment.adminPlugin;
    sppPlugin = StagedProposalProcessor(deployment.sppPlugin);

    // Set up Hats Protocol infrastructure
    _setupHats();
  }

  /// @notice Deploy fresh main DAO for tests
  /// @return mainFactory The deployed main DAO factory
  function deployMainDao() internal returns (VETokenVotingDaoFactory mainFactory) {
    // Ensure CONFIG_PATH points to main DAO config (integration tests may have changed it)
    vm.setEnv("CONFIG_PATH", "config/deployment-config.json");

    DeployDaoFromConfigScript script = new DeployDaoFromConfigScript();
    mainFactory = script.execute();
  }

  /// @notice Deploy main DAO and extract escrow/ivotes for governance tests
  /// @return mainFactory The deployed main DAO factory
  function deployMainDaoWithEscrow() internal returns (VETokenVotingDaoFactory mainFactory) {
    mainFactory = deployMainDao();

    // Get main DAO deployment
    MainDaoDeployment memory mainDeployment = mainFactory.getDeployment();

    // Store escrow and ivotesAdapter for test use
    escrow = mainDeployment.veSystem.votingEscrow;
    ivotesAdapter = mainDeployment.veSystem.ivotesAdapter;
  }

  /// @notice Setup test users as EOAs with labels
  function setupTestUsers() internal {
    // Ensure test users are proper EOAs (not contracts)
    vm.etch(alice, "");
    vm.etch(bob, "");
    vm.etch(charlie, "");

    // Label for better trace readability
    vm.label(alice, "alice");
    vm.label(bob, "bob");
    vm.label(charlie, "charlie");
  }

  /// @notice Create a lock for a user to give them voting power
  /// @param user The user address
  /// @param amount The amount to lock
  /// @return lockId The created lock ID
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

  /// @notice Create a simple DAO metadata update proposal
  /// @param proposer The address creating the proposal
  /// @return proposalId The ID of the created proposal
  function createMetadataProposal(address proposer) internal returns (uint256 proposalId) {
    Action[] memory actions = new Action[](1);
    actions[0] =
      Action({ to: address(dao), value: 0, data: abi.encodeWithSignature("setMetadata(bytes)", "ipfs://updated") });

    proposalId = createSppProposal(proposer, "Update SubDAO Metadata", actions);
  }

  // ============================================
  // HELPERS: Deployment Assertions
  // ============================================

  /// @notice Run standard deployment checks (used by all deployment tests)
  function assertStandardDeployment() internal {
    assertTrue(address(factory) != address(0), "Factory should be deployed");
    assertTrue(address(dao) != address(0), "DAO should be deployed");
    assertTrue(address(tokenVoting) != address(0), "TokenVoting should be deployed");
    assertTrue(address(adminPlugin) != address(0), "Admin plugin should be deployed");
    assertTrue(address(sppPlugin) != address(0), "SPP plugin should be deployed");
  }

  /// @notice Assert deployment struct is populated
  function assertDeploymentStructPopulated() internal {
    assertTrue(address(deployment.dao) != address(0), "Deployment should have DAO");
    assertTrue(address(deployment.adminPlugin) != address(0), "Deployment should have admin plugin");
    assertTrue(address(deployment.tokenVotingPlugin) != address(0), "Deployment should have token voting");
    assertTrue(deployment.sppPlugin != address(0), "Deployment should have SPP plugin");
    assertTrue(deployment.hatsCondition != address(0), "Deployment should have HatsCondition");
  }

  /// @notice Assert factory version
  function assertFactoryVersion(string memory expected) internal {
    assertEq(factory.version(), expected, string.concat("Factory version should be ", expected));
  }

  // ============================================
  // HELPERS: Config Access
  // ============================================

  /// @notice Get the test config (loaded directly by test base)
  function getTestConfig() internal view returns (DeploySubDaoScript.Config memory) {
    return testConfig;
  }
}
