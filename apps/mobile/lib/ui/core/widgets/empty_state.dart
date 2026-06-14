import 'package:flutter/material.dart';

import 'package:mr_carson/theme/app_theme.dart';

/// A real empty state — a soft accent-washed icon, a title, and an optional
/// subtitle, in the "Brass & Ink" palette.
///
/// Reusable presentational widget — no Riverpod, no services. Pump this into
/// the `data`-but-empty arm of an `AsyncValue` for the honest "nothing here
/// yet" moments: no expenses recorded, no answers yet, an empty search. This is
/// for genuine emptiness, not for errors — reach for [ErrorRetryState] when
/// something failed.
///
/// [icon] is the glyph shown in the accent-soft circle. [title] is the primary
/// line; [subtitle] is optional supporting text beneath it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  /// Glyph shown inside the accent-washed circle.
  final IconData icon;

  /// Primary line (the butler's voice — Cormorant display).
  final String title;

  /// Optional supporting text beneath [title].
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: MrCarsonColors.accentSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: MrCarsonColors.accent, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: MrCarsonType.display(
                size: 24,
                weight: FontWeight.w600,
                height: 1.15,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: MrCarsonType.ui(
                  size: 14,
                  color: MrCarsonColors.ink3,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
