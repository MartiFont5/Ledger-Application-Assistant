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
/// Orchestrates one AI case: it builds the compact JSON the model receives,
/// starts a single capability execution for it and reports back whether a group
/// was really created.
///
/// It is the only place in the extension that knows the AI Integration framework
/// exists as a runtime. Everything else either configures it (the capability and
/// the agent) or is called back by it (the tool). The matching engine only asks
/// this codeunit two questions: is AI matching available, and did this case end
/// in a group.
///
/// The codeunit has a TableNo so that one case can be executed through
/// Codeunit.Run. That isolation is the whole error strategy of the AI layer: a
/// framework that is not configured, a model that is unreachable, a tool call
/// that is rejected - none of them may abort the generation of the proposal. The
/// deterministic result the user would have got without AI is always produced.
/// </summary>
codeunit 87506 "LAA_AIMatchMgt"
{
    Access = Internal;
    TableNo = "LAA_LedgerApplProposalHeader";

    var
        clContext: Codeunit "LAA_AIMatchContext";
        clProposalMgt: Codeunit "LAA_LedgerApplProposalMgt";

    trigger OnRun()
    begin
        fExecuteCase(Rec);
    end;

    #region Registration

    /// <summary>
    /// Registers the capability, its prompt, the tool, the agent and the workflow.
    ///
    /// This has to exist because the framework raises OnInstallCapabilities and
    /// OnInstallAgents only from its own install and upgrade triggers, and those
    /// do not run when a dependent extension is installed. An extension that only
    /// subscribes to them is therefore never registered at all: no capability, no
    /// agent, no workflow, and every AI case fails silently.
    ///
    /// So the subscribers stay - they keep this extension in step when the
    /// framework itself is reinstalled or upgraded - and this procedure calls the
    /// same two installers from our own install, our own upgrade and the setup
    /// page. Everything it does is idempotent.
    ///
    /// Order matters: the capability first, because the agent's capability
    /// assignment and the workflow rows have table relations to it.
    /// </summary>
    internal procedure fRegisterAIConfiguration()
    var
        clCapability: Codeunit "LAA_AIMatchCapability";
        clAgent: Codeunit "LAA_AIMatchAgent";
    begin
        clCapability.InstallCapability();
        clAgent.Install();
    end;

    #endregion

    #region Availability

    /// <summary>
    /// Workflow that binds the single capability of the assistant. It is selected
    /// explicitly on every execution, so the framework never routes this agent.
    /// </summary>
    internal procedure fWorkflowId(): Code[50]
    begin
        exit('LAA_AI_MATCH');
    end;

    /// <summary>
    /// True when a case may be sent to the model at all: the feature is switched
    /// on in the setup of the assistant, the framework is enabled, and the agent
    /// exists and is enabled. Nothing here fails: a missing configuration simply
    /// means the deterministic pipeline runs as before.
    /// </summary>
    internal procedure fIsAIMatchingEnabled(): Boolean
    var
        rlAIAgent: Record "AI Agent";
        rlAIModelsSetup: Record "AI Models Setup";
        rlSetup: Record "LAA_LedgerApplSetup";
    begin
        rlSetup.fGetSetup();
        if not rlSetup."Enable AI Matching" then
            exit(false);

        if not rlAIModelsSetup.Get() then
            exit(false);
        if not rlAIModelsSetup.Enabled then
            exit(false);

        if not rlAIAgent.Get(Enum::"AI Agent"::"LAA_LedgerApplicationAssistant") then
            exit(false);

        exit(rlAIAgent.Enabled);
    end;

    /// <summary>
    /// The candidate types phase 1 sends to the model. Not Needed is already
    /// resolved and Unclassified Residual carries no evidence to reason about, so
    /// both go straight to the residual FIFO as before.
    /// </summary>
    internal procedure fIsInScope(pCandidateType: Enum "LAA_AICandidateType"): Boolean
    begin
        exit(pCandidateType in [Enum::"LAA_AICandidateType"::"Multiple Exact Matches",
                               Enum::"LAA_AICandidateType"::"Partial Match",
                               Enum::"LAA_AICandidateType"::"Textual Reference"]);
    end;

    /// <summary>
    /// Confidence of an AI group. It is system defined and comes from the setup:
    /// the model is never asked how sure it is.
    /// </summary>
    internal procedure fGetConfidence(pCandidateType: Enum "LAA_AICandidateType"): Enum "LAA_Confidence"
    var
        rlSetup: Record "LAA_LedgerApplSetup";
    begin
        rlSetup.fGetSetup();

        case pCandidateType of
            Enum::"LAA_AICandidateType"::"Multiple Exact Matches":
                exit(rlSetup."AI Multiple Exact Confidence");
            Enum::"LAA_AICandidateType"::"Textual Reference":
                exit(rlSetup."AI Textual Ref. Confidence");
        end;

        exit(rlSetup."AI Partial Confidence");
    end;

    #endregion

    #region Case execution

    /// <summary>
    /// Runs one case end to end and returns the reservations the matching engine
    /// must apply to its buffer.
    ///
    /// Success is not taken from the model or from the tool: the group is looked
    /// up in the proposal afterwards. If anything rolled the tool call back, the
    /// group is simply not there and the case counts as unresolved, which leaves
    /// the movements to the residual FIFO exactly as before.
    /// </summary>
    internal procedure fRunCase(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pCandidateType: Enum "LAA_AICandidateType"; pApplyingEntryNo: Integer; var pTEMPCaseEntry: Record "LAA_LedgerApplProposalLine" temporary; var pvAppliedEntryNos: List of [Integer]; var pvAppliedAmounts: List of [Decimal]): Boolean
    var
        clAIMatchRunner: Codeunit "LAA_AIMatchMgt";
        vlGroupCreated: Boolean;
    begin
        Clear(pvAppliedEntryNos);
        Clear(pvAppliedAmounts);

        clContext.fSetCase(prProposalHeader."No.", pCandidateType, pApplyingEntryNo, pTEMPCaseEntry);
        if not clContext.fIsActive() then begin
            clContext.fClear();
            exit(false);
        end;

        // Deliberate: calling a codeunit for its return value, and calling out over
        // HTTP, both require a clean transaction. The groups produced so far are
        // final at this point, so committing them costs nothing and the AI pass
        // runs after every deterministic level and before the residual FIFO.
        Commit();

        if not clAIMatchRunner.Run(prProposalHeader) then
            ClearLastError();

        vlGroupCreated := clContext.fIsGroupCreated() and fGroupExists(prProposalHeader, clContext.fGetGroupNo());
        if vlGroupCreated then
            clContext.fGetReservations(pvAppliedEntryNos, pvAppliedAmounts);

        clContext.fClear();

        exit(vlGroupCreated);
    end;

    /// <summary>
    /// One case, one execution, zero or one tool call. Everything the model needs
    /// travels as the execution input; everything the tool needs stays in
    /// LAA_AIMatchContext.
    /// </summary>
    local procedure fExecuteCase(var prProposalHeader: Record "LAA_LedgerApplProposalHeader")
    var
        rlAIExecution: Record "AI Execution";
        clProcessExecution: Codeunit "AI Process Execution";
    begin
        rlAIExecution := clProcessExecution.CreateWorkflowExecution(fWorkflowId(), prProposalHeader.RecordId());
        rlAIExecution.SetUserInput(fBuildCaseJson());

        if not clProcessExecution.RunExecutionInForeground(rlAIExecution) then
            ClearLastError();
    end;

    local procedure fGroupExists(var prProposalHeader: Record "LAA_LedgerApplProposalHeader"; pGroupNo: Integer): Boolean
    var
        rlApplyingLine: Record "LAA_LedgerApplProposalLine";
    begin
        if pGroupNo = 0 then
            exit(false);

        exit(clProposalMgt.fFindApplyingLine(prProposalHeader."No.", pGroupNo, rlApplyingLine));
    end;

    #endregion

    #region Case input

    /// <summary>
    /// The AI input. It is deliberately small: the applying movement, the
    /// candidates the deterministic engine preselected, and only those fields
    /// that carry semantic evidence. Amounts travel as positive magnitudes
    /// because the signs belong to the ledger, not to the model.
    /// </summary>
    internal procedure fBuildCaseJson(): Text
    var
        rlTEMPCaseEntry: Record "LAA_LedgerApplProposalLine" temporary;
        vlCaseJson: JsonObject;
        vlCandidatesArray: JsonArray;
        vlApplyingEntryNo: Integer;
        vlCaseText: Text;
    begin
        clContext.fCopyCaseEntries(rlTEMPCaseEntry);
        vlApplyingEntryNo := clContext.fGetApplyingEntryNo();

        vlCaseJson.Add('candidateType', Format(clContext.fGetCandidateType(), 0, 9));

        if rlTEMPCaseEntry.Get(0, vlApplyingEntryNo) then
            vlCaseJson.Add('applyingMovement', fBuildMovementJson(rlTEMPCaseEntry));

        rlTEMPCaseEntry.Reset();
        rlTEMPCaseEntry.SetCurrentKey("Proposal No.", "Currency Code", "Posting Date", "Line No.");
        rlTEMPCaseEntry.SetFilter("Ledger Entry No.", '<>%1', vlApplyingEntryNo);
        if rlTEMPCaseEntry.FindSet() then
            repeat
                vlCandidatesArray.Add(fBuildMovementJson(rlTEMPCaseEntry));
            until rlTEMPCaseEntry.Next() = 0;

        vlCaseJson.Add('candidateMovements', vlCandidatesArray);
        vlCaseJson.WriteTo(vlCaseText);

        exit(vlCaseText);
    end;

    local procedure fBuildMovementJson(var prTEMPCaseEntry: Record "LAA_LedgerApplProposalLine" temporary): JsonObject
    var
        vlMovementJson: JsonObject;
    begin
        vlMovementJson.Add('entryNo', prTEMPCaseEntry."Ledger Entry No.");
        vlMovementJson.Add('documentType', Format(prTEMPCaseEntry."Document Type", 0, 9));
        vlMovementJson.Add('documentNo', prTEMPCaseEntry."Document No.");
        vlMovementJson.Add('description', prTEMPCaseEntry.Description);
        vlMovementJson.Add('postingDate', fFormatDate(prTEMPCaseEntry."Posting Date"));
        vlMovementJson.Add('dueDate', fFormatDate(prTEMPCaseEntry."Due Date"));
        vlMovementJson.Add('currencyCode', prTEMPCaseEntry."Currency Code");
        vlMovementJson.Add('availableAmount', Abs(prTEMPCaseEntry.fBufferAvailableAmount()));

        // Reference fields only when they carry something. They are the same
        // references the deterministic engine already scans, and an empty one is
        // context the model does not need.
        if prTEMPCaseEntry."External Document No." <> '' then
            vlMovementJson.Add('externalDocumentNo', prTEMPCaseEntry."External Document No.");
        if prTEMPCaseEntry."Payment Reference" <> '' then
            vlMovementJson.Add('paymentReference', prTEMPCaseEntry."Payment Reference");
        if prTEMPCaseEntry."Applies-to Doc. No." <> '' then
            vlMovementJson.Add('appliesToDocNo', prTEMPCaseEntry."Applies-to Doc. No.");

        exit(vlMovementJson);
    end;

    local procedure fFormatDate(pDate: Date): Text
    begin
        if pDate = 0D then
            exit('');

        exit(Format(pDate, 0, 9));
    end;

    #endregion
}
*/
