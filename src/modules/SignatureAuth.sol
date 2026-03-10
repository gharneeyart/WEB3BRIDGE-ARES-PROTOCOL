// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISignatureAuth} from "../interfaces/ISignatureAuth.sol";

abstract contract SignatureAuth is ISignatureAuth {
    bytes32 public immutable DOMAIN_SEPARATOR;

    bytes32 public constant ACTION_TYPEHASH = keccak256("SignedAction(address signer,bytes32 action,uint256 nonce)");

    mapping(address => uint256) public nonces;

    error InvalidSignature();
    error SignatureMalleability();

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("AresProtocol")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function verifySignature(address signer, bytes32 action, uint256 nonce, bytes calldata signature)
        external
        view
        returns (bool)
    {
        bytes32 digest = _digest(signer, action, nonce);
        return _recover(digest, signature) == signer;
    }

    function _verifyAndConsume(address signer, bytes32 action, bytes calldata signature) internal returns (bool) {
        uint256 nonce = nonces[signer];
        bytes32 digest = _digest(signer, action, nonce);
        address recovered = _recover(digest, signature);
        if (recovered != signer) revert InvalidSignature();
        nonces[signer]++;
        emit SignatureUsed(signer, nonce);
        return true;
    }

    function _digest(address signer, bytes32 action, uint256 nonce) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(ACTION_TYPEHASH, signer, action, nonce));
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    function _recover(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        if (sig.length != 65) revert InvalidSignature();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v < 27) v += 27;
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert SignatureMalleability();
        }
        return ecrecover(digest, v, r, s);
    }
}
