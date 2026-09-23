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
/// The single tool of the capability. The framework derives both the tool code
/// and the model-facing function name from this member name, so renaming it
/// renames the tool for every installed company.
/// </summary>
enumextension 87519 "LAA_AIToolImplExt" extends "AI Tool Implementation"
{
    value(87500; "LAA_ApplyAIMatch")
    {
        Caption = 'Apply AI Match', Comment = 'ESP="Aplicar conciliacion de IA"';
        Implementation = "AI Function" = "LAA_AIMatchTool";
    }
}
*/
