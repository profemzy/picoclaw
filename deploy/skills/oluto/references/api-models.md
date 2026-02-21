# LedgerForge API Models Reference

All monetary amounts are strings (Decimal precision). Dates are `YYYY-MM-DD`. UUIDs are strings.

## Core Models

### OlutoTransaction
```json
{
  "id": "uuid",
  "vendor_name": "string",
  "amount": "string (decimal)",
  "currency": "string (default CAD)",
  "description": "string?",
  "transaction_date": "YYYY-MM-DD",
  "category": "string?",
  "classification": "string? (expense|income)",
  "status": "string (draft|processing|inbox_user|inbox_firm|ready|posted|void)",
  "gst_amount": "string (decimal)",
  "pst_amount": "string (decimal)",
  "ai_confidence": "float (0-1)",
  "ai_suggested_category": "string?",
  "business_id": "uuid",
  "import_source": "string?",
  "import_batch_id": "string?",
  "reconciled": "boolean",
  "created_at": "ISO8601?",
  "updated_at": "ISO8601?"
}
```

### OlutoTransactionCreate (POST body)
```json
{
  "vendor_name": "string (required)",
  "amount": "string (required)",
  "currency": "string? (default CAD)",
  "description": "string?",
  "transaction_date": "YYYY-MM-DD (required)",
  "category": "string?",
  "classification": "string?",
  "source_device": "string?",
  "ai_suggested_category": "string?",
  "ai_confidence": "float?",
  "gst_amount": "string?",
  "pst_amount": "string?"
}
```

### OlutoTransactionUpdate (PATCH body)
```json
{
  "vendor_name": "string?",
  "amount": "string?",
  "currency": "string?",
  "description": "string?",
  "transaction_date": "string?",
  "category": "string?",
  "classification": "string?",
  "status": "string?",
  "gst_amount": "string?",
  "pst_amount": "string?"
}
```

### DashboardSummary
```json
{
  "total_revenue": "string",
  "total_expenses": "string",
  "tax_reserved": "string",
  "safe_to_spend": "string",
  "tax_collected": "string",
  "tax_itc": "string",
  "payments_received": "string",
  "outstanding_receivables": "string",
  "outstanding_payables": "string",
  "exceptions_count": "integer",
  "transactions_count": "integer",
  "status_counts": {
    "draft": "integer",
    "processing": "integer",
    "inbox_user": "integer",
    "inbox_firm": "integer",
    "ready": "integer",
    "posted": "integer"
  },
  "recent_transactions": ["OlutoTransaction[]"],
  "exceptions": ["OlutoTransaction[]"]
}
```

### CategorySuggestResponse
```json
{
  "category": "string",
  "confidence": "float (0-1)",
  "reasoning": "string?"
}
```

## Account Models

### Account
```json
{
  "id": "uuid",
  "code": "string",
  "name": "string",
  "account_type": "string (Asset|Liability|Equity|Revenue|Expense)",
  "parent_account_id": "uuid?",
  "is_active": "boolean",
  "business_id": "uuid",
  "created_at": "ISO8601",
  "updated_at": "ISO8601"
}
```

### CreateAccountRequest
```json
{
  "code": "string (required, unique per business)",
  "name": "string (required)",
  "account_type": "string (required: Asset|Liability|Equity|Revenue|Expense)",
  "parent_account_id": "uuid?"
}
```

## Contact Models

### Contact
```json
{
  "id": "uuid",
  "contact_type": "string (Customer|Vendor|Employee)",
  "name": "string",
  "email": "string?",
  "phone": "string?",
  "billing_address": "string?",
  "shipping_address": "string?",
  "business_id": "uuid",
  "created_at": "ISO8601",
  "updated_at": "ISO8601"
}
```

### CreateContactRequest
```json
{
  "contact_type": "string (required: Customer|Vendor|Employee)",
  "name": "string (required, 1-255 chars)",
  "email": "string? (email format)",
  "phone": "string?",
  "billing_address": "string?",
  "shipping_address": "string?"
}
```

## Invoice Models

### Invoice
```json
{
  "id": "uuid",
  "invoice_number": "string",
  "customer_id": "uuid",
  "invoice_date": "date",
  "due_date": "date",
  "total_amount": "decimal",
  "balance": "decimal",
  "status": "string (draft|sent|paid|partial|overdue|void)",
  "customer_memo": "string?",
  "business_id": "uuid",
  "created_at": "ISO8601",
  "updated_at": "ISO8601"
}
```

### CreateInvoiceRequest
```json
{
  "invoice_number": "string (required)",
  "customer_id": "uuid (required)",
  "invoice_date": "date (required)",
  "due_date": "date (required)",
  "customer_memo": "string?",
  "billing_address": "string?",
  "line_items": [
    {
      "line_number": "integer",
      "item_description": "string",
      "quantity": "decimal",
      "unit_price": "decimal",
      "discount_percent": "decimal?",
      "tax_code": "string?",
      "revenue_account_id": "uuid"
    }
  ]
}
```

### InvoiceLineItem
```json
{
  "id": "uuid",
  "invoice_id": "uuid",
  "line_number": "integer",
  "item_description": "string",
  "quantity": "decimal",
  "unit_price": "decimal",
  "amount": "decimal (computed)",
  "discount_percent": "decimal?",
  "discount_amount": "decimal?",
  "tax_code": "string?",
  "revenue_account_id": "uuid"
}
```

## Bill Models

### Bill
```json
{
  "id": "uuid",
  "bill_number": "string?",
  "vendor_id": "uuid",
  "bill_date": "date",
  "due_date": "date",
  "total_amount": "decimal",
  "balance": "decimal",
  "status": "string (open|paid|partial|void)",
  "memo": "string?",
  "business_id": "uuid",
  "created_at": "ISO8601",
  "updated_at": "ISO8601"
}
```

### CreateBillRequest
```json
{
  "bill_number": "string?",
  "vendor_id": "uuid (required)",
  "bill_date": "date (required)",
  "due_date": "date (required)",
  "memo": "string?",
  "line_items": [
    {
      "line_number": "integer",
      "description": "string?",
      "amount": "decimal",
      "expense_account_id": "uuid",
      "billable": "boolean?",
      "customer_id": "uuid?"
    }
  ]
}
```

## Payment Models

### Payment (Customer)
```json
{
  "id": "uuid",
  "payment_number": "string?",
  "customer_id": "uuid",
  "payment_date": "date",
  "amount": "decimal",
  "unapplied_amount": "decimal?",
  "payment_method": "string",
  "reference_number": "string?",
  "deposit_to_account_id": "uuid?",
  "memo": "string?",
  "business_id": "uuid",
  "created_at": "ISO8601",
  "updated_at": "ISO8601"
}
```

### CreatePaymentRequest
```json
{
  "customer_id": "uuid (required)",
  "payment_date": "date (required)",
  "amount": "decimal (required)",
  "payment_method": "string (required)",
  "payment_number": "string?",
  "reference_number": "string?",
  "deposit_to_account_id": "uuid?",
  "memo": "string?",
  "applications": [
    {"invoice_id": "uuid", "amount_applied": "decimal"}
  ]
}
```

### BillPayment (Vendor)
```json
{
  "id": "uuid",
  "vendor_id": "uuid",
  "payment_date": "date",
  "amount": "decimal",
  "payment_method": "string",
  "reference_number": "string?",
  "bank_account_id": "uuid?",
  "memo": "string?",
  "business_id": "uuid",
  "created_at": "ISO8601",
  "updated_at": "ISO8601"
}
```

### CreateBillPaymentRequest
```json
{
  "vendor_id": "uuid (required)",
  "payment_date": "date (required)",
  "amount": "decimal (required)",
  "payment_method": "string (required)",
  "payment_number": "string?",
  "reference_number": "string?",
  "bank_account_id": "uuid?",
  "memo": "string?",
  "applications": [
    {"bill_id": "uuid", "amount_applied": "decimal"}
  ]
}
```

## Receipt Models

### ReceiptResponse
```json
{
  "id": "uuid",
  "transaction_id": "uuid?",
  "bill_id": "uuid?",
  "business_id": "uuid",
  "original_filename": "string",
  "content_type": "string",
  "file_size": "integer",
  "ocr_status": "string (none|pending|completed|failed)",
  "ocr_data": "ReceiptOcrData?",
  "created_at": "ISO8601",
  "updated_at": "ISO8601"
}
```

### ReceiptOcrData
```json
{
  "vendor": "string?",
  "amount": "string?",
  "date": "string?",
  "tax_amounts": {
    "gst": "string?",
    "pst": "string?"
  },
  "raw_text": "string?"
}
```

## Reconciliation Models

### ReconciliationSummary
```json
{
  "total_transactions": "integer",
  "reconciled": "integer",
  "unreconciled": "integer",
  "suggested_matches": "integer"
}
```

### ReconciliationSuggestion
```json
{
  "suggestion_id": "uuid",
  "transaction": "OlutoTransaction",
  "suggested_match": {
    "match_type": "string (payment|bill_payment)",
    "match_id": "uuid",
    "amount": "decimal",
    "date": "string",
    "reference": "string",
    "counterparty": "string"
  },
  "confidence": "decimal",
  "match_reason": "string"
}
```

## Reporting Models

### TrialBalance
```json
{
  "as_of_date": "date",
  "total_debits": "decimal",
  "total_credits": "decimal",
  "is_balanced": "boolean",
  "entries": [
    {"account_id": "uuid", "account_code": "string", "account_name": "string", "account_type": "string", "debit": "decimal", "credit": "decimal", "balance": "decimal"}
  ]
}
```

### ProfitLossStatement
```json
{
  "period_start": "date",
  "period_end": "date",
  "total_revenue": "decimal",
  "total_expenses": "decimal",
  "net_income": "decimal",
  "revenue_entries": [{"account_id": "uuid", "account_code": "string", "account_name": "string", "account_type": "string", "amount": "decimal"}],
  "expense_entries": [{"account_id": "uuid", "account_code": "string", "account_name": "string", "account_type": "string", "amount": "decimal"}]
}
```

### BalanceSheet
```json
{
  "as_of_date": "date",
  "total_assets": "decimal",
  "total_liabilities": "decimal",
  "total_equity": "decimal",
  "asset_entries": [{"account_id": "uuid", "account_code": "string", "account_name": "string", "amount": "decimal"}],
  "liability_entries": ["..."],
  "equity_entries": ["..."]
}
```

### AccountsReceivableAging
```json
{
  "as_of_date": "date",
  "total_outstanding": "decimal",
  "buckets": [
    {
      "customer_id": "uuid",
      "customer_name": "string",
      "current": "decimal",
      "days_1_30": "decimal",
      "days_31_60": "decimal",
      "days_61_90": "decimal",
      "days_91_plus": "decimal",
      "total": "decimal"
    }
  ]
}
```

## Auth Models

### AuthResponse
```json
{
  "access_token": "string (JWT)",
  "refresh_token": "string (JWT)",
  "token_type": "bearer",
  "user": {
    "id": "uuid",
    "username": "string",
    "email": "string",
    "role": "string (viewer|accountant|admin)",
    "full_name": "string?",
    "is_active": "boolean",
    "business_id": "uuid?"
  }
}
```

## Business Model

### Business
```json
{
  "id": "uuid",
  "owner_id": "uuid",
  "name": "string",
  "province": "string?",
  "tax_profile": "object?",
  "created_at": "ISO8601",
  "updated_at": "ISO8601"
}
```
