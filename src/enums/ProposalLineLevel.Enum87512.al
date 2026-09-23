/// <summary>
/// Functional role of a proposal line inside its application group.
/// Every group has exactly one applying entry and one or more applied entries.
/// </summary>
enum 87512 "LAA_ProposalLineLevel"
{
    Extensible = false;
    Caption = 'Level', Comment = 'ESP="Nivel"';

    value(0; " ")
    {
        Caption = ' ', Locked = true;
    }
    value(1; "Applying Entry")
    {
        Caption = 'Applying Entry', Comment = 'ESP="Movimiento liquidador"';
    }
    value(2; "Applied Entry")
    {
        Caption = 'Applied Entry', Comment = 'ESP="Movimiento liquidado"';
    }
}
