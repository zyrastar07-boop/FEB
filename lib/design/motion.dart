import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'refresh_rate.dart';

/// AppMotion — durations, curves, spring presets, reduced-motion gate.
/// All animated widgets must use these constants. No inline literals.
///
/// Durations are tuned for a 60 Hz baseline feel. On high-refresh devices
/// (90/120 Hz) they are automatically scaled down via [scaled] so motion
/// feels equally snappy instead of sluggish. Do not inline `Duration`
/// literals in build methods — route everything through [scaled], [fast],
/// [medium], etc.
class AppMotion {
  AppMotion._();

  // ─── Duration (60 Hz baseline) ──────────────────────────────────────────
  /// Instant — for reduced-motion mode.
  static const Duration instant = Duration.zero;

  /// Micro — button press, chip tap, ripple.
  static const Duration micro = Duration(milliseconds: 100);

  /// Fast — tooltip, small popover, snackbar.
  static const Duration fast = Duration(milliseconds: 150);

  /// Standard — card press, list item, drawer, modal.
  static const Duration standard = Duration(milliseconds: 200);

  /// Medium — page transition, hero, sheet.
  static const Duration medium = Duration(milliseconds: 300);

  /// Slow — complex enter/exit, onboarding.
  static const Duration slow = Duration(milliseconds: 450);

  // ─── Curves ─────────────────────────────────────────────────────────────
  /// Apple-style strong ease-out — enters, exits, feedback.
  static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);

  /// Strong ease-in-out — on-screen movement, morphing.
  static const Curve easeInOut = Cubic(0.77, 0, 0.175, 1);

  /// iOS-like drawer/sheet curve.
  static const Curve easeDrawer = Cubic(0.32, 0.72, 0, 1);

  /// Standard ease — color, hover, subtle.
  static const Curve ease = Curves.ease;

  /// Press-release — snappy release with a whisper of overshoot so buttons
  /// feel springy under the finger without cartoon bounce.
  static const Curve easePressRelease = Cubic(0.2, 1.4, 0.32, 1);

  /// Linear — constant motion (marquee, progress).
  static const Curve linear = Curves.linear;

  // ─── Spring Presets ─────────────────────────────────────────────────────
  /// Critically damped — no overshoot. Default for UI.
  static const SpringDescription springDefault = SpringDescription(
    mass: 1,
    stiffness: 170,
    damping: 26,
  );

  /// Slightly underdamped — for momentum-driven gestures (drag, flick).
  static const SpringDescription springBouncy = SpringDescription(
    mass: 1,
    stiffness: 170,
    damping: 22,
  );

  /// Stiff — for small, snappy elements (chips, badges).
  static const SpringDescription springStiff = SpringDescription(
    mass: 0.8,
    stiffness: 260,
    damping: 24,
  );

  /// Gentle — for large surfaces (sheets, modals).
  static const SpringDescription springGentle = SpringDescription(
    mass: 1.2,
    stiffness: 120,
    damping: 28,
  );

  // ─── Reduced Motion ─────────────────────────────────────────────────────
  /// Returns true when the user has requested reduced motion.
  /// Use to collapse spring/duration animations to instant.
  static bool shouldReduceMotion(BuildContext context) {
    return MediaQuery.of(context).disableAnimations;
  }

  /// Best-effort reduced-transparency gate. Flutter does not expose the OS
  /// "reduce transparency" preference yet, so treat reduce-motion
  /// (`disableAnimations` is how assistive tech maps it) as wanting fewer
  /// translucency effects and render glass surfaces near-opaque.
  static bool shouldReduceTransparency(BuildContext context) {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  /// Blur a glass surface should use — 0 when the user prefers less
  /// transparency (keep the frosted layer, but legible & cheap to paint).
  static double glassBlur(BuildContext context, double defaultBlur) {
    return shouldReduceTransparency(context) ? 0 : defaultBlur;
  }

  /// Returns [duration] or [Duration.zero] based on reduced-motion setting.
  static Duration durationOrInstant(BuildContext context, Duration duration) {
    return shouldReduceMotion(context) ? instant : duration;
  }

  /// Returns [curve] or [Curves.linear] based on reduced-motion setting.
  static Curve curveOrLinear(BuildContext context, Curve curve) {
    return shouldReduceMotion(context) ? Curves.linear : curve;
  }

  /// Returns a spring simulation or an instant tween based on reduced-motion.
  static Simulation springOrInstant(
    BuildContext context, {
    required SpringDescription spring,
    required double from,
    required double to,
    double velocity = 0,
  }) {
    if (shouldReduceMotion(context)) {
      return _InstantSimulation(from: from, to: to);
    }
    return SpringSimulation(spring, from, to, velocity);
  }

  // ─── Refresh-rate-aware duration helpers ────────────────────────────────
  /// Scale [duration] by the device's current refresh rate so the feel stays
  /// consistent across 60 / 90 / 120 Hz panels.
  ///
  /// Usage in a State class:
  /// ```dart
  /// late final AnimationController _ctrl;
  /// @override
  /// void initState() {
  ///   super.initState();
  ///   _ctrl = AnimationController(
  ///     vsync: this,
  ///     duration: AppMotion.scaled(context, AppMotion.medium),
  ///   );
  /// }
  /// ```
  static Duration scaled(BuildContext? context, Duration duration) {
    return RefreshRate.scaleDuration(context, duration);
  }

  /// Frame-count-friendly micro-duration for things that should feel instant
  /// on any device — chip toggles, button ripples, focus rings.
  ///
  /// On 60 Hz this is 80 ms; on 120 Hz it drops to ~56 ms so the visual
  /// feedback never lags behind the finger.
  static Duration microScaled(BuildContext? context) {
    return scaled(context, micro);
  }

  /// Standard-duration helper — card presses, list item taps, drawer slides,
  /// modal enters.
  static Duration standardScaled(BuildContext context) {
    return scaled(context, standard);
  }

  /// Medium-duration helper — page transitions, hero flights, bottom sheets.
  static Duration mediumScaled(BuildContext context) {
    return scaled(context, medium);
  }
}

/// Private instant simulation for reduced-motion mode.
class _InstantSimulation extends Simulation {
  _InstantSimulation({required this.from, required this.to});

  final double from;
  final double to;

  @override
  double x(double time) => to;

  @override
  double dx(double time) => 0;

  @override
  bool isDone(double time) => true;
}

/// Convenience extension for quick motion access in build methods.
extension AppMotionExt on BuildContext {
  bool get reduceMotion => AppMotion.shouldReduceMotion(this);
}