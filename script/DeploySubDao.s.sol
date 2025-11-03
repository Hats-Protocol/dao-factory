// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {
  SubDaoFactory,
  DeploymentParameters,
  Deployment,
  DaoConfig,
  AdminPluginConfig,
  Stage1Config,
  Stage2Config,
  TokenVotingHatsPluginConfig,
  SppPluginConfig
} from "../src/SubDaoFactory.sol";
import { DeploymentScriptHelpers } from "./DeploymentHelpers.sol";

import { TokenVotingSetupHats } from "@token-voting-hats/TokenVotingSetupHats.sol";
import { AdminSetup } from "@admin-plugin/AdminSetup.sol";
import { MajorityVotingBase } from "@token-voting-hats/base/MajorityVotingBase.sol";
import { GovernanceERC20 } from "@token-voting-hats/erc20/GovernanceERC20.sol";
import { GovernanceWrappedERC20 } from "@token-voting-hats/erc20/GovernanceWrappedERC20.sol";
import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

import { VETokenVotingDaoFactory } from "../src/VETokenVotingDaoFactory.sol";

/**
 * @title DeploySubDaoScript
 * @notice Generic deployment script for SubDAOs
 * @dev Run with: forge script script/DeploySubDao.s.sol --rpc-url sepolia --broadcast --verify
 * @dev Configuration loaded from JSON file specified by CONFIG_PATH env var (default: config/subdaos/approver-hat-minter.json)
 * @dev Requires PRIVATE_KEY environment variable to be set
 */
contract DeploySubDaoScript is Script, DeploymentScriptHelpers {
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
  }

  Config config;
  Stage2Config stage2Parsed;

  /// @notice Stores last deployed factory for orchestrator to read
  /// @dev Set by run(), read by orchestrator after calling run()
  SubDaoFactory public lastDeployedFactory;

  /// @notice Small struct to pass main DAO values to _deployFactory without stack depth issues
  struct MainDaoData {
    address ivotesAdapter;
    address tokenVotingPluginRepo;
    uint8 pluginRepoRelease;
    uint16 pluginRepoBuild;
  }

  /// @notice Loads configuration from JSON file
  function _loadConfig() internal {
    string memory root = vm.projectRoot();
    string memory configPath = vm.envOr("CONFIG_PATH", string("config/subdaos/approver-hat-minter.json"));
    string memory path = string.concat(root, "/", configPath);
    string memory json = vm.readFile(path);

    _log("Loading config from:", path);

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
    config.stage2.tokenVotingHats.minDuration = uint64(vm.parseJsonUint(json, ".stage2.tokenVotingHats.minDuration"));
    config.stage2.tokenVotingHats.minProposerVotingPower =
      vm.parseJsonUint(json, ".stage2.tokenVotingHats.minProposerVotingPower");
    // Note: Hat IDs are queried from main DAO factory via getter functions in _getMainDaoFactoryData()
    config.stage2.minAdvance = uint48(vm.parseJsonUint(json, ".stage2.minAdvance"));
    config.stage2.maxAdvance = uint48(vm.parseJsonUint(json, ".stage2.maxAdvance"));
    config.stage2.voteDuration = uint48(vm.parseJsonUint(json, ".stage2.voteDuration"));

    // Parse SPP plugin config
    config.sppPlugin.release = uint8(vm.parseJsonUint(json, ".sppPlugin.release"));
    config.sppPlugin.build = uint16(vm.parseJsonUint(json, ".sppPlugin.build"));
    config.sppPlugin.useExisting = vm.parseJsonBool(json, ".sppPlugin.useExisting");
    // config.sppPlugin.repositoryAddress = vm.parseJsonAddress(json, ".sppPlugin.repositoryAddress");
    config.sppPlugin.metadata = vm.parseJsonString(json, ".sppPlugin.metadata");
    // Note: SPP plugin setup is deployed in _deployPluginSetups(), not read from config
    // Note: SPP plugin repo address is fetched programmatically in _deployFactory()

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

  /// @notice Load main DAO deployment data from the deployed factory via getter functions
  /// @return ivotesAdapter The IVotesAdapter address
  /// @return tokenVotingPluginRepo The TokenVoting plugin repo address
  /// @return proposerHatId The proposer hat ID
  /// @return voterHatId The voter hat ID
  /// @return executorHatId The executor hat ID
  /// @return pluginRepoRelease The plugin repo release number
  /// @return pluginRepoBuild The plugin repo build number
  /// @return tokenVotingSetup The TokenVotingSetupHats contract
  function _getMainDaoFactoryData()
    internal
    view
    returns (
      address ivotesAdapter,
      address tokenVotingPluginRepo,
      uint256 proposerHatId,
      uint256 voterHatId,
      uint256 executorHatId,
      uint8 pluginRepoRelease,
      uint16 pluginRepoBuild,
      TokenVotingSetupHats tokenVotingSetup
    )
  {
    _log("Loading main DAO deployment data from factory getter functions...");

    // Get the main DAO factory instance
    VETokenVotingDaoFactory mainFactory = VETokenVotingDaoFactory(config.mainDaoFactoryAddress);

    // Query via getter functions (no more config!)
    ivotesAdapter = mainFactory.getIVotesAdapter();
    tokenVotingPluginRepo = mainFactory.getTokenVotingPluginRepo();
    tokenVotingSetup = mainFactory.getTokenVotingSetup();
    pluginRepoRelease = mainFactory.getPluginRepoRelease();
    pluginRepoBuild = mainFactory.getPluginRepoBuild();
    proposerHatId = mainFactory.getProposerHatId();
    voterHatId = mainFactory.getVoterHatId();
    executorHatId = mainFactory.getExecutorHatId();
  }

  /// @notice Try to read an address from environment variable
  /// @param key Environment variable name
  /// @return addr Address from env var, or address(0) if not set
  /// @dev Used by orchestrator to pass main DAO addresses via env vars
  function _tryEnvAddress(string memory key) internal view returns (address addr) {
    try vm.envAddress(key) returns (address value) {
      return value;
    } catch {
      return address(0);  // Falls back to config value in execute()
    }
  }

  /// @notice Execute the full deployment (called by run() or from tests)
  /// @param mainDaoFactoryOverride Optional main DAO factory address to use instead of config value
  /// @param mainDaoAddressOverride Optional main DAO address to use instead of config value
  /// @dev If address(0), uses mainDaoFactoryAddress/mainDaoAddress from config; otherwise uses provided addresses
  /// @dev Tests can pass freshly deployed addresses; CLI calls execute(address(0), address(0)) to use config
  /// @return factory The deployed factory contract
  function execute(address mainDaoFactoryOverride, address mainDaoAddressOverride)
    public
    returns (SubDaoFactory factory)
  {
    // Load configuration from JSON
    _loadConfig();

    // Override config if mainDaoFactoryOverride is provided
    if (mainDaoFactoryOverride != address(0)) {
      config.mainDaoFactoryAddress = mainDaoFactoryOverride;
    }

    // Override config if mainDaoAddressOverride is provided
    if (mainDaoAddressOverride != address(0)) {
      config.mainDaoAddress = mainDaoAddressOverride;
    }

    // Load main DAO factory data via getter functions
    (
      address ivotesAdapter,
      address tokenVotingPluginRepo,
      uint256 proposerHatId,
      uint256 voterHatId,
      uint256 executorHatId,
      uint8 pluginRepoRelease,
      uint16 pluginRepoBuild,
      TokenVotingSetupHats tokenVotingSetup
    ) = _getMainDaoFactoryData();

    // Update config with fetched hat IDs
    config.stage2.tokenVotingHats.proposerHatId = proposerHatId;
    config.stage2.tokenVotingHats.voterHatId = voterHatId;
    config.stage2.tokenVotingHats.executorHatId = executorHatId;

    _log("Main DAO factory data:");
    _log("  IVotesAdapter:", ivotesAdapter);
    _log("  TokenVoting plugin repo:", tokenVotingPluginRepo);
    _log("  Plugin repo version - release:", pluginRepoRelease);
    _log("  Plugin repo version - build:", pluginRepoBuild);
    _log("  Hat IDs - Proposer:", config.stage2.tokenVotingHats.proposerHatId);
    _log("  Hat IDs - Voter:", config.stage2.tokenVotingHats.voterHatId);
    _log("  Hat IDs - Executor:", config.stage2.tokenVotingHats.executorHatId);

    // ===== STEP 1 & 2: Deploy Plugin Setups and Factory =====
    factory = _deployPluginSetupsAndFactory(
      tokenVotingSetup, ivotesAdapter, tokenVotingPluginRepo, pluginRepoRelease, pluginRepoBuild
    );

    // ===== STEP 3: Deploy the SubDAO =====
    _deploySubDao(factory);

    // ===== STEP 4: Log deployment artifacts =====
    _logDeployment(factory);

    return factory;
  }

  /// @notice Run script with broadcasting for actual deployment
  /// @dev Orchestrator sets MAIN_DAO_FACTORY and MAIN_DAO env vars to pass addresses
  /// @dev If env vars not set, uses mainDaoFactoryAddress and mainDaoAddress from config
  function run() external {
    verbose = true;

    // Read overrides from env vars (set by orchestrator)
    address mainDaoFactoryOverride = _tryEnvAddress("MAIN_DAO_FACTORY");
    address mainDaoOverride = _tryEnvAddress("MAIN_DAO");

    vm.startBroadcast(_deployer());
    lastDeployedFactory = execute(mainDaoFactoryOverride, mainDaoOverride);
    vm.stopBroadcast();
  }

  /// @notice Deploys all plugin setup contracts
  /// @notice Deploys plugin setups and factory in one function to avoid stack depth issues
  function _deployPluginSetupsAndFactory(
    TokenVotingSetupHats mainDaoTokenVotingSetup,
    address ivotesAdapter,
    address tokenVotingPluginRepo,
    uint8 pluginRepoRelease,
    uint16 pluginRepoBuild
  ) internal returns (SubDaoFactory) {
    TokenVotingSetupHats newTokenVotingSetup;
    AdminSetup adminSetup;
    address sppPluginSetup;
    (newTokenVotingSetup, adminSetup, sppPluginSetup) = _deployPluginSetups(mainDaoTokenVotingSetup);

    MainDaoData memory mainDaoData = MainDaoData({
      ivotesAdapter: ivotesAdapter,
      tokenVotingPluginRepo: tokenVotingPluginRepo,
      pluginRepoRelease: pluginRepoRelease,
      pluginRepoBuild: pluginRepoBuild
    });

    (address osxDaoFactory, address pluginSetupProcessor, address pluginRepoFactory) = _getOSxAddresses();
    return _deployFactory(
      newTokenVotingSetup,
      adminSetup,
      sppPluginSetup,
      osxDaoFactory,
      pluginSetupProcessor,
      pluginRepoFactory,
      mainDaoData
    );
  }

  function _deployPluginSetups(TokenVotingSetupHats mainDaoTokenVotingSetup)
    internal
    returns (TokenVotingSetupHats tokenVotingSetup, AdminSetup adminSetup, address sppPluginSetup)
  {
    _log("=== Deploying Plugin Setup Contracts ===");

    // Get base implementations from main DAO factory setup contract
    address governanceErc20 = mainDaoTokenVotingSetup.governanceERC20Base();
    address governanceWrappedErc20 = mainDaoTokenVotingSetup.governanceWrappedERC20Base();
    require(governanceErc20 != address(0), "governanceErc20 is zero address");
    require(governanceWrappedErc20 != address(0), "governanceWrappedErc20 is zero address");

    _log("Using GovernanceERC20 base from main DAO:", governanceErc20);
    _log("Using GovernanceWrappedERC20 base from main DAO:", governanceWrappedErc20);

    // Deploy TokenVotingSetupHats
    tokenVotingSetup =
      new TokenVotingSetupHats(GovernanceERC20(governanceErc20), GovernanceWrappedERC20(governanceWrappedErc20));
    _log("TokenVotingSetupHats:", address(tokenVotingSetup));

    // Deploy AdminSetup
    adminSetup = new AdminSetup();
    _log("AdminSetup:", address(adminSetup));

    // Get SPP Plugin Setup from existing repo (don't deploy new - it's too large!)
    address sppPluginRepo = _getSppPluginRepo();
    PluginRepo.Tag memory sppRepoTag =
      PluginRepo.Tag({ release: uint8(config.sppPlugin.release), build: uint16(config.sppPlugin.build) });
    PluginRepo.Version memory sppVersion = PluginRepo(sppPluginRepo).getVersion(sppRepoTag);
    sppPluginSetup = sppVersion.pluginSetup;
    _log("SPP Plugin Setup:", sppPluginSetup);

    _log("");
  }

  /// @notice Deploys the SubDaoFactory with all parameters
  function _deployFactory(
    TokenVotingSetupHats tokenVotingSetup,
    AdminSetup adminSetup,
    address sppPluginSetup,
    address osxDaoFactory,
    address pluginSetupProcessor,
    address pluginRepoFactory,
    MainDaoData memory mainDaoData
  ) internal returns (SubDaoFactory) {
    _log("=== Deploying SubDaoFactory ===");

    require(mainDaoData.ivotesAdapter != address(0), "IVotesAdapter is zero address");

    address adminPluginRepo = _getAdminPluginRepo();

    // Use existing SPP plugin repo from Sepolia
    address sppPluginRepo = _getSppPluginRepo();

    DeploymentParameters memory params = DeploymentParameters({
      // Configuration structs
      dao: config.dao,
      adminPlugin: config.adminPlugin,
      stage1: config.stage1,
      stage2: config.stage2,
      sppPlugin: config.sppPlugin,
      // IVotesAdapter queried from main DAO factory
      ivotesAdapter: mainDaoData.ivotesAdapter,
      // Plugin setup contracts
      tokenVotingSetup: tokenVotingSetup,
      tokenVotingPluginRepo: PluginRepo(mainDaoData.tokenVotingPluginRepo),
      adminSetup: adminSetup,
      adminPluginRepo: PluginRepo(adminPluginRepo),
      sppPluginSetup: sppPluginSetup,
      sppPluginRepo: PluginRepo(sppPluginRepo),
      // Plugin repo version info (from main DAO factory)
      tokenVotingPluginRepoRelease: mainDaoData.pluginRepoRelease,
      tokenVotingPluginRepoBuild: mainDaoData.pluginRepoBuild,
      // OSx framework addresses
      osxDaoFactory: osxDaoFactory,
      pluginSetupProcessor: PluginSetupProcessor(pluginSetupProcessor),
      pluginRepoFactory: PluginRepoFactory(pluginRepoFactory)
    });

    SubDaoFactory factory = new SubDaoFactory(params);
    _log("SubDaoFactory:", address(factory));
    _log("");

    return factory;
  }

  /// @notice Deploys the SubDAO via factory.deployOnce()
  function _deploySubDao(SubDaoFactory factory) internal {
    _log("=== Deploying SubDAO ===");

    factory.deployOnce();

    _log("SubDAO deployed successfully!");
    _log("");
  }

  /// @notice Logs all deployment addresses
  function _logDeployment(SubDaoFactory factory) internal view {
    _log("=== Deployment Artifacts ===");
    _log("Factory:", address(factory));
    _log("");

    // Retrieve deployment from factory
    Deployment memory deployment = factory.getDeployment();

    _log("DAO:", address(deployment.dao));
    _log("");
    _log("Plugins:");
    _log("  Admin:", address(deployment.adminPlugin));
    _log("  Admin Repo:", address(deployment.adminPluginRepo));
    _log("  TokenVotingHats:", address(deployment.tokenVotingPlugin));
    _log("  TokenVotingHats Repo:", address(deployment.tokenVotingPluginRepo));
    _log("  SPP Plugin:", deployment.sppPlugin);
    _log("  SPP Plugin Repo:", address(deployment.sppPluginRepo));
  }
}
