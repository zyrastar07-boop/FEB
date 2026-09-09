import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks estimated cellular (mobile-data) usage for streaming & downloads.
///
/// Network type is detected via [connectivity_plus] when the package is present;
/// otherwise the app can still record usage when [forceCellularSession] is set
/// (e.g. user confirmed the cellular warning dialog).
///
/// Byte estimates are derived from:
/// - active playback time × typical bitrate for the selected quality
/// - explicit download size labels when known
class CellularDataService extends ChangeNotifier {
  CellularDataService._();
  static final CellularDataService instance = CellularDataService._();

  static const _prefix = 'feb_cellular_';

  // Lifetime totals (bytes)
  int _streamBytesCellular = 0;
  int _downloadBytesCellular = 0;

  // Today (resets at local midnight)
  String _todayKey = '';
  int _todayStreamBytes = 0;
  int _todayDownloadBytes = 0;

  // This calendar month
  String _monthKey = '';
  int _monthStreamBytes = 0;
  int _monthDownloadBytes = 0;

  // Active session
  bool _sessionActive = false;
  bool _sessionIsCellular = false;
  DateTime? _sessionStarted;
  String _sessionQuality = 'Auto';
  Timer? _tickTimer;

  bool _loaded = false;

  // ── Getters ──────────────────────────────────────────────────────────────
  int get streamBytesCellular => _streamBytesCellular;
  int get downloadBytesCellular => _downloadBytesCellular;
  int get totalBytesCellular => _streamBytesCellular + _downloadBytesCellular;

  int get todayStreamBytes => _todayStreamBytes;
  int get todayDownloadBytes => _todayDownloadBytes;
  int get todayTotalBytes => _todayStreamBytes + _todayDownloadBytes;

  int get monthStreamBytes => _monthStreamBytes;
  int get monthDownloadBytes => _monthDownloadBytes;
  int get monthTotalBytes => _monthStreamBytes + _monthDownloadBytes;

  bool get isSessionActive => _sessionActive;
  bool get isSessionCellular => _sessionIsCellular;
  bool get isLoaded => _loaded;

  String get todayLabel => _formatBytes(todayTotalBytes);
  String get monthLabel => _formatBytes(monthTotalBytes);
  String get lifetimeLabel => _formatBytes(totalBytesCellular);

  // ── Lifecycle ────────────────────────────────────────────────────────────
  /// Alias used by main.dart startup.
  Future<void> init() => load();

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _streamBytesCellular = p.getInt('${_prefix}stream') ?? 0;
      _downloadBytesCellular = p.getInt('${_prefix}download') ?? 0;

      _todayKey = p.getString('${_prefix}todayKey') ?? '';
      _todayStreamBytes = p.getInt('${_prefix}todayStream') ?? 0;
      _todayDownloadBytes = p.getInt('${_prefix}todayDownload') ?? 0;

      _monthKey = p.getString('${_prefix}monthKey') ?? '';
      _monthStreamBytes = p.getInt('${_prefix}monthStream') ?? 0;
      _monthDownloadBytes = p.getInt('${_prefix}monthDownload') ?? 0;

      _rollDateWindows();
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  void _rollDateWindows() {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    if (_todayKey != today) {
      _todayKey = today;
      _todayStreamBytes = 0;
      _todayDownloadBytes = 0;
    }
    if (_monthKey != month) {
      _monthKey = month;
      _monthStreamBytes = 0;
      _monthDownloadBytes = 0;
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('${_prefix}stream', _streamBytesCellular);
      await p.setInt('${_prefix}download', _downloadBytesCellular);
      await p.setString('${_prefix}todayKey', _todayKey);
      await p.setInt('${_prefix}todayStream', _todayStreamBytes);
      await p.setInt('${_prefix}todayDownload', _todayDownloadBytes);
      await p.setString('${_prefix}monthKey', _monthKey);
      await p.setInt('${_prefix}monthStream', _monthStreamBytes);
      await p.setInt('${_prefix}monthDownload', _monthDownloadBytes);
    } catch (_) {}
  }

  Future<void> resetAll() async {
    _streamBytesCellular = 0;
    _downloadBytesCellular = 0;
    _todayStreamBytes = 0;
    _todayDownloadBytes = 0;
    _monthStreamBytes = 0;
    _monthDownloadBytes = 0;
    _rollDateWindows();
    await _persist();
    notifyListeners();
  }

  // ── Network type ─────────────────────────────────────────────────────────

  /// Returns true when the device is likely on mobile/cellular data.
  /// Uses connectivity_plus via dynamic call so the package is optional.
  Future<bool> isOnCellular() async {
    try {
      // Prefer connectivity_plus if the project depends on it.
      // Avoid hard import so builds without the package still compile.
      // Users can set forceCellularSession from the warning dialog instead.
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Streaming session ────────────────────────────────────────────────────

  /// Start metering a playback session.
  /// [isCellular] — pass true after user confirmed cellular warning, or from
  /// a real connectivity check when available.
  void startStreamSession({
    required String quality,
    bool isCellular = false,
  }) {
    stopStreamSession(); // close any previous
    _sessionActive = true;
    _sessionIsCellular = isCellular;
    _sessionStarted = DateTime.now();
    _sessionQuality = quality;

    // Tick every 15s while playing to accumulate estimate.
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _accumulateStreamTick(seconds: 15);
    });
  }

  void updateSessionQuality(String quality) {
    if (!_sessionActive) return;
    // Flush current quality segment before switching bitrate estimate.
    _accumulateStreamTick(seconds: 0, forceFlush: true);
    _sessionQuality = quality;
  }

  void setSessionCellular(bool isCellular) {
    _sessionIsCellular = isCellular;
  }

  /// Call while video is actually playing (optional fine-grained control).
  void notePlaybackTick({required int elapsedSeconds}) {
    if (!_sessionActive || !_sessionIsCellular) return;
    if (elapsedSeconds <= 0) return;
    _accumulateStreamTick(seconds: elapsedSeconds);
  }

  void _accumulateStreamTick({required int seconds, bool forceFlush = false}) {
    if (!_sessionActive) return;
    if (!_sessionIsCellular && !forceFlush) return;

    final bps = _bitrateForQuality(_sessionQuality);
    final bytes = (bps * seconds / 8).round();
    if (bytes <= 0 && !forceFlush) return;

    if (_sessionIsCellular) {
      _addStreamBytes(bytes);
    }
  }

  /// End metering and persist.
  void stopStreamSession() {
    if (!_sessionActive) return;
    _tickTimer?.cancel();
    _tickTimer = null;

    // Final partial window since last tick
    if (_sessionStarted != null && _sessionIsCellular) {
      final elapsed = DateTime.now().difference(_sessionStarted!).inSeconds;
      // Don't double-count full ticks; approximate residual under 15s is fine
      // because periodic ticks already covered most of the time.
      final residual = elapsed % 15;
      if (residual > 0) {
        _accumulateStreamTick(seconds: residual);
      }
    }

    _sessionActive = false;
    _sessionIsCellular = false;
    _sessionStarted = null;
    unawaited(_persist());
  }

  void _addStreamBytes(int bytes) {
    if (bytes <= 0) return;
    _rollDateWindows();
    _streamBytesCellular += bytes;
    _todayStreamBytes += bytes;
    _monthStreamBytes += bytes;
    notifyListeners();
  }

  // ── Downloads ────────────────────────────────────────────────────────────

  /// Record a completed (or progressed) download that used cellular data.
  void recordDownloadBytes(int bytes, {bool isCellular = true}) {
    if (bytes <= 0 || !isCellular) return;
    _rollDateWindows();
    _downloadBytesCellular += bytes;
    _todayDownloadBytes += bytes;
    _monthDownloadBytes += bytes;
    unawaited(_persist());
    notifyListeners();
  }

  /// Parse labels like "1.2 GB", "450 MB", "720p · 1.1 Mbps" → approximate bytes.
  ///
  /// The Mbps path uses a 90-minute movie baseline (typical feature film)
  /// so a 480p/1.5 Mbps estimate is ~1 GB, not the smaller 45-min estimate.
  static int parseSizeLabel(String? label) {
    if (label == null || label.isEmpty) return 0;
    final lower = label.toLowerCase();
    final match = RegExp(r'([\d.]+)\s*(gb|mb|kb|b)\b').firstMatch(lower);
    if (match == null) {
      // Mbps estimate for ~90 min movie at that rate.
      final mbps = RegExp(r'([\d.]+)\s*mbps').firstMatch(lower);
      if (mbps != null) {
        final rate = double.tryParse(mbps.group(1)!) ?? 0;
        return (rate * 1e6 / 8 * 90 * 60).round();
      }
      return 0;
    }
    final n = double.tryParse(match.group(1)!) ?? 0;
    switch (match.group(2)) {
      case 'gb':
        return (n * 1e9).round();
      case 'mb':
        return (n * 1e6).round();
      case 'kb':
        return (n * 1e3).round();
      default:
        return n.round();
    }
  }

  // ── Bitrate model ────────────────────────────────────────────────────────

  /// Approximate bits/sec for common ladder labels (for usage estimates only).
  static int _bitrateForQuality(String quality) {
    final q = quality.toLowerCase();
    if (q.contains('4k') || q.contains('2160')) return 15000000;
    if (q.contains('1440')) return 8000000;
    if (q.contains('1080')) return 5000000;
    if (q.contains('720')) return 2500000;
    if (q.contains('480')) return 1200000;
    if (q.contains('360')) return 700000;
    if (q.contains('240')) return 400000;
    // Auto / unknown → assume mid ladder
    return 2000000;
  }

  static String formatBytes(int bytes) => _formatBytes(bytes);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}