// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";


contract MerkleProofHandler {
    bytes32 public merkleRoot;
    uint256 public round;
    mapping(uint256 => mapping(address => bool)) public claimed;

    event MerkleRootSet(bytes32 indexed newRoot);
    event Claim(address indexed claimant, uint256 amount);

    constructor(address[] memory _owners, uint256 _threshold) EmergencyFunctions(_owners, _threshold) {}

    function setMerkleRoot(bytes32 root) external onlyOwner {
        round++;
        merkleRoot = root;
        emit MerkleRootSet(root);
    }

    function claim(bytes32[] calldata proof, uint256 amount, uint256 _round) external {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        bytes32 computed = MerkleProof.processProof(proof, leaf);
        require(computed == merkleRoot, "Invalid proof");
        require(!claimed[_round][msg.sender], "Already claimed");

        claimed[_round][msg.sender] = true;

        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Claim failed");

        emit Claim(msg.sender, amount);
    }
}
