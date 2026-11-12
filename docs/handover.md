# Project handover: Decentralized Public Infrastructure & Anti-Corruption Registry (India)

> The original handover document, kept for reference. Where the implementation differs, see
> [design-review.md](./design-review.md).

## 1. Executive summary

**Vision:** A tamper-proof, transparent Web3 platform that tracks Indian public infrastructure tenders, contractor performance, and project quality on-chain.

**Core mechanism:** Public procurement data is mirrored onto a low-cost blockchain. Verified local citizens anonymously rate infrastructure quality using zero-knowledge proofs (ZKPs) to prevent retaliation. The platform is sustained entirely by transparent, user-driven micro-donations and Quadratic Funding pools.

## 2. System architecture & tech stack

### A. Blockchain & smart contracts
- **Network:** Polygon PoS or Arbitrum (low gas fees, high throughput, strong EVM ecosystem).
- **Account Abstraction (ERC-4337):** gasless transactions for citizens via a Paymaster contract.
- **Core contracts:**
  - `TenderRegistry.sol`: tender metadata, contractor wallet/ID hashes, budget allocations, completion timelines.
  - `ReviewManager.sol`: verifies ZKP nullifiers, records immutable 1–5 star ratings, links IPFS hashes of photo/video evidence.
  - `TreasuryVault.sol` (Safe multisig): manages donations, funds the Paymaster gas pool, disburses bounties for independent engineering audits.
  - `QuadraticFunding.sol`: distributes matching pools based on the number of unique verified citizen supporters per project.

### B. Identity & privacy
- **Anon Aadhaar (ZKP):** prove possession of a valid Aadhaar and residence in the relevant district/PIN without exposing name, Aadhaar number or wallet address on-chain.
- **Nullifiers:** deterministic hash per (user, project), so one rating per citizen per project while remaining anonymous.
- **MACI:** prevents vote buying/coercion by ensuring users cannot prove how they rated.

### C. Storage & data ingestion
- **IPFS / Filecoin:** tender PDFs, blueprints, citizen photos, audit reports; only CIDs on-chain.
- **Chainlink Functions:** fetch and verify tender data from CPPP and state e-procurement portals to populate `TenderRegistry`.

### D. Frontend & fiat on-ramp
- **PWA:** React/Next.js, optimised for low-bandwidth mobile.
- **Donation bridge:** compliant UPI-to-stablecoin on-ramp (e.g. Onmeta, Transak) into `TreasuryVault`.

## 3. Core user workflows

**Workflow 1: Tender onboarding.** The oracle fetches newly awarded tenders, the details are written to `TenderRegistry`, and anyone can browse them by map, PIN code or contractor.

**Workflow 2: Anonymous citizen rating.** The citizen uploads photo evidence and generates a local Anon Aadhaar proof. The Paymaster sponsors gas, and the rating and IPFS hash are recorded on-chain.

**Workflow 3: Post-vote donation & treasury allocation.** After rating, an optional "Support the Platform" prompt appears. Donations via UPI or crypto go to `TreasuryVault` and are split automatically (e.g. 40% Gas Paymaster, 40% Audit Bounties, 20% Infrastructure & IPFS pinning). Every rupee in and out is visible on a public dashboard.

## 4. Governance & sustainability
- **Zero central ownership:** treasury controlled by a multisig of rotating, vetted civic stewards plus contract rules.
- **Audit bounties:** when a project drops below a critical rating (e.g. < 2.0 stars with 100+ verified reviews), the treasury unlocks a bounty for certified independent civil engineers to run physical tests and upload signed reports to IPFS.
- **RetroPGF:** developers, data scrapers and journalists who expose major defects are rewarded periodically by community vote.

## 5. Phased roadmap
- **Phase 1 (months 1–2):** deploy `TenderRegistry` and `ReviewManager` on Polygon Amoy; integrate the Anon Aadhaar SDK; manually onboard 20–50 municipal road projects in one pilot city (Bengaluru or Pune).
- **Phase 2 (months 3–4):** ERC-4337 Paymaster; public `TreasuryVault` with real-time dashboard; UPI-to-stablecoin widget.
- **Phase 3 (months 5–6):** automated tender ingestion via Chainlink; third-party contract and circuit audits; mainnet beta in one ward with local NGOs.

## 6. Key risks & mitigations

| Risk | Mitigation |
|---|---|
| Fake reviews / Sybil attacks | Anon Aadhaar ZKPs and per-project nullifiers |
| Contractor retaliation | No PII or wallet links on-chain; photo metadata stripped |
| Regulatory friction on crypto donations | FIU-registered on-ramps; non-profit civic tech foundation |
| Low smartphone / Web3 literacy | Passkeys and sponsored gas hide blockchain complexity |

## 7. Immediate next steps
1. **Repository setup:** monorepo with Hardhat/Foundry, Next.js and Anon Aadhaar circuits.
2. **Pilot data schema:** exact JSON metadata schema for tenders and citizen evidence on IPFS.
3. **Legal review:** Indian Web3 counsel on UPI-to-stablecoin routing and data privacy (DPDP Act).
