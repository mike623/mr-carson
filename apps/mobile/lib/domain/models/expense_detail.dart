import 'package:freezed_annotation/freezed_annotation.dart';

part 'expense_detail.freezed.dart';
part 'expense_detail.g.dart';

@freezed
abstract class ExpenseItemSummary with _$ExpenseItemSummary {
  const factory ExpenseItemSummary({
    required String id,
    required String name,
    required String category,
    required double amount,
  }) = _ExpenseItemSummary;

  factory ExpenseItemSummary.fromJson(Map<String, dynamic> json) =>
      _$ExpenseItemSummaryFromJson(json);
}

@freezed
abstract class ExpenseDetail with _$ExpenseDetail {
  const factory ExpenseDetail({
    required String id,
    required String merchant,
    required List<String> categories, // expense-level tags (>=1)
    required String date,
    required double total,
    required String currency,
    String? sourceFile,
    required List<ExpenseItemSummary> items,
  }) = _ExpenseDetail;

  factory ExpenseDetail.fromJson(Map<String, dynamic> json) =>
      _$ExpenseDetailFromJson(json);
}
