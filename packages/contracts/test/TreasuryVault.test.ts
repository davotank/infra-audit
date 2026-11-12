import { expect } from "chai";
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { deployAll, freshNullifier, reveal, PINCODE, VALID_PROOF, USD } from "./fixtures";

describe("TreasuryVault", () => {
  async function funded() {
    const ctx = await deployAll();
    await ctx.token.mint(ctx.donor.address, USD(10_000));
    await ctx.token.connect(ctx.donor).approve(await ctx.vault.getAddress(), USD(10_000));
    await ctx.vault.connect(ctx.donor).donate(USD(5_000));
    return ctx;
  }

  async function makeEligible(ctx: Awaited<ReturnType<typeof deployAll>>) {
    await ctx.reviews.setParams(3 * 3600, 200, 2);
    for (let i = 0; i < 2; i++) {
      await ctx.reviews.submitReview(1, 1, "", freshNullifier(), BigInt(await time.latest()), reveal(PINCODE), VALID_PROOF);
    }
  }

  it("splits donations 40/40/20", async () => {
    const { vault } = await loadFixture(funded);
    expect((await vault.getBucketBalances()).map(BigInt)).to.deep.equal([USD(2000), USD(2000), USD(1000)]);
    expect(await vault.unaccounted()).to.equal(0n);
  });

  it("sends rounding dust to infrastructure", async () => {
    const { vault, token, donor } = await loadFixture(funded);
    await vault.connect(donor).donate(7n);
    // 7 * 0.4 = 2.8 -> 2, 2, remainder 3
    const b = await vault.getBucketBalances();
    expect(b[0]).to.equal(USD(2000) + 2n);
    expect(b[1]).to.equal(USD(2000) + 2n);
    expect(b[2]).to.equal(USD(1000) + 3n);
    expect(await vault.totalAccounted()).to.equal(await token.balanceOf(await vault.getAddress()));
  });

  it("sync() allocates direct transfers from fiat on-ramps", async () => {
    const { vault, token, donor, stranger } = await loadFixture(funded);
    await token.connect(donor).transfer(await vault.getAddress(), USD(100));
    expect(await vault.unaccounted()).to.equal(USD(100));
    await expect(vault.connect(stranger).sync()).to.emit(vault, "UnaccountedFundsSynced").withArgs(USD(100));
    expect(await vault.unaccounted()).to.equal(0n);
    await expect(vault.sync()).to.be.revertedWithCustomError(vault, "ZeroAmount");
  });

  it("only the Safe can spend, and only within a bucket's balance", async () => {
    const { vault, token, stewards, stranger } = await loadFixture(funded);
    await expect(vault.connect(stranger).spend(0, stranger.address, 1n, "x")).to.be.revertedWithCustomError(
      vault,
      "OwnableUnauthorizedAccount",
    );
    await expect(vault.spend(2, stewards.address, USD(1001), "pinning")).to.be.revertedWithCustomError(
      vault,
      "InsufficientBucket",
    );
    await expect(vault.spend(2, stranger.address, USD(250), "ipfs://invoice-cid"))
      .to.emit(vault, "Spent")
      .withArgs(2, stranger.address, USD(250), "ipfs://invoice-cid");
    expect(await token.balanceOf(stranger.address)).to.equal(USD(250));
    expect((await vault.getBucketBalances())[2]).to.equal(USD(750));
  });

  it("split must sum to 100%", async () => {
    const { vault } = await loadFixture(funded);
    await expect(vault.setSplit([5000, 5000, 1])).to.be.revertedWithCustomError(vault, "InvalidSplit");
    await vault.setSplit([5000, 3000, 2000]);
    expect(await vault.splitBps(0)).to.equal(5000n);
  });

  describe("audit bounties", () => {
    it("cannot be opened until the review threshold is crossed", async () => {
      const ctx = await loadFixture(funded);
      await expect(ctx.vault.openBounty(1)).to.be.revertedWithCustomError(ctx.vault, "NotEligibleForAudit");
    });

    it("full lifecycle: open (permissionless) -> assign -> report -> pay", async () => {
      const ctx = await loadFixture(funded);
      await makeEligible(ctx);

      await expect(ctx.vault.connect(ctx.stranger).openBounty(1))
        .to.emit(ctx.vault, "BountyOpened")
        .withArgs(1, USD(500), ctx.stranger.address);
      expect((await ctx.vault.getBucketBalances())[1]).to.equal(USD(1500));
      expect(await ctx.vault.escrowedForBounties()).to.equal(USD(500));
      await expect(ctx.vault.openBounty(1)).to.be.revertedWithCustomError(ctx.vault, "BadBountyState");

      await ctx.vault.assignAuditor(1, ctx.auditor.address);
      await expect(ctx.vault.connect(ctx.stranger).submitReport(1, "cid")).to.be.revertedWithCustomError(
        ctx.vault,
        "NotAssignedAuditor",
      );
      await expect(ctx.vault.connect(ctx.auditor).submitReport(1, "bafyreport")).to.emit(ctx.vault, "BountyReported");

      await expect(ctx.vault.approveBounty(1)).to.emit(ctx.vault, "BountyPaid").withArgs(1, ctx.auditor.address, USD(500));
      expect(await ctx.token.balanceOf(ctx.auditor.address)).to.equal(USD(500));
      expect(await ctx.vault.escrowedForBounties()).to.equal(0n);
      expect(await ctx.vault.unaccounted()).to.equal(0n);
      expect((await ctx.vault.getBounty(1)).reportCID).to.equal("bafyreport");
    });

    it("cancel returns escrow to the audit bucket and allows re-opening", async () => {
      const ctx = await loadFixture(funded);
      await makeEligible(ctx);
      await ctx.vault.openBounty(1);
      await ctx.vault.cancelBounty(1, "auditor unavailable");
      expect((await ctx.vault.getBucketBalances())[1]).to.equal(USD(2000));
      expect(await ctx.vault.escrowedForBounties()).to.equal(0n);
      await expect(ctx.vault.openBounty(1)).to.emit(ctx.vault, "BountyOpened");
    });

    it("reverts when the audit bucket is short", async () => {
      const ctx = await loadFixture(funded);
      await makeEligible(ctx);
      await ctx.vault.setBountyAmount(USD(2001));
      await expect(ctx.vault.openBounty(1)).to.be.revertedWithCustomError(ctx.vault, "InsufficientBucket");
    });
  });
});
