import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/carson_monogram.dart';
import 'package:mr_carson/ui/core/widgets/error_retry_state.dart';

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
          error: s.error,
          onTogglePause: vm.togglePause,
          onRetry: vm.retry,
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
    required this.error,
    required this.onTogglePause,
    required this.onRetry,
    required this.onEnter,
  });

  final double pct;
  final bool done;
  final bool paused;
  final String? error;
  final VoidCallback onTogglePause;
  final VoidCallback onRetry;
  final VoidCallback onEnter;

  /// Real on-device model size (gemma-4-e2b.litertlm, 2.41 GiB on R2 —
  /// see apps/mobile/scripts/setup-r2.sh and kModelHostedOnR2).
  static const double _totalMb = 2467.0;

  // [pct] is the REAL download percentage from GemmaService's progress stream,
  // so the byte count below tracks the actual download. flutter_gemma's stream
  // is percent-only (no byte/speed signal), so speed + ETA remain estimates.
  static _DownloadStats _stats(double pct) {
    final mb = (pct / 100 * _totalMb).clamp(0, _totalMb);
    final speed = 45 + 75 * (0.5 + 0.5 * math.sin(pct * 0.25)); // estimated MB/s
    final remaining = pct >= 100 ? 0.0 : ((_totalMb - mb) / speed); // seconds
    return _DownloadStats(
      mb: mb.toStringAsFixed(0),
      speed: speed.toStringAsFixed(1),
      eta: _fmtEta(remaining),
    );
  }

  static String _fmtEta(double secs) {
    if (secs <= 0) return '0s';
    if (secs < 60) return '${secs.round()}s';
    final m = (secs / 60).floor();
    final s = (secs % 60).round();
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    // Honest error arm — the real download or model load failed. Reuse the
    // shared §6 ErrorRetryState; its Retry button restarts the real download.
    if (error != null) {
      return ErrorRetryState(
        title: 'A hiccup, sir.',
        message: error!,
        onRetry: onRetry,
        retryLabel: 'Try again',
      );
    }

    final stats = _stats(pct);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Progress ring
        _ProgressRing(pct: pct, done: done),
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
        if (!done) _StatsCard(stats: stats),
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

/// Animated 172×172 progress ring with percent or checkmark in the center.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.pct, required this.done});
  final double pct;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final intPct = pct.toInt();
    return SizedBox(
      width: 172,
      height: 172,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(172, 172),
            painter: _RingPainter(progress: pct / 100),
          ),
          if (!done) ...[
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$intPct',
                  style: MrCarsonType.display(
                    size: 50,
                    weight: FontWeight.w600,
                  ),
                ),
                Text(
                  'per cent',
                  style: MrCarsonType.ui(
                    size: 12.5,
                    color: MrCarsonColors.ink3,
                  ),
                ),
              ],
            ),
          ] else ...[
            CustomPaint(
              size: const Size(40, 40),
              painter: _BigCheckPainter(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Paints the two-layer progress ring (track + arc).
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress});
  final double progress; // 0–1

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 6) / 2;
    const stroke = 6.0;

    // Track
    final trackPaint = Paint()
      ..color = MrCarsonColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc
    if (progress > 0) {
      final arcPaint = Paint()
        ..color = MrCarsonColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2; // top
      final sweepAngle = 2 * math.pi * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// Paints a large accent checkmark for the "done" state.
class _BigCheckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MrCarsonColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.15, size.height * 0.52)
      ..lineTo(size.width * 0.40, size.height * 0.76)
      ..lineTo(size.width * 0.85, size.height * 0.28);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BigCheckPainter old) => false;
}

/// Download stats card.
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});
  final _DownloadStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: MrCarsonColors.surface,
            border: Border.all(color: MrCarsonColors.line, width: 1),
            borderRadius: BorderRadius.circular(MrCarsonRadii.tile),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${stats.mb} of 2,467 MB',
                    style: MrCarsonType.ui(size: 14),
                  ),
                  Text(
                    '${stats.speed} MB/s',
                    style: MrCarsonType.ui(size: 14),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${stats.eta} remaining',
                    style: MrCarsonType.ui(
                      size: 13,
                      color: MrCarsonColors.ink3,
                    ),
                  ),
                  Text(
                    'One-time only',
                    style: MrCarsonType.ui(
                      size: 13,
                      color: MrCarsonColors.ink3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _WarnDot(),
            const SizedBox(width: 8),
            Text(
              'Best done on Wi-Fi, sir.',
              style: MrCarsonType.ui(size: 12.5, color: MrCarsonColors.ink3),
            ),
          ],
        ),
      ],
    );
  }
}

/// 5px warn-colored dot.
class _WarnDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: MrCarsonColors.warn,
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

// ── Simple data holder ────────────────────────────────────────────────────────

class _DownloadStats {
  const _DownloadStats({
    required this.mb,
    required this.speed,
    required this.eta,
  });
  final String mb;
  final String speed;
  final String eta;
}
