# AI-Assisted Ledger Application – Implementation Specification

## 1. Objective

Extend the existing deterministic Ledger Application Proposal solution with a small AI-assisted matching layer.

The deterministic engine already:
- Generates ledger application proposals.
- Resolves reliable deterministic matches.
- Classifies unresolved cases using `AI Candidate Type`.
- Falls back to FIFO for cases that cannot be reliably resolved.
- Creates the final proposal groups and proposal lines used by the user for review and posting.

The AI layer must not replace the deterministic engine.

Its only purpose in this phase is:

> Try to improve selected ambiguous cases before FIFO is executed.

If AI resolves the ambiguity:
- Create a normal application group.
- Set `Match Method = AI Assisted`.
- Preserve the original `AI Candidate Type`.

If AI does not resolve the ambiguity:
- Do nothing.
- Allow the existing FIFO logic to continue unchanged.

The implementation should be intentionally small and use the existing Agent Framework architecture.

---

## 2. Current Proposal Data Available

The existing Ledger Application Proposal lines already contain:
- Ledger Entry No.
- Document Type
- Document No.
- Description
- Posting Date
- Due Date
- Currency Code
- Amount to Apply
- Match Method
- Confidence
- AI Candidate Type

Existing `AI Candidate Type` values (`enum 87515 "LAA_AICandidateType"`):
- `Not Needed`
- `Multiple Exact Matches`
- `Textual Reference`
- `Partial Match`
- `Unclassified Residual`

Note the two corrections against earlier drafts of this document: the member is
`Multiple Exact Matches`, in the plural, and there is a fifth value,
`Textual Reference`, which the deterministic engine assigns when it found a
document reference inside a description but could not confirm it on its own.

No new tables are required.
No separate AI Case table is required.
No additional proposal pages are required.

Four fields are added to `LAA_LedgerApplSetup`, all of them configuration:
`Enable AI Matching` (off by default) and one confidence per candidate type in
scope.

---

## 3. Scope of AI Phase 1

AI is executed for:
- `Multiple Exact Matches`
- `Partial Match`
- `Textual Reference`

Explicitly excluded in Phase 1:
- `Not Needed`
- `Unclassified Residual`

The scope is decided in one place, `LAA_AIMatchMgt.fIsInScope`, so widening it in
Phase 2 is a one line change.

Behavior:

### Not Needed
Already resolved deterministically. No AI call.

### Multiple Exact Matches
The deterministic engine found multiple mathematically valid exact matches and could not decide which one is correct.

AI should attempt to select the most plausible counterpart(s) using semantic/business evidence.

### Textual Reference
The deterministic engine found a document reference inside a description or a
reference field, but the explicit reference level refused to act on it because it
was not unique or not conclusive.

This is the case with the strongest semantic evidence of the three, and without
AI it falls straight to FIFO. AI should confirm which candidate the reference
really points at, or reject it when the reference fits several candidates
equally.

### Partial Match
The deterministic engine identified a plausible but incomplete or ambiguous relationship that cannot be safely resolved deterministically.

In the implementation this is the entry whose balance an earlier level already
consumed in part and that still carries a residual.

AI should attempt to identify the correct counterpart(s) and proposed applied amounts.

### Unclassified Residual
Do not call AI in Phase 1.
Continue to the existing FIFO fallback.

---

## 4. Updated Matching Pipeline

Target flow:

```text
Pass 1, per currency
    Explicit Reference
        ↓
    Exact deterministic matches
        ↓
    Exact deterministic combinations
        ↓
    Standard BC tolerance logic
        ↓
    AI Candidate classification
    ↓
AI pass, per case
    If Multiple Exact Matches, Partial Match or Textual Reference:
        Commit
        Execute AI capability
        ↓
    If AI created a valid group:
        Mirror the reservations on the matching buffer
    Else:
        Leave movements unchanged
    ↓
Pass 2, per currency
    Existing FIFO logic
```

AI must run before FIFO creates fallback groups.

Do not create a FIFO group first and then attempt to replace it with AI.

Reason:
- FIFO may consume movements also used by other fallback groups.
- Replacing FIFO afterwards would require releasing/recalculating other groups.
- Running AI first lets existing FIFO remain unchanged as fallback.

---

## 5. Core Design Principle

The AI does not create proposal lines directly.

The AI only proposes a semantic relationship.

AL remains responsible for:
- Validating selected ledger entries.
- Validating entity.
- Validating currency.
- Validating signs.
- Validating open status.
- Validating remaining/available amounts.
- Preventing over-allocation.
- Calculating group and line numbers.
- Creating Level 1 and Level 2 proposal records.
- Setting Match Method.
- Setting system-defined Confidence.
- Preserving AI Candidate Type.

Principle:

```text
LLM proposes the relationship.
AL decides whether the relationship is valid.
Existing Proposal Management persists it.
```

---

## 6. Agent Framework Integration

The framework is the Deloitte **AI Integration** extension:

```json
{ "id": "a97d6237-e1cd-4234-99c4-a578251c3b40",
  "name": "AI Integration", "publisher": "Deloitte", "version": "28.0.3.11" }
```

Its concepts, and how this feature uses them:

| Framework concept | Used as |
|---|---|
| Agent (`enum 87151 "AI Agent"`, extensible) | One headless specialist agent, `LAA_LedgerApplicationAssistant` |
| Capability (`enum 87160 "AI Capability"`, extensible) | One capability, `LAA_AnalyzeLedgerApplMatch` |
| Tool implementation (`enum 87156 "AI Tool Implementation"`, extensible) | One tool, `LAA_ApplyAIMatch` |
| Workflow (`AI Workflow` + step + step capability) | One workflow, `LAA_AI_MATCH`, one step, not router selectable |
| Execution | One per AI case, started explicitly, run in the foreground |

Registration points actually published by the framework, on codeunit
`"AI Installation"` (87160):

- `OnInstallCapabilities` - capability master row, tool master row, prompt content, tool bindings
- `OnInstallAgents` - agent, persona, instructions, capability assignment

There is no installation event for workflows, so the three workflow rows are
written directly, idempotently, in the same shape the framework uses for its own
(`LAA_AIMatchAgent.fInstallWorkflow`).

> Earlier drafts of this document referred to `OnInstallTools`. That event does
> not exist. Tool master rows are installed from `OnInstallCapabilities` through
> `AI Prompt Helper.InstallTool`.

No dependency is taken on Agent Operation or on any generic operation
persistence: the capability stages nothing and requires no approval.

The Ledger Application Proposal module remains the functional owner of proposal data.

---

## 7. Capability

`Enum::"AI Capability"::LAA_AnalyzeLedgerApplMatch`, implemented by
`codeunit 87508 "LAA_AIMatchCapability"`, caption *Analyze Ledger Application
Match*.

It is registered exactly like a framework capability
(`CapabilityGenKnowledge.Codeunit.al` is the model followed):
`InsertCapability` → `InstallTool` → `ShouldOverwriteActiveVersion` →
`BeginTemplateInstallation` → sections and examples → `InsertCapabilityTool` →
`CompleteTemplateInstallation`. The Begin/Complete bracket is what preserves a
prompt an administrator has edited across an upgrade.

Two settings differ from the framework defaults, and both are deliberate:

- **Delegatable = false.** The capability never appears in the catalogue a chat
  agent can delegate to. The only way in is the matching engine.
- **Force Tool Calls = false.** *No match* has to cost nothing: the model simply
  answers one sentence and the execution completes. Nobody reads that answer, so
  no terminal tool is bound and the feature does not depend on the install order
  of the framework's own tools.

Temperature is pinned low (0.1): this is a judgement over supplied evidence, not
a piece of writing.

---

## 8. Capability Execution Granularity

Use:

> 1 AI candidate case = 1 capability execution.

Do not batch unrelated ambiguous cases in Phase 1.

Typical case:

```text
One applying movement
+
A small set of candidate movements
=
One AI execution
```

Benefits:
- Small context.
- Easier debugging.
- Easier evaluation.
- No need for the model to separate unrelated problems.
- One failure does not affect other cases.

Batching may be considered later only if real volume requires it.

---

## 9. AI Case Representation

No AI Case record is persisted. There is no AI case table, no AI result table and
no AI history table.

The case is a transient runtime structure held by
`codeunit 87507 "LAA_AIMatchContext"`, which is `SingleInstance`. It lives from
the moment the matching engine builds the case to the moment the tool is called
back, and it is cleared immediately afterwards - before and after every
execution, so a case can never leak into the next one.

It holds:

- Proposal No.
- AI Candidate Type
- Applying entry no.
- The applying entry and the allowed candidate entries, as verbatim copies of the
  matching buffer rows (`Record "LAA_LedgerApplProposalLine" temporary`, keyed
  `Get(0, <Ledger Entry No.>)` exactly like the buffer, so the available amount is
  still `Remaining Amount at Proposal - Amount to Apply`)
- After a successful tool call: the group number and the list of reservations the
  tool committed

Reusing the proposal line table as the in-memory carrier is the pattern the
matching engine and the Add Movements lookup already use, so the AI layer adds no
new shape to the codebase.

## 10. Applying Movement

For AI Phase 1, the deterministic engine remains responsible for choosing the Applying Entry / Level 1 movement.

AI must not choose or replace the Applying Entry.

The model only decides:

> Which candidate movements should be applied against the already selected Applying Entry?

If the current matching engine does not expose the applying movement clearly at the AI insertion point, Codex should refactor locally so the AI call receives an explicit applying movement.

Do not redesign the full matching architecture solely for this.

---

## 11. Candidate Movements

The AI input contains only movements relevant to the ambiguity, never all open
entries of the customer or vendor.

Candidate discovery is `LAA_LedgerApplMatching.fCollectAICandidates`, and it
applies the predicates the deterministic levels already apply:

- same entity and same currency (the buffer is built per entity, the case per currency)
- opposite sign
- something still available
- inside `Max. Match Date Difference`
- strictly older than the applying movement
- capped at `fMaxCombinationCandidates()` = 15

The chronology filter is what makes one ambiguous cluster produce **one** AI
case, built from its newest movement, instead of one case per movement of the
cluster. It is the same rule the rest of the engine applies: the most recent
movement takes the applying role.

For `Multiple Exact Matches` the set is narrowed once more to counterparts whose
amount matches exactly, because those are the ones the deterministic level could
not choose between.

### Why it does not simply call fCollectCombinationCandidates

That collector also demands a counterpart no larger than the applying movement.
That rule belongs to an exact combination search. A partial application is
precisely the case where a small residual is applied against a larger invoice, so
reusing the collector would hide exactly the candidates a `Partial Match` or a
`Textual Reference` case is about. `fCollectAICandidates` therefore shares every
other predicate but drops that one. It is not a second discovery engine: it reads
the same buffer, through the same helpers, inside the same candidate ceiling, and
can never widen the search beyond what the engine is already allowed to make.

### Multiple Exact Matches

Example:

```text
Applying:
Payment P001 -500

Candidates:
Invoice FV001 +500
Invoice FV002 +500
Invoice FV003 +500
```

### Partial Match

Example:

```text
Applying:
Payment P001 -1,000

Candidates:
Invoice FV001 +600
Invoice FV002 +500
Invoice FV003 +400
```

AI may propose:

```text
FV001 600
FV003 400
```

## 12. AI Input JSON

Built by `LAA_AIMatchMgt.fBuildCaseJson` and stored on the execution with
`AI Execution.SetUserInput`. The agent feeds it into the prompt from
`AppendInputExecutionContext`.

```json
{
  "candidateType": "Multiple Exact Matches",
  "applyingMovement": {
    "entryNo": 201,
    "documentType": "Payment",
    "documentNo": "P001",
    "description": "Payment April invoice 2024-102",
    "postingDate": "2026-05-03",
    "dueDate": "",
    "currencyCode": "EUR",
    "availableAmount": 500
  },
  "candidateMovements": [
    {
      "entryNo": 101,
      "documentType": "Invoice",
      "documentNo": "2024-101",
      "description": "Services March",
      "postingDate": "2026-03-31",
      "dueDate": "2026-04-30",
      "currencyCode": "EUR",
      "availableAmount": 500
    }
  ]
}
```

Rules that the shape encodes:

- `availableAmount` is a **positive magnitude**. The ledger owns the signs and the
  model never reasons about them. All candidates are on the opposite side of the
  applying movement by construction, and the prompt says so.
- Dates and document types are written with `Format(value, 0, 9)`, the invariant
  XML format, so the payload does not change with the session language.
- `externalDocumentNo`, `paymentReference` and `appliesToDocNo` are added **only
  when they carry something**. They are the same reference fields the
  deterministic engine scans in `fFindReferencedEntries`; an empty one is context
  the model does not need.
- Nothing else from the proposal line is sent. Match Method, Confidence, Group
  No., Level and Registered are internal state and would only invite the model to
  reason about them.

## 13. Prompt / Capability Instructions

The prompt lives in `LAA_AIMatchCapability.fInstallSections`, in four sections
plus three worked examples.

**System Rules — Scope and Boundary.** The absolute rules: the deterministic
engine already resolved everything it could; the candidates were preselected and
only they may be chosen; the applying movement is already decided and is never
chosen, replaced or applied to itself; every candidate already fits
arithmetically, so an exact amount match is **not** evidence; when nothing
singles out a candidate, do not call the tool; **nobody is watching this run**, so
never ask a question and never request human input; amounts are positive
magnitudes.

> The "never request human input" rule is not decoration. The framework
> auto-injects `RequestHumanInput` into every standalone work item, and a model
> that reached for it would park the execution as Human Needed on a run that has
> no human in it.

**Task Definition — Role.** What a case looks like, field by field.

**Policy Rules — How to Decide.** Evidence ranked, strongest first: an explicit
document reference; then a distinctive textual overlap; then dates, and only as a
tie breaker between candidates the first two already point at. Then what is
explicitly *never* evidence — the amount fitting, being the oldest or newest,
being the only invoice, the listing order, or a plausible story the model built
itself — followed by the specific reading of each candidate type.

**Output Specification — What to Return.** Exactly one of two outcomes: one call
to `lAA_ApplyAIMatch`, or one sentence of plain text and no call at all.

The core instruction, unchanged from the original draft:

> Only propose a ledger application when the provided document references, descriptions, dates, or other semantic evidence reasonably distinguish the selected candidate(s) from the alternatives. Do not select a candidate only because the amounts fit, because all supplied candidates may already be mathematically valid. If the evidence is insufficient, do not call the application tool.

## 14. Tool

`Enum::"AI Tool Implementation"::LAA_ApplyAIMatch`, implemented by
`codeunit 87510 "LAA_AIMatchTool"`.

The framework derives both identities from the enum member name, so they are
fixed by it:

- tool code: `LAA_APPLYAIMATCH`
- model facing function name: `lAA_ApplyAIMatch`

Renaming the enum member renames the tool for every installed company, so it does
not get renamed.

The tool expresses the business action. There is deliberately no
`Insert Proposal Line`, `Modify Proposal Line`, `Create Level 1` or
`Create Level 2`: the model does not know that a proposal line table exists.

`Max Calls` is 1 and the binding has `Triggers Completion = true`, so one
successful call ends the turn and the model cannot build a group incrementally.

## 15. Tool Input

The whole model facing contract:

```json
{
  "appliedEntries": [
    { "entryNo": 102, "amountToApply": 500 }
  ],
  "reason": "The payment description quotes document number 2024-102."
}
```

`amountToApply` is optional; omitted, the candidate's whole available amount is
applied. `reason` is required and is what forces the model to name its evidence
rather than pick silently.

Everything else comes from the execution context in `LAA_AIMatchContext`:
Proposal No., Entity Type, Entity No., currency, the Applying Entry, the AI
Candidate Type and the allowed candidate entries. None of them is a model
parameter, so none of them can be supplied incorrectly.

## 16. Amount to Apply

The model may provide `Amount to Apply`, especially for `Partial Match`.

Treat the value as a proposal only.

AL must:
- Recalculate current availability.
- Validate the amount.
- Prevent over-allocation.
- Reject amounts larger than available.
- Reject invalid zero/negative magnitudes according to the tool contract.

Prefer representing `Amount to Apply` as a positive magnitude.

AL already knows the sign of the real ledger entries.

---

## 17. Tool Validation

`LAA_AIMatchTool.CallTool` validates in this order, before writing anything:

| Check | How |
|---|---|
| A case is in progress | `LAA_AIMatchContext.fIsActive` |
| Proposal still exists | `Get(fGetProposalNo())` |
| This execution belongs to that case | the framework's `sourceRecordId` equals the proposal header's RecordId |
| Proposal is not obsolete | `clProposalMgt.fTestProposalUsable` |
| Arguments are readable, `appliedEntries` non-empty | JSON parse |
| No duplicate entry | `pvAppliedEntryNos.Contains` |
| Entry is in the candidate set, and is not the applying entry | `fIsAllowedCandidate` |
| Ledger entry still open, with something available | `clProposalMgt.fGetAvailableAmount`, which reads the **live** ledger |
| `amountToApply`, when supplied, is positive and within the entry | explicit check |
| Never more than the applying movement can absorb | running capacity, constrained (see below) |
| Same entity, same currency, compatible signs, no over-allocation, group capacity | enforced again by `fCreateGroup` / `fAddAppliedEntry` |

The case snapshot is only used to narrow the choice. What is actually available
**right now** is read from the live ledger through the existing
`fGetAvailableAmount`, so a movement another group consumed earlier in the same
run cannot be applied twice.

### Reject or constrain

The two are not the same and the tool treats them differently:

- A **contract violation** is rejected: an entry outside the candidate set, a
  duplicate, a negative magnitude, a closed entry, or more than the entry itself
  holds. The tool returns `{"applied": false, "reason": "..."}` as data, not as an
  error, so the model can read why.
- **Running out of room on the applying movement is arithmetic, not a
  violation**, so the amount is constrained instead, exactly as
  `fAllocationAmount` constrains every deterministic level. The result reports the
  amounts that were really applied.

After validation the tool calls the existing `fCreateGroup` and
`fAddAppliedEntry`. It never inserts a proposal line itself, so every invariant
of `LAA_LedgerApplProposalMgt` runs on an AI group exactly as on a manual one.

## 18. Allowed Candidate Validation

This was the one open technical question, and it is resolved without touching the
framework.

The `"AI Function"` contract is JSON only. The `ContextJson` the framework builds
(`AI Process Execution Tools.BuildToolContextJson`) carries framework identities
only - tool code, execution id, iteration, conversation, capability, agent, work
item, source record - and there is **no** hook for a subscriber payload. Adding
one would mean changing the framework.

Instead, the case reaches the tool through a `SingleInstance` codeunit, which
works because the tool runs in the same session and call stack as the execution:

```text
LAA_LedgerApplMatching.fAIMatching
    ↓  fSetCase(...)
LAA_AIMatchContext            (SingleInstance)
    ↓
LAA_AIMatchMgt.fRunCase → Commit → Codeunit.Run → CreateWorkflowExecution
    → RunExecutionInForeground → framework → tool dispatch
    ↓  reads the same instance
LAA_AIMatchTool.CallTool
```

Two settings make that inline dispatch true, and both are load bearing:

| Setting | Where | Why |
|---|---|---|
| `Direct Tool Execution = true` | on the agent, set in `LAA_AIMatchAgent.Install` | otherwise `DispatchToolForScope` sends the call to the self hosted tool web service, in **another session**, where the singleton is empty |
| `Scope = Agent` | on the tool, the default of `InstallTool` | otherwise, with multi environment on, the call is dispatched to the target environment |

The tool does not assume any of this silently. It checks that a case is active
and that the execution's `sourceRecordId` is the proposal header of that case,
and returns a plain rejection if either fails. A misconfiguration therefore
surfaces as "no AI match" plus a readable reason, never as a wrong application.

The allowed candidate set is then exact rather than a fallback: the tool accepts
an entry number only if the same entry is in the case, which is by construction
the same list the model was shown. The applying entry is excluded from it, so the
model cannot apply the applying movement to itself.

## 19. Successful AI Match

When the tool creates a group successfully:

Set:
- `Match Method = AI Assisted`
- `AI Candidate Type = original candidate type`

Do not overwrite `AI Candidate Type` with `Not Needed`.

Examples:

```text
Match Method = AI Assisted
AI Candidate Type = Multiple Exact Matches
Confidence = High
```

```text
Match Method = AI Assisted
AI Candidate Type = Textual Reference
Confidence = High
```

```text
Match Method = AI Assisted
AI Candidate Type = Partial Match
Confidence = Medium
```

---

## 20. Confidence

The LLM is never asked how confident it is. Confidence is system defined, read
from the setup by `LAA_AIMatchMgt.fGetConfidence`:

| AI Candidate Type | Setup field | Default |
|---|---|---|
| `Multiple Exact Matches` | `AI Multiple Exact Confidence` | `High` |
| `Textual Reference` | `AI Textual Ref. Confidence` | `High` |
| `Partial Match` | `AI Partial Confidence` | `Medium` |
| (FIFO) | `FIFO Default Confidence` | `Low` |

They are setup fields rather than constants because `FIFO Default Confidence`
already is one: the same administrator who tunes the FIFO confidence tunes these,
in the same place, after seeing how the first rollout behaves.

Confidence stays informational. As stated in the project rules, it must never
gate posting.

## 21. AI Failure / No Match

No special persistence is required.

If the model:
- Does not call the tool.
- Cannot distinguish candidates.
- Produces no valid proposal.
- Calls the tool with an invalid proposal that is rejected.

Then:
- Do not create an AI Assisted group.
- Leave involved amounts/movements available.
- Continue the existing matching flow.
- Existing FIFO logic remains the fallback.

Do not persist:
- AI error status.
- Retry counters.
- AI result state.

---

## 22. Tool Call Count

Target behavior:

```text
1 capability execution
→ 0 or 1 lAA_ApplyAIMatch tool call
```

The tool creates one application group for the current applying movement.

Do not design an iterative agent loop unless the existing framework requires it structurally.

Do not let the model incrementally construct the same group through repeated tool calls.

---

## 23. Integration Into Existing Matching Engine

The insertion point is `LAA_LedgerApplMatching.fGenerateProposal`, whose single
per-currency loop is **split into two passes** with the AI level between them:

```al
foreach vlCurrencyCode in vlCurrencyList do begin
    fMatchExplicitReference(prProposalHeader, vlCurrencyCode);
    fMatchExactPair(prProposalHeader, vlCurrencyCode);
    fMatchExactCombination(prProposalHeader, vlCurrencyCode);
    fMatchPaymentTolerance(prProposalHeader, vlCurrencyCode);
    fClassifyAICandidates(vlCurrencyCode);
end;

fAIMatching(prProposalHeader, vlCurrencyList);

if rSetup."Enable Residual FIFO" then
    foreach vlCurrencyCode in vlCurrencyList do
        fResidualFIFO(prProposalHeader, vlCurrencyCode);
```

### Why the loop is split

A call to a model is an HTTP callout and cannot be made with pending writes, and
`RunExecutionInForeground` commits on its own. The AI level therefore has to
commit, and it must commit **once, between the two passes**, never interleaved
with FIFO. Splitting the loop is behaviour preserving: every level filters by
currency and every reservation is per entry, so currencies never interact.

### Buffer synchronisation

The tool is the only writer of the group, but the residual FIFO reads the
in-memory buffer. `fApplyAIReservations` mirrors each committed amount onto the
buffer through the existing `fReserveAmount`. Without that step FIFO would
allocate the same amounts a second time; it is the one place where the two halves
of the design have to meet.

### Error isolation

`fRunCase` runs one case through `Codeunit.Run`. A framework that is not
configured, a model that is unreachable, a rejected tool call - none of them may
abort the generation of a proposal, and the deterministic result the user would
have obtained without AI is always produced.

Success is not taken from the model or from the tool: after the run, the group is
looked up in the proposal (`fGroupExists`). If anything rolled the tool call back,
the group is simply not there, the case counts as unresolved and the movements
stay available for FIFO.

## 24. Installation / Registration

`app.json` takes one new dependency, on AI Integration (see section 6). Building
locally also needs `Deloitte_INT-Interfaces` and
`Microsoft_Error Messages with Recommendations` symbols in `.alpackages`, because
AI Integration depends on them.

Registration follows the framework convention of putting it on the object it
registers:

- `LAA_AIMatchCapability` subscribes to `OnInstallCapabilities` and registers the
  capability, the tool master row, the prompt sections, the examples and the tool
  binding.
- `LAA_AIMatchAgent` subscribes to `OnInstallAgents` and registers the agent, its
  persona and instructions, the capability assignment, `Direct Tool Execution`,
  and the workflow rows.

But subscribing is not enough, and this is the one thing about the framework that
is easy to get wrong: **`OnInstallCapabilities` and `OnInstallAgents` are raised
only from `AI Installation.OnInstallAppPerCompany` and
`AI Upgrade.OnUpgradePerCompany`** - that is, only when the *framework itself* is
installed or upgraded. Neither fires when a dependent extension is installed, so
an extension that only subscribes is never registered at all.

`LAA_AIMatchMgt.fRegisterAIConfiguration` therefore calls the same two installers
directly, capability first (the agent assignment and the workflow rows have table
relations to it), and is invoked from three places:

- `LAA_LedgerApplInstall.OnInstallAppPerCompany` - a first install
- `LAA_LedgerApplUpgrade.OnUpgradePerCompany` - an upgrade of this extension,
  including the upgrade from 28.0.1.0 that introduces the feature
- **Register AI Assistant** on the setup page - a manual re-run, which is what a
  developer needs after force publishing, since that fires neither trigger

The subscribers stay as well, so the registration is also refreshed when the
framework is reinstalled or upgraded.

All of it is idempotent. An administrator's edits to the prompt survive, because
the installation is bracketed by `BeginTemplateInstallation` /
`CompleteTemplateInstallation`.

The new setup fields carry `InitValue`, and `fInitializeSetup` is already
idempotent, so the setup itself needs nothing beyond the existing behaviour.

Both permission sets include the framework's own `"AI Agents Framework"`
permission set, because the capability executes in the session of the user who
generates the proposal.

## 25. No New Functional Tables or Pages

This AI phase should not require:
- New proposal tables.
- AI Case tables.
- AI result tables.
- AI history tables.
- New functional pages.
- Proposal page redesign.

`LAA_MatchMethod` already carries `value(7; "AI Assisted")`, declared but until
now unused, so not even an enum value is added. The only schema growth is the
four configuration fields on `LAA_LedgerApplSetup`.

Avoid schema growth unless clearly required.

---

## 26. Expected Code Changes

Everything new lives in `src/ai/`. The rest of the extension is touched in four
places only.

### New objects (`src/ai/`)

| Object | ID | Role |
|---|---|---|
| `LAA_AIMatchMgt` | codeunit 87506 | Orchestrator. Availability, scope, confidence, case JSON, one isolated execution per case. `TableNo` so a case can run through `Codeunit.Run`. |
| `LAA_AIMatchContext` | codeunit 87507 | The transient AI case and the allowed candidate set. `SingleInstance`. |
| `LAA_AIMatchCapability` | codeunit 87508 | `implements "AI Interface Capability"`. Capability, prompt, tool binding. |
| `LAA_AIMatchAgent` | codeunit 87509 | `implements "AI Interface Agent"`. Agent, workflow, prompt input. |
| `LAA_AIMatchTool` | codeunit 87510 | `implements "AI Function"`. The `LAA_ApplyAIMatch` tool. |
| `LAA_AIAgentExt` | enumextension 87517 | `"AI Agent"` → `LAA_LedgerApplicationAssistant` (value 87500) |
| `LAA_AICapabilityExt` | enumextension 87518 | `"AI Capability"` → `LAA_AnalyzeLedgerApplMatch` (value 87500) |
| `LAA_AIToolImplExt` | enumextension 87519 | `"AI Tool Implementation"` → `LAA_ApplyAIMatch` (value 87500) |

The three framework facing codeunits are public because the framework
instantiates them through its interfaces. `LAA_AIMatchMgt` and
`LAA_AIMatchContext` keep `Access = Internal` like the rest of the extension.

### Changed objects

| File | Change |
|---|---|
| `app.json` | AI Integration dependency; version to 28.0.2.0 |
| `LAA_LedgerApplSetup` (table 87500) | fields 30-33: `Enable AI Matching` and three confidences |
| `LAA_LedgerApplSetup` (page 87500) | `group(AIMatching)`, the confidences `Enabled` by the toggle |
| `LAA_LedgerApplMatching` (codeunit 87501) | split loop, and the `Level 6 - AI assisted matching` region: `fAIMatching`, `fAIMatchingForCurrency`, `fBuildAICase`, `fCollectAICandidates`, `fIsAICandidateAmount`, `fAddCaseEntry`, `fApplyAIReservations` |
| `LAA_LedgerApplInstall` (codeunit 87505) | registers the AI configuration on install; `fRegisterAIConfiguration` shared with the upgrade and the page |
| `LAA_LedgerApplUpgrade` (codeunit 87511) | **new.** Registers the AI configuration on upgrade |
| `LAA_Admin`, `LAA_User` | the new codeunits, and `IncludedPermissionSets = "AI Agents Framework"` |

No change to `LAA_LedgerApplProposalMgt`: the AI tool calls `fCreateGroup` and
`fAddAppliedEntry` exactly as the deterministic levels do, and passes through
every invariant they already enforce.

No change to the AI Integration extension.

## 27. Technical Decisions

These required knowledge of the existing codebase. They are now decided.

| Question | Decision |
|---|---|
| App dependency id/version | `a97d6237-e1cd-4234-99c4-a578251c3b40`, Deloitte AI Integration 28.0.3.11 |
| Capability registration API | `AI Prompt Helper.InsertCapability` / `InsertSection` / `InsertExample` / `InsertCapabilityTool`, from `OnInstallCapabilities` |
| Which agent owns the capability | A new headless agent of its own. Reusing a chat agent would expose the capability to chat users and tie the feature to that agent's configuration |
| Object names and IDs | See section 26 |
| Install vs upgrade | One idempotent registration per object, re-run by the framework's `RefreshConfiguration` on upgrade |
| How a capability is executed | `AI Process Execution.CreateWorkflowExecution(workflowId, sourceRecordId)` → `SetUserInput(json)` → `RunExecutionInForeground` |
| How transient context reaches the tool | `SingleInstance` codeunit + `Direct Tool Execution` + `Scope = Agent`. See section 18 |
| Temporary data structure for candidates | `Record "LAA_LedgerApplProposalLine" temporary`, keyed like the matching buffer |
| Where the input JSON comes from | The matching buffer, copied into the case, serialised by `fBuildCaseJson` |
| Proposal Management procedure used | `fCreateGroup` + `fAddAppliedEntry`, the same pair the deterministic levels use |
| How success is detected | The group is looked up in the proposal after the run, not reported by the model or the tool |
| Enum extension approach | Three `enumextension` objects, values inside the 87500-87550 range |
| Error handling | One `Codeunit.Run` per case; a rejection is returned to the model as JSON data, a failure degrades to "no AI match" |
| Telemetry | None. The extension has no telemetry at all and the AI layer does not introduce the first. Measurement is the `AI Candidate Type` and `Match Method` columns already on the proposal lines, plus the framework's own execution pages |
| Test framework | None exists in this extension. Verification is the build plus the scenarios in section 28 |

### Not done, and why

- **No cap on the number of AI cases per proposal.** One ambiguous case is one
  execution, and a messy entity produces as many as it produces. If cost or
  duration turns out to matter in practice, the cap belongs next to
  `Enable AI Matching` in the setup.
- **No batching of unrelated cases.** See section 8.
- **No retry.** A case that fails is a case that FIFO handles, which is the
  behaviour the user already had.

## 28. Phase 1 Test Scenarios

### Feature off – regression guard

This is the first test to run, and the most important one.

Input:
- `Enable AI Matching = false` (the default), any entity that today produces FIFO groups.

Expected:
- The generated proposal is identical to the one produced before this change:
  same groups, same Match Methods, same Confidences.
- This is the guard on the split of the per-currency loop in `fGenerateProposal`.

### Textual Reference – AI resolves

Input:
- Payment P020 = 750, description "Pago fra. 2024-0117"
- Invoice 2024-0117 = 900
- Invoice 2024-0231 = 750
- The deterministic engine classified P020 as `Textual Reference` because the
  reference was not conclusive on its own.

Expected:
- AI selects 2024-0117 with `amountToApply` 750, not 2024-0231, even though
  2024-0231 is the one whose amount fits exactly.
- Match Method = AI Assisted, AI Candidate Type = Textual Reference,
  Confidence = High.

### Framework not configured

Input:
- `Enable AI Matching = true`, but no LLM endpoint key, or no Microsoft Entra
  application user on the agent or in AI Models Setup.

Expected:
- Proposal generation completes normally with FIFO groups.
- No error dialog reaches the user.
- This is the guard on the `Codeunit.Run` isolation in `fRunCase`.

### Multiple Exact Matches – AI resolves

Input:
- Payment P001 = 500
- Invoice FV001 = 500
- Invoice FV002 = 500
- Payment description clearly references FV002

Expected:
- AI receives P001 + FV001 + FV002.
- AI calls tool selecting FV002.
- Tool validates.
- Proposal group created.
- Match Method = AI Assisted.
- AI Candidate Type = Multiple Exact Matches.
- Confidence = High.
- FIFO does not reuse those amounts.

### Multiple Exact Matches – AI cannot resolve

Input:
- Payment P001 = 500
- FV001 = 500
- FV002 = 500
- No distinguishing semantic evidence.

Expected:
- AI does not call tool.
- No AI Assisted group created.
- Existing FIFO handles residual movements.
- Final Match Method remains FIFO.

### Partial Match – AI resolves

Input:
- Payment P001 = 1,000
- FV001 = 600
- FV002 = 500
- FV003 = 400
- Description/reference supports FV001 + FV003.

Expected:
- AI selects FV001 for 600 and FV003 for 400.
- Tool validates both.
- One AI Assisted group is created.
- Confidence = Medium.
- FIFO does not consume those amounts.

### Partial Match – insufficient evidence

Expected:
- No tool call.
- Existing FIFO fallback remains unchanged.

### Invalid tool entry

Model attempts to use an Entry No. outside the provided candidate set.

Expected:
- Tool rejects.
- No proposal lines created.
- FIFO remains available.

### Invalid currency

Selected entry has a different currency.

Expected:
- Tool rejects.

### Over-allocation

AI proposes more than the applying movement can still absorb.

Expected:
- The amounts are constrained to what is left, not rejected, exactly as the
  deterministic levels constrain theirs.
- The tool result reports the amounts that were really applied.
- AI proposes more than a candidate entry itself holds: rejected, because that is
  a contract violation rather than arithmetic.
- Never create an invalid proposal.

### Entry changed concurrently

Ledger entry is no longer open or amount changed before tool execution.

Expected:
- Tool validation prevents invalid group creation.
- Existing proposal obsolescence/current-state rules remain authoritative.

---

## 29. Evaluation Metrics for Initial Rollout

Do not build a new analytics subsystem.

If existing proposal data makes it easy, evaluate:
- Number of `Multiple Exact Matches` AI candidates.
- Number resolved as `AI Assisted`.
- Number falling back to FIFO.
- Number of `Partial Match` candidates.
- Number resolved as `AI Assisted`.
- Number of AI Assisted groups manually changed by users.
- Number of AI Assisted groups successfully posted.
- Number of tool validation failures.

These metrics will determine whether AI support for `Unclassified Residual` is worthwhile.

---

## 30. Future Phase 2

Not part of this implementation.

Potential scope:
- Send `Unclassified Residual` cases to AI.
- Larger semantic candidate windows.
- More open-ended matching based on descriptions/references.

Do not design this now beyond preserving `AI Candidate Type = Unclassified Residual`.

Existing FIFO remains fallback.

---

## 31. Final Design Summary

```text
Existing deterministic engine
        ↓
AI Candidate Type
        ↓
Multiple Exact Matches, Partial Match or Textual Reference?
        ↓ yes
Build compact JSON
        ↓
Execute capability once
        ↓
LLM decides whether evidence is sufficient
        ↓
0 or 1 ApplyAIMatch tool call
        ↓
AL validates
        ↓
Existing Proposal Management creates AI Assisted group
        ↓
If unresolved
        ↓
Existing FIFO
```

Responsibilities:

```text
Deterministic engine
→ Finds ambiguity and provides candidates.

LLM
→ Chooses the semantically most plausible candidate(s), or does nothing.

AI Tool
→ Validates the proposed relationship.

Proposal Management
→ Creates the actual application group.

FIFO
→ Remains the deterministic fallback.
```

The implementation should maximize reuse of the current deterministic solution and Agent Framework and avoid new persistence or architectural layers unless the existing codebase makes them necessary.
