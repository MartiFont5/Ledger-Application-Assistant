/// <summary>
/// Narrow branching layer between the shared proposal engine and the two
/// standard ledger models. Everything that reads customer ledger entries,
/// vendor ledger entries and their detailed entries lives here, so matching,
/// proposal management and the pages stay entity agnostic.
///
/// Posting is deliberately NOT part of this codeunit: the standard application
/// calls live in LAA_LedgerApplPostGroup.
/// </summary>
codeunit 87503 "LAA_LedgerApplEntityMgt"
{
    Access = Internal;

    #region Entity information

    /// <summary>
    /// Returns the name of the customer or vendor, or an empty text when the
    /// entity no longer exists.
    /// </summary>
    internal procedure fGetEntityName(pEntityType: Enum "LAA_EntityType"; pEntityNo: Code[20]): Text[100]
    var
        rlCustomer: Record Customer;
        rlVendor: Record Vendor;
    begin
        case pEntityType of
            pEntityType::Customer:
                if rlCustomer.Get(pEntityNo) then
                    exit(rlCustomer.Name);
            pEntityType::Vendor:
                if rlVendor.Get(pEntityNo) then
                    exit(rlVendor.Name);
        end;

        exit('');
    end;

    /// <summary>
    /// Checks that the customer or vendor exists and is usable.
    /// </summary>
    internal procedure fTestEntity(pEntityType: Enum "LAA_EntityType"; pEntityNo: Code[20])
    var
        rlCustomer: Record Customer;
        rlVendor: Record Vendor;
        TextEntityMissingErr: Label 'Ledger application proposals require an existing customer or vendor. %1 %2 was not found.', Comment = '%1 = entity type caption, %2 = entity number. ESP="Las propuestas de liquidacion requieren un cliente o proveedor existente. No se ha encontrado %1 %2."';
    begin
        case pEntityType of
            pEntityType::Customer:
                if not rlCustomer.Get(pEntityNo) then
                    Error(TextEntityMissingErr, Format(pEntityType), pEntityNo);
            pEntityType::Vendor:
                if not rlVendor.Get(pEntityNo) then
                    Error(TextEntityMissingErr, Format(pEntityType), pEntityNo);
        end;
    end;

    #endregion

    #region Obsolescence source markers

    /// <summary>
    /// Highest ledger entry number that currently exists for this entity.
    /// Entries of other customers/vendors must never obsolete a proposal, so the
    /// marker is always calculated with an entity filter.
    /// </summary>
    internal procedure fGetLastLedgerEntryNo(pEntityType: Enum "LAA_EntityType"; pEntityNo: Code[20]): Integer
    var
        rlCustLedgEntry: Record "Cust. Ledger Entry";
        rlVendLedgEntry: Record "Vendor Ledger Entry";
    begin
        case pEntityType of
            pEntityType::Customer:
                begin
                    rlCustLedgEntry.SetCurrentKey("Entry No.");
                    rlCustLedgEntry.SetRange("Customer No.", pEntityNo);
                    if rlCustLedgEntry.FindLast() then
                        exit(rlCustLedgEntry."Entry No.");
                end;
            pEntityType::Vendor:
                begin
                    rlVendLedgEntry.SetCurrentKey("Entry No.");
                    rlVendLedgEntry.SetRange("Vendor No.", pEntityNo);
                    if rlVendLedgEntry.FindLast() then
                        exit(rlVendLedgEntry."Entry No.");
                end;
        end;

        exit(0);
    end;

    /// <summary>
    /// Highest detailed ledger entry number that currently exists for this entity.
    /// It detects applications, unapplications and any other detailed activity.
    /// </summary>
    internal procedure fGetLastDetailedEntryNo(pEntityType: Enum "LAA_EntityType"; pEntityNo: Code[20]): Integer
    var
        rlDtldCustLedgEntry: Record "Detailed Cust. Ledg. Entry";
        rlDtldVendLedgEntry: Record "Detailed Vendor Ledg. Entry";
    begin
        case pEntityType of
            pEntityType::Customer:
                begin
                    rlDtldCustLedgEntry.SetCurrentKey("Entry No.");
                    rlDtldCustLedgEntry.SetRange("Customer No.", pEntityNo);
                    if rlDtldCustLedgEntry.FindLast() then
                        exit(rlDtldCustLedgEntry."Entry No.");
                end;
            pEntityType::Vendor:
                begin
                    rlDtldVendLedgEntry.SetCurrentKey("Entry No.");
                    rlDtldVendLedgEntry.SetRange("Vendor No.", pEntityNo);
                    if rlDtldVendLedgEntry.FindLast() then
                        exit(rlDtldVendLedgEntry."Entry No.");
                end;
        end;

        exit(0);
    end;

    #endregion

    #region Eligible ledger entries

    /// <summary>
    /// Tells whether the entity has at least one open ledger entry that could be
    /// applied. It is the cheap guard used before a proposal is created, so that
    /// no proposal is generated for an entity with nothing to apply. The
    /// remaining amount is deliberately not calculated here: fCollectOpenEntries
    /// still discards the open entries whose remaining amount is zero.
    /// </summary>
    internal procedure fHasOpenEntries(pEntityType: Enum "LAA_EntityType"; pEntityNo: Code[20]): Boolean
    var
        rlCustLedgEntry: Record "Cust. Ledger Entry";
        rlVendLedgEntry: Record "Vendor Ledger Entry";
    begin
        case pEntityType of
            pEntityType::Customer:
                begin
                    rlCustLedgEntry.SetCurrentKey("Customer No.", Open);
                    rlCustLedgEntry.SetRange("Customer No.", pEntityNo);
                    rlCustLedgEntry.SetRange(Open, true);
                    rlCustLedgEntry.SetRange(Reversed, false);
                    exit(not rlCustLedgEntry.IsEmpty());
                end;
            pEntityType::Vendor:
                begin
                    rlVendLedgEntry.SetCurrentKey("Vendor No.", Open);
                    rlVendLedgEntry.SetRange("Vendor No.", pEntityNo);
                    rlVendLedgEntry.SetRange(Open, true);
                    rlVendLedgEntry.SetRange(Reversed, false);
                    exit(not rlVendLedgEntry.IsEmpty());
                end;
        end;

        exit(false);
    end;

    /// <summary>
    /// Fills the temporary buffer with every ledger entry of the entity that is a
    /// valid candidate for application: open, not reversed and with a remaining
    /// amount different from zero.
    /// </summary>
    internal procedure fCollectOpenEntries(pEntityType: Enum "LAA_EntityType"; pEntityNo: Code[20]; var pTEMPBufferEntry: Record "LAA_LedgerApplProposalLine" temporary)
    var
        rlCustLedgEntry: Record "Cust. Ledger Entry";
        rlVendLedgEntry: Record "Vendor Ledger Entry";
    begin
        pTEMPBufferEntry.Reset();
        pTEMPBufferEntry.DeleteAll(false);

        case pEntityType of
            pEntityType::Customer:
                begin
                    rlCustLedgEntry.SetCurrentKey("Customer No.", Open);
                    rlCustLedgEntry.SetRange("Customer No.", pEntityNo);
                    rlCustLedgEntry.SetRange(Open, true);
                    rlCustLedgEntry.SetRange(Reversed, false);
                    if rlCustLedgEntry.FindSet() then
                        repeat
                            rlCustLedgEntry.CalcFields("Remaining Amount");
                            if rlCustLedgEntry."Remaining Amount" <> 0 then
                                fInsertCustomerBufferEntry(rlCustLedgEntry, pTEMPBufferEntry);
                        until rlCustLedgEntry.Next() = 0;
                end;
            pEntityType::Vendor:
                begin
                    rlVendLedgEntry.SetCurrentKey("Vendor No.", Open);
                    rlVendLedgEntry.SetRange("Vendor No.", pEntityNo);
                    rlVendLedgEntry.SetRange(Open, true);
                    rlVendLedgEntry.SetRange(Reversed, false);
                    if rlVendLedgEntry.FindSet() then
                        repeat
                            rlVendLedgEntry.CalcFields("Remaining Amount");
                            if rlVendLedgEntry."Remaining Amount" <> 0 then
                                fInsertVendorBufferEntry(rlVendLedgEntry, pTEMPBufferEntry);
                        until rlVendLedgEntry.Next() = 0;
                end;
        end;

        pTEMPBufferEntry.Reset();
    end;

    local procedure fInsertCustomerBufferEntry(prCustLedgEntry: Record "Cust. Ledger Entry"; var pTEMPBufferEntry: Record "LAA_LedgerApplProposalLine" temporary)
    begin
        pTEMPBufferEntry.Init();
        pTEMPBufferEntry."Proposal No." := 0;
        pTEMPBufferEntry."Line No." := prCustLedgEntry."Entry No.";
        pTEMPBufferEntry."Entity Type" := pTEMPBufferEntry."Entity Type"::Customer;
        pTEMPBufferEntry."Entity No." := prCustLedgEntry."Customer No.";
        pTEMPBufferEntry."Ledger Entry No." := prCustLedgEntry."Entry No.";
        pTEMPBufferEntry."Document Type" := prCustLedgEntry."Document Type";
        pTEMPBufferEntry."Document No." := prCustLedgEntry."Document No.";
        pTEMPBufferEntry."Posting Date" := prCustLedgEntry."Posting Date";
        pTEMPBufferEntry."Due Date" := prCustLedgEntry."Due Date";
        pTEMPBufferEntry."Currency Code" := prCustLedgEntry."Currency Code";
        pTEMPBufferEntry.Description := prCustLedgEntry.Description;
        pTEMPBufferEntry."External Document No." := prCustLedgEntry."External Document No.";
        pTEMPBufferEntry."Payment Reference" := prCustLedgEntry."Payment Reference";
        pTEMPBufferEntry."Applies-to Doc. No." := prCustLedgEntry."Applies-to Doc. No.";
        pTEMPBufferEntry."Remaining Amount at Proposal" := prCustLedgEntry."Remaining Amount";
        pTEMPBufferEntry."Amount to Apply" := 0;
        pTEMPBufferEntry.Insert(false);
    end;

    local procedure fInsertVendorBufferEntry(prVendLedgEntry: Record "Vendor Ledger Entry"; var pTEMPBufferEntry: Record "LAA_LedgerApplProposalLine" temporary)
    begin
        pTEMPBufferEntry.Init();
        pTEMPBufferEntry."Proposal No." := 0;
        pTEMPBufferEntry."Line No." := prVendLedgEntry."Entry No.";
        pTEMPBufferEntry."Entity Type" := pTEMPBufferEntry."Entity Type"::Vendor;
        pTEMPBufferEntry."Entity No." := prVendLedgEntry."Vendor No.";
        pTEMPBufferEntry."Ledger Entry No." := prVendLedgEntry."Entry No.";
        pTEMPBufferEntry."Document Type" := prVendLedgEntry."Document Type";
        pTEMPBufferEntry."Document No." := prVendLedgEntry."Document No.";
        pTEMPBufferEntry."Posting Date" := prVendLedgEntry."Posting Date";
        pTEMPBufferEntry."Due Date" := prVendLedgEntry."Due Date";
        pTEMPBufferEntry."Currency Code" := prVendLedgEntry."Currency Code";
        pTEMPBufferEntry.Description := prVendLedgEntry.Description;
        pTEMPBufferEntry."External Document No." := prVendLedgEntry."External Document No.";
        pTEMPBufferEntry."Payment Reference" := prVendLedgEntry."Payment Reference";
        pTEMPBufferEntry."Applies-to Doc. No." := prVendLedgEntry."Applies-to Doc. No.";
        pTEMPBufferEntry."Remaining Amount at Proposal" := prVendLedgEntry."Remaining Amount";
        pTEMPBufferEntry."Amount to Apply" := 0;
        pTEMPBufferEntry.Insert(false);
    end;

    /// <summary>
    /// Re-reads one ledger entry and returns its current state. Stored proposal
    /// values are never trusted as current truth, so every validation and every
    /// posting attempt goes through this procedure.
    /// </summary>
    internal procedure fGetCurrentEntryState(pEntityType: Enum "LAA_EntityType"; pLedgerEntryNo: Integer; var pvEntityNo: Code[20]; var pvCurrencyCode: Code[10]; var pvRemainingAmount: Decimal; var pvOpen: Boolean): Boolean
    var
        rlCustLedgEntry: Record "Cust. Ledger Entry";
        rlVendLedgEntry: Record "Vendor Ledger Entry";
    begin
        Clear(pvEntityNo);
        Clear(pvCurrencyCode);
        Clear(pvRemainingAmount);
        Clear(pvOpen);

        case pEntityType of
            pEntityType::Customer:
                begin
                    if not rlCustLedgEntry.Get(pLedgerEntryNo) then
                        exit(false);
                    rlCustLedgEntry.CalcFields("Remaining Amount");
                    pvEntityNo := rlCustLedgEntry."Customer No.";
                    pvCurrencyCode := rlCustLedgEntry."Currency Code";
                    pvRemainingAmount := rlCustLedgEntry."Remaining Amount";
                    pvOpen := rlCustLedgEntry.Open and not rlCustLedgEntry.Reversed;
                    exit(true);
                end;
            pEntityType::Vendor:
                begin
                    if not rlVendLedgEntry.Get(pLedgerEntryNo) then
                        exit(false);
                    rlVendLedgEntry.CalcFields("Remaining Amount");
                    pvEntityNo := rlVendLedgEntry."Vendor No.";
                    pvCurrencyCode := rlVendLedgEntry."Currency Code";
                    pvRemainingAmount := rlVendLedgEntry."Remaining Amount";
                    pvOpen := rlVendLedgEntry.Open and not rlVendLedgEntry.Reversed;
                    exit(true);
                end;
        end;

        exit(false);
    end;

    /// <summary>
    /// Maximum payment tolerance that standard Business Central calculated for
    /// the entry. Zero when payment tolerance is not configured, which makes the
    /// tolerance matching level inactive without any extension parameter.
    /// </summary>
    internal procedure fGetMaxPaymentTolerance(pEntityType: Enum "LAA_EntityType"; pLedgerEntryNo: Integer): Decimal
    var
        rlCustLedgEntry: Record "Cust. Ledger Entry";
        rlVendLedgEntry: Record "Vendor Ledger Entry";
    begin
        case pEntityType of
            pEntityType::Customer:
                if rlCustLedgEntry.Get(pLedgerEntryNo) then
                    exit(Abs(rlCustLedgEntry."Max. Payment Tolerance"));
            pEntityType::Vendor:
                if rlVendLedgEntry.Get(pLedgerEntryNo) then
                    exit(Abs(rlVendLedgEntry."Max. Payment Tolerance"));
        end;

        exit(0);
    end;

    /// <summary>
    /// True when standard Business Central payment tolerance is configured.
    /// The extension never keeps a second copy of these parameters.
    /// </summary>
    internal procedure fIsPaymentToleranceEnabled(): Boolean
    var
        rlGLSetup: Record "General Ledger Setup";
    begin
        if not rlGLSetup.Get() then
            exit(false);

        exit((rlGLSetup."Payment Tolerance %" <> 0) or (rlGLSetup."Max. Payment Tolerance Amount" <> 0));
    end;

    #endregion
}
