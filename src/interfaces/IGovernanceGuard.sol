// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

interface IGovernanceGuard {
    event DrainLimitExceeded(uint256 requested, uint256 remaining);

    function checkDailyLimit(uint256 amount) external view returns (bool);
    function recordSpend(uint256 amount) external;
    function maxDailyBps() external view returns (uint256);
}

