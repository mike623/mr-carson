import 'package:flutter/material.dart';

import 'package:mr_carson/theme/app_theme.dart';

const _monthsLong = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _isoOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Today's date as `YYYY-MM-DD` (local).
String todayIso() => _isoOf(DateTime.now());

/// `'11 June 2026'` from an ISO date string. Falls back to the raw string.
String formatLongDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.day} ${_monthsLong[d.month]} ${d.year}';
}

/// Relative subtitle for a date: "Today", "Yesterday", else the weekday name.
String relativeDateLabel(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const weekdays = [
    '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
    'Saturday', 'Sunday',
  ];
  return weekdays[day.weekday];
}

/// Opens a brass-themed date picker seeded from [currentIso]; returns the
/// chosen date as `YYYY-MM-DD`, or null if dismissed.
Future<String?> pickDate(BuildContext context, String currentIso) async {
  final seed = DateTime.tryParse(currentIso) ?? DateTime.now();
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: seed,
    firstDate: DateTime(2000),
    lastDate: DateTime(now.year + 1, 12, 31),
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: MrCarsonColors.accent,
          onPrimary: MrCarsonColors.accentInk,
          surface: MrCarsonColors.surface,
          onSurface: MrCarsonColors.ink,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: MrCarsonColors.surface,
        ),
      ),
      child: child!,
    ),
  );
  return picked == null ? null : _isoOf(picked);
}
