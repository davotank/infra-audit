import { ethers } from "hardhat";

/**
 * Deploys TenderRegistry, ReviewManager and TreasuryVault.
 *
 * Required env:
 *   STEWARDS_SAFE       Safe multisig that owns everything (create it at app.safe.global first)
 *   ANON_AADHAAR        Address of the deployed Anon Aadhaar verifier on this network
 *   STABLECOIN          ERC-20 the treasury accounts in (e.g. USDC on Polygon)
 * Optional:
 *   BOUNTY_AMOUNT       In token base units (default 500 * 10^6)
 *
 * Note: on testnet you may want STEWARDS_SAFE = deployer so you can onboard pilot tenders
 * yourself; transfer ownership/roles to the Safe before mainnet.
 */
async function main() {
  const safe = required("STEWARDS_SAFE");
  const anonAadhaar = required("ANON_AADHAAR");
  const stablecoin = required("STABLECOIN");
  const bounty = BigInt(process.env.BOUNTY_AMOUNT ?? 500_000_000);

  const registry = await ethers.deployContract("TenderRegistry", [safe]);
  await registry.waitForDeployment();
  console.log("TenderRegistry", await registry.getAddress());

  const reviews = await ethers.deployContract("ReviewManager", [safe, anonAadhaar, await registry.getAddress()]);
  await reviews.waitForDeployment();
  console.log("ReviewManager ", await reviews.getAddress());

  const vault = await ethers.deployContract("TreasuryVault", [safe, stablecoin, await reviews.getAddress(), bounty]);
  await vault.waitForDeployment();
  console.log("TreasuryVault ", await vault.getAddress());
}

function required(name: string): string {
  const v = process.env[name];
  if (!v || !ethers.isAddress(v)) throw new Error(`${name} must be set to an address`);
  return v;
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
