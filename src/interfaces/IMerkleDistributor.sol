// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMerkleDistributor {
    event RootUpdated(uint256 indexed round, bytes32 root);
    event Claimed(uint256 indexed round, address indexed claimant, uint256 amount);

    function setMerkleRoot(bytes32 root) external;
    function claim(bytes32[] calldata proof, uint256 amount) external;
    function hasClaimed(uint256 round, address account) external view returns (bool);
}
