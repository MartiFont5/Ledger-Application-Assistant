/// <summary>
/// Informational matching confidence. It never overrides posting validation
/// and never blocks the user from registering a valid pending group.
/// </summary>
enum 87514 "LAA_Confidence"
{
    Extensible = false;
    Caption = 'Confidence', Comment = 'ESP="Confianza"';

    value(0; " ")
    {
        Caption = ' ', Locked = true;
    }
    value(1; "Very Low")
    {
        Caption = 'Very Low', Comment = 'ESP="Muy baja"';
    }
    value(2; Low)
    {
        Caption = 'Low', Comment = 'ESP="Baja"';
    }
    value(3; Medium)
    {
        Caption = 'Medium', Comment = 'ESP="Media"';
    }
    value(4; High)
    {
        Caption = 'High', Comment = 'ESP="Alta"';
    }
    value(5; "Very High")
    {
        Caption = 'Very High', Comment = 'ESP="Muy alta"';
    }
}
