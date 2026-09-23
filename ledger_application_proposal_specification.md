# Ledger Application Proposal – Functional & Technical Specification

## 1. Purpose

Implement a Business Central feature to generate, review, adjust, and post proposed applications of open Customer Ledger Entries and Vendor Ledger Entries.

The solution must:

- Work for both customers and vendors using the same shared engine and proposal pages.
- Generate application proposals using a deterministic matching algorithm.
- Allow the user to review and manually adjust the proposed application groups.
- Post each application group deterministically using standard Business Central application logic.
- Detect when a proposal becomes obsolete because the relevant customer/vendor ledger data changed after proposal generation.
- Keep the MVP independent from the AI Agent framework, while preparing a clean integration point for future AI-assisted matching.
- Avoid unnecessary persistence, configuration duplication, or overengineering.

The feature is intentionally designed as a finance-domain capability that can later be invoked from UI actions, Job Queue, or an AI workflow.

---

# 2. Scope

## 2.1 In scope for MVP

- Customer Ledger Entries.
- Vendor Ledger Entries.
- Manual creation of an application proposal from the standard Customer Ledger Entries or Vendor Ledger Entries pages.
- Shared proposal model and shared proposal UI.
- Deterministic matching engine.
- Same-currency application only within each application group.
- Partial applications.
- Multiple application groups inside one proposal.
- Manual add/remove of movements from pending groups.
- Posting one group.
- Posting all pending groups.
- Proposal obsolescence control.
- Proposal history.
- Classification of unresolved cases that may later be handled by AI.
- Reuse of standard Business Central payment tolerance configuration and logic.

## 2.2 Explicitly out of scope for MVP

- Actual LLM calls.
- Automatic Job Queue proposal generation.
- Automatic posting without user interaction.
- Application between different currencies inside the same group.
- Matching or application across different customers/vendors.
- Automatic repair of obsolete proposals.
- Generic N:N persisted application groups.
- A dependency on Agent Operation or other operation tables from the AI Agent framework.
- Separate persistence for AI candidate combinations.
- Complex error history, retry counters, technical error tables, or logging infrastructure beyond what is required by the normal BC execution flow.

---

# 3. Entry Points

Add two page actions:

## 3.1 Customer Ledger Entries

Action:

**Create Application Proposal**

Behavior:

- Use the current Customer Ledger Entry only to identify the Customer No.
- Do not restrict the proposal to the selected/current ledger entry.
- Analyze all eligible open ledger entries for that customer.
- Create a new Ledger Application Proposal.
- Open the created proposal for review.

Additional action:

**Application Proposals**

Behavior:

- Open the proposal list filtered by:
  - Entity Type = Customer
  - Entity No. = current Customer No.

## 3.2 Vendor Ledger Entries

Same behavior using Vendor No.

Actions:

- **Create Application Proposal**
- **Application Proposals**

---

# 4. Proposal Uniqueness

Only one active proposal may exist for the same customer/vendor.

An active proposal is:

- Obsolete = false
- Status <> Registered

When the user creates a new proposal and an active proposal already exists:

1. Show a confirmation.
2. Explain that the existing active proposal will be marked obsolete.
3. If confirmed:
   - Mark the previous proposal as Obsolete = true.
   - Create the new proposal.
4. If cancelled:
   - Do not create a new proposal.

Registered proposals remain historical records and are not affected.

---

# 5. Data Model

The solution uses only three new functional tables:

1. `Ledger Application Setup`
2. `Ledger Application Proposal Header`
3. `Ledger Application Proposal Line`

No separate Group table is required.

A group is represented by one Level 1 line and one or more Level 2 lines.

---

# 6. Table: Ledger Application Setup

Keep setup intentionally small.

Suggested fields:

| Field | Purpose |
|---|---|
| Primary Key | Standard singleton setup record |
| Max. Match Date Difference | Maximum date difference allowed for purely numeric deterministic matching |
| Max. Combination Lines | Maximum number of movements considered in an exact 1:N combination search |
| Enable Residual FIFO | Enables the final low-confidence FIFO allocation |
| FIFO Default Confidence | Informational confidence assigned to FIFO-generated groups |

Do not duplicate standard Business Central payment tolerance setup.

## 6.1 Standard BC Payment Tolerance

The setup page may expose the current standard BC payment tolerance values for convenience, but these values must remain owned by the original Business Central configuration.

If the user changes payment tolerance from this page:

- Show a confirmation message explaining that standard Business Central configuration will be modified.
- Use the standard Business Central mechanism for changing/recalculating payment tolerance.
- Do not maintain a second copy of tolerance parameters in `Ledger Application Setup`.

The matching engine must evaluate tolerance using the standard BC setup and application behavior.

---

# 7. Table: Ledger Application Proposal Header

Suggested fields:

| Field | Purpose |
|---|---|
| No. | Proposal identifier |
| Entity Type | Customer / Vendor |
| Entity No. | Customer No. / Vendor No. |
| Status | Not Registered / Partially Registered / Registered |
| Obsolete | Boolean, independent from Status |
| Created At | Proposal creation date/time |
| Created By | User ID |
| Source Last Ledger Entry No. | Obsolescence control marker |
| Source Last Detailed Ledger Entry No. | Obsolescence control marker |
| No. of Groups | Optional FlowField/calculated value |
| No. of Registered Groups | Optional FlowField/calculated value |
| No. of Lines | Optional FlowField/calculated value |

Avoid adding fields unless they provide clear functional value.

Do not add:

- Error history fields.
- Retry counters.
- AI execution fields.
- Agent Operation ID.
- Currency Code at header level.

A proposal may contain groups in different currencies.

---

# 8. Proposal Status

Header Status contains only:

- `Not Registered`
- `Partially Registered`
- `Registered`

Status is derived from application groups:

## Not Registered

No group has been registered.

## Partially Registered

At least one group has been registered and at least one group remains pending.

## Registered

All groups have been registered.

`Obsolete` is a separate Boolean and is not part of Status.

Valid combinations include:

- Status = Not Registered, Obsolete = false
- Status = Not Registered, Obsolete = true
- Status = Partially Registered, Obsolete = false
- Status = Partially Registered, Obsolete = true
- Status = Registered, Obsolete = false

Registered proposals no longer need active obsolescence monitoring.

---

# 9. Table: Ledger Application Proposal Line

A single table represents both group parent and child lines.

Suggested fields:

| Field | Purpose |
|---|---|
| Proposal No. | Parent proposal |
| Line No. | Unique line number within proposal |
| Group No. | Application group identifier |
| Level | 1 = Applying Entry, 2 = Applied Entry |
| Entity Type | Customer / Vendor, if useful for validation |
| Ledger Entry No. | Cust./Vendor Ledger Entry No. |
| Document Type | Snapshot/display |
| Document No. | Snapshot/display |
| Posting Date | Snapshot/display |
| Due Date | Snapshot/display |
| Currency Code | Group-level compatibility check |
| Remaining Amount at Proposal | Snapshot for audit/information |
| Amount to Apply | Concrete amount proposed for this group |
| Match Method | How the group was generated |
| Confidence | Informational matching confidence |
| AI Candidate Type | Future AI classification |
| Manually Modified | Indicates user changed the generated group |
| Registered | Persisted only on Level 1 |

Do not persist complex error state.

A registration error is an execution result, not a business state.

If posting fails:

- Display the Business Central error to the user.
- The group remains functionally pending.
- If the failure proves that underlying ledger data changed, mark the proposal obsolete.

---

# 10. Application Group Model

Every group must have:

- Exactly one Level 1 line.
- One or more Level 2 lines.

Definition:

- **Level 1 = Applying Entry**
- **Level 2 = Applied Entry**

Persisted groups are always normalized to:

`1 Applying Entry -> N Applied Entries`

Never persist a generic N:N application group.

If the matching engine discovers an N:1 or N:N mathematical relation, normalize it into one or more executable 1:N application groups before storing Proposal Lines.

---

# 11. Choosing the Level 1 / Applying Entry

Do not force Level 1 to always be a Payment, Invoice, Credit Memo, etc.

Level 1 is a functional role, not a document type.

Use this decision order:

## Rule 1 – Explicit directional reference

If a strong explicit reference identifies a movement as the movement being applied against another movement, use that direction.

Example:

Payment description explicitly references invoice `FV001`.

Result:

- Level 1 = Payment
- Level 2 = Invoice

## Rule 2 – Chronology

If no directional relationship exists:

- Use the most recent movement in the group as Level 1.
- Use Posting Date as primary ordering.
- Use Entry No. as tie-breaker.

The rationale is that the newer movement normally consumes a previously existing open balance.

## Example – payment applies invoices

- Invoice FV001: +600
- Invoice FV002: +400
- Payment P001: -1,000

Result:

- Level 1: P001
- Level 2: FV001 600
- Level 2: FV002 400

## Example – one invoice paid by multiple payments

- Invoice FV001: +1,000
- Payment P001: -600
- Payment P002: -400

Do not create:

- Invoice as parent with two payments.

Normalize into:

Group 1:
- Level 1: P001
- Level 2: FV001, Amount to Apply = 600

Group 2:
- Level 1: P002
- Level 2: FV001, Amount to Apply = 400

The same Ledger Entry may appear in multiple groups when partially applied.

---

# 12. Reuse of the Same Ledger Entry Across Groups

A Ledger Entry may appear in multiple pending groups.

This is required for:

- Partial applications.
- FIFO.
- Multiple payments against one invoice.
- One movement progressively consumed by several later movements.

The total proposed amount across all pending groups must never exceed the movement's currently available remaining amount.

Define:

`Available Amount for Proposal`

Conceptually:

Current Remaining Amount  
minus  
Amount already reserved by other pending groups of the same proposal.

Registered groups must not be counted as reserved because their application is already reflected in the current ledger balance.

This value is used by:

- Matching Engine
- Add Movements action
- Validation before posting

---

# 13. Currency Rules

Currency is controlled at application group level.

A single proposal may contain:

- EUR groups
- USD groups
- GBP groups
- etc.

But every group must contain movements with the same Currency Code.

MVP rule:

**Do not apply movements across different currencies.**

Cross-currency application may be considered in a later phase.

---

# 14. Eligible Ledger Entries

The deterministic engine should only consider entries that are valid candidates for application.

At minimum:

- Open = true
- Remaining Amount <> 0
- Same customer/vendor
- Not reversed or otherwise invalid for application
- Compatible with standard BC application rules

The engine should use `Remaining Amount`, not original document amount.

The exact eligibility check should preferably reuse standard Business Central application validation where possible rather than recreating all standard rules.

---

# 15. Deterministic Matching Algorithm

Run the matching levels sequentially.

Once an amount is reserved in a generated group, it is no longer available for later matching levels.

The engine should operate inside:

- Entity Type
- Entity No.
- Currency Code

Different currencies are processed independently but stored in the same proposal.

---

# 16. Matching Level 1 – Explicit Reference

Highest-confidence deterministic rule.

Examples of strong references:

- Standard applies-to information.
- Payment Reference.
- External Document No.
- Explicit document number found in a movement description.
- Another unambiguous Business Central reference.

Requirements:

- Same customer/vendor.
- Same currency.
- Opposite economic sign / compatible application direction.
- Referenced entry is still open.
- Amount available is greater than zero.

Partial application is allowed.

Example:

Invoice:
- FV001
- Remaining Amount = 1,000

Payment:
- Description = `Payment FV001`
- Remaining Amount = -600

Proposal:

- Payment as Level 1
- Invoice FV001 as Level 2
- Amount to Apply = 600

Suggested confidence:

Very High / approximately 98–100%.

Explicit reference takes priority over date restrictions.

---

# 17. Matching Level 2 – Exact Unique 1:1

Find two compatible open movements where:

- Same entity.
- Same currency.
- Opposite sign.
- Exact absolute available amount.
- There is only one valid candidate for that amount.

If multiple candidates with the same amount exist, do not arbitrarily choose one.

Classify the case for future AI and continue to later processing.

Suggested confidence:

Approximately 95%.

Apply `Max. Match Date Difference` to purely numeric matches.

---

# 18. Matching Level 3 – Exact Unique 1:N

For an applying movement, search for a unique combination of compatible counterpart movements whose available amounts exactly equal the applying amount.

Rules:

- Same entity.
- Same currency.
- Opposite sign.
- Combination size <= `Max. Combination Lines`.
- Candidate lines within `Max. Match Date Difference`.
- Exact sum.
- The combination must be unique.

Do not port an unrestricted subset-sum / generic N:N engine.

The goal is not mathematical completeness.

The goal is to identify small, understandable, high-confidence exact matches.

If multiple valid exact combinations exist:

- Do not choose one deterministically.
- Classify as `Multiple Exact Matches`.
- Leave for future AI or later FIFO.

Suggested confidence for unique exact combinations:

Approximately 90%.

---

# 19. Matching Level 4 – Standard BC Payment Tolerance

Evaluate remaining compatible pairs/groups using standard Business Central payment tolerance behavior.

Do not use a custom tolerance parameter.

A tolerance match may only be proposed when the standard BC configuration supports the difference.

The actual posting must still use standard BC application logic and validation.

Suggested confidence:

High/Medium, lower than exact matching.

The confidence is informational only.

---

# 20. AI Candidate Classification – MVP

After deterministic reliable matches and before FIFO, classify unresolved situations for future AI handling.

No LLM is called in MVP.

Suggested enum values:

- `None`
- `Multiple Exact Matches`
- `Textual Reference`
- `Partial Match`
- `Unclassified Residual`

Purpose:

- Make future AI insertion easy.
- Measure the real volume of cases where AI may add value.
- Avoid redesigning tables/pages later.

Do not create a separate AI candidate table.

Do not persist every mathematical alternative.

The matching engine should simply classify the relevant unresolved movement/group before FIFO.

In Phase 2, this stage becomes:

Deterministic Matching  
→ AI Candidate Classification  
→ AI Workflow  
→ Validated Proposal Management Tool  
→ Residual FIFO

---

# 21. Future AI Integration

The proposal functionality must remain independent from the AI Agent module.

The future AI integration will create a dependency only to invoke the relevant workflow/capability.

The Agent framework must not own proposal persistence.

Future design:

1. Matching Engine identifies a classified AI candidate.
2. AI workflow receives a limited, curated set of movements/candidate alternatives.
3. LLM classifies or chooses a proposal.
4. Agent calls a dedicated tool such as:
   - `Create Ledger Application Proposal Group`
   - or equivalent.
5. That tool calls the same `Ledger Application Proposal Management` codeunit used by UI and deterministic matching.
6. Proposal Management performs all validations before creating lines.

The AI tool must never insert proposal lines directly without validation.

---

# 22. Matching Level 5 – Residual FIFO

FIFO is the final fallback.

Purpose:

Try to allocate all remaining compatible balances while clearly marking the proposal as low confidence.

FIFO is deterministic and does not imply that the application is semantically correct.

Rules:

- Same customer/vendor.
- Same currency.
- Opposite signs.
- Order by Posting Date.
- Entry No. as tie-breaker.
- Use oldest open counterpart first.
- Allow partial application.
- Continue consuming counterpart movements while balance remains available.
- Build executable 1:N groups.

FIFO must not require an exact zero-sum cluster before generating an application.

Example:

Open entries:

- FV001 +800
- FV002 +700
- FV003 +900
- Payment P001 -1,000
- Payment P002 -600

Possible FIFO groups:

Group 1:
- Level 1: P001 -1,000
- Level 2: FV001 800
- Level 2: FV002 200

Group 2:
- Level 1: P002 -600
- Level 2: FV002 500
- Level 2: FV003 100

Remaining:

- FV003 +800

Suggested FIFO confidence:

Low / configurable informational value such as 20–40%.

The UI must clearly distinguish these groups from reliable deterministic matches.

---

# 23. Match Method

Suggested values:

- Explicit Reference
- Exact 1:1
- Exact 1:N
- Payment Tolerance
- FIFO
- Manual
- AI Assisted (future)

Keep the enum small and functional.

Avoid creating one enum value for every minor technical variation.

---

# 24. Confidence

Confidence is informational.

It must not independently control posting.

The user may post any valid pending group regardless of confidence.

Recommended presentation:

- Very High
- High
- Medium
- Low
- Very Low

A numeric value may also be stored if useful, but avoid overcomplicating the model.

Manual modification should be clearly visible.

If a generated group is manually changed:

- `Manually Modified = true`
- Do not attempt to recalculate an artificial confidence.
- UI may show `Manual`, optionally preserving the original Match Method / Confidence for context.

---

# 25. Proposal Obsolescence

Obsolescence is independent from Status.

Use two source control markers in Proposal Header:

- `Source Last Ledger Entry No.`
- `Source Last Detailed Ledger Entry No.`

They must be calculated for the specific customer/vendor, not globally.

## Customer proposal

At creation:

- Find maximum `Cust. Ledger Entry`.`Entry No.` filtered by Customer No.
- Find maximum `Detailed Cust. Ledg. Entry`.`Entry No.` filtered by Customer No.

## Vendor proposal

Equivalent filters by Vendor No.

These two markers detect:

- New ledger entries for the same entity.
- Applications/unapplications or other detailed ledger activity affecting the same entity.

Movements belonging to another customer/vendor must not obsolete the proposal.

---

# 26. Obsolescence Refresh

## Proposal List OnOpenPage

When the Proposal List opens:

Check only proposals where:

- Obsolete = false
- Status IN:
  - Not Registered
  - Partially Registered

For each active proposal:

1. Recalculate the two current maximum Entry No. values for that entity.
2. Compare with the stored source markers.
3. If either changed:
   - Set Obsolete = true.

This check must remain lightweight.

Do not scan all proposal lines for every proposal during list opening.

Registered proposals do not require ongoing obsolescence validation.

---

# 27. Additional Validity Checks

Also call proposal validity check:

- When opening an individual active proposal.
- Before Add Movements.
- Before Remove Movement.
- Before Register Group.
- Before Register All.

The OnOpenPage validation is only a UX convenience, not the final concurrency guarantee.

---

# 28. Own Posting Must Not Obsolete the Proposal

Posting a group will naturally create/change detailed ledger activity for the same customer/vendor.

After successfully registering a group:

1. Verify the application completed successfully.
2. Recalculate:
   - Source Last Ledger Entry No.
   - Source Last Detailed Ledger Entry No.
3. Save these new values in Proposal Header.
4. Recalculate Header Status.

This distinguishes:

- Changes caused by the proposal itself → refresh control markers.
- External changes between actions → mark Obsolete.

No event subscribers are required for MVP.

---

# 29. Behavior When Proposal Becomes Obsolete

If `Obsolete = true`:

Disable:

- Register Group
- Register All
- Add Movements
- Remove Movement

Display a clear message explaining that the underlying ledger data changed and a new proposal must be generated.

Do not attempt automatic repair or regeneration.

A new proposal can be created from the current ledger state.

---

# 30. Proposal Deletion

A proposal may be deleted only if it has never registered any group.

Therefore:

Allowed:

- Not Registered, no registered groups.
- Obsolete, no registered groups.

Not allowed:

- Partially Registered.
- Registered.
- Obsolete proposal that already contains registered groups.

This preserves auditability of applications actually posted from the proposal.

---

# 31. Proposal List Page

Create:

`Ledger Application Proposal List`

Suggested columns:

- No.
- Entity Type
- Entity No.
- Entity Name
- Created At
- Created By
- Status
- Obsolete
- No. of Groups
- No. of Registered Groups

Suggested actions:

- Open
- Delete
- Create New Proposal where appropriate

The page acts as proposal history and active proposal management.

---

# 32. Proposal Detail Page

Recommended structure:

- `Ledger Application Proposal Card`
- `Ledger Application Proposal Lines` as a ListPart / tree-style page

A three-page solution is technically possible, but the Card + Lines layout provides a more standard Business Central UX without adding data-model complexity.

Suggested Header information:

- Proposal No.
- Customer/Vendor
- Status
- Obsolete
- Created At
- Created By
- Number of Groups
- Registered Groups
- Summary by confidence if easy to calculate

---

# 33. Tree View

Use hierarchical display.

Level 1:
- Applying Entry

Level 2:
- Applied Entries

Example:

`Payment P001 -1,000`
- `Invoice FV001 600`
- `Invoice FV002 400`

Suggested columns:

- Registration Status
- Document Type
- Document No.
- Posting Date
- Due Date
- Currency Code
- Remaining Amount
- Amount to Apply
- Match Method
- Confidence
- AI Candidate Type
- Manually Modified

The page should allow expand/collapse of groups.

---

# 34. Visual Registration Status

Tree UI must display:

- `Pending`
- `Registered`
- `Error`

Persistence should remain simple.

Recommended persisted model:

- `Registered` Boolean on Level 1.

Interpretation:

- Registered = true → `Registered`
- Registered = false → `Pending`

`Error` is primarily an execution-time visual result.

If registration fails:

- Show the BC error.
- Keep the group pending.
- Do not add unnecessary persisted error fields.
- If the error proves source data changed, set Proposal.Obsolete = true.

---

# 35. Add Movements

Action applies only to an unregistered, valid proposal/group.

Enable when:

- Proposal is not obsolete.
- Group is not registered.
- Level 1 still has unallocated available amount, or the selected group can validly accept additional counterpart movements.

Open a lookup/list filtered to eligible ledger entries:

- Same entity.
- Same currency as group.
- Open.
- Compatible sign.
- Not fully reserved by other pending groups.
- Available Amount > 0.

Allow multi-select.

For each selected movement:

- Calculate maximum available amount.
- Add a Level 2 line.
- Set Amount to Apply according to remaining group capacity and movement availability.
- Never over-allocate the Level 1 or Level 2 movement.
- Mark Level 1 `Manually Modified = true`.

All inserts must go through Proposal Management validation.

---

# 36. Remove Movement

Action applies to selected Level 2 line only.

Enable when:

- Proposal is not obsolete.
- Parent group is not registered.

Behavior:

1. Delete selected Level 2 proposal line.
2. Recalculate group available amount.
3. Mark Level 1 `Manually Modified = true`.
4. If no Level 2 lines remain:
   - Delete the Level 1 line as well.
   - Remove the group entirely.

Do not modify the actual Customer/Vendor Ledger Entry.

---

# 37. Register Group

The group is the posting transaction unit.

Before posting:

1. Check proposal validity / obsolescence.
2. Confirm group is not already registered.
3. Read current ledger entries.
4. Validate:
   - Open status.
   - Same entity.
   - Same currency.
   - Current available remaining amount >= proposed Amount to Apply.
   - No invalid BC application state.
5. Execute using standard Business Central application logic.
6. Verify result.
7. Mark Level 1 Registered = true.
8. Refresh source obsolescence markers.
9. Recalculate Header Status.

Do not require:

`Current Remaining Amount = Remaining Amount at Proposal`

because the same ledger entry may legitimately have been partially consumed by a previously registered group from the same proposal.

`Remaining Amount at Proposal` is a snapshot, not a concurrency condition.

---

# 38. Register All

Register pending groups in deterministic order:

- Group No. ascending.

For each group:

1. Recheck proposal validity.
2. If proposal becomes obsolete:
   - Stop processing immediately.
3. Attempt Register Group.
4. If registration succeeds:
   - Continue.
5. If a local/non-obsolescence error occurs:
   - Show/store execution result as appropriate.
   - Continue with next group.
6. If the error indicates underlying ledger data changed:
   - Set Obsolete = true.
   - Stop.

Registered groups must not be rolled back because a later independent group fails.

This behavior supports `Partially Registered`.

---

# 39. Header Status Recalculation

After proposal creation or group registration:

## Not Registered

Registered Groups = 0

## Partially Registered

Registered Groups > 0  
and  
Registered Groups < Total Groups

## Registered

Registered Groups = Total Groups

Do not introduce additional status values.

---

# 40. Main Code Responsibilities

Use separate codeunits/responsibilities.

Recommended:

## `Ledger Application Proposal Mgt.`

Responsibilities:

- Create Proposal Header.
- Create/delete/validate groups and lines.
- Check active proposal uniqueness.
- Calculate proposal-reserved amount.
- Calculate available amount.
- Add/remove movements.
- Validate proposal consistency.
- Mark previous proposal obsolete.
- Recalculate Header Status.
- Shared entry point for future AI tool.

## `Ledger Application Matching`

Responsibilities:

- Read eligible ledger entries.
- Run deterministic matching levels.
- Reserve amounts while matching.
- Normalize discovered matches into executable 1:N groups.
- Classify future AI candidates.
- Run residual FIFO.
- Use Proposal Mgt. to persist groups.

## `Ledger Application Posting`

Responsibilities:

- Validate current posting conditions.
- Map proposal group into standard BC application logic.
- Post Customer applications.
- Post Vendor applications.
- Verify successful application.
- Update source control markers.
- Mark group registered.

Customer and Vendor differences should remain encapsulated here as much as possible.

---

# 41. Shared Customer/Vendor Design

Do not duplicate the functional engine.

Shared logic:

- Matching.
- Group generation.
- Availability calculations.
- Proposal UI.
- Proposal validity.
- Manual edit behavior.
- Confidence.
- AI classification.
- FIFO.

Customer/Vendor-specific logic:

- Source ledger table access.
- Detailed ledger table access.
- Standard BC posting/apply calls.

Use Entity Type to route to the appropriate implementation.

---

# 42. Transaction and Validation Principles

The following rules are mandatory:

- Never over-allocate a ledger entry.
- Never mix currencies inside a group.
- Never mix customers/vendors inside a group.
- Never modify registered groups.
- Never post an obsolete proposal.
- Never trust stored Remaining Amount as current truth.
- Always re-read BC ledger state before posting.
- Always use standard Business Central application logic for actual registration.
- Matching confidence never overrides posting validation.

---

# 43. Performance Principles

Keep MVP simple.

Do not port the original Python algorithm literally.

Especially avoid:

- Generic unrestricted subset-sum.
- Large N:N combinatorial searches.
- Cross-customer/vendor text matching.
- Full proposal-line scans in Proposal List OnOpenPage.

Use:

- Small bounded exact combination searches.
- Entity + Currency partitioning.
- Deterministic ordered processing.
- Simple source markers for obsolescence.
- Standard BC filtered queries.

---

# 44. Testing Scenarios

Codex should include automated tests where feasible.

Minimum functional scenarios:

## Exact reference

- Payment explicitly references one invoice.
- Full application.
- Partial application.

## Exact 1:1

- One unique invoice/payment pair.
- Two invoices with same amount -> must not arbitrarily match.

## Exact 1:N

- One payment equals sum of two invoices.
- More than one exact combination -> classify as AI candidate, do not select exact combination automatically.

## Tolerance

- Difference allowed by BC payment tolerance.
- Difference not allowed by BC payment tolerance.

## FIFO

- One payment across multiple invoices.
- Multiple payments against one invoice.
- Partial remaining balance after FIFO.
- Same entity with multiple currencies -> separate groups by currency.

## Manual edit

- Add movement.
- Remove movement.
- Delete final Level 2 -> group disappears.
- Prevent over-allocation.
- Prevent adding different currency.

## Reuse across groups

- Same invoice appears in two groups with different partial amounts.
- Available amount is correctly reduced.

## Obsolescence

- New ledger entry for same entity -> obsolete.
- New detailed ledger entry/application for same entity -> obsolete.
- New entry for different entity -> proposal remains valid.
- Own successful group posting -> refresh source markers, proposal remains valid.
- Obsolete partially registered proposal -> cannot continue posting.

## Register Group

- Successful registration.
- Attempt to register already registered group.
- Remaining amount insufficient at posting time.

## Register All

- All groups successful.
- One local error, later groups continue.
- External change detected mid-process -> proposal becomes obsolete and execution stops.

## Proposal deletion

- Delete never-registered proposal.
- Delete obsolete never-registered proposal.
- Prevent deleting partially registered proposal.
- Prevent deleting obsolete proposal with registered groups.

---

# 45. Future Phase – AI Assisted Matching

Do not implement now, but preserve this integration contract.

Expected future flow:

1. Deterministic high-confidence matching.
2. Classify unresolved AI candidates.
3. For each candidate:
   - Build a small, curated context.
   - Invoke the Finance-related Agent Workflow.
4. LLM returns structured match recommendation.
5. Agent tool calls `Ledger Application Proposal Mgt.`.
6. Proposal Mgt. validates and persists groups.
7. Residual FIFO handles what AI did not resolve.

Likely AI use cases:

- Multiple exact combinations.
- Truncated or semantically similar references.
- Descriptions identifying documents indirectly.
- Partial payment relationships.
- Ambiguous residual balances.

AI must never:

- Post applications directly.
- Bypass proposal validation.
- Insert proposal lines without Proposal Mgt.
- Apply movements across entities/currencies in MVP rules.
- Override insufficient balances.

---

# 46. Future Phase – Job Queue

Not in MVP.

Design the proposal creation service so the same method can later be invoked from:

- Page action.
- Job Queue.
- Agent workflow.
- API.

Future Job Queue behavior may:

- Iterate customers/vendors.
- Generate proposals without posting.
- Skip entities with an existing active proposal or obsolete/replace according to future configuration.

Do not implement this automation now unless specifically requested later.

---

# 47. Design Decisions Considered Final for MVP

The following decisions should be treated as fixed unless implementation constraints prove otherwise:

1. Three new tables only.
2. Proposal independent from Agent Operation.
3. Shared Customer/Vendor proposal engine and UI.
4. One active proposal per entity.
5. Proposal may contain multiple currencies.
6. One currency per application group.
7. Level 1 = Applying Entry, not a fixed document type.
8. Exactly one Level 1 per group.
9. One or more Level 2 entries per group.
10. Same Ledger Entry may appear in multiple groups with partial amounts.
11. Generic N:N matches are normalized to executable 1:N groups.
12. Matching order:
    - Explicit Reference
    - Unique Exact 1:1
    - Unique Exact 1:N
    - Standard BC Payment Tolerance
    - AI Candidate Classification
    - Residual FIFO
13. No unrestricted combinatorial search.
14. No cross-customer/vendor application.
15. No cross-currency application.
16. Standard BC tolerance is the only tolerance source.
17. Status and Obsolete are separate concepts.
18. Header Status only:
    - Not Registered
    - Partially Registered
    - Registered
19. Obsolescence uses entity-filtered Ledger Entry / Detailed Ledger Entry source markers.
20. Proposal validity is rechecked before user-changing/posting actions.
21. Own group posting refreshes source markers.
22. Registered groups are immutable.
23. Only never-registered proposals may be deleted.
24. Registration is group-by-group.
25. Register All continues after local errors but stops on obsolescence.
26. Error persistence remains minimal.
27. AI is classified but not executed in MVP.
28. Future AI uses the same Proposal Management validation path.
29. FIFO intentionally produces low-confidence proposals for remaining compatible balances.
30. User decides whether to post low-confidence proposals.

---

# 48. Expected MVP User Experience

Typical flow:

1. User opens Customer Ledger Entries.
2. User selects any ledger entry for Customer C10000.
3. User clicks **Create Application Proposal**.
4. System analyzes all eligible open movements for C10000.
5. Proposal is generated using deterministic rules and residual FIFO.
6. Proposal detail opens.
7. User reviews a tree:
   - High-confidence exact groups.
   - Medium-confidence tolerance groups.
   - Low-confidence FIFO groups.
8. User may:
   - Remove proposed counterparts.
   - Add another compatible movement.
   - Register one group.
   - Register all groups.
9. Before every registration, BC ledger state is validated.
10. Successfully registered groups are marked as registered.
11. Partially completed proposals remain available.
12. External ledger changes mark the proposal obsolete.
13. Obsolete proposals cannot continue and must be replaced by a new proposal.
14. Proposal history remains accessible.

---

# 49. Implementation Guidance for Codex

Before coding:

1. Inspect the existing extension architecture and naming conventions.
2. Identify current object ranges and namespaces.
3. Identify existing shared customer/vendor abstraction patterns, if any.
4. Inspect standard BC application codeunits available in the project/runtime version.
5. Reuse standard application/posting logic rather than implementing ledger application posting manually.
6. Reuse standard payment tolerance configuration and processes.
7. Keep the matching engine testable independently from posting.
8. Keep Customer/Vendor-specific posting behind a narrow interface or internal branching layer.
9. Avoid adding additional tables/fields unless an implementation blocker requires them.
10. If a design decision in this specification cannot be implemented cleanly with the target BC runtime, document the issue before changing the functional model.

The priority is a small, maintainable MVP that produces understandable, editable, and safely executable application proposals.
