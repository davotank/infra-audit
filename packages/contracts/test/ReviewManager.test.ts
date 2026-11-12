import { expect } from "chai";
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import {
  deployAll,
  freshNullifier,
  reveal,
  PINCODE,
  OTHER_PINCODE,
  VALID_PROOF,
  INVALID_PROOF,
} from "./fixtures";

const CID = "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku";

describe("ReviewManager", () => {
  async function submit(
    ctx: Awaited<ReturnType<typeof deployAll>>,
    opts: { rating?: number; nullifier?: bigint; pincode?: number; gender?: bigint; ts?: bigint; proof?: typeof VALID_PROOF } = {},
  ) {
    const ts = opts.ts ?? BigInt(await time.latest());
    return ctx.reviews
      .connect(ctx.relayer)
      .submitReview(
        1,
        opts.rating ?? 4,
        CID,
        opts.nullifier ?? freshNullifier(),
        ts,
        reveal(opts.pincode ?? PINCODE, opts.gender ?? 0n),
        opts.proof ?? VALID_PROOF,
      );
  }

  it("accepts a valid review from any relayer and updates aggregates", async () => {
    const ctx = await loadFixture(deployAll);
    const n = freshNullifier();
    await expect(submit(ctx, { rating: 2, nullifier: n }))
      .to.emit(ctx.reviews, "ReviewSubmitted")
      .withArgs(1, n, 2, CID, (v: bigint) => v > 0n);
    await submit(ctx, { rating: 5 });
    const [count, avg, hist] = await ctx.reviews.getAggregate(1);
    expect(count).to.equal(2n);
    expect(avg).to.equal(350n);
    expect(hist.map(Number)).to.deep.equal([0, 1, 0, 0, 1]);
    expect(await ctx.reviews.nullifierUsed(1, n)).to.equal(true);
  });

  it("allows one review per nullifier per tender", async () => {
    const ctx = await loadFixture(deployAll);
    const n = freshNullifier();
    await submit(ctx, { nullifier: n });
    await expect(submit(ctx, { nullifier: n })).to.be.revertedWithCustomError(ctx.reviews, "NullifierAlreadyUsed");
  });

  it("binds the proof to the per-tender seed and the review contents (no tampering by relayer)", async () => {
    const ctx = await loadFixture(deployAll);
    const seed = await ctx.reviews.seedFor(1);
    const signal = await ctx.reviews.signalFor(1, 4, CID);
    await ctx.verifier.expect(seed, signal);
    expect(seed < 2n ** 248n).to.equal(true);

    await expect(submit(ctx, { rating: 4 })).to.emit(ctx.reviews, "ReviewSubmitted");
    // Same proof, rating swapped by a malicious relayer -> signal mismatch -> invalid.
    await expect(submit(ctx, { rating: 1 })).to.be.revertedWithCustomError(ctx.reviews, "InvalidProof");
  });

  it("rejects invalid proofs, bad ratings and unknown tenders", async () => {
    const ctx = await loadFixture(deployAll);
    await expect(submit(ctx, { proof: INVALID_PROOF })).to.be.revertedWithCustomError(ctx.reviews, "InvalidProof");
    await expect(submit(ctx, { rating: 0 })).to.be.revertedWithCustomError(ctx.reviews, "InvalidRating");
    await expect(submit(ctx, { rating: 6 })).to.be.revertedWithCustomError(ctx.reviews, "InvalidRating");
    const ts = BigInt(await time.latest());
    await expect(
      ctx.reviews.submitReview(42, 3, CID, freshNullifier(), ts, reveal(PINCODE), VALID_PROOF),
    ).to.be.revertedWithCustomError(ctx.reviews, "TenderNotFound");
  });

  it("enforces residency (PIN code) and forbids revealing gender", async () => {
    const ctx = await loadFixture(deployAll);
    await expect(submit(ctx, { pincode: OTHER_PINCODE })).to.be.revertedWithCustomError(ctx.reviews, "PincodeMismatch");
    await expect(submit(ctx, { pincode: 0 })).to.be.revertedWithCustomError(ctx.reviews, "PincodeMismatch");
    await expect(submit(ctx, { gender: 77n })).to.be.revertedWithCustomError(ctx.reviews, "GenderMustNotBeRevealed");
  });

  it("enforces proof freshness", async () => {
    const ctx = await loadFixture(deployAll);
    const now = BigInt(await time.latest());
    await expect(submit(ctx, { ts: now - 4n * 3600n })).to.be.revertedWithCustomError(ctx.reviews, "ProofExpired");
    await expect(submit(ctx, { ts: now + 3600n })).to.be.revertedWithCustomError(ctx.reviews, "ProofFromFuture");
  });

  it("reports the audit threshold correctly", async () => {
    const ctx = await loadFixture(deployAll);
    await ctx.reviews.setParams(3 * 3600, 200, 3);
    await submit(ctx, { rating: 1 });
    await submit(ctx, { rating: 2 });
    expect(await ctx.reviews.isBelowAuditThreshold(1)).to.equal(false); // only 2 reviews
    await submit(ctx, { rating: 2 }); // avg 1.66
    expect(await ctx.reviews.isBelowAuditThreshold(1)).to.equal(true);
    await submit(ctx, { rating: 5 }); // avg 2.50
    expect(await ctx.reviews.isBelowAuditThreshold(1)).to.equal(false);
  });

  it("owner can pause; params are range-checked", async () => {
    const ctx = await loadFixture(deployAll);
    await ctx.reviews.pause();
    await expect(submit(ctx)).to.be.revertedWithCustomError(ctx.reviews, "EnforcedPause");
    await ctx.reviews.unpause();
    await expect(submit(ctx)).to.emit(ctx.reviews, "ReviewSubmitted");
    await expect(ctx.reviews.setParams(60, 200, 1)).to.be.revertedWith("maxProofAge out of range");
    await expect(ctx.reviews.connect(ctx.stranger).pause()).to.be.revertedWithCustomError(
      ctx.reviews,
      "OwnableUnauthorizedAccount",
    );
  });
});
