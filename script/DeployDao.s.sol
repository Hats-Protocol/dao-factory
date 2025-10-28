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

/// @notice Deployment script for creating a new DAO with VE governance and TokenVotingHats
/// @dev Run with: forge script script/DeployDaoFromConfig.s.sol --rpc-url sepolia --broadcast --verify
/// @dev Configuration loaded from JSON file specified by CONFIG_PATH env var (default: config/deployment-config.json)
/// @dev Requires PRIVATE_KEY environment variable to be set
contract DeployDaoFromConfigScript is Script {
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

  /// @dev Set up the deployer via their private key from the environment
  function _deployer() internal returns (address) {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    return vm.rememberKey(privKey);
  }

  /// @notice Loads configuration from JSON file
  function _loadConfig() internal {
    string memory root = vm.projectRoot();
    string memory configPath = vm.envOr("CONFIG_PATH", string("config/deployment-config.json"));
    string memory path = string.concat(root, "/", configPath);
    string memory json = vm.readFile(path);

    console.log("Loading config from:", path);

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
    config.tokenVotingHats.votingMode =
      vm.parseJsonString(json, ".tokenVotingHats.votingMode");
    config.tokenVotingHats.supportThreshold =
      uint32(vm.parseJsonUint(json, ".tokenVotingHats.supportThreshold"));
    config.tokenVotingHats.minParticipation =
      uint32(vm.parseJsonUint(json, ".tokenVotingHats.minParticipation"));
    config.tokenVotingHats.minDuration =
      uint64(vm.parseJsonUint(json, ".tokenVotingHats.minDuration"));
    config.tokenVotingHats.minProposerVotingPower =
      vm.parseJsonUint(json, ".tokenVotingHats.minProposerVotingPower");
    config.tokenVotingHats.proposerHatId =
      vm.parseJsonUint(json, ".tokenVotingHats.proposerHatId");
    config.tokenVotingHats.voterHatId =
      vm.parseJsonUint(json, ".tokenVotingHats.voterHatId");
    config.tokenVotingHats.executorHatId =
      vm.parseJsonUint(json, ".tokenVotingHats.executorHatId");
    config.tokenVotingHats.release =
      uint8(vm.parseJsonUint(json, ".tokenVotingHats.release"));
    config.tokenVotingHats.build =
      uint16(vm.parseJsonUint(json, ".tokenVotingHats.build"));
    config.tokenVotingHats.useExisting =
      vm.parseJsonBool(json, ".tokenVotingHats.useExisting");
    config.tokenVotingHats.repositoryAddress =
      vm.parseJsonAddress(json, ".tokenVotingHats.repositoryAddress");
    config.tokenVotingHats.governanceErc20 =
      vm.parseJsonAddress(json, ".tokenVotingHats.governanceErc20");
    config.tokenVotingHats.governanceWrappedErc20 =
      vm.parseJsonAddress(json, ".tokenVotingHats.governanceWrappedErc20");

    // Parse admin plugin config
    config.adminPlugin.adminAddress =
      vm.parseJsonAddress(json, ".adminPlugin.adminAddress");

    console.log("Network:", config.network);
    console.log("Version:", config.version);
    console.log("");
  }

  /// @notice Converts string voting mode to enum
  function _parseVotingMode(string memory mode) internal pure returns (MajorityVotingBase.VotingMode) {
    bytes32 modeHash = keccak256(bytes(mode));
    if (modeHash == keccak256(bytes("Standard"))) return MajorityVotingBase.VotingMode.Standard;
    if (modeHash == keccak256(bytes("EarlyExecution"))) return MajorityVotingBase.VotingMode.EarlyExecution;
    if (modeHash == keccak256(bytes("VoteReplacement"))) return MajorityVotingBase.VotingMode.VoteReplacement;
    revert(string.concat("Invalid voting mode: ", mode));
  }

  function run() external {
    // Load configuration from JSON
    _loadConfig();

    // Get OSx addresses for current chain
    (address osxDaoFactory, address pluginSetupProcessor, address pluginRepoFactory) = _getOSxAddresses();

    vm.startBroadcast(_deployer());

    // ===== STEP 1: Deploy Plugin Setup Contracts =====
    (VESystemSetup veSystemSetup, TokenVotingSetupHats tokenVotingSetup, AdminSetup adminSetup) = _deployPluginSetups();

    // ===== STEP 2: Deploy VETokenVotingDaoFactory =====
    VETokenVotingDaoFactory factory =
      _deployFactory(veSystemSetup, tokenVotingSetup, adminSetup, osxDaoFactory, pluginSetupProcessor, pluginRepoFactory);

    // ===== STEP 3: Deploy the DAO =====
    _deployDao(factory);

    vm.stopBroadcast();

    // ===== STEP 4: Log deployment artifacts =====
    _logDeployment(factory);
  }

  /// @notice Deploys all plugin setup contracts and base implementations
  function _deployPluginSetups() internal returns (VESystemSetup veSystemSetup, TokenVotingSetupHats tokenVotingSetup, AdminSetup adminSetup) {
    console.log("=== Deploying VE Base Implementations ===");

    // Deploy VE system base implementations (reused across all DAOs)
    Clock clockBase = new Clock();
    console.log("Clock base:", address(clockBase));

    VotingEscrow escrowBase = new VotingEscrow();
    console.log("VotingEscrow base:", address(escrowBase));

    // Deploy Curve with curve parameters from config (baked into implementation)
    Curve curveBase = new Curve(
      [
        config.votingPowerCurve.constantCoefficient,
        config.votingPowerCurve.linearCoefficient,
        config.votingPowerCurve.quadraticCoefficient
      ],
      config.votingPowerCurve.maxEpochs
    );
    console.log("Curve base:", address(curveBase));

    ExitQueue queueBase = new ExitQueue();
    console.log("ExitQueue base:", address(queueBase));

    Lock lockBase = new Lock();
    console.log("Lock base:", address(lockBase));

    // Deploy SelfDelegationEscrowIVotesAdapter with curve parameters from config (baked into implementation)
    SelfDelegationEscrowIVotesAdapter ivotesAdapterBase = new SelfDelegationEscrowIVotesAdapter(
      [
        config.votingPowerCurve.constantCoefficient,
        config.votingPowerCurve.linearCoefficient,
        config.votingPowerCurve.quadraticCoefficient
      ],
      config.votingPowerCurve.maxEpochs
    );
    console.log("SelfDelegationEscrowIVotesAdapter base:", address(ivotesAdapterBase));

    // Deploy AddressGaugeVoter base
    AddressGaugeVoter voterBase = new AddressGaugeVoter();
    console.log("AddressGaugeVoter base:", address(voterBase));

    console.log("");
    console.log("=== Deploying Plugin Setup Contracts ===");

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
    console.log("VESystemSetup:", address(veSystemSetup));

    // Use base implementations from config for TokenVoting
    console.log("Using GovernanceERC20 base:", config.tokenVotingHats.governanceErc20);
    console.log("Using GovernanceWrappedERC20 base:", config.tokenVotingHats.governanceWrappedErc20);

    // Deploy TokenVotingSetupHats
    tokenVotingSetup = new TokenVotingSetupHats(
      GovernanceERC20(config.tokenVotingHats.governanceErc20),
      GovernanceWrappedERC20(config.tokenVotingHats.governanceWrappedErc20)
    );
    console.log("TokenVotingSetupHats:", address(tokenVotingSetup));

    // Deploy AdminSetup
    adminSetup = new AdminSetup();
    console.log("AdminSetup:", address(adminSetup));

    console.log("");
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
    console.log("=== Deploying VETokenVotingDaoFactory ===");

    // Determine plugin repo addresses based on config
    address tokenVotingPluginRepo = config.tokenVotingHats.useExisting
      ? config.tokenVotingHats.repositoryAddress
      : address(0);

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
      // Plugin repo version info
      pluginRepoRelease: config.tokenVotingHats.release,
      pluginRepoBuild: config.tokenVotingHats.build,
      // OSx framework addresses
      osxDaoFactory: osxDaoFactory,
      pluginSetupProcessor: PluginSetupProcessor(pluginSetupProcessor),
      pluginRepoFactory: PluginRepoFactory(pluginRepoFactory)
    });

    VETokenVotingDaoFactory factory = new VETokenVotingDaoFactory(params);
    console.log("VETokenVotingDaoFactory:", address(factory));
    console.log("");

    return factory;
  }

  /// @notice Deploys the DAO via factory.deployOnce()
  function _deployDao(VETokenVotingDaoFactory factory) internal {
    console.log("=== Deploying DAO ===");

    factory.deployOnce();

    console.log("DAO deployed successfully!");
    console.log("");
  }

  /// @notice Logs all deployment addresses
  function _logDeployment(VETokenVotingDaoFactory factory) internal view {
    console.log("=== Deployment Artifacts ===");
    console.log("Factory:", address(factory));
    console.log("");

    // Retrieve deployment from factory
    Deployment memory deployment = factory.getDeployment();

    console.log("DAO:", address(deployment.dao));
    console.log("");
    console.log("VE System:");
    console.log("  VotingEscrow:", address(deployment.veSystem.votingEscrow));
    console.log("  Clock:", address(deployment.veSystem.clock));
    console.log("  Curve:", address(deployment.veSystem.curve));
    console.log("  ExitQueue:", address(deployment.veSystem.exitQueue));
    console.log("  NFT Lock:", address(deployment.veSystem.nftLock));
    console.log("  IVotesAdapter:", address(deployment.veSystem.ivotesAdapter));
    console.log("  AddressGaugeVoter:", address(deployment.veSystem.voter));
    console.log("");
    console.log("Plugins:");
    console.log("  TokenVotingHats:", address(deployment.tokenVotingPlugin));
    console.log("  TokenVotingHats Repo:", address(deployment.tokenVotingPluginRepo));
    console.log("  Admin:", address(deployment.adminPlugin));
    console.log("  Admin Repo:", address(deployment.adminPluginRepo));
  }

  /// @notice Gets Admin Plugin repo address for the current chain
  function _getAdminPluginRepo() internal returns (address pluginRepo) {
    // Read addresses from Admin Plugin deployment artifacts
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/lib/admin-plugin/packages/artifacts/src/addresses.json");
    string memory json = vm.readFile(path);

    // Map chain ID to network name
    string memory network = _getNetworkName(block.chainid);

    // Parse plugin repo address for current network
    pluginRepo = vm.parseJsonAddress(json, string.concat(".pluginRepo.", network));

    console.log("Using Admin Plugin repo for", network);
    console.log("  AdminPlugin Repo:", pluginRepo);
  }

  /// @notice Gets OSx framework addresses for the current chain
  function _getOSxAddresses()
    internal
    returns (address daoFactory, address pluginSetupProcessor, address pluginRepoFactory)
  {
    // Read addresses from OSx deployment artifacts
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/lib/osx/packages/artifacts/src/addresses.json");
    string memory json = vm.readFile(path);

    // Map chain ID to network name
    string memory network = _getNetworkName(block.chainid);

    // Parse addresses for current network
    daoFactory = vm.parseJsonAddress(json, string.concat(".daoFactory.", network));
    pluginSetupProcessor = vm.parseJsonAddress(json, string.concat(".pluginSetupProcessor.", network));
    pluginRepoFactory = vm.parseJsonAddress(json, string.concat(".pluginRepoFactory.", network));

    console.log("Using OSx contracts for", network);
    console.log("Chain ID:", block.chainid);
    console.log("  DAOFactory:", daoFactory);
    console.log("  PluginSetupProcessor:", pluginSetupProcessor);
    console.log("  PluginRepoFactory:", pluginRepoFactory);
    console.log("");
  }

  /// @notice Maps chain ID to network name used in addresses.json
  function _getNetworkName(uint256 chainId) internal pure returns (string memory) {
    if (chainId == 1) return "mainnet";
    if (chainId == 11_155_111) return "sepolia";
    if (chainId == 137) return "polygon";
    if (chainId == 42_161) return "arbitrum";
    if (chainId == 421_614) return "arbitrumSepolia";
    if (chainId == 8453) return "base";
    if (chainId == 17_000) return "holesky";
    if (chainId == 56) return "bsc";
    if (chainId == 97) return "bscTestnet";
    if (chainId == 59_144) return "linea";
    if (chainId == 34_443) return "mode";
    if (chainId == 324) return "zksync";
    if (chainId == 300) return "zksyncSepolia";

    revert(
      string.concat(
        "Unsupported chain ID: ",
        vm.toString(chainId),
        ". Check lib/osx/packages/artifacts/src/addresses.json for supported chains"
      )
    );
  }
}
