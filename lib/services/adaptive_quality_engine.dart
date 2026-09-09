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

/// Throughput-aware quality helper.
///
/// Important: when the user's quality is Auto, the player must receive the
/// HLS multivariant/master URL instead of an arbitrarily selected 480p/720p
/// child playlist. Android's Media3/ExoPlayer can then perform real adaptive
/// bitrate selection from the variants advertised by the master playlist.
class AdaptiveQualityEngine {
  AdaptiveQualityEngine._();
  static final AdaptiveQualityEngine instance = AdaptiveQualityEngine._();

  static const _historyWindow = 8;
  static const _upgradeBandwidth720Mbps = 3.5;
  static const _upgradeBandwidth1080Mbps = 7.0;

  final Queue<_BwSample> _samples = Queue();
  String _currentLabel = 'Auto';
  bool _listeningToSettings = false;
  void Function()? _onQualityChange;

  String get currentLabel => _currentLabel;

  bool get canUpgrade720 => _estimatedMbps >= _upgradeBandwidth720Mbps;
  bool get canUpgrade1080 => _estimatedMbps >= _upgradeBandwidth1080Mbps;

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

  /// Returns the quality label the player should expose.
  ///
  /// Auto deliberately stays Auto. The CustomPlayerScreen sees this and uses
  /// the master HLS URL, allowing ExoPlayer to choose and switch variants.
  String resolveQuality(List<HlsVariant> variants, {String? forcedLabel}) {
    final settings = AppSettingsService.instance;

    if (forcedLabel != null && forcedLabel.isNotEmpty) {
      if (forcedLabel.toLowerCase() == 'auto') {
        _currentLabel = 'Auto';
        return 'Auto';
      }
      _currentLabel = forcedLabel;
      return _variantUrl(variants, forcedLabel);
    }

    final maxH = settings.maxStreamHeight;
    final effectiveLabel = settings.effectiveStreamQuality;

    if (effectiveLabel.toLowerCase() == 'auto') {
      _currentLabel = 'Auto';
      return 'Auto';
    }

    if (maxH != null) {
      final capped = _nearestAvailable(variants, maxH);
      _currentLabel = capped;
      return capped;
    }

    _currentLabel = effectiveLabel;
    return effectiveLabel;
  }

  /// Chooses a quality tier for an explicit adaptive switch request.
  /// Initial Auto playback does not call this path; it uses the master HLS URL.
  String tryUpgrade(List<HlsVariant> variants) {
    final settings = AppSettingsService.instance;
    final maxH = settings.maxStreamHeight;

    if (maxH != null) {
      final nearest = _nearestAvailable(variants, maxH);
      _currentLabel = nearest;
      return _variantUrl(variants, nearest);
    }

    final next = _throughputBasedLabel();
    _currentLabel = next;
    return _variantUrl(variants, next);
  }

  void onAttemptComplete({required bool success, required String serverName}) {}

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

  void reset() {
    _samples.clear();
    _currentLabel = 'Auto';
  }

  String _nearestAvailable(List<HlsVariant> variants, int maxHeight) {
    if (variants.isEmpty) return '${maxHeight}p';
    final heights = variants
        .map((v) => _parseHeight(v.resolution))
        .whereType<int>()
        .toList()
      ..sort();
    if (heights.isEmpty) return '${maxHeight}p';
    final match = heights.lastWhere(
      (h) => h <= maxHeight,
      orElse: () => heights.first,
    );
    return '${match}p';
  }

  String _throughputBasedLabel() {
    if (_samples.length < 2) return '480p';
    final bw = _estimatedMbps;
    if (bw >= _upgradeBandwidth1080Mbps) return '1080p';
    if (bw >= _upgradeBandwidth720Mbps) return '720p';
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
      ..sort((a, b) =>
          (_parseHeight(b.resolution) ?? 0)
              .compareTo(_parseHeight(a.resolution) ?? 0));
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
    return int.tryParse(matches.last.group(1)!);
  }
}
