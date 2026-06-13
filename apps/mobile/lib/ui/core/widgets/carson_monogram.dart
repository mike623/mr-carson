import 'package:flutter/material.dart';
import 'package:mr_carson/theme/app_theme.dart';

/// The brass-bordered circle bearing a Cormorant "C" — Mr. Carson's monogram.
///
/// Used at several sizes across the app (onboarding 78px with glow, ask header
/// 40px, carson chat bubble 28px, confirm note 30px). Each call passes its exact
/// dimensions so the rendered look is identical to the original inline copies.
///
/// Defaults reproduce the original look:
/// - [borderWidth] defaults to 1.5 (the big/medium variants use a 1.5px border).
/// - [filled] true paints a solid accent circle with the "C" in [MrCarsonColors.accentInk]
///   (the confirm-note variant); false uses a transparent/surface circle with an
///   accent border and the "C" in [MrCarsonColors.accent].
/// - [glow] true adds the soft accent glow ring (onboarding welcome monogram).
/// - [surfaceFill] true fills the circle with [MrCarsonColors.surface] behind the
///   accent border (onboarding welcome monogram); false leaves it transparent.
class CarsonMonogram extends StatelessWidget {
  const CarsonMonogram({
    super.key,
    required this.size,
    this.borderWidth = 1.5,
    this.glow = false,
    this.surfaceFill = false,
    this.filled = false,
  });

  /// Outer diameter of the circle.
  final double size;

  /// Width of the accent border (ignored when [filled] is true).
  final double borderWidth;

  /// Adds the soft accent glow ring behind the circle.
  final bool glow;

  /// Fills the circle with [MrCarsonColors.surface] (only used with a border).
  final bool surfaceFill;

  /// Paints a solid accent circle with the "C" in [MrCarsonColors.accentInk].
  final bool filled;

  @override
  Widget build(BuildContext context) {
    // The "C" glyph is sized proportionally to the original hand-tuned values:
    //   78 -> 46, 40 -> 24, 30 -> 17, 28 -> 16.
    final glyphSize = _glyphSizeFor(size);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled
            ? MrCarsonColors.accent
            : (surfaceFill ? MrCarsonColors.surface : null),
        border: filled
            ? null
            : Border.all(color: MrCarsonColors.accent, width: borderWidth),
        boxShadow: glow
            ? const [
                BoxShadow(
                  color: MrCarsonColors.accentSoft,
                  blurRadius: 12,
                  spreadRadius: 6,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        'C',
        style: MrCarsonType.display(
          size: glyphSize,
          weight: FontWeight.w600,
          color: filled ? MrCarsonColors.accentInk : MrCarsonColors.accent,
        ),
      ),
    );
  }

  /// Maps an outer diameter to the original "C" glyph size used in each
  /// inline copy, preserving the exact visual proportions.
  static double _glyphSizeFor(double size) {
    if (size >= 78) return 46;
    if (size >= 40) return 24;
    if (size >= 30) return 17;
    return 16; // 28px bubble avatar
  }
}
