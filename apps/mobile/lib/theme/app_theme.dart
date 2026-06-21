import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Mr. Carson design system — "Brass & Ink" (dark-first).
///
/// Ported verbatim from the Claude Design handoff
/// (`designs/mr-carson/project/Mr Carson.dc.html`, the `brass` palette).
/// Discreet English-butler aesthetic: warm near-black ink, charcoal surfaces,
/// antique-brass accent. Type: Cormorant Garamond (display / numerals — the
/// butler's voice) + Hanken Grotesk (UI / body).
class MrCarsonColors {
  const MrCarsonColors._();

  /// Warm near-black page background. CSS `--bg`.
  static const bg = Color(0xFF15120D);

  /// Card / raised surface. CSS `--surface`.
  static const surface = Color(0xFF1F1B14);

  /// Deeper surface (tracks, chips). CSS `--surface-2`.
  static const surface2 = Color(0xFF2A2419);

  /// Hairline borders — brass at 16%. CSS `--line`.
  static const line = Color(0x29C9A86A);

  /// Primary text — warm white. CSS `--ink`.
  static const ink = Color(0xFFF3ECDD);

  /// Secondary text — ink at 62%. CSS `--ink-2`.
  static const ink2 = Color(0x9EF3ECDD);

  /// Tertiary text / hints — ink at 34%. CSS `--ink-3`.
  static const ink3 = Color(0x57F3ECDD);

  /// Antique-brass accent. CSS `--accent`.
  static const accent = Color(0xFFC9A86A);

  /// Accent wash (soft fills, badges) — brass at 14%. CSS `--accent-soft`.
  static const accentSoft = Color(0x24C9A86A);

  /// Ink color that sits on top of the accent (e.g. button label). CSS `--accent-ink`.
  static const accentInk = Color(0xFF191510);

  /// Warning amber (low-confidence cues). CSS `--warn`.
  static const warn = Color(0xFFD8A45E);

  /// Warning wash — amber at 15%. CSS `--warn-soft`.
  static const warnSoft = Color(0x26D8A45E);

  // Category accents (chart bars, expense initials).
  static const grocery = Color(0xFF9DB58C); // CSS `--grocery`
  static const transport = Color(0xFF8FA9C2); // CSS `--transport`
  static const house = Color(0xFFC98F6A); // CSS `--house`

  /// Dot/bar colour for a category name. Falls back to brass for anything
  /// outside the three palette accents.
  static Color forCategory(String name) {
    switch (name.toLowerCase()) {
      case 'groceries':
        return grocery;
      case 'transport':
      case 'travel':
        return transport;
      case 'household':
      case 'utilities':
        return house;
      default:
        return accent;
    }
  }
}

/// Typography helpers. Cormorant Garamond for display, Hanken Grotesk for UI.
///
/// Use [display] for the butler's voice — big headings, numerals, the "C"
/// monogram. Use the theme's default (`textTheme.bodyMedium` etc., all Hanken
/// Grotesk) for everything else.
class MrCarsonType {
  const MrCarsonType._();

  /// Cormorant Garamond — high-contrast serif for display / numerals.
  /// Pass [italic] true for the butler's asides ("At your service.").
  static TextStyle display({
    required double size,
    FontWeight weight = FontWeight.w600,
    Color color = MrCarsonColors.ink,
    bool italic = false,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.cormorantGaramond(
      fontSize: size,
      fontWeight: weight,
      color: color,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// Hanken Grotesk — clean sans for UI / body.
  static TextStyle ui({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color color = MrCarsonColors.ink,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.hankenGrotesk(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}

/// Builds the app-wide [ThemeData]. Hanken Grotesk is the default text family;
/// reach for [MrCarsonType.display] where the design uses Cormorant Garamond.
ThemeData buildMrCarsonTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: MrCarsonColors.bg,
    canvasColor: MrCarsonColors.bg,
    colorScheme: base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: MrCarsonColors.accent,
      onPrimary: MrCarsonColors.accentInk,
      surface: MrCarsonColors.surface,
      onSurface: MrCarsonColors.ink,
      error: MrCarsonColors.warn,
    ),
    textTheme: GoogleFonts.hankenGroteskTextTheme(base.textTheme).apply(
      bodyColor: MrCarsonColors.ink,
      displayColor: MrCarsonColors.ink,
    ),
    splashColor: MrCarsonColors.accentSoft,
    highlightColor: MrCarsonColors.accentSoft,
  );
}

/// Common radii used across the design (px → logical).
class MrCarsonRadii {
  const MrCarsonRadii._();
  static const card = 20.0; // summary / large cards
  static const tile = 16.0; // list tiles, fields, primary buttons
  static const chip = 13.0; // suggestion / category chips
  static const control = 11.0; // small square icon buttons
  static const sheet = 26.0; // bottom action sheet
  static const nav = 24.0; // floating bottom nav pill
}
