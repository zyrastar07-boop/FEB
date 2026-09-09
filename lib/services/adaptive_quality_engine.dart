import 'dart:collection';
import '../screens/custom_player_screen.dart';
import 'app_settings_service.dart';

/// Bandwidth sample collected during buffered playback.
class _BwSample {
  final int bytes;
  final Duration elapsed;
  final DateTime at;

  _BwSample({required this.bytes, required this.elapsed, required this.at});

  double get mbps => bytes <= 0 || elapsed.inMilliseconds == 0
      ? 0.0
      : (bytes * 8.0) / (elapsed.inMilliseconds * 1000);
}

/// Throughput-based adaptive bitrate engine.
///
/// Design:
/// - Always starts at 480p (360p is not supported by any provider)
/// - Actively measures network throughput during playback
/// - Seamlessly upgrades to 720p / 1080p when bandwidth confirms support
/// - Respects global DataSaver and quality caps from AppSettingsService
/// - Cross-communicates: any global setting change immediately overrides local state
class AdaptiveQualityEngine {
  AdaptiveQualityEngine._();
  static final AdaptiveQualityEngine instance = AdaptiveQualityEngine._();

  static const _historyWindow = 8;
  static const _upgradeBandwidth720Mbps = 3.5;
  static const _upgradeBandwidth1080Mbps = 7.0;

  final Queue<_BwSample> _samples = Queue();
  String _currentLabel = '480p';
  bool _listeningToSettings = false;
  void Function()? _onQualityChange;

  /// Currently selected quality label (e.g. "480p", "720p", "1080p", "Auto").
  String get currentLabel => _currentLabel;

  /// Whether throughput has been measured as sufficient for 720p upgrade.
  bool get canUpgrade720 => _estimatedMbps >= _upgradeBandwidth720Mbps;

  /// Whether throughput has been measured as sufficient for 1080p upgrade.
  bool get canUpgrade1080 => _estimatedMbps >= _upgradeBandwidth1080Mbps;

  /// Latest estimated bandwidth in Mbps.
  double get _estimatedMbps {
    if (_samples.isEmpty) return 0.0;
    final recent = _samples.toList();
    if (recent.length == 1) return recent.first.mbps;
    final weights = List<double>.generate(recent.length, (i) => i + 1.0);
    final totalWeight = weights.reduce((a, b) => a + b);
    return recent
        .asMap()
        .entries
        .map((e) => e.value.mbps * (weights[e.key] / totalWeight))
        .reduce((a, b) => a + b);
  }

  /// Records a throughput sample.
  ///
  /// [bytes] — total bytes received during [elapsed].
  /// Called by the player whenever a buffering segment completes.
  void recordSample({required int bytes, required Duration elapsed}) {
    if (bytes <= 0 || elapsed.inMilliseconds < 200) return;
    _samples.add(_BwSample(
      bytes: bytes,
      elapsed: elapsed,
      at: DateTime.now(),
    ));
    while (_samples.length > _historyWindow) {
      _samples.removeFirst();
    }
  }

  /// Returns the best quality label given current throughput estimates
  /// and the list of available HLS variants.
  ///
  /// [variants] — available HLS variants from the scraped stream.
  /// [forcedLabel] — if non-empty, overrides everything (e.g. user manually picked).
  String resolveQuality(List<HlsVariant> variants, {String? forcedLabel}) {
    final settings = AppSettingsService.instance;

    if (forcedLabel != null && forcedLabel.isNotEmpty && forcedLabel.toLowerCase() != 'auto') {
      _currentLabel = forcedLabel;
      return _variantUrl(variants, forcedLabel);
    }

    final maxH = settings.maxStreamHeight;
    final effectiveLabel = settings.effectiveStreamQuality;
    if (effectiveLabel.toLowerCase() != 'auto') {
      _currentLabel = effectiveLabel;
      return _variantUrl(variants, effectiveLabel);
    }

    if (maxH != null) {
      final capped = _nearestAvailable(variants, maxH);
      _currentLabel = capped;
      return _variantUrl(variants, capped);
    }

    final label = _throughputBasedLabel();
    _currentLabel = label;
    return _variantUrl(variants, label);
  }

  /// Upgrades to the next quality tier if bandwidth supports it.
  /// Returns the URL of the chosen variant (same URL if no upgrade available).
  String tryUpgrade(List<HlsVariant> variants) {
    final settings = AppSettingsService.instance;
    final maxH = settings.maxStreamHeight;

    if (maxH != null) {
      final nearest = _nearestAvailable(variants, maxH);
      _currentLabel = nearest;
      return _variantUrl(variants, nearest);
    }

    final next = _throughputBasedLabel();
    if (next == _currentLabel) return _variantUrl(variants, _currentLabel);
    _currentLabel = next;
    return _variantUrl(variants, next);
  }

  /// Called by the player when a server fetch attempt completes.
  /// Used for high-speed failover bookkeeping.
  void onAttemptComplete({required bool success, required String serverName}) {
    // Keep track of attempt outcomes for adaptive timeout tuning
  }

  /// Starts listening to AppSettingsService for real-time global overrides.
  void attachSettingsListener(void Function() onQualityChange) {
    _onQualityChange = onQualityChange;
    if (!_listeningToSettings) {
      _listeningToSettings = true;
      AppSettingsService.instance.addListener(_onGlobalSettingsChanged);
    }
  }

  void _onGlobalSettingsChanged() {
    _onQualityChange?.call();
  }

  void detachSettingsListener() {
    if (_listeningToSettings) {
      AppSettingsService.instance.removeListener(_onGlobalSettingsChanged);
      _listeningToSettings = false;
    }
  }

  /// Resets engine state for a new media item.
  void reset() {
    _samples.clear();
    _currentLabel = '480p';
  }

  /// Returns the nearest available quality ≤ [maxHeight].
  String _nearestAvailable(List<HlsVariant> variants, int maxHeight) {
    if (variants.isEmpty) return '${maxHeight}p';
    final heights = variants
        .map((v) => _parseHeight(v.resolution))
        .whereType<int>()
        .toList()
      ..sort();
    if (heights.isEmpty) return '${maxHeight}p';
    final match = heights.lastWhere((h) => h <= maxHeight, orElse: () => heights.first);
    return '${match}p';
  }

  String _throughputBasedLabel() {
    if (_samples.length < 2) return '480p';
    final bw = _estimatedMbps;
    if (bw >= _upgradeBandwidth1080Mbps) {
      return '1080p';
    }
    if (bw >= _upgradeBandwidth720Mbps) {
      return '720p';
    }
    return '480p';
  }

  String _variantUrl(List<HlsVariant> variants, String label) {
    final targetHeight = _parseHeight(label);
    if (targetHeight == null) {
      return variants.isNotEmpty ? variants.first.url : '';
    }
    final candidates = variants.where((v) {
      final h = _parseHeight(v.resolution);
      return h != null && h == targetHeight;
    }).toList();
    if (candidates.isNotEmpty) return candidates.first.url;
    final allSorted = variants.where((v) {
      final h = _parseHeight(v.resolution);
      return h != null && h > 0;
    }).toList()
      ..sort((a, b) => (_parseHeight(b.resolution) ?? 0).compareTo(_parseHeight(a.resolution) ?? 0));
    return allSorted.isNotEmpty ? allSorted.first.url : '';
  }

  int? _parseHeight(String label) {
    if (label.isEmpty) return null;
    final lower = label.toLowerCase();
    if (lower.contains('4k') || lower.contains('uhd') || lower.contains('2160')) return 2160;
    if (lower.contains('1440') || lower.contains('2k')) return 1440;
    if (lower.contains('1080')) return 1080;
    if (lower.contains('720')) return 720;
    if (lower.contains('480')) return 480;
    final matches = RegExp(r'(\d{3,4})p?').allMatches(lower).toList();
    if (matches.isEmpty) return null;
    final last = matches.last;
    return int.tryParse(last.group(1)!);
  }
}
