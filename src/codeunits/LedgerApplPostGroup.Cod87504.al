/// <summary>
/// Registers one application group. It is a separate codeunit with a table
/// trigger so that it can be invoked with Codeunit.Run: a failing group is then
/// rolled back on its own and the caller can continue with the next group
/// without losing the groups that were already registered.
///
/// This is the only place where the standard Business Central application
/// codeunits are called, and the only place with customer/vendor posting
/// branches.
///
/// The ledger entries are never written directly: the application marks are set
/// through the standard "Cust. Entry-Edit" / "Vend. Entry-Edit" codeunits, which
/// is exactly what the standard Apply Entries pages do. Validating fields on a
/// posted ledger entry and modifying it with its triggers would fire validation
/// and modify subscribers that the standard application flow never fires, so
/// other extensions could block an application that they allow when it is made
/// from the standard page.
/// </summary>
codeunit 87504 "LAA_LedgerApplPostGroup"
{
    TableNo = "LAA_LedgerApplProposalLine";
    Access = Internal;

    var
        clProposalMgt: Codeunit "LAA_LedgerApplProposalMgt";
        clEntityMgt: Codeunit "LAA_LedgerApplEntityMgt";
        TextApplicationFailedErr: Label 'Business Central did not apply application group %1 of proposal %2. The ledger entries were left unchanged.', Comment = '%1 = group number, %2 = proposal number. ESP="Business Central no ha liquidado el grupo %1 de la propuesta %2. Los movimientos no se han modificado."';

    trigger OnRun()
    begin
        fRegisterGroup(Rec);
    end;

    /// <summary>
    /// Validates the current ledger state and posts the group with the standard
    /// application logic. Everything runs in the transaction of the caller's
    /// Codeunit.Run, so a failure leaves neither the ledger nor the proposal
    /// half changed.
    /// </summary>
    local procedure fRegisterGroup(var prApplyingLine: Record "LAA_LedgerApplProposalLine")
    var
        rlProposalHeader: Record "LAA_LedgerApplProposalHeader";
    begin
        prApplyingLine.TestField(Level, prApplyingLine.Level::"Applying Entry");
        rlProposalHeader.Get(prApplyingLine."Proposal No.");

        clProposalMgt.fTestProposalUsable(rlProposalHeader);
        clProposalMgt.fTestGroupOpen(prApplyingLine);

        fValidateGroup(rlProposalHeader, prApplyingLine);

        case rlProposalHeader."Entity Type" of
            rlProposalHeader."Entity Type"::Customer:
                fApplyCustomerGroup(rlProposalHeader, prApplyingLine);
            rlProposalHeader."Entity Type"::Vendor:
                fApplyVendorGroup(rlProposalHeader, prApplyingLine);
        end;

        prApplyingLine.Registered := true;
        prApplyingLine.Modify(true);

        // The proposal itself caused new detailed ledger activity for this entity.
        // Refreshing the markers is what distinguishes our own posting from an
        // external change, so the proposal does not become obsolete.
        clProposalMgt.fRefreshSourceMarkers(rlProposalHeader);
        clProposalMgt.fRecalculateStatus(rlProposalHeader);
    end;

    #region Validation

    /// <summary>
    /// Re-reads every ledger entry of the group. Stored proposal amounts are a
    /// snapshot, never a concurrency condition: what matters is that each entry is
    /// still open and still has enough remaining amount right now.
    /// </summary>
    local procedure fValidateGroup(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; var prApplyingLine: Record "LAA_LedgerApplProposalLine")
    var
        rlAppliedLine: Record "LAA_LedgerApplProposalLine";
        TextNoAppliedEntriesErr: Label 'Application group %1 of proposal %2 has no applied entries and cannot be registered.', Comment = '%1 = group number, %2 = proposal number. ESP="El grupo de liquidacion %1 de la propuesta %2 no tiene movimientos liquidados y no puede registrarse."';
    begin
        fValidateEntry(prProposalHeader, prApplyingLine);

        fFilterAppliedLines(prApplyingLine, rlAppliedLine);
        if rlAppliedLine.IsEmpty() then
            Error(TextNoAppliedEntriesErr, prApplyingLine."Group No.", prApplyingLine."Proposal No.");

        rlAppliedLine.FindSet();
        repeat
            fValidateEntry(prProposalHeader, rlAppliedLine);
            fValidateCurrency(prApplyingLine, rlAppliedLine);
        until rlAppliedLine.Next() = 0;
    end;

    local procedure fValidateEntry(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; var prProposalLine: Record "LAA_LedgerApplProposalLine")
    var
        vlCurrencyCode: Code[10];
        vlEntityNo: Code[20];
        vlRemainingAmount: Decimal;
        vlOpen: Boolean;
        TextEntryMissingErr: Label 'Ledger entry %1 no longer exists.', Comment = '%1 = ledger entry number. ESP="El movimiento %1 ya no existe."';
        TextEntryClosedErr: Label 'Ledger entry %1 (%2 %3) is no longer open and cannot be applied.', Comment = '%1 = ledger entry number, %2 = document type, %3 = document number. ESP="El movimiento %1 (%2 %3) ya no esta abierto y no puede liquidarse."';
        TextEntityMismatchErr: Label 'Ledger entry %1 belongs to %2 and not to %3.', Comment = '%1 = ledger entry number, %2 = current entity, %3 = proposal entity. ESP="El movimiento %1 pertenece a %2 y no a %3."';
        TextInsufficientAmountErr: Label 'Ledger entry %1 (%2 %3) has only %4 left, so %5 can no longer be applied.', Comment = '%1 = ledger entry number, %2 = document type, %3 = document number, %4 = current remaining amount, %5 = proposed amount. ESP="El movimiento %1 (%2 %3) solo tiene %4 pendiente, por lo que ya no pueden liquidarse %5."';
    begin
        if not clEntityMgt.fGetCurrentEntryState(prProposalHeader."Entity Type", prProposalLine."Ledger Entry No.", vlEntityNo, vlCurrencyCode, vlRemainingAmount, vlOpen) then
            Error(TextEntryMissingErr, prProposalLine."Ledger Entry No.");

        if not vlOpen then
            Error(TextEntryClosedErr, prProposalLine."Ledger Entry No.", Format(prProposalLine."Document Type"), prProposalLine."Document No.");

        if vlEntityNo <> prProposalHeader."Entity No." then
            Error(TextEntityMismatchErr, prProposalLine."Ledger Entry No.", vlEntityNo, prProposalHeader."Entity No.");

        if not clProposalMgt.fSameSign(vlRemainingAmount, prProposalLine."Amount to Apply") or
           (Abs(prProposalLine."Amount to Apply") > Abs(vlRemainingAmount))
        then
            Error(TextInsufficientAmountErr, prProposalLine."Ledger Entry No.", Format(prProposalLine."Document Type"), prProposalLine."Document No.", vlRemainingAmount, prProposalLine."Amount to Apply");
    end;

    local procedure fValidateCurrency(var prApplyingLine: Record "LAA_LedgerApplProposalLine"; var prAppliedLine: Record "LAA_LedgerApplProposalLine")
    var
        TextCurrencyMismatchErr: Label 'Application group %1 mixes currency %2 and currency %3. Movements in different currencies cannot be applied to each other.', Comment = '%1 = group number, %2 = first currency, %3 = second currency. ESP="El grupo de liquidacion %1 mezcla las divisas %2 y %3. No pueden liquidarse movimientos en divisas distintas."';
    begin
        if prAppliedLine."Currency Code" <> prApplyingLine."Currency Code" then
            Error(TextCurrencyMismatchErr, prApplyingLine."Group No.", prApplyingLine."Currency Code", prAppliedLine."Currency Code");
    end;

    local procedure fFilterAppliedLines(var prApplyingLine: Record "LAA_LedgerApplProposalLine"; var prAppliedLine: Record "LAA_LedgerApplProposalLine")
    begin
        prAppliedLine.Reset();
        prAppliedLine.SetCurrentKey("Proposal No.", "Group No.", Level, "Line No.");
        prAppliedLine.SetRange("Proposal No.", prApplyingLine."Proposal No.");
        prAppliedLine.SetRange("Group No.", prApplyingLine."Group No.");
        prAppliedLine.SetRange(Level, prAppliedLine.Level::"Applied Entry");
    end;

    #endregion

    #region Customer application

    local procedure fApplyCustomerGroup(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; var prApplyingLine: Record "LAA_LedgerApplProposalLine")
    var
        rlTEMPApplyUnapplyParameters: Record "Apply Unapply Parameters";
        rlApplyingCustLedgEntry: Record "Cust. Ledger Entry";
        rlAppliedLine: Record "LAA_LedgerApplProposalLine";
        rlCustLedgEntry: Record "Cust. Ledger Entry";
        clCustEntryApplyPostedEntries: Codeunit "CustEntry-Apply Posted Entries";
        clCustEntryEdit: Codeunit "Cust. Entry-Edit";
        vlAppliesToID: Code[50];
        vlApplicationDate: Date;
        vlRemainingAmountBefore: Decimal;
    begin
        vlAppliesToID := fGetAppliesToID(prApplyingLine);

        rlApplyingCustLedgEntry.Get(prApplyingLine."Ledger Entry No.");
        rlApplyingCustLedgEntry.CalcFields("Remaining Amount");
        vlRemainingAmountBefore := rlApplyingCustLedgEntry."Remaining Amount";

        rlApplyingCustLedgEntry."Applying Entry" := true;
        rlApplyingCustLedgEntry."Applies-to ID" := vlAppliesToID;
        rlApplyingCustLedgEntry."Amount to Apply" := prApplyingLine."Amount to Apply";
        clCustEntryEdit.Run(rlApplyingCustLedgEntry);

        fFilterAppliedLines(prApplyingLine, rlAppliedLine);
        rlAppliedLine.FindSet();
        repeat
            rlCustLedgEntry.Get(rlAppliedLine."Ledger Entry No.");
            rlCustLedgEntry."Applying Entry" := false;
            rlCustLedgEntry."Applies-to ID" := vlAppliesToID;
            rlCustLedgEntry."Amount to Apply" := rlAppliedLine."Amount to Apply";
            clCustEntryEdit.Run(rlCustLedgEntry);
        until rlAppliedLine.Next() = 0;

        vlApplicationDate := clCustEntryApplyPostedEntries.GetApplicationDate(rlApplyingCustLedgEntry);
        if vlApplicationDate < rlApplyingCustLedgEntry."Posting Date" then
            vlApplicationDate := rlApplyingCustLedgEntry."Posting Date";

        rlTEMPApplyUnapplyParameters.CopyFromCustLedgEntry(rlApplyingCustLedgEntry);
        rlTEMPApplyUnapplyParameters."Posting Date" := vlApplicationDate;
        rlTEMPApplyUnapplyParameters."Document No." := rlApplyingCustLedgEntry."Document No.";

        // Standard Business Central performs the application, including payment
        // tolerance, rounding and all its own validations.
        if clCustEntryApplyPostedEntries.Apply(rlApplyingCustLedgEntry, rlTEMPApplyUnapplyParameters) then;

        fVerifyCustomerApplication(prApplyingLine, prProposalHeader, vlRemainingAmountBefore);
    end;

    local procedure fVerifyCustomerApplication(var prApplyingLine: Record "LAA_LedgerApplProposalLine"; var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pRemainingAmountBefore: Decimal)
    var
        rlCustLedgEntry: Record "Cust. Ledger Entry";
    begin
        rlCustLedgEntry.Get(prApplyingLine."Ledger Entry No.");
        rlCustLedgEntry.CalcFields("Remaining Amount");

        if rlCustLedgEntry."Remaining Amount" = pRemainingAmountBefore then
            Error(TextApplicationFailedErr, prApplyingLine."Group No.", prProposalHeader."No.");
    end;

    #endregion

    #region Vendor application

    local procedure fApplyVendorGroup(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; var prApplyingLine: Record "LAA_LedgerApplProposalLine")
    var
        rlTEMPApplyUnapplyParameters: Record "Apply Unapply Parameters";
        rlApplyingVendLedgEntry: Record "Vendor Ledger Entry";
        rlAppliedLine: Record "LAA_LedgerApplProposalLine";
        rlVendLedgEntry: Record "Vendor Ledger Entry";
        clVendEntryApplyPostedEntries: Codeunit "VendEntry-Apply Posted Entries";
        clVendEntryEdit: Codeunit "Vend. Entry-Edit";
        vlAppliesToID: Code[50];
        vlApplicationDate: Date;
        vlRemainingAmountBefore: Decimal;
    begin
        vlAppliesToID := fGetAppliesToID(prApplyingLine);

        rlApplyingVendLedgEntry.Get(prApplyingLine."Ledger Entry No.");
        rlApplyingVendLedgEntry.CalcFields("Remaining Amount");
        vlRemainingAmountBefore := rlApplyingVendLedgEntry."Remaining Amount";

        rlApplyingVendLedgEntry."Applying Entry" := true;
        rlApplyingVendLedgEntry."Applies-to ID" := vlAppliesToID;
        rlApplyingVendLedgEntry."Amount to Apply" := prApplyingLine."Amount to Apply";
        clVendEntryEdit.Run(rlApplyingVendLedgEntry);

        fFilterAppliedLines(prApplyingLine, rlAppliedLine);
        rlAppliedLine.FindSet();
        repeat
            rlVendLedgEntry.Get(rlAppliedLine."Ledger Entry No.");
            rlVendLedgEntry."Applying Entry" := false;
            rlVendLedgEntry."Applies-to ID" := vlAppliesToID;
            rlVendLedgEntry."Amount to Apply" := rlAppliedLine."Amount to Apply";
            clVendEntryEdit.Run(rlVendLedgEntry);
        until rlAppliedLine.Next() = 0;

        vlApplicationDate := clVendEntryApplyPostedEntries.GetApplicationDate(rlApplyingVendLedgEntry);
        if vlApplicationDate < rlApplyingVendLedgEntry."Posting Date" then
            vlApplicationDate := rlApplyingVendLedgEntry."Posting Date";

        rlTEMPApplyUnapplyParameters.CopyFromVendLedgEntry(rlApplyingVendLedgEntry);
        rlTEMPApplyUnapplyParameters."Posting Date" := vlApplicationDate;
        rlTEMPApplyUnapplyParameters."Document No." := rlApplyingVendLedgEntry."Document No.";

        if clVendEntryApplyPostedEntries.Apply(rlApplyingVendLedgEntry, rlTEMPApplyUnapplyParameters) then;

        fVerifyVendorApplication(prApplyingLine, prProposalHeader, vlRemainingAmountBefore);
    end;

    local procedure fVerifyVendorApplication(var prApplyingLine: Record "LAA_LedgerApplProposalLine"; var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pRemainingAmountBefore: Decimal)
    var
        rlVendLedgEntry: Record "Vendor Ledger Entry";
    begin
        rlVendLedgEntry.Get(prApplyingLine."Ledger Entry No.");
        rlVendLedgEntry.CalcFields("Remaining Amount");

        if rlVendLedgEntry."Remaining Amount" = pRemainingAmountBefore then
            Error(TextApplicationFailedErr, prApplyingLine."Group No.", prProposalHeader."No.");
    end;

    #endregion

    /// <summary>
    /// Application identifier of the group. It is unique per proposal and group,
    /// so an application never picks up entries that the user marked somewhere
    /// else with the standard apply pages.
    /// </summary>
    local procedure fGetAppliesToID(var prApplyingLine: Record "LAA_LedgerApplProposalLine"): Code[50]
    var
        TextAppliesToIDTok: Label 'LAA-%1-%2', Locked = true;
    begin
        exit(CopyStr(StrSubstNo(TextAppliesToIDTok, prApplyingLine."Proposal No.", prApplyingLine."Group No."), 1, 50));
    end;
}
