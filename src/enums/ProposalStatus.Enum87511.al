/// <summary>
/// Registration status of a proposal, derived from its application groups.
/// Obsolescence is a separate concept and is not part of this status.
/// </summary>
enum 87511 "LAA_ProposalStatus"
{
    Extensible = false;
    Caption = 'Proposal Status', Comment = 'ESP="Estado de la propuesta"';

    value(0; "Not Registered")
    {
        Caption = 'Not Registered', Comment = 'ESP="No registrada"';
    }
    value(1; "Partially Registered")
    {
        Caption = 'Partially Registered', Comment = 'ESP="Parcialmente registrada"';
    }
    value(2; Registered)
    {
        Caption = 'Registered', Comment = 'ESP="Registrada"';
    }
}
