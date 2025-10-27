# Self-Delegation Only Solution

## The Core Insight

**Self-delegation IS required for voting power** in the IVotesAdapter system. Here's why:

### How Voting Power Works

1. **Token Balance** ≠ **Voting Power**
   - Owning veTokens (NFTs) gives you potential power
   - `IVotesAdapter.getVotes(address)` returns **delegated voting power to you**
   - NOT your token balance!

2. **The Vote Mechanism** (TokenVoting.sol:264)
```solidity
function _vote(...) {
    // Uses getPastVotes at snapshot time
    uint256 votingPower = votingToken.getPastVotes(_voter, snapshotTimepoint);

    // This is ZERO if tokens aren't delegated!
}
```

3. **Without Delegation**:
   - You own veToken NFT #1 with 1000 underlying tokens
   - `getVotes(yourAddress)` = **0** (nothing delegated to you)
   - You **CANNOT vote** on proposals
   - You **CANNOT create proposals** (if minProposerVotingPower > 0)

4. **With Self-Delegation**:
   - You own veToken NFT #1 with 1000 underlying tokens
   - You call `delegate(yourAddress)` (delegate to self)
   - `getVotes(yourAddress)` = **1000** (your tokens delegated to yourself)
   - You **CAN vote** and create proposals

### Why This Architecture?

This is the IVotes (EIP-5805) standard pattern:
- **Separation of custody and voting rights**
- Token ownership = custody
- Delegation = voting rights
- Allows flexible governance (you can delegate to a representative OR to yourself)

## Your Requirements

You want:
1. ✅ **Self-delegation** - Allow users to delegate to themselves (REQUIRED for voting)
2. ❌ **Block non-self delegation** - Prevent delegating to others
3. ✅ **Minimal changes** - Prefer small tweak to IVotesAdapter if necessary
4. ✅ **No AddressGaugeVoter if possible** - Simplest solution

## The Simplest Solution: Modified IVotesAdapter

### Strategy

Modify `EscrowIVotesAdapter.delegate(address)` to:
1. **Only allow self-delegation**: `require(_delegatee == msg.sender)`
2. **Skip the `updateVotingPower` call**: Since _from == _to, we can early return

### Why This Works

Looking at the code flow:
```solidity
// EscrowIVotesAdapter.sol:170-191
function delegate(address _delegatee) public virtual whenNotPaused {
    address sender = _msgSender();

    // ... delegation logic ...

    // Line 259: This calls updateVotingPower
    IVotingEscrow(escrow).updateVotingPower(sender, _delegatee);
}
```

But in VotingEscrow:
```solidity
// VotingEscrowIncreasing_v1_2_0.sol:692-696
function updateVotingPower(address _from, address _to) public whenNotPaused {
    if (msg.sender != ivotesAdapter) revert OnlyIVotesAdapter();

    IAddressGaugeVoter(voter).updateVotingPower(_from, _to); // ← The problem!
}
```

And in AddressGaugeVoter:
```solidity
// AddressGaugeVoter.sol:334-344
function updateVotingPower(address _from, address _to) external onlyEscrow {
    _updateVotingPower(_from);

    if (_from == _to) return; // ← EARLY RETURN for self-delegation! ✅

    _updateVotingPower(_to);
}
```

**KEY INSIGHT**: AddressGaugeVoter ALREADY has special handling for self-delegation at line 340!
- It updates `_from` once
- If `_from == _to`, it **returns early** without updating `_to` again
- This is because self-delegation doesn't move votes between parties

### The Problem

The issue is we hit line 695 of VotingEscrow BEFORE we can reach AddressGaugeVoter's early return:
```solidity
IAddressGaugeVoter(voter).updateVotingPower(_from, _to);
// ↑ voter is address(0), so this reverts before we can check if _from == _to
```

## Solution Options Ranked by Simplicity

### Option 1: Deploy Minimal AddressGaugeVoter + Enforce Self-Delegation (Recommended)

**Changes Required**:
1. Create `SelfDelegationEscrowIVotesAdapter.sol` (inherits from EscrowIVotesAdapter)
2. Override `delegate(address)` to enforce self-delegation only
3. Deploy AddressGaugeVoter with `enableUpdateVotingPowerHook = true`
4. Wire everything together

**Code**:
```solidity
// src/SelfDelegationEscrowIVotesAdapter.sol
pragma solidity ^0.8.17;

import {EscrowIVotesAdapter} from "@delegation/EscrowIVotesAdapter.sol";

contract SelfDelegationEscrowIVotesAdapter is EscrowIVotesAdapter {
    error NonSelfDelegationNotAllowed();

    constructor(
        int256[3] memory _coefficients,
        uint256 _maxEpochs
    ) EscrowIVotesAdapter(_coefficients, _maxEpochs) {}

    /// @notice Override to enforce self-delegation only
    /// @dev Users can ONLY delegate to themselves
    function delegate(address _delegatee) public override whenNotPaused {
        address sender = _msgSender();

        // ENFORCE: Only self-delegation allowed
        if (_delegatee != sender) {
            revert NonSelfDelegationNotAllowed();
        }

        // Call parent implementation (which allows self-delegation)
        super.delegate(_delegatee);
    }

    // Note: We keep the delegate(uint256[] tokenIds) function as-is
    // It requires DELEGATION_TOKEN_ROLE anyway, so DAO can control it
}
```

**Pros**:
- ✅ Minimal code change (one small contract)
- ✅ No forking of Aragon contracts
- ✅ Clear enforcement of self-delegation policy
- ✅ AddressGaugeVoter's early return makes it effectively a no-op for self-delegation
- ✅ Can add gauge voting later if needed
- ✅ Standard architecture

**Cons**:
- ❌ Requires deploying AddressGaugeVoter (one extra contract)
- ❌ Small gas overhead on delegation (but early return minimizes it)

### Option 2: Skip updateVotingPower Call for Self-Delegation

**Changes Required**:
1. Create `SelfDelegationEscrowIVotesAdapter.sol`
2. Override `delegate(address)` to skip `updateVotingPower` when `_delegatee == sender`

**Code**:
```solidity
// src/SelfDelegationEscrowIVotesAdapter.sol
pragma solidity ^0.8.17;

import {EscrowIVotesAdapter} from "@delegation/EscrowIVotesAdapter.sol";
import {IVotingEscrowIncreasingV1_2_0 as IVotingEscrow} from "@escrow/IVotingEscrowIncreasing_v1_2_0.sol";
import {VotingEscrowV1_2_0 as VotingEscrow} from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";

contract SelfDelegationEscrowIVotesAdapter is EscrowIVotesAdapter {
    error NonSelfDelegationNotAllowed();

    constructor(
        int256[3] memory _coefficients,
        uint256 _maxEpochs
    ) EscrowIVotesAdapter(_coefficients, _maxEpochs) {}

    /// @notice Override to enforce self-delegation only and skip updateVotingPower
    function delegate(address _delegatee) public override whenNotPaused {
        address sender = _msgSender();

        // ENFORCE: Only self-delegation allowed
        if (_delegatee != sender) {
            revert NonSelfDelegationNotAllowed();
        }

        address currentDelegatee = delegates(sender);
        uint256[] memory tokenIds = VotingEscrow(escrow).ownedTokens(sender);
        uint256 ownedTokenLength = tokenIds.length;

        if (currentDelegatee != address(0) && ownedTokenLength != 0) {
            uint256[] memory delegatedTokenIds = getDelegatedTokens(tokenIds);
            if (delegatedTokenIds.length != 0) {
                _undelegate(sender, currentDelegatee, delegatedTokenIds, false);
            }
        }

        delegatees_[sender] = _delegatee;

        if (!autoDelegationDisabled(sender) && _delegatee != address(0) && ownedTokenLength != 0) {
            _delegate(sender, _delegatee, tokenIds, false);
        }

        emit DelegateChanged(sender, currentDelegatee, _delegatee);

        // SKIP updateVotingPower call since _from == _to (self-delegation)
        // This avoids the need for AddressGaugeVoter entirely
    }
}
```

**Pros**:
- ✅ No AddressGaugeVoter needed!
- ✅ Minimal code change
- ✅ Clear enforcement of self-delegation
- ✅ Slightly less gas than Option 1

**Cons**:
- ❌ Duplicates logic from parent contract (maintenance burden)
- ❌ Harder to add gauge voting later
- ❌ More deviation from standard architecture

### Option 3: Auto-Delegate on Lock Creation (Simplest for Users)

**Changes Required**:
1. Create wrapper around VotingEscrow that auto-delegates on `createLock`
2. Still need AddressGaugeVoter OR Option 2's adapter

**Benefit**: Users don't have to manually call `delegate()` - it happens automatically when they lock tokens

**Code** (combine with Option 1 or 2):
```solidity
// Auto-delegation hook in VotingEscrow wrapper or custom Lock contract
function createLock(...) external {
    uint256 tokenId = votingEscrow.createLock(...);

    // Auto-delegate to self
    if (ivotesAdapter.delegates(msg.sender) == address(0)) {
        ivotesAdapter.delegate(msg.sender);
    }
}
```

## Recommendation: Option 1

**Deploy minimal AddressGaugeVoter + SelfDelegationEscrowIVotesAdapter**

### Why?

1. **Least deviation from standard contracts**
   - Only one small wrapper contract
   - No duplication of complex delegation logic
   - Follows proven architecture pattern

2. **Future-proof**
   - Can enable gauge voting later if needed
   - Easy to maintain and upgrade
   - Compatible with Aragon tooling

3. **Gas-efficient for self-delegation**
   - AddressGaugeVoter's `updateVotingPower` has early return for self-delegation
   - Minimal overhead: one address comparison + return
   - No gauge votes = no storage writes

4. **Clear policy enforcement**
   - Explicit revert message: `NonSelfDelegationNotAllowed()`
   - Users get clear feedback
   - DAO can always grant DELEGATION_TOKEN_ROLE for special cases if needed

### Implementation Steps

1. **Create SelfDelegationEscrowIVotesAdapter.sol** (10 lines of override code)
2. **Deploy AddressGaugeVoter** (base implementation + proxy)
3. **Update VESystemSetup** to use SelfDelegationEscrowIVotesAdapter
4. **Deploy DAO** with full system
5. **Set voter address** on VotingEscrow
6. **Grant permissions** between components

### Gas Costs

For self-delegation call flow:
```
User.delegate(self)
  → SelfDelegationEscrowIVotesAdapter.delegate(self) [+500 gas for require check]
    → EscrowIVotesAdapter._delegate(...) [standard delegation logic]
      → VotingEscrow.updateVotingPower(self, self)
        → AddressGaugeVoter.updateVotingPower(self, self)
          → _updateVotingPower(self)
            → if (!isVoting(self)) return; [+2000 gas for check, then return]
          → if (self == self) return; [+500 gas, then return]

Total overhead: ~3000 gas (negligible)
```

## Alternative: If You Really Don't Want AddressGaugeVoter

Use **Option 2** but understand:
- More code to maintain
- Harder to upgrade
- Breaks standard ve-governance pattern
- Can't add gauge voting without redeployment

The tradeoff is:
- Save one contract deployment
- Add technical debt in your custom adapter

**Verdict**: Not worth it. Deploy the stub AddressGaugeVoter.

## Summary

**Best solution for your requirements**:
1. Deploy AddressGaugeVoter (with `enableUpdateVotingPowerHook = true`)
2. Create SelfDelegationEscrowIVotesAdapter that blocks non-self delegation
3. Users must call `delegate(theirOwnAddress)` to activate voting power
4. Users cannot delegate to others (reverts with clear error)
5. Minimal gas overhead, maximum compatibility, future-proof

Would you like me to implement this solution?
