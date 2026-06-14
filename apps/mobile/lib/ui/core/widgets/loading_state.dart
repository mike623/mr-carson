import 'package:flutter/material.dart';

import 'package:mr_carson/theme/app_theme.dart';

/// A centred progress indicator with an optional label, in the "Brass & Ink"
/// palette.
///
/// Reusable presentational widget — no Riverpod, no services. Pump this into
/// the `loading` arm of an `AsyncValue` (model loading, first DB read, an
/// in-flight AI answer, etc.).
///
/// [label] is an optional line of secondary text shown beneath the spinner
/// (e.g. "Reading the ledger…", "Preparing your answer…").
/// [size] is the diameter of the spinner; defaults to 28.
class LoadingState extends StatelessWidget {
  const LoadingState({
    super.key,
    this.label,
    this.size = 28,
  });

  /// Optional caption shown beneath the spinner.
  final String? label;

  /// Diameter of the circular progress indicator.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: const CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(MrCarsonColors.accent),
              ),
            ),
            if (label != null) ...[
              const SizedBox(height: 14),
              Text(
                label!,
                textAlign: TextAlign.center,
                style: MrCarsonType.ui(size: 13, color: MrCarsonColors.ink3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
