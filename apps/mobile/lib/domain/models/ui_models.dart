import 'package:freezed_annotation/freezed_annotation.dart';

import 'ai_models.dart';

part 'ui_models.freezed.dart';
part 'ui_models.g.dart';

// UI / read-side domain models — the reactive data layer's outputs.
//
// These are distinct from ai_models.dart (the AI/tool boundary). They are
// projections shaped for the ledger, detail, donut, and chart surfaces and are
// produced by ExpenseRepository's `.watch()` streams. They never cross into
// Gemma — they are read-only views of persisted data.

/// One row in the ledger list: an expense header (no line items).
///
/// `total` is the receipt total; `vat` is the receipt-level VAT. `date` is the
/// stored 'YYYY-MM-DD' text. `itemCount` is how many line items the expense has.
@freezed
abstract class ExpenseSummary with _$ExpenseSummary {
  const factory ExpenseSummary({
    required String id,
    required String merchant,
    required String date, // YYYY-MM-DD
    required String currency,
    required double total,
    required double vat,
    required int itemCount,
  }) = _ExpenseSummary;

  factory ExpenseSummary.fromJson(Map<String, dynamic> json) =>
      _$ExpenseSummaryFromJson(json);
}

/// A single category slice of a [MonthlySummary] — powers the donut.
@freezed
abstract class CategorySlice with _$CategorySlice {
  const factory CategorySlice({
    required String category,
    required double total,
  }) = _CategorySlice;

  factory CategorySlice.fromJson(Map<String, dynamic> json) =>
      _$CategorySliceFromJson(json);
}

/// Spending rollup for a single calendar month.
///
/// `total` is the sum of expense-level totals in the month. `byCategory` is the
/// per-category breakdown computed from line items (descending by total). The
/// two need not be equal: category buckets sum line items, while `total` sums
/// receipt totals (which may include rounding / unitemised amounts).
@freezed
abstract class MonthlySummary with _$MonthlySummary {
  const factory MonthlySummary({
    required String month, // YYYY-MM
    required double total,
    required String currency,
    required int expenseCount,
    required List<CategorySlice> byCategory,
  }) = _MonthlySummary;

  factory MonthlySummary.fromJson(Map<String, dynamic> json) =>
      _$MonthlySummaryFromJson(json);
}

/// One line item belonging to an expense, for the detail screen.
@freezed
abstract class ExpenseLineItem with _$ExpenseLineItem {
  const factory ExpenseLineItem({
    required String id,
    required String name,
    required String category,
    required double amount,
  }) = _ExpenseLineItem;

  factory ExpenseLineItem.fromJson(Map<String, dynamic> json) =>
      _$ExpenseLineItemFromJson(json);
}

/// An expense header plus its line items — the detail-screen payload.
@freezed
abstract class ExpenseDetail with _$ExpenseDetail {
  const factory ExpenseDetail({
    required String id,
    required String merchant,
    required String date, // YYYY-MM-DD
    required String currency,
    required double total,
    required double vat,
    String? sourceFile,
    required List<ExpenseLineItem> items,
  }) = _ExpenseDetail;

  factory ExpenseDetail.fromJson(Map<String, dynamic> json) =>
      _$ExpenseDetailFromJson(json);
}

/// Chart-ready projection of [CategoryBucket] data over time.
///
/// Thin wrapper around `AppDatabase.byCategoryOverTime` so the chart tool/UI
/// consumes a single typed value (buckets + granularity + currency) instead of
/// an inline record.
@freezed
abstract class ChartData with _$ChartData {
  const factory ChartData({
    required List<CategoryBucket> buckets,
    required Granularity granularity,
    required String currency,
  }) = _ChartData;

  factory ChartData.fromJson(Map<String, dynamic> json) =>
      _$ChartDataFromJson(json);
}
