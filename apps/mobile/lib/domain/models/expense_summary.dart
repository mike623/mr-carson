import 'package:freezed_annotation/freezed_annotation.dart';

part 'expense_summary.freezed.dart';
part 'expense_summary.g.dart';

@freezed
abstract class ExpenseSummary with _$ExpenseSummary {
  const factory ExpenseSummary({
    required String id,
    required String merchant,
    required String category, // primary category (first item's category, or 'Other')
    required double total,
    required String currency,
    required String date, // YYYY-MM-DD
  }) = _ExpenseSummary;

  factory ExpenseSummary.fromJson(Map<String, dynamic> json) =>
      _$ExpenseSummaryFromJson(json);
}
