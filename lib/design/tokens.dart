import 'package:flutter/material.dart';

/// AppDesignTokens — ORYZO design system. Single source of truth for color,
/// type, spacing, radii. All screens and widgets must import from here.
class AppDesignTokens {
  AppDesignTokens._();

  // ─── Color (ORYZO · Noir Gold) ──────────────────────────────────────────
  /// Noir Walnut — Background canvas / void. Warm near-black that keeps cream
  /// and gold legible; the anchor of the noir-gold theme.
  static const Color backgroundCanvas = Color(0xFF100904);

  /// Bronze Bark — Elevated surfaces / cards. Warmed from brown toward gold so
  /// surfaces carry the palette's warmth while text keeps high contrast.
  static const Color surfaceElevated = Color(0xFF6B4A1E);

  /// Warm Cream — Text, icons, outlines.
  static const Color textCream = Color(0xFFFFEDD7);

  /// Bronze Hairline — Dividers, subtle borders.
  static const Color borderCork = Color(0xFF7A5A2F);

  /// Brushed Gold — Muted / secondary elements.
  static const Color muted = Color(0xFF8A6D44);

  /// Ember — Errors, destructive & warning states ONLY. Never a brand accent.
  static const Color accentEmber = Color(0xFFDC5000);

  // Legacy aliases kept for any stray references; do NOT introduce new ones.
  static const Color bg = backgroundCanvas;
  static const Color bgElevated = surfaceElevated;
  static const Color card = surfaceElevated;
  static const Color cardHover = surfaceElevated;
  static const Color cardPressed = surfaceElevated;
  static const Color surface = surfaceElevated;
  static const Color border = borderCork;
  static const Color borderStrong = borderCork;

  static const Color textPrimary = textCream;
  static const Color textSecondary = textCream;
  static const Color textTertiary = muted;
  static const Color textQuaternary = muted;
  static const Color textInverse = Color(0xFF000000); // espresso-black on ember/destructive fills

  /// Signature gold — selected states, ratings, badges, glows & primary CTAs.
  /// Refined down from the original `#FFB800` (~8% darker, hue held at 46°)
  /// so the accent reads as burnished brass instead of hot amber against the
  /// noir canvas. Espresso text keeps >9:1 contrast on this fill.
  static const Color gold = Color(0xFFF0AD00);
  static const Color goldSoft = Color(0x33F0AD00); // gold at ~20% alpha

  /// Muted gold — warmer, less-saturated variant for screens that suffer
  /// from the full-intensity gold (e.g. detail and profile screens, where
  /// even the refined accent can read as loud against the near-black
  /// background for many users). Use via the per-screen
  /// `_gold` constant rather than swapping `gold` globally so app-wide
  /// CTAs (onboarding, paywall, rating stars) keep their existing hue.
  static const Color goldMuted = Color(0xFFC69215);
  static const Color goldMutedSoft = Color(0x33C69215); // muted gold at ~20% alpha

  /// Espresso — text sitting on gold fills (primary CTAs, selected pills).
  /// ~10:1 contrast against `gold`; warmer than pure black.
  static const Color textOnGold = Color(0xFF241706);

  // ─── Glass Morphism ─────────────────────────────────────────────────────
  /// Translucent surface system. Every glass surface must pull its fill,
  /// border, blur, and shadow from here — no ad-hoc `Colors.white.withAlpha`
  /// or hardcoded blur sigmas in feature code.
  ///
  /// Fills are warm noir (same hue family as [backgroundCanvas]) so frosted
  /// layers sit *in* the palette instead of graying it out.

  /// 60% warm noir — chrome that floats over scrolling content
  /// (nav bar, player control bars, search dock).
  static const Color glassFillBar = Color(0x99140C04);

  /// 45% warm noir — sheets, dialogs, expanded panels.
  static const Color glassFillSheet = Color(0x73190F04);

  /// 25% warm noir — chips, pills, hover layers, subtle inline surfaces.
  static const Color glassFillSubtle = Color(0x40190F04);

  /// 8% Warm Cream — inner highlight edge on glass surfaces.
  static const Color glassHighlight = Color(0x14FFEDD7);

  /// 25% gold — default glass hairline border (ties glass to the accent).
  static const Color glassBorder = Color(0x40F0AD00);

  /// 40% gold — emphasized glass border (focused / active surfaces).
  static const Color glassBorderStrong = Color(0x66F0AD00);

  /// Blur sigma — floating chrome over scrolling content.
  static const double glassBlurBar = 22;

  /// Blur sigma — sheets, dialogs, expanded panels.
  static const double glassBlurSheet = 18;

  /// Blur sigma — cards, posters, inline media surfaces.
  static const double glassBlurCard = 12;

  /// Blur sigma — chips, pills, small overlays.
  static const double glassBlurChip = 8;

  /// Depth shadow reserved for floating glass chrome only (nav bar, dock).
  /// Glass needs a drop shadow to read as lifted; flat ORYZO surfaces keep
  /// [elevationNone].
  static const List<BoxShadow> glassShadow = [
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 28,
      offset: Offset(0, 10),
    ),
  ];

  static const Color error = accentEmber;
  static const Color errorSoft = Color(0x33DC5000);
  static const Color success = textCream;
  static const Color warning = accentEmber;

  // ─── Typography (ORYZO) ─────────────────────────────────────────────────
  /// Base font family — RobotoMono (Regular / Medium / Bold registered in
  /// pubspec.yaml). All ORYZO type styles use this.
  static const String fontFamily = 'RobotoMono';
  static const String fontFamilyFallback = 'monospace';

  /// System Voice 1 — Labels, Nav, Headings, Buttons.
  /// ALL CAPS, w500, tight line-height, Warm Cream, no letter spacing.
  static TextStyle systemVoice1({
    double fontSize = 14,
    double height = 1.0,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      height: height,
      letterSpacing: 0,
      color: textCream,
    );
  }

  /// System Voice 2 — Body copy / descriptions ONLY.
  /// Mixed case, w400, size 29 (or relative scale), height 1.26, Warm Cream.
  static TextStyle systemVoice2({
    double fontSize = 29,
    double height = 1.26,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      height: height,
      letterSpacing: 0,
      color: textCream,
    );
  }

  /// Micro-legal — Disclaimers.
  /// ALL CAPS, size 8, w500, Arial/System UI fallback.
  static const TextStyle microLegal = TextStyle(
    fontFamily: 'Arial',
    fontSize: 8,
    fontWeight: FontWeight.w500,
    height: 1.0,
    letterSpacing: 0,
    color: textCream,
  );

  /// Convenience pre-baked styles matching the ORYZO scale.
  static const TextStyle navLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 0.9,
    letterSpacing: 0,
    color: textCream,
  );

  static const TextStyle heading = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 0.9,
    letterSpacing: 0,
    color: textCream,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 29,
    fontWeight: FontWeight.w400,
    height: 1.26,
    letterSpacing: 0,
    color: textCream,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.26,
    letterSpacing: 0,
    color: textCream,
  );

  // ─── Legacy style factories (kept so existing widgets still compile).
  /// These exist only for backward compatibility with current widget code.
  /// Prefer the ORYZO names (navLabel / heading / body / caption) going forward.

  static TextStyle displayLarge({
    double fontSize = 34,
    double height = 1.05,
    FontWeight weight = FontWeight.w800,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: weight,
      height: height,
      letterSpacing: 0,
      color: textCream,
    );
  }

  static TextStyle displayMedium({
    double fontSize = 28,
    double height = 1.1,
  }) {
    return displayLarge(
      fontSize: fontSize,
      height: height,
      weight: FontWeight.w700,
    );
  }

  static TextStyle displaySmall({
    double fontSize = 22,
    double height = 1.15,
  }) {
    return displayLarge(
      fontSize: fontSize,
      height: height,
      weight: FontWeight.w700,
    );
  }

  static TextStyle headlineLarge({
    double fontSize = 20,
    double height = 1.2,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      height: height,
      letterSpacing: 0,
      color: textCream,
    );
  }

  static TextStyle headlineMedium({
    double fontSize = 18,
    double height = 1.25,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: height,
      letterSpacing: 0,
      color: textCream,
    );
  }

  static TextStyle headlineSmall({
    double fontSize = 16,
    double height = 1.3,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: height,
      letterSpacing: 0,
      color: textCream,
    );
  }

  static TextStyle titleLarge({
    double fontSize = 15,
    double height = 1.3,
    Color? color,
    FontWeight? fontWeight,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.w600,
      height: height,
      letterSpacing: 0,
      color: color ?? textCream,
    );
  }

  static TextStyle titleMedium({
    double fontSize = 14,
    double height = 1.35,
    Color? color,
    FontWeight? fontWeight,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.w500,
      height: height,
      letterSpacing: 0,
      color: color ?? textCream,
    );
  }

  static TextStyle titleSmall({
    double fontSize = 13,
    double height = 1.4,
    Color? color,
    FontWeight? fontWeight,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.w500,
      height: height,
      letterSpacing: 0,
      color: color ?? textTertiary,
    );
  }

  static TextStyle bodyLarge({
    double fontSize = 15,
    double height = 1.45,
    Color? color,
    FontWeight? fontWeight,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.w400,
      height: height,
      letterSpacing: 0,
      color: color ?? textCream,
    );
  }

  static TextStyle bodyMedium({
    double fontSize = 13,
    double height = 1.5,
    Color? color,
    FontWeight? fontWeight,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.w400,
      height: height,
      letterSpacing: 0,
      color: color ?? textTertiary,
    );
  }

  static TextStyle bodySmall({
    double fontSize = 11.5,
    double height = 1.5,
    Color? color,
    FontWeight? fontWeight,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.w400,
      height: height,
      letterSpacing: 0,
      color: color ?? textTertiary,
    );
  }

  static TextStyle labelLarge({
    double fontSize = 13,
    double height = 1.2,
    Color? color,
    FontWeight? fontWeight,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.w600,
      height: height,
      letterSpacing: 0,
      color: color ?? textCream,
    );
  }

  static TextStyle labelMedium({
    double fontSize = 12,
    double height = 1.2,
    Color? color,
    FontWeight? fontWeight,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.w500,
      height: height,
      letterSpacing: 0,
      color: color ?? textCream,
    );
  }

  static TextStyle labelSmall({
    double fontSize = 11,
    double height = 1.2,
    Color? color,
    FontWeight? fontWeight,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.w500,
      height: height,
      letterSpacing: 0,
      color: color ?? textTertiary,
    );
  }

  // ─── Spacing ────────────────────────────────────────────────────────────
  /// 4px base unit. All padding/margin/gap values are multiples of 4.
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space7 = 28;
  static const double space8 = 32;
  static const double space10 = 40;
  static const double space12 = 48;
  static const double space16 = 64;
  static const double space24 = 96;

  // ─── Border Radius ──────────────────────────────────────────────────────
  /// Standard cards/containers.
  static const BorderRadius radiusXs = BorderRadius.all(Radius.circular(4));
  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(8));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(12));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(16));
  static const BorderRadius radiusXl = BorderRadius.all(Radius.circular(22));
  static const BorderRadius radius2xl = BorderRadius.all(Radius.circular(28));
  static const BorderRadius radius3xl = BorderRadius.all(Radius.circular(36));
  static const BorderRadius radiusFull = BorderRadius.all(Radius.circular(9999));

  /// Inputs & inline links — zero radius, bottom border only.
  static const BorderRadius radiusZero = BorderRadius.zero;

  /// Primary CTA — pill shape.
  static const BorderRadius radiusPill = BorderRadius.all(Radius.circular(36));

  /// Secondary/ghost buttons.
  static const BorderRadius radiusGhost = BorderRadius.all(Radius.circular(22.5));

  // ─── Elevation / Shadow ─────────────────────────────────────────────────
  /// ORYZO rejects shadows entirely. Depth comes ONLY from background color contrast.
  static const List<BoxShadow> elevationNone = [];

  /// Legacy elevation presets kept so existing widget code still compiles.
  /// These are no-ops under ORYZO; any new UI must use elevationNone.
  static const List<BoxShadow> elevation1 = [];
  static const List<BoxShadow> elevation2 = [];
  static const List<BoxShadow> elevation3 = [];
  static const List<BoxShadow> elevationGold = [];

  // ─── Content Width ──────────────────────────────────────────────────────
  /// Full-bleed layouts. No max-width constraints.
  static const double maxContentWidthMobile = double.infinity;
  static const double maxContentWidthTablet = double.infinity;
  static const double maxContentWidthDesktop = double.infinity;
  static const double maxContentWidthWide = double.infinity;

  // ─── Breakpoints ────────────────────────────────────────────────────────
  static const double bpMobile = 600;
  static const double bpTablet = 900;
  static const double bpDesktop = 1200;
  static const double bpWide = 1600;

  /// Returns the content width constraint for the current viewport.
  static double contentWidth(BuildContext context) => double.infinity;

  /// Returns horizontal page padding for the current viewport.
  /// ORYZO wants full-bleed; internal card padding is handled by components.
  static EdgeInsets pagePadding(BuildContext context) => EdgeInsets.zero;

  /// Grid column counts per breakpoint.
  static int gridColumns(BuildContext context,
      {int mobile = 2, int tablet = 4, int desktop = 6, int wide = 8}) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= bpWide) return wide;
    if (w >= bpDesktop) return desktop;
    if (w >= bpTablet) return tablet;
    return mobile;
  }
}
