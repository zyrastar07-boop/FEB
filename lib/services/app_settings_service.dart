import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global app settings. ChangeNotifier so player / downloads / home can listen.
class AppSettingsService extends ChangeNotifier {
  AppSettingsService._();
  static final AppSettingsService instance = AppSettingsService._();

  static const _prefix = 'feb_settings_';

  // ── Playback ────────────────────────────────────────────────────────────
  String _defaultQuality = 'Auto';
  String _playbackSpeed = '1.0x';
  bool _autoplayNext = true;
  bool _askBeforeResuming = true;
  bool _skipIntros = true; // Default to enabled so skip intro shows for TV shows
  bool _autoplayPreviews = true;
  String _bufferSize = 'Auto'; // Auto | Small (5s) | Medium (15s) | Large (30s)
  String _subtitleLanguage = 'English';
  bool _rememberPosition = true;
  bool _cellularWarning = true;
  bool _subtitlesByDefault = false;

  // ── Content ─────────────────────────────────────────────────────────────
  bool _blockAdultContent = true;
  bool _hideWatchedFromHome = false;
  String _contentLanguage = 'Any';

  // ── Streaming ────────────────────────────────────────────────────────
  String _streamingServerUrl = 'http://127.0.0.1:11470';

  // ── Downloads & network ──────────────────────────────────────────────────
  bool _dataSaver = false;
  bool _downloadOverWifiOnly = true;
  String _downloadQuality = 'High'; // Standard | High | Ultra

  // ── Notifications ───────────────────────────────────────────────────────
  bool _newEpisodeAlerts = true;
  bool _recommendationAlerts = true;
  bool _downloadCompleteAlerts = true;

  // ── Appearance ──────────────────────────────────────────────────────────
  bool _hapticFeedback = true;
  double _textScale = 1.0;
  bool _shareWatchActivity = false;

  // ── Integrations ──────────────────────────────────────────────────────
  // OpenSubtitles.com API key (free tier: 200 downloads/day). Empty =
  // OpenSubtitles downloads disabled; wyzie stays the fallback provider.
  String _openSubtitlesApiKey = '';

  bool _loaded = false;

  // ── Getters ─────────────────────────────────────────────────────────────
  String get defaultQuality => _defaultQuality;
  String get playbackSpeed => _playbackSpeed;
  bool get autoplayNext => _autoplayNext;
  bool get askBeforeResuming => _askBeforeResuming;
  bool get skipIntros => _skipIntros;
  bool get autoplayPreviews => _autoplayPreviews;
  String get bufferSize => _bufferSize;
  String get subtitleLanguage => _subtitleLanguage;
  bool get rememberPosition => _rememberPosition;
  bool get cellularWarning => _cellularWarning;
  bool get subtitlesByDefault => _subtitlesByDefault;
  bool get blockAdultContent => _blockAdultContent;
  bool get hideWatchedFromHome => _hideWatchedFromHome;
  String get contentLanguage => _contentLanguage;
  bool get dataSaver => _dataSaver;
  bool get downloadOverWifiOnly => _downloadOverWifiOnly;
  String get downloadQuality => _downloadQuality;
  String get streamingServerUrl => _streamingServerUrl;
  bool get newEpisodeAlerts => _newEpisodeAlerts;
  bool get recommendationAlerts => _recommendationAlerts;
  bool get downloadCompleteAlerts => _downloadCompleteAlerts;
  bool get hapticFeedback => _hapticFeedback;
  double get textScale => _textScale;
  bool get shareWatchActivity => _shareWatchActivity;
  String get openSubtitlesApiKey => _openSubtitlesApiKey;
  bool get isLoaded => _loaded;

  /// Maps buffer label → approximate seconds for player buffering hints.
  int get bufferSeconds {
    switch (_bufferSize) {
      case 'Small (5s)':
        return 5;
      case 'Medium (15s)':
        return 15;
      case 'Large (30s)':
        return 30;
      default:
        return 15; // Auto
    }
  }

  /// Effective stream quality when data saver is on (caps at 480p).
  String get effectiveStreamQuality {
    if (_dataSaver) return '480p';
    return _defaultQuality;
  }

  /// Preferred height ceiling for HLS variant selection.
  int? get maxStreamHeight {
    final q = effectiveStreamQuality.toLowerCase();
    if (q == 'auto') return null;
    if (q.contains('4k') || q.contains('2160')) return 2160;
    if (q.contains('1080')) return 1080;
    if (q.contains('720')) return 720;
    if (q.contains('480')) return 480;
    return null;
  }

  /// Download preference → preferred max height.
  int get preferredDownloadHeight {
    switch (_downloadQuality) {
      case 'Standard':
        return 480;
      case 'Ultra':
        return 1080;
      case 'High':
      default:
        return 720;
    }
  }

  // ── Setters (persist + notify) ──────────────────────────────────────────
  Future<void> setDefaultQuality(String v) async {
    _defaultQuality = v;
    notifyListeners();
    await _save('defaultQuality', v);
  }

  Future<void> setPlaybackSpeed(String v) async {
    _playbackSpeed = v;
    notifyListeners();
    await _save('playbackSpeed', v);
  }

  Future<void> setAutoplayNext(bool v) async {
    _autoplayNext = v;
    notifyListeners();
    await _saveBool('autoplayNext', v);
  }

  Future<void> setAskBeforeResuming(bool v) async {
    _askBeforeResuming = v;
    notifyListeners();
    await _saveBool('askBeforeResuming', v);
  }

  Future<void> setSkipIntros(bool v) async {
    _skipIntros = v;
    notifyListeners();
    await _saveBool('skipIntros', v);
  }

  Future<void> setAutoplayPreviews(bool v) async {
    _autoplayPreviews = v;
    notifyListeners();
    await _saveBool('autoplayPreviews', v);
  }

  Future<void> setBufferSize(String v) async {
    _bufferSize = v;
    notifyListeners();
    await _save('bufferSize', v);
  }

  Future<void> setSubtitleLanguage(String v) async {
    _subtitleLanguage = v;
    notifyListeners();
    await _save('subtitleLanguage', v);
  }

  Future<void> setRememberPosition(bool v) async {
    _rememberPosition = v;
    notifyListeners();
    await _saveBool('rememberPosition', v);
  }

  Future<void> setCellularWarning(bool v) async {
    _cellularWarning = v;
    notifyListeners();
    await _saveBool('cellularWarning', v);
  }

  Future<void> setSubtitlesByDefault(bool v) async {
    _subtitlesByDefault = v;
    notifyListeners();
    await _saveBool('subtitlesByDefault', v);
  }

  Future<void> setBlockAdultContent(bool v) async {
    _blockAdultContent = v;
    notifyListeners();
    await _saveBool('blockAdultContent', v);
  }

  Future<void> setHideWatchedFromHome(bool v) async {
    _hideWatchedFromHome = v;
    notifyListeners();
    await _saveBool('hideWatchedFromHome', v);
  }

  Future<void> setContentLanguage(String v) async {
    _contentLanguage = v;
    notifyListeners();
    await _save('contentLanguage', v);
  }

  Future<void> setDataSaver(bool v) async {
    _dataSaver = v;
    notifyListeners();
    await _saveBool('dataSaver', v);
  }

  Future<void> setDownloadOverWifiOnly(bool v) async {
    _downloadOverWifiOnly = v;
    notifyListeners();
    await _saveBool('downloadOverWifiOnly', v);
  }

  Future<void> setDownloadQuality(String v) async {
    _downloadQuality = v;
    notifyListeners();
    await _save('downloadQuality', v);
  }

  Future<void> setNewEpisodeAlerts(bool v) async {
    _newEpisodeAlerts = v;
    notifyListeners();
    await _saveBool('newEpisodeAlerts', v);
  }

  Future<void> setRecommendationAlerts(bool v) async {
    _recommendationAlerts = v;
    notifyListeners();
    await _saveBool('recommendationAlerts', v);
  }

  Future<void> setDownloadCompleteAlerts(bool v) async {
    _downloadCompleteAlerts = v;
    notifyListeners();
    await _saveBool('downloadCompleteAlerts', v);
  }

  Future<void> setStreamingServerUrl(String v) async {
    _streamingServerUrl = v;
    notifyListeners();
    await _save('streamingServerUrl', v);
  }

  Future<void> setHapticFeedback(bool v) async {
    _hapticFeedback = v;
    notifyListeners();
    await _saveBool('hapticFeedback', v);
  }

  Future<void> setTextScale(double v) async {
    _textScale = v.clamp(0.8, 1.4);
    notifyListeners();
    await _saveDouble('textScale', _textScale);
  }

  Future<void> setShareWatchActivity(bool v) async {
    _shareWatchActivity = v;
    notifyListeners();
    await _saveBool('shareWatchActivity', v);
  }

  Future<void> setOpenSubtitlesApiKey(String v) async {
    _openSubtitlesApiKey = v.trim();
    notifyListeners();
    await _save('openSubtitlesApiKey', _openSubtitlesApiKey);
  }

  // ── Persistence ─────────────────────────────────────────────────────────
  /// Alias used by main.dart startup.
  Future<void> init() => load();

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _defaultQuality = p.getString('${_prefix}defaultQuality') ?? _defaultQuality;
      _playbackSpeed = p.getString('${_prefix}playbackSpeed') ?? _playbackSpeed;
      _autoplayNext = p.getBool('${_prefix}autoplayNext') ?? _autoplayNext;
      _askBeforeResuming =
          p.getBool('${_prefix}askBeforeResuming') ?? _askBeforeResuming;
      _skipIntros = p.getBool('${_prefix}skipIntros') ?? _skipIntros;
      _autoplayPreviews =
          p.getBool('${_prefix}autoplayPreviews') ?? _autoplayPreviews;
      _bufferSize = p.getString('${_prefix}bufferSize') ?? _bufferSize;
      _subtitleLanguage =
          p.getString('${_prefix}subtitleLanguage') ?? _subtitleLanguage;
      _rememberPosition =
          p.getBool('${_prefix}rememberPosition') ?? _rememberPosition;
      _cellularWarning =
          p.getBool('${_prefix}cellularWarning') ?? _cellularWarning;
      _subtitlesByDefault =
          p.getBool('${_prefix}subtitlesByDefault') ?? _subtitlesByDefault;
      _blockAdultContent =
          p.getBool('${_prefix}blockAdultContent') ?? _blockAdultContent;
      _hideWatchedFromHome =
          p.getBool('${_prefix}hideWatchedFromHome') ?? _hideWatchedFromHome;
      _contentLanguage =
          p.getString('${_prefix}contentLanguage') ?? _contentLanguage;
      _dataSaver = p.getBool('${_prefix}dataSaver') ?? _dataSaver;
      _downloadOverWifiOnly =
          p.getBool('${_prefix}downloadOverWifiOnly') ?? _downloadOverWifiOnly;
      _downloadQuality =
          p.getString('${_prefix}downloadQuality') ?? _downloadQuality;
      _streamingServerUrl =
          p.getString('${_prefix}streamingServerUrl') ?? _streamingServerUrl;
      _newEpisodeAlerts =
          p.getBool('${_prefix}newEpisodeAlerts') ?? _newEpisodeAlerts;
      _recommendationAlerts =
          p.getBool('${_prefix}recommendationAlerts') ?? _recommendationAlerts;
      _downloadCompleteAlerts = p.getBool('${_prefix}downloadCompleteAlerts') ??
          _downloadCompleteAlerts;
      _hapticFeedback = p.getBool('${_prefix}hapticFeedback') ?? _hapticFeedback;
      _textScale = p.getDouble('${_prefix}textScale') ?? _textScale;
      _shareWatchActivity =
          p.getBool('${_prefix}shareWatchActivity') ?? _shareWatchActivity;
      _openSubtitlesApiKey =
          p.getString('${_prefix}openSubtitlesApiKey') ?? _openSubtitlesApiKey;
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save(String key, String value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('$_prefix$key', value);
    } catch (_) {}
  }

  Future<void> _saveBool(String key, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('$_prefix$key', value);
    } catch (_) {}
  }

  Future<void> _saveDouble(String key, double value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('$_prefix$key', value);
    } catch (_) {}
  }
}