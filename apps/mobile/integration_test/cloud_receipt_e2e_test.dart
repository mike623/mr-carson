// CLOUD-path e2e: force Online mode, upload a receipt, run the REAL cloud OCR
// (CloudOcrEngine → local Cloudflare Worker proxy → OpenRouter → Gemma), confirm
// the expense, verify it lands in the Ledger. No on-device model needed.
//
// Prereqs:
//   - The proxy is running and reachable at OCR_PROXY_URL (default
//     http://localhost:8787). On the iOS simulator, localhost reaches the host,
//     so `wrangler dev` on your Mac works as-is.
//   - The proxy has a valid OPENROUTER_API_KEY (.dev.vars).
//
// Run (no screenshots):
//   flutter test integration_test/cloud_receipt_e2e_test.dart -d <sim-id>
// Run (with screenshots → build/e2e_screenshots/):
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/cloud_receipt_e2e_test.dart -d <sim-id> --profile
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mr_carson/ai/device_capability.dart';
import 'package:mr_carson/ai/model_mode.dart';
import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/features/shell/shell_view_model.dart';
import 'package:mr_carson/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Online: receipt → cloud OCR → confirm → ledger',
      timeout: const Timeout(Duration(minutes: 5)), (tester) async {
    // Force Online: persist model_mode=online AND report the device as unable to
    // run offline, so resolveBackend → online regardless.
    SharedPreferences.setMockInitialValues({'model_mode': 'online'});
    final prefs = await SharedPreferences.getInstance();

    // Bundle the test receipt to a real path for the picker seam.
    final bytes = await rootBundle.load('assets/test/receipt.png');
    final tmp = File('${Directory.systemTemp.path}/cloud_e2e_receipt.png')
      ..writeAsBytesSync(bytes.buffer.asUint8List());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceCapabilityProvider.overrideWith(
            (ref) => const DeviceCapability(
                canRunOffline: false, reason: 'simulator'),
          ),
          imagePickerFnProvider.overrideWithValue((_) async => XFile(tmp.path)),
        ],
        child: const MrCarsonApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    // Onboarding → shell.
    await tester.tap(find.text('Begin'));
    await tester.pump(const Duration(seconds: 1));

    final container =
        ProviderScope.containerOf(tester.element(find.byType(MrCarsonApp)));
    // Sanity: Online resolves, so capture is unlocked without an on-device model.
    expect(container.read(modelModeProvider), ModelMode.online);
    await _shot(binding, '01-home-online');

    // Open add sheet → Upload from library → fires the cloud pipeline.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Upload from library'), findsOneWidget,
        reason: 'Upload should be unlocked in Online mode (no on-device model).');
    await tester.tap(find.text('Upload from library'));
    await tester.pump(const Duration(seconds: 1));
    await _shot(binding, '02-processing');

    // Wait for the real cloud OCR to finish: the ready pending card shows "Review".
    final processed = await _pumpUntil(
      tester,
      () => find.text('Review').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 120),
    );
    expect(processed, isTrue,
        reason: 'Receipt never reached awaiting-confirmation — cloud OCR failed.');
    await _shot(binding, '03-pending-ready');

    // Ground truth: assert on what the cloud model actually extracted (the
    // pending row's extractedJson), not on widget-finder timing. The fixture is
    // Blue Bottle Coffee, total 13.59.
    final rows =
        await container.read(pendingRepositoryProvider).watchActive().first;
    final json = rows
        .map((r) => r.extractedJson ?? '')
        .firstWhere((j) => j.isNotEmpty, orElse: () => '');
    debugPrint('E2E extractedJson: $json');
    expect(json.toLowerCase(), contains('blue bottle'),
        reason: 'Cloud OCR did not extract the merchant. Raw: $json');
    expect(json, contains('13.59'),
        reason: 'Cloud OCR did not extract the total. Raw: $json');

    // Review → confirm screen.
    await tester.tap(find.text('Review'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Save expense'), findsOneWidget);
    await _shot(binding, '04-confirm-extracted');

    // Save → back to ledger.
    await tester.tap(find.text('Save expense'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Review'), findsNothing);
    await _shot(binding, '05-ledger-final');
  });
}

/// takeScreenshot only works under `flutter drive`; guard it so the same test
/// also runs under plain `flutter test integration_test`.
Future<void> _shot(
    IntegrationTestWidgetsFlutterBinding binding, String name) async {
  try {
    await binding.takeScreenshot(name);
  } catch (_) {
    // No driver attached — skip.
  }
}

/// Pumps frames until [cond] is true or [timeout] elapses (pump, not
/// pumpAndSettle, so background work doesn't hang it).
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 60),
  Duration step = const Duration(milliseconds: 250),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (cond()) return true;
    await tester.pump(step);
  }
  return cond();
}
