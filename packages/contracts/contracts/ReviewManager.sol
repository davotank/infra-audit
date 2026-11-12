// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IAnonAadhaar} from "./interfaces/IAnonAadhaar.sol";
import {TenderRegistry} from "./TenderRegistry.sol";

/// @title ReviewManager
/// @notice Records one anonymous 1–5 star rating per verified resident per tender.
///
/// Authorisation is the zero-knowledge proof, never msg.sender. Anyone (a relayer, an
/// ERC-4337 bundler, the citizen) may submit the transaction, and the contract stores
/// nothing about who sent it. So reviewers need no wallet, and their reviews of
/// different projects cannot be linked through a shared sender address.
///
/// How the proof is tied to the review:
///  - nullifierSeed = seedFor(tenderId). Anon Aadhaar derives nullifier = H(seed, identity),
///    so each person gets a distinct, unlinkable nullifier per tender: one review each.
///  - signal = signalFor(tenderId, rating, evidenceCID). The proof commits to the review
///    contents, so a relayer or front-runner cannot change the rating or the evidence.
///  - revealArray[2] (pincode) must equal the tender's PIN code (the residency check).
///  - revealArray[1] (gender) must NOT be revealed. It would be a permanent on-chain
///    quasi-identifier for no benefit.
contract ReviewManager is Ownable2Step, Pausable {
    uint8 public constant MIN_RATING = 1;
    uint8 public constant MAX_RATING = 5;

    IAnonAadhaar public immutable verifier;
    TenderRegistry public immutable registry;

    /// Max age of the Aadhaar QR signature timestamp accepted in a proof.
    uint64 public maxProofAge = 3 hours;
    /// Audit trigger: avg rating (x100) strictly below this, with at least `auditMinReviews` reviews.
    uint16 public auditThresholdX100 = 200;
    uint32 public auditMinReviews = 100;

    struct Aggregate {
        uint64 ratingSum;
        uint32 reviewCount;
        uint32[5] histogram; // index 0 => 1 star ... index 4 => 5 stars
    }

    mapping(uint256 tenderId => Aggregate) private _aggregates;
    mapping(uint256 tenderId => mapping(uint256 nullifier => bool)) public nullifierUsed;

    event ReviewSubmitted(
        uint256 indexed tenderId, uint256 indexed nullifier, uint8 rating, string evidenceCID, uint64 recordedAt
    );
    event ParamsUpdated(uint64 maxProofAge, uint16 auditThresholdX100, uint32 auditMinReviews);

    error InvalidRating(uint8 rating);
    error NullifierAlreadyUsed(uint256 tenderId, uint256 nullifier);
    error PincodeMismatch(uint256 expected, uint256 revealed);
    error GenderMustNotBeRevealed();
    error ProofExpired(uint256 timestamp);
    error ProofFromFuture(uint256 timestamp);
    error InvalidProof();
    error TenderNotFound(uint256 tenderId);

    constructor(address owner_, IAnonAadhaar verifier_, TenderRegistry registry_) Ownable(owner_) {
        verifier = verifier_;
        registry = registry_;
    }

    // ---------------------------------------------------------------------
    // Submission
    // ---------------------------------------------------------------------

    /// @param evidenceCID CID of the evidence JSON (evidence.schema.json) or "" for a rating with no evidence.
    function submitReview(
        uint256 tenderId,
        uint8 rating,
        string calldata evidenceCID,
        uint256 nullifier,
        uint256 timestamp,
        uint256[4] calldata revealArray,
        uint256[8] calldata groth16Proof
    ) external whenNotPaused {
        if (!registry.exists(tenderId)) revert TenderNotFound(tenderId);
        if (rating < MIN_RATING || rating > MAX_RATING) revert InvalidRating(rating);
        if (nullifierUsed[tenderId][nullifier]) revert NullifierAlreadyUsed(tenderId, nullifier);

        uint256 expectedPincode = registry.pincodeOf(tenderId);
        if (revealArray[2] != expectedPincode) revert PincodeMismatch(expectedPincode, revealArray[2]);
        if (revealArray[1] != 0) revert GenderMustNotBeRevealed();

        // Allow 5 minutes of clock skew between the citizen's phone and block time.
        if (timestamp > block.timestamp + 5 minutes) revert ProofFromFuture(timestamp);
        if (timestamp + maxProofAge < block.timestamp) revert ProofExpired(timestamp);

        bool ok = verifier.verifyAnonAadhaarProof(
            seedFor(tenderId),
            nullifier,
            timestamp,
            signalFor(tenderId, rating, evidenceCID),
            revealArray,
            groth16Proof
        );
        if (!ok) revert InvalidProof();

        nullifierUsed[tenderId][nullifier] = true;
        Aggregate storage agg = _aggregates[tenderId];
        agg.ratingSum += rating;
        agg.reviewCount += 1;
        agg.histogram[rating - 1] += 1;

        emit ReviewSubmitted(tenderId, nullifier, rating, evidenceCID, uint64(block.timestamp));
    }

    // ---------------------------------------------------------------------
    // Proof inputs: the frontend must compute exactly these values.
    // ---------------------------------------------------------------------

    /// @notice nullifierSeed to pass to the Anon Aadhaar prover for this tender.
    /// @dev Truncated to 248 bits so it is always a valid BN254 field element.
    function seedFor(uint256 tenderId) public view returns (uint256) {
        return uint256(keccak256(abi.encode("infra-audit.review.v1", block.chainid, address(this), tenderId))) >> 8;
    }

    /// @notice signal to pass to the Anon Aadhaar prover. Commits the proof to this exact review.
    function signalFor(uint256 tenderId, uint8 rating, string calldata evidenceCID) public view returns (uint256) {
        return uint256(keccak256(abi.encode(block.chainid, address(this), tenderId, rating, evidenceCID)));
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function getAggregate(uint256 tenderId)
        external
        view
        returns (uint32 reviewCount, uint16 avgRatingX100, uint32[5] memory histogram)
    {
        Aggregate storage agg = _aggregates[tenderId];
        reviewCount = agg.reviewCount;
        avgRatingX100 = _avgX100(agg);
        histogram = agg.histogram;
    }

    /// @notice True when the tender qualifies for an independent audit bounty.
    function isBelowAuditThreshold(uint256 tenderId) external view returns (bool) {
        Aggregate storage agg = _aggregates[tenderId];
        return agg.reviewCount >= auditMinReviews && _avgX100(agg) < auditThresholdX100;
    }

    function _avgX100(Aggregate storage agg) private view returns (uint16) {
        if (agg.reviewCount == 0) return 0;
        return uint16((uint256(agg.ratingSum) * 100) / agg.reviewCount);
    }

    // ---------------------------------------------------------------------
    // Admin (owner = stewards' Safe)
    // ---------------------------------------------------------------------

    function setParams(uint64 maxProofAge_, uint16 auditThresholdX100_, uint32 auditMinReviews_) external onlyOwner {
        require(maxProofAge_ >= 10 minutes && maxProofAge_ <= 7 days, "maxProofAge out of range");
        require(auditThresholdX100_ > 100 && auditThresholdX100_ <= 500, "threshold out of range");
        require(auditMinReviews_ > 0, "minReviews must be > 0");
        maxProofAge = maxProofAge_;
        auditThresholdX100 = auditThresholdX100_;
        auditMinReviews = auditMinReviews_;
        emit ParamsUpdated(maxProofAge_, auditThresholdX100_, auditMinReviews_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
