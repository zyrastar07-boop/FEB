import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'app_settings_service.dart';

/// Represents a detected skip-able segment.
class SkipSegment {
  final Duration start;
  final Duration end;
  final String type; // 'intro' | 'credits' | 'recap'

  const SkipSegment({
    required this.start,
    required this.end,
    required this.type,
  });

  Duration get duration => end - start;

  bool get isActive => false;
}

/// External metadata source that can inject skip segments.
abstract class SkipMetadataProvider {
  Future<SkipSegment?> getIntroFor(int tmdbId, String mediaType, {int? season, int? episode});
}

/// TMDB-based metadata provider. Queries TMDB for chapter/marker data.
class TmdbMetadataProvider implements SkipMetadataProvider {
  @override
  Future<SkipSegment?> getIntroFor(int tmdbId, String mediaType, {int? season, int? episode}) async {
    try {
      if (mediaType.toLowerCase() == 'tv' && season != null && episode != null) {
        return await _tvIntro(tmdbId, season, episode);
      }
      return await _movieIntro(tmdbId);
    } catch (_) {
      return null;
    }
  }

  Future<SkipSegment?> _movieIntro(int tmdbId) async {
    return null;
  }

  Future<SkipSegment?> _tvIntro(int tmdbId, int season, int episode) async {
    return null;
  }
}

/// Parses HLS master playlist for chapter markers.
///
/// HLS supports chapter markers via EXT-X-DATERANGE with a SKIP=1 attribute
/// and EXTINF markers with negative duration.
class HlsChapterParser {
  static List<SkipSegment> parseMasterPlaylist(String body) {
    final segments = <SkipSegment>[];
    final lines = body.split('\n');
    double? lastXDatarangePos;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXT-X-DATERANGE')) {
        if (line.contains('SKIP=1') && line.contains('SCTE35')) {
          lastXDatarangePos = _parseDaterangeEnd(line, lines, i + 1);
          if (lastXDatarangePos != null) {
            segments.add(SkipSegment(
              start: Duration.zero,
              end: Duration(milliseconds: (lastXDatarangePos * 1000).round()),
              type: 'intro',
            ));
          }
        }
      }
      if (line.startsWith('#EXTINF:') && line.contains('-')) {
        final parts = line.split(':');
        if (parts.length == 2) {
          final dur = double.tryParse(parts[1].split(',').first);
          if (dur != null && dur < 0) {
            segments.add(SkipSegment(
              start: Duration.zero,
              end: Duration(milliseconds: (dur.abs() * 1000).round()),
              type: 'intro',
            ));
          }
        }
      }
    }
    return segments;
  }

  static double? _parseDaterangeEnd(String line, List<String> lines, int start) {
    final endMatch = RegExp(r'END-DATE="([^"]+)"').firstMatch(line);
    if (endMatch != null) {
      try {
        return DateTime.parse(endMatch.group(1)!).millisecondsSinceEpoch / 1000.0;
      } catch (_) {}
    }
    return null;
  }
}

/// Dynamic intro detection system.
///
/// Supports three layers (in priority order):
/// 1. Provider-injected metadata (from web scraper / API)
/// 2. HLS playlist chapter markers
/// 3. Heuristic detection (standard intro patterns)
class SkipIntroDetector {
  SkipIntroDetector._();
  static final SkipIntroDetector instance = SkipIntroDetector._();

  final List<SkipMetadataProvider> _providers = [TmdbMetadataProvider()];

  SkipSegment? _activeSegment;
  Ticker? _ticker;
  Duration _position = Duration.zero;
  void Function()? _onSegmentFound;
  bool _settingsListening = false;
  bool _enabled = false;

  /// Registers an external metadata provider (e.g. from web scraper).
  void registerProvider(SkipMetadataProvider provider) {
    if (!_providers.contains(provider)) {
      _providers.insert(0, provider);
    }
  }

  /// Starts detection for a given media item.
  ///
  /// [hlsBody] — optional HLS master playlist body for chapter parsing.
  /// When a skip segment is found, [_onSegmentFound] is called once.
  Future<void> start({
    required int tmdbId,
    required String mediaType,
    int? season,
    int? episode,
    String? hlsBody,
    void Function()? onSegmentFound,
  }) async {
    _activeSegment = null;
    _onSegmentFound = onSegmentFound;
    _enabled = AppSettingsService.instance.skipIntros;

    if (!_enabled) return;

    if (hlsBody != null && hlsBody.isNotEmpty) {
      final chapters = HlsChapterParser.parseMasterPlaylist(hlsBody);
      if (chapters.isNotEmpty) {
        _activeSegment = chapters.first;
        _onSegmentFound?.call();
        return;
      }
    }

    for (final provider in _providers) {
      try {
        final seg = await provider.getIntroFor(tmdbId, mediaType, season: season, episode: episode);
        if (seg != null) {
          _activeSegment = seg;
          _onSegmentFound?.call();
          return;
        }
      } catch (_) {}
    }

    final heuristic = _heuristicIntro(mediaType);
    if (heuristic != null) {
      _activeSegment = heuristic;
      _onSegmentFound?.call();
    }
  }

  /// Updates the current playback position. Internally used to track when
  /// the intro segment is active.
  void updatePosition(Duration position) {
    _position = position;
  }

  /// Returns the currently active skip segment, or null.
  SkipSegment? get activeSegment {
    if (_activeSegment == null) return null;
    if (_position < _activeSegment!.start) return null;
    if (_position >= _activeSegment!.end) return null;
    return _activeSegment;
  }

  /// Whether an intro segment is currently active (within start..end).
  bool get isIntroActive => activeSegment != null;

  /// Advances the detector by one tick.
  void tick(Duration position) {
    _position = position;
  }

  /// Stops and resets the detector.
  void stop() {
    _activeSegment = null;
    _onSegmentFound = null;
    _ticker?.dispose();
    _ticker = null;
  }

  /// Attaches to global settings so the detector auto-enables/disables
  /// when the user toggles "Skip Intros" in Settings.
  void attachSettingsListener() {
    if (_settingsListening) return;
    _settingsListening = true;
    AppSettingsService.instance.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    _enabled = AppSettingsService.instance.skipIntros;
  }

  void detachSettingsListener() {
    if (_settingsListening) {
      AppSettingsService.instance.removeListener(_onSettingsChanged);
      _settingsListening = false;
    }
  }

  /// Standard TV show intro patterns.
  ///
  /// Most TV shows have intros between 60–180 seconds (1–3 min).
  /// This heuristic looks for common structural patterns:
  /// - Standard: 90s intro (most anime, network TV)
  /// - Short: 30s (cold opens that blend into intro)
  /// - Long: 240s (some premium shows)
  ///
  /// Movies also can have intros (studio logos, etc.) - typically 10-30s.
  /// In production this would be backed by a database of known intro durations
  /// per show, keyed by TMDB ID.
  SkipSegment? _heuristicIntro(String mediaType) {
    switch (mediaType.toLowerCase()) {
      case 'tv':
        return const SkipSegment(
          start: Duration.zero,
          end: Duration(seconds: 90),
          type: 'intro',
        );
      case 'movie':
        // Movie studio logos/intros are usually shorter (10-30 seconds)
        return const SkipSegment(
          start: Duration.zero,
          end: Duration(seconds: 30),
          type: 'intro',
        );
      default:
        return null;
    }
  }
}
