/// <summary>
/// The agent that owns the ledger application capability, and its single
/// workflow.
///
/// It is a headless specialist: it requires no user input, it is never routed to
/// from the chat, and its workflow is not selectable by a router. The only caller
/// is LAA_AIMatchMgt, which starts the workflow explicitly for one case.
///
/// Direct Tool Execution is switched on here and is load bearing. It makes the
/// framework execute the tool inline, in the session that started the execution,
/// which is what lets LAA_AIMatchContext carry the case from the matching engine
/// to the tool. With it off the call would be dispatched to the self hosted tool
/// web service in another session and every case would be rejected as having no
/// context.
///
/// This codeunit is public on purpose: it is bound to a value of the framework
/// enum "AI Agent" and is instantiated through the "AI Interface Agent"
/// interface.
/// </summary>
codeunit 87509 "LAA_AIMatchAgent" implements "AI Interface Agent"
{
    #region AI Interface Agent

    /// <summary>
    /// Feeds the case JSON that LAA_AIMatchMgt stored on the execution into the
    /// prompt. On the framework's probe call (Execution ID = 0) it offers the
    /// case currently in memory, so one can be replayed from the execution pages
    /// while debugging.
    /// </summary>
    procedure AppendInputExecutionContext(var PromptBuilder: Codeunit "AI Prompt Builder"; Iteration: Record "AI Execution LLM"; SourceRecordID: RecordId)
    var
        rlAIExecution: Record "AI Execution";
        clAIMatchMgt: Codeunit "LAA_AIMatchMgt";
        vlStoredInput: Text;
    begin
        if Iteration."Execution ID" = 0 then begin
            PromptBuilder.SetInputContent(clAIMatchMgt.fBuildCaseJson());
            exit;
        end;

        if rlAIExecution.Get(Iteration."Execution ID") then
            vlStoredInput := rlAIExecution.GetUserInput();

        if vlStoredInput <> '' then
            PromptBuilder.SetInputContent(vlStoredInput);
    end;

    /// <summary>
    /// Never blocks. Deciding that there is no match is a correct answer here, and
    /// there is no human in this run to hand anything over to.
    /// </summary>
    procedure ValidateGating(var Iteration: Record "AI Execution LLM") NeedHuman: Boolean
    begin
        exit(false);
    end;

    /// <summary>
    /// Nothing to do. Whether the case ended in an application group is read from
    /// the proposal itself, not from the model's final answer.
    /// </summary>
    procedure HandleCompletion(var AIExecution: Record "AI Execution"; var FinalIteration: Record "AI Execution LLM")
    begin
    end;

    #endregion

    #region Installation

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"AI Installation", 'OnInstallAgents', '', false, false)]
    local procedure OnInstallAgents()
    begin
        Install();
    end;

    procedure Install()
    var
        rlAIAgent: Record "AI Agent";
        clAIMatchMgt: Codeunit "LAA_AIMatchMgt";
        clPromptMgt: Codeunit "AI Prompt Helper";
        vlAgent: Enum "AI Agent";
    begin
        vlAgent := Enum::"AI Agent"::"LAA_LedgerApplicationAssistant";

        clPromptMgt.InsertAgent(
            vlAgent,
            'Resolves the ambiguous cases of a ledger application proposal that the deterministic engine could not decide.',
            Enum::"AI Agent Category"::Finance,
            3);   // A case is one question: build the prompt, answer, apply. Three iterations is already generous.

        clPromptMgt.SetAgentType(vlAgent, Enum::"AI Agent Type"::Specialist);
        clPromptMgt.SetRequiresUserInput(vlAgent, false);

        clPromptMgt.SetAgentPersona(vlAgent,
            'You assist the Ledger Application Assistant of Microsoft Dynamics 365 Business Central. ' +
            'A deterministic matching engine has already applied every customer and vendor movement it could ' +
            'resolve safely, and hands you only the cases it refused to decide on amounts alone. You read the ' +
            'documents behind the movements and say which ones actually settle each other, or that you cannot tell.');

        clPromptMgt.SetAgentInstructions(vlAgent,
            'Analyze the single ledger application case you are given and either apply the movements the evidence ' +
            'clearly identifies, or state in one sentence that the evidence is insufficient. Never guess: a case ' +
            'you leave alone is handled by a deterministic fallback afterwards.');

        clPromptMgt.InsertCapabilityAgent(vlAgent, Enum::"AI Capability"::"LAA_AnalyzeLedgerApplMatch");

        // See the summary of this codeunit: the tool must run in the session that
        // owns the case. There is no helper for this field, so it is set directly.
        if rlAIAgent.Get(vlAgent) then
            if not rlAIAgent."Direct Tool Execution" then begin
                rlAIAgent."Direct Tool Execution" := true;
                rlAIAgent.Modify(true);
            end;

        fInstallWorkflow(clAIMatchMgt.fWorkflowId(), vlAgent);
    end;

    /// <summary>
    /// The framework publishes no installation event for workflows, so the rows
    /// are written here, idempotently, in the same shape the framework uses for
    /// its own workflows.
    /// </summary>
    local procedure fInstallWorkflow(pWorkflowId: Code[50]; pAgent: Enum "AI Agent")
    var
        rlStepCapability: Record "AI Workflow Step Capability";
        rlWorkflow: Record "AI Workflow";
        rlWorkflowStep: Record "AI Workflow Step";
        vlCapability: Enum "AI Capability";
        vlStepId: Integer;
        WorkflowDescriptionTok: Label 'Resolve one ambiguous ledger application case of a customer or vendor application proposal.', Locked = true;
        StepDescriptionTok: Label 'Select the candidate movements the applying movement settles, or report that the evidence is insufficient.', Locked = true;
    begin
        vlCapability := Enum::"AI Capability"::"LAA_AnalyzeLedgerApplMatch";
        vlStepId := 10000;

        if rlWorkflow.Get(pWorkflowId) then begin
            rlWorkflow.Agent := pAgent;
            rlWorkflow.Type := rlWorkflow.Type::Standard;
            rlWorkflow.Description := WorkflowDescriptionTok;
            rlWorkflow.Enabled := true;
            rlWorkflow."Selectable By Router" := false;
            rlWorkflow."Planning Type" := rlWorkflow."Planning Type"::"No Planning";
            rlWorkflow."Start Capability" := vlCapability;
            rlWorkflow.Modify(true);
        end else begin
            rlWorkflow.Init();
            rlWorkflow."Workflow ID" := pWorkflowId;
            rlWorkflow.Agent := pAgent;
            rlWorkflow.Type := rlWorkflow.Type::Standard;
            rlWorkflow.Description := WorkflowDescriptionTok;
            rlWorkflow.Enabled := true;
            // Not selectable by a router: this workflow is only ever started
            // explicitly, while a proposal is being generated.
            rlWorkflow."Selectable By Router" := false;
            rlWorkflow."Planning Type" := rlWorkflow."Planning Type"::"No Planning";
            rlWorkflow."Start Capability" := vlCapability;
            rlWorkflow.Insert(true);
        end;

        if rlWorkflowStep.Get(pWorkflowId, vlStepId) then begin
            rlWorkflowStep.Description := StepDescriptionTok;
            rlWorkflowStep."Approval Required" := false;
            rlWorkflowStep.Enabled := true;
            rlWorkflowStep.Modify(true);
        end else begin
            rlWorkflowStep.Init();
            rlWorkflowStep."Workflow ID" := pWorkflowId;
            rlWorkflowStep."Step ID" := vlStepId;
            rlWorkflowStep.Description := StepDescriptionTok;
            // No approval: the user reviews and posts the proposal afterwards, so
            // an AI group is a suggestion on a page, never an executed action.
            rlWorkflowStep."Approval Required" := false;
            rlWorkflowStep.Enabled := true;
            rlWorkflowStep.Insert(true);
        end;

        if not rlStepCapability.Get(pWorkflowId, vlStepId, vlCapability) then begin
            rlStepCapability.Init();
            rlStepCapability."Workflow ID" := pWorkflowId;
            rlStepCapability."Step ID" := vlStepId;
            rlStepCapability.Capability := vlCapability;
            rlStepCapability.Insert(true);
        end;
    end;

    #endregion
}
