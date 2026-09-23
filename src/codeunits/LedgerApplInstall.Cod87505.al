codeunit 87505 "LAA_LedgerApplInstall"
{
    Subtype = Install;
    Access = Internal;

    trigger OnInstallAppPerCompany()
    begin
        fInitializeSetup();
        fRegisterAIConfiguration();
    end;

    /// <summary>
    /// Ensures that the singleton setup exists. Safe to call more than once:
    /// nothing is overwritten.
    /// </summary>
    internal procedure fInitializeSetup()
    var
        rlSetup: Record "LAA_LedgerApplSetup";
    begin
        rlSetup.fGetSetup();
    end;

    /// <summary>
    /// Registers the AI agent, capability, prompt, tool and workflow in the agent
    /// framework. Shared by the install trigger, the upgrade codeunit and the
    /// setup page, because the framework only raises its own installation events
    /// when the framework itself is installed or upgraded.
    /// </summary>
    internal procedure fRegisterAIConfiguration()
    var
        clAIMatchMgt: Codeunit "LAA_AIMatchMgt";
    begin
        clAIMatchMgt.fRegisterAIConfiguration();
    end;
}
