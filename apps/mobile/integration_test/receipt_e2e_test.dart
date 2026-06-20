// On-device REAL-MODEL e2e: upload a receipt photo, run the actual Gemma
// OCR + extraction pipeline, confirm the expense, verify it lands in the Ledger.
//
// Assumes the Gemma model is ALREADY downloaded on the device (download it once
// via the app). The test loads it, then exercises the real pipeline — no mocks
// except the image picker (the native iOS picker can't be driven in-process, so
// `imagePickerFnProvider` is overridden to return a bundled receipt asset).
//
// Run with screenshots:
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/receipt_e2e_test.dart \
//     -d <device-id> --profile
// Screenshots land in build/e2e_screenshots/.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mr_carson/main.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/features/model/model_lifecycle_view_model.dart';
import 'package:mr_carson/features/shell/shell_view_model.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('receipt photo → real OCR → confirm → ledger', timeout:
      const Timeout(Duration(minutes: 40)), (tester) async {
    // flutter_gemma 0.16.x needs a one-time initialize() — main() does it, but
    // this test pumps the app directly and bypasses main()'s bootstrap.
    await FlutterGemma.initialize();

    // --- seed the bundled receipt to a real file path for the picker seam ---
    final bytes = await rootBundle.load('assets/test/receipt.png');
    final tmp = File('${Directory.systemTemp.path}/e2e_receipt.png')
      ..writeAsBytesSync(bytes.buffer.asUint8List());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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

    // --- get the model ready: load if already installed, else download first ---
    // integration_test runs real async on-device, so we can await the real
    // plugin futures directly. downloadModel() is GBs over the network.
    final gemma = container.read(gemmaServiceProvider);
    container.read(modelLifecycleProvider); // keep the lifecycle listener alive
    try {
      await gemma.loadModel();
    } catch (_) {
      // No active model installed yet → download (real, ~2.4 GiB), then load.
      var last = -10;
      await for (final pct in gemma.downloadModel()) {
        if (pct >= last + 10) {
          last = pct;
          debugPrint('E2E model download: $pct%');
        }
      }
      await gemma.loadModel();
    }
    // Let the lifecycle listener propagate ready → isReady so the add-sheet
    // exposes the receipt options.
    await _pumpUntil(
      tester,
      () => container.read(modelLifecycleProvider).isReady,
      timeout: const Duration(seconds: 30),
    );
    expect(gemma.state, GemmaState.ready,
        reason: 'Gemma model not ready — lastError=${gemma.lastError}');
    await binding.takeScreenshot('01-home-model-ready');

    // --- open add sheet → upload from library (fires real pipeline) ---
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Upload from library'));
    await tester.pump(const Duration(seconds: 1));
    await binding.takeScreenshot('02-processing');

    // --- wait for real OCR/extraction: the ready pending card shows "Review" ---
    final processed = await _pumpUntil(
      tester,
      () => find.text('Review').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 300),
    );
    expect(processed, isTrue,
        reason: 'Receipt never reached awaiting-confirmation — OCR/extract failed.');
    await binding.takeScreenshot('03-pending-ready');

    // --- review → confirm screen ---
    await tester.tap(find.text('Review'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Save expense'), findsOneWidget);
    await binding.takeScreenshot('04-confirm-extracted');

    // --- save → back to ledger with the new expense ---
    await tester.tap(find.text('Save expense'));
    await tester.pump(const Duration(seconds: 3));

    // Pending card consumed; we're back on the ledger.
    expect(find.text('Review'), findsNothing);
    await binding.takeScreenshot('05-ledger-final');
  });
}

/// Pumps frames until [cond] is true or [timeout] elapses. Uses pump (not
/// pumpAndSettle) so perpetual animations / background work don't hang it.
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
