# Design review of the handover document

These issues came up while implementing the handover. Each says what changed in the code, or what decision is still open. They are ordered by how much they affect citizen safety and the project's viability.

## 1. ERC-4337 smart accounts would link a citizen's reviews (fixed in the design)

The handover gives every citizen an ERC-4337 account with a Paymaster. A smart account is a persistent on-chain address. Every review submitted from it becomes linkable, and once one review is attributed to a person, all of them are. That contradicts "no wallet links touch the blockchain".

**What the code does:** `ReviewManager.submitReview` is authorised only by the ZK proof and never reads `msg.sender`. A single relayer submits for everyone, so citizens need no account at all. The "Gas Paymaster Pool" bucket funds that relayer. A 4337 Paymaster that sponsors only `submitReview` calls would also work, as long as each citizen does **not** keep a long-lived smart account.

## 2. A proof that is not bound to the review could be rewritten by the relayer (fixed)

If the proof's `signal` does not commit to the review contents, whoever relays the transaction can change the rating or the evidence. **Fixed:** `signal = keccak(chainId, contract, tenderId, rating, evidenceCID)`, and a test shows that a swapped rating fails verification.

## 3. MACI does not fit public, per-review ratings (open decision)

MACI protects against coercion because votes stay encrypted, voters can secretly change them, and a coordinator publishes only a final tally. This design publishes every rating as soon as it is cast, with photo evidence, so MACI cannot be added on top. Adopting MACI would mean dropping public per-review ratings and evidence, running a trusted coordinator who sees votes, and producing tallies in batches.

**Recommendation:** leave MACI out of Phases 1–3. The anonymity of reviews already prevents retaliation. The remaining risk is vote buying ("prove you gave 5 stars"), which matters less here than in an election, and the 3-hour proof freshness window makes buying Aadhaar QR codes harder.

## 4. Anonymity leaks off-chain

The contracts store no personal data, but these off-chain paths can still identify a citizen:

- **IP addresses** at the relayer, the IPFS upload endpoint and the RPC node. Run the upload relay and relayer ourselves with request logging off, and say so in the privacy policy.
- **Timing of the donation prompt.** "Donate right after you vote" lets an observer match a donor's wallet to the review a few seconds earlier. `donate()` deliberately takes no `tenderId`. The UI should also avoid sending the donation in the same moment (or recommend UPI, where the on-ramp is the sender).
- **Photo metadata.** The client must re-encode images, not just "strip" EXIF. The evidence schema forbids precise timestamps, locations finer than about 150 m, and device fields (enforced by tests in `packages/schemas`).
- **Free-text notes.** Warn users before submitting; consider leaving notes out of the pilot.

## 5. "Oracle verifies tender data" claims too much (Phase 3 rescope)

Chainlink Functions has tight limits on execution time and response size. Government portals (CPPP and state portals) use CAPTCHAs, sessions and PDFs. An oracle only proves that a set of nodes fetched a URL. It does not prove the data is correct.

**Recommendation:** run an off-chain scraper that archives the original documents with SHA-256 hashes (already in `tender.schema.json`) and submits through a registrar key, with the Safe able to correct entries. Reconsider Chainlink only if the registrar becomes a trust problem.

## 6. Quadratic Funding needs per-donor Sybil resistance (deferred)

QF matching weights the number of unique contributors, but donations come from wallets, which are free to create. QF therefore needs a nullifier-backed "unique human per round" proof for each contributor, which in turn conflicts with §4 (donor and reviewer linkage). It is deferred until after the pilot, and probably better run on an existing QF stack than as custom code.

## 7. The audit threshold can be gamed in both directions

- A contractor can recruit local residents (for example their own workforce) to post 5-star ratings and keep the average above 2.0.
- A rival can brigade 1-star ratings to trigger audits. This costs the treasury money but has no other effect, since the audit itself is the remedy.
- 100+ reviews per project is high for a pilot. **The threshold is configurable** (`setParams`); start at around 20.
- Consider counting only reviews with evidence toward the trigger, or adding steward triage before `openBounty`. Both are easy to add.

## 8. Residency by Aadhaar PIN code is a rough proxy

The address on an Aadhaar card is often out of date, and people who use a road may live in a neighbouring PIN code. **Phase 1 requires an exact PIN match.** A per-tender allow-list of PIN codes is a simple extension.

## 9. Legal questions to add to the counsel brief (beyond the handover's list)

- **FCRA:** philanthropist matching pools or crypto donations from foreign donors are "foreign contributions", and the non-profit needs FCRA registration before it can accept them.
- **Aadhaar Act / UIDAI offline verification rules:** confirm whether verifying an Aadhaar QR inside a ZK proof is allowed, and on what terms.
- **DPDP Act:** sole proprietor contractors are individuals. Only hashes and CIDs go on-chain, but data pinned to IPFS cannot be guaranteed erased.
- **Defamation and intermediary liability** for citizen notes and photos (IT Rules 2021).
- **Tax:** TDS on transfers of virtual digital assets, and 80G status for donors.

## 10. Smaller notes

- The handover's TreasuryVault is "Safe Multi-Sig". In the code, the Safe is the **owner** of a rules contract, so the split cannot be bypassed and outflows are labelled by bucket.
- The Anon Aadhaar interface (`IAnonAadhaar.sol`) follows the v2 verifier. Pin and re-check it against the exact release before deploying to the testnet.
- Contracts are AGPL-3.0 so that forks stay public. Change this if the foundation prefers MIT or Apache.
