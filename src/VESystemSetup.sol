// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { PluginSetup } from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";
import { IPluginSetup } from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import { PermissionLib } from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import { VotingEscrowV1_2_0 as VotingEscrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { ClockV1_2_0 as Clock } from "@clock/Clock_v1_2_0.sol";
import { LockV1_2_0 as Lock } from "@lock/Lock_v1_2_0.sol";
import { LinearIncreasingCurve as Curve } from "@curve/LinearIncreasingCurve.sol";
import { DynamicExitQueue as ExitQueue } from "@queue/DynamicExitQueue.sol";
import { EscrowIVotesAdapter } from "@delegation/EscrowIVotesAdapter.sol";

/// @notice Parameters for VE system deployment
/// @param underlyingToken The ERC20 token to lock in the VotingEscrow
/// @param veTokenName The name for the veToken NFT
/// @param veTokenSymbol The symbol for the veToken NFT
/// @param minDeposit The minimum amount of tokens required to create a lock
/// @param minLockDuration Min seconds a user must have locked before they can queue an exit
/// @param feePercent The fee taken on withdrawals (1 ether = 100%)
/// @param cooldownPeriod Delay seconds after queuing an exit before withdrawing becomes possible
/// @param curveConstant Constant coefficient for voting power curve (1e18 for flat curve)
/// @param curveLinear Linear coefficient for voting power curve (0 for flat curve)
/// @param curveQuadratic Quadratic coefficient for voting power curve (0 for flat curve)
/// @param curveMaxEpochs Maximum epochs for curve (0 for flat curve)
struct VESystemSetupParams {
  address underlyingToken;
  string veTokenName;
  string veTokenSymbol;
  uint256 minDeposit;
  uint48 minLockDuration;
  uint16 feePercent;
  uint48 cooldownPeriod;
  int256 curveConstant;
  int256 curveLinear;
  int256 curveQuadratic;
  uint48 curveMaxEpochs;
}

/// @notice PluginSetup for deploying a complete VE (Voting Escrow) system
/// @dev This setup deploys all VE components: VotingEscrow, Clock, Curve, ExitQueue, Lock, and IVotesAdapter
contract VESystemSetup is PluginSetup {
  using ProxyLib for address;

  /// @notice Thrown if passed helpers array is of wrong length
  error WrongHelpersArrayLength(uint256 length);

  /// @notice Base implementation contracts (deployed separately, reused via proxies)
  address public immutable clockBase;
  address public immutable escrowBase;
  address public immutable curveBase;
  address public immutable queueBase;
  address public immutable nftBase;
  address public immutable ivotesAdapterBase;

  /// @notice Initializes VESystemSetup with pre-deployed base implementation contracts
  /// @param _clockBase Address of deployed Clock implementation
  /// @param _escrowBase Address of deployed VotingEscrow implementation
  /// @param _curveBase Address of deployed Curve implementation (with specific curve params)
  /// @param _queueBase Address of deployed ExitQueue implementation
  /// @param _nftBase Address of deployed Lock implementation
  /// @param _ivotesAdapterBase Address of deployed IVotesAdapter implementation (with specific curve params)
  constructor(
    address _clockBase,
    address _escrowBase,
    address _curveBase,
    address _queueBase,
    address _nftBase,
    address _ivotesAdapterBase
  ) PluginSetup(_escrowBase) {
    clockBase = _clockBase;
    escrowBase = _escrowBase;
    curveBase = _curveBase;
    queueBase = _queueBase;
    nftBase = _nftBase;
    ivotesAdapterBase = _ivotesAdapterBase;
  }

  /// @notice Prepares the installation of a VE system
  /// @param _dao The DAO address
  /// @param _data The encoded VESystemSetupParams
  /// @return plugin The "plugin" address (VotingEscrow contract)
  /// @return preparedSetupData The prepared setup data including helpers and permissions
  function prepareInstallation(address _dao, bytes calldata _data)
    external
    returns (address plugin, PreparedSetupData memory preparedSetupData)
  {
    VESystemSetupParams memory params = abi.decode(_data, (VESystemSetupParams));

    // Deploy all VE components as proxies
    address clockProxy;
    address escrowProxy;
    address curveProxy;
    address queueProxy;
    address nftProxy;
    address adapterProxy;

    {
      clockProxy = clockBase.deployUUPSProxy(abi.encodeCall(Clock.initialize, (address(_dao))));
    }

    {
      escrowProxy = escrowBase.deployUUPSProxy(
        abi.encodeCall(VotingEscrow.initialize, (params.underlyingToken, address(_dao), clockProxy, params.minDeposit))
      );
    }

    {
      // Use pre-deployed Curve base (already has curve parameters baked in)
      curveProxy = curveBase.deployUUPSProxy(abi.encodeCall(Curve.initialize, (escrowProxy, address(_dao), clockProxy)));
    }

    {
      queueProxy = queueBase.deployUUPSProxy(
        abi.encodeCall(
          ExitQueue.initialize,
          (escrowProxy, params.cooldownPeriod, address(_dao), params.feePercent, clockProxy, params.minLockDuration)
        )
      );
    }

    {
      nftProxy = nftBase.deployUUPSProxy(
        abi.encodeCall(Lock.initialize, (escrowProxy, params.veTokenName, params.veTokenSymbol, address(_dao)))
      );
    }

    {
      // Use pre-deployed IVotesAdapter base (already has curve parameters baked in)
      adapterProxy = ivotesAdapterBase.deployUUPSProxy(
        abi.encodeCall(EscrowIVotesAdapter.initialize, (address(_dao), escrowProxy, clockProxy, false))
      );
    }

    // NOTE: Components are NOT wired together here - the factory will do that
    // after granting itself the necessary permissions

    // The "plugin" for OSx purposes is the VotingEscrow (main entry point)
    plugin = escrowProxy;

    // Return all components as helpers (factory will need them for permissions)
    address[] memory helpers = new address[](5);
    helpers[0] = clockProxy; // index 0: Clock
    helpers[1] = curveProxy; // index 1: Curve
    helpers[2] = queueProxy; // index 2: ExitQueue
    helpers[3] = nftProxy; // index 3: Lock
    helpers[4] = adapterProxy; // index 4: IVotesAdapter

    // Define permissions that need to be granted
    PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](13);

    // VotingEscrow permissions (plugin is escrow)
    permissions[0] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Grant,
      where: plugin,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: VotingEscrow(plugin).ESCROW_ADMIN_ROLE()
    });

    permissions[1] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Grant,
      where: plugin,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: VotingEscrow(plugin).PAUSER_ROLE()
    });

    permissions[2] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Grant,
      where: plugin,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: VotingEscrow(plugin).SWEEPER_ROLE()
    });

    // Curve permissions
    permissions[3] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Grant,
      where: curveProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: Curve(curveProxy).CURVE_ADMIN_ROLE()
    });

    // ExitQueue permissions
    permissions[4] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Grant,
      where: queueProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: ExitQueue(queueProxy).QUEUE_ADMIN_ROLE()
    });

    permissions[5] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Grant,
      where: queueProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: ExitQueue(queueProxy).WITHDRAW_ROLE()
    });

    // Lock permissions
    permissions[6] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Grant,
      where: nftProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: Lock(nftProxy).LOCK_ADMIN_ROLE()
    });

    // IVotesAdapter permissions
    permissions[7] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Grant,
      where: adapterProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: EscrowIVotesAdapter(adapterProxy).DELEGATION_ADMIN_ROLE()
    });

    permissions[8] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Grant,
      where: adapterProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: EscrowIVotesAdapter(adapterProxy).DELEGATION_TOKEN_ROLE()
    });

    // Component cross-permissions (components need to call each other)
    permissions[9] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Grant,
      where: plugin,
      who: queueProxy,
      condition: PermissionLib.NO_CONDITION,
      permissionId: VotingEscrow(plugin).ESCROW_ADMIN_ROLE()
    });

    permissions[10] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Grant,
      where: plugin,
      who: nftProxy,
      condition: PermissionLib.NO_CONDITION,
      permissionId: VotingEscrow(plugin).ESCROW_ADMIN_ROLE()
    });

    permissions[11] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Grant,
      where: nftProxy,
      who: plugin,
      condition: PermissionLib.NO_CONDITION,
      permissionId: Lock(nftProxy).LOCK_ADMIN_ROLE()
    });

    permissions[12] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Grant,
      where: adapterProxy,
      who: plugin,
      condition: PermissionLib.NO_CONDITION,
      permissionId: EscrowIVotesAdapter(adapterProxy).DELEGATION_TOKEN_ROLE()
    });

    preparedSetupData = PreparedSetupData({ helpers: helpers, permissions: permissions });
  }

  /// @notice Prepares the uninstallation of a VE system
  /// @param _dao The DAO address
  /// @param _payload The uninstallation payload
  /// @return permissions The permissions to be revoked
  function prepareUninstallation(address _dao, SetupPayload calldata _payload)
    external
    view
    returns (PermissionLib.MultiTargetPermission[] memory permissions)
  {
    if (_payload.currentHelpers.length != 5) {
      revert WrongHelpersArrayLength(_payload.currentHelpers.length);
    }

    address escrowProxy = _payload.plugin;
    // clockProxy = _payload.currentHelpers[0] - not needed, Clock has no permissions to revoke
    address curveProxy = _payload.currentHelpers[1];
    address queueProxy = _payload.currentHelpers[2];
    address nftProxy = _payload.currentHelpers[3];
    address adapterProxy = _payload.currentHelpers[4];

    // Revoke all permissions granted during installation
    permissions = new PermissionLib.MultiTargetPermission[](13);

    // Revoke VotingEscrow permissions
    permissions[0] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Revoke,
      where: escrowProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: VotingEscrow(escrowProxy).ESCROW_ADMIN_ROLE()
    });

    permissions[1] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Revoke,
      where: escrowProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: VotingEscrow(escrowProxy).PAUSER_ROLE()
    });

    permissions[2] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Revoke,
      where: escrowProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: VotingEscrow(escrowProxy).SWEEPER_ROLE()
    });

    // Revoke Curve permissions
    permissions[3] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Revoke,
      where: curveProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: Curve(curveProxy).CURVE_ADMIN_ROLE()
    });

    // Revoke ExitQueue permissions
    permissions[4] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Revoke,
      where: queueProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: ExitQueue(queueProxy).QUEUE_ADMIN_ROLE()
    });

    permissions[5] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Revoke,
      where: queueProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: ExitQueue(queueProxy).WITHDRAW_ROLE()
    });

    // Revoke Lock permissions
    permissions[6] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Revoke,
      where: nftProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: Lock(nftProxy).LOCK_ADMIN_ROLE()
    });

    // Revoke IVotesAdapter permissions
    permissions[7] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Revoke,
      where: adapterProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: EscrowIVotesAdapter(adapterProxy).DELEGATION_ADMIN_ROLE()
    });

    permissions[8] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Revoke,
      where: adapterProxy,
      who: _dao,
      condition: PermissionLib.NO_CONDITION,
      permissionId: EscrowIVotesAdapter(adapterProxy).DELEGATION_TOKEN_ROLE()
    });

    // Revoke component cross-permissions
    permissions[9] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Revoke,
      where: escrowProxy,
      who: queueProxy,
      condition: PermissionLib.NO_CONDITION,
      permissionId: VotingEscrow(escrowProxy).ESCROW_ADMIN_ROLE()
    });

    permissions[10] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Revoke,
      where: escrowProxy,
      who: nftProxy,
      condition: PermissionLib.NO_CONDITION,
      permissionId: VotingEscrow(escrowProxy).ESCROW_ADMIN_ROLE()
    });

    permissions[11] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Revoke,
      where: nftProxy,
      who: escrowProxy,
      condition: PermissionLib.NO_CONDITION,
      permissionId: Lock(nftProxy).LOCK_ADMIN_ROLE()
    });

    permissions[12] = PermissionLib.MultiTargetPermission({
      operation: PermissionLib.Operation.Revoke,
      where: adapterProxy,
      who: escrowProxy,
      condition: PermissionLib.NO_CONDITION,
      permissionId: EscrowIVotesAdapter(adapterProxy).DELEGATION_TOKEN_ROLE()
    });
  }
}
