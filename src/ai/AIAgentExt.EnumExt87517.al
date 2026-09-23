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
/// Registers the Ledger Application Assistant as an agent of the Deloitte AI
/// Integration framework.
///
/// The agent is deliberately headless: it is never selected from the chat, it
/// owns a single capability and a single workflow, and it is started only by
/// LAA_AIMatchMgt while a proposal is being generated.
/// </summary>
enumextension 87517 "LAA_AIAgentExt" extends "AI Agent"
{
    value(87500; "LAA_LedgerApplicationAssistant")
    {
        Caption = 'Ledger Application Assistant', Comment = 'ESP="Asistente de liquidacion de movimientos"';
        Implementation = "AI Interface Agent" = "LAA_AIMatchAgent";
    }
}
*/
