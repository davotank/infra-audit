import { ethers } from "hardhat";

export const PINCODE = 560001; // Bengaluru GPO
export const OTHER_PINCODE = 411001; // Pune
export const VALID_PROOF = [1n, 0n, 0n, 0n, 0n, 0n, 0n, 0n] as const;
export const INVALID_PROOF = [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n] as const;
export const USD = (n: number) => BigInt(Math.round(n * 1e6)); // 6 decimals

export const refHash = (ref: string) => ethers.keccak256(ethers.toUtf8Bytes(ref));

/** revealArray = [ageAbove18, gender, pincode, state] */
export const reveal = (pincode: number, gender = 0n): [bigint, bigint, bigint, bigint] => [1n, gender, BigInt(pincode), 0n];

export async function deployAll() {
  const [stewards, relayer, donor, auditor, stranger] = await ethers.getSigners();

  const registry = await ethers.deployContract("TenderRegistry", [stewards.address]);
  const verifier = await ethers.deployContract("MockAnonAadhaar");
  const reviews = await ethers.deployContract("ReviewManager", [
    stewards.address,
    await verifier.getAddress(),
    await registry.getAddress(),
  ]);
  const token = await ethers.deployContract("MockStablecoin");
  const vault = await ethers.deployContract("TreasuryVault", [
    stewards.address,
    await token.getAddress(),
    await reviews.getAddress(),
    USD(500),
  ]);

  const now = BigInt((await ethers.provider.getBlock("latest"))!.timestamp);
  await registry.registerTender(
    refHash("2026_BBMP_000001_1"),
    refHash("GSTIN:29ABCDE1234F1Z5"),
    250_000_000_00n, // ₹25 crore in paise
    now,
    now + 365n * 24n * 3600n,
    PINCODE,
    "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi",
  );

  return { stewards, relayer, donor, auditor, stranger, registry, verifier, reviews, token, vault, now };
}

let nullifierCounter = 1000n;
export const freshNullifier = () => ++nullifierCounter;
