// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { DAOFactory } from "@aragon/osx/framework/dao/DAOFactory.sol";
import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { PermissionManager } from "@aragon/osx/core/permission/PermissionManager.sol";
import { PermissionLib } from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { IPluginSetup } from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import { hashHelpers, PluginSetupRef } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import { VotingEscrowV1_2_0 as VotingEscrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { ClockV1_2_0 as Clock } from "@clock/Clock_v1_2_0.sol";
import { LockV1_2_0 as Lock } from "@lock/Lock_v1_2_0.sol";
import { LinearIncreasingCurve as Curve } from "@curve/LinearIncreasingCurve.sol";
import { DynamicExitQueue as ExitQueue } from "@queue/DynamicExitQueue.sol";
import { EscrowIVotesAdapter } from "@delegation/EscrowIVotesAdapter.sol";
import { AddressGaugeVoter } from "@voting/AddressGaugeVoter.sol";

import { VESystemSetup, VESystemSetupParams } from "./VESystemSetup.sol";
import { TokenVotingSetupHats } from "@token-voting-hats/TokenVotingSetupHats.sol";
import { TokenVotingHats } from "@token-voting-hats/TokenVotingHats.sol";
import { AdminSetup } from "@admin-plugin/AdminSetup.sol";
import { Admin } from "@admin-plugin/Admin.sol";
import { MajorityVotingBase } from "@token-voting-hats/base/MajorityVotingBase.sol";
import { IPlugin } from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import { GovernanceERC20 } from "@token-voting-hats/erc20/GovernanceERC20.sol";

/// @notice DAO configuration parameters
struct DaoConfig {
  string metadataUri;
  string subdomain;
}

/// @notice Comprehensive VE system configuration
struct VeSystemConfig {
  // Underlying token
  address underlyingToken;
  uint256 minDeposit;
  // VE token naming
  string veTokenName;
  string veTokenSymbol;
  // Voting escrow settings
  uint48 minLockDuration;
  uint16 feePercent;
  uint48 cooldownPeriod;
  // Voting power curve parameters
  int256 curveConstant;
  int256 curveLinear;
  int256 curveQuadratic;
  uint48 curveMaxEpochs;
}

/// @notice Token voting hats plugin configuration (flattened for ease of use)
struct TokenVotingHatsPluginConfig {
  // Governance settings
  MajorityVotingBase.VotingMode votingMode;
  uint32 supportThreshold;
  uint32 minParticipation;
  uint64 minDuration;
  uint256 minProposerVotingPower;
  // Hats Protocol settings
  uint256 proposerHatId;
  uint256 voterHatId;
  uint256 executorHatId;
}

/// @notice The struct containing all the parameters to deploy the DAO
struct DeploymentParameters {
  // Configuration structs
  DaoConfig dao;
  VeSystemConfig veSystem;
  TokenVotingHatsPluginConfig tokenVotingHats;

  // Plugin setup contracts (must be deployed first)
  VESystemSetup veSystemSetup;
  TokenVotingSetupHats tokenVotingSetup;
  PluginRepo tokenVotingPluginRepo;
  AdminSetup adminSetup;
  PluginRepo adminPluginRepo;
  address adminAddress;

  // Plugin metadata
  string tokenVotingHatsMetadata;

  // Plugin repo version info
  uint8 pluginRepoRelease;
  uint16 pluginRepoBuild;

  // OSx framework addresses (chain-specific)
  address osxDaoFactory;
  PluginSetupProcessor pluginSetupProcessor;
  PluginRepoFactory pluginRepoFactory;
}

/// @notice Struct containing all VE system components
struct VEPluginSet {
  VotingEscrow votingEscrow;
  Clock clock;
  Curve curve;
  ExitQueue exitQueue;
  Lock nftLock;
  EscrowIVotesAdapter ivotesAdapter;
  AddressGaugeVoter voter;
}

/// @notice Contains the artifacts that resulted from running a deployment
struct Deployment {
  DAO dao;
  VEPluginSet veSystem;
  TokenVotingHats tokenVotingPlugin;
  PluginRepo tokenVotingPluginRepo;
  Admin adminPlugin;
  PluginRepo adminPluginRepo;
}

/// @notice A singleton contract designed to run the deployment once and become a read-only store of the contracts
/// deployed
contract VETokenVotingDaoFactory {
  address public immutable deployer;

  function version() external pure returns (string memory) {
    return "1.0.0";
  }

  error AlreadyDeployed();
  error Unauthorized();

  DeploymentParameters parameters;
  Deployment deployment;

  constructor(DeploymentParameters memory _parameters) {
    // Record the deployer to prevent unauthorized deployments
    deployer = msg.sender;

    // Configuration structs
    parameters.dao = _parameters.dao;
    parameters.veSystem = _parameters.veSystem;
    parameters.tokenVotingHats = _parameters.tokenVotingHats;

    // Plugin setup contracts
    parameters.veSystemSetup = _parameters.veSystemSetup;
    parameters.tokenVotingSetup = _parameters.tokenVotingSetup;
    parameters.tokenVotingPluginRepo = _parameters.tokenVotingPluginRepo;
    parameters.adminSetup = _parameters.adminSetup;
    parameters.adminPluginRepo = _parameters.adminPluginRepo;
    parameters.adminAddress = _parameters.adminAddress;

    // Plugin metadata
    parameters.tokenVotingHatsMetadata = _parameters.tokenVotingHatsMetadata;

    // Plugin repo version info
    parameters.pluginRepoRelease = _parameters.pluginRepoRelease;
    parameters.pluginRepoBuild = _parameters.pluginRepoBuild;

    // OSx framework addresses
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

    VEPluginSet memory veSystem = _deployVESystem(dao);
    deployment.veSystem = veSystem;

    (TokenVotingHats tvPlugin, PluginRepo tvRepo) = _installTokenVotingHats(dao, veSystem);
    deployment.tokenVotingPlugin = tvPlugin;
    deployment.tokenVotingPluginRepo = tvRepo;

    (Admin adminPlugin, PluginRepo adminRepo) = _installAdminPlugin(dao);
    deployment.adminPlugin = adminPlugin;
    deployment.adminPluginRepo = adminRepo;

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

  function _deployVESystem(DAO dao) internal returns (VEPluginSet memory veSystem) {
    VESystemSetupParams memory setupParams = VESystemSetupParams({
      underlyingToken: parameters.veSystem.underlyingToken,
      veTokenName: parameters.veSystem.veTokenName,
      veTokenSymbol: parameters.veSystem.veTokenSymbol,
      minDeposit: parameters.veSystem.minDeposit,
      minLockDuration: parameters.veSystem.minLockDuration,
      feePercent: parameters.veSystem.feePercent,
      cooldownPeriod: parameters.veSystem.cooldownPeriod,
      curveConstant: parameters.veSystem.curveConstant,
      curveLinear: parameters.veSystem.curveLinear,
      curveQuadratic: parameters.veSystem.curveQuadratic,
      curveMaxEpochs: parameters.veSystem.curveMaxEpochs
    });

    (address escrowProxy, IPluginSetup.PreparedSetupData memory preparedSetupData) =
      parameters.veSystemSetup.prepareInstallation(address(dao), abi.encode(setupParams));

    veSystem.votingEscrow = VotingEscrow(escrowProxy);
    veSystem.clock = Clock(preparedSetupData.helpers[0]);
    veSystem.curve = Curve(preparedSetupData.helpers[1]);
    veSystem.exitQueue = ExitQueue(preparedSetupData.helpers[2]);
    veSystem.nftLock = Lock(preparedSetupData.helpers[3]);
    veSystem.ivotesAdapter = EscrowIVotesAdapter(preparedSetupData.helpers[4]);
    veSystem.voter = AddressGaugeVoter(preparedSetupData.helpers[5]);

    for (uint256 i = 0; i < preparedSetupData.permissions.length; i++) {
      PermissionLib.MultiTargetPermission memory perm = preparedSetupData.permissions[i];
      if (perm.operation == PermissionLib.Operation.Grant) {
        dao.grant(perm.where, perm.who, perm.permissionId);
      } else if (perm.operation == PermissionLib.Operation.Revoke) {
        dao.revoke(perm.where, perm.who, perm.permissionId);
      }
    }

    // Temporarily grant factory ESCROW_ADMIN_ROLE to wire components
    dao.grant(address(veSystem.votingEscrow), address(this), veSystem.votingEscrow.ESCROW_ADMIN_ROLE());

    // Wire up VE components
    veSystem.votingEscrow.setCurve(address(veSystem.curve));
    veSystem.votingEscrow.setQueue(address(veSystem.exitQueue));
    veSystem.votingEscrow.setLockNFT(address(veSystem.nftLock));
    veSystem.votingEscrow.setIVotesAdapter(address(veSystem.ivotesAdapter));
    veSystem.votingEscrow.setVoter(address(veSystem.voter));

    // Revoke temporary permission
    dao.revoke(address(veSystem.votingEscrow), address(this), veSystem.votingEscrow.ESCROW_ADMIN_ROLE());
  }

  function _installTokenVotingHats(DAO dao, VEPluginSet memory veSystem)
    internal
    returns (TokenVotingHats plugin, PluginRepo pluginRepo)
  {
    if (address(parameters.tokenVotingPluginRepo) == address(0)) {
      pluginRepo = PluginRepoFactory(parameters.pluginRepoFactory)
        .createPluginRepoWithFirstVersion(
          "token-voting-hats", address(parameters.tokenVotingSetup), address(dao), " ", " "
        );
    } else {
      pluginRepo = parameters.tokenVotingPluginRepo;
    }

    PluginRepo.Tag memory repoTag = PluginRepo.Tag(parameters.pluginRepoRelease, parameters.pluginRepoBuild);

    bytes memory installData = parameters.tokenVotingSetup
      .encodeInstallationParametersHats(
        MajorityVotingBase.VotingSettings({
          votingMode: parameters.tokenVotingHats.votingMode,
          supportThreshold: parameters.tokenVotingHats.supportThreshold,
          minParticipation: parameters.tokenVotingHats.minParticipation,
          minDuration: parameters.tokenVotingHats.minDuration,
          minProposerVotingPower: parameters.tokenVotingHats.minProposerVotingPower
        }),
        TokenVotingSetupHats.TokenSettings({ addr: address(veSystem.ivotesAdapter), name: "", symbol: "" }),
        GovernanceERC20.MintSettings({
          receivers: new address[](0), amounts: new uint256[](0), ensureDelegationOnMint: false
        }),
        IPlugin.TargetConfig({ target: address(dao), operation: IPlugin.Operation.Call }),
        0,
        bytes(parameters.tokenVotingHatsMetadata),
        new address[](0),
        TokenVotingSetupHats.HatsConfig({
          proposerHatId: parameters.tokenVotingHats.proposerHatId,
          voterHatId: parameters.tokenVotingHats.voterHatId,
          executorHatId: parameters.tokenVotingHats.executorHatId
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
  }

  function _installAdminPlugin(DAO dao) internal returns (Admin plugin, PluginRepo pluginRepo) {
    pluginRepo = parameters.adminPluginRepo;

    // Use release 1, build 2 (latest admin plugin version)
    PluginRepo.Tag memory repoTag = PluginRepo.Tag(1, 2);

    // Encode installation parameters: admin address and target config
    bytes memory installData = abi.encode(
      parameters.adminAddress, IPlugin.TargetConfig({ target: address(dao), operation: IPlugin.Operation.Call })
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

  // ============================================================
  // IMPORTANT: DO NOT USE THESE GETTERS WITHOUT APPROVAL
  // ============================================================
  // These dedicated getter functions are provided for future use.
  // They are NOT deployed in the current test factory contract.
  // DO NOT call these from scripts until explicitly approved
  // by the developer. Use the temporary helper contract approach
  // in DeploySubDao.s.sol instead.
  // ============================================================

  function getIVotesAdapter() public view returns (address) {
    return address(deployment.veSystem.ivotesAdapter);
  }

  function getTokenVotingPluginRepo() public view returns (address) {
    return address(deployment.tokenVotingPluginRepo);
  }

  function getProposerHatId() public view returns (uint256) {
    return parameters.tokenVotingHats.proposerHatId;
  }

  function getVoterHatId() public view returns (uint256) {
    return parameters.tokenVotingHats.voterHatId;
  }

  function getExecutorHatId() public view returns (uint256) {
    return parameters.tokenVotingHats.executorHatId;
  }

  function getPluginRepoRelease() public view returns (uint8) {
    return parameters.pluginRepoRelease;
  }

  function getPluginRepoBuild() public view returns (uint16) {
    return parameters.pluginRepoBuild;
  }

  function getTokenVotingSetup() public view returns (TokenVotingSetupHats) {
    return parameters.tokenVotingSetup;
  }
}
