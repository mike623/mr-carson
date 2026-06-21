import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/device_capability.dart';
import '../../ai/model_mode.dart';
import '../../data/providers.dart';
import '../../domain/models/ai_models.dart';
import '../../theme/app_theme.dart';
import '../ask/ask_screen.dart';
import '../confirm/confirm_screen.dart';
import '../detail/detail_screen.dart';
import '../ledger/ledger_screen.dart';
import '../manual/manual_entry_screen.dart';
import '../model/engage_screen.dart';
import '../model/model_lifecycle_view_model.dart';
import '../model/model_management_screen.dart';
import '../settings/settings_screen.dart';
import 'shell_view_model.dart';

/// Whether the user can start a receipt capture. True when the on-device model
/// is ready OR the resolved backend is online — cloud OCR needs no local model,
/// so Online users must not be blocked by the on-device model gate.
final captureReadyProvider = Provider<bool>((ref) {
  final mode = ref.watch(modelModeProvider);
  final cap = ref.watch(deviceCapabilityProvider);
  if (resolveBackend(mode, cap) == Backend.online) return true;
  return ref.watch(modelLifecycleProvider).isReady;
});

/// The in-app navigation shell — everything after onboarding.
///
/// Mirrors the design's component state machine
/// (`designs/mr-carson/project/Mr Carson.dc.html`): a floating bottom nav
/// (Ask · + · Ledger), an "add expense" action sheet, a butler toast, and the
/// background-pending flow (upload → processes on device → "Ready for your
/// review" → Confirm). Detail and Confirm present over the active tab.
///
/// A dumb view: navigation, the pending list, and the toast live in
/// [ShellViewModel]; this widget only renders state and forwards taps.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  Future<void> _openAddSheet(
    BuildContext context,
    ShellViewModel vm,
    bool isReady,
  ) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x8C000000),
      builder: (_) => const _AddSheet(),
    );
    const requireReason = 'To read a receipt, I must first come aboard.';
    if (choice == 'manual') {
      vm.go(ShellScreen.manual);
    } else if (choice == 'photo') {
      if (isReady) {
        vm.capturePhoto();
      } else {
        vm.requireModel(reason: requireReason);
      }
    } else if (choice == 'upload') {
      if (isReady) {
        vm.startUpload();
      } else {
        vm.requireModel(reason: requireReason);
      }
    }
  }

  Widget _body(ShellState s, ShellViewModel vm, List<LedgerPending> pendingList) {
    switch (s.screen) {
      case ShellScreen.ask:
        return const AskScreen();
      case ShellScreen.ledger:
        return LedgerScreen(
          pending: pendingList,
          onOpenExpense: vm.openExpense,
          onReviewPending: vm.reviewPending,
          onRetryPending: vm.retryPending,
          onDeletePending: vm.deletePending,
        );
      case ShellScreen.detail:
        return DetailScreen(
          id: s.selectedExpenseId ?? '',
          onBack: () => vm.go(ShellScreen.ledger),
        );
      case ShellScreen.confirm:
        return ConfirmScreen(
          pendingId: s.reviewingId ?? '',
          note: s.reviewingId != null
              ? 'All done while you were away, sir. Two figures want a glance.'
              : 'I read this just now, sir. Two figures want a glance.',
        );
      case ShellScreen.settings:
        return const SettingsScreen();
      case ShellScreen.modelMgmt:
        return const ModelManagementScreen();
      case ShellScreen.manual:
        return const ManualEntryScreen();
      case ShellScreen.engage:
        return const EngageScreen();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(shellViewModelProvider);
    final vm = ref.read(shellViewModelProvider.notifier);
    final isReady = ref.watch(captureReadyProvider);

    // Map pending DB rows to LedgerPending view model objects.
    final pendingRows = ref.watch(pendingReceiptsProvider);
    final pendingList = pendingRows.maybeWhen(
      data: (rows) => rows.map((r) {
        final ready = r.status == PendingStatus.awaitingConfirmation.name;
        final failed = r.status == PendingStatus.failed.name;
        return LedgerPending(
          id: r.id,
          ready: ready,
          failed: failed,
          error: r.errorMessage,
          stage: failed
              ? 'I could not read that one, sir'
              : ready
                  ? 'Ready for your review'
                  : 'Reading the receipt…',
          pct: ready
              ? 100
              : failed
                  ? 0
                  : 50,
          merchant: null,
          total: null,
        );
      }).toList(),
      orElse: () => <LedgerPending>[],
    );

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Stack(
        children: [
          Positioned.fill(child: _body(s, vm, pendingList)),
          if (s.navVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomNav(
                current: s.screen == ShellScreen.ask ? 0 : 1,
                hasPending: pendingList.isNotEmpty,
                onAsk: () => vm.go(ShellScreen.ask),
                onLedger: () => vm.go(ShellScreen.ledger),
                onAdd: () => _openAddSheet(context, vm, isReady),
              ),
            ),
          if (s.toast != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 130,
              child: Center(child: _Toast(message: s.toast!)),
            ),
        ],
      ),
    );
  }
}

/// Full-width bottom tab bar: Ask · + · Ledger.
///
/// Edge-to-edge bar pinned to the bottom with a 1px top border and an upward
/// shadow, mirroring the design's BOTTOM NAV block. The center "+" is an accent
/// circle raised so it overflows above the bar's top edge; the bar does not
/// clip, so the raised button stays unclipped and tappable.
class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.current,
    required this.hasPending,
    required this.onAsk,
    required this.onLedger,
    required this.onAdd,
  });

  final int current; // 0 = Ask, 1 = Ledger
  final bool hasPending;
  final VoidCallback onAsk;
  final VoidCallback onLedger;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MrCarsonColors.surface,
        border: Border(top: BorderSide(color: MrCarsonColors.line)),
        boxShadow: [
          // ~rgba(0,0,0,0.28), cast upward.
          BoxShadow(color: Color(0x47000000), blurRadius: 24, offset: Offset(0, -8)),
        ],
      ),
      // Design: padding 12px top, 24px horizontal, 30px bottom (safe-area-ish).
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _navItem(
            icon: Icons.chat_bubble_outline,
            label: 'Ask',
            active: current == 0,
            onTap: onAsk,
          ),
          _AddButton(onTap: onAdd),
          _navItem(
            icon: Icons.format_list_bulleted,
            label: 'Ledger',
            active: current == 1,
            onTap: onLedger,
            badge: hasPending,
          ),
        ],
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    bool badge = false,
  }) {
    final color = active ? MrCarsonColors.accent : MrCarsonColors.ink3;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 23, color: color),
                if (badge)
                  Positioned(
                    top: -3,
                    right: -2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: MrCarsonColors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: MrCarsonColors.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(label, style: MrCarsonType.ui(size: 10.5, weight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

/// The raised center "+" — a 56×56 accent circle lifted 26px above the bar's
/// top edge (design `margin-top:-26px`). [Transform.translate] keeps it laid
/// out within the row while painting it raised; the bar does not clip, so it
/// stays fully visible and tappable.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -26),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: MrCarsonColors.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: MrCarsonColors.accentSoft, blurRadius: 20, offset: Offset(0, 8)),
            ],
          ),
          child: const Icon(Icons.add, color: MrCarsonColors.accentInk, size: 26),
        ),
      ),
    );
  }
}

/// "Add an expense" action sheet — Enter manually / Take a photograph /
/// Upload from library (design 812-854).
///
/// "Enter manually" is always available; the two receipt-reading options are
/// model-gated. When the model isn't ready a contextual note is shown above the
/// options and the gated options carry a "Setup" lock chip; when ready they
/// show a chevron instead.
class _AddSheet extends ConsumerWidget {
  const _AddSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isReady = ref.watch(captureReadyProvider);

    return Container(
      decoration: const BoxDecoration(
        color: MrCarsonColors.surface,
        border: Border(top: BorderSide(color: MrCarsonColors.line)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(MrCarsonRadii.sheet)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 34),
      // Scrollable so the sheet never overflows on short screens — the extra
      // "needs model" note can push content past the modal's max height.
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: MrCarsonColors.ink3.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Text('Add an expense', style: MrCarsonType.display(size: 26, weight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text('How shall we record it, sir?',
              style: MrCarsonType.ui(size: 13.5, color: MrCarsonColors.ink3)),
          if (!isReady) ...[
            const SizedBox(height: 14),
            _NeedsModelNote(),
          ],
          const SizedBox(height: 18),
          _option(
            context,
            icon: Icons.edit_outlined,
            title: 'Enter manually',
            subtitle: 'Tell me the figures yourself, sir',
            value: 'manual',
            gated: false,
            isReady: isReady,
          ),
          const SizedBox(height: 10),
          _option(
            context,
            icon: Icons.photo_camera_outlined,
            title: 'Take a photograph',
            subtitle: 'Capture a receipt; I shall read it',
            value: 'photo',
            gated: true,
            isReady: isReady,
          ),
          const SizedBox(height: 10),
          _option(
            context,
            icon: Icons.photo_library_outlined,
            title: 'Upload from library',
            subtitle: 'I shall read it in the background',
            value: 'upload',
            gated: true,
            isReady: isReady,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Not just now',
                  style: MrCarsonType.ui(size: 15.5, weight: FontWeight.w600, color: MrCarsonColors.ink2)),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required bool gated,
    required bool isReady,
  }) {
    final showLock = gated && !isReady;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(value),
      child: Container(
        decoration: BoxDecoration(
          color: MrCarsonColors.bg,
          border: Border.all(color: MrCarsonColors.line),
          borderRadius: BorderRadius.circular(MrCarsonRadii.tile),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: MrCarsonColors.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: MrCarsonColors.accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: MrCarsonType.ui(size: 16, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: MrCarsonType.ui(size: 12.5, color: MrCarsonColors.ink3)),
                ],
              ),
            ),
            if (showLock)
              const _SetupChip()
            else
              const Icon(Icons.chevron_right, color: MrCarsonColors.ink3, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Contextual note shown in the Add sheet while the model is absent
/// (design 819-824).
class _NeedsModelNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.accentSoft,
        border: Border.all(color: MrCarsonColors.line),
        borderRadius: BorderRadius.circular(13),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 4),
            decoration: const BoxDecoration(
              color: MrCarsonColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Entering by hand needs nothing of me, sir. To read a receipt '
              'I must first come aboard — a one-time 2.4 GB download.',
              style: MrCarsonType.ui(size: 12.5, color: MrCarsonColors.ink2, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Setup" lock chip shown on model-gated options while the model is absent
/// (design 839/847).
class _SetupChip extends StatelessWidget {
  const _SetupChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: MrCarsonColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 11, color: MrCarsonColors.ink3),
          const SizedBox(width: 5),
          Text('Setup',
              style: MrCarsonType.ui(size: 11, weight: FontWeight.w600, color: MrCarsonColors.ink3)),
        ],
      ),
    );
  }
}

/// Butler toast — dark ink pill, "Very good, sir."
class _Toast extends StatelessWidget {
  const _Toast({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.ink,
        borderRadius: BorderRadius.circular(13),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 26, offset: Offset(0, 10))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Text(message,
          style: MrCarsonType.ui(size: 14, weight: FontWeight.w600, color: MrCarsonColors.bg)),
    );
  }
}
