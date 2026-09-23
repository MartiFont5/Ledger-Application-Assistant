/// <summary>
/// Rule that generated an application group. Informational only:
/// it never controls whether a group may be posted.
/// </summary>
enum 87513 "LAA_MatchMethod"
{
    Extensible = true;
    Caption = 'Match Method', Comment = 'ESP="Metodo de conciliacion"';

    value(0; " ")
    {
        Caption = ' ', Locked = true;
    }
    value(1; "Explicit Reference")
    {
        Caption = 'Explicit Reference', Comment = 'ESP="Referencia explicita"';
    }
    value(2; "Exact 1:1")
    {
        Caption = 'Exact 1:1', Comment = 'ESP="Exacto 1:1"';
    }
    value(3; "Exact 1:N")
    {
        Caption = 'Exact 1:N', Comment = 'ESP="Exacto 1:N"';
    }
    value(4; "Payment Tolerance")
    {
        Caption = 'Payment Tolerance', Comment = 'ESP="Tolerancia de pago"';
    }
    value(5; FIFO)
    {
        Caption = 'FIFO', Comment = 'ESP="FIFO"';
    }
    value(6; Manual)
    {
        Caption = 'Manual', Comment = 'ESP="Manual"';
    }
    value(7; "AI Assisted")
    {
        Caption = 'AI Assisted', Comment = 'ESP="Asistido por IA"';
    }
}
