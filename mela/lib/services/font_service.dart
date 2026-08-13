import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Describes one selectable font in Settings.
class AppFont {
  final String id; // stable key, saved to prefs
  final String label; // shown to the user
  final String family; // must match pubspec.yaml `family:` name
  final bool isDisplay; // true = good for big titles, false = body text

  const AppFont({
    required this.id,
    required this.label,
    required this.family,
    this.isDisplay = false,
  });
}

/// Central place that owns "which font is the app using right now".
///
/// Usage:
///   1. Wrap MaterialApp with `AnimatedBuilder(animation: FontService.instance, ...)`
///      or just read `FontService.instance.bodyFamily` when building a Theme.
///   2. Settings screen calls `FontService.instance.setFont(id)`.
///   3. Add more fonts by (a) dropping the file in assets/fonts,
///      (b) declaring it in pubspec.yaml (see pubspec_fonts_snippet.yaml),
///      (c) adding one line to `fonts` below. That's it — the Settings UI
///      picks it up automatically.
class FontService extends ChangeNotifier {
  FontService._();
  static final FontService instance = FontService._();

  static const _prefsKey = 'app_font_id';

  /// Every font available in the Settings screen.
  /// Add new fonts here after registering them in pubspec.yaml.
  static const List<AppFont> fonts = [
    AppFont(id: 'system', label: 'System Default', family: '', isDisplay: false),
    AppFont(
      id: 'astone_nouvea',
      label: 'Astone Nouvea',
      family: 'AstoneNouvea',
      isDisplay: true,
    ),
    // Example of how the next uploaded font gets added:
    // AppFont(id: 'my_font', label: 'My Font', family: 'MyFont', isDisplay: false),
  ];

  AppFont _current = fonts.first;
  AppFont get current => _current;

  /// Family string ready to hand to a TextStyle / ThemeData.
  /// Empty string means "use Flutter's platform default".
  String? get bodyFamily => _current.family.isEmpty ? null : _current.family;

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_prefsKey);
    if (savedId != null) {
      _current = fonts.firstWhere(
        (f) => f.id == savedId,
        orElse: () => fonts.first,
      );
      notifyListeners();
    }
  }

  Future<void> setFont(String id) async {
    final match = fonts.firstWhere(
      (f) => f.id == id,
      orElse: () => fonts.first,
    );
    if (match.id == _current.id) return;
    _current = match;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, id);
  }

  /// Convenience for building a themed TextStyle that respects the
  /// current font choice while keeping a caller-provided fallback.
  TextStyle style({
    required Color color,
    required double fontSize,
    FontWeight fontWeight = FontWeight.normal,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      fontFamily: bodyFamily,
    );
  }

  // ── Two-font system (matches the reference "F1 profile" screenshots) ──
  //
  // DISPLAY font = bold rounded sans / your custom font (titles, names,
  //   card headings) — this is `current` / `bodyFamily` above, switchable
  //   from Settings.
  // LABEL font = monospace (stats, metadata, uppercase section headers,
  //   timestamps, usernames-as-handles) — fixed to JetBrains Mono via
  //   google_fonts so it doesn't need an uploaded file. Swap the call
  //   below if you'd rather use Space Mono / IBM Plex Mono / etc.

  /// Bold display text — titles, headings, card names.
  /// Uses whatever font is selected in Settings (defaults to your
  /// uploaded Astone Nouvea), falling back to system bold.
  TextStyle display({
    required Color color,
    required double fontSize,
    FontWeight fontWeight = FontWeight.w800,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      fontFamily: bodyFamily ?? 'AstoneNouvea',
    );
  }

  /// Monospace label text — stat numbers, section headers, timestamps,
  /// handles/usernames, metadata rows. Mirrors the reference screenshots'
  /// "WATCHED / THIS YEAR / @f1user4331" styling.
  TextStyle label({
    required Color color,
    required double fontSize,
    FontWeight fontWeight = FontWeight.w500,
    double letterSpacing = 0.6,
    double? height,
    bool uppercase = false,
  }) {
    return GoogleFonts.jetBrainsMono(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}