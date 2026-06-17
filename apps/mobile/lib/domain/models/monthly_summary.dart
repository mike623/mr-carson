import 'package:freezed_annotation/freezed_annotation.dart';

import 'ai_models.dart';

part 'monthly_summary.freezed.dart';
part 'monthly_summary.g.dart';

@freezed
abstract class MonthlySummary with _$MonthlySummary {
  const factory MonthlySummary({
    required String month, // YYYY-MM
    required double total,
    required String currency,
    required List<CategoryBucket> buckets,
  }) = _MonthlySummary;

  factory MonthlySummary.fromJson(Map<String, dynamic> json) =>
      _$MonthlySummaryFromJson(json);
}
