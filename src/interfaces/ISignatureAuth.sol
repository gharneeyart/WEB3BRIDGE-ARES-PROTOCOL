// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

interface ISignatureAuth {
    event SignatureUsed(address indexed signer, uint256 nonce);

    function verifySignature(address signer, bytes32 action, uint256 nonce, bytes calldata signature)
        external
        view
        returns (bool);

    function nonces(address signer) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
