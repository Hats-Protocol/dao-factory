// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";

import {TokenVotingSetupHats} from "@token-voting-hats/TokenVotingSetupHats.sol";
import {TokenVotingHats} from "@token-voting-hats/TokenVotingHats.sol";
import {AdminSetup} from "@admin-plugin/AdminSetup.sol";
import {Admin} from "@admin-plugin/Admin.sol";
import {MajorityVotingBase} from "@token-voting-hats/base/MajorityVotingBase.sol";
import {GovernanceERC20} from "@token-voting-hats/erc20/GovernanceERC20.sol";

import {VETokenVotingDaoFactory} from "./VETokenVotingDaoFactory.sol";

/// @notice DAO configuration parameters
struct DaoConfig {
  string metadataUri;
  string subdomain;
}

/// @notice Admin plugin configuration
struct AdminPluginConfig {
  address adminAddress;
}

/// @notice Stage 1 configuration (veto-voting stage)
struct Stage1Config {
  address proposerAddress;
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

  // Main DAO address (to query IVotesAdapter)
  address mainDaoAddress;
  // Main DAO factory address (to query IVotesAdapter via factory)
  address mainDaoFactoryAddress;

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
}

/// @notice A singleton contract designed to run the deployment once and become a read-only store of the contracts deployed
contract ApproverHatMinterSubDaoFactory {
  address public immutable deployer;

  function version() external pure returns (string memory) {
    return "1.0.0";
  }

  error AlreadyDeployed();
  error Unauthorized();
  error InvalidMainDaoAddress();
  error InvalidIVotesAdapterAddress();

  DeploymentParameters parameters;
  Deployment deployment;

  constructor(DeploymentParameters memory _parameters) {
    deployer = msg.sender;

    parameters.dao = _parameters.dao;
    parameters.adminPlugin = _parameters.adminPlugin;
    parameters.stage1 = _parameters.stage1;
    parameters.stage2 = _parameters.stage2;
    parameters.sppPlugin = _parameters.sppPlugin;
    parameters.mainDaoAddress = _parameters.mainDaoAddress;
    parameters.mainDaoFactoryAddress = _parameters.mainDaoFactoryAddress;
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

    // Get IVotesAdapter address from main DAO
    address ivotesAdapter = _getIVotesAdapterFromMainDao();
    if (ivotesAdapter == address(0)) revert InvalidIVotesAdapterAddress();

    // Install TokenVotingHats plugin (for Stage 2)
    (TokenVotingHats tvPlugin, PluginRepo tvRepo) = _installTokenVotingHats(dao, ivotesAdapter);
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
      parameters.adminPlugin.adminAddress, IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call})
    );

    (address pluginAddress, IPluginSetup.PreparedSetupData memory preparedSetupData) = parameters.pluginSetupProcessor
      .prepareInstallation(
        address(dao),
        PluginSetupProcessor.PrepareInstallationParams({
          pluginSetupRef: PluginSetupRef(repoTag, pluginRepo),
          data: installData
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

    bytes memory installData = parameters.tokenVotingSetup.encodeInstallationParametersHats(
      MajorityVotingBase.VotingSettings({
        votingMode: parameters.stage2.tokenVotingHats.votingMode,
        supportThreshold: parameters.stage2.tokenVotingHats.supportThreshold,
        minParticipation: parameters.stage2.tokenVotingHats.minParticipation,
        minDuration: parameters.stage2.tokenVotingHats.minDuration,
        minProposerVotingPower: parameters.stage2.tokenVotingHats.minProposerVotingPower
      }),
      TokenVotingSetupHats.TokenSettings({addr: ivotesAdapter, name: "", symbol: ""}),
      GovernanceERC20.MintSettings({receivers: new address[](0), amounts: new uint256[](0), ensureDelegationOnMint: false}),
      IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call}),
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
          pluginSetupRef: PluginSetupRef(repoTag, pluginRepo),
          data: installData
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
  }

  function _installSppPlugin(DAO dao, address tokenVotingHatsPlugin)
    internal
    returns (address sppPlugin, PluginRepo sppPluginRepo)
  {
    sppPluginRepo = parameters.sppPluginRepo;
    if (address(sppPluginRepo) == address(0)) {
      sppPluginRepo = PluginRepoFactory(parameters.pluginRepoFactory)
        .createPluginRepoWithFirstVersion(
          "staged-proposal-processor-subdao",
          parameters.sppPluginSetup,
          address(dao),
          " ",
          " "
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
          pluginSetupRef: PluginSetupRef(repoTag, sppPluginRepo),
          data: installData
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

  function _encodeSppInstallationData(address tokenVotingHatsPlugin) internal view returns (bytes memory) {
    // TODO: This is a placeholder - actual encoding depends on SPP plugin setup interface
    // The plan specifies:
    // Stage 1: {addr: proposerAddress, isManual: true, tryAdvance: true, resultType: Veto}
    //   approvalThreshold: 0, vetoThreshold: 1, cancelable: true, editable: true
    // Stage 2: {addr: tokenVotingHatsPluginAddress, isManual: false, tryAdvance: false, resultType: Veto}
    //   approvalThreshold: 0, vetoThreshold: 1, cancelable: false, editable: false
    //
    // The actual SPP plugin setup contract should have a method like:
    //   function encodeSetupData(SppSetupParams memory params) external pure returns (bytes memory);
    //
    // For now, we'll encode a placeholder structure that needs to be updated once
    // the actual SPP plugin setup interface is known.

    // Try to use the SPP setup contract's encode method if available
    // If the setup contract exposes an encodeSetupData function, we should call it here
    // For now, we use placeholder encoding

    // Placeholder encoding - this MUST be updated to match actual SPP setup interface
    // Expected structure (example):
    // struct Stage {
    //   address body;
    //   bool isManual;
    //   bool tryAdvance;
    //   uint8 resultType; // 0 = Approval, 1 = Veto
    //   uint32 approvalThreshold;
    //   uint32 vetoThreshold;
    //   bool cancelable;
    //   bool editable;
    //   uint48 minAdvance;
    //   uint48 maxAdvance;
    //   uint48 voteDuration;
    // }
    // struct SppSetupParams {
    //   Stage[] stages;
    //   string metadata;
    // }

    // Encode Stage 1
    bytes memory stage1 = abi.encode(
      parameters.stage1.proposerAddress, // body
      true, // isManual
      true, // tryAdvance
      uint8(1), // resultType: Veto
      uint32(0), // approvalThreshold
      uint32(1), // vetoThreshold
      true, // cancelable
      true, // editable
      parameters.stage1.minAdvance,
      parameters.stage1.maxAdvance,
      parameters.stage1.voteDuration
    );

    // Encode Stage 2
    bytes memory stage2 = abi.encode(
      tokenVotingHatsPlugin, // body
      false, // isManual
      false, // tryAdvance
      uint8(1), // resultType: Veto
      uint32(0), // approvalThreshold
      uint32(1), // vetoThreshold
      false, // cancelable
      false, // editable
      parameters.stage2.minAdvance,
      parameters.stage2.maxAdvance,
      parameters.stage2.voteDuration
    );

    // Encode as array of stages + metadata
    // TODO: Replace with actual SPP setup encoding once interface is known
    // This might need to call a helper function on the SPP setup contract like:
    //   return ISppPluginSetup(parameters.sppPluginSetup).encodeSetupData(stages, metadata);
    return abi.encode(abi.encodePacked(stage1, stage2), parameters.sppPlugin.metadata);
  }

  function _grantSppPermissions(DAO dao, address sppPlugin) internal {
    // Grant CREATE_PROPOSAL_PERMISSION_ID to Stage 1 proposer address
    // This typically requires a condition check (SPPRuleCondition)
    // For now, we grant directly - actual implementation may need condition-based permissions

    // Grant EXECUTE_PROPOSAL_PERMISSION_ID to SPP plugin
    // Note: Permission IDs depend on SPP plugin implementation
    // Assuming standard permission IDs:
    bytes32 CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");
    bytes32 EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION");

    dao.grant(sppPlugin, parameters.stage1.proposerAddress, CREATE_PROPOSAL_PERMISSION_ID);
    dao.grant(address(dao), sppPlugin, EXECUTE_PROPOSAL_PERMISSION_ID);
  }

  function _getIVotesAdapterFromMainDao() internal view returns (address ivotesAdapter) {
    // Try to get IVotesAdapter from main DAO factory deployment first
    if (parameters.mainDaoFactoryAddress != address(0)) {
      try VETokenVotingDaoFactory(parameters.mainDaoFactoryAddress).getDeployment() returns (
        VETokenVotingDaoFactory.Deployment memory mainDeployment
      ) {
        if (address(mainDeployment.veSystem.ivotesAdapter) != address(0)) {
          return address(mainDeployment.veSystem.ivotesAdapter);
        }
      } catch {
        // Factory query failed, try direct DAO address
      }
    }

    // Fallback: try to get from main DAO address directly
    // This would require the main DAO to expose a getter for IVotesAdapter
    // For now, we require factory approach
    if (parameters.mainDaoAddress != address(0)) {
      // TODO: If main DAO exposes IVotesAdapter via a getter interface, query it here
      // For example: IVotesAdapterGetter(parameters.mainDaoAddress).getIVotesAdapter()
      revert InvalidIVotesAdapterAddress();
    }

    revert InvalidIVotesAdapterAddress();
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
