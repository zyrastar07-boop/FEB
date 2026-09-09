import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:auto_orientation/auto_orientation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/movie.dart';
import '../services/web_view_scraper.dart';
import '../services/wyzie_subtitle_service.dart';
import '../services/subtitle_cache_helper.dart';
import '../services/addon_repository.dart';
import '../services/addon_playback.dart';
import '../services/addon_content_models.dart';
import '../services/debrid_resolver.dart';
import '../widgets/subtitle_track_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/continue_watching_service.dart';
import '../widgets/satellite_pulse_loader.dart';
import 'player_episode_drawer.dart';
import '../services/app_settings_service.dart';
import '../services/tmdb_details_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../design/tokens.dart';
import '../design/motion.dart';
import '../design/screen_metrics.dart';
import '../services/encrypted_cache_manager.dart';
import '../services/adaptive_quality_engine.dart';
import '../services/skip_intro_detector.dart';

const _gold = AppDesignTokens.gold;

class SubtitleItem {
  final Duration start;
  final Duration end;
  final String text;

  SubtitleItem({required this.start, required this.end, required this.text});
}

class HlsVariant {
  final String resolution;
  final String url;

  HlsVariant({required this.resolution, required this.url});
}

/// Small in‑memory cache of resolved (scraped) direct stream URLs.
class _ResolvedStreamCache {
  _ResolvedStreamCache._();

  static const Duration _ttl = Duration(minutes: 15);
  static const int _maxEntries = 24;

  static final Map<String, _ResolvedStreamEntry> _entries = {};

  static String buildKey({
    required String? tmdbId,
    required String mediaType,
    required int season,
    required int episode,
    required String server,
  }) {
    return '${tmdbId ?? ''}_${mediaType.toLowerCase()}_${season}_${episode}_$server';
  }

  static _ResolvedStreamEntry? get(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.resolvedAt) > _ttl) {
      _entries.remove(key);
      return null;
    }
    return entry;
  }

  static void put(
    String key, {
    required String streamUrl,
    required String? referer,
    required List<HlsVariant> variants,
  }) {
    if (_entries.length >= _maxEntries && !_entries.containsKey(key)) {
      final oldestKey = _entries.entries
          .reduce((a, b) =>
              a.value.resolvedAt.isBefore(b.value.resolvedAt) ? a : b)
          .key;
      _entries.remove(oldestKey);
    }
    _entries[key] = _ResolvedStreamEntry(
      streamUrl: streamUrl,
      referer: referer,
      variants: variants,
      resolvedAt: DateTime.now(),
    );
  }
}

class _ResolvedStreamEntry {
  final String streamUrl;
  final String? referer;
  final List<HlsVariant> variants;
  final DateTime resolvedAt;

  _ResolvedStreamEntry({
    required this.streamUrl,
    required this.referer,
    required this.variants,
    required this.resolvedAt,
  });
}

class CustomPlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String? tmdbId;
  final String? imdbId;
  final String mediaType;
  final int? season;
  final int? episode;
  final String wisoApiKey;
  final Map<String, String>? headers;
  final List<Map<String, dynamic>>? servers;
  final bool isOffline;

  final String? initialServerName;
  final String? localSubtitlePath;
  final Movie? movie;
  final int? initialPositionSeconds;

  const CustomPlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    required this.wisoApiKey,
    this.tmdbId,
    this.imdbId,
    this.mediaType = 'movie',
    this.season,
    this.episode,
    this.headers,
    this.servers,
    this.isOffline = false,
    this.initialServerName,
    this.localSubtitlePath,
    this.movie,
    this.initialPositionSeconds,
  });

  @override
  State<CustomPlayerScreen> createState() => _CustomPlayerScreenState();
}

enum ActiveDrawer {
  none,
  settings,
  quality,
  aspectRatio,
  subtitles,
  servers,
  episodes
}

class _CustomPlayerScreenState extends State<CustomPlayerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isSwitchingQuality = false;
  bool _showControls = true;
  bool _hasError = false;
  bool _isLocked = false;
  bool _isScraping = false;
  String _errorMessage = '';
  double _scrapeProgress = 0.0; // 0.0 to 1.0 for progress bar
  Timer? _hideTimer;

  late String _masterStreamUrl;
  late String _activeStreamUrl;
  String? _streamReferer;
  String _selectedServer = 'VidFast';
  List<Map<String, dynamic>> _serverList = [];

  // ── Installed Add-ons as stream sources ──────────────────────────────────
  /// Name prefix marking an add-on stream as the active source. Kept distinct
  /// from every name in [_serverList] so server lookups never collide.
  static const String _addonServerPrefix = 'ADD-ON · ';
  bool _anyAddonsInstalled = false;
  bool _addonSourcesChecked = false;
  bool _addonSourcesLoading = false;
  int _addonSourcesEpoch = 0;
  List<AddonPlaybackSource> _addonSources = const [];

  bool get _isAddonSourceActive =>
      _selectedServer.startsWith(_addonServerPrefix);

  late int _currentSeason;
  late int _currentEpisode;

  List<HlsVariant> _hlsVariants = [];
  String _selectedQuality = AppSettingsService.instance.effectiveStreamQuality;

  // ── High-Speed Server Failover ─────────────────────────────────────────────
  /// How many WebViewScraper errors we've had on the current server.
  /// After 3 attempts we failover to the next server.
  int _serverAttemptCount = 0;
  static const int _maxServerAttempts = 3;
  /// When true, scraper timeout is halved (7s vs normal 14s) for faster failure detection.
  bool _fastFailoverMode = false;

  // ── Bandwidth / Throughput Tracking ────────────────────────────────────────
  int _bwLastBytes = 0;
  bool _bwFirstSampleRecorded = false;
  DateTime? _bwBufferStart;

  // ── Skip Intro ─────────────────────────────────────────────────────────────
  SkipSegment? _skipIntroSegment;
  bool _skipIntroVisible = false;

  ActiveDrawer _activeDrawer = ActiveDrawer.none;

  String _selectedAspectRatio = 'Auto';
  double? _customAspectRatio;
  double _renderedAspect = 0.0;

  double _volumeLevel = 0.5;
  double _brightnessLevel = 0.5;
  bool _showGestureToast = false;
  String _toastIcon = 'volume';
  Timer? _toastTimer;
  DateTime? _lastVolumeUpdate;

  bool _showSeekFlash = false;
  bool _seekFlashForward = true;
  Timer? _seekFlashTimer;

  List<SubtitleItem> _parsedSubtitles = [];
  String _currentSubtitleText = '';
  String _selectedLanguage = 'English';
  bool _subtitlesEnabled = true;
  double _subtitleOffsetSeconds = 0.0;
  int _lastSubtitleCueIndex = -2;

  Timer? _subtitleTimer;

  Offset? _subtitleDragOffset;
  double _subtitleScale = 1.0;

  final WyzieSubtitleService _wyzieSubs = WyzieSubtitleService();
  List<WyzieSubtitleTrack> _availableTracks = [];
  /// Tracks contributed by the active add-on stream (kept separate so the
  /// Wyzie search result can replace its own list without dropping ours).
  List<WyzieSubtitleTrack> _addonSubtitleTracks = const [];
  String? _selectedTrackId;
  bool _loadingTracks = false;

  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _isPlayingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _isBufferingNotifier = ValueNotifier(false);
  final ValueNotifier<double?> _sliderDragNotifier = ValueNotifier(null);
  final ValueNotifier<Duration> _bufferedNotifier = ValueNotifier(Duration.zero);

  bool _showNextEpisodeCard = false;
  bool _nextEpisodeCancelled = false;
  double _nextEpisodeProgress = 0.0;
  Timer? _nextEpisodeTimer;
  AnimationController? _nextEpisodeShimmer;

  Timer? _progressSaveTimer;
  bool _wasPlaying = false;
  bool _hasAppliedInitialSeek = false;
  String? _titleLogoUrl;
  Movie? _hydratedProgressMovie;

  // ─── Connectivity-aware quality capping ──────────────────────────────────────
  /// Cellular hard cap for 'Auto' — mirrors YouTube's own default behavior
  /// of not silently blowing through mobile data at 4K/1080p.
  static const int _cellularAutoCapHeight = 720;
  bool _isCellular = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // ─── Humorous loading messages ─────────────────────────────────────────────
  // ─── Humorous loading messages ──────────────────────────────────────────
  final List<String> _loadingMessagesShort = const [
    'Please wait – our scraper is working its magic.',
    'Grabbing the stream… don\'t go anywhere.',
    'Still faster than cable, right?',
    'Untangling some very stubborn wires.',
    'Politely asking the server to hurry up.',
    'Buffering at the speed of "trust me, bro."',
    'This is the fun part, apparently.',
    'Convincing the CDN we\'re serious this time.',
  ];
  final List<String> _loadingMessagesLong = const [
    'Okay, this one\'s taking a bit – hang tight.',
    'Why is your internet slow? Blame the provider.',
    'Still faster than cable, right? ...right?',
    'Patience is a virtue, but we\'re also impatient.',
    'Almost there… or not? Just kidding. Probably.',
    'This may take a moment – we\'re fighting lag.',
    'Sending a strongly worded email to the network.',
    'Definitely still working. Definitely.',
  ];
  final List<int> _shownMessageIndices = [];
  bool _usingLongMessagePool = false;
  int _currentMessageIndex = 0;
  Timer? _messageTimer;
  DateTime? _scrapingStartedAt;

  late AnimationController _controlsFade;
  late AnimationController _drawerSlide;
  late AnimationController _toastFade;
  late Animation<double> _controlsOpacity;
  late Animation<Offset> _drawerOffset;
  late Animation<double> _toastOpacity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();

    AutoOrientation.landscapeRightMode();

    _currentSeason = widget.season ?? 1;
    _currentEpisode = widget.episode ?? 1;

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _controlsFade = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
    );
    _drawerSlide = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
    );
    _toastFade = AnimationController(
      vsync: this,
      duration: AppMotion.standard,
    );
    _nextEpisodeShimmer = AnimationController(
      vsync: this,
      duration: AppMotion.slow,
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rescaleAll();
    });


    _controlsOpacity =
        CurvedAnimation(parent: _controlsFade, curve: AppMotion.easeOut);
    _drawerOffset = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _drawerSlide, curve: AppMotion.easeDrawer));
    _toastOpacity = CurvedAnimation(parent: _toastFade, curve: AppMotion.easeOut);

    _controlsFade.forward();

    _selectedQuality = AppSettingsService.instance.effectiveStreamQuality;
    _subtitlesEnabled = AppSettingsService.instance.subtitlesByDefault;
    AppSettingsService.instance.addListener(_onAppSettingsChanged);

    _initServerList();
    if (!widget.isOffline && widget.tmdbId != null) {
      // Warm add-on sources in the background so the server drawer can show
      // them immediately once opened.
      unawaited(_refreshAddonSources());
    }
    _initBrightnessAndVolume();
    _initConnectivityMonitoring();
    _maybeWarnCellularThenLoad();

    // ── EncryptedCacheManager: ensure cache is ready ─────────────────────────
    EncryptedCacheManager.instance.init();

    // ── AdaptiveQualityEngine: attach settings listener for global overrides ───
    AdaptiveQualityEngine.instance.attachSettingsListener(_onGlobalQualityOverride);

    // ── SkipIntroDetector: attach settings + start detection ──────────────────
    SkipIntroDetector.instance.attachSettingsListener();
    _initSkipIntro();

    if (!widget.isOffline) {
      _fetchWisoSubtitles();
      unawaited(_loadSubtitleTracks());
    } else {
      unawaited(_loadLocalSubtitles());
    }
    unawaited(_fetchTitleLogo());

    // Start rotating messages while scraping.
    _startMessageRotation();
    _startScrapeProgressSimulation();
  }

  // ── Global quality override handler ─────────────────────────────────────────
  void _onGlobalQualityOverride() {
    if (!mounted || widget.isOffline) return;
    final globalLabel = AppSettingsService.instance.effectiveStreamQuality;
    if (globalLabel.toLowerCase() != 'auto' &&
        globalLabel != _selectedQuality) {
      _changeQuality(globalLabel);
    }
  }

  void _initSkipIntro() {
    final tmdbId = int.tryParse(widget.tmdbId ?? '');
    if (tmdbId == null) return;
    SkipIntroDetector.instance.start(
      tmdbId: tmdbId,
      mediaType: widget.mediaType,
      season: _currentSeason,
      episode: _currentEpisode,
      onSegmentFound: () {
        if (mounted) setState(() {});
      },
    );
  }

  void _rescaleAll() {
    if (!mounted) return;
    _controlsFade.duration = AppMotion.scaled(context, AppMotion.medium);
    _drawerSlide.duration = AppMotion.scaled(context, AppMotion.medium);
    _toastFade.duration = AppMotion.scaled(context, AppMotion.standard);
    _nextEpisodeShimmer?.duration = AppMotion.scaled(context, AppMotion.slow);
  }

  @override
  void dispose() {
    AutoOrientation.fullAutoMode();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    try { _wyzieSubs.dispose(); } catch (_) {}
    _connectivitySub?.cancel();
    _nextEpisodeTimer?.cancel();
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _isPlayingNotifier.dispose();
    _isBufferingNotifier.dispose();
    _sliderDragNotifier.dispose();
    _bufferedNotifier.dispose();
    _messageTimer?.cancel();

    WidgetsBinding.instance.removeObserver(this);
    _stopProgressSaveTimer();
    _stopSubtitleTimer();
    try {
      _saveProgress(force: true);
    } catch (_) {}

    unawaited(_restoreSystemBrightnessAndVolumeUi());

    AppSettingsService.instance.removeListener(_onAppSettingsChanged);
    WakelockPlus.disable();
    _controller?.removeListener(_videoPlayerListener);
    _hideTimer?.cancel();
    _toastTimer?.cancel();
    _seekFlashTimer?.cancel();
    _controlsFade.dispose();
    _drawerSlide.dispose();
    _toastFade.dispose();
    _nextEpisodeShimmer?.dispose();
    _nextEpisodeTimer?.cancel();
    _controller?.dispose();

    // Auto-purge encrypted cache for this media on exit.
    final mediaKey = _cacheKey();
    EncryptedCacheManager.instance.purgeMedia(mediaKey);
    AdaptiveQualityEngine.instance.detachSettingsListener();
    SkipIntroDetector.instance.detachSettingsListener();
    SkipIntroDetector.instance.stop();

    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rescaleAll();
  }

  void _startScrapeProgressSimulation() {
    // Simulate progress during scraping to show user it's working
    Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!mounted || !_isScraping) {
        timer.cancel();
        return;
      }
      setState(() {
        _scrapeProgress = (_scrapeProgress + 0.02).clamp(0.0, 0.95);
      });
    });
  }

  void _startMessageRotation() {
    _messageTimer?.cancel();
    _scrapingStartedAt = DateTime.now();
    _shownMessageIndices.clear();
    _usingLongMessagePool = false;
    _currentMessageIndex = 0;
    _messageTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final elapsed =
          DateTime.now().difference(_scrapingStartedAt ?? DateTime.now());
      final wantsLongPool = elapsed > const Duration(seconds: 8);
      final pool =
          wantsLongPool ? _loadingMessagesLong : _loadingMessagesShort;

      // Switching pools (short → long once the wait drags on) resets the
      // no-repeat tracker so the long pool gets its own fresh shuffle
      // instead of inheriting indices from a different list.
      if (wantsLongPool != _usingLongMessagePool) {
        _usingLongMessagePool = wantsLongPool;
        _shownMessageIndices.clear();
      }

      if (_shownMessageIndices.length >= pool.length) {
        _shownMessageIndices.clear();
      }
      final remaining = List<int>.generate(pool.length, (i) => i)
          .where((i) => !_shownMessageIndices.contains(i))
          .toList();
      final next = remaining[Random().nextInt(remaining.length)];
      _shownMessageIndices.add(next);

      setState(() {
        _currentMessageIndex = next;
      });
    });
  }

  String get _currentLoadingMessage {
    final pool =
        _usingLongMessagePool ? _loadingMessagesLong : _loadingMessagesShort;
    if (_currentMessageIndex >= pool.length) return pool.first;
    return pool[_currentMessageIndex];
  }

  // ─── Error message simplification ──────────────────────────────────────────
  String _simplifyError(String technical) {
    final lower = technical.toLowerCase();
    if (lower.contains('exoplayer') ||
        lower.contains('source error') ||
        lower.contains('decoder') ||
        lower.contains('timeout')) {
      return 'Playback is taking too long. Please try another server or check your connection.';
    }
    if (lower.contains('403') || lower.contains('forbidden')) {
      return 'The stream is not accessible. Try a different server.';
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return 'The video could not be found. It may have been removed.';
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return 'Network error. Please check your internet connection.';
    }
    // Fallback: generic friendly message.
    return 'Something went wrong. Please try again or switch servers.';
  }

  // ─── Scraper callback ──────────────────────────────────────────────────────
  void _onScraperExtracted(ExtractedStreamData data) {
    setState(() {
      _scrapeProgress = 1.0; // Complete!
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _scrapeProgress = 0.0);
    });
    if (!mounted) return;
    final media = data.allStreams;
    if (media.isEmpty) {
      setState(() {
    _isScraping = false;
        _scrapeProgress = 0.0;
        _hasError = true;
        _errorMessage = 'No playable stream found. Try switching servers.';
      });
      return;
    }
    // Use the already parsed list (real resolutions from master playlist).
    _hlsVariants = media
        .map((s) => HlsVariant(
              resolution: s.height != null
                  ? '${s.height}p'
                  : s.format.toUpperCase(),
              url: s.url,
            ))
        .toList();
    _applyPreferredQualityFromVariants();
    final playUrl = _resolveInitialQualityUrl(data.bestUrl);
    _activeStreamUrl = playUrl;
    _masterStreamUrl = data.bestUrl;
    setState(() {
      _isScraping = false;
    });
    // Cache the result.
    _ResolvedStreamCache.put(
      _ResolvedStreamCache.buildKey(
        tmdbId: widget.tmdbId,
        mediaType: widget.mediaType,
        season: _currentSeason,
        episode: _currentEpisode,
        server: _selectedServer,
      ),
      streamUrl: data.bestUrl,
      referer: _streamReferer,
      variants: _hlsVariants,
    );
    _initializePlayer(playUrl);
  }

  // ─── Existing methods (unchanged except for error messages) ──────────────

  Future<void> _fetchTitleLogo() async {
    final id = int.tryParse(widget.tmdbId ?? '');
    if (id == null) return;
    try {
      final isTv = widget.mediaType.toLowerCase() == 'tv';
      final logo = await TmdbDetailsService().getMovieLogo(id, isTv: isTv);
      if (!mounted || logo == null || logo.isEmpty) return;
      setState(() => _titleLogoUrl = logo);
    } catch (e) {
      debugPrint('Player title logo: $e');
    }
  }

  Future<void> _loadLocalSubtitles() async {
    if (!widget.isOffline) return;

    final candidates = <String>[];
    final explicit = widget.localSubtitlePath?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      candidates.add(explicit);
    }

    final videoPath = _resolveLocalFilePath(widget.streamUrl);
    if (videoPath.isNotEmpty) {
      final base = videoPath.replaceAll(RegExp(r'\.[^.]+$'), '');
      candidates.add('$base.srt');
      candidates.add('$base.vtt');
    }

    final seen = <String>{};
    for (final path in candidates) {
      if (!seen.add(path)) continue;
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        final body = await SubtitleCacheHelper.readSubtitleFile(path) ??
            await file.readAsString();
        if (body.trim().isEmpty) continue;
        _parseSrtOrVtt(body);
        if (_parsedSubtitles.isEmpty) continue;
        if (mounted) {
          setState(() => _subtitlesEnabled = true);
          _startSubtitleTimer();
        }
        debugPrint(
          'Offline subtitles loaded from $path '
          '(${_parsedSubtitles.length} cues)',
        );
        return;
      } catch (e) {
        debugPrint('Offline subtitle candidate failed ($path): $e');
      }
    }
  }

  void _onAppSettingsChanged() {
    if (!mounted) return;
    final next = AppSettingsService.instance.effectiveStreamQuality;
    if (next != _selectedQuality && !widget.isOffline) {
      _changeQuality(next);
    }
    final subs = AppSettingsService.instance.subtitlesByDefault;
    if (subs != _subtitlesEnabled) {
      setState(() => _subtitlesEnabled = subs);
    }
  }

  /// One-shot connectivity check before the very first load, so a viewer
  /// starting on cellular never gets handed 'Auto' at full 1080p/4K on the
  /// first request — the request itself asks for the capped height.
  Future<void> _maybeWarnCellularThenLoad() async {
    if (!widget.isOffline) {
      try {
        final result = await Connectivity().checkConnectivity();
        _isCellular = result.contains(ConnectivityResult.mobile);
      } catch (_) {
        _isCellular = false;
      }
      _applyCellularCapIfNeeded(reason: 'initial load');
    }
    await _loadStream(_activeStreamUrl);
  }

  /// Live wifi↔cellular handoff detection during playback. Mirrors what
  /// streaming apps like YouTube do: dropping onto cellular mid-playback
  /// while quality is 'Auto' triggers an immediate downgrade instead of
  /// silently continuing to pull a 1080p/4K stream over mobile data.
  void _initConnectivityMonitoring() {
    if (widget.isOffline) return;
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      final nowCellular = results.contains(ConnectivityResult.mobile) &&
          !results.contains(ConnectivityResult.wifi);
      if (nowCellular == _isCellular) return;
      _isCellular = nowCellular;
      if (!mounted || !_isInitialized) return;
      if (nowCellular) {
        _applyCellularCapIfNeeded(reason: 'wifi→cellular handoff');
      }
      // Switching back to wifi mid-playback intentionally does NOT auto
      // upgrade quality — that would cause an unexpected rebuffer the
      // viewer never asked for. They can pick a higher quality manually.
    });
  }

  /// Downgrades an 'Auto' selection to [_cellularAutoCapHeight] when on
  /// cellular and a higher-resolution variant is currently active. A user
  /// who has *explicitly* picked a quality (not 'Auto') is left alone —
  /// this only caps the adaptive default, same as YouTube's own behavior.
  void _applyCellularCapIfNeeded({required String reason}) {
    if (!_isCellular) return;
    if (_selectedQuality.toLowerCase() != 'auto') return;
    final activeHeight = _parseHeight(_selectedQuality) ??
        (_hlsVariants.isEmpty ? null : _cellularAutoCapHeight + 1);
    if (activeHeight != null && activeHeight <= _cellularAutoCapHeight) return;
    debugPrint(
      'Cellular quality cap ($reason): capping Auto at '
      '${_cellularAutoCapHeight}p',
    );
    if (_isInitialized) {
      unawaited(_changeQuality('${_cellularAutoCapHeight}p'));
    } else {
      // Not initialized yet (this is the pre-first-load path) — just seed
      // the label so the very first request already asks for the capped
      // height instead of loading full quality and immediately switching.
      _selectedQuality = '${_cellularAutoCapHeight}p';
    }
  }

  int? _parseHeight(String label) {
    if (label.isEmpty) return null;
    final lower = label.toLowerCase().trim();
    if (lower.contains('4k') ||
        lower.contains('uhd') ||
        lower.contains('2160')) {
      return 2160;
    }
    if (lower.contains('1440') || lower.contains('2k')) return 1440;
    final matches = RegExp(r'(\d{3,4})').allMatches(lower).toList();
    if (matches.isEmpty) return null;
    for (final m in matches.reversed) {
      final h = int.tryParse(m.group(1)!);
      if (h == null) continue;
      if (h == 2160 ||
          h == 1440 ||
          h == 1080 ||
          h == 720 ||
          h == 480 ||
          h == 360 ||
          h == 240) {
        return h;
      }
    }
    return int.tryParse(matches.last.group(1)!);
  }

  void _applyPreferredQualityFromVariants() {
    if (widget.isOffline || _hlsVariants.isEmpty) return;

    final preferredLabel = (_selectedQuality.isNotEmpty &&
            _selectedQuality.toLowerCase() != 'auto')
        ? _selectedQuality
        : AppSettingsService.instance.effectiveStreamQuality;
    final preferredHeight = _parseHeight(preferredLabel);
    final maxH = AppSettingsService.instance.maxStreamHeight;

    if ((preferredLabel.toLowerCase() == 'auto' || preferredHeight == null) &&
        maxH == null) {
      // ── Throughput-based ABR: start at 480p, let engine scale up ───────────
      // 360p is not supported by any provider — floor is 480p.
      final engine = AdaptiveQualityEngine.instance;
      final label = engine.resolveQuality(_hlsVariants);
      _selectedQuality = label;
      return;
    }

    final candidates = <HlsVariant>[];
    for (final v in _hlsVariants) {
      final h = _parseHeight(v.resolution);
      if (h == null || h <= 0) continue;
      if (maxH != null && h > maxH) continue;
      candidates.add(v);
    }
    if (candidates.isEmpty) {
      candidates.addAll(_hlsVariants);
    }

    HlsVariant? match;
    if (preferredHeight != null && candidates.isNotEmpty) {
      final exact = candidates
          .where((v) => _parseHeight(v.resolution) == preferredHeight)
          .toList();
      if (exact.isNotEmpty) {
        match = exact.first;
      } else {
        final under = candidates.where((v) {
          final h = _parseHeight(v.resolution) ?? 0;
          return h <= preferredHeight;
        }).toList();
        if (under.isNotEmpty) {
          under.sort((a, b) {
            final ha = _parseHeight(a.resolution) ?? 0;
            final hb = _parseHeight(b.resolution) ?? 0;
            return hb.compareTo(ha);
          });
          match = under.first;
        } else {
          candidates.sort((a, b) {
            final ha = _parseHeight(a.resolution) ?? 0;
            final hb = _parseHeight(b.resolution) ?? 0;
            final da = (ha - preferredHeight).abs();
            final db = (hb - preferredHeight).abs();
            if (da != db) return da.compareTo(db);
            return hb.compareTo(ha);
          });
          match = candidates.first;
        }
      }
    } else if (maxH != null && candidates.isNotEmpty) {
      candidates.sort((a, b) {
        final ha = _parseHeight(a.resolution) ?? 0;
        final hb = _parseHeight(b.resolution) ?? 0;
        return hb.compareTo(ha);
      });
      match = candidates.first;
    }

    if (match != null && match.url.isNotEmpty) {
      _selectedQuality = match.resolution;
    } else {
      _selectedQuality = preferredLabel;
    }
  }

  String _resolveInitialQualityUrl(String fallbackUrl) {
    if (widget.isOffline || _hlsVariants.isEmpty) return fallbackUrl;

    final preferredLabel = (_selectedQuality.isNotEmpty &&
            _selectedQuality.toLowerCase() != 'auto')
        ? _selectedQuality
        : AppSettingsService.instance.effectiveStreamQuality;

    if (preferredLabel.isEmpty || preferredLabel.toLowerCase() == 'auto') {
      return fallbackUrl;
    }

    final preferredHeight = _parseHeight(preferredLabel);
    if (preferredHeight == null) return fallbackUrl;

    final maxH = AppSettingsService.instance.maxStreamHeight;
    final candidates = _hlsVariants.where((v) {
      final h = _parseHeight(v.resolution);
      if (h == null || h <= 0) return false;
      if (maxH != null && h > maxH) return false;
      return true;
    }).toList();
    if (candidates.isEmpty) return fallbackUrl;

    final exact = candidates
        .where((v) => _parseHeight(v.resolution) == preferredHeight)
        .toList();
    if (exact.isNotEmpty) return exact.first.url;

    final under = candidates.where((v) {
      final h = _parseHeight(v.resolution) ?? 0;
      return h <= preferredHeight;
    }).toList();
    if (under.isNotEmpty) {
      under.sort((a, b) {
        final ha = _parseHeight(a.resolution) ?? 0;
        final hb = _parseHeight(b.resolution) ?? 0;
        return hb.compareTo(ha);
      });
      return under.first.url;
    }

    candidates.sort((a, b) {
      final ha = _parseHeight(a.resolution) ?? 0;
      final hb = _parseHeight(b.resolution) ?? 0;
      final da = (ha - preferredHeight).abs();
      final db = (hb - preferredHeight).abs();
      if (da != db) return da.compareTo(db);
      return hb.compareTo(ha);
    });
    return candidates.first.url;
  }

  String _resolveLocalFilePath(String value) {
    var raw = value.trim();

    if (raw.length >= 2 &&
        ((raw.startsWith('"') && raw.endsWith('"')) ||
            (raw.startsWith("'") && raw.endsWith("'")))) {
      raw = raw.substring(1, raw.length - 1).trim();
    }

    if (raw.isEmpty) return '';

    if (raw.toLowerCase().startsWith('file://')) {
      try {
        return Uri.parse(raw).toFilePath(windows: Platform.isWindows);
      } catch (e) {
        debugPrint('Offline file URI parse error: $e');
        return '';
      }
    }

    return raw;
  }

  /// Stable cache key for the current media item. Used by EncryptedCacheManager.
  String _cacheKey() {
    return '$widget.tmdbId${widget.mediaType}_s${_currentSeason}_e$_currentEpisode';
  }

  bool _isEmbedUrl(String url) {
    if (widget.isOffline) return false;
    return !url.contains('.m3u8') &&
        !url.contains('.mp4') &&
        !url.contains('.webm');
  }

  void _initServerList() {
    if (widget.isOffline) {
      _masterStreamUrl = widget.streamUrl.trim();
      _activeStreamUrl = _masterStreamUrl;
      _streamReferer = null;
      _selectedServer = 'Offline';
      return;
    }

    final rawServers = (widget.servers != null && widget.servers!.isNotEmpty)
        ? widget.servers!
        : [
    {
        "id": "rive",
        "name": "Rive",
        "url": "https://rivestream.live",
        "movie_url_pattern": "{url}/watch?type=movie&id={tmdbId}",
        "tv_url_pattern": "{url}/watch?type=tv&id={tmdbId}&season={season}&episode={episode}",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 45
    },
    {
        "id": "vidlink",
        "name": "VidLink",
        "url": "https://vidlink.pro",
        "movie_url_pattern": "{url}/movie/{tmdbId}?autoplay=true",
        "tv_url_pattern": "{url}/tv/{tmdbId}/{season}/{episode}?autoplay=true",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 45
    },
    {
        "id": "vidsrc",
        "name": "VixSrc",
        "url": "https://vidsrc.sbs",
        "movie_url_pattern": "{url}/embed/movie/{tmdbId}?autoplay=true",
        "tv_url_pattern": "{url}/embed/tv/{tmdbId}/{season}/{episode}?autoplay=true",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 45
    },
    {
        "id": "cinejoy",
        "name": "MoviesJoy",
        "url": "https://moviesjoy.to",
        "movie_url_pattern": "{url}/watch/{type}/{tmdbId}",
        "tv_url_pattern": "{url}/watch/{type}/{tmdbId}/{season}/{episode}",
        "movie_alias": "movie",
        "tv_alias": "tv",
        "scraper_timeout_seconds": 30
    },
    {
        "id": "vidfast",
        "name": "VidFast",
        "url": "https://vidfast.vc",
        "movie_url_pattern": null,
        "tv_url_pattern": null,
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 30
    },
    {
        "id": "cinesrc",
        "name": "CineSrc",
        "url": "https://cinesrc.st/embed",
        "movie_url_pattern": null,
        "tv_url_pattern": null,
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 30
    },
    {
        "id": "cineplay",
        "name": "Fmovies",
        "url": "https://fmovies.co",
        "movie_url_pattern": "{url}/watch/{tmdbId}",
        "tv_url_pattern": "{url}/watch/{tmdbId}/{season}/{episode}",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 30
    },
    {
        "id": "screenscape",
        "name": "ScreenScape",
        "url": "https://screenscape.me",
        "movie_url_pattern": "{url}/embed?tmdb={tmdbId}&type=movie&autoplay=true",
        "tv_url_pattern": "{url}/embed?tmdb={tmdbId}&type=tv&s={season}&e={episode}&autoplay=true",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 45
    },
    {
        "id": "videasy",
        "name": "Videasy",
        "url": "https://player.videasy.to",
        "movie_url_pattern": "{url}/{type}/{tmdbId}",
        "tv_url_pattern": "{url}/{type}/{tmdbId}/{season}/{episode}",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 30
    },
    {
        "id": "2embed",
        "name": "2Embed",
        "url": "https://2embed.cc",
        "movie_url_pattern": "{url}/movie/{tmdbId}?autoplay=true",
        "tv_url_pattern": "{url}/tv/{tmdbId}/{season}/{episode}?autoplay=true",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 45
    },
    {
        "id": "embedsu",
        "name": "Embed.su",
        "url": "https://embed.su",
        "movie_url_pattern": "{url}/embed/movie/{tmdbId}?autoplay=true",
        "tv_url_pattern": "{url}/embed/tv/{tmdbId}/{season}/{episode}?autoplay=true",
        "movie_alias": null,
        "tv_alias": null,
        "scraper_timeout_seconds": 45
    }
];

    _serverList = rawServers.map((server) {
      final Map<String, dynamic> s = Map.from(server);
      final id = (s['id'] ?? '').toString().toLowerCase();

      if (s['movie_url_pattern'] == null ||
          (s['movie_url_pattern'] as String).isEmpty) {
        if (id == 'vidfast') {
          s['movie_url_pattern'] = '{url}/movie/{tmdbId}?autoPlay=true';
        } else if (id == 'cinesrc' || id == 'embedsu') {
          s['movie_url_pattern'] = '{url}/embed/movie/{tmdbId}?autoPlay=true';
        } else if (id == '2embed') {
          s['movie_url_pattern'] = '{url}/movie/{tmdbId}?autoPlay=true';
        } else if (id == 'videasy') {
          s['movie_url_pattern'] = '{url}/movie/{tmdbId}?autoPlay=true';
        } else {
          s['movie_url_pattern'] = '{url}/{type}/{tmdbId}';
        }
      }
      if (s['tv_url_pattern'] == null ||
          (s['tv_url_pattern'] as String).isEmpty) {
        if (id == 'vidfast') {
          s['tv_url_pattern'] =
              '{url}/tv/{tmdbId}/{season}/{episode}?autoPlay=true';
        } else if (id == 'cinesrc' || id == 'embedsu') {
          s['tv_url_pattern'] =
              '{url}/embed/tv/{tmdbId}/{season}/{episode}?autoPlay=true';
        } else if (id == '2embed') {
          s['tv_url_pattern'] =
              '{url}/tv/{tmdbId}/{season}/{episode}?autoPlay=true';
        } else if (id == 'videasy') {
          s['tv_url_pattern'] =
              '{url}/tv/{tmdbId}/{season}/{episode}?autoPlay=true';
        } else {
          s['tv_url_pattern'] = '{url}/{type}/{tmdbId}/{season}/{episode}';
        }
      }
      return s;
    }).toList();

    final explicitName = widget.initialServerName?.trim();
    if (explicitName != null && explicitName.isNotEmpty) {
      final byName = _serverList.where(
        (s) => (s['name'] ?? '').toString() == explicitName,
      );
      final byId = _serverList.where(
        (s) => (s['id'] ?? '').toString().toLowerCase() ==
            explicitName.toLowerCase(),
      );
      if (byName.isNotEmpty) {
        _selectedServer = byName.first['name'] as String;
      } else if (byId.isNotEmpty) {
        _selectedServer = byId.first['name'] as String? ?? explicitName;
      } else {
        _selectedServer = explicitName;
      }
    } else {
      _selectedServer = _serverList.isNotEmpty
          ? (_serverList.first['name'] as String? ?? 'Server 1')
          : 'Server 1';
    }

    final incoming = widget.streamUrl.trim();
    if (incoming.isNotEmpty) {
      _masterStreamUrl = incoming;
      _activeStreamUrl = incoming;
      _streamReferer = incoming;
    } else {
      final active = _serverList.firstWhere(
        (s) => (s['name'] ?? '') == _selectedServer,
        orElse: () => _serverList.isNotEmpty ? _serverList.first : {},
      );
      final resolved = _resolveServerUrl(active);
      _masterStreamUrl = resolved.isNotEmpty ? resolved : widget.streamUrl;
      _activeStreamUrl = _masterStreamUrl;
      _streamReferer = _masterStreamUrl;
    }
  }

  String _resolveServerUrl(Map<String, dynamic> server) {
    if (widget.isOffline) return widget.streamUrl.trim();

    final isMovie = widget.mediaType.toLowerCase() == 'movie';
    final pattern = isMovie
        ? server['movie_url_pattern'] as String?
        : server['tv_url_pattern'] as String?;

    if (pattern != null && pattern.isNotEmpty) {
      return pattern
          .replaceAll('{url}', server['url'] ?? '')
          .replaceAll('{type}', isMovie ? 'movie' : 'tv')
          .replaceAll('{tmdbId}', widget.tmdbId ?? '')
          .replaceAll('{season}', _currentSeason.toString())
          .replaceAll('{episode}', _currentEpisode.toString());
    }

    return server['url'] ?? widget.streamUrl;
  }

  // Modified _loadStream to use the scraper callback properly
  Future<void> _loadStream(String url, {Duration? startPosition}) async {
    if (!mounted) return;

    // Reset high-speed failover state for fresh stream attempt
    _serverAttemptCount = 0;
    _fastFailoverMode = false;

    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = 'No stream URL available.';
        _isScraping = false;
      });
      return;
    }

    setState(() {
      _hasError = false;
      _errorMessage = '';
    });

    if (widget.isOffline) {
      _masterStreamUrl = widget.streamUrl.trim();
      _activeStreamUrl = _masterStreamUrl;
      setState(() => _isScraping = false);
      await _initializePlayer(_masterStreamUrl, startPosition: startPosition);
      return;
    }

    if (_isEmbedUrl(url)) {
      final cacheKey = _ResolvedStreamCache.buildKey(
        tmdbId: widget.tmdbId,
        mediaType: widget.mediaType,
        season: _currentSeason,
        episode: _currentEpisode,
        server: _selectedServer,
      );
      final cached = _ResolvedStreamCache.get(cacheKey);
      if (cached != null) {
        _streamReferer = cached.referer ?? url;
        _masterStreamUrl = cached.streamUrl;
        _hlsVariants = cached.variants;
        _applyPreferredQualityFromVariants();
        final playUrl = _resolveInitialQualityUrl(cached.streamUrl);
        _activeStreamUrl = playUrl;
        setState(() => _isScraping = false);
        await _initializePlayer(playUrl, startPosition: startPosition);
        return;
      }
      _streamReferer = url;
      setState(() {
        _isScraping = true;
        _isInitialized = false;
      });
    } else {
      setState(() => _isScraping = false);
      if (!widget.isOffline) {
        await _fetchHlsVariants(url);
      }
      String playUrl = url;
      if (_hlsVariants.isNotEmpty &&
          _selectedQuality.isNotEmpty &&
          _selectedQuality.toLowerCase() != 'auto') {
        final preferredHeight = _parseHeight(_selectedQuality);
        if (preferredHeight != null) {
          HlsVariant? match;
          final candidates = _hlsVariants.where((v) {
            final h = _parseHeight(v.resolution);
            return h != null && h > 0;
          }).toList();
          final exact = candidates
              .where((v) => _parseHeight(v.resolution) == preferredHeight)
              .toList();
          if (exact.isNotEmpty) {
            match = exact.first;
          } else {
            final under = candidates.where((v) {
              final h = _parseHeight(v.resolution)!;
              return h <= preferredHeight;
            }).toList();
            if (under.isNotEmpty) {
              under.sort((a, b) =>
                  (_parseHeight(b.resolution) ?? 0)
                      .compareTo(_parseHeight(a.resolution) ?? 0));
              match = under.first;
            }
          }
          if (match != null && match.url.isNotEmpty) {
            playUrl = match.url;
            _activeStreamUrl = playUrl;
          }
        }
      }
      await _initializePlayer(playUrl, startPosition: startPosition);
    }
  }

  Future<void> _changeEpisode(int season, int episode) async {
    if (widget.isOffline) return;
    if (_currentSeason == season && _currentEpisode == episode) return;

    final preservedQuality = _selectedQuality;

    setState(() {
      _currentSeason = season;
      _currentEpisode = episode;
      _isInitialized = false;
      _hlsVariants.clear();
      _showNextEpisodeCard = false;
      _nextEpisodeCancelled = false;
      _nextEpisodeProgress = 0.0;
    });
    _nextEpisodeTimer?.cancel();
    _closeDrawer();

    // When an add-on stream is active, prefer resolving the new episode
    // through the same add-ons; fall back to the normal server scrape when
    // the add-ons have nothing for this episode.
    if (_isAddonSourceActive) {
      final started = await _tryPlayAddonForEpisode(season, episode);
      if (started) return;
      final fallback = _serverList.isNotEmpty ? _serverList.first : null;
      _selectedServer =
          (fallback?['name'] as String?) ?? _selectedServer;
    }

    final activeServer = _serverList.firstWhere(
      (s) => s['name'] == _selectedServer,
      orElse: () => _serverList.first,
    );

    final resolvedUrl = _resolveServerUrl(activeServer);
    _masterStreamUrl = resolvedUrl;
    _activeStreamUrl = resolvedUrl;
    _streamReferer = resolvedUrl;

    await _disposeController();

    if (!widget.isOffline) {
      _fetchWisoSubtitles();
      unawaited(_loadSubtitleTracks());
    }

    if (resolvedUrl.trim().isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = 'No stream URL available for this episode.';
        _isScraping = false;
      });
      return;
    }

    await _loadStream(resolvedUrl);

    if (mounted &&
        preservedQuality.isNotEmpty &&
        preservedQuality.toLowerCase() != 'auto' &&
        _hlsVariants.isNotEmpty) {
      await _changeQuality(preservedQuality, force: true);
    }
  }

  Future<void> _initBrightnessAndVolume() async {
    try {
      FlutterVolumeController.updateShowSystemUI(false);
      _brightnessLevel = await ScreenBrightness().application;
      _volumeLevel = await FlutterVolumeController.getVolume() ?? 0.5;
    } catch (_) {}
  }

  Future<void> _fetchHlsVariants(String url) async {
    if (!url.contains('.m3u8')) return;

    try {
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': '*/*',
      };
      final refStr = _streamReferer ?? _masterStreamUrl;
      try {
        final ref = Uri.parse(refStr);
        if (ref.hasScheme && ref.host.isNotEmpty) {
          headers['Referer'] = '${ref.scheme}://${ref.host}/';
          headers['Origin'] = '${ref.scheme}://${ref.host}';
        }
      } catch (_) {}
      if (widget.headers != null) headers.addAll(widget.headers!);
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final lines = response.body.split('\n');
        List<HlsVariant> variants = [];

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('#EXT-X-STREAM-INF')) {
            String resolution = 'Unknown';
            final resMatch = RegExp(r'RESOLUTION=(\d+x\d+)').firstMatch(line);
            if (resMatch != null) {
              final dimensions = resMatch.group(1)!;
              final height = dimensions.split('x').last;
              resolution = '${height}p';
            }

            if (i + 1 < lines.length) {
              String variantUrl = lines[i + 1].trim();
              if (!variantUrl.startsWith('http')) {
                final Uri baseUri = Uri.parse(url);
                variantUrl = baseUri.resolve(variantUrl).toString();
              }
              variants
                  .add(HlsVariant(resolution: resolution, url: variantUrl));
            }
          }
        }

        if (mounted) {
          if (variants.isNotEmpty) {
            setState(() => _hlsVariants = variants);
          }
          _applyPreferredQualityFromVariants();
        }
      }
    } catch (e) {
      debugPrint('HLS Variant Parse Error: $e');
    }
  }

  bool _isPlayableMediaUrl(String url) {
    if (widget.isOffline) return url.trim().isNotEmpty;
    final lower = url.toLowerCase();
    if (lower.startsWith('blob:') || lower.startsWith('data:')) return false;
    if (_isEmbedUrl(url)) return false;
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.webm') ||
        lower.contains('/hls/') ||
        lower.contains('playlist') ||
        lower.contains('googlevideo');
  }

  Future<void> _disposeController() async {
    _stopSubtitleTimer();
    try {
      await _saveProgress(force: true);
    } catch (_) {}

    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      c.removeListener(_videoPlayerListener);
      await c.pause();
      await c.dispose();
    } catch (_) {}
  }

  Future<void> _initializePlayer(String url,
      {Duration? startPosition}) async {
    // ── Reset bandwidth tracking for new stream ───────────────────────────────
    _bwFirstSampleRecorded = false;
    _bwLastBytes = 0;
    _bwBufferStart = null;
    AdaptiveQualityEngine.instance.reset();

    if (!_isPlayableMediaUrl(url)) {
      if (mounted) {
        setState(() {
          _isScraping = false;
          _isInitialized = false;
          _hasError = true;
          _errorMessage = widget.isOffline
              ? 'The downloaded video file could not be found or played.'
              : 'No direct stream URL found. Please switch to another server.';
        });
      }
      return;
    }

    try {
      await _disposeController();

      if (widget.isOffline) {
        final filePath = _resolveLocalFilePath(widget.streamUrl);
        if (filePath.isEmpty) {
          throw const FileSystemException('The local video path is empty.');
        }

        final parsed = Uri.tryParse(filePath);
        final looksLikeRemoteUrl = parsed != null &&
            parsed.hasScheme &&
            (parsed.scheme == 'http' || parsed.scheme == 'https');
        if (looksLikeRemoteUrl) {
          throw const FileSystemException(
            'Offline playback received a remote URL instead of a local file.',
          );
        }

        final file = File(filePath);
        if (!await file.exists()) {
          throw FileSystemException(
            'The local video file does not exist.',
            filePath,
          );
        }

        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
          throw FileSystemException(
            'The local video file is empty or invalid.',
            filePath,
          );
        }

        debugPrint('Offline player: opening local file: $filePath');

        _controller = VideoPlayerController.file(
          file,
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
        );
      } else {
        final uri = Uri.parse(url);
        final Map<String, String> requestHeaders = {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': '*/*',
          'Accept-Language': 'en-US,en;q=0.9',
          'Connection': 'keep-alive',
        };

        final refererCandidate =
            _streamReferer ?? widget.headers?['Referer'] ?? _masterStreamUrl;
        try {
          final ref = Uri.parse(refererCandidate);
          if (ref.hasScheme && ref.host.isNotEmpty) {
            requestHeaders['Referer'] = '${ref.scheme}://${ref.host}/';
            requestHeaders['Origin'] = '${ref.scheme}://${ref.host}';
          }
        } catch (_) {
          try {
            final media = Uri.parse(url);
            if (media.hasScheme && media.host.isNotEmpty) {
              requestHeaders['Referer'] = '${media.scheme}://${media.host}/';
              requestHeaders['Origin'] = '${media.scheme}://${media.host}';
            }
          } catch (_) {}
        }

        if (widget.headers != null) {
          requestHeaders.addAll(widget.headers!);
        }

        _controller = VideoPlayerController.networkUrl(
          uri,
          httpHeaders: requestHeaders,
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
        );
      }

      await _controller!.initialize();
      _renderedAspect = _controller!.value.aspectRatio;

      try {
        final speedLabel = AppSettingsService.instance.playbackSpeed;
        final speed = double.tryParse(speedLabel.replaceAll('x', '')) ?? 1.0;
        await _controller!.setPlaybackSpeed(speed.clamp(0.5, 2.0));
      } catch (_) {}

      Duration? resumeAt = startPosition;
      final bool isExplicitSeek =
          startPosition != null && startPosition > Duration.zero;

      if (!isExplicitSeek &&
          !_hasAppliedInitialSeek &&
          widget.initialPositionSeconds != null &&
          widget.initialPositionSeconds! > 0 &&
          AppSettingsService.instance.rememberPosition) {
        resumeAt = Duration(seconds: widget.initialPositionSeconds!);
        _hasAppliedInitialSeek = true;
      }

      if (resumeAt != null && resumeAt > Duration.zero) {
        if (isExplicitSeek || AppSettingsService.instance.rememberPosition) {
          final dur = _controller!.value.duration;
          final clamped = dur > Duration.zero && resumeAt >= dur
              ? dur - const Duration(seconds: 3)
              : resumeAt;
          if (clamped > Duration.zero) {
            await _controller!.seekTo(clamped);
          }
        }
      }

      _controller?.addListener(_videoPlayerListener);
      await _controller?.play();
      _wasPlaying = true;
      _bwFirstSampleRecorded = true; // Start measuring bandwidth now
      _bwBufferStart = null; // Reset on new play
      _bwLastBytes = 0;
      _isPlayingNotifier.value = true;
      if (_controller != null && _controller!.value.isInitialized) {
        _positionNotifier.value = _controller!.value.position;
        _durationNotifier.value = _controller!.value.duration;
        _bufferedNotifier.value = _bufferedEndFor(_controller!.value);
      }
      _startProgressSaveTimer();
      _startSubtitleTimer();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
          _isScraping = false;
        });
        _startHideTimer();
      }
    } catch (e, stackTrace) {
      debugPrint('Initialize player error: $e');
      debugPrint('$stackTrace');

      if (mounted) {
        setState(() {
          _isInitialized = false;
          _isScraping = false;
          _hasError = true;
          // Simplified user‑friendly error
          _errorMessage = widget.isOffline
              ? 'The local video could not be found or played. '
                  'The downloaded file may be missing or corrupted.'
              : _simplifyError(e.toString());
        });
      }

      if (widget.isOffline) {
        await _disposeController();
      }
    }
  }

  Future<void> _changeQuality(String qualityLabel, {bool force = false}) async {
    if (widget.isOffline) return;
    if (_isSwitchingQuality && !force) return;

    String targetUrl = _masterStreamUrl;

    if (qualityLabel.toLowerCase() != 'auto' && _hlsVariants.isNotEmpty) {
      final preferredHeight = _parseHeight(qualityLabel);
      HlsVariant? matchingVariant;

      if (preferredHeight != null) {
        final exact = _hlsVariants
            .where((v) => _parseHeight(v.resolution) == preferredHeight)
            .toList();
        if (exact.isNotEmpty) {
          matchingVariant = exact.first;
        } else {
          final under = _hlsVariants.where((v) {
            final h = _parseHeight(v.resolution);
            return h != null && h <= preferredHeight;
          }).toList();
          if (under.isNotEmpty) {
            under.sort((a, b) {
              final ha = _parseHeight(a.resolution) ?? 0;
              final hb = _parseHeight(b.resolution) ?? 0;
              return hb.compareTo(ha);
            });
            matchingVariant = under.first;
          } else {
            final candidates = List<HlsVariant>.from(_hlsVariants);
            candidates.sort((a, b) {
              final ha = _parseHeight(a.resolution) ?? 0;
              final hb = _parseHeight(b.resolution) ?? 0;
              final da = (ha - preferredHeight).abs();
              final db = (hb - preferredHeight).abs();
              if (da != db) return da.compareTo(db);
              return hb.compareTo(ha);
            });
            matchingVariant = candidates.first;
          }
        }
      }

      if (matchingVariant == null || matchingVariant.url.isEmpty) {
        final needle = qualityLabel.toLowerCase().replaceAll('p', '');
        matchingVariant = _hlsVariants.cast<HlsVariant?>().firstWhere(
              (v) => v!.resolution.toLowerCase().contains(needle),
              orElse: () => null,
            );
      }

      if (matchingVariant != null && matchingVariant.url.isNotEmpty) {
        targetUrl = matchingVariant.url;
      }
    } else if (qualityLabel.toLowerCase() == 'auto') {
      // ── Throughput-based ABR: use engine to pick best variant ─────────────────
      if (_hlsVariants.isNotEmpty) {
        targetUrl = AdaptiveQualityEngine.instance.tryUpgrade(_hlsVariants);
      } else {
        targetUrl = _masterStreamUrl;
      }
    }

    if (!force &&
        _selectedQuality == qualityLabel &&
        _activeStreamUrl == targetUrl) {
      return;
    }

    final oldController = _controller;
    final currentPosition = oldController?.value.position ?? Duration.zero;
    final wasPlaying = oldController?.value.isPlaying ?? true;
    final oldSpeed = oldController?.value.playbackSpeed ?? 1.0;

    setState(() {
      _selectedQuality = qualityLabel;
      _activeStreamUrl = targetUrl;
      _isSwitchingQuality = true;
      _hasError = false;
    });
    _closeDrawer();

    VideoPlayerController? newController;
    try {
      newController = await _createNetworkController(targetUrl);
      await newController.initialize();

      try {
        await newController.setPlaybackSpeed(oldSpeed.clamp(0.5, 2.0));
      } catch (_) {}

      if (currentPosition > Duration.zero) {
        final dur = newController.value.duration;
        var seekTo = currentPosition;
        if (dur > Duration.zero && seekTo > dur) {
          seekTo = dur;
        }
        try {
          await newController.seekTo(seekTo);
        } catch (_) {}
      }

      if (wasPlaying) {
        try {
          await newController.play();
        } catch (_) {}
      }

      if (!mounted) {
        try {
          await newController.dispose();
        } catch (_) {}
        return;
      }

      oldController?.removeListener(_videoPlayerListener);
      newController.addListener(_videoPlayerListener);

      setState(() {
        _controller = newController;
        _isInitialized = true;
        _isSwitchingQuality = false;
        _hasError = false;
        _errorMessage = '';
      });

      _positionNotifier.value = newController.value.position;
      _durationNotifier.value = newController.value.duration;
      _isPlayingNotifier.value = newController.value.isPlaying;
      _isBufferingNotifier.value = newController.value.isBuffering;
      _bufferedNotifier.value = _bufferedEndFor(newController.value);

      if (_subtitlesEnabled && _parsedSubtitles.isNotEmpty) {
        _startSubtitleTimer();
      }
      _startHideTimer();
      if (wasPlaying) {
        _startProgressSaveTimer();
      }

      if (oldController != null) {
        final outgoing = oldController;
        Future<void>(() async {
          try {
            await outgoing.pause();
          } catch (_) {}
          try {
            await outgoing.dispose();
          } catch (_) {}
        });
      }
    } catch (e, st) {
      debugPrint('Seamless quality switch failed: $e\n$st');
      try {
        await newController?.dispose();
      } catch (_) {}

      if (!mounted) return;

      setState(() => _isSwitchingQuality = false);
      try {
        await _disposeController();
        if (mounted) setState(() => _isInitialized = false);
        await _initializePlayer(targetUrl, startPosition: currentPosition);
        if (mounted &&
            wasPlaying &&
            _controller != null &&
            _controller!.value.isInitialized) {
          try {
            await _controller!.play();
          } catch (_) {}
        }
      } catch (e2) {
        debugPrint('Quality fallback re-init failed: $e2');
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Could not switch quality. Try another server or quality.';
            _isInitialized = false;
          });
        }
      }
    }
  }

  Future<VideoPlayerController> _createNetworkController(String url) async {
    final uri = Uri.parse(url);
    final Map<String, String> requestHeaders = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Connection': 'keep-alive',
    };

    final refererCandidate =
        _streamReferer ?? widget.headers?['Referer'] ?? _masterStreamUrl;
    try {
      final ref = Uri.parse(refererCandidate);
      if (ref.hasScheme && ref.host.isNotEmpty) {
        requestHeaders['Referer'] = '${ref.scheme}://${ref.host}/';
        requestHeaders['Origin'] = '${ref.scheme}://${ref.host}';
      }
    } catch (_) {
      try {
        final media = Uri.parse(url);
        if (media.hasScheme && media.host.isNotEmpty) {
          requestHeaders['Referer'] = '${media.scheme}://${media.host}/';
          requestHeaders['Origin'] = '${media.scheme}://${media.host}';
        }
      } catch (_) {}
    }

    if (widget.headers != null) {
      requestHeaders.addAll(widget.headers!);
    }

    return VideoPlayerController.networkUrl(
      uri,
      httpHeaders: requestHeaders,
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
        allowBackgroundPlayback: false,
      ),
    );
  }

  void _onDoubleTapSeek(TapDownDetails details) {
    if (_isLocked || _controller == null || !_isInitialized) return;

    final width = MediaQuery.of(context).size.width;
    final dx = details.globalPosition.dx;
    final isRight = dx > width * 0.5;
    final delta = isRight
        ? const Duration(seconds: 10)
        : const Duration(seconds: -10);

    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;
    var target = pos + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (dur > Duration.zero && target > dur) target = dur;

    _controller!.seekTo(target);
    HapticFeedback.lightImpact();
    _updateSubtitleText();

    _seekFlashTimer?.cancel();
    setState(() {
      _showSeekFlash = true;
      _seekFlashForward = isRight;
    });
    _seekFlashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showSeekFlash = false);
    });

    _startHideTimer();
  }

  // ── Installed Add-ons as stream sources ───────────────────────────────────

  Future<void> _refreshAddonSources() async {
    if (widget.isOffline) return;
    if (_addonSourcesChecked) return;
    final epoch = ++_addonSourcesEpoch;
    _addonSourcesChecked = true;

    final manifests = AddonRepository.instance.addons
        .where((a) => a.isActive && a.manifest != null)
        .map((a) => a.manifest!)
        .toList(growable: false);
    if (manifests.isEmpty) {
      _anyAddonsInstalled = false;
      _addonSources = const [];
      return;
    }
    _anyAddonsInstalled = true;
    if (mounted) setState(() => _addonSourcesLoading = true);
    try {
      final sources = await resolveAddonStreamsForContent(
        manifests: manifests,
        tmdbId: widget.tmdbId,
        imdbId: widget.imdbId,
        mediaType: widget.mediaType,
        season: _currentSeason,
        episode: _currentEpisode,
      );
      if (!mounted || epoch != _addonSourcesEpoch) return;
      setState(() => _addonSources = sources);
    } catch (_) {
      if (!mounted || epoch != _addonSourcesEpoch) return;
      setState(() => _addonSources = const []);
    } finally {
      if (mounted && epoch == _addonSourcesEpoch) {
        setState(() => _addonSourcesLoading = false);
      }
    }
  }

  AddonPlaybackSource? _bestAddonSource() =>
      bestPlayableSource(_addonSources);

  /// Starts playback of an add-on stream (direct HLS/MP4/WebM, or a torrent
  /// resolved through debrid into a direct HTTPS link). External-only
  /// entries open in an external app.
  Future<void> _startAddonPlayback(
    AddonPlaybackSource source, {
    Duration? startPosition,
  }) async {
    if (widget.isOffline) return;
    String? directUrl = source.stream.playableDirectUrl;
    if (directUrl == null || directUrl.isEmpty) {
      final external = source.stream.openExternalUrl;
      if (external != null) {
        await launchUrl(Uri.parse(external),
            mode: LaunchMode.externalApplication);
        return;
      }
      // Torrent stream → debrid instant resolve into a direct link.
      if (source.stream.isTorrent) {
        final isTv = widget.mediaType.toLowerCase() == 'tv';
        final result = await resolveAddonStreamTorrent(
          stream: source.stream,
          season: isTv ? _currentSeason : null,
          episode: isTv ? _currentEpisode : null,
        );
        if (!mounted) return;
        if (result.success && result.url != null) {
          directUrl = result.url;
        } else {
          setState(() {
            _hasError = true;
            _errorMessage = result.failureMessage;
            _isScraping = false;
          });
          return;
        }
      } else {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage =
                'This stream has no playable link.';
            _isScraping = false;
          });
        }
        return;
      }
    }
    if (directUrl == null || directUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Could not resolve a playable link for this stream.';
          _isScraping = false;
        });
      }
      return;
    }
    final direct = directUrl;
    final currentPosition = startPosition ??
        (_controller?.value.position ?? Duration.zero);

    await _disposeController();
    _serverAttemptCount = 0;
    _fastFailoverMode = false;

    if (mounted) {
      setState(() {
        _isInitialized = false;
        _hasError = false;
        _errorMessage = '';
        _selectedServer = '$_addonServerPrefix${source.addonName}';
        _masterStreamUrl = direct;
        _activeStreamUrl = direct;
        _streamReferer = null;
        _selectedQuality = AppSettingsService.instance.effectiveStreamQuality;
        _hlsVariants.clear();
      });
    }
    _closeDrawer();

    await _loadStream(direct, startPosition: currentPosition);
    // Attach subtitles advertised by the add-on stream.
    if (mounted) await _installAddonSubtitles(source);
  }

  /// Re-resolves add-on streams for [season]/[episode] and starts the best
  /// match. Returns true when an add-on stream started.
  Future<bool> _tryPlayAddonForEpisode(int season, int episode) async {
    // Invalidate any in-flight fetch for the previous episode.
    _addonSourcesEpoch++;
    _addonSourcesChecked = false;
    await _refreshAddonSources();
    if (!mounted) return false;
    final best = _bestAddonSource();
    if (best == null) return false;
    await _startAddonPlayback(best);
    return true;
  }

  Future<void> _switchServer(Map<String, dynamic> server) async {
    if (widget.isOffline) return;
    final serverName = server['name'] ?? 'Unknown';
    if (_selectedServer == serverName) return;

    final resolvedUrl = _resolveServerUrl(server);
    final currentPosition = _controller?.value.position ?? Duration.zero;

    await _disposeController();

    // Reset high-speed failover state for the new server
    _serverAttemptCount = 0;
    _fastFailoverMode = false;

    setState(() {
      _isInitialized = false;
      _hasError = false;
      _selectedServer = serverName;
      _masterStreamUrl = resolvedUrl;
      _activeStreamUrl = resolvedUrl;
      _streamReferer = resolvedUrl;
      _selectedQuality = AppSettingsService.instance.effectiveStreamQuality;
      _hlsVariants.clear();
    });
    _closeDrawer();

    await _loadStream(resolvedUrl, startPosition: currentPosition);
  }

  // ─── Continue Watching ──────────────────────────────────────────────────────

  Movie? _movieForProgress() {
    if (widget.movie != null) {
      final m = widget.movie!;
      final hasPoster = (m.posterPath).toString().trim().isNotEmpty;
      if (hasPoster) return m;
    }
    if (_hydratedProgressMovie != null) return _hydratedProgressMovie;

    final id = int.tryParse(widget.tmdbId ?? '');
    if (id == null) return null;

    unawaited(_hydrateProgressMovie(id));

    try {
      return Movie.fromJson({
        'id': id,
        'title': widget.title,
        'name': widget.title,
        'poster_path': widget.movie?.posterPath,
        'backdrop_path': widget.movie?.backdropPath,
        'overview': widget.movie?.overview ?? '',
        'vote_average': widget.movie?.voteAverage ?? 0.0,
        'release_date': widget.movie?.releaseDate ?? '',
        'media_type': widget.mediaType,
      });
    } catch (_) {
      return null;
    }
  }

  Future<void> _hydrateProgressMovie(int id) async {
    if (_hydratedProgressMovie != null) return;
    try {
      final isTv = widget.mediaType.toLowerCase() == 'tv';
      final data = await TmdbDetailsService().getMovieDetails(id, isTv: isTv);
      if (data == null) return;
      final movie = Movie.fromJson({
        'id': id,
        'title': data['title'] ?? data['name'] ?? widget.title,
        'name': data['name'] ?? data['title'] ?? widget.title,
        'poster_path': data['poster_path'],
        'backdrop_path': data['backdrop_path'],
        'overview': data['overview'] ?? '',
        'vote_average': data['vote_average'] ?? 0,
        'release_date':
            data['release_date'] ?? data['first_air_date'] ?? '',
        'media_type': widget.mediaType,
      });
      _hydratedProgressMovie = movie;
      if (mounted &&
          (movie.posterPath).toString().trim().isNotEmpty) {
        await _saveProgress(force: true);
      }
    } catch (e) {
      debugPrint('Progress movie hydrate: $e');
    }
  }

  Future<void> _saveProgress({bool force = false}) async {
    if (!AppSettingsService.instance.rememberPosition && !force) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    final movie = _movieForProgress();
    if (movie == null) return;

    final position = c.value.position.inSeconds;
    final duration = c.value.duration.inSeconds;
    if (duration <= 0) return;

    final ratio = position / duration;
    if (position < 30 && ratio <= 0.95) return;

    try {
      await ContinueWatchingService.upsert(
        movie: movie,
        position: position,
        duration: duration,
        season: widget.mediaType.toLowerCase() == 'tv' ? _currentSeason : null,
        episode: widget.mediaType.toLowerCase() == 'tv' ? _currentEpisode : null,
        mediaType: widget.mediaType.toLowerCase() == 'tv' ? 'tv' : 'movie',
      );
    } catch (e) {
      debugPrint('ContinueWatching upsert failed: $e');
    }
  }

  void _startProgressSaveTimer() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final c = _controller;
      if (c != null && c.value.isInitialized && c.value.isPlaying) {
        _saveProgress();
      }
    });
  }

  void _stopProgressSaveTimer() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = null;
  }

  /// End of whichever buffered range currently *covers the playhead* —
  /// i.e. "how far can I play/seek forward from right now without
  /// rebuffering". This intentionally does NOT track the historical
  /// farthest-ever-buffered point: the platform player (ExoPlayer/
  /// AVPlayer) can evict earlier segments from its rolling buffer, so a
  /// stale "buffered far ahead" bar would lie to the user — they'd seek
  /// back into what looks buffered and hit a real network re-fetch
  /// anyway. Returning `pos` when no range covers it (a gap under the
  /// playhead) correctly shows "nothing buffered ahead right now",
  /// matching real YouTube behavior instead of a bar that never shrinks.
  Duration _bufferedEndFor(VideoPlayerValue value) {
    final pos = value.position;
    var coveringEnd = pos;
    for (final range in value.buffered) {
      if (range.start <= pos && range.end >= pos && range.end > coveringEnd) {
        coveringEnd = range.end;
      }
    }
    return coveringEnd;
  }

  void _videoPlayerListener() {
    if (!mounted || _controller == null) return;

    final value = _controller!.value;
    if (value.hasError) {
      _stopSubtitleTimer();
      if (!_hasError || _isInitialized) {
        final detail = value.errorDescription?.trim() ?? '';
        debugPrint('VideoPlayer error: $detail');
        setState(() {
          _isInitialized = false;
          _isScraping = false;
          _hasError = true;
          _errorMessage = widget.isOffline
              ? 'The downloaded video could not be played. '
                  'The local file may be missing, incomplete, or use an unsupported video format.'
              : _simplifyError(detail);
        });
      }
      return;
    }

    if (!value.isInitialized) return;

    final aspect = value.aspectRatio;
    if (aspect > 0 && (aspect - _renderedAspect).abs() > 0.001) {
      _renderedAspect = aspect;
      if (mounted) setState(() {});
    }

    if (_wasPlaying && !value.isPlaying) {
      _saveProgress(force: true);
      _updateSubtitleText();
    }
    if (!_wasPlaying && value.isPlaying) {
      _startSubtitleTimer();
    }
    _wasPlaying = value.isPlaying;

    if (_subtitlesEnabled && _parsedSubtitles.isNotEmpty) {
      _updateSubtitleText();
    }

    final pos = value.position;
    final dur = value.duration;
    if (_positionNotifier.value != pos) {
      _positionNotifier.value = pos;
    }
    if (_durationNotifier.value != dur) {
      _durationNotifier.value = dur;
    }
    if (_isPlayingNotifier.value != value.isPlaying) {
      _isPlayingNotifier.value = value.isPlaying;
    }
    if (_isBufferingNotifier.value != value.isBuffering) {
      _isBufferingNotifier.value = value.isBuffering;
    }

    final coveringBuffered = _bufferedEndFor(value);
    if (_bufferedNotifier.value != coveringBuffered) {
      _bufferedNotifier.value = coveringBuffered;
    }

    // ── Bandwidth measurement: record throughput sample ─────────────────────────
    _recordBandwidthSample(value);

    // ── Skip intro: tick the detector with current position ───────────────────
    SkipIntroDetector.instance.tick(pos);
    final seg = SkipIntroDetector.instance.activeSegment;
    if (seg != _skipIntroSegment) {
      _skipIntroSegment = seg;
      _skipIntroVisible = seg != null;
    }

    // ── Auto-purge encrypted cache when video completes ─────────────────────────
    if (value.position >= dur - const Duration(milliseconds: 500) && dur > Duration.zero) {
      final mediaKey = _cacheKey();
      EncryptedCacheManager.instance.purgeMedia(mediaKey);
    }

    _maybeShowNextEpisodePrompt(pos, dur);
  }

  void _recordBandwidthSample(VideoPlayerValue value) {
    if (!_bwFirstSampleRecorded) return;

    final now = DateTime.now();
    final buffered = value.buffered;
    if (buffered.isEmpty) return;

    int totalBufferedMs = 0;
    for (final range in buffered) {
      totalBufferedMs += (range.end - range.start).inMilliseconds;
    }

    if (value.isBuffering && _bwBufferStart == null) {
      _bwBufferStart = now;
      _bwLastBytes = totalBufferedMs;
    }

    if (!value.isBuffering && _bwBufferStart != null) {
      final elapsed = now.difference(_bwBufferStart!);
      final bytesDelta = (totalBufferedMs - _bwLastBytes).abs();
      if (elapsed.inMilliseconds >= 200 && bytesDelta > 0) {
        AdaptiveQualityEngine.instance.recordSample(
          bytes: bytesDelta,
          elapsed: elapsed,
        );
      }
      _bwBufferStart = null;
    }
  }

  void _maybeShowNextEpisodePrompt(Duration position, Duration duration) {
    if (widget.isOffline) return;
    if (widget.mediaType.toLowerCase() != 'tv') return;
    if (_nextEpisodeCancelled || _showNextEpisodeCard) return;
    if (duration <= Duration.zero) return;
    final remaining = duration - position;
    if (remaining > const Duration(seconds: 60) || remaining <= Duration.zero) {
      return;
    }
    _showNextEpisodeCard = true;
    _nextEpisodeProgress = 0.0;
    _nextEpisodeTimer?.cancel();

    const totalMs = 10000;
    const tickMs = 50;
    var elapsed = 0;
    _nextEpisodeTimer = Timer.periodic(const Duration(milliseconds: tickMs), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      elapsed += tickMs;
      final p = (elapsed / totalMs).clamp(0.0, 1.0);
      if (elapsed >= totalMs) {
        t.cancel();
        _goToNextEpisode();
        return;
      }
      setState(() {
        _nextEpisodeProgress = p;
      });
    });
    if (mounted) setState(() {});
  }

  void _cancelNextEpisodePrompt() {
    _nextEpisodeTimer?.cancel();
    _nextEpisodeTimer = null;
    _nextEpisodeCancelled = true;
    if (mounted) {
      setState(() => _showNextEpisodeCard = false);
    }
  }

  Future<void> _goToNextEpisode() async {
    _nextEpisodeTimer?.cancel();
    _nextEpisodeTimer = null;
    if (!mounted) return;
    setState(() => _showNextEpisodeCard = false);
    await _changeEpisode(_currentSeason, _currentEpisode + 1);
  }

  Future<void> _goToPreviousEpisode() async {
    _nextEpisodeTimer?.cancel();
    _nextEpisodeTimer = null;
    if (!mounted) return;
    setState(() => _showNextEpisodeCard = false);
    if (_currentEpisode <= 1) {
      return;
    }
    await _changeEpisode(_currentSeason, _currentEpisode - 1);
  }

  void _updateSubtitleText() {
    if (!mounted) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    if (!_subtitlesEnabled || _parsedSubtitles.isEmpty) {
      if (_currentSubtitleText.isNotEmpty) {
        setState(() => _currentSubtitleText = '');
      }
      return;
    }

    final position = c.value.position;
    final offsetUs = (_subtitleOffsetSeconds * 1000000).round();
    final effectiveUs = position.inMicroseconds - offsetUs;
    const toleranceUs = 40000;

    String next = '';
    int activeIndex = -1;

    int lo = 0;
    int hi = _parsedSubtitles.length - 1;
    int candidate = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final startUs = _parsedSubtitles[mid].start.inMicroseconds;
      if (startUs - toleranceUs <= effectiveUs) {
        candidate = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }

    if (candidate >= 0) {
      for (int i = candidate;
          i < _parsedSubtitles.length && i <= candidate + 3;
          i++) {
        final sub = _parsedSubtitles[i];
        final startUs = sub.start.inMicroseconds;
        final endUs = sub.end.inMicroseconds;
        if (effectiveUs >= startUs - toleranceUs &&
            effectiveUs <= endUs + toleranceUs) {
          next = sub.text;
          activeIndex = i;
          break;
        }
        if (startUs - toleranceUs > effectiveUs) break;
      }
    }

    if (activeIndex != _lastSubtitleCueIndex) {
      _lastSubtitleCueIndex = activeIndex;
      debugPrint(
        'Subtitle cue  pos=${position.inMilliseconds}ms  '
        'effective=${(effectiveUs / 1000).round()}ms  '
        'offset=${_subtitleOffsetSeconds.toStringAsFixed(1)}s  '
        'cue=$activeIndex/${_parsedSubtitles.length}  '
        'text="${next.length > 40 ? '${next.substring(0, 40)}…' : next}"',
      );
    }

    if (next != _currentSubtitleText) {
      setState(() => _currentSubtitleText = next);
    }
  }

  void _startSubtitleTimer() {
    _subtitleTimer?.cancel();
    if (!_subtitlesEnabled || _parsedSubtitles.isEmpty) return;

    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return;
    }

    _subtitleTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) {
        _stopSubtitleTimer();
        return;
      }
      final ctrl = _controller;
      if (ctrl == null || !ctrl.value.isInitialized) {
        _stopSubtitleTimer();
        return;
      }
      _updateSubtitleText();
    });
    _updateSubtitleText();
  }

  void _stopSubtitleTimer() {
    _subtitleTimer?.cancel();
    _subtitleTimer = null;
  }

  Future<void> _loadSubtitleTracks() async {
    if (widget.isOffline || _loadingTracks) return;
    _loadingTracks = true;
    try {
      final isTv = widget.mediaType.toLowerCase() == 'tv';
      final tracks = await _wyzieSubs.search(
        tmdbId: widget.tmdbId,
        imdbId: widget.imdbId,
        season: isTv ? _currentSeason : null,
        episode: isTv ? _currentEpisode : null,
      );
      if (!mounted) return;
      setState(() {
        _availableTracks = [...tracks, ..._addonSubtitleTracks];
      });
      debugPrint(
          'WyzieSubtitleService: ${tracks.length} tracks available'
          '+${_addonSubtitleTracks.length} from add-ons');
    } catch (e) {
      debugPrint('WyzieSubtitleService list error: $e');
    } finally {
      _loadingTracks = false;
    }
  }

  // ── Add-on subtitles ──────────────────────────────────────────────────────
  /// Turns an add-on stream's `subtitles` into tracks and installs them into
  /// the player's picker, auto-applying the best match (preferred language,
  /// else English, else the first track) — mirroring Wyzie auto-loading.
  Future<void> _installAddonSubtitles(AddonPlaybackSource source) async {
    if (!mounted || widget.isOffline) return;
    final merged = _tracksFromAddonSubtitles(source.stream.subtitles);
    setState(() {
      _addonSubtitleTracks = merged;
      _availableTracks = [
        ..._availableTracks.where((t) => !t.id.startsWith('addon-')),
        ...merged,
      ];
    });
    if (merged.isEmpty) return;

    final iso = WyzieSubtitleService.toIsoLanguage(_selectedLanguage);
    final short = iso.split('-').first.toLowerCase();
    WyzieSubtitleTrack? pick;
    for (final t in merged) {
      if (t.languageCode == iso || t.languageCode == short) {
        pick = t;
        break;
      }
    }
    if (pick == null) {
      for (final t in merged) {
        if (t.languageCode == 'en') {
          pick = t;
          break;
        }
      }
    }
    pick ??= merged.first;
    await _applySubtitleTrack(pick);
  }

  List<WyzieSubtitleTrack> _tracksFromAddonSubtitles(
    List<AddonSubtitle> subtitles,
  ) {
    final tracks = <WyzieSubtitleTrack>[];
    for (var i = 0; i < subtitles.length; i++) {
      final sub = subtitles[i];
      final lang = (sub.lang ?? 'und').trim().toLowerCase();
      final hasName = sub.name != null && sub.name!.trim().isNotEmpty;
      tracks.add(WyzieSubtitleTrack(
        id: 'addon-$i-${lang.isEmpty ? 'und' : lang}',
        url: sub.url,
        languageCode: lang.isEmpty ? 'und' : lang,
        displayLanguage:
            hasName ? sub.name!.trim() : _languageDisplayName(lang),
        format: _subtitleFormatFromUrl(sub.url),
        source: 'Add-on',
        isHearingImpaired: false,
      ));
    }
    return tracks;
  }

  String _subtitleFormatFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.vtt') || lower.contains('webvtt')) return 'vtt';
    if (lower.endsWith('.ass')) return 'ass';
    if (lower.endsWith('.ssa')) return 'ssa';
    if (lower.endsWith('.smi')) return 'smi';
    return 'srt';
  }

  String _languageDisplayName(String code) {
    const names = {
      'en': 'English',
      'es': 'Spanish',
      'fr': 'French',
      'pt': 'Portuguese',
      'de': 'German',
      'it': 'Italian',
      'ar': 'Arabic',
      'hi': 'Hindi',
      'ja': 'Japanese',
      'ko': 'Korean',
      'zh': 'Chinese',
      'ru': 'Russian',
      'tr': 'Turkish',
      'nl': 'Dutch',
      'pl': 'Polish',
      'sv': 'Swedish',
      'da': 'Danish',
      'fi': 'Finnish',
    };
    return names[code] ?? code.toUpperCase();
  }

  Future<void> _applySubtitleTrack(WyzieSubtitleTrack? track) async {
    if (track == null) {
      if (!mounted) return;
      setState(() {
        _subtitlesEnabled = false;
        _currentSubtitleText = '';
        _selectedTrackId = 'off';
        _parsedSubtitles = [];
      });
      _stopSubtitleTimer();
      return;
    }

    final saved = await _wyzieSubs.downloadTrackToFile(track);
    if (!mounted) return;
    if (saved == null || saved.body.trim().isEmpty) {
      debugPrint('WyzieSubtitleService: empty body for ${track.displayLanguage}');
      return;
    }

    _parseSrtOrVtt(saved.body);
    setState(() {
      _subtitlesEnabled = true;
      _selectedLanguage = track.displayLanguage;
      _selectedTrackId = track.id;
    });
    if (_controller?.value.isPlaying == true) {
      _startSubtitleTimer();
    }
    debugPrint(
      'Applied track ${track.displayLanguage}: ${_parsedSubtitles.length} cues'
      '${saved.localPath != null ? ' @ ${saved.localPath}' : ''}',
    );
  }

  Future<void> _openSubtitleTrackPicker() async {
    if (widget.isOffline) {
      _openDrawer(ActiveDrawer.subtitles);
      return;
    }
    if (_availableTracks.isEmpty) {
      await _loadSubtitleTracks();
    }
    if (!mounted) return;

    if (_availableTracks.isEmpty) {
      _openDrawer(ActiveDrawer.subtitles);
      return;
    }

    final chosen = await SubtitleTrackPicker.show(
      context,
      tracks: _availableTracks,
      selectedId: _selectedTrackId,
    );
    if (!mounted) return;
    await _applySubtitleTrack(chosen);
  }

  Future<void> _fetchWisoSubtitles() async {
    final tmdb = widget.tmdbId?.trim();
    final hasImdb =
        widget.imdbId != null && widget.imdbId!.trim().isNotEmpty;
    if ((tmdb == null || tmdb.isEmpty || tmdb == '0') && !hasImdb) {
      debugPrint('Subtitle Fetch Cancelled: No valid TMDB/IMDb ID.');
      return;
    }

    try {
      final isTv = widget.mediaType.toLowerCase() == 'tv';
      final isoLang = WyzieSubtitleService.toIsoLanguage(_selectedLanguage);
      debugPrint(
        'Wyzie search (cached): lang="$_selectedLanguage" → iso="$isoLang" '
        'tmdb=$tmdb imdb=${widget.imdbId}',
      );

      var saved = await _wyzieSubs.fetchPreferred(
        tmdbId: (tmdb != null && tmdb.isNotEmpty && tmdb != '0') ? tmdb : null,
        imdbId: hasImdb ? widget.imdbId : null,
        season: isTv ? _currentSeason : null,
        episode: isTv ? _currentEpisode : null,
        language: isoLang,
      );

      if (saved == null && isoLang.isNotEmpty && isoLang != 'off') {
        saved = await _wyzieSubs.fetchPreferred(
          tmdbId: (tmdb != null && tmdb.isNotEmpty && tmdb != '0') ? tmdb : null,
          imdbId: hasImdb ? widget.imdbId : null,
          season: isTv ? _currentSeason : null,
          episode: isTv ? _currentEpisode : null,
        );
      }

      if (!mounted) return;

      if (saved != null) {
        final result = saved;
        _parseSrtOrVtt(result.body);
        setState(() {
          _subtitlesEnabled = true;
          _selectedLanguage = result.track.displayLanguage;
          _selectedTrackId = result.track.id;
        });
        if (_controller?.value.isPlaying == true) {
          _startSubtitleTimer();
        }
        debugPrint(
          'Subtitles loaded: ${_parsedSubtitles.length} cues '
          '(${result.track.displayLanguage})'
          '${result.localPath != null ? ' @ ${result.localPath}' : ''}',
        );
      } else {
        debugPrint(
          'Wyzie: no usable subtitle for language $_selectedLanguage ($isoLang)',
        );
        setState(() {
          _parsedSubtitles = [];
          _currentSubtitleText = '';
        });
        _stopSubtitleTimer();
      }
    } catch (e) {
      debugPrint('Wyzie Subtitle Fetch Error: $e');
      if (mounted) {
        setState(() {
          _parsedSubtitles = [];
          _currentSubtitleText = '';
        });
        _stopSubtitleTimer();
      }
    }
  }

  void _parseSrtOrVtt(String content) {
    final items = <SubtitleItem>[];
    var text = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (text.startsWith('\uFEFF')) text = text.substring(1);

    final lines = text.split('\n');
    final regExp = RegExp(
      r'(?:(\d{1,2}):)?(\d{1,2}):(\d{2})[,.](\d{1,3})\s*-->\s*(?:(\d{1,2}):)?(\d{1,2}):(\d{2})[,.](\d{1,3})',
    );

    Duration parseTime(String? h, String m, String s, String ms) {
      final msPadded = ms.padRight(3, '0').substring(0, 3);
      return Duration(
        hours: int.tryParse(h ?? '0') ?? 0,
        minutes: int.parse(m),
        seconds: int.parse(s),
        milliseconds: int.parse(msPadded),
      );
    }

    String cleanCueText(String raw) {
      return raw
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\{[^}]+\}'), '')
          .replaceAll(RegExp(r'&nbsp;', caseSensitive: false), ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .trim();
    }

    for (int i = 0; i < lines.length; i++) {
      final match = regExp.firstMatch(lines[i]);
      if (match == null) continue;

      final start = parseTime(match[1], match[2]!, match[3]!, match[4]!);
      final end = parseTime(match[5], match[6]!, match[7]!, match[8]!);

      final textBuffer = StringBuffer();
      int j = i + 1;
      while (j < lines.length && lines[j].trim().isNotEmpty) {
        final line = lines[j].trim();
        if (!RegExp(r'^\d+$').hasMatch(line) && !line.startsWith('NOTE')) {
          textBuffer.writeln(line);
        }
        j++;
      }

      final cue = cleanCueText(textBuffer.toString());
      if (cue.isNotEmpty && end > start) {
        items.add(SubtitleItem(start: start, end: end, text: cue));
      }
    }

    items.sort((a, b) => a.start.compareTo(b.start));
    debugPrint('Parsed ${items.length} subtitle cues from SRT/VTT');

    if (mounted) {
      setState(() {
        _parsedSubtitles = items;
        _currentSubtitleText = '';
      });
      if (_subtitlesEnabled &&
          items.isNotEmpty &&
          _controller != null &&
          _controller!.value.isInitialized) {
        _startSubtitleTimer();
      }
    }
  }

  void _handleVerticalDrag(DragUpdateDetails details, double screenWidth) {
    if (_isLocked) return;
    final isLeft = details.globalPosition.dx < (screenWidth / 2);

    if (isLeft) {
      _brightnessLevel =
          (_brightnessLevel - (details.delta.dy / 300)).clamp(0.1, 1.0);
      ScreenBrightness().setApplicationScreenBrightness(_brightnessLevel);
      _showToast(icon: 'brightness', value: _brightnessLevel);
    } else {
      _volumeLevel =
          (_volumeLevel - (details.delta.dy / 300)).clamp(0.0, 1.0);

      final now = DateTime.now();
      if (_lastVolumeUpdate == null ||
          now.difference(_lastVolumeUpdate!).inMilliseconds > 60) {
        FlutterVolumeController.setVolume(_volumeLevel);
        _lastVolumeUpdate = now;
      }
      _showToast(icon: 'volume', value: _volumeLevel);
    }
  }

  void _showToast({required String icon, required double value}) {
    _toastTimer?.cancel();
    setState(() {
      _showGestureToast = true;
      _toastIcon = icon;
    });
    _toastFade.forward(from: 0);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        _toastFade.reverse().then((_) {
          if (mounted) setState(() => _showGestureToast = false);
        });
      }
    });
  }

  void _setAspectRatio(String value) {
    setState(() {
      _selectedAspectRatio = value;
      switch (value) {
        case 'Fit':
          _customAspectRatio = null;
          break;
        case 'Fill':
          _customAspectRatio = null;
          break;
        case '16:9':
          _customAspectRatio = 16 / 9;
          break;
        case '4:3':
          _customAspectRatio = 4 / 3;
          break;
        case 'Auto':
        default:
          _customAspectRatio = null;
          break;
      }
    });
    _closeDrawer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  BoxFit _getBoxFit() {
    if (_selectedAspectRatio == 'Fill') return BoxFit.cover;
    return BoxFit.contain;
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted &&
          (_controller?.value.isPlaying ?? false) &&
          _activeDrawer == ActiveDrawer.none &&
          !_isLocked) {
        _controlsFade.reverse().then((_) {
          if (mounted) setState(() => _showControls = false);
        });
      }
    });
  }

  void _toggleControls() {
    if (_showGestureToast) {
      _toastTimer?.cancel();
      _toastFade.reverse().then((_) {
        if (mounted) setState(() => _showGestureToast = false);
      });
      return;
    }

    if (_isLocked) return;
    HapticFeedback.selectionClick();

    if (_activeDrawer != ActiveDrawer.none) {
      _closeDrawer();
      return;
    }

    if (_showControls) {
      _controlsFade.reverse().then((_) {
        if (mounted) setState(() => _showControls = false);
      });
    } else {
      setState(() => _showControls = true);
      _controlsFade.forward();
      _startHideTimer();
    }
  }

  void _openDrawer(ActiveDrawer drawer) {
    if (widget.isOffline &&
        (drawer == ActiveDrawer.settings ||
            drawer == ActiveDrawer.quality ||
            drawer == ActiveDrawer.servers ||
            drawer == ActiveDrawer.subtitles ||
            drawer == ActiveDrawer.episodes)) {
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _activeDrawer = drawer;
      _showControls = true;
    });
    _controlsFade.forward();
    _drawerSlide.forward(from: 0);
  }

  void _closeDrawer() {
    _drawerSlide.reverse().then((_) {
      if (mounted) setState(() => _activeDrawer = ActiveDrawer.none);
    });
  }

  void _toggleLock() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isLocked = !_isLocked;
      if (_isLocked) {
        _showControls = false;
        _controlsFade.reverse();
        _closeDrawer();
      } else {
        _showControls = true;
        _controlsFade.forward();
        _startHideTimer();
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return hours > 0
        ? "$hours:${twoDigits(minutes)}:${twoDigits(seconds)}"
        : "${twoDigits(minutes)}:${twoDigits(seconds)}";
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _restoreSystemBrightnessAndVolumeUi();
    } else if (state == AppLifecycleState.resumed) {
      _applyPlayerBrightnessAndVolumeUi();
    }
  }

  Future<void> _restoreSystemBrightnessAndVolumeUi() async {
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
    try {
      FlutterVolumeController.updateShowSystemUI(true);
    } catch (_) {}
  }

  Future<void> _applyPlayerBrightnessAndVolumeUi() async {
    try {
      FlutterVolumeController.updateShowSystemUI(false);
    } catch (_) {}
    try {
      await ScreenBrightness().setApplicationScreenBrightness(
        _brightnessLevel.clamp(0.01, 1.0),
      );
    } catch (_) {}
  }

  // ─── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    final controllerAspect = _controller?.value.aspectRatio ?? 0.0;
    final rawAspect = (controllerAspect.isFinite && controllerAspect > 0)
        ? controllerAspect
        : _renderedAspect;
    final videoAspect =
        (rawAspect.isFinite && rawAspect > 0) ? rawAspect : 16 / 9;
    final effectiveAspectRatio = _customAspectRatio ?? videoAspect;
    final isFullBleed = _selectedAspectRatio == 'Fill';
    final shortestSide = screenSize.shortestSide;
    final cinemaInset = isLandscape
        ? 0.0
        : (screenSize.height * (shortestSide < 600 ? 0.115 : 0.15))
            .clamp(48.0, 150.0)
            .toDouble();

    final panelWidth = screenSize.width <= 520
        ? screenSize.width - 20
        : (screenSize.width * 0.42).clamp(340.0, 500.0).toDouble();

    final panelHeight = switch (_activeDrawer) {
      ActiveDrawer.settings => (screenSize.height * 0.54).clamp(290.0, 420.0).toDouble(),
      ActiveDrawer.quality => (screenSize.height * 0.62).clamp(340.0, 470.0).toDouble(),
      ActiveDrawer.servers => (screenSize.height * 0.72).clamp(390.0, 560.0).toDouble(),
      ActiveDrawer.aspectRatio => (screenSize.height * 0.76).clamp(430.0, 620.0).toDouble(),
      ActiveDrawer.subtitles => (screenSize.height * 0.76).clamp(430.0, 620.0).toDouble(),
      ActiveDrawer.episodes => (screenSize.height * 0.82).clamp(460.0, 700.0).toDouble(),
      _ => (screenSize.height * 0.60).clamp(300.0, 500.0).toDouble(),
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: _onDoubleTapSeek,
        onVerticalDragUpdate: (details) =>
            _handleVerticalDrag(details, screenSize.width),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Cinema video surface ─────────────────────────────────────────
            Positioned(
              top: cinemaInset,
              left: 0,
              right: 0,
              bottom: cinemaInset,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ColoredBox(
                  color: Colors.black,
                  child: _isScraping
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            // Hidden scraper that calls _onScraperExtracted
                            SizedBox(
                              width: 1,
                              height: 1,
                              child: Opacity(
                                opacity: 0.01,
                                child: WebViewScraper(
                                  embedUrl: _activeStreamUrl,
                                  mediaType: widget.mediaType,
                                  season: _currentSeason,
                                  episode: _currentEpisode,
                                  timeoutSeconds: _fastFailoverMode ? 7 : 14,
                                  onDataExtracted: _onScraperExtracted,
                                  onError: (err) {
                                    if (!mounted) return;
                                    _serverAttemptCount++;
                                    AdaptiveQualityEngine.instance.onAttemptComplete(
                                      success: false,
                                      serverName: _selectedServer,
                                    );

                                    final idx = _serverList.indexWhere(
                                      (s) => s['name'] == _selectedServer,
                                    );
                                    final hasNextServer =
                                        idx >= 0 && idx + 1 < _serverList.length;

                                    if (_serverAttemptCount < _maxServerAttempts) {
                                      // Retry same server with reduced timeout (fast mode)
                                      _fastFailoverMode = true;
                                      return;
                                    }

                                    _serverAttemptCount = 0;
                                    _fastFailoverMode = false;

                                    if (hasNextServer) {
                                      final next = _serverList[idx + 1];
                                      final nextName =
                                          next['name']?.toString() ?? '';
                                      if (nextName.isNotEmpty) {
                                        unawaited(_switchServer(next));
                                        return;
                                      }
                                    }
                                    setState(() {
                                      _isScraping = false;
                                      _hasError = true;
                                      _errorMessage = err.isNotEmpty
                                          ? _simplifyError(err)
                                          : 'No stream found. Tap the settings icon and try another server.';
                                    });
                                  },
                                ),
                              ),
                            ),
                            // Humorous message + pulse loader
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SatellitePulseLoader(
                                    size: 120, color: _gold),
                                const SizedBox(height: 24),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 32),
                                  child: Text(
                                    _currentLoadingMessage,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : _isInitialized && !_hasError
                          ? (isFullBleed
                              ? SizedBox.expand(
                                  child: FittedBox(
                                    key: ValueKey(
                                      'fb-${_getBoxFit().name}-${videoAspect.toStringAsFixed(4)}',
                                    ),
                                    fit: _getBoxFit(),
                                    clipBehavior: Clip.hardEdge,
                                    child: SizedBox(
                                      width: 1920,
                                      height: 1920 / videoAspect,
                                      child: VideoPlayer(_controller!),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: AspectRatio(
                                    key: ValueKey(
                                      'ar-${effectiveAspectRatio.toStringAsFixed(4)}',
                                    ),
                                    aspectRatio: effectiveAspectRatio,
                                    child: FittedBox(
                                      fit: _getBoxFit(),
                                      clipBehavior: Clip.hardEdge,
                                      child: SizedBox(
                                        width: 1920,
                                        height: 1920 / videoAspect,
                                        child: VideoPlayer(_controller!),
                                      ),
                                    ),
                                  ),
                                ))
                          : _hasError
                              ? _buildErrorView()
                              : const Center(
                                  child: SatellitePulseLoader(
                                      size: 104, color: _gold),
                                ),
                ),
              ),
            ),

            // Scrim while drawer is open
            if (_activeDrawer != ActiveDrawer.none)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeDrawer,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.42),
                  ),
                ),
              ),

            if (_isSwitchingQuality && _isInitialized && !_hasError)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Color(0x1AFFFFFF),
                    valueColor: AlwaysStoppedAnimation<Color>(_gold),
                  ),
                ),
              ),

            if (_isInitialized && !_hasError && !_isSwitchingQuality)
              ValueListenableBuilder<bool>(
                valueListenable: _isBufferingNotifier,
                builder: (context, isBuffering, _) {
                  if (!isBuffering) return const SizedBox.shrink();
                  return const IgnorePointer(
                    child: Center(
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(_gold),
                        ),
                      ),
                    ),
                  );
                },
              ),

            if (_showSeekFlash)
              Positioned(
                left: _seekFlashForward ? null : 40,
                right: _seekFlashForward ? 40 : null,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showSeekFlash ? 1 : 0,
                    duration: AppMotion.scaled(context, AppMotion.fast),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.68),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _seekFlashForward
                                ? Icons.forward_10_rounded
                                : Icons.replay_10_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _seekFlashForward ? '+10s' : '-10s',
                            style: const TextStyle(
                              fontFamily: 'sans-serif',
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            if (_showGestureToast)
              Positioned(
                top: cinemaInset + 18,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: FadeTransition(
                      opacity: _toastOpacity,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.70),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _toastIcon == 'brightness'
                                  ? Icons.brightness_6_rounded
                                  : Icons.volume_up_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 9),
                            SizedBox(
                              width: 96,
                              child: LinearProgressIndicator(
                                value: _toastIcon == 'brightness'
                                    ? _brightnessLevel
                                    : _volumeLevel,
                                minHeight: 3,
                                color: _gold,
                                backgroundColor: Colors.white24,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            if (_showControls && _isInitialized && !_hasError)
              FadeTransition(
                opacity: _controlsOpacity,
                child: Stack(
                  children: [
                    Positioned(
                      top: cinemaInset,
                      left: 0,
                      right: 0,
                      height: 105,
                      // Translucent scrim must never swallow taps meant for
                      // buttons underneath or beside it.
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xB8000000),
                                Colors.transparent,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: cinemaInset,
                      left: 0,
                      right: 0,
                      height: 120,
                      // Translucent scrim must never swallow taps meant for
                      // buttons underneath or beside it.
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Color(0xB8000000),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Paint order (bottom → top): transport controls sit UNDER
                    // the gradient scrims; header/timeline/action bar sit above
                    // them — the scrims shade the center row (instead of the row
                    // floating over bare video), and chrome can never be
                    // covered by it.
                    //
                    // Centering: the video canvas is inset by [cinemaInset] at
                    // top AND bottom, so pad the centering box down by 2× the
                    // inset before Align centers it — the controls then share
                    // the canvas center axis, not the screen center.
                    Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding: EdgeInsets.only(top: 2 * cinemaInset),
                        child: _buildCenterControls(),
                      ),
                    ),
                    _buildTopHeader(),
                    _buildBottomTimeline(),
                    _buildReferenceActionBar(),
                  ],
                ),
              ),

            if (_subtitlesEnabled && _currentSubtitleText.isNotEmpty)
              _buildDraggableSubtitleOverlay(screenSize),
            if (_showNextEpisodeCard) _buildNextEpisodeOverlay(),

            if (_isLocked)
              Positioned(
                top: 15,
                right: 16,
                child: _minimalIconButton(Icons.lock_rounded, _toggleLock),
              ),

            if (_activeDrawer != ActiveDrawer.none)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: screenSize.width <= 520 ? 10 : 14,
                      top: 10,
                      bottom: 10,
                    ),
                    child: SizedBox(
                      width: panelWidth,
                      height: panelHeight.clamp(
                        280.0,
                        screenSize.height - 20.0,
                      ),
                      child: SlideTransition(
                        position: _drawerOffset,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF101010).withValues(alpha: 0.985),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 1,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x99000000),
                                blurRadius: 30,
                                spreadRadius: 1,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: _buildActiveDrawerContent(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Helper widgets ────────────────────────────────────────────────────────

  Widget _buildTopHeader() {
    final pad = MediaQuery.paddingOf(context);
    final metrics = ScreenMetrics.of(context);

    return Positioned(
      top: 8 + pad.top,
      left: metrics.playerChromePadding,
      right: metrics.playerChromePadding,
      child: SizedBox(
        height: metrics.playerControlBarHeight,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Center(child: _buildTmdbTitleMark()),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _minimalIconButton(
                Icons.arrow_back_rounded,
                () => Navigator.of(context).maybePop(),
                semanticLabel: 'Back',
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.mediaType.toLowerCase() == 'tv') ...[
                    _minimalIconButton(
                      Icons.video_library_rounded,
                      () => _openDrawer(ActiveDrawer.episodes),
                      semanticLabel:
                          'Episodes (S$_currentSeason E$_currentEpisode)',
                    ),
                    const SizedBox(width: 4),
                  ],
                  _minimalIconButton(
                    Icons.fit_screen_rounded,
                    () => _openDrawer(ActiveDrawer.aspectRatio),
                    semanticLabel: 'Aspect ratio',
                  ),
                  const SizedBox(width: 4),
                  _minimalIconButton(
                    Icons.tune_rounded,
                    () => _openDrawer(ActiveDrawer.settings),
                    semanticLabel: 'Settings',
                  ),
                  const SizedBox(width: 4),
                  _minimalIconButton(
                    _isLocked
                        ? Icons.lock_rounded
                        : Icons.lock_outline_rounded,
                    _toggleLock,
                    semanticLabel: _isLocked ? 'Unlock controls' : 'Lock controls',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTmdbTitleMark() {
    final width = MediaQuery.sizeOf(context).width;
    final maxLogoWidth = (width * 0.26).clamp(120.0, 230.0).toDouble();

    if (_titleLogoUrl != null && _titleLogoUrl!.isNotEmpty) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxLogoWidth,
          maxHeight: 34,
        ),
        child: CachedNetworkImage(
          key: ValueKey('top_logo_$_titleLogoUrl'),
          imageUrl: _titleLogoUrl!,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          memCacheHeight: 96,
          errorWidget: (_, _, _) => _buildCompactTitleText(),
        ),
      );
    }
    return _buildCompactTitleText();
  }

  Widget _buildCompactTitleText() {
    final width = MediaQuery.sizeOf(context).width;
    final fontSize = (width * 0.012).clamp(11.0, 15.0).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 70),
      child: Text(
        widget.title,
        maxLines: 1,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'sans-serif',
          color: Colors.white.withValues(alpha: 0.82),
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  Widget _minimalIconButton(
    IconData icon,
    VoidCallback onTap, {
    String? semanticLabel,
  }) {
    return AppButton(
      onPressed: onTap,
      variant: AppButtonVariant.ghost,
      padding: const EdgeInsets.all(7),
      borderRadius: AppDesignTokens.radiusFull,
      semanticLabel: semanticLabel,
      child: Icon(icon, color: Colors.white70, size: 20),
    );
  }

  Widget _buildCenterControls() {
    return Center(
      child: ValueListenableBuilder<bool>(
        valueListenable: _isPlayingNotifier,
        builder: (context, isPlaying, _) {
          final isTv = widget.mediaType.toLowerCase() == 'tv';

          // ── Skip Intro button — only visible when intro segment is active ───────
          // Button appears to the left of rewind; fades in/out with intro window.
          final skipIntroSeg = _skipIntroSegment;
          final showSkipIntro = _skipIntroVisible &&
              skipIntroSeg != null &&
              AppSettingsService.instance.skipIntros;

          // One horizontal row; every child shares the same vertical axis.
          // Icons are centered inside fixed 44×44 touch bounds so the ±10s
          // glyphs sit on the exact same baseline as the 56×56 Play/Pause
          // circle. Gaps are uniform (32px) regardless of which children are
          // present, so spacing never depends on TV/movie mode.
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isTv)
                _transportIcon(
                  Icons.skip_previous_rounded,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _goToPreviousEpisode();
                    _startHideTimer();
                  },
                  iconSize: 26,
                ),
              if (isTv) const SizedBox(width: 32),
              if (showSkipIntro) ...[
                _skipIntroButton(skipIntroSeg),
                const SizedBox(width: 32),
              ],
              _transportIcon(
                Icons.replay_10_rounded,
                onTap: () {
                  HapticFeedback.selectionClick();
                  final c = _controller;
                  if (c == null) return;
                  c.seekTo(c.value.position - const Duration(seconds: 10));
                  _startHideTimer();
                },
                iconSize: 27,
              ),
              const SizedBox(width: 32),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  final c = _controller;
                  if (c == null) return;
                  if (isPlaying) {
                    c.pause();
                  } else {
                    c.play();
                  }
                  _startHideTimer();
                },
                child: Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.13),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 31,
                  ),
                ),
              ),
              const SizedBox(width: 32),
              _transportIcon(
                Icons.forward_10_rounded,
                onTap: () {
                  HapticFeedback.selectionClick();
                  final c = _controller;
                  if (c == null) return;
                  c.seekTo(c.value.position + const Duration(seconds: 10));
                  _startHideTimer();
                },
                iconSize: 27,
              ),
              if (isTv) ...[
                const SizedBox(width: 32),
                _transportIcon(
                  Icons.skip_next_rounded,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _goToNextEpisode();
                    _startHideTimer();
                  },
                  iconSize: 26,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Skip Intro button — appears to the left of the rewind control while an
  /// intro segment is active. Tapping it jumps past the segment and dismisses
  /// the button until the next detected segment.
  Widget _skipIntroButton(SkipSegment segment) {
    return AppButton(
      onPressed: () {
        HapticFeedback.selectionClick();
        final c = _controller;
        if (c == null) return;
        c.seekTo(segment.end);
        setState(() {
          _skipIntroVisible = false;
          _skipIntroSegment = null;
        });
        _startHideTimer();
      },
      variant: AppButtonVariant.ghost,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      borderRadius: AppDesignTokens.radiusFull,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fast_forward_rounded, color: _gold, size: 18),
          const SizedBox(width: 6),
          Text(
            'Skip Intro',
            style: const TextStyle(
              fontFamily: 'sans-serif',
              color: _gold,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Transport icon inside a fixed square touch target with the icon
  /// optically centered in it — keeps all side glyphs on one baseline next
  /// to the taller Play/Pause circle.
  Widget _transportIcon(IconData icon, {required VoidCallback onTap, double iconSize = 27}) {
    return AppButton(
      onPressed: onTap,
      variant: AppButtonVariant.ghost,
      padding: EdgeInsets.zero,
      borderRadius: AppDesignTokens.radiusFull,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Icon(icon, color: Colors.white70, size: iconSize),
        ),
      ),
    );
  }

  Widget _buildBottomTimeline() {
    return Positioned(
      left: 14,
      right: 14,
      bottom: 48,
      child: ValueListenableBuilder<Duration>(
        valueListenable: _durationNotifier,
        builder: (context, duration, _) {
          return ValueListenableBuilder<Duration>(
            valueListenable: _positionNotifier,
            builder: (context, position, _) {
              return ValueListenableBuilder<Duration>(
                valueListenable: _bufferedNotifier,
                builder: (context, buffered, _) {
                  return ValueListenableBuilder<double?>(
                    valueListenable: _sliderDragNotifier,
                    builder: (context, dragValue, _) {
                      final maxMs = duration.inMilliseconds > 0
                          ? duration.inMilliseconds.toDouble()
                          : 1.0;
                      final actualValue = position.inMilliseconds
                          .toDouble()
                          .clamp(0.0, maxMs);
                      final bufferedValue = buffered.inMilliseconds
                          .toDouble()
                          .clamp(0.0, maxMs);
                      final isDragging = dragValue != null;
                      final displayValue =
                          (dragValue ?? actualValue).clamp(0.0, maxMs);
                      final displayPosition =
                          Duration(milliseconds: displayValue.toInt());

                      return Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: Text(
                              _formatDuration(displayPosition),
                              style: TextStyle(
                                fontFamily: 'sans-serif',
                                color: isDragging
                                    ? _gold
                                    : Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final barWidth = constraints.maxWidth;
                                final playedFrac =
                                    (displayValue / maxMs).clamp(0.0, 1.0);
                                final bufferedFrac =
                                    (bufferedValue / maxMs).clamp(0.0, 1.0);

                                void seekFromDx(double dx) {
                                  final x = dx.clamp(0.0, barWidth);
                                  final value = (x / barWidth) * maxMs;
                                  _sliderDragNotifier.value = value;
                                }

                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragStart: (d) =>
                                      seekFromDx(d.localPosition.dx),
                                  onHorizontalDragUpdate: (d) =>
                                      seekFromDx(d.localPosition.dx),
                                  onHorizontalDragEnd: (_) {
                                    final v = _sliderDragNotifier.value;
                                    if (v != null) {
                                      _controller?.seekTo(Duration(
                                          milliseconds: v.toInt()));
                                    }
                                    _sliderDragNotifier.value = null;
                                    _startHideTimer();
                                  },
                                  onTapDown: (d) {
                                    final x = d.localPosition.dx
                                        .clamp(0.0, barWidth);
                                    final seekMs = (x / barWidth) * maxMs;
                                    _controller?.seekTo(Duration(
                                        milliseconds: seekMs.toInt()));
                                    _startHideTimer();
                                  },
                                  child: SizedBox(
                                    height: 18,
                                    child: Center(
                                      child: CustomPaint(
                                        size: Size(barWidth, isDragging ? 4 : 3),
                                        painter: _ScrubBarPainter(
                                          playedFraction: playedFrac,
                                          bufferedFraction: bufferedFrac,
                                          isDragging: isDragging,
                                          gold: _gold,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          SizedBox(
                            width: 54,
                            child: Text(
                              duration > Duration.zero
                                  ? _formatDuration(duration)
                                  : '00:00',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontFamily: 'sans-serif',
                                color: isDragging
                                    ? _gold
                                    : Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // Fixed: use Wrap to prevent overlap
  Widget _buildReferenceActionBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 11,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          _referenceAction(
            icon: Icons.settings_outlined,
            label: 'Quality',
            onTap: widget.isOffline
                ? null
                : () => _openDrawer(ActiveDrawer.quality),
          ),
          _referenceAction(
            icon: Icons.speed_outlined,
            label: 'Speed',
            onTap: _openSpeedPicker,
          ),
          _referenceAction(
            icon: Icons.subtitles_outlined,
            label: 'Audio & Subtitles',
            onTap: () {
              if (widget.isOffline) {
                _openDrawer(ActiveDrawer.subtitles);
              } else {
                _openSubtitleTrackPicker();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _referenceAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return AppButton(
      onPressed: onTap,
      variant: AppButtonVariant.ghost,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      borderRadius: AppDesignTokens.radiusMd,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 18),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'sans-serif',
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.05,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSpeedPicker() async {
    final current = _controller?.value.playbackSpeed ?? 1.0;
    const speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.60),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFF111111),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
            side: const BorderSide(color: Colors.white10),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 370),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Speed',
                          style: TextStyle(
                            fontFamily: 'sans-serif',
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _minimalIconButton(
                        Icons.close_rounded,
                        () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...speeds.map((speed) {
                    final selected = (speed - current).abs() < 0.01;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Material(
                        color: selected
                            ? const Color(0x332D2615)
                            : const Color(0xFF1D1D1B),
                        borderRadius: BorderRadius.circular(11),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(11),
                          onTap: () async {
                            try {
                              await _controller?.setPlaybackSpeed(speed);
                            } catch (_) {}
                            if (mounted) {
                              setState(() {});
                            }
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                          child: Container(
                            height: 43,
                            padding: const EdgeInsets.symmetric(horizontal: 13),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: selected
                                    ? _gold.withValues(alpha: 0.75)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    speed == 1.0
                                        ? '1×  Normal'
                                        : '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}×',
                                    style: TextStyle(
                                      fontFamily: 'sans-serif',
                                      color: selected
                                          ? _gold
                                          : Colors.white,
                                      fontSize: 13,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (selected)
                                  const Icon(Icons.check_rounded,
                                      color: _gold, size: 17),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveDrawerContent() {
    if (widget.isOffline &&
        _activeDrawer != ActiveDrawer.none &&
        _activeDrawer != ActiveDrawer.aspectRatio &&
        _activeDrawer != ActiveDrawer.subtitles &&
        _activeDrawer != ActiveDrawer.settings) {
      return const SizedBox.shrink();
    }

    switch (_activeDrawer) {
      case ActiveDrawer.settings:
        return _buildSettingsMainDrawer();
      case ActiveDrawer.servers:
        return _buildServersDrawer();
      case ActiveDrawer.quality:
        return _buildQualityDrawer();
      case ActiveDrawer.aspectRatio:
        return _buildAspectRatioDrawer();
      case ActiveDrawer.subtitles:
        return _buildSubtitlesDrawer();
      case ActiveDrawer.episodes:
        return PlayerEpisodeDrawer(
          tmdbId: widget.tmdbId ?? '',
          movieTitle: widget.movie?.title ?? widget.title,
          posterUrl: widget.movie?.posterPath ?? '',
          currentSeason: _currentSeason,
          currentEpisode: _currentEpisode,
          onEpisodeSelected: (season, episode) {
            _changeEpisode(season, episode);
          },
          onClose: _closeDrawer,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSettingsMainDrawer() {
    final isTv = widget.mediaType.toLowerCase() == 'tv';
    final hasSubs = !widget.isOffline || _parsedSubtitles.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _referenceDrawerHeader('Settings', onClose: _closeDrawer),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _compactSettingsTile(
                  icon: Icons.fit_screen_rounded,
                  title: 'Aspect ratio',
                  value: _selectedAspectRatio,
                  onTap: () => _openDrawer(ActiveDrawer.aspectRatio),
                ),
                if (hasSubs) ...[
                  const SizedBox(height: 7),
                  _compactSettingsTile(
                    icon: Icons.subtitles_outlined,
                    title: 'Subtitles',
                    value: _subtitlesEnabled
                        ? (widget.isOffline ? 'On' : _selectedLanguage)
                        : 'Off',
                    onTap: () {
                      if (widget.isOffline) {
                        _openDrawer(ActiveDrawer.subtitles);
                      } else {
                        _openSubtitleTrackPicker();
                      }
                    },
                  ),
                ],
                if (!widget.isOffline && isTv) ...[
                  const SizedBox(height: 7),
                  _compactSettingsTile(
                    icon: Icons.tv_rounded,
                    title: 'Episode',
                    value: 'S$_currentSeason E$_currentEpisode',
                    onTap: () => _openDrawer(ActiveDrawer.episodes),
                  ),
                ],
                if (!widget.isOffline) ...[
                  const SizedBox(height: 7),
                  _compactSettingsTile(
                    icon: Icons.dns_outlined,
                    title: 'Server',
                    value: _selectedServer,
                    onTap: () => _openDrawer(ActiveDrawer.servers),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _referenceDrawerHeader(
    String title, {
    required VoidCallback onClose,
    bool showBack = false,
    VoidCallback? onBack,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 5),
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            if (showBack) ...[
              _minimalIconButton(
                Icons.arrow_back_ios_new_rounded,
                onBack ?? _closeDrawer,
              ),
              const SizedBox(width: 2),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'sans-serif',
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
            ),
            _minimalIconButton(Icons.close_rounded, onClose),
          ],
        ),
      ),
    );
  }

  Widget _compactSettingsTile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF1C1C1C),
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.035),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white70, size: 19),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'sans-serif',
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: 'sans-serif',
                    color: Color(0xFFE2C65A),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white38,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServersDrawer() {
    return Column(
      children: [
        _referenceDrawerHeader(
          "Playback server",
          showBack: true,
          onBack: () => _openDrawer(ActiveDrawer.settings),
          onClose: _closeDrawer,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...List<Widget>.generate(_serverList.length, (index) {
                final server = _serverList[index];
                final serverName =
                    server['name'] ?? 'Server ${index + 1}';
                final isSelected = _selectedServer == serverName;

                return _pillTile(
                  title: serverName,
                  subtitle: isSelected ? 'Active' : 'Fast',
                  isSelected: isSelected,
                  onTap: () => _switchServer(server),
                );
              }),
              ..._buildAddonSourceTiles(),
            ],
          ),
        ),
      ],
    );
  }

  /// Section shown under the classic servers inside the server drawer:
  /// playable streams returned by the user's installed add-ons for this title.
  List<Widget> _buildAddonSourceTiles() {
    if (widget.isOffline || (!_anyAddonsInstalled && !_addonSourcesLoading)) {
      return const [];
    }
    return [
      const SizedBox(height: 6),
      Row(
        children: const [
          Icon(Icons.extension_rounded, color: _gold, size: 13),
          SizedBox(width: 6),
          Text(
            'SOURCES FROM YOUR ADD-ONS',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (_addonSourcesLoading)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _gold),
              ),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Searching your add-ons…',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ),
        )
      else if (_addonSources.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'No streams found in your add-ons for this title.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        )
      else
        for (final source in _addonSources)
          _pillTile(
            title: source.title,
            subtitle: source.addonName,
            isSelected: _isAddonSourceActive &&
                source.stream.playableDirectUrl == _masterStreamUrl,
            onTap: () => _startAddonPlayback(source),
          ),
    ];
  }

  Widget _buildQualityDrawer() {
    // 360p is not supported by any provider — ladder starts at 480p.
    const ladder = [1080, 720, 480];
    final heights = <int>{};
    for (final v in _hlsVariants) {
      final h = _parseHeight(v.resolution);
      if (h != null && h > 0) heights.add(h);
    }

    final ordered = <int>[];
    for (final h in ladder) {
      if (heights.isEmpty || heights.contains(h)) ordered.add(h);
    }
    if (heights.isNotEmpty) {
      final extras = heights.where((h) => !ladder.contains(h)).toList()
        ..sort((a, b) => b.compareTo(a));
      ordered.addAll(extras);
    }

    final selectedHeight = _parseHeight(_selectedQuality);
    final isAuto = _selectedQuality.trim().isEmpty ||
        _selectedQuality.toLowerCase() == 'auto';

    String qualityClass(int h) {
      if (h >= 2160) return '4K UHD';
      if (h >= 1080) return 'Full HD';
      if (h >= 720) return 'HD';
      return 'SD';
    }

    return Column(
      children: [
        _referenceDrawerHeader('Quality', onClose: _closeDrawer),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.isOffline)
                  _referenceQualityCard(
                    label: 'Auto',
                    detail: 'Adaptive · Best available',
                    secondary: 'HLS',
                    selected: isAuto,
                    onTap: () => _changeQuality('Auto'),
                  ),
                ...ordered.map((h) => _referenceQualityCard(
                      label: '${h}p',
                      detail: qualityClass(h),
                      secondary: 'HLS',
                      selected: !isAuto && selectedHeight == h,
                      onTap: () => _changeQuality('${h}p'),
                    )),
                if (widget.isOffline)
                  _referenceQualityCard(
                    label: 'Local',
                    detail: 'Offline playback',
                    secondary: 'Device',
                    selected: true,
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _referenceQualityCard({
    required String label,
    required String detail,
    required String secondary,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? const Color(0xFF2C2515)
            : const Color(0xFF1C1C1B),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 62,
            padding: const EdgeInsets.fromLTRB(13, 8, 10, 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? _gold.withValues(alpha: 0.78)
                    : Colors.white.withValues(alpha: 0.025),
                width: selected ? 1.1 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'sans-serif',
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$detail  ·  $secondary',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'sans-serif',
                          color: Colors.white38,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white38,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAspectRatioDrawer() {
    final ratios = <Map<String, String>>[
      {'label': 'Auto', 'hint': 'recommended'},
      {'label': 'Fit', 'hint': 'no crop'},
      {'label': 'Fill', 'hint': 'crop edges if needed'},
      {'label': '16:9', 'hint': 'Standard HD / streaming'},
      {'label': '4:3', 'hint': 'Older TV, classic film'},
    ];

    return Column(
      children: [
        _referenceDrawerHeader(
          "Aspect ratio",
          showBack: true,
          onBack: () => _openDrawer(ActiveDrawer.settings),
          onClose: _closeDrawer,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ratios.length,
            itemBuilder: (context, index) {
              final r = ratios[index];
              final label = r['label']!;
              return _pillTile(
                title: label,
                subtitle: r['hint'],
                isSelected: _selectedAspectRatio == label,
                onTap: () => _setAspectRatio(label),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSubtitlesDrawer() {
    final languages = [
      'Off',
      'English',
      'Spanish',
      'French',
      'Arabic',
      'German'
    ];

    return Column(
      children: [
        _referenceDrawerHeader(
          "Subtitles",
          showBack: true,
          onBack: () => _openDrawer(ActiveDrawer.settings),
          onClose: _closeDrawer,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!widget.isOffline && _availableTracks.isNotEmpty) ...[
                _sectionHeader("AVAILABLE TRACKS"),
                _pillTile(
                  title: 'Browse all tracks…',
                  subtitle: '${_availableTracks.length} from Wyzie',
                  isSelected: false,
                  onTap: () {
                    _closeDrawer();
                    _openSubtitleTrackPicker();
                  },
                ),
                const SizedBox(height: 8),
              ],
              _sectionHeader("SUBTITLE LANGUAGE"),
              ...languages.map((lang) {
                final isSelected =
                    (_subtitlesEnabled && _selectedLanguage == lang) ||
                        (!_subtitlesEnabled && lang == 'Off');
                return _pillTile(
                  title: lang,
                  isSelected: isSelected,
                  onTap: () {
                    setState(() {
                      if (lang == 'Off') {
                        _subtitlesEnabled = false;
                        _currentSubtitleText = '';
                        _stopSubtitleTimer();
                      } else {
                        _subtitlesEnabled = true;
                        _selectedLanguage = lang;
                        if (!widget.isOffline) {
                          _fetchWisoSubtitles();
                        } else if (_parsedSubtitles.isNotEmpty) {
                          _startSubtitleTimer();
                        }
                        if (_controller?.value.isPlaying == true) {
                          _startSubtitleTimer();
                        }
                      }
                    });
                    _closeDrawer();
                  },
                );
              }),
              if (_subtitlesEnabled) ...[
                const SizedBox(height: 16),
                _sectionHeader("SUBTITLE SYNC OFFSET"),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1B1E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "${_subtitleOffsetSeconds >= 0 ? '+' : ''}${_subtitleOffsetSeconds.toStringAsFixed(1)}s",
                        style: const TextStyle(
                            color: _gold,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _offsetBtn("-1.0s", () {
                            setState(() => _subtitleOffsetSeconds -= 1.0);
                            _updateSubtitleText();
                          }),
                          _offsetBtn("-0.5s", () {
                            setState(() => _subtitleOffsetSeconds -= 0.5);
                            _updateSubtitleText();
                          }),
                          _offsetBtn("Reset", () {
                            setState(() => _subtitleOffsetSeconds = 0.0);
                            _updateSubtitleText();
                          }, reset: true),
                          _offsetBtn("+0.5s", () {
                            setState(() => _subtitleOffsetSeconds += 0.5);
                            _updateSubtitleText();
                          }),
                          _offsetBtn("+1.0s", () {
                            setState(() => _subtitleOffsetSeconds += 1.0);
                            _updateSubtitleText();
                          }),
                        ],
                      ),
                    ],
                  ),
                )
              ]
            ],
          ),
        ),
      ],
    );
  }

  Widget _offsetBtn(String label, VoidCallback onTap, {bool reset = false}) {
    return AppButton(
      onPressed: onTap,
      variant: AppButtonVariant.ghost,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      borderRadius: AppDesignTokens.radiusMd,
      child: Text(
        label,
        style: TextStyle(
          color: reset ? Colors.black : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(
            color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _pillTile({
    required String title,
    String? subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        borderRadius: AppDesignTokens.radius3xl,
        backgroundColor: isSelected
            ? const Color(0xFF332A15)
            : const Color(0xFF1C1C1E),
        border: true,
        borderColor: isSelected ? _gold : Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? _gold : Colors.white,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 15,
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: isSelected ? _gold : Colors.white38,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDraggableSubtitleOverlay(Size screenSize) {
    const maxBoxWidth = 320.0;
    final pad = MediaQuery.paddingOf(context);
    final defaultLeft = (screenSize.width - maxBoxWidth) / 2;
    final defaultTop = screenSize.height -
        (_showControls ? 110.0 : 64.0) -
        pad.bottom -
        36;

    final left = (_subtitleDragOffset?.dx ?? defaultLeft)
        .clamp(8.0, screenSize.width - 80.0);
    final top = (_subtitleDragOffset?.dy ?? defaultTop)
        .clamp(pad.top + 8.0, screenSize.height - pad.bottom - 40.0);

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          setState(() {
            final base = _subtitleDragOffset ?? Offset(defaultLeft, defaultTop);
            final next = base + details.delta;
            _subtitleDragOffset = Offset(
              next.dx.clamp(8.0, screenSize.width - 80.0),
              next.dy.clamp(pad.top + 8.0, screenSize.height - pad.bottom - 40.0),
            );
          });
        },
        onLongPress: () {
          setState(() {
            _subtitleDragOffset = null;
            _subtitleScale = 1.0;
          });
        },
        onDoubleTap: () {
          setState(() {
            _subtitleScale = _subtitleScale < 1.15 ? 1.25 : 1.0;
          });
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxBoxWidth * _subtitleScale,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Text(
              _currentSubtitleText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14 * _subtitleScale,
                fontWeight: FontWeight.w600,
                height: 1.25,
                shadows: const [
                  Shadow(
                    color: Colors.black87,
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNextEpisodeOverlay() {
    if (!_showNextEpisodeCard) return const SizedBox.shrink();
    final nextEp = _currentEpisode + 1;
    final pad = MediaQuery.paddingOf(context);
    final secondsLeft = ((1.0 - _nextEpisodeProgress) * 15)
        .clamp(0, 15)
        .toInt();

    return Positioned(
      left: 12,
      right: 12,
      bottom: 24 + pad.bottom,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: const Color(0xF0141416),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _gold.withValues(alpha: 0.35),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.skip_next_rounded,
                    color: _gold,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Next in ${secondsLeft}s',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        Text(
                          'S${_currentSeason.toString().padLeft(2, '0')}E${nextEp.toString().padLeft(2, '0')}  ·  ${widget.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _cancelNextEpisodePrompt,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _goToNextEpisode,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black,
                      backgroundColor: _gold,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Play now',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 2,
                width: double.infinity,
                child: AnimatedBuilder(
                  animation: _nextEpisodeShimmer!,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _GoldShimmerProgressPainter(
                        progress: _nextEpisodeProgress,
                        shimmerValue: _nextEpisodeShimmer!.value,
                      ),
                      size: Size.infinite,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF141416).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _gold.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded, color: _gold, size: 36),
            ),
            const SizedBox(height: 18),
            const Text(
              'Playback Failed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage.isNotEmpty
                  ? _errorMessage
                  : (widget.isOffline
                      ? 'The local video could not be found or played.'
                      : 'Playback failed on current server. Try switching servers.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            if (!widget.isOffline) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: () => _openDrawer(ActiveDrawer.servers),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.dns_rounded, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Switch Server',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              const Text(
                'Check that the downloaded file still exists and is not corrupted.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Gold shimmer progress painter for the next-episode autoplay bar.
class _GoldShimmerProgressPainter extends CustomPainter {
  _GoldShimmerProgressPainter({
    required this.progress,
    required this.shimmerValue,
  });

  final double progress;
  final double shimmerValue;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, track);

    if (progress <= 0) return;

    final barWidth = size.width * progress.clamp(0.0, 1.0);
    final rect = Rect.fromLTWH(0, 0, barWidth, size.height);

    final base = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFB8962E),
          _gold,
          Color(0xFFE8C872),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, base);

    final shimmerX = (shimmerValue * (barWidth + 80)) - 40;
    final shimmerRect = Rect.fromLTWH(shimmerX, 0, 60, size.height);
    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(shimmerRect);

    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(shimmerRect, shimmerPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoldShimmerProgressPainter old) =>
      old.progress != progress || old.shimmerValue != shimmerValue;
}

/// YouTube-style scrub bar: background → buffered (light gold) → played (solid gold) + thumb.
class _ScrubBarPainter extends CustomPainter {
  _ScrubBarPainter({
    required this.playedFraction,
    required this.bufferedFraction,
    required this.isDragging,
    required this.gold,
  });

  final double playedFraction;
  final double bufferedFraction;
  final bool isDragging;
  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final trackRect = Offset.zero & size;

    final bg = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(trackRect, radius), bg);

    if (bufferedFraction > 0) {
      final bufRect = Rect.fromLTWH(
        0,
        0,
        size.width * bufferedFraction.clamp(0.0, 1.0),
        size.height,
      );
      final bufPaint = Paint()
        ..color = gold.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(RRect.fromRectAndRadius(bufRect, radius), bufPaint);
    }

    if (playedFraction > 0) {
      final playedRect = Rect.fromLTWH(
        0,
        0,
        size.width * playedFraction.clamp(0.0, 1.0),
        size.height,
      );
      final playedPaint = Paint()
        ..color = gold
        ..style = PaintingStyle.fill;
      canvas.drawRRect(RRect.fromRectAndRadius(playedRect, radius), playedPaint);
    }

    final thumbX = size.width * playedFraction.clamp(0.0, 1.0);
    final thumbRadius = isDragging ? 8.0 : 6.0;
    canvas.drawCircle(
      Offset(thumbX, size.height / 2),
      thumbRadius + 3,
      Paint()..color = gold.withValues(alpha: 0.25),
    );
    canvas.drawCircle(
      Offset(thumbX, size.height / 2),
      thumbRadius,
      Paint()
        ..color = gold
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(thumbX, size.height / 2),
      thumbRadius * 0.45,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _ScrubBarPainter old) =>
      old.playedFraction != playedFraction ||
      old.bufferedFraction != bufferedFraction ||
      old.isDragging != isDragging;
}