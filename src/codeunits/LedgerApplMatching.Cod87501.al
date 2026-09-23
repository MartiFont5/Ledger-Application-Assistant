/// <summary>
/// Deterministic matching engine. It reads the eligible ledger entries of one
/// entity into a temporary buffer and runs the matching levels sequentially:
///
///   1. Explicit reference
///   2. Unique exact 1:1
///   3. Unique exact 1:N
///   4. Standard Business Central payment tolerance
///   5. AI candidate classification
///   6. AI assisted matching, only when it is enabled in the setup
///   7. Residual FIFO
///
/// Once an amount has been reserved by a generated group it is no longer
/// available for the later levels. Entity and currency partition the work: the
/// engine never matches across customers/vendors and never across currencies.
///
/// Groups are always persisted through LAA_LedgerApplProposalMgt, so every group
/// created here passes exactly the same validations as a manual or an AI change.
/// </summary>
codeunit 87501 "LAA_LedgerApplMatching"
{
    Access = Internal;

    var
        rSetup: Record "LAA_LedgerApplSetup";
        rTEMPBufferEntry: Record "LAA_LedgerApplProposalLine" temporary;
        clEntityMgt: Codeunit "LAA_LedgerApplEntityMgt";
        clProposalMgt: Codeunit "LAA_LedgerApplProposalMgt";
        vSearchIterations: Integer;

    #region Search boundaries

    /// <summary>Largest candidate pool taken into an exact combination search.</summary>
    local procedure fMaxCombinationCandidates(): Integer
    begin
        exit(15);
    end;

    /// <summary>Hard ceiling of visited states, so the search can never run away.</summary>
    local procedure fMaxSearchIterations(): Integer
    begin
        exit(20000);
    end;

    /// <summary>Shortest document number accepted as a reference inside a description.</summary>
    local procedure fMinReferenceLength(): Integer
    begin
        exit(3);
    end;

    #endregion

    #region Entry point

    /// <summary>
    /// Generates every application group of a proposal that has just been created.
    /// </summary>
    internal procedure fGenerateProposal(var prProposalHeader: Record "LAA_LedgerApplProposalHeader")
    var
        vlCurrencyCode: Code[10];
        vlCurrencyList: List of [Code[10]];
    begin
        rSetup.fGetSetup();

        clEntityMgt.fCollectOpenEntries(prProposalHeader."Entity Type", prProposalHeader."Entity No.", rTEMPBufferEntry);

        fGetCurrencyList(vlCurrencyList);

        // Two passes, with the AI level in between. Everything deterministic runs
        // first for every currency because the AI level has to commit: a call to a
        // model is an HTTP callout and cannot be made with pending writes.
        // Currencies never interact - every level filters by currency and every
        // reservation is per entry - so splitting the loop changes no result.
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
    end;

    #endregion

    #region Level 1 - Explicit reference

    local procedure fMatchExplicitReference(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pCurrencyCode: Code[10])
    var
        vlEntryNo: Integer;
        vlEntryNoList: List of [Integer];
    begin
        fGetEntryNoList(pCurrencyCode, vlEntryNoList);

        foreach vlEntryNo in vlEntryNoList do
            fMatchExplicitReferenceForEntry(prProposalHeader, pCurrencyCode, vlEntryNo);
    end;

    local procedure fMatchExplicitReferenceForEntry(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pCurrencyCode: Code[10]; pApplyingEntryNo: Integer)
    var
        vlAppliedAmounts: List of [Decimal];
        vlAppliedEntryNos: List of [Integer];
        vlReferencedList: List of [Integer];
        vlCapacity: Decimal;
        vlCounterAvailable: Decimal;
        vlAmount: Decimal;
        vlTotalApplied: Decimal;
        vlReferencedNo: Integer;
    begin
        vlCapacity := fGetAvailable(pApplyingEntryNo);
        if vlCapacity = 0 then
            exit;

        fFindReferencedEntries(pCurrencyCode, pApplyingEntryNo, vlReferencedList);

        foreach vlReferencedNo in vlReferencedList do begin
            vlCounterAvailable := fGetAvailable(vlReferencedNo);

            if (vlCapacity <> 0) and (vlCounterAvailable <> 0) and not fSameSign(vlCounterAvailable, vlCapacity) then begin
                vlAmount := fAllocationAmount(vlCapacity, vlCounterAvailable);
                vlAppliedEntryNos.Add(vlReferencedNo);
                vlAppliedAmounts.Add(vlAmount);
                vlTotalApplied += vlAmount;
                vlCapacity += vlAmount;
            end;
        end;

        if vlAppliedEntryNos.Count() = 0 then
            exit;

        // The entry that carries the reference is the one being applied against the
        // others, so it takes the applying role whatever its document type is.
        fCreateGroupFromPlan(prProposalHeader, pApplyingEntryNo, -vlTotalApplied, vlAppliedEntryNos, vlAppliedAmounts,
                             Enum::"LAA_MatchMethod"::"Explicit Reference", Enum::"LAA_Confidence"::"Very High");
    end;

    /// <summary>
    /// Returns the open entries that the given entry explicitly references through
    /// standard applies-to information, payment reference, external document number
    /// or a document number written in its description.
    /// </summary>
    local procedure fFindReferencedEntries(pCurrencyCode: Code[10]; pApplyingEntryNo: Integer; var pvReferencedList: List of [Integer])
    var
        vlAllEntryNoList: List of [Integer];
        vlAppliesToDocNo: Code[20];
        vlCandidateDocNo: Code[20];
        vlCandidateExtDocNo: Code[35];
        vlExternalDocNo: Code[35];
        vlPaymentReference: Code[50];
        vlApplyingAvailable: Decimal;
        vlCandidateAvailable: Decimal;
        vlCandidateNo: Integer;
        vlDescription: Text;
    begin
        Clear(pvReferencedList);

        if not rTEMPBufferEntry.Get(0, pApplyingEntryNo) then
            exit;

        vlAppliesToDocNo := rTEMPBufferEntry."Applies-to Doc. No.";
        vlPaymentReference := rTEMPBufferEntry."Payment Reference";
        vlExternalDocNo := rTEMPBufferEntry."External Document No.";
        vlDescription := UpperCase(rTEMPBufferEntry.Description);
        vlApplyingAvailable := fBufferAvailable();

        if (vlAppliesToDocNo = '') and (vlPaymentReference = '') and (vlExternalDocNo = '') and (vlDescription = '') then
            exit;

        fGetEntryNoList(pCurrencyCode, vlAllEntryNoList);

        foreach vlCandidateNo in vlAllEntryNoList do
            if vlCandidateNo <> pApplyingEntryNo then
                if rTEMPBufferEntry.Get(0, vlCandidateNo) then begin
                    vlCandidateAvailable := fBufferAvailable();
                    vlCandidateDocNo := rTEMPBufferEntry."Document No.";
                    vlCandidateExtDocNo := rTEMPBufferEntry."External Document No.";

                    if (vlCandidateAvailable <> 0) and not fSameSign(vlCandidateAvailable, vlApplyingAvailable) then
                        if fReferenceMatches(vlAppliesToDocNo, vlPaymentReference, vlExternalDocNo, vlDescription, vlCandidateDocNo, vlCandidateExtDocNo) then
                            pvReferencedList.Add(vlCandidateNo);
                end;
    end;

    local procedure fReferenceMatches(pAppliesToDocNo: Code[20]; pPaymentReference: Code[50]; pExternalDocNo: Code[35]; pDescription: Text; pCandidateDocNo: Code[20]; pCandidateExtDocNo: Code[35]): Boolean
    begin
        if pCandidateDocNo = '' then
            exit(false);

        if (pAppliesToDocNo <> '') and (pAppliesToDocNo = pCandidateDocNo) then
            exit(true);

        if fReferenceValueMatches(pPaymentReference, pCandidateDocNo, pCandidateExtDocNo) then
            exit(true);

        if fReferenceValueMatches(pExternalDocNo, pCandidateDocNo, pCandidateExtDocNo) then
            exit(true);

        if pDescription = '' then
            exit(false);

        if (StrLen(pCandidateDocNo) >= fMinReferenceLength()) and (StrPos(pDescription, UpperCase(pCandidateDocNo)) > 0) then
            exit(true);

        if (StrLen(pCandidateExtDocNo) >= fMinReferenceLength()) and (StrPos(pDescription, UpperCase(pCandidateExtDocNo)) > 0) then
            exit(true);

        exit(false);
    end;

    local procedure fReferenceValueMatches(pReferenceValue: Text; pCandidateDocNo: Code[20]; pCandidateExtDocNo: Code[35]): Boolean
    begin
        if pReferenceValue = '' then
            exit(false);

        if pReferenceValue = pCandidateDocNo then
            exit(true);

        exit((pCandidateExtDocNo <> '') and (pReferenceValue = pCandidateExtDocNo));
    end;

    #endregion

    #region Level 2 - Unique exact 1:1

    local procedure fMatchExactPair(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pCurrencyCode: Code[10])
    var
        vlAppliedAmounts: List of [Decimal];
        vlAppliedEntryNos: List of [Integer];
        vlEntryNoList: List of [Integer];
        vlAvailable: Decimal;
        vlApplyingEntryNo: Integer;
        vlAppliedEntryNo: Integer;
        vlCounterpartNo: Integer;
        vlEntryNo: Integer;
        vlOppositeCount: Integer;
        vlSameSideCount: Integer;
    begin
        fGetEntryNoList(pCurrencyCode, vlEntryNoList);

        foreach vlEntryNo in vlEntryNoList do begin
            vlAvailable := fGetAvailable(vlEntryNo);

            if vlAvailable <> 0 then begin
                fCountExactCandidates(pCurrencyCode, vlEntryNo, vlAvailable, vlOppositeCount, vlCounterpartNo, vlSameSideCount);

                // A single candidate on each side of the match: nothing has to be
                // chosen arbitrarily, so the pair is safe to propose.
                if (vlOppositeCount = 1) and (vlSameSideCount = 1) then begin
                    fGetApplyingRole(vlEntryNo, vlCounterpartNo, vlApplyingEntryNo, vlAppliedEntryNo);

                    Clear(vlAppliedEntryNos);
                    Clear(vlAppliedAmounts);
                    vlAppliedEntryNos.Add(vlAppliedEntryNo);
                    vlAppliedAmounts.Add(fGetAvailable(vlAppliedEntryNo));

                    fCreateGroupFromPlan(prProposalHeader, vlApplyingEntryNo, fGetAvailable(vlApplyingEntryNo), vlAppliedEntryNos, vlAppliedAmounts,
                                         Enum::"LAA_MatchMethod"::"Exact 1:1", Enum::"LAA_Confidence"::High);
                end;
            end;
        end;
    end;

    /// <summary>
    /// Counts how many entries could take part in an exact amount match, both on
    /// the opposite side and on the same side as the evaluated entry. Two invoices
    /// with the same amount must never be matched arbitrarily, which is why the
    /// same side is counted as well.
    /// </summary>
    local procedure fCountExactCandidates(pCurrencyCode: Code[10]; pEntryNo: Integer; pAvailable: Decimal; var pvOppositeCount: Integer; var pvOppositeEntryNo: Integer; var pvSameSideCount: Integer)
    var
        vlEntryNoList: List of [Integer];
        vlCandidateAvailable: Decimal;
        vlCandidateNo: Integer;
    begin
        pvOppositeCount := 0;
        pvOppositeEntryNo := 0;
        pvSameSideCount := 0;

        fGetEntryNoList(pCurrencyCode, vlEntryNoList);

        foreach vlCandidateNo in vlEntryNoList do begin
            vlCandidateAvailable := fGetAvailable(vlCandidateNo);

            if (vlCandidateAvailable <> 0) and (Abs(vlCandidateAvailable) = Abs(pAvailable)) then
                if fSameSign(vlCandidateAvailable, pAvailable) then
                    pvSameSideCount += 1
                else
                    if fIsWithinDateLimit(pEntryNo, vlCandidateNo) then begin
                        pvOppositeCount += 1;
                        pvOppositeEntryNo := vlCandidateNo;
                    end;
        end;
    end;

    #endregion

    #region Level 3 - Unique exact 1:N

    local procedure fMatchExactCombination(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pCurrencyCode: Code[10])
    var
        vlEntryNo: Integer;
        vlEntryNoList: List of [Integer];
    begin
        fGetEntryNoList(pCurrencyCode, vlEntryNoList);

        foreach vlEntryNo in vlEntryNoList do
            fMatchExactCombinationForEntry(prProposalHeader, pCurrencyCode, vlEntryNo);
    end;

    local procedure fMatchExactCombinationForEntry(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pCurrencyCode: Code[10]; pApplyingEntryNo: Integer)
    var
        vlCandidateAmounts: List of [Decimal];
        vlCandidateEntryNos: List of [Integer];
        vlCurrentIndexes: List of [Integer];
        vlSolutionIndexes: List of [Integer];
        vlAvailable: Decimal;
        vlSolutionCount: Integer;
    begin
        vlAvailable := fGetAvailable(pApplyingEntryNo);
        if vlAvailable = 0 then
            exit;

        fCollectCombinationCandidates(pCurrencyCode, pApplyingEntryNo, vlAvailable, vlCandidateEntryNos, vlCandidateAmounts);
        if vlCandidateEntryNos.Count() < 2 then
            exit;

        vSearchIterations := 0;
        fSearchCombination(vlCandidateAmounts, 1, Abs(vlAvailable), vlCurrentIndexes, vlSolutionIndexes, vlSolutionCount);

        // More than one exact combination exists: choosing one would be arbitrary,
        // so the case is left to the AI classification and to the residual FIFO.
        if vlSolutionCount <> 1 then
            exit;

        fCreateCombinationGroups(prProposalHeader, pApplyingEntryNo, vlCandidateEntryNos, vlSolutionIndexes);
    end;

    local procedure fCollectCombinationCandidates(pCurrencyCode: Code[10]; pApplyingEntryNo: Integer; pApplyingAvailable: Decimal; var pvCandidateEntryNos: List of [Integer]; var pvCandidateAmounts: List of [Decimal])
    var
        vlEntryNoList: List of [Integer];
        vlCandidateAvailable: Decimal;
        vlCandidateNo: Integer;
    begin
        Clear(pvCandidateEntryNos);
        Clear(pvCandidateAmounts);

        fGetEntryNoList(pCurrencyCode, vlEntryNoList);

        foreach vlCandidateNo in vlEntryNoList do
            if (vlCandidateNo <> pApplyingEntryNo) and (pvCandidateEntryNos.Count() < fMaxCombinationCandidates()) then begin
                vlCandidateAvailable := fGetAvailable(vlCandidateNo);

                if (vlCandidateAvailable <> 0) and
                   not fSameSign(vlCandidateAvailable, pApplyingAvailable) and
                   (Abs(vlCandidateAvailable) <= Abs(pApplyingAvailable)) and
                   fIsWithinDateLimit(pApplyingEntryNo, vlCandidateNo)
                then begin
                    pvCandidateEntryNos.Add(vlCandidateNo);
                    pvCandidateAmounts.Add(Abs(vlCandidateAvailable));
                end;
            end;
    end;

    /// <summary>
    /// Small bounded search for exact combinations. It is deliberately not a
    /// general subset-sum solver: the candidate list, the combination size and the
    /// number of visited states are all capped, and the search stops as soon as a
    /// second solution proves the case ambiguous.
    /// </summary>
    local procedure fSearchCombination(var pvCandidateAmounts: List of [Decimal]; pStartIndex: Integer; pRemainingAmount: Decimal; var pvCurrentIndexes: List of [Integer]; var pvSolutionIndexes: List of [Integer]; var pvSolutionCount: Integer)
    var
        vlCandidateAmount: Decimal;
        vlIndex: Integer;
        vlCurrentIndex: Integer;
    begin
        if pvSolutionCount > 1 then
            exit;

        vSearchIterations += 1;
        if vSearchIterations > fMaxSearchIterations() then
            exit;

        if pRemainingAmount = 0 then begin
            // 1:1 matches were already handled by the previous level.
            if pvCurrentIndexes.Count() >= 2 then begin
                pvSolutionCount += 1;

                if pvSolutionCount = 1 then begin
                    Clear(pvSolutionIndexes);
                    foreach vlCurrentIndex in pvCurrentIndexes do
                        pvSolutionIndexes.Add(vlCurrentIndex);
                end;
            end;
            exit;
        end;

        if pvCurrentIndexes.Count() >= rSetup."Max. Combination Lines" then
            exit;

        for vlIndex := pStartIndex to pvCandidateAmounts.Count() do begin
            vlCandidateAmount := pvCandidateAmounts.Get(vlIndex);

            if vlCandidateAmount <= pRemainingAmount then begin
                pvCurrentIndexes.Add(vlIndex);
                fSearchCombination(pvCandidateAmounts, vlIndex + 1, pRemainingAmount - vlCandidateAmount, pvCurrentIndexes, pvSolutionIndexes, pvSolutionCount);
                pvCurrentIndexes.RemoveAt(pvCurrentIndexes.Count());
            end;
        end;
    end;

    /// <summary>
    /// Turns the discovered exact combination into executable groups. When the
    /// applying entry is the most recent one the result is a single 1:N group.
    /// Otherwise the relation is an N:1 one, which is normalized into one 1:N
    /// group per counterpart so that every stored group stays executable.
    /// </summary>
    local procedure fCreateCombinationGroups(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pApplyingEntryNo: Integer; var pvCandidateEntryNos: List of [Integer]; var pvSolutionIndexes: List of [Integer])
    var
        vlAppliedAmounts: List of [Decimal];
        vlAppliedEntryNos: List of [Integer];
        vlSolutionEntryNos: List of [Integer];
        vlAmount: Decimal;
        vlCapacity: Decimal;
        vlCounterAvailable: Decimal;
        vlTotalApplied: Decimal;
        vlIndex: Integer;
        vlSolutionEntryNo: Integer;
    begin
        foreach vlIndex in pvSolutionIndexes do
            vlSolutionEntryNos.Add(pvCandidateEntryNos.Get(vlIndex));

        if not fIsMostRecent(pApplyingEntryNo, vlSolutionEntryNos) then begin
            fCreateNormalizedGroups(prProposalHeader, pApplyingEntryNo, vlSolutionEntryNos);
            exit;
        end;

        vlCapacity := fGetAvailable(pApplyingEntryNo);

        foreach vlSolutionEntryNo in vlSolutionEntryNos do begin
            vlCounterAvailable := fGetAvailable(vlSolutionEntryNo);

            if (vlCapacity <> 0) and (vlCounterAvailable <> 0) then begin
                vlAmount := fAllocationAmount(vlCapacity, vlCounterAvailable);
                vlAppliedEntryNos.Add(vlSolutionEntryNo);
                vlAppliedAmounts.Add(vlAmount);
                vlTotalApplied += vlAmount;
                vlCapacity += vlAmount;
            end;
        end;

        if vlAppliedEntryNos.Count() > 0 then
            fCreateGroupFromPlan(prProposalHeader, pApplyingEntryNo, -vlTotalApplied, vlAppliedEntryNos, vlAppliedAmounts,
                                 Enum::"LAA_MatchMethod"::"Exact 1:N", Enum::"LAA_Confidence"::High);
    end;

    /// <summary>
    /// Normalizes an N:1 relation into several 1:N groups: every counterpart
    /// becomes the applying entry of its own group and consumes its share of the
    /// single opposite entry.
    /// </summary>
    local procedure fCreateNormalizedGroups(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pAppliedEntryNo: Integer; var pvApplyingEntryNos: List of [Integer])
    var
        vlAppliedAmounts: List of [Decimal];
        vlAppliedEntryNos: List of [Integer];
        vlAmount: Decimal;
        vlApplyingAvailable: Decimal;
        vlSharedAvailable: Decimal;
        vlApplyingEntryNo: Integer;
    begin
        foreach vlApplyingEntryNo in pvApplyingEntryNos do begin
            vlSharedAvailable := fGetAvailable(pAppliedEntryNo);
            vlApplyingAvailable := fGetAvailable(vlApplyingEntryNo);

            if (vlSharedAvailable <> 0) and (vlApplyingAvailable <> 0) then begin
                vlAmount := fAllocationAmount(vlApplyingAvailable, vlSharedAvailable);

                Clear(vlAppliedEntryNos);
                Clear(vlAppliedAmounts);
                vlAppliedEntryNos.Add(pAppliedEntryNo);
                vlAppliedAmounts.Add(vlAmount);

                fCreateGroupFromPlan(prProposalHeader, vlApplyingEntryNo, -vlAmount, vlAppliedEntryNos, vlAppliedAmounts,
                                     Enum::"LAA_MatchMethod"::"Exact 1:N", Enum::"LAA_Confidence"::High);
            end;
        end;
    end;

    #endregion

    #region Level 4 - Standard payment tolerance

    local procedure fMatchPaymentTolerance(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pCurrencyCode: Code[10])
    var
        vlAppliedAmounts: List of [Decimal];
        vlAppliedEntryNos: List of [Integer];
        vlEntryNoList: List of [Integer];
        vlAvailable: Decimal;
        vlAppliedEntryNo: Integer;
        vlApplyingEntryNo: Integer;
        vlCounterpartNo: Integer;
        vlEntryNo: Integer;
    begin
        // Tolerance is only proposed when the standard Business Central setup
        // supports it. The extension never owns a tolerance parameter of its own.
        if not clEntityMgt.fIsPaymentToleranceEnabled() then
            exit;

        fGetEntryNoList(pCurrencyCode, vlEntryNoList);

        foreach vlEntryNo in vlEntryNoList do begin
            vlAvailable := fGetAvailable(vlEntryNo);

            if vlAvailable <> 0 then
                if fFindUniqueToleranceCounterpart(prProposalHeader, pCurrencyCode, vlEntryNo, vlAvailable, vlCounterpartNo) then begin
                    fGetApplyingRole(vlEntryNo, vlCounterpartNo, vlApplyingEntryNo, vlAppliedEntryNo);

                    Clear(vlAppliedEntryNos);
                    Clear(vlAppliedAmounts);
                    vlAppliedEntryNos.Add(vlAppliedEntryNo);
                    vlAppliedAmounts.Add(fGetAvailable(vlAppliedEntryNo));

                    fCreateGroupFromPlan(prProposalHeader, vlApplyingEntryNo, fGetAvailable(vlApplyingEntryNo), vlAppliedEntryNos, vlAppliedAmounts,
                                         Enum::"LAA_MatchMethod"::"Payment Tolerance", Enum::"LAA_Confidence"::Medium);
                end;
        end;
    end;

    local procedure fFindUniqueToleranceCounterpart(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pCurrencyCode: Code[10]; pEntryNo: Integer; pAvailable: Decimal; var pvCounterpartNo: Integer): Boolean
    var
        vlEntryNoList: List of [Integer];
        vlCandidateAvailable: Decimal;
        vlDifference: Decimal;
        vlToleranceAmount: Decimal;
        vlCandidateNo: Integer;
        vlMatchCount: Integer;
    begin
        pvCounterpartNo := 0;
        fGetEntryNoList(pCurrencyCode, vlEntryNoList);

        foreach vlCandidateNo in vlEntryNoList do begin
            vlCandidateAvailable := fGetAvailable(vlCandidateNo);

            if (vlCandidateAvailable <> 0) and
               not fSameSign(vlCandidateAvailable, pAvailable) and
               fIsWithinDateLimit(pEntryNo, vlCandidateNo)
            then begin
                vlDifference := Abs(Abs(vlCandidateAvailable) - Abs(pAvailable));
                vlToleranceAmount := fGetMaxToleranceOfPair(prProposalHeader, pEntryNo, vlCandidateNo);

                if (vlDifference <> 0) and (vlToleranceAmount > 0) and (vlDifference <= vlToleranceAmount) then begin
                    vlMatchCount += 1;
                    pvCounterpartNo := vlCandidateNo;
                end;
            end;
        end;

        exit(vlMatchCount = 1);
    end;

    local procedure fGetMaxToleranceOfPair(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pEntryNo1: Integer; pEntryNo2: Integer): Decimal
    var
        vlTolerance1: Decimal;
        vlTolerance2: Decimal;
    begin
        vlTolerance1 := clEntityMgt.fGetMaxPaymentTolerance(prProposalHeader."Entity Type", pEntryNo1);
        vlTolerance2 := clEntityMgt.fGetMaxPaymentTolerance(prProposalHeader."Entity Type", pEntryNo2);

        if vlTolerance1 > vlTolerance2 then
            exit(vlTolerance1);

        exit(vlTolerance2);
    end;

    #endregion

    #region Level 5 - AI candidate classification

    /// <summary>
    /// Classifies what the deterministic levels could not resolve. No LLM is
    /// called: the classification travels with the entry and is written on the
    /// proposal lines that the residual FIFO creates for it, so the volume of
    /// cases where AI could add value can be measured without any new table.
    /// </summary>
    local procedure fClassifyAICandidates(pCurrencyCode: Code[10])
    var
        vlEntryNoList: List of [Integer];
        vlCandidateType: Enum "LAA_AICandidateType";
        vlAvailable: Decimal;
        vlEntryNo: Integer;
    begin
        fGetEntryNoList(pCurrencyCode, vlEntryNoList);

        foreach vlEntryNo in vlEntryNoList do begin
            vlAvailable := fGetAvailable(vlEntryNo);

            if vlAvailable <> 0 then begin
                vlCandidateType := fDetermineCandidateType(pCurrencyCode, vlEntryNo, vlAvailable);

                if rTEMPBufferEntry.Get(0, vlEntryNo) then begin
                    rTEMPBufferEntry."AI Candidate Type" := vlCandidateType;
                    rTEMPBufferEntry.Modify(false);
                end;
            end;
        end;
    end;

    local procedure fDetermineCandidateType(pCurrencyCode: Code[10]; pEntryNo: Integer; pAvailable: Decimal): Enum "LAA_AICandidateType"
    var
        vlReferencedList: List of [Integer];
        vlReservedAmount: Decimal;
        vlCounterpartNo: Integer;
        vlOppositeCount: Integer;
        vlSameSideCount: Integer;
    begin
        fCountExactCandidates(pCurrencyCode, pEntryNo, pAvailable, vlOppositeCount, vlCounterpartNo, vlSameSideCount);
        if (vlOppositeCount > 1) or ((vlOppositeCount = 1) and (vlSameSideCount > 1)) then
            exit(Enum::"LAA_AICandidateType"::"Multiple Exact Matches");

        fFindReferencedEntries(pCurrencyCode, pEntryNo, vlReferencedList);
        if vlReferencedList.Count() > 0 then
            exit(Enum::"LAA_AICandidateType"::"Textual Reference");

        if rTEMPBufferEntry.Get(0, pEntryNo) then
            vlReservedAmount := rTEMPBufferEntry."Amount to Apply";
        if vlReservedAmount <> 0 then
            exit(Enum::"LAA_AICandidateType"::"Partial Match");

        exit(Enum::"LAA_AICandidateType"::"Unclassified Residual");
    end;

    #endregion

    #region Level 6 - AI assisted matching

    /// <summary>
    /// Last chance before the residual FIFO. Every ambiguous case the level above
    /// classified is offered to the AI agent, which either recognizes the real
    /// counterparts from the documents themselves or leaves the movements alone.
    ///
    /// Nothing here can break the generation of a proposal. When the feature is
    /// off, when the framework is not configured, or when a single case fails for
    /// any reason, the movements simply stay available and the residual FIFO runs
    /// exactly as it always has.
    /// </summary>
    local procedure fAIMatching(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; var pvCurrencyList: List of [Code[10]])
    var
        clAIMatchMgt: Codeunit "LAA_AIMatchMgt";
        vlCurrencyCode: Code[10];
    begin
        if not rSetup."Enable AI Matching" then
            exit;

        if not clAIMatchMgt.fIsAIMatchingEnabled() then
            exit;

        foreach vlCurrencyCode in pvCurrencyList do
            fAIMatchingForCurrency(prProposalHeader, clAIMatchMgt, vlCurrencyCode);
    end;

    local procedure fAIMatchingForCurrency(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; var pclAIMatchMgt: Codeunit "LAA_AIMatchMgt"; pCurrencyCode: Code[10])
    var
        rlTEMPCaseEntry: Record "LAA_LedgerApplProposalLine" temporary;
        vlAppliedAmounts: List of [Decimal];
        vlAppliedEntryNos: List of [Integer];
        vlCandidateType: Enum "LAA_AICandidateType";
        vlEntryNo: Integer;
        vlEntryNoList: List of [Integer];
    begin
        fGetEntryNoList(pCurrencyCode, vlEntryNoList);

        foreach vlEntryNo in vlEntryNoList do
            if fBuildAICase(pclAIMatchMgt, pCurrencyCode, vlEntryNo, vlCandidateType, rlTEMPCaseEntry) then
                if pclAIMatchMgt.fRunCase(prProposalHeader, vlCandidateType, vlEntryNo, rlTEMPCaseEntry, vlAppliedEntryNos, vlAppliedAmounts) then
                    fApplyAIReservations(vlAppliedEntryNos, vlAppliedAmounts);
    end;

    /// <summary>
    /// Builds the case of one entry, or returns false when the entry is not an AI
    /// case at all. The availability is read again for every entry, so a movement
    /// an earlier AI case already consumed is skipped instead of being offered a
    /// second time.
    /// </summary>
    local procedure fBuildAICase(var pclAIMatchMgt: Codeunit "LAA_AIMatchMgt"; pCurrencyCode: Code[10]; pApplyingEntryNo: Integer; var pvCandidateType: Enum "LAA_AICandidateType"; var pTEMPCaseEntry: Record "LAA_LedgerApplProposalLine" temporary): Boolean
    var
        vlCandidateEntryNos: List of [Integer];
        vlAvailable: Decimal;
        vlCandidateNo: Integer;
    begin
        pTEMPCaseEntry.Reset();
        pTEMPCaseEntry.DeleteAll(false);
        Clear(pvCandidateType);

        vlAvailable := fGetAvailable(pApplyingEntryNo);
        if vlAvailable = 0 then
            exit(false);

        pvCandidateType := fGetCandidateType(pApplyingEntryNo);
        if not pclAIMatchMgt.fIsInScope(pvCandidateType) then
            exit(false);

        fCollectAICandidates(pCurrencyCode, pApplyingEntryNo, vlAvailable, pvCandidateType, vlCandidateEntryNos);
        if vlCandidateEntryNos.Count() = 0 then
            exit(false);

        if not fAddCaseEntry(pApplyingEntryNo, pTEMPCaseEntry) then
            exit(false);

        foreach vlCandidateNo in vlCandidateEntryNos do
            fAddCaseEntry(vlCandidateNo, pTEMPCaseEntry);

        exit(true);
    end;

    /// <summary>
    /// Candidate discovery for an AI case. It applies the same predicates the
    /// deterministic levels apply - same currency, opposite sign, something still
    /// available, inside the date limit - and stays inside the same candidate
    /// ceiling, so an AI case can never widen the search the engine is allowed to
    /// make.
    ///
    /// It does NOT reuse fCollectCombinationCandidates, because that collector
    /// also demands a counterpart no larger than the applying movement. That rule
    /// belongs to an exact combination: a partial application is precisely the
    /// case where a small residual is applied against a larger invoice, and
    /// reusing the collector would hide exactly the candidates a Partial Match or
    /// a Textual Reference case is about.
    ///
    /// Only strictly older counterparts survive, which is the chronology rule the
    /// rest of the engine already applies - the most recent movement takes the
    /// applying role. It also means one cluster produces one AI case, built from
    /// its newest movement, instead of one case per movement of the cluster.
    ///
    /// For Multiple Exact Matches the set is narrowed once more to the
    /// counterparts whose amount matches exactly, because those are the ones the
    /// deterministic level was unable to choose between.
    /// </summary>
    local procedure fCollectAICandidates(pCurrencyCode: Code[10]; pApplyingEntryNo: Integer; pApplyingAvailable: Decimal; pCandidateType: Enum "LAA_AICandidateType"; var pvCandidateEntryNos: List of [Integer])
    var
        vlEntryNoList: List of [Integer];
        vlCandidateAvailable: Decimal;
        vlCandidateNo: Integer;
    begin
        Clear(pvCandidateEntryNos);

        fGetEntryNoList(pCurrencyCode, vlEntryNoList);

        // The list is ordered by posting date, so the ceiling keeps the oldest
        // counterparts, which are the ones the chronology rule accepts anyway.
        foreach vlCandidateNo in vlEntryNoList do
            if (vlCandidateNo <> pApplyingEntryNo) and (pvCandidateEntryNos.Count() < fMaxCombinationCandidates()) then begin
                vlCandidateAvailable := fGetAvailable(vlCandidateNo);

                if (vlCandidateAvailable <> 0) and
                   not fSameSign(vlCandidateAvailable, pApplyingAvailable) and
                   fIsWithinDateLimit(pApplyingEntryNo, vlCandidateNo) and
                   fIsOlderThan(vlCandidateNo, pApplyingEntryNo) and
                   fIsAICandidateAmount(pCandidateType, vlCandidateAvailable, pApplyingAvailable)
                then
                    pvCandidateEntryNos.Add(vlCandidateNo);
            end;
    end;

    /// <summary>
    /// Amount rule per candidate type. Multiple Exact Matches is about
    /// counterparts that fit the applying movement to the cent, so only those are
    /// offered. The other two types are semantic, not arithmetic: any compatible
    /// balance may be the right counterpart, whole or in part.
    /// </summary>
    local procedure fIsAICandidateAmount(pCandidateType: Enum "LAA_AICandidateType"; pCandidateAvailable: Decimal; pApplyingAvailable: Decimal): Boolean
    begin
        if pCandidateType <> Enum::"LAA_AICandidateType"::"Multiple Exact Matches" then
            exit(true);

        exit(Abs(pCandidateAvailable) = Abs(pApplyingAvailable));
    end;

    local procedure fAddCaseEntry(pLedgerEntryNo: Integer; var pTEMPCaseEntry: Record "LAA_LedgerApplProposalLine" temporary): Boolean
    begin
        if not rTEMPBufferEntry.Get(0, pLedgerEntryNo) then
            exit(false);

        pTEMPCaseEntry := rTEMPBufferEntry;
        pTEMPCaseEntry.Insert(false);

        exit(true);
    end;

    /// <summary>
    /// Mirrors on the buffer what the AI tool already wrote to the proposal. The
    /// tool is the only writer of the group, but the buffer is what the residual
    /// FIFO reads, so without this the same amounts would be allocated twice.
    /// </summary>
    local procedure fApplyAIReservations(var pvEntryNos: List of [Integer]; var pvAmounts: List of [Decimal])
    var
        vlIndex: Integer;
    begin
        for vlIndex := 1 to pvEntryNos.Count() do
            fReserveAmount(pvEntryNos.Get(vlIndex), pvAmounts.Get(vlIndex));
    end;

    #endregion

    #region Level 7 - Residual FIFO

    /// <summary>
    /// Final low-confidence fallback. It allocates the remaining compatible
    /// balances oldest first and does not require an exact zero-sum cluster, so
    /// partial balances are allocated as far as they reach.
    /// </summary>
    local procedure fResidualFIFO(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pCurrencyCode: Code[10])
    var
        vlEntryNo: Integer;
        vlEntryNoList: List of [Integer];
    begin
        fGetEntryNoList(pCurrencyCode, vlEntryNoList);

        foreach vlEntryNo in vlEntryNoList do
            fResidualFIFOForEntry(prProposalHeader, vlEntryNo, vlEntryNoList);
    end;

    local procedure fResidualFIFOForEntry(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pApplyingEntryNo: Integer; var pvEntryNoList: List of [Integer])
    var
        vlAppliedAmounts: List of [Decimal];
        vlAppliedEntryNos: List of [Integer];
        vlAmount: Decimal;
        vlCapacity: Decimal;
        vlCounterAvailable: Decimal;
        vlTotalApplied: Decimal;
        vlCounterpartNo: Integer;
    begin
        vlCapacity := fGetAvailable(pApplyingEntryNo);
        if vlCapacity = 0 then
            exit;

        // The list is ordered by posting date, so the oldest open counterpart is
        // consumed first. Only older counterparts are considered, which keeps the
        // newest movement of every group in the applying role.
        foreach vlCounterpartNo in pvEntryNoList do
            if (vlCounterpartNo <> pApplyingEntryNo) and fIsOlderThan(vlCounterpartNo, pApplyingEntryNo) then begin
                vlCounterAvailable := fGetAvailable(vlCounterpartNo);

                if (vlCapacity <> 0) and (vlCounterAvailable <> 0) and not fSameSign(vlCounterAvailable, vlCapacity) then begin
                    vlAmount := fAllocationAmount(vlCapacity, vlCounterAvailable);
                    vlAppliedEntryNos.Add(vlCounterpartNo);
                    vlAppliedAmounts.Add(vlAmount);
                    vlTotalApplied += vlAmount;
                    vlCapacity += vlAmount;
                end;
            end;

        if vlAppliedEntryNos.Count() > 0 then
            fCreateGroupFromPlan(prProposalHeader, pApplyingEntryNo, -vlTotalApplied, vlAppliedEntryNos, vlAppliedAmounts,
                                 Enum::"LAA_MatchMethod"::FIFO, rSetup."FIFO Default Confidence");
    end;

    #endregion

    #region Group creation

    /// <summary>
    /// Persists one application group through the proposal management codeunit and
    /// keeps the matching buffer in sync, so that the reserved amounts are no
    /// longer offered to the later matching levels.
    /// </summary>
    local procedure fCreateGroupFromPlan(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pApplyingEntryNo: Integer; pApplyingAmount: Decimal; var pvAppliedEntryNos: List of [Integer]; var pvAppliedAmounts: List of [Decimal]; pMatchMethod: Enum "LAA_MatchMethod"; pConfidence: Enum "LAA_Confidence")
    var
        rlTEMPEntryCopy: Record "LAA_LedgerApplProposalLine" temporary;
        vlAppliedAmount: Decimal;
        vlAppliedEntryNo: Integer;
        vlGroupNo: Integer;
        vlIndex: Integer;
    begin
        if pApplyingAmount = 0 then
            exit;

        if not fCopyBufferEntry(pApplyingEntryNo, rlTEMPEntryCopy) then
            exit;

        vlGroupNo := clProposalMgt.fCreateGroup(prProposalHeader, rlTEMPEntryCopy, pApplyingAmount, pMatchMethod, pConfidence, fGetCandidateType(pApplyingEntryNo));
        fReserveAmount(pApplyingEntryNo, pApplyingAmount);

        for vlIndex := 1 to pvAppliedEntryNos.Count() do begin
            vlAppliedEntryNo := pvAppliedEntryNos.Get(vlIndex);
            vlAppliedAmount := pvAppliedAmounts.Get(vlIndex);

            if fCopyBufferEntry(vlAppliedEntryNo, rlTEMPEntryCopy) then begin
                clProposalMgt.fAddAppliedEntry(prProposalHeader, vlGroupNo, rlTEMPEntryCopy, vlAppliedAmount, pMatchMethod, pConfidence, fGetCandidateType(vlAppliedEntryNo));
                fReserveAmount(vlAppliedEntryNo, vlAppliedAmount);
            end;
        end;
    end;

    #endregion

    #region Buffer helpers

    local procedure fGetCurrencyList(var pvCurrencyList: List of [Code[10]])
    begin
        Clear(pvCurrencyList);

        rTEMPBufferEntry.Reset();
        rTEMPBufferEntry.SetCurrentKey("Proposal No.", "Currency Code", "Posting Date", "Line No.");
        if rTEMPBufferEntry.FindSet() then
            repeat
                if not pvCurrencyList.Contains(rTEMPBufferEntry."Currency Code") then
                    pvCurrencyList.Add(rTEMPBufferEntry."Currency Code");
            until rTEMPBufferEntry.Next() = 0;
    end;

    /// <summary>
    /// Entry numbers of one currency, ordered by posting date and entry number.
    /// The engine always works on a snapshot list instead of an open cursor, so
    /// that reserving an amount never disturbs an ongoing iteration.
    /// </summary>
    local procedure fGetEntryNoList(pCurrencyCode: Code[10]; var pvEntryNoList: List of [Integer])
    begin
        Clear(pvEntryNoList);

        rTEMPBufferEntry.Reset();
        rTEMPBufferEntry.SetCurrentKey("Proposal No.", "Currency Code", "Posting Date", "Line No.");
        rTEMPBufferEntry.SetRange("Currency Code", pCurrencyCode);
        if rTEMPBufferEntry.FindSet() then
            repeat
                pvEntryNoList.Add(rTEMPBufferEntry."Ledger Entry No.");
            until rTEMPBufferEntry.Next() = 0;
        rTEMPBufferEntry.Reset();
    end;

    local procedure fGetAvailable(pLedgerEntryNo: Integer): Decimal
    begin
        if not rTEMPBufferEntry.Get(0, pLedgerEntryNo) then
            exit(0);

        exit(fBufferAvailable());
    end;

    local procedure fBufferAvailable(): Decimal
    begin
        exit(rTEMPBufferEntry."Remaining Amount at Proposal" - rTEMPBufferEntry."Amount to Apply");
    end;

    local procedure fReserveAmount(pLedgerEntryNo: Integer; pAmount: Decimal)
    begin
        if not rTEMPBufferEntry.Get(0, pLedgerEntryNo) then
            exit;

        rTEMPBufferEntry."Amount to Apply" += pAmount;
        rTEMPBufferEntry.Modify(false);
    end;

    local procedure fCopyBufferEntry(pLedgerEntryNo: Integer; var pTEMPEntryCopy: Record "LAA_LedgerApplProposalLine" temporary): Boolean
    begin
        pTEMPEntryCopy.Reset();
        pTEMPEntryCopy.DeleteAll(false);

        if not rTEMPBufferEntry.Get(0, pLedgerEntryNo) then
            exit(false);

        pTEMPEntryCopy := rTEMPBufferEntry;
        pTEMPEntryCopy."Amount to Apply" := 0;
        pTEMPEntryCopy.Insert(false);

        exit(true);
    end;

    local procedure fGetCandidateType(pLedgerEntryNo: Integer): Enum "LAA_AICandidateType"
    var
        vlCandidateType: Enum "LAA_AICandidateType";
    begin
        if rTEMPBufferEntry.Get(0, pLedgerEntryNo) then
            vlCandidateType := rTEMPBufferEntry."AI Candidate Type";

        exit(vlCandidateType);
    end;

    local procedure fGetPostingDate(pLedgerEntryNo: Integer): Date
    begin
        if rTEMPBufferEntry.Get(0, pLedgerEntryNo) then
            exit(rTEMPBufferEntry."Posting Date");

        exit(0D);
    end;

    #endregion

    #region Calculation helpers

    /// <summary>
    /// Chronology rule: when no directional reference exists, the most recent
    /// movement takes the applying role because it normally consumes a previously
    /// existing open balance.
    /// </summary>
    local procedure fGetApplyingRole(pEntryNo1: Integer; pEntryNo2: Integer; var pvApplyingEntryNo: Integer; var pvAppliedEntryNo: Integer)
    begin
        if fIsOlderThan(pEntryNo2, pEntryNo1) then begin
            pvApplyingEntryNo := pEntryNo1;
            pvAppliedEntryNo := pEntryNo2;
            exit;
        end;

        pvApplyingEntryNo := pEntryNo2;
        pvAppliedEntryNo := pEntryNo1;
    end;

    local procedure fIsOlderThan(pEntryNo: Integer; pReferenceEntryNo: Integer): Boolean
    var
        vlDate: Date;
        vlReferenceDate: Date;
    begin
        vlDate := fGetPostingDate(pEntryNo);
        vlReferenceDate := fGetPostingDate(pReferenceEntryNo);

        if vlDate <> vlReferenceDate then
            exit(vlDate < vlReferenceDate);

        exit(pEntryNo < pReferenceEntryNo);
    end;

    local procedure fIsMostRecent(pEntryNo: Integer; var pvOtherEntryNos: List of [Integer]): Boolean
    var
        vlOtherEntryNo: Integer;
    begin
        foreach vlOtherEntryNo in pvOtherEntryNos do
            if not fIsOlderThan(vlOtherEntryNo, pEntryNo) then
                exit(false);

        exit(true);
    end;

    local procedure fIsWithinDateLimit(pEntryNo1: Integer; pEntryNo2: Integer): Boolean
    var
        vlDateDifference: Integer;
    begin
        if rSetup."Max. Match Date Difference" <= 0 then
            exit(true);

        vlDateDifference := Abs(fGetPostingDate(pEntryNo1) - fGetPostingDate(pEntryNo2));

        exit(vlDateDifference <= rSetup."Max. Match Date Difference");
    end;

    /// <summary>
    /// Amount that may be allocated to a counterpart, signed like the counterpart
    /// and never larger than the capacity that is left in the group.
    /// </summary>
    local procedure fAllocationAmount(pCapacity: Decimal; pCounterAvailable: Decimal): Decimal
    begin
        if Abs(pCounterAvailable) <= Abs(pCapacity) then
            exit(pCounterAvailable);

        exit(clProposalMgt.fSignOf(pCounterAvailable) * Abs(pCapacity));
    end;

    local procedure fSameSign(pAmount1: Decimal; pAmount2: Decimal): Boolean
    begin
        exit(clProposalMgt.fSameSign(pAmount1, pAmount2));
    end;

    #endregion
}
