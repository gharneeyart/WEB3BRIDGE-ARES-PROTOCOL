// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMerkleDistributor} from "../interfaces/IMerkleDistributor.sol";
import {SafeTransfer} from "../libraries/SafeTransfer.sol";

abstract contract MerkleDistributor is IMerkleDistributor {
    using SafeTransfer for address;

    uint256 public currentRound;
    bytes32 public merkleRoot;
    address public merkleAdmin;

    mapping(uint256 => mapping(address => bool)) private _claimed;

    error AlreadyClaimed();
    error InvalidProof();
    error ZeroRoot();
    error NotMerkleAdmin();

    function setMerkleRoot(bytes32 root) external virtual override {
        if (msg.sender != merkleAdmin) revert NotMerkleAdmin();
        _setMerkleRoot(root);
    }

    function _setMerkleAdmin(address admin) internal {
        require(admin != address(0), "zero admin");
        merkleAdmin = admin;
    }

    function _setMerkleRoot(bytes32 root) internal {
        if (root == bytes32(0)) revert ZeroRoot();
        currentRound++;
        merkleRoot = root;
        emit RootUpdated(currentRound, root);
    }

    function claim(bytes32[] calldata proof, uint256 amount) external {
        uint256 round = currentRound;
        if (_claimed[round][msg.sender]) revert AlreadyClaimed();

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        if (!_verify(proof, leaf)) revert InvalidProof();

        _claimed[round][msg.sender] = true;
        emit Claimed(round, msg.sender, amount);

        msg.sender.safeTransferETH(amount);
    }

    function hasClaimed(uint256 round, address account) external view returns (bool) {
        return _claimed[round][account];
    }

    function _verify(bytes32[] calldata proof, bytes32 leaf) internal view returns (bool) {
        bytes32 computed = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 p = proof[i];
            computed =
                computed < p ? keccak256(abi.encodePacked(computed, p)) : keccak256(abi.encodePacked(p, computed));
        }
        return computed == merkleRoot;
    }
}
