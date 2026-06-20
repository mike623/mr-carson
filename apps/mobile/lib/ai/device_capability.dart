import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether this device can realistically run the on-device Gemma model.
class DeviceCapability {
  const DeviceCapability({required this.canRunOffline, required this.reason});

  final bool canRunOffline;

  /// Human-readable explanation, shown as a Settings hint when false.
  final String reason;
}

// Floors below which the on-device model is unreliable / unsupported.
const _kIosMinMajor = 16;
const _kAndroidMinSdk = 26; // Android 8.0

/// Pure capability rule — unit-testable without platform channels.
///
/// Note: this is a coarse gate (simulator + OS floor). Exact RAM/storage isn't
/// available cross-platform via device_info_plus; the real failure signal is a
/// runtime load failure, handled separately by recording it and switching the
/// effective mode. // ponytail: OS-floor heuristic; add RAM probe if false
/// negatives show up.
DeviceCapability capabilityFrom({
  required bool isPhysicalDevice,
  required bool isIOS,
  int? iosMajorVersion,
  int? androidSdk,
}) {
  if (!isPhysicalDevice) {
    return const DeviceCapability(
      canRunOffline: false,
      reason: 'The simulator can\'t run the on-device model — use Online here.',
    );
  }
  if (isIOS) {
    if (iosMajorVersion == null) {
      return const DeviceCapability(
          canRunOffline: false, reason: 'Unknown iOS version.');
    }
    return iosMajorVersion >= _kIosMinMajor
        ? const DeviceCapability(canRunOffline: true, reason: '')
        : const DeviceCapability(
            canRunOffline: false, reason: 'iOS $_kIosMinMajor or newer needed.');
  }
  if (androidSdk == null) {
    return const DeviceCapability(
        canRunOffline: false, reason: 'Unknown Android version.');
  }
  return androidSdk >= _kAndroidMinSdk
      ? const DeviceCapability(canRunOffline: true, reason: '')
      : const DeviceCapability(
          canRunOffline: false, reason: 'Android 8 or newer needed.');
}

/// Gathers platform facts and applies [capabilityFrom].
Future<DeviceCapability> detectCapability({DeviceInfoPlugin? deviceInfo}) async {
  final info = deviceInfo ?? DeviceInfoPlugin();
  if (Platform.isIOS) {
    final ios = await info.iosInfo;
    final major = int.tryParse(ios.systemVersion.split('.').first);
    return capabilityFrom(
      isPhysicalDevice: ios.isPhysicalDevice,
      isIOS: true,
      iosMajorVersion: major,
    );
  }
  if (Platform.isAndroid) {
    final android = await info.androidInfo;
    return capabilityFrom(
      isPhysicalDevice: android.isPhysicalDevice,
      isIOS: false,
      androidSdk: android.version.sdkInt,
    );
  }
  // Desktop/web (e.g. running tests on host): treat as incapable → online.
  return const DeviceCapability(
      canRunOffline: false, reason: 'On-device model not supported here.');
}

/// Current capability. Seeded conservatively; `main()` refines it after
/// [detectCapability]. Recorded runtime load failures can also flip it false.
final deviceCapabilityProvider = StateProvider<DeviceCapability>(
  (ref) => const DeviceCapability(canRunOffline: true, reason: ''),
);
