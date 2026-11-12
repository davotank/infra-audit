// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReviewManager} from "./ReviewManager.sol";

/// @title TreasuryVault
/// @notice Holds community donations in a single stablecoin and splits every inflow into
///         budget buckets by fixed rules. Every inflow and outflow emits an event, and the
///         public dashboard is built from those events.
///
/// Custody model: this contract is the rulebook and the stewards' Safe multisig is its
/// owner. The Safe can only move funds out of a bucket through `spend`, which records the
/// bucket, recipient and a memo. It cannot move funds between buckets. Audit bounties are
/// opened permissionlessly once ReviewManager reports that a tender is below the quality
/// threshold, and are paid only after the auditor files a report.
///
/// On-ramp compatibility: UPI on-ramps (Onmeta, Transak, ...) deliver tokens with a plain
/// ERC-20 transfer, not by calling `donate`. Anyone can call `sync()` to split such
/// unaccounted tokens by the same rules.
contract TreasuryVault is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Bucket {
        GasPaymaster,
        AuditBounties,
        Infrastructure
    }

    enum BountyStatus {
        None,
        Open,
        Assigned,
        Reported,
        Paid,
        Cancelled
    }

    struct Bounty {
        BountyStatus status;
        address auditor;
        uint128 amount;
        string reportCID;
    }

    uint256 public constant BPS = 10_000;
    uint256 private constant BUCKET_COUNT = 3;

    IERC20 public immutable token;
    ReviewManager public immutable reviews;

    uint16[3] public splitBps = [4000, 4000, 2000];
    uint256[3] public bucketBalance;
    /// Funds reserved for open bounties. They are already out of the AuditBounties bucket.
    uint256 public escrowedForBounties;
    uint128 public bountyAmount;

    mapping(uint256 tenderId => Bounty) private _bounties;

    event Donation(address indexed donor, uint256 amount);
    event UnaccountedFundsSynced(uint256 amount);
    event Allocated(uint256 gasPaymaster, uint256 auditBounties, uint256 infrastructure);
    event Spent(Bucket indexed bucket, address indexed to, uint256 amount, string memo);
    event SplitUpdated(uint16[3] splitBps);
    event BountyAmountUpdated(uint128 amount);
    event BountyOpened(uint256 indexed tenderId, uint128 amount, address openedBy);
    event BountyAssigned(uint256 indexed tenderId, address indexed auditor);
    event BountyReported(uint256 indexed tenderId, address indexed auditor, string reportCID);
    event BountyPaid(uint256 indexed tenderId, address indexed auditor, uint128 amount);
    event BountyCancelled(uint256 indexed tenderId, string reason);

    error ZeroAmount();
    error InsufficientBucket(Bucket bucket, uint256 available, uint256 requested);
    error InvalidSplit();
    error NotEligibleForAudit(uint256 tenderId);
    error BadBountyState(uint256 tenderId, BountyStatus status);
    error NotAssignedAuditor();
    error ZeroAddress();

    constructor(address owner_, IERC20 token_, ReviewManager reviews_, uint128 bountyAmount_) Ownable(owner_) {
        token = token_;
        reviews = reviews_;
        bountyAmount = bountyAmount_;
    }

    // ---------------------------------------------------------------------
    // Inflows
    // ---------------------------------------------------------------------

    /// @notice Donate `amount` tokens (requires prior approve). Deliberately takes no tenderId:
    ///         linking a donation to a project right after a review could de-anonymise the reviewer.
    function donate(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - before;
        emit Donation(msg.sender, received);
        _allocate(received);
    }

    /// @notice Split any tokens sent directly (e.g. by a fiat on-ramp) into the buckets.
    function sync() external nonReentrant returns (uint256 amount) {
        amount = unaccounted();
        if (amount == 0) revert ZeroAmount();
        emit UnaccountedFundsSynced(amount);
        _allocate(amount);
    }

    function unaccounted() public view returns (uint256) {
        return token.balanceOf(address(this)) - totalAccounted();
    }

    function totalAccounted() public view returns (uint256 total) {
        for (uint256 i; i < BUCKET_COUNT; ++i) total += bucketBalance[i];
        total += escrowedForBounties;
    }

    function _allocate(uint256 amount) private {
        uint256 gas = (amount * splitBps[0]) / BPS;
        uint256 audit = (amount * splitBps[1]) / BPS;
        uint256 infra = amount - gas - audit; // rounding dust goes to infrastructure
        bucketBalance[0] += gas;
        bucketBalance[1] += audit;
        bucketBalance[2] += infra;
        emit Allocated(gas, audit, infra);
    }

    // ---------------------------------------------------------------------
    // Outflows (owner = stewards' Safe)
    // ---------------------------------------------------------------------

    /// @notice Pay `amount` from `bucket` to `to`. `memo` should reference an off-chain invoice or IPFS CID.
    function spend(Bucket bucket, address to, uint256 amount, string calldata memo) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 i = uint256(bucket);
        if (bucketBalance[i] < amount) revert InsufficientBucket(bucket, bucketBalance[i], amount);
        bucketBalance[i] -= amount;
        emit Spent(bucket, to, amount, memo);
        token.safeTransfer(to, amount);
    }

    function setSplit(uint16[3] calldata newSplit) external onlyOwner {
        if (uint256(newSplit[0]) + newSplit[1] + newSplit[2] != BPS) revert InvalidSplit();
        splitBps = newSplit;
        emit SplitUpdated(newSplit);
    }

    function setBountyAmount(uint128 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        bountyAmount = amount;
        emit BountyAmountUpdated(amount);
    }

    // ---------------------------------------------------------------------
    // Audit bounties
    // ---------------------------------------------------------------------

    /// @notice Anyone can open a bounty once the tender has crossed the review threshold.
    function openBounty(uint256 tenderId) external nonReentrant {
        Bounty storage b = _bounties[tenderId];
        if (b.status != BountyStatus.None && b.status != BountyStatus.Cancelled) {
            revert BadBountyState(tenderId, b.status);
        }
        if (!reviews.isBelowAuditThreshold(tenderId)) revert NotEligibleForAudit(tenderId);

        uint128 amount = bountyAmount;
        uint256 i = uint256(Bucket.AuditBounties);
        if (bucketBalance[i] < amount) revert InsufficientBucket(Bucket.AuditBounties, bucketBalance[i], amount);
        bucketBalance[i] -= amount;
        escrowedForBounties += amount;

        _bounties[tenderId] = Bounty({status: BountyStatus.Open, auditor: address(0), amount: amount, reportCID: ""});
        emit BountyOpened(tenderId, amount, msg.sender);
    }

    /// @notice Stewards assign a vetted, certified civil engineer.
    function assignAuditor(uint256 tenderId, address auditor) external onlyOwner {
        if (auditor == address(0)) revert ZeroAddress();
        Bounty storage b = _bounties[tenderId];
        if (b.status != BountyStatus.Open) revert BadBountyState(tenderId, b.status);
        b.status = BountyStatus.Assigned;
        b.auditor = auditor;
        emit BountyAssigned(tenderId, auditor);
    }

    /// @notice The auditor files the signed report (audit-report.schema.json) pinned to IPFS.
    function submitReport(uint256 tenderId, string calldata reportCID) external {
        Bounty storage b = _bounties[tenderId];
        if (b.status != BountyStatus.Assigned) revert BadBountyState(tenderId, b.status);
        if (msg.sender != b.auditor) revert NotAssignedAuditor();
        if (bytes(reportCID).length == 0) revert ZeroAmount();
        b.status = BountyStatus.Reported;
        b.reportCID = reportCID;
        emit BountyReported(tenderId, msg.sender, reportCID);
    }

    function approveBounty(uint256 tenderId) external onlyOwner nonReentrant {
        Bounty storage b = _bounties[tenderId];
        if (b.status != BountyStatus.Reported) revert BadBountyState(tenderId, b.status);
        b.status = BountyStatus.Paid;
        escrowedForBounties -= b.amount;
        emit BountyPaid(tenderId, b.auditor, b.amount);
        token.safeTransfer(b.auditor, b.amount);
    }

    /// @notice Return escrowed funds to the audit bucket (auditor unavailable, report rejected, ...).
    function cancelBounty(uint256 tenderId, string calldata reason) external onlyOwner {
        Bounty storage b = _bounties[tenderId];
        if (b.status != BountyStatus.Open && b.status != BountyStatus.Assigned && b.status != BountyStatus.Reported) {
            revert BadBountyState(tenderId, b.status);
        }
        b.status = BountyStatus.Cancelled;
        escrowedForBounties -= b.amount;
        bucketBalance[uint256(Bucket.AuditBounties)] += b.amount;
        emit BountyCancelled(tenderId, reason);
    }

    function getBounty(uint256 tenderId) external view returns (Bounty memory) {
        return _bounties[tenderId];
    }

    function getBucketBalances() external view returns (uint256[3] memory) {
        return bucketBalance;
    }
}
