import 'package:flutter/material.dart';

/// App-wide responsive metrics. Thin, pure-Dart utility — no widgets.
///
/// Centralises MediaQuery reads so the player, detail screen, and sheets
/// use the same numbers for safe areas, breakpoints, and player-specific
/// sizing. Returns a value object (not a BuildContext extension) so it
/// can be passed down cheaply and tested in isolation.
///
/// Usage:
/// ```dart
/// final m = ScreenMetrics.of(context);
/// final barH = m.playerControlBarHeight;
/// final padH = m.horizontalPagePadding;
/// ```
@immutable
class ScreenMetrics {
  const ScreenMetrics({
    required this.size,
    required this.shortestSide,
    required this.longestSide,
    required this.aspectRatio,
    required this.isLandscape,
    required this.isTablet,
    required this.padding,
    required this.viewInsets,
    required this.textScaler,
  });

  final Size size;
  final double shortestSide;
  final double longestSide;
  final double aspectRatio;

  final bool isLandscape;

  /// True when the shortest side ≥ 600 (typical tablet cutoff). Used to
  /// grow touch targets, icon sizes, and content widths without a heavier
  /// breakpoint framework.
  final bool isTablet;

  final EdgeInsets padding;
  final EdgeInsets viewInsets;

  /// Effective text scaler — kept here so future helpers can scale player
  /// chrome relative to user OS-level font size.
  final TextScaler textScaler;

  /// Capture metrics from a [BuildContext]. Cheap; safe to call per build.
  factory ScreenMetrics.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    return ScreenMetrics(
      size: size,
      shortestSide: size.shortestSide,
      longestSide: size.longestSide,
      aspectRatio:
          size.height == 0 ? 1.0 : size.width / size.height,
      isLandscape: size.width > size.height,
      isTablet: size.shortestSide >= 600,
      padding: mq.padding,
      viewInsets: mq.viewInsets,
      textScaler: mq.textScaler,
    );
  }

  // ── Player ────────────────────────────────────────────────────────────

  /// Height of the player top / bottom control bars. Landscape phones get
  /// smaller bars so the video gets the full safe area; portrait keeps
  /// the reference's taller bar for thumb-friendly tap targets.
  double get playerControlBarHeight => isLandscape ? 44 : 56;

  /// Side padding inside the player chrome. Keeps buttons off the very
  /// edge on notched devices.
  double get playerChromePadding => isTablet ? 18 : 12;

  /// Center-play button size — scales up on tablets so the hit area
  /// stays comfortable.
  double get playerCenterButtonSize => isTablet ? 72 : 60;

  /// Center-play icon size.
  double get playerCenterButtonIconSize => isTablet ? 36 : 30;

  /// Side seek button (double-tap skip) size.
  double get playerSeekButtonSize => isTablet ? 64 : 52;

  /// Icon size for top-bar buttons.
  double get playerTopBarIconSize => isTablet ? 22 : 20;

  // ── Sheets & content ──────────────────────────────────────────────────

  /// Horizontal page padding that matches the player chrome and respects
  /// notches / home indicators.
  EdgeInsets get horizontalPagePadding => EdgeInsets.symmetric(
        horizontal: isTablet ? 20 : 14,
      );

  /// Maximum content width for centered layouts (sheets, detail sections).
  /// Caps at 560 so wide tablets don't get unreadably long lines.
  double get maxContentWidth => isTablet ? 560 : size.width;

  /// Recommended minimum tap target (Material spec is 48; we expose it
  /// so future helpers stay aligned).
  static const double minTapTarget = 48;

  /// Returns a scaled icon size: base on phones, +2 on tablets.
  double scaledIcon(double base) =>
      isTablet ? base + 2 : base;
}
