codeunit 87505 "LAA_LedgerApplInstall"
{
    Subtype = Install;
    Access = Internal;

    trigger OnInstallAppPerCompany()
    begin
        fInitializeSetup();
        // Disabled in the no-AI variant: there is no agent framework to register into.
        // fRegisterAIConfiguration();
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

    // ========================================================================
    // DISABLED IN THE NO-AI VARIANT OF THIS EXTENSION.
    //
    // fRegisterAIConfiguration registered the agent, capability, prompt, tool
    // and workflow in the Deloitte "AI Integration" framework, which this
    // variant does not declare as a dependency. Its only callers - the install
    // trigger above, LAA_LedgerApplUpgrade and the setup page action - are
    // commented out as well. Restore by re-adding the dependency and removing
    // the /* ... */ markers.
    // ========================================================================
    /*
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
    */
}
