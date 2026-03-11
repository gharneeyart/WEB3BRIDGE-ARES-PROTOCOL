# ARES Protocol — Protocol Specification
## Proposal Lifecycle

The ARES Treasury enforces a structured lifecycle for all governance proposals. Each proposal represents a treasury action (transfer, call, or upgrade) and moves through the following stages:

1. **Proposal Creation**

A governor calls submitProposal(target, value, data, actionType) and deposits 0.01 ETH.

The contract verifies:

Caller is a governor (onlyGovernor).

Proposal deposit is provided.

Action-specific constraints (e.g., upgrades require data, no ETH value).

The proposal is assigned a unique ID and enters the Pending state.

The submitting governor is automatically counted as the first confirmation.

2. **Proposal Approval**

Governors call confirmProposal(proposalId) to approve a Pending proposal.

Each governor can confirm a proposal only once.

Once the number of confirmations reaches the required threshold

Proposal state changes from Pending → Queued.

Timelock begins (executeAfter = block.timestamp + 1 hour).

Confirmations beyond the threshold are rejected to prevent double-counting.

3. **Queueing and Timelock**

A proposal in Queued state cannot execute until the timelock expires.

The executeAfter timestamp enforces a delay, providing governance review time.

Any attempt to execute before executeAfter reverts.

4. **Execution**

Any governor can call executeProposal(proposalId) once the timelock has elapsed.

The protocol performs Checks-Effects-Interactions:

The proposal state is set to Executed before calling external contracts.

ETH or calldata is sent to the target address.

Proposal deposit is refunded to the proposer.

After execution:

Proposal is immutable; replay is prevented by state checks.

The proposal cannot be re-executed.

5. **Cancellation**

Only the original proposer can cancel a Pending or Queued proposal.

The proposer calls cancelProposal(proposalId).

Upon cancellation:

Proposal state becomes Cancelled.

Deposit is refunded.

Cancelled proposals cannot be executed, and all state-changing calls after cancellation are rejected.