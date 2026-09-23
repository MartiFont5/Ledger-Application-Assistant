/// <summary>
/// Owner of the proposal model. Every creation, change or deletion of a proposal
/// header, application group or proposal line goes through this codeunit,
/// whatever the caller is: page actions, the deterministic matching engine, a
/// future job queue entry or the future AI tool.
///
/// Nothing else may insert proposal lines directly, because all the functional
/// invariants (one applying entry per group, one currency per group, one entity
/// per group, never over-allocate a ledger entry) are enforced here.
/// </summary>
codeunit 87500 "LAA_LedgerApplProposalMgt"
{
    Access = Internal;

    var
        clEntityMgt: Codeunit "LAA_LedgerApplEntityMgt";
        TextProposalObsoleteErr: Label 'Proposal %1 is obsolete because the ledger entries of %2 changed after it was generated. Create a new proposal from the current ledger state.', Comment = '%1 = proposal number, %2 = entity number. ESP="La propuesta %1 esta obsoleta porque los movimientos de %2 cambiaron despues de generarla. Cree una nueva propuesta a partir del estado actual."';
        TextGroupRegisteredErr: Label 'Application group %1 of proposal %2 has already been registered and can no longer be changed.', Comment = '%1 = group number, %2 = proposal number. ESP="El grupo de liquidacion %1 de la propuesta %2 ya se ha registrado y no puede modificarse."';
        TextGroupNotFoundErr: Label 'Application group %1 was not found in proposal %2.', Comment = '%1 = group number, %2 = proposal number. ESP="No se ha encontrado el grupo de liquidacion %1 en la propuesta %2."';

    #region Proposal creation

    /// <summary>
    /// Creates a proposal for the entity after asking the user what to do with an
    /// existing active proposal. This is the entry point of the page actions.
    /// </summary>
    internal procedure fCreateProposalWithConfirmation(pEntityType: Enum "LAA_EntityType"; pEntityNo: Code[20]): Integer
    var
        rlActiveProposal: Record "LAA_LedgerApplProposalHeader";
        vlReplaceActive: Boolean;
        TextReplaceActiveQst: Label 'Proposal %1 is still active for %2.\\If you continue, proposal %1 is marked as obsolete and a new proposal is generated from the current ledger entries.\\Do you want to continue?', Comment = '%1 = proposal number, %2 = entity number. ESP="La propuesta %1 sigue activa para %2.\\Si continua, la propuesta %1 se marcara como obsoleta y se generara una nueva propuesta a partir de los movimientos actuales.\\Desea continuar?"';
    begin
        clEntityMgt.fTestEntity(pEntityType, pEntityNo);

        // Checked before the confirmation: there is no point in asking the user to
        // replace an active proposal when nothing can be proposed anyway.
        if not clEntityMgt.fHasOpenEntries(pEntityType, pEntityNo) then begin
            fShowNothingToApply(pEntityType, pEntityNo, false);
            exit(0);
        end;

        if fFindActiveProposal(pEntityType, pEntityNo, rlActiveProposal) then begin
            if not GuiAllowed() then
                exit(0);
            if not Confirm(TextReplaceActiveQst, false, rlActiveProposal."No.", pEntityNo) then
                exit(0);
            vlReplaceActive := true;
        end;

        exit(fCreateProposal(pEntityType, pEntityNo, vlReplaceActive));
    end;

    /// <summary>
    /// Creates and generates a proposal without any user interaction, so the same
    /// service can later be invoked from a job queue, an API or an agent workflow.
    /// Returns 0 when there is nothing to apply, because an empty proposal is
    /// never stored.
    /// </summary>
    internal procedure fCreateProposal(pEntityType: Enum "LAA_EntityType"; pEntityNo: Code[20]; pvReplaceActiveProposal: Boolean): Integer
    var
        rlProposalHeader: Record "LAA_LedgerApplProposalHeader";
        rlActiveProposal: Record "LAA_LedgerApplProposalHeader";
        clMatching: Codeunit "LAA_LedgerApplMatching";
        vlActiveProposalReplaced: Boolean;
        TextActiveProposalExistsErr: Label 'Proposal %1 is still active for %2. Only one active proposal is allowed per customer or vendor.', Comment = '%1 = proposal number, %2 = entity number. ESP="La propuesta %1 sigue activa para %2. Solo se permite una propuesta activa por cliente o proveedor."';
    begin
        clEntityMgt.fTestEntity(pEntityType, pEntityNo);

        if not clEntityMgt.fHasOpenEntries(pEntityType, pEntityNo) then begin
            fShowNothingToApply(pEntityType, pEntityNo, false);
            exit(0);
        end;

        if fFindActiveProposal(pEntityType, pEntityNo, rlActiveProposal) then begin
            if not pvReplaceActiveProposal then
                Error(TextActiveProposalExistsErr, rlActiveProposal."No.", pEntityNo);
            fSetObsolete(rlActiveProposal);
            vlActiveProposalReplaced := true;
        end;

        fInsertProposalHeader(pEntityType, pEntityNo, rlProposalHeader);
        clMatching.fGenerateProposal(rlProposalHeader);

        // A proposal without a single application group cannot be reviewed,
        // completed or posted, so it is discarded instead of being left in the
        // list, and the proposal it was about to replace stays usable.
        rlProposalHeader.CalcFields("No. of Groups");
        if rlProposalHeader."No. of Groups" = 0 then begin
            rlProposalHeader.Delete(true);
            if vlActiveProposalReplaced then
                fClearObsolete(rlActiveProposal);
            fShowNothingToApply(pEntityType, pEntityNo, true);
            exit(0);
        end;

        fRecalculateStatus(rlProposalHeader);

        exit(rlProposalHeader."No.");
    end;

    /// <summary>
    /// Tells the user why no proposal was created. Nothing is shown when the
    /// creation runs without a user interface, because the callers already handle
    /// the returned proposal number 0.
    /// </summary>
    local procedure fShowNothingToApply(pEntityType: Enum "LAA_EntityType"; pEntityNo: Code[20]; pvHadOpenEntries: Boolean)
    var
        TextNoOpenEntriesMsg: Label 'There are no open ledger entries to apply for %1 %2, so no proposal has been created.', Comment = '%1 = entity type caption, %2 = entity number. ESP="No hay movimientos abiertos que liquidar para %1 %2, por lo que no se ha creado ninguna propuesta."';
        TextNoGroupsMsg: Label 'No application could be proposed for the open ledger entries of %1 %2, so no proposal has been created.', Comment = '%1 = entity type caption, %2 = entity number. ESP="No se ha podido proponer ninguna liquidacion para los movimientos abiertos de %1 %2, por lo que no se ha creado ninguna propuesta."';
    begin
        if not GuiAllowed() then
            exit;

        if pvHadOpenEntries then
            Message(TextNoGroupsMsg, Format(pEntityType), pEntityNo)
        else
            Message(TextNoOpenEntriesMsg, Format(pEntityType), pEntityNo);
    end;

    /// <summary>
    /// Inserts the proposal header and takes the two obsolescence source markers
    /// that describe the ledger state the proposal was built on.
    /// </summary>
    internal procedure fInsertProposalHeader(pEntityType: Enum "LAA_EntityType"; pEntityNo: Code[20]; var prProposalHeader: Record "LAA_LedgerApplProposalHeader")
    begin
        prProposalHeader.Init();
        prProposalHeader."No." := fGetNextProposalNo();
        prProposalHeader."Entity Type" := pEntityType;
        prProposalHeader."Entity No." := pEntityNo;
        prProposalHeader."Entity Name" := clEntityMgt.fGetEntityName(pEntityType, pEntityNo);
        prProposalHeader.Status := prProposalHeader.Status::"Not Registered";
        prProposalHeader."Obsolete" := false;
        prProposalHeader."Created At" := CurrentDateTime();
        prProposalHeader."Created By" := CopyStr(UserId(), 1, MaxStrLen(prProposalHeader."Created By"));
        prProposalHeader."Source Last Ledger Entry No." := clEntityMgt.fGetLastLedgerEntryNo(pEntityType, pEntityNo);
        prProposalHeader."Source Last Detailed Entry No." := clEntityMgt.fGetLastDetailedEntryNo(pEntityType, pEntityNo);
        prProposalHeader.Insert(true);
    end;

    /// <summary>
    /// An active proposal is one that is not obsolete and not fully registered.
    /// Registered proposals stay as history and never block a new proposal.
    /// </summary>
    internal procedure fFindActiveProposal(pEntityType: Enum "LAA_EntityType"; pEntityNo: Code[20]; var prProposalHeader: Record "LAA_LedgerApplProposalHeader"): Boolean
    begin
        prProposalHeader.Reset();
        prProposalHeader.SetCurrentKey("Entity Type", "Entity No.", "Obsolete", Status);
        prProposalHeader.SetRange("Entity Type", pEntityType);
        prProposalHeader.SetRange("Entity No.", pEntityNo);
        prProposalHeader.SetRange("Obsolete", false);
        prProposalHeader.SetFilter(Status, '<>%1', prProposalHeader.Status::Registered);

        exit(prProposalHeader.FindFirst());
    end;

    #endregion

    #region Obsolescence control

    /// <summary>
    /// Recalculates the two source markers and marks the proposal obsolete when
    /// the ledger entries of the entity changed after the proposal was generated
    /// or last refreshed. Returns true when the proposal can still be used.
    /// </summary>
    internal procedure fCheckProposalValidity(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"): Boolean
    var
        vlCurrentLastEntryNo: Integer;
        vlCurrentLastDetailedNo: Integer;
    begin
        if prProposalHeader."Obsolete" then
            exit(false);

        // A fully registered proposal is history: it no longer needs monitoring.
        if prProposalHeader.Status = prProposalHeader.Status::Registered then
            exit(true);

        vlCurrentLastEntryNo := clEntityMgt.fGetLastLedgerEntryNo(prProposalHeader."Entity Type", prProposalHeader."Entity No.");
        vlCurrentLastDetailedNo := clEntityMgt.fGetLastDetailedEntryNo(prProposalHeader."Entity Type", prProposalHeader."Entity No.");

        if (vlCurrentLastEntryNo <> prProposalHeader."Source Last Ledger Entry No.") or
           (vlCurrentLastDetailedNo <> prProposalHeader."Source Last Detailed Entry No.")
        then begin
            fSetObsolete(prProposalHeader);
            exit(false);
        end;

        exit(true);
    end;

    /// <summary>
    /// Validity guard called before every action that changes or posts a proposal.
    /// </summary>
    internal procedure fTestProposalUsable(var prProposalHeader: Record "LAA_LedgerApplProposalHeader")
    begin
        if not fCheckProposalValidity(prProposalHeader) then
            Error(TextProposalObsoleteErr, prProposalHeader."No.", prProposalHeader."Entity No.");
    end;

    internal procedure fSetObsolete(var prProposalHeader: Record "LAA_LedgerApplProposalHeader")
    begin
        if prProposalHeader."Obsolete" then
            exit;

        prProposalHeader."Obsolete" := true;
        prProposalHeader.Modify(true);
    end;

    /// <summary>
    /// Reverts the obsolescence of a proposal that was marked obsolete to make
    /// room for a replacement that was never stored, so the user keeps the
    /// proposal that was already there.
    /// </summary>
    internal procedure fClearObsolete(var prProposalHeader: Record "LAA_LedgerApplProposalHeader")
    begin
        if not prProposalHeader."Obsolete" then
            exit;

        prProposalHeader."Obsolete" := false;
        prProposalHeader.Modify(true);
    end;

    /// <summary>
    /// Stores the ledger state produced by the proposal itself, so that posting a
    /// group never makes the proposal obsolete. Only external changes do.
    /// </summary>
    internal procedure fRefreshSourceMarkers(var prProposalHeader: Record "LAA_LedgerApplProposalHeader")
    begin
        prProposalHeader."Source Last Ledger Entry No." := clEntityMgt.fGetLastLedgerEntryNo(prProposalHeader."Entity Type", prProposalHeader."Entity No.");
        prProposalHeader."Source Last Detailed Entry No." := clEntityMgt.fGetLastDetailedEntryNo(prProposalHeader."Entity Type", prProposalHeader."Entity No.");
        prProposalHeader.Modify(true);
    end;

    /// <summary>
    /// Lightweight obsolescence refresh used when the proposal list is opened.
    /// Only active proposals are checked and no proposal line is ever scanned.
    /// </summary>
    internal procedure fCheckActiveProposals()
    var
        rlProposalHeader: Record "LAA_LedgerApplProposalHeader";
        vlProposalNoList: List of [Integer];
        vlProposalNo: Integer;
    begin
        rlProposalHeader.SetCurrentKey("Entity Type", "Entity No.", "Obsolete", Status);
        rlProposalHeader.SetRange("Obsolete", false);
        rlProposalHeader.SetFilter(Status, '<>%1', rlProposalHeader.Status::Registered);
        if rlProposalHeader.FindSet() then
            repeat
                vlProposalNoList.Add(rlProposalHeader."No.");
            until rlProposalHeader.Next() = 0;

        // The numbers are collected first: marking a proposal obsolete changes a
        // field of the key that the loop above iterates on.
        foreach vlProposalNo in vlProposalNoList do
            if rlProposalHeader.Get(vlProposalNo) then
                if fCheckProposalValidity(rlProposalHeader) then;
    end;

    #endregion

    #region Group and line creation

    /// <summary>
    /// Creates a new application group from its applying entry and returns the
    /// group number. This is the only supported way of starting a group, for the
    /// matching engine today and for the AI tool tomorrow.
    /// </summary>
    internal procedure fCreateGroup(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; var pTEMPApplyingEntry: Record "LAA_LedgerApplProposalLine" temporary; pAmountToApply: Decimal; pMatchMethod: Enum "LAA_MatchMethod"; pConfidence: Enum "LAA_Confidence"; pAICandidateType: Enum "LAA_AICandidateType"): Integer
    var
        rlProposalLine: Record "LAA_LedgerApplProposalLine";
        vlGroupNo: Integer;
        TextAmountZeroErr: Label 'An application group cannot be created with a zero amount for ledger entry %1.', Comment = '%1 = ledger entry number. ESP="No puede crearse un grupo de liquidacion con importe cero para el movimiento %1."';
    begin
        if pAmountToApply = 0 then
            Error(TextAmountZeroErr, pTEMPApplyingEntry."Ledger Entry No.");

        fTestEntryAllocation(prProposalHeader, pTEMPApplyingEntry."Ledger Entry No.", pAmountToApply, 0);

        vlGroupNo := fGetNextGroupNo(prProposalHeader."No.");

        fInitLineFromEntry(prProposalHeader, rlProposalLine, pTEMPApplyingEntry);
        rlProposalLine."Group No." := vlGroupNo;
        rlProposalLine.Level := rlProposalLine.Level::"Applying Entry";
        rlProposalLine.Indentation := 0;
        rlProposalLine."Amount to Apply" := pAmountToApply;
        rlProposalLine."Match Method" := pMatchMethod;
        rlProposalLine.Confidence := pConfidence;
        rlProposalLine."AI Candidate Type" := pAICandidateType;
        rlProposalLine.Insert(true);

        exit(vlGroupNo);
    end;

    /// <summary>
    /// Adds one applied entry to an existing group after validating entity,
    /// currency, direction and available amount.
    /// </summary>
    internal procedure fAddAppliedEntry(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pGroupNo: Integer; var pTEMPAppliedEntry: Record "LAA_LedgerApplProposalLine" temporary; pAmountToApply: Decimal; pMatchMethod: Enum "LAA_MatchMethod"; pConfidence: Enum "LAA_Confidence"; pAICandidateType: Enum "LAA_AICandidateType")
    var
        rlApplyingLine: Record "LAA_LedgerApplProposalLine";
        rlProposalLine: Record "LAA_LedgerApplProposalLine";
        TextCurrencyErr: Label 'Ledger entry %1 uses currency %2 and cannot be added to application group %3, which uses currency %4. Movements in different currencies cannot be applied to each other.', Comment = '%1 = ledger entry number, %2 = currency of the entry, %3 = group number, %4 = currency of the group. ESP="El movimiento %1 utiliza la divisa %2 y no puede anadirse al grupo de liquidacion %3, que utiliza la divisa %4. No pueden liquidarse movimientos en divisas distintas."';
        TextDirectionErr: Label 'Ledger entry %1 has the same sign as the applying entry of application group %2. Only movements with opposite signs can be applied.', Comment = '%1 = ledger entry number, %2 = group number. ESP="El movimiento %1 tiene el mismo signo que el movimiento liquidador del grupo %2. Solo pueden liquidarse movimientos de signo contrario."';
        TextDuplicateErr: Label 'Ledger entry %1 is already part of application group %2.', Comment = '%1 = ledger entry number, %2 = group number. ESP="El movimiento %1 ya forma parte del grupo de liquidacion %2."';
        TextEntityErr: Label 'Ledger entry %1 does not belong to %2 and cannot be added to the proposal.', Comment = '%1 = ledger entry number, %2 = entity number. ESP="El movimiento %1 no pertenece a %2 y no puede anadirse a la propuesta."';
        TextAmountZeroErr: Label 'Ledger entry %1 cannot be added with a zero amount.', Comment = '%1 = ledger entry number. ESP="El movimiento %1 no puede anadirse con importe cero."';
    begin
        fGetApplyingLine(prProposalHeader."No.", pGroupNo, rlApplyingLine);
        fTestGroupOpen(rlApplyingLine);

        if pAmountToApply = 0 then
            Error(TextAmountZeroErr, pTEMPAppliedEntry."Ledger Entry No.");

        if pTEMPAppliedEntry."Entity No." <> prProposalHeader."Entity No." then
            Error(TextEntityErr, pTEMPAppliedEntry."Ledger Entry No.", prProposalHeader."Entity No.");

        if pTEMPAppliedEntry."Currency Code" <> rlApplyingLine."Currency Code" then
            Error(TextCurrencyErr, pTEMPAppliedEntry."Ledger Entry No.", pTEMPAppliedEntry."Currency Code", pGroupNo, rlApplyingLine."Currency Code");

        if fSameSign(pAmountToApply, rlApplyingLine."Amount to Apply") then
            Error(TextDirectionErr, pTEMPAppliedEntry."Ledger Entry No.", pGroupNo);

        if fEntryExistsInGroup(prProposalHeader."No.", pGroupNo, pTEMPAppliedEntry."Ledger Entry No.") then
            Error(TextDuplicateErr, pTEMPAppliedEntry."Ledger Entry No.", pGroupNo);

        fTestEntryAllocation(prProposalHeader, pTEMPAppliedEntry."Ledger Entry No.", pAmountToApply, 0);
        fTestGroupCapacity(prProposalHeader, pGroupNo, pTEMPAppliedEntry."Ledger Entry No.", pAmountToApply);

        fInitLineFromEntry(prProposalHeader, rlProposalLine, pTEMPAppliedEntry);
        rlProposalLine."Group No." := pGroupNo;
        rlProposalLine.Level := rlProposalLine.Level::"Applied Entry";
        rlProposalLine.Indentation := 1;
        rlProposalLine."Amount to Apply" := pAmountToApply;
        rlProposalLine."Match Method" := pMatchMethod;
        rlProposalLine.Confidence := pConfidence;
        rlProposalLine."AI Candidate Type" := pAICandidateType;
        rlProposalLine.Insert(true);
    end;

    local procedure fInitLineFromEntry(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; var prProposalLine: Record "LAA_LedgerApplProposalLine"; var pTEMPEntry: Record "LAA_LedgerApplProposalLine" temporary)
    begin
        prProposalLine.Init();
        prProposalLine.TransferFields(pTEMPEntry, false);
        prProposalLine."Proposal No." := prProposalHeader."No.";
        prProposalLine."Line No." := fGetNextLineNo(prProposalHeader."No.");
        prProposalLine."Entity Type" := prProposalHeader."Entity Type";
        prProposalLine."Entity No." := pTEMPEntry."Entity No.";
        prProposalLine."Manually Modified" := false;
        prProposalLine.Registered := false;
    end;

    #endregion

    #region Availability and allocation

    /// <summary>
    /// Amount of a ledger entry that is still free for this proposal: its current
    /// remaining amount less the amount already reserved by the pending groups of
    /// the same proposal. Registered groups are not counted as reserved because
    /// their application is already reflected in the ledger balance.
    /// </summary>
    internal procedure fGetAvailableAmount(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pLedgerEntryNo: Integer; pExcludeGroupNo: Integer): Decimal
    var
        vlEntityNo: Code[20];
        vlCurrencyCode: Code[10];
        vlRemainingAmount: Decimal;
        vlOpen: Boolean;
    begin
        if not clEntityMgt.fGetCurrentEntryState(prProposalHeader."Entity Type", pLedgerEntryNo, vlEntityNo, vlCurrencyCode, vlRemainingAmount, vlOpen) then
            exit(0);

        if not vlOpen then
            exit(0);

        exit(vlRemainingAmount - fGetReservedAmount(prProposalHeader."No.", pLedgerEntryNo, pExcludeGroupNo));
    end;

    /// <summary>
    /// Amount of a ledger entry already committed by the pending groups of the
    /// proposal.
    /// </summary>
    internal procedure fGetReservedAmount(pProposalNo: Integer; pLedgerEntryNo: Integer; pExcludeGroupNo: Integer): Decimal
    var
        rlProposalLine: Record "LAA_LedgerApplProposalLine";
        vlReservedAmount: Decimal;
    begin
        rlProposalLine.SetCurrentKey("Proposal No.", "Ledger Entry No.");
        rlProposalLine.SetRange("Proposal No.", pProposalNo);
        rlProposalLine.SetRange("Ledger Entry No.", pLedgerEntryNo);
        if rlProposalLine.FindSet() then
            repeat
                if (rlProposalLine."Group No." <> pExcludeGroupNo) and
                   not fIsGroupRegistered(pProposalNo, rlProposalLine."Group No.")
                then
                    vlReservedAmount += rlProposalLine."Amount to Apply";
            until rlProposalLine.Next() = 0;

        exit(vlReservedAmount);
    end;

    local procedure fTestEntryAllocation(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pLedgerEntryNo: Integer; pAmountToApply: Decimal; pExcludeGroupNo: Integer)
    var
        vlAvailableAmount: Decimal;
        TextOverAllocationErr: Label 'Only %1 of ledger entry %2 is still available in proposal %3, so %4 cannot be proposed.', Comment = '%1 = available amount, %2 = ledger entry number, %3 = proposal number, %4 = requested amount. ESP="Solo quedan %1 disponibles del movimiento %2 en la propuesta %3, por lo que no pueden proponerse %4."';
        TextEntryClosedErr: Label 'Ledger entry %1 is no longer open and cannot take part in an application proposal.', Comment = '%1 = ledger entry number. ESP="El movimiento %1 ya no esta abierto y no puede participar en una propuesta de liquidacion."';
    begin
        vlAvailableAmount := fGetAvailableAmount(prProposalHeader, pLedgerEntryNo, pExcludeGroupNo);

        if vlAvailableAmount = 0 then
            Error(TextEntryClosedErr, pLedgerEntryNo);

        if fSameSign(vlAvailableAmount, pAmountToApply) and (Abs(pAmountToApply) <= Abs(vlAvailableAmount)) then
            exit;

        Error(TextOverAllocationErr, Abs(vlAvailableAmount), pLedgerEntryNo, prProposalHeader."No.", Abs(pAmountToApply));
    end;

    /// <summary>
    /// Amount of the applying entry of a group that is not yet covered by its
    /// applied entries.
    /// </summary>
    internal procedure fGetGroupCapacity(pProposalNo: Integer; pGroupNo: Integer): Decimal
    var
        rlApplyingLine: Record "LAA_LedgerApplProposalLine";
    begin
        fGetApplyingLine(pProposalNo, pGroupNo, rlApplyingLine);
        exit(Abs(rlApplyingLine."Amount to Apply") - Abs(fGetGroupAppliedTotal(pProposalNo, pGroupNo)));
    end;

    internal procedure fGetGroupAppliedTotal(pProposalNo: Integer; pGroupNo: Integer): Decimal
    var
        rlProposalLine: Record "LAA_LedgerApplProposalLine";
        vlTotalAmount: Decimal;
    begin
        rlProposalLine.SetCurrentKey("Proposal No.", "Group No.", Level, "Line No.");
        rlProposalLine.SetRange("Proposal No.", pProposalNo);
        rlProposalLine.SetRange("Group No.", pGroupNo);
        rlProposalLine.SetRange(Level, rlProposalLine.Level::"Applied Entry");
        if rlProposalLine.FindSet() then
            repeat
                vlTotalAmount += rlProposalLine."Amount to Apply";
            until rlProposalLine.Next() = 0;

        exit(vlTotalAmount);
    end;

    local procedure fTestGroupCapacity(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pGroupNo: Integer; pLedgerEntryNo: Integer; pAmountToApply: Decimal)
    var
        vlCapacity: Decimal;
        TextGroupFullErr: Label 'The applying entry of application group %1 can still take %2, so ledger entry %3 cannot be added with %4.', Comment = '%1 = group number, %2 = remaining capacity, %3 = ledger entry number, %4 = requested amount. ESP="El movimiento liquidador del grupo %1 admite todavia %2, por lo que el movimiento %3 no puede anadirse con %4."';
    begin
        // The capacity is widened by the standard payment tolerance of the entry,
        // which is how Business Central itself closes an entry that is paid short.
        vlCapacity := fGetGroupCapacity(prProposalHeader."No.", pGroupNo) +
                      clEntityMgt.fGetMaxPaymentTolerance(prProposalHeader."Entity Type", pLedgerEntryNo);

        if Abs(pAmountToApply) > vlCapacity then
            Error(TextGroupFullErr, pGroupNo, vlCapacity, pLedgerEntryNo, Abs(pAmountToApply));
    end;

    #endregion

    #region Manual changes

    /// <summary>
    /// Collects the ledger entries that may still be added to an application group:
    /// same entity, same currency, opposite sign, open and not fully reserved by
    /// the other pending groups of the proposal.
    /// </summary>
    internal procedure fCollectCandidatesForGroup(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pGroupNo: Integer; var pTEMPCandidateEntry: Record "LAA_LedgerApplProposalLine" temporary)
    var
        rlApplyingLine: Record "LAA_LedgerApplProposalLine";
        rlTEMPOpenEntry: Record "LAA_LedgerApplProposalLine" temporary;
        vlAvailableAmount: Decimal;
    begin
        fGetApplyingLine(prProposalHeader."No.", pGroupNo, rlApplyingLine);

        pTEMPCandidateEntry.Reset();
        pTEMPCandidateEntry.DeleteAll(false);

        clEntityMgt.fCollectOpenEntries(prProposalHeader."Entity Type", prProposalHeader."Entity No.", rlTEMPOpenEntry);

        if rlTEMPOpenEntry.FindSet() then
            repeat
                vlAvailableAmount := fGetAvailableAmount(prProposalHeader, rlTEMPOpenEntry."Ledger Entry No.", 0);

                if (vlAvailableAmount <> 0) and
                   (rlTEMPOpenEntry."Currency Code" = rlApplyingLine."Currency Code") and
                   not fSameSign(vlAvailableAmount, rlApplyingLine."Amount to Apply") and
                   not fEntryExistsInGroup(prProposalHeader."No.", pGroupNo, rlTEMPOpenEntry."Ledger Entry No.")
                then begin
                    pTEMPCandidateEntry := rlTEMPOpenEntry;
                    pTEMPCandidateEntry."Amount to Apply" := vlAvailableAmount;
                    pTEMPCandidateEntry.Insert(false);
                end;
            until rlTEMPOpenEntry.Next() = 0;

        pTEMPCandidateEntry.Reset();
    end;

    /// <summary>
    /// Adds the selected movements to a pending group, never over-allocating the
    /// applying entry or the added entries, and flags the group as manually changed.
    /// </summary>
    internal procedure fAddMovements(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pGroupNo: Integer; var pTEMPSelectedEntry: Record "LAA_LedgerApplProposalLine" temporary): Integer
    var
        rlApplyingLine: Record "LAA_LedgerApplProposalLine";
        vlBlankConfidence: Enum "LAA_Confidence";
        vlManualMatchMethod: Enum "LAA_MatchMethod";
        vlAddedCount: Integer;
        vlAmountToApply: Decimal;
        vlAvailableAmount: Decimal;
        vlMaxAmount: Decimal;
    begin
        fTestProposalUsable(prProposalHeader);
        fGetApplyingLine(prProposalHeader."No.", pGroupNo, rlApplyingLine);
        fTestGroupOpen(rlApplyingLine);

        pTEMPSelectedEntry.Reset();
        if pTEMPSelectedEntry.FindSet() then
            repeat
                vlAvailableAmount := fGetAvailableAmount(prProposalHeader, pTEMPSelectedEntry."Ledger Entry No.", 0);
                vlMaxAmount := fGetGroupCapacity(prProposalHeader."No.", pGroupNo) +
                               clEntityMgt.fGetMaxPaymentTolerance(prProposalHeader."Entity Type", pTEMPSelectedEntry."Ledger Entry No.");

                if (vlAvailableAmount <> 0) and (vlMaxAmount > 0) then begin
                    vlAmountToApply := vlAvailableAmount;
                    if Abs(vlAmountToApply) > vlMaxAmount then
                        vlAmountToApply := fSignOf(vlAvailableAmount) * vlMaxAmount;

                    // A movement the user picked is Manual, and no artificial
                    // confidence is invented for it. The applying entry keeps its
                    // original match method as context and is flagged as changed.
                    fAddAppliedEntry(prProposalHeader, pGroupNo, pTEMPSelectedEntry, vlAmountToApply,
                                     vlManualMatchMethod::Manual, vlBlankConfidence, pTEMPSelectedEntry."AI Candidate Type");
                    vlAddedCount += 1;
                end;
            until pTEMPSelectedEntry.Next() = 0;

        if vlAddedCount > 0 then
            fMarkGroupManuallyModified(prProposalHeader."No.", pGroupNo);

        exit(vlAddedCount);
    end;

    /// <summary>
    /// Removes one applied entry from a pending group. The ledger entry itself is
    /// never touched. When the last applied entry is removed the whole group
    /// disappears, because a group without applied entries cannot be posted.
    /// </summary>
    internal procedure fRemoveMovement(var prProposalLine: Record "LAA_LedgerApplProposalLine")
    var
        rlProposalHeader: Record "LAA_LedgerApplProposalHeader";
        rlApplyingLine: Record "LAA_LedgerApplProposalLine";
        rlRemainingLine: Record "LAA_LedgerApplProposalLine";
        vlGroupNo: Integer;
        TextNotAppliedEntryErr: Label 'Only applied entries can be removed from an application group. Select one of the indented lines.', Comment = 'ESP="Solo pueden quitarse movimientos liquidados de un grupo de liquidacion. Seleccione una de las lineas sangradas."';
    begin
        if prProposalLine.Level <> prProposalLine.Level::"Applied Entry" then
            Error(TextNotAppliedEntryErr);

        rlProposalHeader.Get(prProposalLine."Proposal No.");
        fTestProposalUsable(rlProposalHeader);

        vlGroupNo := prProposalLine."Group No.";
        fGetApplyingLine(prProposalLine."Proposal No.", vlGroupNo, rlApplyingLine);
        fTestGroupOpen(rlApplyingLine);

        prProposalLine.Delete(true);

        rlRemainingLine.SetCurrentKey("Proposal No.", "Group No.", Level, "Line No.");
        rlRemainingLine.SetRange("Proposal No.", rlProposalHeader."No.");
        rlRemainingLine.SetRange("Group No.", vlGroupNo);
        rlRemainingLine.SetRange(Level, rlRemainingLine.Level::"Applied Entry");
        if rlRemainingLine.IsEmpty() then
            rlApplyingLine.Delete(true)
        else begin
            rlApplyingLine."Manually Modified" := true;
            rlApplyingLine.Modify(true);
        end;

        fRecalculateStatus(rlProposalHeader);
    end;

    local procedure fMarkGroupManuallyModified(pProposalNo: Integer; pGroupNo: Integer)
    var
        rlApplyingLine: Record "LAA_LedgerApplProposalLine";
    begin
        fGetApplyingLine(pProposalNo, pGroupNo, rlApplyingLine);
        rlApplyingLine."Manually Modified" := true;
        rlApplyingLine.Modify(true);
    end;

    #endregion

    #region Status and deletion

    /// <summary>
    /// Derives the header status from the registration state of its groups.
    /// </summary>
    internal procedure fRecalculateStatus(var prProposalHeader: Record "LAA_LedgerApplProposalHeader")
    var
        vlStatus: Enum "LAA_ProposalStatus";
    begin
        prProposalHeader.CalcFields("No. of Groups", "No. of Registered Groups");

        case true of
            prProposalHeader."No. of Registered Groups" = 0:
                vlStatus := vlStatus::"Not Registered";
            prProposalHeader."No. of Registered Groups" < prProposalHeader."No. of Groups":
                vlStatus := vlStatus::"Partially Registered";
            else
                vlStatus := vlStatus::Registered;
        end;

        if prProposalHeader.Status = vlStatus then
            exit;

        prProposalHeader.Status := vlStatus;
        prProposalHeader.Modify(true);
    end;

    /// <summary>
    /// Deletes a proposal that never registered a group, so that the audit trail
    /// of applications actually posted from a proposal is preserved.
    /// </summary>
    internal procedure fDeleteProposal(var prProposalHeader: Record "LAA_LedgerApplProposalHeader")
    var
        TextDeleteQst: Label 'Delete application proposal %1?', Comment = '%1 = proposal number. ESP="Desea eliminar la propuesta de liquidacion %1?"';
    begin
        if GuiAllowed() then
            if not Confirm(TextDeleteQst, false, prProposalHeader."No.") then
                exit;

        prProposalHeader.Delete(true);
    end;

    #endregion

    #region Helpers

    internal procedure fGetApplyingLine(pProposalNo: Integer; pGroupNo: Integer; var prApplyingLine: Record "LAA_LedgerApplProposalLine")
    begin
        if not fFindApplyingLine(pProposalNo, pGroupNo, prApplyingLine) then
            Error(TextGroupNotFoundErr, pGroupNo, pProposalNo);
    end;

    internal procedure fFindApplyingLine(pProposalNo: Integer; pGroupNo: Integer; var prApplyingLine: Record "LAA_LedgerApplProposalLine"): Boolean
    begin
        prApplyingLine.Reset();
        prApplyingLine.SetCurrentKey("Proposal No.", "Group No.", Level, "Line No.");
        prApplyingLine.SetRange("Proposal No.", pProposalNo);
        prApplyingLine.SetRange("Group No.", pGroupNo);
        prApplyingLine.SetRange(Level, prApplyingLine.Level::"Applying Entry");

        exit(prApplyingLine.FindFirst());
    end;

    internal procedure fIsGroupRegistered(pProposalNo: Integer; pGroupNo: Integer): Boolean
    var
        rlApplyingLine: Record "LAA_LedgerApplProposalLine";
    begin
        if not fFindApplyingLine(pProposalNo, pGroupNo, rlApplyingLine) then
            exit(false);

        exit(rlApplyingLine.Registered);
    end;

    internal procedure fTestGroupOpen(var prApplyingLine: Record "LAA_LedgerApplProposalLine")
    begin
        if prApplyingLine.Registered then
            Error(TextGroupRegisteredErr, prApplyingLine."Group No.", prApplyingLine."Proposal No.");
    end;

    local procedure fEntryExistsInGroup(pProposalNo: Integer; pGroupNo: Integer; pLedgerEntryNo: Integer): Boolean
    var
        rlProposalLine: Record "LAA_LedgerApplProposalLine";
    begin
        rlProposalLine.SetCurrentKey("Proposal No.", "Group No.", Level, "Line No.");
        rlProposalLine.SetRange("Proposal No.", pProposalNo);
        rlProposalLine.SetRange("Group No.", pGroupNo);
        rlProposalLine.SetRange("Ledger Entry No.", pLedgerEntryNo);

        exit(not rlProposalLine.IsEmpty());
    end;

    /// <summary>
    /// Proposals are numbered with a simple counter over the existing proposals,
    /// the same way group and line numbers are assigned. No number series is
    /// involved, so nothing has to be configured before the first proposal.
    /// </summary>
    internal procedure fGetNextProposalNo(): Integer
    var
        rlProposalHeader: Record "LAA_LedgerApplProposalHeader";
    begin
        rlProposalHeader.Reset();
        if rlProposalHeader.FindLast() then
            exit(rlProposalHeader."No." + 1);

        exit(1);
    end;

    internal procedure fGetNextGroupNo(pProposalNo: Integer): Integer
    var
        rlProposalLine: Record "LAA_LedgerApplProposalLine";
    begin
        rlProposalLine.SetCurrentKey("Proposal No.", "Group No.", Level, "Line No.");
        rlProposalLine.SetRange("Proposal No.", pProposalNo);
        if rlProposalLine.FindLast() then
            exit(rlProposalLine."Group No." + 1);

        exit(1);
    end;

    internal procedure fGetNextLineNo(pProposalNo: Integer): Integer
    var
        rlProposalLine: Record "LAA_LedgerApplProposalLine";
    begin
        rlProposalLine.SetRange("Proposal No.", pProposalNo);
        if rlProposalLine.FindLast() then
            exit(rlProposalLine."Line No." + 10000);

        exit(10000);
    end;

    internal procedure fSameSign(pAmount1: Decimal; pAmount2: Decimal): Boolean
    begin
        exit(((pAmount1 > 0) and (pAmount2 > 0)) or ((pAmount1 < 0) and (pAmount2 < 0)));
    end;

    internal procedure fSignOf(pAmount: Decimal): Integer
    begin
        if pAmount < 0 then
            exit(-1);

        exit(1);
    end;

    #endregion
}
