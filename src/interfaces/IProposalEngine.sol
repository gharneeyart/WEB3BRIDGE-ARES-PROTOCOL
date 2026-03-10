// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

interface IProposalEngine {
    function submitProposal(address _to, uint256 _value, bytes calldata _data) external returns (uint256);

    function confirmProposal(uint256 _proposalId) external;

    function executeProposal(uint256 _proposalId) external;
    function cancelProposal(uint256 _proposalId) external;
}
