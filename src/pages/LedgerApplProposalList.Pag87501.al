/// <summary>
/// Proposal history and active proposal management.
///
/// Opening the list performs the lightweight obsolescence check: only proposals
/// that are still active are evaluated, and only through their two source
/// markers. No proposal line is read.
/// </summary>
page 87501 "LAA_LedgerApplProposalList"
{
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Lists;
    SourceTable = "LAA_LedgerApplProposalHeader";
    Caption = 'Ledger Application Proposals', Comment = 'ESP="Propuestas de liquidacion de movimientos"';
    // The page stays read only through ModifyAllowed and InsertAllowed, never
    // through Editable: a non editable page also hides the standard Delete
    // action, and proposals have to be deletable from the list.
    Editable = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = true;
    SourceTableView = sorting("No.") order(descending);

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field("No."; Rec."No.")
                {
                    ApplicationArea = All;
                    DrillDown = true;
                    ToolTip = 'Specifies the number of the proposal. Choose the number to review its application groups.', Comment = 'ESP="Especifica el numero de la propuesta. Elija el numero para revisar sus grupos de liquidacion."';

                    trigger OnDrillDown()
                    begin
                        fShowProposalLines();
                    end;
                }
                field("Entity Type"; Rec."Entity Type")
                {
                    ApplicationArea = All;
                }
                field("Entity No."; Rec."Entity No.")
                {
                    ApplicationArea = All;
                }
                field("Entity Name"; Rec."Entity Name")
                {
                    ApplicationArea = All;
                }
                field(Status; Rec.Status)
                {
                    ApplicationArea = All;
                    StyleExpr = vStatusStyle;
                }
                field("Obsolete"; Rec."Obsolete")
                {
                    ApplicationArea = All;
                    StyleExpr = vObsoleteStyle;
                }
                field("No. of Groups"; Rec."No. of Groups")
                {
                    ApplicationArea = All;
                }
                field("No. of Registered Groups"; Rec."No. of Registered Groups")
                {
                    ApplicationArea = All;
                }
                field("Created At"; Rec."Created At")
                {
                    ApplicationArea = All;
                }
                field("Created By"; Rec."Created By")
                {
                    ApplicationArea = All;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(LAA_CreateProposal)
            {
                ApplicationArea = All;
                Caption = 'Create Application Proposal', Comment = 'ESP="Crear propuesta de liquidacion"';
                ToolTip = 'Analyse the open ledger entries of a customer or a vendor and generate a new application proposal.', Comment = 'ESP="Analiza los movimientos abiertos de un cliente o proveedor y genera una nueva propuesta de liquidacion."';
                Image = NewDocument;

                trigger OnAction()
                begin
                    fCreateProposalForSelectedEntity();
                end;
            }
        }
        area(Navigation)
        {
            action(LAA_LedgerApplSetup)
            {
                ApplicationArea = All;
                Caption = 'Ledger Application Setup', Comment = 'ESP="Configuracion de liquidacion de movimientos"';
                ToolTip = 'Open the setup of the Ledger Application Assistant, where the matching and residual allocation rules are configured.', Comment = 'ESP="Abre la configuracion del asistente de liquidacion de movimientos, donde se configuran las reglas de conciliacion y de asignacion residual."';
                Image = Setup;
                RunObject = page "LAA_LedgerApplSetup";
            }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process', Comment = 'ESP="Proceso"';

                actionref(LAA_CreateProposalRef; LAA_CreateProposal)
                {
                }
                actionref(LAA_LedgerApplSetupRef; LAA_LedgerApplSetup)
                {
                }
            }
        }
    }

    views
    {
        view(LAA_ActiveProposals)
        {
            Caption = 'Active', Comment = 'ESP="Activas"';
            Filters = where("Obsolete" = const(false), Status = filter("Not Registered" | "Partially Registered"));
        }
        view(LAA_RegisteredProposals)
        {
            Caption = 'Registered', Comment = 'ESP="Registradas"';
            Filters = where(Status = const(Registered));
        }
    }

    var
        vObsoleteStyle: Text;
        vStatusStyle: Text;

    trigger OnOpenPage()
    var
        clProposalMgt: Codeunit "LAA_LedgerApplProposalMgt";
    begin
        clProposalMgt.fCheckActiveProposals();
    end;

    trigger OnAfterGetRecord()
    begin
        fSetStyles();
    end;

    local procedure fSetStyles()
    begin
        vObsoleteStyle := '';
        if Rec."Obsolete" then
            vObsoleteStyle := 'Unfavorable';

        case Rec.Status of
            Rec.Status::"Not Registered":
                vStatusStyle := 'Attention';
            Rec.Status::"Partially Registered",
            Rec.Status::Registered:
                vStatusStyle := 'Favorable';
            else
                vStatusStyle := '';
        end;
    end;

    local procedure fShowProposalLines()
    var
        rlProposalLine: Record "LAA_LedgerApplProposalLine";
    begin
        rlProposalLine.SetRange("Proposal No.", Rec."No.");
        Page.Run(Page::"LAA_LedgerApplProposalLines", rlProposalLine);
    end;

    local procedure fCreateProposalForSelectedEntity()
    var
        rlCustomer: Record Customer;
        rlProposalLine: Record "LAA_LedgerApplProposalLine";
        rlVendor: Record Vendor;
        clProposalMgt: Codeunit "LAA_LedgerApplProposalMgt";
        vlEntityType: Enum "LAA_EntityType";
        vlProposalNo: Integer;
        vlChoice: Integer;
        TextEntityChoiceLbl: Label 'Customer,Vendor', Comment = 'ESP="Cliente,Proveedor"';
        TextEntityChoiceQst: Label 'Create an application proposal for a customer or for a vendor?', Comment = 'ESP="Desea crear una propuesta de liquidacion para un cliente o para un proveedor?"';
    begin
        vlChoice := StrMenu(TextEntityChoiceLbl, 1, TextEntityChoiceQst);
        if vlChoice = 0 then
            exit;

        case vlChoice of
            1:
                begin
                    vlEntityType := vlEntityType::Customer;
                    if Page.RunModal(Page::"Customer List", rlCustomer) <> Action::LookupOK then
                        exit;
                    vlProposalNo := clProposalMgt.fCreateProposalWithConfirmation(vlEntityType, rlCustomer."No.");
                end;
            2:
                begin
                    vlEntityType := vlEntityType::Vendor;
                    if Page.RunModal(Page::"Vendor List", rlVendor) <> Action::LookupOK then
                        exit;
                    vlProposalNo := clProposalMgt.fCreateProposalWithConfirmation(vlEntityType, rlVendor."No.");
                end;
        end;

        if vlProposalNo = 0 then
            exit;

        CurrPage.Update(false);

        rlProposalLine.SetRange("Proposal No.", vlProposalNo);
        Page.Run(Page::"LAA_LedgerApplProposalLines", rlProposalLine);
    end;
}
