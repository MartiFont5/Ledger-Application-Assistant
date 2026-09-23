/// <summary>
/// Visual registration state of an application group in the proposal tree.
/// Only Registered is persisted; Error is an execution-time result.
/// </summary>
enum 87516 "LAA_RegistrationStatus"
{
    Extensible = false;
    Caption = 'Registration Status', Comment = 'ESP="Estado de registro"';

    value(0; Pending)
    {
        Caption = 'Pending', Comment = 'ESP="Pendiente"';
    }
    value(1; Registered)
    {
        Caption = 'Registered', Comment = 'ESP="Registrado"';
    }
    value(2; Error)
    {
        Caption = 'Error', Comment = 'ESP="Error"';
    }
}
