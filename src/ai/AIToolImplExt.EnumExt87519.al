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
