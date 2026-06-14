import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../ask/ask_screen.dart';
import '../confirm/confirm_screen.dart';
import '../detail/detail_screen.dart';
import '../ledger/ledger_screen.dart';
import 'shell_view_model.dart';

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

  Future<void> _openAddSheet(BuildContext context, ShellViewModel vm) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x8C000000),
      builder: (_) => const _AddSheet(),
    );
    if (choice == 'photo') {
      vm.capturePhoto();
    } else if (choice == 'upload') {
      vm.startUpload();
    }
  }

  Widget _body(ShellState s, ShellViewModel vm) {
    switch (s.screen) {
      case ShellScreen.ask:
        return const AskScreen();
      case ShellScreen.ledger:
        return LedgerScreen(
          pending: s.pending,
          onOpenExpense: (_) => vm.go(ShellScreen.detail),
          onReviewPending: vm.reviewPending,
        );
      case ShellScreen.detail:
        return DetailScreen(onBack: () => vm.go(ShellScreen.ledger));
      case ShellScreen.confirm:
        return ConfirmScreen(
          note: s.reviewingId != null
              ? 'All done while you were away, sir. Two figures want a glance.'
              : 'I read this just now, sir. Two figures want a glance.',
          onDiscard: vm.discardConfirm,
          onSave: vm.saveConfirm,
        );
      // TODO(task 4): replace with real Settings screen.
      case ShellScreen.settings:
        return const _PlaceholderScreen('Settings');
      // TODO(task 4): replace with real Model Management screen.
      case ShellScreen.modelMgmt:
        return const _PlaceholderScreen('Model Management');
      // TODO(task 2): replace with real Manual Entry screen.
      case ShellScreen.manual:
        return const _PlaceholderScreen('Manual Entry');
      // TODO(task 3): replace with real Engage screen.
      case ShellScreen.engage:
        return const _PlaceholderScreen('Engage');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(shellViewModelProvider);
    final vm = ref.read(shellViewModelProvider.notifier);

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Stack(
        children: [
          Positioned.fill(child: _body(s, vm)),
          if (s.navVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomNav(
                current: s.screen == ShellScreen.ask ? 0 : 1,
                hasPending: s.pending.isNotEmpty,
                onAsk: () => vm.go(ShellScreen.ask),
                onLedger: () => vm.go(ShellScreen.ledger),
                onAdd: () => _openAddSheet(context, vm),
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

/// "Add an expense" action sheet — Take a photograph / Upload from library.
class _AddSheet extends StatelessWidget {
  const _AddSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MrCarsonColors.surface,
        border: Border(top: BorderSide(color: MrCarsonColors.line)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(MrCarsonRadii.sheet)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 34),
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
          Text('How shall I receive the receipt, sir?',
              style: MrCarsonType.ui(size: 13.5, color: MrCarsonColors.ink3)),
          const SizedBox(height: 18),
          _option(
            context,
            icon: Icons.photo_camera_outlined,
            title: 'Take a photograph',
            subtitle: 'Capture a receipt this instant',
            value: 'photo',
          ),
          const SizedBox(height: 10),
          _option(
            context,
            icon: Icons.photo_library_outlined,
            title: 'Upload from library',
            subtitle: 'I shall read it in the background',
            value: 'upload',
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
    );
  }

  Widget _option(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
  }) {
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
            const Icon(Icons.chevron_right, color: MrCarsonColors.ink3, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Temporary placeholder for screens not yet built (Settings, Model
/// Management, Manual Entry, Engage). Replaced by real screens in later tasks.
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Center(
        child: Text(name, style: MrCarsonType.display(size: 32)),
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
