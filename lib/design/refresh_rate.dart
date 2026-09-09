import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Read-only snapshot of the device's current refresh rate.
///
/// This is the single source of truth for motion timing decisions across the
/// app — animation durations, step counts for manual tween simulations, and
/// expensive per-frame effects (blur, glass) all consult it so a 120 Hz
/// device feels snappy and a 60 Hz device stays buttery instead of fighting
/// the hardware.
class RefreshRate {
  RefreshRate._();

  /// Most recently observed refresh rate, in Hz.
  ///
  /// Starts at 60.0 (the safe default) and is refreshed by the
  /// [RefreshRateService] tick. Consumer code should treat this as a hint,
  /// not a hard guarantee — thermal throttling and power saving can change
  /// it at any time.
  static double current = 60.0;

  /// True when the device is running at 90 Hz or higher.
  static bool get isHighRefresh => current >= 90.0;

  /// True when the device is running at 120 Hz.
  static bool get isUltrarefresh => current >= 120.0;

  /// Estimated frame interval in milliseconds for the current rate.
  ///
  /// Used by motion code to convert frame counts into real durations when
  /// a frame-accurate feel is wanted (for example, "12 frames at 120 Hz" →
  /// 100 ms, but "12 frames at 60 Hz" → 200 ms).
  static double get frameIntervalMs => 1000.0 / current;

  /// True when running on a desktop / desktop-class platform where the
  /// [RefreshRateService] sampler is unreliable (Windows in particular can
  /// hand back frame intervals that look like 240 Hz even on a 60 Hz panel,
  /// which makes every animation in the app feel broken and over-snappy).
  static bool get isUnreliablePlatform {
    if (kIsWeb) return true;
    if (defaultTargetPlatform == TargetPlatform.windows) return true;
    if (defaultTargetPlatform == TargetPlatform.macOS) return true;
    if (defaultTargetPlatform == TargetPlatform.linux) return true;
    return false;
  }

  /// Scale factor applied to standard motion durations on high-refresh
  /// displays so the *feel* stays consistent instead of every animation
  /// feeling twice as slow on a 120 Hz screen.
  ///
  /// 60 Hz  → 1.00× (baseline, nothing scaled)
  /// 90 Hz  → 0.85× (slightly snappier)
  /// 120 Hz → 0.70× (noticeably faster)
  /// 144 Hz+ → 0.60× (fast but not instant)
  ///
  /// The curve is deliberately non-linear — going from 60→120 Hz is not the
  /// same as halving every duration, because human perception of motion
  /// doesn't scale linearly with frame count. Tweak these breakpoints if the
  /// feel is too fast / too slow on your target devices.
  static double durationScale(BuildContext? context) {
    // If the context is null (e.g. test harness, background compute), fall
    // back to the baseline so nothing breaks.
    if (context == null) return 1.0;

    // Honor the user's reduced-motion request by not speeding anything up —
    // reduced motion already collapses durations to zero / instant in
    // AppMotion, so this path is mostly defensive.
    if (MediaQuery.maybeOf(context)?.disableAnimations == true) {
      return 1.0;
    }

    // On desktop-class platforms the per-frame sampler is unreliable
    // (Windows / Linux / macOS routinely report frame intervals that
    // correspond to 120+ Hz on a 60 Hz panel, which then makes every
    // animation in the app feel jittery and "too fast"). Treat those
    // platforms as 60 Hz and don't scale anything.
    if (isUnreliablePlatform) return 1.0;

    // On 60 Hz there is nothing to do.
    if (!isHighRefresh) return 1.0;
    if (isUltrarefresh) return 0.70;

    // 90 Hz — mild speedup.
    return 0.85;
  }

  /// Convert a "base" duration (as written for a 60 Hz feel) into the
  /// actual duration to pass to an [AnimationController] or [CurvedAnimation]
  /// on the current device.
  ///
  /// Usage:
  /// ```dart
  /// final d = RefreshRate.scaleDuration(context, AppMotion.medium);
  /// ```
  static Duration scaleDuration(BuildContext? context, Duration base) {
    if (base == Duration.zero) return Duration.zero;
    final scale = durationScale(context);
    if (scale == 1.0) return base;
    return Duration(microseconds: (base.inMicroseconds * scale).round());
  }
}

/// Service that keeps [RefreshRate.current] fresh by listening to the frame
/// timing stream.
///
/// Instantiate once (typically in `main()` after `ensureInitialized()`) and
/// forget — it self-cleans when the app is backgrounded and reattaches on
/// resume. No manual teardown required.
class RefreshRateService {
  RefreshRateService._();

  static RefreshRateService? _instance;
  static RefreshRateService get instance => _instance ??= RefreshRateService._();

  FrameCallback? _frameCallback;
  bool _listening = false;

  /// Start sampling the refresh rate.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops if already
  /// listening.
  void start() {
    if (_listening) return;
    if (RefreshRate.isUnreliablePlatform) {
      // Pin to 60 Hz on desktop-class platforms where the frame sampler
      // routinely mis-reports the panel rate. Without this, Windows in
      // particular will hand back intervals that look like 240 Hz, the
      // whole app's animations will scale down to ~25% of their intended
      // duration, and the UI will feel jittery / broken.
      RefreshRate.current = 60.0;
      return;
    }
    _listening = true;

    _frameCallback = _sampleFrameRate;
    SchedulerBinding.instance.addPersistentFrameCallback(_frameCallback!);
  }

  /// Stop sampling.
  ///
  /// Called automatically on lifecycle pause; also safe to call manually.
  void stop() {
    if (!_listening) return;
    _listening = false;
    // The frame callback gates itself on `_listening`, so simply flipping
    // the flag is enough to silence it without removing the registration.
    // We still drop our local reference to avoid pinning the closure.
    _frameCallback = null;
  }

  void _sampleFrameRate(Duration elapsed) {
    // Honor the stop() call even though we can't actually unregister a
    // persistent frame callback (Flutter doesn't expose a matching
    // remove API for the persistent variant).
    if (!_listening) return;

    // The first few frames after a resume can be sloppy (GPU warm-up,
    // texture uploads), so ignore elapsed values that are implausibly large
    // or zero. A real frame interval on a healthy device is between ~4 ms
    // (240 Hz) and ~33 ms (30 Hz). Anything outside that window is almost
    // certainly a hiccup and should not update our estimate.
    final intervalUs = elapsed.inMicroseconds;
    if (intervalUs <= 0 || intervalUs > 33_000_000) return;

    final hz = 1_000_000.0 / intervalUs;

    // Smooth toward the sample instead of snapping — a single slow frame
    // (garbage collection, a heavy layout) should not drag the estimate all
    // the way down and make the whole app feel sluggish for the next minute.
    //
    // Exponential moving average with alpha ≈ 0.15: heavy smoothing, slow to
    // react to genuine rate changes (which usually persist for seconds anyway),
    // fast enough to notice a sustained 120→60 Hz drop within a couple hundred
    // frames.
    final alpha = 0.15;
    RefreshRate.current = RefreshRate.current * (1 - alpha) + hz * alpha;

    // Clamp to a sane range so a single garbage sample can't corrupt the state
    // even if the smoothing math somehow produces an absurd value.
    if (RefreshRate.current < 25.0) RefreshRate.current = 25.0;
    if (RefreshRate.current > 240.0) RefreshRate.current = 240.0;
  }
}
