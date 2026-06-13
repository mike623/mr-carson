import 'models/ai_models.dart';

// Ported from packages/database/src/util/dateRange.ts.
// ISO week, Monday-start. All math in UTC to match the TS source exactly.

class _Range {
  final String start;
  final String end;
  const _Range(this.start, this.end);
}

String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

DateTime _startOfWeek(DateTime d) {
  // weekday: Mon=1..Sun=7  ->  days since Monday = weekday-1
  final daysSinceMonday = d.weekday - 1;
  return DateTime.utc(d.year, d.month, d.day - daysSinceMonday);
}

_Range _rangeFor(DateRange name, DateTime now) {
  final today = DateTime.utc(now.year, now.month, now.day);
  switch (name) {
    case DateRange.today:
      return _Range(_iso(today), _iso(today));
    case DateRange.yesterday:
      final y = today.subtract(const Duration(days: 1));
      return _Range(_iso(y), _iso(y));
    case DateRange.thisWeek:
      final start = _startOfWeek(today);
      return _Range(_iso(start), _iso(start.add(const Duration(days: 6))));
    case DateRange.lastWeek:
      final thisWeekStart = _startOfWeek(today);
      final start = thisWeekStart.subtract(const Duration(days: 7));
      final end = thisWeekStart.subtract(const Duration(days: 1));
      return _Range(_iso(start), _iso(end));
    case DateRange.thisMonth:
      final start = DateTime.utc(today.year, today.month, 1);
      final end = DateTime.utc(today.year, today.month + 1, 0); // day 0 = last of prev
      return _Range(_iso(start), _iso(end));
    case DateRange.lastMonth:
      final start = DateTime.utc(today.year, today.month - 1, 1);
      final end = DateTime.utc(today.year, today.month, 0);
      return _Range(_iso(start), _iso(end));
    case DateRange.thisYear:
      return _Range(_iso(DateTime.utc(today.year, 1, 1)),
          _iso(DateTime.utc(today.year, 12, 31)));
    case DateRange.allTime:
      return const _Range('0001-01-01', '9999-12-31');
  }
}

/// Returns null when no range is specified (caller leaves dates unbounded).
({String start, String end})? resolveDateRange(QueryExpensesArgs args,
    {DateTime? now}) {
  if (args.startDate != null && args.endDate != null) {
    return (start: args.startDate!, end: args.endDate!);
  }
  if (args.dateRange != null) {
    final r = _rangeFor(args.dateRange!, (now ?? DateTime.now()).toUtc());
    return (start: r.start, end: r.end);
  }
  return null;
}
