/// <summary>
/// Review and posting page of one application proposal.
///
/// The page is a tree of application groups: the applying entry at the first
/// level and the entries it applies indented below it, so a proposal reads as
/// "this movement settles these movements". It is always opened filtered to a
/// single proposal, whose number is shown in the filter pane.
///
/// Every action rechecks the validity of the proposal first, because the check
/// performed when the page opens is only a convenience, not a concurrency
/// guarantee.
/// </summary>
page 87503 "LAA_LedgerApplProposalLines"
{
    PageType = List;
    ApplicationArea = All;
    UsageCategory = None;
    SourceTable = "LAA_LedgerApplProposalLine";
    Caption = 'Proposed Applications', Comment = 'ESP="Liquidaciones propuestas"';
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
                ShowAsTree = true;
                IndentationColumn = Rec.Indentation;
                TreeInitialState = ExpandAll;

                field(GroupNo; vGroupNoText)
                {
                    ApplicationArea = All;
                    Caption = 'Group No.', Comment = 'ESP="Nro. grupo"';
                    ToolTip = 'Specifies the application group that the line belongs to. Each group is registered as one single application.', Comment = 'ESP="Especifica el grupo de liquidacion al que pertenece la linea. Cada grupo se registra como una unica liquidacion."';
                    StyleExpr = vLineStyle;
                }
                field("Ledger Entry No."; Rec."Ledger Entry No.")
                {
                    ApplicationArea = All;
                    DrillDown = true;
                    Caption = 'Entry No.', Comment = 'ESP="Nº Mov."';
                    ToolTip = 'Specifies the customer or vendor ledger entry that the line proposes to apply. Choose the number to open that ledger entry.', Comment = 'ESP="Especifica el movimiento de cliente o proveedor que la linea propone liquidar. Elija el numero para abrir dicho movimiento."';

                    trigger OnDrillDown()
                    begin
                        fShowLedgerEntry();
                    end;
                }
                field("Document Type"; Rec."Document Type")
                {
                    ApplicationArea = All;
                }
                field("Document No."; Rec."Document No.")
                {
                    ApplicationArea = All;
                    StyleExpr = vLineStyle;
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
                }
                field("Amount to Apply"; Rec."Amount to Apply")
                {
                    ApplicationArea = All;
                    StyleExpr = vLineStyle;
                }
                field("Match Method"; Rec."Match Method")
                {
                    ApplicationArea = All;
                }
                field(Confidence; Rec.Confidence)
                {
                    ApplicationArea = All;
                    StyleExpr = vConfidenceStyle;
                }
                field("AI Candidate Type"; Rec."AI Candidate Type")
                {
                    ApplicationArea = All;
                    StyleExpr = vAICandidateStyle;
                }
                field("Manually Modified"; Rec."Manually Modified")
                {
                    ApplicationArea = All;
                }
                field(RegistrationStatus; vRegistrationStatus)
                {
                    ApplicationArea = All;
                    Caption = 'Registration Status', Comment = 'ESP="Estado de registro"';
                    ToolTip = 'Specifies whether the application group is still pending or has already been registered.', Comment = 'ESP="Especifica si el grupo de liquidacion sigue pendiente o ya se ha registrado."';
                    StyleExpr = vRegistrationStyle;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(LAA_PostGroup)
            {
                ApplicationArea = All;
                Caption = 'Post', Comment = 'ESP="Registrar"';
                ToolTip = 'Post the selected application group with the standard Business Central application logic. The current ledger state is validated first.', Comment = 'ESP="Registra el grupo de liquidacion seleccionado con la logica de liquidacion estandar de Business Central. Antes se valida el estado actual de los movimientos."';
                Image = PostApplication;
                Scope = Repeater;
                Enabled = vProposalUsable;

                trigger OnAction()
                var
                    rlApplyingLine: Record "LAA_LedgerApplProposalLine";
                    clPosting: Codeunit "LAA_LedgerApplPosting";
                begin
                    clProposalMgt.fGetApplyingLine(Rec."Proposal No.", Rec."Group No.", rlApplyingLine);
                    clPosting.fRegisterGroup(rlApplyingLine);
                    fRefreshPage();
                end;
            }
            action(LAA_PostAll)
            {
                ApplicationArea = All;
                Caption = 'Post All', Comment = 'ESP="Registrar todo"';
                ToolTip = 'Post every pending application group, in ascending group order. A group that fails does not stop the others, but an external change to the ledger entries does.', Comment = 'ESP="Registra todos los grupos de liquidacion pendientes, en orden ascendente de grupo. Un grupo que falla no detiene a los demas, pero un cambio externo en los movimientos si."';
                Image = PostBatch;
                Enabled = vProposalUsable;

                trigger OnAction()
                var
                    rlProposalHeader: Record "LAA_LedgerApplProposalHeader";
                    clPosting: Codeunit "LAA_LedgerApplPosting";
                begin
                    if not fGetProposalHeader(rlProposalHeader) then
                        exit;

                    clPosting.fRegisterAll(rlProposalHeader);
                    fRefreshPage();
                end;
            }
            action(LAA_AddMovements)
            {
                ApplicationArea = All;
                Caption = 'Add Movements', Comment = 'ESP="Anadir movimientos"';
                ToolTip = 'Add more ledger entries to the selected application group. Only entries of the same customer or vendor, in the same currency, with the opposite sign and with an available amount can be added.', Comment = 'ESP="Anade mas movimientos al grupo de liquidacion seleccionado. Solo pueden anadirse movimientos del mismo cliente o proveedor, en la misma divisa, de signo contrario y con importe disponible."';
                Image = Add;
                Scope = Repeater;
                Enabled = vProposalUsable;

                trigger OnAction()
                begin
                    fAddMovements();
                end;
            }
            action(LAA_RemoveMovement)
            {
                ApplicationArea = All;
                Caption = 'Remove Movement', Comment = 'ESP="Quitar movimiento"';
                ToolTip = 'Remove the selected applied entry from its application group. The ledger entry itself is not changed. Removing the last applied entry removes the whole group.', Comment = 'ESP="Quita el movimiento liquidado seleccionado de su grupo de liquidacion. El movimiento no se modifica. Al quitar el ultimo movimiento liquidado se elimina todo el grupo."';
                Image = Delete;
                Scope = Repeater;
                Enabled = vProposalUsable;

                trigger OnAction()
                begin
                    clProposalMgt.fRemoveMovement(Rec);
                    fRefreshPage();
                end;
            }
        }
        area(Navigation)
        {
            action(LAA_ShowLedgerEntries)
            {
                ApplicationArea = All;
                Caption = 'Show Ledger Entries', Comment = 'ESP="Ver movimientos"';
                ToolTip = 'Open all open ledger entries of the customer or vendor of the proposal.', Comment = 'ESP="Abre todos los movimientos abiertos del cliente o proveedor de la propuesta."';
                Image = Entries;

                trigger OnAction()
                begin
                    fShowOpenLedgerEntries();
                end;
            }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process', Comment = 'ESP="Proceso"';

                actionref(LAA_PostGroupRef; LAA_PostGroup)
                {
                }
                actionref(LAA_PostAllRef; LAA_PostAll)
                {
                }
                actionref(LAA_AddMovementsRef; LAA_AddMovements)
                {
                }
                actionref(LAA_RemoveMovementRef; LAA_RemoveMovement)
                {
                }
                actionref(LAA_ShowLedgerEntriesRef; LAA_ShowLedgerEntries)
                {
                }
            }
        }
    }

    var
        clProposalMgt: Codeunit "LAA_LedgerApplProposalMgt";
        vRegistrationStatus: Enum "LAA_RegistrationStatus";
        vProposalUsable: Boolean;
        vAICandidateStyle: Text;
        vConfidenceStyle: Text;
        vGroupNoText: Text;
        vLineStyle: Text;
        vRegistrationStyle: Text;

    trigger OnOpenPage()
    var
        rlProposalHeader: Record "LAA_LedgerApplProposalHeader";
    begin
        if fGetProposalHeader(rlProposalHeader) then
            if clProposalMgt.fCheckProposalValidity(rlProposalHeader) then;

        fUpdateProposalState();
        fShowObsoleteNotification();
    end;

    trigger OnAfterGetRecord()
    begin
        vGroupNoText := Format(Rec."Group No.");
        fSetRegistrationStatus();
        fSetStyles();
    end;

    trigger OnAfterGetCurrRecord()
    begin
        fUpdateProposalState();
    end;

    /// <summary>
    /// Resolves the proposal the page is showing, from the current line or, when
    /// the proposal has no lines at all, from the filter the page was opened with.
    /// </summary>
    local procedure fGetProposalHeader(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"): Boolean
    var
        vlProposalNo: Integer;
    begin
        vlProposalNo := Rec."Proposal No.";

        if (vlProposalNo = 0) and (Rec.GetFilter("Proposal No.") <> '') then
            vlProposalNo := Rec.GetRangeMin("Proposal No.");

        if vlProposalNo = 0 then
            exit(false);

        exit(prProposalHeader.Get(vlProposalNo));
    end;

    local procedure fUpdateProposalState()
    var
        rlProposalHeader: Record "LAA_LedgerApplProposalHeader";
    begin
        vProposalUsable := false;

        if not fGetProposalHeader(rlProposalHeader) then
            exit;

        vProposalUsable := not rlProposalHeader."Obsolete" and (rlProposalHeader.Status <> rlProposalHeader.Status::Registered);
    end;

    local procedure fShowObsoleteNotification()
    var
        rlProposalHeader: Record "LAA_LedgerApplProposalHeader";
        vlObsoleteNotification: Notification;
        TextObsoleteNotificationMsg: Label 'The ledger entries of %1 changed after proposal %2 was generated. It can no longer be posted or changed. Create a new proposal from the current ledger state.', Comment = '%1 = entity number, %2 = proposal number. ESP="Los movimientos de %1 cambiaron despues de generar la propuesta %2. Ya no puede registrarse ni modificarse. Cree una nueva propuesta a partir del estado actual."';
    begin
        if not fGetProposalHeader(rlProposalHeader) then
            exit;

        if not rlProposalHeader."Obsolete" then
            exit;

        vlObsoleteNotification.Message(StrSubstNo(TextObsoleteNotificationMsg, rlProposalHeader."Entity No.", rlProposalHeader."No."));
        vlObsoleteNotification.Scope(NotificationScope::LocalScope);
        vlObsoleteNotification.Send();
    end;

    local procedure fSetRegistrationStatus()
    var
        rlApplyingLine: Record "LAA_LedgerApplProposalLine";
    begin
        if Rec.Level = Rec.Level::"Applying Entry" then begin
            vRegistrationStatus := Rec.fRegistrationStatus();
            exit;
        end;

        // An applied entry shows the state of the group it belongs to.
        if clProposalMgt.fFindApplyingLine(Rec."Proposal No.", Rec."Group No.", rlApplyingLine) then
            vRegistrationStatus := rlApplyingLine.fRegistrationStatus()
        else
            vRegistrationStatus := vRegistrationStatus::Pending;
    end;

    local procedure fSetStyles()
    begin
        vRegistrationStyle := '';
        if vRegistrationStatus = vRegistrationStatus::Registered then
            vRegistrationStyle := 'Favorable';

        vLineStyle := '';
        if Rec.Level = Rec.Level::"Applying Entry" then
            vLineStyle := 'Strong';
        if Rec."Manually Modified" then
            vLineStyle := 'StrongAccent';

        case Rec.Confidence of
            Rec.Confidence::"Very High", Rec.Confidence::High:
                vConfidenceStyle := 'Favorable';
            Rec.Confidence::Medium:
                vConfidenceStyle := 'Ambiguous';
            Rec.Confidence::Low, Rec.Confidence::"Very Low":
                vConfidenceStyle := 'Attention';
            else
                vConfidenceStyle := '';
        end;

        // "Not Needed" is the normal outcome and stays discreet; a residual the
        // engine could not even classify is the one that asks for a review.
        case Rec."AI Candidate Type" of
            Rec."AI Candidate Type"::"Not Needed":
                vAICandidateStyle := 'Subordinate';
            Rec."AI Candidate Type"::"Unclassified Residual":
                vAICandidateStyle := 'Attention';
            else
                vAICandidateStyle := 'Strong';
        end;
    end;

    local procedure fAddMovements()
    var
        rlProposalHeader: Record "LAA_LedgerApplProposalHeader";
        rlTEMPCandidateEntry: Record "LAA_LedgerApplProposalLine" temporary;
        rlTEMPSelectedEntry: Record "LAA_LedgerApplProposalLine" temporary;
        glCandidatePage: Page "LAA_ApplEntryCandidates";
        vlAddedCount: Integer;
        TextNoCandidatesMsg: Label 'There is no ledger entry left that can be added to application group %1.', Comment = '%1 = group number. ESP="No queda ningun movimiento que pueda anadirse al grupo de liquidacion %1."';
        TextNothingAddedMsg: Label 'No movement was added to application group %1.', Comment = '%1 = group number. ESP="No se ha anadido ningun movimiento al grupo de liquidacion %1."';
    begin
        rlProposalHeader.Get(Rec."Proposal No.");
        clProposalMgt.fTestProposalUsable(rlProposalHeader);
        clProposalMgt.fCollectCandidatesForGroup(rlProposalHeader, Rec."Group No.", rlTEMPCandidateEntry);

        if rlTEMPCandidateEntry.IsEmpty() then begin
            Message(TextNoCandidatesMsg, Rec."Group No.");
            exit;
        end;

        glCandidatePage.fSetCandidates(rlTEMPCandidateEntry);
        glCandidatePage.LookupMode(true);
        if glCandidatePage.RunModal() <> Action::LookupOK then
            exit;

        glCandidatePage.fGetSelection(rlTEMPSelectedEntry);
        vlAddedCount := clProposalMgt.fAddMovements(rlProposalHeader, Rec."Group No.", rlTEMPSelectedEntry);

        if vlAddedCount = 0 then
            Message(TextNothingAddedMsg, Rec."Group No.");

        fRefreshPage();
    end;

    local procedure fShowLedgerEntry()
    var
        rlCustLedgEntry: Record "Cust. Ledger Entry";
        rlVendLedgEntry: Record "Vendor Ledger Entry";
    begin
        case Rec."Entity Type" of
            Rec."Entity Type"::Customer:
                if rlCustLedgEntry.Get(Rec."Ledger Entry No.") then begin
                    rlCustLedgEntry.SetRecFilter();
                    Page.Run(Page::"Customer Ledger Entries", rlCustLedgEntry);
                end;
            Rec."Entity Type"::Vendor:
                if rlVendLedgEntry.Get(Rec."Ledger Entry No.") then begin
                    rlVendLedgEntry.SetRecFilter();
                    Page.Run(Page::"Vendor Ledger Entries", rlVendLedgEntry);
                end;
        end;
    end;

    /// <summary>
    /// Opens the open ledger entries of the customer or vendor of the proposal,
    /// so the whole ledger situation can be reviewed next to the proposal.
    /// </summary>
    local procedure fShowOpenLedgerEntries()
    var
        rlProposalHeader: Record "LAA_LedgerApplProposalHeader";
        rlCustLedgEntry: Record "Cust. Ledger Entry";
        rlVendLedgEntry: Record "Vendor Ledger Entry";
    begin
        if not fGetProposalHeader(rlProposalHeader) then
            exit;

        case rlProposalHeader."Entity Type" of
            rlProposalHeader."Entity Type"::Customer:
                begin
                    rlCustLedgEntry.SetRange("Customer No.", rlProposalHeader."Entity No.");
                    rlCustLedgEntry.SetRange(Open, true);
                    Page.Run(Page::"Customer Ledger Entries", rlCustLedgEntry);
                end;
            rlProposalHeader."Entity Type"::Vendor:
                begin
                    rlVendLedgEntry.SetRange("Vendor No.", rlProposalHeader."Entity No.");
                    rlVendLedgEntry.SetRange(Open, true);
                    Page.Run(Page::"Vendor Ledger Entries", rlVendLedgEntry);
                end;
        end;
    end;

    local procedure fRefreshPage()
    begin
        fUpdateProposalState();
        CurrPage.Update(false);
    end;
}
