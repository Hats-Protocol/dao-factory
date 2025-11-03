# SubDAO Deployment Orchestrator

**Purpose**: Safe production deployment of main DAO + multiple SubDAOs with manual verification checkpoints.

## Overview

This orchestrator provides a two-step deployment process:

1. **Step 1**: Deploy main DAO → Save addresses to broadcast artifacts
2. **VERIFICATION CHECKPOINT**: Manually verify main DAO deployment
3. **Step 2**: Deploy SubDAOs → Read main DAO from artifacts, deploy both SubDAOs

## Why Two Steps?

**Safety**: Deploying SubDAOs on a broken main DAO is expensive and risky. Manual verification between steps prevents costly mistakes.

**Use Case**: You're deploying:
- 1 Main DAO (with VE system, token voting, Hats-permissioning config)
- 2 SubDAOs (approver-hat-minter and member-curator)

Both SubDAOs share the main DAO's infrastructure (IVotesAdapter, hat IDs, plugin repositories).

## How the Orchestrator Works

### Nested run() Pattern

The orchestrator uses a **nested run() pattern** to avoid Foundry limitations:

```
Orchestrator (NO broadcast):
  1. Read addresses from broadcast artifacts
  2. Set env vars (MAIN_DAO_FACTORY, MAIN_DAO)
  3. Create child script instance
  4. Call child.run() ←─┐
                         │
Child Script:            │
  5. Read env vars  ←────┘
  6. vm.startBroadcast() (child's own broadcast)
  7. Deploy SubDAO
  8. vm.stopBroadcast()
  9. Store factory in lastDeployedFactory
                         │
Orchestrator:            │
  10. Read result ───────┘
```

**Why this works:**
- ✅ Parent has NO broadcast block (avoids calling script methods from within broadcast)
- ✅ Each child has its own independent broadcast block
- ✅ Addresses passed via environment variables (like CONFIG_PATH)
- ✅ Results returned via public variable

**Why the old pattern failed:**
```solidity
// ❌ BROKEN: Cannot call script.execute() from within broadcast
vm.startBroadcast();
script.execute(addresses);  // Foundry tries to broadcast to script address (doesn't exist on-chain)
vm.stopBroadcast();
```

### Environment Variables Flow

| Variable | Set By | Read By | Purpose |
|----------|---------|---------|---------|
| `CONFIG_PATH` | Orchestrator | Child script | Select which config file |
| `MAIN_DAO_FACTORY` | Orchestrator | Child script | Override factory address |
| `MAIN_DAO` | Orchestrator | Child script | Override DAO address |

If env vars not set, child scripts fall back to values in config files.

---

## Quick Start: Testing with Anvil

**TL;DR**: Test the full deployment without spending gas:

```bash
# Terminal 1: Start local fork
anvil --fork-url $SEPOLIA_RPC_URL

# Terminal 2: Run full deployment
forge script script/orchestrator/01_DeployMainDao.s.sol --rpc-url local --broadcast
# Verify output looks good
forge script script/orchestrator/02_DeploySubDaos.s.sol --rpc-url local --broadcast
# Clean up
rm -rf broadcast/*/31337/
```

See the full [Dry Run section](#dry-run-simulation) for details.

---

## Prerequisites

### Required Tools
- **Foundry** (latest version): `foundryup`
  - Includes `forge`, `cast`, and `anvil` for local testing
- **RPC URL**: Sepolia testnet or Ethereum mainnet
  - For testing: anvil local fork (included with Foundry)
- **Deployer wallet**: Private key with sufficient ETH for gas (~0.5 ETH on mainnet)
  - Not needed for anvil testing

### Required Files
```
config/
├── dao-config.json              # Main DAO configuration
└── subdaos/
    ├── approver-hat-minter.json # SubDAO 1 configuration
    └── member-curator.json      # SubDAO 2 configuration
```

---

## Configuration Files

### Main DAO Config
**Location**: `config/dao-config.json`

Defines the main DAO parameters:
- VE system (token, max lock duration, etc.)
- Hats permissioning structure (proposer, voter, executor hats)
- Governance parameters (voting thresholds, durations)
- Plugin versions

### SubDAO Configs
**Location**: `config/subdaos/`

#### Key Differences Between SubDAOs

| Parameter | Approver-Hat-Minter | Member-Curator | Notes |
|-----------|---------------------|----------------|-------|
| **Purpose** | Manage hat minting approvals | Manage DAO membership | Different governance domains |
| `dao.subdomain` | "approver-hat-minter" | "member-curator" | Unique identifier |
| `dao.metadataUri` | ipfs://QmApprover... | ipfs://QmMember... | Different IPFS metadata |
| `stage1.proposerAddress` | 0x123... | 0x456... | Can be same or different |
| `stage2.voteDuration` | 259200 (3 days) | 86400 (1 day) | Member decisions are faster |
| `sppPlugin.metadata` | Approver SPP metadata | Member SPP metadata | Different descriptions |

#### Shared Parameters (Queried from Main DAO)

These are **NOT** in SubDAO configs - they're read from the main DAO factory:
- `mainDaoAddress` - Parent DAO
- `mainDaoFactoryAddress` - Factory with getter functions
- `ivotesAdapter` - Voting power oracle (from main DAO)
- Hat IDs (proposerHatId, voterHatId, executorHatId)
- Plugin repos and versions

---

## Deployment Process

<NETWORK> can be:
- sepolia
- mainnet
- local (for testing with anvil - see [Dry Run section](#dry-run-simulation))

**💡 Tip**: Before deploying to a real network, test the full flow using the [anvil dry run approach](#dry-run-simulation) to catch errors without spending gas.

### Step 1: Deploy Main DAO

```bash
forge script script/orchestrator/01_DeployMainDao.s.sol --rpc-url <NETWORK> \
  --broadcast \
  --verify \
  -vvv
```

#### What This Does:
1. Deploys VE system (VotingEscrow, Clock, Curve, ExitQueue, IVotesAdapter)
2. Deploys main DAO with token voting plugin
3. Creates Hats permissioning structure (proposer, voter, executor hats)
4. Saves deployment to `broadcast/01_DeployMainDao.s.sol/<chainId>/run-latest.json`

#### Expected Output:
```
=== Main DAO Deployment ===
✓ VETokenVotingDaoFactory deployed at: 0xABC123...
✓ Main DAO deployed at: 0xDEF456...

IVotesAdapter: 0x789ABC...
Proposer Hat ID: 26959946667150639794667015087019630673637144422540572481103610249216
Voter Hat ID: 26959946667150639794667015087019630673637144422540572481103610249217
Executor Hat ID: 26959946667150639794667015087019630673637144422540572481103610249218

✓ Deployment saved to: broadcast/01_DeployMainDao.s.sol/11155111/run-latest.json
```

---

### VERIFICATION CHECKPOINT #1

**⚠️ CRITICAL: Do NOT proceed to Step 2 until you've verified all of these:**

#### 1. Verify Factory Address on Etherscan

```bash
# Open factory on Etherscan
open https://sepolia.etherscan.io/address/<FACTORY_ADDRESS>
```

**Check**:
- Contract is verified (green checkmark)
- Constructor arguments match your config
- Contract name is `VETokenVotingDaoFactory`

#### 2. Verify Main DAO Deployment

```bash
# Get deployment from factory
cast call <FACTORY_ADDRESS> "getDeployment()" --rpc-url <NETWORK>
```

**Expected**: Returns non-zero addresses for:
- `dao` - Main DAO address
- `ivotesAdapter` - Voting power oracle
- `tokenVotingPlugin` - Token voting plugin
- All other components

#### 3. Verify IVotesAdapter

```bash
# Get IVotesAdapter address
cast call <FACTORY_ADDRESS> "getIVotesAdapter()" --rpc-url <NETWORK>
```

**Expected**: Returns non-zero address (e.g., `0x789ABC...`)

**Verify**: This address should be a deployed EscrowIVotesAdapter contract

#### 4. Verify Hat IDs

```bash
# Get hat IDs
cast call <FACTORY_ADDRESS> "getProposerHatId()" --rpc-url <NETWORK>
cast call <FACTORY_ADDRESS> "getVoterHatId()" --rpc-url <NETWORK>
cast call <FACTORY_ADDRESS> "getExecutorHatId()" --rpc-url <NETWORK>
```

**Expected**: Returns large numbers (hat IDs are uint256)

**Note**: Hat IDs will look like: `26959946667150639794667015087019630673637144422540572481103610249216`

#### 5. Verify Permissions

```bash
# Check main DAO permissions on Etherscan
open https://sepolia.etherscan.io/address/<MAIN_DAO_ADDRESS>#readContract
```

**Check**:
- Token voting plugin has EXECUTE_PERMISSION on DAO
- No unexpected addresses have ROOT_PERMISSION
- Plugin setup processor does NOT have ROOT_PERMISSION (it should be revoked)

#### 6. Verify Plugin Repos

```bash
# Get token voting plugin repo
cast call <FACTORY_ADDRESS> "getTokenVotingPluginRepo()" --rpc-url <NETWORK>
```

**Expected**: Returns address of TokenVotingHats plugin repo

---

### What to Do If Verification Fails

**If any check fails:**

1. **DO NOT PROCEED to Step 2**
2. **Document the issue**: What check failed and why
3. **Debug**: Review deployment logs, check contract code
4. **Decide**:
   - **If fixable**: Redeploy main DAO (you haven't deployed SubDAOs yet, so it's safe)
   - **If critical bug**: Stop, review contract code, fix bug, redeploy
5. **Re-verify**: After fix, run all verification checks again

**Common Issues**:
- **Gas estimation failed**: Increase gas limit or gas price
- **Deployment reverted**: Check constructor parameters in config
- **Permissions missing**: Check setup functions in factory
- **Wrong addresses**: Check config file paths and values

---

### IMPORTANT: Clean Up Broadcast Artifacts

**Before Step 2**, you must ensure only ONE type of broadcast artifact exists to prevent deployment mode mismatch.

#### The Problem

Foundry creates different artifacts for different deployment modes:
- **Real deployment** (`--broadcast`): `broadcast/.../run-latest.json`
- **Dry-run/simulation** (no `--broadcast`): `broadcast/.../dry-run/run-latest.json`

If **both exist**, the orchestrator will **fail fast** with an error to prevent you from accidentally:
- Deploying SubDAOs to a simulated (non-existent) main DAO
- Mixing real and dry-run artifacts
- Using stale artifacts from previous deployments

#### Clean Up Commands

**For production deployment** (using real broadcast):
```bash
# Remove all dry-run artifacts before deploying SubDAOs
rm -rf broadcast/01_DeployMainDao.s.sol/*/dry-run/
```

**For testing/simulation** (using dry-run):
```bash
# Remove real broadcast artifacts to use dry-run
rm broadcast/01_DeployMainDao.s.sol/*/run-latest.json
```

**After anvil testing** (chain ID 31337):
```bash
# Remove all anvil artifacts after local testing
rm -rf broadcast/*/31337/
```

#### Error Message

If both exist, you'll see:
```
BroadcastReader: Found both real and dry-run artifacts.
This prevents accidental deployment mode mismatch.
Please clean up before deploying:
  For production: rm -rf broadcast/01_DeployMainDao.s.sol/*/dry-run/
  For testing:    rm broadcast/01_DeployMainDao.s.sol/*/run-latest.json
```

---

### Step 2: Deploy SubDAOs

**⚠️ Only proceed if ALL verification checks passed AND artifacts cleaned up**

```bash
forge script script/orchestrator/02_DeploySubDaos.s.sol --rpc-url <NETWORK> \
  --broadcast \
  --verify \
  -vvv
```

#### What This Does:
1. Reads main DAO factory address from Step 1's broadcast artifacts
2. Reads main DAO address from factory's `getDeployment()`
3. Deploys approver-hat-minter SubDAO using `config/subdaos/approver-hat-minter.json`
4. Deploys member-curator SubDAO using `config/subdaos/member-curator.json`
5. Both SubDAOs query main DAO factory for shared infrastructure
6. Saves deployment to `broadcast/02_DeploySubDaos.s.sol/<chainId>/run-latest.json`

#### Expected Output:
```
Reading main DAO factory from broadcast artifacts...
Main DAO Factory: 0xABC123...
Main DAO: 0xDEF456...

=== Deploying approver-hat-minter SubDAO ===
  Config: config/subdaos/approver-hat-minter.json
  Factory deployed: 0x111222...
  DAO deployed: 0x333444...
✓ Approver-Hat-Minter SubDAO deployed

=== Deploying member-curator SubDAO ===
  Config: config/subdaos/member-curator.json
  Factory deployed: 0x555666...
  DAO deployed: 0x777888...
✓ Member-Curator SubDAO deployed

=== Deployment Summary ===
Main DAO Factory: 0xABC123...
Main DAO: 0xDEF456...
Approver-Hat-Minter SubDAO: 0x333444...
Member-Curator SubDAO: 0x777888...
```

---

### VERIFICATION CHECKPOINT #2

**After SubDAO deployment, verify:**

#### 1. Both SubDAOs Deployed

```bash
# Check both factories on Etherscan
open https://sepolia.etherscan.io/address/<APPROVER_FACTORY>
open https://sepolia.etherscan.io/address/<MEMBER_CURATOR_FACTORY>
```

**Check**:
- Both contracts verified
- Different addresses
- Contract name is `SubDaoFactory`

#### 2. SubDAOs Share Same IVotesAdapter

```bash
# Get IVotesAdapter from main DAO
MAIN_ADAPTER=$(cast call <MAIN_FACTORY> "getIVotesAdapter()" --rpc-url <NETWORK>)
echo "Main DAO IVotesAdapter: $MAIN_ADAPTER"

# Get IVotesAdapter from approver SubDAO
APPROVER_ADAPTER=$(cast call <APPROVER_FACTORY> "getDeploymentParameters()" --rpc-url <NETWORK> | grep ivotesAdapter)
echo "Approver IVotesAdapter: $APPROVER_ADAPTER"

# Get IVotesAdapter from member-curator SubDAO
MEMBER_ADAPTER=$(cast call <MEMBER_CURATOR_FACTORY> "getDeploymentParameters()" --rpc-url <NETWORK> | grep ivotesAdapter)
echo "Member-Curator IVotesAdapter: $MEMBER_ADAPTER"
```

**Expected**: All three should be the **same address**

#### 3. Verify Stage2 Durations

Check the configs or deploymentParameters:
- **Approver-Hat-Minter**: 259200 seconds (3 days)
- **Member-Curator**: 86400 seconds (1 day)

#### 4. Verify Permissions on Each SubDAO

For each SubDAO, check on Etherscan:
```bash
open https://sepolia.etherscan.io/address/<APPROVER_DAO>#readContract
open https://sepolia.etherscan.io/address/<MEMBER_CURATOR_DAO>#readContract
```

**Check**:
- Token voting plugin has EXECUTE_PERMISSION
- SPP plugin has EXECUTE_PERMISSION
- Admin plugin has EXECUTE_PERMISSION
- Factory does NOT have ROOT_PERMISSION (revoked after deployment)
- Stage1 proposer has CREATE_PROPOSAL_PERMISSION on SPP

#### 5. Verify SubDAOs Are Independent

**Test**: Create a test proposal in each SubDAO (on testnet):

```bash
# In approver SubDAO
cast send <APPROVER_SPP> "createProposal(...)" --rpc-url <NETWORK>

# In member-curator SubDAO
cast send <MEMBER_CURATOR_SPP> "createProposal(...)" --rpc-url <NETWORK>
```

**Expected**: Both succeed independently

---

## Troubleshooting

### Issue: "Broadcast artifact not found"

**Error**: `BroadcastReader: Failed to read broadcast artifact`

**Cause**: Step 2 can't find Step 1's broadcast output

**Solution**:
1. Check that Step 1 ran successfully with `--broadcast` flag
2. Verify file exists:
   ```bash
   ls -la broadcast/01_DeployMainDao.s.sol/<chainId>/run-latest.json
   ```
3. Ensure you're on the same chain (chainId must match between steps)
4. **If file missing**: Re-run Step 1 with `--broadcast`

### Issue: "Main DAO factory has no getter functions"

**Error**: Contract doesn't have `getIVotesAdapter()` function

**Cause**: Old factory version deployed without getter functions

**Solution**:
1. Verify you're using latest factory code
2. Check factory contract on Etherscan - should have these functions:
   - `getIVotesAdapter()`
   - `getTokenVotingPluginRepo()`
   - `getProposerHatId()`, `getVoterHatId()`, `getExecutorHatId()`
3. If missing: Redeploy main DAO with updated factory

### Issue: "SubDAO deployment reverts with 'InvalidIVotesAdapterAddress'"

**Error**: SubDAO factory constructor reverts

**Cause**: Main DAO factory getter returns `address(0)`

**Solution**:
1. Verify main DAO deployed correctly:
   ```bash
   cast call <MAIN_FACTORY> "getDeployment()" --rpc-url <NETWORK>
   ```
2. Check IVotesAdapter is set:
   ```bash
   cast call <MAIN_FACTORY> "getIVotesAdapter()" --rpc-url <NETWORK>
   ```
3. If returns zero address: Main DAO deployment failed, redeploy Step 1

### Issue: "Gas estimation failed"

**Error**: Transaction reverts during gas estimation

**Cause**: Not enough gas, or deployment will revert

**Solution**:
1. Increase gas limit:
   ```bash
   --gas-limit 10000000
   ```
2. Check deployer has enough ETH:
   ```bash
   cast balance <DEPLOYER_ADDRESS> --rpc-url <NETWORK>
   ```
3. Check for deployment errors in logs (run with `-vvvv`)

### Issue: "Verification failed on Etherscan"

**Error**: Contract verification fails after deployment

**Cause**: Compiler settings mismatch or Etherscan issues

**Solution**:
1. Check compiler version in `foundry.toml` matches deployed bytecode
2. Verify EVM version matches network
3. Try manual verification:
   ```bash
   forge verify-contract <ADDRESS> <CONTRACT_NAME> \
     --chain-id <CHAIN_ID> \
     --etherscan-api-key <ETHERSCAN_API_KEY>
   ```

---

## Advanced Usage

### Dry Run (Simulation)

#### The Challenge

Standard dry runs don't persist state between scripts, making full end-to-end testing impossible:

```bash
# ❌ This doesn't work for testing the full flow
forge script script/orchestrator/01_DeployMainDao.s.sol --rpc-url sepolia  # State lost
forge script script/orchestrator/02_DeploySubDaos.s.sol --rpc-url sepolia  # Can't read Step 1's addresses
```

#### Solution: Anvil Local Fork

Use anvil to create a persistent local fork where state persists between steps:

**Terminal 1: Start Anvil**
```bash
# Fork from Sepolia (or mainnet)
anvil --fork-url <NETWORK> --port 8545

# Keep this terminal running during the test
```

**Terminal 2: Run Full Deployment Test**
```bash
# Step 1: Deploy main DAO to local fork
forge script script/orchestrator/01_DeployMainDao.s.sol --rpc-url local --broadcast -vvv

# ✅ State persists on anvil
# ✅ Broadcast artifacts are created
# ✅ Manually verify output

# Step 2: Deploy SubDAOs (reads from Step 1's broadcast artifacts)
forge script script/orchestrator/02_DeploySubDaos.s.sol --rpc-url local --broadcast -vvv

# ✅ BroadcastReader successfully reads Step 1's addresses
# ✅ Full end-to-end test complete

# Clean up broadcast artifacts when done
rm -rf broadcast/01_DeployMainDao.s.sol/31337/
rm -rf broadcast/02_DeploySubDaos.s.sol/31337/
```

**Benefits of Anvil Approach:**
- ✅ Tests the actual production flow including BroadcastReader
- ✅ Maintains two-step verification checkpoint
- ✅ State persists between steps (deployed addresses available)
- ✅ No real gas costs
- ✅ Can inspect blockchain state between steps
- ✅ Tests fail-fast mode mismatch detection

**Note**: Chain ID 31337 is anvil's default. The `local` RPC endpoint is configured in `foundry.toml`.

### Deploy Only One SubDAO

If you only need to deploy one SubDAO (not both):

```bash
# Set which config to use
export CONFIG_PATH="config/subdaos/approver-hat-minter.json"

# Deploy single SubDAO
forge script script/DeploySubDao.s.sol \
  --rpc-url <NETWORK> \
  --broadcast \
  -vvv
```

**Use Case**: Testing, incremental deployment, or different SubDAO types

### Redeploying a Failed SubDAO

If one SubDAO deployment fails but the other succeeds:

1. **Don't panic**: Main DAO is fine, other SubDAO is fine
2. **Fix the issue**: Update config, fix parameters, increase gas, etc.
3. **Redeploy just the failed SubDAO**:
   ```bash
   export CONFIG_PATH="config/subdaos/member-curator.json"
   forge script script/DeploySubDao.s.sol \
     --rpc-url <NETWORK> \
     --broadcast \
     -vvv
   ```
4. **Verify**: Run verification checkpoint 2 again

---

## Production Deployment Checklist

### Pre-Deployment

- [ ] All config files reviewed and approved by team
- [ ] Deployer wallet has sufficient ETH (~0.5 ETH on mainnet for gas)
- [ ] All contracts audited and approved
- [ ] All tests passing (`forge test`)
- [ ] **Full dry run completed using anvil** (see [Dry Run section](#dry-run-simulation))
- [ ] Dry run verified: addresses logged, contracts deployed, permissions correct
- [ ] Metadata URIs uploaded to IPFS and pinned
- [ ] Proposer addresses confirmed
- [ ] Simulation run successfully on mainnet fork:
  ```bash
  forge script script/orchestrator/01_DeployMainDao.s.sol \
    --fork-url $MAINNET_RPC_URL \
    -vvv
  ```
- [ ] Team standing by for verification checkpoints
- [ ] Etherscan API key configured for contract verification

### During Deployment

#### After Step 1 (Main DAO):
- [ ] Main DAO factory deployed and verified on Etherscan
- [ ] Factory getters return correct values:
  - [ ] `getIVotesAdapter()` returns non-zero
  - [ ] `getTokenVotingPluginRepo()` returns non-zero
  - [ ] Hat IDs are large uint256 values
- [ ] Main DAO deployment retrieved via `getDeployment()`
- [ ] Main DAO permissions verified on Etherscan:
  - [ ] Token voting has EXECUTE_PERMISSION
  - [ ] Factory does NOT have ROOT_PERMISSION
  - [ ] Plugin setup processor does NOT have ROOT_PERMISSION
- [ ] **CHECKPOINT: Team reviews and approves main DAO**
- [ ] Broadcast artifact saved: `broadcast/01_DeployMainDao.s.sol/<chainId>/run-latest.json`

#### After Step 2 (SubDAOs):
- [ ] Both SubDAO factories deployed successfully
- [ ] Both SubDAOs deployed successfully
- [ ] Both SubDAOs share same IVotesAdapter (verified via getter)
- [ ] Each SubDAO has correct stage2 duration:
  - [ ] Approver-Hat-Minter: 259200 (3 days)
  - [ ] Member-Curator: 86400 (1 day)
- [ ] All permissions verified on Etherscan for both SubDAOs
- [ ] Test proposals created in each SubDAO (testnet only)
- [ ] **CHECKPOINT: Team reviews and approves both SubDAOs**

### Post-Deployment

- [ ] Document all deployed addresses in team wiki/docs:
  - Main DAO Factory
  - Main DAO
  - IVotesAdapter
  - Approver-Hat-Minter Factory & DAO
  - Member-Curator Factory & DAO
- [ ] Update frontend/dApp with new contract addresses
- [ ] Create initial test proposals in each SubDAO
- [ ] Monitor proposals for 24-48 hours
- [ ] Test voting in each SubDAO with team members
- [ ] Test proposal execution in each SubDAO
- [ ] Announce deployment to community (blog post, Twitter, Discord)
- [ ] Archive broadcast artifacts for future reference
- [ ] Update deployment documentation with actual addresses

---

## FAQ

### Q: Can I deploy more than 2 SubDAOs?

**A**: Yes! The orchestrator currently deploys 2 (approver-hat-minter and member-curator), but you can:
1. Add more config files to `config/subdaos/`
2. Update `02_DeploySubDaos.s.sol` to deploy additional SubDAOs
3. Each SubDAO shares the same main DAO infrastructure

### Q: Can I deploy SubDAOs later after main DAO?

**A**: Yes! SubDAOs can be deployed anytime after main DAO:
1. Main DAO is deployed and addresses saved
2. Later (days/weeks), deploy SubDAOs using `script/DeploySubDao.s.sol`
3. Just pass main DAO factory address as parameter

### Q: What if I make a mistake in the config?

**A**: Depends on the mistake:
- **Before deployment**: Fix config, redeploy
- **After main DAO deployment**: Can fix SubDAO configs and redeploy just SubDAOs
- **After SubDAO deployment**: Must deploy new SubDAO factory (old one has `deployOnce()` protection)

### Q: How much does deployment cost?

**Estimates** (gas prices vary):
- **Sepolia testnet**: ~0.01 ETH (cheap)
- **Mainnet (50 gwei)**: ~0.3-0.5 ETH
- **Mainnet (high gas)**: Up to 1 ETH

Always dry-run first to estimate!

### Q: Can SubDAOs interact with each other?

**A**: No, they're independent:
- Separate DAO contracts
- Separate SPP plugin instances
- Separate permissions
- Separate proposal spaces

**But**: They share voting power (same IVotesAdapter), so same users can participate in both.

### Q: What if main DAO factory is on different chain?

**A**: Can't deploy SubDAOs on different chain:
- SubDAOs query main DAO factory via on-chain calls
- Must be on same network (Sepolia, mainnet, etc.)
- If need multi-chain: Deploy separate main DAO per chain

### Q: How do I update a SubDAO after deployment?

**A**: SubDAOs use OSx plugin framework:
- Can upgrade plugins via DAO vote
- Can update permissions via DAO vote
- Can add new plugins via DAO vote
- **Cannot** change factory deployment (it's immutable)

### Q: How do I test the full deployment without spending gas?

**A**: Use the [anvil dry run approach](#dry-run-simulation):

1. Start anvil: `anvil --fork-url $SEPOLIA_RPC_URL`
2. Deploy to local fork: `--rpc-url local --broadcast`
3. State persists between Step 1 and Step 2
4. Tests BroadcastReader and full workflow

**Why not just use `forge script` without `--broadcast`?**
- Standard dry runs don't persist state between scripts
- Step 2 can't read Step 1's addresses
- Anvil creates a persistent local blockchain that mimics production

---

## Support

### Resources

- **Foundry Documentation**: https://book.getfoundry.sh/
- **Aragon OSx Docs**: https://devs.aragon.org/
- **Hats Protocol Docs**: https://docs.hatsprotocol.xyz/

### Getting Help

1. **Check troubleshooting section** above
2. **Review test files** in `test/orchestrator/` for examples
3. **Review deployment logs** with `-vvvv` flag for detailed traces
4. **Check Etherscan** for contract verification and transaction details
5. **Contact team** if issue persists

---

## Changelog

### v1.0.0 (Initial Release)
- Orchestrated deployment for main DAO + 2 SubDAOs
- Verification checkpoints between steps
- BroadcastReader for artifact parsing
- Support for approver-hat-minter and member-curator SubDAOs

---

**Next Steps**: After successful deployment, see post-deployment checklist above.

**Questions?**: Contact the team or review test files for examples.
