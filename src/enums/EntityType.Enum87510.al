/// <summary>
/// Identifies whether a proposal works on customer or vendor ledger entries.
/// It is the routing key of the shared customer/vendor engine.
/// </summary>
enum 87510 "LAA_EntityType"
{
    Extensible = true;
    Caption = 'Entity Type', Comment = 'ESP="Tipo de entidad"';

    value(0; Customer)
    {
        Caption = 'Customer', Comment = 'ESP="Cliente"';
    }
    value(1; Vendor)
    {
        Caption = 'Vendor', Comment = 'ESP="Proveedor"';
    }
}
