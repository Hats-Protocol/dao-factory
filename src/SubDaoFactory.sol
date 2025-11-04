// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { DAOFactory } from "@aragon/osx/framework/dao/DAOFactory.sol";
import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { PermissionManager } from "@aragon/osx/core/permission/PermissionManager.sol";
import { PermissionLib } from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import { IPermissionCondition } from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { IPluginSetup } from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import { hashHelpers, PluginSetupRef } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import { IPlugin } from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";

import { TokenVotingSetupHats } from "@token-voting-hats/TokenVotingSetupHats.sol";
import { TokenVotingHats } from "@token-voting-hats/TokenVotingHats.sol";
import { AdminSetup } from "@admin-plugin/AdminSetup.sol";
import { Admin } from "@admin-plugin/Admin.sol";
import { MajorityVotingBase } from "@token-voting-hats/base/MajorityVotingBase.sol";
import { GovernanceERC20 } from "@token-voting-hats/erc20/GovernanceERC20.sol";
import { StagedProposalProcessor } from "staged-proposal-processor-plugin/StagedProposalProcessor.sol";
import { RuledCondition } from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

/// @notice DAO configuration parameters
struct DaoConfig {
  string metadataUri;
  string subdomain;
}

/// @notice Admin plugin configuration
struct AdminPluginConfig {
  address adminAddress;
}

/// @notice Stage 1 configuration (veto or approve mode)
struct Stage1Config {
  string mode; // "veto" or "approve"
  uint256 proposerHatId; // If 0, use direct grant to controllerAddress. Otherwise use HatsCondition.
  address controllerAddress; // Proposer in veto mode, approver in approve mode
  uint48 minAdvance;
  uint48 maxAdvance;
  uint48 voteDuration;
}

/// @notice Token voting hats plugin configuration for Stage 2
struct TokenVotingHatsPluginConfig {
  MajorityVotingBase.VotingMode votingMode;
  uint32 supportThreshold;
  uint32 minParticipation;
  uint64 minDuration;
  uint256 minProposerVotingPower;
  uint256 proposerHatId;
  uint256 voterHatId;
  uint256 executorHatId;
}

/// @notice Stage 2 configuration (veto stage)
struct Stage2Config {
  TokenVotingHatsPluginConfig tokenVotingHats;
  uint48 minAdvance;
  uint48 maxAdvance;
  uint48 voteDuration;
}

/// @notice SPP plugin configuration
struct SppPluginConfig {
  uint8 release;
  uint16 build;
  bool useExisting;
  address repositoryAddress;
  string metadata;
}

/// @notice The struct containing all the parameters to deploy the subDAO
struct DeploymentParameters {
  // Configuration structs
  DaoConfig dao;
  AdminPluginConfig adminPlugin;
  Stage1Config stage1;
  Stage2Config stage2;
  SppPluginConfig sppPlugin;

  // IVotesAdapter address (queried from main DAO factory in deployment script)
  address ivotesAdapter;

  // Plugin setup contracts (must be deployed first)
  TokenVotingSetupHats tokenVotingSetup;
  PluginRepo tokenVotingPluginRepo;
  AdminSetup adminSetup;
  PluginRepo adminPluginRepo;
  address sppPluginSetup;
  PluginRepo sppPluginRepo;

  // Plugin repo version info
  uint8 tokenVotingPluginRepoRelease;
  uint16 tokenVotingPluginRepoBuild;

  // OSx framework addresses (chain-specific)
  address osxDaoFactory;
  PluginSetupProcessor pluginSetupProcessor;
  PluginRepoFactory pluginRepoFactory;
}

/// @notice Contains the artifacts that resulted from running a deployment
struct Deployment {
  DAO dao;
  Admin adminPlugin;
  PluginRepo adminPluginRepo;
  TokenVotingHats tokenVotingPlugin;
  PluginRepo tokenVotingPluginRepo;
  address sppPlugin;
  PluginRepo sppPluginRepo;
  address hatsCondition; // HatsCondition from TokenVotingHats, used for SPP permissions
}

/**
 * @title SubDaoFactory
 * @notice Generic factory for deploying SubDAOs that share main DAO infrastructure
 * @dev Can be used for any SubDAO type (approver-hat-minter, member-curator, etc.)
 * @dev A singleton contract designed to run the deployment once and become a read-only store of the contracts deployed
 */
contract SubDaoFactory {
  address public immutable deployer;

  function version() external pure returns (string memory) {
    return "1.0.0";
  }

  error AlreadyDeployed();
  error Unauthorized();
  error InvalidIVotesAdapterAddress();
  error InvalidControllerAddress();
  error InvalidStage1Mode();

  DeploymentParameters parameters;
  Deployment deployment;

  constructor(DeploymentParameters memory _parameters) {
    deployer = msg.sender;

    parameters.dao = _parameters.dao;
    parameters.adminPlugin = _parameters.adminPlugin;
    parameters.stage1 = _parameters.stage1;
    parameters.stage2 = _parameters.stage2;
    parameters.sppPlugin = _parameters.sppPlugin;
    parameters.ivotesAdapter = _parameters.ivotesAdapter;
    parameters.tokenVotingSetup = _parameters.tokenVotingSetup;
    parameters.tokenVotingPluginRepo = _parameters.tokenVotingPluginRepo;
    parameters.adminSetup = _parameters.adminSetup;
    parameters.adminPluginRepo = _parameters.adminPluginRepo;
    parameters.sppPluginSetup = _parameters.sppPluginSetup;
    parameters.sppPluginRepo = _parameters.sppPluginRepo;
    parameters.tokenVotingPluginRepoRelease = _parameters.tokenVotingPluginRepoRelease;
    parameters.tokenVotingPluginRepoBuild = _parameters.tokenVotingPluginRepoBuild;
    parameters.osxDaoFactory = _parameters.osxDaoFactory;
    parameters.pluginSetupProcessor = _parameters.pluginSetupProcessor;
    parameters.pluginRepoFactory = _parameters.pluginRepoFactory;
  }

  function deployOnce() public {
    if (msg.sender != deployer) revert Unauthorized();
    if (address(deployment.dao) != address(0)) revert AlreadyDeployed();

    DAO dao = _prepareDao();
    deployment.dao = dao;

    _grantApplyInstallationPermissions(dao);

    // Install Admin plugin
    (Admin adminPlugin, PluginRepo adminRepo) = _installAdminPlugin(dao);
    deployment.adminPlugin = adminPlugin;
    deployment.adminPluginRepo = adminRepo;

    // Use IVotesAdapter from parameters (queried in deployment script)
    if (parameters.ivotesAdapter == address(0)) revert InvalidIVotesAdapterAddress();

    // Validate Stage 1 configuration
    if (parameters.stage1.controllerAddress == address(0)) revert InvalidControllerAddress();
    bytes32 modeHash = keccak256(bytes(parameters.stage1.mode));
    if (modeHash != keccak256(bytes("veto")) && modeHash != keccak256(bytes("approve"))) {
      revert InvalidStage1Mode();
    }

    // Install TokenVotingHats plugin (for Stage 2)
    (TokenVotingHats tvPlugin, PluginRepo tvRepo) = _installTokenVotingHats(dao, parameters.ivotesAdapter);
    deployment.tokenVotingPlugin = tvPlugin;
    deployment.tokenVotingPluginRepo = tvRepo;

    // Install SPP plugin with 2 stages
    (address sppPlugin, PluginRepo sppRepo) = _installSppPlugin(dao, address(tvPlugin));
    deployment.sppPlugin = sppPlugin;
    deployment.sppPluginRepo = sppRepo;

    _revokeApplyInstallationPermissions(dao);
    _revokeOwnerPermission(dao);
  }

  function _prepareDao() internal returns (DAO dao) {
    (dao,) = DAOFactory(parameters.osxDaoFactory)
      .createDao(
        DAOFactory.DAOSettings({
          trustedForwarder: address(0),
          daoURI: "",
          subdomain: parameters.dao.subdomain,
          metadata: bytes(parameters.dao.metadataUri)
        }),
        new DAOFactory.PluginSettings[](0)
      );

    // Grant ROOT_PERMISSION to this factory so it can install plugins
    Action[] memory actions = new Action[](1);
    actions[0].to = address(dao);
    actions[0].data = abi.encodeCall(PermissionManager.grant, (address(dao), address(this), dao.ROOT_PERMISSION_ID()));

    dao.execute(bytes32(0), actions, 0);
  }

  function _installAdminPlugin(DAO dao) internal returns (Admin plugin, PluginRepo pluginRepo) {
    pluginRepo = parameters.adminPluginRepo;

    // Use release 1, build 2 (latest admin plugin version)
    PluginRepo.Tag memory repoTag = PluginRepo.Tag(1, 2);

    // Encode installation parameters: admin address and target config
    bytes memory installData = abi.encode(
      parameters.adminPlugin.adminAddress,
      IPlugin.TargetConfig({ target: address(dao), operation: IPlugin.Operation.Call })
    );

    (address pluginAddress, IPluginSetup.PreparedSetupData memory preparedSetupData) = parameters.pluginSetupProcessor
      .prepareInstallation(
        address(dao),
        PluginSetupProcessor.PrepareInstallationParams({
          pluginSetupRef: PluginSetupRef(repoTag, pluginRepo), data: installData
        })
      );

    parameters.pluginSetupProcessor
      .applyInstallation(
        address(dao),
        PluginSetupProcessor.ApplyInstallationParams({
          pluginSetupRef: PluginSetupRef(repoTag, pluginRepo),
          plugin: pluginAddress,
          permissions: preparedSetupData.permissions,
          helpersHash: hashHelpers(preparedSetupData.helpers)
        })
      );

    plugin = Admin(pluginAddress);
  }

  function _installTokenVotingHats(DAO dao, address ivotesAdapter)
    internal
    returns (TokenVotingHats plugin, PluginRepo pluginRepo)
  {
    pluginRepo = parameters.tokenVotingPluginRepo;
    if (address(pluginRepo) == address(0)) {
      pluginRepo = PluginRepoFactory(parameters.pluginRepoFactory)
        .createPluginRepoWithFirstVersion(
          "token-voting-hats-subdao", address(parameters.tokenVotingSetup), address(dao), " ", " "
        );
    }

    PluginRepo.Tag memory repoTag =
      PluginRepo.Tag(parameters.tokenVotingPluginRepoRelease, parameters.tokenVotingPluginRepoBuild);

    bytes memory installData = parameters.tokenVotingSetup
      .encodeInstallationParametersHats(
        MajorityVotingBase.VotingSettings({
          votingMode: parameters.stage2.tokenVotingHats.votingMode,
          supportThreshold: parameters.stage2.tokenVotingHats.supportThreshold,
          minParticipation: parameters.stage2.tokenVotingHats.minParticipation,
          minDuration: parameters.stage2.tokenVotingHats.minDuration,
          minProposerVotingPower: parameters.stage2.tokenVotingHats.minProposerVotingPower
        }),
        TokenVotingSetupHats.TokenSettings({ addr: ivotesAdapter, name: "", symbol: "" }),
        GovernanceERC20.MintSettings({
          receivers: new address[](0), amounts: new uint256[](0), ensureDelegationOnMint: false
        }),
        IPlugin.TargetConfig({ target: address(dao), operation: IPlugin.Operation.Call }),
        0,
        bytes(""),
        new address[](0),
        TokenVotingSetupHats.HatsConfig({
          proposerHatId: parameters.stage2.tokenVotingHats.proposerHatId,
          voterHatId: parameters.stage2.tokenVotingHats.voterHatId,
          executorHatId: parameters.stage2.tokenVotingHats.executorHatId
        })
      );

    (address pluginAddress, IPluginSetup.PreparedSetupData memory preparedSetupData) = parameters.pluginSetupProcessor
      .prepareInstallation(
        address(dao),
        PluginSetupProcessor.PrepareInstallationParams({
          pluginSetupRef: PluginSetupRef(repoTag, pluginRepo), data: installData
        })
      );

    parameters.pluginSetupProcessor
      .applyInstallation(
        address(dao),
        PluginSetupProcessor.ApplyInstallationParams({
          pluginSetupRef: PluginSetupRef(repoTag, pluginRepo),
          plugin: pluginAddress,
          permissions: preparedSetupData.permissions,
          helpersHash: hashHelpers(preparedSetupData.helpers)
        })
      );

    plugin = TokenVotingHats(pluginAddress);

    // Store HatsCondition (helpers[0]) for use in SPP permission grants
    if (preparedSetupData.helpers.length > 0) {
      deployment.hatsCondition = preparedSetupData.helpers[0];
    }
  }

  function _installSppPlugin(DAO dao, address tokenVotingHatsPlugin)
    internal
    returns (address sppPlugin, PluginRepo sppPluginRepo)
  {
    sppPluginRepo = parameters.sppPluginRepo;
    if (address(sppPluginRepo) == address(0)) {
      sppPluginRepo = PluginRepoFactory(parameters.pluginRepoFactory)
        .createPluginRepoWithFirstVersion(
          "staged-proposal-processor-subdao", parameters.sppPluginSetup, address(dao), " ", " "
        );
    }

    PluginRepo.Tag memory repoTag = PluginRepo.Tag(parameters.sppPlugin.release, parameters.sppPlugin.build);

    // Encode SPP installation parameters with 2 stages
    // Stage 1: Manual body (proposerAddress)
    // Stage 2: Automatic body (tokenVotingHatsPlugin)
    bytes memory installData = _encodeSppInstallationData(tokenVotingHatsPlugin);

    (address pluginAddress, IPluginSetup.PreparedSetupData memory preparedSetupData) = parameters.pluginSetupProcessor
      .prepareInstallation(
        address(dao),
        PluginSetupProcessor.PrepareInstallationParams({
          pluginSetupRef: PluginSetupRef(repoTag, sppPluginRepo), data: installData
        })
      );

    parameters.pluginSetupProcessor
      .applyInstallation(
        address(dao),
        PluginSetupProcessor.ApplyInstallationParams({
          pluginSetupRef: PluginSetupRef(repoTag, sppPluginRepo),
          plugin: pluginAddress,
          permissions: preparedSetupData.permissions,
          helpersHash: hashHelpers(preparedSetupData.helpers)
        })
      );

    sppPlugin = pluginAddress;

    // Grant necessary permissions for SPP
    _grantSppPermissions(dao, sppPlugin);
  }

  /// @notice Encodes installation data for the SPP plugin
  /// @dev Follows the StagedProposalProcessorSetup.prepareInstallation encoding:
  /// @dev abi.encode(bytes metadata, Stage[] stages, Rule[] rules, TargetConfig targetConfig)
  /// @param tokenVotingHatsPlugin Address of the TokenVotingHats plugin for stage 2
  /// @return Encoded installation data
  function _encodeSppInstallationData(address tokenVotingHatsPlugin) internal view returns (bytes memory) {
    // Create 2-stage array
    StagedProposalProcessor.Stage[] memory stages = new StagedProposalProcessor.Stage[](2);

    // Stage 1: Manual veto or approval by controller address
    // Mode determines ResultType and thresholds:
    // - "veto" mode: default allow, controller can block (approvalThreshold=0, vetoThreshold=1)
    // - "approve" mode: default block, controller must approve (approvalThreshold=1, vetoThreshold=0)
    bool isApproveMode = keccak256(bytes(parameters.stage1.mode)) == keccak256(bytes("approve"));

    StagedProposalProcessor.Body[] memory stage1Bodies = new StagedProposalProcessor.Body[](1);
    stage1Bodies[0] = StagedProposalProcessor.Body({
      addr: parameters.stage1.controllerAddress,
      isManual: true,
      tryAdvance: true, // Advance immediately on approval (both modes)
      resultType: isApproveMode
        ? StagedProposalProcessor.ResultType.Approval
        : StagedProposalProcessor.ResultType.Veto
    });

    stages[0] = StagedProposalProcessor.Stage({
      bodies: stage1Bodies,
      maxAdvance: uint64(parameters.stage1.maxAdvance),
      minAdvance: uint64(parameters.stage1.minAdvance),
      voteDuration: uint64(parameters.stage1.voteDuration),
      approvalThreshold: isApproveMode ? uint16(1) : uint16(0),
      vetoThreshold: isApproveMode ? uint16(0) : uint16(1),
      cancelable: true,
      editable: true
    });

    // Stage 2: Automatic voting via TokenVotingHats plugin
    StagedProposalProcessor.Body[] memory stage2Bodies = new StagedProposalProcessor.Body[](1);
    stage2Bodies[0] = StagedProposalProcessor.Body({
      addr: tokenVotingHatsPlugin,
      isManual: false,
      tryAdvance: false,
      resultType: StagedProposalProcessor.ResultType.Veto
    });

    stages[1] = StagedProposalProcessor.Stage({
      bodies: stage2Bodies,
      maxAdvance: uint64(parameters.stage2.maxAdvance),
      minAdvance: uint64(parameters.stage2.minAdvance),
      voteDuration: uint64(parameters.stage2.voteDuration),
      approvalThreshold: 0,
      vetoThreshold: 1,
      cancelable: false,
      editable: false
    });

    // Empty rules array - we'll use direct permission grants instead
    // This keeps the setup simple; permissions are managed in _grantSppPermissions()
    RuledCondition.Rule[] memory rules = new RuledCondition.Rule[](0);

    // Target config for executing actions on the DAO
    IPlugin.TargetConfig memory targetConfig =
      IPlugin.TargetConfig({ target: address(deployment.dao), operation: IPlugin.Operation.Call });

    // Encode according to StagedProposalProcessorSetup interface
    return abi.encode(bytes(parameters.sppPlugin.metadata), stages, rules, targetConfig);
  }

  function _grantSppPermissions(DAO dao, address sppPlugin) internal {
    // Permission IDs from SPP plugin
    bytes32 CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");
    bytes32 EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION");

    // ANY_ADDR constant used by plugin setup (matches StagedProposalProcessorSetup)
    address ANY_ADDR = address(type(uint160).max);

    // Step 1: Revoke the broad CREATE_PROPOSAL permission granted by setup to ANY_ADDR
    // The setup grants this with a RuledCondition, but since we're using empty rules,
    // it effectively allows anyone. We revoke it to restrict permissions.
    dao.revoke(sppPlugin, ANY_ADDR, CREATE_PROPOSAL_PERMISSION_ID);

    // Step 2: Grant CREATE_PROPOSAL permission based on proposerHatId configuration
    if (parameters.stage1.proposerHatId != 0) {
      // Hat-based permissions: Any address wearing the proposer hat can create proposals
      // Use HatsCondition from TokenVotingHats to check hat eligibility
      dao.grantWithCondition(
        sppPlugin,
        ANY_ADDR,
        CREATE_PROPOSAL_PERMISSION_ID,
        IPermissionCondition(deployment.hatsCondition)
      );
    } else {
      // Direct grant: Only controllerAddress can create proposals
      dao.grant(sppPlugin, parameters.stage1.controllerAddress, CREATE_PROPOSAL_PERMISSION_ID);
    }

    // Step 3: Grant SPP permission to create proposals in TokenVotingHats for Stage 2
    // This allows SPP to create sub-proposals when advancing to the voting stage
    dao.grant(address(deployment.tokenVotingPlugin), sppPlugin, CREATE_PROPOSAL_PERMISSION_ID);

    // Grant EXECUTE_PROPOSAL permission to SPP plugin so it can execute on the DAO
    dao.grant(address(dao), sppPlugin, EXECUTE_PROPOSAL_PERMISSION_ID);
  }

  function _grantApplyInstallationPermissions(DAO dao) internal {
    dao.grant(address(dao), address(parameters.pluginSetupProcessor), dao.ROOT_PERMISSION_ID());
    dao.grant(
      address(parameters.pluginSetupProcessor),
      address(this),
      parameters.pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID()
    );
  }

  function _revokeApplyInstallationPermissions(DAO dao) internal {
    dao.revoke(
      address(parameters.pluginSetupProcessor),
      address(this),
      parameters.pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID()
    );
    dao.revoke(address(dao), address(parameters.pluginSetupProcessor), dao.ROOT_PERMISSION_ID());
  }

  function _revokeOwnerPermission(DAO dao) internal {
    dao.revoke(address(dao), address(this), dao.EXECUTE_PERMISSION_ID());
    dao.revoke(address(dao), address(this), dao.ROOT_PERMISSION_ID());
  }

  function getDeploymentParameters() public view returns (DeploymentParameters memory) {
    return parameters;
  }

  function getDeployment() public view returns (Deployment memory) {
    return deployment;
  }
}
