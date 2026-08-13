import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  });

  @override
  State<CustomPlayerScreen> createState() => _CustomPlayerScreenState();
}

enum ActiveDrawer { none, settings, quality, aspectRatio, subtitles, servers }

class _CustomPlayerScreenState extends State<CustomPlayerScreen>
    with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _hasError = false;
  bool _isLocked = false;
  String _errorMessage = '';
  Timer? _hideTimer;

  late String _masterStreamUrl;
  late String _activeStreamUrl;
  String _selectedServer = 'VidFast';
  List<Map<String, dynamic>> _serverList = [];

  List<HlsVariant> _hlsVariants = [];
  String _selectedQuality = 'Auto';

  ActiveDrawer _activeDrawer = ActiveDrawer.none;

  String _selectedAspectRatio = 'Auto';
  double? _customAspectRatio;

  double _volumeLevel = 0.5;
  double _brightnessLevel = 0.5;
  bool _showGestureToast = false;
  String _toastIcon = 'volume';
  Timer? _toastTimer;

  List<SubtitleItem> _parsedSubtitles = [];
  String _currentSubtitleText = '';
  String _selectedLanguage = 'English';
  bool _subtitlesEnabled = true;
  double _subtitleOffsetSeconds = 0.0;

  // Animations
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
    _initializePlayer(_activeStreamUrl);
    _fetchHlsVariants(_masterStreamUrl);
    _fetchWisoSubtitles();
  }

  void _initServerList() {
    if (widget.servers != null && widget.servers!.isNotEmpty) {
      _serverList = widget.servers!;
    } else {
      _serverList = [
        {
          "id": "vidfast",
          "name": "VidFast",
          "url": widget.streamUrl,
          "movie_url_pattern": null,
          "tv_url_pattern": null,
        },
        {
          "id": "cinesrc",
          "name": "CineSrc",
          "url": "https://cinesrc.st/embed",
          "movie_url_pattern": null,
          "tv_url_pattern": null,
        },
        {
          "id": "cineplay",
          "name": "CinePlay",
          "url": "https://www.cineplay.to",
          "movie_url_pattern": "{url}/{type}/{tmdbId}?play=true",
          "tv_url_pattern":
              "{url}/{type}/{tmdbId}/{season}/{episode}?play=true",
        },
        {
          "id": "videasy",
          "name": "Videasy",
          "url": "https://player.videasy.to",
          "movie_url_pattern": "{url}/{type}/{tmdbId}",
          "tv_url_pattern": "{url}/{type}/{tmdbId}/{season}/{episode}",
        }
      ];
    }

    final initialServer = _serverList.first;
    _selectedServer = initialServer['name'] ?? 'VidFast';
    _masterStreamUrl = _resolveServerUrl(initialServer);
    _activeStreamUrl = _masterStreamUrl;
  }

  String _resolveServerUrl(Map<String, dynamic> server) {
    final isMovie = widget.mediaType.toLowerCase() == 'movie';
    final pattern = isMovie
        ? server['movie_url_pattern'] as String?
        : server['tv_url_pattern'] as String?;

    if (pattern != null && pattern.isNotEmpty) {
      return pattern
          .replaceAll('{url}', server['url'] ?? '')
          .replaceAll('{type}', isMovie ? 'movie' : 'tv')
          .replaceAll('{tmdbId}', widget.tmdbId ?? '')
          .replaceAll('{season}', (widget.season ?? 1).toString())
          .replaceAll('{episode}', (widget.episode ?? 1).toString());
    }

    return server['url'] ?? widget.streamUrl;
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

  Future<void> _initializePlayer(String url, {Duration? startPosition}) async {
    try {
      final uri = Uri.parse(url);
      final Map<String, String> requestHeaders = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      };

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

      await _controller!.initialize();

      if (startPosition != null) {
        await _controller!.seekTo(startPosition);
      }

      _controller?.play();
      _controller?.addListener(_videoPlayerListener);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
        });
        _startHideTimer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage =
              'Playback failed on server. Try switching servers.';
        });
      }
    }
  }

  Future<void> _changeQuality(String qualityLabel, String targetUrl) async {
    if (_selectedQuality == qualityLabel) return;

    final currentPosition = _controller?.value.position ?? Duration.zero;

    _controller?.removeListener(_videoPlayerListener);
    if (_controller != null) await _controller!.pause();
    if (_controller != null) await _controller!.dispose();

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

    _controller?.removeListener(_videoPlayerListener);
    if (_controller != null) await _controller!.pause();
    if (_controller != null) await _controller!.dispose();

    setState(() {
      _isInitialized = false;
      _selectedServer = serverName;
      _masterStreamUrl = resolvedUrl;
      _activeStreamUrl = resolvedUrl;
      _selectedQuality = 'Auto';
      _hlsVariants.clear();
    });
    _closeDrawer();

    _fetchHlsVariants(resolvedUrl);
    await _initializePlayer(resolvedUrl, startPosition: currentPosition);
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
    if (widget.wisoApiKey.isEmpty) return;

    try {
      final url = Uri.parse(
          'https://api.wiso.tv/v1/subtitles?imdb_id=${widget.imdbId ?? ""}&lang=${_selectedLanguage.toLowerCase()}');
      final response = await http.get(
        url,
        headers: {
          'x-api-key': widget.wisoApiKey,
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null && data['data'].isNotEmpty) {
          String downloadUrl = data['data'][0]['link'] ?? '';
          final subFileResponse = await http.get(Uri.parse(downloadUrl));
          if (subFileResponse.statusCode == 200) {
            _parseSrtOrVtt(subFileResponse.body);
          }
        }
      }
    } catch (e) {
      debugPrint("Subtitle Fetch Error: $e");
    }
  }

  void _parseSrtOrVtt(String content) {
    List<SubtitleItem> items = [];
    final lines = content.split('\n');
    final regExp = RegExp(
        r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})');

    Duration parseTime(String h, String m, String s, String ms) {
      return Duration(
        hours: int.parse(h),
        minutes: int.parse(m),
        seconds: int.parse(s),
        milliseconds: int.parse(ms),
      );
    }

    for (int i = 0; i < lines.length; i++) {
      final match = regExp.firstMatch(lines[i]);
      if (match != null) {
        Duration start =
            parseTime(match[1]!, match[2]!, match[3]!, match[4]!);
        Duration end =
            parseTime(match[5]!, match[6]!, match[7]!, match[8]!);

        StringBuffer textBuffer = StringBuffer();
        int j = i + 1;
        while (j < lines.length && lines[j].trim().isNotEmpty) {
          textBuffer.writeln(lines[j].trim());
          j++;
        }

        items.add(SubtitleItem(
            start: start, end: end, text: textBuffer.toString().trim()));
      }
    }

    setState(() => _parsedSubtitles = items);
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
      FlutterVolumeController.setVolume(_volumeLevel);
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
      // Standard cinematic / TV player ratios only
      switch (value) {
        case '16:9':
          _customAspectRatio = 16 / 9;
          break;
        case '4:3':
          _customAspectRatio = 4 / 3;
          break;
        case '1.85:1':
          _customAspectRatio = 1.85;
          break;
        case '2.39:1':
          _customAspectRatio = 2.39;
          break;
        case '21:9':
          _customAspectRatio = 21 / 9;
          break;
        case 'Fill':
          final size = MediaQuery.of(context).size;
          _customAspectRatio = size.width / size.height;
          break;
        default: // Auto = native video aspect ratio
          _customAspectRatio = null;
      }
    });
    _closeDrawer();
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
    final effectiveAspectRatio = _customAspectRatio ??
        (_isInitialized
            ? (_controller?.value.aspectRatio ?? 16 / 9)
            : 16 / 9);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onVerticalDragUpdate: (details) =>
            _handleVerticalDrag(details, screenSize.width),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video
            if (_isInitialized && !_hasError)
              Center(
                child: AspectRatio(
                  aspectRatio: effectiveAspectRatio,
                  child: VideoPlayer(_controller!),
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

            // Subtitles
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

            // Gesture toast
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

            // Controls overlay
            if (_showControls && _isInitialized && !_hasError)
              FadeTransition(
                opacity: _controlsOpacity,
                child: Stack(
                  children: [
                    // Gradients
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

            // Lock indicator
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
                      border: Border.all(color: _gold.withValues(alpha: 0.5)),
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

            // Side drawer with slide animation
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
            () => _initializePlayer(_activeStreamUrl),
            gold: true,
          ),
          const SizedBox(width: 8),
          _circleBtn(
            _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            _toggleLock,
          ),
          const Spacer(),
          _pillBadge(_selectedQuality, () => _openDrawer(ActiveDrawer.quality),
              highlight: true),
          const SizedBox(width: 8),
          _pillBadge("Aspect: $_selectedAspectRatio",
              () => _openDrawer(ActiveDrawer.aspectRatio)),
          const SizedBox(width: 8),
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
            icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
            onPressed: () {
              _controller?.seekTo(
                  _controller!.value.position - const Duration(seconds: 10));
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
            icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
            onPressed: () {
              _controller?.seekTo(
                  _controller!.value.position + const Duration(seconds: 10));
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
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
                _controller
                    ?.seekTo(Duration(milliseconds: value.toInt()));
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
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSettingsMainDrawer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _drawerHeader("Settings", onClose: _closeDrawer),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _sectionHeader("GENERAL"),
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
              _pillTile(
                title: 'Auto',
                subtitle: 'Adaptive (ABR)',
                isSelected: _selectedQuality == 'Auto',
                onTap: () => _changeQuality('Auto', _masterStreamUrl),
              ),
              if (_hlsVariants.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text("HLS RESOLUTIONS",
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
                    onTap: () => _changeQuality(v.resolution, v.url),
                  );
                }),
              ] else if (!_masterStreamUrl.contains('.m3u8')) ...[
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    "Standard stream. Dynamic resolution selection relies on HLS manifests.",
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                )
              ]
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAspectRatioDrawer() {
    // Proper film / TV player ratios
    final ratios = <Map<String, String>>[
      {'label': 'Auto', 'hint': 'Native video'},
      {'label': '16:9', 'hint': 'Widescreen TV'},
      {'label': '4:3', 'hint': 'Classic / SD'},
      {'label': '1.85:1', 'hint': 'Flat cinema'},
      {'label': '2.39:1', 'hint': 'Scope / anamorphic'},
      {'label': '21:9', 'hint': 'Ultrawide'},
      {'label': 'Fill', 'hint': 'Stretch to screen'},
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
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: _gold, size: 48),
          const SizedBox(height: 12),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () => _openDrawer(ActiveDrawer.servers),
            child: const Text('Switch Server',
                style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}