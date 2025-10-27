# Complete Deployment Configuration

## 0. DAO Deployment (First Step)

### Using Aragon OSx DAOFactory
```solidity
// DAO Factory parameters
DAOFactory.DAOSettings memory daoSettings = {
    trustedForwarder: address(0),     // No meta-transactions
    daoURI: "",                        // Optional DAO metadata URI
    subdomain: "",                     // Optional ENS subdomain
    metadata: bytes("")                // Optional DAO metadata
};

// Deploy DAO
(DAO dao, ) = DAOFactory(osxDaoFactory).createDao(
    daoSettings,
    new DAOFactory.PluginSettings[](0)  // No plugins yet
);
```

### OSx Contract Addresses (Chain-Specific)
You need these addresses for your target chain:
```solidity
osxDaoFactory: address               // DAOFactory contract
pluginSetupProcessor: address        // PluginSetupProcessor contract  
pluginRepoFactory: address           // PluginRepoFactory contract
```

Find these in [Aragon's osx-commons configs](https://github.com/aragon/osx-commons/tree/main/configs/src/deployments/json)

### Initial DAO Permissions
```solidity
// Grant ROOT to deployer temporarily for setup
dao.grant(dao, deployer, dao.ROOT_PERMISSION_ID())

// Optional: Grant EXECUTE to external address
dao.grant(dao, daoExecutor, dao.EXECUTE_PERMISSION_ID())
```

## 1. Core VE Lock Parameters

### VotingEscrow
```solidity
token: address                       // Underlying ERC20 token address
minDeposit: X tokens (e.g., 1000e18) // Must lock at least X tokens
```

### ExitQueue
```solidity
minLock: 15724800        // 6 months in seconds (182.5 days * 86400)
feePercent: 0            // No withdrawal fee
cooldown: 0              // No cooldown period after minLock expires
```

### Curve (LinearIncreasingCurve)
```solidity
// Constructor parameters
coefficients: [1e18, 0, 0]  // [constant, linear, quadratic]
maxEpochs: 0                 // No time horizon (flat curve)
```

### EscrowIVotesAdapter
```solidity
// Constructor parameters (MUST match Curve)
coefficients: [1e18, 0, 0]
maxEpochs: 0

// Initialize parameters
startPaused: false  // Can vote immediately
```

### Lock NFT
```solidity
veTokenName: string     // e.g., "Vote Escrowed TOKEN"
veTokenSymbol: string   // e.g., "veTOKEN"
```

## 2. Component Deployment Order

```solidity
// Deploy DAO first
DAO dao = deployDao()

// Deploy implementation contracts
Clock clockImpl = new Clock()
VotingEscrow escrowImpl = new VotingEscrow()
LinearIncreasingCurve curveImpl = new LinearIncreasingCurve([1e18, 0, 0], 0)
ExitQueue queueImpl = new ExitQueue()
Lock lockImpl = new Lock()
EscrowIVotesAdapter adapterImpl = new EscrowIVotesAdapter([1e18, 0, 0], 0)

// Deploy proxies and initialize
1. Clock.initialize(dao)
2. VotingEscrow.initialize(token, dao, clock, minDeposit)
3. EscrowIVotesAdapter.initialize(dao, escrow, clock, false)
4. LinearIncreasingCurve.initialize(escrow, dao, clock)
5. ExitQueue.initialize(escrow, 0, dao, 0, clock, 15724800)
6. Lock.initialize(escrow, veTokenName, veTokenSymbol, dao)
```

## 3. Wiring (requires ESCROW_ADMIN_ROLE)

```solidity
// Grant temporary admin
dao.grant(escrow, deployer, escrow.ESCROW_ADMIN_ROLE())

// Connect components
escrow.setCurve(curve)
escrow.setQueue(exitQueue)
escrow.setLockNFT(lockNFT)
escrow.setIVotesAdapter(ivotesAdapter)

// Revoke temporary admin
dao.revoke(escrow, deployer, escrow.ESCROW_ADMIN_ROLE())
```

## 4. Plugin Installation

### TokenVotingHats Plugin
```solidity
// Use PluginSetupProcessor to install
pluginSetupProcessor.prepareInstallation(dao, {
    pluginSetupRef: tokenVotingHatsPluginSetupRef,
    data: abi.encode(
        votingToken: address(ivotesAdapter),  // Use adapter, not escrow!
        // ... other TokenVotingHats settings
    )
})

// Apply installation
pluginSetupProcessor.applyInstallation(...)
```

<!-- ### Capital Distributor Plugin
```solidity
// Use PluginSetupProcessor to install
pluginSetupProcessor.prepareInstallation(dao, {
    pluginSetupRef: capitalDistributorPluginSetupRef,
    data: abi.encode(
        allocatorStrategyFactory,  // Address of AllocatorStrategyFactory
        actionEncoderFactory       // Address of ActionEncoderFactory
    )
})

// Apply installation
pluginSetupProcessor.applyInstallation(...)
``` 
-->

## 5. Final DAO Permissions

```solidity
// Grant to DAO itself
dao.grant(escrow, dao, escrow.ESCROW_ADMIN_ROLE())
dao.grant(escrow, dao, escrow.PAUSER_ROLE())
dao.grant(escrow, dao, escrow.SWEEPER_ROLE())
dao.grant(curve, dao, curve.CURVE_ADMIN_ROLE())
dao.grant(exitQueue, dao, exitQueue.QUEUE_ADMIN_ROLE())
dao.grant(exitQueue, dao, exitQueue.WITHDRAW_ROLE())
dao.grant(lockNFT, dao, lockNFT.LOCK_ADMIN_ROLE())
dao.grant(ivotesAdapter, dao, ivotesAdapter.DELEGATION_ADMIN_ROLE())
dao.grant(ivotesAdapter, dao, ivotesAdapter.DELEGATION_TOKEN_ROLE())

// Grant to TokenVotingHats
dao.grant(dao, tokenVotingHatsPlugin, dao.EXECUTE_PERMISSION_ID())

// Revoke deployer's temporary permissions
dao.revoke(dao, deployer, dao.ROOT_PERMISSION_ID())
dao.revoke(dao, deployer, dao.EXECUTE_PERMISSION_ID())
```

<!-- ## 6. Capital Distributor Plugin Configuration

### Strategy: DirectAllocationStrategy
```solidity
// Strategy that stores fixed per-address allocations configured by the DAO
// - Allocations are immutable once written
// - Campaign creation requires no auxData
// - No initialization parameters required

// Campaign creation (by DAO)
directAllocationStrategy.setAllocationCampaign(campaignId, bytes(""))

// Setting allocations (by DAO)
address[] memory recipients = [...];
uint256[] memory amounts = [...];
directAllocationStrategy.setAllocations(campaignId, recipients, amounts)
```

### Action Encoder: VaultDepositPayoutActionEncoder
```solidity
// Encodes actions to deposit funds into campaign-specific vaults
// Requires vault address configuration per campaign

// Campaign setup (by DAO)
bytes memory vaultSetupData = abi.encode(vaultAddress);
vaultDepositEncoder.setupCampaign(campaignId, vaultSetupData)

// Per payout, creates two actions:
// 1. token.approve(vault, amount)
// 2. vault.deposit(amount, recipient)
```

### Factory Setup Requirements
```solidity
// Two factories must be deployed with registered types:

// 1. AllocatorStrategyFactory with DirectAllocationStrategy registered
allocatorStrategyFactory.registerStrategyType(
    keccak256("DirectAllocationStrategy"),
    directAllocationStrategyImpl,
    "Direct allocation strategy",
    feeRecipient,
    feeBasisPoints
)

// 2. ActionEncoderFactory with VaultDepositPayoutActionEncoder registered
actionEncoderFactory.registerActionEncoder(
    keccak256("VaultDepositPayoutActionEncoder"),
    vaultDepositEncoderImpl,
    "Vault deposit payout encoder"
)
``` 
-->

### Post-Installation Configuration
```solidity
// DAO must configure allowed selectors on ExecuteSelectorCondition
// This controls what actions the plugin can execute on the DAO

executeSelectorCondition.addSelectors([
    ExecuteSelectorCondition.SelectorTarget({
        target: token,
        selector: IERC20.approve.selector
    }),
    ExecuteSelectorCondition.SelectorTarget({
        target: vault,
        selector: IVault.deposit.selector
    })
])
```

## Required Inputs Summary

- **Chain-specific**: `osxDaoFactory`, `pluginSetupProcessor`, `pluginRepoFactory`
- **Token**: Underlying ERC20 address
- **Lock params**: `minDeposit` amount
- **Metadata**: `veTokenName`, `veTokenSymbol`
- **Plugin setup contracts**: TokenVotingHats 
<!-- and Capital Distributor plugin setup addresses -->
<!-- - **Capital Distributor**: `allocatorStrategyFactory`, `actionEncoderFactory` addresses -->