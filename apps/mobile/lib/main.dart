import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/app_shell.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The on-device model is loaded lazily by [GemmaService] (lib/ai/gemma_service.dart),
  // driven from the onboarding download flow. flutter_gemma ^0.9.0 self-registers
  // its plugin, so there is no eager init to do here.
  runApp(const ProviderScope(child: MrCarsonApp()));
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
