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
/// The single capability of the Ledger Application Assistant agent: decide which
/// of the preselected candidate movements should be applied against one already
/// chosen applying movement.
/// </summary>
enumextension 87518 "LAA_AICapabilityExt" extends "AI Capability"
{
    value(87500; "LAA_AnalyzeLedgerApplMatch")
    {
        Caption = 'Analyze Ledger Application Match', Comment = 'ESP="Analizar liquidacion de movimientos"';
        Implementation = "AI Interface Capability" = "LAA_AIMatchCapability";
    }
}
*/
