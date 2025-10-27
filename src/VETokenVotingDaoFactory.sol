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
import {
    hashHelpers,
    PluginSetupRef
} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import {VotingEscrowV1_2_0 as VotingEscrow} from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import {ClockV1_2_0 as Clock} from "@clock/Clock_v1_2_0.sol";
import {LockV1_2_0 as Lock} from "@lock/Lock_v1_2_0.sol";
import {LinearIncreasingCurve as Curve} from "@curve/LinearIncreasingCurve.sol";
import {DynamicExitQueue as ExitQueue} from "@queue/DynamicExitQueue.sol";
import {EscrowIVotesAdapter} from "@delegation/EscrowIVotesAdapter.sol";

import {VESystemSetup, VESystemSetupParams} from "./VESystemSetup.sol";
import {TokenVotingSetupHats} from "@token-voting-hats/TokenVotingSetupHats.sol";
import {TokenVotingHats} from "@token-voting-hats/TokenVotingHats.sol";
import {MajorityVotingBase} from "@token-voting-hats/base/MajorityVotingBase.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {GovernanceERC20} from "@token-voting-hats/erc20/GovernanceERC20.sol";


/// @notice The struct containing all the parameters to deploy the DAO
struct DeploymentParameters {
    // DAO settings
    address daoExecutor;
    string daoMetadataURI;
    string daoSubdomain;

    // VE token parameters
    address underlyingToken;
    string veTokenName;
    string veTokenSymbol;
    uint256 minDeposit;

    // VE system settings (fixed for flat curve)
    uint48 minLockDuration;
    uint16 feePercent;
    uint48 cooldownPeriod;

    // Hats configuration
    uint256 proposerHatId;
    uint256 voterHatId;
    uint256 executorHatId;

    // Plugin setup contracts (must be deployed first)
    VESystemSetup veSystemSetup;
    TokenVotingSetupHats tokenVotingSetup;
    PluginRepo tokenVotingPluginRepo;

    // OSx addresses (chain-specific)
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
}

/// @notice Contains the artifacts that resulted from running a deployment
struct Deployment {
    DAO dao;
    VEPluginSet veSystem;
    TokenVotingHats tokenVotingPlugin;
    PluginRepo tokenVotingPluginRepo;
}

/// @notice A singleton contract designed to run the deployment once and become a read-only store of the contracts deployed
contract VETokenVotingDaoFactory {
    // Flat curve configuration constants - 1:1 ratio (1 token locked = 1 vote)
    int256 constant CURVE_CONSTANT_COEFF = 1e18;
    int256 constant CURVE_LINEAR_COEFF = 0;
    int256 constant CURVE_QUADRATIC_COEFF = 0;
    uint48 constant CURVE_MAX_EPOCHS = 0;

    // Default voting settings (for testing)
    uint32 constant DEFAULT_SUPPORT_THRESHOLD = 10000;   // 1% (10,000 / 1,000,000)
    uint32 constant DEFAULT_MIN_PARTICIPATION = 0;       // 0% (no quorum requirement)
    uint64 constant DEFAULT_MIN_DURATION = 3600;         // 60 minutes (minimum allowed by plugin)
    uint256 constant DEFAULT_MIN_PROPOSER_VOTING_POWER = 0;

    // Plugin repo version
    uint8 constant PLUGIN_REPO_RELEASE = 1;
    uint16 constant PLUGIN_REPO_BUILD = 1;

    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    error AlreadyDeployed();

    DeploymentParameters parameters;
    Deployment deployment;

    constructor(DeploymentParameters memory _parameters) {
        parameters.daoExecutor = _parameters.daoExecutor;
        parameters.daoMetadataURI = _parameters.daoMetadataURI;
        parameters.daoSubdomain = _parameters.daoSubdomain;
        parameters.underlyingToken = _parameters.underlyingToken;
        parameters.veTokenName = _parameters.veTokenName;
        parameters.veTokenSymbol = _parameters.veTokenSymbol;
        parameters.minDeposit = _parameters.minDeposit;
        parameters.minLockDuration = _parameters.minLockDuration;
        parameters.feePercent = _parameters.feePercent;
        parameters.cooldownPeriod = _parameters.cooldownPeriod;
        parameters.proposerHatId = _parameters.proposerHatId;
        parameters.voterHatId = _parameters.voterHatId;
        parameters.executorHatId = _parameters.executorHatId;
        parameters.veSystemSetup = _parameters.veSystemSetup;
        parameters.tokenVotingSetup = _parameters.tokenVotingSetup;
        parameters.tokenVotingPluginRepo = _parameters.tokenVotingPluginRepo;
        parameters.osxDaoFactory = _parameters.osxDaoFactory;
        parameters.pluginSetupProcessor = _parameters.pluginSetupProcessor;
        parameters.pluginRepoFactory = _parameters.pluginRepoFactory;
    }

    function deployOnce() public {
        if (address(deployment.dao) != address(0)) revert AlreadyDeployed();

        DAO dao = _prepareDao();
        deployment.dao = dao;

        _grantApplyInstallationPermissions(dao);

        VEPluginSet memory veSystem = _deployVESystem(dao);
        deployment.veSystem = veSystem;

        (TokenVotingHats tvPlugin, PluginRepo tvRepo) = _installTokenVotingHats(dao, veSystem);
        deployment.tokenVotingPlugin = tvPlugin;
        deployment.tokenVotingPluginRepo = tvRepo;

        _revokeApplyInstallationPermissions(dao);
        _revokeOwnerPermission(dao);
    }

    function _prepareDao() internal returns (DAO dao) {
        (dao, ) = DAOFactory(parameters.osxDaoFactory).createDao(
            DAOFactory.DAOSettings({
                trustedForwarder: address(0),
                daoURI: "",
                subdomain: parameters.daoSubdomain,
                metadata: bytes(parameters.daoMetadataURI)
            }),
            new DAOFactory.PluginSettings[](0)
        );

        address daoExecutor = parameters.daoExecutor;
        Action[] memory actions = new Action[](daoExecutor == address(0) ? 1 : 2);
        actions[0].to = address(dao);
        actions[0].data = abi.encodeCall(
            PermissionManager.grant,
            (address(dao), address(this), dao.ROOT_PERMISSION_ID())
        );

        if (daoExecutor != address(0)) {
            actions[1].to = address(dao);
            actions[1].data = abi.encodeCall(
                PermissionManager.grant,
                (address(dao), daoExecutor, dao.EXECUTE_PERMISSION_ID())
            );
        }

        dao.execute(bytes32(0), actions, 0);
    }

    function _deployVESystem(DAO dao) internal returns (VEPluginSet memory veSystem) {
        VESystemSetupParams memory setupParams = VESystemSetupParams({
            underlyingToken: parameters.underlyingToken,
            veTokenName: parameters.veTokenName,
            veTokenSymbol: parameters.veTokenSymbol,
            minDeposit: parameters.minDeposit,
            minLockDuration: parameters.minLockDuration,
            feePercent: parameters.feePercent,
            cooldownPeriod: parameters.cooldownPeriod,
            curveConstant: CURVE_CONSTANT_COEFF,
            curveLinear: CURVE_LINEAR_COEFF,
            curveQuadratic: CURVE_QUADRATIC_COEFF,
            curveMaxEpochs: CURVE_MAX_EPOCHS
        });

        (address escrowProxy, IPluginSetup.PreparedSetupData memory preparedSetupData) =
            parameters.veSystemSetup.prepareInstallation(address(dao), abi.encode(setupParams));

        veSystem.votingEscrow = VotingEscrow(escrowProxy);
        veSystem.clock = Clock(preparedSetupData.helpers[0]);
        veSystem.curve = Curve(preparedSetupData.helpers[1]);
        veSystem.exitQueue = ExitQueue(preparedSetupData.helpers[2]);
        veSystem.nftLock = Lock(preparedSetupData.helpers[3]);
        veSystem.ivotesAdapter = EscrowIVotesAdapter(preparedSetupData.helpers[4]);

        for (uint256 i = 0; i < preparedSetupData.permissions.length; i++) {
            PermissionLib.MultiTargetPermission memory perm = preparedSetupData.permissions[i];
            if (perm.operation == PermissionLib.Operation.Grant) {
                dao.grant(perm.where, perm.who, perm.permissionId);
            } else if (perm.operation == PermissionLib.Operation.Revoke) {
                dao.revoke(perm.where, perm.who, perm.permissionId);
            }
        }

        // Temporarily grant factory ESCROW_ADMIN_ROLE to wire components
        dao.grant(
            address(veSystem.votingEscrow),
            address(this),
            veSystem.votingEscrow.ESCROW_ADMIN_ROLE()
        );

        // Wire up VE components
        veSystem.votingEscrow.setCurve(address(veSystem.curve));
        veSystem.votingEscrow.setQueue(address(veSystem.exitQueue));
        veSystem.votingEscrow.setLockNFT(address(veSystem.nftLock));
        veSystem.votingEscrow.setIVotesAdapter(address(veSystem.ivotesAdapter));

        // Revoke temporary permission
        dao.revoke(
            address(veSystem.votingEscrow),
            address(this),
            veSystem.votingEscrow.ESCROW_ADMIN_ROLE()
        );
    }

    function _installTokenVotingHats(
        DAO dao,
        VEPluginSet memory veSystem
    ) internal returns (TokenVotingHats plugin, PluginRepo pluginRepo) {
        if (address(parameters.tokenVotingPluginRepo) == address(0)) {
            pluginRepo = PluginRepoFactory(parameters.pluginRepoFactory)
                .createPluginRepoWithFirstVersion(
                    "token-voting-hats",
                    address(parameters.tokenVotingSetup),
                    address(dao),
                    " ",
                    " "
                );
        } else {
            pluginRepo = parameters.tokenVotingPluginRepo;
        }

        PluginRepo.Tag memory repoTag = PluginRepo.Tag(PLUGIN_REPO_RELEASE, PLUGIN_REPO_BUILD);

        bytes memory installData = parameters.tokenVotingSetup.encodeInstallationParametersHats(
            MajorityVotingBase.VotingSettings({
                votingMode: MajorityVotingBase.VotingMode.Standard,
                supportThreshold: DEFAULT_SUPPORT_THRESHOLD,
                minParticipation: DEFAULT_MIN_PARTICIPATION,
                minDuration: DEFAULT_MIN_DURATION,
                minProposerVotingPower: DEFAULT_MIN_PROPOSER_VOTING_POWER
            }),
            TokenVotingSetupHats.TokenSettings({
                addr: address(veSystem.ivotesAdapter),
                name: "",
                symbol: ""
            }),
            GovernanceERC20.MintSettings({
                receivers: new address[](0),
                amounts: new uint256[](0),
                ensureDelegationOnMint: false
            }),
            IPlugin.TargetConfig({
                target: address(dao),
                operation: IPlugin.Operation.Call
            }),
            0,
            bytes(""),
            new address[](0),
            TokenVotingSetupHats.HatsConfig({
                proposerHatId: parameters.proposerHatId,
                voterHatId: parameters.voterHatId,
                executorHatId: parameters.executorHatId
            })
        );

        (address pluginAddress, IPluginSetup.PreparedSetupData memory preparedSetupData) =
            parameters.pluginSetupProcessor.prepareInstallation(
                address(dao),
                PluginSetupProcessor.PrepareInstallationParams({
                    pluginSetupRef: PluginSetupRef(repoTag, pluginRepo),
                    data: installData
                })
            );

        parameters.pluginSetupProcessor.applyInstallation(
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
        dao.revoke(
            address(dao),
            address(parameters.pluginSetupProcessor),
            dao.ROOT_PERMISSION_ID()
        );
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
