// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title SignatureUtils
/// @notice EIP-712 structured signature verification with per-user nonces.
///
/// @dev --- ORIGINAL BUG (Discovery: manual review) ---
///      The original EvictionVault.verifySignature() accepted a raw messageHash
///      and signature with no domain separator and no nonce. This means:
///
///      1. REPLAY ATTACK: A valid signature on chain A can be replayed on chain B
///         because there is no chainId binding. Similarly, a used signature can be
///         re-submitted to the same contract with no protection.
///
///      2. SIGNATURE MALLEABILITY: Raw ecrecover allows the `s` value to be flipped
///         to its complement (secp256k1 symmetry), producing a second valid signature
///         for the same message from the same key. An attacker can forge a "different"
///         signature that ecrecover still accepts.
///
///      --- 2026 DANGER CONTEXT ---
///      Signature replay was the root cause of the Ronin Bridge hack ($625M, 2022)
///      and several 2025 cross-chain exploits. With more protocols operating across
///      10+ chains simultaneously, an unbound signature is essentially a skeleton key.
///
///      --- SOLUTION ---
///      - EIP-712 domain separator binds every signature to (name, version, chainId, verifyingContract).
///      - Per-user nonce increments on every verified signature, making replays impossible.
///      - `s` value is restricted to the lower half of the curve (s <= secp256k1n/2)
///        to close the malleability window, matching OpenZeppelin ECDSA behaviour.
contract SignatureAuth {
    bytes32 public immutable DOMAIN_SEPARATOR;

    bytes32 public constant PROPOSAL_TYPEHASH = keccak256("SignedAction(address signer,bytes32 action,uint256 nonce)");
  
    mapping(address => uint256) public nonces;

    event SignatureVerified(address indexed signer, bytes32 indexed action, uint256 nonce);

    error InvalidSignature();
    error SignatureMalleability();

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Ares Protocol")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function verifyAndConsumeNonce(address signer, bytes32 action, bytes memory signature) internal returns (bool) {
        uint256 currentNonce = nonces[signer];

        bytes32 structHash = keccak256(abi.encode(PROPOSAL_TYPEHASH, signer, action, currentNonce));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        address recovered = _recoverSigner(digest, signature);
        if (recovered == address(0) || recovered != signer) revert InvalidSignature();

        nonces[signer]++;
        emit SignatureVerified(signer, action, currentNonce);
        return true;
    }

    function verifySignature(address signer, bytes32 action, uint256 nonce, bytes memory signature)
        external
        view
        returns (bool)
    {
        bytes32 structHash = keccak256(abi.encode(PROPOSAL_TYPEHASH, signer, action, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address recovered = _recoverSigner(digest, signature);
        return recovered != address(0) && recovered == signer;
    }

    function _recoverSigner(bytes32 digest, bytes memory signature) internal pure returns (address) {
        if (signature.length != 65) revert InvalidSignature();

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        if (v < 27) v += 27;

        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert SignatureMalleability();
        }

        return ecrecover(digest, v, r, s);
    }

    // cross-chain replay protection
    function crossChainActionHash(bytes32 action) external view returns (bytes32) {
        return keccak256(abi.encodePacked(block.chainid, action));
    } 

}
