// Shared currency formatting helpers.
//
// Extracted from ledger_screen.dart and detail_screen.dart to avoid
// duplication.  Import this file in any feature that needs currency
// display strings.

/// Returns the currency symbol for a given ISO-4217 [currency] code.
///
/// Falls back to `'<code> '` (with a trailing space) for unknown codes so
/// the amount is still readable.
String currencySymbol(String currency) {
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

/// Formats [amount] as a two-decimal-place string, e.g. `'12.50'`.
String formatAmount(double amount) {
  return amount.toStringAsFixed(2);
}
