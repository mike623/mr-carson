import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mr_carson/theme/app_theme.dart';

/// Shared model-download progress UI.
///
/// Extracted from the onboarding flow so the in-app model surfaces (Engage,
/// Model Management) and onboarding all render an identical progress ring and
/// stats card from a single source of truth.
///
/// The byte/speed/ETA figures are derived by [modelDownloadStats]. Onboarding
/// passes its real on-device model size; the in-app screens pass the 2.4 GB /
/// 2,400 MB figure the rest of the app and the design copy use.

/// Animated progress ring with a percent (or a checkmark when [done]) centered.
///
/// [size] controls the ring diameter (onboarding/Engage use 172; Model
/// Management uses a smaller ring). [pctFontSize] and [checkSize] scale the
/// center content with the ring.
class ModelProgressRing extends StatelessWidget {
  const ModelProgressRing({
    super.key,
    required this.pct,
    this.done = false,
    this.size = 172,
    this.pctFontSize = 50,
    this.checkSize = 40,
  });

  /// Download progress, 0–100.
  final double pct;

  /// When true, paints a completed (full) ring with a checkmark.
  final bool done;

  /// Outer diameter of the ring.
  final double size;

  /// Font size of the centered percent number.
  final double pctFontSize;

  /// Size of the checkmark shown in the [done] state.
  final double checkSize;

  @override
  Widget build(BuildContext context) {
    final intPct = pct.toInt();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: ModelRingPainter(progress: done ? 1 : pct / 100),
          ),
          if (!done) ...[
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$intPct',
                  style: MrCarsonType.display(
                    size: pctFontSize,
                    weight: FontWeight.w600,
                  ),
                ),
                Text(
                  'per cent',
                  style: MrCarsonType.ui(
                    size: 12.5,
                    color: MrCarsonColors.ink3,
                  ),
                ),
              ],
            ),
          ] else ...[
            CustomPaint(
              size: Size(checkSize, checkSize),
              painter: ModelCheckPainter(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Paints the two-layer progress ring (track + arc).
class ModelRingPainter extends CustomPainter {
  const ModelRingPainter({required this.progress});

  /// 0–1.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 6) / 2;
    const stroke = 6.0;

    // Track
    final trackPaint = Paint()
      ..color = MrCarsonColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc
    if (progress > 0) {
      final arcPaint = Paint()
        ..color = MrCarsonColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2; // top
      final sweepAngle = 2 * math.pi * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(ModelRingPainter old) => old.progress != progress;
}

/// Paints a large accent checkmark for the "done" state.
class ModelCheckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MrCarsonColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.15, size.height * 0.52)
      ..lineTo(size.width * 0.40, size.height * 0.76)
      ..lineTo(size.width * 0.85, size.height * 0.28);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(ModelCheckPainter old) => false;
}

/// Download stats card: "{mb} / {total} MB" + speed on the top row, ETA +
/// "One-time only" on the bottom row. Optionally shows the "Best done on
/// Wi-Fi, sir." hint beneath (onboarding / Engage show it; Model Management
/// renders the hint separately).
class ModelStatsCard extends StatelessWidget {
  const ModelStatsCard({
    super.key,
    required this.stats,
    this.showWifiHint = false,
    this.totalMbLabel = '2,400 MB',
  });

  final ModelDownloadStats stats;

  /// When true, renders the "Best done on Wi-Fi, sir." warn hint below the card.
  final bool showWifiHint;

  /// Label for the total size shown in the top-left ("{mb} of {totalMbLabel}").
  final String totalMbLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: MrCarsonColors.surface,
            border: Border.all(color: MrCarsonColors.line, width: 1),
            borderRadius: BorderRadius.circular(MrCarsonRadii.tile),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${stats.mb} of $totalMbLabel',
                    style: MrCarsonType.ui(size: 14),
                  ),
                  Text(
                    '${stats.speed} MB/s',
                    style: MrCarsonType.ui(size: 14),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${stats.eta} remaining',
                    style: MrCarsonType.ui(
                      size: 13,
                      color: MrCarsonColors.ink3,
                    ),
                  ),
                  Text(
                    'One-time only',
                    style: MrCarsonType.ui(
                      size: 13,
                      color: MrCarsonColors.ink3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showWifiHint) ...[
          const SizedBox(height: 10),
          const ModelWifiHint(),
        ],
      ],
    );
  }
}

/// "Best done on Wi-Fi, sir." with a small warn dot.
class ModelWifiHint extends StatelessWidget {
  const ModelWifiHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: MrCarsonColors.warn,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Best done on Wi-Fi, sir.',
          style: MrCarsonType.ui(size: 12.5, color: MrCarsonColors.ink3),
        ),
      ],
    );
  }
}

/// Immutable holder for the derived download stat strings.
class ModelDownloadStats {
  const ModelDownloadStats({
    required this.mb,
    required this.speed,
    required this.eta,
  });

  /// Megabytes downloaded so far, formatted (no decimals).
  final String mb;

  /// Estimated download speed in MB/s, formatted (one decimal).
  final String speed;

  /// Formatted ETA (e.g. "1m 20s", "0s").
  final String eta;
}

/// Derives [ModelDownloadStats] for a given [pct] (0–100) and total size in MB.
///
/// [pct] should be the real download percentage where available. The byte count
/// tracks it exactly; speed + ETA are estimates (the underlying stream is
/// percent-only — no byte/speed signal).
ModelDownloadStats modelDownloadStats(double pct, {double totalMb = 2400.0}) {
  final mb = (pct / 100 * totalMb).clamp(0, totalMb);
  final speed = 45 + 75 * (0.5 + 0.5 * math.sin(pct * 0.25)); // estimated MB/s
  final remaining = pct >= 100 ? 0.0 : ((totalMb - mb) / speed); // seconds
  return ModelDownloadStats(
    mb: mb.toStringAsFixed(0),
    speed: speed.toStringAsFixed(1),
    eta: formatEta(remaining),
  );
}

/// Formats a seconds value into a short ETA string ("45s", "1m 20s", "0s").
String formatEta(double secs) {
  if (secs <= 0) return '0s';
  if (secs < 60) return '${secs.round()}s';
  final m = (secs / 60).floor();
  final s = (secs % 60).round();
  return '${m}m ${s}s';
}
