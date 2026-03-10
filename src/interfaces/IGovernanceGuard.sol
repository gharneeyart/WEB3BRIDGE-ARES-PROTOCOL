// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

interface IGovernanceGuard {
    function checkProposalCreation(address _proposer) external view returns (bool);

    function checkVotingEligibility(address _voter) external view returns (bool);

    function checkExecutionEligibility(uint256 _proposalId) external view returns (bool);
}
