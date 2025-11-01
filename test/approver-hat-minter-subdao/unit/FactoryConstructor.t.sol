// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { BaseFactoryTest } from "../../base/BaseFactoryTest.sol";
import {
  ApproverHatMinterSubDaoFactory,
  DeploymentParameters,
  DaoConfig,
  AdminPluginConfig,
  Stage1Config,
  Stage2Config,
  TokenVotingHatsPluginConfig,
  SppPluginConfig
} from "../../../src/ApproverHatMinterSubDaoFactory.sol";
import { TokenVotingSetupHats } from "@token-voting-hats/TokenVotingSetupHats.sol";
import { AdminSetup } from "@admin-plugin/AdminSetup.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { MajorityVotingBase } from "@token-voting-hats/base/MajorityVotingBase.sol";
import { VETokenVotingDaoFactory } from "../../../src/VETokenVotingDaoFactory.sol";
import { DeployDaoFromConfigScript } from "../../../script/DeployDao.s.sol";

/**
 * @title FactoryConstructorTest
 * @notice Unit tests for ApproverHatMinterSubDaoFactory constructor
 * @dev Tests parameter storage using values from config file
 */
contract FactoryConstructorTest is BaseFactoryTest {
  ApproverHatMinterSubDaoFactory factory;

  // Main DAO factory (deployed for real addresses, not mocks!)
  VETokenVotingDaoFactory mainFactory;

  // Config loaded from JSON
  Config config;

  // Test deployer
  address deployer = address(0x1);

  // Struct to hold config (mirrors script config structure)
  struct Config {
    DaoConfig dao;
    address mainDaoAddress;
    address ivotesAdapter;
    address tokenVotingPluginRepo;
    address tokenVotingSetup;
    uint8 pluginRepoRelease;
    uint16 pluginRepoBuild;
    uint256 proposerHatId;
    uint256 voterHatId;
    uint256 executorHatId;
    AdminPluginConfig adminPlugin;
    Stage1Config stage1;
    Stage2Config stage2;
    SppPluginConfig sppPlugin;
  }

  function setUp() public {
    // Set up fork (required to deploy real contracts)
    setupFork();

    // Deploy real main DAO to get real addresses (no mocks!)
    DeployDaoFromConfigScript script = new DeployDaoFromConfigScript();
    mainFactory = script.execute();

    // Load config for SubDAO-specific settings
    _loadConfig();
  }

  /// @notice Load config from JSON file
  function _loadConfig() internal {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/config/approver-hat-minter-subdao-config.json");
    string memory json = vm.readFile(path);

    // Parse DAO config
    config.dao.metadataUri = vm.parseJsonString(json, ".dao.metadataUri");
    config.dao.subdomain = vm.parseJsonString(json, ".dao.subdomain");

    // Parse main DAO address
    config.mainDaoAddress = vm.parseJsonAddress(json, ".mainDaoAddress");

    // Query main DAO factory for deployment data (no mocks, real addresses!)
    config.ivotesAdapter = mainFactory.getIVotesAdapter();
    config.tokenVotingPluginRepo = mainFactory.getTokenVotingPluginRepo();
    config.tokenVotingSetup = address(mainFactory.getTokenVotingSetup());
    config.pluginRepoRelease = mainFactory.getPluginRepoRelease();
    config.pluginRepoBuild = mainFactory.getPluginRepoBuild();
    config.proposerHatId = mainFactory.getProposerHatId();
    config.voterHatId = mainFactory.getVoterHatId();
    config.executorHatId = mainFactory.getExecutorHatId();

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
    // Hat IDs come from main DAO factory (already queried above)
    config.stage2.tokenVotingHats.proposerHatId = config.proposerHatId;
    config.stage2.tokenVotingHats.voterHatId = config.voterHatId;
    config.stage2.tokenVotingHats.executorHatId = config.executorHatId;
    config.stage2.minAdvance = uint48(vm.parseJsonUint(json, ".stage2.minAdvance"));
    config.stage2.maxAdvance = uint48(vm.parseJsonUint(json, ".stage2.maxAdvance"));
    config.stage2.voteDuration = uint48(vm.parseJsonUint(json, ".stage2.voteDuration"));

    // Parse SPP plugin config
    config.sppPlugin.release = uint8(vm.parseJsonUint(json, ".sppPlugin.release"));
    config.sppPlugin.build = uint16(vm.parseJsonUint(json, ".sppPlugin.build"));
    config.sppPlugin.useExisting = vm.parseJsonBool(json, ".sppPlugin.useExisting");
    config.sppPlugin.metadata = vm.parseJsonString(json, ".sppPlugin.metadata");
  }

  /// @notice Converts string voting mode to enum
  function _parseVotingMode(string memory mode) internal pure returns (MajorityVotingBase.VotingMode) {
    bytes32 modeHash = keccak256(bytes(mode));
    if (modeHash == keccak256(bytes("Standard"))) return MajorityVotingBase.VotingMode.Standard;
    if (modeHash == keccak256(bytes("EarlyExecution"))) return MajorityVotingBase.VotingMode.EarlyExecution;
    if (modeHash == keccak256(bytes("VoteReplacement"))) return MajorityVotingBase.VotingMode.VoteReplacement;
    revert(string.concat("Invalid voting mode: ", mode));
  }

  /// @notice Helper to create minimal valid deployment parameters from config
  function _createMinimalParams() internal returns (DeploymentParameters memory) {
    DeploymentParameters memory params;

    // DAO config (from config file)
    params.dao = config.dao;

    // Admin plugin config (from config file)
    params.adminPlugin = config.adminPlugin;

    // Stage 1 config (from config file)
    params.stage1 = config.stage1;

    // Stage 2 config (from config file)
    params.stage2 = config.stage2;

    // SPP plugin config (from config file)
    params.sppPlugin = config.sppPlugin;

    // IVotesAdapter (from config file)
    params.ivotesAdapter = config.ivotesAdapter;

    // Plugin setups (use mock addresses for unit tests - no actual deployment)
    params.tokenVotingSetup = TokenVotingSetupHats(makeAddr("tokenVotingSetup"));
    params.tokenVotingPluginRepo = PluginRepo(config.tokenVotingPluginRepo);
    params.adminSetup = AdminSetup(makeAddr("adminSetup"));
    params.adminPluginRepo = PluginRepo(makeAddr("adminPluginRepo"));
    params.sppPluginSetup = makeAddr("sppPluginSetup");
    params.sppPluginRepo = PluginRepo(makeAddr("sppPluginRepo"));

    // Plugin repo version info (from config)
    params.tokenVotingPluginRepoRelease = config.pluginRepoRelease;
    params.tokenVotingPluginRepoBuild = config.pluginRepoBuild;

    // OSx framework addresses (use mock addresses for unit tests)
    params.osxDaoFactory = makeAddr("osxDaoFactory");
    params.pluginSetupProcessor = PluginSetupProcessor(makeAddr("pluginSetupProcessor"));
    params.pluginRepoFactory = PluginRepoFactory(makeAddr("pluginRepoFactory"));

    return params;
  }

  /// @notice Test that constructor stores deployer correctly
  function test_ConstructorStoresDeployer() public {
    DeploymentParameters memory params = _createMinimalParams();

    vm.prank(deployer);
    factory = new ApproverHatMinterSubDaoFactory(params);

    assertEq(factory.deployer(), deployer, "Deployer should be stored correctly");
  }

  /// @notice Test that constructor stores DAO config correctly
  function test_ConstructorStoresDaoConfig() public {
    DeploymentParameters memory params = _createMinimalParams();

    vm.prank(deployer);
    factory = new ApproverHatMinterSubDaoFactory(params);

    DeploymentParameters memory storedParams = factory.getDeploymentParameters();
    assertEq(storedParams.dao.metadataUri, params.dao.metadataUri, "Metadata URI should match");
    assertEq(storedParams.dao.subdomain, params.dao.subdomain, "Subdomain should match");
  }

  /// @notice Test that constructor stores admin plugin config correctly
  function test_ConstructorStoresAdminConfig() public {
    DeploymentParameters memory params = _createMinimalParams();

    vm.prank(deployer);
    factory = new ApproverHatMinterSubDaoFactory(params);

    DeploymentParameters memory storedParams = factory.getDeploymentParameters();
    assertEq(
      storedParams.adminPlugin.adminAddress, config.adminPlugin.adminAddress, "Admin address should match config"
    );
  }

  /// @notice Test that constructor stores Stage 1 config correctly
  function test_ConstructorStoresStage1Config() public {
    DeploymentParameters memory params = _createMinimalParams();

    vm.prank(deployer);
    factory = new ApproverHatMinterSubDaoFactory(params);

    DeploymentParameters memory storedParams = factory.getDeploymentParameters();
    assertEq(storedParams.stage1.proposerAddress, config.stage1.proposerAddress, "Proposer address should match config");
    assertEq(storedParams.stage1.minAdvance, config.stage1.minAdvance, "minAdvance should match config");
    assertEq(storedParams.stage1.maxAdvance, config.stage1.maxAdvance, "maxAdvance should match config");
    assertEq(storedParams.stage1.voteDuration, config.stage1.voteDuration, "voteDuration should match config");
  }

  /// @notice Test that constructor stores Stage 2 config correctly
  function test_ConstructorStoresStage2Config() public {
    DeploymentParameters memory params = _createMinimalParams();

    vm.prank(deployer);
    factory = new ApproverHatMinterSubDaoFactory(params);

    DeploymentParameters memory storedParams = factory.getDeploymentParameters();
    assertEq(
      uint8(storedParams.stage2.tokenVotingHats.votingMode),
      uint8(config.stage2.tokenVotingHats.votingMode),
      "Voting mode should match config"
    );
    assertEq(
      storedParams.stage2.tokenVotingHats.supportThreshold,
      config.stage2.tokenVotingHats.supportThreshold,
      "Support threshold should match config"
    );
    assertEq(
      storedParams.stage2.tokenVotingHats.minParticipation,
      config.stage2.tokenVotingHats.minParticipation,
      "Min participation should match config"
    );
    assertEq(
      storedParams.stage2.tokenVotingHats.minDuration,
      config.stage2.tokenVotingHats.minDuration,
      "Min duration should match config"
    );
    assertEq(
      storedParams.stage2.tokenVotingHats.proposerHatId,
      config.stage2.tokenVotingHats.proposerHatId,
      "Proposer hat ID should match config"
    );
    assertEq(
      storedParams.stage2.tokenVotingHats.voterHatId,
      config.stage2.tokenVotingHats.voterHatId,
      "Voter hat ID should match config"
    );
    assertEq(
      storedParams.stage2.tokenVotingHats.executorHatId,
      config.stage2.tokenVotingHats.executorHatId,
      "Executor hat ID should match config"
    );
  }

  /// @notice Test that constructor stores IVotesAdapter correctly
  function test_ConstructorStoresIVotesAdapter() public {
    DeploymentParameters memory params = _createMinimalParams();

    vm.prank(deployer);
    factory = new ApproverHatMinterSubDaoFactory(params);

    DeploymentParameters memory storedParams = factory.getDeploymentParameters();
    assertEq(storedParams.ivotesAdapter, config.ivotesAdapter, "IVotesAdapter should match config");
  }

  /// @notice Test that constructor stores plugin setup addresses correctly
  function test_ConstructorStoresPluginSetups() public {
    DeploymentParameters memory params = _createMinimalParams();

    vm.prank(deployer);
    factory = new ApproverHatMinterSubDaoFactory(params);

    DeploymentParameters memory storedParams = factory.getDeploymentParameters();
    assertEq(address(storedParams.tokenVotingSetup), address(params.tokenVotingSetup), "TokenVotingSetup should match");
    assertEq(address(storedParams.adminSetup), address(params.adminSetup), "AdminSetup should match");
    assertEq(storedParams.sppPluginSetup, params.sppPluginSetup, "SPP plugin setup should match");
  }

  /// @notice Test that constructor stores OSx framework addresses correctly
  function test_ConstructorStoresOSxAddresses() public {
    DeploymentParameters memory params = _createMinimalParams();

    vm.prank(deployer);
    factory = new ApproverHatMinterSubDaoFactory(params);

    DeploymentParameters memory storedParams = factory.getDeploymentParameters();
    // Verify addresses are set (we use mock addresses in unit tests)
    assertTrue(storedParams.osxDaoFactory != address(0), "OSx DAO factory should be set");
    assertTrue(address(storedParams.pluginSetupProcessor) != address(0), "Plugin setup processor should be set");
    assertTrue(address(storedParams.pluginRepoFactory) != address(0), "Plugin repo factory should be set");
  }

  /// @notice Test that factory version is set correctly
  function test_FactoryVersion() public {
    DeploymentParameters memory params = _createMinimalParams();

    vm.prank(deployer);
    factory = new ApproverHatMinterSubDaoFactory(params);

    assertEq(factory.version(), "1.0.0", "Factory version should be 1.0.0");
  }

  /// @notice Test that deployment is initially empty
  function test_InitialDeploymentIsEmpty() public {
    DeploymentParameters memory params = _createMinimalParams();

    vm.prank(deployer);
    factory = new ApproverHatMinterSubDaoFactory(params);

    // Check that deployment struct is empty (DAO address is zero)
    assertEq(address(factory.getDeployment().dao), address(0), "Initial deployment should be empty");
  }
}
