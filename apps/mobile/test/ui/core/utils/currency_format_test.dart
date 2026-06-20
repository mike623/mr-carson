import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ui/core/utils/currency_format.dart';

void main() {
  group('currencyCode (symbol → ISO)', () {
    test('maps known symbols', () {
      expect(currencyCode('£'), 'GBP');
      expect(currencyCode(r'$'), 'USD');
      expect(currencyCode('€'), 'EUR');
    });

    test('unknown symbol falls back to GBP', () {
      expect(currencyCode('¥'), 'GBP');
      expect(currencyCode(''), 'GBP');
    });

    test('round-trips with currencySymbol', () {
      for (final sym in ['£', r'$', '€']) {
        expect(currencySymbol(currencyCode(sym)), sym);
      }
    });
  });
}
