/// <summary>
/// Setup of the Ledger Application Assistant.
///
/// The payment tolerance group only displays the standard Business Central
/// values. They stay owned by the General Ledger Setup and can only be changed
/// through the standard Change Payment Tolerance process, so the extension never
/// keeps a second copy of them.
/// </summary>
page 87500 "LAA_LedgerApplSetup"
{
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = None;
    SourceTable = "LAA_LedgerApplSetup";
    Caption = 'Ledger Application Setup', Comment = 'ESP="Configuracion de liquidacion de movimientos"';
    InsertAllowed = false;
    DeleteAllowed = false;
    AboutTitle = 'About the Ledger Application Assistant', Comment = 'ESP="Acerca del asistente de liquidacion de movimientos"';
    AboutText = 'These settings control how application proposals are generated for customers and vendors. Payment tolerance is not configured here: it is read from the standard General Ledger Setup.', Comment = 'ESP="Estos ajustes controlan como se generan las propuestas de liquidacion para clientes y proveedores. La tolerancia de pago no se configura aqui: se lee de la configuracion de contabilidad estandar."';

    layout
    {
        area(Content)
        {
            group(Matching)
            {
                Caption = 'Matching', Comment = 'ESP="Conciliacion"';

                field("Max. Match Date Difference"; Rec."Max. Match Date Difference")
                {
                    ApplicationArea = All;
                }
                field("Max. Combination Lines"; Rec."Max. Combination Lines")
                {
                    ApplicationArea = All;
                }
            }
            group(ResidualAllocation)
            {
                Caption = 'Residual Allocation', Comment = 'ESP="Asignacion residual"';

                field("Enable Residual FIFO"; Rec."Enable Residual FIFO")
                {
                    ApplicationArea = All;
                }
                field("FIFO Default Confidence"; Rec."FIFO Default Confidence")
                {
                    ApplicationArea = All;
                    Enabled = Rec."Enable Residual FIFO";
                }
            }
            group(AIMatching)
            {
                Caption = 'AI Matching', Comment = 'ESP="Conciliacion con IA"';

                field("Enable AI Matching"; Rec."Enable AI Matching")
                {
                    ApplicationArea = All;
                }
                field("AI Multiple Exact Confidence"; Rec."AI Multiple Exact Confidence")
                {
                    ApplicationArea = All;
                    Enabled = Rec."Enable AI Matching";
                }
                field("AI Partial Confidence"; Rec."AI Partial Confidence")
                {
                    ApplicationArea = All;
                    Enabled = Rec."Enable AI Matching";
                }
                field("AI Textual Ref. Confidence"; Rec."AI Textual Ref. Confidence")
                {
                    ApplicationArea = All;
                    Enabled = Rec."Enable AI Matching";
                }
            }
            group(PaymentTolerance)
            {
                Caption = 'Payment Tolerance (General Ledger Setup)', Comment = 'ESP="Tolerancia de pago (configuracion de contabilidad)"';

                field(PaymentTolerancePct; vPaymentTolerancePct)
                {
                    ApplicationArea = All;
                    Caption = 'Payment Tolerance %', Comment = 'ESP="% tolerancia de pago"';
                    ToolTip = 'Specifies the payment tolerance percentage of the standard General Ledger Setup. The matching engine proposes a tolerance match only when this standard configuration supports the difference.', Comment = 'ESP="Especifica el porcentaje de tolerancia de pago de la configuracion de contabilidad estandar. El motor de conciliacion solo propone una coincidencia por tolerancia cuando esta configuracion estandar admite la diferencia."';
                    Editable = false;
                    DecimalPlaces = 0 : 5;
                }
                field(MaxPaymentToleranceAmount; vMaxPaymentToleranceAmount)
                {
                    ApplicationArea = All;
                    Caption = 'Max. Payment Tolerance Amount', Comment = 'ESP="Importe max. tolerancia de pago"';
                    ToolTip = 'Specifies the maximum payment tolerance amount of the standard General Ledger Setup.', Comment = 'ESP="Especifica el importe maximo de tolerancia de pago de la configuracion de contabilidad estandar."';
                    Editable = false;
                }
                field(PaymentToleranceWarning; vPaymentToleranceWarning)
                {
                    ApplicationArea = All;
                    Caption = 'Payment Tolerance Warning', Comment = 'ESP="Aviso tolerancia de pago"';
                    ToolTip = 'Specifies whether standard Business Central shows the payment tolerance warning while an application is posted.', Comment = 'ESP="Especifica si Business Central estandar muestra el aviso de tolerancia de pago al registrar una liquidacion."';
                    Editable = false;
                }
                field(PaymentDiscountGracePeriod; vPaymentDiscountGracePeriod)
                {
                    ApplicationArea = All;
                    Caption = 'Payment Discount Grace Period', Comment = 'ESP="Periodo de gracia dto. pago"';
                    ToolTip = 'Specifies the payment discount grace period of the standard General Ledger Setup.', Comment = 'ESP="Especifica el periodo de gracia de descuento por pronto pago de la configuracion de contabilidad estandar."';
                    Editable = false;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(LAA_ChangePaymentTolerance)
            {
                ApplicationArea = All;
                Caption = 'Change Payment Tolerance', Comment = 'ESP="Cambiar tolerancia de pago"';
                ToolTip = 'Run the standard Business Central process that changes the payment tolerance and recalculates it on the open ledger entries. The values belong to the General Ledger Setup, not to this extension.', Comment = 'ESP="Ejecuta el proceso estandar de Business Central que cambia la tolerancia de pago y la recalcula en los movimientos abiertos. Los valores pertenecen a la configuracion de contabilidad, no a esta extension."';
                Image = ChangeDate;

                trigger OnAction()
                var
                    TextChangeToleranceQst: Label 'The payment tolerance belongs to the standard General Ledger Setup and is used by the whole company, not only by application proposals.\\Changing it recalculates the tolerance of the open customer and vendor ledger entries.\\Do you want to continue?', Comment = 'ESP="La tolerancia de pago pertenece a la configuracion de contabilidad estandar y la utiliza toda la empresa, no solo las propuestas de liquidacion.\\Al cambiarla se recalcula la tolerancia de los movimientos abiertos de clientes y proveedores.\\Desea continuar?"';
                begin
                    if not Confirm(TextChangeToleranceQst, false) then
                        exit;

                    Report.Run(Report::"Change Payment Tolerance", true, false);
                    fLoadPaymentToleranceValues();
                    CurrPage.Update(false);
                end;
            }
            action(LAA_ApplicationProposals)
            {
                ApplicationArea = All;
                Caption = 'Application Proposals', Comment = 'ESP="Propuestas de liquidacion"';
                ToolTip = 'Open the list of application proposals generated for customers and vendors.', Comment = 'ESP="Abre la lista de propuestas de liquidacion generadas para clientes y proveedores."';
                Image = List;
                RunObject = page "LAA_LedgerApplProposalList";
            }
            action(LAA_RegisterAIAssistant)
            {
                ApplicationArea = All;
                Caption = 'Register AI Assistant', Comment = 'ESP="Registrar asistente de IA"';
                ToolTip = 'Register the agent, the capability, its instructions, the tool and the workflow of the AI matching layer in the agent framework. This runs automatically when the extension is installed or upgraded; use it after publishing a new version of the instructions, or to check that the registration is in place.', Comment = 'ESP="Registra el agente, la capacidad, sus instrucciones, la herramienta y el flujo de la capa de conciliacion con IA en el framework de agentes. Se ejecuta automaticamente al instalar o actualizar la extension; utilicelo despues de publicar una nueva version de las instrucciones, o para comprobar que el registro esta hecho."';
                Image = Setup;

                trigger OnAction()
                var
                    clInstall: Codeunit "LAA_LedgerApplInstall";
                    TextAIRegisteredMsg: Label 'The AI assistant is registered. You can review it in the agent framework, on the AI Agents and AI Capabilities pages.', Comment = 'ESP="El asistente de IA esta registrado. Puede revisarlo en el framework de agentes, en las paginas Agentes IA y Capacidades IA."';
                begin
                    clInstall.fRegisterAIConfiguration();
                    Message(TextAIRegisteredMsg);
                end;
            }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process', Comment = 'ESP="Proceso"';

                actionref(LAA_ChangePaymentToleranceRef; LAA_ChangePaymentTolerance)
                {
                }
                actionref(LAA_ApplicationProposalsRef; LAA_ApplicationProposals)
                {
                }
                actionref(LAA_RegisterAIAssistantRef; LAA_RegisterAIAssistant)
                {
                }
            }
        }
    }

    var
        vPaymentDiscountGracePeriod: DateFormula;
        vMaxPaymentToleranceAmount: Decimal;
        vPaymentTolerancePct: Decimal;
        vPaymentToleranceWarning: Boolean;

    trigger OnOpenPage()
    var
        clInstall: Codeunit "LAA_LedgerApplInstall";
    begin
        clInstall.fInitializeSetup();
        Rec.fGetSetup();
        fLoadPaymentToleranceValues();
    end;

    local procedure fLoadPaymentToleranceValues()
    var
        rlGLSetup: Record "General Ledger Setup";
    begin
        Clear(vPaymentTolerancePct);
        Clear(vMaxPaymentToleranceAmount);
        Clear(vPaymentToleranceWarning);
        Clear(vPaymentDiscountGracePeriod);

        if not rlGLSetup.Get() then
            exit;

        vPaymentTolerancePct := rlGLSetup."Payment Tolerance %";
        vMaxPaymentToleranceAmount := rlGLSetup."Max. Payment Tolerance Amount";
        vPaymentToleranceWarning := rlGLSetup."Payment Tolerance Warning";
        vPaymentDiscountGracePeriod := rlGLSetup."Payment Discount Grace Period";
    end;
}
