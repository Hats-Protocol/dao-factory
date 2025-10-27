# DAO Deployment Configuration

This directory contains JSON configuration files for DAO deployments.

## Quick Start

1. Copy the example config:
   ```bash
   cp config/deployment-config.example.json config/my-dao.json
   ```

2. Edit `my-dao.json` with your DAO parameters

3. Deploy using the config:
   ```bash
   CONFIG_PATH=config/my-dao.json forge script script/DeployDaoFromConfig.s.sol \
     --rpc-url sepolia \
     --broadcast \
     --verify
   ```

## Configuration Structure

### dao
Basic DAO settings:
- `executor`: Address with execute permissions (use `0x0...0` for default)
- `metadataUri`: IPFS URI for DAO metadata (optional)
- `subdomain`: ENS subdomain for the DAO (optional)

### underlyingToken
The ERC20 token users lock for voting power:
- `addr`: Token contract address
- `minDeposit`: Minimum lockable amount (in token decimals, e.g., `"1000000000000000000"` = 1 token)

### veToken
The NFT representing locked positions:
- `name`: Token name (e.g., "Vote Escrowed DEUS")
- `symbol`: Token symbol (e.g., "veDEUS")

### votingEscrow
Lock mechanics:
- `minLockDuration`: Minimum seconds before exit queue (e.g., `15724800` = 6 months)
- `feePercent`: Withdrawal fee (0-10000, where 10000 = 100%)
- `cooldownPeriod`: Seconds after exit queue before withdrawal (0 = instant)

### votingPowerCurve
Voting power calculation coefficients:
- `constantCoefficient`: Constant term (`"1000000000000000000"` = 1.0)
- `linearCoefficient`: Linear growth over time
- `quadraticCoefficient`: Quadratic growth over time
- `maxEpochs`: Time horizon (0 = flat curve, 1:1 ratio)

**Example**: For a flat curve (1 token locked = 1 vote), use:
```json
{
  "constantCoefficient": "1000000000000000000",
  "linearCoefficient": "0",
  "quadraticCoefficient": "0",
  "maxEpochs": 0
}
```

### tokenVotingHatsPlugin

#### governance
Voting settings:
- `votingMode`: "Standard", "EarlyExecution", or "VoteReplacement"
- `supportThreshold`: Yes votes required (basis points, e.g., `10000` = 1%)
- `minParticipation`: Quorum requirement (0-1000000, where `1000000` = 100%)
- `minDuration`: Minimum proposal duration in seconds
- `minProposerVotingPower`: Minimum voting power to create proposals (`"0"` = anyone with veTokens)

#### hatsProtocol
Hat IDs for access control:
- `proposerHatId`: Who can create proposals
- `voterHatId`: Who can vote
- `executorHatId`: Who can execute (use `"0x...01"` for public execution)

#### repository
Plugin repository settings:
- `release`: Plugin release number
- `build`: Plugin build number
- `useExisting`: Use existing repo (`true`) or create new (`false`)
- `addr`: Plugin repo address (required if `useExisting` is true)

#### baseImplementations
Chain-specific pre-deployed contracts:
- `governanceErc20`: GovernanceERC20 base implementation
- `governanceWrappedErc20`: GovernanceWrappedERC20 base implementation

## Network-Specific Addresses

### Sepolia Testnet
```json
{
  "tokenVotingHatsPlugin": {
    "repository": {
      "addr": "0xe4a0dE2301e9c9A305DC5aed0348A3bB50B3e063"
    },
    "baseImplementations": {
      "governanceErc20": "0xA03C2182af8eC460D498108C92E8638a580b94d4",
      "governanceWrappedErc20": "0x6E924eA5864044D8642385683fFA5AD42FB687f2"
    }
  }
}
```

## Tips

- **Large numbers**: Use strings for large numbers to avoid precision issues (e.g., `"1000000000000000000"` instead of `1e18`)
- **Addresses**: Always use full checksummed addresses
- **Zero address**: Use `"0x0000000000000000000000000000000000000000"` for default/empty addresses
- **Testing**: Start with the example config and modify incrementally
