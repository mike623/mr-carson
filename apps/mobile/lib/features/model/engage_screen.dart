import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mr_carson/theme/app_theme.dart';

import '../shell/shell_view_model.dart';
import 'model_lifecycle_view_model.dart';
import 'model_progress.dart';

/// Full-screen model-setup invitation ("Engage Mr. Carson").
///
/// Shown when a surface needs the model present (via
/// [ShellViewModel.requireModel]). Three states, driven by
/// [ModelLifecycleState]:
///   • CTA — model absent (or error, shown as a retryable CTA)
///   • Progress — model downloading
///   • Ready — model loaded
///
/// The shell hides the bottom nav while this screen is up. Dismiss / Enter
/// returns to the Ask screen.
class EngageScreen extends ConsumerWidget {
  const EngageScreen({super.key});

  static const _defaultReason =
      "A moment, sir — I'll fetch my mind so I may answer you.";

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(modelLifecycleProvider);
    final modelVm = ref.read(modelLifecycleProvider.notifier);
    final shellVm = ref.read(shellViewModelProvider.notifier);
    final reason = ref.watch(
      shellViewModelProvider.select((s) => s.engageReason),
    );

    void dismiss() => shellVm.go(ShellScreen.ask);

    final Widget content;
    if (model.isDownloading) {
      content = _ProgressBody(
        pct: model.downloadPct,
        paused: model.paused,
        onTogglePause: modelVm.togglePause,
        onDismiss: dismiss,
      );
    } else if (model.isReady) {
      content = _ReadyBody(onEnter: dismiss);
    } else {
      // Absent or error — both shown as a CTA (error retries via engage()).
      content = _CtaBody(
        reason: reason.isEmpty ? _defaultReason : reason,
        onEngage: modelVm.engage,
        onDismiss: dismiss,
      );
    }

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Column(
        children: [
          // Top-left × dismiss.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _IconSquareButton(
                onTap: dismiss,
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: MrCarsonColors.ink2,
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(30, 6, 30, 38),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - 200,
                ),
                child: content,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CTA state (absent / error)
// ═══════════════════════════════════════════════════════════════════════════

class _CtaBody extends StatelessWidget {
  const _CtaBody({
    required this.reason,
    required this.onEngage,
    required this.onDismiss,
  });

  final String reason;
  final VoidCallback onEngage;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 12),
        // Brass seal "C" — 118px, accent border, accentSoft halo.
        const _EngageSeal(),
        const SizedBox(height: 30),
        Text(
          'Shall I prepare myself, sir?',
          style: MrCarsonType.display(
            size: 33,
            weight: FontWeight.w600,
            height: 1.08,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 312),
          child: Text(
            'A one-time download brings his mind aboard, so he may read your '
            'receipts and answer your questions — entirely on this device.',
            style: MrCarsonType.ui(
              size: 15,
              color: MrCarsonColors.ink2,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 22),
        // Reason card — contextual italic line.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: Container(
            decoration: BoxDecoration(
              color: MrCarsonColors.surface,
              border: Border.all(color: MrCarsonColors.line, width: 1),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: MrCarsonColors.accent,
                    boxShadow: [
                      BoxShadow(
                        color: MrCarsonColors.accentSoft,
                        blurRadius: 8,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    reason,
                    style: MrCarsonType.display(
                      size: 15,
                      italic: true,
                      weight: FontWeight.w500,
                      color: MrCarsonColors.ink2,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Meta row.
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MetaItem(
              color: MrCarsonColors.grocery,
              label: '2.4 GB · one-time',
            ),
            SizedBox(width: 22),
            _MetaItem(
              color: MrCarsonColors.transport,
              label: 'Stays on device',
            ),
          ],
        ),
        const SizedBox(height: 32),
        _PrimaryButton(label: 'Engage Mr. Carson', onTap: onEngage),
        const SizedBox(height: 8),
        _TextButton(label: 'Not just now', onTap: onDismiss),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Progress state
// ═══════════════════════════════════════════════════════════════════════════

class _ProgressBody extends StatelessWidget {
  const _ProgressBody({
    required this.pct,
    required this.paused,
    required this.onTogglePause,
    required this.onDismiss,
  });

  final double pct;
  final bool paused;
  final VoidCallback onTogglePause;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final stats = modelDownloadStats(pct);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 12),
        ModelProgressRing(pct: pct, size: 172),
        const SizedBox(height: 30),
        Text(
          'A moment while I prepare.',
          style: MrCarsonType.display(
            size: 33,
            weight: FontWeight.w600,
            height: 1.08,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 312),
          child: Text(
            'Downloading once, so I may work without the cloud.',
            style: MrCarsonType.ui(
              size: 15,
              color: MrCarsonColors.ink2,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: ModelStatsCard(stats: stats),
        ),
        const SizedBox(height: 13),
        const ModelWifiHint(),
        const SizedBox(height: 32),
        _OutlineButton(
          label: paused ? 'Resume' : 'Pause',
          onTap: onTogglePause,
        ),
        const SizedBox(height: 8),
        _TextButton(label: 'Continue in the background', onTap: onDismiss),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Ready state
// ═══════════════════════════════════════════════════════════════════════════

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({required this.onEnter});

  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 12),
        const ModelProgressRing(pct: 100, done: true, size: 172, checkSize: 50),
        const SizedBox(height: 30),
        Text(
          'At your post.',
          style: MrCarsonType.display(
            size: 33,
            weight: FontWeight.w600,
            height: 1.08,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 312),
          child: Text(
            'Everything is ready, sir.',
            style: MrCarsonType.ui(
              size: 15,
              color: MrCarsonColors.ink2,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 32),
        _PrimaryButton(label: 'Enter', onTap: onEnter),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Small pieces
// ═══════════════════════════════════════════════════════════════════════════

/// Brass seal "C" — 118px circle, 1.5px accent border, accentSoft halo.
class _EngageSeal extends StatelessWidget {
  const _EngageSeal();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      height: 118,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        border: Border.fromBorderSide(
          BorderSide(color: MrCarsonColors.accent, width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: MrCarsonColors.accentSoft,
            blurRadius: 0,
            spreadRadius: 8,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'C',
          style: MrCarsonType.display(
            size: 66,
            weight: FontWeight.w600,
            color: MrCarsonColors.accent,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: MrCarsonType.ui(size: 12.5, color: MrCarsonColors.ink3),
        ),
      ],
    );
  }
}

/// 40×40 square icon button with a 1px line border.
class _IconSquareButton extends StatelessWidget {
  const _IconSquareButton({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: MrCarsonColors.surface,
          border: Border.all(color: MrCarsonColors.line, width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// Full-width solid accent primary button.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

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
            style: MrCarsonType.ui(
              size: 16,
              weight: FontWeight.w600,
              color: MrCarsonColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width text-only (ghost) button.
class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Text(
            label,
            style: MrCarsonType.ui(
              size: 15.5,
              weight: FontWeight.w600,
              color: MrCarsonColors.ink2,
            ),
          ),
        ),
      ),
    );
  }
}
