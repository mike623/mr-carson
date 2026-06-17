import 'package:flutter/material.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/carson_monogram.dart';

/// Single-screen onboarding for Mr. Carson.
///
/// Welcome only: monogram, tagline, body copy, "Nothing leaves your phone"
/// assurance, and a primary "Begin" CTA. Tapping Begin enters the app directly.
///
/// The old privacy/permission and model-download steps were removed — model
/// setup is now lazy, owned by the `model/` feature (the Ask locked-state CTA
/// and the Model Management screen download on demand), so onboarding no longer
/// blocks the user behind a 2.4 GB download before they can look around.
///
/// [onEnter] is called when the user taps "Begin".
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onEnter});

  final VoidCallback onEnter;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  // One-time entrance fade/slide (mirrors the prototype's `mcUp .5s`).
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 96, 30, 40),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: _StepWelcome(onNext: widget.onEnter),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Welcome
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
