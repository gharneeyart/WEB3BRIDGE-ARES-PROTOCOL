// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IGovernanceGuard} from "../interfaces/IGovernanceGuard.sol";

abstract contract GovernanceGuard is IGovernanceGuard {
    uint256 public constant maxDailyBps = 1000;
    uint256 public constant PROPOSAL_DEPOSIT = 0.01 ether;

    mapping(uint256 => uint256) private _dailySpend;
    mapping(uint256 => address) public proposalDepositor;
    mapping(uint256 => uint256) private _dailyBalanceSnapshot;

    error DailyLimitExceeded();
    error DepositRequired();
    error DepositReturnFailed();

    function _snapshotTodayBalance() internal {
        uint256 today = block.timestamp / 1 days;
        if (_dailyBalanceSnapshot[today] == 0) {
            _dailyBalanceSnapshot[today] = address(this).balance;
        }
    }

    function checkDailyLimit(uint256 amount) public view returns (bool) {
        uint256 today = block.timestamp / 1 days;
        uint256 snapshotBalance = _dailyBalanceSnapshot[today];

        if (snapshotBalance == 0) {
            snapshotBalance = address(this).balance;
        }

        uint256 maxSpend = (snapshotBalance * maxDailyBps) / 10_000;
        return (_dailySpend[today] + amount) <= maxSpend;
    }

    function recordSpend(uint256 amount) public {
        _snapshotTodayBalance();
        if (!checkDailyLimit(amount)) revert DailyLimitExceeded();
        _dailySpend[block.timestamp / 1 days] += amount;
    }

    function checkAndRecordWithdrawal(uint256 amount) external {
        recordSpend(amount);
    }

    function _lockDeposit(uint256 proposalId, address proposer) internal {
        if (msg.value < PROPOSAL_DEPOSIT) revert DepositRequired();
        proposalDepositor[proposalId] = proposer;
    }

    function _returnDeposit(uint256 proposalId) internal {
        address depositor = proposalDepositor[proposalId];
        if (depositor == address(0)) return;
        proposalDepositor[proposalId] = address(0);
        (bool ok,) = depositor.call{value: PROPOSAL_DEPOSIT}("");
        if (!ok) revert DepositReturnFailed();
    }
}
