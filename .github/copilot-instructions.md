# Ledger Application Assistant

## What this extension does
Generates, reviews and posts application proposals for open customer and vendor ledger entries. A deterministic matching engine reads the eligible open entries of one customer/vendor, builds application groups (one applying entry + N applied entries), and the user reviews, adjusts and registers them from a tree page. Registration always goes through the standard Business Central application codeunits — the extension never posts applications itself. It only extends standard behaviour: two actions are added to the standard Customer/Vendor Ledger Entries pages and nothing standard is replaced.

## Identity
- Publisher: Deloitte
- Affix: `LAA_` — prefix on all object names (e.g. `LAA_LedgerApplProposalHeader`)
- Object ID range: `87500–87550` (must match `app.json`)
- Target: Business Central 28 (SaaS), runtime 17.0
- Language: AL

## Dependencies
None. This is the **no-AI variant** of the extension: the `AI Integration` dependency
(Deloitte, `a97d6237-e1cd-4234-99c4-a578251c3b40`) has been removed from `app.json`, and
every object and call site that bound to it is commented out rather than deleted. Do not
re-introduce the dependency or uncomment the AI layer on this branch.

## Documentation language
English. Captions, tooltips and labels carry a Spanish translation in `Comment = 'ESP="..."'`.

## Object map
| Range | Objects |
|---|---|
| Tables `87500–87502` | `LAA_LedgerApplSetup`, `LAA_LedgerApplProposalHeader`, `LAA_LedgerApplProposalLine` |
| Enums `87510–87516` | `LAA_EntityType`, `LAA_ProposalStatus`, `LAA_ProposalLineLevel`, `LAA_MatchMethod`, `LAA_Confidence`, `LAA_AICandidateType`, `LAA_RegistrationStatus` |
| Codeunits `87500–87505`, `87511` | `LAA_LedgerApplProposalMgt`, `LAA_LedgerApplMatching`, `LAA_LedgerApplPosting`, `LAA_LedgerApplEntityMgt`, `LAA_LedgerApplPostGroup`, `LAA_LedgerApplInstall`, `LAA_LedgerApplUpgrade` |
| Pages `87500–87504` | `LAA_LedgerApplSetup`, `LAA_LedgerApplProposalList`, `LAA_LedgerApplProposalLines`, `LAA_ApplEntryCandidates` (87502 is free — the proposal card was removed) |
| PageExtensions `87510–87511` | `LAA_CustLedgerEntriesExt` (page 25), `LAA_VendLedgerEntriesExt` (page 29) |
| PermissionSets `87500–87501` | `LAA_Admin`, `LAA_User` |
| AI layer, `src/ai/` | **Commented out in this variant.** Codeunits `87506–87510` and EnumExtensions `87517–87519`. IDs stay reserved so the layer can be restored unchanged |

## Architecture rules
These are the load-bearing decisions. Do not work around them.

- **Three functional tables only.** A group is *not* a table: it is one `Level = Applying Entry` line plus one or more `Level = Applied Entry` lines sharing a `Group No.`. Do not add a group table.
- **`LAA_LedgerApplProposalMgt` owns the model.** Nothing else inserts, changes or deletes proposal headers, groups or lines — not the matching engine, not the pages, not the future AI tool. All invariants are enforced there: one applying entry per group, one currency per group, one entity per group, never over-allocate a ledger entry.
- **`LAA_LedgerApplEntityMgt` is the only place that reads customer/vendor ledger tables.** `LAA_LedgerApplPostGroup` is the only place that writes them and calls the standard application codeunits. Everything else is entity agnostic and routes on `Enum LAA_EntityType`.
- **Groups are always normalized to 1:N before being stored.** If the engine finds an N:1 or N:N relation, split it into several executable 1:N groups (`fCreateNormalizedGroups`). Never persist a generic N:N group.
- **Level 1 is a functional role, not a document type.** Rule 1: the entry carrying an explicit reference applies the others. Rule 2 (no reference): the most recent entry by Posting Date, then Entry No.
- **Payment tolerance has exactly one source: standard BC.** Read it from `General Ledger Setup` / `"Max. Payment Tolerance"` on the ledger entry, and change it only through report 34 `Change Payment Tolerance`. Never add a tolerance field to `LAA_LedgerApplSetup`.
- **Status and Obsolete are independent.** `Status` is derived from the registration of the groups (`fRecalculateStatus`). `Obsolete` comes from the two entity-filtered source markers. Do not merge them and do not add status values.
- **Own posting must not obsolete the proposal.** After a successful group registration, `fRefreshSourceMarkers` re-reads both markers. That is what distinguishes our own posting from an external change.
- **Stored amounts are snapshots, never concurrency conditions.** `Remaining Amount at Proposal` is informational. Always re-read the ledger through `fGetCurrentEntryState` before validating or posting.
- **Bounded search only.** The exact 1:N search is capped by `fMaxCombinationCandidates`, `fMaxSearchIterations` and `Max. Combination Lines`, and aborts as soon as a second solution proves the case ambiguous. Never introduce an unrestricted subset-sum or a cross-entity text search.
- **Two pages, no proposal card.** `LAA_LedgerApplProposalList` is the history and entry point; `LAA_LedgerApplProposalLines` is a full List page (not a ListPart) that shows the tree of one proposal and carries every review and posting action. Do not reintroduce a card page with a lines part. The lines page resolves its proposal through `fGetProposalHeader`, from the current line or from the `Proposal No.` filter it was opened with, so it still works for a proposal with no groups.

## The matching buffer
The matching engine and the Add Movements lookup use `Record "LAA_LedgerApplProposalLine" temporary` as an in-memory buffer instead of a fourth table. In buffer records:

- `"Line No."` = `"Ledger Entry No."` (so `Get('', <entry no>)` addresses an entry)
- `"Remaining Amount at Proposal"` = current remaining amount
- `"Amount to Apply"` = amount already reserved by generated groups
- available = the difference between the two (`fBufferAvailableAmount`)

A temporary record variable is its own table instance, so the engine never iterates an open cursor while reserving. It snapshots entry numbers into a `List of [Integer]` (`fGetEntryNoList`, ordered by currency, posting date, entry no.) and then addresses records one by one. Keep that pattern.

## Transactions
- `LAA_LedgerApplPostGroup` has `TableNo` so it can be called with `Codeunit.Run`: a group that fails rolls back alone.
- `LAA_LedgerApplPosting` commits before each `Run` and after each success. Registered groups are never rolled back because a later group fails — that is what makes `Partially Registered` real.
- Where obsolescence is detected during posting it is committed *before* the `Error`, otherwise the error would roll the flag back. Those `Commit()` calls are deliberate and commented.

## Project-specific rules
- Object names: `LAA_` + PascalCase with no spaces (`LAA_LedgerApplProposalHeader`). Fields inside own tables carry no affix.
- Procedures: `f` + PascalCase. Prefer `local`; use `internal` for the cross-object API. Codeunits are `Access = Internal`.
- Variables: `p` parameters, `r`/`rl` records, `c`/`cl` codeunits, `g`/`gl` pages, `v`/`vl` other. Temporary records put `TEMP` after the scope prefix (`rlTEMPOpenEntry`) — this deviates from CodeCop `AA0073`, which is disabled in `.vscode/_BC.ruleset.json` for that reason.
- Labels: `Text<Description><Suffix>` with `Err`, `Msg`, `Qst`, `Lbl`, `Tok`. Every placeholder documented in `Comment`, followed by the `ESP="..."` translation.
- Every new field needs `DataClassification`; every page field needs `ApplicationArea` and a `ToolTip` (the tooltip may live on the table field).
- `Obsolete` is a field name here, not the AL property — always write it quoted: `Rec."Obsolete"`.
- Enum values `"Exact 1:1"` and `"Exact 1:N"` contain a colon on purpose; keep them quoted.
- Confidence is informational. It must never gate posting.
- The UI says **Post** / **Post All** (ESP `Registrar` / `Registrar todo`); the data model and the code say *register* (`Registered`, `fRegisterGroup`, `fRegisterAll`, `LAA_ProposalStatus`). That split is intentional — do not rename the fields or the procedures to match the captions.

## Deliberately absent
Do not "fix" these by adding them — they were excluded by design:
- Error history fields, retry counters, technical error tables. A failed registration is an execution result; the group simply stays pending.
- Agent Operation, approval staging, or any other generic operation persistence of the AI framework. The AI capability stages nothing.
- A currency code on the proposal header (a proposal may hold groups in several currencies).
- Cross-currency and cross-entity application.
- Event subscribers for obsolescence — the two source markers are enough.
- Automatic repair or regeneration of an obsolete proposal.

## The AI matching layer (`src/ai/`) — DISABLED IN THIS VARIANT
The whole layer is commented out and the dependency is gone. What follows describes it as
it exists in the AI variant, kept so the layer can be restored faithfully; none of it runs
here. What is disabled: all of `src/ai/`, `fRegisterAIConfiguration` in
`LAA_LedgerApplInstall` and its callers (`LAA_LedgerApplUpgrade`, the **Register AI
Assistant** setup action), the Level 6 region and its call site in `LAA_LedgerApplMatching`,
the `AI Matching` setup group, and the `AI Agents Framework` grant plus the five AI codeunit
grants in both permission sets.

What deliberately stays live: the `LAA_AICandidateType` enum and the `AI Candidate Type`
field (Level 5 only labels what the deterministic levels could not resolve — it calls no
model), `LAA_MatchMethod::"AI Assisted"`, and the four setup fields, so the table schema is
unchanged between the two variants.

- **The deterministic engine is the owner, the AI is a guest.** `fGenerateProposal` calls `fAIMatching` and nothing else changes. A case the AI does not resolve costs nothing: the movements stay available and FIFO runs exactly as before.
- **`fGenerateProposal` runs in two passes.** All deterministic levels for every currency, then the AI pass, then FIFO for every currency. The AI pass has to `Commit()` — an LLM call is an HTTP callout — so it must never be interleaved with FIFO. Currencies never interact, so the split changes no result. Do not merge the loops back.
- **The AI tool creates groups through `LAA_LedgerApplProposalMgt` like everyone else** (`fCreateGroup` / `fAddAppliedEntry`), and `fApplyAIReservations` mirrors what it wrote onto the matching buffer. Without that mirror FIFO allocates the same amounts twice.
- **The AI case is never persisted.** It lives in `LAA_AIMatchContext`, a `SingleInstance` codeunit, from the moment the engine builds it to the moment the tool reads it. That works only because the agent has `Direct Tool Execution = true` and the tool has `Scope = Agent`, which keep the tool inline in the same session. Both flags are load bearing; changing either silently breaks every case.
- **Success is read from the proposal, never from the model.** `fRunCase` looks the group up after the run, so anything that rolled the tool call back counts as no match.
- **Registration does not happen by itself.** `OnInstallCapabilities` / `OnInstallAgents` are raised only when the *framework* is installed or upgraded, never when a dependent extension is, so subscribing to them is not enough. `LAA_LedgerApplInstall`, `LAA_LedgerApplUpgrade` and the **Register AI Assistant** setup action all call `fRegisterAIConfiguration`. After a force publish, which fires neither trigger, use the action.
- **One case fails alone.** Every case runs through `Codeunit.Run`. No configuration, no model, no key — the user still gets the deterministic proposal.
- **The model decides one thing only:** which of the preselected candidates the applying movement settles. It never chooses the applying movement, never sees a table, and never supplies a confidence.
- No new tables, no new pages, no new enum values on LAA's own enums: `LAA_MatchMethod::"AI Assisted"` already existed. The only schema growth is four setup fields.

## Building locally
`.alpackages` holds the BC 28.4 symbol packages plus `Deloitte_INT-Interfaces` and
`Microsoft_Error Messages with Recommendations` (git-ignored). This variant does **not**
need `Deloitte_AI Integration`; if the file is still in your local `.alpackages` it is
unused and can be deleted. The project compiles clean with CodeCop, UICop and
PerTenantExtensionCop against `.vscode/_BC.ruleset.json`.

## Reference
Corporate standards, reusable prompts and personas come from the shared plugin and apply automatically:
- `.github/instructions/` — always-on rules
- `.github/prompts/` — invocable actions
- `.github/agents/` — available personas

Only deviations from those standards are described above.
