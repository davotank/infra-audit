// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {IAnonAadhaar} from "../interfaces/IAnonAadhaar.sol";

/// @notice TEST ONLY. Accepts a proof iff groth16Proof[0] == 1 and the signal and seed match
///         what the test registered, so tests can check that ReviewManager binds the right values.
contract MockAnonAadhaar is IAnonAadhaar {
    bool public checkBinding;
    uint256 public expectedSeed;
    uint256 public expectedSignal;

    function expect(uint256 seed, uint256 signal) external {
        checkBinding = true;
        expectedSeed = seed;
        expectedSignal = signal;
    }

    function verifyAnonAadhaarProof(
        uint256 nullifierSeed,
        uint256,
        uint256,
        uint256 signal,
        uint256[4] calldata,
        uint256[8] calldata groth16Proof
    ) external view returns (bool) {
        if (checkBinding && (nullifierSeed != expectedSeed || signal != expectedSignal)) return false;
        return groth16Proof[0] == 1;
    }
}
