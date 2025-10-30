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

import {VETokenVotingDaoFactory} from "../src/VETokenVotingDaoFactory.sol";

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

  /// @notice TEMPORARY: Main DAO deployment data loaded from config
  /// @dev These values are extracted from broadcast artifacts to avoid on-chain queries
  /// @dev Once main DAO factory is redeployed with getter functions, this should be removed
  /// @dev and replaced with direct on-chain calls to mainDaoFactory.getX() methods
  struct MainDaoDeploymentData {
    address ivotesAdapter;
    address tokenVotingPluginRepo;
    address tokenVotingSetup;
    uint8 pluginRepoRelease;
    uint16 pluginRepoBuild;
    uint256 proposerHatId;
    uint256 voterHatId;
    uint256 executorHatId;
  }

  struct Config {
    string version;
    string network;
    DaoConfig dao;
    address mainDaoAddress;
    address mainDaoFactoryAddress;
    MainDaoDeploymentData mainDaoDeploymentData; // TEMPORARY: loaded from config
    AdminPluginConfig adminPlugin;
    Stage1Config stage1;
    Stage2Config stage2;
    SppPluginConfig sppPlugin;
  }

  Config config;
  Stage2Config stage2Parsed;

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

    // TEMPORARY: Parse main DAO deployment data from config
    // Once main DAO factory is redeployed with getter functions, replace this with direct on-chain queries
    config.mainDaoDeploymentData.ivotesAdapter =
      vm.parseJsonAddress(json, ".mainDaoDeploymentData.ivotesAdapter");
    config.mainDaoDeploymentData.tokenVotingPluginRepo =
      vm.parseJsonAddress(json, ".mainDaoDeploymentData.tokenVotingPluginRepo");
    config.mainDaoDeploymentData.tokenVotingSetup =
      vm.parseJsonAddress(json, ".mainDaoDeploymentData.tokenVotingSetup");
    config.mainDaoDeploymentData.pluginRepoRelease =
      uint8(vm.parseJsonUint(json, ".mainDaoDeploymentData.pluginRepoRelease"));
    config.mainDaoDeploymentData.pluginRepoBuild =
      uint16(vm.parseJsonUint(json, ".mainDaoDeploymentData.pluginRepoBuild"));
    config.mainDaoDeploymentData.proposerHatId = vm.parseJsonUint(json, ".mainDaoDeploymentData.proposerHatId");
    config.mainDaoDeploymentData.voterHatId = vm.parseJsonUint(json, ".mainDaoDeploymentData.voterHatId");
    config.mainDaoDeploymentData.executorHatId = vm.parseJsonUint(json, ".mainDaoDeploymentData.executorHatId");

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
    // Note: Hat IDs are loaded from mainDaoDeploymentData section above
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

  /// @notice TEMPORARY: Load main DAO deployment data from config
  /// @dev This function reads from config instead of querying on-chain to avoid Foundry fork bugs
  /// @dev Once main DAO factory is redeployed with dedicated getter functions, replace this with:
  /// @dev   ivotesAdapter = mainFactory.getIVotesAdapter();
  /// @dev   tokenVotingPluginRepo = mainFactory.getTokenVotingPluginRepo();
  /// @dev   tokenVotingSetup = mainFactory.getTokenVotingSetup();
  /// @dev   proposerHatId = mainFactory.getProposerHatId();
  /// @dev   etc.
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
    console.log("Loading main DAO deployment data from config...");

    // TEMPORARY: Load all values from config instead of querying on-chain
    // Replace with direct getter calls after main factory redeployment
    ivotesAdapter = config.mainDaoDeploymentData.ivotesAdapter;
    tokenVotingPluginRepo = config.mainDaoDeploymentData.tokenVotingPluginRepo;
    proposerHatId = config.mainDaoDeploymentData.proposerHatId;
    voterHatId = config.mainDaoDeploymentData.voterHatId;
    executorHatId = config.mainDaoDeploymentData.executorHatId;
    pluginRepoRelease = config.mainDaoDeploymentData.pluginRepoRelease;
    pluginRepoBuild = config.mainDaoDeploymentData.pluginRepoBuild;
    tokenVotingSetup = TokenVotingSetupHats(config.mainDaoDeploymentData.tokenVotingSetup);
  }

  /// @notice Execute the full deployment (called by run() or from tests)
  /// @return factory The deployed factory contract
  function execute() public returns (ApproverHatMinterSubDaoFactory factory) {
    // Load configuration from JSON
    _loadConfig();

    // TEMPORARY: Load main DAO factory data from config
    // Once main factory is redeployed with getters, replace with on-chain queries
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

    console.log("Main DAO factory data:");
    console.log("  IVotesAdapter:", ivotesAdapter);
    console.log("  TokenVoting plugin repo:", tokenVotingPluginRepo);
    console.log("  Plugin repo version - release:", pluginRepoRelease);
    console.log("  Plugin repo version - build:", pluginRepoBuild);
    console.log("  Hat IDs - Proposer:", config.stage2.tokenVotingHats.proposerHatId);
    console.log("  Hat IDs - Voter:", config.stage2.tokenVotingHats.voterHatId);
    console.log("  Hat IDs - Executor:", config.stage2.tokenVotingHats.executorHatId);

    // ===== STEP 1 & 2: Deploy Plugin Setups and Factory =====
    factory = _deployPluginSetupsAndFactory(
      tokenVotingSetup,
      ivotesAdapter,
      tokenVotingPluginRepo,
      pluginRepoRelease,
      pluginRepoBuild
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
  /// @notice Deploys plugin setups and factory in one function to avoid stack depth issues
  function _deployPluginSetupsAndFactory(
    TokenVotingSetupHats mainDaoTokenVotingSetup,
    address ivotesAdapter,
    address tokenVotingPluginRepo,
    uint8 pluginRepoRelease,
    uint16 pluginRepoBuild
  ) internal returns (ApproverHatMinterSubDaoFactory) {
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
    console.log("=== Deploying Plugin Setup Contracts ===");

    // Get base implementations from main DAO factory setup contract
    address governanceErc20 = mainDaoTokenVotingSetup.governanceERC20Base();
    address governanceWrappedErc20 = mainDaoTokenVotingSetup.governanceWrappedERC20Base();
    require(governanceErc20 != address(0), "governanceErc20 is zero address");
    require(governanceWrappedErc20 != address(0), "governanceWrappedErc20 is zero address");

    console.log("Using GovernanceERC20 base from main DAO:", governanceErc20);
    console.log("Using GovernanceWrappedERC20 base from main DAO:", governanceWrappedErc20);

    // Deploy TokenVotingSetupHats
    tokenVotingSetup = new TokenVotingSetupHats(
      GovernanceERC20(governanceErc20), GovernanceWrappedERC20(governanceWrappedErc20)
    );
    console.log("TokenVotingSetupHats:", address(tokenVotingSetup));

    // Deploy AdminSetup
    adminSetup = new AdminSetup();
    console.log("AdminSetup:", address(adminSetup));

    // Get SPP Plugin Setup from existing repo (don't deploy new - it's too large!)
    address sppPluginRepo = _getSppPluginRepo();
    PluginRepo.Tag memory sppRepoTag = PluginRepo.Tag({
      release: uint8(config.sppPlugin.release),
      build: uint16(config.sppPlugin.build)
    });
    PluginRepo.Version memory sppVersion = PluginRepo(sppPluginRepo).getVersion(sppRepoTag);
    sppPluginSetup = sppVersion.pluginSetup;
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
    address pluginRepoFactory,
    MainDaoData memory mainDaoData
  ) internal returns (ApproverHatMinterSubDaoFactory) {
    console.log("=== Deploying ApproverHatMinterSubDaoFactory ===");

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
