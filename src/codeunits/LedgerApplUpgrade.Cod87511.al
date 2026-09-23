/// <summary>
/// Reapplies the idempotent configuration on every upgrade of this extension.
///
/// In the AI variant it existed for the AI layer: the install trigger only runs
/// on a first install, and the agent framework raises its own installation
/// events only when the framework itself is installed or upgraded - never when
/// a dependent extension is. In this no-AI variant there is no agent to
/// register, so the codeunit is kept only to guarantee that the singleton setup
/// record exists after an upgrade.
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
        // Disabled in the no-AI variant: see LAA_LedgerApplInstall.
        // clInstall.fRegisterAIConfiguration();
    end;
}
