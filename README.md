# infra-audit

A public, tamper-proof registry of Indian infrastructure tenders, with **anonymous, verified citizen ratings** (Anon Aadhaar zero-knowledge proofs) and a **rules-based community treasury** that funds independent engineering audits of failing projects.

Status: **Phase 1 proof of concept**, targeting Polygon Amoy.

## Repository layout

```
packages/
  contracts/   Hardhat + OpenZeppelin 5, Solidity 0.8.24
    contracts/TenderRegistry.sol   tender mirror (PIN code, contractor hash, budget, IPFS CID)
    contracts/ReviewManager.sol    one ZK-verified anonymous rating per resident per tender
    contracts/TreasuryVault.sol    40/40/20 donation split, Safe-controlled spending, audit bounties
    test/                          22 tests
  schemas/     JSON Schemas for everything pinned to IPFS, with examples and privacy tests
docs/
  architecture.md    components, sequence diagrams, on-chain ↔ IPFS mapping
  design-review.md   where the implementation departs from the handover and why; open decisions
  handover.md        the original project handover
```

## Quick start

```bash
npm install
```

```bash
npm test
```

Deploy to Amoy (after creating the stewards' Safe):

```bash
STEWARDS_SAFE=0x... ANON_AADHAAR=0x... STABLECOIN=0x... AMOY_RPC_URL=... DEPLOYER_PRIVATE_KEY=... npm run deploy:amoy -w @infra-audit/contracts
```

## Key design decisions

- **The ZK proof is the authorisation; `msg.sender` is ignored.** Any relayer can submit a review, and citizens need no wallet, so no on-chain account links one person's reviews.
- **The nullifier seed is per tender**: one review per person per project, and reviews of different projects cannot be linked.
- **The proof's signal commits to `(tenderId, rating, evidenceCID)`**, so relayers cannot tamper with reviews.
- **The treasury is a rules contract owned by a Safe.** Inflows are split automatically, including direct on-ramp transfers via `sync()`. Every outflow is labelled by bucket. Audit bounties open permissionlessly once ratings cross the threshold.

Read [docs/design-review.md](docs/design-review.md) before building further: it covers MACI, ERC-4337, the oracle and legal (FCRA) issues in the original plan.

## Next steps

1. Create the stewards' Safe on Amoy, then deploy against the real Anon Aadhaar verifier and test one proof end to end.
2. Relayer service: an HTTP endpoint that calls `submitReview` and keeps no request logs.
3. Next.js PWA: tender map/search, a review flow using `@anon-aadhaar/react`, and a treasury dashboard built from events.
4. Onboard 20–50 pilot tenders using `tender.schema.json`.
5. Brief legal counsel using the list in design-review.md §9.
