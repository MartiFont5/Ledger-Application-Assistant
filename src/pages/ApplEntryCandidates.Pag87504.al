/// <summary>
/// Multi-select lookup of the ledger entries that may still be added to an
/// application group. The page works on an in-memory list prepared by the
/// proposal management codeunit, so what it shows is exactly what can validly be
/// added: same entity, same currency, opposite sign and still available.
/// </summary>
page 87504 "LAA_ApplEntryCandidates"
{
    PageType = List;
    ApplicationArea = All;
    UsageCategory = None;
    SourceTable = "LAA_LedgerApplProposalLine";
    SourceTableTemporary = true;
    Caption = 'Ledger Entries to Add', Comment = 'ESP="Movimientos a anadir"';
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field("Document Type"; Rec."Document Type")
                {
                    ApplicationArea = All;
                }
                field("Document No."; Rec."Document No.")
                {
                    ApplicationArea = All;
                }
                field(Description; Rec.Description)
                {
                    ApplicationArea = All;
                }
                field("Posting Date"; Rec."Posting Date")
                {
                    ApplicationArea = All;
                }
                field("Due Date"; Rec."Due Date")
                {
                    ApplicationArea = All;
                }
                field("Currency Code"; Rec."Currency Code")
                {
                    ApplicationArea = All;
                }
                field("Remaining Amount at Proposal"; Rec."Remaining Amount at Proposal")
                {
                    ApplicationArea = All;
                    Caption = 'Remaining Amount', Comment = 'ESP="Importe pendiente"';
                    ToolTip = 'Specifies the current remaining amount of the ledger entry.', Comment = 'ESP="Especifica el importe pendiente actual del movimiento."';
                }
                field("Amount to Apply"; Rec."Amount to Apply")
                {
                    ApplicationArea = All;
                    Caption = 'Available Amount', Comment = 'ESP="Importe disponible"';
                    ToolTip = 'Specifies how much of the ledger entry is still free, that is its remaining amount less the amount already reserved by the other pending groups of this proposal.', Comment = 'ESP="Especifica cuanto queda libre del movimiento, es decir su importe pendiente menos el importe ya reservado por los demas grupos pendientes de esta propuesta."';
                }
                field("External Document No."; Rec."External Document No.")
                {
                    ApplicationArea = All;
                }
                field("Ledger Entry No."; Rec."Ledger Entry No.")
                {
                    ApplicationArea = All;
                }
            }
        }
    }

    var
        rTEMPSelectedEntry: Record "LAA_LedgerApplProposalLine" temporary;

    // The selection has to be read while the page is still running, because
    // CurrPage is no longer available once RunModal has returned to the caller.
    trigger OnQueryClosePage(CloseAction: Action): Boolean
    begin
        if CloseAction = Action::LookupOK then
            fCaptureSelection();

        exit(true);
    end;

    /// <summary>
    /// Loads the candidate list prepared by the caller.
    /// </summary>
    internal procedure fSetCandidates(var pTEMPCandidateEntry: Record "LAA_LedgerApplProposalLine" temporary)
    begin
        Rec.Reset();
        Rec.DeleteAll(false);

        pTEMPCandidateEntry.Reset();
        if pTEMPCandidateEntry.FindSet() then
            repeat
                Rec := pTEMPCandidateEntry;
                Rec.Insert(false);
            until pTEMPCandidateEntry.Next() = 0;

        if Rec.FindFirst() then;
    end;

    /// <summary>
    /// Returns the entries the user selected, supporting multi-select.
    /// </summary>
    internal procedure fGetSelection(var pTEMPSelectedEntry: Record "LAA_LedgerApplProposalLine" temporary)
    begin
        pTEMPSelectedEntry.Reset();
        pTEMPSelectedEntry.DeleteAll(false);

        rTEMPSelectedEntry.Reset();
        if rTEMPSelectedEntry.FindSet() then
            repeat
                pTEMPSelectedEntry := rTEMPSelectedEntry;
                pTEMPSelectedEntry.Insert(false);
            until rTEMPSelectedEntry.Next() = 0;
    end;

    local procedure fCaptureSelection()
    begin
        rTEMPSelectedEntry.Reset();
        rTEMPSelectedEntry.DeleteAll(false);

        CurrPage.SetSelectionFilter(Rec);
        if Rec.FindSet() then
            repeat
                rTEMPSelectedEntry := Rec;
                rTEMPSelectedEntry.Insert(false);
            until Rec.Next() = 0;

        Rec.Reset();
    end;
}
