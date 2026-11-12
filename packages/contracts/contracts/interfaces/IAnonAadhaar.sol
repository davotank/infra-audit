// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

/// @notice Interface of the Anon Aadhaar on-chain verifier (anon-aadhaar/contracts, v2).
/// @dev Re-check this signature against the exact anon-aadhaar release you deploy against.
///      revealArray = [ageAbove18, gender, pincode, state]; a field the user chose not to
///      reveal is 0. The verifier hashes `signal` internally before comparing it with the
///      proof's public signal, so callers pass the raw uint256.
interface IAnonAadhaar {
    function verifyAnonAadhaarProof(
        uint256 nullifierSeed,
        uint256 nullifier,
        uint256 timestamp,
        uint256 signal,
        uint256[4] calldata revealArray,
        uint256[8] calldata groth16Proof
    ) external view returns (bool);
}
