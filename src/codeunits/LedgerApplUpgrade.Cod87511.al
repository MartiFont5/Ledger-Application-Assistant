/// <summary>
/// Reapplies the idempotent configuration on every upgrade of this extension.
///
/// It exists for the AI layer. The install trigger only runs on a first install,
/// and the agent framework raises its own installation events only when the
/// framework itself is installed or upgraded - never when a dependent extension
/// is. Without this codeunit, an environment that already had version 28.0.1.0
/// would upgrade to the AI version and still have no agent, no capability and no
/// workflow.
/// </summary>
codeunit 87511 "LAA_LedgerApplUpgrade"
{
    Subtype = Upgrade;
    Access = Internal;

    trigger OnUpgradePerCompany()
    var
        clInstall: Codeunit "LAA_LedgerApplInstall";
    begin
        clInstall.fInitializeSetup();
        clInstall.fRegisterAIConfiguration();
    end;
}
