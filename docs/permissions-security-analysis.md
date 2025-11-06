# DAO Factory Permissions: Security Analysis

**Generated**: 2025-11-03
**System Version**: 1.0.0
**Network**: Sepolia (deployed configuration)

> **Note**: For a summary of what permissions exist post-deployment, see [permissions-analysis.md](permissions-analysis.md)

## Overview

This document provides security analysis, permission flows, modification procedures, and technical references for the DAO Factory permission system. It complements the main permissions analysis document with operational and security details.

---

## 1. Temporary Factory Permissions

During deployment, the VETokenVotingDaoFactory temporarily receives permissions to install plugins. These are all revoked at the end of deployment.

### 1.1 Main DAO Temporary Permissions

#### 1.1.1 Temporary ROOT_PERMISSION_ID (Factory)
- **Where**: DAO
- **Who**: VETokenVotingDaoFactory
- **Permission ID**: `ROOT_PERMISSION_ID`
- **Purpose**: Allows factory to install plugins
- **Status**: Granted in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol), **REVOKED** in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol)

#### 1.1.2 Temporary EXECUTE_PERMISSION_ID (Factory)
- **Where**: DAO
- **Who**: VETokenVotingDaoFactory
- **Permission ID**: `EXECUTE_PERMISSION_ID`
- **Purpose**: Allows factory to execute setup actions
- **Status**: Granted in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol), **REVOKED** in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol)

#### 1.1.3 Temporary ESCROW_ADMIN_ROLE (Factory)
- **Where**: VotingEscrow
- **Who**: VETokenVotingDaoFactory
- **Permission ID**: `ESCROW_ADMIN_ROLE`
- **Purpose**: Allows factory to wire VE system components together
- **Status**: Granted in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol), **REVOKED** in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol)

#### 1.1.4 Temporary PluginSetupProcessor Permissions
- **ROOT_PERMISSION_ID on DAO**: Granted/revoked in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol)
- **APPLY_INSTALLATION_PERMISSION_ID on PluginSetupProcessor**: Granted/revoked in [VETokenVotingDaoFactory.sol](src/VETokenVotingDaoFactory.sol)

### 1.2 SubDAO Temporary Permissions

During SubDAO deployment, the SubDaoFactory temporarily receives permissions that are revoked at the end.

#### 1.2.1 Temporary ROOT_PERMISSION_ID (Factory)
- **Where**: SubDAO
- **Who**: SubDaoFactory
- **Purpose**: Allows factory to install plugins
- **Status**: Granted in [SubDaoFactory.sol](src/SubDaoFactory.sol), **REVOKED** in [SubDaoFactory.sol](src/SubDaoFactory.sol)

#### 1.2.2 Temporary EXECUTE_PERMISSION_ID (Factory)
- **Where**: SubDAO
- **Who**: SubDaoFactory
- **Purpose**: Allows factory to execute setup actions
- **Status**: Granted in [SubDaoFactory.sol](src/SubDaoFactory.sol), **REVOKED** in [SubDaoFactory.sol](src/SubDaoFactory.sol)

#### 1.2.3 Temporary PluginSetupProcessor Permissions
- **ROOT_PERMISSION_ID on SubDAO**: Granted/revoked in [SubDaoFactory.sol](src/SubDaoFactory.sol)
- **APPLY_INSTALLATION_PERMISSION_ID**: Granted/revoked in [SubDaoFactory.sol](src/SubDaoFactory.sol)

---

## 2. Permission Flow Diagrams

### 2.1 Main DAO: Proposal Execution Flow (TokenVotingHats)

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

### 2.2 Main DAO: Admin Execution Flow

```
Admin Address (0x624123...)
└─> EXECUTE_PROPOSAL on Admin Plugin
    └─> EXECUTE on DAO
        └─> Executes actions
```

### 2.3 Main DAO: Administrative Control

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

### 2.4 SubDAO: Veto Mode Flow (approver-hat-minter)

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

### 2.5 SubDAO: Approve Mode Flow (member-curator)

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

---

## 3. Security Considerations

### 3.1 Main DAO Security

#### 3.1.1 Critical Permissions

The following permissions represent the highest risk if compromised:

1. **DAO ROOT_PERMISSION_ID**: Can modify all other permissions
2. **Admin Address EXECUTE_PROPOSAL_PERMISSION**: Direct execution path bypassing governance
3. **DAO ESCROW_ADMIN_ROLE on VotingEscrow**: Can modify core escrow behavior

#### 3.1.2 Hats Protocol Dependencies

The governance system depends on Hats Protocol for access control:
- **Single Point of Failure**: If Hats Protocol is compromised, governance access is compromised
- **Hat Transferability**: Governance rights transfer with Hats
- **Hat Admin Control**: Whoever controls the Hats tree structure controls governance access

#### 3.1.3 Component Interaction Permissions

Several components have ADMIN permissions on each other, creating trust relationships:
- ExitQueue can modify VotingEscrow state
- Lock NFT can modify VotingEscrow state
- VotingEscrow can modify Lock NFT state
- VotingEscrow can modify IVotesAdapter state

These are necessary for system functionality but represent attack vectors if any component is compromised.

#### 3.1.4 Emergency Response

The DAO has several emergency response capabilities:
- **PAUSER_ROLE**: Can pause VotingEscrow operations
- **SWEEPER_ROLE**: Can recover accidentally sent tokens
- **Admin Plugin**: Provides emergency execution path

### 3.2 SubDAO Security

#### 3.2.1 Stage 1 Controller Risk
- **Veto Mode**: Controller has veto power and can block proposals
- **Approve Mode**: Controller must approve proposals for them to advance
- **Mitigation**: Controller address should be a trusted multisig or smart contract

#### 3.2.2 Stage Bypass Risk
- **Risk**: SPP has CREATE_PROPOSAL permission on TokenVotingHats, could potentially bypass Stage 1
- **Mitigation**: Only SPP-created proposals should be executed; direct Stage 2 proposals should be carefully monitored

#### 3.2.3 Shared Voting Power
- **Risk**: All SubDAOs share the same voting power (IVotesAdapter) from main DAO
- **Benefit**: Consistent voting power across the system
- **Consideration**: Large VE lock holders have influence across all SubDAOs

#### 3.2.4 Hat-Based Permission Dependencies
- **Risk**: SubDAOs depend on main DAO's hat structure
- **Single Point of Control**: Whoever controls the main DAO's Hats tree controls SubDAO Stage 2 governance
- **Mitigation**: Main DAO hat admin should be carefully secured

---

## 4. Permission Modification

### 4.1 How to Modify Permissions

All permissions (except Admin plugin's EXECUTE_PROPOSAL_PERMISSION) can be modified through DAO governance:

1. Create proposal via TokenVotingHats (requires proposer Hat)
2. Vote on proposal (requires voter Hat)
3. Execute proposal (requires executor Hat)
4. Proposal calls `DAO.grant()` or `DAO.revoke()`

### 4.2 Cannot Be Modified Without Governance

- All DAO administrative roles
- All VE system administrative roles
- TokenVotingHats plugin settings and permissions
- Admin plugin target configuration

### 4.3 Can Be Modified By Admin Address

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

**Document Version**: 1.0
**Last Updated**: 2025-11-03
