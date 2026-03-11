# ARES Protocol — Architecture

## Overview

ARES Treasury is a secure treasury execution system designed to coordinate protocol governance over treasury assets. The system is organized into four independent modules, each responsible for a specific concern. These modules are combined in the ProposalEngine contract through inheritance, allowing the protocol to separate security responsibilities while maintaining a single execution entry point.

```
AresTreasury (src/core/ProposalEngine.sol)
    ├── SignatureAuth   (src/modules/SignatureAuth.sol)
    ├── MerkleDistributor (src/modules/MerkleDistributor.sol)
    └── GovernanceGuard  (src/modules/GovernanceGuard.sol)

Interfaces: src/interfaces/
    ├── IGovernanceGuard 
    ├── IProposalEngine 
    ├── IMerkleDistributor 
    └── ISignatureAuth  
Libraries:  src/libraries/SafeTransfer.sol
```

## Module Separation

### 1. ProposalEngine 
Manages the full lifecycle of treasury actions:
`Pending` → `Queued` → `Executed` (or `Cancelled` at any point before Executed)
A proposal enters the Pending state immediately it's submitted by a governor. While in this state, other governors will confirm the proposal. Once the number of confirmations reaches the required threshold, the proposal is moved into the Queued state and a one-hour timelock begins.
After the timelock expires, any governor can call executeProposal(). The proposal state is updated to Executed before the external call is performed, preventing reentrancy attacks. A proposal can also be Cancelled by its proposer at any time before execution.
This queue-based execution model ensures that treasury actions cannot occur instantly, giving governors and the community time to react to potentially malicious proposals.

### 2. SignatureAuth
The SignatureAuth module verifies off-chain approvals using the EIP-712 structured signature standard. Instead of requiring governors to approve actions directly on-chain, they can sign a message off-chain which is later submitted and verified by the contract.
Each signature is bound to a specific domain containing the protocol name, version, chain ID, and the verifyingContract address. This ensures that a signature created for ARES cannot be reused on another contract or another blockchain, preventing both cross-chain and cross-contract replay attacks. A monotonic nonce is also tracked per signer to prevent signatures from being replayed multiple times on the same chain.

### 3. MerkleDistributor
The MerkleDistributor module enables the protocol to distribute rewards to a large number of participants efficiently. Instead of storing every recipient on-chain, the protocol stores only a Merkle root, which represents the set of all eligible recipients and their reward amounts.
Participants claim rewards by submitting a Merkle proof verifying that their (address, amount) pair exists in the tree. This approach allows thousands of claims without large on-chain storage costs. Each distribution round uses a separate namespace to prevent double claims while allowing new roots to be published for future reward rounds.

### 4. GovernanceGuard
Two independent economic defenses:
- **Daily spend cap**: At most 10% of the treasury balance can leave in any 24-hour window.
  A balance snapshot is taken once per day, all spending within that day is accumulated.
- **Proposal deposit**: Every proposer must lock PROPOSAL_DEPOSIT (0.01 ETH) when submitting, which makes spam proposals expensive. They get it back on execution or cancellation.

## Security Boundaries
- Only governors can submit, confirm and execute with the help of the modifier.
- Only proposer who doubles as a governor can cancel a proposal
- Execution cannot happen before timelock 
- Each proposal can only be executed once 
- Reward claims cannot be performed twice.
- Treasury spending is restricted by the daily drain limit.

## Trust Assumptions

1. The governor set is assumed to be honest at deployment.  A majority colluding can still spend up to 10% of the treasury per day.
2. The `merkleAdmin` is trusted to publish correct Merkle roots.  A malicious admin could publish a root that lets them claim all rewards.  
3. The blockchain timestamp is assumed to be approximately correct. Block producers can manipulate timestamps slightly (typically ±15 seconds), but this is negligible compared to the one-hour timelock delay.
