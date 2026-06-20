import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mr_carson/theme/app_theme.dart';

import '../../ai/device_capability.dart';
import '../../ai/model_mode.dart';
import '../model/model_lifecycle_view_model.dart';
import '../shell/shell_view_model.dart';
import 'currency_provider.dart';
import 'transcript_prefs.dart';

/// The Settings (gear) page.
///
/// Sections: Mr. Carson's mind (model-status row → Model Management), General
/// (currency picker), Discretion (two static assurances), Livery (theme
/// swatches — brass-locked, cosmetic only), and a version footer.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(modelLifecycleProvider);
    final currency = ref.watch(currencyProvider);
    final currencyVm = ref.read(currencyProvider.notifier);
    final shellVm = ref.read(shellViewModelProvider.notifier);

    final status = _modelStatus(model);

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BackHeader(
            title: 'Settings',
            onBack: () => shellVm.go(ShellScreen.ask),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Mr. Carson's mind ──────────────────────────────────
                  const _SectionLabel("Mr. Carson's mind"),
                  _ModelCard(
                    statusText: status.label,
                    statusColor: status.color,
                    onTap: () => shellVm.go(ShellScreen.modelMgmt),
                  ),

                  // ── Where he thinks ───────────────────────────────────
                  const SizedBox(height: 18),
                  const _SectionLabel('Where he thinks'),
                  const _ModelLocationCard(),

                  // ── General → Currency ─────────────────────────────────
                  const _SectionLabel('General'),
                  _CurrencyRow(
                    selected: currency,
                    onSelect: currencyVm.set,
                  ),

                  // ── His workings ───────────────────────────────────────
                  const _SectionLabel("His workings"),
                  const _TranscriptCard(),

                  // ── Discretion ─────────────────────────────────────────
                  const _SectionLabel('Discretion'),
                  const _DiscretionCard(),

                  // ── Livery ─────────────────────────────────────────────
                  const _SectionLabel('Livery'),
                  const _LiverySwatches(),

                  const SizedBox(height: 28),
                  Center(
                    child: Text(
                      'Mr. Carson · on-device · v1.0',
                      style: MrCarsonType.ui(
                        size: 11.5,
                        color: MrCarsonColors.ink3,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Maps the model lifecycle to a status label + color for the model row.
  static ({String label, Color color}) _modelStatus(ModelLifecycleState s) {
    if (s.isReady) {
      return (label: 'Ready', color: MrCarsonColors.grocery);
    }
    if (s.isDownloading) {
      return (
        label: 'Downloading… ${s.downloadPct.toInt()}%',
        color: MrCarsonColors.accent,
      );
    }
    if (s.isError) {
      return (label: 'Needs attention', color: MrCarsonColors.warn);
    }
    return (label: 'Not set up', color: MrCarsonColors.ink3);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Header
// ═══════════════════════════════════════════════════════════════════════════

/// Back-chevron header used by Settings and Model Management.
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
// Sections
// ═══════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Text(
        label.toUpperCase(),
        style: MrCarsonType.ui(
          size: 11,
          color: MrCarsonColors.ink3,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Tappable model-status card — brass "C" tile, "The model", status line.
class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.statusText,
    required this.statusColor,
    required this.onTap,
  });

  final String statusText;
  final Color statusColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: MrCarsonColors.surface,
          border: Border.all(color: MrCarsonColors.line, width: 1),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Brass "C" rounded-square tile.
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: MrCarsonColors.accentSoft,
                border: Border.all(color: MrCarsonColors.accent, width: 1.5),
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'C',
                  style: MrCarsonType.display(
                    size: 27,
                    weight: FontWeight.w600,
                    color: MrCarsonColors.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The model',
                    style: MrCarsonType.ui(
                      size: 15.5,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          statusText,
                          style: MrCarsonType.ui(
                            size: 12.5,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: MrCarsonColors.ink3,
            ),
          ],
        ),
      ),
    );
  }
}

/// Currency row with a £/$ segmented control.
class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({required this.selected, required this.onSelect});
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        border: Border.all(color: MrCarsonColors.line, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Currency', style: MrCarsonType.ui(size: 14.5)),
                const SizedBox(height: 2),
                Text(
                  'For the figures you enter, sir.',
                  style: MrCarsonType.ui(size: 12, color: MrCarsonColors.ink3),
                ),
              ],
            ),
          ),
          // Segmented control.
          Container(
            decoration: BoxDecoration(
              color: MrCarsonColors.bg,
              border: Border.all(color: MrCarsonColors.line, width: 1),
              borderRadius: BorderRadius.circular(11),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in kCurrencyOptions)
                  Padding(
                    padding: EdgeInsets.only(
                      left: c == kCurrencyOptions.first ? 0 : 4,
                    ),
                    child: _CurrencyButton(
                      label: c,
                      selected: c == selected,
                      onTap: () => onSelect(c),
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

class _CurrencyButton extends StatelessWidget {
  const _CurrencyButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minWidth: 46),
        height: 34,
        decoration: BoxDecoration(
          color: selected ? MrCarsonColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: MrCarsonType.ui(
            size: 14,
            weight: FontWeight.w600,
            color: selected ? MrCarsonColors.accentInk : MrCarsonColors.ink2,
          ),
        ),
      ),
    );
  }
}

/// Segmented Auto / Offline / Online control with consent + capability hint.
class _ModelLocationCard extends ConsumerWidget {
  const _ModelLocationCard();

  static const _modes = [
    (mode: ModelMode.auto, label: 'Auto'),
    (mode: ModelMode.offline, label: 'Offline'),
    (mode: ModelMode.online, label: 'Online'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(modelModeProvider);
    final cap = ref.watch(deviceCapabilityProvider);

    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        border: Border.all(color: MrCarsonColors.line, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reads receipts', style: MrCarsonType.ui(size: 14.5)),
          const SizedBox(height: 2),
          Text(
            'Offline keeps everything on this phone. Online is faster and works '
            'on any device, but sends the receipt to our server to be read.',
            style: MrCarsonType.ui(size: 12, color: MrCarsonColors.ink3),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final m in _modes)
                Padding(
                  padding: EdgeInsets.only(left: m == _modes.first ? 0 : 6),
                  child: _ModeButton(
                    label: m.label,
                    selected: m.mode == selected,
                    onTap: () => _choose(context, ref, m.mode),
                  ),
                ),
            ],
          ),
          if (!cap.canRunOffline && cap.reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              cap.reason,
              style: MrCarsonType.ui(size: 11.5, color: MrCarsonColors.warn),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _choose(
      BuildContext context, WidgetRef ref, ModelMode mode) async {
    if (mode == ModelMode.online) {
      final ok = await _confirmOnline(context);
      if (ok != true) return;
    }
    ref.read(modelModeProvider.notifier).set(mode);
  }

  Future<bool?> _confirmOnline(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MrCarsonColors.surface,
        title: Text('Read receipts online?',
            style: MrCarsonType.ui(size: 16, weight: FontWeight.w600)),
        content: Text(
          'With Online, the receipt image leaves your phone and is sent to our '
          'server to be read. Nothing is stored there. You can switch back to '
          'Offline at any time.',
          style: MrCarsonType.ui(size: 13.5, color: MrCarsonColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep offline',
                style: MrCarsonType.ui(size: 14, color: MrCarsonColors.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Use Online',
                style: MrCarsonType.ui(
                    size: 14,
                    color: MrCarsonColors.accent,
                    weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? MrCarsonColors.accent : MrCarsonColors.bg,
          border: Border.all(color: MrCarsonColors.line, width: 1),
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: MrCarsonType.ui(
            size: 13.5,
            weight: FontWeight.w600,
            color: selected ? MrCarsonColors.accentInk : MrCarsonColors.ink2,
          ),
        ),
      ),
    );
  }
}

/// Two discretion rows — copy reflects the active backend.
class _DiscretionCard extends ConsumerWidget {
  const _DiscretionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modelModeProvider);
    final cap = ref.watch(deviceCapabilityProvider);
    final online = resolveBackend(mode, cap) == Backend.online;

    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        border: Border.all(color: MrCarsonColors.line, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _row(
            dot: online ? MrCarsonColors.warn : MrCarsonColors.grocery,
            label: online
                ? 'Receipts are read online when needed'
                : 'Everything stays on this phone',
            trailing: online ? 'Online' : 'Always',
            border: true,
          ),
          _row(
            dot: MrCarsonColors.transport,
            label: online
                ? 'No account — only receipt images are sent'
                : 'No account, no cloud, no sign-in',
            trailing: '—',
            border: false,
          ),
        ],
      ),
    );
  }

  Widget _row({
    required Color dot,
    required String label,
    required String trailing,
    required bool border,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: border
            ? const Border(bottom: BorderSide(color: MrCarsonColors.line))
            : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: MrCarsonType.ui(size: 14.5))),
          Text(
            trailing,
            style: MrCarsonType.ui(size: 12.5, color: MrCarsonColors.ink3),
          ),
        ],
      ),
    );
  }
}

/// Two opt-in toggles controlling whether the Ask transcript reveals Mr.
/// Carson's reasoning and the ledger lookups (tool calls) behind each reply.
/// Both default off — the chat stays clean.
class _TranscriptCard extends ConsumerWidget {
  const _TranscriptCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(transcriptPrefsProvider);
    final vm = ref.read(transcriptPrefsProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        border: Border.all(color: MrCarsonColors.line, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _ToggleRow(
            label: 'Show his reasoning',
            sub: 'Reveal the model\'s private thinking.',
            value: prefs.showThinking,
            onChanged: vm.setShowThinking,
            border: true,
          ),
          _ToggleRow(
            label: 'Show his workings',
            sub: 'List the ledger lookups behind each reply.',
            value: prefs.showToolCalls,
            onChanged: vm.setShowToolCalls,
            border: false,
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
    required this.border,
  });

  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: border
            ? const Border(bottom: BorderSide(color: MrCarsonColors.line))
            : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: MrCarsonType.ui(size: 14.5)),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: MrCarsonType.ui(size: 12, color: MrCarsonColors.ink3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: MrCarsonColors.accentInk,
            activeTrackColor: MrCarsonColors.accent,
            inactiveThumbColor: MrCarsonColors.ink3,
            inactiveTrackColor: MrCarsonColors.bg,
            trackOutlineColor:
                const WidgetStatePropertyAll(MrCarsonColors.line),
          ),
        ],
      ),
    );
  }
}

/// Three theme swatches. The app is brass-locked: only "Brass & Ink" is
/// selectable (ring) and there is no runtime theming engine — tapping the
/// other swatches is a deliberate no-op (purely cosmetic affordance).
class _LiverySwatches extends StatelessWidget {
  const _LiverySwatches();

  static const _themes = [
    (label: 'Brass & Ink', swatch: MrCarsonColors.accent, selected: true),
    (label: 'Study Green', swatch: MrCarsonColors.grocery, selected: false),
    (label: 'Silver Service', swatch: Color(0xFFB9BEC4), selected: false),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _themes.length; i++) ...[
          if (i > 0) const SizedBox(width: 11),
          Expanded(
            child: _Swatch(
              label: _themes[i].label,
              color: _themes[i].swatch,
              selected: _themes[i].selected,
            ),
          ),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.color,
    required this.selected,
  });
  final String label;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        border: Border.all(
          // Selected: 2px solid ink (design line ~579: '2px solid var(--ink)').
          color: selected ? MrCarsonColors.ink : MrCarsonColors.line,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
        // Selected outer double-ring (design 'ring'): a 2px bg gap then a
        // 3.5px accent ring outside it. Inner shadow listed first so it sits
        // beneath the accent ring.
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: MrCarsonColors.bg,
                  blurRadius: 0,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: MrCarsonColors.accent,
                  blurRadius: 0,
                  spreadRadius: 3.5,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(10, 13, 10, 12),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: MrCarsonColors.line, width: 1),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            label,
            textAlign: TextAlign.center,
            style: MrCarsonType.ui(
              size: 12,
              weight: FontWeight.w600,
              color: MrCarsonColors.ink2,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
