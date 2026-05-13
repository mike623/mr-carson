// Inlined schema so bundlers (Mastra dev) ship it with the JS.
// Keep in sync with the human-friendly schema.sql in this directory.
export const SCHEMA_SQL = `-- Mr. Carson DuckDB schema
-- Source of truth for both confirmed expenses and pending workflow state.

CREATE TABLE IF NOT EXISTS categories (
  name TEXT PRIMARY KEY,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS merchants (
  name TEXT PRIMARY KEY,
  normalized TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS expenses (
  id UUID PRIMARY KEY,
  user_id TEXT NOT NULL,
  merchant TEXT NOT NULL,
  date DATE NOT NULL,
  currency TEXT NOT NULL,
  total DECIMAL(12, 2) NOT NULL,
  vat DECIMAL(12, 2) DEFAULT 0,
  source_file TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT now()
);

-- Backfill: existing DBs predate the vat column. DuckDB doesn't allow
-- NOT NULL on ALTER ADD COLUMN, so we add nullable + DEFAULT 0, then
-- backfill any rows that didn't get the default to 0.
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS vat DECIMAL(12, 2) DEFAULT 0;
UPDATE expenses SET vat = 0 WHERE vat IS NULL;

CREATE INDEX IF NOT EXISTS idx_expenses_user_date ON expenses (user_id, date);
CREATE INDEX IF NOT EXISTS idx_expenses_user_merchant ON expenses (user_id, merchant);

CREATE TABLE IF NOT EXISTS expense_items (
  id UUID PRIMARY KEY,
  expense_id UUID NOT NULL REFERENCES expenses(id),
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  amount DECIMAL(12, 2) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_expense_items_expense ON expense_items (expense_id);
CREATE INDEX IF NOT EXISTS idx_expense_items_category ON expense_items (category);

-- Pending receipts: hold workflow state between OCR and user confirmation.
CREATE TABLE IF NOT EXISTS pending_expenses (
  id UUID PRIMARY KEY,
  user_id TEXT NOT NULL,
  chat_id TEXT NOT NULL,
  status TEXT NOT NULL,
  file_path TEXT,
  raw_ocr TEXT,
  extracted_json TEXT,
  error_message TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT now(),
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pending_user_status ON pending_expenses (user_id, status);

-- Chat sessions: one active conversation thread per user. /new rotates the
-- active thread id; prior threads remain in Mastra Memory storage.
CREATE TABLE IF NOT EXISTS chat_sessions (
  user_id TEXT PRIMARY KEY,
  active_thread_id TEXT NOT NULL,
  started_at TIMESTAMP NOT NULL DEFAULT now()
);
`;
