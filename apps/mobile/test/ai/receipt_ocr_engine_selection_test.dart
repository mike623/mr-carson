import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/device_capability.dart';
import 'package:mr_carson/ai/model_mode.dart';
import 'package:mr_carson/ai/receipt_ocr_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container(List<Override> extra) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs), ...extra],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('online mode yields CloudOcrEngine', () async {
    final c = await _container([]);
    c.read(modelModeProvider.notifier).set(ModelMode.online);
    expect(c.read(receiptOcrEngineProvider), isA<CloudOcrEngine>());
  });

  test('offline mode yields GemmaOcrEngine', () async {
    final c = await _container([]);
    c.read(modelModeProvider.notifier).set(ModelMode.offline);
    expect(c.read(receiptOcrEngineProvider), isA<GemmaOcrEngine>());
  });

  test('auto + incapable device yields CloudOcrEngine', () async {
    final c = await _container([]);
    c.read(deviceCapabilityProvider.notifier).state =
        const DeviceCapability(canRunOffline: false, reason: 'sim');
    // mode defaults to auto
    expect(c.read(receiptOcrEngineProvider), isA<CloudOcrEngine>());
  });
}
