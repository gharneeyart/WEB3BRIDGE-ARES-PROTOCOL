// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

library SafeTransfer {
    error TransferFailed(address recipient, uint256 amount);

    function safeTransferETH(address recipient, uint256 amount) internal {
        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert TransferFailed(recipient, amount);
    }
}
