import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The currency symbols the app supports. Defaults to GBP.
const List<String> kCurrencyOptions = ['£', r'$'];

/// Holds the user's selected currency symbol (default `£`). Settings and any
/// money-rendering surface read from here so the symbol stays consistent.
class CurrencyNotifier extends Notifier<String> {
  @override
  String build() => '£';

  /// Select a currency symbol (use one of [kCurrencyOptions]).
  void set(String symbol) => state = symbol;
}

/// Provider for the selected currency symbol.
final currencyProvider =
    NotifierProvider<CurrencyNotifier, String>(CurrencyNotifier.new);
