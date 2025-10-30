// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {
  ApproverHatMinterSubDaoFactory,
  DeploymentParameters,
  Deployment,
  DaoConfig,
  AdminPluginConfig,
  Stage1Config,
  Stage2Config,
  TokenVotingHatsPluginConfig,
  SppPluginConfig
} from "../src/ApproverHatMinterSubDaoFactory.sol";
import {DeploymentScriptHelpers} from "./DeploymentHelpers.sol";

import {TokenVotingSetupHats} from "@token-voting-hats/TokenVotingSetupHats.sol";
import {AdminSetup} from "@admin-plugin/AdminSetup.sol";
import {MajorityVotingBase} from "@token-voting-hats/base/MajorityVotingBase.sol";
import {GovernanceERC20} from "@token-voting-hats/erc20/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@token-voting-hats/erc20/GovernanceWrappedERC20.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

/// @notice Deployment script for creating a new SubDAO with Admin, TokenVotingHats, and SPP plugins
/// @dev Run with: forge script script/DeployApproverHatMinterSubDao.s.sol --rpc-url sepolia --broadcast --verify
/// @dev Configuration loaded from JSON file specified by CONFIG_PATH env var (default: config/approver-hat-minter-subdao-config.json)
/// @dev Requires PRIVATE_KEY environment variable to be set
contract DeployApproverHatMinterSubDaoScript is Script, DeploymentScriptHelpers {
  struct TokenVotingHatsScriptConfig {
    string votingMode;
    uint32 supportThreshold;
    uint32 minParticipation;
    uint64 minDuration;
    uint256 minProposerVotingPower;
    uint256 proposerHatId;
    uint256 voterHatId;
    uint256 executorHatId;
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
    address mainDaoAddress;
    address mainDaoFactoryAddress;
    AdminPluginConfig adminPlugin;
    Stage1Config stage1;
    Stage2Config stage2;
    SppPluginConfig sppPlugin;
    // Token Voting Hats config (from main DAO)
    address tokenVotingPluginRepo;
    uint8 tokenVotingPluginRepoRelease;
    uint16 tokenVotingPluginRepoBuild;
    address governanceErc20;
    address governanceWrappedErc20;
    address sppPluginSetup;
  }

  Config config;
  Stage2Config stage2Parsed;

  /// @notice Loads configuration from JSON file
  function _loadConfig() internal {
    string memory root = vm.projectRoot();
    string memory configPath = vm.envOr("CONFIG_PATH", string("config/approver-hat-minter-subdao-config.json"));
    string memory path = string.concat(root, "/", configPath);
    string memory json = vm.readFile(path);

    console.log("Loading config from:", path);

    // Parse root level fields
    config.version = vm.parseJsonString(json, ".version");
    config.network = vm.parseJsonString(json, ".network");

    // Parse DAO config
    config.dao.metadataUri = vm.parseJsonString(json, ".dao.metadataUri");
    config.dao.subdomain = vm.parseJsonString(json, ".dao.subdomain");

    // Parse main DAO addresses
    config.mainDaoAddress = vm.parseJsonAddress(json, ".mainDaoAddress");
    config.mainDaoFactoryAddress = vm.parseJsonAddress(json, ".mainDaoFactoryAddress");

    // Parse admin plugin config
    config.adminPlugin.adminAddress = vm.parseJsonAddress(json, ".adminPlugin.adminAddress");

    // Parse Stage 1 config
    config.stage1.proposerAddress = vm.parseJsonAddress(json, ".stage1.proposerAddress");
    config.stage1.minAdvance = uint48(vm.parseJsonUint(json, ".stage1.minAdvance"));
    config.stage1.maxAdvance = uint48(vm.parseJsonUint(json, ".stage1.maxAdvance"));
    config.stage1.voteDuration = uint48(vm.parseJsonUint(json, ".stage1.voteDuration"));

    // Parse Stage 2 config
    config.stage2.tokenVotingHats.votingMode =
      _parseVotingMode(vm.parseJsonString(json, ".stage2.tokenVotingHats.votingMode"));
    config.stage2.tokenVotingHats.supportThreshold =
      uint32(vm.parseJsonUint(json, ".stage2.tokenVotingHats.supportThreshold"));
    config.stage2.tokenVotingHats.minParticipation =
      uint32(vm.parseJsonUint(json, ".stage2.tokenVotingHats.minParticipation"));
    config.stage2.tokenVotingHats.minDuration =
      uint64(vm.parseJsonUint(json, ".stage2.tokenVotingHats.minDuration"));
    config.stage2.tokenVotingHats.minProposerVotingPower =
      vm.parseJsonUint(json, ".stage2.tokenVotingHats.minProposerVotingPower");
    config.stage2.tokenVotingHats.proposerHatId =
      vm.parseJsonUint(json, ".stage2.tokenVotingHats.proposerHatId");
    config.stage2.tokenVotingHats.voterHatId = vm.parseJsonUint(json, ".stage2.tokenVotingHats.voterHatId");
    config.stage2.tokenVotingHats.executorHatId =
      vm.parseJsonUint(json, ".stage2.tokenVotingHats.executorHatId");
    config.stage2.minAdvance = uint48(vm.parseJsonUint(json, ".stage2.minAdvance"));
    config.stage2.maxAdvance = uint48(vm.parseJsonUint(json, ".stage2.maxAdvance"));
    config.stage2.voteDuration = uint48(vm.parseJsonUint(json, ".stage2.voteDuration"));

    // Parse SPP plugin config
    config.sppPlugin.release = uint8(vm.parseJsonUint(json, ".sppPlugin.release"));
    config.sppPlugin.build = uint16(vm.parseJsonUint(json, ".sppPlugin.build"));
    config.sppPlugin.useExisting = vm.parseJsonBool(json, ".sppPlugin.useExisting");
    config.sppPlugin.repositoryAddress = vm.parseJsonAddress(json, ".sppPlugin.repositoryAddress");
    config.sppPlugin.metadata = vm.parseJsonString(json, ".sppPlugin.metadata");

    // Parse Token Voting Hats config (from main DAO)
    config.tokenVotingPluginRepo = vm.parseJsonAddress(json, ".tokenVotingHats.repositoryAddress");
    config.tokenVotingPluginRepoRelease = uint8(vm.parseJsonUint(json, ".tokenVotingHats.release"));
    config.tokenVotingPluginRepoBuild = uint16(vm.parseJsonUint(json, ".tokenVotingHats.build"));
    config.governanceErc20 = vm.parseJsonAddress(json, ".tokenVotingHats.governanceErc20");
    config.governanceWrappedErc20 = vm.parseJsonAddress(json, ".tokenVotingHats.governanceWrappedErc20");

    // Parse SPP plugin setup address
    config.sppPluginSetup = vm.parseJsonAddress(json, ".sppPlugin.setupAddress");

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

  /// @notice Execute the full deployment (called by run() or from tests)
  /// @return factory The deployed factory contract
  function execute() public returns (ApproverHatMinterSubDaoFactory factory) {
    // Load configuration from JSON
    _loadConfig();

    // Get OSx addresses for current chain
    (address osxDaoFactory, address pluginSetupProcessor, address pluginRepoFactory) = _getOSxAddresses();

    // ===== STEP 1: Deploy Plugin Setup Contracts =====
    (TokenVotingSetupHats tokenVotingSetup, AdminSetup adminSetup, address sppPluginSetup) =
      _deployPluginSetups();

    // ===== STEP 2: Deploy ApproverHatMinterSubDaoFactory =====
    factory = _deployFactory(
      tokenVotingSetup, adminSetup, sppPluginSetup, osxDaoFactory, pluginSetupProcessor, pluginRepoFactory
    );

    // ===== STEP 3: Deploy the SubDAO =====
    _deploySubDao(factory);

    // ===== STEP 4: Log deployment artifacts =====
    _logDeployment(factory);

    return factory;
  }

  /// @notice Run script with broadcasting for actual deployment
  function run() external {
    vm.startBroadcast(_deployer());
    execute();
    vm.stopBroadcast();
  }

  /// @notice Deploys all plugin setup contracts
  function _deployPluginSetups()
    internal
    returns (TokenVotingSetupHats tokenVotingSetup, AdminSetup adminSetup, address sppPluginSetup)
  {
    console.log("=== Deploying Plugin Setup Contracts ===");

    // Use base implementations from config for TokenVoting
    require(config.governanceErc20 != address(0), "governanceErc20 not set in config");
    require(config.governanceWrappedErc20 != address(0), "governanceWrappedErc20 not set in config");

    console.log("Using GovernanceERC20 base:", config.governanceErc20);
    console.log("Using GovernanceWrappedERC20 base:", config.governanceWrappedErc20);

    // Deploy TokenVotingSetupHats
    tokenVotingSetup = new TokenVotingSetupHats(
      GovernanceERC20(config.governanceErc20), GovernanceWrappedERC20(config.governanceWrappedErc20)
    );
    console.log("TokenVotingSetupHats:", address(tokenVotingSetup));

    // Deploy AdminSetup
    adminSetup = new AdminSetup();
    console.log("AdminSetup:", address(adminSetup));

    // Use SPP Plugin Setup from config
    require(config.sppPluginSetup != address(0), "sppPluginSetup not set in config");
    sppPluginSetup = config.sppPluginSetup;
    console.log("SPP Plugin Setup:", sppPluginSetup);

    console.log("");
  }

  /// @notice Deploys the ApproverHatMinterSubDaoFactory with all parameters
  function _deployFactory(
    TokenVotingSetupHats tokenVotingSetup,
    AdminSetup adminSetup,
    address sppPluginSetup,
    address osxDaoFactory,
    address pluginSetupProcessor,
    address pluginRepoFactory
  ) internal returns (ApproverHatMinterSubDaoFactory) {
    console.log("=== Deploying ApproverHatMinterSubDaoFactory ===");

    // Use plugin repo addresses from config
    address tokenVotingPluginRepo = config.tokenVotingPluginRepo;
    address adminPluginRepo = _getAdminPluginRepo();
    address sppPluginRepo = config.sppPlugin.useExisting ? config.sppPlugin.repositoryAddress : address(0);

    DeploymentParameters memory params = DeploymentParameters({
      // Configuration structs
      dao: config.dao,
      adminPlugin: config.adminPlugin,
      stage1: config.stage1,
      stage2: config.stage2,
      sppPlugin: config.sppPlugin,
      // Main DAO addresses
      mainDaoAddress: config.mainDaoAddress,
      mainDaoFactoryAddress: config.mainDaoFactoryAddress,
      // Plugin setup contracts
      tokenVotingSetup: tokenVotingSetup,
      tokenVotingPluginRepo: PluginRepo(tokenVotingPluginRepo),
      adminSetup: adminSetup,
      adminPluginRepo: PluginRepo(adminPluginRepo),
      sppPluginSetup: sppPluginSetup,
      sppPluginRepo: PluginRepo(sppPluginRepo),
      // Plugin repo version info (from main DAO config)
      tokenVotingPluginRepoRelease: config.tokenVotingPluginRepoRelease,
      tokenVotingPluginRepoBuild: config.tokenVotingPluginRepoBuild,
      // OSx framework addresses
      osxDaoFactory: osxDaoFactory,
      pluginSetupProcessor: PluginSetupProcessor(pluginSetupProcessor),
      pluginRepoFactory: PluginRepoFactory(pluginRepoFactory)
    });

    ApproverHatMinterSubDaoFactory factory = new ApproverHatMinterSubDaoFactory(params);
    console.log("ApproverHatMinterSubDaoFactory:", address(factory));
    console.log("");

    return factory;
  }

  /// @notice Deploys the SubDAO via factory.deployOnce()
  function _deploySubDao(ApproverHatMinterSubDaoFactory factory) internal {
    console.log("=== Deploying SubDAO ===");

    factory.deployOnce();

    console.log("SubDAO deployed successfully!");
    console.log("");
  }

  /// @notice Logs all deployment addresses
  function _logDeployment(ApproverHatMinterSubDaoFactory factory) internal view {
    console.log("=== Deployment Artifacts ===");
    console.log("Factory:", address(factory));
    console.log("");

    // Retrieve deployment from factory
    Deployment memory deployment = factory.getDeployment();

    console.log("DAO:", address(deployment.dao));
    console.log("");
    console.log("Plugins:");
    console.log("  Admin:", address(deployment.adminPlugin));
    console.log("  Admin Repo:", address(deployment.adminPluginRepo));
    console.log("  TokenVotingHats:", address(deployment.tokenVotingPlugin));
    console.log("  TokenVotingHats Repo:", address(deployment.tokenVotingPluginRepo));
    console.log("  SPP Plugin:", deployment.sppPlugin);
    console.log("  SPP Plugin Repo:", address(deployment.sppPluginRepo));
  }
}
