import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/device_capability.dart';

void main() {
  test('simulator/emulator cannot run offline', () {
    final cap = capabilityFrom(
      isPhysicalDevice: false, isIOS: true, iosMajorVersion: 18);
    expect(cap.canRunOffline, isFalse);
    expect(cap.reason, contains('imulator'));
  });

  test('modern physical iPhone can run offline', () {
    final cap = capabilityFrom(
      isPhysicalDevice: true, isIOS: true, iosMajorVersion: 17);
    expect(cap.canRunOffline, isTrue);
  });

  test('old iOS cannot run offline', () {
    final cap = capabilityFrom(
      isPhysicalDevice: true, isIOS: true, iosMajorVersion: 14);
    expect(cap.canRunOffline, isFalse);
  });

  test('modern physical Android can run offline', () {
    final cap = capabilityFrom(
      isPhysicalDevice: true, isIOS: false, androidSdk: 30);
    expect(cap.canRunOffline, isTrue);
  });

  test('old Android cannot run offline', () {
    final cap = capabilityFrom(
      isPhysicalDevice: true, isIOS: false, androidSdk: 24);
    expect(cap.canRunOffline, isFalse);
  });

  test('unknown version is conservatively incapable', () {
    final cap = capabilityFrom(
      isPhysicalDevice: true, isIOS: true, iosMajorVersion: null);
    expect(cap.canRunOffline, isFalse);
  });
}
