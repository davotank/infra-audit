import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { deployAll, refHash, PINCODE } from "./fixtures";

describe("TenderRegistry", () => {
  it("registers a tender with ids starting at 1", async () => {
    const { registry } = await loadFixture(deployAll);
    expect(await registry.tenderCount()).to.equal(1n);
    const t = await registry.getTender(1);
    expect(t.pincode).to.equal(PINCODE);
    expect(t.status).to.equal(1n); // Awarded
    expect(await registry.tenderIdByRef(refHash("2026_BBMP_000001_1"))).to.equal(1n);
    expect(await registry.exists(0)).to.equal(false);
    expect(await registry.exists(2)).to.equal(false);
  });

  it("rejects duplicate portal references", async () => {
    const { registry, now } = await loadFixture(deployAll);
    await expect(
      registry.registerTender(refHash("2026_BBMP_000001_1"), refHash("x"), 1n, now, now + 1n, PINCODE, "cid"),
    ).to.be.revertedWithCustomError(registry, "DuplicateTender");
  });

  it("validates PIN codes and deadlines", async () => {
    const { registry, now } = await loadFixture(deployAll);
    await expect(
      registry.registerTender(refHash("a"), refHash("x"), 1n, now, now + 1n, 56001, "cid"),
    ).to.be.revertedWithCustomError(registry, "InvalidPincode");
    await expect(
      registry.registerTender(refHash("b"), refHash("x"), 1n, now, now - 1n, PINCODE, "cid"),
    ).to.be.revertedWithCustomError(registry, "InvalidInput");
  });

  it("only registrars can write", async () => {
    const { registry, stranger, now } = await loadFixture(deployAll);
    await expect(
      registry.connect(stranger).registerTender(refHash("c"), refHash("x"), 1n, now, now + 1n, PINCODE, "cid"),
    ).to.be.revertedWithCustomError(registry, "AccessControlUnauthorizedAccount");
    await expect(registry.connect(stranger).updateStatus(1, 3)).to.be.revertedWithCustomError(
      registry,
      "AccessControlUnauthorizedAccount",
    );
  });

  it("keeps history of status, metadata and deadline changes in events", async () => {
    const { registry, now } = await loadFixture(deployAll);
    await expect(registry.updateStatus(1, 2)).to.emit(registry, "TenderStatusUpdated").withArgs(1, 1, 2);
    await expect(registry.updateMetadata(1, "newcid")).to.emit(registry, "TenderMetadataUpdated");
    const extended = now + 500n * 24n * 3600n;
    await expect(registry.updateDeadline(1, extended)).to.emit(registry, "TenderDeadlineUpdated");
    const t = await registry.getTender(1);
    expect(t.metadataCID).to.equal("newcid");
    expect(t.deadline).to.equal(extended);
    await expect(registry.updateStatus(99, 2)).to.be.revertedWithCustomError(registry, "UnknownTender");
  });
});
