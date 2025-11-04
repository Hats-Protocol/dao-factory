# DAO Factory Permissions Analysis

**Generated**: 2025-10-27
**System Version**: 1.0.0
**Network**: Sepolia (deployed configuration)

## Overview

This document provides a comprehensive list of all permissions that exist in the DAO system post-deployment. The system deploys an Aragon OSx DAO with three main plugin systems:

1. **VE (Voting Escrow) System** - A complete vote-escrowed governance system with 7 components
2. **TokenVotingHats Plugin** - A Hats Protocol-gated governance plugin
3. **Admin Plugin** - Emergency administrative capabilities

## Permission Structure

Each permission in the system is defined by:
- **Where**: The contract address where the permission is granted
- **Who**: The address/entity that receives the permission
- **Permission ID**: The specific permission identifier (keccak256 hash)
- **Condition**: Optional permission condition contract (e.g., for Hats-gated access)
- **Purpose**: What the permission enables

---

## 1. DAO Core Permissions

### 1.1 ROOT_PERMISSION_ID
- **Where**: DAO
- **Who**: DAO itself
- **Permission ID**: `ROOT_PERMISSION_ID` (from DAO.sol)
- **Purpose**: Highest-level permission allowing management of all other permissions
- **Status**: Granted during deployment, revoked from factory at end

### 1.2 EXECUTE_PERMISSION_ID (on DAO)
Multiple grants of the EXECUTE permission on the DAO allow different entities to execute actions:

#### 1.2.1 TokenVotingHats Plugin → DAO
- **Where**: DAO
- **Who**: TokenVotingHats plugin
- **Permission ID**: `keccak256("EXECUTE_PERMISSION")`
- **Purpose**: Allows the TokenVotingHats plugin to execute approved proposals on the DAO

#### 1.2.2 Admin Plugin → DAO
- **Where**: DAO
- **Who**: Admin plugin
- **Permission ID**: `keccak256("EXECUTE_PERMISSION")`
- **Purpose**: Allows the Admin plugin to execute administrative actions on the DAO

---

## 2. VE (Voting Escrow) System Permissions

The VE system consists of 7 interconnected components. Permissions are granted to:
- The DAO (for administrative control)
- Component-to-component interactions (for system functionality)

### 2.1 VotingEscrow (Main Plugin)

The VotingEscrow is the "plugin" entry point for the VE system.

#### 2.1.1 ESCROW_ADMIN_ROLE (DAO)
- **Where**: VotingEscrow
- **Who**: DAO
- **Permission ID**: `VotingEscrow.ESCROW_ADMIN_ROLE()` = `keccak256("ESCROW_ADMIN")`
- **Purpose**: Allows DAO to:
  - Set curve implementation (`setCurve`)
  - Set exit queue implementation (`setQueue`)
  - Set lock NFT implementation (`setLockNFT`)
  - Set IVotes adapter implementation (`setIVotesAdapter`)
  - Set voter implementation (`setVoter`)
  - Administrative configuration of the escrow system
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)

#### 2.1.2 ESCROW_ADMIN_ROLE (ExitQueue → VotingEscrow)
- **Where**: VotingEscrow
- **Who**: ExitQueue
- **Permission ID**: `VotingEscrow.ESCROW_ADMIN_ROLE()`
- **Purpose**: Allows ExitQueue to modify escrow state when users withdraw their locked tokens
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)

#### 2.1.3 ESCROW_ADMIN_ROLE (Lock → VotingEscrow)
- **Where**: VotingEscrow
- **Who**: Lock (NFT)
- **Permission ID**: `VotingEscrow.ESCROW_ADMIN_ROLE()`
- **Purpose**: Allows Lock NFT to modify escrow state when NFTs are minted, transferred, or burned
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)

#### 2.1.4 PAUSER_ROLE (DAO)
- **Where**: VotingEscrow
- **Who**: DAO
- **Permission ID**: `VotingEscrow.PAUSER_ROLE()` = `keccak256("PAUSER")`
- **Purpose**: Allows DAO to pause/unpause the VotingEscrow in emergency situations
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)

#### 2.1.5 SWEEPER_ROLE (DAO)
- **Where**: VotingEscrow
- **Who**: DAO
- **Permission ID**: `VotingEscrow.SWEEPER_ROLE()` = `keccak256("SWEEPER")`
- **Purpose**: Allows DAO to sweep accidentally sent tokens from the escrow contract
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)

### 2.2 Curve (Voting Power Curve)

#### 2.2.1 CURVE_ADMIN_ROLE (DAO)
- **Where**: Curve (LinearIncreasingCurve)
- **Who**: DAO
- **Permission ID**: `Curve.CURVE_ADMIN_ROLE()` = `keccak256("CURVE_ADMIN_ROLE")`
- **Purpose**: Allows DAO to modify curve parameters that determine voting power over time
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)
- **Configuration**: Flat curve (constant=1e18, linear=0, quadratic=0, maxEpochs=0)

### 2.3 ExitQueue (Token Withdrawal Queue)

#### 2.3.1 QUEUE_ADMIN_ROLE (DAO)
- **Where**: ExitQueue (DynamicExitQueue)
- **Who**: DAO
- **Permission ID**: `ExitQueue.QUEUE_ADMIN_ROLE()` = `keccak256("QUEUE_ADMIN")`
- **Purpose**: Allows DAO to:
  - Update cooldown period
  - Update minimum lock duration
  - Update withdrawal fee percentage
  - Configure queue parameters
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)
- **Configuration**: No cooldown period (0), No fee (0%)

#### 2.3.2 WITHDRAW_ROLE (DAO)
- **Where**: ExitQueue
- **Who**: DAO
- **Permission ID**: `ExitQueue.WITHDRAW_ROLE()` = `keccak256("WITHDRAW_ROLE")`
- **Purpose**: Allows DAO to withdraw accumulated fees from the exit queue
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)

### 2.4 Lock (NFT Representation)

#### 2.4.1 LOCK_ADMIN_ROLE (DAO)
- **Where**: Lock (ERC721 NFT)
- **Who**: DAO
- **Permission ID**: `Lock.LOCK_ADMIN_ROLE()` = `keccak256("LOCK_ADMIN")`
- **Purpose**: Allows DAO to perform administrative operations on the Lock NFT contract
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)

#### 2.4.2 LOCK_ADMIN_ROLE (VotingEscrow → Lock)
- **Where**: Lock (NFT)
- **Who**: VotingEscrow
- **Permission ID**: `Lock.LOCK_ADMIN_ROLE()`
- **Purpose**: Allows VotingEscrow to mint/burn Lock NFTs when users create/destroy locks
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)

### 2.5 IVotesAdapter (Delegation Adapter)

The IVotesAdapter (SelfDelegationEscrowIVotesAdapter) exposes the VE system as an IVotes-compatible token for use with governance systems.

#### 2.5.1 DELEGATION_ADMIN_ROLE (DAO)
- **Where**: IVotesAdapter (SelfDelegationEscrowIVotesAdapter)
- **Who**: DAO
- **Permission ID**: `SelfDelegationEscrowIVotesAdapter.DELEGATION_ADMIN_ROLE()` = `keccak256("DELEGATION_ADMIN")`
- **Purpose**: Allows DAO to configure delegation parameters
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)

#### 2.5.2 DELEGATION_TOKEN_ROLE (DAO)
- **Where**: IVotesAdapter
- **Who**: DAO
- **Permission ID**: `SelfDelegationEscrowIVotesAdapter.DELEGATION_TOKEN_ROLE()` = `keccak256("DELEGATION_TOKEN_ROLE")`
- **Purpose**: Allows DAO to manage token-related delegation settings
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)

#### 2.5.3 DELEGATION_TOKEN_ROLE (VotingEscrow → IVotesAdapter)
- **Where**: IVotesAdapter
- **Who**: VotingEscrow
- **Permission ID**: `SelfDelegationEscrowIVotesAdapter.DELEGATION_TOKEN_ROLE()`
- **Purpose**: Allows VotingEscrow to update delegation state when lock balances change
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)

### 2.6 AddressGaugeVoter (Gauge Voting System)

#### 2.6.1 GAUGE_ADMIN_ROLE (DAO)
- **Where**: AddressGaugeVoter
- **Who**: DAO
- **Permission ID**: `AddressGaugeVoter.GAUGE_ADMIN_ROLE()` = `keccak256("GAUGE_ADMIN")`
- **Purpose**: Allows DAO to:
  - Add new gauges for voting
  - Remove gauges
  - Configure gauge parameters
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)

#### 2.6.2 EXECUTE_PERMISSION (DAO)
- **Where**: AddressGaugeVoter
- **Who**: DAO
- **Permission ID**: `keccak256("EXECUTE_PERMISSION")`
- **Purpose**: Allows DAO to execute approved gauge actions
- **Granted in**: [VESystemSetup.sol](src/VESystemSetup.sol)

### 2.7 Clock (Time Management)

The Clock component has no permissions - it is a pure utility contract used by other components to track time and epochs.

---

## 3. TokenVotingHats Plugin Permissions

The TokenVotingHats plugin extends the standard Aragon TokenVoting plugin with Hats Protocol integration, gating proposal creation, voting, and execution behind specific Hat IDs.

### 3.1 DAO Administrative Permissions

#### 3.1.1 UPDATE_VOTING_SETTINGS_PERMISSION_ID (DAO)
- **Where**: TokenVotingHats plugin
- **Who**: DAO
- **Permission ID**: `TokenVotingHats.UPDATE_VOTING_SETTINGS_PERMISSION_ID()` = `keccak256("UPDATE_VOTING_SETTINGS_PERMISSION")`
- **Purpose**: Allows DAO to update voting parameters:
  - Voting mode (Standard/EarlyExecution/VoteReplacement)
  - Support threshold
  - Minimum participation
  - Minimum duration
  - Minimum proposer voting power
- **Granted in**: [TokenVotingSetupHats.sol](lib/token-voting-plugin/src/TokenVotingSetupHats.sol)

#### 3.1.2 SET_TARGET_CONFIG_PERMISSION_ID (DAO)
- **Where**: TokenVotingHats plugin
- **Who**: DAO
- **Permission ID**: `keccak256("SET_TARGET_CONFIG_PERMISSION")`
- **Purpose**: Allows DAO to change which contract the plugin targets for execution
- **Granted in**: [TokenVotingSetupHats.sol](lib/token-voting-plugin/src/TokenVotingSetupHats.sol)

#### 3.1.3 SET_METADATA_PERMISSION_ID (DAO)
- **Where**: TokenVotingHats plugin
- **Who**: DAO
- **Permission ID**: `keccak256("SET_METADATA_PERMISSION")`
- **Purpose**: Allows DAO to update plugin metadata
- **Granted in**: [TokenVotingSetupHats.sol](lib/token-voting-plugin/src/TokenVotingSetupHats.sol)

### 3.2 Hats-Gated Permissions

These permissions use the Hats Protocol to gate access based on whether an address wears a specific Hat.

**Hats Configuration** (from deployment config):
- **Proposer Hat**: `0x0000071e00030001000000000000000000000000000000000000000000000000`
- **Voter Hat**: `0x0000071e00030001000000000000000000000000000000000000000000000000` (same as proposer)
- **Executor Hat**: `0x0000000000000000000000000000000000000000000000000000000000000001` (anyone wearing Hat ID 1)

#### 3.2.1 CREATE_PROPOSAL_PERMISSION_ID (ANY_ADDR with HatsCondition)
- **Where**: TokenVotingHats plugin
- **Who**: `ANY_ADDR` (0xff...ff)
- **Permission ID**: `TokenVotingHats.CREATE_PROPOSAL_PERMISSION_ID()` = `keccak256("CREATE_PROPOSAL_PERMISSION")`
- **Condition**: HatsCondition (checks proposerHatId)
- **Purpose**: Allows anyone wearing the proposer Hat to create proposals
- **Granted in**: [TokenVotingSetupHats.sol](lib/token-voting-plugin/src/TokenVotingSetupHats.sol)
- **Implementation**: HatsCondition checks `IHats(hats).isWearerOfHat(msg.sender, proposerHatId)`

#### 3.2.2 CAST_VOTE_PERMISSION_ID (ANY_ADDR with HatsCondition)
- **Where**: TokenVotingHats plugin
- **Who**: `ANY_ADDR` (0xff...ff)
- **Permission ID**: `TokenVotingHats.CAST_VOTE_PERMISSION_ID()` = `keccak256("CAST_VOTE_PERMISSION")`
- **Condition**: HatsCondition (checks voterHatId)
- **Purpose**: Allows anyone wearing the voter Hat to vote on proposals
- **Granted in**: [TokenVotingSetupHats.sol](lib/token-voting-plugin/src/TokenVotingSetupHats.sol)
- **Implementation**: HatsCondition checks `IHats(hats).isWearerOfHat(msg.sender, voterHatId)`

#### 3.2.3 EXECUTE_PROPOSAL_PERMISSION_ID (ANY_ADDR with HatsCondition)
- **Where**: TokenVotingHats plugin
- **Who**: `ANY_ADDR` (0xff...ff)
- **Permission ID**: `TokenVotingHats.EXECUTE_PROPOSAL_PERMISSION_ID()` = `keccak256("EXECUTE_PROPOSAL_PERMISSION")`
- **Condition**: HatsCondition (checks executorHatId)
- **Purpose**: Allows anyone wearing the executor Hat to execute approved proposals
- **Granted in**: [TokenVotingSetupHats.sol](lib/token-voting-plugin/src/TokenVotingSetupHats.sol)
- **Implementation**: HatsCondition checks `IHats(hats).isWearerOfHat(msg.sender, executorHatId)`

### 3.3 Token Permissions

The TokenVotingHats plugin uses the IVotesAdapter (from the VE system) as its voting token. No additional token permissions are granted since the token is not a new GovernanceERC20 but an existing IVotes implementation.

---

## 4. Admin Plugin Permissions

The Admin plugin provides a direct execution path for a designated administrator address.

**Admin Address** (from deployment config): `0x624123ec4A9f48Be7AA8a307a74381E4ea7530D4`

### 4.1 EXECUTE_PROPOSAL_PERMISSION_ID (Admin Address)
- **Where**: Admin plugin
- **Who**: Admin address (`0x624123ec4A9f48Be7AA8a307a74381E4ea7530D4`)
- **Permission ID**: `keccak256("EXECUTE_PROPOSAL_PERMISSION")`
- **Purpose**: Allows the admin address to directly execute actions through the Admin plugin
- **Granted in**: [AdminSetup.sol](lib/admin-plugin/packages/contracts/src/AdminSetup.sol)

### 4.2 SET_TARGET_CONFIG_PERMISSION_ID (DAO)
- **Where**: Admin plugin
- **Who**: DAO
- **Permission ID**: `keccak256("SET_TARGET_CONFIG_PERMISSION")`
- **Purpose**: Allows DAO to change which contract the Admin plugin targets
- **Granted in**: [AdminSetup.sol](lib/admin-plugin/packages/contracts/src/AdminSetup.sol)

### 4.3 EXECUTE_PERMISSION_ID (Admin Plugin → DAO)
- **Where**: DAO
- **Who**: Admin plugin
- **Permission ID**: `keccak256("EXECUTE_PERMISSION")`
- **Purpose**: Allows the Admin plugin to execute actions on the DAO
- **Granted in**: [AdminSetup.sol](lib/admin-plugin/packages/contracts/src/AdminSetup.sol)

---

## 5. Temporary Factory Permissions

During deployment, the VETokenVotingDaoFactory temporarily receives permissions to install plugins. These are all revoked at the end of deployment.

### 5.1 Temporary ROOT_PERMISSION_ID (Factory)
- **Where**: DAO
- **Who**: VETokenVotingDaoFactory
- **Permission ID**: `ROOT_PERMISSION_ID`
- **Purpose**: Allows factory to install plugins
- **Status**: Granted in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol), **REVOKED** in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol)

### 5.2 Temporary EXECUTE_PERMISSION_ID (Factory)
- **Where**: DAO
- **Who**: VETokenVotingDaoFactory
- **Permission ID**: `EXECUTE_PERMISSION_ID`
- **Purpose**: Allows factory to execute setup actions
- **Status**: Granted in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol), **REVOKED** in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol)

### 5.3 Temporary ESCROW_ADMIN_ROLE (Factory)
- **Where**: VotingEscrow
- **Who**: VETokenVotingDaoFactory
- **Permission ID**: `ESCROW_ADMIN_ROLE`
- **Purpose**: Allows factory to wire VE system components together
- **Status**: Granted in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol), **REVOKED** in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol)

### 5.4 Temporary PluginSetupProcessor Permissions
- **ROOT_PERMISSION_ID on DAO**: Granted/revoked in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol)
- **APPLY_INSTALLATION_PERMISSION_ID on PluginSetupProcessor**: Granted/revoked in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol)

---

## 6. Permission Summary by Entity

### 6.1 DAO Permissions

The DAO has administrative control over all system components:

**On VE System:**
- VotingEscrow: `ESCROW_ADMIN_ROLE`, `PAUSER_ROLE`, `SWEEPER_ROLE`
- Curve: `CURVE_ADMIN_ROLE`
- ExitQueue: `QUEUE_ADMIN_ROLE`, `WITHDRAW_ROLE`
- Lock: `LOCK_ADMIN_ROLE`
- IVotesAdapter: `DELEGATION_ADMIN_ROLE`, `DELEGATION_TOKEN_ROLE`
- AddressGaugeVoter: `GAUGE_ADMIN_ROLE`, `EXECUTE_PERMISSION`

**On Governance Plugins:**
- TokenVotingHats: `UPDATE_VOTING_SETTINGS_PERMISSION_ID`, `SET_TARGET_CONFIG_PERMISSION_ID`, `SET_METADATA_PERMISSION_ID`
- Admin: `SET_TARGET_CONFIG_PERMISSION_ID`

**On Itself:**
The DAO grants itself five core permissions during deployment via DAOFactory:
- `ROOT_PERMISSION_ID` - Allows managing all other permissions
- `UPGRADE_DAO_PERMISSION_ID` - Allows upgrading the DAO implementation
- `SET_TRUSTED_FORWARDER_PERMISSION_ID` - Allows setting meta-transaction forwarder
- `SET_METADATA_PERMISSION_ID` - Allows updating DAO metadata
- `REGISTER_STANDARD_CALLBACK_PERMISSION_ID` - Allows registering standard callbacks
- **Granted in**: DAOFactory during DAO creation

### 6.2 TokenVotingHats Plugin Permissions

**On DAO:**
- `EXECUTE_PERMISSION_ID` (can execute approved proposals)

**Receives from ANY_ADDR (via HatsCondition):**
- Proposal creation (proposer Hat wearers)
- Vote casting (voter Hat wearers)
- Proposal execution (executor Hat wearers)

### 6.3 Admin Plugin Permissions

**On DAO:**
- `EXECUTE_PERMISSION_ID` (can execute actions)

**Receives from Admin Address:**
- `EXECUTE_PROPOSAL_PERMISSION_ID` (admin can trigger execution)

### 6.4 Admin Address Direct Permissions

The admin address (`0x624123ec4A9f48Be7AA8a307a74381E4ea7530D4`) has:
- `EXECUTE_PROPOSAL_PERMISSION_ID` on Admin plugin (can directly execute actions through Admin plugin)

### 6.5 Hat Wearers (via HatsCondition)

Anyone wearing the appropriate Hats Protocol hat can:
- **Proposer Hat** (`0x0000071e00030001000000000000000000000000000000000000000000000000`): Create proposals in TokenVotingHats
- **Voter Hat** (`0x0000071e00030001000000000000000000000000000000000000000000000000`): Cast votes in TokenVotingHats
- **Executor Hat** (`0x0000000000000001`): Execute approved proposals in TokenVotingHats

### 6.6 Component-to-Component Permissions

Internal system permissions for VE components:
- ExitQueue → VotingEscrow: `ESCROW_ADMIN_ROLE`
- Lock → VotingEscrow: `ESCROW_ADMIN_ROLE`
- VotingEscrow → Lock: `LOCK_ADMIN_ROLE`
- VotingEscrow → IVotesAdapter: `DELEGATION_TOKEN_ROLE`

### 6.7 SubDAO Permissions Summary

**Per SubDAO:**
- SPP Plugin → SubDAO: `EXECUTE_PROPOSAL_PERMISSION_ID`
- SPP Plugin → TokenVotingHats: `CREATE_PROPOSAL_PERMISSION_ID`
- TokenVotingHats → SubDAO: `EXECUTE_PERMISSION_ID`
- Admin Plugin → SubDAO: `EXECUTE_PERMISSION_ID`
- Controller or Hat Wearers → SPP: `CREATE_PROPOSAL_PERMISSION_ID` (mode-dependent)
- Hat Wearers → TokenVotingHats: Proposal creation, voting, execution (via HatsCondition)

**Shared from Main DAO:**
- IVotesAdapter: Voting power for all SubDAOs
- Hat IDs: Governance permissions for all SubDAOs
- HatsCondition: Permission validation for all SubDAOs

---

## 7. Permission Flow Diagrams

### 7.1 Proposal Execution Flow (TokenVotingHats)

```
1. Proposer (wearing proposerHat)
   └─> CREATE_PROPOSAL on TokenVotingHats
       └─> Creates proposal

2. Voters (wearing voterHat)
   └─> CAST_VOTE on TokenVotingHats
       └─> Vote on proposal

3. Executor (wearing executorHat)
   └─> EXECUTE_PROPOSAL on TokenVotingHats
       └─> EXECUTE on DAO
           └─> Executes actions
```

### 7.2 Admin Execution Flow

```
Admin Address (0x624123...)
└─> EXECUTE_PROPOSAL on Admin Plugin
    └─> EXECUTE on DAO
        └─> Executes actions
```

### 7.3 DAO Administrative Control

```
DAO Governance (via proposals)
├─> VE System Configuration
│   ├─> VotingEscrow: pause, set components
│   ├─> Curve: update parameters
│   ├─> ExitQueue: update cooldown/fees
│   ├─> Lock: admin operations
│   ├─> IVotesAdapter: delegation config
│   └─> AddressGaugeVoter: gauge management
│
└─> Plugin Configuration
    ├─> TokenVotingHats: voting settings
    └─> Admin: target configuration
```

---

## 8. Security Considerations

### 8.1 Critical Permissions

The following permissions represent the highest risk if compromised:

1. **DAO ROOT_PERMISSION_ID**: Can modify all other permissions
2. **Admin Address EXECUTE_PROPOSAL_PERMISSION**: Direct execution path bypassing governance
3. **DAO ESCROW_ADMIN_ROLE on VotingEscrow**: Can modify core escrow behavior

### 8.2 Hats Protocol Dependencies

The governance system depends on Hats Protocol for access control:
- **Single Point of Failure**: If Hats Protocol is compromised, governance access is compromised
- **Hat Transferability**: Governance rights transfer with Hats
- **Hat Admin Control**: Whoever controls the Hats tree structure controls governance access

### 8.3 Component Interaction Permissions

Several components have ADMIN permissions on each other, creating trust relationships:
- ExitQueue can modify VotingEscrow state
- Lock NFT can modify VotingEscrow state
- VotingEscrow can modify Lock NFT state
- VotingEscrow can modify IVotesAdapter state

These are necessary for system functionality but represent attack vectors if any component is compromised.

### 8.4 Emergency Response

The DAO has several emergency response capabilities:
- **PAUSER_ROLE**: Can pause VotingEscrow operations
- **SWEEPER_ROLE**: Can recover accidentally sent tokens
- **Admin Plugin**: Provides emergency execution path

---

## 9. Permission Modification

### 9.1 How to Modify Permissions

All permissions (except Admin plugin's EXECUTE_PROPOSAL_PERMISSION) can be modified through DAO governance:

1. Create proposal via TokenVotingHats (requires proposer Hat)
2. Vote on proposal (requires voter Hat)
3. Execute proposal (requires executor Hat)
4. Proposal calls `DAO.grant()` or `DAO.revoke()`

### 9.2 Cannot Be Modified Without Governance

- All DAO administrative roles
- All VE system administrative roles
- TokenVotingHats plugin settings and permissions
- Admin plugin target configuration

### 9.3 Can Be Modified By Admin Address

The Admin address (`0x624123ec4A9f48Be7AA8a307a74381E4ea7530D4`) can potentially execute any action on the DAO, including permission modifications, through the Admin plugin without going through governance.

---

## Appendix A: Permission ID Reference

### Core DAO Permissions
```solidity
ROOT_PERMISSION_ID = dao.ROOT_PERMISSION_ID()
EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION")
UPGRADE_DAO_PERMISSION_ID = dao.UPGRADE_DAO_PERMISSION_ID()
SET_TRUSTED_FORWARDER_PERMISSION_ID = dao.SET_TRUSTED_FORWARDER_PERMISSION_ID()
SET_METADATA_PERMISSION_ID = dao.SET_METADATA_PERMISSION_ID()
REGISTER_STANDARD_CALLBACK_PERMISSION_ID = dao.REGISTER_STANDARD_CALLBACK_PERMISSION_ID()
```

### VE System Permissions
```solidity
// VotingEscrow
ESCROW_ADMIN_ROLE = keccak256("ESCROW_ADMIN")
PAUSER_ROLE = keccak256("PAUSER")
SWEEPER_ROLE = keccak256("SWEEPER")

// Curve
CURVE_ADMIN_ROLE = keccak256("CURVE_ADMIN_ROLE")

// ExitQueue
QUEUE_ADMIN_ROLE = keccak256("QUEUE_ADMIN")
WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE")

// Lock
LOCK_ADMIN_ROLE = keccak256("LOCK_ADMIN")

// IVotesAdapter
DELEGATION_ADMIN_ROLE = keccak256("DELEGATION_ADMIN")
DELEGATION_TOKEN_ROLE = keccak256("DELEGATION_TOKEN_ROLE")

// AddressGaugeVoter
GAUGE_ADMIN_ROLE = keccak256("GAUGE_ADMIN")
```

### TokenVotingHats Permissions
```solidity
UPDATE_VOTING_SETTINGS_PERMISSION_ID = keccak256("UPDATE_VOTING_SETTINGS_PERMISSION")
CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION")
CAST_VOTE_PERMISSION_ID = keccak256("CAST_VOTE_PERMISSION")
EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION")
SET_TARGET_CONFIG_PERMISSION_ID = keccak256("SET_TARGET_CONFIG_PERMISSION")
SET_METADATA_PERMISSION_ID = keccak256("SET_METADATA_PERMISSION")
```

### Admin Plugin Permissions
```solidity
EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION")
SET_TARGET_CONFIG_PERMISSION_ID = keccak256("SET_TARGET_CONFIG_PERMISSION")
```

### Staged Proposal Processor (SPP) Permissions
```solidity
CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION")
EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION")
// Note: SPP uses approval/veto rules configured via RuledCondition
```

---

## Appendix B: Source Code References

### Factory
- **VETokenVotingDaoFactory.sol**: [src/VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol)

### VE System
- **VESystemSetup.sol**: [src/VESystemSetup.sol](src/VESystemSetup.sol)
- **VotingEscrow**: `lib/ve-governance/src/escrow/VotingEscrowIncreasing_v1_2_0.sol`
- **Clock**: `lib/ve-governance/src/clock/Clock_v1_2_0.sol`
- **Curve**: `lib/ve-governance/src/curve/LinearIncreasingCurve.sol`
- **ExitQueue**: `lib/ve-governance/src/queue/DynamicExitQueue.sol`
- **Lock**: `lib/ve-governance/src/lock/Lock_v1_2_0.sol`
- **IVotesAdapter**: `lib/ve-governance/src/delegation/SelfDelegationEscrowIVotesAdapter.sol`
- **AddressGaugeVoter**: `lib/ve-governance/src/voting/AddressGaugeVoter.sol`

### Plugins
- **TokenVotingSetupHats.sol**: [lib/token-voting-plugin/src/TokenVotingSetupHats.sol](lib/token-voting-plugin/src/TokenVotingSetupHats.sol)
- **TokenVotingHats.sol**: `lib/token-voting-plugin/src/TokenVotingHats.sol`
- **HatsCondition.sol**: `lib/token-voting-plugin/src/condition/HatsCondition.sol`
- **AdminSetup.sol**: [lib/admin-plugin/packages/contracts/src/AdminSetup.sol](lib/admin-plugin/packages/contracts/src/AdminSetup.sol)
- **Admin.sol**: `lib/admin-plugin/packages/contracts/src/Admin.sol`

### Deployment Scripts
- **DeployDao.s.sol**: [script/DeployDao.s.sol](script/DeployDao.s.sol)
- **DeploySubDao.s.sol**: [script/DeploySubDao.s.sol](script/DeploySubDao.s.sol)
- **Orchestrator**: [script/orchestrator/](script/orchestrator/)

### SubDAO Factory
- **SubDaoFactory.sol**: [src/SubDaoFactory.sol](src/SubDaoFactory.sol)
- **Staged Proposal Processor Plugin**: `lib/staged-proposal-processor-plugin/`

---

## 10. SubDAO Permissions

The SubDAO system extends the main DAO with configurable sub-DAOs that implement two-stage governance through the Staged Proposal Processor (SPP) plugin.

### 10.1 SubDAO Architecture

Each SubDAO consists of:
1. **Independent DAO**: Each SubDAO gets its own Aragon OSx DAO instance
2. **Stage 1 (SPP Plugin)**: Initial proposal stage with veto or approval mode
3. **Stage 2 (TokenVotingHats Plugin)**: Full governance voting using main DAO's VE system
4. **Admin Plugin**: Emergency execution capability

**Shared Infrastructure from Main DAO:**
- IVotesAdapter (voting power)
- Hat IDs (for Stage 2 permissions)
- HatsCondition contract

### 10.2 Stage 1: Staged Proposal Processor (SPP) Permissions

The SPP plugin manages the first governance stage with two operating modes.

#### 10.2.1 CREATE_PROPOSAL_PERMISSION_ID (Mode-Dependent)

**Veto Mode** (approver-hat-minter SubDAO):
- **Where**: SPP Plugin
- **Who**: Controller Address directly (`0x2D7473039D40d26789981c907AbE9D37bf463e4E`)
- **Permission ID**: `keccak256("CREATE_PROPOSAL_PERMISSION")`
- **Purpose**: Allows controller to create proposals that default to "approved" unless explicitly vetoed by the controller
- **Configuration**: `proposerHatId = 0` (triggers direct grant to controller only)
- **Stage 1 Body**: Single member (controller address) with veto capability
- **Granted in**: [SubDaoFactory.sol](src/SubDaoFactory.sol)

**Note**: In veto mode with `proposerHatId = 0`, only the designated controller address can create proposals AND exercise veto power in Stage 1. The Stage 1 voting body consists exclusively of the controller address.

**Approve Mode** (member-curator SubDAO):
- **Where**: SPP Plugin
- **Who**: `ANY_ADDR` (0xff...ff)
- **Condition**: HatsCondition (checks proposerHatId from main DAO)
- **Permission ID**: `keccak256("CREATE_PROPOSAL_PERMISSION")`
- **Purpose**: Anyone wearing the proposer Hat can create proposals (requires explicit approval)
- **Configuration**: `proposerHatId` auto-set to main DAO proposer hat during deployment
- **Granted in**: [SubDaoFactory.sol](src/SubDaoFactory.sol)

**Note**: The deployment script automatically populates `stage1.proposerHatId` with the main DAO's proposer hat when the config value is 0 in approve mode ([DeploySubDao.s.sol](script/DeploySubDao.s.sol)). This means approve mode SubDAOs are always hat-gated in the deployed configuration. To implement direct grant to a controller address instead, set a non-zero `proposerHatId` in the config and modify the factory logic accordingly.

#### 10.2.2 EXECUTE_PROPOSAL_PERMISSION_ID (SPP → SubDAO)
- **Where**: SubDAO
- **Who**: SPP Plugin
- **Permission ID**: `keccak256("EXECUTE_PROPOSAL_PERMISSION")`
- **Purpose**: Allows SPP to execute proposals that pass Stage 1
- **Granted in**: [SubDaoFactory.sol](src/SubDaoFactory.sol)

#### 10.2.3 CREATE_PROPOSAL_PERMISSION_ID (SPP → TokenVotingHats)
- **Where**: TokenVotingHats Plugin (Stage 2)
- **Who**: SPP Plugin
- **Permission ID**: `keccak256("CREATE_PROPOSAL_PERMISSION")`
- **Purpose**: Allows SPP to create sub-proposals in Stage 2 when advancing proposals
- **Granted in**: [SubDaoFactory.sol](src/SubDaoFactory.sol)

### 10.3 Stage 2: TokenVotingHats Plugin Permissions

SubDAO Stage 2 uses the main DAO's hat IDs and voting infrastructure.

#### 10.3.1 UPDATE_VOTING_SETTINGS_PERMISSION_ID (DAO)
- **Where**: TokenVotingHats plugin
- **Who**: SubDAO
- **Permission ID**: `keccak256("UPDATE_VOTING_SETTINGS_PERMISSION")`
- **Purpose**: Allows SubDAO to update Stage 2 voting parameters
- **Granted in**: TokenVotingSetupHats during plugin installation

#### 10.3.2 CREATE_PROPOSAL_PERMISSION_ID (SPP + Hat Wearers)
- **Where**: TokenVotingHats plugin
- **Who**: Both SPP Plugin (from Stage 1) and ANY_ADDR with HatsCondition
- **Condition**: HatsCondition (checks main DAO's proposer hat)
- **Purpose**: SPP advances proposals; hat wearers can create direct Stage 2 proposals
- **Granted in**: TokenVotingSetupHats + [SubDaoFactory.sol](src/SubDaoFactory.sol)

#### 10.3.3 CAST_VOTE_PERMISSION_ID (ANY_ADDR with HatsCondition)
- **Where**: TokenVotingHats plugin
- **Who**: `ANY_ADDR` (0xff...ff)
- **Condition**: HatsCondition (checks main DAO's voter hat)
- **Purpose**: Anyone wearing the main DAO's voter Hat can vote on Stage 2 proposals
- **Hat ID**: Shared with main DAO (e.g., `0x0000071e00030000...`)
- **Granted in**: TokenVotingSetupHats during plugin installation

#### 10.3.4 EXECUTE_PROPOSAL_PERMISSION_ID (ANY_ADDR with HatsCondition)
- **Where**: TokenVotingHats plugin
- **Who**: `ANY_ADDR` (0xff...ff)
- **Condition**: HatsCondition (checks main DAO's executor hat)
- **Purpose**: Anyone wearing the main DAO's executor Hat can execute approved proposals
- **Hat ID**: Shared with main DAO
- **Granted in**: TokenVotingSetupHats during plugin installation

#### 10.3.5 EXECUTE_PERMISSION_ID (TokenVotingHats → SubDAO)
- **Where**: SubDAO
- **Who**: TokenVotingHats Plugin
- **Permission ID**: `keccak256("EXECUTE_PERMISSION")`
- **Purpose**: Allows TokenVotingHats to execute approved proposals on the SubDAO
- **Granted in**: TokenVotingSetupHats during plugin installation

### 10.4 Admin Plugin Permissions (Per SubDAO)

Each SubDAO has its own Admin plugin instance with the same admin address.

#### 10.4.1 EXECUTE_PROPOSAL_PERMISSION_ID (Admin Address)
- **Where**: SubDAO Admin plugin
- **Who**: Admin address (`0x624123ec4A9f48Be7AA8a307a74381E4ea7530D4`)
- **Permission ID**: `keccak256("EXECUTE_PROPOSAL_PERMISSION")`
- **Purpose**: Allows admin to directly execute actions through the SubDAO's Admin plugin
- **Granted in**: AdminSetup during plugin installation

#### 10.4.2 EXECUTE_PERMISSION_ID (Admin Plugin → SubDAO)
- **Where**: SubDAO
- **Who**: SubDAO Admin plugin
- **Permission ID**: `keccak256("EXECUTE_PERMISSION")`
- **Purpose**: Allows Admin plugin to execute actions on the SubDAO
- **Granted in**: AdminSetup during plugin installation

### 10.5 SubDAO Configuration Examples

#### 10.5.1 Approver Hat Minter (Veto Mode)
**Purpose**: Default-allow governance with veto capability

**Stage 1 Configuration:**
- Mode: `veto`
- Controller: Direct grant to `0x2D7473039D40d26789981c907AbE9D37bf463e4E`
- `proposerHatId`: `0` (triggers direct grant to controller only)
- Vote Duration: 3600 seconds (1 hour)
- Approval Threshold: `0` (auto-approve unless vetoed)
- Veto Threshold: `1` (controller is sole Stage 1 body member with veto power)

**Stage 2 Configuration:**
- Min Duration: 259200 seconds (3 days)
- Reuses main DAO hat IDs for voting

#### 10.5.2 Member Curator (Approve Mode)
**Purpose**: Default-block governance requiring explicit approval

**Stage 1 Configuration:**
- Mode: `approve`
- Controller: `0x2D7473039D40d26789981c907AbE9D37bf463e4E` (for approval/veto actions)
- `proposerHatId`: `0` in config → auto-converted to main DAO proposer hat during deployment
- **Actual Deployment**: Hat-based proposal creation (anyone wearing main DAO proposer hat can create proposals)
- Vote Duration: 604800 seconds (7 days)
- Max Advance: 3155760000 seconds (~100 years - once approved, can advance any time)
- Approval Threshold: `1` (requires explicit approval)
- Veto Threshold: `0` (no veto capability)

**Stage 2 Configuration:**
- Min Duration: 86400 seconds (1 day)
- Reuses main DAO hat IDs for voting

### 10.6 Permission Flow Diagrams

#### 10.6.1 Veto Mode Flow (approver-hat-minter)

```
1. Controller creates proposal in SPP (Stage 1)
   └─> Proposal auto-approved after minAdvance if controller doesn't veto

2. Controller can veto in Stage 1 (sole Stage 1 body member)
   └─> Veto blocks proposal from advancing

3. SPP advances to TokenVotingHats (Stage 2)
   └─> CREATE_PROPOSAL on TokenVotingHats

4. Hat wearers vote in Stage 2
   └─> CAST_VOTE on TokenVotingHats

5. Hat wearers execute
   └─> EXECUTE_PROPOSAL on TokenVotingHats
       └─> EXECUTE on SubDAO
```

#### 10.6.2 Approve Mode Flow (member-curator)

```
1. Hat wearers (wearing main DAO proposer hat) create proposal in SPP (Stage 1)
   └─> Proposal defaults to "blocked" state

2. Controller must explicitly approve
   └─> Approval allows proposal to advance after voteDuration

3. SPP advances to TokenVotingHats (Stage 2)
   └─> CREATE_PROPOSAL on TokenVotingHats

4. Hat wearers vote in Stage 2
   └─> CAST_VOTE on TokenVotingHats

5. Hat wearers execute
   └─> EXECUTE_PROPOSAL on TokenVotingHats
       └─> EXECUTE on SubDAO
```

### 10.7 Shared Infrastructure

SubDAOs reuse critical infrastructure from the main DAO:

#### 10.7.1 IVotesAdapter (Voting Power)
- **Where**: Main DAO's SelfDelegationEscrowIVotesAdapter
- **Used By**: All SubDAO TokenVotingHats plugins (Stage 2)
- **Purpose**: Provides voting power based on main DAO's VE locks
- **Benefit**: Unified voting power across all SubDAOs

#### 10.7.2 Hat IDs (Stage 2 Governance)
- **Proposer Hat**: Shared across main DAO and all SubDAOs
- **Voter Hat**: Shared across main DAO and all SubDAOs
- **Executor Hat**: Shared across main DAO and all SubDAOs
- **Benefit**: Consistent governance permissions across the entire DAO system

#### 10.7.3 HatsCondition Contract
- **Where**: Deployed by main DAO factory
- **Used By**: All SubDAOs for hat-based permission checks
- **Purpose**: Validates hat ownership for conditional permissions

### 10.8 Temporary SubDAO Factory Permissions

During SubDAO deployment, the SubDaoFactory temporarily receives permissions that are revoked at the end.

#### 10.8.1 Temporary ROOT_PERMISSION_ID (Factory)
- **Where**: SubDAO
- **Who**: SubDaoFactory
- **Purpose**: Allows factory to install plugins
- **Status**: Granted in [SubDaoFactory.sol](src/SubDaoFactory.sol), **REVOKED** in [SubDaoFactory.sol](src/SubDaoFactory.sol)

#### 10.8.2 Temporary EXECUTE_PERMISSION_ID (Factory)
- **Where**: SubDAO
- **Who**: SubDaoFactory
- **Purpose**: Allows factory to execute setup actions
- **Status**: Granted in [SubDaoFactory.sol](src/SubDaoFactory.sol), **REVOKED** in [SubDaoFactory.sol](src/SubDaoFactory.sol)

#### 10.8.3 Temporary PluginSetupProcessor Permissions
- **ROOT_PERMISSION_ID on SubDAO**: Granted/revoked in [SubDaoFactory.sol](src/SubDaoFactory.sol)
- **APPLY_INSTALLATION_PERMISSION_ID**: Granted/revoked in [SubDaoFactory.sol](src/SubDaoFactory.sol)

### 10.9 Security Considerations for SubDAOs

#### 10.9.1 Stage 1 Controller Risk
- **Veto Mode**: Controller has veto power and can block proposals
- **Approve Mode**: Controller must approve proposals for them to advance
- **Mitigation**: Controller address should be a trusted multisig or smart contract

#### 10.9.2 Stage Bypass Risk
- **Risk**: SPP has CREATE_PROPOSAL permission on TokenVotingHats, could potentially bypass Stage 1
- **Mitigation**: Only SPP-created proposals should be executed; direct Stage 2 proposals should be carefully monitored

#### 10.9.3 Shared Voting Power
- **Risk**: All SubDAOs share the same voting power (IVotesAdapter) from main DAO
- **Benefit**: Consistent voting power across the system
- **Consideration**: Large VE lock holders have influence across all SubDAOs

#### 10.9.4 Hat-Based Permission Dependencies
- **Risk**: SubDAOs depend on main DAO's hat structure
- **Single Point of Control**: Whoever controls the main DAO's Hats tree controls SubDAO Stage 2 governance
- **Mitigation**: Main DAO hat admin should be carefully secured

---

**Document Version**: 1.1
**Last Updated**: 2025-11-03
**Total Permissions Granted**:
- Main DAO: 32 (excluding 5 temporary permissions revoked at deployment end)
- Per SubDAO: ~15 (excluding 4 temporary permissions revoked at deployment end)
- Total for system with 2 SubDAOs: ~62 active permissions
