/// <summary>
/// Entry point of the assistant on the customer side. The selected ledger entry
/// is only used to identify the customer: the proposal always analyses every
/// eligible open entry of that customer, not just the selected one.
/// </summary>
pageextension 87510 "LAA_CustLedgerEntriesExt" extends "Customer Ledger Entries"
{
    actions
    {
        addlast(processing)
        {
            group(LAA_ApplicationAssistant)
            {
                Caption = 'Application Assistant', Comment = 'ESP="Asistente de liquidacion"';
                Image = Apply;

                action(LAA_CreateApplicationProposal)
                {
                    ApplicationArea = All;
                    Caption = 'Create Application Proposal', Comment = 'ESP="Crear propuesta de liquidacion"';
                    ToolTip = 'Analyse all eligible open ledger entries of this customer and generate an application proposal that you can review, adjust and register.', Comment = 'ESP="Analiza todos los movimientos abiertos elegibles de este cliente y genera una propuesta de liquidacion que puede revisar, ajustar y registrar."';
                    Image = SuggestElectronicDocument;
                    Visible = false;

                    trigger OnAction()
                    begin
                        fLAA_CreateApplicationProposal();
                    end;
                }
                action(LAA_ApplicationProposals)
                {
                    ApplicationArea = All;
                    Caption = 'Application Proposals', Comment = 'ESP="Propuestas de liquidacion"';
                    ToolTip = 'Open the application proposals that were generated for this customer.', Comment = 'ESP="Abre las propuestas de liquidacion generadas para este cliente."';
                    Image = List;

                    trigger OnAction()
                    begin
                        fLAA_ShowApplicationProposals();
                    end;
                }
            }
        }
        addlast(Category_Process)
        {
            actionref(LAA_CreateApplicationProposalRef; LAA_CreateApplicationProposal)
            {
            }
            actionref(LAA_ApplicationProposalsRef; LAA_ApplicationProposals)
            {
            }
        }
    }

    local procedure fLAA_CreateApplicationProposal()
    var
        rlProposalLine: Record "LAA_LedgerApplProposalLine";
        clProposalMgt: Codeunit "LAA_LedgerApplProposalMgt";
        vlEntityType: Enum "LAA_EntityType";
        vlProposalNo: Integer;
    begin
        Rec.TestField("Customer No.");

        vlProposalNo := clProposalMgt.fCreateProposalWithConfirmation(vlEntityType::Customer, Rec."Customer No.");
        if vlProposalNo = 0 then
            exit;

        rlProposalLine.SetRange("Proposal No.", vlProposalNo);
        Page.Run(Page::"LAA_LedgerApplProposalLines", rlProposalLine);
    end;

    local procedure fLAA_ShowApplicationProposals()
    var
        rlProposalHeader: Record "LAA_LedgerApplProposalHeader";
        vlEntityType: Enum "LAA_EntityType";
    begin
        Rec.TestField("Customer No.");

        rlProposalHeader.SetRange("Entity Type", vlEntityType::Customer);
        rlProposalHeader.SetRange("Entity No.", Rec."Customer No.");
        Page.Run(Page::"LAA_LedgerApplProposalList", rlProposalHeader);
    end;
}
