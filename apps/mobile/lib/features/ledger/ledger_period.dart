import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/domain/date_range.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/domain/models/expense_summary.dart';
import 'package:mr_carson/domain/models/monthly_summary.dart';

// ---------------------------------------------------------------------------
// Period model
// ---------------------------------------------------------------------------

/// The Ledger's active reporting period — either a named preset or a custom
/// inclusive ISO range chosen on the calendar.
class LedgerPeriod {
  const LedgerPeriod.preset(this.preset)
      : startIso = null,
        endIso = null;

  const LedgerPeriod.custom(String this.startIso, String this.endIso)
      : preset = null;

  /// Null when a custom range is active.
  final DateRange? preset;

  /// Inclusive ISO bounds — non-null only for a custom range.
  final String? startIso;
  final String? endIso;

  static const _presetLabels = {
    DateRange.thisMonth: 'This month',
    DateRange.lastMonth: 'Last month',
    DateRange.thisWeek: 'This week',
    DateRange.lastWeek: 'Last week',
    DateRange.thisYear: 'This year',
    DateRange.allTime: 'All time',
  };

  /// Presets offered in the period sheet, in display order.
  static const presets = [
    DateRange.thisMonth,
    DateRange.lastMonth,
    DateRange.thisWeek,
    DateRange.lastWeek,
    DateRange.thisYear,
    DateRange.allTime,
  ];

  bool get isCustom => preset == null;

  /// Short label for the header chip.
  String get label =>
      preset == null ? 'Custom' : (_presetLabels[preset] ?? 'This month');

  static String labelFor(DateRange r) => _presetLabels[r] ?? r.name;

  /// Inclusive ISO `(start, end)` bounds for querying.
  ({String start, String end}) resolve({DateTime? now}) {
    if (preset != null) return isoRangeFor(preset!, now: now);
    return (start: startIso!, end: endIso!);
  }
}

// ---------------------------------------------------------------------------
// Date formatting helpers (shared with the period sheet)
// ---------------------------------------------------------------------------

const _monthsShort = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _monthsLong = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String monthLongLabel(int year, int month) => '${_monthsLong[month]} $year';

/// Human range subtitle, e.g. "1–30 Jun 2026" or "1 Jun – 3 Jul 2026".
String formatRangeLabel(String startIso, String endIso) {
  if (startIso.startsWith('0001') && endIso.startsWith('9999')) {
    return 'Every receipt on file';
  }
  final s = DateTime.parse(startIso);
  final e = DateTime.parse(endIso);
  if (s.year == e.year && s.month == e.month) {
    return '${s.day}–${e.day} ${_monthsShort[s.month]} ${s.year}';
  }
  if (s.year == e.year) {
    return '${s.day} ${_monthsShort[s.month]} – ${e.day} ${_monthsShort[e.month]} ${s.year}';
  }
  return '${s.day} ${_monthsShort[s.month]} ${s.year} – '
      '${e.day} ${_monthsShort[e.month]} ${e.year}';
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

class PeriodNotifier extends StateNotifier<LedgerPeriod> {
  PeriodNotifier() : super(const LedgerPeriod.preset(DateRange.thisMonth));

  void setPreset(DateRange range) =>
      state = LedgerPeriod.preset(range);

  void setCustom(String startIso, String endIso) =>
      state = LedgerPeriod.custom(startIso, endIso);
}

/// The Ledger's active period selection.
final periodProvider =
    StateNotifierProvider<PeriodNotifier, LedgerPeriod>((ref) {
  return PeriodNotifier();
});

/// Category summary for the active period.
final periodSummaryProvider = StreamProvider<MonthlySummary>((ref) {
  final period = ref.watch(periodProvider).resolve();
  return ref
      .watch(expenseRepositoryProvider)
      .watchSummaryInRange(period.start, period.end);
});

/// Expenses within the active period, newest first.
final periodExpensesProvider = StreamProvider<List<ExpenseSummary>>((ref) {
  final period = ref.watch(periodProvider).resolve();
  return ref
      .watch(expenseRepositoryProvider)
      .watchExpensesInRange(period.start, period.end);
});

/// Per-day spend totals for a calendar month (`YYYY-MM-DD` → total).
final monthDailyTotalsProvider =
    StreamProvider.family<Map<String, double>, ({int year, int month})>(
        (ref, ym) {
  final start = DateTime(ym.year, ym.month, 1);
  final end = DateTime(ym.year, ym.month + 1, 0); // last day of month
  String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return ref
      .watch(expenseRepositoryProvider)
      .watchDailyTotals(iso(start), iso(end));
});

/// Total for a given preset — used to label the period-sheet rows.
final presetTotalProvider =
    StreamProvider.family<double, DateRange>((ref, range) {
  final r = isoRangeFor(range);
  return ref
      .watch(expenseRepositoryProvider)
      .watchSummaryInRange(r.start, r.end)
      .map((s) => s.total);
});
