// ============================================================================
// DISABLED IN THE NO-AI VARIANT OF THIS EXTENSION.
//
// This object belongs to the AI matching layer and binds directly to the
// Deloitte "AI Integration" dependency, which this variant does not declare in
// app.json. The object is commented out rather than deleted: restore it by
// re-adding the dependency and removing the /* ... */ markers below.
// ============================================================================
/*
/// <summary>
/// The only tool the model is given: apply the candidate movements it selected
/// against the applying movement of the current AI case.
///
/// The model never sees a proposal line, a group number or a table. It sends
/// ledger entry numbers and, optionally, the magnitude it wants applied to each.
/// Everything else - proposal, entity, currency, applying entry, candidate type
/// and the set of entries it was allowed to choose from - comes from
/// LAA_AIMatchContext, so there is nothing else for the model to get wrong.
///
/// This codeunit is public on purpose: it is bound to a value of the framework
/// enum "AI Tool Implementation" and is instantiated by the framework through the
/// "AI Function" interface.
/// </summary>
codeunit 87510 "LAA_AIMatchTool" implements "AI Function"
{
    var
        clContext: Codeunit "LAA_AIMatchContext";
        clProposalMgt: Codeunit "LAA_LedgerApplProposalMgt";
        TextNoActiveCaseLbl: Label 'There is no ledger application case in progress, so no application can be created.', Comment = 'ESP="No hay ningun caso de liquidacion de movimientos en curso, por lo que no puede crearse ninguna liquidacion."';
        TextWrongCaseLbl: Label 'This execution does not belong to the ledger application case in progress.', Comment = 'ESP="Esta ejecucion no pertenece al caso de liquidacion de movimientos en curso."';
        TextProposalGoneLbl: Label 'Proposal %1 no longer exists.', Comment = '%1 = proposal number. ESP="La propuesta %1 ya no existe."';
        TextBadArgumentsLbl: Label 'The arguments could not be read as JSON.', Comment = 'ESP="No se han podido leer los argumentos como JSON."';
        TextNoEntriesLbl: Label 'appliedEntries is missing or empty. Select at least one candidate movement, or do not call this tool at all.', Comment = 'ESP="appliedEntries falta o esta vacio. Seleccione al menos un movimiento candidato, o no llame a esta herramienta."';
        TextNoEntryNoLbl: Label 'Every appliedEntries item must carry a numeric entryNo.', Comment = 'ESP="Cada elemento de appliedEntries debe llevar un entryNo numerico."';
        TextDuplicateEntryLbl: Label 'Ledger entry %1 was selected more than once.', Comment = '%1 = ledger entry number. ESP="El movimiento %1 se ha seleccionado mas de una vez."';
        TextNotCandidateLbl: Label 'Ledger entry %1 was not among the candidate movements of this case and cannot be applied.', Comment = '%1 = ledger entry number. ESP="El movimiento %1 no estaba entre los movimientos candidatos de este caso y no puede liquidarse."';
        TextNotAvailableLbl: Label 'Ledger entry %1 has no amount available any more.', Comment = '%1 = ledger entry number. ESP="El movimiento %1 ya no tiene importe disponible."';
        TextAmountTooLargeLbl: Label 'amountToApply %1 exceeds the %2 still available on ledger entry %3.', Comment = '%1 = requested amount, %2 = available amount, %3 = ledger entry number. ESP="El importe %1 supera los %2 todavia disponibles en el movimiento %3."';
        TextAmountNotPositiveLbl: Label 'amountToApply must be a positive magnitude; ledger entry %1 was sent with %2.', Comment = '%1 = ledger entry number, %2 = requested amount. ESP="amountToApply debe ser una magnitud positiva; el movimiento %1 se ha enviado con %2."';
        TextNoCapacityLbl: Label 'Applying entry %1 has nothing left to allocate, so none of the selected movements could be applied.', Comment = '%1 = ledger entry number. ESP="El movimiento liquidador %1 no tiene nada pendiente de asignar, por lo que no se ha podido liquidar ninguno de los movimientos seleccionados."';
        TextAppliedLbl: Label 'Application group %1 created with match method AI Assisted.', Comment = '%1 = group number. ESP="Grupo de liquidacion %1 creado con metodo de conciliacion Asistido por IA."';

    /// <summary>
    /// Validates the relationship the model proposed and, only if it survives
    /// every check, creates the application group through the proposal owner.
    /// A rejection is returned as data, not as an error, so the model can read
    /// the reason and either correct itself or give up within the same execution.
    /// </summary>
    procedure CallTool(ArgumentsJson: Text; ContextJson: Text; var ResultText: Text; var Success: Boolean)
    var
        rlProposalHeader: Record "LAA_LedgerApplProposalHeader";
        vlAppliedAmounts: List of [Decimal];
        vlAppliedEntryNos: List of [Integer];
        vlGroupNo: Integer;
        vlReason: Text;
    begin
        Success := false;

        if not clContext.fIsActive() then begin
            ResultText := fBuildRejected(TextNoActiveCaseLbl);
            exit;
        end;

        if not rlProposalHeader.Get(clContext.fGetProposalNo()) then begin
            ResultText := fBuildRejected(StrSubstNo(TextProposalGoneLbl, clContext.fGetProposalNo()));
            exit;
        end;

        if not fBelongsToCurrentCase(ContextJson, rlProposalHeader) then begin
            ResultText := fBuildRejected(TextWrongCaseLbl);
            exit;
        end;

        // The proposal must still describe the current ledger state. This is the
        // same guard every manual change goes through, and it errors on purpose:
        // an obsolete proposal must not be silently extended.
        clProposalMgt.fTestProposalUsable(rlProposalHeader);

        if not fValidateArguments(ArgumentsJson, rlProposalHeader, vlAppliedEntryNos, vlAppliedAmounts, vlReason) then begin
            ResultText := fBuildRejected(vlReason);
            exit;
        end;

        vlGroupNo := fCreateAIGroup(rlProposalHeader, vlAppliedEntryNos, vlAppliedAmounts);

        ResultText := fBuildApplied(vlGroupNo, vlAppliedEntryNos, vlAppliedAmounts);
        Success := true;
    end;

    #region Validation

    /// <summary>
    /// Guards against a tool call that belongs to a different execution than the
    /// case currently in memory. The framework stamps the execution source record
    /// on every tool context, and LAA_AIMatchMgt always starts the execution from
    /// the proposal header of the case.
    /// </summary>
    local procedure fBelongsToCurrentCase(pContextJson: Text; var prProposalHeader: Record "LAA_LedgerApplProposalHeader"): Boolean
    var
        vlContextJson: JsonObject;
        vlToken: JsonToken;
        vlSourceRecordId: Text;
    begin
        if not vlContextJson.ReadFrom(pContextJson) then
            exit(true);

        if not vlContextJson.Get('sourceRecordId', vlToken) then
            exit(true);

        if not vlToken.IsValue() then
            exit(true);

        vlSourceRecordId := vlToken.AsValue().AsText();
        if vlSourceRecordId = '' then
            exit(true);

        exit(vlSourceRecordId = Format(prProposalHeader.RecordId()));
    end;

    /// <summary>
    /// Reads appliedEntries and turns it into the signed amounts the proposal
    /// owner expects.
    ///
    /// A contract violation is rejected: an entry outside the candidate set, a
    /// duplicate, a negative magnitude, a closed entry, or more than an entry
    /// itself still holds. Running out of room on the applying movement is not a
    /// violation - it is arithmetic - so the amount is constrained instead,
    /// exactly as fAllocationAmount constrains every deterministic level. The
    /// result reports the amounts that were really applied.
    /// </summary>
    local procedure fValidateArguments(pArgumentsJson: Text; var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; var pvAppliedEntryNos: List of [Integer]; var pvAppliedAmounts: List of [Decimal]; var pvReason: Text): Boolean
    var
        vlArgumentsJson: JsonObject;
        vlEntryObject: JsonObject;
        vlEntriesArray: JsonArray;
        vlEntriesToken: JsonToken;
        vlEntryToken: JsonToken;
        vlApplyingAvailable: Decimal;
        vlAvailableAmount: Decimal;
        vlMagnitude: Decimal;
        vlRemainingCapacity: Decimal;
        vlApplyingEntryNo: Integer;
        vlEntryNo: Integer;
        vlAmountSupplied: Boolean;
    begin
        Clear(pvAppliedEntryNos);
        Clear(pvAppliedAmounts);
        Clear(pvReason);

        if not vlArgumentsJson.ReadFrom(pArgumentsJson) then begin
            pvReason := TextBadArgumentsLbl;
            exit(false);
        end;

        if not vlArgumentsJson.Get('appliedEntries', vlEntriesToken) or not vlEntriesToken.IsArray() then begin
            pvReason := TextNoEntriesLbl;
            exit(false);
        end;

        vlEntriesArray := vlEntriesToken.AsArray();
        if vlEntriesArray.Count() = 0 then begin
            pvReason := TextNoEntriesLbl;
            exit(false);
        end;

        vlApplyingEntryNo := clContext.fGetApplyingEntryNo();
        vlApplyingAvailable := fCurrentAvailableAmount(prProposalHeader, vlApplyingEntryNo);
        if vlApplyingAvailable = 0 then begin
            pvReason := StrSubstNo(TextNotAvailableLbl, vlApplyingEntryNo);
            exit(false);
        end;
        vlRemainingCapacity := Abs(vlApplyingAvailable);

        foreach vlEntryToken in vlEntriesArray do begin
            if not vlEntryToken.IsObject() then begin
                pvReason := TextNoEntryNoLbl;
                exit(false);
            end;

            vlEntryObject := vlEntryToken.AsObject();
            if not fTryGetInteger(vlEntryObject, 'entryNo', vlEntryNo) then begin
                pvReason := TextNoEntryNoLbl;
                exit(false);
            end;

            if pvAppliedEntryNos.Contains(vlEntryNo) then begin
                pvReason := StrSubstNo(TextDuplicateEntryLbl, vlEntryNo);
                exit(false);
            end;

            if not clContext.fIsAllowedCandidate(vlEntryNo) then begin
                pvReason := StrSubstNo(TextNotCandidateLbl, vlEntryNo);
                exit(false);
            end;

            // The live ledger is authoritative. The case snapshot only narrows the
            // choice; what is actually free right now decides the amount.
            vlAvailableAmount := fCurrentAvailableAmount(prProposalHeader, vlEntryNo);
            if vlAvailableAmount = 0 then begin
                pvReason := StrSubstNo(TextNotAvailableLbl, vlEntryNo);
                exit(false);
            end;

            vlAmountSupplied := fTryGetDecimal(vlEntryObject, 'amountToApply', vlMagnitude);
            if not vlAmountSupplied then
                vlMagnitude := Abs(vlAvailableAmount);

            if vlAmountSupplied then begin
                if vlMagnitude <= 0 then begin
                    pvReason := StrSubstNo(TextAmountNotPositiveLbl, vlEntryNo, vlMagnitude);
                    exit(false);
                end;

                if vlMagnitude > Abs(vlAvailableAmount) then begin
                    pvReason := StrSubstNo(TextAmountTooLargeLbl, vlMagnitude, Abs(vlAvailableAmount), vlEntryNo);
                    exit(false);
                end;
            end;

            // Never take more than the applying movement can still absorb.
            if vlMagnitude > vlRemainingCapacity then
                vlMagnitude := vlRemainingCapacity;

            // The applying movement is fully allocated: the remaining selections
            // stay open and are left to the deterministic fallback.
            if vlMagnitude <= 0 then
                break;

            pvAppliedEntryNos.Add(vlEntryNo);
            pvAppliedAmounts.Add(clProposalMgt.fSignOf(vlAvailableAmount) * vlMagnitude);
            vlRemainingCapacity -= vlMagnitude;
        end;

        if pvAppliedEntryNos.Count() = 0 then begin
            pvReason := StrSubstNo(TextNoCapacityLbl, vlApplyingEntryNo);
            exit(false);
        end;

        exit(true);
    end;

    local procedure fCurrentAvailableAmount(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pLedgerEntryNo: Integer): Decimal
    begin
        exit(clProposalMgt.fGetAvailableAmount(prProposalHeader, pLedgerEntryNo, 0));
    end;

    #endregion

    #region Group creation

    /// <summary>
    /// Creates the application group exactly as the deterministic levels do, with
    /// the match method set to AI Assisted, the confidence taken from the setup
    /// and the original AI candidate type preserved. The reservations are handed
    /// back to the matching engine through the context, so the residual FIFO
    /// cannot allocate the same amounts again.
    /// </summary>
    local procedure fCreateAIGroup(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; var pvAppliedEntryNos: List of [Integer]; var pvAppliedAmounts: List of [Decimal]): Integer
    var
        rlTEMPEntryCopy: Record "LAA_LedgerApplProposalLine" temporary;
        clAIMatchMgt: Codeunit "LAA_AIMatchMgt";
        vlReservedAmounts: List of [Decimal];
        vlReservedEntryNos: List of [Integer];
        vlCandidateType: Enum "LAA_AICandidateType";
        vlConfidence: Enum "LAA_Confidence";
        vlAppliedAmount: Decimal;
        vlApplyingAmount: Decimal;
        vlTotalApplied: Decimal;
        vlAppliedEntryNo: Integer;
        vlApplyingEntryNo: Integer;
        vlGroupNo: Integer;
        vlIndex: Integer;
    begin
        vlApplyingEntryNo := clContext.fGetApplyingEntryNo();
        vlCandidateType := clContext.fGetCandidateType();
        vlConfidence := clAIMatchMgt.fGetConfidence(vlCandidateType);

        foreach vlAppliedAmount in pvAppliedAmounts do
            vlTotalApplied += vlAppliedAmount;
        vlApplyingAmount := -vlTotalApplied;

        clContext.fGetCaseEntry(vlApplyingEntryNo, rlTEMPEntryCopy);
        vlGroupNo := clProposalMgt.fCreateGroup(prProposalHeader, rlTEMPEntryCopy, vlApplyingAmount, Enum::"LAA_MatchMethod"::"AI Assisted", vlConfidence, vlCandidateType);

        vlReservedEntryNos.Add(vlApplyingEntryNo);
        vlReservedAmounts.Add(vlApplyingAmount);

        for vlIndex := 1 to pvAppliedEntryNos.Count() do begin
            vlAppliedEntryNo := pvAppliedEntryNos.Get(vlIndex);
            vlAppliedAmount := pvAppliedAmounts.Get(vlIndex);

            clContext.fGetCaseEntry(vlAppliedEntryNo, rlTEMPEntryCopy);
            clProposalMgt.fAddAppliedEntry(prProposalHeader, vlGroupNo, rlTEMPEntryCopy, vlAppliedAmount, Enum::"LAA_MatchMethod"::"AI Assisted", vlConfidence, vlCandidateType);

            vlReservedEntryNos.Add(vlAppliedEntryNo);
            vlReservedAmounts.Add(vlAppliedAmount);
        end;

        // Only reached when every line was inserted. A failure on any of them
        // leaves the whole tool call rolled back by the framework and the context
        // without a result, which the matching engine reads as "no AI match".
        clContext.fRegisterResult(vlGroupNo, vlReservedEntryNos, vlReservedAmounts);

        exit(vlGroupNo);
    end;

    #endregion

    #region JSON helpers

    local procedure fBuildRejected(pReason: Text): Text
    var
        vlResultJson: JsonObject;
        vlResultText: Text;
    begin
        vlResultJson.Add('applied', false);
        vlResultJson.Add('reason', pReason);
        vlResultJson.WriteTo(vlResultText);

        exit(vlResultText);
    end;

    local procedure fBuildApplied(pGroupNo: Integer; var pvAppliedEntryNos: List of [Integer]; var pvAppliedAmounts: List of [Decimal]): Text
    var
        vlEntryJson: JsonObject;
        vlResultJson: JsonObject;
        vlEntriesArray: JsonArray;
        vlResultText: Text;
        vlIndex: Integer;
    begin
        for vlIndex := 1 to pvAppliedEntryNos.Count() do begin
            Clear(vlEntryJson);
            vlEntryJson.Add('entryNo', pvAppliedEntryNos.Get(vlIndex));
            vlEntryJson.Add('amountApplied', Abs(pvAppliedAmounts.Get(vlIndex)));
            vlEntriesArray.Add(vlEntryJson);
        end;

        vlResultJson.Add('applied', true);
        vlResultJson.Add('groupNo', pGroupNo);
        vlResultJson.Add('appliedEntries', vlEntriesArray);
        vlResultJson.Add('message', StrSubstNo(TextAppliedLbl, pGroupNo));
        vlResultJson.WriteTo(vlResultText);

        exit(vlResultText);
    end;

    local procedure fTryGetInteger(var pJsonObject: JsonObject; pPropertyName: Text; var pvValue: Integer): Boolean
    var
        vlToken: JsonToken;
    begin
        pvValue := 0;

        if not pJsonObject.Get(pPropertyName, vlToken) or not vlToken.IsValue() then
            exit(false);

        if vlToken.AsValue().IsNull() then
            exit(false);

        exit(Evaluate(pvValue, vlToken.AsValue().AsText(), 9));
    end;

    local procedure fTryGetDecimal(var pJsonObject: JsonObject; pPropertyName: Text; var pvValue: Decimal): Boolean
    var
        vlToken: JsonToken;
    begin
        pvValue := 0;

        if not pJsonObject.Get(pPropertyName, vlToken) or not vlToken.IsValue() then
            exit(false);

        if vlToken.AsValue().IsNull() then
            exit(false);

        exit(Evaluate(pvValue, vlToken.AsValue().AsText(), 9));
    end;

    #endregion
}
*/
