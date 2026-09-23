/// <summary>
/// Orchestrates the registration of application groups. The group is the posting
/// transaction unit: each group is posted on its own so that a group that fails
/// never rolls back the groups that already succeeded, which is what makes the
/// Partially Registered status possible.
/// </summary>
codeunit 87502 "LAA_LedgerApplPosting"
{
    Access = Internal;

    var
        clProposalMgt: Codeunit "LAA_LedgerApplProposalMgt";
        TextObsoleteStoppedErr: Label 'The ledger entries of %1 changed while the proposal was being registered, so proposal %2 is now obsolete and the process stopped. %3 application groups were registered.', Comment = '%1 = entity number, %2 = proposal number, %3 = number of registered groups. ESP="Los movimientos de %1 cambiaron durante el registro, por lo que la propuesta %2 esta ahora obsoleta y el proceso se ha detenido. Se han registrado %3 grupos de liquidacion."';

    #region Register one group

    /// <summary>
    /// Registers a single application group and reports the Business Central error
    /// to the user when the application cannot be posted.
    /// </summary>
    internal procedure fRegisterGroup(var prApplyingLine: Record "LAA_LedgerApplProposalLine")
    var
        rlProposalHeader: Record "LAA_LedgerApplProposalHeader";
        clPostGroup: Codeunit "LAA_LedgerApplPostGroup";
        vlErrorText: Text;
        TextRegisteredMsg: Label 'Application group %1 was registered.', Comment = '%1 = group number. ESP="El grupo de liquidacion %1 se ha registrado."';
        TextObsoleteAfterErrorErr: Label 'The application could not be posted and the ledger entries of %1 have changed, so proposal %2 is now obsolete.\\%3', Comment = '%1 = entity number, %2 = proposal number, %3 = original error. ESP="No se ha podido registrar la liquidacion y los movimientos de %1 han cambiado, por lo que la propuesta %2 esta ahora obsoleta.\\%3"';
    begin
        prApplyingLine.TestField(Level, prApplyingLine.Level::"Applying Entry");
        rlProposalHeader.Get(prApplyingLine."Proposal No.");

        clProposalMgt.fTestProposalUsable(rlProposalHeader);
        clProposalMgt.fTestGroupOpen(prApplyingLine);

        // The group posts in its own transaction, so a failure leaves the ledger
        // and the proposal untouched and the error can be shown to the user.
        Commit();
        Clear(clPostGroup);

        if clPostGroup.Run(prApplyingLine) then begin
            Commit();
            if GuiAllowed() then
                Message(TextRegisteredMsg, prApplyingLine."Group No.");
            exit;
        end;

        vlErrorText := GetLastErrorText();

        if not clProposalMgt.fCheckProposalValidity(rlProposalHeader) then begin
            // The failure proved that the source data changed. The obsolescence is
            // committed first so that the error message does not roll it back.
            Commit();
            Error(TextObsoleteAfterErrorErr, rlProposalHeader."Entity No.", rlProposalHeader."No.", vlErrorText);
        end;

        Error(vlErrorText);
    end;

    #endregion

    #region Register all groups

    /// <summary>
    /// Registers every pending group in ascending group order. A local error does
    /// not stop the run, but an external change to the ledger entries of the
    /// entity does: continuing would post applications that were calculated on
    /// data that no longer exists.
    /// </summary>
    internal procedure fRegisterAll(var prProposalHeader: Record "LAA_LedgerApplProposalHeader")
    var
        vlGroupNoList: List of [Integer];
        vlGroupNo: Integer;
        vlFailedCount: Integer;
        vlRegisteredCount: Integer;
        vlStopped: Boolean;
        vlLastErrorText: Text;
        TextNothingToRegisterMsg: Label 'Proposal %1 has no pending application groups.', Comment = '%1 = proposal number. ESP="La propuesta %1 no tiene grupos de liquidacion pendientes."';
    begin
        clProposalMgt.fTestProposalUsable(prProposalHeader);

        fCollectPendingGroups(prProposalHeader, vlGroupNoList);
        if vlGroupNoList.Count() = 0 then begin
            if GuiAllowed() then
                Message(TextNothingToRegisterMsg, prProposalHeader."No.");
            exit;
        end;

        foreach vlGroupNo in vlGroupNoList do
            if not vlStopped then
                vlStopped := fRegisterPendingGroup(prProposalHeader, vlGroupNo, vlRegisteredCount, vlFailedCount, vlLastErrorText);

        if prProposalHeader.Get(prProposalHeader."No.") then;

        fReportResult(prProposalHeader, vlRegisteredCount, vlFailedCount, vlStopped, vlLastErrorText);
    end;

    /// <summary>
    /// Registers one pending group and returns true when the whole run must stop,
    /// which only happens when the proposal became obsolete.
    /// </summary>
    local procedure fRegisterPendingGroup(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pGroupNo: Integer; var pvRegisteredCount: Integer; var pvFailedCount: Integer; var pvLastErrorText: Text): Boolean
    var
        rlApplyingLine: Record "LAA_LedgerApplProposalLine";
        clPostGroup: Codeunit "LAA_LedgerApplPostGroup";
    begin
        if not clProposalMgt.fCheckProposalValidity(prProposalHeader) then begin
            Commit();
            exit(true);
        end;

        if not clProposalMgt.fFindApplyingLine(prProposalHeader."No.", pGroupNo, rlApplyingLine) then
            exit(false);

        if rlApplyingLine.Registered then
            exit(false);

        Commit();
        Clear(clPostGroup);

        if clPostGroup.Run(rlApplyingLine) then begin
            pvRegisteredCount += 1;
            // Registered groups are never rolled back because a later independent
            // group fails, which is what makes Partially Registered possible.
            Commit();
            exit(false);
        end;

        pvFailedCount += 1;
        pvLastErrorText := GetLastErrorText();

        // A local error lets the run continue; a proposal that became obsolete
        // stops it, because the later groups were calculated on data that changed.
        if clProposalMgt.fCheckProposalValidity(prProposalHeader) then
            exit(false);

        Commit();
        exit(true);
    end;

    local procedure fCollectPendingGroups(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; var pvGroupNoList: List of [Integer])
    var
        rlApplyingLine: Record "LAA_LedgerApplProposalLine";
    begin
        Clear(pvGroupNoList);

        rlApplyingLine.SetCurrentKey("Proposal No.", "Group No.", Level, "Line No.");
        rlApplyingLine.SetRange("Proposal No.", prProposalHeader."No.");
        rlApplyingLine.SetRange(Level, rlApplyingLine.Level::"Applying Entry");
        rlApplyingLine.SetRange(Registered, false);
        if rlApplyingLine.FindSet() then
            repeat
                pvGroupNoList.Add(rlApplyingLine."Group No.");
            until rlApplyingLine.Next() = 0;
    end;

    local procedure fReportResult(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pRegisteredCount: Integer; pFailedCount: Integer; pvStopped: Boolean; pErrorText: Text)
    var
        TextAllRegisteredMsg: Label '%1 application groups of proposal %2 were registered.', Comment = '%1 = number of registered groups, %2 = proposal number. ESP="Se han registrado %1 grupos de liquidacion de la propuesta %2."';
        TextPartialMsg: Label '%1 application groups were registered and %2 could not be registered.\\Last error:\%3', Comment = '%1 = number of registered groups, %2 = number of failed groups, %3 = last error. ESP="Se han registrado %1 grupos de liquidacion y %2 no han podido registrarse.\\Ultimo error:\%3"';
    begin
        // The obsolescence was committed before, so reporting it as an error does
        // not roll it back and the user cannot miss that the proposal is dead.
        if pvStopped then
            Error(TextObsoleteStoppedErr, prProposalHeader."Entity No.", prProposalHeader."No.", pRegisteredCount);

        if not GuiAllowed() then
            exit;

        if pFailedCount = 0 then begin
            Message(TextAllRegisteredMsg, pRegisteredCount, prProposalHeader."No.");
            exit;
        end;

        Message(TextPartialMsg, pRegisteredCount, pFailedCount, pErrorText);
    end;

    #endregion
}
