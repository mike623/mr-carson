import 'package:flutter/material.dart';
import 'package:mr_carson/theme/app_theme.dart';

/// Centered brass spinner with an optional caption.
///
/// Used by ledger, detail, and any screen that needs a full-body loading
/// placeholder. Pure presentational — no providers or data dependencies.
///
/// The spinner matches the `_BrassSpinner` style used in `ask_screen.dart`:
/// a [CircularProgressIndicator] tinted [MrCarsonColors.accent] with a soft
/// [MrCarsonColors.accentSoft] track.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message});

  /// Optional caption rendered beneath the spinner in the butler's voice.
  /// E.g. "One moment, sir." — pass null to show the spinner alone.
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation(MrCarsonColors.accent),
              backgroundColor: MrCarsonColors.accentSoft,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: MrCarsonType.ui(
                size: 14,
                color: MrCarsonColors.ink3,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
