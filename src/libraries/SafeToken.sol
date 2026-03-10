// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

library SafeToken {
    function safeTransfer(address token, address to, uint256 amount) internal {
        bool ok = IERC20Minimal(token).transfer(to, amount);
        require(ok, "SafeToken: transfer failed");
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        bool ok = IERC20Minimal(token).transferFrom(from, to, amount);
        require(ok, "SafeToken: transferFrom failed");
    }
}

