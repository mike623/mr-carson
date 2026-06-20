import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/device_capability.dart';
import 'package:mr_carson/ai/model_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const capable = DeviceCapability(canRunOffline: true, reason: '');
  const incapable = DeviceCapability(canRunOffline: false, reason: 'sim');

  test('resolveBackend honours explicit modes', () {
    expect(resolveBackend(ModelMode.offline, incapable), Backend.offline);
    expect(resolveBackend(ModelMode.online, capable), Backend.online);
  });

  test('auto resolves by capability', () {
    expect(resolveBackend(ModelMode.auto, capable), Backend.offline);
    expect(resolveBackend(ModelMode.auto, incapable), Backend.online);
  });

  test('modelModeProvider persists the choice', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);

    expect(c.read(modelModeProvider), ModelMode.auto); // default
    c.read(modelModeProvider.notifier).set(ModelMode.online);
    expect(c.read(modelModeProvider), ModelMode.online);
    expect(prefs.getString('model_mode'), 'online');

    // A fresh container reading the same prefs restores the choice.
    final c2 = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c2.dispose);
    expect(c2.read(modelModeProvider), ModelMode.online);
  });
}
