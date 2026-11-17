/// <summary>
/// Day-to-day access: generate, adjust and register application proposals,
/// without being able to change the setup of the assistant.
/// </summary>
permissionset 87501 "LAA_User"
{
    Caption = 'Ledger Application Assistant - User', Comment = 'ESP="Asistente de liquidacion de movimientos - Usuario"';
    Assignable = true;
    Access = Public;

    // The AI matching layer runs the Deloitte AI Integration framework in the
    // session of the user who generates the proposal, so it needs the permission
    // set that framework publishes for its consumers.
    IncludedPermissionSets = "AI Agents Framework";

    Permissions =
        tabledata "LAA_LedgerApplSetup" = R,
        tabledata "LAA_LedgerApplProposalHeader" = RIMD,
        tabledata "LAA_LedgerApplProposalLine" = RIMD,
        tabledata "Cust. Ledger Entry" = RM,
        tabledata "Vendor Ledger Entry" = RM,
        table "LAA_LedgerApplSetup" = X,
        table "LAA_LedgerApplProposalHeader" = X,
        table "LAA_LedgerApplProposalLine" = X,
        page "LAA_LedgerApplProposalList" = X,
        page "LAA_LedgerApplProposalLines" = X,
        page "LAA_ApplEntryCandidates" = X,
        codeunit "LAA_LedgerApplProposalMgt" = X,
        codeunit "LAA_LedgerApplMatching" = X,
        codeunit "LAA_LedgerApplPosting" = X,
        codeunit "LAA_LedgerApplPostGroup" = X,
        codeunit "LAA_LedgerApplEntityMgt" = X,
        codeunit "LAA_AIMatchMgt" = X,
        codeunit "LAA_AIMatchContext" = X,
        codeunit "LAA_AIMatchCapability" = X,
        codeunit "LAA_AIMatchTool" = X;
}
