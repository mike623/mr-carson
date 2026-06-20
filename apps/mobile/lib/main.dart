import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/device_capability.dart';
import 'ai/model_mode.dart';
import 'core/error_reporter.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/app_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // flutter_gemma 0.16.x requires an explicit one-time initialize() before any
  // plugin use (model install, createModel, etc.); omitting it throws StateError
  // at runtime. The on-device model itself is loaded lazily by [GemmaService]
  // (lib/ai/gemma_service.dart) via the in-app model lifecycle (Ask locked-state
  // CTA / Model Management screen) — not during onboarding.
  await FlutterGemma.initialize();

  final prefs = await SharedPreferences.getInstance();
  final capability = await detectCapability();

  // SentryFlutter.init's appRunner installs the zone + Flutter error handlers
  // that capture uncaught errors. With no DSN it's a no-op shell, so dev/local
  // builds run unchanged; pass --dart-define=SENTRY_DSN=... to enable.
  await SentryFlutter.init(
    (options) {
      options.dsn = kSentryDsn;
      options.tracesSampleRate = 0.2;
      // Privacy: receipts are personal. Don't ship request bodies / PII.
      options.sendDefaultPii = false;
    },
    appRunner: () => runApp(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceCapabilityProvider.overrideWith((ref) => capability),
        ],
        child: const MrCarsonApp(),
      ),
    ),
  );
}

/// Root of the Mr. Carson app. Brass & Ink, dark-first.
class MrCarsonApp extends StatelessWidget {
  const MrCarsonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mr. Carson',
      debugShowCheckedModeBanner: false,
      theme: buildMrCarsonTheme(),
      home: const _Root(),
    );
  }
}

/// Gates onboarding → in-app shell.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _onboarded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: _onboarded
          ? const AppShell()
          : OnboardingScreen(onEnter: () => setState(() => _onboarded = true)),
    );
  }
}
