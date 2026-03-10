// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

interface IProposalEngine {
    enum ProposalState {
        Pending,
        Queued,
        Executed,
        Cancelled
    }

    enum ActionType {
        Transfer,
        Call,
        Upgrade
    }

    event ProposalSubmitted(uint256 indexed id, address indexed proposer);
    event ProposalConfirmed(uint256 indexed id, address indexed governor);
    event ProposalQueued(uint256 indexed id, uint256 executeAfter);
    event ProposalExecuted(uint256 indexed id);
    event ProposalCancelled(uint256 indexed id);

    function submitProposal(address target, uint256 value, bytes calldata data, ActionType actionType)
        external
        payable
        returns (uint256 id);

    function confirmProposal(uint256 proposalId) external;
    function executeProposal(uint256 proposalId) external;
    function cancelProposal(uint256 proposalId) external;
    function getState(uint256 proposalId) external view returns (ProposalState);
}
