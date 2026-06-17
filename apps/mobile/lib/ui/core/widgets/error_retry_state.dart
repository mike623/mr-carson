import 'package:flutter/material.dart';
import 'package:mr_carson/theme/app_theme.dart';

/// Centered error message + "Try again" button.
///
/// Used by any screen that needs to surface a recoverable failure to the user.
/// Pure presentational — no providers or data dependencies.
///
/// The button matches the primary button style used throughout the app:
/// a solid [MrCarsonColors.accent] pill with [MrCarsonColors.accentInk] label,
/// at [MrCarsonRadii.tile] corner radius.
class ErrorRetryState extends StatelessWidget {
  const ErrorRetryState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  /// Human-readable error description shown above the retry button.
  final String message;

  /// Called when the user taps "Try again".
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: MrCarsonType.ui(
                size: 15,
                color: MrCarsonColors.ink2,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onRetry,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: MrCarsonColors.accent,
                  borderRadius: BorderRadius.circular(MrCarsonRadii.tile),
                ),
                child: Text(
                  'Try again',
                  style: MrCarsonType.ui(
                    size: 15,
                    weight: FontWeight.w600,
                    color: MrCarsonColors.accentInk,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
