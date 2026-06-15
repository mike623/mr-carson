import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mr_carson/features/model/model_progress.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/carson_monogram.dart';

import 'onboarding_view_model.dart';

/// Three-step onboarding flow for Mr. Carson.
///
/// Steps:
///   0 — Welcome (monogram, tagline, body copy, primary CTA)
///   1 — Privacy / permission assurances + camera-permission card
///   2 — Model-download progress ring → Enter
///
/// A dumb view: all download/step logic lives in [OnboardingViewModel]. The
/// only state held here is the UI-specific step-transition animation.
///
/// [onEnter] is called when the user taps "Enter" on the final step.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.onEnter});

  final VoidCallback onEnter;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  // ── Step transition animation (UI-specific — stays in the View) ─────────────
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _replayTransition() {
    _fadeCtrl
      ..reset()
      ..forward();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final vm = ref.read(onboardingViewModelProvider.notifier);
    final s = ref.watch(onboardingViewModelProvider);

    // Replay the fade/slide whenever the step changes.
    ref.listen<int>(
      onboardingViewModelProvider.select((v) => v.step),
      (_, __) => _replayTransition(),
    );

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 96, 30, 40),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: _buildStep(s, vm),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(OnboardingState s, OnboardingViewModel vm) {
    switch (s.step) {
      case 0:
        return _StepWelcome(onNext: vm.begin);
      case 1:
        return _StepPrivacy(onNext: vm.allowAndStartDownload);
      case 2:
        return _StepDownload(
          pct: s.downloadPct,
          done: s.done,
          paused: s.paused,
          onTogglePause: vm.togglePause,
          onEnter: widget.onEnter,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Step 0 — Welcome
// ═══════════════════════════════════════════════════════════════════════════════

class _StepWelcome extends StatefulWidget {
  const _StepWelcome({required this.onNext});
  final VoidCallback onNext;

  @override
  State<_StepWelcome> createState() => _StepWelcomeState();
}

class _StepWelcomeState extends State<_StepWelcome> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Monogram
        const CarsonMonogram(size: 78, glow: true, surfaceFill: true),
        const SizedBox(height: 26),
        // Title
        Text(
          'Mr. Carson',
          style: MrCarsonType.display(
            size: 52,
            weight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        // Tagline
        Text(
          'At your service.',
          style: MrCarsonType.display(
            size: 23,
            italic: true,
            color: MrCarsonColors.accent,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        // Body copy
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              'A discreet valet for your expenses. Snap a receipt; I shall read it, '
              'file it, and answer any question you might have — quietly, and entirely '
              'on your own device.',
              style: MrCarsonType.ui(
                size: 16,
                color: MrCarsonColors.ink2,
                height: 1.62,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 20),
        // "Nothing leaves your phone" row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _AccentDot(size: 7, glowSize: 3),
            const SizedBox(width: 10),
            Text(
              'Nothing ever leaves your phone.',
              style: MrCarsonType.ui(
                size: 13.5,
                color: MrCarsonColors.ink3,
              ),
            ),
          ],
        ),
        const Spacer(),
        // Primary button
        GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onNext();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.985 : 1.0,
            duration: const Duration(milliseconds: 80),
            child: const _PrimaryButton(
              label: 'Begin',
              onTap: null, // handled by GestureDetector above
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Step 1 — Privacy
// ═══════════════════════════════════════════════════════════════════════════════

class _StepPrivacy extends StatelessWidget {
  const _StepPrivacy({required this.onNext});
  final VoidCallback onNext;

  static const _assurances = [
    'Every receipt is read on this device.',
    'No account, no cloud, no sign-in.',
    'Your figures are yours alone.',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Heading
        Text(
          'On your phone.\nOnly.',
          style: MrCarsonType.display(
            size: 38,
            weight: FontWeight.w600,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'A word on discretion, sir, before we begin.',
          style: MrCarsonType.ui(
            size: 15.5,
            color: MrCarsonColors.ink2,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 30),
        // Assurance list
        ...List.generate(_assurances.length, (i) {
          final isLast = i == _assurances.length - 1;
          return Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: isLast
                    ? BorderSide.none
                    : const BorderSide(color: MrCarsonColors.line, width: 1),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 17),
            child: Row(
              children: [
                _CheckCircle(),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _assurances[i],
                    style: MrCarsonType.ui(size: 15.5),
                  ),
                ),
              ],
            ),
          );
        }),
        const Spacer(),
        // Camera permission card
        _CameraCard(),
        const SizedBox(height: 14),
        // Primary button
        _PrimaryButton(label: 'Allow & continue', onTap: onNext),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Step 2 — Download
// ═══════════════════════════════════════════════════════════════════════════════

class _StepDownload extends StatelessWidget {
  const _StepDownload({
    required this.pct,
    required this.done,
    required this.paused,
    required this.onTogglePause,
    required this.onEnter,
  });

  final double pct;
  final bool done;
  final bool paused;
  final VoidCallback onTogglePause;
  final VoidCallback onEnter;

  /// Real on-device model size (gemma-3n-E2B-it-int4.litertlm, 3655827456 B).
  static const double _totalMb = 3487.0;

  @override
  Widget build(BuildContext context) {
    // [pct] is the REAL download percentage from GemmaService's progress stream,
    // so the byte count tracks the actual download. The stream is percent-only
    // (no byte/speed signal), so speed + ETA remain estimates.
    final stats = modelDownloadStats(pct, totalMb: _totalMb);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Progress ring
        ModelProgressRing(pct: pct, done: done),
        const SizedBox(height: 30),
        // Title
        Text(
          done ? 'At your service, sir.' : 'Bringing Mr. Carson aboard',
          style: MrCarsonType.display(size: 30, weight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 7),
        // Subtitle
        Text(
          done
              ? 'Everything is ready.'
              : 'Downloading once, so I may work without the cloud.',
          style: MrCarsonType.ui(
            size: 14.5,
            color: MrCarsonColors.ink2,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        // Stats card (hidden when done)
        if (!done)
          ModelStatsCard(
            stats: stats,
            showWifiHint: true,
            totalMbLabel: '3,487 MB',
          ),
        const Spacer(),
        // Bottom button
        if (!done)
          _OutlineButton(
            label: paused ? 'Resume' : 'Pause',
            onTap: onTogglePause,
          )
        else
          _PrimaryButton(label: 'Enter', onTap: onEnter),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Small reusable pieces
// ═══════════════════════════════════════════════════════════════════════════════

/// Small accent dot with optional glow ring.
class _AccentDot extends StatelessWidget {
  const _AccentDot({required this.size, required this.glowSize});
  final double size;
  final double glowSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: MrCarsonColors.accent,
        boxShadow: [
          BoxShadow(
            color: MrCarsonColors.accentSoft,
            blurRadius: glowSize * 2,
            spreadRadius: glowSize,
          ),
        ],
      ),
    );
  }
}

/// 22px circle with 1.5px accent border and a checkmark inside.
class _CheckCircle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: MrCarsonColors.accent, width: 1.5),
        color: Colors.transparent,
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.check, size: 11, color: MrCarsonColors.accent),
    );
  }
}

/// Camera permission info card.
class _CameraCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        border: Border.all(color: MrCarsonColors.line, width: 1),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          // Camera icon square
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: MrCarsonColors.accentSoft,
              borderRadius: BorderRadius.circular(MrCarsonRadii.control),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.photo_camera_outlined,
              color: MrCarsonColors.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Camera access',
                  style: MrCarsonType.ui(size: 15.5, weight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  'To read receipts — on device.',
                  style: MrCarsonType.ui(
                    size: 13,
                    color: MrCarsonColors.ink3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width solid accent primary button.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: MrCarsonColors.accent,
            borderRadius: BorderRadius.circular(MrCarsonRadii.tile),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: MrCarsonType.ui(
              size: 17,
              weight: FontWeight.w600,
              color: MrCarsonColors.accentInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width outline button (transparent bg, 1px line border).
class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: MrCarsonColors.line, width: 1),
            borderRadius: BorderRadius.circular(MrCarsonRadii.tile),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: MrCarsonType.ui(size: 16, color: MrCarsonColors.ink),
          ),
        ),
      ),
    );
  }
}
