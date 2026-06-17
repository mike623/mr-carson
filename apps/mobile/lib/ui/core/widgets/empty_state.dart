import 'package:flutter/material.dart';
import 'package:mr_carson/theme/app_theme.dart';

/// Centered empty-state placeholder with a display-font title, optional muted
/// body, and an optional icon.
///
/// Copy should use the butler's voice — e.g. "Nothing to show just yet, sir."
/// Pure presentational — no providers or data dependencies.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.body,
    this.icon,
  });

  /// Primary message rendered in Cormorant Garamond (the butler's voice).
  final String title;

  /// Optional supporting copy rendered in Hanken Grotesk at reduced opacity.
  final String? body;

  /// Optional icon shown above the title.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 36,
                color: MrCarsonColors.ink3,
              ),
              const SizedBox(height: 16),
            ],
            Text(
              title,
              style: MrCarsonType.display(
                size: 22,
                weight: FontWeight.w600,
                color: MrCarsonColors.ink,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: 10),
              Text(
                body!,
                style: MrCarsonType.ui(
                  size: 14,
                  color: MrCarsonColors.ink3,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
