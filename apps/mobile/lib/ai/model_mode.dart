import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_capability.dart';

/// Holds the [SharedPreferences] instance. Overridden in `main()` (after
/// `SharedPreferences.getInstance()`) and in tests with an in-memory instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override sharedPreferencesProvider in main()'),
);

/// User-chosen inference location. Persisted across launches.
enum ModelMode { auto, offline, online }

/// The resolved backend after applying device capability to a [ModelMode].
enum Backend { offline, online }

/// Resolves the concrete backend. `auto` picks offline when the device can run
/// the on-device model, otherwise online.
Backend resolveBackend(ModelMode mode, DeviceCapability cap) {
  switch (mode) {
    case ModelMode.offline:
      return Backend.offline;
    case ModelMode.online:
      return Backend.online;
    case ModelMode.auto:
      return cap.canRunOffline ? Backend.offline : Backend.online;
  }
}

const _kModelModeKey = 'model_mode';

class ModelModeNotifier extends Notifier<ModelMode> {
  @override
  ModelMode build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_kModelModeKey);
    return ModelMode.values.where((m) => m.name == raw).firstOrNull ??
        ModelMode.auto;
  }

  void set(ModelMode mode) {
    ref.read(sharedPreferencesProvider).setString(_kModelModeKey, mode.name);
    state = mode;
  }
}

final modelModeProvider =
    NotifierProvider<ModelModeNotifier, ModelMode>(ModelModeNotifier.new);

/// The concrete backend after applying device capability to the chosen mode.
/// Read this (not [resolveBackend] directly) so consumers depend on one
/// provider and tests can override it without wiring SharedPreferences.
final resolvedBackendProvider = Provider<Backend>(
  (ref) => resolveBackend(
    ref.watch(modelModeProvider),
    ref.watch(deviceCapabilityProvider),
  ),
);
