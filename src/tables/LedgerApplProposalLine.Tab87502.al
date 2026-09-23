/// <summary>
/// Line of an application proposal. One single table represents both the parent
/// of a group (Level = Applying Entry) and its children (Level = Applied Entry),
/// so no separate group table is needed.
///
/// The same table is also used as a temporary in-memory buffer by the matching
/// engine and by the Add Movements lookup. In the buffer the fields are read as:
///   "Remaining Amount at Proposal" = current remaining amount of the ledger entry
///   "Amount to Apply"              = amount already reserved by generated groups
/// so the still available amount is the difference between both.
/// </summary>
table 87502 "LAA_LedgerApplProposalLine"
{
    Caption = 'Ledger Application Proposal Line', Comment = 'ESP="Linea de propuesta de liquidacion"';
    DataClassification = CustomerContent;
    Extensible = false;

    fields
    {
        field(1; "Proposal No."; Integer)
        {
            Caption = 'Proposal No.', Comment = 'ESP="Nro. propuesta"';
            ToolTip = 'Specifies the proposal that the line belongs to.', Comment = 'ESP="Especifica la propuesta a la que pertenece la linea."';
            DataClassification = CustomerContent;
            TableRelation = "LAA_LedgerApplProposalHeader"."No.";
        }
        field(2; "Line No."; Integer)
        {
            Caption = 'Line No.', Comment = 'ESP="Nro. linea"';
            ToolTip = 'Specifies the number that identifies the line inside the proposal.', Comment = 'ESP="Especifica el numero que identifica la linea dentro de la propuesta."';
            DataClassification = CustomerContent;
        }
        field(10; "Group No."; Integer)
        {
            Caption = 'Group No.', Comment = 'ESP="Nro. grupo"';
            ToolTip = 'Specifies the application group that the line belongs to. Each group is registered as one single application.', Comment = 'ESP="Especifica el grupo de liquidacion al que pertenece la linea. Cada grupo se registra como una unica liquidacion."';
            DataClassification = CustomerContent;
        }
        field(11; Level; Enum "LAA_ProposalLineLevel")
        {
            Caption = 'Level', Comment = 'ESP="Nivel"';
            ToolTip = 'Specifies whether the line is the applying entry of the group or one of the entries that the group applies.', Comment = 'ESP="Especifica si la linea es el movimiento liquidador del grupo o uno de los movimientos que el grupo liquida."';
            DataClassification = CustomerContent;
        }
        field(12; Indentation; Integer)
        {
            Caption = 'Indentation', Comment = 'ESP="Sangria"';
            ToolTip = 'Specifies the indentation of the line in the proposal tree.', Comment = 'ESP="Especifica la sangria de la linea en el arbol de la propuesta."';
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(20; "Entity Type"; Enum "LAA_EntityType")
        {
            Caption = 'Entity Type', Comment = 'ESP="Tipo de entidad"';
            ToolTip = 'Specifies whether the line refers to a customer or to a vendor ledger entry.', Comment = 'ESP="Especifica si la linea se refiere a un movimiento de cliente o de proveedor."';
            DataClassification = CustomerContent;
        }
        field(21; "Entity No."; Code[20])
        {
            Caption = 'Entity No.', Comment = 'ESP="Nro. entidad"';
            ToolTip = 'Specifies the customer or vendor of the ledger entry.', Comment = 'ESP="Especifica el cliente o proveedor del movimiento."';
            DataClassification = CustomerContent;
            TableRelation = if ("Entity Type" = const(Customer)) Customer."No."
            else
            if ("Entity Type" = const(Vendor)) Vendor."No.";
        }
        field(30; "Ledger Entry No."; Integer)
        {
            Caption = 'Ledger Entry No.', Comment = 'ESP="Nro. movimiento"';
            ToolTip = 'Specifies the customer or vendor ledger entry that the line proposes to apply.', Comment = 'ESP="Especifica el movimiento de cliente o proveedor que la linea propone liquidar."';
            DataClassification = CustomerContent;
        }
        field(31; "Document Type"; Enum "Gen. Journal Document Type")
        {
            Caption = 'Document Type', Comment = 'ESP="Tipo documento"';
            ToolTip = 'Specifies the document type of the ledger entry.', Comment = 'ESP="Especifica el tipo de documento del movimiento."';
            DataClassification = CustomerContent;
        }
        field(32; "Document No."; Code[20])
        {
            Caption = 'Document No.', Comment = 'ESP="Nro. documento"';
            ToolTip = 'Specifies the document number of the ledger entry.', Comment = 'ESP="Especifica el numero de documento del movimiento."';
            DataClassification = CustomerContent;
        }
        field(33; "Posting Date"; Date)
        {
            Caption = 'Posting Date', Comment = 'ESP="Fecha registro"';
            ToolTip = 'Specifies the posting date of the ledger entry.', Comment = 'ESP="Especifica la fecha de registro del movimiento."';
            DataClassification = CustomerContent;
        }
        field(34; "Due Date"; Date)
        {
            Caption = 'Due Date', Comment = 'ESP="Fecha vencimiento"';
            ToolTip = 'Specifies the due date of the ledger entry.', Comment = 'ESP="Especifica la fecha de vencimiento del movimiento."';
            DataClassification = CustomerContent;
        }
        field(35; "Currency Code"; Code[10])
        {
            Caption = 'Currency Code', Comment = 'ESP="Cod. divisa"';
            ToolTip = 'Specifies the currency of the ledger entry. All entries of one application group share the same currency.', Comment = 'ESP="Especifica la divisa del movimiento. Todos los movimientos de un grupo de liquidacion comparten la misma divisa."';
            DataClassification = CustomerContent;
            TableRelation = Currency;
        }
        field(36; Description; Text[100])
        {
            Caption = 'Description', Comment = 'ESP="Descripcion"';
            ToolTip = 'Specifies the description of the ledger entry. The matching engine also scans it for document references.', Comment = 'ESP="Especifica la descripcion del movimiento. El motor de conciliacion tambien la analiza en busca de referencias a documentos."';
            DataClassification = CustomerContent;
        }
        field(37; "External Document No."; Code[35])
        {
            Caption = 'External Document No.', Comment = 'ESP="Nro. documento externo"';
            ToolTip = 'Specifies the external document number of the ledger entry.', Comment = 'ESP="Especifica el numero de documento externo del movimiento."';
            DataClassification = CustomerContent;
        }
        field(38; "Payment Reference"; Code[50])
        {
            Caption = 'Payment Reference', Comment = 'ESP="Referencia de pago"';
            ToolTip = 'Specifies the payment reference of the ledger entry.', Comment = 'ESP="Especifica la referencia de pago del movimiento."';
            DataClassification = CustomerContent;
        }
        field(39; "Applies-to Doc. No."; Code[20])
        {
            Caption = 'Applies-to Doc. No.', Comment = 'ESP="Nro. doc. a liquidar"';
            ToolTip = 'Specifies the document that the ledger entry was posted to apply.', Comment = 'ESP="Especifica el documento que el movimiento se registro para liquidar."';
            DataClassification = CustomerContent;
        }
        field(40; "Remaining Amount at Proposal"; Decimal)
        {
            Caption = 'Remaining Amount at Proposal', Comment = 'ESP="Importe pendiente al proponer"';
            ToolTip = 'Specifies the remaining amount that the ledger entry had when the proposal was generated. It is an informational snapshot and is never used as a posting condition.', Comment = 'ESP="Especifica el importe pendiente que tenia el movimiento al generar la propuesta. Es una foto informativa y nunca se utiliza como condicion de registro."';
            DataClassification = CustomerContent;
            AutoFormatType = 1;
            AutoFormatExpression = Rec."Currency Code";
            Editable = false;
        }
        field(41; "Amount to Apply"; Decimal)
        {
            Caption = 'Amount to Apply', Comment = 'ESP="Importe a liquidar"';
            ToolTip = 'Specifies the amount of the ledger entry that this application group proposes to apply.', Comment = 'ESP="Especifica el importe del movimiento que este grupo de liquidacion propone liquidar."';
            DataClassification = CustomerContent;
            AutoFormatType = 1;
            AutoFormatExpression = Rec."Currency Code";
        }
        field(50; "Match Method"; Enum "LAA_MatchMethod")
        {
            Caption = 'Match Method', Comment = 'ESP="Metodo de conciliacion"';
            ToolTip = 'Specifies the rule that generated the application group.', Comment = 'ESP="Especifica la regla que genero el grupo de liquidacion."';
            DataClassification = CustomerContent;
        }
        field(51; Confidence; Enum "LAA_Confidence")
        {
            Caption = 'Confidence', Comment = 'ESP="Confianza"';
            ToolTip = 'Specifies how reliable the generated match is. The value is informational and never prevents the group from being registered.', Comment = 'ESP="Especifica la fiabilidad de la conciliacion generada. El valor es informativo y nunca impide registrar el grupo."';
            DataClassification = CustomerContent;
        }
        field(52; "AI Candidate Type"; Enum "LAA_AICandidateType")
        {
            Caption = 'AI Candidate Type', Comment = 'ESP="Tipo de candidato IA"';
            ToolTip = 'Specifies the kind of situation that the deterministic engine could not resolve on its own and that artificial intelligence may resolve in a future phase.', Comment = 'ESP="Especifica el tipo de situacion que el motor determinista no pudo resolver por si mismo y que la inteligencia artificial podra resolver en una fase futura."';
            DataClassification = CustomerContent;
        }
        field(53; "Manually Modified"; Boolean)
        {
            Caption = 'Manually Modified', Comment = 'ESP="Modificado manualmente"';
            ToolTip = 'Specifies that a user changed the generated application group by adding or removing movements.', Comment = 'ESP="Especifica que un usuario modifico el grupo de liquidacion generado anadiendo o quitando movimientos."';
            DataClassification = CustomerContent;
        }
        field(60; Registered; Boolean)
        {
            Caption = 'Registered', Comment = 'ESP="Registrado"';
            ToolTip = 'Specifies that the application group has already been posted. Registered groups can no longer be changed.', Comment = 'ESP="Especifica que el grupo de liquidacion ya se ha registrado. Los grupos registrados ya no pueden modificarse."';
            DataClassification = CustomerContent;
            Editable = false;
        }
    }

    keys
    {
        key(PK; "Proposal No.", "Line No.")
        {
            Clustered = true;
        }
        key(Group; "Proposal No.", "Group No.", Level, "Line No.")
        {
        }
        key(Entry; "Proposal No.", "Ledger Entry No.")
        {
            SumIndexFields = "Amount to Apply";
        }
        key(Sorting; "Proposal No.", "Currency Code", "Posting Date", "Line No.")
        {
        }
    }

    fieldgroups
    {
        fieldgroup(DropDown; "Document Type", "Document No.", "Posting Date", "Amount to Apply")
        {
        }
    }

    /// <summary>
    /// Amount of the entry that is still free in the matching buffer.
    /// Only meaningful while the record is used as a temporary buffer record.
    /// </summary>
    internal procedure fBufferAvailableAmount(): Decimal
    begin
        exit(Rec."Remaining Amount at Proposal" - Rec."Amount to Apply");
    end;

    /// <summary>
    /// Registration status shown in the proposal tree. Only Registered is persisted;
    /// Error is an execution-time result and is passed in by the caller.
    /// </summary>
    internal procedure fRegistrationStatus(): Enum "LAA_RegistrationStatus"
    begin
        if Rec.Registered then
            exit(Enum::"LAA_RegistrationStatus"::Registered);

        exit(Enum::"LAA_RegistrationStatus"::Pending);
    end;
}
