import 'package:flutter/material.dart';

import 'package:mr_carson/theme/app_theme.dart';

/// Shared, presentation-only formatting helpers for the read-side UI.
///
/// These mirror the private `_money` helpers used in the confirm/shell screens,
/// hoisted so the ledger + detail screens (spec §3) format money and dates
/// identically without duplicating the switch in every widget.

/// Currency symbol for a 3-letter ISO code, falling back to "CODE ".
String currencyPrefix(String currency) {
  switch (currency.toUpperCase()) {
    case 'GBP':
      return '£';
    case 'USD':
      return '\$';
    case 'EUR':
      return '€';
    default:
      return '$currency ';
  }
}

/// Formats [amount] with the symbol for [currency], 2dp (e.g. "£6.15").
String formatMoney(String currency, double amount) =>
    '${currencyPrefix(currency)}${amount.toStringAsFixed(2)}';

const _monthNames = <String>[
  '',
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Renders a stored 'YYYY-MM-DD' date as the design's "12 June 2026".
///
/// Falls back to the raw string if it cannot be parsed.
String formatLongDate(String isoDate) {
  final parts = isoDate.split('-');
  if (parts.length != 3) return isoDate;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return isoDate;
  if (month < 1 || month > 12) return isoDate;
  return '$day ${_monthNames[month]} $year';
}

/// Renders a 'YYYY-MM' month key as the design's "June 2026".
///
/// Falls back to the raw string if it cannot be parsed.
String formatLongMonth(String monthKey) {
  final parts = monthKey.split('-');
  if (parts.length != 2) return monthKey;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null) return monthKey;
  if (month < 1 || month > 12) return monthKey;
  return '${_monthNames[month]} $year';
}

/// Maps a category name to its palette colour, matching the design's legend.
///
/// Unknown categories cycle through the accent / category hues so the donut and
/// legend always agree. "Other" (and anything unmapped after the cycle) falls
/// back to a muted ink.
Color categoryColor(String category, {int index = 0}) {
  switch (category.toLowerCase()) {
    case 'dining':
    case 'restaurants':
    case 'food':
      return MrCarsonColors.accent;
    case 'groceries':
      return MrCarsonColors.grocery;
    case 'transport':
    case 'travel':
      return MrCarsonColors.transport;
    case 'household':
    case 'house':
    case 'home':
      return MrCarsonColors.house;
    case 'other':
      return MrCarsonColors.ink3;
  }
  // Unmapped categories: cycle the palette so slices stay distinguishable.
  const palette = <Color>[
    MrCarsonColors.accent,
    MrCarsonColors.grocery,
    MrCarsonColors.transport,
    MrCarsonColors.house,
  ];
  return palette[index % palette.length];
}
