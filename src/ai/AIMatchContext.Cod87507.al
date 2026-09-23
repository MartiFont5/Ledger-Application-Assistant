/// <summary>
/// The AI case, held in memory for exactly one capability execution.
///
/// Nothing about an AI case is persisted: there is no AI case table, no AI result
/// table and no AI history. The case lives here, between the moment the matching
/// engine builds it and the moment LAA_AIMatchTool is called back by the model,
/// and it is cleared immediately afterwards.
///
/// This works because the agent runs with Direct Tool Execution and the tool is
/// Agent scoped, so the framework executes the tool inline, in the same session
/// and call stack as the execution that was started by LAA_AIMatchMgt. A single
/// instance codeunit therefore reaches the tool intact. If either flag were
/// changed on the agent or on the tool the framework would dispatch the call to
/// another session and this context would arrive empty, which the tool detects
/// and reports instead of guessing.
///
/// The case is also the allowed candidate set: the tool accepts a ledger entry
/// only if the same entry was part of the input handed to the model.
/// </summary>
codeunit 87507 "LAA_AIMatchContext"
{
    Access = Internal;
    SingleInstance = true;

    var
        rTEMPCaseEntry: Record "LAA_LedgerApplProposalLine" temporary;
        vReservedAmounts: List of [Decimal];
        vReservedEntryNos: List of [Integer];
        vCandidateType: Enum "LAA_AICandidateType";
        vActive: Boolean;
        vApplyingEntryNo: Integer;
        vGroupCreated: Boolean;
        vGroupNo: Integer;
        vProposalNo: Integer;

    #region Case lifecycle

    /// <summary>
    /// Forgets the current case. Called before and after every execution, so a
    /// case can never leak into the next one or into an unrelated execution.
    /// </summary>
    internal procedure fClear()
    begin
        rTEMPCaseEntry.Reset();
        rTEMPCaseEntry.DeleteAll(false);

        Clear(vReservedEntryNos);
        Clear(vReservedAmounts);
        Clear(vCandidateType);
        vActive := false;
        vApplyingEntryNo := 0;
        vGroupCreated := false;
        vGroupNo := 0;
        vProposalNo := 0;
    end;

    /// <summary>
    /// Stores the case that is about to be sent to the model. The entries arrive
    /// as copies of the matching buffer, so they keep the buffer semantics:
    /// "Line No." is the ledger entry number and the available amount is the
    /// difference between the remaining amount and the amount already reserved.
    /// </summary>
    internal procedure fSetCase(pProposalNo: Integer; pCandidateType: Enum "LAA_AICandidateType"; pApplyingEntryNo: Integer; var pTEMPCaseEntry: Record "LAA_LedgerApplProposalLine" temporary)
    begin
        fClear();

        vProposalNo := pProposalNo;
        vCandidateType := pCandidateType;
        vApplyingEntryNo := pApplyingEntryNo;

        pTEMPCaseEntry.Reset();
        if pTEMPCaseEntry.FindSet() then
            repeat
                rTEMPCaseEntry := pTEMPCaseEntry;
                rTEMPCaseEntry.Insert(false);
            until pTEMPCaseEntry.Next() = 0;

        vActive := rTEMPCaseEntry.Get(0, pApplyingEntryNo);
    end;

    internal procedure fIsActive(): Boolean
    begin
        exit(vActive);
    end;

    internal procedure fGetProposalNo(): Integer
    begin
        exit(vProposalNo);
    end;

    internal procedure fGetApplyingEntryNo(): Integer
    begin
        exit(vApplyingEntryNo);
    end;

    internal procedure fGetCandidateType(): Enum "LAA_AICandidateType"
    begin
        exit(vCandidateType);
    end;

    #endregion

    #region Case content

    /// <summary>
    /// Hands the caller its own copy of the case entries, applying entry included,
    /// ordered as the matching buffer orders them.
    /// </summary>
    internal procedure fCopyCaseEntries(var pTEMPTargetEntry: Record "LAA_LedgerApplProposalLine" temporary)
    begin
        pTEMPTargetEntry.Reset();
        pTEMPTargetEntry.DeleteAll(false);

        rTEMPCaseEntry.Reset();
        rTEMPCaseEntry.SetCurrentKey("Proposal No.", "Currency Code", "Posting Date", "Line No.");
        if rTEMPCaseEntry.FindSet() then
            repeat
                pTEMPTargetEntry := rTEMPCaseEntry;
                pTEMPTargetEntry.Insert(false);
            until rTEMPCaseEntry.Next() = 0;
        rTEMPCaseEntry.Reset();
    end;

    /// <summary>
    /// True only for a ledger entry that was part of the candidate list shown to
    /// the model. The applying entry is deliberately excluded: the model may not
    /// apply the applying movement to itself.
    /// </summary>
    internal procedure fIsAllowedCandidate(pLedgerEntryNo: Integer): Boolean
    begin
        if pLedgerEntryNo = vApplyingEntryNo then
            exit(false);

        exit(rTEMPCaseEntry.Get(0, pLedgerEntryNo));
    end;

    /// <summary>
    /// Copies one case entry into a single record temporary buffer shaped the way
    /// LAA_LedgerApplProposalMgt expects it, with the reserved amount zeroed.
    /// </summary>
    internal procedure fGetCaseEntry(pLedgerEntryNo: Integer; var pTEMPEntryCopy: Record "LAA_LedgerApplProposalLine" temporary): Boolean
    begin
        pTEMPEntryCopy.Reset();
        pTEMPEntryCopy.DeleteAll(false);

        if not rTEMPCaseEntry.Get(0, pLedgerEntryNo) then
            exit(false);

        pTEMPEntryCopy := rTEMPCaseEntry;
        pTEMPEntryCopy."Amount to Apply" := 0;
        pTEMPEntryCopy.Insert(false);

        exit(true);
    end;

    /// <summary>
    /// Signed amount of a case entry that was still free when the case was built.
    /// It is a first filter only: LAA_LedgerApplProposalMgt revalidates every
    /// amount against the live ledger before a line is inserted.
    /// </summary>
    internal procedure fGetAvailableAmount(pLedgerEntryNo: Integer): Decimal
    begin
        if not rTEMPCaseEntry.Get(0, pLedgerEntryNo) then
            exit(0);

        exit(rTEMPCaseEntry.fBufferAvailableAmount());
    end;

    #endregion

    #region Case result

    /// <summary>
    /// Records what the tool actually committed, so that the matching engine can
    /// reserve the same amounts on its buffer. Without this the buffer would
    /// still show the amounts as free and the residual FIFO would allocate them a
    /// second time.
    /// </summary>
    internal procedure fRegisterResult(pGroupNo: Integer; var pvEntryNos: List of [Integer]; var pvAmounts: List of [Decimal])
    begin
        vGroupNo := pGroupNo;
        vReservedEntryNos := pvEntryNos;
        vReservedAmounts := pvAmounts;
        vGroupCreated := true;
    end;

    internal procedure fIsGroupCreated(): Boolean
    begin
        exit(vGroupCreated);
    end;

    internal procedure fGetGroupNo(): Integer
    begin
        exit(vGroupNo);
    end;

    internal procedure fGetReservations(var pvEntryNos: List of [Integer]; var pvAmounts: List of [Decimal])
    begin
        pvEntryNos := vReservedEntryNos;
        pvAmounts := vReservedAmounts;
    end;

    #endregion
}
