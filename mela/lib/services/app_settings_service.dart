import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists profile / playback preferences across restarts.
class AppSettingsService extends ChangeNotifier {
  AppSettingsService._();
  static final AppSettingsService instance = AppSettingsService._();

  SharedPreferences? _prefs;
  bool _ready = false;
  bool get isReady => _ready;

  // General & playback
  bool autoplayNext = true;
  bool askBeforeResuming = false;
  bool skipIntros = true;
  bool autoplayPreviews = true;
  String defaultQuality = 'Auto';
  String playbackSpeed = '1.0x';

  // Content
  bool blockAdultContent = true;
  bool hideWatchedFromHome = false;
  String contentLanguage = 'Any';

  // Downloads
  bool dataSaver = false;
  bool downloadOverWifiOnly = true;
  String downloadQuality = 'High';

  // Notifications
  bool newEpisodeAlerts = true;
  bool recommendationAlerts = false;
  bool downloadCompleteAlerts = true;

  // Accessibility
  bool hapticFeedback = true;
  bool subtitlesByDefault = false;
  double textScale = 1.0;

  // Privacy
  bool shareWatchActivity = true;

  Future<void> init() async {
    if (_ready) return;
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;

    autoplayNext = p.getBool('autoplayNext') ?? true;
    askBeforeResuming = p.getBool('askBeforeResuming') ?? false;
    skipIntros = p.getBool('skipIntros') ?? true;
    autoplayPreviews = p.getBool('autoplayPreviews') ?? true;
    defaultQuality = p.getString('defaultQuality') ?? 'Auto';
    playbackSpeed = p.getString('playbackSpeed') ?? '1.0x';

    blockAdultContent = p.getBool('blockAdultContent') ?? true;
    hideWatchedFromHome = p.getBool('hideWatchedFromHome') ?? false;
    contentLanguage = p.getString('contentLanguage') ?? 'Any';

    dataSaver = p.getBool('dataSaver') ?? false;
    downloadOverWifiOnly = p.getBool('downloadOverWifiOnly') ?? true;
    downloadQuality = p.getString('downloadQuality') ?? 'High';

    newEpisodeAlerts = p.getBool('newEpisodeAlerts') ?? true;
    recommendationAlerts = p.getBool('recommendationAlerts') ?? false;
    downloadCompleteAlerts = p.getBool('downloadCompleteAlerts') ?? true;

    hapticFeedback = p.getBool('hapticFeedback') ?? true;
    subtitlesByDefault = p.getBool('subtitlesByDefault') ?? false;
    textScale = p.getDouble('textScale') ?? 1.0;

    shareWatchActivity = p.getBool('shareWatchActivity') ?? true;

    _ready = true;
    notifyListeners();
  }

  Future<void> _setBool(String key, bool value) async {
    await _prefs?.setBool(key, value);
    notifyListeners();
  }

  Future<void> _setString(String key, String value) async {
    await _prefs?.setString(key, value);
    notifyListeners();
  }

  Future<void> _setDouble(String key, double value) async {
    await _prefs?.setDouble(key, value);
    notifyListeners();
  }

  Future<void> setAutoplayNext(bool v) async {
    autoplayNext = v;
    await _setBool('autoplayNext', v);
  }

  Future<void> setAskBeforeResuming(bool v) async {
    askBeforeResuming = v;
    await _setBool('askBeforeResuming', v);
  }

  Future<void> setSkipIntros(bool v) async {
    skipIntros = v;
    await _setBool('skipIntros', v);
  }

  Future<void> setAutoplayPreviews(bool v) async {
    autoplayPreviews = v;
    await _setBool('autoplayPreviews', v);
  }

  Future<void> setDefaultQuality(String v) async {
    defaultQuality = v;
    await _setString('defaultQuality', v);
  }

  Future<void> setPlaybackSpeed(String v) async {
    playbackSpeed = v;
    await _setString('playbackSpeed', v);
  }

  Future<void> setBlockAdultContent(bool v) async {
    blockAdultContent = v;
    await _setBool('blockAdultContent', v);
  }

  Future<void> setHideWatchedFromHome(bool v) async {
    hideWatchedFromHome = v;
    await _setBool('hideWatchedFromHome', v);
  }

  Future<void> setContentLanguage(String v) async {
    contentLanguage = v;
    await _setString('contentLanguage', v);
  }

  Future<void> setDataSaver(bool v) async {
    dataSaver = v;
    await _setBool('dataSaver', v);
  }

  Future<void> setDownloadOverWifiOnly(bool v) async {
    downloadOverWifiOnly = v;
    await _setBool('downloadOverWifiOnly', v);
  }

  Future<void> setDownloadQuality(String v) async {
    downloadQuality = v;
    await _setString('downloadQuality', v);
  }

  Future<void> setNewEpisodeAlerts(bool v) async {
    newEpisodeAlerts = v;
    await _setBool('newEpisodeAlerts', v);
  }

  Future<void> setRecommendationAlerts(bool v) async {
    recommendationAlerts = v;
    await _setBool('recommendationAlerts', v);
  }

  Future<void> setDownloadCompleteAlerts(bool v) async {
    downloadCompleteAlerts = v;
    await _setBool('downloadCompleteAlerts', v);
  }

  Future<void> setHapticFeedback(bool v) async {
    hapticFeedback = v;
    await _setBool('hapticFeedback', v);
  }

  Future<void> setSubtitlesByDefault(bool v) async {
    subtitlesByDefault = v;
    await _setBool('subtitlesByDefault', v);
  }

  Future<void> setTextScale(double v) async {
    textScale = v;
    await _setDouble('textScale', v);
  }

  Future<void> setShareWatchActivity(bool v) async {
    shareWatchActivity = v;
    await _setBool('shareWatchActivity', v);
  }
}
