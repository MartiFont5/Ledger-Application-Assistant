# ✅ Test Scenarios — Ledger Application Assistant

Acceptance scenarios for the MVP, derived from section 44 of the functional specification. Each row is written so it can be executed by hand in a sandbox **and** used as the specification for an automated test codeunit.

Unless a row says otherwise, run every scenario twice: once for a **customer** and once for a **vendor**. Both use the same engine and the same pages, so a difference between them is a defect.

**Legend** — Applying entry = the movement that settles (Level 1). Applied entry = the movement being settled (Level 2).

---

## 1. Explicit reference

| # | Setup | Action | Expected result |
|---|-------|--------|-----------------|
| 1.1 | Invoice `FV001` 1,000 open. Payment 1,000 whose description reads `Payment FV001` | Create proposal | One group. Applying entry = the payment. Applied entry = `FV001`, amount 1,000. Match Method `Explicit Reference`, Confidence `Very High` |
| 1.2 | Invoice `FV001` 1,000 open. Payment 600 with description `Payment FV001` | Create proposal | One group, applied amount 600. `FV001` keeps 400 open |
| 1.3 | Invoice `FV001` 1,000. Payment 1,000 with Payment Reference = `FV001` | Create proposal | Same as 1.1 — the reference is taken from the payment reference |
| 1.4 | Invoice with External Document No. `EXT-77`. Payment with description `Ref EXT-77` | Create proposal | Matched by external document number |
| 1.5 | Invoice `FV001` dated 1 January. Payment referencing `FV001` dated 1 December. `Max. Match Date Difference` = 5 | Create proposal | Still matched — an explicit reference ignores the date limit |
| 1.6 | Payment referencing `FV001`, where `FV001` is already closed | Create proposal | No explicit-reference group for `FV001`; the payment falls through to the later rules |

---

## 2. Exact 1:1

| # | Setup | Action | Expected result |
|---|-------|--------|-----------------|
| 2.1 | One invoice 500, one payment 500, no references | Create proposal | One group, Match Method `Exact 1:1`, Confidence `High`. Applying entry = the more recent movement |
| 2.2 | Two invoices of 500 each, one payment 500 | Create proposal | **No** `Exact 1:1` group. The payment is flagged `Multiple Exact Matches` and only FIFO may allocate it |
| 2.3 | One invoice 500, two payments of 500 | Create proposal | **No** `Exact 1:1` group — ambiguity is symmetrical |
| 2.4 | Invoice 500 dated 1 March, payment 500 dated 30 April, `Max. Match Date Difference` = 10 | Create proposal | No `Exact 1:1` group; the date limit applies to matches made only by amount |
| 2.5 | Invoice 500 posted after the payment 500 | Create proposal | Applying entry = the invoice, because it is the more recent movement |

---

## 3. Exact 1:N

| # | Setup | Action | Expected result |
|---|-------|--------|-----------------|
| 3.1 | Invoices 600 and 400, payment 1,000 (most recent) | Create proposal | One group: applying entry = payment, applied entries = both invoices with 600 and 400. Match Method `Exact 1:N` |
| 3.2 | Invoice 1,000 (oldest), payments 600 and 400 | Create proposal | **Two** groups: payment 600 applying invoice 600, payment 400 applying invoice 400. The N:1 relation is normalized, never stored as one group |
| 3.3 | Invoices 500, 500 and 1,000; payment 1,000 | Create proposal | More than one exact combination exists → no `Exact 1:N` group, flagged `Multiple Exact Matches` |
| 3.4 | Six invoices that only add up in a five-line combination, `Max. Combination Lines` = 3 | Create proposal | No `Exact 1:N` group — the combination size limit is respected |
| 3.5 | Large open balance, dozens of entries | Create proposal | Completes without a noticeable delay: the candidate pool, the combination size and the visited states are all capped |

---

## 4. Payment tolerance

| # | Setup | Action | Expected result |
|---|-------|--------|-----------------|
| 4.1 | General Ledger Setup allows a tolerance of 5. Invoice 1,000, payment 995 | Create proposal | One group, Match Method `Payment Tolerance`, Confidence `Medium`. The applied invoice carries its full 1,000 |
| 4.2 | Same as 4.1, registered | Post | Standard Business Central closes the invoice and posts the tolerance entry. The extension posts nothing itself |
| 4.3 | Tolerance allows 5. Invoice 1,000, payment 900 | Create proposal | No tolerance group — the difference exceeds what standard BC accepts. FIFO may still allocate 900 |
| 4.4 | Payment tolerance not configured at all | Create proposal | The tolerance rule is inactive; no group uses it |
| 4.5 | Two invoices both within tolerance of the same payment | Create proposal | No tolerance group — the rule only proposes an unambiguous counterpart |

---

## 5. Residual FIFO

| # | Setup | Action | Expected result |
|---|-------|--------|-----------------|
| 5.1 | `FV001` 800, `FV002` 700, `FV003` 900 (in that date order), then payments `P001` 1,000 and `P002` 600 | Create proposal | Group 1: `P001` applying `FV001` 800 and `FV002` 200. Group 2: `P002` applying `FV002` 500 and `FV003` 100. `FV003` keeps 800 open |
| 5.2 | One payment 1,000, three older invoices of 400 each | Create proposal | One group consuming 400, 400 and 200, oldest first. The third invoice keeps 200 |
| 5.3 | One invoice 1,000, two later payments of 600 and 400 | Create proposal | Two groups, each payment applying its share of the invoice |
| 5.4 | Balance that cannot be fully allocated | Create proposal | FIFO still produces groups for what it can allocate; it does not require an exact zero-sum cluster |
| 5.5 | Customer with EUR and USD open entries | Create proposal | One proposal, separate groups per currency. No group mixes currencies |
| 5.6 | `Enable Residual FIFO` = No | Create proposal | Only deterministic groups are created; residual balances are left alone |
| 5.7 | `FIFO Default Confidence` = `Very Low` | Create proposal | FIFO groups show `Very Low` and are visually distinguishable from the exact ones |

---

## 6. Manual adjustment

| # | Setup | Action | Expected result |
|---|-------|--------|-----------------|
| 6.1 | A pending FIFO group with spare capacity on its applying entry | Add Movements | Only compatible entries are offered: same entity, same currency, opposite sign, still available. Selected entries join the group and it is marked *Manually Modified* |
| 6.2 | A pending group | Add Movements, multi-select two entries | Both are added; neither the applying entry nor the added entries are over-allocated |
| 6.3 | A group whose applying entry is fully allocated | Add Movements | Nothing can be added; the user is told so |
| 6.4 | A group with two applied entries | Remove Movement on one | The line disappears, the freed amount becomes available again, the group is marked *Manually Modified*. The ledger entry itself is unchanged |
| 6.5 | A group with one applied entry | Remove Movement | The whole group disappears, applying entry included |
| 6.6 | Customer with EUR and USD entries, a EUR group selected | Add Movements | The USD entries are not offered at all |
| 6.7 | A registered group | Add Movements / Remove Movement | Refused — registered groups are immutable |
| 6.8 | An applying entry line selected | Remove Movement | Refused with a message explaining that only indented applied entries can be removed |

---

## 7. Reuse of the same entry across groups

| # | Setup | Action | Expected result |
|---|-------|--------|-----------------|
| 7.1 | Scenario 5.1 | Inspect `FV002` | It appears in two groups, with 200 in one and 500 in the other. The total never exceeds its remaining amount |
| 7.2 | Scenario 5.1 | Add Movements on another group and look for `FV002` | The available amount offered is its remaining amount less what the other pending groups already reserve |
| 7.3 | Scenario 5.1 | Register group 1, then Add Movements elsewhere | The amount consumed by the registered group is no longer counted as reserved — it is already reflected in the ledger balance |

---

## 8. Obsolescence

| # | Setup | Action | Expected result |
|---|-------|--------|-----------------|
| 8.1 | Active proposal for customer A | Post a new invoice for customer A, reopen the proposal list | The proposal is marked *Obsolete* |
| 8.2 | Active proposal for customer A | Apply two entries of customer A by hand with the standard action | Marked *Obsolete* — the detailed entry marker caught it |
| 8.3 | Active proposal for customer A | Post an invoice for customer **B** | Proposal A stays valid. Other entities never obsolete it |
| 8.4 | Active proposal with several groups | Register one group successfully | The proposal stays valid and becomes *Partially Registered*. Its own posting refreshes the markers |
| 8.5 | Obsolete proposal | Try Post, Post All, Add Movements, Remove Movement | All refused with a message explaining that the ledger data changed and a new proposal is needed |
| 8.6 | Obsolete *Partially Registered* proposal | Try to continue posting | Refused. The groups already registered stay registered |
| 8.7 | Fully registered proposal | Post new entries for the same entity, reopen the list | It stays *Registered* and is not flagged — registered proposals need no monitoring |
| 8.8 | Active proposal | Open the proposal list | The check reads only the two markers per active proposal; no proposal line is scanned |

---

## 9. Post

| # | Setup | Action | Expected result |
|---|-------|--------|-----------------|
| 9.1 | A pending group | Post | The application is posted by standard BC. The group shows *Registered*, the header status is recalculated, the markers are refreshed |
| 9.2 | A registered group | Post again | Refused — the group is already registered |
| 9.3 | A pending group whose applied invoice was partly paid elsewhere, leaving less than proposed | Post | Refused, naming the entry and the amount that is actually left |
| 9.4 | A pending group whose applied invoice was closed elsewhere | Post | Refused because the entry is no longer open, and the proposal is marked obsolete |
| 9.5 | A group reusing an entry already consumed by a registered group of the same proposal | Post | Succeeds. `Remaining Amount at Proposal` is a snapshot, not a posting condition |
| 9.6 | A group whose applying entry is a payment settling three invoices | Post | One single application posted, covering all three |

---

## 10. Post All

| # | Setup | Action | Expected result |
|---|-------|--------|-----------------|
| 10.1 | Proposal with three valid pending groups | Post All | All three registered, in ascending group order. Status becomes *Registered* |
| 10.2 | Proposal where group 2 cannot be posted for a local reason | Post All | Groups 1 and 3 are registered, group 2 stays pending, the error is reported, status becomes *Partially Registered* |
| 10.3 | Proposal where the ledger changes mid-run | Post All | Processing stops immediately, the proposal is marked obsolete, and the groups already registered stay registered |
| 10.4 | Proposal with no pending groups | Post All | Nothing happens and the user is told there is nothing to register |

---

## 11. Proposal uniqueness

| # | Setup | Action | Expected result |
|---|-------|--------|-----------------|
| 11.1 | No proposal for customer A | Create Application Proposal | Created and opened without any question |
| 11.2 | Active proposal for customer A | Create Application Proposal | Confirmation explaining that the existing proposal will be marked obsolete |
| 11.3 | Same, confirmed | — | The old proposal becomes obsolete, a new one is created and opened |
| 11.4 | Same, cancelled | — | Nothing is created and the existing proposal is untouched |
| 11.5 | Only a *Registered* proposal exists for customer A | Create Application Proposal | Created without a question — registered proposals are history |
| 11.6 | Only an obsolete proposal exists | Create Application Proposal | Created without a question |

---

## 12. Proposal deletion

| # | Setup | Action | Expected result |
|---|-------|--------|-----------------|
| 12.1 | *Not Registered* proposal | Delete | Deleted with its lines |
| 12.2 | Obsolete proposal that never registered anything | Delete | Deleted |
| 12.3 | *Partially Registered* proposal | Delete | Refused |
| 12.4 | Obsolete proposal that contains registered groups | Refused | The audit trail of posted applications is preserved |
| 12.5 | *Registered* proposal | Delete | Refused |

---

## 13. Entry points and UI

| # | Setup | Action | Expected result |
|---|-------|--------|-----------------|
| 13.1 | Customer Ledger Entries, any entry of customer A selected | Create Application Proposal | Every eligible open entry of customer A is analysed, not only the selected one |
| 13.2 | Customer Ledger Entries | Application Proposals | The list opens filtered to customer A |
| 13.3 | Vendor Ledger Entries | Both actions | Same behaviour, by vendor |
| 13.4 | Any proposal | Open the tree | Groups can be expanded and collapsed; applied entries are indented under their applying entry |
| 13.5 | A manually modified group | Look at the tree | Visibly marked as manually modified, with the original match method still visible for context |
| 13.6 | Application Proposals list | Use the *Active* and *Registered* views | Filter correctly |
| 13.7 | Ledger Application Setup | Change Payment Tolerance | A confirmation explains that standard company-wide configuration will change, then the standard process runs |

---

## 14. AI candidate classification

Turn **Enable AI Matching** off for these scenarios. They check classification without calling a language model.

| # | Setup | Expected classification |
|---|-------|------------------------|
| 14.1 | Two invoices of the same amount competing for one payment | `Multiple Exact Matches` |
| 14.2 | A payment whose description references an invoice that is already closed | `Textual Reference` |
| 14.3 | A movement partly allocated by an earlier rule, with a balance left | `Partial Match` |
| 14.4 | A leftover balance with no relation to anything | `Unclassified Residual` |
| 14.5 | A movement fully resolved by a deterministic rule | `None` |

---

## 15. Agent-free AI matching

These are acceptance scenarios, not a record of executed tests. Run for both customers and vendors. Unless stated otherwise, enable AI matching and direct tool execution, configure a working model, and enable residual FIFO.

| # | Setup | Action | Expected result |
|---|-------|--------|-----------------|
| 15.1 | AI matching off, direct tool execution off | Generate a proposal | Same deterministic groups, amounts and confidence as before; no direct-execution error |
| 15.2 | AI matching on, direct tool execution off, no previous proposal | Generate a proposal | Configuration error explains how to enable direct execution or disable AI matching; no proposal or AI run is created; shared setup stays off |
| 15.3 | Same as 15.2, with an active proposal | Confirm replacement | Same configuration error; existing proposal, groups and obsolete flag remain unchanged; no replacement is stored |
| 15.4 | Direct execution off | Install, upgrade, or use Register AI Assistant twice | Registration succeeds without changing shared setup; one enabled matching workflow with one step and capability, no approval or chat routing, and a three-iteration limit |
| 15.5 | Several equal-amount invoices; only one has distinctive textual evidence linking it to the payment, without a unique explicit-reference match | Generate a proposal | AI Assisted group selects only the identified candidate; candidate type and configured confidence are preserved |
| 15.6 | Same-amount invoices with no distinguishing evidence | Generate a proposal | No AI group; ordinary FIFO fallback; plain-text no-match is valid |
| 15.7 | Model returns an entry outside the offered candidates, a duplicate, a negative amount or an excessive amount | Generate a proposal | Invalid selection is rejected; no invalid or partial AI group survives; unresolved amounts remain available for FIFO |
| 15.8 | Endpoint unavailable, key missing, or tool execution fails | Generate a proposal | That case does not abort proposal generation; deterministic groups remain and FIFO handles unresolved amounts |
| 15.9 | Several ambiguous cases across two currencies | Generate a proposal | Deterministic matching runs first, then AI, then FIFO; no cross-currency groups or reservations from a previous case |
| 15.10 | AI resolves only part of an available balance | Inspect all groups | FIFO sees the AI reservation; total proposed never exceeds available balance |
| 15.11 | Missing framework setup or disabled matching workflow | Generate a proposal | Existing deterministic-only fallback; no agent configuration is required |
| 15.12 | Proposal with AI Assisted and deterministic groups | Post / Post All | User-triggered standard posting remains unchanged; a failed group does not undo successful groups |

---

## Notes for automating these

- The test app is a separate AL project that depends on this extension, plus the Microsoft test libraries (`Test Runner`, `Library Assert`, `Tests-TestLibraries`, `System Application Test Library`). The AL compiler compiles every `.al` file under the project folder, nested folders included, so the test project cannot live inside this one.
- Build the fixtures with the standard libraries — `LibrarySales`, `LibraryPurchase`, `LibraryERM`, `LibraryJournals` — and post real documents. The engine reads `Remaining Amount`, which only exists once entries are posted.
- Section 5 and section 7 are the highest-value automated tests: they pin the FIFO allocation order and the availability arithmetic, which are the two places where a regression would be silent.
- Obsolescence tests only need a new posted entry for the same entity; there is no need to simulate a concurrent session.
- For sections 9 and 10, assert on the resulting `Detailed Cust. Ledg. Entry` / `Detailed Vendor Ledg. Entry` rows, not only on the proposal, so that the test proves the ledger really moved.
