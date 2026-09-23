/// <summary>
/// Header of an application proposal for one customer or one vendor.
/// A proposal may contain groups in several currencies, so no currency is held here.
/// Status and Obsolete are two independent concepts.
/// </summary>
table 87501 "LAA_LedgerApplProposalHeader"
{
    Caption = 'Ledger Application Proposal', Comment = 'ESP="Propuesta de liquidacion de movimientos"';
    DataClassification = CustomerContent;
    Extensible = false;
    DrillDownPageId = "LAA_LedgerApplProposalList";
    LookupPageId = "LAA_LedgerApplProposalList";

    fields
    {
        field(1; "No."; Integer)
        {
            Caption = 'No.', Comment = 'ESP="Nro."';
            ToolTip = 'Specifies the number that identifies the application proposal.', Comment = 'ESP="Especifica el numero que identifica la propuesta de liquidacion."';
            DataClassification = CustomerContent;
        }
        field(10; "Entity Type"; Enum "LAA_EntityType")
        {
            Caption = 'Entity Type', Comment = 'ESP="Tipo de entidad"';
            ToolTip = 'Specifies whether the proposal works on customer or vendor ledger entries.', Comment = 'ESP="Especifica si la propuesta trabaja sobre movimientos de cliente o de proveedor."';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(11; "Entity No."; Code[20])
        {
            Caption = 'Entity No.', Comment = 'ESP="Nro. entidad"';
            ToolTip = 'Specifies the customer or vendor whose open ledger entries the proposal analyses.', Comment = 'ESP="Especifica el cliente o proveedor cuyos movimientos abiertos analiza la propuesta."';
            DataClassification = CustomerContent;
            Editable = false;
            TableRelation = if ("Entity Type" = const(Customer)) Customer."No."
            else
            if ("Entity Type" = const(Vendor)) Vendor."No.";
        }
        field(12; "Entity Name"; Text[100])
        {
            Caption = 'Entity Name', Comment = 'ESP="Nombre entidad"';
            ToolTip = 'Specifies the name of the customer or vendor, as it was when the proposal was created.', Comment = 'ESP="Especifica el nombre del cliente o proveedor, tal como estaba al crear la propuesta."';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(20; Status; Enum "LAA_ProposalStatus")
        {
            Caption = 'Status', Comment = 'ESP="Estado"';
            ToolTip = 'Specifies how many of the application groups of the proposal have already been registered.', Comment = 'ESP="Especifica cuantos de los grupos de liquidacion de la propuesta ya se han registrado."';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(21; "Obsolete"; Boolean)
        {
            Caption = 'Obsolete', Comment = 'ESP="Obsoleta"';
            ToolTip = 'Specifies that the customer or vendor ledger data changed after the proposal was generated, so the proposal can no longer be used. Create a new proposal from the current ledger state.', Comment = 'ESP="Especifica que los datos de movimientos del cliente o proveedor cambiaron despues de generar la propuesta, por lo que ya no puede utilizarse. Cree una nueva propuesta a partir del estado actual."';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(30; "Created At"; DateTime)
        {
            Caption = 'Created At', Comment = 'ESP="Creada el"';
            ToolTip = 'Specifies when the proposal was generated.', Comment = 'ESP="Especifica cuando se genero la propuesta."';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(31; "Created By"; Code[50])
        {
            Caption = 'Created By', Comment = 'ESP="Creada por"';
            ToolTip = 'Specifies the user who generated the proposal.', Comment = 'ESP="Especifica el usuario que genero la propuesta."';
            DataClassification = EndUserIdentifiableInformation;
            Editable = false;
            TableRelation = User."User Name";
            ValidateTableRelation = false;
        }
        field(40; "Source Last Ledger Entry No."; Integer)
        {
            Caption = 'Source Last Ledger Entry No.', Comment = 'ESP="Ultimo nro. mov. origen"';
            ToolTip = 'Specifies the highest customer or vendor ledger entry number that existed for this entity when the proposal was generated or last refreshed. It is used to detect external changes.', Comment = 'ESP="Especifica el numero de movimiento de cliente o proveedor mas alto que existia para esta entidad al generar o actualizar la propuesta. Se utiliza para detectar cambios externos."';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(41; "Source Last Detailed Entry No."; Integer)
        {
            Caption = 'Source Last Detailed Entry No.', Comment = 'ESP="Ultimo nro. mov. detallado origen"';
            ToolTip = 'Specifies the highest detailed customer or vendor ledger entry number that existed for this entity when the proposal was generated or last refreshed. It is used to detect external applications and unapplications.', Comment = 'ESP="Especifica el numero de movimiento detallado mas alto que existia para esta entidad al generar o actualizar la propuesta. Se utiliza para detectar liquidaciones y deshacer liquidaciones externas."';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(50; "No. of Groups"; Integer)
        {
            Caption = 'No. of Groups', Comment = 'ESP="Nro. de grupos"';
            ToolTip = 'Specifies how many application groups the proposal contains.', Comment = 'ESP="Especifica cuantos grupos de liquidacion contiene la propuesta."';
            FieldClass = FlowField;
            Editable = false;
            CalcFormula = count("LAA_LedgerApplProposalLine" where("Proposal No." = field("No."),
                                                                   Level = const("Applying Entry")));
        }
        field(51; "No. of Registered Groups"; Integer)
        {
            Caption = 'No. of Registered Groups', Comment = 'ESP="Nro. de grupos registrados"';
            ToolTip = 'Specifies how many application groups of the proposal have already been registered.', Comment = 'ESP="Especifica cuantos grupos de liquidacion de la propuesta ya se han registrado."';
            FieldClass = FlowField;
            Editable = false;
            CalcFormula = count("LAA_LedgerApplProposalLine" where("Proposal No." = field("No."),
                                                                   Level = const("Applying Entry"),
                                                                   Registered = const(true)));
        }
        field(52; "No. of Lines"; Integer)
        {
            Caption = 'No. of Lines', Comment = 'ESP="Nro. de lineas"';
            ToolTip = 'Specifies how many proposal lines the proposal contains, counting both applying and applied entries.', Comment = 'ESP="Especifica cuantas lineas contiene la propuesta, contando movimientos liquidadores y liquidados."';
            FieldClass = FlowField;
            Editable = false;
            CalcFormula = count("LAA_LedgerApplProposalLine" where("Proposal No." = field("No.")));
        }
    }

    keys
    {
        key(PK; "No.")
        {
            Clustered = true;
        }
        key(Entity; "Entity Type", "Entity No.", "Obsolete", Status)
        {
        }
    }

    fieldgroups
    {
        fieldgroup(DropDown; "No.", "Entity No.", "Entity Name", Status)
        {
        }
        fieldgroup(Brick; "No.", "Entity Name", Status, "Obsolete")
        {
        }
    }

    trigger OnDelete()
    var
        rlProposalLine: Record "LAA_LedgerApplProposalLine";
        TextDeleteRegisteredErr: Label 'Proposal %1 cannot be deleted because it already contains registered application groups.', Comment = '%1 = proposal number. ESP="La propuesta %1 no puede eliminarse porque ya contiene grupos de liquidacion registrados."';
    begin
        Rec.CalcFields("No. of Registered Groups");
        if Rec."No. of Registered Groups" > 0 then
            Error(TextDeleteRegisteredErr, Rec."No.");

        rlProposalLine.SetRange("Proposal No.", Rec."No.");
        rlProposalLine.DeleteAll(false);
    end;
}
