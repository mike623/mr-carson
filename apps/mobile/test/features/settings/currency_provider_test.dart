import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/features/settings/currency_provider.dart';

void main() {
  test('currency defaults to £', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(currencyProvider), '£');
  });

  test("set(' ' + dollar) updates the selected symbol", () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(currencyProvider.notifier).set(r'$');
    expect(container.read(currencyProvider), r'$');
  });

  test('kCurrencyOptions exposes £ and \$', () {
    expect(kCurrencyOptions, containsAll(<String>['£', r'$']));
  });
}
