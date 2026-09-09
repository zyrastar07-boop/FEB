import 'package:flutter/material.dart';

/// Screen size classification used across the app.
enum ScreenType { mobile, tablet, desktop, tv }

/// Central adaptive helpers for responsive layouts and TV detection.
class Adaptive {
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1024;
  static const double desktopBreakpoint = 1440;

  /// Returns the current screen type. Prefer [NavigationMode.directional]
  /// for Android TV / remote devices.
  static ScreenType of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final navMode = MediaQuery.navigationModeOf(context);
    final isDirectional = navMode == NavigationMode.directional;

    if (isDirectional || size.width >= desktopBreakpoint) {
      return ScreenType.tv;
    }
    if (size.width >= tabletBreakpoint) return ScreenType.desktop;
    if (size.width >= mobileBreakpoint) return ScreenType.tablet;
    return ScreenType.mobile;
  }

  /// Dynamic grid column count based on breakpoints.
  static int gridColumns(
    BuildContext context, {
    int mobile = 2,
    int tablet = 4,
    int desktop = 6,
    int tv = 6,
  }) {
    switch (of(context)) {
      case ScreenType.mobile:
        return mobile;
      case ScreenType.tablet:
        return tablet;
      case ScreenType.desktop:
      case ScreenType.tv:
        return desktop;
    }
  }

  /// Max content width for very large screens (desktop / TV).
  static double maxContentWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w > 1600) return 1400;
    if (w > 1200) return 1100;
    return w;
  }

  /// Consistent horizontal page padding.
  static EdgeInsets pagePadding(BuildContext context) {
    switch (of(context)) {
      case ScreenType.mobile:
        return const EdgeInsets.symmetric(horizontal: 16);
      case ScreenType.tablet:
        return const EdgeInsets.symmetric(horizontal: 24);
      case ScreenType.desktop:
      case ScreenType.tv:
        return const EdgeInsets.symmetric(horizontal: 32);
    }
  }

  static bool isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  /// True when running on Android TV / directional navigation.
  static bool isTv(BuildContext context) {
    final navMode = MediaQuery.navigationModeOf(context);
    return navMode == NavigationMode.directional || of(context) == ScreenType.tv;
  }

  /// Helper for hero / list card widths.
  static double cardWidth(BuildContext context, {bool large = false}) {
    final type = of(context);
    if (large) {
      switch (type) {
        case ScreenType.mobile:
          return 160;
        case ScreenType.tablet:
          return 180;
        case ScreenType.desktop:
        case ScreenType.tv:
          return 200;
      }
    }
    switch (type) {
      case ScreenType.mobile:
        return 140;
      case ScreenType.tablet:
        return 155;
      case ScreenType.desktop:
      case ScreenType.tv:
        return 170;
    }
  }
}