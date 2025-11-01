// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {
  VETokenVotingDaoFactory,
  DeploymentParameters,
  Deployment,
  DaoConfig,
  VeSystemConfig,
  TokenVotingHatsPluginConfig
} from "../src/VETokenVotingDaoFactory.sol";

import { VESystemSetup } from "../src/VESystemSetup.sol";
import { TokenVotingSetupHats } from "@token-voting-hats/TokenVotingSetupHats.sol";
import { AdminSetup } from "@admin-plugin/AdminSetup.sol";
import { GovernanceERC20 } from "@token-voting-hats/erc20/GovernanceERC20.sol";
import { GovernanceWrappedERC20 } from "@token-voting-hats/erc20/GovernanceWrappedERC20.sol";
import { MajorityVotingBase } from "@token-voting-hats/base/MajorityVotingBase.sol";

// VE System components
import { ClockV1_2_0 as Clock } from "@clock/Clock_v1_2_0.sol";
import { VotingEscrowV1_2_0 as VotingEscrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { LinearIncreasingCurve as Curve } from "@curve/LinearIncreasingCurve.sol";
import { DynamicExitQueue as ExitQueue } from "@queue/DynamicExitQueue.sol";
import { LockV1_2_0 as Lock } from "@lock/Lock_v1_2_0.sol";
import { SelfDelegationEscrowIVotesAdapter } from "@delegation/SelfDelegationEscrowIVotesAdapter.sol";
import { AddressGaugeVoter } from "@voting/AddressGaugeVoter.sol";

import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { DeploymentScriptHelpers } from "./DeploymentHelpers.sol";

/// @notice Deployment script for creating a new DAO with VE governance and TokenVotingHats
/// @dev Run with: forge script script/DeployDaoFromConfig.s.sol --rpc-url sepolia --broadcast --verify
/// @dev Configuration loaded from JSON file specified by CONFIG_PATH env var (default: config/deployment-config.json)
/// @dev Requires PRIVATE_KEY environment variable to be set
contract DeployDaoFromConfigScript is DeploymentScriptHelpers {
  // ============================================
  // CONFIGURATION STRUCTURE (mirrors JSON structure)
  // ============================================
  // Note: DaoConfig, VeSystemConfig, and TokenVotingHatsPluginConfig
  // are imported from VETokenVotingDaoFactory to avoid duplication

  struct VotingPowerCurveConfig {
    int256 constantCoefficient;
    int256 linearCoefficient;
    int256 quadraticCoefficient;
    uint48 maxEpochs;
  }

  struct AdminPluginConfig {
    address adminAddress;
  }

  // Script-specific wrapper that extends the factory's TokenVotingHatsPluginConfig
  // with script-only fields (votingMode as string, repository, base implementations)
  struct TokenVotingHatsScriptConfig {
    string votingMode; // String version, will be parsed to enum for the factory config
    uint32 supportThreshold;
    uint32 minParticipation;
    uint64 minDuration;
    uint256 minProposerVotingPower;
    uint256 proposerHatId;
    uint256 voterHatId;
    uint256 executorHatId;
    string metadata;
    // Script-only fields
    uint8 release;
    uint16 build;
    bool useExisting;
    address repositoryAddress;
    address governanceErc20;
    address governanceWrappedErc20;
  }

  struct Config {
    string version;
    string network;
    DaoConfig dao;
    VeSystemConfig veSystem;
    VotingPowerCurveConfig votingPowerCurve;
    TokenVotingHatsScriptConfig tokenVotingHats;
    AdminPluginConfig adminPlugin;
  }

  Config config;

  // ============================================
  // INTERNAL HELPERS
  // ============================================

  /// @notice Loads configuration from JSON file
  function _loadConfig() internal {
    string memory root = vm.projectRoot();
    string memory configPath = vm.envOr("CONFIG_PATH", string("config/deployment-config.json"));
    string memory path = string.concat(root, "/", configPath);
    string memory json = vm.readFile(path);

    _log("Loading config from:", path);

    // Parse root level fields
    config.version = vm.parseJsonString(json, ".version");
    config.network = vm.parseJsonString(json, ".network");

    // Parse DAO config
    config.dao.metadataUri = vm.parseJsonString(json, ".dao.metadataUri");
    config.dao.subdomain = vm.parseJsonString(json, ".dao.subdomain");

    // Parse VE system config
    config.veSystem.underlyingToken = vm.parseJsonAddress(json, ".veSystem.underlyingToken");
    config.veSystem.minDeposit = vm.parseJsonUint(json, ".veSystem.minDeposit");
    config.veSystem.veTokenName = vm.parseJsonString(json, ".veSystem.veTokenName");
    config.veSystem.veTokenSymbol = vm.parseJsonString(json, ".veSystem.veTokenSymbol");
    config.veSystem.minLockDuration = uint48(vm.parseJsonUint(json, ".veSystem.minLockDuration"));
    config.veSystem.feePercent = uint16(vm.parseJsonUint(json, ".veSystem.feePercent"));
    config.veSystem.cooldownPeriod = uint48(vm.parseJsonUint(json, ".veSystem.cooldownPeriod"));

    // Parse voting power curve config (separate - used for base implementation deployment)
    config.votingPowerCurve.constantCoefficient = vm.parseJsonInt(json, ".votingPowerCurve.constantCoefficient");
    config.votingPowerCurve.linearCoefficient = vm.parseJsonInt(json, ".votingPowerCurve.linearCoefficient");
    config.votingPowerCurve.quadraticCoefficient = vm.parseJsonInt(json, ".votingPowerCurve.quadraticCoefficient");
    config.votingPowerCurve.maxEpochs = uint48(vm.parseJsonUint(json, ".votingPowerCurve.maxEpochs"));

    // Parse token voting hats plugin config (all fields flattened)
    config.tokenVotingHats.votingMode = vm.parseJsonString(json, ".tokenVotingHats.votingMode");
    config.tokenVotingHats.supportThreshold = uint32(vm.parseJsonUint(json, ".tokenVotingHats.supportThreshold"));
    config.tokenVotingHats.minParticipation = uint32(vm.parseJsonUint(json, ".tokenVotingHats.minParticipation"));
    config.tokenVotingHats.minDuration = uint64(vm.parseJsonUint(json, ".tokenVotingHats.minDuration"));
    config.tokenVotingHats.minProposerVotingPower = vm.parseJsonUint(json, ".tokenVotingHats.minProposerVotingPower");
    config.tokenVotingHats.proposerHatId = vm.parseJsonUint(json, ".tokenVotingHats.proposerHatId");
    config.tokenVotingHats.voterHatId = vm.parseJsonUint(json, ".tokenVotingHats.voterHatId");
    config.tokenVotingHats.executorHatId = vm.parseJsonUint(json, ".tokenVotingHats.executorHatId");
    config.tokenVotingHats.metadata = vm.parseJsonString(json, ".tokenVotingHats.metadata");
    config.tokenVotingHats.release = uint8(vm.parseJsonUint(json, ".tokenVotingHats.release"));
    config.tokenVotingHats.build = uint16(vm.parseJsonUint(json, ".tokenVotingHats.build"));
    config.tokenVotingHats.useExisting = vm.parseJsonBool(json, ".tokenVotingHats.useExisting");
    config.tokenVotingHats.repositoryAddress = vm.parseJsonAddress(json, ".tokenVotingHats.repositoryAddress");
    config.tokenVotingHats.governanceErc20 = vm.parseJsonAddress(json, ".tokenVotingHats.governanceErc20");
    config.tokenVotingHats.governanceWrappedErc20 = vm.parseJsonAddress(json, ".tokenVotingHats.governanceWrappedErc20");

    // Parse admin plugin config
    config.adminPlugin.adminAddress = vm.parseJsonAddress(json, ".adminPlugin.adminAddress");

    _log("Network:", config.network);
    _log("Version:", config.version);
    _log("");
  }

  /// @notice Converts string voting mode to enum
  function _parseVotingMode(string memory mode) internal pure returns (MajorityVotingBase.VotingMode) {
    bytes32 modeHash = keccak256(bytes(mode));
    if (modeHash == keccak256(bytes("Standard"))) return MajorityVotingBase.VotingMode.Standard;
    if (modeHash == keccak256(bytes("EarlyExecution"))) return MajorityVotingBase.VotingMode.EarlyExecution;
    if (modeHash == keccak256(bytes("VoteReplacement"))) return MajorityVotingBase.VotingMode.VoteReplacement;
    revert(string.concat("Invalid voting mode: ", mode));
  }

  /// @notice Execute the full deployment (called by run() or from tests)
  /// @return factory The deployed factory contract
  function execute() public returns (VETokenVotingDaoFactory factory) {
    // Load configuration from JSON
    _loadConfig();

    // Get OSx addresses for current chain
    (address osxDaoFactory, address pluginSetupProcessor, address pluginRepoFactory) = _getOSxAddresses();

    // ===== STEP 1: Deploy Plugin Setup Contracts =====
    (VESystemSetup veSystemSetup, TokenVotingSetupHats tokenVotingSetup, AdminSetup adminSetup) = _deployPluginSetups();

    // ===== STEP 2: Deploy VETokenVotingDaoFactory =====
    factory = _deployFactory(
      veSystemSetup, tokenVotingSetup, adminSetup, osxDaoFactory, pluginSetupProcessor, pluginRepoFactory
    );

    // ===== STEP 3: Deploy the DAO =====
    _deployDao(factory);

    // ===== STEP 4: Log deployment artifacts =====
    _logDeployment(factory);

    return factory;
  }

  /// @notice Run script with broadcasting for actual deployment
  function run() external {
    verbose = true;
    vm.startBroadcast(_deployer());
    execute();
    vm.stopBroadcast();
  }

  /// @notice Deploys all plugin setup contracts and base implementations
  function _deployPluginSetups()
    internal
    returns (VESystemSetup veSystemSetup, TokenVotingSetupHats tokenVotingSetup, AdminSetup adminSetup)
  {
    _log("=== Deploying VE Base Implementations ===");

    // Deploy VE system base implementations (reused across all DAOs)
    Clock clockBase = new Clock();
    _log("Clock base:", address(clockBase));

    VotingEscrow escrowBase = new VotingEscrow();
    _log("VotingEscrow base:", address(escrowBase));

    // Deploy Curve with curve parameters from config (baked into implementation)
    Curve curveBase = new Curve(
      [
        config.votingPowerCurve.constantCoefficient,
        config.votingPowerCurve.linearCoefficient,
        config.votingPowerCurve.quadraticCoefficient
      ],
      config.votingPowerCurve.maxEpochs
    );
    _log("Curve base:", address(curveBase));

    ExitQueue queueBase = new ExitQueue();
    _log("ExitQueue base:", address(queueBase));

    Lock lockBase = new Lock();
    _log("Lock base:", address(lockBase));

    // Deploy SelfDelegationEscrowIVotesAdapter with curve parameters from config (baked into implementation)
    SelfDelegationEscrowIVotesAdapter ivotesAdapterBase = new SelfDelegationEscrowIVotesAdapter(
      [
        config.votingPowerCurve.constantCoefficient,
        config.votingPowerCurve.linearCoefficient,
        config.votingPowerCurve.quadraticCoefficient
      ],
      config.votingPowerCurve.maxEpochs
    );
    _log("SelfDelegationEscrowIVotesAdapter base:", address(ivotesAdapterBase));

    // Deploy AddressGaugeVoter base
    AddressGaugeVoter voterBase = new AddressGaugeVoter();
    _log("AddressGaugeVoter base:", address(voterBase));

    _log("");
    _log("=== Deploying Plugin Setup Contracts ===");

    // Deploy VESystemSetup with all base implementation addresses
    veSystemSetup = new VESystemSetup(
      address(clockBase),
      address(escrowBase),
      address(curveBase),
      address(queueBase),
      address(lockBase),
      address(ivotesAdapterBase),
      address(voterBase)
    );
    _log("VESystemSetup:", address(veSystemSetup));

    // Use base implementations from config for TokenVoting
    _log("Using GovernanceERC20 base:", config.tokenVotingHats.governanceErc20);
    _log("Using GovernanceWrappedERC20 base:", config.tokenVotingHats.governanceWrappedErc20);

    // Deploy TokenVotingSetupHats
    tokenVotingSetup = new TokenVotingSetupHats(
      GovernanceERC20(config.tokenVotingHats.governanceErc20),
      GovernanceWrappedERC20(config.tokenVotingHats.governanceWrappedErc20)
    );
    _log("TokenVotingSetupHats:", address(tokenVotingSetup));

    // Deploy AdminSetup
    adminSetup = new AdminSetup();
    _log("AdminSetup:", address(adminSetup));

    _log("");
  }

  /// @notice Deploys the VETokenVotingDaoFactory with all parameters
  function _deployFactory(
    VESystemSetup veSystemSetup,
    TokenVotingSetupHats tokenVotingSetup,
    AdminSetup adminSetup,
    address osxDaoFactory,
    address pluginSetupProcessor,
    address pluginRepoFactory
  ) internal returns (VETokenVotingDaoFactory) {
    _log("=== Deploying VETokenVotingDaoFactory ===");

    // Determine plugin repo addresses based on config
    address tokenVotingPluginRepo =
      config.tokenVotingHats.useExisting ? config.tokenVotingHats.repositoryAddress : address(0);

    address adminPluginRepo = _getAdminPluginRepo();

    // Build TokenVotingHatsPluginConfig with parsed voting mode
    TokenVotingHatsPluginConfig memory tokenVotingHatsConfig = TokenVotingHatsPluginConfig({
      votingMode: _parseVotingMode(config.tokenVotingHats.votingMode),
      supportThreshold: config.tokenVotingHats.supportThreshold,
      minParticipation: config.tokenVotingHats.minParticipation,
      minDuration: config.tokenVotingHats.minDuration,
      minProposerVotingPower: config.tokenVotingHats.minProposerVotingPower,
      proposerHatId: config.tokenVotingHats.proposerHatId,
      voterHatId: config.tokenVotingHats.voterHatId,
      executorHatId: config.tokenVotingHats.executorHatId
    });

    // Build VeSystemConfig with curve parameters from votingPowerCurve config
    VeSystemConfig memory veSystemConfig = VeSystemConfig({
      underlyingToken: config.veSystem.underlyingToken,
      minDeposit: config.veSystem.minDeposit,
      veTokenName: config.veSystem.veTokenName,
      veTokenSymbol: config.veSystem.veTokenSymbol,
      minLockDuration: config.veSystem.minLockDuration,
      feePercent: config.veSystem.feePercent,
      cooldownPeriod: config.veSystem.cooldownPeriod,
      curveConstant: config.votingPowerCurve.constantCoefficient,
      curveLinear: config.votingPowerCurve.linearCoefficient,
      curveQuadratic: config.votingPowerCurve.quadraticCoefficient,
      curveMaxEpochs: config.votingPowerCurve.maxEpochs
    });

    DeploymentParameters memory params = DeploymentParameters({
      // Configuration structs
      dao: config.dao,
      veSystem: veSystemConfig,
      tokenVotingHats: tokenVotingHatsConfig,
      // Plugin setup contracts
      veSystemSetup: veSystemSetup,
      tokenVotingSetup: tokenVotingSetup,
      tokenVotingPluginRepo: PluginRepo(tokenVotingPluginRepo),
      adminSetup: adminSetup,
      adminPluginRepo: PluginRepo(adminPluginRepo),
      adminAddress: config.adminPlugin.adminAddress,
      // Plugin metadata
      tokenVotingHatsMetadata: config.tokenVotingHats.metadata,
      // Plugin repo version info
      pluginRepoRelease: config.tokenVotingHats.release,
      pluginRepoBuild: config.tokenVotingHats.build,
      // OSx framework addresses
      osxDaoFactory: osxDaoFactory,
      pluginSetupProcessor: PluginSetupProcessor(pluginSetupProcessor),
      pluginRepoFactory: PluginRepoFactory(pluginRepoFactory)
    });

    VETokenVotingDaoFactory factory = new VETokenVotingDaoFactory(params);
    _log("VETokenVotingDaoFactory:", address(factory));
    _log("");

    return factory;
  }

  /// @notice Deploys the DAO via factory.deployOnce()
  function _deployDao(VETokenVotingDaoFactory factory) internal {
    _log("=== Deploying DAO ===");

    factory.deployOnce();

    _log("DAO deployed successfully!");
    _log("");
  }

  /// @notice Logs all deployment addresses
  function _logDeployment(VETokenVotingDaoFactory factory) internal view {
    _log("=== Deployment Artifacts ===");
    _log("Factory:", address(factory));
    _log("");

    // Retrieve deployment from factory
    Deployment memory deployment = factory.getDeployment();

    _log("DAO:", address(deployment.dao));
    _log("");
    _log("VE System:");
    _log("  VotingEscrow:", address(deployment.veSystem.votingEscrow));
    _log("  Clock:", address(deployment.veSystem.clock));
    _log("  Curve:", address(deployment.veSystem.curve));
    _log("  ExitQueue:", address(deployment.veSystem.exitQueue));
    _log("  NFT Lock:", address(deployment.veSystem.nftLock));
    _log("  IVotesAdapter:", address(deployment.veSystem.ivotesAdapter));
    _log("  AddressGaugeVoter:", address(deployment.veSystem.voter));
    _log("");
    _log("Plugins:");
    _log("  TokenVotingHats:", address(deployment.tokenVotingPlugin));
    _log("  TokenVotingHats Repo:", address(deployment.tokenVotingPluginRepo));
    _log("  Admin:", address(deployment.adminPlugin));
    _log("  Admin Repo:", address(deployment.adminPluginRepo));
  }
}
