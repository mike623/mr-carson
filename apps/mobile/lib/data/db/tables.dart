import 'package:drift/drift.dart';

// Drift schema — ported from packages/database/src/schema.sql.
//
// Changes vs the DuckDB source (deliberate, see architecture brief):
//  - Dropped `user_id` everywhere: single-device app, no tenant scoping.
//  - Dropped `chat_id` from pending: Telegram concept, gone.
//  - DECIMAL(12,2) -> REAL. The TS queries already CAST to DOUBLE and round to
//    2dp in app code, so REAL matches existing arithmetic. (If you later want
//    exact money, switch to integer cents — but that changes all the SUM math.)
//  - UUID -> TEXT (uuid v4 string, assigned in Dart).
//  - DATE -> TEXT 'YYYY-MM-DD' to match the string format used in every query
//    (`e.date >= ?` compares against 'YYYY-MM-DD' literals).
//  - now() -> currentDateAndTime.

@TableIndex(name: 'idx_expenses_date', columns: {#date})
@TableIndex(name: 'idx_expenses_merchant', columns: {#merchant})
@TableIndex(name: 'idx_expenses_image_hash', columns: {#imageHash})
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get merchant => text()();
  TextColumn get date => text()(); // YYYY-MM-DD
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  RealColumn get total => real()();
  RealColumn get vat => real().withDefault(const Constant(0))();
  // Expense-level categories — JSON array of category names. Lets one expense
  // carry several tags independent of line items ("choose as many as apply").
  // Nullable for rows written before schema v2; readers fall back to the
  // distinct set of line-item categories.
  TextColumn get categories => text().nullable()();
  TextColumn get sourceFile => text().nullable()();
  TextColumn get imageHash => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_expense_items_expense', columns: {#expenseId})
@TableIndex(name: 'idx_expense_items_category', columns: {#category})
class ExpenseItems extends Table {
  TextColumn get id => text()();
  TextColumn get expenseId =>
      text().references(Expenses, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get category => text()();
  RealColumn get amount => real()();

  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get name => text()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {name};
}

class Merchants extends Table {
  TextColumn get name => text()();
  TextColumn get normalized => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {name};
}

// Pending receipts: workflow state between capture and user confirmation.
// `status` holds a PendingStatus enum name (see ai_models.dart).
// `extractedJson` holds the JSON of an ExpenseDraft once OCR+extract succeeds.
@TableIndex(name: 'idx_pending_status', columns: {#status})
class PendingExpenses extends Table {
  TextColumn get id => text()();
  TextColumn get status => text()();
  TextColumn get filePath => text().nullable()();
  TextColumn get rawOcr => text().nullable()();
  TextColumn get extractedJson => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
