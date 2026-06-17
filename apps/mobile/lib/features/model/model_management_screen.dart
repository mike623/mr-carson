import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mr_carson/theme/app_theme.dart';

import '../shell/shell_view_model.dart';
import 'model_lifecycle_view_model.dart';
import 'model_progress.dart';

/// Model Management screen — state-driven download control plus a
/// remove-confirm dialog. Reached from Settings ("The model" row).
///
/// States, driven by [ModelLifecycleState]:
///   • absent — "Download now" → engage()
///   • downloading — pause/resume + Cancel (remove())
///   • ready — "Remove download" → confirm dialog → remove()
///   • error — "Try again" → retry()
class ModelManagementScreen extends ConsumerWidget {
  const ModelManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(modelLifecycleProvider);
    final modelVm = ref.read(modelLifecycleProvider.notifier);
    final shellVm = ref.read(shellViewModelProvider.notifier);

    final copy = _copyFor(model);

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Column(
        children: [
          _BackHeader(
            title: 'The model',
            onBack: () => shellVm.go(ShellScreen.settings),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 26, 18, 40),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - 200,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Seal (absent/ready) or progress ring (downloading).
                    if (model.isDownloading)
                      ModelProgressRing(
                        pct: model.downloadPct,
                        size: 152,
                        pctFontSize: 44,
                      )
                    else
                      const _ModelSeal(),
                    const SizedBox(height: 22),
                    Text(
                      copy.title,
                      style: MrCarsonType.display(
                        size: 28,
                        weight: FontWeight.w600,
                        height: 1.12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 9),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(
                        copy.subtitle,
                        style: MrCarsonType.ui(
                          size: 14.5,
                          color: MrCarsonColors.ink2,
                          height: 1.55,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 18),
                    // FittedBox keeps the single-line chip from overflowing on
                    // narrow widths (the chip is intentionally min-width).
                    const FittedBox(fit: BoxFit.scaleDown, child: _GemmaChip()),

                    // Downloading stats.
                    if (model.isDownloading) ...[
                      const SizedBox(height: 18),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: ModelStatsCard(
                          stats: modelDownloadStats(model.downloadPct),
                        ),
                      ),
                    ],

                    // Error card.
                    if (model.isError) ...[
                      const SizedBox(height: 18),
                      _ErrorCard(message: model.error ?? 'Something went awry.'),
                    ],

                    const SizedBox(height: 28),
                    _actions(context, model, modelVm),

                    const SizedBox(height: 18),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(
                        'Hosted by us and fetched once — no account, no token, '
                        'nothing to sign into.',
                        style: MrCarsonType.ui(
                          size: 11.5,
                          color: MrCarsonColors.ink3,
                          height: 1.55,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── actions ──────────────────────────────────────────────────────────────

  Widget _actions(
    BuildContext context,
    ModelLifecycleState model,
    ModelLifecycleViewModel vm,
  ) {
    if (model.isDownloading) {
      return Row(
        children: [
          Expanded(
            child: _OutlineButton(
              label: model.paused ? 'Resume' : 'Pause',
              onTap: vm.togglePause,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: _OutlineButton(
              label: 'Cancel',
              color: MrCarsonColors.warn,
              onTap: vm.remove,
            ),
          ),
        ],
      );
    }
    if (model.isReady) {
      return Column(
        children: [
          _WarnFillButton(
            label: 'Remove download',
            onTap: () => _showRemoveDialog(context, vm),
          ),
        ],
      );
    }
    if (model.isError) {
      return _PrimaryButton(label: 'Try again', onTap: vm.retry);
    }
    // Absent.
    return Column(
      children: [
        _PrimaryButton(label: 'Download now', onTap: vm.engage),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: MrCarsonColors.warn,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'A one-time download. Best done on Wi-Fi, sir.',
                style: MrCarsonType.ui(size: 12.5, color: MrCarsonColors.ink3),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showRemoveDialog(
    BuildContext context,
    ModelLifecycleViewModel vm,
  ) async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (dialogContext) => _RemoveDialog(
        onRemove: () {
          Navigator.of(dialogContext).pop();
          vm.remove();
        },
        onKeep: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  // ── copy ───────────────────────────────────────────────────────────────

  static ({String title, String subtitle}) _copyFor(ModelLifecycleState s) {
    if (s.isDownloading) {
      return (
        title: 'Coming aboard…',
        subtitle: 'Downloading once, so I may work without the cloud.',
      );
    }
    if (s.isReady) {
      return (
        title: 'At your service',
        subtitle: 'My mind is aboard and ready, sir.',
      );
    }
    if (s.isError) {
      return (
        title: 'Something went amiss.',
        subtitle: 'The download did not complete. We may try once more.',
      );
    }
    return (
      title: "My mind isn't aboard yet.",
      subtitle:
          'A one-time download lets me read receipts and answer questions, '
          'entirely on this device.',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Header
// ═══════════════════════════════════════════════════════════════════════════

class _BackHeader extends StatelessWidget {
  const _BackHeader({required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 58, 16, 12),
      decoration: const BoxDecoration(
        color: MrCarsonColors.bg,
        border: Border(bottom: BorderSide(color: MrCarsonColors.line)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
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
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 15,
                color: MrCarsonColors.ink2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: MrCarsonType.ui(size: 16, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Pieces
// ═══════════════════════════════════════════════════════════════════════════

/// 96px rounded-square brass seal "C" with an accentSoft halo.
class _ModelSeal extends StatelessWidget {
  const _ModelSeal();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: MrCarsonColors.accentSoft,
        border: Border.all(color: MrCarsonColors.accent, width: 1.5),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: MrCarsonColors.accentSoft,
            blurRadius: 0,
            spreadRadius: 7,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          'C',
          style: MrCarsonType.display(
            size: 54,
            weight: FontWeight.w600,
            color: MrCarsonColors.accent,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// "Gemma · on-device · ~2.4 GB" chip.
class _GemmaChip extends StatelessWidget {
  const _GemmaChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        border: Border.all(color: MrCarsonColors.line, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: MrCarsonColors.accent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Gemma · on-device',
            style: MrCarsonType.ui(size: 13, weight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 13, color: MrCarsonColors.line),
          const SizedBox(width: 10),
          Text(
            '~2.4 GB',
            style: MrCarsonType.ui(size: 13, color: MrCarsonColors.ink3),
          ),
        ],
      ),
    );
  }
}

/// Mono error card (warn wash).
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: MrCarsonColors.warnSoft,
        border: Border.all(color: MrCarsonColors.warnSoft, width: 1),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        message,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: ['Menlo', 'Courier'],
          fontSize: 11.5,
          height: 1.55,
          color: MrCarsonColors.warn,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Remove dialog
// ═══════════════════════════════════════════════════════════════════════════

class _RemoveDialog extends StatelessWidget {
  const _RemoveDialog({required this.onRemove, required this.onKeep});
  final VoidCallback onRemove;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(30),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        decoration: BoxDecoration(
          color: MrCarsonColors.surface,
          border: Border.all(color: MrCarsonColors.line, width: 1),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: MrCarsonColors.warnSoft,
                borderRadius: BorderRadius.circular(15),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.delete_outline,
                size: 24,
                color: MrCarsonColors.warn,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Send me ashore, sir?',
              style: MrCarsonType.display(
                size: 26,
                weight: FontWeight.w600,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                style: MrCarsonType.ui(
                  size: 14.5,
                  color: MrCarsonColors.ink2,
                  height: 1.55,
                ),
                children: [
                  const TextSpan(text: 'Removing my mind frees '),
                  TextSpan(
                    text: '2.4 GB',
                    style: MrCarsonType.ui(
                      size: 14.5,
                      weight: FontWeight.w600,
                      height: 1.55,
                    ),
                  ),
                  const TextSpan(
                    text:
                        '. Your ledger remains untouched — but asking questions '
                        'and reading receipts will need a one-time re-download.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _WarnSolidButton(label: 'Remove · free 2.4 GB', onTap: onRemove),
            const SizedBox(height: 10),
            _TextButton(label: 'Keep him aboard', onTap: onKeep),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Buttons
// ═══════════════════════════════════════════════════════════════════════════

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

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.label,
    required this.onTap,
    this.color = MrCarsonColors.ink,
  });
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
            style: MrCarsonType.ui(size: 16, weight: FontWeight.w600, color: color),
          ),
        ),
      ),
    );
  }
}

/// Ready-state "Remove download" — warn wash fill + warn text.
class _WarnFillButton extends StatelessWidget {
  const _WarnFillButton({required this.label, required this.onTap});
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
            color: MrCarsonColors.warnSoft,
            border: Border.all(color: MrCarsonColors.warnSoft, width: 1),
            borderRadius: BorderRadius.circular(MrCarsonRadii.tile),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: MrCarsonType.ui(
              size: 16.5,
              weight: FontWeight.w600,
              color: MrCarsonColors.warn,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog "Remove" — solid warn fill, bg-colored text.
class _WarnSolidButton extends StatelessWidget {
  const _WarnSolidButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: MrCarsonColors.warn,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: MrCarsonType.ui(
              size: 16,
              weight: FontWeight.w600,
              color: MrCarsonColors.bg,
            ),
          ),
        ),
      ),
    );
  }
}

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
