import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/features/model/model_lifecycle_view_model.dart';
import 'package:mr_carson/features/model/model_management_screen.dart';
import 'package:mr_carson/theme/app_theme.dart';

/// A [ModelLifecycleViewModel] stand-in that returns a seeded state with no
/// service wiring (no network / no GemmaService needed in tests).
class _FakeModelVm extends ModelLifecycleViewModel {
  _FakeModelVm(this._seed);
  final ModelLifecycleState _seed;

  @override
  ModelLifecycleState build() {
    ref.onDispose(() {});
    return _seed;
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget buildSubject(ModelLifecycleState model) {
    return ProviderScope(
      overrides: [
        modelLifecycleProvider.overrideWith(() => _FakeModelVm(model)),
      ],
      child: MaterialApp(
        theme: buildMrCarsonTheme(),
        home: const ModelManagementScreen(),
      ),
    );
  }

  testWidgets('absent state shows "Download now" and the Gemma chip',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildSubject(const ModelLifecycleState(phase: GemmaState.notDownloaded)),
    );
    await tester.pump();

    expect(find.text('The model'), findsOneWidget);
    expect(find.text('Download now'), findsOneWidget);
    expect(find.text('Gemma · on-device'), findsOneWidget);
    expect(find.text('~2.4 GB'), findsOneWidget);
    // No remove control in the absent state.
    expect(find.text('Remove download'), findsNothing);
  });

  testWidgets('ready state shows "Remove download" and opens the confirm dialog',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildSubject(const ModelLifecycleState(phase: GemmaState.ready)),
    );
    await tester.pump();

    expect(find.text('Remove download'), findsOneWidget);
    expect(find.text('Download now'), findsNothing);

    await tester.tap(find.text('Remove download'));
    await tester.pumpAndSettle();

    // Remove-confirm dialog.
    expect(find.text('Send me ashore, sir?'), findsOneWidget);
    expect(find.text('Remove · free 2.4 GB'), findsOneWidget);
    expect(find.text('Keep him aboard'), findsOneWidget);
  });
}
