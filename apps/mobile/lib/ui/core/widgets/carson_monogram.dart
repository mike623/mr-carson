import 'package:flutter/material.dart';
import 'package:mr_carson/theme/app_theme.dart';

/// The brass-bordered circle bearing a service bell — Mr. Carson's monogram.
///
/// Used at several sizes across the app (onboarding 78px with glow, ask header
/// 40px, carson chat bubble 28px, confirm note 30px). Each call passes its exact
/// dimensions so the rendered look is identical to the original inline copies.
///
/// Defaults reproduce the original look:
/// - [borderWidth] defaults to 1.5 (the big/medium variants use a 1.5px border).
/// - [filled] true paints a solid accent circle with the bell in
///   [MrCarsonColors.accentInk] (the confirm-note variant); false uses a
///   transparent/surface circle with an accent border and an accent bell.
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

  /// Paints a solid accent circle with the bell in [MrCarsonColors.accentInk].
  final bool filled;

  @override
  Widget build(BuildContext context) {
    // The bell glyph is sized to ~55% of the circle, matching the original SVG
    // proportions (40px circle → 22px svg, 28px → 16px, etc.).
    final glyph = size * 0.55;
    final color = filled ? MrCarsonColors.accentInk : MrCarsonColors.accent;

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
      child: CarsonBell(size: glyph, color: color),
    );
  }
}

/// The service-bell glyph alone (no circle). Brass stroke icon ported from the
/// design's inline SVG (viewBox 0 0 32 32, stroke-width 1.7, round caps).
class CarsonBell extends StatelessWidget {
  const CarsonBell({super.key, required this.size, this.color});

  /// Box side; the bell is drawn within a [size]×[size] square.
  final double size;

  /// Stroke colour. Defaults to [MrCarsonColors.accent].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _BellPainter(color ?? MrCarsonColors.accent),
    );
  }
}

class _BellPainter extends CustomPainter {
  _BellPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 32.0; // SVG authored on a 32-unit grid
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset p(double x, double y) => Offset(x * s, y * s);

    // Top knob: M14 7 a2 2 0 0 1 4 0
    final knob = Path()
      ..moveTo(14 * s, 7 * s)
      ..arcToPoint(p(18, 7), radius: Radius.circular(2 * s), clockwise: true);
    canvas.drawPath(knob, paint);

    // Stem: 16,8 -> 16,11
    canvas.drawLine(p(16, 8), p(16, 11), paint);

    // Dome: M9 23 C9 16 11 11 16 11 s7 5 7 12
    final dome = Path()
      ..moveTo(9 * s, 23 * s)
      ..cubicTo(9 * s, 16 * s, 11 * s, 11 * s, 16 * s, 11 * s)
      // smooth cubic 's7 5 7 12' → control reflected, then (16+7,11+5),(16+7,11+12)
      ..cubicTo(21 * s, 11 * s, 23 * s, 16 * s, 23 * s, 23 * s);
    canvas.drawPath(dome, paint);

    // Base line: 6.5,23 -> 25.5,23
    canvas.drawLine(p(6.5, 23), p(25.5, 23), paint);

    // Clapper: M13.6 25 a2.4 2.4 0 0 0 4.8 0
    final clapper = Path()
      ..moveTo(13.6 * s, 25 * s)
      ..arcToPoint(p(18.4, 25),
          radius: Radius.circular(2.4 * s), clockwise: false);
    canvas.drawPath(clapper, paint);

    // Centre dot (filled): cx16 cy19.4 r1.15
    canvas.drawCircle(
      p(16, 19.4),
      1.15 * s,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _BellPainter old) => old.color != color;
}
