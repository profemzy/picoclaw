# Oluto AI Agent Playbooks

Each of the 8 planned AI agents has a focused set of LedgerForge API endpoints it uses. This document maps each agent to its workflows.

## Agent 1: Daily Briefing (P0)

**Purpose:** CFO-in-your-pocket morning summary.

**Workflow:**
1. Get dashboard summary: `GET /businesses/{bid}/transactions/summary`
2. Get overdue invoices: `GET /businesses/{bid}/invoices/overdue`
3. Get overdue bills: `GET /businesses/{bid}/bills/overdue`
4. Get recent transactions (overnight): `GET /businesses/{bid}/transactions?start_date=YESTERDAY&limit=10`

**Output format:** Natural language summary covering:
- Cash position (safe_to_spend from dashboard)
- Overnight transaction count + 3 largest
- Outstanding receivables total
- Upcoming payables total
- 3 prioritized action items (e.g., "Send reminder for Invoice #42, $2,400 overdue 7 days")

**Trigger:** Cron schedule (configurable, default 7 AM local time)

## Agent 2: Receipt Snap (P0)

**Purpose:** Zero-effort receipt capture and categorization.

**Workflow:**
1. Extract OCR from uploaded image:
   ```bash
   TOKEN=$(oluto-auth.sh)
   curl -H "Authorization: Bearer $TOKEN" -F "file=@RECEIPT_PATH" ${BASE_URL}/api/v1/businesses/{bid}/receipts/extract-ocr
   ```
2. Get AI category suggestion: `POST /businesses/{bid}/transactions/suggest-category` with extracted vendor/amount
3. Find matching transaction: `GET /businesses/{bid}/transactions?start_date=DATE-2d&end_date=DATE+2d&limit=20` then filter by amount match (±$5)
4. If match found, upload receipt to transaction: `POST /businesses/{bid}/transactions/{tid}/receipts`
5. If no match, create new transaction with OCR data

**Key data:** vendor, amount, date, GST/PST from OCR

## Agent 3: Conversational Bookkeeper (P0)

**Purpose:** Natural language financial queries — ask anything.

**Endpoints used:** ALL endpoints (full API surface). This agent needs access to everything.

**Example queries and endpoint mapping:**
- "How much did I spend on office supplies this quarter?" → `GET /transactions?category=Office+Expenses&start_date=...`
- "Did Sarah's invoice get paid?" → `GET /contacts/customers` → find Sarah → `GET /customers/{id}/invoices`
- "What's my GST owing this month?" → `GET /transactions/summary` → tax_collected - tax_itc
- "Am I profitable this month?" → `GET /reports/profit-loss?start_date=...&end_date=...`
- "Can I safely buy a $2,000 laptop?" → `GET /transactions/summary` → check safe_to_spend against $2,000
- "Show me all transactions from Staples" → `GET /transactions?limit=100` → filter by vendor_name
- "Create an invoice for John, $5,000 for consulting" → find John in contacts → `POST /invoices`

**Multi-turn context:** Resolve pronouns using conversation history ("What about that invoice?" → reference last mentioned invoice)

## Agent 4: Cash Flow Predictor (P1)

**Purpose:** Proactive cash flow warnings before problems happen.

**Workflow:**
1. Get transaction history (90+ days): `GET /businesses/{bid}/transactions?start_date=90_DAYS_AGO&limit=1000`
2. Get invoice aging: `GET /businesses/{bid}/reports/ar-aging?as_of_date=TODAY`
3. Get upcoming bills: `GET /businesses/{bid}/bills?status=open`
4. Get current cash position: `GET /businesses/{bid}/transactions/summary`
5. Analyze patterns: recurring expenses, seasonal trends, payment velocity
6. Project 30/60/90-day cash position

**Scenario modeling:** "What if I hire a contractor for $4,000/mo?" → subtract from projected cash flow

## Agent 5: Invoice Follow-Up (P1)

**Purpose:** Autonomous accounts receivable management.

**Workflow:**
1. Get overdue invoices: `GET /businesses/{bid}/invoices/overdue`
2. For each overdue invoice, get customer contact: `GET /businesses/{bid}/contacts/{customer_id}`
3. Determine escalation level based on days overdue:
   - Day 1: Gentle reminder
   - Day 7: Firm request
   - Day 14: Final notice
4. Draft follow-up message with invoice details
5. Track payment: `GET /businesses/{bid}/invoices/{id}/payments`

**Trigger:** Daily cron at 9 AM

## Agent 6: Tax Season Prep (P1)

**Purpose:** Perpetually CRA-ready throughout the year.

**Workflow:**
1. Find uncategorized transactions: `GET /businesses/{bid}/transactions?limit=100` → filter where category is null
2. For each, suggest category: `POST /businesses/{bid}/transactions/suggest-category`
3. Check receipt coverage: for each posted transaction, `GET /businesses/{bid}/transactions/{tid}/receipts`
4. Get P&L for tax estimate: `GET /businesses/{bid}/reports/profit-loss?start_date=JAN1&end_date=TODAY`
5. Calculate tax readiness score:
   - Categorized transactions (40% weight)
   - Receipt coverage (30% weight)
   - Filing deadline status (30% weight)

**CRA deadlines to track:**
- T2125 (self-employment): June 15
- Corporate tax: 6 months after fiscal year-end
- GST/HST: quarterly filing

## Agent 7: Smart Notifications (P2)

**Purpose:** Context-aware, actionable alerts.

**Workflow for new transaction alert:**
1. Get transaction detail: `GET /businesses/{bid}/transactions/{tid}`
2. Get AI category: `POST /businesses/{bid}/transactions/suggest-category`
3. Check for anomalies: compare amount against historical average for this vendor
4. Format enriched notification:
   - "$450 charge from Staples. Categorized as 'Office Expenses' (92% confidence), GST: $21.43"

**Anomaly detection:** Compare transaction amount against mean + 2 standard deviations of same-vendor transactions

## Agent 8: Vendor Intelligence (P2)

**Purpose:** Spending pattern analysis and cost optimization.

**Workflow:**
1. Get all transactions: `GET /businesses/{bid}/transactions?limit=1000`
2. Group by vendor_name, calculate:
   - Monthly spend per vendor
   - Month-over-month change
   - Price increase detection (>5% MoM for 2+ months)
3. Get vendor contacts: `GET /businesses/{bid}/contacts/vendors`
4. Identify optimization opportunities:
   - Duplicate vendors (similar names, same category)
   - Bulk discount candidates (frequent small purchases)
   - Contract renewal reminders

**Output:** Top 10 vendors ranked by spend, with trend indicators and recommendations
