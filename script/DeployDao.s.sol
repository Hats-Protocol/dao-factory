// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import { VETokenVotingDaoFactory, DeploymentParameters } from "../src/VETokenVotingDaoFactory.sol";

import { VESystemSetup } from "../src/VESystemSetup.sol";
import { TokenVotingSetupHats } from "@token-voting-hats/TokenVotingSetupHats.sol";
import { GovernanceERC20 } from "@token-voting-hats/erc20/GovernanceERC20.sol";
import { GovernanceWrappedERC20 } from "@token-voting-hats/erc20/GovernanceWrappedERC20.sol";

// VE System components
import { ClockV1_2_0 as Clock } from "@clock/Clock_v1_2_0.sol";
import { VotingEscrowV1_2_0 as VotingEscrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { LinearIncreasingCurve as Curve } from "@curve/LinearIncreasingCurve.sol";
import { DynamicExitQueue as ExitQueue } from "@queue/DynamicExitQueue.sol";
import { LockV1_2_0 as Lock } from "@lock/Lock_v1_2_0.sol";
import { EscrowIVotesAdapter } from "@delegation/EscrowIVotesAdapter.sol";

import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

/// @notice Deployment script for creating a new DAO with VE governance and TokenVotingHats
/// @dev Run with: forge script script/DeployDao.s.sol --rpc-url sepolia --broadcast --verify
/// @dev OSx addresses automatically selected based on chain ID
/// @dev Requires PRIVATE_KEY environment variable to be set
contract DeployDaoScript is Script {
  // ============================================
  // DAO CONFIGURATION - UPDATE THESE VALUES
  // ============================================

  // DAO Settings
  address constant DAO_EXECUTOR = 0x624123ec4A9f48Be7AA8a307a74381E4ea7530D4; // Optional: specific executor address (or address(0))
  string constant DAO_METADATA_URI = ""; // Optional: IPFS URI for DAO metadata
  string constant DAO_SUBDOMAIN = ""; // Optional: ENS subdomain (e.g., "my-dao")

  // Underlying Token (token that users lock to get voting power)
  address constant UNDERLYING_TOKEN = 0x8577073B9931CA5b73c8Cf44fb1C8CC8342815E4;
  uint256 constant MIN_DEPOSIT = 1e18; // Minimum amount to lock (in token decimals)

  // VE Token Settings (the NFT representing locked positions)
  string constant VE_TOKEN_NAME = "Vote Escrowed TOKEN";
  string constant VE_TOKEN_SYMBOL = "veTOKEN";

  // VE Lock Settings
  uint48 constant MIN_LOCK_DURATION = 15_724_800; // 6 months in seconds
  uint16 constant FEE_PERCENT = 0; // Withdrawal fee (0 = no fee)
  uint48 constant COOLDOWN_PERIOD = 0; // Cooldown after exit queue (0 = instant)

  // Flat Curve Configuration (1:1 ratio - 1 token locked = 1 vote)
  int256 constant CURVE_CONSTANT_COEFF = 1e18; // Constant term = 1.0
  int256 constant CURVE_LINEAR_COEFF = 0; // No linear growth over time
  int256 constant CURVE_QUADRATIC_COEFF = 0; // No quadratic growth over time
  uint48 constant CURVE_MAX_EPOCHS = 0; // No time horizon (flat curve)

  // Hats Protocol Configuration
  uint256 constant PROPOSER_HAT_ID = 0x0000071c00030000000000000000000000000000000000000000000000000000;
  uint256 constant VOTER_HAT_ID = 0x0000071c00030000000000000000000000000000000000000000000000000000;
  uint256 constant EXECUTOR_HAT_ID = uint256(1);

  // ============================================
  // CHAIN-SPECIFIC ADDRESSES
  // ============================================

  // Token Voting Plugin Base Implementations (Sepolia)
  address constant GOVERNANCE_ERC20_BASE = 0xA03C2182af8eC460D498108C92E8638a580b94d4;
  address constant GOVERNANCE_WRAPPED_ERC20_BASE = 0x6E924eA5864044D8642385683fFA5AD42FB687f2;

  // Optional: Use existing TokenVoting plugin repo (or address(0) to create new)
  address constant EXISTING_TOKEN_VOTING_REPO = 0xe4a0dE2301e9c9A305DC5aed0348A3bB50B3e063;

  // ============================================
  // INTERNAL HELPERS
  // ============================================

  /// @dev Set up the deployer via their private key from the environment
  function _deployer() internal returns (address) {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    return vm.rememberKey(privKey);
  }

  function run() external {
    // Get OSx addresses for current chain
    (address osxDaoFactory, address pluginSetupProcessor, address pluginRepoFactory) = _getOSxAddresses();

    vm.startBroadcast(_deployer());

    // ===== STEP 1: Deploy Plugin Setup Contracts =====
    (VESystemSetup veSystemSetup, TokenVotingSetupHats tokenVotingSetup) = _deployPluginSetups();

    // ===== STEP 2: Deploy VETokenVotingDaoFactory =====
    VETokenVotingDaoFactory factory =
      _deployFactory(veSystemSetup, tokenVotingSetup, osxDaoFactory, pluginSetupProcessor, pluginRepoFactory);

    // ===== STEP 3: Deploy the DAO =====
    _deployDao(factory);

    vm.stopBroadcast();

    // ===== STEP 4: Log deployment artifacts =====
    _logDeployment(factory);
  }

  /// @notice Deploys all plugin setup contracts and base implementations
  function _deployPluginSetups() internal returns (VESystemSetup veSystemSetup, TokenVotingSetupHats tokenVotingSetup) {
    console.log("=== Deploying VE Base Implementations ===");

    // Deploy VE system base implementations (reused across all DAOs)
    Clock clockBase = new Clock();
    console.log("Clock base:", address(clockBase));

    VotingEscrow escrowBase = new VotingEscrow();
    console.log("VotingEscrow base:", address(escrowBase));

    // Deploy Curve with flat curve parameters (baked into implementation)
    Curve curveBase = new Curve(
      [CURVE_CONSTANT_COEFF, CURVE_LINEAR_COEFF, CURVE_QUADRATIC_COEFF],
      CURVE_MAX_EPOCHS
    );
    console.log("Curve base:", address(curveBase));

    ExitQueue queueBase = new ExitQueue();
    console.log("ExitQueue base:", address(queueBase));

    Lock lockBase = new Lock();
    console.log("Lock base:", address(lockBase));

    // Deploy IVotesAdapter with flat curve parameters (baked into implementation)
    EscrowIVotesAdapter ivotesAdapterBase = new EscrowIVotesAdapter(
      [CURVE_CONSTANT_COEFF, CURVE_LINEAR_COEFF, CURVE_QUADRATIC_COEFF],
      CURVE_MAX_EPOCHS
    );
    console.log("IVotesAdapter base:", address(ivotesAdapterBase));

    console.log("");
    console.log("=== Deploying Plugin Setup Contracts ===");

    // Deploy VESystemSetup with all base implementation addresses
    veSystemSetup = new VESystemSetup(
      address(clockBase),
      address(escrowBase),
      address(curveBase),
      address(queueBase),
      address(lockBase),
      address(ivotesAdapterBase)
    );
    console.log("VESystemSetup:", address(veSystemSetup));

    // Use existing base implementations for TokenVoting
    console.log("Using GovernanceERC20 base:", GOVERNANCE_ERC20_BASE);
    console.log("Using GovernanceWrappedERC20 base:", GOVERNANCE_WRAPPED_ERC20_BASE);

    // Deploy TokenVotingSetupHats
    tokenVotingSetup = new TokenVotingSetupHats(
      GovernanceERC20(GOVERNANCE_ERC20_BASE), GovernanceWrappedERC20(GOVERNANCE_WRAPPED_ERC20_BASE)
    );
    console.log("TokenVotingSetupHats:", address(tokenVotingSetup));

    console.log("");
  }

  /// @notice Deploys the VETokenVotingDaoFactory with all parameters
  function _deployFactory(
    VESystemSetup veSystemSetup,
    TokenVotingSetupHats tokenVotingSetup,
    address osxDaoFactory,
    address pluginSetupProcessor,
    address pluginRepoFactory
  ) internal returns (VETokenVotingDaoFactory) {
    console.log("=== Deploying VETokenVotingDaoFactory ===");

    DeploymentParameters memory params = DeploymentParameters({
      // DAO settings
      daoExecutor: DAO_EXECUTOR,
      daoMetadataURI: DAO_METADATA_URI,
      daoSubdomain: DAO_SUBDOMAIN,
      // VE token parameters
      underlyingToken: UNDERLYING_TOKEN,
      veTokenName: VE_TOKEN_NAME,
      veTokenSymbol: VE_TOKEN_SYMBOL,
      minDeposit: MIN_DEPOSIT,
      // VE system settings
      minLockDuration: MIN_LOCK_DURATION,
      feePercent: FEE_PERCENT,
      cooldownPeriod: COOLDOWN_PERIOD,
      // Hats configuration
      proposerHatId: PROPOSER_HAT_ID,
      voterHatId: VOTER_HAT_ID,
      executorHatId: EXECUTOR_HAT_ID,
      // Plugin setup contracts
      veSystemSetup: veSystemSetup,
      tokenVotingSetup: tokenVotingSetup,
      tokenVotingPluginRepo: PluginRepo(EXISTING_TOKEN_VOTING_REPO),
      // OSx addresses (automatically selected based on chain)
      osxDaoFactory: osxDaoFactory,
      pluginSetupProcessor: PluginSetupProcessor(pluginSetupProcessor),
      pluginRepoFactory: PluginRepoFactory(pluginRepoFactory)
    });

    VETokenVotingDaoFactory factory = new VETokenVotingDaoFactory(params);
    console.log("VETokenVotingDaoFactory:", address(factory));
    console.log("");

    return factory;
  }

  /// @notice Deploys the DAO via factory.deployOnce()
  function _deployDao(VETokenVotingDaoFactory factory) internal {
    console.log("=== Deploying DAO ===");

    factory.deployOnce();

    console.log("DAO deployed successfully!");
    console.log("");
  }

  /// @notice Logs all deployment addresses
  function _logDeployment(VETokenVotingDaoFactory factory) internal {
    console.log("=== Deployment Artifacts ===");
    console.log("Factory:", address(factory));
    console.log("");
    console.log("Call factory.getDeployment() to retrieve:");
    console.log("  - DAO address");
    console.log("  - VE System components (VotingEscrow, Clock, Curve, ExitQueue, Lock, IVotesAdapter)");
    console.log("  - TokenVotingHats plugin");
    console.log("  - TokenVotingHats plugin repo");
  }

  /// @notice Gets OSx framework addresses for the current chain
  function _getOSxAddresses()
    internal
    returns (address daoFactory, address pluginSetupProcessor, address pluginRepoFactory)
  {
    // Read addresses from OSx deployment artifacts
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/lib/osx/packages/artifacts/src/addresses.json");
    string memory json = vm.readFile(path);

    // Map chain ID to network name
    string memory network = _getNetworkName(block.chainid);

    // Parse addresses for current network
    daoFactory = vm.parseJsonAddress(json, string.concat(".daoFactory.", network));
    pluginSetupProcessor = vm.parseJsonAddress(json, string.concat(".pluginSetupProcessor.", network));
    pluginRepoFactory = vm.parseJsonAddress(json, string.concat(".pluginRepoFactory.", network));

    console.log("Using OSx contracts for", network);
    console.log("Chain ID:", block.chainid);
    console.log("  DAOFactory:", daoFactory);
    console.log("  PluginSetupProcessor:", pluginSetupProcessor);
    console.log("  PluginRepoFactory:", pluginRepoFactory);
    console.log("");
  }

  /// @notice Maps chain ID to network name used in addresses.json
  function _getNetworkName(uint256 chainId) internal pure returns (string memory) {
    if (chainId == 1) return "mainnet";
    if (chainId == 11_155_111) return "sepolia";
    if (chainId == 137) return "polygon";
    if (chainId == 42_161) return "arbitrum";
    if (chainId == 421_614) return "arbitrumSepolia";
    if (chainId == 8453) return "base";
    if (chainId == 17_000) return "holesky";
    if (chainId == 56) return "bsc";
    if (chainId == 97) return "bscTestnet";
    if (chainId == 59_144) return "linea";
    if (chainId == 34_443) return "mode";
    if (chainId == 324) return "zksync";
    if (chainId == 300) return "zksyncSepolia";

    revert(
      string.concat(
        "Unsupported chain ID: ",
        vm.toString(chainId),
        ". Check lib/osx/packages/artifacts/src/addresses.json for supported chains"
      )
    );
  }
}
