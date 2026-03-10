// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {ProposalEngine} from "../modules/ProposalEngine.sol";
import {SignatureAuth} from "../modules/SignatureAuth.sol";
import {MerkleDistributor} from "../modules/MerkleDistributor.sol";
import {GovernanceGuard} from "../modules/GovernanceGuard.sol";
import {IProposalEngine} from "../interfaces/IProposalEngine.sol";
import {SafeTransfer} from "../libraries/SafeTransfer.sol";

contract AresTreasury is ProposalEngine, SignatureAuth, MerkleDistributor {
    using SafeTransfer for address;

    event TreasuryDeposit(address indexed from, uint256 amount);

    uint256 public constant MAX_DAILY_BPS = 1000;
    mapping(uint256 => uint256) private _dailySpend;
    mapping(uint256 => uint256) private _dailySnapshot;

    error DailyLimitExceeded();

    constructor(address[] memory _governors, uint256 _threshold, address _merkleAdmin)
        ProposalEngine(_governors, _threshold)
        SignatureAuth()
    {
        if (_merkleAdmin != address(0)) {
            _setMerkleAdmin(_merkleAdmin);
        }
    }

    function submit(address _target, uint256 _value, bytes calldata _data, IProposalEngine.ActionType _actionType)
        external
        payable
        onlyGovernor
        returns (uint256)
    {
        return submitProposal(_target, _value, _data, _actionType);
    }

    function confirm(uint256 proposalId) external onlyGovernor {
        confirmProposal(proposalId);
    }

    function execute(uint256 proposalId) external onlyGovernor {
        _executeProposalInternal(proposalId);
    }

    function cancelAndRefund(uint256 proposalId) external onlyGovernor {
        cancelProposal(proposalId);
    }

    function stateOf(uint256 proposalId) external view returns (IProposalEngine.ProposalState) {
        return getState(proposalId);
    }

    function executeProposal(uint256 proposalId) external override onlyGovernor {
        _executeProposalInternal(proposalId);
    }

    function _executeProposalInternal(uint256 proposalId) internal {
        ProposalEngine.Proposal storage prop = proposals[proposalId];

        if (prop.state != IProposalEngine.ProposalState.Queued) revert WRONG_STATE();
        if (prop.executeAfter == 0) revert TIMELOCK_NOT_STARTED();
        if (block.timestamp < prop.executeAfter) revert TIMELOCK_NOT_ELAPSED();

        if (prop.value > 0) {
            _checkAndRecordSpend(prop.value);
        }

        prop.state = IProposalEngine.ProposalState.Executed;

        (bool ok,) = prop.target.call{value: prop.value}(prop.data);
        require(ok, "execution failed");

        (bool refund,) = prop.proposer.call{value: prop.deposit}("");
        require(refund, "deposit refund failed");

        emit ProposalExecuted(proposalId);
    }

    function _checkAndRecordSpend(uint256 amount) internal {
        uint256 today = block.timestamp / 1 days;

        if (_dailySnapshot[today] == 0) {
            _dailySnapshot[today] = address(this).balance;
        }

        uint256 maxSpend = (_dailySnapshot[today] * MAX_DAILY_BPS) / 10_000;
        if (_dailySpend[today] + amount > maxSpend) revert DailyLimitExceeded();
        _dailySpend[today] += amount;
    }

    function setMerkleRoot(bytes32 root) external override {
        if (msg.sender != merkleAdmin) revert NotMerkleAdmin();
        _setMerkleRoot(root);
    }

    function deposit() external payable {
        emit TreasuryDeposit(msg.sender, msg.value);
    }

    receive() external payable override {
        emit TreasuryDeposit(msg.sender, msg.value);
    }
}
