# DAO Factory Permissions Analysis

**Generated**: 2025-11-04
**System Version**: 1.0.0
**Network**: Sepolia (deployed configuration)

> **Note**: For security analysis, permission flows, and modification procedures, see [permissions-security-analysis.md](permissions-security-analysis.md)

## Overview

This document provides a focused summary of all permissions that exist in the DAO system post-deployment. The system consists of:

1. **Main DAO** - Aragon OSx DAO with VE governance and TokenVotingHats plugin
2. **SubDAOs** - Configurable sub-DAOs with two-stage governance (SPP + TokenVotingHats)

**Key Addresses:**
- **Admin Address**: `0x624123ec4A9f48Be7AA8a307a74381E4ea7530D4`
- **Proposer Hat**: `0x0000071e00030001000000000000000000000000000000000000000000000000`
- **Voter Hat**: `0x0000071e00030001000000000000000000000000000000000000000000000000`
- **Executor Hat**: `0x0000000000000001`

---

## 1. Main DAO Permissions Summary

### 1.1 DAO Self-Permissions

The DAO grants itself five core permissions during deployment:
- `ROOT_PERMISSION_ID` - Manage all other permissions
- `UPGRADE_DAO_PERMISSION_ID` - Upgrade the DAO implementation
- `SET_TRUSTED_FORWARDER_PERMISSION_ID` - Set meta-transaction forwarder
- `SET_METADATA_PERMISSION_ID` - Update DAO metadata
- `REGISTER_STANDARD_CALLBACK_PERMISSION_ID` - Register standard callbacks

### 1.2 DAO Administrative Permissions

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

### 1.3 Plugin Permissions on DAO

**TokenVotingHats Plugin:**
- `EXECUTE_PERMISSION_ID` - Execute approved proposals on DAO

**Admin Plugin:**
- `EXECUTE_PERMISSION_ID` - Execute admin actions on DAO

### 1.4 Admin Address Permissions

The admin address has:
- `EXECUTE_PROPOSAL_PERMISSION_ID` on Admin plugin (direct execution through Admin plugin)

### 1.5 Hat Wearer Permissions

Anyone wearing the appropriate hat can (via HatsCondition):
- **Proposer Hat**: Create proposals in TokenVotingHats
- **Voter Hat**: Cast votes in TokenVotingHats
- **Executor Hat**: Execute approved proposals in TokenVotingHats

### 1.6 VE System Internal Permissions

Component-to-component permissions for system functionality:
- ExitQueue → VotingEscrow: `ESCROW_ADMIN_ROLE`
- Lock → VotingEscrow: `ESCROW_ADMIN_ROLE`
- VotingEscrow → Lock: `LOCK_ADMIN_ROLE`
- VotingEscrow → IVotesAdapter: `DELEGATION_TOKEN_ROLE`

---

## 2. SubDAO Permissions Summary

### 2.1 SubDAO Architecture

Each SubDAO has:
- Independent Aragon OSx DAO instance
- Stage 1: SPP Plugin (veto or approve mode)
- Stage 2: TokenVotingHats Plugin (uses main DAO's VE system)
- Admin Plugin (shared admin address)

**Shared from Main DAO:**
- IVotesAdapter (voting power)
- Hat IDs (governance permissions)
- HatsCondition (permission validation)

**Main DAO Control:**
- Main DAO has `ROOT_PERMISSION_ID` on each SubDAO
- This grants the main DAO full control to install/uninstall plugins and manage all SubDAO permissions

### 2.2 Stage 1 (SPP) Permissions by Mode

**Veto Mode** (e.g., approver-hat-minter):
- Controller address → SPP: `CREATE_PROPOSAL_PERMISSION_ID` (direct grant)
- Controller is sole Stage 1 voting body member with veto power
- SPP → SubDAO: `EXECUTE_PROPOSAL_PERMISSION_ID`
- SPP → TokenVotingHats: `CREATE_PROPOSAL_PERMISSION_ID`

**Approve Mode** (e.g., member-curator):
- Hat wearers (ANY_ADDR via HatsCondition) → SPP: `CREATE_PROPOSAL_PERMISSION_ID`
- Controller is sole Stage 1 voting body member with approval power
- SPP → SubDAO: `EXECUTE_PROPOSAL_PERMISSION_ID`
- SPP → TokenVotingHats: `CREATE_PROPOSAL_PERMISSION_ID`

### 2.3 Stage 2 (TokenVotingHats) Permissions

Same as main DAO TokenVotingHats:
- SubDAO → TokenVotingHats: `UPDATE_VOTING_SETTINGS_PERMISSION_ID`, `SET_TARGET_CONFIG_PERMISSION_ID`, `SET_METADATA_PERMISSION_ID`
- Hat wearers (ANY_ADDR via HatsCondition) → TokenVotingHats: `CREATE_PROPOSAL_PERMISSION_ID`, `CAST_VOTE_PERMISSION_ID`, `EXECUTE_PROPOSAL_PERMISSION_ID`
- TokenVotingHats → SubDAO: `EXECUTE_PERMISSION_ID`

### 2.4 SubDAO Admin Plugin Permissions

- Admin address → Admin plugin: `EXECUTE_PROPOSAL_PERMISSION_ID`
- Admin plugin → SubDAO: `EXECUTE_PERMISSION_ID`

### 2.5 Main DAO Control Over SubDAOs

Each SubDAO grants `ROOT_PERMISSION_ID` to the main DAO during deployment:
- **Where**: SubDAO (on itself)
- **Who**: Main DAO address
- **Purpose**: Enables main DAO to install/uninstall plugins and manage all SubDAO permissions
- **Use Case**: Allows main DAO governance to upgrade or modify SubDAO functionality without requiring SubDAO governance approval

This creates a hierarchical governance structure where the main DAO has ultimate control over all SubDAOs while each SubDAO operates independently for day-to-day governance.

### 2.6 Configuration Examples

#### Approver Hat Minter (Veto Mode)
- **Purpose**: Default-allow governance with controller veto
- **Stage 1**: Controller-only proposal creation and veto (proposerHatId = 0)
- **Stage 2**: Full hat-based governance using main DAO hats

#### Member Curator (Approve Mode)
- **Purpose**: Default-block governance requiring controller approval
- **Stage 1**: Hat-based proposal creation, controller approval (proposerHatId auto-set to main DAO proposer hat)
- **Stage 2**: Full hat-based governance using main DAO hats

---

## 3. Detailed Permission Reference

### 3.1 DAO Core Permissions

**ROOT_PERMISSION_ID**
- Where: DAO
- Who: DAO itself
- Purpose: Highest-level permission for managing all other permissions

**EXECUTE_PERMISSION_ID on DAO**
- Where: DAO
- Who: TokenVotingHats plugin, Admin plugin
- Purpose: Execute approved proposals or admin actions on the DAO

### 3.2 VE System Permissions (Condensed)

**VotingEscrow:**
- DAO: `ESCROW_ADMIN_ROLE`, `PAUSER_ROLE`, `SWEEPER_ROLE`
- ExitQueue: `ESCROW_ADMIN_ROLE`
- Lock: `ESCROW_ADMIN_ROLE`

**Curve:**
- DAO: `CURVE_ADMIN_ROLE`

**ExitQueue:**
- DAO: `QUEUE_ADMIN_ROLE`, `WITHDRAW_ROLE`

**Lock:**
- DAO: `LOCK_ADMIN_ROLE`
- VotingEscrow: `LOCK_ADMIN_ROLE`

**IVotesAdapter:**
- DAO: `DELEGATION_ADMIN_ROLE`, `DELEGATION_TOKEN_ROLE`
- VotingEscrow: `DELEGATION_TOKEN_ROLE`

**AddressGaugeVoter:**
- DAO: `GAUGE_ADMIN_ROLE`, `EXECUTE_PERMISSION`

### 3.3 TokenVotingHats Plugin Permissions

**DAO Administrative Permissions:**
- DAO → TokenVotingHats: `UPDATE_VOTING_SETTINGS_PERMISSION_ID`, `SET_TARGET_CONFIG_PERMISSION_ID`, `SET_METADATA_PERMISSION_ID`

**Hat-Gated Permissions (via HatsCondition):**
- ANY_ADDR (wearing proposer hat) → TokenVotingHats: `CREATE_PROPOSAL_PERMISSION_ID`
- ANY_ADDR (wearing voter hat) → TokenVotingHats: `CAST_VOTE_PERMISSION_ID`
- ANY_ADDR (wearing executor hat) → TokenVotingHats: `EXECUTE_PROPOSAL_PERMISSION_ID`

**Execution Permission:**
- TokenVotingHats → DAO: `EXECUTE_PERMISSION_ID`

### 3.4 Admin Plugin Permissions

**Admin Address:**
- Admin address → Admin plugin: `EXECUTE_PROPOSAL_PERMISSION_ID`

**DAO Control:**
- DAO → Admin plugin: `SET_TARGET_CONFIG_PERMISSION_ID`

**Execution:**
- Admin plugin → DAO: `EXECUTE_PERMISSION_ID`

### 3.5 SubDAO Detailed Permissions

**Main DAO Root Permission:**
- Where: SubDAO
- Who: Main DAO address
- Permission: `ROOT_PERMISSION_ID`
- Purpose: Allows main DAO to install/uninstall plugins on SubDAO and manage all SubDAO permissions
- Granted: During SubDAO deployment by SubDaoFactory

**Stage 1 (SPP) CREATE_PROPOSAL Grant:**

*Veto Mode:*
- Where: SPP Plugin
- Who: Controller address directly (e.g., `0x2D7473039D40d26789981c907AbE9D37bf463e4E`)
- Purpose: Controller creates proposals and can veto (sole Stage 1 voting member)

*Approve Mode:*
- Where: SPP Plugin
- Who: ANY_ADDR with HatsCondition (main DAO proposer hat)
- Purpose: Hat wearers create proposals; controller must approve (sole Stage 1 voting member)

**Stage 1 (SPP) Execution:**
- SPP → SubDAO: `EXECUTE_PROPOSAL_PERMISSION_ID`
- SPP → TokenVotingHats: `CREATE_PROPOSAL_PERMISSION_ID`

**Stage 2 (TokenVotingHats):**
- SubDAO → TokenVotingHats: `UPDATE_VOTING_SETTINGS_PERMISSION_ID`, `SET_TARGET_CONFIG_PERMISSION_ID`, `SET_METADATA_PERMISSION_ID`
- ANY_ADDR (via HatsCondition) → TokenVotingHats: `CREATE_PROPOSAL_PERMISSION_ID`, `CAST_VOTE_PERMISSION_ID`, `EXECUTE_PROPOSAL_PERMISSION_ID`
- TokenVotingHats → SubDAO: `EXECUTE_PERMISSION_ID`

**Admin Plugin:**
- Admin address → Admin plugin: `EXECUTE_PROPOSAL_PERMISSION_ID`
- Admin plugin → SubDAO: `EXECUTE_PERMISSION_ID`

---

## 4. Permission Count Summary

**Main DAO**: 32 active permissions post-deployment
- DAO self-permissions: 5
- VE system permissions: 15
- TokenVotingHats permissions: 6
- Admin plugin permissions: 3
- Internal component permissions: 3

**Per SubDAO**: ~16 active permissions post-deployment
- Main DAO ROOT_PERMISSION: 1
- SPP permissions: 3
- TokenVotingHats permissions: 6
- Admin plugin permissions: 2
- SubDAO self-permissions: 4

**Total for system with 2 SubDAOs**: ~64 active permissions

---

**Document Version**: 2.1
**Last Updated**: 2025-11-04
