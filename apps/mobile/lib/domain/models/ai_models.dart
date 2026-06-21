import 'package:freezed_annotation/freezed_annotation.dart';

part 'ai_models.freezed.dart';
part 'ai_models.g.dart';

// Domain models — ported from packages/shared-types/src/index.ts (Zod schemas).
// These are the AI boundary: what Gemma reads/writes and what tools accept.
// Drift generates its own row classes; these are the structured payloads that
// move between the model, the repositories, and the UI.

/// Default currency ISO code used when no currency can be inferred from a receipt.
const String kDefaultCurrency = 'GBP';

const List<String> kDefaultCategories = [
  'Groceries',
  'Dining',
  'Pets',
  'Transport',
  'Utilities',
  'Entertainment',
  'Health',
  'Household',
  'Shopping',
  'Travel',
  'Other',
];

@freezed
abstract class ExpenseItemDraft with _$ExpenseItemDraft {
  const factory ExpenseItemDraft({
    required String name,
    required double amount,
    required String category,
  }) = _ExpenseItemDraft;

  factory ExpenseItemDraft.fromJson(Map<String, dynamic> json) =>
      _$ExpenseItemDraftFromJson(json);
}

/// The structured expense Gemma extracts from a receipt, before it's persisted.
@freezed
abstract class ExpenseDraft with _$ExpenseDraft {
  const factory ExpenseDraft({
    required String merchant,
    required String date, // YYYY-MM-DD
    required String currency, // 3-letter, uppercase
    required double total,
    double? vat,
    required List<ExpenseItemDraft> items,
    // Expense-level category tags. Independent of line items so an expense can
    // be filed under several categories at once.
    List<String>? categories,
  }) = _ExpenseDraft;

  factory ExpenseDraft.fromJson(Map<String, dynamic> json) =>
      _$ExpenseDraftFromJson(json);
}

@freezed
abstract class OcrResult with _$OcrResult {
  const factory OcrResult({
    ExpenseDraft? structured,
    required String rawText,
    double? confidence,
  }) = _OcrResult;

  factory OcrResult.fromJson(Map<String, dynamic> json) =>
      _$OcrResultFromJson(json);
}

enum PendingStatus {
  received,
  ocrComplete,
  awaitingConfirmation,
  confirmed,
  rejected,
  inserted,
  failed,
}

enum DateRange {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  thisYear,
  allTime,
}

enum Granularity { day, week, month }

enum ChartType { bar, line, pie, doughnut }

@freezed
abstract class QueryExpensesArgs with _$QueryExpensesArgs {
  const factory QueryExpensesArgs({
    String? category,
    String? merchant,
    String? itemName,
    List<String>? itemNames, // ORed synonym expansion ("noodles" -> [...])
    DateRange? dateRange,
    String? startDate, // YYYY-MM-DD
    String? endDate, // YYYY-MM-DD
    int? limit,
    bool? includeImages,
  }) = _QueryExpensesArgs;

  factory QueryExpensesArgs.fromJson(Map<String, dynamic> json) =>
      _$QueryExpensesArgsFromJson(json);
}

@freezed
abstract class QueryRow with _$QueryRow {
  const factory QueryRow({
    required String expenseId,
    required String date,
    required String merchant,
    required String name,
    required String category,
    required double amount,
    required String currency,
    String? sourceFile,
  }) = _QueryRow;

  factory QueryRow.fromJson(Map<String, dynamic> json) =>
      _$QueryRowFromJson(json);
}

@freezed
abstract class QueryExpensesResult with _$QueryExpensesResult {
  const factory QueryExpensesResult({
    required double total,
    required double vatTotal,
    required String currency,
    required int count,
    required List<QueryRow> rows,
  }) = _QueryExpensesResult;

  factory QueryExpensesResult.fromJson(Map<String, dynamic> json) =>
      _$QueryExpensesResultFromJson(json);
}

@freezed
abstract class CategoryBucket with _$CategoryBucket {
  const factory CategoryBucket({
    required String bucket,
    required String category,
    required double total,
  }) = _CategoryBucket;

  factory CategoryBucket.fromJson(Map<String, dynamic> json) =>
      _$CategoryBucketFromJson(json);
}
