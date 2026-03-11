# ARES Protocol — Security Analysis

### 1. Reentrancy (ProposalEngine)

**Attack:** A malicious contract receives ETH from `executeProposal` and immediately calls back into `executeProposal` before the first call returns, trying to re-use the same proposal to drain funds multiple times.

**Mitigation:** `_executeProposal` sets the proposal state to `Executed` before calling the external `target`. On re-entry, the second call sees `state != Queued` and reverts with `WRONG_STATE()`. This is exercised in `testExploit_Reentrancy`.

### 2. Signature Replay (SignatureAuth)

**Attack:** An attacker captures a valid signed authorization and re-submits it, either on the same chain (same-chain replay) or on a different chain (cross-chain replay).

**Mitigation:** `SignatureAuth` uses an EIP-712 domain separator that includes `name`, `version`, `chainId`, and `verifyingContract`. Every signature is bound to a per-signer `nonce` that increments inside `_verifyAndConsume`. Replays with the same signature fail because the nonce has advanced; cross-chain replays fail because the domain differs.

### 3. Double Claim (MerkleDistributor)

**Attack:** A contributor calls `claim()` twice in the same Merkle round to receive double their allocation.

**Mitigation:** `MerkleDistributor` tracks `_claimed[round][account]`. This flag is set **before** transferring ETH. A second call for the same `(round, account)` reverts with `AlreadyClaimed()`. The checks follow the checks-effects-interactions pattern to avoid reentrancy around the flag.

### 4. Unauthorized Governance Actions

**Attack:** A non-governor tries to submit, confirm, cancel, or execute a proposal, effectively bypassing governance.

**Mitigation:** All governance entrypoints (`submitProposal`, `confirmProposal`, `cancelProposal`, `executeProposal`, `setMerkleRoot`) carry the `onlyGovernor` modifier, which checks `isGovernor[msg.sender]` and reverts with `NOT_GOVERNOR()` if false. `executeProposalWithSignature` additionally validates that the recovered signer is a governor before executing.

### 5. Timelock Bypass

**Attack:** An attacker tries to execute a proposal before the 1‑hour timelock elapses, or executes a proposal that never reached the threshold and therefore was never queued.

**Mitigation:** `_executeProposal` requires `state == Queued`, `executeAfter != 0`, and `block.timestamp >= executeAfter`. Proposals that never reached the threshold remain `Pending` with `executeAfter = 0`, so they are rejected with `WRONG_STATE()` or `TIMELOCK_NOT_STARTED()`/`TIMELOCK_NOT_ELAPSED()`. The behavior is covered by `testProposalLifecycle`, `testExploit_PrematureExecution`, and `testExploit_ExecutePendingProposal`.

### 6. Proposal Replay / Double Execution

**Attack:** Re-execute an already executed proposal to drain treasury twice.

**Mitigation:** Once a proposal is executed, its state is permanently set to `Executed`. Subsequent calls fail the `state == Queued` check and revert with `WRONG_STATE()`. This is validated in `testExploit_ReplayExecution` and `testExploit_CancelExecutedProposal`.

### 7. Daily Drain Limit (GovernanceGuard)

**Attack:** A malicious quorum of governors tries to drain the entire treasury in a single day using one or more proposals.

**Mitigation:** Before any ETH is sent, `_executeProposal` calls `recordSpend(value)`. `GovernanceGuard` snapshots the starting daily balance and enforces that cumulative outflows for that day do not exceed `maxDailyBps` (10% by default). Any attempt to exceed this limit reverts with `DailyLimitExceeded()`, forcing large drains to be spread over multiple days.

### 8. Proposal Griefing via Spam

**Attack:** A governor floods the system with thousands of low-value proposals, making it hard to find or process legitimate ones.

**Mitigation:** Every proposal submission requires locking a flat `PROPOSAL_DEPOSIT` (0.01 ETH). The deposit is returned only when the proposal is executed or cancelled. Honest governors eventually recover their funds; spammers who abandon proposals lose their deposit, making sustained spam expensive. The `testExploit_SubmitWithoutDeposit` test ensures deposits are enforced.

### 9. Merkle Root Manipulation

**Attack:** A compromised governor sets a fraudulent Merkle root that gives themselves or an attacker address most of the reward pool.

**Mitigation:** `setMerkleRoot` is restricted to governors. In addition, the protocol design expects root changes to be observable during the timelock window (because they are typically scheduled through the proposal engine), so users and off-chain monitors can react. The `currentRound` mechanism also isolates damage to the active round; past rounds cannot be re-opened by changing the root.

## Remaining Risks

- **Governor key compromise:** If enough governors (at least the configured `threshold`) are compromised, they can still collude to drain funds within the daily limit. The timelock and daily cap slow this down but do not completely prevent it.
- **Target contract bugs:** `ProposalEngine` executes arbitrary calls against `target`. If those contracts contain vulnerabilities, a correctly approved proposal can still perform harmful actions.
- **Operational monitoring:** The safety of timelocks, Merkle roots, and daily limits assumes that users or off-chain services are monitoring state and events and can respond in time.
