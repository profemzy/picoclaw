# LedgerForge API Endpoints Reference

Base URL: Configured in `~/.oluto-config.json` (default: `http://localhost:3000`)
Auth: All endpoints except health and auth require `Authorization: Bearer <JWT>`
Response envelope: `{ "success": bool, "data": <T> }`

## Auth (Public)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/auth/register` | Register new user. Body: `{email, password, username?, role?, full_name?}`. Returns tokens + user. |
| POST | `/api/v1/auth/login` | Login. Body: `{username, password}`. Returns `{access_token, refresh_token, token_type, user}`. |
| POST | `/api/v1/auth/refresh` | Refresh token. Body: `{refresh_token}`. Returns new access token. |
| GET | `/api/v1/auth/me` | Get current user profile. Returns `{id, username, email, role, business_id?}`. |
| GET | `/api/v1/health` | Health check (no auth). Returns `{status, version, database, cache}`. |

## Businesses

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/businesses` | Create business. Body: `{name, province?, tax_profile?}`. |
| GET | `/api/v1/businesses` | List businesses owned by current user. |
| GET | `/api/v1/businesses/{id}` | Get business by ID. |
| PATCH | `/api/v1/businesses/{id}` | Update business. Body: `{name?, province?, tax_profile?}`. |

## Accounts

Path prefix: `/api/v1/businesses/{business_id}/accounts`

| Method | Path | Query Params | Description |
|--------|------|-------------|-------------|
| GET | `/accounts` | `account_type?`, `parent_id?`, `include_inactive?` | List accounts with optional filters. |
| POST | `/accounts` | — | Create account. Body: `{code, name, account_type, parent_account_id?}`. |
| GET | `/accounts/{id}` | — | Get account by ID. |
| PUT | `/accounts/{id}` | — | Update account. Body: `{name?, is_active?}`. |
| DELETE | `/accounts/{id}` | — | Deactivate account (must have no transactions). |
| GET | `/accounts/{id}/hierarchy` | — | Get parent + children tree. |
| GET | `/accounts/{id}/balance` | — | Get current balance (posted transactions only). |

## Oluto Transactions (Business-Scoped)

Path prefix: `/api/v1/businesses/{business_id}/transactions`

| Method | Path | Query/Body | Description |
|--------|------|-----------|-------------|
| GET | `/transactions` | `status?`, `start_date?`, `end_date?`, `skip?`, `limit?` | List transactions with filters. |
| POST | `/transactions` | Body: `OlutoTransactionCreate` | Create transaction. |
| GET | `/transactions/summary` | — | Dashboard KPIs: revenue, expenses, safe-to-spend, tax, AR/AP, exceptions, status counts, recent txns. |
| GET | `/transactions/{id}` | — | Get single transaction. |
| PATCH | `/transactions/{id}` | Body: `OlutoTransactionUpdate` | Partial update. |
| DELETE | `/transactions/{id}` | — | Delete (draft only). |
| PATCH | `/transactions/bulk-status` | Body: `{transaction_ids?, batch_id?, status}` | Bulk status update. |
| POST | `/transactions/suggest-category` | Body: `{vendor_name, amount?, description?}` | AI category suggestion. Returns `{category, confidence, reasoning?}`. |
| GET | `/transactions/duplicates` | — | Find duplicate transactions (same date+amount+vendor). |
| POST | `/transactions/import/parse` | multipart file | Parse CSV (sync) or PDF (async job) for preview. |
| POST | `/transactions/import/confirm` | Body: `{file_type, transactions[]}` | Confirm and create imported transactions. |
| GET | `/transactions/jobs/{job_id}` | — | Poll PDF import job status. |

## Contacts

Path prefix: `/api/v1/businesses/{business_id}/contacts`

| Method | Path | Query | Description |
|--------|------|-------|-------------|
| GET | `/contacts` | `contact_type?`, `limit?` | List all contacts. |
| POST | `/contacts` | — | Create contact. Body: `{contact_type, name, email?, phone?, billing_address?, shipping_address?}`. |
| GET | `/contacts/{id}` | — | Get contact by ID. |
| PUT | `/contacts/{id}` | — | Update contact. Body: `{name?, email?, phone?, billing_address?, shipping_address?}`. |
| DELETE | `/contacts/{id}` | — | Delete (fails if contact has transactions). |
| GET | `/contacts/customers` | — | List customers only. |
| GET | `/contacts/vendors` | — | List vendors only. |
| GET | `/contacts/employees` | — | List employees only. |

## Invoices (A/R)

Path prefix: `/api/v1/businesses/{business_id}/invoices`

| Method | Path | Query | Description |
|--------|------|-------|-------------|
| GET | `/invoices` | `customer_id?`, `status?`, `limit?`, `offset?` | List invoices. |
| POST | `/invoices` | — | Create invoice. Body: `{invoice_number, customer_id, invoice_date, due_date, line_items[]}`. |
| GET | `/invoices/{id}` | — | Get invoice with line items. |
| PUT | `/invoices/{id}/status` | — | Update status. Body: `{status}`. Values: draft, sent, paid, partial, overdue, void. |
| GET | `/invoices/overdue` | — | List overdue invoices. |
| GET | `/customers/{id}/invoices` | — | List invoices for a specific customer. |
| GET | `/invoices/{id}/payments` | — | List payments applied to an invoice. |

## Payments (Customer A/R)

Path prefix: `/api/v1/businesses/{business_id}/payments`

| Method | Path | Query | Description |
|--------|------|-------|-------------|
| GET | `/payments` | `customer_id?`, `unapplied_only?`, `limit?`, `offset?` | List payments. |
| POST | `/payments` | — | Create payment. Body: `{customer_id, payment_date, amount, payment_method, applications[{invoice_id, amount_applied}]}`. |
| GET | `/payments/{id}` | — | Get payment details. |
| PUT | `/payments/{id}/apply` | — | Apply payment to invoices. Body: `{applications[{invoice_id, amount_applied}]}`. |
| GET | `/payments/unapplied` | — | List unapplied payments. |

## Bills (A/P)

Path prefix: `/api/v1/businesses/{business_id}/bills`

| Method | Path | Query | Description |
|--------|------|-------|-------------|
| GET | `/bills` | `vendor_id?`, `status?`, `limit?`, `offset?` | List bills. |
| POST | `/bills` | — | Create bill. Body: `{vendor_id, bill_date, due_date, line_items[{line_number, description?, amount, expense_account_id}]}`. |
| GET | `/bills/{id}` | — | Get bill with line items. |
| PUT | `/bills/{id}/status` | — | Update status. Body: `{status}`. Values: open, paid, partial, void. |
| DELETE | `/bills/{id}` | — | Delete bill. |
| GET | `/bills/overdue` | — | List overdue bills. |
| GET | `/vendors/{id}/bills` | — | List bills for a specific vendor. |

## Bill Payments (Vendor A/P)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/businesses/{bid}/bill-payments` | Create bill payment. Body: `{vendor_id, payment_date, amount, payment_method, applications[{bill_id, amount_applied}]}`. |

## Receipts

Path prefix: `/api/v1/businesses/{business_id}`

| Method | Path | Description |
|--------|------|-------------|
| POST | `/transactions/{tid}/receipts` | Upload receipt (multipart: file, run_ocr?). Returns receipt + OCR data. |
| GET | `/transactions/{tid}/receipts` | List receipts for transaction. |
| GET | `/receipts/{rid}` | Get receipt metadata. |
| DELETE | `/receipts/{rid}` | Delete receipt. |
| GET | `/receipts/{rid}/download` | Get signed download URL. |
| POST | `/receipts/extract-ocr` | Extract OCR only (multipart: file). No receipt saved. |
| POST | `/bills/{bid}/receipts` | Upload receipt for bill (multipart). |
| GET | `/bills/{bid}/receipts` | List receipts for bill. |

## Reconciliation

Path prefix: `/api/v1/businesses/{business_id}/reconciliation`

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/summary` | — | Reconciliation stats: total, reconciled, unreconciled, suggested_matches. |
| GET | `/suggestions` | — | AI-matched suggestions (pending approval). |
| GET | `/unreconciled` | `limit?`, `offset?` | List unreconciled transactions. |
| POST | `/confirm` | `{transaction_id, match_id, match_type}` | Confirm a match. match_type: payment or bill_payment. |
| POST | `/reject` | `{suggestion_id}` | Reject a suggestion. |
| POST | `/unlink` | `{transaction_id}` | Unlink a confirmed match. |
| POST | `/auto` | `{min_confidence?: 0.9}` | Auto-reconcile high-confidence matches. |
| POST | `/mark-reconciled` | `{transaction_ids: []}` | Manually mark transactions reconciled. |
| POST | `/mark-unreconciled` | `{transaction_ids: []}` | Mark transactions unreconciled. |
| GET | `/reconciled` | `limit?`, `offset?` | List reconciled transactions. |

## Reporting

Path prefix: `/api/v1/businesses/{business_id}/reports`

| Method | Path | Query | Description |
|--------|------|-------|-------------|
| GET | `/trial-balance` | `as_of_date` (required) | Trial balance as of date. Returns entries with debit/credit/balance per account. |
| GET | `/profit-loss` | `start_date`, `end_date` (required) | P&L for period. Returns revenue/expense entries + net income. |
| GET | `/balance-sheet` | `as_of_date` (required) | Balance sheet. Returns assets/liabilities/equity entries + totals. |
| GET | `/ar-aging` | `as_of_date` (required) | A/R aging. Returns buckets: current, 1-30, 31-60, 61-90, 91+ days per customer. |

## Import (Legacy)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/import/accounts` | Bulk import accounts from CSV (multipart). |
| GET | `/api/v1/import/accounts/template` | Download CSV template. |
