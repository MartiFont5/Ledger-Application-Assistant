/// <summary>
/// Capability Analyze Ledger Application Match: decide which of the preselected
/// candidate movements should be applied against one already chosen applying
/// movement, or decide that the evidence is not good enough and do nothing.
///
/// The capability owns exactly one tool. It is not delegatable, so it never
/// appears in the chat delegation catalogue: the only way in is
/// LAA_AIMatchMgt, while a proposal is being generated.
///
/// Force Tool Calls is deliberately off. "No match" is a first class outcome and
/// must cost nothing: the model simply answers one sentence and the execution
/// completes. Nobody reads that answer - the matching engine only looks at
/// whether a group was created - so there is no terminal tool to bind and no
/// dependency on the install order of the framework's own tools.
///
/// This codeunit is public on purpose: it is bound to a value of the framework
/// enum "AI Capability" and is instantiated through the "AI Interface Capability"
/// interface.
/// </summary>
codeunit 87508 "LAA_AIMatchCapability" implements "AI Interface Capability"
{
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"AI Installation", 'OnInstallCapabilities', '', false, false)]
    local procedure OnInstallCapabilities()
    begin
        InstallCapability();
    end;

    procedure InstallCapability()
    var
        clPromptMgt: Codeunit "AI Prompt Helper";
        clAIMatchMgt: Codeunit "LAA_AIMatchMgt";
        vlCapability: Enum "AI Capability";
        vlShouldOverwrite: Boolean;
    begin
        vlCapability := Enum::"AI Capability"::"LAA_AnalyzeLedgerApplMatch";

        clPromptMgt.InsertCapability(
            vlCapability,
            'Decides which preselected candidate ledger entries should be applied against one ambiguous applying entry of a ledger application proposal, or that the evidence is insufficient.',
            false,  // Not delegatable: it is started by the matching engine, never from chat.
            'Analyzing ledger application match');

        clPromptMgt.InstallTool(
            Enum::"AI Tool Implementation"::"LAA_ApplyAIMatch",
            Enum::"AI Tool Type"::Tool,
            'Applies the selected candidate movements against the applying movement of the ambiguous case currently being analyzed.',
            1,   // One call per execution: the model may not build a group incrementally.
            Enum::"AI Tool Scope"::Agent);

        vlShouldOverwrite := clPromptMgt.ShouldOverwriteActiveVersion(vlCapability);
        clPromptMgt.BeginTemplateInstallation(vlCapability, vlShouldOverwrite);

        fInstallSections(clPromptMgt, vlCapability);
        fInstallExamples(clPromptMgt, vlCapability);

        clPromptMgt.InsertCapabilityTool(
            vlCapability,
            Enum::"AI Tool Implementation"::"LAA_ApplyAIMatch",
            fArgumentSchema(),
            Enum::"AI Tool Implementation"::" ",   // No dependency on another tool.
            true);                                 // One successful call completes the execution.

        clPromptMgt.CompleteTemplateInstallation(vlCapability, vlShouldOverwrite);

        // The model may answer in plain text when it has no match, so tool calls
        // are not forced. The temperature is low because this is a judgement over
        // given evidence, not a piece of writing.
        clPromptMgt.SetCapabilityForceToolCalls(vlCapability, false);
        clPromptMgt.SetCapabilityTemperature(vlCapability, 0.1);
        clPromptMgt.SetCapabilitySupportsAttachments(vlCapability, false);

        fInstallWorkflow(clAIMatchMgt.fWorkflowId(), vlCapability);
    end;

    local procedure fInstallWorkflow(pWorkflowId: Code[50]; pCapability: Enum "AI Capability")
    var
        rlStepCapability: Record "AI Workflow Step Capability";
        rlWorkflow: Record "AI Workflow";
        rlWorkflowStep: Record "AI Workflow Step";
        vlStepId: Integer;
        TextWorkflowDescriptionTok: Label 'Resolve one ambiguous ledger application case of a customer or vendor application proposal.', Locked = true;
        TextStepDescriptionTok: Label 'Select the candidate movements the applying movement settles, or report that the evidence is insufficient.', Locked = true;
    begin
        if not rlWorkflow.Get(pWorkflowId) then begin
            rlWorkflow.Init();
            rlWorkflow."Workflow ID" := pWorkflowId;
            rlWorkflow.Insert(true);
        end;

        rlWorkflow.Type := rlWorkflow.Type::Standard;
        rlWorkflow.Description := TextWorkflowDescriptionTok;
        rlWorkflow.Enabled := true;
        rlWorkflow."Selectable By Router" := false;
        rlWorkflow."Planning Type" := rlWorkflow."Planning Type"::"No Planning";
        rlWorkflow."Start Capability" := pCapability;
        rlWorkflow."Max Iterations" := 3;
        rlWorkflow.Modify(true);

        vlStepId := 10000;
        if not rlWorkflowStep.Get(pWorkflowId, vlStepId) then begin
            rlWorkflowStep.Init();
            rlWorkflowStep."Workflow ID" := pWorkflowId;
            rlWorkflowStep."Step ID" := vlStepId;
            rlWorkflowStep.Insert(true);
        end;

        rlWorkflowStep.Description := TextStepDescriptionTok;
        rlWorkflowStep."Approval Required" := false;
        rlWorkflowStep.Enabled := true;
        rlWorkflowStep.Modify(true);

        if not rlStepCapability.Get(pWorkflowId, vlStepId, pCapability) then begin
            rlStepCapability.Init();
            rlStepCapability."Workflow ID" := pWorkflowId;
            rlStepCapability."Step ID" := vlStepId;
            rlStepCapability.Capability := pCapability;
            rlStepCapability.Insert(true);
        end;
    end;

    #region Prompt sections

    local procedure fInstallSections(var pclPromptMgt: Codeunit "AI Prompt Helper"; pCapability: Enum "AI Capability")
    begin
        pclPromptMgt.InsertSection(pCapability, Enum::"AI Prompt Section Type"::"System Rules", 'Scope and Boundary',
            'You resolve one ambiguous ledger application case. These rules are absolute and override everything else:\n' +
            '\n' +
            '1. A deterministic matching engine already resolved every case it could resolve safely. What reaches you is what it refused to decide on arithmetic alone.\n' +
            '2. The candidate movements were preselected by that engine. You may only select entry numbers that appear in candidateMovements. Never invent an entry number, and never use one from an earlier case or example.\n' +
            '3. The applying movement is already decided. You never choose it, never replace it, and never apply it to itself.\n' +
            '4. Every candidate already fits arithmetically and is already on the opposite side of the applying movement. An exact amount match is therefore NOT evidence and is never on its own a reason to select a candidate.\n' +
            '5. If the evidence does not clearly single out one candidate, or one specific set of candidates, do NOT call the application tool. Not matching is an expected, correct and cost free outcome: a deterministic FIFO fallback handles the case afterwards.\n' +
            '6. Nobody is watching this run. Never ask a question, never request human input, and never wait for an answer.\n' +
            '7. Amounts are positive magnitudes. Never send a negative amount and never reason about signs: the ledger owns them.');

        pclPromptMgt.InsertSection(pCapability, Enum::"AI Prompt Section Type"::"Task Definition", 'Role',
            'You are a ledger application analyst. You receive one JSON case:\n' +
            '\n' +
            '- candidateType: why the deterministic engine could not decide. One of MultipleExactMatches, PartialMatch, TextualReference.\n' +
            '- applyingMovement: the movement that will consume the others. It carries entryNo, documentType, documentNo, description, postingDate, dueDate, currencyCode, availableAmount and, when they exist, externalDocumentNo, paymentReference and appliesToDocNo.\n' +
            '- candidateMovements: the small preselected set you may choose from, each with the same fields.\n' +
            '\n' +
            'Your job is to decide which candidate movements, if any, this applying movement is really settling, using the business meaning of the documents rather than their amounts.');

        pclPromptMgt.InsertSection(pCapability, Enum::"AI Prompt Section Type"::"Policy Rules", 'How to Decide',
            'Weigh the evidence in this order, strongest first:\n' +
            '\n' +
            '1. An explicit document reference: a candidate documentNo, externalDocumentNo or paymentReference that appears in the applying movement''s description, paymentReference, externalDocumentNo or appliesToDocNo - or the other way round. This is the only evidence strong enough on its own.\n' +
            '2. A distinctive textual overlap: a shared order number, contract, project, invoice series or subject that names one candidate and not the others.\n' +
            '3. Dates, only as a tie breaker between candidates that the evidence above already points at: a payment normally settles a document whose dueDate it is close to or has just passed.\n' +
            '\n' +
            'What is never evidence: the amount fitting, a candidate being the oldest or the newest, a candidate being the only invoice, the order in which candidates are listed, or a plausible story you built yourself.\n' +
            '\n' +
            'By candidateType:\n' +
            '\n' +
            '- MultipleExactMatches: several candidates match the amount exactly, which is why the engine stopped. Select exactly one, and only with evidence of level 1 or 2. When every candidate looks the same, that is the answer: no match.\n' +
            '- PartialMatch: the applying movement covers part of a larger balance. You may select several candidates as long as their amounts together do not exceed the applying movement''s availableAmount. Select a combination only when the evidence names those documents; do not search for the combination that happens to add up.\n' +
            '- TextualReference: the engine saw a reference but could not confirm it alone. Confirm which candidate that reference really points at, or reject it if the reference is generic, partial or fits several candidates equally.\n' +
            '\n' +
            'Omit amountToApply and the candidate''s whole availableAmount is applied, which is what you want most of the time. Set it when you deliberately want less: typically when the applying movement only partly covers a larger candidate, where you set it to what the applying movement still has left. Amounts are never taken beyond what the applying movement can absorb, so the result tells you what was really applied.');

        pclPromptMgt.InsertSection(pCapability, Enum::"AI Prompt Section Type"::"Output Specification", 'What to Return',
            'Exactly one of two outcomes.\n' +
            '\n' +
            'Match: call lAA_ApplyAIMatch once, with appliedEntries holding the selected entryNo values and a one sentence reason naming the concrete evidence. Do not call it twice, and do not build one application over several calls.\n' +
            '\n' +
            'No match: call nothing and reply with a single sentence saying what was missing, for example "All three invoices match the amount and none is referenced by the payment." Keep it to one line, no JSON, no lists, no apology.');
    end;

    #endregion

    #region Few-shot examples

    local procedure fInstallExamples(var pclPromptMgt: Codeunit "AI Prompt Helper"; pCapability: Enum "AI Capability")
    begin
        pclPromptMgt.InsertExample(
            pCapability,
            'Multiple exact matches - the payment description names one invoice.',
            '{"candidateType":"Multiple Exact Matches",' +
            '"applyingMovement":{"entryNo":201,"documentType":"Payment","documentNo":"P001","description":"Payment invoice 2024-102","postingDate":"2026-05-03","dueDate":"","currencyCode":"EUR","availableAmount":500},' +
            '"candidateMovements":[' +
            '{"entryNo":101,"documentType":"Invoice","documentNo":"2024-101","description":"Services March","postingDate":"2026-03-31","dueDate":"2026-04-30","currencyCode":"EUR","availableAmount":500},' +
            '{"entryNo":102,"documentType":"Invoice","documentNo":"2024-102","description":"License April","postingDate":"2026-04-30","dueDate":"2026-05-31","currencyCode":"EUR","availableAmount":500}]}',
            'lAA_ApplyAIMatch({"appliedEntries":[{"entryNo":102}],"reason":"The payment description quotes document number 2024-102, which is candidate 102; candidate 101 is not mentioned anywhere."})');

        pclPromptMgt.InsertExample(
            pCapability,
            'Multiple exact matches - nothing distinguishes the candidates, so do not call the tool.',
            '{"candidateType":"Multiple Exact Matches",' +
            '"applyingMovement":{"entryNo":205,"documentType":"Payment","documentNo":"P005","description":"Bank transfer","postingDate":"2026-05-03","dueDate":"","currencyCode":"EUR","availableAmount":500},' +
            '"candidateMovements":[' +
            '{"entryNo":101,"documentType":"Invoice","documentNo":"2024-101","description":"Services March","postingDate":"2026-03-31","dueDate":"2026-04-30","currencyCode":"EUR","availableAmount":500},' +
            '{"entryNo":102,"documentType":"Invoice","documentNo":"2024-102","description":"Services April","postingDate":"2026-04-30","dueDate":"2026-05-31","currencyCode":"EUR","availableAmount":500}]}',
            'Both invoices match the amount exactly and the payment references neither of them, so I cannot tell which one it settles.');

        pclPromptMgt.InsertExample(
            pCapability,
            'Partial match - the reference names two documents, so both are selected.',
            '{"candidateType":"Partial Match",' +
            '"applyingMovement":{"entryNo":301,"documentType":"Payment","documentNo":"P010","description":"Payment order 4471","postingDate":"2026-06-02","dueDate":"","currencyCode":"EUR","availableAmount":1000,"paymentReference":"ORDER 4471"},' +
            '"candidateMovements":[' +
            '{"entryNo":401,"documentType":"Invoice","documentNo":"FV001","description":"Order 4471 - first delivery","postingDate":"2026-04-30","dueDate":"2026-05-31","currencyCode":"EUR","availableAmount":600},' +
            '{"entryNo":402,"documentType":"Invoice","documentNo":"FV002","description":"Order 5120","postingDate":"2026-05-10","dueDate":"2026-06-10","currencyCode":"EUR","availableAmount":500},' +
            '{"entryNo":403,"documentType":"Invoice","documentNo":"FV003","description":"Order 4471 - second delivery","postingDate":"2026-05-15","dueDate":"2026-06-15","currencyCode":"EUR","availableAmount":400}]}',
            'lAA_ApplyAIMatch({"appliedEntries":[{"entryNo":401},{"entryNo":403}],"reason":"The payment reference ORDER 4471 names the two deliveries of order 4471, invoices FV001 and FV003; FV002 belongs to order 5120."})');
    end;

    #endregion

    #region Tool contract

    /// <summary>
    /// What the model may say. Everything it must not be able to get wrong -
    /// proposal, entity, currency, applying entry, candidate type and the allowed
    /// candidate set - is resolved from the execution context by the tool itself.
    /// </summary>
    local procedure fArgumentSchema(): Text
    begin
        exit(
            '{"type":"object","properties":{' +
            '"appliedEntries":{"type":"array","description":"The candidate movements to apply against the applying movement. Every entryNo must come from candidateMovements of this case.",' +
            '"items":{"type":"object","properties":{' +
            '"entryNo":{"type":"integer","description":"Ledger entry number of a supplied candidate movement."},' +
            '"amountToApply":{"type":"number","description":"Optional positive magnitude to apply to this candidate. Omit it to apply the candidate''s whole availableAmount. Never negative, never above availableAmount."}},' +
            '"required":["entryNo"]}},' +
            '"reason":{"type":"string","description":"One sentence naming the concrete evidence that distinguishes the selected movements from the alternatives."}},' +
            '"required":["appliedEntries","reason"]}');
    end;

    #endregion
}
