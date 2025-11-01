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
 * @title FactoryAccessControlTest
 * @notice Unit tests for ApproverHatMinterSubDaoFactory access control and error conditions
 * @dev Tests authorization and validation using config values
 */
contract FactoryAccessControlTest is BaseFactoryTest {
  ApproverHatMinterSubDaoFactory factory;

  // Main DAO factory (deployed for real addresses, not mocks!)
  VETokenVotingDaoFactory mainFactory;

  // Config loaded from JSON
  Config config;

  // Test addresses
  address deployer = address(0x1);
  address unauthorized = address(0x2);

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

  /// @notice Helper to create parameters with zero IVotesAdapter
  function _createParamsWithZeroIVotesAdapter() internal returns (DeploymentParameters memory) {
    DeploymentParameters memory params = _createMinimalParams();
    params.ivotesAdapter = address(0); // Set to zero address
    return params;
  }

  /// @notice Test that unauthorized caller cannot call deployOnce()
  function test_DeployOnce_RevertsForUnauthorizedCaller() public {
    DeploymentParameters memory params = _createMinimalParams();

    vm.prank(deployer);
    factory = new ApproverHatMinterSubDaoFactory(params);

    // Try to call deployOnce as unauthorized user
    vm.prank(unauthorized);
    vm.expectRevert(ApproverHatMinterSubDaoFactory.Unauthorized.selector);
    factory.deployOnce();
  }

  /// @notice Test that zero IVotesAdapter is stored (validation happens in deployOnce)
  /// @dev The InvalidIVotesAdapterAddress check is tested in fork tests
  function test_ZeroIVotesAdapterCanBeStored() public {
    DeploymentParameters memory params = _createParamsWithZeroIVotesAdapter();

    vm.prank(deployer);
    factory = new ApproverHatMinterSubDaoFactory(params);

    // Verify zero address is stored (will fail on deployOnce())
    DeploymentParameters memory storedParams = factory.getDeploymentParameters();
    assertEq(storedParams.ivotesAdapter, address(0), "Zero IVotesAdapter should be stored in constructor");
  }

  /// @notice Test that deployer address is stored correctly
  function test_DeployerIsSetCorrectly() public {
    DeploymentParameters memory params = _createMinimalParams();

    vm.prank(deployer);
    factory = new ApproverHatMinterSubDaoFactory(params);

    assertEq(factory.deployer(), deployer, "Deployer should be msg.sender");
  }

  /// @notice Test that different deployers can create different factories
  function test_MultipleFactoriesWithDifferentDeployers() public {
    DeploymentParameters memory params1 = _createMinimalParams();
    DeploymentParameters memory params2 = _createMinimalParams();

    address deployer1 = address(0x100);
    address deployer2 = address(0x200);

    vm.prank(deployer1);
    ApproverHatMinterSubDaoFactory factory1 = new ApproverHatMinterSubDaoFactory(params1);

    vm.prank(deployer2);
    ApproverHatMinterSubDaoFactory factory2 = new ApproverHatMinterSubDaoFactory(params2);

    assertEq(factory1.deployer(), deployer1, "Factory1 deployer should be deployer1");
    assertEq(factory2.deployer(), deployer2, "Factory2 deployer should be deployer2");
    assertTrue(address(factory1) != address(factory2), "Factories should have different addresses");
  }
}
