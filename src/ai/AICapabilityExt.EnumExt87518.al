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
