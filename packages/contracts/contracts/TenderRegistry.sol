// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title TenderRegistry
/// @notice On-chain mirror of public infrastructure tenders. Heavy data (tender PDFs,
///         BOQs, blueprints) lives on IPFS; only the fields the other contracts must
///         reason about are stored here.
/// @dev Phase 1: REGISTRAR_ROLE is held by the stewards' Safe (manual onboarding).
///      Phase 3: grant REGISTRAR_ROLE to the oracle consumer contract as well.
///      Records are never deleted; every change is an event so the history is auditable.
contract TenderRegistry is AccessControl {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    enum Status {
        None,
        Awarded,
        InProgress,
        Completed,
        Abandoned
    }

    struct Tender {
        /// keccak256 of the portal's tender reference (e.g. "2026_BBMP_123456_1"). Used for dedupe.
        bytes32 externalRefHash;
        /// keccak256 of a normalised contractor identifier (GSTIN preferred). Lets anyone
        /// aggregate a contractor's track record without storing PII on-chain.
        bytes32 contractorIdHash;
        /// Awarded value in paise (INR * 100). uint128 is far beyond any real budget.
        uint128 awardedValuePaise;
        uint64 awardedAt;
        uint64 deadline;
        /// 6-digit Indian PIN code of the work site. Used by ReviewManager for the residency check.
        uint32 pincode;
        Status status;
        /// IPFS CID of the tender metadata JSON (see packages/schemas/schemas/tender.schema.json).
        string metadataCID;
    }

    uint256 public tenderCount;
    mapping(uint256 tenderId => Tender) private _tenders;
    mapping(bytes32 externalRefHash => uint256 tenderId) public tenderIdByRef;

    event TenderRegistered(
        uint256 indexed tenderId,
        bytes32 indexed externalRefHash,
        bytes32 indexed contractorIdHash,
        uint32 pincode,
        uint128 awardedValuePaise,
        uint64 deadline,
        string metadataCID
    );
    event TenderStatusUpdated(uint256 indexed tenderId, Status previous, Status current);
    event TenderMetadataUpdated(uint256 indexed tenderId, string previousCID, string currentCID);
    event TenderDeadlineUpdated(uint256 indexed tenderId, uint64 previous, uint64 current);

    error DuplicateTender(bytes32 externalRefHash, uint256 existingId);
    error UnknownTender(uint256 tenderId);
    error InvalidPincode(uint32 pincode);
    error InvalidInput();

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
    }

    function registerTender(
        bytes32 externalRefHash,
        bytes32 contractorIdHash,
        uint128 awardedValuePaise,
        uint64 awardedAt,
        uint64 deadline,
        uint32 pincode,
        string calldata metadataCID
    ) external onlyRole(REGISTRAR_ROLE) returns (uint256 tenderId) {
        if (externalRefHash == bytes32(0) || bytes(metadataCID).length == 0) revert InvalidInput();
        if (deadline < awardedAt) revert InvalidInput();
        // Indian PIN codes are 6 digits and never start with 0.
        if (pincode < 100000 || pincode > 999999) revert InvalidPincode(pincode);
        uint256 existing = tenderIdByRef[externalRefHash];
        if (existing != 0) revert DuplicateTender(externalRefHash, existing);

        tenderId = ++tenderCount; // ids start at 1 so 0 can mean "not found"
        _tenders[tenderId] = Tender({
            externalRefHash: externalRefHash,
            contractorIdHash: contractorIdHash,
            awardedValuePaise: awardedValuePaise,
            awardedAt: awardedAt,
            deadline: deadline,
            pincode: pincode,
            status: Status.Awarded,
            metadataCID: metadataCID
        });
        tenderIdByRef[externalRefHash] = tenderId;

        emit TenderRegistered(
            tenderId, externalRefHash, contractorIdHash, pincode, awardedValuePaise, deadline, metadataCID
        );
    }

    function updateStatus(uint256 tenderId, Status status) external onlyRole(REGISTRAR_ROLE) {
        Tender storage t = _get(tenderId);
        if (status == Status.None) revert InvalidInput();
        emit TenderStatusUpdated(tenderId, t.status, status);
        t.status = status;
    }

    /// @notice Point at a new metadata document (e.g. after a corrigendum). The old CID stays in the event log.
    function updateMetadata(uint256 tenderId, string calldata metadataCID) external onlyRole(REGISTRAR_ROLE) {
        Tender storage t = _get(tenderId);
        if (bytes(metadataCID).length == 0) revert InvalidInput();
        emit TenderMetadataUpdated(tenderId, t.metadataCID, metadataCID);
        t.metadataCID = metadataCID;
    }

    /// @notice Record an official extension of time. Extensions are themselves a signal worth tracking.
    function updateDeadline(uint256 tenderId, uint64 deadline) external onlyRole(REGISTRAR_ROLE) {
        Tender storage t = _get(tenderId);
        if (deadline < t.awardedAt) revert InvalidInput();
        emit TenderDeadlineUpdated(tenderId, t.deadline, deadline);
        t.deadline = deadline;
    }

    function getTender(uint256 tenderId) external view returns (Tender memory) {
        return _get(tenderId);
    }

    function exists(uint256 tenderId) public view returns (bool) {
        return tenderId != 0 && tenderId <= tenderCount;
    }

    function pincodeOf(uint256 tenderId) external view returns (uint32) {
        return _get(tenderId).pincode;
    }

    function _get(uint256 tenderId) private view returns (Tender storage t) {
        if (!exists(tenderId)) revert UnknownTender(tenderId);
        t = _tenders[tenderId];
    }
}
