import 'package:flutter/material.dart';

import 'package:mr_carson/theme/app_theme.dart';

/// An honest error state — a warning glyph, a message, and a "Retry" button.
///
/// Reusable presentational widget — no Riverpod, no services. Pump this into
/// the `error` arm of an `AsyncValue` for the failures that are worth surfacing
/// plainly: the model failed to load, the AI is unavailable, a DuckDB query or
/// a watch stream threw. Honesty over reassurance — show what went wrong and
/// give the user a way to try again.
///
/// [message] is the human-readable explanation. [onRetry] is invoked when the
/// user taps the button; [retryLabel] defaults to "Retry". [title] is an
/// optional bolder headline above the message.
class ErrorRetryState extends StatelessWidget {
  const ErrorRetryState({
    super.key,
    required this.message,
    required this.onRetry,
    this.title,
    this.retryLabel = 'Retry',
  });

  /// Human-readable explanation of what went wrong.
  final String message;

  /// Called when the user taps the retry button.
  final VoidCallback onRetry;

  /// Optional headline shown above [message].
  final String? title;

  /// Label for the retry button. Defaults to "Retry".
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: MrCarsonColors.warn,
              size: 40,
            ),
            const SizedBox(height: 16),
            if (title != null) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: MrCarsonType.display(
                  size: 22,
                  weight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: MrCarsonType.ui(
                size: 14,
                color: MrCarsonColors.ink2,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            _RetryButton(label: retryLabel, onTap: onRetry),
          ],
        ),
      ),
    );
  }
}

/// Solid accent pill button, matching the app's `_PrimaryButton` / `Review`
/// button idiom (GestureDetector + accent fill + accentInk label).
class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: MrCarsonColors.accent,
          borderRadius: BorderRadius.circular(MrCarsonRadii.tile),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: MrCarsonType.ui(
            size: 15,
            weight: FontWeight.w600,
            color: MrCarsonColors.accentInk,
          ),
        ),
      ),
    );
  }
}
