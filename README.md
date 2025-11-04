# DAO Factory

Factory contracts for deploying the Hats DAO, using Aragon OSx Vote Escrow (VE) governance and configurable SubDAOs.

## Overview

This repository contains:
- **Main DAO Factory**: Deploys Aragon OSx DAO with VE token governance and Hats Protocol integration
- **SubDAO Factory**: Deploys configurable SubDAOs with staged proposal processing (veto or approval mode)

## Development

### Prerequisites

1. Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
2. Clone the repository and install dependencies:
   ```bash
   forge install
   ```

### Building

Compile all contracts:
```bash
forge build
```

### Testing

Run all tests:
```bash
forge test --summary --jobs 1
```

**Important:** Tests must be run with `--jobs 1` (sequential execution) to ensure proper test isolation.

Run specific test suites:
```bash
# SubDAO tests
forge test --match-path "test/subdao/**/*.sol"

# Fork tests
forge test --match-path "test/fork/**/*.sol"

# Unit tests
forge test --match-path "test/unit/**/*.sol"
```

Run with detailed output:
```bash
forge test --summary --jobs 1 -vv
```

### Test Coverage

Generate coverage report:
```bash
forge coverage
```

## Deployment

### Configuration Files

Configuration files are located in `config/`:
- `config/deployment-config.json` - Main DAO configuration
- `config/subdaos/` - SubDAO configurations

### Deployment Scripts

Individual deployment scripts in `script/`:
- `DeployDao.s.sol` - Main DAO deployment
- `DeploySubDao.s.sol` - SubDAO deployment

### Production Deployment Orchestrator

For safe production deployments with manual verification checkpoints, use the orchestrator in `script/orchestrator/`:
- `01_DeployMainDao.s.sol` - Step 1: Deploy Main DAO
- `02_DeploySubDaos.s.sol` - Step 2: Deploy SubDAOs

The orchestrator provides a two-step deployment process with a verification checkpoint between main DAO and SubDAO deployments. For complete instructions, see [script/orchestrator/README.md](script/orchestrator/README.md).

## Project Structure

```
├── src/                    # Smart contracts
│   ├── VETokenVotingDaoFactory.sol
│   └── SubDaoFactory.sol
├── script/                 # Deployment scripts
│   ├── DeployDao.s.sol
│   ├── DeploySubDao.s.sol
│   └── orchestrator/      # Production deployment orchestrator
├── test/                   # Test files
│   ├── fork/              # Fork tests
│   ├── unit/              # Unit tests
│   ├── subdao/            # SubDAO tests
│   └── orchestrator/      # Integration tests
├── config/                 # Configuration files
└── docs/                   # Documentation
```

## Documentation

- [Production Deployment Orchestrator](script/orchestrator/README.md) - Safe two-step deployment guide
- [Permissions Analysis](docs/permissions-analysis.md) - Permission structure analysis
