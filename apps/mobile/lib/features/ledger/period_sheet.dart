import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mr_carson/domain/date_range.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/features/settings/currency_provider.dart';
import 'package:mr_carson/theme/app_theme.dart';

import 'ledger_period.dart';

/// Bottom sheet for choosing the Ledger's reporting period — named presets
/// (each with its total) plus a custom range picked on the calendar.
///
/// Commits the choice through [periodProvider] and closes itself.
Future<void> showPeriodSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => const _PeriodSheet(),
  );
}

class _PeriodSheet extends ConsumerStatefulWidget {
  const _PeriodSheet();

  @override
  ConsumerState<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends ConsumerState<_PeriodSheet> {
  late DateTime _visibleMonth;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);
    // Seed the calendar from an existing custom selection.
    final period = ref.read(periodProvider);
    if (period.isCustom) {
      _rangeStart = DateTime.parse(period.startIso!);
      _rangeEnd = DateTime.parse(period.endIso!);
      _visibleMonth = DateTime(_rangeStart!.year, _rangeStart!.month, 1);
    }
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _pickPreset(DateRange r) {
    ref.read(periodProvider.notifier).setPreset(r);
    Navigator.of(context).pop();
  }

  void _tapDay(DateTime day) {
    setState(() {
      if (_rangeStart == null || _rangeEnd != null) {
        // Begin a fresh selection.
        _rangeStart = day;
        _rangeEnd = null;
      } else if (day.isBefore(_rangeStart!)) {
        _rangeStart = day;
      } else {
        _rangeEnd = day;
      }
    });
  }

  void _applyCustom() {
    if (_rangeStart == null) return;
    final end = _rangeEnd ?? _rangeStart!;
    ref.read(periodProvider.notifier).setCustom(_iso(_rangeStart!), _iso(end));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(periodProvider);
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: MrCarsonColors.surface,
          border: Border(top: BorderSide(color: MrCarsonColors.line)),
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(MrCarsonRadii.sheet)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
        child: ListView(
          controller: scrollController,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: MrCarsonColors.ink3.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text('Choose a period',
                style: MrCarsonType.display(size: 26, weight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(
              period.isCustom
                  ? formatRangeLabel(period.startIso!, period.endIso!)
                  : 'Currently ${period.label.toLowerCase()}',
              style: MrCarsonType.ui(size: 13, color: MrCarsonColors.ink3),
            ),
            const SizedBox(height: 18),

            // Presets
            for (final r in LedgerPeriod.presets) ...[
              _PresetRow(
                range: r,
                selected: !period.isCustom && period.preset == r,
                onTap: () => _pickPreset(r),
              ),
              const SizedBox(height: 8),
            ],

            // Divider
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 12, 2, 14),
              child: Row(
                children: [
                  const Expanded(child: Divider(color: MrCarsonColors.line)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or a particular range',
                        style: MrCarsonType.display(
                            size: 14,
                            color: MrCarsonColors.ink3,
                            italic: true)),
                  ),
                  const Expanded(child: Divider(color: MrCarsonColors.line)),
                ],
              ),
            ),

            _Calendar(
              visibleMonth: _visibleMonth,
              rangeStart: _rangeStart,
              rangeEnd: _rangeEnd,
              onPrev: () => setState(() => _visibleMonth =
                  DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1)),
              onNext: () => setState(() => _visibleMonth =
                  DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1)),
              onTapDay: _tapDay,
            ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _rangeStart == null ? null : _applyCustom,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MrCarsonColors.accent,
                  disabledBackgroundColor:
                      MrCarsonColors.accent.withValues(alpha: 0.35),
                  foregroundColor: MrCarsonColors.accentInk,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text('Apply',
                    style: MrCarsonType.ui(
                        size: 16,
                        weight: FontWeight.w600,
                        color: MrCarsonColors.accentInk)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preset row — radio ring + label + sub + total
// ---------------------------------------------------------------------------

class _PresetRow extends ConsumerWidget {
  const _PresetRow({
    required this.range,
    required this.selected,
    required this.onTap,
  });

  final DateRange range;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iso = isoRangeFor(range);
    final symbol = ref.watch(currencyProvider);
    final totalAsync = ref.watch(presetTotalProvider(range));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? MrCarsonColors.accentSoft : MrCarsonColors.bg,
          border: Border.all(
              color: selected ? MrCarsonColors.accent : MrCarsonColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? MrCarsonColors.accent : MrCarsonColors.ink3,
                  width: 1.6,
                ),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MrCarsonColors.accent
                      .withValues(alpha: selected ? 1 : 0),
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(LedgerPeriod.labelFor(range),
                      style: MrCarsonType.ui(
                          size: 15.5, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(formatRangeLabel(iso.start, iso.end),
                      style:
                          MrCarsonType.ui(size: 12, color: MrCarsonColors.ink3)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            totalAsync.when(
              data: (total) => Text(
                '$symbol${total.toStringAsFixed(2)}',
                style: MrCarsonType.display(
                  size: 19,
                  weight: FontWeight.w600,
                  color: selected ? MrCarsonColors.accent : MrCarsonColors.ink,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              loading: () => Text('$symbol—',
                  style: MrCarsonType.display(
                      size: 19,
                      weight: FontWeight.w600,
                      color: MrCarsonColors.ink3)),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Calendar — Monday-start month grid with spending dots + range selection
// ---------------------------------------------------------------------------

class _Calendar extends ConsumerWidget {
  const _Calendar({
    required this.visibleMonth,
    required this.rangeStart,
    required this.rangeEnd,
    required this.onPrev,
    required this.onNext,
    required this.onTapDay,
  });

  final DateTime visibleMonth;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onTapDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = visibleMonth.year;
    final month = visibleMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // Mon=1..Sun=7 -> leading blanks before day 1.
    final leadingBlanks = DateTime(year, month, 1).weekday - 1;

    final dailyTotals =
        ref.watch(monthDailyTotalsProvider((year: year, month: month)));
    final totalsMap = dailyTotals.value ?? const <String, double>{};

    final cells = <Widget>[];
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox(height: 38));
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final iso =
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      cells.add(_DayCell(
        day: day,
        hasDot: (totalsMap[iso] ?? 0) > 0,
        state: _cellState(date),
        onTap: () => onTapDay(date),
      ));
    }

    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.bg,
        border: Border.all(color: MrCarsonColors.line),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _NavButton(icon: Icons.chevron_left, onTap: onPrev),
              Text(monthLongLabel(year, month),
                  style:
                      MrCarsonType.display(size: 18, weight: FontWeight.w600)),
              _NavButton(icon: Icons.chevron_right, onTap: onNext),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(
                    child: Text(d,
                        style: MrCarsonType.ui(
                            size: 10.5,
                            weight: FontWeight.w600,
                            color: MrCarsonColors.ink3,
                            letterSpacing: 0.5)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            childAspectRatio: 1.05,
            children: cells,
          ),
        ],
      ),
    );
  }

  _DayState _cellState(DateTime date) {
    final start = rangeStart;
    if (start == null) return _DayState.normal;
    final end = rangeEnd;
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(start.year, start.month, start.day);
    if (end == null) {
      return d == s ? _DayState.edge : _DayState.normal;
    }
    final e = DateTime(end.year, end.month, end.day);
    if (d == s || d == e) return _DayState.edge;
    if (d.isAfter(s) && d.isBefore(e)) return _DayState.between;
    return _DayState.normal;
  }
}

enum _DayState { normal, edge, between }

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.hasDot,
    required this.state,
    required this.onTap,
  });

  final int day;
  final bool hasDot;
  final _DayState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isEdge = state == _DayState.edge;
    final isBetween = state == _DayState.between;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isEdge
              ? MrCarsonColors.accent
              : isBetween
                  ? MrCarsonColors.accentSoft
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(isEdge ? 11 : 8),
        ),
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '$day',
              style: MrCarsonType.ui(
                size: 14,
                weight: isEdge ? FontWeight.w700 : FontWeight.w500,
                color: isEdge
                    ? MrCarsonColors.accentInk
                    : MrCarsonColors.ink,
              ),
            ),
            if (hasDot && !isEdge)
              Positioned(
                bottom: 5,
                child: Container(
                  width: 3.5,
                  height: 3.5,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: MrCarsonColors.accent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: MrCarsonColors.surface,
          border: Border.all(color: MrCarsonColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: MrCarsonColors.ink2),
      ),
    );
  }
}
