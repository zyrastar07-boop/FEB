import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/web_view_scraper.dart';
import '../services/wyzie_service.dart';
import 'player_episode_drawer.dart';

const _gold = Color(0xFFD4AF37);

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
    with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _hasError = false;
  bool _isLocked = false;
  bool _isScraping = false;
  String _errorMessage = '';
  Timer? _hideTimer;

  late String _masterStreamUrl;
  late String _activeStreamUrl;
  String _selectedServer = 'Mella Direct';
  List<Map<String, dynamic>> _serverList = [];

  late int _currentSeason;
  late int _currentEpisode;

  List<HlsVariant> _hlsVariants = [];
  String _selectedQuality = 'Auto';

  ActiveDrawer _activeDrawer = ActiveDrawer.none;

  String _selectedAspectRatio = 'Full Screen';
  double? _customAspectRatio;

  double _volumeLevel = 0.5;
  double _brightnessLevel = 0.5;
  bool _showGestureToast = false;
  String _toastIcon = 'volume';
  Timer? _toastTimer;
  DateTime? _lastVolumeUpdate;

  List<SubtitleItem> _parsedSubtitles = [];
  String _currentSubtitleText = '';
  String _selectedLanguage = 'English';
  bool _subtitlesEnabled = true;
  double _subtitleOffsetSeconds = 0.0;

  late AnimationController _controlsFade;
  late AnimationController _drawerSlide;
  late AnimationController _toastFade;
  late Animation<double> _controlsOpacity;
  late Animation<Offset> _drawerOffset;
  late Animation<double> _toastOpacity;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    _currentSeason = widget.season ?? 1;
    _currentEpisode = widget.episode ?? 1;

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _controlsFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _drawerSlide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _toastFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _controlsOpacity =
        CurvedAnimation(parent: _controlsFade, curve: Curves.easeOut);
    _drawerOffset = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _drawerSlide, curve: Curves.easeOutCubic));
    _toastOpacity = CurvedAnimation(parent: _toastFade, curve: Curves.easeOut);

    _controlsFade.forward();

    _initServerList();
    _initBrightnessAndVolume();
    _loadStream(_activeStreamUrl);
    if (!widget.isOffline) {
      _fetchWisoSubtitles();
    }
  }

  bool _isEmbedUrl(String url) {
    if (widget.isOffline) return false;
    return !url.contains('.m3u8') &&
        !url.contains('.mp4') &&
        !url.contains('.webm');
  }

  void _initServerList() {
    final rawServers = widget.servers != null && widget.servers!.isNotEmpty
        ? widget.servers!
        : [
            {
              "id": "mella_direct",
              "name": "Mella Direct",
              "url": "https://mella.direct",
              "movie_url_pattern": null,
              "tv_url_pattern": null,
            },
            {
              "id": "mela_cinema_core",
              "name": "Mela Cinema Core",
              "url": "https://cinema.mela.core",
              "movie_url_pattern": null,
              "tv_url_pattern": null,
            },
            {
              "id": "mela_nexus_prime",
              "name": "Mela Nexus Prime Stream",
              "url": "https://nexus.mela.prime",
              "movie_url_pattern": "{url}/{type}/{tmdbId}?play=true",
              "tv_url_pattern":
                  "{url}/{type}/{tmdbId}/{season}/{episode}?play=true",
            },
            {
              "id": "mela_cronus_fiber",
              "name": "Mela Cronus Fiber Relay",
              "url": "https://cronus.mela.relay",
              "movie_url_pattern": "{url}/{type}/{tmdbId}",
              "tv_url_pattern": "{url}/{type}/{tmdbId}/{season}/{episode}",
            }
          ];

    _serverList = rawServers.map((server) {
      final Map<String, dynamic> s = Map.from(server);
      final id = (s['id'] ?? '').toString().toLowerCase();

      if (s['movie_url_pattern'] == null ||
          (s['movie_url_pattern'] as String).isEmpty) {
        if (id == 'mella_direct' || id == 'mela_cinema_core') {
          s['movie_url_pattern'] = '{url}/movie/{tmdbId}?autoPlay=true';
        } else {
          s['movie_url_pattern'] = '{url}/{type}/{tmdbId}';
        }
      }
      if (s['tv_url_pattern'] == null ||
          (s['tv_url_pattern'] as String).isEmpty) {
        if (id == 'mella_direct' || id == 'mela_cinema_core') {
          s['tv_url_pattern'] =
              '{url}/tv/{tmdbId}/{season}/{episode}?autoPlay=true';
        } else {
          s['tv_url_pattern'] = '{url}/{type}/{tmdbId}/{season}/{episode}';
        }
      }
      return s;
    }).toList();

    final initialServer = _serverList.first;
    _selectedServer = initialServer['name'] ?? 'Mella Direct';

    final resolvedInitialUrl = _resolveServerUrl(initialServer);
    _masterStreamUrl = resolvedInitialUrl.isNotEmpty ? resolvedInitialUrl : widget.streamUrl; 
    _activeStreamUrl = _masterStreamUrl;
  }

  String _resolveServerUrl(Map<String, dynamic> server) {
    if (widget.isOffline) return widget.streamUrl;

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

  Future<void> _loadStream(String url, {Duration? startPosition}) async {
    setState(() {
      _hasError = false;
      _errorMessage = '';
    });

    if (!widget.isOffline && _isEmbedUrl(url)) {
      setState(() {
        _isScraping = true;
        _isInitialized = false;
      });
    } else {
      setState(() => _isScraping = false);
      if (!widget.isOffline) {
        await _fetchHlsVariants(url);
      }
      await _initializePlayer(url, startPosition: startPosition);
    }
  }

  Future<void> _changeEpisode(int season, int episode) async {
    if (_currentSeason == season && _currentEpisode == episode) return;

    setState(() {
      _currentSeason = season;
      _currentEpisode = episode;
      _isInitialized = false;
      _selectedQuality = 'Auto';
      _hlsVariants.clear();
    });
    _closeDrawer();

    final activeServer = _serverList.firstWhere(
      (s) => s['name'] == _selectedServer,
      orElse: () => _serverList.first,
    );

    final resolvedUrl = _resolveServerUrl(activeServer);
    _masterStreamUrl = resolvedUrl;
    _activeStreamUrl = resolvedUrl;

    await _disposeController();

    if (!widget.isOffline) {
      _fetchWisoSubtitles();
    }

    await _loadStream(resolvedUrl);
  }

  Future<void> _initBrightnessAndVolume() async {
    try {
      FlutterVolumeController.updateShowSystemUI(false);
      _brightnessLevel = await ScreenBrightness().current;
      _volumeLevel = await FlutterVolumeController.getVolume() ?? 0.5;
    } catch (_) {}
  }

  Future<void> _fetchHlsVariants(String url) async {
    if (!url.contains('.m3u8')) return;

    try {
      final response = await http.get(Uri.parse(url), headers: widget.headers);
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

        if (mounted) setState(() => _hlsVariants = variants);
      }
    } catch (e) {
      debugPrint('HLS Variant Parse Error: $e');
    }
  }

  bool _isPlayableMediaUrl(String url) {
    if (widget.isOffline) return true;
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
    if (!_isPlayableMediaUrl(url)) {
      if (mounted) {
        setState(() {
          _isScraping = false;
          _isInitialized = false;
          _hasError = true;
          _errorMessage =
              'No direct stream URL found. Please switch to another server.';
        });
      }
      return;
    }

    try {
      await _disposeController();

      final uri = Uri.parse(url);

      if (widget.isOffline || uri.scheme == 'file') {
        final String filePath = uri.scheme == 'file' ? uri.toFilePath() : url;
        _controller = VideoPlayerController.file(
          File(filePath),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
        );
      } else {
        final Map<String, String> requestHeaders = {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': '*/*',
        };

        try {
          final ref = Uri.parse(_masterStreamUrl);
          if (ref.hasScheme && ref.host.isNotEmpty) {
            requestHeaders['Referer'] = '${ref.scheme}://${ref.host}/';
            requestHeaders['Origin'] = '${ref.scheme}://${ref.host}';
          }
        } catch (_) {}

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

      if (startPosition != null && startPosition > Duration.zero) {
        await _controller!.seekTo(startPosition);
      }

      _controller?.play();
      _controller?.addListener(_videoPlayerListener);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
          _isScraping = false;
        });
        _startHideTimer();
      }
    } catch (e) {
      debugPrint('Initialize player error: $e');
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _hasError = true;
          _errorMessage =
              'Playback failed on this server. Try switching servers.\n$e';
        });
      }
    }
  }

  Future<void> _changeQuality(String qualityLabel) async {
    if (_selectedQuality == qualityLabel) return;

    String targetUrl = _masterStreamUrl;
    if (qualityLabel != 'Auto') {
      final matchingVariant = _hlsVariants.firstWhere(
        (v) =>
            v.resolution.toLowerCase().contains(qualityLabel.toLowerCase()),
        orElse: () => HlsVariant(resolution: '', url: ''),
      );
      if (matchingVariant.url.isNotEmpty) {
        targetUrl = matchingVariant.url;
      }
    }

    final currentPosition = _controller?.value.position ?? Duration.zero;

    await _disposeController();

    setState(() {
      _isInitialized = false;
      _selectedQuality = qualityLabel;
      _activeStreamUrl = targetUrl;
    });
    _closeDrawer();

    await _initializePlayer(targetUrl, startPosition: currentPosition);
  }

  Future<void> _switchServer(Map<String, dynamic> server) async {
    final serverName = server['name'] ?? 'Unknown';
    if (_selectedServer == serverName) return;

    final resolvedUrl = _resolveServerUrl(server);
    final currentPosition = _controller?.value.position ?? Duration.zero;

    await _disposeController();

    setState(() {
      _isInitialized = false;
      _hasError = false;
      _selectedServer = serverName;
      _masterStreamUrl = resolvedUrl;
      _activeStreamUrl = resolvedUrl;
      _selectedQuality = 'Auto';
      _hlsVariants.clear();
    });
    _closeDrawer();

    await _loadStream(resolvedUrl, startPosition: currentPosition);
  }

  void _videoPlayerListener() {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) {
      return;
    }

    if (_subtitlesEnabled && _parsedSubtitles.isNotEmpty) {
      final position = _controller?.value.position ?? Duration.zero;
      final offsetMs = (_subtitleOffsetSeconds * 1000).toInt();
      final effectivePosition = position - Duration(milliseconds: offsetMs);

      final activeSub = _parsedSubtitles.firstWhere(
        (sub) =>
            effectivePosition >= sub.start && effectivePosition <= sub.end,
        orElse: () =>
            SubtitleItem(start: Duration.zero, end: Duration.zero, text: ''),
      );

      if (_currentSubtitleText != activeSub.text) {
        setState(() => _currentSubtitleText = activeSub.text);
      }
    } else if (_currentSubtitleText.isNotEmpty) {
      setState(() => _currentSubtitleText = '');
    }

    setState(() {});
  }

  Future<void> _fetchWisoSubtitles() async {
    final int? tmdbIdInt = int.tryParse(widget.tmdbId ?? '');
    final hasImdb =
        widget.imdbId != null && widget.imdbId!.trim().isNotEmpty;
    if ((tmdbIdInt == null || tmdbIdInt <= 0) && !hasImdb) {
      debugPrint('Subtitle Fetch Cancelled: No valid TMDB/IMDb ID.');
      return;
    }

    try {
      // Keys live on the Cloudflare Worker — client uses keyless WyzieService.
      final wyzie = WyzieService();

      final isTv = widget.mediaType.toLowerCase() == 'tv';
      // Wyzie requires ISO 639-1 codes (en, es, fr…) — not full names.
      final isoLang = WyzieService.toIsoLanguage(_selectedLanguage);

      List<WyzieSubtitle> results = await wyzie.searchSubtitles(
        tmdbId: (tmdbIdInt != null && tmdbIdInt > 0) ? tmdbIdInt : null,
        imdbId: hasImdb ? widget.imdbId : null,
        season: isTv ? _currentSeason : null,
        episode: isTv ? _currentEpisode : null,
        language: isoLang,
      );

      // Soft fallback: if language filter returned nothing, try without it.
      if (results.isEmpty && isoLang.isNotEmpty) {
        results = await wyzie.searchSubtitles(
          tmdbId: (tmdbIdInt != null && tmdbIdInt > 0) ? tmdbIdInt : null,
          imdbId: hasImdb ? widget.imdbId : null,
          season: isTv ? _currentSeason : null,
          episode: isTv ? _currentEpisode : null,
        );
        // Prefer entries matching the requested language when present.
        final preferred = results
            .where((s) =>
                s.language.toLowerCase() == isoLang ||
                s.display.toLowerCase().contains(_selectedLanguage.toLowerCase()))
            .toList();
        if (preferred.isNotEmpty) results = preferred;
      }

      if (results.isNotEmpty) {
        final String subtitleContent =
            await wyzie.fetchSubtitleText(results.first.url);

        if (mounted) {
          _parseSrtOrVtt(subtitleContent);
          debugPrint(
              'Subtitles loaded: ${_parsedSubtitles.length} cues (${results.first.display})');
        }
      } else {
        debugPrint(
            'Wyzie: No subtitles found for language $_selectedLanguage ($isoLang)');
        if (mounted) {
          setState(() {
            _parsedSubtitles = [];
            _currentSubtitleText = '';
          });
        }
      }
    } catch (e) {
      debugPrint('Wyzie Subtitle Fetch Error: $e');
      if (mounted) {
        setState(() {
          _parsedSubtitles = [];
          _currentSubtitleText = '';
        });
      }
    }
  }

  void _parseSrtOrVtt(String content) {
    final items = <SubtitleItem>[];
    // Normalize line endings and strip BOM / WEBVTT header noise.
    var text = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (text.startsWith('\uFEFF')) text = text.substring(1);

    final lines = text.split('\n');
    // Supports HH:MM:SS,mmm and MM:SS.mmm (optional hours) with , or .
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
      // Strip common SRT/VTT tags: <i>, <b>, <font…>, {\an8}, etc.
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
        // Skip cue numbers and NOTE blocks
        final line = lines[j].trim();
        if (!RegExp(r'^\d+$').hasMatch(line) && !line.startsWith('NOTE')) {
          textBuffer.writeln(line);
        }
        j++;
      }

      final cue = cleanCueText(textBuffer.toString());
      if (cue.isNotEmpty) {
        items.add(SubtitleItem(start: start, end: end, text: cue));
      }
    }

    if (mounted) {
      setState(() {
        _parsedSubtitles = items;
        _currentSubtitleText = '';
      });
    }
  }

  void _handleVerticalDrag(DragUpdateDetails details, double screenWidth) {
    if (_isLocked) return;
    final isLeft = details.globalPosition.dx < (screenWidth / 2);

    if (isLeft) {
      _brightnessLevel =
          (_brightnessLevel - (details.delta.dy / 300)).clamp(0.1, 1.0);
      ScreenBrightness().setScreenBrightness(_brightnessLevel);
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
        case 'Full Screen':
        case 'Cover':
        case 'Fill':
          _customAspectRatio = null;
          break;
        case '32:9':
          _customAspectRatio = 32 / 9;
          break;
        case '24:10':
          _customAspectRatio = 24 / 10;
          break;
        case '21:9':
          _customAspectRatio = 21 / 9;
          break;
        case '19.5:9':
          _customAspectRatio = 19.5 / 9;
          break;
        case '2:1':
          _customAspectRatio = 2.0;
          break;
        case '16:10':
          _customAspectRatio = 16 / 10;
          break;
        case '16:9':
          _customAspectRatio = 16 / 9;
          break;
        case '3:2':
          _customAspectRatio = 3 / 2;
          break;
        case '4:3':
          _customAspectRatio = 4 / 3;
          break;
        case '5:4':
          _customAspectRatio = 5 / 4;
          break;
        case 'Auto':
        default:
          _customAspectRatio = null;
          break;
      }
    });
    _closeDrawer();
  }

  BoxFit _getBoxFit() {
    if (_selectedAspectRatio == 'Fill' ||
        _selectedAspectRatio == 'Cover' ||
        _selectedAspectRatio == 'Full Screen') {
      return BoxFit.cover;
    }
    return BoxFit.contain;
  }

  bool get _isFullBleed =>
      _selectedAspectRatio == 'Full Screen' ||
      _selectedAspectRatio == 'Cover' ||
      _selectedAspectRatio == 'Fill';

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
  void dispose() {
    WakelockPlus.disable();
    _controller?.removeListener(_videoPlayerListener);
    _hideTimer?.cancel();
    _toastTimer?.cancel();
    _controlsFade.dispose();
    _drawerSlide.dispose();
    _toastFade.dispose();
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final videoAspect = _controller?.value.aspectRatio ?? 16 / 9;
    final effectiveAspectRatio = _customAspectRatio ?? videoAspect;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onVerticalDragUpdate: (details) =>
            _handleVerticalDrag(details, screenSize.width),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_isScraping)
              WebViewScraper(
                embedUrl: _activeStreamUrl,
                mediaType: widget.mediaType,
                season: _currentSeason,
                episode: _currentEpisode,
                timeoutSeconds: 7,
                onDataExtracted: (extractedData) async {
                  if (!mounted) return;
                  final media = extractedData.allStreams
                      .where((s) =>
                          s.format == 'hls' ||
                          s.format == 'mp4' ||
                          s.format == 'webm' ||
                          s.url.contains('.m3u8') ||
                          s.url.contains('.mp4'))
                      .toList();
                  if (media.isEmpty) {
                    setState(() {
                      _isScraping = false;
                      _hasError = true;
                      _errorMessage =
                          'No playable stream found. Try switching servers.';
                    });
                    return;
                  }
                  final best = media.first;
                  setState(() {
                    _isScraping = false;
                    _masterStreamUrl = best.url;
                    _activeStreamUrl = best.url;
                    _hlsVariants = media
                        .map((s) => HlsVariant(
                              resolution: s.height != null
                                  ? '${s.height}p'
                                  : s.format.toUpperCase(),
                              url: s.url,
                            ))
                        .toList();
                  });
                  await _fetchHlsVariants(best.url);
                  await _initializePlayer(best.url);
                },
                onError: (err) {
                  if (!mounted) return;
                  setState(() {
                    _isScraping = false;
                    _hasError = true;
                    _errorMessage = err.isNotEmpty
                        ? err
                        : 'Failed to extract stream. Try another server.';
                  });
                },
              )
            else if (_isInitialized && !_hasError)
              _isFullBleed
                  ? SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: 1920,
                          height: 1920 /
                              (_controller?.value.aspectRatio ?? 16 / 9),
                          child: VideoPlayer(_controller!),
                        ),
                      ),
                    )
                  : Center(
                      child: SizedBox.expand(
                        child: FittedBox(
                          fit: _getBoxFit(),
                          child: SizedBox(
                            width: 1920,
                            height: 1920 / effectiveAspectRatio,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                      ),
                    )
            else if (_hasError)
              _buildErrorView()
            else
              const Center(
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    color: _gold,
                    strokeWidth: 2.5,
                  ),
                ),
              ),
            if (_subtitlesEnabled && _currentSubtitleText.isNotEmpty)
              Positioned(
                bottom: 80,
                left: 40,
                right: 40,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _currentSubtitleText.isNotEmpty ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _currentSubtitleText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_showGestureToast)
              Positioned(
                top: 80,
                child: FadeTransition(
                  opacity: _toastOpacity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _gold, width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _toastIcon == 'brightness'
                              ? Icons.brightness_6
                              : Icons.volume_up,
                          color: _gold,
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 100,
                          child: LinearProgressIndicator(
                            value: _toastIcon == 'brightness'
                                ? _brightnessLevel
                                : _volumeLevel,
                            color: _gold,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ],
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
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 100,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.black87, Colors.transparent],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 130,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, Colors.black87],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    _buildTopHeader(),
                    _buildCenterControls(),
                    _buildBottomTimeline(),
                  ],
                ),
              ),
            if (_isLocked)
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 20,
                child: GestureDetector(
                  onTap: _toggleLock,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: _gold.withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded, color: _gold, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'Tap to unlock',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_activeDrawer != ActiveDrawer.none)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: screenSize.width * 0.40,
                child: SlideTransition(
                  position: _drawerOffset,
                  child: Container(
                    color: const Color(0xFF0F0F0F).withValues(alpha: 0.97),
                    child: _buildActiveDrawerContent(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    final isTv = widget.mediaType.toLowerCase() == 'tv';

    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Row(
        children: [
          _circleBtn(Icons.arrow_back, () => Navigator.pop(context)),
          const SizedBox(width: 8),
          _circleBtn(
            Icons.refresh,
            () => _loadStream(_activeStreamUrl),
            gold: true,
          ),
          const SizedBox(width: 8),
          _circleBtn(
            _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            _toggleLock,
          ),
          const Spacer(),
          if (!widget.isOffline) ...[
            if (isTv) ...[
              _pillBadge(
                "S$_currentSeason E$_currentEpisode",
                () => _openDrawer(ActiveDrawer.episodes),
                highlight: true,
              ),
              const SizedBox(width: 8),
            ],
            _pillBadge(_selectedQuality,
                () => _openDrawer(ActiveDrawer.quality),
                highlight: true),
            const SizedBox(width: 8),
          ],
          _pillBadge("Aspect: $_selectedAspectRatio",
              () => _openDrawer(ActiveDrawer.aspectRatio)),
          const SizedBox(width: 8),
          if (!widget.isOffline) ...[
            _pillBadge(
              "Subs: ${_subtitlesEnabled ? _selectedLanguage : 'Off'}",
              () => _openDrawer(ActiveDrawer.subtitles),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _openDrawer(ActiveDrawer.settings),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1F1F),
                  shape: BoxShape.circle,
                  border: Border.all(color: _gold, width: 1),
                ),
                child: const Icon(Icons.tune_rounded, color: _gold, size: 18),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, {bool gold = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          shape: BoxShape.circle,
          border: gold ? Border.all(color: _gold, width: 1.5) : null,
        ),
        child: Icon(icon, color: gold ? _gold : Colors.white, size: 18),
      ),
    );
  }

  Widget _pillBadge(String label, VoidCallback onTap,
      {bool highlight = false}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: highlight ? _gold : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: highlight ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    final isPlaying = _controller?.value.isPlaying ?? false;

    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            iconSize: 42,
            icon:
                const Icon(Icons.replay_10_rounded, color: Colors.white),
            onPressed: () {
              _controller?.seekTo(_controller!.value.position -
                  const Duration(seconds: 10));
              _startHideTimer();
            },
          ),
          const SizedBox(width: 32),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (_controller != null) {
                  isPlaying ? _controller!.pause() : _controller!.play();
                }
              });
              _startHideTimer();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: _gold,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.black,
                size: 38,
              ),
            ),
          ),
          const SizedBox(width: 32),
          IconButton(
            iconSize: 42,
            icon:
                const Icon(Icons.forward_10_rounded, color: Colors.white),
            onPressed: () {
              _controller?.seekTo(_controller!.value.position +
                  const Duration(seconds: 10));
              _startHideTimer();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomTimeline() {
    final position = _controller?.value.position ?? Duration.zero;
    final duration = _controller?.value.duration ?? Duration.zero;

    return Positioned(
      bottom: 12,
      left: 20,
      right: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _gold,
              inactiveTrackColor: Colors.white24,
              thumbColor: _gold,
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: position.inMilliseconds
                  .toDouble()
                  .clamp(0.0, duration.inMilliseconds.toDouble()),
              min: 0.0,
              max: duration.inMilliseconds.toDouble() > 0
                  ? duration.inMilliseconds.toDouble()
                  : 1.0,
              onChanged: (value) {
                _controller?.seekTo(Duration(milliseconds: value.toInt()));
                _startHideTimer();
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(position),
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12)),
              Text("-${_formatDuration(duration - position)}",
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveDrawerContent() {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _drawerHeader("Settings", onClose: _closeDrawer),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _sectionHeader("GENERAL"),
              if (isTv) ...[
                _settingsRow(
                  icon: Icons.tv_rounded,
                  title: "Episodes",
                  subtitle: "S$_currentSeason E$_currentEpisode",
                  onTap: () => _openDrawer(ActiveDrawer.episodes),
                ),
                const SizedBox(height: 16),
              ],
              _settingsRow(
                icon: Icons.dns_outlined,
                title: "Playback server",
                subtitle: _selectedServer,
                onTap: () => _openDrawer(ActiveDrawer.servers),
              ),
              const SizedBox(height: 16),
              _sectionHeader("VIDEO"),
              _settingsRow(
                icon: Icons.tune,
                title: "Quality",
                subtitle: _selectedQuality,
                onTap: () => _openDrawer(ActiveDrawer.quality),
              ),
              const SizedBox(height: 10),
              _settingsRow(
                icon: Icons.aspect_ratio,
                title: "Aspect ratio",
                subtitle: _selectedAspectRatio,
                onTap: () => _openDrawer(ActiveDrawer.aspectRatio),
              ),
              const SizedBox(height: 16),
              _sectionHeader("AUDIO & SUBTITLES"),
              _settingsRow(
                icon: Icons.subtitles_outlined,
                title: "Subtitles",
                subtitle: _subtitlesEnabled ? _selectedLanguage : "Off",
                onTap: () => _openDrawer(ActiveDrawer.subtitles),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServersDrawer() {
    return Column(
      children: [
        _drawerHeader(
          "Playback server",
          showBack: true,
          onBack: () => _openDrawer(ActiveDrawer.settings),
          onClose: _closeDrawer,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _serverList.length,
            itemBuilder: (context, index) {
              final server = _serverList[index];
              final serverName = server['name'] ?? 'Server ${index + 1}';
              final isSelected = _selectedServer == serverName;

              return _pillTile(
                title: serverName,
                subtitle: isSelected ? 'Active' : 'Fast',
                isSelected: isSelected,
                onTap: () => _switchServer(server),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQualityDrawer() {
    final defaultQualities = ['Auto', '1080p', '720p', '480p'];

    return Column(
      children: [
        _drawerHeader(
          "Video quality",
          showBack: true,
          onBack: () => _openDrawer(ActiveDrawer.settings),
          onClose: _closeDrawer,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text("RESOLUTION PRESETS",
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              ...defaultQualities.map((q) {
                return _pillTile(
                  title: q,
                  subtitle: q == 'Auto' ? 'Adaptive (ABR)' : 'Manual Selection',
                  isSelected: _selectedQuality == q,
                  onTap: () => _changeQuality(q),
                );
              }),
              if (_hlsVariants.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text("HLS MANIFEST VARIANTS",
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
                ..._hlsVariants.map((v) {
                  return _pillTile(
                    title: v.resolution,
                    subtitle: 'HLS Stream',
                    isSelected: _selectedQuality == v.resolution,
                    onTap: () => _changeQuality(v.resolution),
                  );
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAspectRatioDrawer() {
    final ratios = <Map<String, String>>[
      {'label': 'Full Screen', 'hint': 'Edge-to-edge '},
      {'label': 'Cover', 'hint': 'Fill screen'},
      {'label': 'Auto', 'hint': 'Automatic'},
      {'label': '32:9', 'hint': 'Super Ultra-Wide'},
      {'label': '24:10', 'hint': 'Anamorphic Cinema'},
      {'label': '21:9', 'hint': 'Ultra-Wide Monitor'},
      {'label': '19.5:9', 'hint': 'Modern Smartphone'},
      {'label': '2:1', 'hint': 'Univisium Streaming'},
      {'label': '16:10', 'hint': 'Android Tablets'},
      {'label': '16:9', 'hint': 'Universal HD TV '},
      {'label': '3:2', 'hint': 'Premium Laptops'},
      {'label': '4:3', 'hint': 'Standard Tablets'},
      {'label': '5:4', 'hint': 'Legacy Displays'},
      {'label': 'Fill', 'hint': 'Stretch to Screen'},
    ];

    return Column(
      children: [
        _drawerHeader(
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
        _drawerHeader(
          "Subtitles",
          showBack: true,
          onBack: () => _openDrawer(ActiveDrawer.settings),
          onClose: _closeDrawer,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                      } else {
                        _subtitlesEnabled = true;
                        _selectedLanguage = lang;
                        _fetchWisoSubtitles();
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
                          _offsetBtn("-1.0s",
                              () => setState(() => _subtitleOffsetSeconds -= 1.0)),
                          _offsetBtn("-0.5s",
                              () => setState(() => _subtitleOffsetSeconds -= 0.5)),
                          _offsetBtn("Reset",
                              () => setState(() => _subtitleOffsetSeconds = 0.0),
                              reset: true),
                          _offsetBtn("+0.5s",
                              () => setState(() => _subtitleOffsetSeconds += 0.5)),
                          _offsetBtn("+1.0s",
                              () => setState(() => _subtitleOffsetSeconds += 1.0)),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: reset ? _gold : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: reset ? Colors.black : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _drawerHeader(String title,
      {bool showBack = false,
      VoidCallback? onBack,
      required VoidCallback onClose}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          if (showBack)
            GestureDetector(
              onTap: onBack,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                    color: Color(0xFF1C1C1E), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 14),
              ),
            ),
          if (showBack) const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                  color: Color(0xFF1C1C1E), shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ],
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

  Widget _settingsRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1B1E),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 14)),
            ),
            Text(subtitle,
                style: const TextStyle(color: _gold, fontSize: 14)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
          ],
        ),
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
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF332A15)
                : const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isSelected ? _gold : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? _gold : Colors.white,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 15,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isSelected ? _gold : Colors.white38,
                    fontSize: 13,
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
                  : 'Playback failed on current server. Try switching servers.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
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
          ],
        ),
      ),
    );
  }
}