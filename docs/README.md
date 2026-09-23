# 🧩 Ledger Application Assistant
### A Microsoft Dynamics 365 Business Central Extension

---

## How it works?

Applying open invoices, payments and credit memos by hand is slow and repetitive, and the person doing it has to hold the whole customer balance in their head.

The Ledger Application Assistant reads every open ledger entry of one customer or one vendor, works out which movements settle which, and presents the result as an **application proposal**: a reviewable list of application groups that the user can adjust before posting. Nothing is posted automatically, and each group is posted with the same standard Business Central application logic a user would trigger by hand.

It **adds** a way to prepare applications. It does not replace or change how Business Central applies entries.

---

## Process diagram

```
User opens Customer (or Vendor) Ledger Entries
and clicks "Create Application Proposal"
         │
         ▼
┌─────────────────────────────────────────────────────┐
│           STANDARD BC (unchanged)                   │
│  The open ledger entries of the customer/vendor,    │
│  exactly as Business Central maintains them         │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│             THE EXTENSION KICKS IN  ★               │
│                                                     │
│  1. Reads every eligible open entry of that         │
│     customer/vendor, per currency                   │
│  2. Matches them: explicit reference → exact 1:1    │
│     → exact 1:N → payment tolerance → AI (opt-in)   │
│     → FIFO                                          │
│  3. Builds application groups and shows them as a   │
│     tree with a confidence indicator                │
│  4. User reviews, adds or removes movements         │
│  5. User registers one group, or all of them        │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│           STANDARD BC (unchanged)                   │
│  The application is posted by standard Business     │
│  Central, including payment tolerance and rounding  │
└─────────────────────────────────────────────────────┘
```

> ★ = the extension &nbsp;&nbsp; Everything else is standard Business Central

---

## What the extension manages

| Feature | Description |
|---------|-------------|
| **Application proposal** | A reviewable set of proposed applications for one customer or one vendor, generated from the current open entries |
| **Application group** | The unit that gets posted: one movement that settles one or more opposite movements |
| **Deterministic matching** | Five ordered rules, from an explicit document reference down to a plain FIFO allocation |
| **Confidence** | Tells the user at a glance how reliable each proposed group is, from Very High to Very Low |
| **Manual adjustment** | Add or remove movements from any group that has not been registered yet |
| **Group-by-group posting** | Register one group or all pending groups; a group that fails does not undo the ones that worked |
| **Obsolescence control** | A proposal is automatically retired when the ledger entries it was built on change |
| **Proposal history** | Every proposal, registered or obsolete, stays available for consultation |
| **AI candidate flag** | Marks the situations a future AI phase could resolve, so their real volume can be measured today |

---

## What the extension does NOT change

- ✅ How Business Central applies ledger entries — the standard application process does the posting
- ✅ The standard **Apply Entries** action on customer and vendor ledger entries — still there, still works
- ✅ Payment tolerance — it stays in the standard General Ledger Setup and keeps working for everyone else
- ✅ Customer and vendor ledger entries — the proposal never edits a movement, it only proposes applications
- ✅ Posting, currencies, exchange rates, discounts and rounding — all standard
- ✅ Reports, statements and aging — output is identical

---

## Supported scenarios

| Scenario | Supported | Notes |
|----------|:---:|---|
| Customers | ✅ | Same engine and same pages as vendors |
| Vendors | ✅ | |
| One payment settling several invoices | ✅ | One group, several applied entries |
| One invoice settled by several payments | ✅ | Split into one group per payment |
| Partial applications | ✅ | A movement may appear in several groups with different amounts |
| Several currencies for the same customer | ✅ | One proposal, separate groups per currency |
| Payment tolerance differences | ✅ | Only when the standard configuration allows the difference |
| Applying across two currencies | — | Not allowed; each group is single-currency |
| Applying across two customers/vendors | — | Not allowed |
| Automatic posting without a user | — | Every registration is triggered by a person |
| AI-assisted matching | — | Prepared for, not active |

---

## Setup overview

Search for **Ledger Application Setup**.

```
Ledger Application Setup
│
├── General
│   └── Proposal Nos.                 → number series for new proposals
│                                       (created automatically on installation)
│
├── Matching
│   ├── Max. Match Date Difference    → how far apart two movements may be
│   │                                   when they are matched only by amount
│   └── Max. Combination Lines        → how many movements may form one
│                                       exact combination
│
├── Residual Allocation
│   ├── Enable Residual FIFO          → allocate what is left, oldest first
│   └── FIFO Default Confidence       → confidence shown on those groups
│
├── AI Matching
│   ├── Enable AI Matching            → let the AI agent try the ambiguous
│   │                                   cases before FIFO. Off by default
│   ├── AI Multiple Exact Confidence  → confidence for a case where several
│   │                                   candidates matched the amount
│   ├── AI Partial Confidence         → confidence for a partial balance
│   └── AI Textual Ref. Confidence    → confidence for a confirmed reference
│
└── Payment Tolerance (read-only)
    └── The standard General Ledger Setup values, shown for convenience,
        with an action to run the standard change process
```

### Key concepts

**Application group.** The unit of work and the unit of posting. Every group has exactly one *applying entry* — the movement that settles — and one or more *applied entries* — the movements being settled. The tree shows the applying entry first with its applied entries indented beneath it.

**Applying entry is a role, not a document type.** It is not always the payment. If a movement explicitly references another one, that movement applies the other. Otherwise the most recent movement takes the role, because a newer movement normally consumes a balance that already existed.

**Confidence is information, not permission.** It says how sure the matching was: a payment naming its invoice scores Very High, a plain FIFO allocation scores Low. The user can register any valid group regardless of confidence, and should look closely at the low ones.

**Obsolete is not the same as registered.** *Status* says how much of the proposal has been posted. *Obsolete* says the ledger entries changed after the proposal was built — someone posted a new invoice, or applied something by hand — so the proposal no longer describes reality and must be replaced. The proposal's own postings never make it obsolete.

**Availability.** A movement can take part in several groups, but the total proposed across the pending groups never exceeds what is actually left on it.

---

## The matching rules

They run in order. Once an amount is taken by a group, later rules no longer see it.

| # | Rule | What it looks for | Confidence |
|---|------|-------------------|------------|
| 1 | **Explicit Reference** | A movement that names another one through applies-to information, payment reference, external document number, or a document number written in its description | Very High |
| 2 | **Exact 1:1** | Two opposite movements with exactly the same amount, where neither side has a competing candidate | High |
| 3 | **Exact 1:N** | One movement whose amount is exactly the sum of a small, unique combination of opposite movements | High |
| 4 | **Payment Tolerance** | A pair whose difference standard Business Central is configured to accept | Medium |
| 5 | **AI Assisted** | Of the candidates rules 1-4 left ambiguous, the ones the documents themselves identify — references, document numbers, descriptions, dates. Off by default | High or Medium (configurable) |
| 6 | **Residual FIFO** | Whatever compatible balance is left, oldest counterpart first | Low (configurable) |

> When two different matches are equally valid — two invoices of the same amount, or two exact combinations — the deterministic rules deliberately propose **neither**. Choosing at random would be worse than leaving the case to a person. The movement is flagged as an AI candidate.
>
> That flag is what rule 5 acts on. The AI is given only the movement and the handful of candidates the engine had already shortlisted, and it is asked one question: which of them do the documents actually identify? Amounts fitting is not an answer — they all fit already. When nothing distinguishes them the AI proposes nothing, and the case falls to FIFO exactly as before. Everything it does propose is validated again in AL before a group exists, and the user still reviews and posts it.

---

## Registering a proposal

Select a proposal in the **Ledger Application Proposals** list and choose **Proposed Applications** to open its tree. Everything else happens on that page.

| Action | Where | What it does |
|--------|-------|--------------|
| **Post** | On a line in the tree | Validates the current ledger state and posts that one group |
| **Post All** | On the tree page | Posts every pending group, in group order |
| **Add Movements** | On a line in the tree | Adds more compatible movements to a pending group |
| **Remove Movement** | On an applied entry | Takes it out of the group; removing the last one removes the group |
| **Show Ledger Entry** | On a line in the tree | Opens the customer or vendor ledger entry behind the line |

> Before every one of these actions the proposal is revalidated against the live ledger. If something changed, the action is refused and the proposal is marked obsolete.

> **Post All** keeps going when an individual group fails — the ones that worked stay posted and the proposal becomes *Partially Registered*. It stops immediately if the ledger changed underneath it.

> An obsolete proposal announces itself with a notification when its tree is opened, and its Post, Post All, Add Movements and Remove Movement actions are switched off.

---

## Notes

**When the extension is not set up.** The setup record and the proposal number series are created automatically when the extension is installed, so proposals can be generated straight away. The setup only tunes the matching.

**Payment tolerance.** The values shown on the setup page belong to the standard General Ledger Setup and are used by the whole company. The *Change Payment Tolerance* action runs the standard Business Central process, which also recalculates the tolerance on open entries — it is not a setting private to this extension.

**Only one live proposal per customer or vendor.** Creating a new one for the same entity asks for confirmation and retires the previous one. Proposals that already posted something are kept for audit and can never be deleted.

**Obsolete proposals are not repaired.** They cannot be registered or changed, and there is no automatic fix: the reliable answer is to generate a new proposal from the current situation.

**Performance.** The engine works on one customer or vendor at a time, splits the work per currency, and caps its combination search deliberately. It aims at small, understandable, high-confidence matches rather than mathematical completeness.
